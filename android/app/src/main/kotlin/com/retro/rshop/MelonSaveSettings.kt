package com.retro.rshop

import android.os.Process
import android.util.Xml
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.URI

/** The installed runtime's three save-location preferences, read-only. No
 * general private-file reader, settings export or title-based save guessing. */
internal object MelonSaveSettings {
    private const val PREF_ROOT = "/data/user/0/me.magnum.melondualds/shared_prefs"
    private const val PREF_NAME = "me.magnum.melondualds_preferences.xml"
    private const val MAX_SETTINGS = 1024 * 1024

    fun configuredDirectory(besideRom: Boolean, customTree: String?): String? {
        if (besideRom || customTree == null) return null
        val uri = URI(customTree)
        require(uri.scheme == "content" && uri.rawAuthority == "com.android.externalstorage.documents" &&
            uri.rawQuery == null && uri.rawFragment == null &&
            uri.rawPath.matches(Regex("/tree/[^/]+")))
        val document = uri.path.removePrefix("/tree/")
        val volume = document.substringBefore(':')
        require(':' in document && (volume == "primary" || volume.matches(Regex("[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}"))))
        val root = if (volume == "primary") "/storage/emulated/0" else "/storage/$volume"
        return "$root/${document.substringAfter(':')}".also {
            require(MelonSaveBoundary.validDirectory(it))
        }
    }

    internal fun parse(bytes: ByteArray): JSONObject {
        require(bytes.size in 1..MAX_SETTINGS)
        val parser = Xml.newPullParser()
        parser.setInput(ByteArrayInputStream(bytes), "UTF-8")
        var besideRom = true
        var srm = false
        var custom: String? = null
        val seen = mutableSetOf<String>()
        var map = false
        while (true) {
            when (parser.nextToken()) {
                XmlPullParser.DOCDECL -> throw IOException("save_settings_unresolved")
                XmlPullParser.START_TAG -> {
                    if (parser.depth == 1) {
                        require(!map && parser.name == "map"); map = true
                    } else if (parser.depth == 2) {
                        val key = parser.getAttributeValue(null, "name")
                        if (key in setOf("use_rom_dir", "save_file_use_srm_extension", "sram_dir")) {
                            require(seen.add(key!!))
                            if (key == "sram_dir") {
                                require(parser.name == "set")
                                val values = mutableListOf<String>()
                                while (parser.nextToken() != XmlPullParser.END_TAG || parser.depth != 2) {
                                    require(parser.eventType != XmlPullParser.END_DOCUMENT && parser.eventType != XmlPullParser.DOCDECL)
                                    if (parser.eventType == XmlPullParser.START_TAG) {
                                        require(parser.depth == 3 && parser.name == "string" && values.isEmpty())
                                        values.add(parser.nextText())
                                    }
                                }
                                custom = values.singleOrNull()
                            } else {
                                require(parser.name == "boolean")
                                val value = parser.getAttributeValue(null, "value")
                                require(value == "true" || value == "false")
                                if (key == "use_rom_dir") besideRom = value == "true" else srm = value == "true"
                            }
                        }
                    }
                }
                XmlPullParser.END_DOCUMENT -> break
            }
        }
        require(map)
        val directory = configuredDirectory(besideRom, custom)
        return JSONObject().put("mode", if (directory == null) "rom" else "custom")
            .put("directory", directory ?: JSONObject.NULL).put("extension", if (srm) "srm" else "sav")
    }

    fun read(): JSONObject {
        require(Process.myUid() == 0)
        val root = OwnedStorageNative.openRoot(PREF_ROOT)
        try {
            val parent = OwnedStorageNative.identity(root)
            val fd = OwnedStorageNative.openFile(root, PREF_NAME, false, false)
            try {
                val before = OwnedStorageNative.identity(fd)
                require(before[2] in 1..MAX_SETTINGS.toLong())
                val bytes = ByteArray(before[2].toInt())
                var offset = 0
                while (offset < bytes.size) {
                    val chunk = OwnedStorageNative.read(fd, offset.toLong(), minOf(65536, bytes.size - offset))
                    require(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                }
                if (!before.contentEquals(OwnedStorageNative.identity(fd)) ||
                    !before.contentEquals(OwnedStorageNative.entryIdentity(root, PREF_NAME)))
                    throw IOException("source_changed")
                val current = OwnedStorageNative.openRoot(PREF_ROOT)
                try {
                    if (!parent.take(2).equals(OwnedStorageNative.identity(current).take(2)))
                        throw IOException("source_changed")
                } finally { OwnedStorageNative.close(current) }
                return parse(bytes)
            } finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(root) }
    }
}
