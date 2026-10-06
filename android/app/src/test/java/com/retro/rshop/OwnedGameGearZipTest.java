package com.retro.rshop;

import org.junit.Test;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import static org.junit.Assert.*;

public class OwnedGameGearZipTest {
    private byte[] archive(boolean stored, String... names) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            for (String name : names) {
                byte[] rom = new byte[512 * 1024];
                for (int i = 0; i < rom.length; i++) rom[i] = (byte) (i % 251);
                ZipEntry entry = new ZipEntry(name);
                if (stored) {
                    CRC32 crc = new CRC32(); crc.update(rom);
                    entry.setMethod(ZipEntry.STORED); entry.setSize(rom.length); entry.setCrc(crc.getValue());
                }
                zip.putNextEntry(entry); zip.write(rom); zip.closeEntry();
            }
        }
        return bytes.toByteArray();
    }
    private void validate(byte[] bytes) throws Exception {
        File file = File.createTempFile("rshop-gg-", ".zip");
        try {
            Files.write(file.toPath(), bytes);
            OwnedGameGearZip.validate(file.getPath());
            assertArrayEquals(bytes, Files.readAllBytes(file.toPath()));
        } finally { assertTrue(file.delete()); }
    }
    private void reject(byte[] bytes) throws Exception {
        try { validate(bytes); fail("Unsafe ZIP was accepted"); }
        catch (java.io.IOException expected) { }
    }
    @Test public void storedAndDeflatedSingleMemberRemainUnchanged() throws Exception {
        validate(archive(true, "Game.gg")); validate(archive(false, "Game (USA).gg"));
    }
    @Test public void multiMemberWrongFormatAndUnsafeNamesAreRejected() throws Exception {
        reject(archive(false, "Game.gg", "Other.gg"));
        for (String name : new String[]{"../Game.gg", "folder/Game.gg", "C:Game.gg", "Game.n64", "folder\\Game.gg"}) {
            reject(archive(false, name));
        }
    }
    @Test public void corruptTruncatedAndContradictoryRecordsAreRejected() throws Exception {
        byte[] valid = archive(true, "Game.gg");
        byte[] corrupt = valid.clone(); corrupt[100] ^= 1; reject(corrupt);
        reject(Arrays.copyOf(valid, valid.length - 1));
        byte[] wrongName = valid.clone(); wrongName[30] ^= 1; reject(wrongName);
        byte[] encrypted = valid.clone(); encrypted[6] |= 1; reject(encrypted);
        byte[] extra = Arrays.copyOf(valid, valid.length + 1); reject(extra);
        byte[] budget = valid.clone();
        int central = valid.length - 22 - 46 - "Game.gg".length();
        budget[central + 27] = 2; reject(budget);
        byte[] link = valid.clone(); link[central + 41] = (byte) 0xa0; reject(link);
    }
}
