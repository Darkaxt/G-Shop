package com.retro.rshop;

import org.junit.Test;
import org.tukaani.xz.FinishableWrapperOutputStream;
import org.tukaani.xz.LZMA2Options;
import org.tukaani.xz.LZMAOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import static org.junit.Assert.*;

public class OwnedN64SevenZipTest {
    @Test public void nesProfileStreamsInesAndNes2IdentityWithoutChangingArchive() throws Exception {
        for (boolean nes2 : new boolean[]{false, true}) {
            byte[] raw = new byte[16 + 16384 + 8192];
            System.arraycopy(new byte[]{'N', 'E', 'S', 0x1a}, 0, raw, 0, 4);
            raw[4] = 1; raw[5] = 1; raw[7] = (byte) (nes2 ? 8 : 0);
            for (int codec : new int[]{0, 1, 2}) {
                for (boolean encodedHeader : new boolean[]{false, true}) {
                    byte[] encoded = archive("Game.nes", raw, codec, encodedHeader, raw.length, codec == 2 ? 0 : 4096, 1);
                    File file = File.createTempFile("rshop-nes-identity-", ".7z");
                    try {
                        Files.write(file.toPath(), encoded);
                        java.util.Map<String, Object> value = OwnedN64SevenZip.validate(file.getPath(), "nes");
                        assertEquals("Game.nes", value.get("filename"));
                        assertEquals((long) raw.length, value.get("sizeBytes"));
                        assertEquals(hash(raw, "MD5"), value.get("md5"));
                        assertEquals(hash(raw, "SHA-1"), value.get("sha1"));
                        assertNotEquals(hash(encoded, "MD5"), value.get("md5"));
                        assertArrayEquals(encoded, Files.readAllBytes(file.toPath()));
                    } finally { assertTrue(file.delete()); }
                }
            }
        }
    }

    @Test public void nesProfileRejectsInvalidHeaderNamesAndWorkBudget() throws Exception {
        byte[] raw = rom();
        System.arraycopy(new byte[]{'N', 'E', 'S', 0x1a}, 0, raw, 0, 4);
        byte[][] invalid = {
            archive("Game.gb", raw, 1, true, raw.length, 4096, 1),
            archive("Game.sfc", raw, 1, true, raw.length, 4096, 1),
            archive("../Game.nes", raw, 1, true, raw.length, 4096, 1),
            archive("Game.nes", rom(), 1, true, raw.length, 4096, 1),
            archive("Game.nes", Arrays.copyOf(raw, 4), 1, true, 4, 4096, 1),
            archive("Game.nes", raw, 1, true, 16L * 1024 * 1024 + 1, 4096, 1),
            archive("Game.nes", raw, 1, true, raw.length, 4096, 2),
        };
        for (byte[] encoded : invalid) {
            File file = File.createTempFile("rshop-nes-reject-", ".7z");
            try {
                Files.write(file.toPath(), encoded);
                try { OwnedN64SevenZip.validate(file.getPath(), "nes"); fail("Invalid NES profile accepted"); }
                catch (IOException expected) { assertEquals("unsupported_archive", expected.getMessage()); }
            } finally { assertTrue(file.delete()); }
        }
    }

    @Test public void nesMemberCannotBorrowAnotherConsoleProfile() throws Exception {
        byte[] raw = rom();
        System.arraycopy(new byte[]{'N', 'E', 'S', 0x1a}, 0, raw, 0, 4);
        File file = File.createTempFile("rshop-nes-mapping-", ".7z");
        try {
            Files.write(file.toPath(), archive("Game.nes", raw, 1, true, raw.length, 4096, 1));
            for (String platform : new String[]{"n64", "gb", "gbc", "gba", "snes"}) {
                try { OwnedN64SevenZip.validate(file.getPath(), platform); fail("Wrong console accepted"); }
                catch (IOException expected) { assertEquals("unsupported_archive", expected.getMessage()); }
            }
        } finally { assertTrue(file.delete()); }
    }

    @Test public void mappedGbaSevenZipStreamsMemberIdentityWithoutChangingArchive() throws Exception {
        byte[] raw = rom();
        raw[0] = 0;
        byte[] encoded = archive("Game.gba", raw, 1, true, raw.length, 4096, 1);
        File file = File.createTempFile("rshop-gba-identity-", ".7z");
        try {
            Files.write(file.toPath(), encoded);
            java.util.Map<String, Object> value = OwnedN64SevenZip.validate(file.getPath(), "gba");
            assertEquals("Game.gba", value.get("filename"));
            assertEquals((long) raw.length, value.get("sizeBytes"));
            assertEquals(hash(raw, "SHA-1"), value.get("sha1"));
            assertEquals(hash(raw, "MD5"), value.get("md5"));
            assertNotEquals(hash(encoded, "MD5"), value.get("md5"));
            assertArrayEquals(encoded, Files.readAllBytes(file.toPath()));
        } finally { assertTrue(file.delete()); }
    }

    @Test public void gbaProfileAcceptsRawStreamAboveGameBoyBudget() throws Exception {
        byte[] raw = new byte[17 * 1024 * 1024];
        byte[] encoded = archive("Large.gba", raw, 1, true, raw.length, 4096, 1);
        File file = File.createTempFile("rshop-gba-budget-", ".7z");
        try {
            Files.write(file.toPath(), encoded);
            java.util.Map<String, Object> value = OwnedN64SevenZip.validate(file.getPath(), "gba");
            assertEquals((long) raw.length, value.get("sizeBytes"));
            assertEquals(hash(raw, "MD5"), value.get("md5"));
            assertEquals(hash(raw, "SHA-1"), value.get("sha1"));
            assertArrayEquals(encoded, Files.readAllBytes(file.toPath()));
        } finally { assertTrue(file.delete()); }
    }

    @Test public void gbaProfileRejectsWrongMemberAndDeclaredWorkBeyond32MiB() throws Exception {
        for (String name : new String[]{"Game.gb", "Game.z64", "../Game.gba"}) {
            File file = File.createTempFile("rshop-gba-reject-", ".7z");
            try {
                Files.write(file.toPath(), archive(name, rom(), 1, true, rom().length, 4096, 1));
                try { OwnedN64SevenZip.validate(file.getPath(), "gba"); fail("Mapped member rejected"); }
                catch (IOException expected) { assertEquals("unsupported_archive", expected.getMessage()); }
            } finally { assertTrue(file.delete()); }
        }
        File file = File.createTempFile("rshop-gba-bound-", ".7z");
        try {
            Files.write(file.toPath(), archive("Game.gba", rom(), 1, true, 32L * 1024 * 1024 + 1, 4096, 1));
            try { OwnedN64SevenZip.validate(file.getPath(), "gba"); fail("Budget rejected before decoding"); }
            catch (IOException expected) { assertEquals("unsupported_archive", expected.getMessage()); }
        } finally { assertTrue(file.delete()); }
    }

    @Test public void mappedGameBoySevenZipReturnsRawMemberNotContainerIdentity() throws Exception {
        byte[] raw = rom();
        raw[0] = 0; // This path must not misapply N64's magic check.
        for (String platform : new String[]{"gb", "gbc"}) {
            String name = "Game." + platform;
            byte[] encoded = archive(name, raw, 1, true, raw.length, 4096, 1);
            File file = File.createTempFile("rshop-gb-identity-", ".7z");
            try {
                Files.write(file.toPath(), encoded);
                java.util.Map<?, ?> value = (java.util.Map<?, ?>) OwnedN64SevenZip.class
                        .getDeclaredMethod("validate", String.class, String.class)
                        .invoke(null, file.getPath(), platform);
                assertEquals(name, value.get("filename"));
                assertEquals(hash(raw, "SHA-1"), value.get("sha1"));
                assertEquals(hash(raw, "MD5"), value.get("md5"));
                assertNotEquals(hash(encoded, "MD5"), value.get("md5"));
                assertArrayEquals(encoded, Files.readAllBytes(file.toPath()));
            } finally { assertTrue(file.delete()); }
        }
    }

    @Test public void gameBoyProfileRejectsWrongNamesAndUnboundedRawSize() throws Exception {
        for (String platform : new String[]{"gb", "gbc", "snes"}) {
            for (String name : new String[]{"Game.z64", "../Game.gb", "Game.gba"}) {
                File file = File.createTempFile("rshop-gb-reject-", ".7z");
                try {
                    Files.write(file.toPath(), archive(name, rom(), 1, true, rom().length, 4096, 1));
                    try {
                        OwnedN64SevenZip.class.getDeclaredMethod("validate", String.class, String.class)
                                .invoke(null, file.getPath(), platform);
                        fail("Wrong mapped member must not identify a Game Boy ROM");
                    } catch (java.lang.reflect.InvocationTargetException error) {
                        assertTrue(error.getCause() instanceof IOException);
                    }
                } finally { assertTrue(file.delete()); }
            }
        }
        File file = File.createTempFile("rshop-gb-bound-", ".7z");
        try {
            Files.write(file.toPath(), archive("Game.gb", rom(), 1, true, 16L * 1024 * 1024 + 1, 4096, 1));
            try {
                OwnedN64SevenZip.class.getDeclaredMethod("validate", String.class, String.class)
                        .invoke(null, file.getPath(), "gb");
                fail("Raw work budget must be checked before decoding");
            } catch (java.lang.reflect.InvocationTargetException error) {
                assertTrue(error.getCause() instanceof IOException);
            }
        } finally { assertTrue(file.delete()); }
    }

    @Test public void validatedArchiveReturnsMemberHashesNotContainerHashes() throws Exception {
        byte[] raw = rom();
        byte[] encoded = archive("Game.z64", raw, 1, true, raw.length, 4096, 1);
        File file = File.createTempFile("rshop-n64-identity-", ".7z");
        try {
            Files.write(file.toPath(), encoded);
            Object result = OwnedN64SevenZip.class.getDeclaredMethod("validate", String.class)
                    .invoke(null, file.getPath());
            assertNotNull("Validated raw member identity is required", result);
            java.util.Map<?, ?> identity = (java.util.Map<?, ?>) result;
            assertEquals("Game.z64", identity.get("filename"));
            assertEquals((long) raw.length, identity.get("sizeBytes"));
            assertEquals(hash(raw, "SHA-1"), identity.get("sha1"));
            assertEquals(hash(raw, "MD5"), identity.get("md5"));
            assertNotEquals(hash(encoded, "SHA-1"), identity.get("sha1"));
            assertArrayEquals(encoded, Files.readAllBytes(file.toPath()));
        } finally { assertTrue(file.delete()); }
    }
    private static String hash(byte[] bytes, String algorithm) throws Exception {
        StringBuilder hex = new StringBuilder();
        for (byte value : java.security.MessageDigest.getInstance(algorithm).digest(bytes))
            hex.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
        return hex.toString();
    }
    private static byte[] rom() {
        byte[] bytes = new byte[8192];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) (i % 251);
        System.arraycopy(new byte[]{(byte) 0x80, 0x37, 0x12, 0x40}, 0, bytes, 0, 4);
        return bytes;
    }
    private static long crc(byte[] bytes) { CRC32 crc = new CRC32(); crc.update(bytes); return crc.getValue(); }
    private static void fixed(ByteArrayOutputStream out, long value, int size) {
        for (int i = 0; i < size; i++) out.write((int) (value >>> (8 * i)) & 255);
    }
    private static void number(ByteArrayOutputStream out, long value) {
        for (int extra = 0; extra < 8; extra++) {
            if (value < (1L << (7 + 7 * extra))) {
                out.write((0xff << (8 - extra)) | (int) (value >>> (8 * extra)));
                fixed(out, value, extra); return;
            }
        }
        out.write(255); fixed(out, value, 8);
    }
    private static byte[] packed(byte[] value, int codec) throws Exception {
        return packed(value, codec, false);
    }
    private static byte[] packed(byte[] value, int codec, boolean endMarker) throws Exception {
        if (codec == 0) return value.clone();
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        LZMA2Options options = new LZMA2Options(); options.setDictSize(4096);
        if (codec == 1) {
            try (LZMAOutputStream stream = new LZMAOutputStream(bytes, options, endMarker)) { stream.write(value); }
        } else {
            try (org.tukaani.xz.FinishableOutputStream stream = options.getOutputStream(new FinishableWrapperOutputStream(bytes))) {
                stream.write(value);
            }
        }
        return bytes.toByteArray();
    }
    private static void streams(ByteArrayOutputStream out, long position, byte[] packed,
                                byte[] raw, int codec, long rawSize, int dictionary) {
        streams(out, position, packed, raw, codec, rawSize, dictionary, false);
    }
    private static void streams(ByteArrayOutputStream out, long position, byte[] packed,
                                byte[] raw, int codec, long rawSize, int dictionary, boolean substreamCrc) {
        out.write(6); number(out, position); number(out, 1);
        out.write(9); number(out, packed.length); out.write(0);
        out.write(7); out.write(11); number(out, 1); out.write(0); number(out, 1);
        if (codec == 0) { out.write(1); out.write(0); }
        else if (codec == 1) {
            out.write(0x23); out.write(3); out.write(1); out.write(1);
            number(out, 5); out.write(0x5d); fixed(out, dictionary, 4);
        } else { out.write(0x21); out.write(0x21); number(out, 1); out.write(dictionary); }
        out.write(12); number(out, rawSize);
        if (!substreamCrc) { out.write(10); out.write(1); fixed(out, crc(raw), 4); }
        out.write(0); out.write(8);
        if (substreamCrc) {
            out.write(13); number(out, 1); out.write(9); // Empty Size array for one stream.
            out.write(10); out.write(1); fixed(out, crc(raw), 4);
        }
        out.write(0); out.write(0);
    }
    private static byte[] archive(String name, byte[] raw, int codec, boolean encoded,
                                  long declared, int dictionary, int count) throws Exception {
        return archive(name, raw, codec, encoded, declared, dictionary, count, false);
    }
    private static byte[] archive(String name, byte[] raw, int codec, boolean encoded,
                                  long declared, int dictionary, int count, boolean substreamCrc) throws Exception {
        return archive(name, raw, codec, encoded, declared, dictionary, count, substreamCrc, false);
    }
    private static byte[] archive(String name, byte[] raw, int codec, boolean encoded,
                                  long declared, int dictionary, int count, boolean substreamCrc,
                                  boolean endMarker) throws Exception {
        byte[] compressed = packed(raw, codec, endMarker);
        ByteArrayOutputStream header = new ByteArrayOutputStream();
        header.write(1); header.write(4);
        streams(header, 0, compressed, raw, codec, declared, dictionary, substreamCrc);
        header.write(5); number(header, count);
        byte[] filename = (name + "\0").getBytes(StandardCharsets.UTF_16LE);
        header.write(0x11); number(header, filename.length + 1); header.write(0); header.write(filename);
        header.write(0x15); number(header, 6); header.write(1); header.write(0); fixed(header, 0x20, 4);
        header.write(0); header.write(0);
        byte[] plain = header.toByteArray(), next = plain, encodedBytes = new byte[0];
        if (encoded) {
            encodedBytes = packed(plain, 1, endMarker);
            ByteArrayOutputStream nextHeader = new ByteArrayOutputStream(); nextHeader.write(0x17);
            streams(nextHeader, compressed.length, encodedBytes, plain, 1, plain.length, 4096);
            next = nextHeader.toByteArray();
        }
        ByteArrayOutputStream start = new ByteArrayOutputStream();
        fixed(start, compressed.length + encodedBytes.length, 8); fixed(start, next.length, 8); fixed(start, crc(next), 4);
        ByteArrayOutputStream file = new ByteArrayOutputStream();
        file.write(new byte[]{0x37,0x7a,(byte)0xbc,(byte)0xaf,0x27,0x1c,0,3});
        fixed(file, crc(start.toByteArray()), 4); file.write(start.toByteArray());
        file.write(compressed); file.write(encodedBytes); file.write(next); return file.toByteArray();
    }
    private static byte[] archive(String name, int codec, boolean encoded) throws Exception {
        return archive(name, rom(), codec, encoded, rom().length, codec == 2 ? 0 : 4096, 1);
    }
    private static void validate(byte[] bytes, boolean zip) throws Exception {
        File file = File.createTempFile("rshop-n64-", zip ? ".zip" : ".7z");
        try {
            Files.write(file.toPath(), bytes);
            if (zip) OwnedGameGearZip.validateN64(file.getPath()); else OwnedN64SevenZip.validate(file.getPath());
            assertArrayEquals(bytes, Files.readAllBytes(file.toPath()));
        } finally { assertTrue(file.delete()); }
    }
    private static void reject(byte[] bytes, boolean zip) throws Exception {
        try { validate(bytes, zip); fail("Invalid N64 archive was accepted"); } catch (IOException expected) { }
    }
    @Test public void copyLzmaAndLzma2WithPlainAndEncodedHeadersPreserveBytes() throws Exception {
        for (int codec = 0; codec < 3; codec++) for (boolean encoded : new boolean[]{false, true}) {
            validate(archive("Game (USA).z64", codec, encoded), false);
        }
    }
    @Test public void singleRomSizeMarkerAndSubstreamCrcMatchRealSevenZipLayout() throws Exception {
        validate(archive("Game.z64", rom(), 1, true, rom().length, 4096, 1, true), false);
        byte[] damaged = archive("Game.z64", rom(), 0, true, rom().length, 0, 1, true);
        damaged[100] ^= 1;
        reject(damaged, false);
    }
    private static long little(byte[] bytes, int start, int size) {
        long value = 0;
        for (int i = 0; i < size; i++) value |= (bytes[start + i] & 255L) << (8 * i);
        return value;
    }
    private static void overwrite(byte[] bytes, int start, long value, int size) {
        for (int i = 0; i < size; i++) bytes[start + i] = (byte) (value >>> (8 * i));
    }
    private static byte[] romVault(byte[] original, char type) {
        int next = 32 + (int) little(original, 12, 8);
        byte[] result = Arrays.copyOf(original, original.length + 32);
        System.arraycopy(original, next, result, next + 32, original.length - next);
        byte[] magic = ("RomVault7Z0" + type).getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(magic, 0, result, next, magic.length);
        overwrite(result, next + 12, little(original, 28, 4), 4);
        overwrite(result, next + 16, next + 32, 8);
        overwrite(result, next + 24, little(original, 20, 8), 8);
        overwrite(result, 12, next, 8); // New relative next-header offset.
        CRC32 start = new CRC32(); start.update(result, 12, 20);
        overwrite(result, 8, start.getValue(), 4);
        return result;
    }
    @Test public void romVaultMetadataMustAgreeExactlyWithValidatedHeader() throws Exception {
        byte[] original = archive("Game.z64", rom(), 1, true, rom().length, 4096, 1, true);
        for (char type : new char[]{'1', '2'}) validate(romVault(original, type), false);
        int marker = 32 + (int) little(original, 12, 8);
        for (int relative : new int[]{0, 12, 16, 24}) {
            byte[] bad = romVault(original, '1'); bad[marker + relative] ^= 1; reject(bad, false);
        }
        reject(romVault(original, '3'), false);
        byte[] bytes = romVault(original, '1');
        reject(Arrays.copyOf(bytes, bytes.length + 1), false);
    }
    @Test public void knownSizeLzmaValidatesWithOrWithoutAnEndMarker() throws Exception {
        for (boolean endMarker : new boolean[]{false, true}) {
            for (boolean encoded : new boolean[]{false, true}) {
                byte[] bytes = archive("Game.z64", rom(), 1, encoded, rom().length,
                        4096, 1, true, endMarker);
                validate(encoded ? romVault(bytes, '1') : bytes, false);
            }
        }
    }
    @Test public void unsafeNamesWrongSignatureAndMultipleFilesCannotBeInstalled() throws Exception {
        for (String name : new String[]{"../Game.z64", "folder/Game.z64", "C:Game.z64", "Game.gg", "Game\n.z64", "Game\0.z64"}) {
            reject(archive(name, 0, false), false);
        }
        byte[] wrong = rom(); wrong[0] = 0;
        reject(archive("Game.z64", wrong, 0, false, wrong.length, 0, 1), false);
        reject(archive("Game.z64", rom(), 0, false, rom().length, 0, 2), false);
    }
    @Test public void dictionaryAndOutputBudgetsRejectBeforeDecompression() throws Exception {
        reject(archive("Game.z64", rom(), 1, true, OwnedN64SevenZip.ROM_LIMIT + 1, 4096, 1), false);
        reject(archive("Game.z64", rom(), 1, false, rom().length, Integer.MAX_VALUE, 1), false);
        reject(archive("Game.z64", rom(), 2, false, rom().length, 40, 1), false);
    }
    @Test public void crcTruncationAndTrailingDataCannotPass() throws Exception {
        byte[] original = archive("Game.z64", 0, true);
        byte[] corrupt = original.clone(); corrupt[100] ^= 1; reject(corrupt, false);
        corrupt = original.clone(); corrupt[15] ^= 1; reject(corrupt, false);
        corrupt = original.clone(); corrupt[corrupt.length - 2] ^= 1; reject(corrupt, false);
        reject(Arrays.copyOf(original, original.length - 1), false);
        reject(Arrays.copyOf(original, original.length + 1), false);
    }
    private static byte[] zip(String... names) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            for (String name : names) { zip.putNextEntry(new ZipEntry(name)); zip.write(rom()); zip.closeEntry(); }
        }
        return bytes.toByteArray();
    }
    @Test public void n64ZipReusesStrictSingleMemberLayout() throws Exception {
        validate(zip("Game.n64"), true);
        reject(zip("Game.n64", "Other.z64"), true);
        reject(zip("../Game.v64"), true);
        reject(zip("Game\n.z64"), true);
        byte[] bytes = zip("Game.z64"); bytes[60] ^= 1; reject(bytes, true);
    }
}
