package com.retro.rshop;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.util.Arrays;
import java.util.Locale;
import java.util.zip.CRC32;
import java.util.zip.DataFormatException;
import java.util.zip.Inflater;

/** Validates one explicitly mapped Sega cartridge or N64 ZIP member without
 * extraction or whole-ROM buffers.
 * Production callers pass only their already-pinned /proc/self/fd descriptor.
 * ZIP record layout: PKWARE APPNOTE 6.3.10, sections 4.3.7-4.3.16.
 */
final class OwnedGameGearZip {
    // Explicit work budget, not a claim about a console's physical ROM maximum.
    static final long MAX_MEMBER_BYTES = 16L * 1024 * 1024;
    private static final int BUFFER = 65536;

    static java.util.Map<String, Object> validate(String descriptorPath) throws IOException {
        return validate(descriptorPath, "gamegear");
    }

    static java.util.Map<String, Object> validateN64(String descriptorPath) throws IOException {
        return validate(descriptorPath, "n64");
    }

    static java.util.Map<String, Object> validate(String descriptorPath, String platform) throws IOException {
        String extension;
        switch (platform) {
            case "gamegear": extension = ".gg"; break;
            case "megadrive": extension = ".md"; break;
            case "mastersystem": extension = ".sms"; break;
            case "sg1000": extension = ".sg"; break;
            case "n64": extension = null; break;
            case "nds": extension = ".nds"; break;
            default: throw invalid();
        }
        boolean n64 = "n64".equals(platform);
        long limit = "nds".equals(platform) ? OwnedN64SevenZip.DS_ROM_LIMIT :
                n64 ? OwnedN64SevenZip.ROM_LIMIT : MAX_MEMBER_BYTES;
        try (RandomAccessFile file = new RandomAccessFile(descriptorPath, "r")) {
            long length = file.length();
            require(length >= 98 && length <= limit + 3L * BUFFER);
            byte[] tail = read(file, Math.max(0, length - BUFFER - 22),
                    (int) Math.min(length, BUFFER + 22L));
            int end = -1;
            for (int i = tail.length - 22; i >= 0; i--) {
                if (u32(tail, i) == 0x06054b50L && i + 22 + u16(tail, i + 20) == tail.length) {
                    end = i; break;
                }
            }
            require(end >= 0);
            require(u16(tail, end + 4) == 0 && u16(tail, end + 6) == 0 &&
                    u16(tail, end + 8) == 1 && u16(tail, end + 10) == 1);
            long centralSize = u32(tail, end + 12), centralOffset = u32(tail, end + 16);
            require(centralSize >= 46 && centralSize <= BUFFER &&
                    centralOffset + centralSize == length - tail.length + end);
            byte[] central = read(file, centralOffset, (int) centralSize);
            require(u32(central, 0) == 0x02014b50L && u16(central, 6) <= 20 &&
                    u16(central, 34) == 0 && u32(central, 42) == 0);
            int flags = u16(central, 8), method = u16(central, 10);
            require((flags & ~0x080e) == 0 && (method == 0 || method == 8) &&
                    (method != 0 || (flags & 6) == 0));
            long crc = u32(central, 16), compressed = u32(central, 20), raw = u32(central, 24);
            require(raw >= (n64 ? 4 : 1) && raw <= limit && compressed > 0 && compressed <= limit);
            int nameLength = u16(central, 28), extraLength = u16(central, 30), commentLength = u16(central, 32);
            require(nameLength > 3 && nameLength <= 1024 &&
                    46 + nameLength + extraLength + commentLength == central.length);
            int unixType = (int) ((u32(central, 38) >>> 16) & 0xf000);
            require((u32(central, 38) & 0x10) == 0 && (unixType == 0 || unixType == 0x8000));
            byte[] name = Arrays.copyOfRange(central, 46, 46 + nameLength);
            String decoded;
            try {
                decoded = Charset.forName((flags & 0x800) != 0 ? "UTF-8" : "Cp437").newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(name)).toString();
            } catch (CharacterCodingException error) { throw invalid(); }
            require((n64 ? OwnedN64SevenZip.safeName(decoded) : decoded.toLowerCase(Locale.ROOT).endsWith(extension)) &&
                    !decoded.startsWith(".") && decoded.chars().noneMatch(c ->
                            c < 32 || c == 127 || c == '/' || c == '\\' || c == ':'));
            extras(central, 46 + nameLength, extraLength);
            byte[] local = read(file, 0, 30);
            require(u32(local, 0) == 0x04034b50L && u16(local, 4) == u16(central, 6) &&
                    u16(local, 6) == flags && u16(local, 8) == method &&
                    u32(local, 10) == u32(central, 12) && u16(local, 26) == nameLength);
            int localExtra = u16(local, 28);
            require(localExtra <= BUFFER);
            byte[] localFields = read(file, 30, nameLength + localExtra);
            require(Arrays.equals(name, Arrays.copyOfRange(localFields, 0, nameLength)));
            extras(localFields, nameLength, localExtra);
            boolean descriptor = (flags & 8) != 0;
            require(descriptor
                    ? u32(local, 14) == 0 && u32(local, 18) == 0 && u32(local, 22) == 0
                    : u32(local, 14) == crc && u32(local, 18) == compressed && u32(local, 22) == raw);
            long dataStart = 30L + nameLength + localExtra, dataEnd = dataStart + compressed;
            if (descriptor) {
                long size = centralOffset - dataEnd;
                require(size == 12 || size == 16);
                byte[] value = read(file, dataEnd, (int) size);
                int start = size == 16 ? 4 : 0;
                require((start == 0 || u32(value, 0) == 0x08074b50L) &&
                        u32(value, start) == crc && u32(value, start + 4) == compressed && u32(value, start + 8) == raw);
            } else require(dataEnd == centralOffset);
            // The exact single member covers all bytes before the central record.
            // No hidden local entries, SFX prefix, ZIP64 records or trailing data.
            CRC32 actual = new CRC32();
            OwnedArchiveIdentity identity = new OwnedArchiveIdentity();
            byte[] input = new byte[BUFFER], output = new byte[BUFFER], magic = new byte[4];
            file.seek(dataStart);
            long remaining = compressed, produced = 0;
            Inflater inflater = method == 8 ? new Inflater(true) : null;
            try {
                while (remaining > 0) {
                    int count = (int) Math.min(remaining, BUFFER);
                    file.readFully(input, 0, count); remaining -= count;
                    if (inflater == null) {
                        if (n64) prefix(input, count, produced, magic);
                        produced += count; actual.update(input, 0, count);
                        identity.add(input, count);
                    } else {
                        require(!inflater.finished());
                        inflater.setInput(input, 0, count);
                        while (!inflater.needsInput() && !inflater.finished()) {
                            int inflated = inflater.inflate(output);
                            require(inflated > 0 || inflater.finished());
                            if (n64) prefix(output, inflated, produced, magic);
                            produced += inflated;
                            require(produced <= raw);
                            actual.update(output, 0, inflated);
                            identity.add(output, inflated);
                        }
                    }
                    require(produced <= raw);
                }
                require(inflater == null || (inflater.finished() && inflater.getRemaining() == 0));
                require(produced == raw && actual.getValue() == crc);
                require(!n64 || OwnedN64SevenZip.n64Magic(magic));
            } catch (DataFormatException error) { throw invalid(); }
            finally { if (inflater != null) inflater.end(); }
            return identity.member(decoded);
        }
    }

    private static void prefix(byte[] bytes, int count, long produced, byte[] magic) {
        for (int i = 0; i < count && produced + i < 4; i++) magic[(int) produced + i] = bytes[i];
    }

    private static void extras(byte[] bytes, int offset, int size) throws IOException {
        int end = offset + size;
        while (offset < end) {
            require(offset + 4 <= end);
            int type = u16(bytes, offset), count = u16(bytes, offset + 2);
            // ZIP64, AES and Unicode alternate-name overrides are not this route.
            require(type != 1 && type != 0x9901 && type != 0x7075 && offset + 4 + count <= end);
            offset += 4 + count;
        }
    }
    private static byte[] read(RandomAccessFile file, long offset, int count) throws IOException {
        require(offset >= 0 && count >= 0 && count <= BUFFER + 1024 && offset + count <= file.length());
        byte[] value = new byte[count]; file.seek(offset); file.readFully(value); return value;
    }
    private static int u16(byte[] value, int offset) {
        return (value[offset] & 255) | ((value[offset + 1] & 255) << 8);
    }
    private static long u32(byte[] value, int offset) {
        return Integer.toUnsignedLong(u16(value, offset) | (u16(value, offset + 2) << 16));
    }
    private static void require(boolean valid) throws IOException { if (!valid) throw invalid(); }
    private static IOException invalid() { return new IOException("unsupported_archive"); }
}
