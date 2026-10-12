package com.retro.rshop

import android.content.Context
import android.os.Process
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction

/** One root child for a protected save directory; no recursion, polling timer,
 * shell-interpolated save path, detached helper or ADB runtime dependency. */
internal class SaveRootWatch(context: Context, entries: List<SaveFileWatch.Mapping>,
    changed: (String) -> Unit, unavailable: () -> Unit) : Closeable {
    private val child: java.lang.Process
    private val input: DataInputStream
    private val output: DataOutputStream
    private val diagnostics: Thread
    private var receiver: Thread? = null
    @Volatile private var closing = false

    init {
        require(entries.isNotEmpty() && entries.size <= 4096 && entries.all {
            it.route == "melon" && MelonSaveBoundary.isProtectedDirectory(it.directory)
        })
        val apk = context.applicationInfo.sourceDir
        fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
        val command = "CLASSPATH=${quote(apk)} /system/bin/app_process -Xmx64m /system/bin " +
            "com.retro.rshop.RootSaveProcess ${quote(apk)} watch"
        child = ProcessBuilder("su", "-c", command).start()
        input = DataInputStream(child.inputStream.buffered())
        output = DataOutputStream(child.outputStream.buffered())
        diagnostics = Thread({ child.errorStream.use { stream ->
            val bytes = ByteArray(1024)
            while (stream.read(bytes) >= 0) { /* bounded drain, no private logs */ }
        } }, "rshop-save-watch-stderr").apply { start() }
        try {
            output.writeInt(entries.size)
            for (entry in entries) { output.writeUTF(entry.key); output.writeUTF(entry.name) }
            output.flush()
            check(input.readInt() == 1) // Only after inotify_add_watch succeeds.
            val keys = entries.map { it.key }.toSet()
            receiver = Thread({
                try {
                    while (true) {
                        val key = input.readUTF()
                        check(key in keys)
                        if (!closing) changed(key)
                    }
                } catch (_: Exception) {
                    if (!closing) {
                        runCatching { output.close() }
                        unavailable()
                    }
                }
            }, "rshop-save-watch-events").apply { start() }
        } catch (error: Exception) {
            close()
            throw IOException("root_watch_unavailable", error)
        }
    }

    override fun close() {
        if (closing) return
        closing = true
        // Closing stdin wakes poll even when no save events arrive. The reader
        // keeps draining stdout until child exit, so a full pipe cannot deadlock.
        runCatching { output.close() }
        try { child.waitFor(); receiver?.join() }
        finally { try { input.close() } finally { diagnostics.join() } }
    }
}

object RootSaveWatchWorker {
    /** Decode bounded kernel frames. Overflow invalidates every mapped save;
     * never silently classify a missed event stream as healthy. */
    internal fun events(bytes: ByteArray): List<Pair<Int, String?>> {
        require(bytes.size <= 65536)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.nativeOrder())
        val events = mutableListOf<Pair<Int, String?>>()
        while (buffer.hasRemaining()) {
            require(buffer.remaining() >= 16)
            buffer.int // wd
            val mask = buffer.int
            buffer.int // cookie
            val size = buffer.int
            require(size >= 0 && size <= buffer.remaining())
            val name = ByteArray(size).also(buffer::get)
            val end = name.indexOf(0).let { if (it < 0) size else it }
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            events.add(mask to if (end == 0) null else decoder.decode(ByteBuffer.wrap(name, 0, end)).toString())
        }
        return events
    }

    @JvmStatic fun serve() {
        require(Process.myUid() == 0)
        val input = DataInputStream(System.`in`)
        val output = DataOutputStream(System.out.buffered())
        val count = input.readInt()
        require(count in 1..4096)
        val entries = (0 until count).map {
            SaveFileWatch.Mapping(input.readUTF(), MelonSaveBoundary.PROTECTED_SOURCE,
                input.readUTF(), "melon")
        }
        require(entries.map { it.key }.toSet().size == count)
        val directory = OwnedStorageNative.openRoot(MelonSaveBoundary.PROTECTED_BACKING)
        try {
            val pinned = OwnedStorageNative.identity(directory)
            val watch = OwnedStorageNative.saveWatchOpen(directory)
            try {
                val fresh = OwnedStorageNative.openRoot(MelonSaveBoundary.PROTECTED_BACKING)
                try { check(pinned.take(2) == OwnedStorageNative.identity(fresh).take(2)) }
                finally { OwnedStorageNative.close(fresh) }
                output.writeInt(1); output.flush()
                while (true) {
                    val bytes = OwnedStorageNative.saveWatchRead(watch) ?: break
                    val keys = linkedSetOf<String>()
                    var invalid = false
                    for ((mask, name) in events(bytes)) {
                        // Q_OVERFLOW, UNMOUNT, IGNORED, DELETE_SELF, MOVE_SELF.
                        if (mask and (0x4000 or 0x2000 or 0x8000 or 0x400 or 0x800) != 0) {
                            invalid = true; keys.addAll(entries.map { it.key })
                        } else keys.addAll(SaveFileWatch.affected(entries, mask, name))
                    }
                    for (key in keys) output.writeUTF(key)
                    output.flush()
                    if (invalid) break // Parent receives EOF and invalidates registration.
                }
            } finally { OwnedStorageNative.close(watch) }
        } finally { OwnedStorageNative.close(directory) }
    }
}
