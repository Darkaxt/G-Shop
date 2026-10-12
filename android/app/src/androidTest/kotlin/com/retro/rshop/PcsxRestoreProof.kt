package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** One exclusive content override redirects BOTH card roles to disposable files.
 * User cards/configuration remain untouched. Uses the real CONTENTLESS reply. */
internal object PcsxRestoreProof {
    fun exercise(context: Context, installationId: String, filename: String, encodedLeaf: String) {
        check(context.packageName == "com.darkaxt.rshop.debug")
        var service = SaveCaptureService(context)
        val captures = mutableListOf<String>()
        val restores = mutableListOf<String>()
        val extraStages = mutableListOf<String>()
        fun id() = UUID.randomUUID().toString().replace("-", "")
        val directory = File("/storage/emulated/0/RetroArch/saves", "RShopPcsxRestore-${id()}")
        check(directory.mkdir())
        val override = File("/storage/emulated/0/RetroArch/config/PCSX-ReARMed", encodedLeaf.dropLast(4) + ".cfg")
        check(!override.exists())
        val configuration = "savefile_directory = \"${directory.path}\"\nsort_savefiles_enable = \"false\"\n"
        fun write(file: File, bytes: ByteArray) {
            FileOutputStream(file).use { it.write(bytes); it.fd.sync() }
        }
        fun close() { val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await() }
        fun call(method: String, arguments: Map<String, Any>, expected: String? = null): Any? {
            val done = CountDownLatch(1)
            var value: Any? = null
            var failure: String? = null
            service.handle(MethodCall(method, arguments), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await()
            check(failure == expected) { "PCSX restore $method: $failure (expected $expected)" }
            return value
        }
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        fun selection(slot: Int): Map<String, Any> = mapOf("installationId" to installationId,
            "filename" to filename, "directory" to directory.path, "slot" to slot,
            "mode" to if (slot == 1) "libretro" else "shared",
            "name" to if (slot == 1) encodedLeaf.dropLast(4) + ".srm" else "pcsx-card2.mcd")
        fun capture(slot: Int, baseline: Boolean = false): String {
            val key = id().also(captures::add)
            call("capturePcsx", selection(slot) + mapOf("captureId" to key, "restoreBaseline" to baseline))
            return key
        }
        fun stage(slot: Int, bytes: ByteArray): String {
            val key = id().also(restores::add)
            val args = selection(slot) + mapOf("captureId" to key, "size" to bytes.size.toLong(), "sha256" to digest(bytes))
            call("beginPcsxRestore", args)
            call("beginPcsxRestore", args + ("slot" to if (slot == 1) 2 else 1), "source_changed")
            for (offset in bytes.indices step 65536) {
                val end = minOf(offset + 65536, bytes.size)
                check(call("appendRestore", mapOf("captureId" to key, "offset" to offset.toLong(),
                    "bytes" to bytes.copyOfRange(offset, end))) == end.toLong())
            }
            call("sealRestore", mapOf("captureId" to key))
            return key
        }
        try {
            check(override.createNewFile()); write(override, configuration.toByteArray())
            check(SaveSourceStorage.pcsxSettings(context, encodedLeaf).getString("directory") == directory.path)
            for (slot in 1..2) {
                val file = File(directory, selection(slot).getValue("name") as String)
                check(file.createNewFile())
                val before = ByteArray(131072) { (it + slot).toByte() }
                val after = ByteArray(131072) { (it + 81 + slot).toByte() }
                write(file, before)
                val original = capture(slot)
                write(file, after)
                val retained = capture(slot)
                val restored = stage(slot, before)
                val args = selection(slot) + mapOf("captureId" to restored, "rollbackCaptureId" to retained)
                call("publishRestore", mapOf("captureId" to restored, "rollbackCaptureId" to retained), "invalid_restore")
                call("publishPcsxRestore", args + ("filename" to "synthetic.zip"), "invalid_selection")
                call("publishPcsxRestore", selection(if (slot == 1) 2 else 1) +
                    mapOf("captureId" to restored, "rollbackCaptureId" to retained), "invalid_restore")
                FileOutputStream(file, true).use { call("publishPcsxRestore", args, "source_changed") }
                check(file.readBytes().contentEquals(after))
                call("publishPcsxRestore", args)
                check(file.readBytes().contentEquals(before))
                val old = JSONObject(File(context.filesDir, "save-captures/$retained/capture.json").readText())
                check(File(context.filesDir, "save-captures/$retained/member-0").readBytes().contentEquals(after))
                check(old.getJSONArray("files").getJSONObject(0).getString("sha256") == digest(after))

                // Replay after process recreation, including a lost terminal
                // acknowledgement: only the staged inode at the target qualifies.
                val journal = File(context.filesDir, "save-restores/$restored/restore.json")
                write(journal, JSONObject(journal.readText()).put("phase", "publishing").toString().toByteArray())
                close(); service = SaveCaptureService(context)
                call("publishPcsxRestore", args)
                check(JSONObject(journal.readText()).getString("phase") == "published")
                check(file.readBytes().contentEquals(before))

                val rollback = stage(slot, after)
                val rollbackArgs = selection(slot) + mapOf("captureId" to rollback, "rollbackCaptureId" to original)
                write(override, (configuration + "# changed settings revision\n").toByteArray())
                // Selection is still valid; the root lane rejects a revision
                // change after opening rather than blindly trusting that layout.
                val selected = PcsxSaveSettings.Selection(directory.path,
                    PcsxSaveSettings.Card(slot, if (slot == 1) "libretro" else "shared", file.name))
                val stageName = ".rshop-save-restore-${id()}".also(extraStages::add)
                SaveSourceStorage.openPcsxRestore(context, encodedLeaf, selected, stageName.takeLast(32)).use { lane ->
                    val fd = lane.openFile(stageName, true, true)
                    try {
                        write(override, configuration.toByteArray())
                        try { lane.write(fd, 0, byteArrayOf(1)); error("Accepted changed PCSX settings") }
                        catch (error: IOException) { check(error.message == "source_changed") }
                        try { lane.openFile(file.name, false, true); error("Opened target writable") }
                        catch (error: IOException) { check(error.message == "source_changed" || error.message == "root_unavailable") }
                    } finally { lane.closeFile(fd) }
                }
                check(File(directory, stageName).delete())
                call("publishPcsxRestore", rollbackArgs)
                check(file.readBytes().contentEquals(after))

                // A first-save absence is independently retained and published
                // without overwriting a surprise entry.
                check(file.delete())
                val absent = capture(slot, baseline = true)
                val missing = stage(slot, before)
                call("publishPcsxRestore", selection(slot) + mapOf("captureId" to missing, "rollbackCaptureId" to absent))
                check(file.readBytes().contentEquals(before))
            }
        } finally {
            close()
            check(!override.exists() || override.delete())
            val names = setOf(encodedLeaf.dropLast(4) + ".srm", "pcsx-card2.mcd") + extraStages + restores.map { ".rshop-save-restore-$it" }
            directory.listFiles()!!.forEach { check(it.isFile && it.name in names); check(it.delete()) }
            check(directory.delete())
            fun clean(root: String, ids: List<String>, names: Set<String>) {
                for (key in ids) {
                    val dir = File(context.filesDir.canonicalFile, "$root/$key")
                    if (!dir.exists()) continue
                    check(dir.canonicalFile == dir.absoluteFile)
                    val entries = dir.listFiles()!!
                    check(entries.all { it.isFile && it.canonicalFile == it.absoluteFile && it.name in names })
                    entries.forEach { check(it.delete()) }; check(dir.delete())
                }
            }
            clean("save-captures", captures, setOf("capture.json", "capture.json.part", "member-0"))
            clean("save-restores", restores, setOf("restore.json", "restore.json.next", "member"))
        }
    }
}
