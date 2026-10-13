package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class StandardSaveRootsTest {
    @Test fun dolphinFolderCardsShareHistoryWithoutSelectingSystemData() {
        val config = StandardSaveRoots.dolphinConfiguration(emptyMap())!!
        assertEquals("shared-gc-memory-cards.save", config.logicalRomName)
        assertTrue(config.acceptsFile("USA/Card A/8P-GFZE-f_zero.dat.gci"))
        assertTrue(config.acceptsFile("USA/Card A/MC_SYSTEM_AREA"))
        assertFalse(config.acceptsFile("USA/Card B/Other.gci"))
        assertFalse(config.acceptsFile("SRAM.raw"))
        assertFalse(config.acceptsFile("USA/IPL.bin"))
        assertEquals(8, StandardSaveRoots.dolphinConfiguration(mapOf("SlotB" to "8"))!!.folders.size)
        assertNull(StandardSaveRoots.dolphinConfiguration(mapOf("SlotA" to "255")))
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.dolphinConfiguration(mapOf("GCIFolderAPathOverride" to "/storage/emulated/0/Other"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.dolphinConfiguration(mapOf("SlotA" to "1"))
        }
    }
    @Test fun flycastSelectsOnlyEnabledSharedVirtualCards() {
        val ini = """
            [config]
            PerGameVmu = no
            Dreamcast.VMUPath =
            [input]
            device1 = 0
            device1.1 = 1
            device1.2 = 1
            device2 = 10
            device2.1 = 1
            [achievements]
            Token = never-export-this
        """.trimIndent()
        val config = StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast", ini)
        assertEquals(listOf("vmu_save_A1.bin", "vmu_save_A2.bin"), config!!.files)
        assertEquals("/storage/emulated/0/Flycast/data", config.directory)
        assertEquals("shared-vmu-cards.save", config.logicalRomName)
        val grant = OwnedRomGrantPath.parse(listOf("copy", "copy:17:dreamcast", "Game.chd"))
        assertEquals("dreamcast", grant.platform)
        assertEquals(17L, grant.observationId)
        assertFalse(config.acceptsFile("dc_boot.bin"))
        assertFalse(config.toString().contains("never-export-this"))
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast", ini.replace("PerGameVmu = no", "PerGameVmu = yes"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast", ini + "\n[GAME-ID]\nPerGameVmu = yes")
        }
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast", ini + "\n[GAME-ID]\nconfig.PerGameVmu = yes")
        }
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast", ini.replace("device1.1 = 1", "device1.1 = 1\ndevice1.1.net = 1"))
        }
        val custom = StandardSaveRoots.flycastConfiguration("/storage/emulated/0/Flycast",
            ini.replace("Dreamcast.VMUPath =", "Dreamcast.VMUPath = /storage/1234-ABCD/VMUs"))
        assertEquals("/storage/1234-ABCD/VMUs", custom!!.directory)
    }
    @Test fun settingsSelectEnabledPhysicalCardsNotRomNamesOrDisabledSlots() {
        val settings = mapOf("MemoryCards/Slot1_Enable" to "true",
            "MemoryCards/Slot1_Filename" to "Mcd001.ps2", "MemoryCards/Slot2_Enable" to "false",
            "MemoryCards/Slot2_Filename" to "Unused.ps2", "MemoryCards/Multitap1_Slot2_Enable" to "true",
            "MemoryCards/Multitap1_Slot2_Filename" to "Extra.ps2")
        assertEquals(listOf("Extra.ps2", "Mcd001.ps2"), StandardSaveRoots.netherCards(settings))
        assertEquals(listOf("Mcd001.ps2"), StandardSaveRoots.netherCards(settings + mapOf(
            "MemoryCards/Multitap1_Slot2_Filename" to "Mcd001.ps2")))
        assertThrows(IllegalArgumentException::class.java) {
            StandardSaveRoots.netherCards(settings + mapOf("MemoryCards/Slot1_Filename" to "../other.ps2"))
        }
    }
}
