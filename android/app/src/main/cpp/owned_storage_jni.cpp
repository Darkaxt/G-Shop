#include "owned_storage.h"

#include <cerrno>
#include <cstdio>
#include <jni.h>
#include <new>
#include <string>
#include <system_error>

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
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_retro_rshop_OwnedStorageNative_openRoot(JNIEnv* env, jobject, jstring path) {
    return guarded<jint>(env, -1, [&] { return owned::openRoot(utf8(env, path)); });
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
Java_com_retro_rshop_OwnedStorageNative_close(JNIEnv* env, jobject, jint fd) {
    guardedVoid(env, [&] { owned::close(fd); });
}
