package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class RomCompanionBoundaryTest {
    @Test fun sharedFolderAssociatesExactRomSidecarsNotPrefixNeighbours() {
        for (name in listOf("Game.sav", "Game.state1", "Game.png", "Game.gba.state", "Game.cache"))
            assertTrue(name, RomCompanionBoundary.associated("Game.gba", name))
        assertTrue(RomCompanionBoundary.associated("Bioshock.gba", "Bioshock.sav"))
        assertTrue(RomCompanionBoundary.associated("Password.gba", "Password.png"))
        for (name in listOf("Game.gba", "Game 2.sav", "Game2.png", "Other.sav", "Game.chd",
                "Game.zip", "Game.iso", "Game.gba.tmp", "Game.cfg", "Game.ini", "Game.token.json",
                "../Game.sav", "nested/Game.sav", ".Game.sav", "Game.sav/child"))
            assertFalse(name, RomCompanionBoundary.associated("Game.gba", name))
    }

    @Test fun changedSnapshotDetectsReplacementWithoutTimestampWinning() {
        val old = mapOf("Game.sav" to listOf(1L, 2L, 4L, 100L, 0L),
            "Game.png" to listOf(1L, 3L, 8L, 100L, 0L))
        val next = mapOf("Game.sav" to listOf(1L, 4L, 4L, 100L, 0L),
            "Game.png" to old.getValue("Game.png"),
            "Game.cache" to listOf(1L, 5L, 0L, 99L, 0L))
        assertEquals(listOf("Game.cache", "Game.sav"), RomCompanionBoundary.changed(old, next))
        assertTrue(RomCompanionBoundary.changed(next, next).isEmpty())
        // Removal is not an upload and must not become remote deletion.
        assertTrue(RomCompanionBoundary.changed(old, emptyMap()).isEmpty())
    }

    @Test fun unsupportedOrOversizedSnapshotIsNotSilentlyTruncated() {
        assertThrows(IllegalArgumentException::class.java) {
            RomCompanionBoundary.changed(emptyMap(), mapOf("Game.sav" to listOf(1L)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            RomCompanionBoundary.changed(emptyMap(), (0..RomCompanionBoundary.MAX_MEMBERS)
                .associate { "Game.$it" to listOf(1L, it.toLong(), 0L, 100L, 0L) })
        }
    }
}
