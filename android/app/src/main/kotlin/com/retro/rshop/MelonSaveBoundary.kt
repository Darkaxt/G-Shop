package com.retro.rshop

/** MelonDualDS 0.8.0.rc2 SRAM; ordinary shared or root-assisted standard storage.
 * SaveManager opens, rewrites and closes SRAM on each flush. Capture requires
 * an open-writer census plus an overlapping-mutation guard; publication still
 * requires the stopped runtime. A quiet interval is not either boundary. */
internal object MelonSaveBoundary {
    const val PACKAGE = "me.magnum.melondualds"
    const val VERSION = "0.8.0.rc2"
    const val FORMAT = "melondualds-sram-v1"
    const val MAX_BYTES = 64L * 1024 * 1024
    const val PROTECTED_SOURCE = "/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves"
    const val PROTECTED_BACKING = "/data/media/0/Android/data/me.magnum.melondualds/files/saves"
    fun isProtectedDirectory(path: String): Boolean = path == PROTECTED_SOURCE
    fun backingDirectory(path: String): String {
        require(validDirectory(path))
        return if (path.startsWith("/storage/emulated/0/"))
            "/data/media/0/" + path.removePrefix("/storage/emulated/0/")
        else "/mnt/media_rw/" + path.removePrefix("/storage/")
    }
    fun validName(name: String): Boolean = name.length in 5..255 &&
        (name.endsWith(".sav") || name.endsWith(".srm")) &&
        name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }
    fun validDirectory(path: String): Boolean = isProtectedDirectory(path) ||
        path.matches(Regex("/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+")) &&
            path.split('/').drop(1).all { part -> part.isNotEmpty() && part != "." &&
                part != ".." && !part.equals("android", true) &&
                part.none { it == '\\' || it.code < 32 || it.code == 127 } }
}
