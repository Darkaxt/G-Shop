package com.retro.rshop

/** PPSSPP v1.20.4 SaveState::SaveSlot writes a .tmp then renames it on
 * successful completion. Only published retail slots are snapshots; thumbnails,
 * undo files and temporary files are not required state members. This is NOT a
 * writer-quiescence contract for SAVEDATA directories or for restore. */
internal object PpssppSaveBoundary {
    const val MAX_STATE_BYTES = 256L * 1024 * 1024
    const val COMPANION_FORMAT = "ppsspp-screenshot-jpeg-v1"
    private val protected = Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/Android/data/org\\.ppsspp\\.ppsspp/files/.+/PPSSPP_STATE")
    fun isProtectedDirectory(path: String): Boolean = protected.matches(path) && validDirectory(path)
    fun validName(name: String) =
        name.matches(Regex("[A-Z0-9]{9}_[0-9]\\.[0-9]{2}_[0-9]{1,2}\\.ppst"))
    fun validCompanionName(name: String) =
        name.matches(Regex("[A-Z0-9]{9}_[0-9]\\.[0-9]{2}_[0-9]{1,2}\\.jpg"))
    fun validSourceName(name: String) = validName(name) || validCompanionName(name)

    fun validDirectory(path: String): Boolean {
        if (!path.matches(Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+/PPSSPP_STATE"))) return false
        val parts = path.split('/')
        return parts.drop(1).none { it.isEmpty() || it == "." || it == ".." ||
            it.any { c -> c <= '\u001f' || c == '\u007f' || c == '\\' } } &&
            (parts.none { it.equals("Android", ignoreCase = true) } || protected.matches(path))
    }
}
