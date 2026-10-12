package com.retro.rshop

/** Pinned 1.22.2 battery-save formats. Capture uses root filesystem evidence,
 * not a frontend reply. Restore still requires CONTENTLESS after content_deinit,
 * after autosave_deinit joins the writer and final CMD_EVENT_SAVE_FILES returns.
 * State tasks require separate analysis; this route must not capture them. */
internal object RetroArchSaveBoundary {
    fun saveDirectory(platform: String): String? = when (platform) {
        "gba" -> "/storage/emulated/0/RetroArch/saves/mGBA"
        "nes" -> "/storage/emulated/0/RetroArch/saves/FCEUmm"
        "gamegear", "mastersystem", "megadrive" -> "/storage/emulated/0/RetroArch/saves/Genesis Plus GX"
        "n64" -> "/storage/emulated/0/RetroArch/saves/Mupen64Plus-Next"
        else -> null
    }
    fun snapshotNames(directory: String, name: String): List<String> {
        require(directory in listOf(saveDirectory("gba"), saveDirectory("nes"), saveDirectory("gamegear"), saveDirectory("n64")))
        require(validName(name))
        // Watch the clock even when absent so creation during SRAM capture
        // cannot produce a falsely complete group.
        return if (directory == saveDirectory("gba")) listOf(name, name.dropLast(4) + ".rtc") else listOf(name)
    }
    // Pinned SAF archive launch: preserve the encoded document ID. Decoding
    // %2F or using the display name would select a different save on disk.
    fun archiveSaveName(encodedLeaf: String, gameGear: Boolean = false): String {
        val extension = if (gameGear) ".zip" else ".7z"
        require(encodedLeaf.endsWith(extension, ignoreCase = true))
        val name = encodedLeaf.dropLast(extension.length) + ".srm"
        require(validName(name))
        return name
    }

    fun contentClosed(response: String): Boolean =
        response == "GET_STATUS CONTENTLESS" || response == "GET_STATUS CONTENTLESS\n"

    fun validName(name: String): Boolean = name.length in 5..255 &&
        name.endsWith(".srm") && name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }
}
