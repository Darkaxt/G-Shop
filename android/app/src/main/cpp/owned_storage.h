#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace rshop::owned {
struct Identity {
    uint64_t device;
    uint64_t inode;
    int64_t size;
    int64_t modifiedSeconds;
    int64_t modifiedNanos;
};

int openRoot(const std::string& absolute);
int openDirectory(int root, const std::string& relative, bool create);
int openFile(int dir, const std::string& name, bool createExclusive, bool writable);
// Identity accepts directories and single-link regular files. Data operations
// and entryIdentity accept only single-link regular files.
Identity identity(int fd);
// Kernel mount identity for an owned file/directory descriptor. Unlike st_dev,
// this distinguishes bind mounts on which rename may still report EXDEV.
uint64_t mountId(int fd);
Identity entryIdentity(int dir, const std::string& name);
std::vector<uint8_t> read(int fd, int64_t offset, int length);
void write(int fd, int64_t offset, const std::vector<uint8_t>& bytes);
void truncate(int fd, int64_t size);
void sync(int fd);
// Requires app-exclusive control of source entries during publication. Does not
// replace an existing destination and does not flush either parent directory.
// Missing renameat2 support reports ENOTSUP; cross-volume moves report EXDEV.
void renameNoReplace(int fromDir, const std::string& from, int toDir, const std::string& to);
// Caller must hold app-exclusive control of this PRIVATE stage directory.
// Never use for public installation paths. An absent entry is an idempotent
// replay; both deletion and replay sync the pinned parent before returning.
void retirePrivateFile(int dir, const std::string& name, const Identity& expected);
void close(int fd);
}  // namespace rshop::owned
