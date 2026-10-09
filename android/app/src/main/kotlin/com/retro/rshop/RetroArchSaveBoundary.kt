package com.retro.rshop

/** Pinned 1.22.2 battery-save protocol. PAUSED/SAVE_FILES receipts are not a
 * writer boundary: autosave can still write. CONTENTLESS follows content_deinit,
 * after autosave_deinit joins the writer and final CMD_EVENT_SAVE_FILES returns.
 * State tasks require separate analysis; this route must not capture them. */
internal object RetroArchSaveBoundary {
    // Pinned SAF archive launch: preserve the encoded document ID. Decoding
    // %2F or using the display name would select a different save on disk.
    fun archiveSaveName(encodedLeaf: String): String {
        require(encodedLeaf.endsWith(".7z", ignoreCase = true))
        val name = encodedLeaf.dropLast(3) + ".srm"
        require(validName(name))
        return name
    }

    fun contentClosed(response: String): Boolean =
        response == "GET_STATUS CONTENTLESS" || response == "GET_STATUS CONTENTLESS\n"

    fun validName(name: String): Boolean = name.length in 5..255 &&
        name.endsWith(".srm") && name.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }
}
