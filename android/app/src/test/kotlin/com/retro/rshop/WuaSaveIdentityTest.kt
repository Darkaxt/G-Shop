package com.retro.rshop

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class WuaSaveIdentityTest {
    @Test fun realLibrarySampleUsesTheSameBoundedReaderWhenProvided() {
        val path = System.getenv("RSHOP_WUA_SAMPLE")
        org.junit.Assume.assumeNotNull(path)
        java.io.RandomAccessFile(path!!, "r").use { source ->
            var bytesRead = 0
            val title = WuaSaveIdentity.titleId(source.length()) { offset, count ->
                bytesRead += count
                source.seek(offset); ByteArray(count).also(source::readFully)
            }
            assertTrue(title.matches(Regex("00050000[0-9a-f]{8}")))
            assertTrue(bytesRead < 65536)
        }
    }
    private fun fixture(titles: List<String> = listOf("0005000010102000_v0", "0005000e10102000_v64")): ByteArray {
        val bytes = ByteArray(1024); val out = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        var nameOffset = 0
        titles.forEachIndexed { index, name ->
            bytes[64 + nameOffset] = name.length.toByte(); name.toByteArray().copyInto(bytes, 65 + nameOffset)
            val row = 256 + (index + 1) * 16
            out.putInt(row, nameOffset); out.putInt(row + 4, titles.size + 1 + index); out.putInt(row + 8, 1)
            out.putInt(256 + (titles.size + 1 + index) * 16, Int.MIN_VALUE)
            nameOffset += name.length + 1
        }
        out.putInt(256, 0x7fffffff); out.putInt(260, 1); out.putInt(264, titles.size)
        val footer = bytes.size - 144
        out.putLong(footer + 32, 64); out.putLong(footer + 40, nameOffset.toLong())
        out.putLong(footer + 48, 256); out.putLong(footer + 56, (1 + titles.size * 2) * 16L)
        out.putLong(footer + 128, bytes.size.toLong()); out.putInt(footer + 136, 0x61bf3a01); out.putInt(footer + 140, 0x169f52d6)
        return bytes
    }
    private fun read(bytes: ByteArray): String = WuaSaveIdentity.titleId(bytes.size.toLong()) { offset, count ->
        require(count <= 144); bytes.copyOfRange(offset.toInt(), offset.toInt() + count)
    }
    @Test fun baseTitleComesFromBoundedRootIndexNotFilenameOrDlc() {
        assertEquals("0005000010102000", read(fixture()))
        assertThrows(IllegalArgumentException::class.java) { read(fixture(listOf("0005000e10102000_v64"))) }
        assertThrows(IllegalArgumentException::class.java) { read(fixture(listOf("0005000010102000_v0", "0005000010103000_v0"))) }
    }
    @Test fun truncatedCorruptOverlappingAndOversizedIndexesAreRejected() {
        for (mutate in listOf<(ByteArray) -> Unit>(
            { it[it.size - 1] = 0 },
            { ByteBuffer.wrap(it).putLong(it.size - 144 + 128, Long.MAX_VALUE) },
            { ByteBuffer.wrap(it).putLong(it.size - 144 + 48, 64) },
            { ByteBuffer.wrap(it).putInt(264, Int.MAX_VALUE) },
            { ByteBuffer.wrap(it).putInt(260, Int.MAX_VALUE) },
            { ByteBuffer.wrap(it).putInt(272, Int.MAX_VALUE - 1) }
        )) assertThrows(IllegalArgumentException::class.java) { read(fixture().also(mutate)) }
        assertThrows(IllegalArgumentException::class.java) { read(fixture().copyOf(1023)) }
    }
    @Test fun cemuProfileSelectsOneTitleAndAccountWithoutSystemData() {
        val config = StandardSaveRoots.cemuConfiguration("/storage/emulated/0/Cemu/mlc01", 0x80000001, "0005000010102000")
        assertTrue(config.acceptsFile("00050000/10102000/user/80000001/save.bin"))
        assertTrue(config.acceptsFile("00050000/10102000/meta/meta.xml"))
        assertFalse(config.acceptsFile("00050000/10102000/user/80000002/save.bin"))
        assertFalse(config.acceptsFile("00050000/10103000/user/80000001/save.dat"))
        assertFalse(config.acceptsFile("system/act/80000001/account.dat"))
        assertNull(config.logicalRomName)
    }
}
