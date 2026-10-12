package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

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
        val restores = mutableSetOf<String>()
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
        fun observedChange(directory: String = source, action: () -> Unit) {
            val changed = CountDownLatch(1)
            val unavailable = AtomicBoolean(false)
            val mapping = SaveFileWatch.Mapping("d".repeat(64), directory,
                directory.substringAfterLast('/'), "ppsspp-savedata")
            val watch = SaveRootWatch(context, listOf(mapping), { key ->
                check(key == mapping.key); changed.countDown()
            }, { unavailable.set(true); changed.countDown() })
            try {
                action(); changed.await(); check(!unavailable.get())
            } finally { watch.close() }
        }
        try {
            for ((name, bytes) in data) shell("/system/bin/cat > '$backing/$name'", bytes)
            observedChange { shell("/system/bin/cat > '$backing/CUSTOM.SAV'", data["CUSTOM.SAV"]!!) }
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

            // The same channel used by cloud restore must preserve the complete
            // group across service recreation, not just expose a rename primitive.
            fun stageRestore(target: String, bytes: Map<String, ByteArray>): String {
                val restore = id().also(restores::add)
                stagedGroups[".rshop-save-group-$restore"] = data.keys + bytes.keys
                val ordered = bytes.toSortedMap()
                for (index in ordered.keys.indices)
                    restores.add(digest("$restore/$index".toByteArray()).take(32))
                call("beginRestoreGroup", mapOf("captureId" to restore, "name" to target.substringAfterLast('/'),
                    "ppssppSavedataDirectory" to target, "members" to ordered.map { (leaf, payload) ->
                        mapOf("name" to leaf, "size" to payload.size.toLong(), "sha256" to digest(payload)) }))
                for ((index, payload) in ordered.values.withIndex()) {
                    var offset = 0
                    while (offset < payload.size) {
                        val end = minOf(offset + 65536, payload.size)
                        check(call("appendRestoreGroup", mapOf("captureId" to restore, "member" to index,
                            "offset" to offset.toLong(), "bytes" to payload.copyOfRange(offset, end))) == end.toLong())
                        offset = end
                    }
                }
                call("sealRestoreGroup", mapOf("captureId" to restore))
                return restore
            }
            fun verifyFolder(target: String, bytes: Map<String, ByteArray>) {
                SaveSourceStorage.open(context, target).use { storage ->
                    check(storage.names() == bytes.keys.sorted())
                    for ((leaf, payload) in bytes) {
                        val file = storage.openFile(leaf, false, false)
                        try {
                            check(storage.identity(file)[2] == payload.size.toLong())
                            val observed = MessageDigest.getInstance("SHA-256")
                            var offset = 0L
                            while (offset < payload.size) {
                                val chunk = storage.read(file, offset, minOf(65536L, payload.size - offset).toInt())
                                check(chunk.isNotEmpty()); observed.update(chunk); offset += chunk.size
                            }
                            check(observed.digest().contentEquals(MessageDigest.getInstance("SHA-256").digest(payload)))
                        } finally { storage.closeFile(file) }
                    }
                }
            }
            val nextBytes = linkedMapOf("PARAM.SFO" to byteArrayOf(19, 20), "NEW.DAT" to byteArrayOf())
            val restore = stageRestore(source, nextBytes)
            close(); service = SaveCaptureService(context)
            observedChange {
                call("publishRestoreGroup", mapOf("captureId" to restore, "rollbackCaptureId" to captureId))
            }
            verifyFolder(source, nextBytes)
            close(); service = SaveCaptureService(context)
            call("publishRestoreGroup", mapOf("captureId" to restore, "rollbackCaptureId" to captureId))
            verifyFolder(source, nextBytes)
            val newBaseline = capture(id().also(captures::add))
            val undo = stageRestore(source, data)
            call("publishRestoreGroup", mapOf("captureId" to undo, "rollbackCaptureId" to newBaseline["captureId"]!!))
            verifyFolder(source, data)
            shell("test -z \"\$(find '$fixture/PSP/SAVEDATA' -maxdepth 1 -name '.rshop-save-group-$restore' -print)\"")

            val changedBaseline = capture(id().also(captures::add))
            val rejected = stageRestore(source, nextBytes)
            val changed = data.toMutableMap().also { it["PARAM.SFO"] = ByteArray(31) { 99 } }
            shell("/system/bin/cat > '$backing/PARAM.SFO'", changed["PARAM.SFO"])
            call("publishRestoreGroup", mapOf("captureId" to rejected, "rollbackCaptureId" to changedBaseline["captureId"]!!), "source_changed")
            verifyFolder(source, changed)
            shell("/system/bin/cat > '$backing/PARAM.SFO'", data["PARAM.SFO"])

            val firstTarget = "${source.substringBeforeLast('/')}/ULUS00000JOURNAL"
            @Suppress("UNCHECKED_CAST")
            val firstBaseline = call("capturePpssppSavedata", mapOf("captureId" to id().also(captures::add),
                "directory" to firstTarget, "restoreBaseline" to true)) as Map<String, Any>
            val firstRestore = stageRestore(firstTarget, nextBytes)
            additionalGroups[firstTarget.substringAfterLast('/')] = nextBytes.keys
            close(); service = SaveCaptureService(context)
            observedChange(firstTarget) {
                call("publishRestoreGroup", mapOf("captureId" to firstRestore, "rollbackCaptureId" to firstBaseline["captureId"]!!))
            }
            verifyFolder(firstTarget, nextBytes)

            fun journal(restoreId: String, values: JSONObject) {
                val file = File(context.filesDir.canonicalFile, "save-restores/$restoreId/group.json")
                FileOutputStream(file).use { it.write(values.toString().toByteArray()); it.fd.sync() }
                val parent = OwnedStorageNative.openRoot(file.parentFile!!.absolutePath)
                try { OwnedStorageNative.sync(parent) } finally { OwnedStorageNative.close(parent) }
            }
            val recoveryBaseline = capture(id().also(captures::add))
            val recovery = stageRestore(source, nextBytes)
            val recoveryStage = ".rshop-save-group-$recovery"
            val recoveryRecord = JSONObject(File(context.filesDir.canonicalFile, "save-restores/$recovery/group.json").readText())
                .put("rollbackId", recoveryBaseline["captureId"]!!)
            SaveSourceStorage.open(context, source.substringBeforeLast('/')).use { storage ->
                val current = storage.openSaveGroup(source.substringAfterLast('/'))
                val currentIdentity = try { storage.identity(current) } finally { storage.closeFile(current) }
                val next = storage.openSaveGroup(recoveryStage, createExclusive = true)
                try {
                    for ((leaf, payload) in nextBytes) {
                        val file = storage.openSaveGroupFile(next, leaf, true, true)
                        try {
                            if (payload.isNotEmpty()) storage.write(file, 0, payload)
                            storage.sync(file)
                        } finally { storage.closeFile(file) }
                    }
                    storage.sync(next)
                    val staged = storage.identity(next)
                    journal(recovery, recoveryRecord.put("parent", JSONArray(storage.identity(storage.root).take(2)))
                        .put("current", JSONArray(currentIdentity.toList())).put("stageAnchor", JSONArray(staged.toList()))
                        .put("staged", JSONArray(staged.toList())).put("phase", "publishing"))
                    storage.publishSaveGroup(recoveryStage, source.substringAfterLast('/'), staged, currentIdentity, version)
                    // No journal receipt: actual namespace commit preceded process loss.
                } finally { storage.closeFile(next) }
            }
            close(); service = SaveCaptureService(context)
            call("publishRestoreGroup", mapOf("captureId" to recovery, "rollbackCaptureId" to recoveryBaseline["captureId"]!!))
            verifyFolder(source, nextBytes)
            check(JSONObject(File(context.filesDir.canonicalFile, "save-restores/$recovery/group.json").readText()).getString("phase") == "published")

            val allocatedBaseline = capture(id().also(captures::add))
            val allocated = stageRestore(source, data)
            val allocatedRecord = JSONObject(File(context.filesDir.canonicalFile, "save-restores/$allocated/group.json").readText())
                .put("rollbackId", allocatedBaseline["captureId"]!!).put("phase", "staging")
            SaveSourceStorage.open(context, source.substringBeforeLast('/')).use { storage ->
                journal(allocated, allocatedRecord.put("parent", JSONArray(storage.identity(storage.root).take(2))))
                val empty = storage.openSaveGroup(".rshop-save-group-$allocated", createExclusive = true)
                storage.closeFile(empty) // No inode receipt: recover only this exact empty allocation.
            }
            close(); service = SaveCaptureService(context)
            call("publishRestoreGroup", mapOf("captureId" to allocated, "rollbackCaptureId" to allocatedBaseline["captureId"]!!))
            verifyFolder(source, data)
            for (restored in listOf(restore, undo, firstRestore, recovery, allocated))
                shell("test ! -e '$fixture/PSP/SAVEDATA/.rshop-save-group-$restored'")
        } finally {
            try {
                for (capture in captures) call("retireCapture", mapOf("captureId" to capture))
            } finally {
                close()
                for (restore in restores) {
                    val directory = File(context.filesDir.canonicalFile, "save-restores/$restore")
                    if (directory.exists()) {
                        val entries = directory.listFiles()!!
                        check(entries.all { it.isFile && it.name in setOf("member", "restore.json", "restore.json.next", "group.json", "group.json.next") })
                        entries.forEach { check(it.delete()) }; check(directory.delete())
                    }
                }
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
                for (name in data.keys + "NEW.DAT") shell("if [ -f '$backing/$name' ]; then rm '$backing/$name'; fi")
                shell("rmdir '$backing' && rmdir '$fixture/PSP/SAVEDATA' && rmdir '$fixture/PSP' && rmdir '$fixture'")
            }
        }
        return "PASS complete protected PPSSPP SAVEDATA capture and journaled restore: root member/folder-replacement/first-folder watch delivery and joined shutdown; streamed empty companions; mutation/runtime refusal; recreated-service publication/replay and rollback; changed-local refusal; first-folder restore; recovery after actual atomic commit without receipt and empty allocation without inode receipt; exact exchanged-stage/fixture/capture retirement; no real save/ROM/settings/Drive mutation"
    }
}
