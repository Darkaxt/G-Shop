package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** App-UID capture and atomic destination-write proof using exclusive disposable
 * save bytes. Requires the real installed RetroArch's CONTENTLESS reply. Does not
 * mock its UDP endpoint, run gameplay, access Drive or alter an existing save. */
internal object SegaSaveRouteProof {
    fun exercise(context: Context, n64: Boolean = false): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val source = File("/storage/emulated/0/RetroArch/saves/" +
            if (n64) "Mupen64Plus-Next" else "Genesis Plus GX")
        check(source.isDirectory && source.canonicalFile == source.absoluteFile)
        val initialNames = source.list()!!.toSet()
        val service = SaveCaptureService(context)
        val ownedCaptures = mutableListOf<String>()
        val ownedRestores = mutableListOf<String>()
        val names = mutableListOf<String>()
        fun id() = UUID.randomUUID().toString().replace("-", "")
        fun call(method: String, arguments: Map<String, Any>, expectedError: String? = null): Any? {
            val done = CountDownLatch(1)
            var value: Any? = null
            var failure: String? = null
            service.handle(MethodCall(method, arguments), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) {
                    failure = code; done.countDown()
                }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await() // Native acknowledgement, never an elapsed-time success.
            check(failure == expectedError) { "Native save operation: $failure (expected $expectedError)" }
            return value
        }
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        fun write(file: File, bytes: ByteArray) {
            FileOutputStream(file).use { it.write(bytes); it.fd.sync() }
        }
        fun capture(route: String, name: String): String {
            val captureId = id().also(ownedCaptures::add)
            @Suppress("UNCHECKED_CAST")
            val receipt = call("captureRetroArch", mapOf("captureId" to captureId,
                "name" to name, "retroArchRoute" to route)) as Map<String, Any>
            check(receipt["captureId"] == captureId)
            @Suppress("UNCHECKED_CAST")
            val files = receipt["files"] as List<Map<String, Any>>
            check(files.size == 1 && files.single()["name"] == name)
            val captured = File(files.single()["path"] as String).readBytes()
            check(captured.contentEquals(File(source, name).readBytes()))
            check(digest(captured) == files.single()["sha256"])
            return captureId
        }
        fun restore(route: String, name: String, bytes: ByteArray, rollback: String) {
            val restoreId = id().also(ownedRestores::add)
            call("beginRestore", mapOf("captureId" to restoreId, "name" to name,
                "retroArchRoute" to route, "size" to bytes.size.toLong(), "sha256" to digest(bytes)))
            call("beginRestore", mapOf("captureId" to restoreId, "name" to name,
                "retroArchRoute" to if (route == "mastersystem") "megadrive" else "mastersystem",
                "size" to bytes.size.toLong(), "sha256" to digest(bytes)), "invalid_restore")
            var offset = 0
            while (offset < bytes.size) {
                val end = minOf(offset + 65536, bytes.size)
                check(call("appendRestore", mapOf("captureId" to restoreId, "offset" to offset.toLong(),
                    "bytes" to bytes.copyOfRange(offset, end))) == end.toLong())
                offset = end
            }
            call("sealRestore", mapOf("captureId" to restoreId))
            call("publishRestore", mapOf("captureId" to restoreId, "rollbackCaptureId" to rollback))
            check(File(source, name).readBytes().contentEquals(bytes))
        }
        try {
            for (route in if (n64) listOf("n64") else listOf("mastersystem", "megadrive")) {
                val name = "rshop-$route-proof-${id()}.srm".also(names::add)
                val file = File(source, name)
                check(file.createNewFile()) // Never replace a pre-existing entry.
                val before = ByteArray(if (n64) 296960 else 50) { (it + 11).toByte() }
                val after = ByteArray(before.size) { (it + 71).toByte() }
                write(file, before)
                val original = capture(route, name)
                call("captureRetroArch", mapOf("captureId" to original, "name" to name,
                    "retroArchRoute" to if (route == "mastersystem") "megadrive" else "mastersystem"), "invalid_capture")
                write(file, after)
                val rollback = capture(route, name)
                restore(route, name, before, rollback)
                val restored = capture(route, name)
                restore(route, name, after, restored)
                check(file.readBytes().contentEquals(after))
                check(source.list()!!.toSet() == initialNames + names)
            }
        } finally {
            val closed = CountDownLatch(1)
            service.shutdown { closed.countDown() }
            closed.await()
            // These IDs were exclusively allocated above. Unknown members are
            // preserved and fail cleanup; no recursive delete or broad sweep.
            fun removePrivate(root: String, ids: List<String>, allowed: Set<String>) {
                for (ownedId in ids) {
                    val directory = File(context.filesDir.canonicalFile, "$root/$ownedId")
                    if (!directory.exists()) continue
                    check(directory.canonicalFile == directory.absoluteFile)
                    val members = directory.listFiles()!!
                    check(members.all { it.name in allowed && it.isFile &&
                        it.canonicalFile == it.absoluteFile })
                    members.forEach { check(it.delete()) }
                    check(directory.delete())
                }
            }
            for (name in names) {
                val file = File(source, name)
                check(file.canonicalFile == file.absoluteFile)
                if (file.exists()) check(file.delete())
            }
            removePrivate("save-captures", ownedCaptures, setOf("capture.json", "capture.json.part", "member-0"))
            removePrivate("save-restores", ownedRestores, setOf("restore.json", "restore.json.part", "member"))
            check(source.list()!!.toSet() == initialNames)
        }
        return "PASS ${if (n64) "n64 complete 296960-byte memory" else "mastersystem/megadrive"} app-UID capture/digest, cross-console capture/restore replay rejection, atomic expected-location restore and retained-byte rollback; real RetroArch CONTENTLESS; exclusive fixtures removed; no Drive/gameplay/settings/ROM access"
    }
}
