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
 * Inspect kernel status and the reviewed PPSSPP native-worker lifecycle, never
 * emulator/user payloads. Android keeps PPSSPP's process after normal Exit. */
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

    // PPSSPP v1.20.4 NativeInit eagerly starts PoolW workers; NativeShutdown
    // joins them after core/render shutdown. A cached AMS state alone is not
    // sufficient: Back/onStop intentionally leaves the native runtime alive.
    // Keep this evidence versioned like the associated save-state format.
    internal fun cachedPpssppClosed(versionCode: Long, commandPrefix: ByteArray,
        uidState: String, threads: List<String>): Boolean =
        versionCode == 120040000L &&
            commandPrefix.contentEquals((PpssppSaveSettings.PACKAGE + '\u0000').toByteArray()) &&
            uidState.trim() in setOf("18 (CACHED_RECENT)", "19 (CACHED_EMPTY)") &&
            threads.isNotEmpty() && threads.none {
                it.startsWith("PoolW") || it in setOf("EmuThread", "VulkanRenderMan", "ShaderCompile")
            }

    /** Read only bounded kernel metadata; a vanished PID/TID is not a live writer. */
    private fun kernelBytes(path: String, limit: Int, buffer: ByteArray, prefix: Boolean = false): ByteArray? {
        val fd = try { Os.open(path, OsConstants.O_RDONLY or OsConstants.O_CLOEXEC, 0) }
        catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT || error.errno == OsConstants.ESRCH) return null
            throw error
        }
        return try {
            val bytes = ByteArrayOutputStream()
            while (!prefix || bytes.size() < limit) {
                val count = Os.read(fd, buffer, 0, minOf(buffer.size, limit + (if (prefix) 0 else 1) - bytes.size()))
                if (count == 0) break
                if (bytes.size() + count > limit) throw IOException("root_unavailable")
                bytes.write(buffer, 0, count)
            }
            bytes.toByteArray()
        } finally { Os.close(fd) }
    }

    private fun uidState(uid: Int): String {
        // A joined system-service query, not another su/app_process per PID.
        val child = ProcessBuilder("/system/bin/cmd", "activity", "get-uid-state", uid.toString())
            .redirectErrorStream(true).start()
        try {
            child.outputStream.close()
            val bytes = ByteArrayOutputStream()
            val buffer = ByteArray(256)
            child.inputStream.use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > 1024) throw IOException("root_unavailable")
                    bytes.write(buffer, 0, count)
                }
            }
            if (child.waitFor() != 0) throw IOException("root_unavailable")
            return bytes.toString("UTF-8")
        } finally {
            try { child.outputStream.close() } finally {
                try { child.inputStream.close() } finally { child.waitFor() }
            }
        }
    }

    private fun ppssppRuntimeClosed(pid: String, uid: Int, versionCode: Long, buffer: ByteArray): Boolean {
        if (versionCode != 120040000L) return false
        fun start(): String? = kernelBytes("/proc/$pid/stat", 65536, buffer)?.toString(Charsets.UTF_8)?.let {
            val fields = it.substringAfterLast(')').trim().split(Regex("\\s+"))
            require(fields.size >= 20 && fields[19].matches(Regex("[0-9]+")))
            fields[19]
        }
        val before = start() ?: return true
        // Inspect argv[0] only, never launch arguments or save/ROM paths.
        val command = kernelBytes("/proc/$pid/cmdline", PpssppSaveSettings.PACKAGE.length + 1,
            buffer, prefix = true) ?: return true
        if (!command.contentEquals((PpssppSaveSettings.PACKAGE + '\u0000').toByteArray())) return false
        val stateBefore = uidState(uid)
        if (stateBefore.trim() !in setOf("18 (CACHED_RECENT)", "19 (CACHED_EMPTY)")) return false
        val taskRoot = File("/proc/$pid/task")
        val tasks = taskRoot.list() ?: throw IOException("root_unavailable")
        val names = tasks.mapNotNull { tid ->
            require(tid.isNotEmpty() && tid.all { it in '0'..'9' })
            kernelBytes("${taskRoot.path}/$tid/comm", 64, buffer)?.toString(Charsets.UTF_8)?.removeSuffix("\n")
        }
        val after = start() ?: return true
        if (before != after) throw IOException("source_changed")
        return cachedPpssppClosed(versionCode, command, stateBefore, names) &&
            cachedPpssppClosed(versionCode, command, uidState(uid), names)
    }

    fun requireClosed(packageName: String, versionCode: Long = 0) {
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
            val status = kernelBytes("/proc/$pid/status", 65536, buffer)?.toString(Charsets.UTF_8) ?: continue
            if (blocksRestore(status, uid) && !(packageName == PpssppSaveSettings.PACKAGE &&
                    ppssppRuntimeClosed(pid, uid, versionCode, buffer))) throw IOException("emulator_running")
        }
    }
}
