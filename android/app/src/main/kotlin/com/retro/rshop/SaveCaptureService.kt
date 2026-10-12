package com.retro.rshop

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
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

/** One cancellable capture at a time. No emulator termination or guessed sleeps.
 * Root-assisted source access retains the same capture and restore journals.
 * Explicit mGBA SRAM/RTC, Sega cartridge SRAM and published
 * PPSSPP state slots cross into app-private, durably sealed staging. */
internal class SaveCaptureService(private val activity: Context) {
    companion object {
        // Normalize only the framework-owned parent. Capture IDs and members
        // remain no-follow, canonical-equality checked descendants of this root.
        internal fun stagingRoot(filesDir: File): File = File(filesDir.canonicalFile, "save-captures")
        private const val MGBA_SOURCE = "/storage/emulated/0/RetroArch/saves/mGBA"
        private const val GAMEGEAR_SOURCE = "/storage/emulated/0/RetroArch/saves/Genesis Plus GX"
        private const val N64_SOURCE = "/storage/emulated/0/RetroArch/saves/Mupen64Plus-Next"
        internal fun validGroupNames(name: String, members: List<String>): Boolean =
            RetroArchSaveBoundary.validName(name) && members.size == 2 &&
                members.toSet() == setOf(name, name.dropLast(4) + ".rtc")

        internal fun groupRestorePending(filesDir: File, name: String): Boolean {
            val restores = File(filesDir.canonicalFile, "save-restores")
            return restores.listFiles().orEmpty().any { directory ->
                val journal = File(directory, "group.json")
                if (!journal.exists()) false else {
                    require(journal.canonicalFile == journal.absoluteFile && journal.isFile && journal.length() in 1..131072)
                    val record = JSONObject(journal.readText())
                    record.getString("name") == name && record.getString("phase") in setOf("staging", "publishing", "retiring")
                }
            }
        }
        internal fun validRestoreBinding(name: String, size: Long, format: String, source: String): Boolean =
            when (format) {
                "mgba-battery" -> source == MGBA_SOURCE && RetroArchSaveBoundary.validName(name) &&
                    size in 1..(16L * 1024 * 1024)
                "gamegear-battery", "mastersystem-battery", "megadrive-battery" ->
                    source == GAMEGEAR_SOURCE && RetroArchSaveBoundary.validName(name) &&
                    size in 1..65536L
                "n64-battery" -> source == N64_SOURCE && RetroArchSaveBoundary.validName(name) &&
                    size == 296960L
                "ppsspp-slot-v1" -> PpssppSaveBoundary.validDirectory(source) &&
                    PpssppSaveBoundary.validName(name) && size in 1..PpssppSaveBoundary.MAX_STATE_BYTES
                MelonSaveBoundary.FORMAT -> MelonSaveBoundary.validDirectory(source) &&
                    MelonSaveBoundary.validName(name) && size in 1..MelonSaveBoundary.MAX_BYTES
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
    private fun batterySource(route: String): String = when (route) {
        "gba" -> MGBA_SOURCE
        "gamegear", "mastersystem", "megadrive" -> GAMEGEAR_SOURCE
        "n64" -> N64_SOURCE
        else -> throw Failure("invalid_selection")
    }
    private fun batteryRoute(call: MethodCall): String =
        (call.argument<String>("retroArchRoute") ?: "gba").also { batterySource(it) }
    private fun batteryFormat(route: String): String = when (route) {
        "gba" -> "mgba-battery"
        "gamegear", "mastersystem", "megadrive" -> "$route-battery"
        "n64" -> "n64-battery"
        else -> throw Failure("invalid_selection")
    }
    private fun routeForFormat(format: String): String = when (format) {
        "mgba-battery", "ppsspp-slot-v1", MelonSaveBoundary.FORMAT -> "gba"
        "gamegear-battery" -> "gamegear"
        "mastersystem-battery" -> "mastersystem"
        "megadrive-battery" -> "megadrive"
        "n64-battery" -> "n64"
        else -> throw Failure("invalid_restore")
    }

    private fun batteryMaxBytes(route: String): Long = when (route) {
        "gba" -> 16L * 1024 * 1024
        "gamegear", "mastersystem", "megadrive" -> 65536L
        "n64" -> 296960L // Complete EEPROM + 4 Controller Paks + SRAM + FlashRAM.
        else -> throw Failure("invalid_selection")
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "installedSaveEmulators") {
                // Independent read-only metadata; does not take the file worker,
                // start another capture, prompt for a grant or inspect save data.
                val packages = call.argument<List<String>>("packages")
                    ?: throw Failure("invalid_selection")
                if (packages.size !in 1..64 || packages.toSet().size != packages.size ||
                    packages.any { it.length > 255 ||
                        !it.matches(Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+")) }) {
                    throw Failure("invalid_selection")
                }
                val rows = packages.mapNotNull { packageName ->
                    val info = try {
                        @Suppress("DEPRECATION")
                        activity.packageManager.getPackageInfo(packageName, PackageManager.GET_PROVIDERS)
                    } catch (_: PackageManager.NameNotFoundException) { return@mapNotNull null }
                    val authorities = info.providers.orEmpty().filter {
                        it.enabled && it.exported && it.grantUriPermissions &&
                            it.readPermission == "android.permission.MANAGE_DOCUMENTS"
                    }.flatMap { it.authority.orEmpty().split(';') }
                        .filter(String::isNotEmpty).distinct().sorted()
                    mapOf("packageName" to packageName,
                        "versionName" to (info.versionName ?: "unknown"),
                        "documentAuthorities" to authorities)
                }
                result.success(rows)
                return
            }
            if (call.method == "cancel") {
                val requested = id(call)
                synchronized(guard) {
                    if (active == requested) { cancelled = true; socket?.close() }
                }
                result.success(null)
                return
            }
            if (call.method == "openPpssppAppInfo" || call.method == "openMelonAppInfo") {
                if (activity !is Activity) throw Failure("interaction_required")
                // User-mediated Android settings only. Never stop another app
                // ourselves or mistake background/paused for writer completion.
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:" + if (call.method == "openMelonAppInfo")
                        MelonSaveBoundary.PACKAGE else "org.ppsspp.ppsspp")))
                result.success(null)
                return
            }
            if (call.method in setOf("openRetroArch", "openPpsspp", "openMelon")) {
                if (activity !is Activity) throw Failure("interaction_required")
                val emulator = when (call.method) {
                    "openPpsspp" -> "org.ppsspp.ppsspp"
                    "openMelon" -> MelonSaveBoundary.PACKAGE
                    else -> "com.retroarch.aarch64"
                }
                val intent = activity.packageManager.getLaunchIntentForPackage(emulator)
                    ?: throw Failure("emulator_missing")
                // Explicit user action only. No ROM extras, close/quit command,
                // account selection or settings mutation.
                activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                result.success(null)
                return
            }
            val captureId = if (call.method !in setOf("retroArchNames", "ppssppNames", "ppssppSavedataFolders", "melonNames", "melonSaveSettings", "ppssppSaveSettings")) id(call) else null
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
                        "ppssppSavedataFolders" -> {
                            val parent = call.argument<String>("directory") ?: ""
                            if (!PpssppSavedataBoundary.validParent(parent)) throw Failure("invalid_selection")
                            SaveSourceStorage.open(activity, parent).use { it.names() }
                        }
                        "ppssppSaveSettings" -> {
                            @Suppress("DEPRECATION")
                            val runtime = activity.packageManager.getPackageInfo(PpssppSaveSettings.PACKAGE, 0)
                            if (runtime.versionName !in setOf("1.20.4", "v1.20.4")) throw Failure("emulator_changed")
                            mapOf("directory" to SaveSourceStorage.ppssppSettings(activity).getString("directory"))
                        }
                        "melonNames" -> melonNames(call.argument<String>("directory") ?: "")
                        "melonSaveSettings" -> {
                            @Suppress("DEPRECATION")
                            val runtime = activity.packageManager.getPackageInfo(MelonSaveBoundary.PACKAGE, 0)
                            if (runtime.versionName != MelonSaveBoundary.VERSION) throw Failure("emulator_changed")
                            val settings = SaveSourceStorage.melonSettings(activity)
                            mapOf("mode" to settings.getString("mode"), "extension" to settings.getString("extension"),
                                "directory" to if (settings.isNull("directory")) null else settings.getString("directory"))
                        }
                        "captureRetroArch" -> capture(captureId!!,
                            call.argument<String>("name") ?: "", retroArchRoute = batteryRoute(call),
                            restoreBaseline = call.argument<Boolean>("restoreBaseline") == true)
                        "capturePpsspp" -> capture(captureId!!,
                            call.argument<String>("name") ?: "",
                            call.argument<String>("directory") ?: "",
                            restoreBaseline = call.argument<Boolean>("restoreBaseline") == true)
                        "capturePpssppSavedata" -> capturePpssppSavedata(captureId!!,
                            call.argument<String>("directory") ?: "",
                            restoreBaseline = call.argument<Boolean>("restoreBaseline") == true)
                        "captureMelon" -> capture(captureId!!,
                            call.argument<String>("name") ?: "",
                            melonDirectory = call.argument<String>("directory") ?: "",
                            restoreBaseline = call.argument<Boolean>("restoreBaseline") == true)
                        "retireCapture" -> retireCapture(captureId!!)
                        "beginRestore" -> beginRestore(captureId!!, call)
                        "appendRestore" -> appendRestore(captureId!!, call)
                        "sealRestore" -> sealRestore(captureId!!)
                        "publishRestore" -> publishRestore(captureId!!,
                            call.argument<String>("rollbackCaptureId") ?: "")
                        "beginRestoreGroup" -> beginRestoreGroup(captureId!!, call)
                        "appendRestoreGroup" -> appendRestoreGroup(captureId!!, call)
                        "sealRestoreGroup" -> sealRestoreGroup(captureId!!)
                        "publishRestoreGroup" -> publishRestoreGroup(captureId!!,
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
                        else if (e is Failure) e.code
                        else if (e is java.io.IOException && e.message == "root_unavailable") "root_unavailable"
                        else if (e is java.io.IOException && e.message == "save_settings_unresolved") "save_settings_unresolved"
                        else if (e is java.io.IOException && e.message == "source_changed") "source_changed"
                        else "capture_unavailable"
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
            (!PpssppSaveBoundary.isProtectedDirectory(directory) &&
                File(directory).canonicalPath != directory)) throw Failure("invalid_selection")
        if (PpssppSaveBoundary.isProtectedDirectory(directory))
            return SaveSourceStorage.open(activity, directory).use { it.names() }
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

    private fun melonNames(directory: String): List<String> {
        check()
        if (!MelonSaveBoundary.validDirectory(directory) ||
            (!MelonSaveBoundary.isProtectedDirectory(directory) &&
                File(directory).canonicalPath != directory)) throw Failure("invalid_selection")
        return SaveSourceStorage.open(activity, directory).use { it.names() }
    }

    private fun captured(directory: File, name: String,
                         ppssppDirectory: String? = null,
                         retroArchRoute: String = "gba",
                         melonDirectory: String? = null,
                         restoreBaseline: Boolean = false,
                         savedata: Boolean = false): Map<String, Any>? {
        val seal = File(directory, "capture.json")
        if (!seal.exists()) return null
        if (seal.length() !in 1..(if (savedata) 131072 else 16384)) throw Failure("invalid_capture")
        val record = JSONObject(seal.readText())
        if (record.getString("name") != name || record.getString("captureId") != directory.name) {
            throw Failure("invalid_capture")
        }
        // A capture ID cannot be replayed against another directory or format.
        // Older mGBA journals lack these fields and retain their original binding.
        val expectedFormat = if (savedata) PpssppSavedataBoundary.FORMAT else if (melonDirectory != null) MelonSaveBoundary.FORMAT
            else if (ppssppDirectory != null) "ppsspp-slot-v1"
            else batteryFormat(retroArchRoute)
        val expectedSource = melonDirectory ?: ppssppDirectory ?: batterySource(retroArchRoute)
        if (record.optString("format", "mgba-battery") != expectedFormat ||
            record.optString("source", MGBA_SOURCE) != expectedSource) {
            throw Failure("invalid_capture")
        }
        val members = record.getJSONArray("files")
        val includesRtc = ppssppDirectory == null && melonDirectory == null && retroArchRoute == "gba"
        val maxMembers = if (savedata) PpssppSavedataBoundary.MAX_MEMBERS else if (includesRtc) 2 else 1
        val maxSize = if (savedata) PpssppSavedataBoundary.MAX_BYTES else if (melonDirectory != null) MelonSaveBoundary.MAX_BYTES
            else if (ppssppDirectory != null) PpssppSaveBoundary.MAX_STATE_BYTES
            else batteryMaxBytes(retroArchRoute)
        val absent = record.optBoolean("localWasAbsent")
        if (savedata && record.optJSONArray("sourceIdentity")?.length() != 2) throw Failure("invalid_capture")
        if (absent && (!restoreBaseline || members.length() != 0 ||
                record.optJSONArray("sourceIdentity")?.length() != 2)) throw Failure("invalid_capture")
        if (!absent && members.length() !in 1..maxMembers) throw Failure("invalid_capture")
        val output = mutableListOf<Map<String, Any>>()
        for (i in 0 until members.length()) {
            check()
            val item = members.getJSONObject(i)
            val file = File(directory, "member-$i")
            if (if (savedata) !PpssppSavedataBoundary.validMember(item.getString("name")) else item.getString("name") != name &&
                (!includesRtc || item.getString("name") != name.dropLast(4) + ".rtc")) {
                throw Failure("invalid_capture")
            }
            if (file.canonicalFile != file.absoluteFile || !file.isFile ||
                file.length() !in (if (savedata) 0 else 1)..maxSize ||
                (!savedata && ppssppDirectory == null && melonDirectory == null &&
                    retroArchRoute == "n64" && file.length() != maxSize) ||
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
        if ((!absent && !savedata && output.count { it["name"] == name } != 1) ||
            (savedata && output.sumOf { (it["size"] as Number).toLong() } > maxSize) ||
            output.map { it["name"] }.toSet().size != output.size) throw Failure("invalid_capture")
        return mapOf("captureId" to directory.name, "deviceId" to record.getString("deviceId"),
            "emulatorVersion" to record.getString("emulatorVersion"), "files" to output,
            "localWasAbsent" to absent,
            "sourceIdentity" to if (absent || savedata) (0..1).map { record.getJSONArray("sourceIdentity").getLong(it) } else emptyList<Long>()).let {
                if (savedata) it + ("savedataGroupPresent" to record.optBoolean("savedataGroupPresent", true)) else it
            }
    }

    private fun retireCapture(id: String): Any? {
        check()
        val reviewed = SaveCaptureRetirement.review(root, id)
        val directory = File(root, id)
        if (!directory.exists()) {
            // Complete a prior directory unlink whose parent sync was lost.
            if (root.exists()) {
                val parent = OwnedStorageNative.openRoot(root.absolutePath)
                try { OwnedStorageNative.sync(parent) }
                finally { OwnedStorageNative.close(parent) }
            }
            return null
        }
        val stage = OwnedStorageNative.openRoot(directory.absolutePath)
        try {
            // Pin/review every member before the first unlink. The existing
            // native primitive rechecks identity and rejects links/hardlinks.
            val identities = reviewed.associate { file ->
                val fd = OwnedStorageNative.openFile(stage, file.name, false, false)
                try { file.name to OwnedStorageNative.identity(fd) }
                finally { OwnedStorageNative.close(fd) }
            }
            for ((name, identity) in identities) {
                check()
                OwnedStorageNative.retirePrivateFile(stage, name, identity)
            }
            OwnedStorageNative.sync(stage)
        } finally { OwnedStorageNative.close(stage) }
        check()
        if (directory.canonicalFile != directory.absoluteFile || !directory.delete()) {
            throw Failure("capture_storage")
        }
        val parent = OwnedStorageNative.openRoot(root.absolutePath)
        try { OwnedStorageNative.sync(parent) }
        finally { OwnedStorageNative.close(parent) }
        return null
    }

    private fun capture(captureId: String, name: String,
                        ppssppDirectory: String? = null,
                        retroArchRoute: String = "gba",
                        melonDirectory: String? = null,
                        restoreBaseline: Boolean = false): Map<String, Any> {
        val ppsspp = ppssppDirectory != null
        val melon = melonDirectory != null
        val standalone = ppsspp || melon
        if ((ppsspp && melon) || (standalone && retroArchRoute != "gba")) throw Failure("invalid_selection")
        if (if (melon) !MelonSaveBoundary.validName(name) || !MelonSaveBoundary.validDirectory(melonDirectory!!)
            else if (ppsspp) !PpssppSaveBoundary.validName(name) ||
                !PpssppSaveBoundary.validDirectory(ppssppDirectory!!)
            else !RetroArchSaveBoundary.validName(name)) throw Failure("invalid_selection")
        val sourceDirectory = melonDirectory ?: ppssppDirectory ?: batterySource(retroArchRoute)
        if (!SaveSourceStorage.isProtectedDirectory(sourceDirectory) &&
            File(sourceDirectory).canonicalPath != sourceDirectory) throw Failure("invalid_selection")
        val packageName = if (melon) MelonSaveBoundary.PACKAGE else if (ppsspp) "org.ppsspp.ppsspp" else "com.retroarch.aarch64"
        @Suppress("DEPRECATION")
        val version = activity.packageManager.getPackageInfo(packageName, 0).versionName
            ?: throw Failure("emulator_missing")
        // Installed baseline investigated in S10_SAVE_BACKUP_DESIGN. Do not
        // extrapolate the writer contract to an unreviewed future runtime.
        val versions = if (melon) setOf(MelonSaveBoundary.VERSION)
            else if (ppsspp) setOf("v1.20.4", "1.20.4") else setOf("1.22.2_GIT", "1.22.2")
        if (version !in versions) throw Failure("runtime_unreviewed")
        val device = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ANDROID_ID)
            ?: throw Failure("device_identity_unavailable")
        if (!root.isDirectory && !root.mkdir()) throw Failure("capture_storage")
        if (root.canonicalFile != root.absoluteFile) throw Failure("invalid_capture")
        val directory = File(root, captureId)
        if (directory.exists() && directory.canonicalFile != directory.absoluteFile) throw Failure("invalid_capture")
        if (!directory.isDirectory && !directory.mkdir()) throw Failure("capture_storage")
        captured(directory, name, ppssppDirectory, retroArchRoute, melonDirectory, restoreBaseline)?.let { return it }
        // Only these exact private files can be leftovers from this journaled
        // capture ID. An unexpected entry is preserved and blocks replay.
        val leftovers = directory.listFiles() ?: throw Failure("capture_storage")
        if (leftovers.any { it.name !in setOf("member-0", "member-1", "capture.json.part") ||
                it.canonicalFile != it.absoluteFile || !it.isFile }) throw Failure("invalid_capture")
        leftovers.forEach { if (!it.delete()) throw Failure("capture_storage") }

        val connection = if (standalone) null else synchronized(guard) {
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
        val sourceStorage = SaveSourceStorage.open(activity, sourceDirectory)
        val sourceDir = sourceStorage.root
        val stageDir = try { OwnedStorageNative.openRoot(directory.absolutePath) }
            catch (e: Exception) { sourceStorage.close(); throw e }
        val fds = mutableListOf<Int>()
        try {
            if (melon) sourceStorage.beginMelonSnapshot(activity, name)
            val absent = restoreBaseline && !sourceStorage.exists(name)
            val selected = if (absent) mutableListOf<String>() else mutableListOf(name)
            val rtc = name.dropLast(4) + ".rtc"
            if (!standalone && retroArchRoute != "gba" && File(sourceDirectory, rtc).exists()) {
                throw Failure("related_group_unfinished")
            }
            if (!standalone && File(sourceDirectory, rtc).exists()) {
                if (absent) throw Failure("related_group_changed")
                selected += rtc
            }
            for (member in selected) fds += sourceStorage.openFile(member, false, false)
            val identities = fds.map(sourceStorage::identity)
            val maxSize = if (melon) MelonSaveBoundary.MAX_BYTES else if (ppsspp) PpssppSaveBoundary.MAX_STATE_BYTES
                else batteryMaxBytes(retroArchRoute)
            if (identities.any { it[2] !in 1..maxSize }) throw Failure("invalid_save_size")
            if (!standalone && retroArchRoute == "n64" && identities.any { it[2] != maxSize }) {
                throw Failure("invalid_save_size")
            }
            val members = JSONArray()
            for (i in fds.indices) {
                check()
                val target = OwnedStorageNative.openFile(stageDir, "member-$i", true, true)
                try {
                    val digest = MessageDigest.getInstance("SHA-256")
                    var offset = 0L
                    while (offset < identities[i][2]) {
                        check()
                        val bytes = sourceStorage.read(fds[i], offset,
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
            if (absent && sourceStorage.exists(name)) throw Failure("source_changed")
            // Compare the complete group after all copies, including the RTC
            // existence assertion. A changed/replaced source never gets a seal.
            if (!standalone && File(sourceDirectory, rtc).exists() != selected.contains(rtc)) throw Failure("source_changed")
            for (i in fds.indices) {
                if (!same(identities[i], sourceStorage.identity(fds[i])) ||
                    !same(identities[i], sourceStorage.entryIdentity(selected[i]))) {
                    throw Failure("source_changed")
                }
            }
            // Reconcile the selected path with the pinned source root,
            // after any protocol wait as well as the complete copy.
            if (sourceStorage.currentRootIdentity().take(2) !=
                sourceStorage.identity(sourceDir).take(2)) throw Failure("source_changed")
            if (melon) sourceStorage.verifyMelonSnapshot()
            check()
            val record = JSONObject().put("captureId", captureId).put("name", name)
                .put("deviceId", hash(device.toByteArray(Charsets.UTF_8)))
                .put("emulatorVersion", version).put("files", members)
                .put("format", if (melon) MelonSaveBoundary.FORMAT else if (ppsspp) "ppsspp-slot-v1"
                    else batteryFormat(retroArchRoute))
                .put("source", sourceDirectory).put("localWasAbsent", absent)
            if (absent) record.put("sourceIdentity", JSONArray(sourceStorage.identity(sourceDir).take(2)))
            val part = File(directory, "capture.json.part")
            FileOutputStream(part).use { it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
            OwnedStorageNative.renameNoReplace(stageDir, part.name, stageDir, "capture.json")
            OwnedStorageNative.sync(stageDir)
            return captured(directory, name, ppssppDirectory, retroArchRoute, melonDirectory, restoreBaseline) ?: throw Failure("capture_storage")
        } finally {
            try { fds.forEach { runCatching { sourceStorage.closeFile(it) } } }
            finally { try { OwnedStorageNative.close(stageDir) } finally { sourceStorage.close() } }
        }
    }

    /** Capture every member at PPSSPP's reviewed native-exit boundary. Root
     * handles source IO and one whole-directory inotify guard; payloads remain
     * streamed through the existing app-owned capture journal. */
    private fun capturePpssppSavedata(captureId: String, sourceDirectory: String,
                                    restoreBaseline: Boolean): Map<String, Any> {
        if (!PpssppSavedataBoundary.validDirectory(sourceDirectory)) throw Failure("invalid_selection")
        val name = sourceDirectory.substringAfterLast('/')
        @Suppress("DEPRECATION")
        val version = activity.packageManager.getPackageInfo(PpssppSaveSettings.PACKAGE, 0).versionName
        if (version !in setOf("v1.20.4", "1.20.4")) throw Failure("runtime_unreviewed")
        val device = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ANDROID_ID)
            ?: throw Failure("device_identity_unavailable")
        if (!root.isDirectory && !root.mkdir()) throw Failure("capture_storage")
        if (root.canonicalFile != root.absoluteFile) throw Failure("invalid_capture")
        val directory = File(root, captureId)
        if (directory.exists() && directory.canonicalFile != directory.absoluteFile) throw Failure("invalid_capture")
        if (!directory.isDirectory && !directory.mkdir()) throw Failure("capture_storage")
        captured(directory, name, sourceDirectory, restoreBaseline = restoreBaseline, savedata = true)?.let { return it }
        val leftovers = directory.listFiles() ?: throw Failure("capture_storage")
        val allowed = (0 until PpssppSavedataBoundary.MAX_MEMBERS).map { "member-$it" }.toSet() + "capture.json.part"
        if (leftovers.any { it.name !in allowed || it.canonicalFile != it.absoluteFile || !it.isFile })
            throw Failure("invalid_capture")
        leftovers.forEach { if (!it.delete()) throw Failure("capture_storage") }
        val opened = try { SaveSourceStorage.open(activity, sourceDirectory) }
        catch (error: java.io.IOException) {
            if (!restoreBaseline || error.message != "owned_storage:2") throw error
            return captureAbsentPpssppSavedata(captureId, directory, sourceDirectory, version!!, device)
        }
        opened.use { storage ->
            fun closed() {
                check()
                try { storage.verifyEmulatorClosed(activity) } catch (error: java.io.IOException) {
                    if (error.message != "emulator_running") throw error
                    throw Failure("stop_ppsspp_required")
                }
            }
            storage.beginPpssppSavedataSnapshot()
            closed()
            val selected = storage.names()
            val absent = restoreBaseline && selected.isEmpty()
            if (!absent && !PpssppSavedataBoundary.validMembers(selected)) throw Failure("invalid_selection")
            val parentIdentity = storage.identity(storage.root)
            val members = JSONArray()
            val identities = mutableListOf<LongArray>()
            var total = 0L
            val stage = OwnedStorageNative.openRoot(directory.absolutePath)
            try {
                for ((index, member) in selected.withIndex()) {
                    check()
                    val fd = storage.openFile(member, false, false)
                    try {
                        val before = storage.identity(fd)
                        if (before[2] !in 0..PpssppSavedataBoundary.MAX_BYTES ||
                            total > PpssppSavedataBoundary.MAX_BYTES - before[2]) throw Failure("invalid_save_size")
                        total += before[2]
                        val target = OwnedStorageNative.openFile(stage, "member-$index", true, true)
                        val digest = MessageDigest.getInstance("SHA-256")
                        try {
                            var offset = 0L
                            while (offset < before[2]) {
                                check()
                                val bytes = storage.read(fd, offset, minOf(65536L, before[2] - offset).toInt())
                                if (bytes.isEmpty()) throw Failure("source_changed")
                                digest.update(bytes); OwnedStorageNative.write(target, offset, bytes); offset += bytes.size
                            }
                            OwnedStorageNative.sync(target)
                        } finally { OwnedStorageNative.close(target) }
                        if (!same(before, storage.identity(fd)) || !same(before, storage.entryIdentity(member)))
                            throw Failure("source_changed")
                        identities.add(before)
                        members.put(JSONObject().put("name", member).put("size", before[2]).put("identity", JSONArray(before.toList()))
                            .put("sha256", digest.digest().joinToString("") { "%02x".format(it) }))
                    } finally { storage.closeFile(fd) }
                }
                closed()
                if (storage.names() != selected || storage.currentRootIdentity().take(2) != parentIdentity.take(2))
                    throw Failure("source_changed")
                for (index in selected.indices) if (!same(identities[index], storage.entryIdentity(selected[index])))
                    throw Failure("source_changed")
                storage.verifyPpssppSavedataSnapshot()
                check()
                val record = JSONObject().put("captureId", captureId).put("name", name)
                    .put("deviceId", hash(device.toByteArray(Charsets.UTF_8))).put("emulatorVersion", version)
                    .put("files", members).put("format", PpssppSavedataBoundary.FORMAT)
                    .put("source", sourceDirectory).put("localWasAbsent", absent).put("savedataGroupPresent", true)
                record.put("sourceIdentity", JSONArray(parentIdentity.take(2)))
                val part = File(directory, "capture.json.part")
                FileOutputStream(part).use { it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
                OwnedStorageNative.renameNoReplace(stage, part.name, stage, "capture.json")
                OwnedStorageNative.sync(stage)
                return captured(directory, name, sourceDirectory, restoreBaseline = restoreBaseline, savedata = true)
                    ?: throw Failure("capture_storage")
            } finally { OwnedStorageNative.close(stage) }
        }
    }

    private fun captureAbsentPpssppSavedata(id: String, directory: File, sourceDirectory: String,
                                           version: String, device: String): Map<String, Any> {
        SaveSourceStorage.open(activity, sourceDirectory.substringBeforeLast('/')).use { storage ->
            storage.beginPpssppSavedataSnapshot()
            try { storage.verifyEmulatorClosed(activity) } catch (error: java.io.IOException) {
                if (error.message != "emulator_running") throw error
                throw Failure("stop_ppsspp_required")
            }
            val name = sourceDirectory.substringAfterLast('/')
            try {
                val existing = storage.openSaveGroup(name)
                storage.closeFile(existing)
                throw Failure("source_changed")
            } catch (error: java.io.IOException) { if (error.message != "owned_storage:2") throw error }
            val parent = storage.identity(storage.root)
            if (storage.currentRootIdentity().take(2) != parent.take(2)) throw Failure("source_changed")
            storage.verifyPpssppSavedataSnapshot()
            check()
            val record = JSONObject().put("captureId", id).put("name", name)
                .put("deviceId", hash(device.toByteArray(Charsets.UTF_8))).put("emulatorVersion", version)
                .put("files", JSONArray()).put("format", PpssppSavedataBoundary.FORMAT)
                .put("source", sourceDirectory).put("localWasAbsent", true).put("savedataGroupPresent", false)
                .put("sourceIdentity", JSONArray(parent.take(2)))
            val stage = OwnedStorageNative.openRoot(directory.absolutePath)
            try {
                val part = File(directory, "capture.json.part")
                FileOutputStream(part).use { it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
                OwnedStorageNative.renameNoReplace(stage, part.name, stage, "capture.json")
                OwnedStorageNative.sync(stage)
            } finally { OwnedStorageNative.close(stage) }
            return captured(directory, name, sourceDirectory, restoreBaseline = true, savedata = true)
                ?: throw Failure("capture_storage")
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
        val groupId = record.optString("groupId").takeIf { it.isNotEmpty() }
        val validBinding = if (groupId == null) validRestoreBinding(record.getString("name"), record.getLong("size"),
                record.optString("format", "mgba-battery"), record.optString("source", source)) else {
            val group = groupRecord(restoreDirectory(groupId))
            val members = group.getJSONArray("members")
            (0 until members.length()).any { index ->
                val member = members.getJSONObject(index)
                childId(groupId, index) == directory.name && member.getString("name") == record.getString("name") &&
                    member.getLong("size") == record.getLong("size") && member.getString("sha256") == record.getString("sha256")
            } && record.getString("format") == group.optString("format", "mgba-battery") &&
                record.getString("source") == group.optString("source", MGBA_SOURCE)
        }
        if (record.getString("id") != directory.name || !validBinding ||
            !record.getString("sha256").matches(Regex("[a-f0-9]{64}")) ||
            record.getString("phase") !in setOf("downloading", "ready", "publishing", "published")) {
            throw Failure("invalid_restore")
        }
        return record
    }

    private fun writeRestoreRecord(directory: File, record: JSONObject, leaf: String = "restore.json") {
        // This directory is exclusively app-private and owned by the single
        // native worker. Only its exact journal temporary is replaced.
        val next = File(directory, "$leaf.next")
        if (next.canonicalFile != next.absoluteFile || (next.exists() && !next.isFile)) {
            throw Failure("invalid_restore")
        }
        FileOutputStream(next).use {
            it.write(record.toString().toByteArray(Charsets.UTF_8)); it.fd.sync()
        }
        Os.rename(next.absolutePath, File(directory, leaf).absolutePath)
        val parent = OwnedStorageNative.openRoot(directory.absolutePath)
        try { OwnedStorageNative.sync(parent) } finally { OwnedStorageNative.close(parent) }
    }

    private fun digestFd(fd: Int, size: Long, cancellable: Boolean = true,
                         sourceStorage: SaveSourceStorage? = null): String {
        val digest = MessageDigest.getInstance("SHA-256")
        var offset = 0L
        while (offset < size) {
            if (cancellable) check()
            val length = minOf(65536L, size - offset).toInt()
            val bytes = sourceStorage?.read(fd, offset, length) ?: OwnedStorageNative.read(fd, offset, length)
            if (bytes.isEmpty()) throw Failure("source_changed")
            digest.update(bytes); offset += bytes.size
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun entryAbsent(parent: Int, name: String): Boolean = try {
        OwnedStorageNative.entryIdentity(parent, name); false
    } catch (error: java.io.IOException) {
        if (error.message != "owned_storage:2") throw error
        true
    }

    private fun beginRestore(id: String, call: MethodCall, groupId: String? = null): Any? {
        check()
        val name = call.argument<String>("name") ?: ""
        val size = call.argument<Number>("size")?.toLong() ?: 0L
        val digest = call.argument<String>("sha256") ?: ""
        val ppssppDirectory = call.argument<String>("ppssppDirectory")
        val melonDirectory = call.argument<String>("melonDirectory")
        val route = batteryRoute(call)
        if ((ppssppDirectory != null && melonDirectory != null) ||
            ((ppssppDirectory != null || melonDirectory != null) && route != "gba")) throw Failure("invalid_restore")
        val group = groupId?.let { groupRecord(restoreDirectory(it)) }
        val sourceDirectory = group?.optString("source", MGBA_SOURCE) ?: melonDirectory ?: ppssppDirectory ?: batterySource(route)
        val format = group?.optString("format", "mgba-battery") ?: if (melonDirectory != null) MelonSaveBoundary.FORMAT else if (ppssppDirectory != null) "ppsspp-slot-v1"
            else batteryFormat(route)
        val validBinding = if (group == null) validRestoreBinding(name, size, format, sourceDirectory)
            else (0 until group.getJSONArray("members").length()).any { index ->
                val member = group.getJSONArray("members").getJSONObject(index)
                childId(groupId!!, index) == id && member.getString("name") == name &&
                    member.getLong("size") == size && member.getString("sha256") == digest
            }
        // SRAM is also a group member; its normal scalar binding remains valid.
        if (!validBinding ||
            (!SaveSourceStorage.isProtectedDirectory(sourceDirectory) &&
                File(sourceDirectory).canonicalPath != sourceDirectory) ||
            !digest.matches(Regex("[a-f0-9]{64}"))) throw Failure("invalid_restore")
        val directory = restoreDirectory(id)
        val journal = File(directory, "restore.json")
        if (journal.exists()) {
            val record = restoreRecord(directory)
            if (record.getString("name") != name || record.getLong("size") != size ||
                record.getString("sha256") != digest ||
                record.optString("groupId").takeIf { it.isNotEmpty() } != groupId ||
                record.optString("format", "mgba-battery") != format ||
                record.optString("source", source) != sourceDirectory) throw Failure("invalid_restore")
            if (record.getString("phase") != "downloading") return null
        } else {
            if (directory.list()?.isNotEmpty() != false) throw Failure("invalid_restore")
            writeRestoreRecord(directory, JSONObject().put("id", id).put("name", name)
                .put("size", size).put("sha256", digest).put("format", format)
                .put("source", sourceDirectory).put("phase", "downloading").also {
                    if (groupId != null) it.put("groupId", groupId)
                })
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

    private fun publishRestore(id: String, rollbackId: String, groupId: String? = null): Any? {
        check()
        if (!rollbackId.matches(Regex("[a-f0-9]{32}")) || rollbackId == id) throw Failure("invalid_restore")
        val directory = restoreDirectory(id)
        val record = restoreRecord(directory)
        if (record.optString("groupId").takeIf { it.isNotEmpty() } != groupId) throw Failure("invalid_restore")
        val group = groupId?.let { groupRecord(restoreDirectory(it)) }
        if (record.optString("format") == PpssppSavedataBoundary.FORMAT) throw Failure("invalid_restore")
        if (group != null && group.getString("phase") != "publishing") throw Failure("invalid_restore")
        if (record.getString("phase") == "downloading") throw Failure("invalid_restore")
        if (record.has("rollbackId") && record.getString("rollbackId") != rollbackId) {
            throw Failure("invalid_restore")
        }
        if (record.getString("phase") == "published") return null // durable receipt, no mutation
        sealRestore(id)
        val name = record.getString("name")
        val ppsspp = record.optString("format", "mgba-battery") == "ppsspp-slot-v1"
        val melon = record.optString("format") == MelonSaveBoundary.FORMAT
        val standalone = ppsspp || melon
        val sourceDirectory = record.optString("source", source)
        if (!SaveSourceStorage.isProtectedDirectory(sourceDirectory) &&
            File(sourceDirectory).canonicalPath != sourceDirectory) throw Failure("invalid_restore")
        val rollbackDirectory = File(root, rollbackId)
        if (rollbackDirectory.canonicalFile != rollbackDirectory.absoluteFile) throw Failure("invalid_restore")
        val batteryRoute = routeForFormat(record.optString("format", "mgba-battery"))
        val rollback = captured(rollbackDirectory, group?.getString("name") ?: name,
            sourceDirectory.takeIf { ppsspp }, batteryRoute, sourceDirectory.takeIf { melon }, true)
            ?: throw Failure("invalid_restore")
        val absent = rollback["localWasAbsent"] == true
        @Suppress("UNCHECKED_CAST")
        val oldMembers = (rollback["files"] as List<Map<String, Any>>).filter {
            group == null || it["name"] == name
        }
        if (oldMembers.size != if (absent) 0 else 1) throw Failure("related_group_unfinished")
        @Suppress("DEPRECATION")
        val packageName = if (melon) MelonSaveBoundary.PACKAGE else if (ppsspp) "org.ppsspp.ppsspp" else "com.retroarch.aarch64"
        val version = activity.packageManager.getPackageInfo(packageName, 0).versionName
        val versions = if (melon) setOf(MelonSaveBoundary.VERSION) else if (ppsspp) setOf("v1.20.4", "1.20.4") else setOf("1.22.2", "1.22.2_GIT")
        if (version !in versions ||
            rollback["emulatorVersion"] != version) throw Failure("runtime_unreviewed")
        val rtc = name.dropLast(4) + ".rtc"
        if (group == null && !standalone && File(sourceDirectory, rtc).exists()) throw Failure("related_group_unfinished")
        record.put("rollbackId", rollbackId)
        writeRestoreRecord(directory, record) // durable rollback association before public IO
        val connection = if (standalone) null else synchronized(guard) {
            check(); DatagramSocket().also { socket = it }
        }
        connection?.connect(InetAddress.getByName("127.0.0.1"), 55355)
        val sourceStorage = SaveSourceStorage.open(activity, sourceDirectory)
        fun writerClosed() {
            check()
            if (connection != null) contentClosed(connection) else {
                try { sourceStorage.verifyEmulatorClosed(activity) }
                catch (error: java.io.IOException) {
                    if (error.message != "emulator_running") throw error
                    throw Failure(if (melon) "stop_melon_required" else "stop_ppsspp_required")
                }
            }
        }
        val parent = sourceStorage.root
        val privateDir = try { OwnedStorageNative.openRoot(directory.absolutePath) }
            catch (e: Exception) { sourceStorage.close(); throw e }
        val stageName = ".rshop-save-restore-$id"
        fun rootOperation(operation: String, review: JSONObject? = null): JSONObject = try {
            RootSavePublication.request(activity, operation, record, stageName, review)
        } catch (error: java.io.IOException) {
            throw Failure(when (error.message) {
                "owned_storage:17", "owned_storage:2", "source_changed" -> "source_changed"
                "root_unavailable" -> "root_unavailable"
                else -> "restore_unavailable"
            })
        }
        try {
            // Lost acknowledgement after atomic rename: finish durability/receipt
            // only when the recorded staged identity is now the destination.
            if (record.getString("phase") == "publishing" && !sourceStorage.exists(stageName)) {
                record.optJSONObject("rootPublication")?.let { rootOperation("verify", it) }
                val expected = record.getJSONArray("staged")
                val identity = LongArray(5) { expected.getLong(it) }
                val placed = sourceStorage.entryIdentity(name)
                if (if (absent) (0..2).any { identity[it] != placed[it] }
                    else !same(identity, placed)) throw Failure("source_changed")
                sourceStorage.sync(parent)
                writeRestoreRecord(directory, record.put("phase", "published"))
                return null
            }
            writerClosed()
            @Suppress("UNCHECKED_CAST")
            if (absent && sourceStorage.identity(parent).take(2) !=
                    rollback["sourceIdentity"] as List<Long>) throw Failure("source_changed")
            val current = if (absent) -1 else sourceStorage.openFile(name, false, false)
            try {
                val oldIdentity = if (absent) null else sourceStorage.identity(current)
                fun verifyCurrent() {
                    if (absent) {
                        if (sourceStorage.exists(name)) throw Failure("source_changed")
                    } else if (oldIdentity!![2] != (oldMembers.single()["size"] as Number).toLong() ||
                        digestFd(current, oldIdentity[2], sourceStorage = sourceStorage) != oldMembers.single()["sha256"] ||
                        !same(oldIdentity, sourceStorage.identity(current)) ||
                        !same(oldIdentity, sourceStorage.entryIdentity(name))) throw Failure("source_changed")
                }
                verifyCurrent()
                val exists = sourceStorage.exists(stageName)
                if (exists && !record.has("stageAnchor")) throw Failure("restore_stage_conflict")
                val staged = sourceStorage.openFile(stageName, !exists, true)
                try {
                    val initial = sourceStorage.identity(staged)
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
                            if (!sourceStorage.read(staged, offset, length)
                                    .contentEquals(OwnedStorageNative.read(member, offset, length))) {
                                throw Failure("restore_stage_conflict")
                            }
                            offset += length
                        }
                        while (offset < size) {
                            check()
                            val bytes = OwnedStorageNative.read(member, offset, minOf(65536L, size - offset).toInt())
                            if (bytes.isEmpty()) throw Failure("changed_capture")
                            sourceStorage.write(staged, offset, bytes); offset += bytes.size
                        }
                        sourceStorage.sync(staged)
                        if (digestFd(staged, size, sourceStorage = sourceStorage) != record.getString("sha256")) throw Failure("changed_capture")
                    } finally { OwnedStorageNative.close(member) }
                    writerClosed()
                    if (group == null && !standalone && File(sourceDirectory, rtc).exists()) throw Failure("source_changed")
                    verifyCurrent()
                    // Reopen the namespace to reject a moved/replaced ancestor.
                    val a = sourceStorage.identity(parent); val b = sourceStorage.currentRootIdentity()
                    if (a[0] != b[0] || a[1] != b[1]) throw Failure("source_changed")
                    val newIdentity = sourceStorage.identity(staged)
                    if (absent && !sourceStorage.rootAssisted && !record.has("rootPublication")) {
                        // Root review returns backing-inode identities, which are
                        // distinct from FUSE identities. Seal both before commit.
                        record.put("rootPublication", rootOperation("review"))
                    }
                    record.put("staged", JSONArray(newIdentity.toList())).put("phase", "publishing")
                    writeRestoreRecord(directory, record)
                    sourceStorage.sync(parent)
                    check() // last cancellation point before atomic replacement
                    writerClosed()
                    if (absent) {
                        if (sourceStorage.rootAssisted) sourceStorage.renameNoReplace(stageName, name) else {
                            rootOperation("publish", record.getJSONObject("rootPublication"))
                            rootOperation("verify", record.getJSONObject("rootPublication"))
                        }
                        val placed = sourceStorage.entryIdentity(name)
                        if ((0..2).any { placed[it] != newIdentity[it] }) throw Failure("source_changed")
                    } else {
                        val placed = sourceStorage.replace(stageName, name, newIdentity, oldIdentity!!)
                        if (!same(placed, newIdentity)) throw Failure("source_changed")
                    }
                    // No cancellation between namespace commit and durable receipt.
                    sourceStorage.sync(parent)
                    writeRestoreRecord(directory, record.put("phase", "published"))
                } finally { sourceStorage.closeFile(staged) }
            } finally { if (current >= 0) sourceStorage.closeFile(current) }
        } finally { OwnedStorageNative.close(privateDir); sourceStorage.close() }
        return null
    }

    private fun childId(groupId: String, index: Int): String = hash("$groupId/$index".toByteArray()).take(32)

    private fun groupRecord(directory: File): JSONObject {
        val file = File(directory, "group.json")
        if (file.canonicalFile != file.absoluteFile || !file.isFile || file.length() !in 1..131072) throw Failure("invalid_restore")
        val record = JSONObject(file.readText())
        val members = record.getJSONArray("members")
        val names = (0 until members.length()).map { members.getJSONObject(it).getString("name") }
        val savedata = record.optString("format", "mgba-battery") == PpssppSavedataBoundary.FORMAT
        val valid = if (savedata) PpssppSavedataBoundary.validDirectory(record.getString("source")) &&
            record.getString("source").substringAfterLast('/') == record.getString("name") && PpssppSavedataBoundary.validMembers(names)
            else record.optString("format", "mgba-battery") == "mgba-battery" && record.optString("source", MGBA_SOURCE) == MGBA_SOURCE &&
                validGroupNames(record.getString("name"), names)
        val max = if (savedata) PpssppSavedataBoundary.MAX_BYTES else 16L * 1024 * 1024
        if (record.getString("id") != directory.name || !valid || names != names.sorted() ||
            record.getString("phase") !in (if (savedata) setOf("downloading", "ready", "staging", "publishing", "retiring", "published")
                else setOf("downloading", "ready", "publishing", "published")) ||
            (0 until members.length()).any { val m = members.getJSONObject(it)
                m.getLong("size") !in (if (savedata) 0 else 1)..max || !m.getString("sha256").matches(Regex("[a-f0-9]{64}")) ||
                    (m.getLong("size") == 0L && m.getString("sha256") != hash(byteArrayOf())) } ||
            (savedata && (0 until members.length()).sumOf { members.getJSONObject(it).getLong("size") } > max)) {
            throw Failure("invalid_restore")
        }
        return record
    }

    private fun beginRestoreGroup(id: String, call: MethodCall): Any? {
        check()
        val name = call.argument<String>("name") ?: ""
        val savedataDirectory = call.argument<String>("ppssppSavedataDirectory")
        val savedata = savedataDirectory != null
        val format = if (savedata) PpssppSavedataBoundary.FORMAT else "mgba-battery"
        val sourceDirectory = savedataDirectory ?: MGBA_SOURCE
        val raw = call.argument<List<Map<String, Any>>>("members") ?: throw Failure("invalid_restore")
        val names = raw.map { it["name"] as? String ?: "" }
        if (if (savedata) !PpssppSavedataBoundary.validDirectory(sourceDirectory) ||
                sourceDirectory.substringAfterLast('/') != name || !PpssppSavedataBoundary.validMembers(names)
            else !validGroupNames(name, names)) throw Failure("invalid_restore")
        val members = JSONArray()
        val max = if (savedata) PpssppSavedataBoundary.MAX_BYTES else 16L * 1024 * 1024
        var total = 0L
        for (item in raw.sortedBy { it["name"] as String }) {
            val size = (item["size"] as? Number)?.toLong() ?: 0L
            val digest = item["sha256"] as? String ?: ""
            if (size !in (if (savedata) 0 else 1)..max || !digest.matches(Regex("[a-f0-9]{64}")) ||
                (size == 0L && digest != hash(byteArrayOf())) || (savedata && total > max - size)) throw Failure("invalid_restore")
            total += size
            members.put(JSONObject().put("name", item["name"]).put("size", size).put("sha256", digest))
        }
        val directory = restoreDirectory(id)
        if (File(directory, "group.json").exists()) {
            val old = groupRecord(directory)
            if (old.getString("name") != name || old.optString("format", "mgba-battery") != format ||
                old.optString("source", MGBA_SOURCE) != sourceDirectory ||
                old.getJSONArray("members").toString() != members.toString()) throw Failure("invalid_restore")
        } else {
            if (directory.list()?.isNotEmpty() != false) throw Failure("invalid_restore")
            writeRestoreRecord(directory, JSONObject().put("id", id).put("name", name)
                .put("members", members).put("format", format).put("source", sourceDirectory).put("phase", "downloading"), "group.json")
        }
        for (index in 0 until members.length()) {
            val member = members.getJSONObject(index)
            beginRestore(childId(id, index), MethodCall("beginRestore", mapOf(
                "name" to member.getString("name"), "size" to member.getLong("size"),
                "sha256" to member.getString("sha256"))), id)
        }
        return null
    }

    private fun appendRestoreGroup(id: String, call: MethodCall): Long {
        val record = groupRecord(restoreDirectory(id))
        val index = call.argument<Int>("member") ?: -1
        if (index !in 0 until record.getJSONArray("members").length()) throw Failure("invalid_restore")
        return appendRestore(childId(id, index), call)
    }

    private fun sealRestoreGroup(id: String): Any? {
        val directory = restoreDirectory(id)
        val record = groupRecord(directory)
        for (index in 0 until record.getJSONArray("members").length()) sealRestore(childId(id, index))
        if (record.getString("phase") == "downloading") writeRestoreRecord(directory, record.put("phase", "ready"), "group.json")
        return null
    }

    private fun publishPpssppSavedataGroup(id: String, rollbackId: String, directory: File, record: JSONObject): Any? {
        if (record.getString("phase") == "downloading" ||
            (record.has("rollbackId") && record.getString("rollbackId") != rollbackId)) throw Failure("invalid_restore")
        sealRestoreGroup(id)
        val sourceDirectory = record.getString("source")
        val name = record.getString("name")
        val rollbackDirectory = File(root, rollbackId)
        if (rollbackDirectory.canonicalFile != rollbackDirectory.absoluteFile) throw Failure("invalid_restore")
        val rollback = captured(rollbackDirectory, name, sourceDirectory, restoreBaseline = true, savedata = true)
            ?: throw Failure("invalid_restore")
        val baseline = JSONObject(File(rollbackDirectory, "capture.json").readText())
        val previous = baseline.getJSONArray("files")
        val members = record.getJSONArray("members")
        val present = rollback["savedataGroupPresent"] == true
        @Suppress("DEPRECATION")
        val runtime = activity.packageManager.getPackageInfo(PpssppSaveSettings.PACKAGE, 0)
        if (runtime.versionName != rollback["emulatorVersion"] || runtime.versionName !in setOf("v1.20.4", "1.20.4"))
            throw Failure("runtime_changed")
        @Suppress("DEPRECATION")
        val version = if (android.os.Build.VERSION.SDK_INT >= 28) runtime.longVersionCode else runtime.versionCode.toLong()
        val stageName = ".rshop-save-group-$id"
        fun identity(values: JSONArray, length: Int = 5): LongArray {
            if (values.length() != length) throw Failure("invalid_restore")
            return LongArray(length) { values.getLong(it) }
        }
        fun names(items: JSONArray): List<String> = (0 until items.length()).map { items.getJSONObject(it).getString("name") }
        SaveSourceStorage.open(activity, sourceDirectory.substringBeforeLast('/')).use { storage ->
            fun closed() {
                check()
                try { storage.verifyEmulatorClosed(activity) } catch (error: java.io.IOException) {
                    if (error.message != "emulator_running") throw error
                    throw Failure("stop_ppsspp_required")
                }
            }
            closed()
            val parentIdentity = storage.identity(storage.root).take(2)
            if (record.has("parent") && identity(record.getJSONArray("parent"), 2).toList() != parentIdentity)
                throw Failure("source_changed")
            fun verifyGroup(group: Int, items: JSONArray, original: Boolean = false, subset: Boolean = false): LongArray {
                val before = storage.identity(group)
                val actualNames = storage.saveGroupNames(group)
                val expectedNames = names(items)
                if (if (subset) actualNames.any { it !in expectedNames } else actualNames != expectedNames.sorted())
                    throw Failure("source_changed")
                for (leaf in actualNames) {
                    check()
                    val member = (0 until items.length()).map(items::getJSONObject).single { it.getString("name") == leaf }
                    val fd = storage.openSaveGroupFile(group, leaf, false, false)
                    try {
                        val beforeFile = storage.identity(fd)
                        if (beforeFile[2] != member.getLong("size") ||
                            (original && !same(beforeFile, identity(member.getJSONArray("identity")))) ||
                            digestFd(fd, beforeFile[2], sourceStorage = storage) != member.getString("sha256") ||
                            !same(beforeFile, storage.identity(fd)) || !same(beforeFile, storage.saveGroupEntryIdentity(group, leaf)))
                            throw Failure("source_changed")
                    } finally { storage.closeFile(fd) }
                }
                if (storage.saveGroupNames(group) != actualNames || !same(before, storage.identity(group)) ||
                    storage.currentRootIdentity().take(2) != parentIdentity) throw Failure("source_changed")
                return before
            }
            fun openTarget(): Int? = try { storage.openSaveGroup(name) } catch (error: java.io.IOException) {
                if (error.message != "owned_storage:2") throw error
                null
            }
            var snapshotArmed = false
            fun reviewPrevious(): LongArray? {
                val group = openTarget()
                if (!present) {
                    if (group != null) { storage.closeFile(group); throw Failure("source_changed") }
                    if (identity(baseline.getJSONArray("sourceIdentity"), 2).toList() != parentIdentity)
                        throw Failure("source_changed")
                    return null
                }
                if (group == null) throw Failure("source_changed")
                try {
                    if (storage.identity(group).take(2) != identity(baseline.getJSONArray("sourceIdentity"), 2).toList())
                        throw Failure("source_changed")
                    if (!snapshotArmed) { storage.beginSaveGroupSnapshot(group); snapshotArmed = true }
                    val result = verifyGroup(group, previous, original = true)
                    storage.verifyPpssppSavedataSnapshot()
                    closed()
                    return result
                } finally { storage.closeFile(group) }
            }
            if (record.getString("phase") == "ready") {
                val current = reviewPrevious()
                // An existing stage is never claimed by a new allocation intent.
                if (storage.saveStageExists(stageName)) throw Failure("source_changed")
                record.put("rollbackId", rollbackId).put("parent", JSONArray(parentIdentity)).put("phase", "staging")
                if (current != null) record.put("current", JSONArray(current.toList()))
                writeRestoreRecord(directory, record, "group.json")
            }
            if (record.getString("phase") == "staging") {
                reviewPrevious()
                val stage = if (record.has("stageAnchor")) storage.openSaveGroup(stageName, anchor = identity(record.getJSONArray("stageAnchor")))
                    else {
                        // Intent precedes mkdir. Without an inode receipt only
                        // that intent's empty stage is recoverable; no data is adopted.
                        val created = if (storage.saveStageExists(stageName)) storage.openSaveGroup(stageName, recoverEmpty = true)
                            else storage.openSaveGroup(stageName, createExclusive = true)
                        record.put("stageAnchor", JSONArray(storage.identity(created).toList()))
                        writeRestoreRecord(directory, record, "group.json")
                        created
                    }
                try {
                    if (storage.saveGroupNames(stage).any { it !in names(members) }) throw Failure("source_changed")
                    for (index in 0 until members.length()) {
                        check()
                        val member = members.getJSONObject(index)
                        val leaf = member.getString("name")
                        val privateDirectory = OwnedStorageNative.openRoot(restoreDirectory(childId(id, index)).absolutePath)
                        try {
                            val from = OwnedStorageNative.openFile(privateDirectory, "member", false, false)
                            try {
                                val fromIdentity = OwnedStorageNative.identity(from)
                                if (fromIdentity[2] != member.getLong("size") || digestFd(from, fromIdentity[2]) != member.getString("sha256"))
                                    throw Failure("changed_capture")
                                val target = try { storage.openSaveGroupFile(stage, leaf, false, true) }
                                catch (error: java.io.IOException) {
                                    if (error.message != "owned_storage:2") throw error
                                    storage.openSaveGroupFile(stage, leaf, true, true)
                                }
                                try {
                                    val copied = storage.identity(target)[2]
                                    if (copied > fromIdentity[2]) throw Failure("source_changed")
                                    var offset = 0L
                                    while (offset < fromIdentity[2]) {
                                        check()
                                        val length = minOf(65536L, fromIdentity[2] - offset,
                                            if (offset < copied) copied - offset else 65536L).toInt()
                                        val chunk = OwnedStorageNative.read(from, offset, length)
                                        if (chunk.isEmpty()) throw Failure("changed_capture")
                                        if (offset < copied) {
                                            if (!storage.read(target, offset, length).contentEquals(chunk)) throw Failure("source_changed")
                                        } else storage.write(target, offset, chunk)
                                        offset += chunk.size
                                    }
                                    storage.sync(target)
                                    if (!same(fromIdentity, OwnedStorageNative.identity(from))) throw Failure("changed_capture")
                                } finally { storage.closeFile(target) }
                            } finally { OwnedStorageNative.close(from) }
                        } finally { OwnedStorageNative.close(privateDirectory) }
                    }
                    storage.sync(stage)
                    val staged = verifyGroup(stage, members)
                    val current = reviewPrevious()
                    closed()
                    record.put("staged", JSONArray(staged.toList())).put("phase", "publishing")
                    if (current != null) record.put("current", JSONArray(current.toList()))
                    writeRestoreRecord(directory, record, "group.json")
                } finally { storage.closeFile(stage) }
            }
            if (record.getString("phase") == "publishing") {
                val staged = identity(record.getJSONArray("staged"))
                val target = openTarget()
                var committed = false
                if (target != null) try {
                    if (storage.identity(target).take(2) == staged.take(2)) {
                        if (!snapshotArmed) { storage.beginSaveGroupSnapshot(target); snapshotArmed = true }
                        if (!same(verifyGroup(target, members), staged)) throw Failure("source_changed")
                        storage.verifyPpssppSavedataSnapshot(); closed(); committed = true
                    }
                } finally { storage.closeFile(target) }
                if (!committed) {
                    val current = reviewPrevious()
                    if (present && !same(current!!, identity(record.getJSONArray("current")))) throw Failure("source_changed")
                    val stage = storage.openSaveGroup(stageName, anchor = staged)
                    try {
                        if (!same(verifyGroup(stage, members), staged)) throw Failure("source_changed")
                        if (snapshotArmed) storage.verifyPpssppSavedataSnapshot()
                        closed()
                        val placed = storage.publishSaveGroup(stageName, name, staged, current, version)
                        if (!same(placed, staged)) throw Failure("source_changed")
                    } finally { storage.closeFile(stage) }
                }
                // Cancellation cannot split namespace commit from durable receipt.
                storage.sync(storage.root)
                writeRestoreRecord(directory, record.put("phase", "retiring"), "group.json")
            }
            if (record.getString("phase") == "retiring") {
                closed()
                if (present) {
                    val oldIdentity = identity(record.getJSONArray("current"))
                    val old = try { storage.openSaveGroup(stageName, anchor = oldIdentity) }
                    catch (error: java.io.IOException) { if (error.message != "owned_storage:2") throw error; null }
                    if (old != null) try {
                        verifyGroup(old, previous, original = true, subset = true)
                        for (leaf in storage.saveGroupNames(old)) {
                            check()
                            val member = (0 until previous.length()).map(previous::getJSONObject).single { it.getString("name") == leaf }
                            storage.retireSaveGroupMember(old, leaf, identity(member.getJSONArray("identity")), version)
                        }
                        storage.sync(old)
                    } finally { storage.closeFile(old) }
                    storage.retireSaveGroup(stageName, oldIdentity, version)
                }
                writeRestoreRecord(directory, record.put("phase", "published"), "group.json")
            }
        }
        return null
    }

    private fun publishRestoreGroup(id: String, rollbackId: String): Any? {
        check()
        if (!rollbackId.matches(Regex("[a-f0-9]{32}")) || rollbackId == id) throw Failure("invalid_restore")
        val directory = restoreDirectory(id)
        val record = groupRecord(directory)
        if (record.getString("phase") == "published") return null
        if (record.optString("format") == PpssppSavedataBoundary.FORMAT)
            return publishPpssppSavedataGroup(id, rollbackId, directory, record)
        if (record.getString("phase") == "downloading" ||
            (record.has("rollbackId") && record.getString("rollbackId") != rollbackId)) throw Failure("invalid_restore")
        sealRestoreGroup(id)
        val name = record.getString("name")
        val rollback = captured(File(root, rollbackId), name, restoreBaseline = true) ?: throw Failure("invalid_restore")
        val absent = rollback["localWasAbsent"] == true
        @Suppress("UNCHECKED_CAST") val old = rollback["files"] as List<Map<String, Any>>
        if (!(absent && old.isEmpty()) && !validGroupNames(name, old.map { it["name"] as String })) throw Failure("related_group_changed")
        val members = record.getJSONArray("members")
        fun verifyCurrentGroup() {
            check()
            val parent = OwnedStorageNative.openRoot(MGBA_SOURCE)
            try {
                for (index in 0 until members.length()) {
                    val next = members.getJSONObject(index)
                    val child = restoreRecord(restoreDirectory(childId(id, index)))
                    val targetName = next.getString("name")
                    val stage = File(MGBA_SOURCE, ".rshop-save-restore-${childId(id, index)}")
                    val placed = child.getString("phase") == "published" ||
                        (child.getString("phase") == "publishing" && !stage.exists())
                    if (absent && !placed) {
                        if (!entryAbsent(parent, targetName)) throw Failure("source_changed")
                        continue
                    }
                    val before = old.singleOrNull { it["name"] == targetName }
                    val size = if (placed) next.getLong("size") else (before!!["size"] as Number).toLong()
                    val digest = if (placed) next.getString("sha256") else before!!["sha256"] as String
                    val fd = OwnedStorageNative.openFile(parent, targetName, false, false)
                    try {
                        val identity = OwnedStorageNative.identity(fd)
                        // Before replacement, require the complete stable stat
                        // snapshot. After replacement, the durable child receipt
                        // anchors the committed inode/size and desired digest.
                        // Android FUSE may refresh mtime on the first read after
                        // rename, even for our closed, fsynced file. Mtime is not
                        // the identity of a committed save. Do not retry hashing
                        // or accept a different inode because its bytes match.
                        val committed = if (placed) child.getJSONArray("staged") else null
                        fun matchesCommitted(actual: LongArray): Boolean =
                            committed != null && (0..2).all { actual[it] == committed.getLong(it) }
                        if (identity[2] != size || (placed && !matchesCommitted(identity)) ||
                            digestFd(fd, size) != digest) throw Failure("source_changed")
                        val reviewedIdentity = OwnedStorageNative.identity(fd)
                        val entry = OwnedStorageNative.entryIdentity(parent, targetName)
                        if (if (placed) !matchesCommitted(reviewedIdentity) || !matchesCommitted(entry)
                            else !same(identity, reviewedIdentity) || !same(identity, entry)) throw Failure("source_changed")
                    } finally { OwnedStorageNative.close(fd) }
                }
                val currentParent = OwnedStorageNative.openRoot(MGBA_SOURCE)
                try {
                    if (OwnedStorageNative.identity(parent).take(2) !=
                        OwnedStorageNative.identity(currentParent).take(2)) throw Failure("source_changed")
                } finally { OwnedStorageNative.close(currentParent) }
            } finally { OwnedStorageNative.close(parent) }
        }
        verifyCurrentGroup() // Validate every rollback/committed member before any further mutation.
        writeRestoreRecord(directory, record.put("rollbackId", rollbackId).put("phase", "publishing"), "group.json")
        for (index in 0 until members.length()) {
            verifyCurrentGroup()
            publishRestore(childId(id, index), rollbackId, id)
        }
        verifyCurrentGroup()
        writeRestoreRecord(directory, record.put("phase", "published"), "group.json")
        return null
    }

    fun shutdown(afterClosed: (() -> Unit)? = null) {
        synchronized(guard) { closed = true; cancelled = true; socket?.close() }
        // Queue the admission release AFTER all accepted file work. Closing a
        // Dart engine or cancelling a socket alone is not worker completion.
        if (afterClosed != null) worker.execute { main.post { afterClosed() } }
        worker.shutdown()
    }
}
