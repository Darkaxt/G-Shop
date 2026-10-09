package com.retro.rshop

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.system.Os
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.security.MessageDigest
import java.util.concurrent.Executors

/** One cancellable capture at a time. No emulator termination, guessed sleeps,
 * storage bypass or automatic source scan. Explicit mGBA SRAM/RTC and published
 * PPSSPP state slots cross into app-private, durably sealed staging. */
internal class SaveCaptureService(private val activity: Activity) {
    companion object {
        // Normalize only the framework-owned parent. Capture IDs and members
        // remain no-follow, canonical-equality checked descendants of this root.
        internal fun stagingRoot(filesDir: File): File = File(filesDir.canonicalFile, "save-captures")
        private const val MGBA_SOURCE = "/storage/emulated/0/RetroArch/saves/mGBA"
        internal fun validRestoreBinding(name: String, size: Long, format: String, source: String): Boolean =
            when (format) {
                "mgba-battery" -> source == MGBA_SOURCE && RetroArchSaveBoundary.validName(name) &&
                    size in 1..(16L * 1024 * 1024)
                "ppsspp-slot-v1" -> PpssppSaveBoundary.validDirectory(source) &&
                    PpssppSaveBoundary.validName(name) && size in 1..PpssppSaveBoundary.MAX_STATE_BYTES
                else -> false
            }
    }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val root = stagingRoot(activity.filesDir)
    private val restores = File(activity.filesDir.canonicalFile, "save-restores")
    private val source = MGBA_SOURCE
    private val guard = Any()
    private var active: String? = null
    private var socket: DatagramSocket? = null
    private var cancelled = false
    private var closed = false
    private class Failure(val code: String) : Exception()
    private fun check() = synchronized(guard) {
        if (cancelled || closed) throw Failure("cancelled")
    }
    private fun id(call: MethodCall): String = (call.argument<String>("captureId") ?: "").also {
        if (!it.matches(Regex("[a-f0-9]{32}"))) throw Failure("invalid_capture")
    }
    private fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }
    private fun same(a: LongArray, b: LongArray) = a.contentEquals(b)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "cancel") {
                val requested = id(call)
                synchronized(guard) {
                    if (active == requested) { cancelled = true; socket?.close() }
                }
                result.success(null)
                return
            }
            if (call.method == "openPpssppAppInfo") {
                // User-mediated Android settings only. Never stop another app
                // ourselves or mistake background/paused for writer completion.
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:org.ppsspp.ppsspp")))
                result.success(null)
                return
            }
            if (call.method == "openRetroArch" || call.method == "openPpsspp") {
                val emulator = if (call.method == "openPpsspp") "org.ppsspp.ppsspp" else "com.retroarch.aarch64"
                val intent = activity.packageManager.getLaunchIntentForPackage(emulator)
                    ?: throw Failure("emulator_missing")
                // Explicit user action only. No ROM extras, close/quit command,
                // account selection or settings mutation.
                activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                result.success(null)
                return
            }
            val captureId = if (call.method !in setOf("retroArchNames", "ppssppNames")) id(call) else null
            synchronized(guard) {
                if (closed) throw Failure("closed")
                if (active != null) throw Failure("capture_busy")
                active = captureId ?: "listing"
                cancelled = false
            }
            worker.execute {
                val complete: () -> Unit = try {
                    val value = when (call.method) {
                        "retroArchNames" -> names()
                        "ppssppNames" -> ppssppNames(call.argument<String>("directory") ?: "")
                        "captureRetroArch" -> capture(captureId!!,
                            call.argument<String>("name") ?: "")
                        "capturePpsspp" -> capture(captureId!!,
                            call.argument<String>("name") ?: "",
                            call.argument<String>("directory") ?: "")
                        "beginRestore" -> beginRestore(captureId!!, call)
                        "appendRestore" -> appendRestore(captureId!!, call)
                        "sealRestore" -> sealRestore(captureId!!)
                        "publishRestore" -> publishRestore(captureId!!,
                            call.argument<String>("rollbackCaptureId") ?: "")
                        else -> throw Failure("invalid_method")
                    }
                    ({ result.success(value) })
                } catch (e: Exception) {
                    if (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                        // Diagnostic boundary only: never log names, paths, save bytes
                        // or arbitrary exception messages. JNI exposes errno alone.
                        val errno = e.message?.takeIf { it.matches(Regex("owned_storage:[0-9]+")) }
                        val frames = e.stackTrace.filter { it.className.startsWith("com.retro.rshop.") }
                            .take(4).joinToString { "${it.methodName}:${it.lineNumber}" }
                        Log.w("RShopSaveCapture", "${e.javaClass.simpleName} ${errno ?: ""} $frames")
                    }
                    val code = if (synchronized(guard) { cancelled || closed }) "cancelled"
                        else if (e is Failure) e.code else "capture_unavailable"
                    ({ result.error(code, "Save capture: $code", null) })
                } finally {
                    synchronized(guard) { socket?.close(); socket = null; active = null }
                }
                // A Dart continuation can immediately send the next chunk.
                // Release the native operation BEFORE its acknowledgement,
                // never race result delivery against the worker's finally block.
                main.post { complete() }
            }
        } catch (e: Exception) {
            val code = if (e is Failure) e.code else "capture_unavailable"
            result.error(code, "Save capture: $code", null)
        }
    }

    private fun names(): List<String> {
        check()
        val entries = File(source).list() ?: throw Failure("storage_permission")
        if (entries.size > 4096) throw Failure("too_many_saves")
        return entries.filter(RetroArchSaveBoundary::validName).sorted()
    }

    private fun ppssppNames(directory: String): List<String> {
        check()
        if (!PpssppSaveBoundary.validDirectory(directory) ||
            File(directory).canonicalPath != directory) throw Failure("invalid_selection")
        val entries = File(directory).list() ?: throw Failure("storage_permission")
        if (entries.size > 4096) throw Failure("too_many_saves")
        return entries.filter(PpssppSaveBoundary::validName).sorted()
    }

    private fun contentClosed(connection: DatagramSocket) {
        check()
        val command = "GET_STATUS\n".toByteArray(Charsets.US_ASCII)
        connection.send(DatagramPacket(command, command.size))
        val reply = DatagramPacket(ByteArray(2048), 2048)
        // Indefinite protocol wait; explicit cancellation closes this exact
        // socket. Background silence never becomes success or a false failure.
        connection.receive(reply)
        check()
        if (!RetroArchSaveBoundary.contentClosed(String(reply.data, 0, reply.length, Charsets.US_ASCII))) {
            throw Failure("close_content_required")
        }
    }

    private fun captured(directory: File, name: String,
                         ppssppDirectory: String? = null): Map<String, Any>? {
        val seal = File(directory, "capture.json")
        if (!seal.exists()) return null
        if (seal.length() !in 1..16384) throw Failure("invalid_capture")
        val record = JSONObject(seal.readText())
        if (record.getString("name") != name || record.getString("captureId") != directory.name) {
            throw Failure("invalid_capture")
        }
        // A capture ID cannot be replayed against another directory or format.
        // Older mGBA journals lack these fields and retain their original binding.
        if (ppssppDirectory != null) {
            if (record.optString("format") != "ppsspp-slot-v1" ||
                record.optString("source") != ppssppDirectory) throw Failure("invalid_capture")
        } else if (record.optString("format", "mgba-battery") != "mgba-battery") {
            throw Failure("invalid_capture")
        }
        val members = record.getJSONArray("files")
        val maxMembers = if (ppssppDirectory == null) 2 else 1
        val maxSize = if (ppssppDirectory == null) 16L * 1024 * 1024 else PpssppSaveBoundary.MAX_STATE_BYTES
        if (members.length() !in 1..maxMembers) throw Failure("invalid_capture")
        val output = mutableListOf<Map<String, Any>>()
        for (i in 0 until members.length()) {
            check()
            val item = members.getJSONObject(i)
            val file = File(directory, "member-$i")
            if (item.getString("name") != name &&
                (ppssppDirectory != null || item.getString("name") != name.dropLast(4) + ".rtc")) {
                throw Failure("invalid_capture")
            }
            if (file.canonicalFile != file.absoluteFile || !file.isFile ||
                file.length() !in 1..maxSize ||
                file.length() != item.getLong("size")) throw Failure("changed_capture")
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { stream ->
                val buffer = ByteArray(65536)
                while (true) {
                    check()
                    val size = stream.read(buffer)
                    if (size < 0) break
                    digest.update(buffer, 0, size)
                }
            }
            val sum = digest.digest().joinToString("") { "%02x".format(it) }
            if (sum != item.getString("sha256")) throw Failure("changed_capture")
            output += mapOf("name" to item.getString("name"), "path" to file.absolutePath,
                "size" to item.getLong("size"), "sha256" to sum)
        }
        if (output.count { it["name"] == name } != 1 ||
            output.map { it["name"] }.toSet().size != output.size) throw Failure("invalid_capture")
        return mapOf("captureId" to directory.name, "deviceId" to record.getString("deviceId"),
            "emulatorVersion" to record.getString("emulatorVersion"), "files" to output)
    }

    private fun capture(captureId: String, name: String,
                        ppssppDirectory: String? = null): Map<String, Any> {
        val ppsspp = ppssppDirectory != null
        if (if (ppsspp) !PpssppSaveBoundary.validName(name) ||
                !PpssppSaveBoundary.validDirectory(ppssppDirectory!!)
            else !RetroArchSaveBoundary.validName(name)) throw Failure("invalid_selection")
        val sourceDirectory = ppssppDirectory ?: source
        if (File(sourceDirectory).canonicalPath != sourceDirectory) throw Failure("invalid_selection")
        val packageName = if (ppsspp) "org.ppsspp.ppsspp" else "com.retroarch.aarch64"
        @Suppress("DEPRECATION")
        val version = activity.packageManager.getPackageInfo(packageName, 0).versionName
            ?: throw Failure("emulator_missing")
        // Installed baseline investigated in S10_SAVE_BACKUP_DESIGN. Do not
        // extrapolate the writer contract to an unreviewed future runtime.
        val versions = if (ppsspp) setOf("v1.20.4", "1.20.4") else setOf("1.22.2_GIT", "1.22.2")
        if (version !in versions) throw Failure("runtime_unreviewed")
        val device = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ANDROID_ID)
            ?: throw Failure("device_identity_unavailable")
        if (!root.isDirectory && !root.mkdir()) throw Failure("capture_storage")
        if (root.canonicalFile != root.absoluteFile) throw Failure("invalid_capture")
        val directory = File(root, captureId)
        if (directory.exists() && directory.canonicalFile != directory.absoluteFile) throw Failure("invalid_capture")
        if (!directory.isDirectory && !directory.mkdir()) throw Failure("capture_storage")
        captured(directory, name, ppssppDirectory)?.let { return it }
        // Only these exact private files can be leftovers from this journaled
        // capture ID. An unexpected entry is preserved and blocks replay.
        val leftovers = directory.listFiles() ?: throw Failure("capture_storage")
        if (leftovers.any { it.name !in setOf("member-0", "member-1", "capture.json.part") ||
                it.canonicalFile != it.absoluteFile || !it.isFile }) throw Failure("invalid_capture")
        leftovers.forEach { if (!it.delete()) throw Failure("capture_storage") }

        val connection = if (ppsspp) null else synchronized(guard) {
            check(); DatagramSocket().also { socket = it }
        }
        if (connection != null) {
            connection.connect(InetAddress.getByName("127.0.0.1"), 55355)
            contentClosed(connection)
        }
        // PPSSPP SaveSlot publishes .ppst only after closing its .tmp writer.
        // Holding the opened no-follow descriptor captures that complete inode;
        // changing the selected entry or inode before sealing rejects the copy.
        // This does not authorize writes/restores while PPSSPP is running.
        val sourceDir = OwnedStorageNative.openRoot(sourceDirectory)
        val stageDir = try { OwnedStorageNative.openRoot(directory.absolutePath) }
            catch (e: Exception) { OwnedStorageNative.close(sourceDir); throw e }
        val fds = mutableListOf<Int>()
        try {
            val selected = mutableListOf(name)
            val rtc = name.dropLast(4) + ".rtc"
            if (!ppsspp && File(sourceDirectory, rtc).exists()) selected += rtc
            for (member in selected) fds += OwnedStorageNative.openFile(sourceDir, member, false, false)
            val identities = fds.map(OwnedStorageNative::identity)
            val maxSize = if (ppsspp) PpssppSaveBoundary.MAX_STATE_BYTES else 16L * 1024 * 1024
            if (identities.any { it[2] !in 1..maxSize }) throw Failure("invalid_save_size")
            val members = JSONArray()
            for (i in fds.indices) {
                check()
                val target = OwnedStorageNative.openFile(stageDir, "member-$i", true, true)
                try {
                    val digest = MessageDigest.getInstance("SHA-256")
                    var offset = 0L
                    while (offset < identities[i][2]) {
                        check()
                        val bytes = OwnedStorageNative.read(fds[i], offset,
                            minOf(65536L, identities[i][2] - offset).toInt())
                        if (bytes.isEmpty()) throw Failure("source_changed")
                        digest.update(bytes)
                        OwnedStorageNative.write(target, offset, bytes)
                        offset += bytes.size
                    }
                    OwnedStorageNative.sync(target)
                    members.put(JSONObject().put("name", selected[i]).put("size", offset)
                        .put("sha256", digest.digest().joinToString("") { "%02x".format(it) }))
                } finally { OwnedStorageNative.close(target) }
            }
            if (connection != null) contentClosed(connection)
            // Compare the complete group after all copies, including the RTC
            // existence assertion. A changed/replaced source never gets a seal.
            if (!ppsspp && File(sourceDirectory, rtc).exists() != selected.contains(rtc)) throw Failure("source_changed")
            for (i in fds.indices) {
                if (!same(identities[i], OwnedStorageNative.identity(fds[i])) ||
                    !same(identities[i], OwnedStorageNative.entryIdentity(sourceDir, selected[i]))) {
                    throw Failure("source_changed")
                }
            }
            val currentDir = OwnedStorageNative.openRoot(sourceDirectory)
            try {
                // Reconcile the selected path with the pinned source root,
                // after any protocol wait as well as the complete copy.
                if (OwnedStorageNative.identity(currentDir).take(2) !=
                    OwnedStorageNative.identity(sourceDir).take(2)) throw Failure("source_changed")
            } finally { OwnedStorageNative.close(currentDir) }
            check()
            val record = JSONObject().put("captureId", captureId).put("name", name)
                .put("deviceId", hash(device.toByteArray(Charsets.UTF_8)))
                .put("emulatorVersion", version).put("files", members)
                .put("format", if (ppsspp) "ppsspp-slot-v1" else "mgba-battery")
            if (ppsspp) record.put("source", sourceDirectory)
            val part = File(directory, "capture.json.part")
            FileOutputStream(part).use { it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
            OwnedStorageNative.renameNoReplace(stageDir, part.name, stageDir, "capture.json")
            OwnedStorageNative.sync(stageDir)
            return captured(directory, name, ppssppDirectory) ?: throw Failure("capture_storage")
        } finally {
            fds.forEach(OwnedStorageNative::close)
            OwnedStorageNative.close(stageDir)
            OwnedStorageNative.close(sourceDir)
        }
    }

    private fun restoreDirectory(id: String): File {
        if (!id.matches(Regex("[a-f0-9]{32}"))) throw Failure("invalid_restore")
        if (!restores.isDirectory && !restores.mkdir()) throw Failure("capture_storage")
        if (restores.canonicalFile != restores.absoluteFile) throw Failure("invalid_restore")
        val directory = File(restores, id)
        if (!directory.isDirectory && !directory.mkdir()) throw Failure("capture_storage")
        if (directory.canonicalFile != directory.absoluteFile) throw Failure("invalid_restore")
        return directory
    }

    private fun restoreRecord(directory: File): JSONObject {
        val file = File(directory, "restore.json")
        if (file.canonicalFile != file.absoluteFile || !file.isFile || file.length() !in 1..16384) {
            throw Failure("invalid_restore")
        }
        val record = JSONObject(file.readText())
        if (record.getString("id") != directory.name ||
            !validRestoreBinding(record.getString("name"), record.getLong("size"),
                record.optString("format", "mgba-battery"), record.optString("source", source)) ||
            !record.getString("sha256").matches(Regex("[a-f0-9]{64}")) ||
            record.getString("phase") !in setOf("downloading", "ready", "publishing", "published")) {
            throw Failure("invalid_restore")
        }
        return record
    }

    private fun writeRestoreRecord(directory: File, record: JSONObject) {
        // This directory is exclusively app-private and owned by the single
        // native worker. Only its exact journal temporary is replaced.
        val next = File(directory, "restore.json.next")
        if (next.canonicalFile != next.absoluteFile || (next.exists() && !next.isFile)) {
            throw Failure("invalid_restore")
        }
        FileOutputStream(next).use {
            it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync()
        }
        Os.rename(next.absolutePath, File(directory, "restore.json").absolutePath)
        val parent = OwnedStorageNative.openRoot(directory.absolutePath)
        try { OwnedStorageNative.sync(parent) } finally { OwnedStorageNative.close(parent) }
    }

    private fun digestFd(fd: Int, size: Long, cancellable: Boolean = true): String {
        val digest = MessageDigest.getInstance("SHA-256")
        var offset = 0L
        while (offset < size) {
            if (cancellable) check()
            val bytes = OwnedStorageNative.read(fd, offset, minOf(65536L, size - offset).toInt())
            if (bytes.isEmpty()) throw Failure("source_changed")
            digest.update(bytes); offset += bytes.size
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun beginRestore(id: String, call: MethodCall): Any? {
        check()
        val name = call.argument<String>("name") ?: ""
        val size = call.argument<Number>("size")?.toLong() ?: 0L
        val digest = call.argument<String>("sha256") ?: ""
        val ppssppDirectory = call.argument<String>("ppssppDirectory")
        val sourceDirectory = ppssppDirectory ?: source
        val format = if (ppssppDirectory != null) "ppsspp-slot-v1" else "mgba-battery"
        if (!validRestoreBinding(name, size, format, sourceDirectory) ||
            File(sourceDirectory).canonicalPath != sourceDirectory ||
            !digest.matches(Regex("[a-f0-9]{64}"))) throw Failure("invalid_restore")
        val directory = restoreDirectory(id)
        val journal = File(directory, "restore.json")
        if (journal.exists()) {
            val record = restoreRecord(directory)
            if (record.getString("name") != name || record.getLong("size") != size ||
                record.getString("sha256") != digest ||
                record.optString("format", "mgba-battery") != format ||
                record.optString("source", source) != sourceDirectory) throw Failure("invalid_restore")
            if (record.getString("phase") != "downloading") return null
        } else {
            if (directory.list()?.isNotEmpty() != false) throw Failure("invalid_restore")
            writeRestoreRecord(directory, JSONObject().put("id", id).put("name", name)
                .put("size", size).put("sha256", digest).put("format", format)
                .put("source", sourceDirectory).put("phase", "downloading"))
        }
        val parent = OwnedStorageNative.openRoot(directory.absolutePath)
        try {
            val member = File(directory, "member")
            val fd = OwnedStorageNative.openFile(parent, "member", !member.exists(), true)
            try { OwnedStorageNative.truncate(fd, 0); OwnedStorageNative.sync(fd) }
            finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(parent) }
        return null
    }

    private fun appendRestore(id: String, call: MethodCall): Long {
        check()
        val directory = restoreDirectory(id)
        val record = restoreRecord(directory)
        val offset = call.argument<Number>("offset")?.toLong() ?: -1L
        val bytes = call.argument<ByteArray>("bytes") ?: throw Failure("invalid_restore")
        if (offset < 0 || bytes.isEmpty() || bytes.size > 65536 ||
            offset + bytes.size > record.getLong("size")) throw Failure("invalid_restore")
        val downloading = record.getString("phase") == "downloading"
        val parent = OwnedStorageNative.openRoot(directory.absolutePath)
        try {
            val fd = OwnedStorageNative.openFile(parent, "member", false, downloading)
            try {
                if (downloading) {
                    if (OwnedStorageNative.identity(fd)[2] != offset) throw Failure("invalid_restore")
                    OwnedStorageNative.write(fd, offset, bytes)
                } else if (!OwnedStorageNative.read(fd, offset, bytes.size).contentEquals(bytes)) {
                    throw Failure("changed_capture")
                }
            } finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(parent) }
        return offset + bytes.size
    }

    private fun sealRestore(id: String): Any? {
        check()
        val directory = restoreDirectory(id)
        val record = restoreRecord(directory)
        val parent = OwnedStorageNative.openRoot(directory.absolutePath)
        try {
            val fd = OwnedStorageNative.openFile(parent, "member", false, false)
            try {
                val before = OwnedStorageNative.identity(fd)
                if (before[2] != record.getLong("size") ||
                    digestFd(fd, before[2]) != record.getString("sha256") ||
                    !same(before, OwnedStorageNative.identity(fd))) throw Failure("changed_capture")
                OwnedStorageNative.sync(fd)
            } finally { OwnedStorageNative.close(fd) }
        } finally { OwnedStorageNative.close(parent) }
        if (record.getString("phase") == "downloading") {
            writeRestoreRecord(directory, record.put("phase", "ready"))
        }
        return null
    }

    private fun publishRestore(id: String, rollbackId: String): Any? {
        check()
        if (!rollbackId.matches(Regex("[a-f0-9]{32}")) || rollbackId == id) throw Failure("invalid_restore")
        val directory = restoreDirectory(id)
        val record = restoreRecord(directory)
        if (record.getString("phase") == "downloading") throw Failure("invalid_restore")
        if (record.has("rollbackId") && record.getString("rollbackId") != rollbackId) {
            throw Failure("invalid_restore")
        }
        if (record.getString("phase") == "published") return null // durable receipt, no mutation
        sealRestore(id)
        val name = record.getString("name")
        val ppsspp = record.optString("format", "mgba-battery") == "ppsspp-slot-v1"
        val sourceDirectory = record.optString("source", source)
        if (File(sourceDirectory).canonicalPath != sourceDirectory) throw Failure("invalid_restore")
        val rollbackDirectory = File(root, rollbackId)
        if (rollbackDirectory.canonicalFile != rollbackDirectory.absoluteFile) throw Failure("invalid_restore")
        val rollback = captured(rollbackDirectory, name, sourceDirectory.takeIf { ppsspp })
            ?: throw Failure("invalid_restore")
        @Suppress("UNCHECKED_CAST")
        val oldMembers = rollback["files"] as List<Map<String, Any>>
        if (oldMembers.size != 1) throw Failure("related_group_unfinished")
        @Suppress("DEPRECATION")
        val packageName = if (ppsspp) "org.ppsspp.ppsspp" else "com.retroarch.aarch64"
        val version = activity.packageManager.getPackageInfo(packageName, 0).versionName
        val versions = if (ppsspp) setOf("v1.20.4", "1.20.4") else setOf("1.22.2", "1.22.2_GIT")
        if (version !in versions ||
            rollback["emulatorVersion"] != version) throw Failure("runtime_unreviewed")
        val rtc = name.dropLast(4) + ".rtc"
        if (!ppsspp && File(sourceDirectory, rtc).exists()) throw Failure("related_group_unfinished")
        record.put("rollbackId", rollbackId)
        writeRestoreRecord(directory, record) // durable rollback association before public IO
        val connection = if (ppsspp) null else synchronized(guard) {
            check(); DatagramSocket().also { socket = it }
        }
        connection?.connect(InetAddress.getByName("127.0.0.1"), 55355)
        fun writerClosed() {
            check()
            if (connection != null) contentClosed(connection) else {
                @Suppress("DEPRECATION")
                val info = activity.packageManager.getApplicationInfo(packageName, 0)
                if (info.flags and ApplicationInfo.FLAG_STOPPED == 0) throw Failure("stop_ppsspp_required")
            }
        }
        val parent = OwnedStorageNative.openRoot(sourceDirectory)
        val privateDir = try { OwnedStorageNative.openRoot(directory.absolutePath) }
            catch (e: Exception) { OwnedStorageNative.close(parent); throw e }
        val stageName = ".rshop-save-restore-$id"
        try {
            // Lost acknowledgement after atomic rename: finish durability/receipt
            // only when the recorded staged identity is now the destination.
            if (record.getString("phase") == "publishing" && !File(sourceDirectory, stageName).exists()) {
                val expected = record.getJSONArray("staged")
                val identity = LongArray(5) { expected.getLong(it) }
                if (!same(identity, OwnedStorageNative.entryIdentity(parent, name))) throw Failure("source_changed")
                OwnedStorageNative.sync(parent)
                writeRestoreRecord(directory, record.put("phase", "published"))
                return null
            }
            writerClosed()
            val current = OwnedStorageNative.openFile(parent, name, false, false)
            try {
                val oldIdentity = OwnedStorageNative.identity(current)
                if (oldIdentity[2] != (oldMembers.single()["size"] as Number).toLong() ||
                    digestFd(current, oldIdentity[2]) != oldMembers.single()["sha256"] ||
                    !same(oldIdentity, OwnedStorageNative.identity(current))) throw Failure("source_changed")
                val exists = File(sourceDirectory, stageName).exists()
                if (exists && !record.has("stageAnchor")) throw Failure("restore_stage_conflict")
                val staged = OwnedStorageNative.openFile(parent, stageName, !exists, true)
                try {
                    val initial = OwnedStorageNative.identity(staged)
                    if (exists) {
                        val anchor = record.getJSONArray("stageAnchor")
                        if (initial[0] != anchor.getLong(0) || initial[1] != anchor.getLong(1)) {
                            throw Failure("restore_stage_conflict")
                        }
                    } else {
                        record.put("stageAnchor", JSONArray(initial.toList()))
                        writeRestoreRecord(directory, record)
                    }
                    val member = OwnedStorageNative.openFile(privateDir, "member", false, false)
                    try {
                        val size = record.getLong("size")
                        if (initial[2] > size) throw Failure("restore_stage_conflict")
                        // Resume only an exact prefix of the sealed cloud bytes.
                        // Never truncate or delete an unexpected shared entry.
                        var offset = 0L
                        while (offset < initial[2]) {
                            check()
                            val length = minOf(65536L, initial[2] - offset).toInt()
                            if (!OwnedStorageNative.read(staged, offset, length)
                                    .contentEquals(OwnedStorageNative.read(member, offset, length))) {
                                throw Failure("restore_stage_conflict")
                            }
                            offset += length
                        }
                        while (offset < size) {
                            check()
                            val bytes = OwnedStorageNative.read(member, offset, minOf(65536L, size - offset).toInt())
                            if (bytes.isEmpty()) throw Failure("changed_capture")
                            OwnedStorageNative.write(staged, offset, bytes); offset += bytes.size
                        }
                        OwnedStorageNative.sync(staged)
                        if (digestFd(staged, size) != record.getString("sha256")) throw Failure("changed_capture")
                    } finally { OwnedStorageNative.close(member) }
                    writerClosed()
                    if ((!ppsspp && File(sourceDirectory, rtc).exists()) || !same(oldIdentity, OwnedStorageNative.identity(current)) ||
                        digestFd(current, oldIdentity[2]) != oldMembers.single()["sha256"]) throw Failure("source_changed")
                    // Reopen the namespace to reject a moved/replaced ancestor.
                    val freshParent = OwnedStorageNative.openRoot(sourceDirectory)
                    try {
                        val a = OwnedStorageNative.identity(parent); val b = OwnedStorageNative.identity(freshParent)
                        if (a[0] != b[0] || a[1] != b[1]) throw Failure("source_changed")
                    } finally { OwnedStorageNative.close(freshParent) }
                    val newIdentity = OwnedStorageNative.identity(staged)
                    record.put("staged", JSONArray(newIdentity.toList())).put("phase", "publishing")
                    writeRestoreRecord(directory, record)
                    OwnedStorageNative.sync(parent)
                    check() // last cancellation point before atomic replacement
                    writerClosed()
                    val placed = OwnedStorageNative.replaceReviewedSave(parent, stageName, name, newIdentity, oldIdentity)
                    if (!same(placed, newIdentity)) throw Failure("source_changed")
                    // No cancellation between namespace commit and durable receipt.
                    OwnedStorageNative.sync(parent)
                    writeRestoreRecord(directory, record.put("phase", "published"))
                } finally { OwnedStorageNative.close(staged) }
            } finally { OwnedStorageNative.close(current) }
        } finally { OwnedStorageNative.close(privateDir); OwnedStorageNative.close(parent) }
        return null
    }

    fun shutdown() {
        synchronized(guard) { closed = true; cancelled = true; socket?.close() }
        worker.shutdown()
    }
}
