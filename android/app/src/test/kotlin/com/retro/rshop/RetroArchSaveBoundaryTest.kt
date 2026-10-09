package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class RetroArchSaveBoundaryTest {
    @Test fun saveTargetRetainsTheExactEncodedLaunchDocumentLeaf() {
        assertEquals("installation%2FAero%20the%20Acro-Bat%20(Europe).srm",
            RetroArchSaveBoundary.archiveSaveName("installation%2FAero%20the%20Acro-Bat%20(Europe).7z"))
        assertEquals("copy%3A42%3Agba%2FGame.srm",
            RetroArchSaveBoundary.archiveSaveName("copy%3A42%3Agba%2FGame.7z"))
        for (leaf in listOf("Game.zip", "installation/Game.7z", "bad\\Game.7z", "a".repeat(256) + ".7z")) {
            assertThrows(IllegalArgumentException::class.java) { RetroArchSaveBoundary.archiveSaveName(leaf) }
        }
    }

    @Test fun requiresExactContentlessReceipt() {
        assertTrue(RetroArchSaveBoundary.contentClosed("GET_STATUS CONTENTLESS\n"))
        assertTrue(RetroArchSaveBoundary.contentClosed("GET_STATUS CONTENTLESS"))
        for (response in listOf("", "OK", "GET_STATUS PAUSED mgba,Game,crc32=12345678",
            "GET_STATUS PLAYING mgba,Game,crc32=12345678", "GET_STATUS CONTENTLESS bad",
            "GET_STATUS CONTENTLESS\nGET_STATUS PLAYING", "GET_STATUS CONTENTLESS\u0000")) {
            assertFalse(response, RetroArchSaveBoundary.contentClosed(response))
        }
    }

    @Test fun acceptsOnlyExplicitBatteryNames() {
        assertTrue(RetroArchSaveBoundary.validName("Pokémon - Odyssey (USA).srm"))
        for (name in listOf("../Game.srm", "Game.state", "Game.gba", "Game.srm/other",
            "Game\\other.srm", "Game\u0000.srm", "Game.rtc", ".srm")) {
            assertFalse(name, RetroArchSaveBoundary.validName(name))
        }
    }
}
