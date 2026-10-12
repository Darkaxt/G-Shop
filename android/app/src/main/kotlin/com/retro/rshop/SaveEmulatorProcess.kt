package com.retro.rshop

import android.os.Process
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/** Root-only exit evidence for standalone restores. Android's stopped-package
 * flag is neither required for a normal exit nor proof that no UID writer exists.
 * Inspect kernel status, not process command lines or emulator/user payloads. */
internal object SaveEmulatorProcess {
    internal fun blocksRestore(status: String, uid: Int): Boolean {
        require(uid >= 10000)
        val states = status.lineSequence().filter { it.startsWith("State:") }.toList()
        val identities = status.lineSequence().filter { it.startsWith("Uid:") }.toList()
        require(states.size == 1 && identities.size == 1)
        val state = states.single().substringAfter(':').trim().substringBefore(' ')
        require(state.length == 1 && state[0] in "RSDTtZXxKWPI")
        val roles = identities.single().substringAfter(':').trim().split(Regex("\\s+"))
        require(roles.size == 4)
        val uids = roles.map { value ->
            require(value.matches(Regex("[0-9]+")))
            requireNotNull(value.toIntOrNull())
        }
        return uid in uids && state !in setOf("Z", "X", "x")
    }

    fun requireClosed(packageName: String) {
        require(Process.myUid() == 0 && packageName in
            setOf(PpssppSaveSettings.PACKAGE, MelonSaveBoundary.PACKAGE))
        val uid = Os.stat("/data/user/0/$packageName").st_uid
        require(uid >= 10000)
        val processes = File("/proc").list() ?: throw IOException("root_unavailable")
        // One reusable IO buffer serves this census in the restore's joined
        // root child. No su per PID/chunk, signals or guessed quiet delay.
        val buffer = ByteArray(1024)
        for (pid in processes) {
            if (pid.isEmpty() || pid.any { it !in '0'..'9' }) continue
            val fd = try { Os.open("/proc/$pid/status", OsConstants.O_RDONLY or OsConstants.O_CLOEXEC, 0) }
            catch (error: ErrnoException) {
                if (error.errno == OsConstants.ENOENT || error.errno == OsConstants.ESRCH) continue
                throw error
            }
            val status = try {
                val bytes = ByteArrayOutputStream()
                while (true) {
                    val count = Os.read(fd, buffer, 0, buffer.size)
                    if (count == 0) break
                    if (bytes.size() + count > 65536) throw IOException("root_unavailable")
                    bytes.write(buffer, 0, count)
                }
                bytes.toString("UTF-8")
            } finally { Os.close(fd) }
            if (blocksRestore(status, uid)) throw IOException("emulator_running")
        }
    }
}
