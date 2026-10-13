package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class StandardSaveRootsTest {
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
