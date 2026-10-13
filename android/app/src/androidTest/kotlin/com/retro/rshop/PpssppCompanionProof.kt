package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Exclusive synthetic screenshot. No user saves, ROMs, accounts or emulator
 * state are changed. A live emulator is not stopped to obtain restore evidence. */
internal object PpssppCompanionProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        fun id() = UUID.randomUUID().toString().replace("-", "")
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }
        val parent = File("/storage/emulated/0/RShopCompanion-${id()}")
        check(parent.mkdir())
        val source = File(parent, "PPSSPP_STATE")
        check(source.mkdir() && source.canonicalFile == source.absoluteFile)
        val file = File(source, "UTST00001_1.00_0.jpg")
        check(file.createNewFile())
        val a = ByteArray(131073) { (it + 11).toByte() }
        val b = ByteArray(a.size) { (it + 31).toByte() }
        fun write(bytes: ByteArray) = FileOutputStream(file).use { it.write(bytes); it.fd.sync() }
        val captures = mutableListOf<String>()
        val restores = mutableListOf<String>()
        val service = SaveCaptureService(context)
        fun call(method: String, args: Map<String, Any>, expected: String? = null,
                 allowRunningRefusal: Boolean = false): Any? {
            val done = CountDownLatch(1)
            var value: Any? = null
            var error: String? = null
            service.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                override fun notImplemented() { error = "not_implemented"; done.countDown() }
            })
            done.await()
            check(error == expected || allowRunningRefusal && error == "stop_ppsspp_required") {
                "$method: $error (expected $expected)"
            }
            return if (allowRunningRefusal && error != null) error else value
        }
        fun capture(expected: String? = null): String {
            val capture = id().also(captures::add)
            val result = call("capturePpssppCompanion", mapOf("captureId" to capture,
                "directory" to source.path, "name" to file.name), expected)
            if (expected == null) {
                @Suppress("UNCHECKED_CAST") val member =
                    ((result as Map<*, *>)["files"] as List<Map<String, Any>>).single()
                check(member["name"] == file.name && member["size"] == a.size.toLong())
                val sealed = File(member["path"] as String).readBytes()
                check(sealed.contentEquals(file.readBytes()) && digest(sealed) == member["sha256"])
            }
            return capture
        }
        val changed = CountDownLatch(1)
        var watchFailed = false
        val key = "e".repeat(64)
        val watch = SaveFileWatch(context, unavailable = { watchFailed = true }) {
            check(it == key); changed.countDown()
        }
        var restored = false
        try {
            check(watch.replace(listOf(SaveFileWatch.Mapping(key, source.path, file.name,
                "ppsspp-companion"))) == listOf(key))
            write(a); changed.await(); check(!watchFailed)
            FileOutputStream(file, true).use { capture("source_changed") }
            SaveSourceStorage.open(context, source.path).use { storage ->
                storage.beginPpssppCompanionSnapshot(context, file.name)
                val reader = storage.openFile(file.name, false, false)
                try { storage.verifySnapshot() } finally { storage.closeFile(reader) }
                write(b)
                try { storage.verifySnapshot(); error("Accepted overlapping write") }
                catch (error: java.io.IOException) { check(error.message == "source_changed") }
            }
            write(a)
            val first = capture()
            check((call("ppssppNames", mapOf("directory" to source.path)) as List<*>).isEmpty())
            call("capturePpsspp", mapOf("captureId" to first, "directory" to source.path,
                "name" to file.name), "invalid_selection")
            write(b)
            val rollback = capture()
            val restore = id().also(restores::add)
            call("beginRestore", mapOf("captureId" to restore, "name" to file.name,
                "ppssppDirectory" to source.path, "ppssppCompanion" to true,
                "size" to a.size.toLong(), "sha256" to digest(a)))
            var offset = 0
            while (offset < a.size) {
                val end = minOf(a.size, offset + 65536)
                check(call("appendRestore", mapOf("captureId" to restore, "offset" to offset.toLong(),
                    "bytes" to a.copyOfRange(offset, end))) == end.toLong())
                offset = end
            }
            call("sealRestore", mapOf("captureId" to restore))
            // A cached process after normal Exit can be closed without Android's
            // stopped-package flag. Let the actual native lifecycle guard decide.
            val refused = call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback),
                allowRunningRefusal = true) == "stop_ppsspp_required"
            check(file.readBytes().contentEquals(if (refused) b else a))
            restored = !refused
        } finally {
            watch.close()
            val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await()
            check(source.list()!!.toSet() == setOf(file.name))
            check(file.delete() && source.delete() && parent.delete())
            for ((root, ids, allowed) in listOf(
                Triple("save-captures", captures, setOf("capture.json", "capture.json.part", "member-0")),
                Triple("save-restores", restores, setOf("restore.json", "restore.json.next", "member")))) {
                for (owned in ids) {
                    val folder = File(context.filesDir.canonicalFile, "$root/$owned")
                    if (!folder.exists()) continue
                    check(folder.canonicalFile == folder.absoluteFile)
                    val files = folder.listFiles()!!
                    check(files.all { it.name in allowed && it.isFile && it.canonicalFile == it.absoluteFile })
                    files.forEach { check(it.delete()) }; check(folder.delete())
                }
            }
        }
        return "PASS PPSSPP screenshot companion: exact watch, writer/mutation rejection, reader admitted, full streamed digest, state separation, restore staging; " +
            (if (restored) "closed-runtime restore verified" else "running-runtime restore refused without changing bytes") +
            "; exclusive fixture cleanup; no user saves/ROMs/accounts changed"
    }
}
