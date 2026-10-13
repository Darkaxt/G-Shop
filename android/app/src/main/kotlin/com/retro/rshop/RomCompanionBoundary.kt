package com.retro.rshop

import java.util.Locale

/** Shared-folder association only. Changes request coherent capture; this is
 * neither a writer-completion check nor permission to overwrite a cloud head. */
internal object RomCompanionBoundary {
    const val MAX_MEMBERS = 128
    const val MAX_BYTES = 512L * 1024 * 1024
    const val MAX_DEPTH = 16
    const val FORMAT = "rom-companion-files-v1"
    fun validDirectory(path: String): Boolean =
        path.matches(Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+")) &&
            path.split('/').drop(1).all { it.isNotEmpty() && it != "." && it != ".." &&
                it.none { c -> c <= '\u001f' || c == '\u007f' || c == '\\' } }
    private val excludedExtensions = setOf("7z", "zip", "rar", "gba", "gb", "gbc", "nes", "sfc", "smc",
        "n64", "z64", "v64", "nds", "3ds", "cia", "iso", "cso", "chd", "cue", "bin", "img", "pbp",
        "rvz", "gcm", "wbfs", "wua", "wad", "xci", "nsp", "sms", "gg", "md", "gen", "rom",
        "bios", "cfg", "ini", "conf", "config", "key", "pem", "p12", "pfx", "jks",
        "tmp", "part", "lock")
    fun validLeaf(name: String): Boolean = name.isNotEmpty() && name.length <= 255 &&
        !name.startsWith('.') && !name.endsWith('.') && !name.endsWith(' ') &&
        name.none { it <= '\u001f' || it == '\u007f' || it in "/\\:" }
    fun validPath(path: String): Boolean = path.length <= 1024 &&
        path.split('/').let { it.size in 1..MAX_DEPTH && it.all(::validLeaf) }
    fun isolated(romName: String, directory: String): Boolean =
        romName.lastIndexOf('.') > 0 && directory.substringAfterLast('/') == romName.substringBeforeLast('.')
    private fun safePart(name: String): Boolean = name.lowercase(Locale.ROOT).split('.', '-', '_', ' ').none {
        it in setOf("credential", "credentials", "password", "passwords", "token", "tokens", "secret",
            "secrets", "bios", "settings", "config", "auth")
    }
    fun associatedDirectory(romName: String, relative: String, isolated: Boolean = false): Boolean {
        if (!validLeaf(romName) || !validPath(relative)) return false
        val stem = romName.substringBeforeLast('.', "")
        if (stem.isEmpty()) return false
        val parts = relative.split('/')
        if (!isolated && parts.first() != stem && !parts.first().startsWith("$stem.")) return false
        if (!isolated && parts.first() != stem && !safePart(parts.first().removePrefix("$stem."))) return false
        return (if (isolated) parts else parts.drop(1)).all(::safePart)
    }
    fun associated(romName: String, name: String, isolated: Boolean = false): Boolean {
        if (!validLeaf(romName) || !validPath(name) || name == romName) return false
        val split = romName.lastIndexOf('.')
        if (split <= 0) return false
        val leaf = name.substringAfterLast('/')
        val prefix = romName.substring(0, split) + "."
        if (name.contains('/')) {
            if (!associatedDirectory(romName, name.substringBeforeLast('/'), isolated)) return false
        } else if (!isolated && !name.startsWith(prefix)) return false
        val lower = (if (leaf.startsWith(prefix)) leaf.removePrefix(prefix) else leaf).lowercase(Locale.ROOT)
        if (lower.substringAfterLast('.') in excludedExtensions) return false
        return safePart(lower)
    }
    fun validIdentity(value: List<Long>): Boolean = value.size == 5 && value[2] >= 0 && value[4] in 0..999999999L
    fun changed(before: Map<String, List<Long>>, after: Map<String, List<Long>>): List<String> {
        require(listOf(before, after).all { it.size <= MAX_MEMBERS && it.keys.all(::validPath) &&
            it.values.all(::validIdentity) })
        return after.keys.filter { after[it] != before[it] }.sorted()
    }
}
