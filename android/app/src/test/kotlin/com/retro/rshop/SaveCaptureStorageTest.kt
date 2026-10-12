package com.retro.rshop

import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import org.junit.Assert.*
import org.junit.Test

class SaveCaptureStorageTest {
    @Test fun melonSaveBindingUsesSharedOrItsStandardRootAssistedSramAndItsOwnFormat() {
        val path = "/storage/emulated/0/Saves/MelonDualDS"
        for (name in listOf("Game.sav", "Game.srm")) {
            assertTrue(SaveCaptureService.validRestoreBinding(name, 4, MelonSaveBoundary.FORMAT, path))
            assertTrue(SaveCaptureService.validRestoreBinding(name, 4, MelonSaveBoundary.FORMAT,
                MelonSaveBoundary.PROTECTED_SOURCE))
        }
        for (name in listOf("../Game.sav", ".sav", "Game.nds", "Game.ml1", "Game.sav.tmp", "Game\\save.sav")) {
            assertFalse(MelonSaveBoundary.validName(name))
        }
        for (source in listOf("/storage/emulated/0", "$path/..", "$path//child",
                "/storage/emulated/0/Android/data/me.magnum.melondualds/files",
                "/storage/emulated/0/Android/data/another.emulator/files/saves", "/data/user/0/me.magnum.melondualds")) {
            assertFalse(SaveCaptureService.validRestoreBinding("Game.sav", 4, MelonSaveBoundary.FORMAT, source))
        }
        assertFalse(SaveCaptureService.validRestoreBinding("Game.sav", MelonSaveBoundary.MAX_BYTES + 1, MelonSaveBoundary.FORMAT, path))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.sav", 4, "mgba-battery", path))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.sav", 4, "mgba-battery", MelonSaveBoundary.PROTECTED_SOURCE))
    }
    @Test fun relatedRestoreAcceptsOnlyTheSramAndItsExactClockCompanion() {
        assertTrue(SaveCaptureService.validGroupNames("Game.srm", listOf("Game.rtc", "Game.srm")))
        for (names in listOf(listOf("Game.srm"), listOf("Game.srm", "Other.rtc"),
            listOf("Game.srm", "Game.srm"), listOf("Game.srm", "../Game.rtc"), listOf("Game.srm", "Game.state"))) {
            assertFalse(SaveCaptureService.validGroupNames("Game.srm", names))
        }
    }
    @Test fun segaCartridgeFormatsHaveExplicitConsoleJournalsAndTheReviewedCoreDirectory() {
        val genesis = "/storage/emulated/0/RetroArch/saves/Genesis Plus GX"
        for (format in listOf("mastersystem-battery", "megadrive-battery")) {
            assertTrue(SaveCaptureService.validRestoreBinding("encoded%2FGame.srm", 65536, format, genesis))
            assertFalse(SaveCaptureService.validRestoreBinding("Game.srm", 65537, format, genesis))
            assertFalse(SaveCaptureService.validRestoreBinding("Game.srm", 4, format,
                "/storage/emulated/0/RetroArch/saves/mGBA"))
            assertFalse(SaveCaptureService.validRestoreBinding("Game.rtc", 4, format, genesis))
            assertFalse(SaveCaptureService.validRestoreBinding("Game.state", 4, format, genesis))
        }
    }
    @Test fun gameGearBatteryRestoreCannotReuseMgbasNamespaceOrStateFormat() {
        val genesis = "/storage/emulated/0/RetroArch/saves/Genesis Plus GX"
        val mgba = "/storage/emulated/0/RetroArch/saves/mGBA"
        assertTrue(SaveCaptureService.validRestoreBinding("Game.srm", 65536,
            "gamegear-battery", genesis))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.srm", 65537,
            "gamegear-battery", genesis))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.srm", 4,
            "gamegear-battery", mgba))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.srm", 4,
            "mgba-battery", genesis))
        assertFalse(SaveCaptureService.validRestoreBinding("Game.state", 4,
            "gamegear-battery", genesis))
    }
    @Test fun restoreJournalsBindTheExactEmulatorFormatAndExpectedDirectory() {
        val slot = "ULUS10001_1.00_0.ppst"
        val psp = "/storage/emulated/0/PSP/PPSSPP_STATE"
        val mgba = "/storage/emulated/0/RetroArch/saves/mGBA"
        assertTrue(SaveCaptureService.validRestoreBinding(slot, 32L * 1024 * 1024, "ppsspp-slot-v1", psp))
        assertTrue(SaveCaptureService.validRestoreBinding("Game.srm", 4, "mgba-battery", mgba))
        for ((name, format, root) in listOf(
            Triple(slot, "mgba-battery", mgba), Triple("Game.srm", "ppsspp-slot-v1", psp),
            Triple(slot, "ppsspp-slot-v1", mgba), Triple("Game.srm", "mgba-battery", psp),
            Triple(slot, "unknown", psp), Triple(slot, "ppsspp-slot-v1", "$psp/.."))) {
            assertFalse(SaveCaptureService.validRestoreBinding(name, 4, format, root))
        }
        assertFalse(SaveCaptureService.validRestoreBinding(slot, 0, "ppsspp-slot-v1", psp))
        assertFalse(SaveCaptureService.validRestoreBinding(slot, PpssppSaveBoundary.MAX_STATE_BYTES + 1,
            "ppsspp-slot-v1", psp))
    }
    @Test fun normalizesTheFrameworkParentBeforeCheckingItsOwnChildren() {
        val directory = Files.createTempDirectory(Paths.get("D:/Temp"), "rshop-capture-root-").toFile()
        val filesDir = File(directory, "files")
        assertTrue(filesDir.mkdir())
        try {
            // Android's framework path can have a different canonical parent.
            // A lexical alias reproduces the same equality failure without a link.
            val frameworkPath = File(directory, "files/../files")
            val root = SaveCaptureService.stagingRoot(frameworkPath)
            assertEquals(File(filesDir.canonicalFile, "save-captures"), root)
            val capture = File(root, "94c67873045b25304ec9cf75defd656e")
            assertEquals(capture.absoluteFile, capture.canonicalFile)
        } finally {
            assertTrue(filesDir.delete())
            assertTrue(directory.delete())
        }
    }
}
