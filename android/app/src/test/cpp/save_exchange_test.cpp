#include "owned_storage.h"

#include <cerrno>
#include <dlfcn.h>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <system_error>
#include <unistd.h>

// Run on a NEW exact directory in the actual mapped save filesystem. This
// capability check never opens the user's slots and removes only its two files.
int main(int argc, char** argv) {
    if (argc != 2 || argv[1][0] != '/') return 2;
    const std::string root(argv[1]);
    if (::mkdir(root.c_str(), 0700) < 0) return 2;
    int parent = -1, old = -1, candidate = -1;
    int result = 1;
    try {
        parent = rshop::owned::openRoot(root);
        old = rshop::owned::openFile(parent, "slot", true, true);
        candidate = rshop::owned::openFile(parent, "candidate", true, true);
        rshop::owned::write(old, 0, {1, 2, 3});
        rshop::owned::write(candidate, 0, {4, 5, 6});
        rshop::owned::sync(old); rshop::owned::sync(candidate);
        using RenameAt2 = int (*)(int, const char*, int, const char*, unsigned);
        const auto exchange = reinterpret_cast<RenameAt2>(::dlsym(RTLD_DEFAULT, "renameat2"));
        if (!exchange) throw std::system_error(ENOTSUP, std::generic_category());
        if (exchange(parent, "candidate", parent, "slot", 2) < 0)
            throw std::system_error(errno, std::generic_category());
        rshop::owned::sync(parent);
        if (rshop::owned::entryIdentity(parent, "slot").inode != rshop::owned::identity(candidate).inode ||
            rshop::owned::entryIdentity(parent, "candidate").inode != rshop::owned::identity(old).inode ||
            rshop::owned::read(old, 0, 3) != std::vector<uint8_t>({1, 2, 3}) ||
            rshop::owned::read(candidate, 0, 3) != std::vector<uint8_t>({4, 5, 6}))
            throw std::runtime_error("exchange did not preserve both objects");
        std::cout << "PASS atomic exchange retains both complete files\n";
        result = 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL atomic exchange: " << e.what() << '\n';
    }
    if (old >= 0) ::close(old);
    if (candidate >= 0) ::close(candidate);
    if (parent >= 0) ::close(parent);
    // The root was exclusively created by this invocation; never recurse.
    ::unlink((root + "/slot").c_str());
    ::unlink((root + "/candidate").c_str());
    if (::rmdir(root.c_str()) < 0) return 3;
    return result;
}
