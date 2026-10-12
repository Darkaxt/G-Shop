package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class MelonSaveSettingsTest {
    @Test fun selectedCustomTreeResolvesWithoutAPicker() {
        assertEquals("/storage/emulated/0/RetroArch/saves",
            MelonSaveSettings.configuredDirectory(false,
                "content://com.android.externalstorage.documents/tree/primary%3ARetroArch%2Fsaves"))
        assertEquals("/storage/75D7-DC5F/Emulator saves/DS",
            MelonSaveSettings.configuredDirectory(false,
                "content://com.android.externalstorage.documents/tree/75D7-DC5F%3AEmulator%20saves%2FDS"))
    }
    @Test fun saveBesideRomIgnoresAStaleCustomTree() {
        assertNull(MelonSaveSettings.configuredDirectory(true,
            "content://com.android.externalstorage.documents/tree/primary%3ARetroArch%2Fsaves"))
        assertNull(MelonSaveSettings.configuredDirectory(false, null))
    }
    @Test fun customResolutionNeverSubstitutesAnUnrelatedOrEscapingPath() {
        for (uri in listOf(
            "content://other.provider/tree/primary%3ASaves",
            "content://com.android.externalstorage.documents/tree/primary%3A..%2FSaves",
            "content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata%2Fother",
            "content://com.android.externalstorage.documents/tree/primary%3ASaves?extra=yes",
            "content://com.android.externalstorage.documents/tree/primary%3ASaves%2F%2FDS",
            "content://com.android.externalstorage.documents/tree/primary%3ASaves%00",
            "content://com.android.externalstorage.documents/tree/primary%3A",
            "file:///data/user/0/other")) {
            try { MelonSaveSettings.configuredDirectory(false, uri); fail(uri) }
            catch (_: IllegalArgumentException) { }
        }
    }
}
