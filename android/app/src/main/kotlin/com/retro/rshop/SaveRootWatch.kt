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
            it.route == entries.first().route &&
                if (it.route == "ppsspp-savedata")
                    it.directory.substringBeforeLast('/') == entries.first().directory.substringBeforeLast('/') &&
                        PpssppSavedataBoundary.validDirectory(it.directory)
                else it.directory == entries.first().directory &&
                    (it.pcsx != null || SaveSourceStorage.isProtectedDirectory(it.directory))
        })
        val apk = context.applicationInfo.sourceDir
        fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
        val command = "CLASSPATH=${quote(apk)} /system/bin/app_process -Xmx64m /system/bin " +
            "com.retro.rshop.RootSaveProcess ${quote(apk)} watch"
        child = ProcessBuilder(*(if (entries.first().pcsx != null)
            arrayOf("su", "--mount-master", "-c", command) else arrayOf("su", "-c", command))).start()
        input = DataInputStream(child.inputStream.buffered())
        output = DataOutputStream(child.outputStream.buffered())
        diagnostics = Thread({ child.errorStream.use { stream ->
            val bytes = ByteArray(1024)
            while (stream.read(bytes) >= 0) { /* bounded drain, no private logs */ }
        } }, "rshop-save-watch-stderr").apply { start() }
        try {
            output.writeUTF(if (entries.first().route == "ppsspp-savedata")
                entries.first().directory.substringBeforeLast('/') else entries.first().directory)
            output.writeUTF(entries.first().route)
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
    internal data class Event(val descriptor: Int, val mask: Int, val name: String?)
    /** Decode bounded kernel frames. Overflow invalidates every mapped save;
     * never silently classify a missed event stream as healthy. */
    internal fun events(bytes: ByteArray): List<Pair<Int, String?>> =
        frames(bytes).map { it.mask to it.name }

    internal fun frames(bytes: ByteArray): List<Event> {
        require(bytes.size <= 65536)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.nativeOrder())
        val events = mutableListOf<Event>()
        while (buffer.hasRemaining()) {
            require(buffer.remaining() >= 16)
            val descriptor = buffer.int
            val mask = buffer.int
            buffer.int // cookie
            val size = buffer.int
            require(size >= 0 && size <= buffer.remaining())
            val name = ByteArray(size).also(buffer::get)
            val end = name.indexOf(0).let { if (it < 0) size else it }
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            events.add(Event(descriptor, mask, if (end == 0) null else decoder.decode(ByteBuffer.wrap(name, 0, end)).toString()))
        }
        return events
    }

    /** One inotify descriptor watches the parent and every explicitly associated
     * save group. Parent events re-arm replaced/new groups before acknowledging
     * pending work; member events never assert snapshot coherence. */
    private fun savedata(source: String, directory: Int, entries: List<SaveFileWatch.Mapping>,
                         output: DataOutputStream) {
        val backing = SaveSourceStorage.backingDirectory(source)
        val pinned = OwnedStorageNative.identity(directory).take(2)
        val groups = entries.groupBy { it.name }
        val descriptors = mutableMapOf<Int, String>()
        val watch = OwnedStorageNative.saveWatchOpen(directory)
        try {
            val parent = OwnedStorageNative.saveWatchAdd(watch, directory)
            fun verifyParent() {
                val fresh = OwnedStorageNative.openRoot(backing)
                try { check(pinned == OwnedStorageNative.identity(fresh).take(2)) }
                finally { OwnedStorageNative.close(fresh) }
            }
            fun arm(name: String) {
                descriptors.entries.firstOrNull { it.value == name }?.key?.let {
                    descriptors.remove(it); OwnedStorageNative.saveWatchRemove(watch, it)
                }
                verifyParent()
                val group = try { OwnedStorageNative.openDirectory(directory, name, false) }
                    catch (error: IOException) { if (error.message != "owned_storage:2") throw error; return }
                try {
                    val identity = OwnedStorageNative.identity(group).take(2)
                    val descriptor = OwnedStorageNative.saveWatchAdd(watch, group)
                    val fresh = OwnedStorageNative.openDirectory(directory, name, false)
                    try { check(identity == OwnedStorageNative.identity(fresh).take(2)) }
                    finally { OwnedStorageNative.close(fresh) }
                    verifyParent()
                    descriptors[descriptor] = name
                } finally { OwnedStorageNative.close(group) }
            }
            groups.keys.forEach(::arm)
            verifyParent()
            output.writeInt(1); output.flush()
            while (true) {
                val bytes = OwnedStorageNative.saveWatchRead(watch) ?: break
                val keys = linkedSetOf<String>()
                val rearm = linkedSetOf<String>()
                var invalid = false
                for (event in frames(bytes)) {
                    if (event.mask and (0x4000 or 0x2000) != 0 ||
                        event.descriptor == parent && event.mask and (0x8000 or 0x400 or 0x800) != 0) {
                        invalid = true; keys.addAll(entries.map { it.key })
                    } else if (event.descriptor == parent) {
                        if (event.name in groups && event.mask and (0x100 or 0x200 or 0x40 or 0x80) != 0) {
                            rearm.add(event.name!!); keys.addAll(groups[event.name]!!.map { it.key })
                        }
                    } else descriptors[event.descriptor]?.let { group ->
                        if (event.mask and (0x8000 or 0x400 or 0x800) != 0) {
                            rearm.add(group); keys.addAll(groups[group]!!.map { it.key })
                        } else keys.addAll(SaveFileWatch.affected(groups[group]!!, event.mask, event.name))
                    }
                }
                if (!invalid) rearm.forEach(::arm)
                for (key in keys) output.writeUTF(key)
                output.flush()
                if (invalid) break
            }
        } finally { OwnedStorageNative.close(watch) }
    }

    @JvmStatic fun serve() {
        require(Process.myUid() == 0)
        val input = DataInputStream(System.`in`)
        val output = DataOutputStream(System.out.buffered())
        val source = input.readUTF()
        val route = input.readUTF()
        require(when (route) {
            "melon" -> MelonSaveBoundary.isProtectedDirectory(source)
            "ppsspp" -> PpssppSaveBoundary.isProtectedDirectory(source)
            "ppsspp-savedata" -> PpssppSavedataBoundary.validParent(source)
            else -> Regex("pcsx-(libretro|shared)-([12])").matches(route) &&
                PcsxSaveSettings.storagePath(source) == source
        })
        val count = input.readInt()
        require(count in 1..4096)
        val entries = (0 until count).map {
            val key = input.readUTF(); val name = input.readUTF()
            SaveFileWatch.Mapping(key, if (route == "ppsspp-savedata") "$source/$name" else source, name, route)
        }
        require(entries.map { it.key }.toSet().size == count)
        val backing = if (entries.first().pcsx != null) {
            // Same validated global-mount path as the configured card capture;
            // do not broaden the generic standalone storage allowlist.
            if (source.startsWith("/storage/emulated/0/"))
                "/data/media/0/" + source.removePrefix("/storage/emulated/0/")
            else "/mnt/media_rw/" + source.removePrefix("/storage/")
        } else SaveSourceStorage.backingDirectory(source)
        val directory = OwnedStorageNative.openRoot(backing)
        try {
            if (route == "ppsspp-savedata") { savedata(source, directory, entries, output); return }
            val pinned = OwnedStorageNative.identity(directory)
            val watch = OwnedStorageNative.saveWatchOpen(directory)
            try {
                val fresh = OwnedStorageNative.openRoot(backing)
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
