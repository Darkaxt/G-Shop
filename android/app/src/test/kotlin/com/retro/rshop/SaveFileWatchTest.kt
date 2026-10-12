package com.retro.rshop

import android.os.FileObserver
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SaveFileWatchTest {
    private val mapping = SaveFileWatch.Mapping("a".repeat(64),
        "/storage/emulated/0/PSP/PPSSPP_STATE", "ULUS10041_1.00_0.ppst")

    @Test fun completePspFolderWatchAdmitsAllMembersButNotSiblingOrStagePaths() {
        val group = SaveFileWatch.Mapping("c".repeat(64),
            "/storage/emulated/0/PSP/SAVEDATA/ULUS10041DATA00", "ULUS10041DATA00", "ppsspp-savedata")
        assertEquals(listOf(group), SaveFileWatch.decode(listOf(mapOf("key" to group.key,
            "directory" to group.directory, "name" to group.name, "route" to group.route))))
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.CREATE, FileObserver.MOVED_TO,
                FileObserver.MOVED_FROM, FileObserver.DELETE)) {
            for (member in listOf("PARAM.SFO", "CUSTOM.SAV", "EMPTY", "ICON0.PNG")) {
                assertEquals(listOf(group.key), SaveFileWatch.affected(listOf(group), event, member))
            }
            for (member in listOf("../Other", "nested/data", ".rshop-save-group-${"a".repeat(32)}")) {
                assertTrue(SaveFileWatch.affected(listOf(group), event, member).isEmpty())
            }
        }
        assertTrue(SaveFileWatch.affected(listOf(mapping), FileObserver.CREATE, mapping.name).isEmpty())
        try { SaveFileWatch.Mapping(group.key, group.directory, "Other", group.route); fail() }
        catch (_: IllegalArgumentException) {}
    }

    @Test fun onlyExactMappedPublicationOrRemovalRequestsWork() {
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO,
                FileObserver.MOVED_FROM, FileObserver.DELETE)) {
            assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), event, mapping.name))
            for (other in listOf("${mapping.name}.tmp", "Other.ppst", "../${mapping.name}", "Game.iso")) {
                assertTrue(SaveFileWatch.affected(listOf(mapping), event, other).isEmpty())
            }
        }
        assertTrue(SaveFileWatch.affected(listOf(mapping), FileObserver.MODIFY, mapping.name).isEmpty())
        assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), FileObserver.MOVE_SELF, null))
    }

    @Test fun aWatchCannotExpandIntoArbitraryFilesOrProtectedFolders() {
        for (name in listOf("Game.iso", "Game.sav", "../ULUS10041_1.00_0.ppst")) {
            try { SaveFileWatch.Mapping(mapping.key, mapping.directory, name); fail(name) }
            catch (_: IllegalArgumentException) {}
        }
        for (directory in listOf("/storage/emulated/0", "${mapping.directory}/..",
                "/storage/emulated/0/Android/data/org.ppsspp.ppsspp/PPSSPP_STATE")) {
            try { SaveFileWatch.Mapping(mapping.key, directory, mapping.name); fail(directory) }
            catch (_: IllegalArgumentException) {}
        }
        try { SaveFileWatch.Mapping("bad", mapping.directory, mapping.name); fail() }
        catch (_: IllegalArgumentException) {}
    }

    @Test fun melonRouteKeepsExactSaveAssociationAndDecodesKernelFrames() {
        val melon = SaveFileWatch.Mapping("b".repeat(64), MelonSaveBoundary.PROTECTED_SOURCE,
            "Game.sav", "melon")
        val decoded = SaveFileWatch.decode(listOf(mapOf("key" to melon.key,
            "directory" to melon.directory, "name" to melon.name, "route" to "melon")))
        assertEquals(listOf(melon), decoded)
        val bytes = ByteBuffer.allocate(28).order(ByteOrder.nativeOrder())
            .putInt(1).putInt(FileObserver.CLOSE_WRITE).putInt(0).putInt(12)
            .put("Game.sav\u0000\u0000\u0000\u0000".toByteArray()).array()
        val event = RootSaveWatchWorker.events(bytes).single()
        assertEquals(listOf(melon.key), SaveFileWatch.affected(decoded, event.first, event.second))
        assertTrue(SaveFileWatch.affected(decoded, event.first, "Other.sav").isEmpty())
        for (bad in listOf(bytes.copyOf(15), bytes.copyOf(27))) {
            try { RootSaveWatchWorker.events(bad); fail() } catch (_: IllegalArgumentException) {}
        }
        try { SaveFileWatch.Mapping(melon.key, melon.directory, "Game.nds", "melon"); fail() }
        catch (_: IllegalArgumentException) {}
    }
}
