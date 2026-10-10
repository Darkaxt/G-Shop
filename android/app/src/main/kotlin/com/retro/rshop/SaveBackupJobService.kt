package com.retro.rshop

import android.app.job.JobParameters
import android.app.job.JobService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** One bounded mapping pass. Never starts an Activity or accepts auth consent. */
class SaveBackupJobService : JobService() {
    private var engine: FlutterEngine? = null
    private var capture: SaveCaptureService? = null
    private var channel: MethodChannel? = null
    private var parameters: JobParameters? = null
    private var owner: String? = null
    private var stopped = false
    private var finished = false

    override fun onStartJob(params: JobParameters): Boolean {
        parameters = params; stopped = false; finished = false
        val foreground = SaveBackgroundChannel.foreground
        if (foreground != null) {
            channel = foreground
            SaveBackgroundChannel.watchDetach(foreground) { finishPass("engine_detached") }
            runPass()
        } else try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val runtime = FlutterEngine(applicationContext)
            engine = runtime
            val messenger = runtime.dartExecutor.binaryMessenger
            val identity = UUID.randomUUID().toString()
            owner = identity
            SaveOperationChannel.attach(messenger, identity)
            val captures = SaveCaptureService(applicationContext)
            capture = captures
            MethodChannel(messenger, "com.retro.rshop/save_capture")
                .setMethodCallHandler(captures::handle)
            DriveTokenCacheChannel.attach(applicationContext, messenger)
            channel = MethodChannel(messenger, SaveBackgroundChannel.NAME).also { bridge ->
                bridge.setMethodCallHandler { call, reply ->
                    if (call.method == "ready") {
                        reply.success(null)
                        if (stopped) stopPass() else runPass()
                    } else reply.notImplemented()
                }
            }
            runtime.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:retro_eshop/services/saves/save_backup_background.dart",
                "saveBackupBackground"))
        } catch (_: Exception) { finishPass("startup_unavailable") }
        return true
    }

    private fun runPass() {
        if (finished) return
        channel?.invokeMethod("run", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finishPass(null, result)
            override fun error(code: String, message: String?, details: Any?) = finishPass("dispatch_unavailable")
            override fun notImplemented() = finishPass("dispatch_unavailable")
        })
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopped = true
        stopPass()
        // The durable journal and next periodic/startup event retain recovery.
        // Do not start an immediate unbounded retry loop.
        return false
    }

    private fun stopPass() {
        if (finished) return
        channel?.invokeMethod("stop", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finishPass("stopped")
            override fun error(code: String, message: String?, details: Any?) = finishPass("stop_unavailable")
            override fun notImplemented() = finishPass("stop_unavailable")
        })
    }

    private fun finishPass(issue: String?, summary: Any? = null) {
        if (finished) return
        finished = true
        SaveBackgroundChannel.unwatchDetach()
        // Fixed diagnostic codes only: no account, paths, tokens or save data.
        val receipt = getSharedPreferences("save-background-dispatch", MODE_PRIVATE).edit()
            .putString("outcome", issue ?: "completed")
            .putLong("finishedAt", System.currentTimeMillis())
        for (key in listOf("enabled", "pending", "verified", "unchanged", "attention")) {
            val count = (summary as? Map<*, *>)?.get(key) as? Number
            if (count != null && count.toLong() in 0..4096L) receipt.putLong(key, count.toLong())
            else receipt.remove(key)
        }
        receipt.apply()
        val captures = capture
        capture = null
        if (captures != null) captures.shutdown { closeRuntime() }
        else closeRuntime()
    }

    private fun closeRuntime() {
        engine?.destroy()
        engine = null
        owner?.let(SaveOperationChannel::detach)
        owner = null
        if (!stopped) parameters?.let { jobFinished(it, false) }
        parameters = null
        channel = null
    }
}
