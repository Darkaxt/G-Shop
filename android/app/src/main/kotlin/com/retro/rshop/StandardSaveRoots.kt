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
        if (configuration.profile != null &&
            (configuration.profile != NETHER_PROFILE || nether()?.json()?.toString() != configuration.json().toString()))
            throw IOException("source_changed")
    }
}
