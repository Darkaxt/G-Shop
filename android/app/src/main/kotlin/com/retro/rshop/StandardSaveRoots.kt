package com.retro.rshop

import android.os.Process
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException

/** Resolves configuration only; capture, watch and restore use the shared lane. */
internal object StandardSaveRoots {
    const val NETHER = "xyz.aethersx2.android"
    const val NETHER_PROFILE = "nether-cards-v1"
    const val FLYCAST = "com.flycast.emulator"
    const val FLYCAST_PROFILE = "flycast-shared-vmus-v1"
    const val DOLPHIN = "org.dolphinemu.dolphinemu"
    const val DOLPHIN_PROFILE = "dolphin-gci-cards-v1"
    const val AZAHAR = "io.github.lime3ds.android"
    const val AZAHAR_PROFILE = "azahar-title-save-v1"
    fun packageFor(platformId: String): String? = when (platformId) {
        "ps2" -> NETHER
        "dreamcast" -> FLYCAST
        "gc" -> DOLPHIN
        "n3ds" -> AZAHAR
        else -> null
    }
    fun validProfile(profile: String, emulator: String, core: String, kind: String,
        resourceId: String?, format: String): Boolean = kind == "save" && when (profile) {
        NETHER_PROFILE -> emulator == NETHER && core == "pcsx2" && resourceId == "memory-cards" && format == "ps2-shared-memory-cards-v1"
        FLYCAST_PROFILE -> emulator == FLYCAST && core == "flycast" && resourceId == "vmu-cards" && format == "dreamcast-vmu-v1"
        DOLPHIN_PROFILE -> emulator == DOLPHIN && core == "dolphin" && resourceId == "gc-memory-cards" && format == "gamecube-gci-cards-v1"
        AZAHAR_PROFILE -> emulator == AZAHAR && core == "azahar" && resourceId == null && format == AZAHAR_PROFILE
        else -> false
    }
    internal fun azaharConfiguration(home: String, programId: String): SaveRootConfiguration {
        require(SaveRootConfiguration.validDirectory(home, AZAHAR) && programId.matches(Regex("00040000[0-9a-f]{8}")))
        val low = programId.takeLast(8)
        val root = "$home/sdmc/Nintendo 3DS/${"0".repeat(32)}/${"0".repeat(32)}/title/00040000"
        val metadata = "$low/data/00000001.metadata"
        return SaveRootConfiguration(root, AZAHAR, "azahar", "save", AZAHAR_PROFILE,
            listOf(metadata), listOf("$low/data/00000001"), listOf(metadata), profile = AZAHAR_PROFILE)
    }
    fun azahar(programId: String): SaveRootConfiguration {
        require(Process.myUid() == 0)
        val parser = Xml.newPullParser()
        // Azahar keeps its per-game library cache in this same preference file.
        // The current Thor file is 1,632,041 bytes, unlike the small card settings.
        parser.setInput(ByteArrayInputStream(read("/data/user/0/$AZAHAR/shared_prefs", "${AZAHAR}_preferences.xml", 4 * 1024 * 1024)), "UTF-8")
        var uri: String? = null; var map = false
        while (true) when (parser.nextToken()) {
            XmlPullParser.DOCDECL -> throw IOException("save_settings_unresolved")
            XmlPullParser.START_TAG -> {
                if (parser.depth == 1) { require(!map && parser.name == "map"); map = true }
                else if (parser.depth == 2 && parser.getAttributeValue(null, "name") == "CITRA_DIRECTORY") {
                    require(uri == null && parser.name == "string"); uri = parser.nextText()
                }
            }
            XmlPullParser.END_DOCUMENT -> break
        }
        require(map && uri != null)
        val parsed = android.net.Uri.parse(uri)
        require(parsed.scheme == "content" && parsed.authority == "com.android.externalstorage.documents")
        val document = android.provider.DocumentsContract.getTreeDocumentId(parsed)
        val volume = document.substringBefore(':'); val relative = document.substringAfter(':', "")
        require(relative.isNotEmpty())
        val base = if (volume == "primary") "/storage/emulated/0" else {
            require(volume.matches(Regex("[a-fA-F0-9]{4}-[a-fA-F0-9]{4}"))); "/storage/$volume"
        }
        return azaharConfiguration("$base/$relative", programId)
    }
    private val dolphinKeys = setOf("SlotA", "SlotB", "GCIFolderAPath", "GCIFolderBPath",
        "GCIFolderAPathOverride", "GCIFolderBPathOverride")
    /** Dolphin MainSettings::GetGCIFolderPath: the folders are virtual cards,
     * not one unrelated per-game save history for each .gci member. */
    internal fun dolphinConfiguration(settings: Map<String, String>): SaveRootConfiguration? {
        val folders = listOf('A', 'B').flatMap { slot ->
            val raw = settings["Slot$slot"]
            require(raw == null || raw.toIntOrNull() in 0..14 || raw == "255")
            when (raw?.toInt() ?: if (slot == 'A') 8 else 255) {
                8 -> {
                    require(settings["GCIFolder${slot}Path"].isNullOrEmpty() &&
                        settings["GCIFolder${slot}PathOverride"].isNullOrEmpty()) { "save_settings_unresolved" }
                    listOf("EUR", "JAP", "USA", "DEV").map { "$it/Card $slot" }
                }
                1 -> throw IllegalArgumentException("save_settings_unresolved") // raw/custom card: exact mapping
                else -> emptyList()
            }
        }
        if (folders.isEmpty()) return null
        return SaveRootConfiguration("/storage/emulated/0/Android/data/$DOLPHIN/files/GC",
            DOLPHIN, "dolphin", "save", "gamecube-gci-cards-v1", emptyList(), folders, emptyList(),
            resourceId = "gc-memory-cards", profile = DOLPHIN_PROFILE)
    }
    private fun dolphinCore(ini: String): Map<String, String> {
        val values = mutableMapOf<String, String>(); var section = ""
        for (raw in ini.lineSequence()) {
            val line = raw.trim()
            if (line.startsWith('[')) { require(line.endsWith(']')); section = line.drop(1).dropLast(1); continue }
            if (section != "Core" || '=' !in line || line.startsWith('#') || line.startsWith(';')) continue
            val key = line.substringBefore('=').trim()
            if (key in dolphinKeys) { require(key !in values); values[key] = line.substringAfter('=').trim() }
        }
        return values
    }
    fun dolphin(): SaveRootConfiguration? {
        require(Process.myUid() == 0)
        val home = "/storage/emulated/0/Android/data/$DOLPHIN/files"
        // An initialized external-files directory takes precedence in Dolphin's
        // DirectoryInitialization. No fallback to a stale legacy tree.
        val ini = read("$home/Config", "Dolphin.ini", 512 * 1024).toString(Charsets.UTF_8)
        val gameRoot = "$home/GameSettings"
        val root = OwnedStorageNative.openRoot(gameRoot)
        try {
            val identity = OwnedStorageNative.identity(root).take(2)
            val names = File(gameRoot).list() ?: error("Unreadable settings")
            require(names.size <= 1024)
            for (name in names.filter { it.endsWith(".ini", true) }) {
                require(RomCompanionBoundary.validLeaf(name))
                if (dolphinCore(read(gameRoot, name, 65536).toString(Charsets.UTF_8)).isNotEmpty())
                    throw IOException("save_settings_unresolved")
            }
            val fresh = OwnedStorageNative.openRoot(gameRoot)
            try { if (identity != OwnedStorageNative.identity(fresh).take(2)) throw IOException("source_changed") }
            finally { OwnedStorageNative.close(fresh) }
        } finally { OwnedStorageNative.close(root) }
        return dolphinConfiguration(dolphinCore(ini))
    }
    /** Flycast oslib.cpp::getVmuPath, cfg/option.cpp. No filename/title guessing. */
    internal fun flycastConfiguration(home: String, ini: String): SaveRootConfiguration? {
        require(SaveRootConfiguration.validDirectory("$home/data", FLYCAST) && ini.toByteArray().size <= 512 * 1024)
        val values = mutableMapOf<String, String>()
        val relevant = setOf("PerGameVmu", "Dreamcast.VMUPath") + (1..4).flatMap { port ->
            listOf("device$port", "device$port.1", "device$port.2", "device$port.1.net", "device$port.2.net", "device$port.UseNetworkExpansionDevices")
        }
        var section = ""
        for (raw in ini.lineSequence()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith(';') || line.startsWith('#')) continue
            if (line.startsWith('[')) { require(line.endsWith(']')); section = line.drop(1).dropLast(1); continue }
            if ('=' !in line) continue
            val key = line.substringBefore('=').trim()
            // Per-game options are stored as section.name beneath the game ID.
            require(relevant.none { option -> key == "${if (option.startsWith("device")) "input" else "config"}.$option" }) {
                "save_settings_unresolved"
            }
            if (key !in relevant) continue
            val expected = if (key.startsWith("device")) "input" else "config"
            require(section == expected && key !in values) { "save_settings_unresolved" }
            values[key] = line.substringAfter('=').trim()
        }
        fun boolean(key: String, default: Boolean): Boolean = when (values[key]?.lowercase()) {
            null -> default
            "yes", "true", "1" -> true
            "no", "false", "0" -> false
            else -> throw IllegalArgumentException("save_settings_unresolved")
        }
        require(!boolean("PerGameVmu", true)) { "save_settings_unresolved" }
        val directory = values["Dreamcast.VMUPath"].orEmpty().ifEmpty { "$home/data" }.trimEnd('/')
        require(SaveRootConfiguration.validDirectory(directory, FLYCAST))
        val files = (1..4).flatMap { port ->
            val rawParent = values["device$port"]
            require(rawParent == null || rawParent.toIntOrNull() in 0..19)
            val parent = rawParent?.toInt() ?: if (port == 1) 0 else 10
            if (parent == 10) emptyList() else {
                require(!boolean("device$port.UseNetworkExpansionDevices", false)) { "save_settings_unresolved" }
                (1..2).filter { slot ->
                    val key = "device$port.$slot"
                    val value = values[key]
                    require(value == null || value.toIntOrNull() != null)
                    val network = values["$key.net"]
                    require(network == null || network.toIntOrNull() == 0) { "save_settings_unresolved" }
                    (value?.toInt() ?: if (port == 1) 1 else 10) == 1
                }.map { slot -> "vmu_save_${('A'.code + port - 1).toChar()}$slot.bin" }
            }
        }
        if (files.isEmpty()) return null
        return SaveRootConfiguration(directory, FLYCAST, "flycast", "save", "dreamcast-vmu-v1",
            files, emptyList(), emptyList(), resourceId = "vmu-cards", profile = FLYCAST_PROFILE)
    }
    fun flycast(): SaveRootConfiguration? {
        require(Process.myUid() == 0)
        val parser = Xml.newPullParser()
        parser.setInput(ByteArrayInputStream(read("/data/user/0/$FLYCAST/shared_prefs", "${FLYCAST}_preferences.xml", 512 * 1024)), "UTF-8")
        var home: String? = null; var map = false
        while (true) {
            when (parser.nextToken()) {
                XmlPullParser.DOCDECL -> throw IOException("save_settings_unresolved")
                XmlPullParser.START_TAG -> {
                    if (parser.depth == 1) { require(!map && parser.name == "map"); map = true }
                    else if (parser.depth == 2 && parser.getAttributeValue(null, "name") == "home_directory") {
                        require(home == null && parser.name == "string"); home = parser.nextText().trimEnd('/')
                    }
                }
                XmlPullParser.END_DOCUMENT -> break
            }
        }
        require(map && home != null && SaveRootConfiguration.validDirectory("$home/data", FLYCAST))
        val selectedHome = home
        val config = flycastConfiguration(selectedHome, read(selectedHome, "emu.cfg", 512 * 1024).toString(Charsets.UTF_8)) ?: return null
        // Existing older cards outside the write location need an exact mapping;
        // do not silently back up an empty destination instead of their bytes.
        for (name in config.files) {
            if (!File(config.directory, name).exists() && File(selectedHome, name).exists())
                throw IOException("save_settings_unresolved")
        }
        return config
    }
    private val slots = listOf("Slot1", "Slot2") + (1..2).flatMap { port ->
        (2..4).map { slot -> "Multitap${port}_Slot$slot" }
    }
    internal fun netherCards(settings: Map<String, String>): List<String> {
        require(slots.take(2).all { "MemoryCards/${it}_Enable" in settings })
        return slots.filter { slot ->
            val value = settings["MemoryCards/${slot}_Enable"] ?: "false"
            require(value == "true" || value == "false"); value == "true"
        }.map { slot ->
            val name = settings["MemoryCards/${slot}_Filename"] ?: error("Missing card name")
            require(RomCompanionBoundary.validLeaf(name) && name.endsWith(".ps2", true))
            name
        }.distinct().sorted()
    }
    private fun read(rootPath: String, name: String, maximum: Int): ByteArray {
        val root = OwnedStorageNative.openRoot(rootPath)
        try {
            val parent = OwnedStorageNative.identity(root).take(2)
            val fd = OwnedStorageNative.openFile(root, name, false, false)
            try {
                val identity = OwnedStorageNative.identity(fd)
                require(identity[2] in 1..maximum.toLong())
                val bytes = ByteArray(identity[2].toInt()); var offset = 0
                while (offset < bytes.size) {
                    val chunk = OwnedStorageNative.read(fd, offset.toLong(), minOf(65536, bytes.size - offset))
                    require(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                }
                val fresh = OwnedStorageNative.openRoot(rootPath)
                try {
                    if (!identity.contentEquals(OwnedStorageNative.identity(fd)) ||
                        !identity.contentEquals(OwnedStorageNative.entryIdentity(fresh, name)) ||
                        parent != OwnedStorageNative.identity(fresh).take(2)) throw IOException("source_changed")
                } finally { OwnedStorageNative.close(fresh) }
                return bytes
            } finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(root) }
    }
    fun nether(): SaveRootConfiguration? {
        require(Process.myUid() == 0)
        val bytes = read("/data/user/0/$NETHER/shared_prefs", "${NETHER}_preferences.xml", 512 * 1024)
        val parser = Xml.newPullParser()
        parser.setInput(ByteArrayInputStream(bytes), "UTF-8")
        val selected = mutableMapOf<String, String>(); var map = false
        while (true) {
            when (parser.nextToken()) {
                XmlPullParser.DOCDECL -> throw IOException("save_settings_unresolved")
                XmlPullParser.START_TAG -> {
                    if (parser.depth == 1) { require(!map && parser.name == "map"); map = true }
                    else if (parser.depth == 2) {
                        val key = parser.getAttributeValue(null, "name") ?: continue
                        if (slots.any { key == "MemoryCards/${it}_Enable" || key == "MemoryCards/${it}_Filename" }) {
                            require(key !in selected)
                            selected[key] = if (key.endsWith("_Enable")) {
                                require(parser.name == "boolean"); parser.getAttributeValue(null, "value") ?: error("Missing enable")
                            } else { require(parser.name == "string"); parser.nextText() }
                        }
                    }
                }
                XmlPullParser.END_DOCUMENT -> break
            }
        }
        require(map)
        // Overrides need an exact game/card association, not a global-card guess.
        val gameSettings = "/data/media/0/Android/data/$NETHER/files/gamesettings"
        val root = try { OwnedStorageNative.openRoot(gameSettings) }
            catch (error: IOException) { if (error.message != "owned_storage:2") throw error; -1 }
        if (root >= 0) try {
            val identity = OwnedStorageNative.identity(root).take(2)
            val names = File(gameSettings).list() ?: error("Unreadable settings")
            require(names.size <= 1024)
            for (name in names.filter { it.endsWith(".ini", true) }) {
                require(RomCompanionBoundary.validLeaf(name))
                if (read(gameSettings, name, 65536).toString(Charsets.UTF_8).lineSequence()
                    .any { it.trim().equals("[MemoryCards]", true) }) throw IOException("save_settings_unresolved")
            }
            val fresh = OwnedStorageNative.openRoot(gameSettings)
            try { if (identity != OwnedStorageNative.identity(fresh).take(2)) throw IOException("source_changed") }
            finally { OwnedStorageNative.close(fresh) }
        } finally { OwnedStorageNative.close(root) }
        val files = netherCards(selected)
        if (files.isEmpty()) return null
        return SaveRootConfiguration("/storage/emulated/0/Android/data/$NETHER/files/memcards",
            NETHER, "pcsx2", "save", "ps2-shared-memory-cards-v1", files, emptyList(), emptyList(),
            resourceId = "memory-cards", profile = NETHER_PROFILE)
    }
    fun verify(configuration: SaveRootConfiguration) {
        val current = when (configuration.profile) {
            null -> return
            NETHER_PROFILE -> nether()
            FLYCAST_PROFILE -> flycast()
            DOLPHIN_PROFILE -> dolphin()
            AZAHAR_PROFILE -> azahar("00040000" + configuration.files.single().substringBefore('/'))
            else -> throw IOException("source_changed")
        }
        if (current?.json()?.toString() != configuration.json().toString()) throw IOException("source_changed")
    }
}
