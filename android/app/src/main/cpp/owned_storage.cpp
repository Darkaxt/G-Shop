#include "owned_storage.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits>
#include <string_view>
#include <sys/stat.h>
#include <system_error>
#include <unistd.h>

namespace rshop::owned {
namespace {
constexpr size_t kMaximumChunk = 64 * 1024;
constexpr int kDirectoryFlags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK;
constexpr int kTraversalFlags = O_PATH | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW;

[[noreturn]] void fail(int error) {
    throw std::system_error(error, std::generic_category());
}

class Descriptor {
public:
    explicit Descriptor(int fd) : fd_(fd) {}
    ~Descriptor() { if (fd_ >= 0) ::close(fd_); }
    Descriptor(const Descriptor&) = delete;
    Descriptor& operator=(const Descriptor&) = delete;
    int get() const { return fd_; }
    int release() { int value = fd_; fd_ = -1; return value; }
    void reset(int fd) { if (fd_ >= 0) ::close(fd_); fd_ = fd; }
private:
    int fd_;
};

void basename(const std::string& name) {
    if (name.empty() || name == "." || name == ".." ||
        name.find('/') != std::string::npos || name.find('\0') != std::string::npos) fail(EINVAL);
}

std::vector<std::string> components(const std::string& relative) {
    std::vector<std::string> result;
    size_t begin = 0;
    while (begin <= relative.size()) {
        size_t end = relative.find('/', begin);
        auto part = relative.substr(begin, end == std::string::npos ? end : end - begin);
        basename(part);
        result.push_back(std::move(part));
        if (end == std::string::npos) break;
        begin = end + 1;
    }
    return result;
}

struct stat descriptorStat(int fd) {
    struct stat status{};
    int result;
    do { result = ::fstat(fd, &status); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
    return status;
}

void regular(const struct stat& status) {
    if (!S_ISREG(status.st_mode)) fail(EINVAL);
    if (status.st_nlink != 1) fail(EMLINK);
}

void directory(int fd) {
    if (!S_ISDIR(descriptorStat(fd).st_mode)) fail(ENOTDIR);
}

Identity toIdentity(const struct stat& status) {
    return {static_cast<uint64_t>(status.st_dev), static_cast<uint64_t>(status.st_ino),
            static_cast<int64_t>(status.st_size), static_cast<int64_t>(status.st_mtim.tv_sec),
            static_cast<int64_t>(status.st_mtim.tv_nsec)};
}

int openAt(int dir, const std::string& name, int flags, mode_t mode = 0) {
    int result;
    do { result = ::openat(dir, name.c_str(), flags, mode); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
    return result;
}

int duplicateDirectory(int fd) {
    directory(fd);
    int result;
    do { result = ::fcntl(fd, F_DUPFD_CLOEXEC, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
    return result;
}

void flush(int fd) {
    int result;
    do { result = ::fsync(fd); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
}

void range(int64_t offset, size_t length) {
    if (offset < 0 || length > kMaximumChunk ||
        static_cast<uint64_t>(offset) > static_cast<uint64_t>(std::numeric_limits<off_t>::max()) ||
        length > static_cast<uint64_t>(std::numeric_limits<off_t>::max()) - static_cast<uint64_t>(offset)) {
        fail(EINVAL);
    }
}

uint64_t parseMountId(std::string_view metadata) {
    constexpr std::string_view prefix = "mnt_id:";
    bool found = false;
    uint64_t mount = 0;
    while (!metadata.empty()) {
        const size_t newline = metadata.find('\n');
        auto line = metadata.substr(0, newline);
        if (line.substr(0, prefix.size()) == prefix) {
            if (found) fail(EIO);
            found = true;
            line.remove_prefix(prefix.size());
            while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) line.remove_prefix(1);
            if (line.empty()) fail(EIO);
            for (char digit : line) {
                if (digit < '0' || digit > '9') fail(EIO);
                const uint64_t value = static_cast<uint64_t>(digit - '0');
                if (mount > (std::numeric_limits<uint64_t>::max() - value) / 10) fail(EIO);
                mount = mount * 10 + value;
            }
            if (mount == 0) fail(EIO);
        }
        if (newline == std::string_view::npos) break;
        metadata.remove_prefix(newline + 1);
    }
    if (!found) fail(ENOTSUP);
    return mount;
}
}  // namespace

int openRoot(const std::string& absolute) {
    if (absolute.empty() || absolute.front() != '/') fail(EINVAL);
    // Validate the complete path before opening anything or creating directories.
    auto parts = absolute == "/" ? std::vector<std::string>{} : components(absolute.substr(1));
    // Ancestors need search permission, not permission to list their contents.
    // Only the returned directory needs a readable descriptor for fsync.
    Descriptor current(openAt(AT_FDCWD, "/", parts.empty() ? kDirectoryFlags : kTraversalFlags));
    for (size_t index = 0; index < parts.size(); ++index) {
        const int flags = index + 1 == parts.size() ? kDirectoryFlags : kTraversalFlags;
        current.reset(openAt(current.get(), parts[index], flags));
    }
    return current.release();
}

int openDirectory(int root, const std::string& relative, bool create) {
    auto parts = relative.empty() ? std::vector<std::string>{} : components(relative);
    Descriptor current(duplicateDirectory(root));
    for (const auto& part : parts) {
        if (create) {
            int result;
            do { result = ::mkdirat(current.get(), part.c_str(), 0700); } while (result < 0 && errno == EINTR);
            if (result < 0 && errno != EEXIST) fail(errno);
            // Persist each new child entry before descending to the next parent.
            if (result == 0) flush(current.get());
        }
        current.reset(openAt(current.get(), part, kDirectoryFlags));
    }
    return current.release();
}

int openFile(int dir, const std::string& name, bool createExclusive, bool writable) {
    basename(name);
    directory(dir);
    int flags = (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK;
    if (createExclusive) flags |= O_CREAT | O_EXCL;
    Descriptor file(openAt(dir, name, flags, 0600));
    regular(descriptorStat(file.get()));
    return file.release();
}

Identity identity(int fd) {
    auto status = descriptorStat(fd);
    if (!S_ISDIR(status.st_mode)) regular(status);
    return toIdentity(status);
}

uint64_t mountId(int fd) {
    identity(fd);
    // This bounded procfs read is descriptor metadata, not file payload. Mount
    // IDs distinguish bind mounts that share st_dev but reject rename with EXDEV.
    const std::string path = "/proc/self/fdinfo/" + std::to_string(fd);
    Descriptor metadata(openAt(AT_FDCWD, path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
    std::array<char, 4096> bytes{};
    size_t total = 0;
    while (total < bytes.size()) {
        const ssize_t count = ::read(metadata.get(), bytes.data() + total, bytes.size() - total);
        if (count < 0) { if (errno == EINTR) continue; fail(errno); }
        if (count == 0) return parseMountId(std::string_view(bytes.data(), total));
        total += static_cast<size_t>(count);
    }
    // Never accept an unproven/truncated metadata record at the read bound.
    fail(EOVERFLOW);
}

Identity entryIdentity(int dir, const std::string& name) {
    basename(name);
    directory(dir);
    struct stat status{};
    int result;
    do { result = ::fstatat(dir, name.c_str(), &status, AT_SYMLINK_NOFOLLOW); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
    regular(status);
    return toIdentity(status);
}

std::vector<uint8_t> read(int fd, int64_t offset, int length) {
    if (length < 0) fail(EINVAL);
    range(offset, static_cast<size_t>(length));
    regular(descriptorStat(fd));
    std::vector<uint8_t> bytes(static_cast<size_t>(length));
    size_t total = 0;
    while (total < bytes.size()) {
        ssize_t result = ::pread(fd, bytes.data() + total, bytes.size() - total, static_cast<off_t>(offset + total));
        if (result < 0) { if (errno == EINTR) continue; fail(errno); }
        if (result == 0) break;
        total += static_cast<size_t>(result);
    }
    bytes.resize(total);
    return bytes;
}

void write(int fd, int64_t offset, const std::vector<uint8_t>& bytes) {
    range(offset, bytes.size());
    regular(descriptorStat(fd));
    size_t total = 0;
    while (total < bytes.size()) {
        ssize_t result = ::pwrite(fd, bytes.data() + total, bytes.size() - total, static_cast<off_t>(offset + total));
        if (result < 0) { if (errno == EINTR) continue; fail(errno); }
        if (result == 0) fail(EIO);
        total += static_cast<size_t>(result);
    }
}

void truncate(int fd, int64_t size) {
    range(size, 0);
    regular(descriptorStat(fd));
    int result;
    do { result = ::ftruncate(fd, static_cast<off_t>(size)); } while (result < 0 && errno == EINTR);
    if (result < 0) fail(errno);
}

void sync(int fd) {
    identity(fd);  // Reject special files; both ordinary files and directories can be flushed.
    flush(fd);
}

void renameNoReplace(int fromDir, const std::string& from, int toDir, const std::string& to) {
    basename(from);
    basename(to);
    entryIdentity(fromDir, from);
    directory(toDir);
    // Android API 24 must load without a relocation against the API 30 symbol.
    using RenameAt2 = int (*)(int, const char*, int, const char*, unsigned int);
    static auto renameAt2 = reinterpret_cast<RenameAt2>(::dlsym(RTLD_DEFAULT, "renameat2"));
    if (renameAt2 == nullptr) fail(ENOTSUP);
    constexpr unsigned int noReplace = 1;
    if (renameAt2(fromDir, from.c_str(), toDir, to.c_str(), noReplace) < 0) {
        int error = errno;
        if (error == ENOSYS || error == EINVAL || error == EOPNOTSUPP) fail(ENOTSUP);
        fail(error);
    }
    // The caller must fsync both pinned parents before reporting durability.
}

void close(int fd) {
    // Never retry close after EINTR: the descriptor may already have been reused.
    if (::close(fd) < 0) fail(errno);
}
}  // namespace rshop::owned
