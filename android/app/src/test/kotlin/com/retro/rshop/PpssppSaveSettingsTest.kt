package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class PpssppSaveSettingsTest {
    @Test fun resolvesActualTreeDocumentAndSharedPathUsingPspFolderRules() {
        val cases = mapOf(
            "content://com.android.externalstorage.documents/tree/primary%3APSP/document/primary%3APSP" to
                "/storage/emulated/0/PSP/PPSSPP_STATE",
            "content://com.android.externalstorage.documents/tree/75D7-DC5F%3AEmulator%20saves" to
                "/storage/75D7-DC5F/Emulator saves/PSP/PPSSPP_STATE",
            "content://com.android.externalstorage.documents/tree/primary%3A/document/primary%3Apsp" to
                "/storage/emulated/0/psp/PPSSPP_STATE",
            "/storage/emulated/0" to "/storage/emulated/0/PSP/PPSSPP_STATE",
            "/storage/75D7-DC5F/Games/PSP2" to "/storage/75D7-DC5F/Games/PSP2/PSP/PPSSPP_STATE")
        for ((input, expected) in cases) assertEquals(expected, PpssppSaveSettings.configuredDirectory(input))
    }

    @Test fun rejectsUnresolvedForeignEscapingAndMalformedSettingsWithoutGuessing() {
        for (value in listOf("", "../PSP", "/storage/emulated/0/PSP/../other",
            "/storage/emulated/0//PSP", "/storage/emulated/0/PSP\n",
            "content://other.provider/tree/primary%3APSP",
            "content://com.android.externalstorage.documents/tree/primary%3APSP/document/primary%3APSP2",
            "content://com.android.externalstorage.documents/tree/primary%3APSP/document/75D7-DC5F%3APSP",
            "content://com.android.externalstorage.documents/tree/primary%3APSP?query=yes",
            "content://com.android.externalstorage.documents/tree/primary%3APSP%00",
            "content://com.android.externalstorage.documents/tree/primary%3APSP/document/primary%3APSP%2F..%2Fother")) {
            assertTrue(value, runCatching { PpssppSaveSettings.configuredDirectory(value) }.isFailure)
        }
        for (bytes in listOf(byteArrayOf(), ByteArray(4097) { 65 }, byteArrayOf(0xc3.toByte(), 0x28))) {
            assertTrue(runCatching { PpssppSaveSettings.parse(bytes) }.isFailure)
        }
    }
}
