package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Actual app-UID group writes with exclusive disposable files. The interrupted
 * receipt is injected only in this instrumentation, never a production hook. */
internal object MgbaGroupSaveProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val source = File("/storage/emulated/0/RetroArch/saves/mGBA")
        check(source.isDirectory && source.canonicalFile == source.absoluteFile)
        val initial = source.list()!!.toSet()
        var service = SaveCaptureService(context)
        val captures = mutableListOf<String>()
        val restores = mutableListOf<String>()
        fun id() = UUID.randomUUID().toString().replace("-", "")
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        fun child(group: String, index: Int) = digest("$group/$index".toByteArray()).take(32)
        val name = "rshop-mgba-group-${id()}.srm"
        val held = File(source, "$name.held")
        val names = listOf(name.dropLast(4) + ".rtc", name)
        val before = names.associateWith { ByteArray(50) { i -> (i + 11).toByte() } }
        val after = names.associateWith { ByteArray(50) { i -> (i + 71).toByte() } }
        fun write(file: File, bytes: ByteArray) = FileOutputStream(file).use { it.write(bytes); it.fd.sync() }
        fun close() { val ack = CountDownLatch(1); service.shutdown { ack.countDown() }; ack.await() }
        fun call(method: String, args: Map<String, Any>, expected: String? = null): Any? {
            val ack = CountDownLatch(1)
            var value: Any? = null
            var error: String? = null
            service.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; ack.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = code; ack.countDown() }
                override fun notImplemented() { error = "not_implemented"; ack.countDown() }
            })
            ack.await()
            check(error == expected) { "$method: $error (expected $expected)" }
            return value
        }
        fun capture(): String {
            val capture = id().also(captures::add)
            @Suppress("UNCHECKED_CAST") val receipt = call("captureRetroArch", mapOf("captureId" to capture, "name" to name)) as Map<String, Any>
            @Suppress("UNCHECKED_CAST") val members = receipt["files"] as List<Map<String, Any>>
            check(members.map { it["name"] }.toSet() == names.toSet())
            for (member in members) {
                val bytes = File(member["path"] as String).readBytes()
                check(digest(bytes) == member["sha256"] && bytes.contentEquals(File(source, member["name"] as String).readBytes()))
            }
            return capture
        }
        fun stage(bytes: Map<String, ByteArray>, earlySeal: Boolean = false): String {
            val restore = id().also(restores::add)
            restores += (0..1).map { child(restore, it) }
            call("beginRestoreGroup", mapOf("captureId" to restore, "name" to name,
                "members" to names.map { mapOf("name" to it, "size" to bytes.getValue(it).size.toLong(), "sha256" to digest(bytes.getValue(it))) }))
            for ((index, member) in names.withIndex()) {
                check(call("appendRestoreGroup", mapOf("captureId" to restore, "member" to index,
                    "offset" to 0L, "bytes" to bytes.getValue(member))) == 50L)
                if (earlySeal && index == 0) {
                    call("sealRestoreGroup", mapOf("captureId" to restore), "changed_capture")
                    check(names.all { File(source, it).readBytes().contentEquals(after.getValue(it)) })
                }
            }
            call("sealRestoreGroup", mapOf("captureId" to restore))
            return restore
        }
        try {
            for (member in names) { val f = File(source, member); check(f.createNewFile()); write(f, before.getValue(member)) }
            capture()
            for (member in names) write(File(source, member), after.getValue(member))
            val rollback = capture()
            val restore = stage(before, earlySeal = true)
            // A scalar call cannot bypass the group publication guard.
            call("publishRestore", mapOf("captureId" to child(restore, 0), "rollbackCaptureId" to rollback), "invalid_restore")
            // Model process loss immediately after the first actual atomic
            // member publication. Persist exactly the normal coordinator intent.
            val journal = File(context.filesDir.canonicalFile, "save-restores/$restore/group.json")
            val record = JSONObject(journal.readText()).put("rollbackId", rollback).put("phase", "publishing")
            write(journal, record.toString().toByteArray())
            val publish = SaveCaptureService::class.java.getDeclaredMethod("publishRestore", String::class.java, String::class.java, String::class.java)
            publish.isAccessible = true
            publish.invoke(service, child(restore, 0), rollback, restore)
            check(File(source, names[0]).readBytes().contentEquals(before.getValue(names[0])))
            check(File(source, names[1]).readBytes().contentEquals(after.getValue(names[1])))
            check(SaveCaptureService.groupRestorePending(context.filesDir, name))
            close()
            service = SaveCaptureService(context)
            // A published child is not permission to accept changed bytes or
            // a replacement inode with identical bytes on resumed publication.
            write(File(source, names[0]), after.getValue(names[0]))
            call("publishRestoreGroup", mapOf("captureId" to restore, "rollbackCaptureId" to rollback), "source_changed")
            write(File(source, names[0]), before.getValue(names[0]))
            check(!held.exists() && File(source, names[0]).renameTo(held))
            try {
                check(File(source, names[0]).createNewFile())
                write(File(source, names[0]), before.getValue(names[0]))
                call("publishRestoreGroup", mapOf("captureId" to restore, "rollbackCaptureId" to rollback), "source_changed")
            } finally {
                check(File(source, names[0]).delete())
                check(held.renameTo(File(source, names[0])))
            }
            call("publishRestoreGroup", mapOf("captureId" to restore, "rollbackCaptureId" to rollback))
            check(names.all { File(source, it).readBytes().contentEquals(before.getValue(it)) })
            check(!SaveCaptureService.groupRestorePending(context.filesDir, name))
            val current = capture()
            val undo = stage(after)
            call("publishRestoreGroup", mapOf("captureId" to undo, "rollbackCaptureId" to current))
            check(names.all { File(source, it).readBytes().contentEquals(after.getValue(it)) })
        } catch (error: Exception) {
            val state = restores.filterIndexed { index, _ -> index % 3 == 0 }.map { group ->
                (0..1).map { index ->
                    val journal = File(context.filesDir.canonicalFile, "save-restores/${child(group, index)}/restore.json")
                    if (journal.isFile) JSONObject(journal.readText()).getString("phase") else "absent"
                }
            }
            val beforeMatches = names.map { File(source, it).takeIf(File::isFile)?.readBytes()?.contentEquals(before.getValue(it)) }
            val afterMatches = names.map { File(source, it).takeIf(File::isFile)?.readBytes()?.contentEquals(after.getValue(it)) }
            throw IllegalStateException("${error.message}; before=$beforeMatches after=$afterMatches childPhases=$state", error)
        } finally {
            close()
            check(!held.exists())
            for (member in names) {
                val f = File(source, member)
                check(f.canonicalFile == f.absoluteFile)
                if (f.exists()) check(f.delete())
            }
            fun remove(root: String, ids: List<String>, allowed: Set<String>) {
                for (owned in ids) {
                    val directory = File(context.filesDir.canonicalFile, "$root/$owned")
                    if (!directory.exists()) continue
                    check(directory.canonicalFile == directory.absoluteFile)
                    val files = directory.listFiles()!!
                    check(files.all { it.name in allowed && it.isFile && it.canonicalFile == it.absoluteFile })
                    files.forEach { check(it.delete()) }
                    check(directory.delete())
                }
            }
            remove("save-captures", captures, setOf("capture.json", "capture.json.part", "member-0", "member-1"))
            remove("save-restores", restores, setOf("group.json", "group.json.next", "restore.json", "restore.json.next", "member"))
            check(source.list()!!.toSet() == initial)
        }
        return "PASS mGBA SRAM/RTC app-UID capture/digests, whole-group seal, scalar-bypass rejection, changed-byte and replacement-inode rejection, interrupted-prefix recovery after service recreation, expected-location group restore and retained-byte rollback; real RetroArch CONTENTLESS; exclusive fixtures removed; no Drive/gameplay/settings/ROM access"
    }
}
