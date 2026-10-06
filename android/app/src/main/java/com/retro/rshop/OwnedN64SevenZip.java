package com.retro.rshop;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.charset.CodingErrorAction;
import java.util.Arrays;
import java.util.Locale;
import java.util.zip.CRC32;
import org.tukaani.xz.LZMAInputStream;
import org.tukaani.xz.LZMA2InputStream;

/** Narrow read-only validator, not an extraction engine. Structure follows
 * https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt. Counts/ranges are
 * checked before allocations; XZ only decodes an explicitly bounded stream. */
final class OwnedN64SevenZip {
    static final int HEADER_LIMIT = 65536;
    static final long ROM_LIMIT = 128L * 1024 * 1024; // Work budget, not hardware capacity.
    private static final int DICTIONARY_LIMIT = 32 * 1024 * 1024;
    private static final byte[] SIGNATURE = {0x37, 0x7a, (byte) 0xbc, (byte) 0xaf, 0x27, 0x1c};

    static java.util.Map<String, Object> validate(String descriptorPath) throws IOException {
        try (RandomAccessFile file = new RandomAccessFile(descriptorPath, "r")) {
            long length = file.length();
            require(length >= 32 && length <= ROM_LIMIT + 3L * HEADER_LIMIT);
            byte[] signature = read(file, 0, 32);
            require(Arrays.equals(SIGNATURE, Arrays.copyOf(signature, 6)) && signature[6] == 0 &&
                    (signature[7] & 255) <= 4 && crc(signature, 12, 20) == le32(signature, 8));
            long offset = le64(signature, 12), size = le64(signature, 20);
            require(offset <= length - 32 && size > 0 && size <= HEADER_LIMIT &&
                    size == length - 32 - offset);
            long nextStart = 32 + offset;
            byte[] header = read(file, nextStart, (int) size);
            require(crc(header, 0, header.length) == le32(signature, 28));
            long romEnd = nextStart;
            boolean romVault = false;
            if ((header[0] & 255) == 0x17) {
                Reader encoded = new Reader(header); encoded.expect(0x17);
                Stream stream = streams(encoded, HEADER_LIMIT);
                encoded.end();
                require(stream.position <= offset && stream.packed <= offset - stream.position);
                long gap = offset - stream.position - stream.packed;
                if (gap != 0) {
                    // RomVault's structured 7z marker, not arbitrary padding:
                    // https://github.com/RomVault/RVWorld/blob/master/Compress/StructuredZip/Structured7Zip.cs
                    require(gap == 32);
                    byte[] marker = read(file, nextStart - 32, 32);
                    require(Arrays.equals("RomVault7Z0".getBytes(StandardCharsets.US_ASCII),
                            Arrays.copyOf(marker, 11)) && (marker[11] == '1' || marker[11] == '2') &&
                            le32(marker, 12) == le32(signature, 28) &&
                            le64(marker, 16) == nextStart && le64(marker, 24) == size);
                    romVault = true;
                }
                byte[] decoded = new byte[(int) stream.unpacked];
                decode(file, stream, decoded, false, null);
                header = decoded;
                romEnd = 32 + stream.position;
            }
            Reader plain = new Reader(header); plain.expect(1); plain.expect(4);
            Stream rom = streams(plain, ROM_LIMIT);
            require(!romVault || rom.method == 1);
            require(rom.position == 0 && rom.packed == romEnd - 32 && rom.unpacked >= 4);
            plain.expect(5); require(plain.number() == 1);
            String name = files(plain);
            require(name != null && safeName(name));
            plain.expect(0); plain.end();
            OwnedArchiveIdentity identity = new OwnedArchiveIdentity();
            decode(file, rom, null, true, identity);
            return identity.member(name);
        }
    }

    private static final class Stream {
        long position, packed, unpacked;
        Long packedCrc, crc;
        int method, dictionary;
        byte properties;
    }

    private static Stream streams(Reader r, long limit) throws IOException {
        Stream s = new Stream();
        r.expect(6); s.position = r.number(); require(r.number() == 1);
        r.expect(9); s.packed = r.number();
        require(s.packed > 0 && s.packed <= ROM_LIMIT + HEADER_LIMIT);
        if (r.peek() == 10) { r.byteValue(); s.packedCrc = digest(r); }
        r.expect(0); r.expect(7); r.expect(11);
        require(r.number() == 1); r.expect(0); // One inline folder.
        require(r.number() == 1); // One coder; no filter chains or alternative methods.
        int flags = r.byteValue(), idSize = flags & 15;
        require((flags & 0xc0) == 0 && idSize >= 1 && idSize <= 4);
        byte[] id = r.bytes(idSize);
        if ((flags & 0x10) != 0) require(r.number() == 1 && r.number() == 1);
        byte[] props = (flags & 0x20) != 0 ? r.bytes(r.bounded(5)) : new byte[0];
        if (Arrays.equals(id, new byte[]{0})) {
            require(props.length == 0); s.method = 0;
        } else if (Arrays.equals(id, new byte[]{3, 1, 1})) {
            require(props.length == 5); s.method = 1; s.properties = props[0];
            long dictionary = le32(props, 1);
            require(dictionary <= DICTIONARY_LIMIT); s.dictionary = (int) dictionary;
            require(LZMAInputStream.getMemoryUsage(s.dictionary, s.properties) <= 40 * 1024);
        } else if (Arrays.equals(id, new byte[]{0x21})) {
            require(props.length == 1 && (props[0] & 255) <= 40); s.method = 2;
            int p = props[0] & 255;
            long dictionary = p == 40 ? 0xffffffffL : ((2L | (p & 1)) << (p / 2 + 11));
            require(dictionary <= DICTIONARY_LIMIT); s.dictionary = (int) dictionary;
            require(LZMA2InputStream.getMemoryUsage(s.dictionary) <= 40 * 1024);
        } else throw invalid(); // Includes encrypted and unsupported codecs.
        r.expect(12); s.unpacked = r.number(); require(s.unpacked > 0 && s.unpacked <= limit);
        if (r.peek() == 10) { r.byteValue(); s.crc = digest(r); }
        r.expect(0);
        if (r.peek() == 8) {
            r.byteValue();
            if (r.peek() == 13) { r.byteValue(); require(r.number() == 1); }
            // With one stream there is no substream-size array.
            // 7-Zip may still emit the Size property marker with an empty array.
            if (r.peek() == 9) r.byteValue();
            if (r.peek() == 10) {
                r.byteValue(); require(s.crc == null); s.crc = digest(r);
            }
            r.expect(0);
        }
        r.expect(0); require(s.crc != null);
        if (s.method == 0) require(s.packed == s.unpacked);
        return s;
    }

    private static Long digest(Reader r) throws IOException {
        int defined = r.byteValue();
        require(defined == 0 || defined == 1);
        if (defined == 0) require(r.byteValue() == 0x80);
        return r.fixed32();
    }

    private static String files(Reader r) throws IOException {
        String name = null;
        int seen = 0;
        while (r.peek() != 0) {
            int kind = r.byteValue(); require(kind >= 0x0e && kind <= 0x19);
            int mask = 1 << kind; require((seen & mask) == 0); seen |= mask;
            Reader property = new Reader(r.bytes(r.bounded(HEADER_LIMIT)));
            switch (kind) {
                case 0x11:
                    property.expect(0); byte[] value = property.bytes(property.remaining());
                    require(value.length >= 4 && value.length <= 2050 && value.length % 2 == 0 &&
                            value[value.length - 1] == 0 && value[value.length - 2] == 0);
                    name = StandardCharsets.UTF_16LE.newDecoder()
                            .onMalformedInput(CodingErrorAction.REPORT)
                            .onUnmappableCharacter(CodingErrorAction.REPORT)
                            .decode(ByteBuffer.wrap(value, 0, value.length - 2)).toString();
                    break;
                case 0x0e: property.expect(0); break; // No empty stream/directory.
                case 0x12: case 0x13: case 0x14: case 0x15:
                    int defined = property.byteValue(); require(defined == 0 || defined == 1);
                    if (defined == 0) {
                        int bits = property.byteValue(); require(bits == 0 || bits == 0x80);
                        defined = bits == 0 ? 0 : 1;
                    }
                    property.expect(0); // External properties not supported.
                    if (defined != 0) {
                        if (kind == 0x15) {
                            long attrs = property.fixed32(); int type = (int) ((attrs >>> 16) & 0xf000);
                            require((attrs & 0x10) == 0 && (type == 0 || type == 0x8000));
                        } else property.bytes(8);
                    }
                    break;
                case 0x19: while (property.remaining() > 0) property.expect(0); break;
                default: throw invalid(); // Anti files, external/start-position and unknown data.
            }
            property.end();
        }
        r.expect(0); return name;
    }

    static boolean safeName(String name) {
        String lower = name.toLowerCase(Locale.ROOT);
        return (lower.endsWith(".n64") || lower.endsWith(".z64") || lower.endsWith(".v64")) &&
                !name.startsWith(".") && name.chars().noneMatch(c ->
                        c < 32 || c == 127 || c == '/' || c == '\\' || c == ':');
    }

    static boolean n64Magic(byte[] value) {
        long magic = le32(value, 0);
        return magic == 0x40123780L || magic == 0x12408037L || magic == 0x80371240L;
    }

    private static void decode(RandomAccessFile file, Stream s, byte[] header, boolean rom,
                               OwnedArchiveIdentity identity) throws IOException {
        require(s.position <= file.length() - 32 && s.packed <= file.length() - 32 - s.position);
        file.seek(32 + s.position);
        PackedInput bounded = new PackedInput(file, s.packed);
        BufferedInputStream input = new BufferedInputStream(bounded, HEADER_LIMIT);
        InputStream decoded = s.method == 0 ? input : s.method == 1
                ? new LZMAInputStream(input, s.unpacked, s.properties, s.dictionary)
                : new LZMA2InputStream(input, s.dictionary);
        if (decoded instanceof LZMAInputStream) {
            // XZ 1.12 verifies/consumes EOS when present alongside a known size.
            // Exact output length, CRC and complete packed consumption still apply.
            ((LZMAInputStream) decoded).enableRelaxedEndCondition();
        }
        CRC32 crc = new CRC32(); byte[] buffer = new byte[HEADER_LIMIT], magic = new byte[4];
        long count = 0;
        try (InputStream stream = decoded) {
            for (int n; (n = stream.read(buffer)) != -1;) {
                require(n > 0 && n <= s.unpacked - count);
                for (int i = 0; i < n && count + i < 4; i++) magic[(int) count + i] = buffer[i];
                if (header != null) System.arraycopy(buffer, 0, header, (int) count, n);
                if (identity != null) identity.add(buffer, n);
                crc.update(buffer, 0, n); count += n;
            }
            require(count == s.unpacked && crc.getValue() == s.crc && input.available() == 0 &&
                    bounded.remaining == 0 && (s.packedCrc == null || bounded.crc.getValue() == s.packedCrc));
            require(!rom || n64Magic(magic));
        }
    }

    private static final class PackedInput extends InputStream {
        final RandomAccessFile file; long remaining; final CRC32 crc = new CRC32();
        PackedInput(RandomAccessFile file, long size) { this.file = file; remaining = size; }
        @Override public int read() throws IOException {
            if (remaining == 0) return -1;
            int value = file.read(); require(value >= 0); remaining--; crc.update(value); return value;
        }
        @Override public int read(byte[] b, int off, int len) throws IOException {
            if (len == 0) return 0; if (remaining == 0) return -1;
            int n = file.read(b, off, (int) Math.min(remaining, len)); require(n > 0);
            remaining -= n; crc.update(b, off, n); return n;
        }
        @Override public int available() { return (int) Math.min(remaining, Integer.MAX_VALUE); }
        // Stream close must not close the caller's pinned RandomAccessFile.
    }

    private static final class Reader {
        final byte[] data; int pos;
        Reader(byte[] data) { this.data = data; }
        int remaining() { return data.length - pos; }
        int peek() throws IOException { require(remaining() > 0); return data[pos] & 255; }
        int byteValue() throws IOException { int result = peek(); pos++; return result; }
        void expect(int value) throws IOException { require(byteValue() == value); }
        byte[] bytes(int count) throws IOException {
            require(count >= 0 && count <= remaining());
            byte[] result = Arrays.copyOfRange(data, pos, pos + count); pos += count; return result;
        }
        long number() throws IOException {
            int first = byteValue(), mask = 0x80; long value = 0;
            for (int i = 0; i < 8; i++, mask >>>= 1) {
                if ((first & mask) == 0) return value | ((long) (first & (mask - 1)) << (8 * i));
                value |= (long) byteValue() << (8 * i);
            }
            require(value >= 0); return value;
        }
        int bounded(int maximum) throws IOException {
            long result = number(); require(result <= maximum && result <= remaining()); return (int) result;
        }
        long fixed32() throws IOException { return le32(bytes(4), 0); }
        void end() throws IOException { require(remaining() == 0); }
    }

    private static byte[] read(RandomAccessFile file, long offset, int count) throws IOException {
        require(count >= 0 && count <= HEADER_LIMIT && offset >= 0 && offset <= file.length() &&
                count <= file.length() - offset);
        byte[] bytes = new byte[count]; file.seek(offset); file.readFully(bytes); return bytes;
    }
    private static long le32(byte[] b, int p) {
        return (b[p] & 255L) | ((b[p + 1] & 255L) << 8) | ((b[p + 2] & 255L) << 16) | ((b[p + 3] & 255L) << 24);
    }
    private static long le64(byte[] b, int p) throws IOException {
        require((b[p + 7] & 128) == 0); return le32(b, p) | (le32(b, p + 4) << 32);
    }
    private static long crc(byte[] b, int p, int n) { CRC32 crc = new CRC32(); crc.update(b, p, n); return crc.getValue(); }
    private static void require(boolean ok) throws IOException { if (!ok) throw invalid(); }
    private static IOException invalid() { return new IOException("unsupported_archive"); }
}
