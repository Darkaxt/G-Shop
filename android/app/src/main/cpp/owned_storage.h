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
// Exclusive save-restore staging directory on the destination filesystem.
int createSaveDirectory(int parent, const std::string& name);
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
// Save restore ONLY: caller has durable rollback bytes and explicit replacement
// choice, plus verified emulator writer quiescence. Same pinned parent; checks
// both complete identities. Atomic namespace mutation is never retried. This
// does not lock an external emulator or authorize arbitrary ROM overwrites.
Identity replaceReviewedSave(int dir, const std::string& stage, const std::string& target,
                             const Identity& staged, const Identity& current);
// Complete save-group restore only. The caller has checked every member and
// writer completion. Atomically install an absent directory or exchange it with
// the reviewed old directory, retaining that old group at stage for rollback.
Identity publishReviewedSaveDirectory(int parent, const std::string& stage, const std::string& target,
                                     const Identity& staged, const Identity* current);
// Only for a destination namespace held EXCLUSIVELY by the app and proved
// PRIVATE by the Android boundary. Never use this for public publication.
// Rejects a changed source and any existing destination. Uses ordinary rename
// because Android public FUSE may reject RENAME_NOREPLACE. The returned identity
// MUST be compared with expected after the move: an external source replacement
// can race the precheck. Keep mismatched objects; never unlink them optimistically.
// Durable intent must precede this call. Parent sync and receipt persistence are
// separate recovery steps; this call does not flush either parent.
Identity quarantineIntoPrivate(int fromDir, const std::string& from, int privateDir,
                               const std::string& to, const Identity& expected);
// Caller must hold app-exclusive control of this PRIVATE stage directory.
// Never use for public installation paths. An absent entry is an idempotent
// replay; both deletion and replay sync the pinned parent before returning.
void retirePrivateFile(int dir, const std::string& name, const Identity& expected);
// Reviewed save-only stage, after its complete rollback capture is durable.
// Requires the same pinned directory inode and an empty stage; never recursive.
void retireSaveDirectory(int parent, const std::string& name, const Identity& expected);
void close(int fd);
}  // namespace rshop::owned
