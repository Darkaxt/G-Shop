package com.retro.rshop

import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.content.Context
import java.io.Closeable
import java.io.File

/** Exact opted-in emulator publication events, never recursive discovery or a
 * writer-completion assertion. Capture still enforces its reviewed boundary.
 * Android may end this process; durable pending work and scheduled/return
 * comparisons recover missed events. No permanent foreground service or timer.
 * https://developer.android.com/reference/android/os/FileObserver */
internal class SaveFileWatch(private val context: Context? = null,
    private val unavailable: () -> Unit = {}, private val changed: (String) -> Unit) : Closeable {
    data class Mapping(val key: String, val directory: String, val name: String,
        val route: String = "ppsspp") {
        init {
            require(key.matches(Regex("[a-f0-9]{64}")))
            require(when (route) {
                "ppsspp" -> PpssppSaveBoundary.validDirectory(directory) && PpssppSaveBoundary.validName(name)
                "melon" -> MelonSaveBoundary.validDirectory(directory) && MelonSaveBoundary.validName(name)
                "ppsspp-savedata" -> PpssppSavedataBoundary.validDirectory(directory) &&
                    directory.substringAfterLast('/') == name
                else -> route.startsWith("retroarch-") &&
                    RetroArchSaveBoundary.saveDirectory(route.removePrefix("retroarch-")) == directory &&
                    RetroArchSaveBoundary.validName(name)
            })
        }
    }
    companion object {
        private const val FILE_EVENTS = FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO or
            FileObserver.MOVED_FROM or FileObserver.DELETE
        private const val SELF_EVENTS = FileObserver.DELETE_SELF or FileObserver.MOVE_SELF
        fun affected(mappings: List<Mapping>, event: Int, name: String?): List<String> =
            if (event and SELF_EVENTS != 0) mappings.map { it.key }
            else mappings.filter {
                if (it.route == "ppsspp-savedata") event and (FILE_EVENTS or FileObserver.CREATE) != 0 &&
                    name != null && PpssppSavedataBoundary.validMember(name)
                else event and FILE_EVENTS != 0 && (it.name == name ||
                    (RetroArchSaveBoundary.includesRtc(it.route.removePrefix("retroarch-")) &&
                        name == it.name.dropLast(4) + ".rtc"))
            }.map { it.key }
        fun decode(raw: List<*>): List<Mapping> {
            require(raw.size <= 4096)
            val mappings = raw.map { value ->
                val row = value as? Map<*, *> ?: throw IllegalArgumentException()
                require(row.keys == setOf("key", "directory", "name") ||
                    row.keys == setOf("key", "directory", "name", "route"))
                Mapping(row["key"] as? String ?: throw IllegalArgumentException(),
                    row["directory"] as? String ?: throw IllegalArgumentException(),
                    row["name"] as? String ?: throw IllegalArgumentException(),
                    if (row.containsKey("route")) row["route"] as? String
                        ?: throw IllegalArgumentException() else "ppsspp")
            }
            require(mappings.map { it.key }.toSet().size == mappings.size)
            return mappings
        }
    }
    private val main = Handler(Looper.getMainLooper())
    // Strong references are required for FileObserver's lifetime.
    private val observers = mutableListOf<FileObserver>()
    private val rootObservers = mutableListOf<SaveRootWatch>()
    @Volatile private var generation = 0L

    @Synchronized fun replace(mappings: List<Mapping>): List<String> {
        close()
        val token = generation
        // One bounded set/post per registration generation, not one queued
        // Runnable for every kernel event during a busy UI frame.
        val pending = linkedSetOf<String>()
        var posted = false
        fun enqueue(keys: List<String>) = synchronized(pending) {
            if (generation != token) return@synchronized
            pending.addAll(keys)
            if (!posted) {
                posted = true
                main.post {
                    val batch = synchronized(pending) {
                        pending.toList().also { pending.clear(); posted = false }
                    }
                    if (generation == token) batch.forEach(changed)
                }
            }
        }
        val registered = mutableListOf<String>()
        for ((directory, entries) in mappings.groupBy {
            if (it.route == "ppsspp-savedata") it.directory.substringBeforeLast('/') else it.directory
        }) {
            var observer: FileObserver? = null
            try {
                if (entries.first().route == "ppsspp-savedata" || SaveSourceStorage.isProtectedDirectory(directory)) {
                    val root = SaveRootWatch(context ?: throw IllegalStateException(), entries,
                        { key -> enqueue(listOf(key)) }, { main.post {
                            if (generation == token) unavailable()
                        } })
                    rootObservers.add(root)
                    registered.addAll(entries.map { it.key })
                    continue
                }
                val folder = File(directory)
                require(folder.isDirectory && folder.canRead() && folder.canExecute() &&
                    folder.canonicalPath == directory)
                @Suppress("DEPRECATION")
                val next = object : FileObserver(directory, FILE_EVENTS or SELF_EVENTS) {
                    override fun onEvent(event: Int, path: String?) {
                        enqueue(affected(entries, event, path))
                    }
                }
                observer = next
                next.startWatching()
                observers.add(next)
                registered.addAll(entries.map { it.key })
            } catch (_: Exception) {
                // A revoked/missing folder affects its own mappings only. The
                // receipt omits them; launch must require its exact mapping.
                observer?.stopWatching()
            }
        }
        return registered
    }
    @Synchronized override fun close() {
        generation++
        observers.forEach(FileObserver::stopWatching)
        observers.clear()
        rootObservers.forEach(SaveRootWatch::close)
        rootObservers.clear()
    }
}
