package com.retro.rshop

import android.content.Context
import android.content.pm.ApplicationInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Exclusive emulator-external-files fixture; no real Memory Stick or cloud IO. */
internal object PpssppProtectedSaveProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        @Suppress("DEPRECATION")
        val runtime = context.packageManager.getPackageInfo(PpssppSaveSettings.PACKAGE, 0)
        check(runtime.versionName in setOf("1.20.4", "v1.20.4"))
        check(runtime.applicationInfo!!.flags and ApplicationInfo.FLAG_STOPPED != 0)
        fun id() = UUID.randomUUID().toString().replace("-", "")
        val leaf = "RShopFixture-${id()}"
        val source = "/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/$leaf/PSP/PPSSPP_STATE"
        val backing = SaveSourceStorage.backingDirectory(source)
        val fixture = backing.removeSuffix("/PSP/PPSSPP_STATE")
        check(fixture.matches(Regex("/data/media/0/Android/data/org\\.ppsspp\\.ppsspp/files/RShopFixture-[a-f0-9]{32}")))
        fun shell(command: String) {
            val child = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
            child.outputStream.close()
            child.inputStream.use { input -> val bytes = ByteArray(1024); while (input.read(bytes) >= 0) {} }
            check(child.waitFor() == 0)
        }
        val uid = runtime.applicationInfo!!.uid
        shell("mkdir '$fixture' && mkdir '$fixture/PSP' && mkdir '$backing' && " +
            "chown $uid:$uid '$fixture' '$fixture/PSP' '$backing' && chmod 700 '$fixture' '$fixture/PSP' '$backing'")
        val name = "ULUS00000_1.00_0.ppst"
        val a = ByteArray(131073) { (it + 17).toByte() }
        val b = ByteArray(a.size) { (it + 57).toByte() }
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val captures = mutableListOf<String>()
        val restores = mutableListOf<String>()
        val stages = mutableListOf<String>()
        var service = SaveCaptureService(context)
        val watched = CountDownLatch(1)
        val events = mutableListOf<String>()
        var watchFailed = false
        val watch = SaveFileWatch(context, unavailable = { watchFailed = true }) { key ->
            synchronized(events) { events.add(key) }; watched.countDown()
        }
        fun closeService() { val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await() }
        fun call(method: String, args: Map<String, Any>, expected: String? = null): Any? {
            val done = CountDownLatch(1)
            var value: Any? = null
            var error: String? = null
            service.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                override fun notImplemented() { error = "not_implemented"; done.countDown() }
            })
            done.await(); check(error == expected) { "$method: $error (expected $expected)" }; return value
        }
        fun read(): ByteArray = SaveSourceStorage.open(context, source).use { storage ->
            check(storage.rootAssisted)
            val fd = storage.openFile(name, false, false)
            try {
                check(storage.identity(fd)[2] == a.size.toLong())
                ByteArray(a.size).also { bytes ->
                    var offset = 0
                    while (offset < bytes.size) {
                        val chunk = storage.read(fd, offset.toLong(), minOf(65536, bytes.size - offset))
                        check(chunk.isNotEmpty()); chunk.copyInto(bytes, offset); offset += chunk.size
                    }
                }
            } finally { storage.closeFile(fd) }
        }
        fun write(bytes: ByteArray) = SaveSourceStorage.open(context, source).use { storage ->
            val old = if (storage.exists(name)) storage.entryIdentity(name) else null
            val stage = ".rshop-save-restore-${id()}".also(stages::add)
            val fd = storage.openFile(stage, true, true)
            val placed = try {
                var offset = 0
                while (offset < bytes.size) {
                    val end = minOf(bytes.size, offset + 65536)
                    storage.write(fd, offset.toLong(), bytes.copyOfRange(offset, end)); offset = end
                }
                storage.sync(fd); storage.identity(fd)
            } finally { storage.closeFile(fd) }
            if (old == null) storage.renameNoReplace(stage, name) else storage.replace(stage, name, placed, old)
            storage.sync(storage.root)
        }
        fun capture(): Pair<String, ByteArray> {
            val capture = id().also(captures::add)
            @Suppress("UNCHECKED_CAST")
            val receipt = call("capturePpsspp", mapOf("captureId" to capture,
                "directory" to source, "name" to name)) as Map<String, Any>
            @Suppress("UNCHECKED_CAST") val member = (receipt["files"] as List<Map<String, Any>>).single()
            val bytes = File(member["path"] as String).readBytes()
            check(member["name"] == name && member["size"] == bytes.size.toLong() &&
                member["sha256"] == digest(bytes) && bytes.contentEquals(read()))
            return capture to bytes
        }
        fun stage(bytes: ByteArray): String {
            val restore = id().also(restores::add)
            call("beginRestore", mapOf("captureId" to restore, "name" to name,
                "ppssppDirectory" to source, "size" to bytes.size.toLong(), "sha256" to digest(bytes)))
            var offset = 0
            while (offset < bytes.size) {
                val end = minOf(bytes.size, offset + 65536)
                check(call("appendRestore", mapOf("captureId" to restore, "offset" to offset.toLong(),
                    "bytes" to bytes.copyOfRange(offset, end))) == end.toLong()); offset = end
            }
            call("sealRestore", mapOf("captureId" to restore)); return restore
        }
        try {
            val key = "c".repeat(64)
            check(watch.replace(listOf(SaveFileWatch.Mapping(key, source, name),
                SaveFileWatch.Mapping("d".repeat(64), source, "ULUS00000_1.00_1.ppst"))) ==
                listOf(key, "d".repeat(64)))
            write(a); watched.await(); watch.close()
            check(!watchFailed); synchronized(events) { check(events.isNotEmpty() && events.all { it == key }) }
            check(call("ppssppNames", mapOf("directory" to source)) == listOf(name))
            val original = capture()
            write(b); val rollback = capture(); val restore = stage(original.second)
            write(a)
            call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback.first), "source_changed")
            check(read().contentEquals(a)); write(b)
            // A test-owned process runs under the emulator UID without starting
            // PPSSPP or changing its stopped flag/settings. Kernel UID evidence
            // must reject restore even when Android still says stopped=true.
            val uidProcess = ProcessBuilder("su", uid.toString(), "-c", "/system/bin/cat").start()
            val diagnostics = Thread({ uidProcess.errorStream.use { stream ->
                val buffer = ByteArray(1024); while (stream.read(buffer) >= 0) {}
            } }, "rshop-uid-fixture-stderr").apply { start() }
            try {
                uidProcess.outputStream.write("rshop-owned-uid-process\n".toByteArray())
                uidProcess.outputStream.flush()
                check(uidProcess.inputStream.bufferedReader().readLine() == "rshop-owned-uid-process")
                check(context.packageManager.getApplicationInfo(PpssppSaveSettings.PACKAGE, 0)
                    .flags and ApplicationInfo.FLAG_STOPPED != 0)
                call("publishRestore", mapOf("captureId" to restore,
                    "rollbackCaptureId" to rollback.first), "stop_ppsspp_required")
                check(read().contentEquals(b))
            } finally {
                uidProcess.outputStream.close(); uidProcess.inputStream.close()
                check(uidProcess.waitFor() == 0); diagnostics.join()
            }
            closeService(); service = SaveCaptureService(context)
            call("publishRestore", mapOf("captureId" to restore, "rollbackCaptureId" to rollback.first))
            check(read().contentEquals(a))
            val restored = capture(); val undo = stage(rollback.second)
            call("publishRestore", mapOf("captureId" to undo, "rollbackCaptureId" to restored.first))
            check(read().contentEquals(b))
        } finally {
            watch.close(); closeService()
            // Exact generated names only; rmdir refuses unexpected content.
            val allowed = listOf(name) + stages + restores.map { ".rshop-save-restore-$it" }
            allowed.forEach { shell("if [ -e '$backing/$it' ]; then rm -- '$backing/$it'; fi") }
            shell("rmdir -- '$backing' '$fixture/PSP' '$fixture'")
            for ((root, ids, allowedFiles) in listOf(
                Triple("save-captures", captures, setOf("capture.json", "capture.json.part", "member-0")),
                Triple("save-restores", restores, setOf("restore.json", "restore.json.next", "member")))) {
                for (owned in ids) {
                    val directory = File(context.filesDir.canonicalFile, "$root/$owned")
                    if (!directory.exists()) continue
                    check(directory.canonicalFile == directory.absoluteFile)
                    val files = directory.listFiles()!!
                    check(files.all { it.name in allowedFiles && it.isFile && it.canonicalFile == it.absoluteFile })
                    files.forEach { check(it.delete()) }; check(directory.delete())
                }
            }
        }
        return "PASS PPSSPP protected external-files app-UID/root listing, streamed capture/digest, exact publication watch, joined shutdown, real emulator-UID process refusal despite stopped=true, process-exit/recreated-service atomic restore, changed-local refusal and retained rollback; exclusive fixture removed; no emulator settings/real saves/ROM/cloud mutation"
    }
}
