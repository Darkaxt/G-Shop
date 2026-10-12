package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Exclusive mock save-folder bytes. Never touches a real Memory Stick, ROM,
 * emulator setting or Drive object. Save-content loading is not an acceptance gate. */
internal object PpssppSavedataCaptureProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        fun id() = UUID.randomUUID().toString().replace("-", "")
        @Suppress("DEPRECATION")
        val runtime = context.packageManager.getPackageInfo(PpssppSaveSettings.PACKAGE, 0)
        val fixture = "/data/media/0/Android/data/org.ppsspp.ppsspp/files/RShopFixture-${id()}"
        check(fixture.matches(Regex("/data/media/0/Android/data/org\\.ppsspp\\.ppsspp/files/RShopFixture-[a-f0-9]{32}")))
        val source = fixture.replace("/data/media/0/", "/storage/emulated/0/") + "/PSP/SAVEDATA/ULUS00000DATA00"
        val backing = SaveSourceStorage.backingDirectory(source)
        fun shell(command: String, bytes: ByteArray? = null) {
            val child = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
            child.outputStream.use { if (bytes != null) it.write(bytes) }
            child.inputStream.use { input -> val buffer = ByteArray(1024); while (input.read(buffer) >= 0) {} }
            check(child.waitFor() == 0)
        }
        val uid = runtime.applicationInfo!!.uid
        shell("mkdir '$fixture' && mkdir '$fixture/PSP' && mkdir '$fixture/PSP/SAVEDATA' && mkdir '$backing' && " +
            "chown $uid:$uid '$fixture' '$fixture/PSP' '$fixture/PSP/SAVEDATA' '$backing' && " +
            "chmod 700 '$fixture' '$fixture/PSP' '$fixture/PSP/SAVEDATA' '$backing'")
        val data = linkedMapOf("PARAM.SFO" to ByteArray(31) { it.toByte() },
            "CUSTOM.SAV" to ByteArray(131073) { (it + 17).toByte() },
            "ICON0.PNG" to ByteArray(37) { (it + 33).toByte() }, "EMPTY" to byteArrayOf())
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val captures = mutableListOf<String>()
        val stagedGroups = mutableMapOf<String, Set<String>>()
        val additionalGroups = mutableMapOf<String, Set<String>>()
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
            done.await(); check(error == expected) { "$method: $error (expected $expected)" }; return value
        }
        fun capture(captureId: String): Map<String, Any> {
            @Suppress("UNCHECKED_CAST")
            return call("capturePpssppSavedata", mapOf("captureId" to captureId, "directory" to source)) as Map<String, Any>
        }
        try {
            for ((name, bytes) in data) shell("/system/bin/cat > '$backing/$name'", bytes)
            check(call("ppssppSavedataFolders", mapOf("directory" to source.substringBeforeLast('/'))) ==
                listOf("ULUS00000DATA00"))
            SaveSourceStorage.open(context, source).use { storage ->
                check(storage.rootAssisted)
                storage.verifyEmulatorClosed(context)
                check(storage.names() == data.keys.sorted())
                storage.beginPpssppSavedataSnapshot()
                shell("/system/bin/cat > '$backing/EMPTY'", byteArrayOf(7))
                try { storage.verifyPpssppSavedataSnapshot(); error("Group mutation was not rejected") }
                catch (error: java.io.IOException) { check(error.message == "source_changed") }
            }
            shell("/system/bin/cat > '$backing/EMPTY'", byteArrayOf())
            val captureId = id().also(captures::add)
            val receipt = capture(captureId)
            @Suppress("UNCHECKED_CAST") val members = receipt["files"] as List<Map<String, Any>>
            check(members.map { it["name"] } == data.keys.sorted())
            for (member in members) {
                val bytes = data[member["name"]]!!
                check(member["size"] == bytes.size.toLong() && member["sha256"] == digest(bytes))
                check(File(member["path"] as String).readBytes().contentEquals(bytes))
            }
            close(); service = SaveCaptureService(context)
            check(capture(captureId) == receipt) // Durable complete group after service recreation.
            call("capturePpsspp", mapOf("captureId" to id().also(captures::add),
                "directory" to source, "name" to "ULUS00000_1.00_0.ppst"), "invalid_selection")
            call("capturePpssppSavedata", mapOf("captureId" to id().also(captures::add),
                "directory" to source.replace("/PSP/SAVEDATA/ULUS00000DATA00", "/PSP/PPSSPP_STATE")), "invalid_selection")
            @Suppress("UNCHECKED_CAST")
            val missing = call("capturePpssppSavedata", mapOf("captureId" to id().also(captures::add),
                "directory" to "${source.substringBeforeLast('/')}/ULUS00000MISSING", "restoreBaseline" to true)) as Map<String, Any>
            check(missing["localWasAbsent"] == true && missing["savedataGroupPresent"] == false &&
                (missing["files"] as List<*>).isEmpty() && (missing["sourceIdentity"] as List<*>).size == 2)

            val writer = ProcessBuilder("su", uid.toString(), "-c", "/system/bin/cat").redirectErrorStream(true).start()
            try {
                writer.outputStream.write("rshop-save-group-writer\n".toByteArray()); writer.outputStream.flush()
                check(writer.inputStream.bufferedReader().readLine() == "rshop-save-group-writer")
                call("capturePpssppSavedata", mapOf("captureId" to id().also(captures::add),
                    "directory" to source), "stop_ppsspp_required")
            } finally {
                writer.outputStream.close()
                writer.inputStream.use { input -> val buffer = ByteArray(1024); while (input.read(buffer) >= 0) {} }
                check(writer.waitFor() == 0)
            }
            shell("mkdir '$backing/nested'")
            try {
                call("capturePpssppSavedata", mapOf("captureId" to id().also(captures::add),
                    "directory" to source), "capture_unavailable")
            } finally { shell("rmdir '$backing/nested'") }

            // Exercise the real root-backed same-filesystem publication, not a
            // leaf-by-leaf approximation: membership changes are one rename.
            val stage = ".rshop-save-group-${id()}"
            val replacement = linkedMapOf("PARAM.SFO" to byteArrayOf(41, 42), "NEW.DAT" to byteArrayOf())
            val parentPath = source.substringBeforeLast('/')
            @Suppress("DEPRECATION")
            val version = if (android.os.Build.VERSION.SDK_INT >= 28) runtime.longVersionCode else runtime.versionCode.toLong()
            stagedGroups[stage] = replacement.keys
            SaveSourceStorage.open(context, parentPath).use { storage ->
                storage.verifyEmulatorClosed(context)
                val previous = storage.openSaveGroup("ULUS00000DATA00")
                val previousIdentity = storage.identity(previous)
                storage.closeFile(previous)
                val next = storage.openSaveGroup(stage, createExclusive = true)
                try {
                    for ((name, bytes) in replacement) {
                        val fd = storage.openSaveGroupFile(next, name, true, true)
                        try {
                            if (bytes.isNotEmpty()) storage.write(fd, 0, bytes)
                            storage.sync(fd)
                        } finally { storage.closeFile(fd) }
                    }
                    storage.sync(next)
                    val nextIdentity = storage.identity(next)
                    val changed = previousIdentity.clone().also { it[2]++ }
                    try {
                        storage.publishSaveGroup(stage, "ULUS00000DATA00", nextIdentity, changed, version)
                        error("Changed directory baseline was not rejected")
                    } catch (error: java.io.IOException) { check(error.message == "owned_storage:${android.system.OsConstants.ESTALE}") }
                    check(storage.names() == listOf("ULUS00000DATA00")) // Owned stage isn't a game save.
                    check(storage.publishSaveGroup(stage, "ULUS00000DATA00", nextIdentity, previousIdentity, version)
                        .contentEquals(nextIdentity))
                    stagedGroups[stage] = data.keys
                } finally { storage.closeFile(next) }
                fun verify(name: String, expected: Map<String, ByteArray>, anchor: LongArray? = null): LongArray {
                    val group = storage.openSaveGroup(name, anchor = anchor)
                    try {
                        check(storage.saveGroupNames(group) == expected.keys.sorted())
                        for ((leaf, bytes) in expected) {
                            val fd = storage.openSaveGroupFile(group, leaf, false, false)
                            try {
                                check(storage.identity(fd)[2] == bytes.size.toLong())
                                val actual = java.io.ByteArrayOutputStream()
                                var offset = 0L
                                while (offset < bytes.size) {
                                    val chunk = storage.read(fd, offset, minOf(65536L, bytes.size - offset).toInt())
                                    check(chunk.isNotEmpty()); actual.write(chunk); offset += chunk.size
                                }
                                check(actual.toByteArray().contentEquals(bytes))
                            } finally { storage.closeFile(fd) }
                        }
                        return storage.identity(group)
                    } finally { storage.closeFile(group) }
                }
                val placed = verify("ULUS00000DATA00", replacement)
                val rollback = verify(stage, data, previousIdentity)
                // Reopen the exact retained group and atomically roll back.
                val old = storage.openSaveGroup(stage, anchor = rollback)
                try { storage.publishSaveGroup(stage, "ULUS00000DATA00", rollback, placed, version) }
                finally { storage.closeFile(old) }
                stagedGroups[stage] = replacement.keys
                verify("ULUS00000DATA00", data)

                val firstStage = ".rshop-save-group-${id()}"
                stagedGroups[firstStage] = replacement.keys
                val first = storage.openSaveGroup(firstStage, createExclusive = true)
                try {
                    for ((leaf, bytes) in replacement) {
                        val fd = storage.openSaveGroupFile(first, leaf, true, true)
                        try {
                            if (bytes.isNotEmpty()) storage.write(fd, 0, bytes)
                            storage.sync(fd)
                        } finally { storage.closeFile(fd) }
                    }
                    storage.sync(first)
                    val firstIdentity = storage.identity(first)
                    try {
                        storage.publishSaveGroup(firstStage, "ULUS00000DATA00", firstIdentity, null, version)
                        error("First publication replaced an existing save folder")
                    } catch (error: java.io.IOException) { check(error.message == "owned_storage:${android.system.OsConstants.EEXIST}") }
                    verify("ULUS00000DATA00", data)
                    additionalGroups["ULUS00000MISSING"] = replacement.keys
                    check(storage.publishSaveGroup(firstStage, "ULUS00000MISSING", firstIdentity, null, version)
                        .contentEquals(firstIdentity))
                    stagedGroups.remove(firstStage)
                    verify("ULUS00000MISSING", replacement)
                } finally { storage.closeFile(first) }
            }
        } finally {
            try {
                for (capture in captures) call("retireCapture", mapOf("captureId" to capture))
            } finally {
                close()
                for ((stage, members) in stagedGroups) {
                    check(PpssppSavedataBoundary.validStage(stage))
                    for (member in members) shell("if [ -f '$fixture/PSP/SAVEDATA/$stage/$member' ]; then rm '$fixture/PSP/SAVEDATA/$stage/$member'; fi")
                    shell("if [ -d '$fixture/PSP/SAVEDATA/$stage' ]; then rmdir '$fixture/PSP/SAVEDATA/$stage'; fi")
                }
                for ((group, members) in additionalGroups) {
                    check(PpssppSavedataBoundary.validMember(group))
                    for (member in members) shell("if [ -f '$fixture/PSP/SAVEDATA/$group/$member' ]; then rm '$fixture/PSP/SAVEDATA/$group/$member'; fi")
                    shell("if [ -d '$fixture/PSP/SAVEDATA/$group' ]; then rmdir '$fixture/PSP/SAVEDATA/$group'; fi")
                }
                for (name in data.keys) shell("rm '$backing/$name'")
                shell("rmdir '$backing' && rmdir '$fixture/PSP/SAVEDATA' && rmdir '$fixture/PSP' && rmdir '$fixture'")
            }
        }
        return "PASS complete protected PPSSPP SAVEDATA folder: streamed capture including empty companion, mutation/runtime checks, absent-folder baseline and recreated-service replay; root-backed atomic membership-changing publication, changed-baseline refusal and complete rollback; first-folder publication and existing-folder refusal; exact fixture/capture retirement; no real save/ROM/settings/Drive mutation"
    }
}
