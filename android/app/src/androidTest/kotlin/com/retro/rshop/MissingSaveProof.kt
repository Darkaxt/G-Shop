package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import org.json.JSONObject

/** Complete native missing-save restore at an expendable expected destination.
 * Uses application root admission, not shell-UID root or real emulator saves. */
internal object MissingSaveProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        fun id() = UUID.randomUUID().toString().replace("-", "")
        val parent = File("/storage/emulated/0/RShopLiveTest")
        check(parent.isDirectory && parent.canonicalFile == parent.absoluteFile)
        val source = File(parent, "missing-save-${id()}")
        check(source.mkdir())
        val target = File(source, "Fixture.sav")
        val baseline = id()
        val expendable = id()
        val restore = id()
        val desired = byteArrayOf(21, 22, 23, 24)
        val competing = byteArrayOf(31, 32, 33, 34)
        val digest = MessageDigest.getInstance("SHA-256").digest(desired)
            .joinToString("") { "%02x".format(it) }
        var service = SaveCaptureService(context)
        fun close() { val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await() }
        fun call(method: String, args: Map<String, Any>, expected: String? = null): Any? {
            val done = CountDownLatch(1)
            var value: Any? = null
            var error: String? = null
            service.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                override fun notImplemented() { error = "not_implemented"; done.countDown() }
            })
            done.await()
            check(error == expected) { "$method: $error (expected $expected)" }
            return value
        }
        val captureArgs = mapOf("captureId" to baseline, "directory" to source.path, "name" to target.name)
        val publishArgs = mapOf("captureId" to restore, "rollbackCaptureId" to baseline)
        try {
            @Suppress("UNCHECKED_CAST")
            val receipt = call("captureMelon", captureArgs + ("restoreBaseline" to true)) as Map<String, Any>
            check(receipt["localWasAbsent"] == true && (receipt["files"] as List<*>).isEmpty())
            call("captureMelon", captureArgs, "invalid_capture") // Never an empty backup.
            call("captureMelon", captureArgs + mapOf("captureId" to expendable, "restoreBaseline" to true))
            call("retireCapture", mapOf("captureId" to expendable))
            check(!File(context.filesDir.canonicalFile, "save-captures/$expendable").exists())
            call("beginRestore", mapOf("captureId" to restore, "name" to target.name,
                "melonDirectory" to source.path, "size" to desired.size.toLong(), "sha256" to digest))
            call("appendRestore", mapOf("captureId" to restore, "offset" to 0L, "bytes" to desired))
            call("sealRestore", mapOf("captureId" to restore))
            check(target.createNewFile())
            FileOutputStream(target).use { it.write(competing); it.fd.sync() }
            call("publishRestore", publishArgs, "source_changed")
            check(target.readBytes().contentEquals(competing))
            check(target.delete()) // Exact exclusively created competing fixture.
            close(); service = SaveCaptureService(context)
            call("publishRestore", publishArgs)
            check(target.readBytes().contentEquals(desired))
            // Reproduce a lost final acknowledgement using only this owned
            // receipt. A resumed commit must validate, not replace, the target.
            val journal = File(context.filesDir.canonicalFile, "save-restores/$restore/restore.json")
            val record = JSONObject(journal.readText()).put("phase", "publishing")
            FileOutputStream(journal).use { it.write(record.toString().toByteArray()); it.fd.sync() }
            close(); service = SaveCaptureService(context)
            call("publishRestore", publishArgs)
            check(target.readBytes().contentEquals(desired))
            check(JSONObject(journal.readText()).getString("phase") == "published")
        } finally {
            close()
            // An unexpected entry is preserved and makes this proof fail.
            val leaves = source.list()!!.toSet()
            check(leaves.all { it == target.name || it == ".rshop-save-restore-$restore" })
            for (name in leaves) {
                val file = File(source, name)
                check(file.isFile && file.canonicalFile == file.absoluteFile && file.delete())
            }
            check(source.delete())
            for ((root, token, allowed) in listOf(
                Triple("save-captures", baseline, setOf("capture.json", "capture.json.part")),
                Triple("save-captures", expendable, setOf("capture.json", "capture.json.part")),
                Triple("save-restores", restore, setOf("restore.json", "restore.json.next", "member")))) {
                val directory = File(context.filesDir.canonicalFile, "$root/$token")
                if (!directory.exists()) continue
                val files = directory.listFiles()!!
                check(files.all { it.name in allowed && it.isFile && it.canonicalFile == it.absoluteFile })
                files.forEach { check(it.delete()) }; check(directory.delete())
            }
        }
        return "PASS application-root missing save: sealed absence, empty-backup rejection, competing-local preservation, verified destination bytes, service-recreation restore and lost-ack recovery; exclusive fixture cleanup; no real save/ROM/configuration/cloud access"
    }
}
