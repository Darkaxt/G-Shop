package com.retro.rshop

import android.content.Context
import android.content.pm.ApplicationInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import org.json.JSONObject

/** App-UID proof for the explicitly mapped shared SRAM route. No emulator
 * launch, user configuration change, real save, account or network operation. */
internal object MelonSaveProof {
    fun exercise(context: Context, protected: Boolean = false, liveCapture: Boolean = false): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        @Suppress("DEPRECATION")
        val runtime = context.packageManager.getPackageInfo(MelonSaveBoundary.PACKAGE, 0)
        check(runtime.versionName == MelonSaveBoundary.VERSION)
        check((runtime.applicationInfo!!.flags and ApplicationInfo.FLAG_STOPPED == 0) == liveCapture)
        fun id() = UUID.randomUUID().toString().replace("-", "")
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val parent = File("/storage/emulated/0/RShopLiveTest")
        val createdParent = !protected && !parent.exists() && parent.mkdir()
        if (!protected) check(parent.isDirectory && parent.canonicalFile == parent.absoluteFile)
        val source = if (protected) File(MelonSaveBoundary.PROTECTED_SOURCE) else File(parent, "melon-save-${id()}")
        if (!protected) check(source.mkdir() && source.canonicalFile == source.absoluteFile)
        val file = File(source, if (protected) "RShopFixture-${id()}.sav" else "Fixture.sav")
        if (!protected) check(file.createNewFile())
        val a = ByteArray(if (protected) 131073 else 50) { (it + 17).toByte() }
        val b = ByteArray(a.size) { (it + 57).toByte() }
        val captures = mutableListOf<String>()
        val restores = mutableListOf<String>()
        var service = SaveCaptureService(context)
        fun read(): ByteArray = if (!protected) file.readBytes() else
            SaveSourceStorage.open(context, source.path).use { storage ->
                check(storage.rootAssisted)
                val fd = storage.openFile(file.name, false, false)
                try {
                    val size = storage.identity(fd)[2].toInt()
                    check(size == a.size)
                    ByteArray(size).also { bytes ->
                        var offset = 0
                        while (offset < size) {
                            val chunk = storage.read(fd, offset.toLong(), minOf(65536, size - offset))
                            check(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                        }
                    }
                } finally { storage.closeFile(fd) }
            }
        fun write(bytes: ByteArray) {
            if (!protected) { FileOutputStream(file).use { it.write(bytes); it.fd.sync() }; return }
            SaveSourceStorage.open(context, source.path).use { storage ->
                check(storage.rootAssisted)
                val old = if (storage.exists(file.name)) storage.entryIdentity(file.name) else null
                val stage = ".rshop-save-restore-${id()}"
                val fd = storage.openFile(stage, true, true)
                val placed = try {
                    var offset = 0
                    while (offset < bytes.size) {
                        val end = minOf(bytes.size, offset + 65536)
                        storage.write(fd, offset.toLong(), bytes.copyOfRange(offset, end)); offset = end
                    }
                    storage.sync(fd); storage.identity(fd)
                } finally { storage.closeFile(fd) }
                if (old == null) storage.renameNoReplace(stage, file.name) else storage.replace(stage, file.name, placed, old)
                storage.sync(storage.root)
            }
        }
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
        fun capture(): Pair<String, File> {
            val capture = id().also(captures::add)
            @Suppress("UNCHECKED_CAST")
            val receipt = call("captureMelon", mapOf("captureId" to capture,
                "directory" to source.path, "name" to file.name)) as Map<String, Any>
            check(receipt["emulatorVersion"] == MelonSaveBoundary.VERSION)
            @Suppress("UNCHECKED_CAST") val member = (receipt["files"] as List<Map<String, Any>>).single()
            val sealed = File(member["path"] as String)
            check(member["name"] == file.name && member["size"] == a.size.toLong())
            check(digest(sealed.readBytes()) == member["sha256"] && sealed.readBytes().contentEquals(read()))
            return capture to sealed
        }
        fun stage(bytes: ByteArray): String {
            val restore = id().also(restores::add)
            call("beginRestore", mapOf("captureId" to restore, "name" to file.name,
                "melonDirectory" to source.path, "size" to bytes.size.toLong(), "sha256" to digest(bytes)))
            var offset = 0
            while (offset < bytes.size) {
                val end = minOf(bytes.size, offset + 65536)
                check(call("appendRestore", mapOf("captureId" to restore, "offset" to offset.toLong(),
                    "bytes" to bytes.copyOfRange(offset, end))) == end.toLong())
                offset = end
            }
            call("sealRestore", mapOf("captureId" to restore))
            return restore
        }
        val watched = CountDownLatch(1)
        val events = mutableListOf<String>()
        var watchFailed = false
        val watch = SaveFileWatch(context, unavailable = { watchFailed = true }) { key ->
            synchronized(events) { events.add(key) }
            watched.countDown()
        }
        try {
            val key = "c".repeat(64)
            val otherKey = "d".repeat(64)
            check(watch.replace(listOf(
                SaveFileWatch.Mapping(key, source.path, file.name, "melon"),
                SaveFileWatch.Mapping(otherKey, source.path, "UnrelatedFixture.sav", "melon")
            )) == listOf(key, otherKey))
            write(a)
            watched.await()
            watch.close() // EOF shutdown and joined root child, without a save event.
            check(!watchFailed)
            synchronized(events) { check(events.isNotEmpty() && events.all { it == key }) }
            // A first launch legitimately has no SRAM file. ENOENT from the
            // existence lookup must not poison an otherwise unchanged guard.
            // Namespace mutations still invalidate the kernel-backed snapshot.
            val absentName = "RShopFixture-${id()}.sav"
            SaveSourceStorage.open(context, source.path).use { storage ->
                storage.beginMelonSnapshot(context, absentName)
                check(!storage.exists(absentName))
                storage.verifySnapshot()
            }
            val absentCapture = id().also(captures::add)
            @Suppress("UNCHECKED_CAST")
            val absence = call("captureMelon", mapOf("captureId" to absentCapture,
                "directory" to source.path, "name" to absentName,
                "restoreBaseline" to true)) as Map<String, Any>
            check(absence["localWasAbsent"] == true && (absence["files"] as List<*>).isEmpty())
            // A writer can be paused between two writes with unchanged stat
            // fields. Neither a quiet file nor the emulator's stopped flag is
            // proof that this descriptor has completed its generation.
            val unfinished = id().also(captures::add)
            val heldWriter = if (protected) ProcessBuilder("su", "-c",
                "exec 3<>'${MelonSaveBoundary.PROTECTED_BACKING}/${file.name}'; printf 'READY\\n'; read done").start() else null
            val sharedWriter = if (!protected) FileOutputStream(file, true) else null
            try {
                if (heldWriter != null) check(heldWriter.inputStream.bufferedReader().readLine() == "READY")
                call("captureMelon", mapOf("captureId" to unfinished,
                    "directory" to source.path, "name" to file.name), "source_changed")
                check(!File(context.filesDir.canonicalFile, "save-captures/$unfinished/capture.json").exists())
            } finally {
                sharedWriter?.close()
                if (heldWriter != null) {
                    heldWriter.outputStream.close()
                    check(heldWriter.waitFor() == 0 || heldWriter.exitValue() == 1)
                    heldWriter.inputStream.close(); heldWriter.errorStream.close()
                }
            }
            SaveSourceStorage.open(context, source.path).use { storage ->
                storage.beginMelonSnapshot(context, file.name)
                // A descriptor used only for reading must not block capture.
                val reader = storage.openFile(file.name, false, false)
                try { storage.verifySnapshot() } finally { storage.closeFile(reader) }
                write(b)
                repeat(2) {
                    try { storage.verifySnapshot(); error("Sealed an overlapping write") }
                    catch (error: java.io.IOException) { check(error.message == "source_changed") }
                }
            }
            write(a)
            @Suppress("UNCHECKED_CAST")
            val names = call("melonNames", mapOf("directory" to source.path)) as List<String>
            check(file.name in names && (protected || names == listOf(file.name)))
            val first = capture()
            call("capturePpsspp", mapOf("captureId" to first.first, "directory" to source.path,
                "name" to file.name), "invalid_selection")
            call("captureMelon", mapOf("captureId" to first.first, "directory" to parent.path,
                "name" to file.name), "invalid_capture")
            if (liveCapture) {
                val restore = stage(first.second.readBytes())
                call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to first.first), "stop_melon_required")
                check(read().contentEquals(a))
                return "PASS MelonDualDS running-runtime ${if (protected) "protected" else "shared"} capture: absent first-save baseline accepted, open writer rejected, mutation rejection stays invalid, read-only descriptor admitted, closed-file capture/digest accepted without FLAG_STOPPED; live restore rejected without changing bytes; exclusive fixture cleanup; no gameplay/Drive/ROM access"
            }
            write(b)
            val rollback = capture()
            val restore = stage(first.second.readBytes())
            write(a)
            call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback.first), "source_changed")
            check(read().contentEquals(a))
            write(b)
            close()
            service = SaveCaptureService(context)
            call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback.first))
            check(read().contentEquals(a))
            if (protected) {
                // A committed namespace write whose final private receipt was
                // lost must be recognized, not replaced again or misreported.
                val journal = File(context.filesDir.canonicalFile, "save-restores/$restore/restore.json")
                val committed = JSONObject(journal.readText())
                check(committed.getString("phase") == "published")
                committed.put("phase", "publishing")
                FileOutputStream(journal).use {
                    it.write(committed.toString().toByteArray(Charsets.UTF_8)); it.fd.sync()
                }
                close(); service = SaveCaptureService(context)
                call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback.first))
                check(read().contentEquals(a) && JSONObject(journal.readText()).getString("phase") == "published")
            }
            val restored = capture()
            val undo = stage(rollback.second.readBytes())
            call("publishRestore", mapOf("captureId" to undo, "rollbackCaptureId" to restored.first))
            check(read().contentEquals(b))
        } finally {
            watch.close()
            close()
            // Only reviewed test-owned files; unexpected content is preserved.
            if (protected) {
                val bytes = read()
                check(bytes.contentEquals(a) || bytes.contentEquals(b))
                check(file.name.matches(Regex("RShopFixture-[a-f0-9]{32}\\.sav")))
                val remove = ProcessBuilder("su", "-c", "rm -- '${MelonSaveBoundary.PROTECTED_BACKING}/${file.name}'").start()
                check(remove.waitFor() == 0)
                SaveSourceStorage.open(context, source.path).use { check(!it.exists(file.name)) }
            } else {
                check(source.list()!!.toSet() == setOf(file.name))
                check(file.delete() && source.delete())
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
            remove("save-captures", captures, setOf("capture.json", "capture.json.part", "member-0"))
            remove("save-restores", restores, setOf("restore.json", "restore.json.next", "member"))
            if (createdParent) check(parent.delete())
        }
        return "PASS MelonDualDS 0.8.0.rc2 ${if (protected) "root-assisted standard protected" else "shared"} mapping: open writer/mutation rejected, read-only descriptor admitted, exact-file watch registration/publication and joined shutdown, app-UID capture/digest, exact format/directory replay rejection, changed-local rejection, stopped-runtime service-recreation restore, retained-byte rollback, exclusive fixture cleanup; no emulator configuration/gameplay/Drive/ROM access"
    }
}
