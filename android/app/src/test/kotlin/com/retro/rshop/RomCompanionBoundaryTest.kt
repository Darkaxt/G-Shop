package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class RomCompanionBoundaryTest {
    @Test fun nestedAndIsolatedFoldersKeepTheirRomBoundary() {
        // A ROM-bound directory may itself have a suffix; the inventory verifies
        // whether it is a real directory rather than inferring type from its name.
        for (path in listOf("Game/images/shot.png", "Game.cache/tiles/frame.dat", "Game/progress.sav", "Game.sav/child"))
            assertTrue(path, RomCompanionBoundary.associated("Game.gba", path))
        for (path in listOf("Other/images/shot.png", "Game2/progress.sav", "Game/bios/bios.dat",
                "Game/images/../Other.sav", "Game/copy.gba", "Game/config/settings.json", "Game.credentials/user.json"))
            assertFalse(path, RomCompanionBoundary.associated("Game.gba", path))
        assertTrue(RomCompanionBoundary.isolated("Game.gba", "/storage/emulated/0/Roms/gba/Game"))
        assertTrue(RomCompanionBoundary.associated("Game.gba", "progress.sav", true))
        assertTrue(RomCompanionBoundary.associated("Game.gba", "images/shot.png", true))
        assertFalse(RomCompanionBoundary.associated("Game.gba", "Game.gba", true))
        assertFalse(RomCompanionBoundary.associated("Game.gba", "credentials.json", true))
    }
    @Test fun sharedFolderAssociatesExactRomSidecarsNotPrefixNeighbours() {
        for (name in listOf("Game.sav", "Game.state1", "Game.png", "Game.gba.state", "Game.cache"))
            assertTrue(name, RomCompanionBoundary.associated("Game.gba", name))
        assertTrue(RomCompanionBoundary.associated("Bioshock.gba", "Bioshock.sav"))
        assertTrue(RomCompanionBoundary.associated("Password.gba", "Password.png"))
        for (name in listOf("Game.gba", "Game 2.sav", "Game2.png", "Other.sav", "Game.chd",
                "Game.zip", "Game.iso", "Game.gba.tmp", "Game.cfg", "Game.ini", "Game.token.json",
                "../Game.sav", "nested/Game.sav", ".Game.sav", "Game.sav/../Other.sav"))
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
