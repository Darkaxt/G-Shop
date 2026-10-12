package com.retro.rshop

/** Complete flat SAVEDATA folders, separate from save-state slots. PPSSPP's
 * utility format can contain 99 listed payloads plus metadata/media. Unknown
 * members are never silently filtered out. No save-content parsing is needed. */
internal object PpssppSavedataBoundary {
    const val FORMAT = "ppsspp-savedata-v1"
    const val MAX_MEMBERS = 128
    const val MAX_BYTES = 512L * 1024 * 1024
    fun validStage(name: String): Boolean = name.matches(Regex("\\.rshop-save-group-[a-f0-9]{32}"))
    private val public = Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+/[Pp][Ss][Pp]/SAVEDATA")
    private val standard = Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/[Pp][Ss][Pp]/SAVEDATA")
    private val protected = Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/Android/data/org\\.ppsspp\\.ppsspp/files(/.*)?/[Pp][Ss][Pp]/SAVEDATA")

    fun validMember(name: String): Boolean = name.isNotEmpty() && name.length <= 255 &&
        name != "." && name != ".." && !name.startsWith(".rshop-") &&
        !name.endsWith('.') && !name.endsWith(' ') &&
        name.none { it <= '\u001f' || it == '\u007f' || it in "/\\:" }
    fun validMembers(names: List<String>): Boolean = names.size in 1..MAX_MEMBERS &&
        names.toSet().size == names.size && names.all(::validMember)
    fun validParent(path: String): Boolean {
        if (!public.matches(path) && !standard.matches(path)) return false
        val parts = path.split('/').drop(1)
        return parts.none { it.isEmpty() || it == "." || it == ".." ||
            it.any { c -> c <= '\u001f' || c == '\u007f' || c == '\\' } } &&
            (parts.none { it.equals("Android", true) } || protected.matches(path))
    }
    fun validDirectory(path: String): Boolean = validParent(path.substringBeforeLast('/', "")) &&
        validMember(path.substringAfterLast('/'))
    fun isProtectedDirectory(path: String): Boolean = validDirectory(path) &&
        protected.matches(path.substringBeforeLast('/'))
}
