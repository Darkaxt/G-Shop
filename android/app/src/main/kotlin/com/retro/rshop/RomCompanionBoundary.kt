package com.retro.rshop

import java.util.Locale

/** Shared-folder association only. Changes request coherent capture; this is
 * neither a writer-completion check nor permission to overwrite a cloud head. */
internal object RomCompanionBoundary {
    const val MAX_MEMBERS = 128
    private val excludedExtensions = setOf("7z", "zip", "rar", "gba", "gb", "gbc", "nes", "sfc", "smc",
        "n64", "z64", "v64", "nds", "3ds", "cia", "iso", "cso", "chd", "cue", "bin", "img", "pbp",
        "rvz", "gcm", "wbfs", "wua", "wad", "xci", "nsp", "sms", "gg", "md", "gen", "rom",
        "bios", "cfg", "ini", "conf", "config", "key", "pem", "p12", "pfx", "jks",
        "tmp", "part", "lock")
    fun validLeaf(name: String): Boolean = name.isNotEmpty() && name.length <= 255 &&
        !name.startsWith('.') && !name.endsWith('.') && !name.endsWith(' ') &&
        name.none { it <= '\u001f' || it == '\u007f' || it in "/\\:" }
    fun associated(romName: String, name: String): Boolean {
        if (!validLeaf(romName) || !validLeaf(name) || name == romName) return false
        val split = romName.lastIndexOf('.')
        if (split <= 0 || !name.startsWith(romName.substring(0, split) + ".")) return false
        val lower = name.substring(split + 1).lowercase(Locale.ROOT)
        if (lower.substringAfterLast('.') in excludedExtensions) return false
        val parts = lower.split('.', '-', '_', ' ')
        return parts.none { it in setOf("credential", "credentials", "password", "passwords", "token",
            "tokens", "secret", "secrets", "bios", "settings", "config", "auth") }
    }
    fun validIdentity(value: List<Long>): Boolean = value.size == 5 && value[2] >= 0 && value[4] in 0..999999999L
    fun changed(before: Map<String, List<Long>>, after: Map<String, List<Long>>): List<String> {
        require(listOf(before, after).all { it.size <= MAX_MEMBERS && it.keys.all(::validLeaf) &&
            it.values.all(::validIdentity) })
        return after.keys.filter { after[it] != before[it] }.sorted()
    }
}
