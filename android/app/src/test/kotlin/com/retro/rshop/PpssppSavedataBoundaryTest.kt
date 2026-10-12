package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class PpssppSavedataBoundaryTest {
    @Test fun ownedRestoreDirectoriesAreNotGameSaveFolders() {
        val stage = ".rshop-save-group-" + "a".repeat(32)
        assertTrue(PpssppSavedataBoundary.validStage(stage))
        assertFalse(PpssppSavedataBoundary.validMember(stage))
        assertFalse(PpssppSavedataBoundary.validDirectory("/storage/emulated/0/PSP/SAVEDATA/$stage"))
        for (bad in listOf(".rshop-save-group-", stage + "x", stage.uppercase(), "../$stage"))
            assertFalse(PpssppSavedataBoundary.validStage(bad))
    }
    @Test fun memoryStickSaveFoldersAreDistinctFromStateSlotsAndPrivateSettings() {
        for (parent in listOf("/storage/emulated/0/PSP/SAVEDATA", "/storage/emulated/0/psp/SAVEDATA",
                "/storage/75D7-DC5F/Games/PSP/SAVEDATA", "/storage/emulated/0/.rshop-custom:stick/PSP/SAVEDATA",
                "/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/PSP/SAVEDATA")) {
            assertTrue(PpssppSavedataBoundary.validParent(parent))
            assertTrue(PpssppSavedataBoundary.validDirectory("$parent/ULUS10001DATA00"))
        }
        for (parent in listOf("/storage/emulated/0/PSP/PPSSPP_STATE", "/data/user/0/org.ppsspp.ppsspp/files",
                "/storage/emulated/0/Android/data/other/files/PSP/SAVEDATA",
                "/storage/emulated/0/../PSP/SAVEDATA", "/storage/emulated/0/PSP//SAVEDATA")) {
            assertFalse(PpssppSavedataBoundary.validParent(parent))
            assertFalse(PpssppSavedataBoundary.validDirectory("$parent/ULUS10001DATA00"))
        }
    }

    @Test fun customPayloadNamesAndEmptyCompanionsBelongToTheWholeFolder() {
        for (name in listOf("PARAM.SFO", "DATA.BIN", "ICON0.PNG", "ICON1.PMF", "PIC1.PNG", "SND0.AT3",
                "CUSTOM.SAV", "SETTINGS.DAT", "EMPTY", "game slot 1.dat")) {
            assertTrue(PpssppSavedataBoundary.validMember(name))
        }
        assertTrue(PpssppSavedataBoundary.validMembers(listOf("PARAM.SFO", "CUSTOM.SAV", "EMPTY")))
        for (bad in listOf("", ".", "..", "../DATA.BIN", "nested/DATA.BIN", "a\\b", "x:y",
                "bad\u0000", "bad.", "bad ", ".rshop-save-restore-" + "a".repeat(32))) {
            assertFalse(PpssppSavedataBoundary.validMember(bad))
        }
        assertFalse(PpssppSavedataBoundary.validMembers(listOf("DATA.BIN", "DATA.BIN")))
        assertFalse(PpssppSavedataBoundary.validMembers(emptyList()))
        assertFalse(PpssppSavedataBoundary.validMembers(List(129) { "FILE$it" }))
    }
}
