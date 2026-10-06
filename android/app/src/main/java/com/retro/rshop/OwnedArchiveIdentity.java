package com.retro.rshop;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.CRC32;

/** Streamed identifiers for the two existing bounded archive validators. */
final class OwnedArchiveIdentity {
    private final MessageDigest md5 = digest("MD5"), sha1 = digest("SHA-1"), sha256 = digest("SHA-256");
    private final CRC32 crc = new CRC32();
    private long size;
    void add(byte[] bytes, int count) {
        md5.update(bytes, 0, count); sha1.update(bytes, 0, count); sha256.update(bytes, 0, count);
        crc.update(bytes, 0, count); size += count;
    }
    Map<String, Object> member(String name) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("kind", "rawRom"); result.put("filename", name); result.put("sizeBytes", size);
        result.put("crc32", String.format(java.util.Locale.ROOT, "%08x", crc.getValue()));
        result.put("md5", hex(md5.digest())); result.put("sha1", hex(sha1.digest()));
        return result;
    }
    static Map<String, Object> container(String path) throws IOException {
        OwnedArchiveIdentity hash = new OwnedArchiveIdentity();
        try (RandomAccessFile file = new RandomAccessFile(path, "r")) {
            long size = file.length();
            if (size <= 0 || size > OwnedN64SevenZip.ROM_LIMIT + 3L * OwnedN64SevenZip.HEADER_LIMIT)
                throw new IOException("unsupported_archive");
            byte[] buffer = new byte[65536];
            for (int count; (count = file.read(buffer)) != -1;) {
                if (count <= 0 || hash.size + count > size) throw new IOException("changed");
                hash.add(buffer, count);
            }
            if (hash.size != size || file.length() != size) throw new IOException("changed");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("sizeBytes", hash.size);
        result.put("md5", hex(hash.md5.digest())); result.put("sha1", hex(hash.sha1.digest()));
        result.put("sha256", hex(hash.sha256.digest()));
        return result;
    }
    private static MessageDigest digest(String name) {
        try { return MessageDigest.getInstance(name); }
        catch (NoSuchAlgorithmException error) { throw new IllegalStateException(error); }
    }
    private static String hex(byte[] bytes) {
        char[] value = new char[bytes.length * 2];
        char[] alphabet = "0123456789abcdef".toCharArray();
        for (int i = 0; i < bytes.length; i++) {
            value[i * 2] = alphabet[(bytes[i] & 255) >>> 4]; value[i * 2 + 1] = alphabet[bytes[i] & 15];
        }
        return new String(value);
    }
}
