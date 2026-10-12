package com.retro.rshop

import android.os.Process
import java.io.IOException
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Read only PPSSPP's exact Memory Stick selection. See v1.20.4 NativeApp.cpp
 * and GetSysDirectory in Core/Util/PathUtil.cpp. No settings export or scan. */
internal object PpssppSaveSettings {
    const val PACKAGE = "org.ppsspp.ppsspp"
    private const val ROOT = "/data/user/0/org.ppsspp.ppsspp/files"
    private const val NAME = "memstick_dir.txt"
    private const val MAX_BYTES = 4096

    internal fun configuredDirectory(value: String): String {
        require(value.isNotEmpty() && value.length <= MAX_BYTES &&
            value.none { it <= '\u001f' || it == '\u007f' || it == '\\' })
        val path = if (value.startsWith("/storage/")) value else {
            val uri = URI(value)
            require(uri.scheme == "content" && uri.rawAuthority == "com.android.externalstorage.documents" &&
                uri.rawQuery == null && uri.rawFragment == null)
            val raw = uri.rawPath.split('/')
            require(raw.size in setOf(3, 5) && raw[0].isEmpty() && raw[1] == "tree" &&
                (raw.size == 3 || raw[3] == "document"))
            // Decode each URI segment separately so encoded separators cannot
            // change the URI grammar before tree containment is checked.
            fun decode(segment: String) = URI("content://resolver/$segment").path.removePrefix("/")
            val tree = decode(raw[2])
            val document = if (raw.size == 5) decode(raw[4]) else tree
            require(document == tree || document.startsWith(
                if (tree.endsWith(':')) tree else tree.trimEnd('/') + "/"))
            require(':' in document)
            val volume = document.substringBefore(':')
            require(volume == "primary" || volume.matches(Regex("[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}")))
            val root = if (volume == "primary") "/storage/emulated/0" else "/storage/$volume"
            val relative = document.substringAfter(':')
            if (relative.isEmpty()) root else "$root/$relative"
        }
        require(path.matches(Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})(/.*)?")))
        require(path.split('/').drop(1).none { it.isEmpty() || it == "." || it == ".." ||
            it.any { c -> c <= '\u001f' || c == '\u007f' || c == '\\' } })
        val psp = if (path.substringAfterLast('/').equals("PSP", ignoreCase = true)) path else "$path/PSP"
        return "$psp/PPSSPP_STATE".also { require(PpssppSaveBoundary.validDirectory(it)) }
    }

    internal fun parse(bytes: ByteArray): String {
        require(bytes.size in 1..MAX_BYTES)
        return configuredDirectory(Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString())
    }

    fun read(): String {
        require(Process.myUid() == 0)
        val root = OwnedStorageNative.openRoot(ROOT)
        try {
            val parent = OwnedStorageNative.identity(root)
            val fd = OwnedStorageNative.openFile(root, NAME, false, false)
            try {
                val before = OwnedStorageNative.identity(fd)
                require(before[2] in 1..MAX_BYTES.toLong())
                val bytes = ByteArray(before[2].toInt())
                var offset = 0
                while (offset < bytes.size) {
                    val chunk = OwnedStorageNative.read(fd, offset.toLong(), minOf(65536, bytes.size - offset))
                    require(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                }
                if (!before.contentEquals(OwnedStorageNative.identity(fd)) ||
                    !before.contentEquals(OwnedStorageNative.entryIdentity(root, NAME))) throw IOException("source_changed")
                val fresh = OwnedStorageNative.openRoot(ROOT)
                try {
                    if (parent.take(2) != OwnedStorageNative.identity(fresh).take(2)) throw IOException("source_changed")
                } finally { OwnedStorageNative.close(fresh) }
                return parse(bytes)
            } finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(root) }
    }
}
