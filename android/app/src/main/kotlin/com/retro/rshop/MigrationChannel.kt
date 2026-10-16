package com.retro.rshop

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Maintenance admission persists across a process death. Recovery clears it
 * only after the private restore journal is settled, before normal bootstrap. */
internal object MigrationChannel {
    const val NAME = "com.retro.rshop/migration"
    @Volatile var busy = false
        private set
    private var jobs = 0
    private val quiescence = mutableListOf<MethodChannel.Result>()
    fun active(context: Context): Boolean = context.getSharedPreferences(
        "migration-maintenance", Context.MODE_PRIVATE).getBoolean("active", false)
    fun jobStarted() { jobs++ }
    fun jobFinished() {
        check(jobs > 0); jobs--
        if (jobs == 0) {
            val replies = quiescence.toList(); quiescence.clear()
            replies.forEach { it.success(null) }
        }
    }
    fun attach(activity: Activity, messenger: BinaryMessenger) {
        busy = active(activity)
        MethodChannel(messenger, NAME).setMethodCallHandler { call, reply ->
            try {
                when (call.method) {
                    "maintenance" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: throw IllegalArgumentException()
                        check(activity.getSharedPreferences("migration-maintenance", Context.MODE_PRIVATE)
                            .edit().putBoolean("active", enabled).commit())
                        busy = enabled; reply.success(null)
                    }
                    "quiescent" -> {
                        check(busy && quiescence.isEmpty())
                        if (jobs == 0) reply.success(null) else quiescence.add(reply)
                    }
                    "restart" -> {
                        val component = activity.packageManager.getLaunchIntentForPackage(activity.packageName)
                            ?.component ?: throw IllegalStateException()
                        reply.success(null)
                        activity.startActivity(Intent.makeRestartActivityTask(component))
                    }
                    else -> reply.notImplemented()
                }
            } catch (_: Exception) { reply.error("migration_unavailable", "Migration unavailable", null) }
        }
    }
}
