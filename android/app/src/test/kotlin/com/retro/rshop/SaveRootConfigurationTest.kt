package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class SaveRootConfigurationTest {
    @Test fun privateFilesRootStillRequiresExactPackageAndSelectedMembers() {
        assertTrue(SaveRootConfiguration.validDirectory("/data/user/0/example.emulator/files", "example.emulator"))
        assertTrue(SaveRootConfiguration.validDirectory("/data/data/example.emulator/files", "example.emulator"))
        for (path in listOf("/data/user/0/other.app/files", "/data/user/0/example.emulator",
                "/data/user/0/example.emulator/shared_prefs", "/data/user/0/example.emulator/files/../shared_prefs"))
            assertFalse(path, SaveRootConfiguration.validDirectory(path, "example.emulator"))
    }
    @Test fun configuredSharedResourceUsesOneLogicalNameNotTheInitiatingRom() {
        val config = SaveRootConfiguration("/storage/emulated/0/Emulator/memcards",
            "example.emulator", "example", "save", "memory-card-v1", listOf("Mcd001.ps2"),
            emptyList(), listOf("Mcd001.ps2"), resourceId = "card-1")
        assertEquals("shared-card-1.save", config.logicalRomName)
        assertTrue(config.acceptsFile("Mcd001.ps2"))
        assertFalse(config.acceptsFile("Mcd002.ps2"))
    }
    @Test fun configuredGroupsReuseExactFileAndDirectorySelection() {
        val config = SaveRootConfiguration("/data/user/0/example.emulator/files/saves",
            "example.emulator", "example", "save", "example-save-v1",
            listOf("card.bin", "Game.sav", "Game.rtc"), listOf("TITLE123"), listOf("Game.sav"))
        assertTrue(config.acceptsFile("card.bin"))
        assertTrue(config.acceptsFile("TITLE123/slot/save.dat"))
        assertTrue(config.acceptsDirectory("TITLE123/slot"))
        assertTrue(config.completeGroup(setOf("Game.sav")))
        assertTrue(config.completeGroup(emptySet()))
        assertFalse(config.completeGroup(setOf("Game.rtc")))
        for (name in listOf("Other.sav", "TITLE124/slot/save.dat", "TITLE123/bios.bin",
                "TITLE123/settings.ini", "TITLE123/other.iso", "../Game.sav"))
            assertFalse(name, config.acceptsFile(name))
        assertTrue(SaveRootConfiguration.validDirectory(config.directory, config.emulator))
        assertFalse(SaveRootConfiguration.validDirectory("/data/user/0/other.app/files/saves", config.emulator))
    }
    @Test fun configuredWatchAdmitsOnlyItsGameFiles() {
        val config = SaveRootConfiguration("/storage/emulated/0/Emulator/saves", "example.emulator",
            "example", "state", "example-state-v1", listOf("Game.state"), emptyList(), emptyList())
        val mapping = SaveFileWatch.Mapping("a".repeat(64), config.directory, "Game.gba", "rom-companion", config)
        assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), 8, "Game.state"))
        assertTrue(SaveFileWatch.affected(listOf(mapping), 8, "Other.state").isEmpty())
    }
}
