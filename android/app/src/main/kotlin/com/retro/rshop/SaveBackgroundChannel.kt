package com.retro.rshop

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Android owns periodic admission. No timer, exact alarm or screen wake. */
internal object SaveBackgroundChannel {
    const val JOB_ID = 0x525342
    const val PERIOD_MS = 6L * 60 * 60 * 1000
    const val NAME = "com.retro.rshop/save_background"
    var foreground: MethodChannel? = null
        private set
    private var detached: (() -> Unit)? = null
    private var watch: SaveFileWatch? = null
    // Joining root children must never block Flutter's platform/UI thread.
    private val watchLane = Executors.newSingleThreadExecutor { work -> Thread(work, "rshop-save-watch-owner") }
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var watchGeneration = 0L

    fun attach(context: Context, messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, NAME)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ready" -> {
                        if (foreground !== channel) stopWatch()
                        foreground = channel; result.success(null)
                    }
                    "watch" -> {
                        check(foreground === channel)
                        val mappings = SaveFileWatch.decode(call.argument<List<Any>>("mappings")
                            ?: throw IllegalArgumentException())
                        val token = ++watchGeneration
                        val delivery = SaveWatchDelivery(
                            { foreground === channel && token == watchGeneration },
                            { key, done, failed -> channel.invokeMethod("changed", key,
                                object : MethodChannel.Result {
                                    override fun success(result: Any?) { done() }
                                    override fun error(code: String, message: String?, details: Any?) { failed() }
                                    override fun notImplemented() { failed() }
                                }) },
                            { channel.invokeMethod("watchUnavailable", null) })
                        watchLane.execute {
                            try {
                                watch?.close(); watch = null
                                if (token != watchGeneration) {
                                    main.post { result.error("watch_unavailable", "Save watch changed", null) }
                                    return@execute
                                }
                                val observer = SaveFileWatch(context.applicationContext,
                                    unavailable = delivery::unavailable, changed = delivery::changed)
                                    .also { watch = it }
                                val receipt = observer.replace(mappings)
                                main.post {
                                    if (foreground === channel && token == watchGeneration) {
                                        result.success(receipt)
                                        delivery.admitted()
                                    }
                                    else result.error("watch_unavailable", "Save watch changed", null)
                                }
                            } catch (_: Exception) {
                                main.post { result.error("watch_unavailable", "Save watch unavailable", null) }
                            }
                        }
                    }
                    "schedule" -> {
                        val enabled = call.argument<Boolean>("enabled")
                            ?: throw IllegalArgumentException()
                        schedule(context, enabled)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("schedule_unavailable", "Background backup schedule unavailable", null)
            }
        }
        return channel
    }

    fun schedule(context: Context, enabled: Boolean) {
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        if (!enabled) { scheduler.cancel(JOB_ID); return }
        val component = ComponentName(context, SaveBackupJobService::class.java)
        val old = scheduler.getPendingJob(JOB_ID)
        if (old?.service == component && old.isPeriodic && old.isPersisted &&
            old.intervalMillis == PERIOD_MS && old.networkType == JobInfo.NETWORK_TYPE_ANY) return
        val info = JobInfo.Builder(JOB_ID, component)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(PERIOD_MS).setPersisted(true).build()
        check(scheduler.schedule(info) == JobScheduler.RESULT_SUCCESS)
    }

    fun watchDetach(channel: MethodChannel, callback: () -> Unit) {
        if (foreground === channel) detached = callback else callback()
    }
    fun unwatchDetach() { detached = null }
    private fun stopWatch() {
        watchGeneration++
        watchLane.execute { watch?.close(); watch = null }
    }
    fun detach(channel: MethodChannel?) {
        if (channel != null && foreground === channel) {
            stopWatch()
            foreground = null
            val notify = detached
            detached = null
            notify?.invoke()
        }
    }
}
