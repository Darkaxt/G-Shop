package com.retro.rshop

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
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

    fun attach(context: Context, messenger: BinaryMessenger): MethodChannel {
        val channel = MethodChannel(messenger, NAME)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "ready" -> { foreground = channel; result.success(null) }
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
    fun detach(channel: MethodChannel?) {
        if (channel != null && foreground === channel) {
            foreground = null
            val notify = detached
            detached = null
            notify?.invoke()
        }
    }
}
