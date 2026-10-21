package org.emunix.unipatcher.patcher

import org.emunix.unipatcher.helpers.ResourceProvider
import org.emunix.unipatcher.utils.Crc16
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.InterruptedIOException

/** Synthetic bytes and the upstream GPL test corpus, never copyrighted ROMs. */
class PatchEngineTest {
    @get:Rule val folder = TemporaryFolder()
    private val resources = object : ResourceProvider {
        override val tempDir get() = folder.root
        override fun getString(resId: Int) = "patch_error_$resId"
        override fun getAsset(fileName: String) = error("Unexpected repair asset")
    }
    private fun check(format: String, patch: ByteArray, base: ByteArray, expected: ByteArray) {
        val original = folder.newFile().apply { writeBytes(base) }
        val resource = folder.newFile().apply { writeBytes(patch) }
        val output = File(folder.root, "result-${folder.root.list()!!.size}")
        GShopPatchEngine.apply(format, resource, original, output, resources, emptyList())
        assertArrayEquals(expected, output.readBytes())
        assertArrayEquals(base, original.readBytes())
        assertArrayEquals(patch, resource.readBytes())
    }
    private fun fixture(path: String) = javaClass.getResourceAsStream(path)!!.use { it.readBytes() }
    private fun bytes(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private fun le(value: Long, size: Int = 4) = ByteArray(size) { (value shr (it * 8)).toByte() }

    @Test fun upstreamIpsAndIps32Corpus() {
        for (stem in listOf("min", "extend", "rle")) {
            check("ips", fixture("/ips/${stem}_ips.ips"), fixture("/ips/${stem}_ips.bin"),
                fixture("/ips/${stem}_ips_modified.bin"))
            check("ips32", fixture("/ips/${stem}_ips32.ips"), fixture("/ips/${stem}_ips32.bin"),
                fixture("/ips/${stem}_ips32_mod.bin"))
        }
        check("ips", fixture("/ips/truncate.ips"), fixture("/ips/truncate.bin"),
            fixture("/ips/truncate_modified.bin"))
    }
    @Test fun upstreamUpsAndBpsCorpus() {
        check("ups", fixture("/ups/readUpsCrc.ups"), fixture("/ups/readUpsCrc.bin"),
            fixture("/ups/readUpsCrc_m.bin"))
        check("bps", fixture("/bps/1.bps"), fixture("/bps/1.bin"), fixture("/bps/1m.bin"))
    }
    @Test fun gbaApsChecksBothBlockCrcs() {
        val base = ByteArray(65536) { (it % 251).toByte() }
        val expected = base.copyOf().apply { this[27] = 42 }
        val xor = ByteArray(base.size) { (base[it].toInt() xor expected[it].toInt()).toByte() }
        val patch = "APS1".toByteArray() + le(base.size.toLong()) + le(expected.size.toLong()) +
            le(0) + le(Crc16().calculate(base).toLong(), 2) +
            le(Crc16().calculate(expected).toLong(), 2) + xor
        check("aps", patch, base, expected)
    }
    @Test fun n64ApsUsesDeclaredCartridgeIdentity() {
        val base = ByteArray(128).apply {
            this[0] = 0x80.toByte(); this[0x3c] = 'G'.code.toByte()
            this[0x3d] = 'E'.code.toByte(); this[0x3e] = 'U'.code.toByte()
        }
        val expected = base.copyOf().apply { this[90] = 12 }
        val patch = "APS10".toByteArray() + bytes(1, 0) + ByteArray(50) +
            bytes(1, 'G'.code, 'E'.code, 'U'.code) + base.copyOfRange(0x10, 0x18) +
            ByteArray(5) + le(128) + le(90) + bytes(1, 12)
        check("aps", patch, base, expected)
        val wrong = base.copyOf().apply { this[0x3e] = 'J'.code.toByte() }
        assertThrows(Exception::class.java) { check("aps", patch, wrong, expected) }
    }
    @Test fun ppfAndDpsLiteralRecords() {
        val base = bytes(1, 2, 3, 4)
        val expected = bytes(1, 2, 9, 4)
        val ppf = ByteArray(56).apply { "PPF10".toByteArray().copyInto(this) } +
            le(2) + bytes(1, 9)
        check("ppf", ppf, base, expected)
        val dps = ByteArray(198).apply { this[193] = 1; le(4).copyInto(this, 194) } +
            bytes(1) + le(0) + le(4) + expected
        check("dps", dps, base, expected)
    }
    @Test fun corruptChecksummedPatchesAndWrongInputsAreRejected() {
        for ((format, patchPath, basePath) in listOf(
            Triple("ups", "/ups/readUpsCrc.ups", "/ups/readUpsCrc.bin"),
            Triple("bps", "/bps/1.bps", "/bps/1.bin"))) {
            val patch = fixture(patchPath)
            val base = fixture(basePath)
            val bad = patch.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
            assertThrows(Exception::class.java) { check(format, bad, base, base) }
            val wrong = base.copyOf().apply { this[0] = (this[0].toInt() xor 1).toByte() }
            assertThrows(Exception::class.java) { check(format, patch, wrong, base) }
        }
        assertThrows(Exception::class.java) {
            check("ips", "PATCH".toByteArray() + bytes(0, 0, 0, 0, 10), bytes(1), bytes(1))
        }
    }
    @Test fun cancellationAndUndeclaredPreparationRejectBeforeOriginalWrite() {
        Thread.currentThread().interrupt()
        try {
            assertThrows(InterruptedIOException::class.java) {
                check("ips", fixture("/ips/min_ips.ips"), fixture("/ips/min_ips.bin"), bytes(1))
            }
        } finally { Thread.interrupted() }
        val original = folder.newFile().apply { writeBytes(bytes(1, 2)) }
        val patch = folder.newFile().apply { writeBytes("PATCH".toByteArray()) }
        val output = File(folder.root, "no-output")
        assertThrows(IllegalArgumentException::class.java) {
            GShopPatchEngine.apply("ebp", patch, original, output, resources, emptyList())
        }
        assertFalse(output.exists())
        assertArrayEquals(bytes(1, 2), original.readBytes())
    }

    @Test fun ebpExplicitPreparationWithOwnerSuppliedCanonicalBase() {
        // Optional for public contributors without the original game. Release
        // acceptance explicitly supplies this private fixture and checks no skip.
        val path = System.getenv("RSHOP_EBP_BASE")
        org.junit.Assume.assumeTrue("Owner-supplied EBP base not configured", !path.isNullOrEmpty())
        val original = File(path!!)
        val before = original.readBytes()
        assertEquals(0x300000, before.size)
        val md5 = java.security.MessageDigest.getInstance("MD5").digest(before)
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        assertEquals("a864b2e5c141d2dec1c4cbed75a42a85", md5)
        val value = before[0x200].toInt() xor 1
        val patch = folder.newFile().apply {
            writeBytes("PATCH".toByteArray() + bytes(0, 2, 0, 0, 1, value) + "EOF".toByteArray())
        }
        val output = File(folder.root, "ebp-output")
        GShopPatchEngine.apply("ebp", patch, original, output, resources, listOf("ebp-canonical-base"))
        val expected = before.copyOf().apply { this[0x200] = value.toByte() }
        assertArrayEquals(expected, output.readBytes())
        assertArrayEquals(before, original.readBytes())
    }
}
