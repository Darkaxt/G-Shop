package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class PpssppSaveBoundaryTest {
    @Test fun onlyCompletedRetailSlotsAreSelected() {
        assertTrue(PpssppSaveBoundary.validName("ULUS10001_1.00_0.ppst"))
        assertTrue(PpssppSaveBoundary.validName("ULES01234_2.01_99.ppst"))
        for (name in listOf("../ULUS10001_1.00_0.ppst", "ULUS10001_1.00_0.ppst.tmp",
                "ULUS10001_1.00_0.jpg", "ULUS10001_1.00_0.undo", "Game.iso", "Game.ppst",
                "ULUS10001_1.00_-1.ppst", "ULUS10001_1.00_100.ppst")) {
            assertFalse(name, PpssppSaveBoundary.validName(name))
        }
    }

    @Test fun mappingIsAnExplicitSharedStateDirectoryNotAnAppDataBypass() {
        assertTrue(PpssppSaveBoundary.validDirectory("/storage/emulated/0/Games/PSP/PPSSPP_STATE"))
        assertTrue(PpssppSaveBoundary.validDirectory("/storage/75D7-DC5F/PSP/PPSSPP_STATE"))
        for (path in listOf("/storage/emulated/0", "/storage/emulated/0/PSP/SAVEDATA",
                "/storage/emulated/0/../PPSSPP_STATE", "/data/user/0/PSP/PPSSPP_STATE",
                "/storage/emulated/0/Android/data/org.ppsspp.ppsspp/PPSSPP_STATE",
                "/storage/emulated/0/PSP//PPSSPP_STATE", "/storage/emulated/0/PSP/PPSSPP_STATE/")) {
            assertFalse(path, PpssppSaveBoundary.validDirectory(path))
        }
    }
}
