#include "owned_storage.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <jni.h>
#include <memory>
#include <new>
#include <string>
#include <system_error>
#include <vector>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
namespace owned = rshop::owned;

[[noreturn]] void invalid() { throw std::system_error(EINVAL, std::generic_category()); }

void throwIo(JNIEnv* env, int error) noexcept {
    if (env->ExceptionCheck()) return;
    jclass type = env->FindClass("java/io/IOException");
    if (type == nullptr) return;
    char message[48];
    std::snprintf(message, sizeof(message), "owned_storage:%d", error);
    env->ThrowNew(type, message);
    env->DeleteLocalRef(type);
}

template<class Result, class Action>
Result guarded(JNIEnv* env, Result fallback, Action action) {
    try { return action(); }
    catch (const std::system_error& error) { throwIo(env, error.code().value()); }
    catch (const std::bad_alloc&) { throwIo(env, ENOMEM); }
    catch (...) { throwIo(env, EIO); }
    return fallback;
}

template<class Action>
void guardedVoid(JNIEnv* env, Action action) {
    guarded<int>(env, 0, [&] { action(); return 0; });
}

class Utf16 {
public:
    Utf16(JNIEnv* env, jstring value) : env_(env), value_(value), chars_(env->GetStringChars(value, nullptr)) {}
    ~Utf16() { if (chars_ != nullptr) env_->ReleaseStringChars(value_, chars_); }
    const jchar* get() const { return chars_; }
private:
    JNIEnv* env_;
    jstring value_;
    const jchar* chars_;
};

void appendUtf8(std::string& output, uint32_t codepoint) {
    if (codepoint < 0x80) {
        output.push_back(static_cast<char>(codepoint));
    } else if (codepoint < 0x800) {
        output.push_back(static_cast<char>(0xc0 | (codepoint >> 6)));
        output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
    } else if (codepoint < 0x10000) {
        output.push_back(static_cast<char>(0xe0 | (codepoint >> 12)));
        output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
    } else {
        output.push_back(static_cast<char>(0xf0 | (codepoint >> 18)));
        output.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
    }
}

std::string utf8(JNIEnv* env, jstring value) {
    if (value == nullptr) invalid();
    jsize size = env->GetStringLength(value);
    Utf16 input(env, value);
    if (input.get() == nullptr) throw std::bad_alloc();
    std::string output;
    for (jsize index = 0; index < size; ++index) {
        uint32_t codepoint = input.get()[index];
        if (codepoint == 0) invalid();
        if (codepoint >= 0xd800 && codepoint <= 0xdbff) {
            if (++index == size) invalid();
            uint32_t low = input.get()[index];
            if (low < 0xdc00 || low > 0xdfff) invalid();
            codepoint = 0x10000 + ((codepoint - 0xd800) << 10) + low - 0xdc00;
        } else if (codepoint >= 0xdc00 && codepoint <= 0xdfff) {
            invalid();
        }
        appendUtf8(output, codepoint);
    }
    return output;
}

jlongArray identityArray(JNIEnv* env, const owned::Identity& value) {
    jlong fields[] = {static_cast<jlong>(value.device), static_cast<jlong>(value.inode),
                      value.size, value.modifiedSeconds, value.modifiedNanos};
    auto result = env->NewLongArray(5);
    if (result != nullptr) env->SetLongArrayRegion(result, 0, 5, fields);
    return result;
}

owned::Identity identityValue(JNIEnv* env, jlongArray value) {
    if (value == nullptr || env->GetArrayLength(value) != 5) invalid();
    jlong fields[5]{};
    env->GetLongArrayRegion(value, 0, 5, fields);
    if (env->ExceptionCheck() || fields[2] < 0 || fields[4] < 0 || fields[4] >= 1000000000) invalid();
    return {static_cast<uint64_t>(fields[0]), static_cast<uint64_t>(fields[1]),
            fields[2], fields[3], fields[4]};
}
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveWatchOpen(JNIEnv* env, jobject, jint directory) {
    return guarded<jint>(env, -1, [&] {
        // The directory is already pinned by the no-follow storage boundary.
        // Follow only our proc descriptor link, never an unverified caller path.
        std::string path = "/proc/self/fd/" + std::to_string(directory);
        int fd = ::inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
        if (fd < 0) throw std::system_error(errno, std::generic_category());
        constexpr uint32_t events = IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM |
            IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT | IN_ONLYDIR;
        if (::inotify_add_watch(fd, path.c_str(), events) < 0) {
            int error = errno;
            ::close(fd);
            throw std::system_error(error, std::generic_category());
        }
        return fd;
    });
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveWatchRead(JNIEnv* env, jobject, jint watch) {
    return guarded<jbyteArray>(env, nullptr, [&]() -> jbyteArray {
        for (;;) {
            pollfd sources[] = {{STDIN_FILENO, POLLIN, 0}, {watch, POLLIN, 0}};
            int result;
            do { result = ::poll(sources, 2, -1); } while (result < 0 && errno == EINTR);
            if (result < 0) throw std::system_error(errno, std::generic_category());
            // EOF or any unexpected control input ends the exact owned child.
            if (sources[0].revents != 0) return nullptr;
            if (sources[1].revents & (POLLERR | POLLHUP | POLLNVAL))
                throw std::system_error(EIO, std::generic_category());
            if (!(sources[1].revents & POLLIN)) continue;
            char bytes[65536];
            ssize_t size;
            do { size = ::read(watch, bytes, sizeof(bytes)); } while (size < 0 && errno == EINTR);
            if (size < 0 && errno == EAGAIN) continue;
            if (size <= 0) throw std::system_error(size < 0 ? errno : EIO, std::generic_category());
            auto output = env->NewByteArray(static_cast<jsize>(size));
            if (output != nullptr) env->SetByteArrayRegion(output, 0, static_cast<jsize>(size),
                reinterpret_cast<const jbyte*>(bytes));
            return output;
        }
    });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveWatchAdd(JNIEnv* env, jobject, jint watch, jint directory) {
    return guarded<jint>(env, -1, [&] {
        std::string path = "/proc/self/fd/" + std::to_string(directory);
        constexpr uint32_t events = IN_CLOSE_WRITE | IN_CREATE | IN_MOVED_TO | IN_MOVED_FROM |
            IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT | IN_ONLYDIR;
        int descriptor = ::inotify_add_watch(watch, path.c_str(), events);
        if (descriptor < 0) throw std::system_error(errno, std::generic_category());
        return descriptor;
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveWatchRemove(JNIEnv* env, jobject, jint watch, jint descriptor) {
    guardedVoid(env, [&] {
        if (::inotify_rm_watch(watch, descriptor) < 0 && errno != EINVAL)
            throw std::system_error(errno, std::generic_category());
    });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveSnapshotOpen(JNIEnv* env, jobject, jint directory) {
    return guarded<jint>(env, -1, [&] {
        std::string path = "/proc/self/fd/" + std::to_string(directory);
        int fd = ::inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
        if (fd < 0) throw std::system_error(errno, std::generic_category());
        constexpr uint32_t events = IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_CREATE |
            IN_MOVED_TO | IN_MOVED_FROM | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT | IN_ONLYDIR;
        if (::inotify_add_watch(fd, path.c_str(), events) < 0) {
            int error = errno;
            ::close(fd);
            throw std::system_error(error, std::generic_category());
        }
        return fd;
    });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveSnapshotChanged(JNIEnv* env, jobject, jint watch, jstring name) {
    return guarded<jboolean>(env, JNI_TRUE, [&]() -> jboolean {
        std::string leaf = utf8(env, name);
        alignas(inotify_event) char bytes[65536];
        // Bound work under unrelated directory churn. Exhausting the bound is
        // unavailable evidence, never a claim that the queue was clean.
        for (int frame = 0; frame < 4; ++frame) {
            ssize_t size;
            do { size = ::read(watch, bytes, sizeof(bytes)); } while (size < 0 && errno == EINTR);
            if (size < 0 && errno == EAGAIN) return JNI_FALSE;
            if (size <= 0) throw std::system_error(size < 0 ? errno : EIO, std::generic_category());
            size_t offset = 0;
            while (offset < static_cast<size_t>(size)) {
                if (static_cast<size_t>(size) - offset < sizeof(inotify_event)) invalid();
                const auto* event = reinterpret_cast<const inotify_event*>(bytes + offset);
                size_t length = sizeof(inotify_event) + event->len;
                if (length > static_cast<size_t>(size) - offset) invalid();
                if (event->mask & (IN_Q_OVERFLOW | IN_UNMOUNT | IN_IGNORED | IN_DELETE_SELF | IN_MOVE_SELF))
                    return JNI_TRUE;
                // Empty selection guards an entire SAVEDATA folder, including
                // directory attributes and members added during capture.
                if (leaf.empty()) return JNI_TRUE;
                if (event->len > 0 && ::strnlen(event->name, event->len) == leaf.size() &&
                    std::memcmp(event->name, leaf.data(), leaf.size()) == 0) return JNI_TRUE;
                offset += length;
            }
        }
        return JNI_TRUE;
    });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_retro_rshop_OwnedStorageNative_saveSnapshotHasWriter(JNIEnv* env, jobject, jint directory,
    jstring name, jstring source, jstring backing) {
    return guarded<jboolean>(env, JNI_TRUE, [&]() -> jboolean {
        if (::geteuid() != 0) throw std::system_error(EACCES, std::generic_category());
        const std::string leaf = utf8(env, name);
        const std::string publicPath = utf8(env, source) + "/" + leaf;
        const std::string backingPath = utf8(env, backing) + "/" + leaf;
        const bool group = leaf.empty();
        struct stat pinned{}, publicFile{};
        if (!group && ::fstatat(directory, leaf.c_str(), &pinned, AT_SYMLINK_NOFOLLOW) < 0) {
            if (errno != ENOENT) throw std::system_error(errno, std::generic_category());
        } else if (!group && (!S_ISREG(pinned.st_mode) || pinned.st_nlink != 1)) invalid();
        if (!group && ::stat(publicPath.c_str(), &publicFile) < 0 && errno != ENOENT && errno != EACCES)
            throw std::system_error(errno, std::generic_category());
        auto exited = [](int error) { return error == ENOENT || error == ESRCH; };
        auto numeric = [](const char* text) {
            if (*text == '\0') return false;
            for (; *text; ++text) if (*text < '0' || *text > '9') return false;
            return true;
        };
        auto next = [](DIR* dir) {
            errno = 0;
            dirent* entry = ::readdir(dir);
            if (entry == nullptr && errno != 0) throw std::system_error(errno, std::generic_category());
            return entry;
        };
        auto closeDir = [](DIR* dir) { ::closedir(dir); };
        // One bounded member inventory and one /proc traversal for a complete
        // flat save folder, not one root process or process scan per member.
        // The already armed inotify guard rejects membership/mutation races.
        std::vector<struct stat> groupFiles;
        if (group) {
            int fd = ::openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
            if (fd < 0) throw std::system_error(errno, std::generic_category());
            std::unique_ptr<DIR, decltype(closeDir)> members(::fdopendir(fd), closeDir);
            if (!members) { int error = errno; ::close(fd); throw std::system_error(error, std::generic_category()); }
            size_t count = 0;
            while (auto* member = next(members.get())) {
                if (std::strcmp(member->d_name, ".") == 0 || std::strcmp(member->d_name, "..") == 0) continue;
                if (++count > 128) invalid(); // PPSSPP SAVEDATA's existing member bound.
                struct stat backingMember{}, publicMember{};
                if (::fstatat(directory, member->d_name, &backingMember, AT_SYMLINK_NOFOLLOW) < 0)
                    throw std::system_error(errno, std::generic_category());
                if (!S_ISREG(backingMember.st_mode) || backingMember.st_nlink != 1) invalid();
                groupFiles.push_back(backingMember);
                const std::string path = publicPath + member->d_name;
                if (::stat(path.c_str(), &publicMember) == 0) groupFiles.push_back(publicMember);
                else if (errno != ENOENT && errno != EACCES) throw std::system_error(errno, std::generic_category());
            }
        }
        std::unique_ptr<DIR, decltype(closeDir)> processes(::opendir("/proc"), closeDir);
        if (!processes) throw std::system_error(errno, std::generic_category());
        while (auto* process = next(processes.get())) {
            if (!numeric(process->d_name)) continue;
            const std::string prefix = std::string("/proc/") + process->d_name;
            std::unique_ptr<DIR, decltype(closeDir)> descriptors(::opendir((prefix + "/fd").c_str()), closeDir);
            if (!descriptors) {
                if (exited(errno)) continue;
                throw std::system_error(errno, std::generic_category());
            }
            while (auto* descriptor = next(descriptors.get())) {
                if (!numeric(descriptor->d_name)) continue;
                struct stat candidate{};
                if (::fstatat(::dirfd(descriptors.get()), descriptor->d_name, &candidate, 0) < 0) {
                    if (exited(errno)) continue;
                    throw std::system_error(errno, std::generic_category());
                }
                if (!S_ISREG(candidate.st_mode)) continue;
                bool matched = (pinned.st_ino != 0 && candidate.st_dev == pinned.st_dev && candidate.st_ino == pinned.st_ino) ||
                    (publicFile.st_ino != 0 && candidate.st_dev == publicFile.st_dev && candidate.st_ino == publicFile.st_ino);
                if (group) for (const auto& member : groupFiles) {
                    if (candidate.st_dev == member.st_dev && candidate.st_ino == member.st_ino) { matched = true; break; }
                }
                if (!matched) {
                    // FUSE and backing inode numbers differ. Also recognize the
                    // exact descriptor path in the writer's mount namespace.
                    char path[4096];
                    ssize_t size = ::readlinkat(::dirfd(descriptors.get()), descriptor->d_name, path, sizeof(path));
                    if (size < 0) {
                        if (exited(errno)) continue;
                        throw std::system_error(errno, std::generic_category());
                    }
                    if (static_cast<size_t>(size) == sizeof(path)) throw std::system_error(ENAMETOOLONG, std::generic_category());
                    std::string actual(path, static_cast<size_t>(size));
                    auto inGroup = [&](const std::string& prefix) {
                        return actual.compare(0, prefix.size(), prefix) == 0 && actual.size() > prefix.size() &&
                            actual.find('/', prefix.size()) == std::string::npos;
                    };
                    matched = group ? inGroup(publicPath) || inGroup(backingPath) : actual == publicPath || actual == backingPath;
                }
                if (!matched) continue;
                auto closeFile = [](FILE* file) { ::fclose(file); };
                std::unique_ptr<FILE, decltype(closeFile)> info(
                    ::fopen((prefix + "/fdinfo/" + descriptor->d_name).c_str(), "re"), closeFile);
                if (!info) {
                    if (exited(errno)) continue;
                    throw std::system_error(errno, std::generic_category());
                }
                char line[256];
                bool flagsFound = false;
                while (::fgets(line, sizeof(line), info.get()) != nullptr) {
                    unsigned long flags;
                    if (std::sscanf(line, "flags:\t%lo", &flags) != 1) continue;
                    flagsFound = true;
                    if ((flags & O_ACCMODE) != O_RDONLY) return JNI_TRUE;
                    break;
                }
                if (::ferror(info.get())) throw std::system_error(EIO, std::generic_category());
                if (!flagsFound) {
                    // A descriptor may close between stat and fdinfo. Its
                    // CLOSE_WRITE is then in the already armed mutation guard.
                    struct stat current{};
                    if (::fstatat(::dirfd(descriptors.get()), descriptor->d_name, &current, 0) == 0 || !exited(errno))
                        throw std::system_error(EIO, std::generic_category());
                }
            }
        }
        return JNI_FALSE;
    });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_openRoot(JNIEnv* env, jobject, jstring path) {
    return guarded<jint>(env, -1, [&] { return owned::openRoot(utf8(env, path)); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_createSaveDirectory(JNIEnv* env, jobject, jint parent, jstring name) {
    return guarded<jint>(env, -1, [&] { return owned::createSaveDirectory(parent, utf8(env, name)); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_openDirectory(JNIEnv* env, jobject, jint root, jstring path, jboolean create) {
    return guarded<jint>(env, -1, [&] { return owned::openDirectory(root, utf8(env, path), create == JNI_TRUE); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_openFile(JNIEnv* env, jobject, jint dir, jstring name, jboolean create, jboolean writable) {
    return guarded<jint>(env, -1, [&] { return owned::openFile(dir, utf8(env, name), create == JNI_TRUE, writable == JNI_TRUE); });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_identity(JNIEnv* env, jobject, jint fd) {
    return guarded<jlongArray>(env, nullptr, [&] { return identityArray(env, owned::identity(fd)); });
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_retro_rshop_OwnedStorageNative_mountId(JNIEnv* env, jobject, jint fd) {
    return guarded<jlong>(env, -1, [&] { return static_cast<jlong>(owned::mountId(fd)); });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_entryIdentity(JNIEnv* env, jobject, jint dir, jstring name) {
    return guarded<jlongArray>(env, nullptr, [&] { return identityArray(env, owned::entryIdentity(dir, utf8(env, name))); });
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_read(JNIEnv* env, jobject, jint fd, jlong offset, jint length) {
    return guarded<jbyteArray>(env, nullptr, [&] {
        auto bytes = owned::read(fd, offset, length);
        auto result = env->NewByteArray(static_cast<jsize>(bytes.size()));
        if (result != nullptr && !bytes.empty()) {
            env->SetByteArrayRegion(result, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<const jbyte*>(bytes.data()));
        }
        return result;
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_write(JNIEnv* env, jobject, jint fd, jlong offset, jbyteArray value) {
    guardedVoid(env, [&] {
        if (value == nullptr) invalid();
        jsize size = env->GetArrayLength(value);
        if (size > 65536) invalid();
        std::vector<uint8_t> bytes(static_cast<size_t>(size));
        if (size > 0) env->GetByteArrayRegion(value, 0, size, reinterpret_cast<jbyte*>(bytes.data()));
        if (!env->ExceptionCheck()) owned::write(fd, offset, bytes);
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_truncate(JNIEnv* env, jobject, jint fd, jlong size) {
    guardedVoid(env, [&] { owned::truncate(fd, size); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_sync(JNIEnv* env, jobject, jint fd) {
    guardedVoid(env, [&] { owned::sync(fd); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_renameNoReplace(JNIEnv* env, jobject, jint fromDir, jstring from, jint toDir, jstring to) {
    guardedVoid(env, [&] { owned::renameNoReplace(fromDir, utf8(env, from), toDir, utf8(env, to)); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_retirePrivateFile(JNIEnv* env, jobject, jint dir, jstring name, jlongArray expected) {
    guardedVoid(env, [&] { owned::retirePrivateFile(dir, utf8(env, name), identityValue(env, expected)); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_retireReviewedSaveMember(JNIEnv* env, jobject, jint dir, jstring name, jlongArray expected) {
    // The root source boundary admits only an anchored, owned save stage after
    // writer completion. Reuse the no-follow, exact-member unlink primitive.
    guardedVoid(env, [&] { owned::retirePrivateFile(dir, utf8(env, name), identityValue(env, expected)); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_retireSaveDirectory(JNIEnv* env, jobject, jint parent, jstring name, jlongArray expected) {
    guardedVoid(env, [&] { owned::retireSaveDirectory(parent, utf8(env, name), identityValue(env, expected)); });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_replaceReviewedSave(JNIEnv* env, jobject, jint dir,
    jstring stage, jstring target, jlongArray staged, jlongArray current) {
    return guarded<jlongArray>(env, nullptr, [&] {
        return identityArray(env, owned::replaceReviewedSave(dir, utf8(env, stage), utf8(env, target),
            identityValue(env, staged), identityValue(env, current)));
    });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_publishReviewedSaveDirectory(JNIEnv* env, jobject, jint parent,
    jstring stage, jstring target, jlongArray staged, jlongArray current) {
    return guarded<jlongArray>(env, nullptr, [&] {
        owned::Identity old{};
        if (current != nullptr) old = identityValue(env, current);
        return identityArray(env, owned::publishReviewedSaveDirectory(parent, utf8(env, stage), utf8(env, target),
            identityValue(env, staged), current == nullptr ? nullptr : &old));
    });
}

extern "C" JNIEXPORT jlongArray JNICALL
Java_com_retro_rshop_OwnedStorageNative_quarantineIntoPrivate(JNIEnv* env, jobject, jint fromDir, jstring from,
                                                              jint privateDir, jstring to, jlongArray expected) {
    return guarded<jlongArray>(env, nullptr, [&] {
        return identityArray(env, owned::quarantineIntoPrivate(fromDir, utf8(env, from), privateDir,
                                                              utf8(env, to), identityValue(env, expected)));
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_retro_rshop_OwnedStorageNative_close(JNIEnv* env, jobject, jint fd) {
    guardedVoid(env, [&] { owned::close(fd); });
}
