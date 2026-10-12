package com.retro.rshop

/** Descriptor primitives only. No tokens, arbitrary deletion or install claims. */
internal object OwnedStorageNative {
    init { System.loadLibrary("rshop_owned_storage") }
    external fun openRoot(path: String): Int
    external fun openDirectory(root: Int, relative: String, create: Boolean): Int
    external fun createSaveDirectory(parent: Int, name: String): Int
    external fun openFile(dir: Int, name: String, createExclusive: Boolean, writable: Boolean): Int
    external fun identity(fd: Int): LongArray
    external fun mountId(fd: Int): Long
    external fun entryIdentity(dir: Int, name: String): LongArray
    external fun read(fd: Int, offset: Long, length: Int): ByteArray
    external fun write(fd: Int, offset: Long, bytes: ByteArray)
    external fun truncate(fd: Int, size: Long)
    external fun sync(fd: Int)
    external fun renameNoReplace(fromDir: Int, from: String, toDir: Int, to: String)
    /** Explicit save-only restore, after a sealed rollback and writer boundary. */
    external fun replaceReviewedSave(dir: Int, stage: String, target: String,
                                     staged: LongArray, current: LongArray): LongArray
    /** Complete save-only group, with reviewed members and retained rollback. */
    external fun publishReviewedSaveDirectory(parent: Int, stage: String, target: String,
        staged: LongArray, current: LongArray?): LongArray
    /** Destination must be the app-exclusive private staging namespace. */
    external fun quarantineIntoPrivate(fromDir: Int, from: String, privateDir: Int, to: String, expected: LongArray): LongArray
    /** App-exclusive private stage entries only; never public installation paths. */
    external fun retirePrivateFile(dir: Int, name: String, expected: LongArray)
    external fun retireReviewedSaveMember(dir: Int, name: String, expected: LongArray)
    external fun retireSaveDirectory(parent: Int, name: String, expected: LongArray)
    external fun close(fd: Int)
    /** Kernel-confirmed directory registration and EOF-driven watch shutdown. */
    external fun saveWatchOpen(directory: Int): Int
    external fun saveWatchRead(watch: Int): ByteArray?
    /** Capture-only guard. Arm before the writer census, check after the copy. */
    external fun saveSnapshotOpen(directory: Int): Int
    /** Empty name guards all folder events for a complete SAVEDATA group. */
    external fun saveSnapshotChanged(watch: Int, name: String): Boolean
    /** Root-only read-only /proc census; no emulator signals or data writes. */
    external fun saveSnapshotHasWriter(directory: Int, name: String, source: String, backing: String): Boolean
}
