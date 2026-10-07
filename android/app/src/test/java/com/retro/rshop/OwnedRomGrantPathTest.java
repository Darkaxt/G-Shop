package com.retro.rshop;

import java.io.FileNotFoundException;
import java.util.Arrays;
import org.junit.Test;
import static org.junit.Assert.*;

public class OwnedRomGrantPathTest {
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
