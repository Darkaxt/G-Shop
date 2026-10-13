package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class N3dsSaveIdentityTest {
    private fun ncch(): ByteArray = ByteArray(512).also { bytes ->
        "NCCH".toByteArray().copyInto(bytes, 0x100)
        byteArrayOf(0, 0x57, 0x4c, 0, 0, 0, 4, 0).copyInto(bytes, 0x118)
        bytes[0x18f] = 4
    }
    private fun read(bytes: ByteArray): String = N3dsSaveIdentity.programId(bytes.size.toLong()) { offset, count ->
        bytes.copyOfRange(offset.toInt(), offset.toInt() + count)
    }
    @Test fun headerIdentityIgnoresDisplayNamesAndFollowsPartitionZero() {
        assertEquals("00040000004c5700", read(ncch()))
        val cci = ByteArray(1024)
        "NCSD".toByteArray().copyInto(cci, 0x100)
        cci[0x120] = 1; cci[0x124] = 1
        ncch().copyInto(cci, 512)
        assertEquals("00040000004c5700", read(cci))
        cci[0x120] = 3
        assertThrows(IllegalArgumentException::class.java) { read(cci) }
    }
    @Test fun unsupportedCompressedEncryptedSystemAndTruncatedFilesStayUnresolved() {
        for (bytes in listOf(ByteArray(512), ncch().also { it[0x18f] = 0 },
            ncch().also { it[0x11d] = 1 }, ncch().copyOf(511))) {
            assertThrows(IllegalArgumentException::class.java) { read(bytes) }
        }
    }
    @Test fun onlyOneTitleDataGroupIsSelectedWithItsFormatMetadata() {
        val config = StandardSaveRoots.azaharConfiguration("/storage/emulated/0/Azahar", "00040000004c5700")
        assertEquals(listOf("004c5700/data/00000001"), config.folders)
        assertEquals(config.files, config.required)
        assertTrue(config.acceptsFile("004c5700/data/00000001/main.bin"))
        assertFalse(config.acceptsFile("00934200/data/00000001/hime00.sav"))
        assertFalse(config.acceptsFile("004c5700/content/game.app"))
        assertFalse(config.acceptsFile("004c5700/data/00000001/bios.bin"))
        assertNull(config.resourceId)
    }
}
