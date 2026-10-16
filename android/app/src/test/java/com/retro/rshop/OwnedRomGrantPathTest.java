package com.retro.rshop;

import java.io.FileNotFoundException;
import java.util.Arrays;
import org.junit.Test;
import static org.junit.Assert.*;

public class OwnedRomGrantPathTest {
    @Test public void standaloneCartridgesRetainTheConsoleAndRejectArchivesAndBundles() {
        String[][] formats = {{"gba", "gba"}, {"gb", "gb"}, {"gbc", "gbc"}, {"nes", "nes"},
            {"snes", "sfc"}, {"snes", "smc"}, {"n64", "z64"}, {"n64", "v64"}, {"n64", "n64"},
            {"gamegear", "gg"}, {"mastersystem", "sms"}, {"megadrive", "md"}, {"sg1000", "sg"}};
        for (String[] format : formats) {
            String name = "Patched." + format[1].toUpperCase();
            assertTrue(OwnedRomGrantPath.rawCartridge(name, format[0]));
            assertTrue(OwnedRomGrantPath.standaloneCartridge(name, "", false, 0, 0));
            assertFalse(OwnedRomGrantPath.standaloneCartridge(name, format[0], false, 0, 0));
            assertFalse(OwnedRomGrantPath.standaloneCartridge(name, "", true, 0, 0));
            assertFalse(OwnedRomGrantPath.standaloneCartridge(name, "", false, 1, 1));
        }
        assertFalse(OwnedRomGrantPath.rawCartridge("Game.gba", "gb"));
        assertFalse(OwnedRomGrantPath.rawCartridge("Game.bin", "atari2600"));
        for (String name : new String[]{"Game.7z", "Game.zip", "Game.exe", "../Game.gba"}) {
            assertFalse(OwnedRomGrantPath.standaloneCartridge(name, "", false, 0, 0));
        }
    }
    @Test public void standaloneDsRetainsItsExactLeafAndRejectsBundles() throws Exception {
        assertTrue(OwnedRomGrantPath.standaloneNds("Game.NDS", "", false, 0, 0));
        for (String name : new String[]{"Game.7z", "Game.zip", "Game.chd", "../Game.nds"}) {
            assertFalse(OwnedRomGrantPath.standaloneNds(name, "", false, 0, 0));
        }
        assertFalse(OwnedRomGrantPath.standaloneNds("Game.nds", "gba", false, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneNds("Game.nds", "", true, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneNds("Game.nds", "", false, 1, 1));
        OwnedRomGrantPath path = OwnedRomGrantPath.parse(Arrays.asList("tree", "copy:17:nds",
            "document", "copy:17:nds/Game.nds"));
        assertEquals("nds", path.platform);
        assertEquals(Long.valueOf(17), path.observationId);
        assertEquals("Game.nds", path.filename);
    }
    @Test public void segaObservedCopiesRetainTheirBoundConsoleLeaf() throws Exception {
        for (String platform : new String[]{"megadrive", "mastersystem", "sg1000"}) {
            String id = "copy:17:" + platform;
            OwnedRomGrantPath path = OwnedRomGrantPath.parse(Arrays.asList("tree", id, "document", id + "/Game.zip"));
            assertEquals(platform, path.platform);
            assertEquals(Long.valueOf(17), path.observationId);
            assertEquals("Game.zip", path.filename);
        }
        for (String platform : new String[]{"32x", "sega", "sg-1000"}) {
            String id = "copy:17:" + platform;
            try { OwnedRomGrantPath.parse(Arrays.asList("tree", id, "document", id + "/Game.zip")); fail("Unmapped console accepted"); }
            catch (FileNotFoundException expected) { }
        }
    }
    @Test public void observedCopyHasASeparateLeafNamespaceAndBoundPlatform() throws Exception {
        OwnedRomGrantPath document = OwnedRomGrantPath.parse(Arrays.asList("tree", "copy:17:gb", "document", "copy:17:gb/Game.7z"));
        assertEquals("copy:17:gb", document.installationId);
        assertEquals("Game.7z", document.filename);
        assertTrue(document.document);
        OwnedRomGrantPath direct = OwnedRomGrantPath.parse(Arrays.asList("copy", "copy:17:gc", "Game.rvz"));
        assertEquals("copy:17:gc", direct.installationId);
        assertFalse(direct.document);
        for (String id : new String[]{"copy:0:gb", "copy:-1:gb", "copy:17:unknown", "copy:17:gb:other", "copy:99999999999999999999:gb"}) {
            try { OwnedRomGrantPath.parse(Arrays.asList("tree", id, "document", id + "/Game.7z")); fail("Invalid copy accepted"); }
            catch (FileNotFoundException expected) { }
        }
        try { OwnedRomGrantPath.parse(Arrays.asList("installation", "copy:17:gb", "Game.7z")); fail("Ownership namespace borrowed"); }
        catch (FileNotFoundException expected) { }
    }
    @Test public void standaloneWuaCannotGrantOtherFormatsArchivesOrBundles() {
        assertTrue(OwnedRomGrantPath.standaloneWua("Game.WUA", "", false, 0, 0));
        for (String extension : new String[]{"zip", "7z", "wud", "wux", "rpx", "chd"}) {
            assertFalse(OwnedRomGrantPath.standaloneWua("Game." + extension, "", false, 0, 0));
        }
        assertFalse(OwnedRomGrantPath.standaloneWua("Game.wua", "n64", false, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneWua("Game.wua", "", true, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneWua("Game.wua", "", false, 1, 1));
        assertFalse(OwnedRomGrantPath.standaloneWua("Game.wua", "", false, 0, 1));
        assertFalse(OwnedRomGrantPath.standaloneWua("../Game.wua", "", false, 0, 0));
    }
    @Test public void standaloneChdDocumentCannotGrantAnArchiveOrBundle() {
        assertTrue(OwnedRomGrantPath.standaloneChd("Game.CHD", "", false, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneChd("Game.zip", "", false, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneChd("Game.chd", "n64", false, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneChd("Game.chd", "", true, 0, 0));
        assertFalse(OwnedRomGrantPath.standaloneChd("Game.chd", "", false, 1, 1));
        assertFalse(OwnedRomGrantPath.standaloneChd("Game.chd", "", false, 0, 1));
        assertFalse(OwnedRomGrantPath.standaloneChd("../Game.chd", "", false, 0, 0));
    }
    @Test public void documentLeafRetainsArchiveNameAndExactInstallation() throws Exception {
        OwnedRomGrantPath path = OwnedRomGrantPath.parse(Arrays.asList("tree", "owned-id", "document",
                "owned-id/Aerial Assault (World) (Rev 1).zip"));
        assertEquals("owned-id", path.installationId);
        assertEquals("Aerial Assault (World) (Rev 1).zip", path.filename);
        assertTrue(path.document);
    }
    @Test public void existingSingleFileGrantsKeepTheirIdentity() throws Exception {
        OwnedRomGrantPath path = OwnedRomGrantPath.parse(Arrays.asList("installation", "owned-id", "Game.rvz"));
        assertEquals("owned-id", path.installationId); assertEquals("Game.rvz", path.filename);
        assertFalse(path.document);
    }
    @Test public void rootSiblingNestedAndArchiveDelimiterAreNotGranted() throws Exception {
        for (String[] segments : new String[][] {
                {"tree", "owned-id"}, {"tree", "owned-id", "document", "owned-id"},
                {"tree", "owned-id", "document", "other-id/Game.zip"},
                {"tree", "owned-id", "document", "owned-id/../Game.zip"},
                {"tree", "owned-id", "document", "owned-id/folder/Game.zip"},
                {"tree", "owned-id", "document", "owned-id/Game.zip#Other.gg"},
                {"installation", "owned-id", "../Game.rvz"},
                {"installation", "owned-id", "Game\u0000.rvz"}}) {
            try { OwnedRomGrantPath.parse(Arrays.asList(segments)); fail("Non-leaf grant accepted"); }
            catch (FileNotFoundException expected) { }
        }
    }
}
