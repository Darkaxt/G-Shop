package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** The private card/override belong to one exclusive synthetic owned CHD.
 * The real shared card is read only. No emulator, account or Drive mutations. */
internal object PcsxCaptureProof {
    fun exercise(context: Context, installationId: String, filename: String, encodedLeaf: String) {
        val service = SaveCaptureService(context)
        val captures = mutableSetOf<String>()
        val layout = SaveSourceStorage.pcsxSettings(context, encodedLeaf)
        val directory = File(layout.getString("directory"))
        val privateName = encodedLeaf.dropLast(4) + ".srm"
        val privateCard = File(directory, privateName)
        val shared = File(directory, "pcsx-card2.mcd")
        val override = File("/storage/emulated/0/RetroArch/config/PCSX-ReARMed", encodedLeaf.dropLast(4) + ".cfg")
        check(!privateCard.exists() && !override.exists())
        val initialNames = directory.list()!!.toSet()
        val originalShared = shared.readBytes()
        check(originalShared.size == 131072)
        val sharedIdentity = SaveSourceStorage.pcsxSettings(context, encodedLeaf).toString()
        fun id() = UUID.randomUUID().toString().replace("-", "").also(captures::add)
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        fun capture(slot: Int, captureId: String = id(), expected: String? = null,
                    baseline: Boolean = false, mode: String = if (slot == 1) "libretro" else "shared"): Map<*, *>? {
            val done = CountDownLatch(1)
            var receipt: Map<*, *>? = null
            var failure: String? = null
            service.handle(MethodCall("capturePcsx", mapOf("captureId" to captureId,
                "installationId" to installationId, "filename" to filename,
                "directory" to directory.path, "slot" to slot, "mode" to mode,
                "name" to if (slot == 1) privateName else shared.name, "restoreBaseline" to baseline)), object : MethodChannel.Result {
                override fun success(result: Any?) { receipt = result as Map<*, *>; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await()
            check(failure == expected) { "PCSX capture: $failure (expected $expected)" }
            return receipt
        }
        fun write(bytes: ByteArray) { FileOutputStream(privateCard).use { it.write(bytes); it.fd.sync() } }
        fun verify(receipt: Map<*, *>, name: String, bytes: ByteArray) {
            val row = (receipt["files"] as List<*>).single() as Map<*, *>
            check(row["name"] == name && row["size"] == bytes.size.toLong() && row["sha256"] == digest(bytes))
            check(File(row["path"] as String).readBytes().contentEquals(bytes))
        }
        try {
            val missing = capture(1, baseline = true)!!
            check(missing["localWasAbsent"] == true && (missing["files"] as List<*>).isEmpty())
            check(privateCard.createNewFile())
            val bytes = ByteArray(131072) { (it + 31).toByte() }
            write(bytes.copyOf(131071))
            val truncated = id()
            capture(1, truncated, "invalid_save_size")
            check(!File(context.filesDir, "save-captures/$truncated/capture.json").exists())
            write(bytes)
            FileOutputStream(privateCard, true).use { capture(1, expected = "source_changed") }
            val privateId = id()
            FileInputStream(privateCard).use { verify(capture(1, privateId)!!, privateName, bytes) }
            verify(capture(1, privateId)!!, privateName, bytes) // Durable replay.
            capture(2, privateId, "invalid_capture")
            capture(1, expected = "source_changed", mode = "shared")
            verify(capture(2)!!, shared.name, originalShared)

            val selected = PcsxSaveSettings.Selection(directory.path, PcsxSaveSettings.Card(1, "libretro", privateName))
            SaveSourceStorage.openPcsxCapture(context, encodedLeaf, selected).use { source ->
                for (action in listOf<() -> Unit>(
                    { source.openFile(shared.name, false, false); error("Read another card through private lane") },
                    { source.openFile(privateName, false, true); error("Opened card for writing through capture lane") })) {
                    try { action(); error("Accepted out-of-scope card access") }
                    catch (error: IOException) { check(error.message == "root_unavailable") }
                }
            }
            SaveSourceStorage.openPcsxCapture(context, encodedLeaf, selected).use { source ->
                source.beginPcsxSnapshot(context, privateName)
                write(bytes) // Same bytes/size still overlap the snapshot.
                try { source.verifySnapshot(); error("Accepted overlapping PS1 writer") }
                catch (error: IOException) { check(error.message == "source_changed") }
            }
            SaveSourceStorage.openPcsxCapture(context, encodedLeaf, selected).use { source ->
                source.beginPcsxSnapshot(context, privateName)
                check(override.createNewFile())
                FileOutputStream(override).use { it.write("# exclusive settings revision proof\n".toByteArray()); it.fd.sync() }
                try { source.verifySnapshot(); error("Accepted new game override") }
                catch (error: IOException) { check(error.message == "source_changed") }
            }
            check(override.delete())
            check(privateCard.readBytes().contentEquals(bytes))
            check(shared.readBytes().contentEquals(originalShared))
            check(SaveSourceStorage.pcsxSettings(context, encodedLeaf).toString() == sharedIdentity)
        } finally {
            val closed = CountDownLatch(1)
            service.shutdown { closed.countDown() }; closed.await()
            check(!override.exists() || override.delete())
            check(!privateCard.exists() || privateCard.delete())
            for (captureId in captures) {
                val stage = File(context.filesDir.canonicalFile, "save-captures/$captureId")
                if (!stage.exists()) continue
                check(stage.canonicalFile == stage.absoluteFile)
                val members = stage.listFiles()!!
                check(members.all { it.isFile && it.canonicalFile == it.absoluteFile &&
                    it.name in setOf("capture.json", "capture.json.part", "member-0") })
                members.forEach { check(it.delete()) }; check(stage.delete())
            }
            check(directory.list()!!.toSet() == initialNames)
            check(shared.readBytes().contentEquals(originalShared))
        }
    }
}
