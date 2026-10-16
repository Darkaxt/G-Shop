package com.retro.rshop

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.*
import java.util.concurrent.Executors
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import com.google.android.gms.auth.GoogleAuthUtil

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.retro.rshop/zip"
    private val STORAGE_CHANNEL = "com.retro.rshop/storage"
    private val PROGRESS_CHANNEL = "com.retro.rshop/zip_progress"
    private val SMB_CHANNEL = "com.retro.rshop/smb"
    private val SMB_PROGRESS_CHANNEL = "com.retro.rshop/smb_progress"
    private val TAG = "MainActivity"

    private val extractorPool = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val smbService = SmbService()
    private var ownedStorage: OwnedStorageService? = null
    private var romCacheChannel: MethodChannel? = null
    private var saveCapture: SaveCaptureService? = null
    private var socketImport: SocketImportChannel? = null
    private var patchWork: PatchWorkChannel? = null
    private val saveOperationOwner = java.util.UUID.randomUUID().toString()
    private var saveBackgroundChannel: MethodChannel? = null

    private var progressSink: EventChannel.EventSink? = null
    private var smbProgressSink: EventChannel.EventSink? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity onCreate")
        // Acquire a WiFi multicast lock so mDNS / Bonjour discovery (used by
        // NetworkDiscoveryService for SMB/RomM detection) can actually receive
        // multicast packets on Android. Without this, Android silently drops
        // them and the discovery stream stays empty.
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("rshop-mdns")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.d(TAG, "Multicast lock acquired: ${multicastLock?.isHeld}")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire multicast lock: $e")
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // Ensure the Flutter view receives D-pad/gamepad events immediately
            // without needing an initial button press to "activate" the controller.
            // Android doesn't give the content view input focus by default.
            window.decorView.let { view ->
                view.isFocusableInTouchMode = true
                view.requestFocus()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MigrationChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        socketImport = SocketImportChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        patchWork = PatchWorkChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        SaveOperationChannel.attach(flutterEngine.dartExecutor.binaryMessenger, saveOperationOwner)
        saveBackgroundChannel = SaveBackgroundChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        romCacheChannel = RomCacheChannel.attach(this, flutterEngine.dartExecutor.binaryMessenger,true)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.retro.rshop/save_capture").setMethodCallHandler { call, result ->
            val service = saveCapture ?: SaveCaptureService(this).also { saveCapture = it }
            service.handle(call, result)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.retro.rshop/companions").setMethodCallHandler { call, result ->
            if (call.method != "applications") {
                result.notImplemented()
            } else try {
                result.success(CompanionLauncher.applications(this))
            } catch (_: Exception) {
                result.error("companion_apps_unavailable", "Installed app list unavailable", null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.retro.rshop/drive_authorization").setMethodCallHandler { call, result ->
            if (call.method != "clearTokenIfMicroG") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val token = call.argument<String>("token")
            if (token.isNullOrBlank()) {
                result.error("invalid_arguments", "Missing token", null)
                return@setMethodCallHandler
            }
            val microG = try {
                packageManager.getServiceInfo(ComponentName("com.google.android.gms",
                    "org.microg.gms.auth.credentials.identity.AuthorizationService"), 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
            if (!microG) {
                result.success(false)
                return@setMethodCallHandler
            }
            extractorPool.execute {
                try {
                    // microG uses the same OAuth token cache for both APIs. Its
                    // older native auth service implements this synchronous call.
                    // No timeout, account removal, persisted token or raw log.
                    @Suppress("DEPRECATION")
                    GoogleAuthUtil.clearToken(applicationContext, token)
                    mainHandler.post { result.success(true) }
                } catch (_: Exception) {
                    mainHandler.post {
                        result.error("unavailable", "Token cache clear failed", null)
                    }
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractZip" -> {
                    val zipPath = call.argument<String>("zipPath")
                    val targetPath = call.argument<String>("targetPath")

                    if (zipPath == null || targetPath == null) {
                        result.error("INVALID_ARGS", "zipPath and targetPath required", null)
                        return@setMethodCallHandler
                    }

                    extractorPool.execute {
                        try {
                            val extractedFiles = extractZip(zipPath, targetPath)
                            mainHandler.post {
                                result.success(extractedFiles)
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("EXTRACT_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // SMB Progress EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMB_PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smbProgressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    smbProgressSink = null
                }
            }
        )

        // SMB MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMB_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "testConnection" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments required", null)
                        return@setMethodCallHandler
                    }
                    smbService.smbPool.execute {
                        try {
                            val response = smbService.testConnection(args)
                            mainHandler.post { result.success(response) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SMB_ERROR", e.message, null) }
                        }
                    }
                }
                "listFiles" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments required", null)
                        return@setMethodCallHandler
                    }
                    smbService.smbPool.execute {
                        try {
                            val files = smbService.listFiles(args)
                            mainHandler.post { result.success(files) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("SMB_ERROR", e.message, null) }
                        }
                    }
                }
                "startDownload" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        smbService.startDownload(args, smbProgressSink, mainHandler)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SMB_ERROR", e.message, null)
                    }
                }
                "cancelDownload" -> {
                    val downloadId = call.argument<String>("downloadId")
                    if (downloadId == null) {
                        result.error("INVALID_ARGS", "downloadId required", null)
                        return@setMethodCallHandler
                    }
                    smbService.cancelDownload(downloadId)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method.startsWith("owned") || call.method == "localCopyInspect" || call.method == "launchOwnedDolphin" ||
                call.method == "launchOwnedRetroArchGameGear" || call.method == "launchOwnedRetroArchN64" ||
                call.method == "launchOwnedRetroArchMegaDrive" || call.method == "launchOwnedRetroArchMasterSystem" ||
                call.method == "launchOwnedRetroArchSG1000" ||
                call.method == "launchOwnedRetroArchGameBoy" ||
                call.method == "launchOwnedRetroArchNes" ||
                call.method == "launchOwnedRetroArchSnes" ||
                call.method == "launchOwnedRetroArchGameBoyColor" || call.method == "launchOwnedRetroArchGameBoyAdvance" ||
                call.method == "reviewOwnedRetroArchGameBoyAdvanceSave" ||
                call.method == "reviewOwnedRetroArchGameGearSave" ||
                call.method == "reviewOwnedRetroArchMasterSystemSave" ||
                call.method == "reviewOwnedRetroArchMegaDriveSave" ||
                call.method == "reviewOwnedRetroArchN64Save" ||
                call.method == "reviewOwnedRetroArchNesSave" ||
                call.method == "reviewOwnedRetroArchSnesSave" ||
                call.method == "reviewOwnedRetroArchGameBoySave" ||
                call.method == "reviewOwnedRetroArchGameBoyColorSave" ||
                call.method == "reviewOwnedRetroArchPcsxSaves" ||
                call.method == "launchOwnedRetroArchPSX" || call.method == "launchOwnedPPSSPP" ||
                call.method == "launchOwnedNetherSX2" || call.method == "launchOwnedCemu" ||
                call.method == "launchOwnedMelon" || call.method == "reviewOwnedMelonSave") {
                val service = ownedStorage ?: OwnedStorageService(applicationContext).also { ownedStorage = it }
                service.handle(call, result)
                return@setMethodCallHandler
            }
            when (call.method) {
                "getFreeSpace" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGS", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val stat = StatFs(path)
                        val freeBytes = stat.availableBytes
                        val totalBytes = stat.totalBytes
                        result.success(mapOf("freeBytes" to freeBytes, "totalBytes" to totalBytes))
                    } catch (e: Exception) {
                        result.error("STAT_ERROR", e.message, null)
                    }
                }
                "getDeviceMemory" -> {
                    try {
                        val am = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        val memInfo = android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(memInfo)
                        result.success(mapOf("totalBytes" to memInfo.totalMem))
                    } catch (e: Exception) {
                        result.error("MEMORY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        patchWork?.dispose()
        socketImport?.dispose()
        val captures = saveCapture
        if (captures != null) captures.shutdown { SaveOperationChannel.detach(saveOperationOwner) }
        else SaveOperationChannel.detach(saveOperationOwner)
        val owned = ownedStorage
        if(owned!=null)owned.shutdown { RomCacheChannel.detach(romCacheChannel) }
        else RomCacheChannel.detach(romCacheChannel)
        extractorPool.shutdown()
        smbService.shutdown()
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release multicast lock: $e")
        }
        super.onDestroy()
        SaveBackgroundChannel.detach(saveBackgroundChannel)
    }

    private fun sendProgress(extractedBytes: Long, totalBytes: Long) {
        val sink = progressSink ?: return
        if (totalBytes <= 0) return
        val percent = (extractedBytes.toDouble() / totalBytes * 100).toInt().coerceIn(0, 100)
        mainHandler.post {
            sink.success(mapOf("extracted" to extractedBytes, "total" to totalBytes, "percent" to percent))
        }
    }

    private val MAX_EXTRACT_BYTES = 8L * 1024 * 1024 * 1024 // 8 GB guard

    private fun extractZip(zipPath: String, targetPath: String): List<String> {
        val extractedFiles = mutableListOf<String>()
        val buffer = ByteArray(65536)
        var totalBytes = 0L
        var extractedBytes = 0L

        // Get total size via ZipFile (random-access, reads only central directory)
        try {
            ZipFile(zipPath).use { zf ->
                val entries = zf.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.size > 0) totalBytes += entry.size
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ZipFile size scan failed, progress will be unavailable: ${e.message}")
            totalBytes = 0
        }

        // Extract files
        File(zipPath).inputStream().use { fis ->
            val zis = ZipInputStream(BufferedInputStream(fis, 65536))
            var entry = zis.nextEntry

            val canonicalTarget = File(targetPath).canonicalPath
            var lastReportedPercent = -1

            while (entry != null) {
                val file = File(targetPath, entry.name)

                // Zip Slip protection: reject entries that escape the target directory
                if (!file.canonicalPath.startsWith(canonicalTarget + File.separator) &&
                    file.canonicalPath != canonicalTarget) {
                    entry = zis.nextEntry
                    continue
                }

                if (entry.isDirectory) {
                    file.mkdirs()
                } else {
                    file.parentFile?.mkdirs()

                    BufferedOutputStream(FileOutputStream(file), 65536).use { bos ->
                        var len: Int
                        while (zis.read(buffer).also { len = it } > 0) {
                            bos.write(buffer, 0, len)
                            extractedBytes += len
                            if (extractedBytes > MAX_EXTRACT_BYTES) {
                                throw IOException("Zip bomb detected: extracted data exceeds ${MAX_EXTRACT_BYTES / (1024 * 1024 * 1024)} GB limit")
                            }
                        }
                    }

                    extractedFiles.add(entry.name)

                    // Report progress (throttle: only on percent change)
                    if (totalBytes > 0) {
                        val currentPercent = (extractedBytes.toDouble() / totalBytes * 100).toInt()
                        if (currentPercent != lastReportedPercent) {
                            lastReportedPercent = currentPercent
                            sendProgress(extractedBytes, totalBytes)
                        }
                    }
                }

                entry = zis.nextEntry
            }

            zis.close()
        }

        return extractedFiles
    }

}
