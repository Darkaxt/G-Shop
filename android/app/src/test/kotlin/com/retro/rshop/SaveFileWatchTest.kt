package com.retro.rshop

import android.os.FileObserver
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SaveFileWatchTest {
    @Test fun pcsxWatchKeepsPrivateAndSharedCardsSeparate() {
        val private = SaveFileWatch.Mapping("d".repeat(64),
            "/storage/emulated/0/RetroArch/saves/PCSX-ReARMed", "owned%2FGame.srm", "pcsx-libretro-1")
        val shared = SaveFileWatch.Mapping("e".repeat(64), private.directory, "pcsx-card2.mcd", "pcsx-shared-2")
        val rows = listOf(private, shared)
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO, FileObserver.DELETE)) {
            assertEquals(listOf(private.key), SaveFileWatch.affected(rows, event, private.name))
            assertEquals(listOf(shared.key), SaveFileWatch.affected(rows, event, shared.name))
            for (leaf in listOf("Other.srm", "owned%2FGame.rtc", "Game.chd", "retroarch.cfg"))
                assertTrue(SaveFileWatch.affected(rows, event, leaf).isEmpty())
        }
        for ((route, name) in listOf("pcsx-libretro-2" to private.name,
                "pcsx-shared-2" to "pcsx-card1.mcd", "pcsx-serial-1" to "SLUS.mcd"))
            assertThrows(IllegalArgumentException::class.java) {
                SaveFileWatch.Mapping(private.key, private.directory, name, route)
            }
        assertThrows(IllegalArgumentException::class.java) {
            SaveFileWatch.Mapping(private.key, "/storage/emulated/0/Android/data/other/files/saves",
                private.name, private.route)
        }
    }
    @Test fun sameBoyWatchKeepsEachExactGameAndItsClock() {
        for (route in listOf("gb", "gbc")) {
            val mapping = SaveFileWatch.Mapping("b".repeat(64),
                "/storage/emulated/0/RetroArch/saves/SameBoy", "owned%2FGame.srm", "retroarch-$route")
            assertEquals(listOf(mapping), SaveFileWatch.decode(listOf(mapOf("key" to mapping.key,
                "directory" to mapping.directory, "name" to mapping.name, "route" to mapping.route))))
            for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO, FileObserver.DELETE)) {
                for (leaf in listOf(mapping.name, "owned%2FGame.rtc"))
                    assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), event, leaf))
                for (leaf in listOf("Other.srm", "Other.rtc", "owned%2FGame.state", "../${mapping.name}"))
                    assertTrue(SaveFileWatch.affected(listOf(mapping), event, leaf).isEmpty())
            }
            assertThrows(IllegalArgumentException::class.java) {
                SaveFileWatch.Mapping(mapping.key, "/storage/emulated/0/RetroArch/saves/mGBA", mapping.name, mapping.route)
            }
        }
    }
    @Test fun snesWatchIncludesOnlyItsExactSramAndClock() {
        val mapping = SaveFileWatch.Mapping("a".repeat(64),
            "/storage/emulated/0/RetroArch/saves/Snes9x", "owned%2FGame.srm", "retroarch-snes")
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO, FileObserver.DELETE)) {
            for (leaf in listOf(mapping.name, "owned%2FGame.rtc"))
                assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), event, leaf))
            for (leaf in listOf("Other.rtc", "owned%2FGame.state", "../${mapping.name}"))
                assertTrue(SaveFileWatch.affected(listOf(mapping), event, leaf).isEmpty())
        }
    }
    @Test fun nesWatchBindsOnlyFceummAndTheExactSrm() {
        val mapping = SaveFileWatch.Mapping("f".repeat(64),
            "/storage/emulated/0/RetroArch/saves/FCEUmm", "owned%2FGame.srm", "retroarch-nes")
        assertEquals(listOf(mapping), SaveFileWatch.decode(listOf(mapOf("key" to mapping.key,
            "directory" to mapping.directory, "name" to mapping.name, "route" to mapping.route))))
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO, FileObserver.DELETE)) {
            assertEquals(listOf(mapping.key), SaveFileWatch.affected(listOf(mapping), event, mapping.name))
            for (other in listOf("Other.srm", "owned%2FGame.rtc", "owned%2FGame.state", "../${mapping.name}")) {
                assertTrue(SaveFileWatch.affected(listOf(mapping), event, other).isEmpty())
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            SaveFileWatch.Mapping(mapping.key, "/storage/emulated/0/RetroArch/saves/mGBA", mapping.name, mapping.route)
        }
    }
    @Test fun retroArchWatchKeepsCoreAndExactSavePlusRequiredClock() {
        val gba = SaveFileWatch.Mapping("d".repeat(64),
            "/storage/emulated/0/RetroArch/saves/mGBA", "owned%2FGame.srm", "retroarch-gba")
        val n64 = SaveFileWatch.Mapping("e".repeat(64),
            "/storage/emulated/0/RetroArch/saves/Mupen64Plus-Next", "owned%2FGame.srm", "retroarch-n64")
        for (event in listOf(FileObserver.CLOSE_WRITE, FileObserver.MOVED_TO, FileObserver.DELETE)) {
            assertEquals(listOf(gba.key), SaveFileWatch.affected(listOf(gba), event, gba.name))
            assertEquals(listOf(gba.key), SaveFileWatch.affected(listOf(gba), event, "owned%2FGame.rtc"))
            assertTrue(SaveFileWatch.affected(listOf(n64), event, "owned%2FGame.rtc").isEmpty())
            assertTrue(SaveFileWatch.affected(listOf(gba), event, "Other.srm").isEmpty())
        }
        assertEquals(listOf(gba), SaveFileWatch.decode(listOf(mapOf("key" to gba.key,
            "directory" to gba.directory, "name" to gba.name, "route" to gba.route))))
        for (route in listOf("retroarch-n64", "retroarch-unknown", "retroarch-gamegear")) {
            try { SaveFileWatch.Mapping(gba.key, gba.directory, gba.name, route); fail() }
            catch (_: IllegalArgumentException) {}
        }
        try { SaveFileWatch.Mapping(gba.key, gba.directory, "Game.gba", gba.route); fail() }
        catch (_: IllegalArgumentException) {}
    }
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
