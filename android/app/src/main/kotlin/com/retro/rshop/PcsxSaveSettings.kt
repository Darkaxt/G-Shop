package com.retro.rshop

import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/** Exact installed PCSX-ReARMed card configuration, not title matching.
 * The owned CHD launch uses the document URI's encoded leaf and "document"
 * parent. Configuration is read-only and never exported over the root channel. */
internal object PcsxSaveSettings {
    const val PACKAGE = "com.retroarch.aarch64"
    const val CONFIG = "/storage/emulated/0/Android/data/com.retroarch.aarch64/files/retroarch.cfg"
    private const val CORE = "PCSX-ReARMed"
    private const val MAX_FILE_BYTES = 1024 * 1024
    private val keys = setOf("rgui_config_directory", "savefile_directory", "sort_savefiles_enable",
        "sort_savefiles_by_content_enable", "savefiles_in_content_dir", "global_core_options",
        "game_specific_options", "core_options_path", "auto_overrides_enable",
        "pcsx_rearmed_memcard1", "pcsx_rearmed_memcard2")
    data class Card(val slot: Int, val mode: String, val name: String?)
    data class Layout(val directory: String, val cards: List<Card>)
    data class Selection(val directory: String, val card: Card) {
        val format: String get() = "pcsx-${card.mode}-card${card.slot}-v1"
        fun acceptsSize(size: Long): Boolean = size == 131072L
        // Shared cards belong to the configured resource, not the ROM which
        // triggered capture. Private cards retain their existing ROM binding.
        fun captureKey(ownedUri: String): List<Any> =
            (if (card.mode == "shared") emptyList() else listOf(ownedUri)) +
                listOf(card.slot, card.mode, requireNotNull(card.name), directory)
    }
    fun select(layout: Layout, slot: Int): Selection {
        require(slot in 1..2 && storagePath(layout.directory) == layout.directory)
        require(layout.cards.map { it.slot }.toSet().size == layout.cards.size)
        val card = requireNotNull(layout.cards.singleOrNull { it.slot == slot })
        val name = requireNotNull(card.name)
        require(name.length in 5..255 && name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 })
        require(when (card.mode) {
            "libretro" -> slot == 1 && name.endsWith(".srm")
            "shared" -> name == "pcsx-card$slot.mcd"
            else -> false // Serial cards require disc evidence, not a title guess.
        })
        return Selection(layout.directory, card)
    }

    fun validChdLeaf(value: String): Boolean = value.length in 5..255 &&
        value.endsWith(".chd", ignoreCase = true) &&
        value.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }

    internal fun storagePath(value: String): String {
        require(value.length in 1..4096 && value.matches(Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+")))
        require(value.split('/').drop(1).none { it.isEmpty() || it == "." || it == ".." ||
            it.any { c -> c == '\\' || c.code < 32 || c.code == 127 } })
        require(value.split('/').none { it.equals("Android", true) } ||
            value.startsWith("/storage/emulated/0/Android/data/$PACKAGE/files/"))
        return value
    }

    private fun parse(text: String): Map<String, String> {
        require(text.length <= MAX_FILE_BYTES)
        val values = mutableMapOf<String, String>()
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            // Includes may override settings; do not ignore them and guess.
            require(!line.startsWith("#include") && !line.startsWith("#reference"))
            val key = line.substringBefore('=').trim()
            if (key !in keys) continue
            val match = Regex("([a-zA-Z0-9_]+)\\s*=\\s*(?:\"([^\"]*)\"|([^\\s#]+))\\s*(?:#.*)?")
                .matchEntire(line) ?: throw IllegalArgumentException("save_settings_unresolved")
            require(key !in values)
            values[key] = match.groupValues[2].ifEmpty { match.groupValues[3] }
        }
        return values
    }

    private fun flag(settings: Map<String, String>, key: String, default: Boolean): Boolean =
        when (settings[key]) { null -> default; "true" -> true; "false" -> false
            else -> throw IllegalArgumentException("save_settings_unresolved") }

    fun resolve(encodedLeaf: String, read: (String) -> String?): Layout {
        require(validChdLeaf(encodedLeaf))
        val stem = encodedLeaf.dropLast(4)
        val settings = parse(requireNotNull(read(CONFIG))).toMutableMap()
        val configDirectory = storagePath(requireNotNull(settings["rgui_config_directory"]))
        val coreDirectory = "$configDirectory/$CORE"
        if (flag(settings, "auto_overrides_enable", true)) {
            for (name in listOf(CORE, "document", stem)) {
                read("$coreDirectory/$name.cfg")?.let { settings.putAll(parse(it)) }
            }
        }
        // These content-URI policies need separate frontend destination evidence.
        // Never replace them with the normal shared-storage save directory.
        require(!flag(settings, "savefiles_in_content_dir", false) &&
            !flag(settings, "sort_savefiles_by_content_enable", false))
        val saveDirectory = storagePath(requireNotNull(settings["savefile_directory"])) +
            if (flag(settings, "sort_savefiles_enable", true)) "/$CORE" else ""
        val effectiveCoreDirectory = storagePath(requireNotNull(settings["rgui_config_directory"])) + "/$CORE"
        var options: String? = null
        if (flag(settings, "game_specific_options", true)) {
            options = read("$effectiveCoreDirectory/$stem.opt")
                ?: read("$effectiveCoreDirectory/document.opt")
        }
        if (options == null && !flag(settings, "global_core_options", false)) {
            options = read("$effectiveCoreDirectory/$CORE.opt")
        }
        if (options == null) {
            val path = settings["core_options_path"].orEmpty().ifEmpty {
                CONFIG.substringBeforeLast('/') + "/retroarch-core-options.cfg"
            }
            options = read(storagePath(path))
        }
        // A selected options file replaces, rather than overlays, the other
        // options files. Missing keys use the actual core's declared defaults.
        val selected = options?.let(::parse).orEmpty()
        val cards = (1..2).mapNotNull { slot ->
            val mode = selected["pcsx_rearmed_memcard$slot"] ?: if (slot == 1) "libretro" else "shared"
            require(mode in (if (slot == 1) setOf("libretro", "serial", "shared", "none")
                else setOf("serial", "shared", "none")))
            when (mode) {
                "none" -> null
                "libretro" -> Card(slot, mode, "$stem.srm")
                "shared" -> Card(slot, mode, "pcsx-card$slot.mcd")
                else -> Card(slot, mode, null) // No serial guessed from a filename.
            }
        }
        return Layout(saveDirectory, cards)
    }

    /** One coherent, bounded settings read in the existing joined root lane. */
    fun read(encodedLeaf: String): JSONObject = inspect(encodedLeaf).first.let { layout ->
        JSONObject().put("directory", layout.directory).put("cards", JSONArray().also { array ->
            layout.cards.forEach { card -> array.put(JSONObject().put("slot", card.slot).put("mode", card.mode)
                .put("name", card.name ?: JSONObject.NULL)) }
        })
    }

    /** Revision pins every selected and absent override across a capture. */
    fun readSelection(encodedLeaf: String, slot: Int): Pair<Selection, String> {
        val (layout, revision) = inspect(encodedLeaf)
        return select(layout, slot) to revision
    }

    private fun inspect(encodedLeaf: String): Pair<Layout, String> {
        require(Process.myUid() == 0 && validChdLeaf(encodedLeaf))
        data class Observation(val parent: List<Long>?, val entry: List<Long>?, val text: String?)
        val observations = linkedMapOf<String, Observation>()
        var total = 0L
        fun observe(path: String, payload: Boolean): Observation {
            storagePath(path)
            require(path.endsWith(".cfg") || path.endsWith(".opt"))
            val directory = path.substringBeforeLast('/')
            val name = path.substringAfterLast('/')
            val root = try { OwnedStorageNative.openRoot(backing(directory)) }
                catch (error: IOException) {
                    if (error.message == "owned_storage:2") return Observation(null, null, null)
                    throw error
                }
            try {
                val parent = OwnedStorageNative.identity(root).take(2)
                val fd = try { OwnedStorageNative.openFile(root, name, false, false) }
                    catch (error: IOException) {
                        if (error.message == "owned_storage:2") return Observation(parent, null, null)
                        throw error
                    }
                try {
                    val before = OwnedStorageNative.identity(fd)
                    require(before[2] in 0..MAX_FILE_BYTES.toLong())
                    var text: String? = null
                    if (payload) {
                        total += before[2]; require(total <= 4L * MAX_FILE_BYTES)
                        val bytes = ByteArray(before[2].toInt())
                        var offset = 0
                        while (offset < bytes.size) {
                            val chunk = OwnedStorageNative.read(fd, offset.toLong(), minOf(65536, bytes.size - offset))
                            require(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                        }
                        text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                    }
                    if (!before.contentEquals(OwnedStorageNative.identity(fd)) ||
                        !before.contentEquals(OwnedStorageNative.entryIdentity(root, name))) throw IOException("source_changed")
                    return Observation(parent, before.toList(), text)
                } finally { OwnedStorageNative.close(fd) }
            } finally { OwnedStorageNative.close(root) }
        }
        val layout = resolve(encodedLeaf) { path ->
            observations.getOrPut(path) { observe(path, true) }.text
        }
        // Revalidate missing overrides too: a newly created game option file
        // must invalidate the lower-precedence result, not silently select it.
        for ((path, before) in observations) {
            val after = observe(path, false)
            if (before.parent != after.parent || before.entry != after.entry) throw IOException("source_changed")
        }
        val evidence = JSONArray()
        for ((path, observation) in observations) evidence.put(JSONArray().put(path)
            .put(observation.parent?.let(::JSONArray) ?: JSONObject.NULL)
            .put(observation.entry?.let(::JSONArray) ?: JSONObject.NULL))
        val revision = MessageDigest.getInstance("SHA-256").digest(evidence.toString().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return layout to revision
    }

    private fun backing(path: String): String = if (path.startsWith("/storage/emulated/0/"))
        "/data/media/0/" + path.removePrefix("/storage/emulated/0/")
        else "/mnt/media_rw/" + path.removePrefix("/storage/")
}
