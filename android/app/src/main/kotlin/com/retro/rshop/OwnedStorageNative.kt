package com.retro.rshop

/** Descriptor primitives only. No tokens, arbitrary deletion or install claims. */
internal object OwnedStorageNative {
    init { System.loadLibrary("rshop_owned_storage") }
    external fun openRoot(path: String): Int
    external fun openDirectory(root: Int, relative: String, create: Boolean): Int
    external fun openFile(dir: Int, name: String, createExclusive: Boolean, writable: Boolean): Int
    external fun identity(fd: Int): LongArray
    external fun mountId(fd: Int): Long
    external fun entryIdentity(dir: Int, name: String): LongArray
    external fun read(fd: Int, offset: Long, length: Int): ByteArray
    external fun write(fd: Int, offset: Long, bytes: ByteArray)
    external fun truncate(fd: Int, size: Long)
    external fun sync(fd: Int)
    external fun renameNoReplace(fromDir: Int, from: String, toDir: Int, to: String)
    external fun close(fd: Int)
}
