#include "owned_storage.h"

#include <cerrno>
#include <fcntl.h>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <system_error>
#include <unistd.h>
#include <utility>
#include <vector>

namespace owned = rshop::owned;

namespace {
void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
void syscallCheck(int result) {
    if (result < 0) throw std::system_error(errno, std::generic_category());
}
void fails(const std::function<void()>& action, int expected = 0) {
    try { action(); }
    catch (const std::system_error& error) {
        check(expected == 0 || error.code().value() == expected, "unexpected errno");
        return;
    }
    throw std::runtime_error("unsafe operation unexpectedly succeeded");
}
struct Fd {
    int value;
    explicit Fd(int fd) : value(fd) {}
    ~Fd() { if (value >= 0) ::close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
// The supplied root must not exist. Cleanup is limited to individually registered
// fixture entries; a collision is an error, never permission to remove old data.
struct Fixture {
    std::string root;
    std::vector<std::pair<std::string, bool>> entries;
    explicit Fixture(std::string path) : root(std::move(path)) {
        check(!root.empty() && root.front() == '/' && root.back() != '/', "absolute new test root required");
        syscallCheck(::mkdir(root.c_str(), 0700));
        entries.emplace_back(root, true);
    }
    ~Fixture() {
        for (auto it = entries.rbegin(); it != entries.rend(); ++it) {
            int result = it->second ? ::rmdir(it->first.c_str()) : ::unlink(it->first.c_str());
            if (result < 0 && errno != ENOENT) std::cerr << "fixture cleanup errno=" << errno << '\n';
        }
    }
    std::string path(const std::string& name) const { return root + "/" + name; }
    void track(const std::string& name, bool dir = false) { entries.emplace_back(path(name), dir); }
};

struct RestoreDirectoryMode {
    std::string path;
    ~RestoreDirectoryMode() {
        if (::chmod(path.c_str(), 0700) < 0) std::cerr << "fixture mode restoration errno=" << errno << '\n';
    }
};

void executeOnlyAncestor(Fixture& f) {
    const auto ancestor = f.path("search-only");
    const auto leaf = f.path("search-only/readable-leaf");
    syscallCheck(::mkdir(ancestor.c_str(), 0700)); f.track("search-only", true);
    syscallCheck(::mkdir(leaf.c_str(), 0700)); f.track("search-only/readable-leaf", true);
    RestoreDirectoryMode restore{ancestor};
    syscallCheck(::chmod(ancestor.c_str(), 0111));
    Fd root(owned::openRoot(leaf));
    check(owned::identity(root.value).inode != 0, "execute-only ancestor blocked root traversal");
    owned::sync(root.value);
    Fd file(owned::openFile(root.value, "reachable", true, true)); f.track("search-only/readable-leaf/reachable");
    owned::write(file.value, 0, {31});
    owned::sync(file.value);
    owned::sync(root.value);
    check(owned::read(file.value, 0, 1) == std::vector<uint8_t>({31}), "readable final root unusable");
}

void ioAndIdentity(Fixture& f, int root) {
    Fd same(owned::openDirectory(root, "", false));
    check(owned::identity(root).inode == owned::identity(same.value).inode, "empty directory path must duplicate root");
    const uint64_t rootMount = owned::mountId(root);
    check(rootMount > 0 && owned::mountId(same.value) == rootMount, "duplicate directory mount identity mismatch");
    fails([&] { owned::mountId(-1); }, EBADF);
    Fd file(owned::openFile(root, "io.bin", true, true)); f.track("io.bin");
    check(owned::mountId(file.value) == rootMount, "same-root file mount identity mismatch");
    const std::vector<uint8_t> bytes{1, 2, 3, 4};
    owned::write(file.value, 0, bytes);
    owned::write(file.value, 2, {7, 8});
    owned::sync(file.value);
    check(owned::read(file.value, 0, 20) == std::vector<uint8_t>({1, 2, 7, 8}), "offset write/read mismatch");
    check(owned::read(file.value, 2, 2) == std::vector<uint8_t>({7, 8}), "offset read mismatch");
    fails([&] { owned::openFile(root, "io.bin", true, true); }, EEXIST);
    check(owned::read(file.value, 0, 4) == std::vector<uint8_t>({1, 2, 7, 8}), "exclusive collision destroyed bytes");
    auto before = owned::identity(file.value);
    auto entry = owned::entryIdentity(root, "io.bin");
    check(before.inode == entry.inode && before.device == entry.device && entry.size == 4, "entry identity mismatch");
    owned::truncate(file.value, 2);
    check(owned::identity(file.value).size == 2, "truncate failed");
    check(owned::read(file.value, 2, 2).empty(), "EOF must return empty");
    fails([&] { owned::read(file.value, -1, 1); }, EINVAL);
    fails([&] { owned::read(file.value, 0, -1); }, EINVAL);
    fails([&] { owned::read(file.value, 0, 65537); }, EINVAL);
    fails([&] { owned::write(file.value, 0, std::vector<uint8_t>(65537)); }, EINVAL);
    fails([&] { owned::read(file.value, std::numeric_limits<int64_t>::max(), 1); }, EINVAL);
    fails([&] { owned::write(file.value, -1, {}); }, EINVAL);
    fails([&] { owned::write(file.value, std::numeric_limits<int64_t>::max(), {1}); }, EINVAL);
    fails([&] { owned::truncate(file.value, -1); }, EINVAL);
    owned::write(file.value, 0, std::vector<uint8_t>(65536, 42));
    check(owned::read(file.value, 0, 65536).size() == 65536, "maximum chunk rejected");
    Fd readonly(owned::openFile(root, "io.bin", false, false));
    fails([&] { owned::write(readonly.value, 0, {1}); }, EBADF);
    fails([&] { owned::read(root, 0, 1); });
    fails([&] { owned::write(root, 0, {}); });
    fails([&] { owned::truncate(root, 0); });
    fails([&] { owned::entryIdentity(root, "missing"); }, ENOENT);
    fails([&] { owned::openFile(root, "missing", false, false); }, ENOENT);
    int closed = owned::openDirectory(root, "", false);
    owned::close(closed);
    check(::fcntl(closed, F_GETFD) == -1 && errno == EBADF, "close left descriptor open");
}

void pathAndLinkRejection(Fixture& f, int root) {
    for (const std::string& bad : std::vector<std::string>{".", "..", "../escape", "/absolute", "a/../b", "a/./b", "a//b", "a/", std::string("nul\0tail", 8)}) {
        fails([&] { owned::openDirectory(root, bad, true); }, EINVAL);
        fails([&] { owned::openFile(root, bad, true, true); }, EINVAL);
        fails([&] { owned::entryIdentity(root, bad); }, EINVAL);
    }
    fails([&] { owned::openFile(root, "", true, true); }, EINVAL);
    fails([&] { owned::openRoot("relative"); }, EINVAL);
    fails([&] { owned::openRoot(f.root + "/../escape"); }, EINVAL);
    fails([&] { owned::openRoot(f.root + "//nested"); }, EINVAL);
    syscallCheck(::symlink("io.bin", f.path("file-link").c_str())); f.track("file-link");
    syscallCheck(::symlink(".", f.path("dir-link").c_str())); f.track("dir-link");
    fails([&] { owned::openFile(root, "file-link", false, false); });
    fails([&] { owned::entryIdentity(root, "file-link"); });
    fails([&] { owned::openDirectory(root, "dir-link", false); });
    fails([&] { owned::openRoot(f.path("dir-link")); });
    fails([&] { owned::openDirectory(root, "io.bin", false); });
    syscallCheck(::mkdir(f.path("directory").c_str(), 0700)); f.track("directory", true);
    fails([&] { owned::openFile(root, "directory", false, false); });
    fails([&] { owned::entryIdentity(root, "directory"); });
    Fd linked(owned::openFile(root, "io.bin", false, true));
    syscallCheck(::link(f.path("io.bin").c_str(), f.path("hard-link").c_str())); f.track("hard-link");
    fails([&] { owned::openFile(root, "io.bin", false, false); });
    fails([&] { owned::entryIdentity(root, "hard-link"); });
    fails([&] { owned::identity(linked.value); });
    fails([&] { owned::read(linked.value, 0, 1); });
    fails([&] { owned::write(linked.value, 0, {1}); });
    fails([&] { owned::truncate(linked.value, 0); });
    fails([&] { owned::renameNoReplace(root, "hard-link", root, "hard-published"); });
    syscallCheck(::unlink(f.path("hard-link").c_str()));
    syscallCheck(::mkfifo(f.path("fifo").c_str(), 0600)); f.track("fifo");
    fails([&] { owned::openFile(root, "fifo", false, false); });
    fails([&] { owned::entryIdentity(root, "fifo"); });
}

void pinnedDirectories(Fixture& f, int root) {
    Fd pinned(owned::openDirectory(root, "pin", true)); f.track("pin", true);
    auto before = owned::identity(pinned.value);
    syscallCheck(::rename(f.path("pin").c_str(), f.path("moved").c_str())); f.track("moved", true);
    syscallCheck(::mkdir(f.path("pin").c_str(), 0700));
    Fd file(owned::openFile(pinned.value, "bound", true, true)); f.track("moved/bound");
    owned::write(file.value, 0, {9});
    check(::access(f.path("pin/bound").c_str(), F_OK) < 0 && errno == ENOENT, "pinned descriptor followed replacement");
    check(owned::identity(pinned.value).inode == before.inode, "pinned identity changed");
    Fd nested(owned::openDirectory(root, "parent/child", true));
    f.track("parent", true); f.track("parent/child", true);
    check(owned::identity(nested.value).inode != 0, "nested directory not opened");
    Fd utf(owned::openFile(root, u8"保存-🎮.bin", true, true)); f.track(u8"保存-🎮.bin");
    owned::write(utf.value, 0, {23});
    check(owned::entryIdentity(root, u8"保存-🎮.bin").inode == owned::identity(utf.value).inode, "UTF8 entry mismatch");
}

void renameContract(Fixture& f, int root) {
    Fd source(owned::openFile(root, "source", true, true)); f.track("source");
    Fd dest(owned::openFile(root, "dest", true, true)); f.track("dest");
    owned::write(source.value, 0, {10}); owned::write(dest.value, 0, {20});
    fails([&] { owned::renameNoReplace(root, "source", root, "dest"); }, EEXIST);
    check(owned::read(source.value, 0, 1) == std::vector<uint8_t>({10}) &&
          owned::read(dest.value, 0, 1) == std::vector<uint8_t>({20}), "rename collision changed bytes");
    check(owned::entryIdentity(root, "source").inode == owned::identity(source.value).inode, "collision removed source");
    check(owned::entryIdentity(root, "dest").inode == owned::identity(dest.value).inode, "collision replaced destination");
    fails([&] { owned::renameNoReplace(root, "../source", root, "published"); }, EINVAL);
    fails([&] { owned::renameNoReplace(root, "source", root, "../published"); }, EINVAL);
    fails([&] { owned::renameNoReplace(root, "file-link", root, "link-published"); });
    fails([&] { owned::renameNoReplace(root, "directory", root, "dir-published"); });
    owned::renameNoReplace(root, "source", root, "published"); f.track("published");
    check(owned::entryIdentity(root, "published").inode == owned::identity(source.value).inode, "rename identity changed");
    fails([&] { owned::entryIdentity(root, "source"); }, ENOENT);
    owned::sync(root);
}

void privateRetirementContract(Fixture& f, int root) {
    Fd stage(owned::openFile(root, "private-stage", true, true)); f.track("private-stage");
    Fd installed(owned::openFile(root, "retirement-installed", true, true)); f.track("retirement-installed");
    owned::write(stage.value, 0, {41, 42});
    owned::write(installed.value, 0, {41, 42});
    const auto expected = owned::identity(stage.value);
    owned::retirePrivateFile(root, "private-stage", expected);
    fails([&] { owned::entryIdentity(root, "private-stage"); }, ENOENT);
    owned::retirePrivateFile(root, "private-stage", expected);
    check(owned::read(installed.value, 0, 2) == std::vector<uint8_t>({41, 42}),
          "private retirement changed installed bytes");

    Fd changed(owned::openFile(root, "changed-stage", true, true)); f.track("changed-stage");
    owned::write(changed.value, 0, {51});
    const auto before = owned::identity(changed.value);
    for (int field = 0; field < 5; ++field) {
        auto different = before;
        switch (field) {
            case 0: different.device++; break;
            case 1: different.inode++; break;
            case 2: different.size++; break;
            case 3: different.modifiedSeconds++; break;
            default: different.modifiedNanos = (different.modifiedNanos + 1) % 1000000000; break;
        }
        fails([&] { owned::retirePrivateFile(root, "changed-stage", different); }, ESTALE);
        check(owned::entryIdentity(root, "changed-stage").inode == before.inode,
              "identity mismatch removed the private stage");
    }
    owned::write(changed.value, 1, {52});
    fails([&] { owned::retirePrivateFile(root, "changed-stage", before); }, ESTALE);
    check(owned::read(changed.value, 0, 2) == std::vector<uint8_t>({51, 52}),
          "changed private bytes were not preserved");

    for (const std::string& bad : std::vector<std::string>{"", ".", "..", "../changed-stage", "/absolute",
             "a/changed-stage", std::string("nul\0tail", 8)}) {
        fails([&] { owned::retirePrivateFile(root, bad, before); }, EINVAL);
    }
    fails([&] { owned::retirePrivateFile(-1, "missing-stage", before); }, EBADF);
    fails([&] { owned::retirePrivateFile(root, "file-link", before); });
    fails([&] { owned::retirePrivateFile(root, "directory", before); });
    fails([&] { owned::retirePrivateFile(root, "fifo", before); });
    struct stat linkStatus{};
    syscallCheck(::lstat(f.path("file-link").c_str(), &linkStatus));
    check(S_ISLNK(linkStatus.st_mode), "retirement removed a symlink");
    syscallCheck(::stat(f.path("directory").c_str(), &linkStatus));
    check(S_ISDIR(linkStatus.st_mode), "retirement removed a directory");

    const auto linkedExpected = owned::identity(changed.value);
    syscallCheck(::link(f.path("changed-stage").c_str(), f.path("retirement-hard-link").c_str()));
    f.track("retirement-hard-link");
    fails([&] { owned::retirePrivateFile(root, "changed-stage", linkedExpected); }, EMLINK);
    fails([&] { owned::retirePrivateFile(root, "retirement-hard-link", linkedExpected); }, EMLINK);
    syscallCheck(::stat(f.path("changed-stage").c_str(), &linkStatus));
    check(linkStatus.st_nlink == 2, "retirement removed a hard link");
}
void privateQuarantineContract(Fixture& f, int root) {
    const auto directory = f.path("quarantine-private");
    syscallCheck(::mkdir(directory.c_str(), 0700)); f.track("quarantine-private", true);
    Fd privateDir(owned::openRoot(directory));
    Fd publicFile(owned::openFile(root, "quarantine-public", true, true)); f.track("quarantine-public");
    f.track("quarantine-private/owned");
    owned::write(publicFile.value, 0, {61, 62, 63});
    owned::sync(publicFile.value);
    const auto expected = owned::identity(publicFile.value);
    for (int field = 0; field < 5; ++field) {
        auto different = expected;
        switch (field) {
            case 0: different.device++; break;
            case 1: different.inode++; break;
            case 2: different.size++; break;
            case 3: different.modifiedSeconds++; break;
            default: different.modifiedNanos = (different.modifiedNanos + 1) % 1000000000; break;
        }
        fails([&] { owned::quarantineIntoPrivate(root, "quarantine-public", privateDir.value, "owned", different); }, ESTALE);
        check(owned::entryIdentity(root, "quarantine-public").inode == expected.inode,
              "mismatched ownership moved the public file");
    }
    Fd collision(owned::openFile(privateDir.value, "occupied", true, true)); f.track("quarantine-private/occupied");
    owned::write(collision.value, 0, {71});
    fails([&] { owned::quarantineIntoPrivate(root, "quarantine-public", privateDir.value, "occupied", expected); }, EEXIST);
    check(owned::read(collision.value, 0, 1) == std::vector<uint8_t>({71}), "private collision was overwritten");
    fails([&] { owned::quarantineIntoPrivate(root, "file-link", privateDir.value, "owned", expected); });
    fails([&] { owned::quarantineIntoPrivate(root, "../quarantine-public", privateDir.value, "owned", expected); }, EINVAL);
    auto moved = owned::quarantineIntoPrivate(root, "quarantine-public", privateDir.value, "owned", expected);
    check(moved.inode == expected.inode && moved.device == expected.device && moved.size == expected.size,
          "quarantine did not retain the original object");
    fails([&] { owned::entryIdentity(root, "quarantine-public"); }, ENOENT);
    Fd quarantined(owned::openFile(privateDir.value, "owned", false, false));
    check(owned::read(quarantined.value, 0, 3) == std::vector<uint8_t>({61, 62, 63}), "quarantine changed bytes");
    // A writer opened before the namespace move is NOT prevented by the move.
    // Preserve altered quarantine objects; deletion requires fresh validation.
    owned::write(publicFile.value, 3, {64});
    fails([&] { owned::retirePrivateFile(privateDir.value, "owned", moved); }, ESTALE);
    check(owned::read(quarantined.value, 0, 4) == std::vector<uint8_t>({61, 62, 63, 64}), "changed quarantine was deleted");
}

void saveReplacementContract(Fixture& f, int root) {
    Fd old(owned::openFile(root, "save-old", true, true)); f.track("save-old");
    Fd stage(owned::openFile(root, "save-stage", true, true)); f.track("save-stage");
    Fd rollback(owned::openFile(root, "save-rollback", true, true)); f.track("save-rollback");
    owned::write(old.value, 0, {1, 2, 3});
    owned::write(rollback.value, 0, {1, 2, 3}); owned::sync(rollback.value);
    owned::write(stage.value, 0, {4, 5, 6});
    owned::sync(stage.value);
    const auto oldIdentity = owned::identity(old.value);
    const auto stagedIdentity = owned::identity(stage.value);
    auto changed = oldIdentity;
    changed.size++;
    fails([&] { owned::replaceReviewedSave(root, "save-stage", "save-old", stagedIdentity, changed); }, ESTALE);
    check(owned::read(old.value, 0, 3) == std::vector<uint8_t>({1, 2, 3}), "changed save overwritten");
    changed = stagedIdentity;
    changed.inode++;
    fails([&] { owned::replaceReviewedSave(root, "save-stage", "save-old", changed, oldIdentity); }, ESTALE);
    const auto placed = owned::replaceReviewedSave(root, "save-stage", "save-old", stagedIdentity, oldIdentity);
    check(placed.inode == stagedIdentity.inode, "replacement did not retain staged inode");
    Fd current(owned::openFile(root, "save-old", false, false));
    check(owned::read(current.value, 0, 3) == std::vector<uint8_t>({4, 5, 6}), "replacement bytes wrong");
    check(owned::read(rollback.value, 0, 3) == std::vector<uint8_t>({1, 2, 3}), "rollback bytes lost");
}
}  // namespace

int main(int argc, char** argv) {
    if (argc != 2) { std::cerr << "Usage: owned_storage_test /absolute/new-test-root\n"; return 2; }
    try {
        std::cout << "PHASE fixture creation" << std::endl;
        Fixture fixture(argv[1]);
        std::cout << "PHASE root traversal" << std::endl;
        Fd root(owned::openRoot(fixture.root));
        std::cout << "PHASE execute-only ancestor" << std::endl;
        executeOnlyAncestor(fixture);
        std::cout << "PHASE I/O and identity" << std::endl;
        ioAndIdentity(fixture, root.value);
        std::cout << "PHASE path and link rejection" << std::endl;
        pathAndLinkRejection(fixture, root.value);
        std::cout << "PHASE pinned directories" << std::endl;
        pinnedDirectories(fixture, root.value);
        std::cout << "PHASE no-replace rename" << std::endl;
        renameContract(fixture, root.value);
        std::cout << "PHASE private stage retirement" << std::endl;
        privateRetirementContract(fixture, root.value);
        std::cout << "PHASE private quarantine" << std::endl;
        privateQuarantineContract(fixture, root.value);
        std::cout << "PHASE reviewed save replacement" << std::endl;
        saveReplacementContract(fixture, root.value);
        std::cout << "PASS owned storage filesystem contract\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL owned storage: " << error.what() << '\n';
        return 1;
    }
}
