package com.retro.rshop

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.PersistableBundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

/** Main-thread, process-wide admission for UI/headless cache engines. Ownership
 * ends on actual joined completion/detach, never on a timer or a stale lease. */
internal object RomCacheChannel {
    const val NAME = "com.darkaxt.gshop/rom_cache"
    const val PERIODIC_ID = 0x525344
    const val EXPIRY_ID = 0x525345
    private const val PERIOD = 6L*60*60*1000
    private data class Waiting(val channel: MethodChannel, val reply: MethodChannel.Result,
        val migration: Boolean = false)
    private val waiting = ArrayDeque<Waiting>()
    private var owner: MethodChannel? = null
    var foreground: MethodChannel? = null
        private set
    private var runningJobs = 0
    private val detached = mutableSetOf<() -> Unit>()

    fun attach(context: Context, messenger: BinaryMessenger, foregroundEngine: Boolean,
        ready: (() -> Unit)? = null): MethodChannel {
        val channel = MethodChannel(messenger, NAME)
        channel.setMethodCallHandler { call, reply ->
            try {
                when(call.method) {
                    "ready" -> { if (foregroundEngine) foreground = channel; reply.success(null); ready?.invoke() }
                    "acquire" -> {
                        check(owner !== channel && waiting.none { it.channel === channel })
                        val migration = call.argument<Boolean>("migration") == true
                        if(MigrationChannel.busy && !migration) {
                            reply.error("migration_in_progress","Migration in progress",null)
                        } else { waiting.add(Waiting(channel, reply, migration)); admit() }
                    }
                    "cancelAdmission" -> {
                        val cancelled = waiting.filter { it.channel === channel }
                        waiting.removeAll(cancelled.toSet())
                        cancelled.forEach { it.reply.error("cancelled","Cleanup stopped",null) }
                        reply.success(null)
                    }
                    "release" -> { check(owner === channel); owner = null; reply.success(null); admit() }
                    "schedule" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: throw IllegalArgumentException()
                        val due = call.argument<Number>("dueMillis")?.toLong()
                        context.getSharedPreferences("rom-cache-schedule",Context.MODE_PRIVATE).edit()
                            .putBoolean("enabled",enabled).putLong("due",due ?: -1).commit()
                        applySchedule(context); reply.success(null)
                    }
                    else -> reply.notImplemented()
                }
            } catch (_: Exception) { reply.error("cache_unavailable","Cleanup unavailable",null) }
        }
        return channel
    }
    private fun admit() {
        if (owner != null || waiting.isEmpty()) return
        val next = waiting.removeFirst()
        if(MigrationChannel.busy && !next.migration) {
            next.reply.error("migration_in_progress","Migration in progress",null); admit()
        } else { owner = next.channel; next.reply.success(null) }
    }
    fun watchDetach(channel:MethodChannel, callback:()->Unit):()->Unit {
        if (foreground === channel) detached.add(callback) else callback()
        return { detached.remove(callback) }
    }
    fun detach(channel:MethodChannel?) {
        if(channel==null)return
        val cancelled=waiting.filter { it.channel === channel }
        waiting.removeAll(cancelled.toSet())
        cancelled.forEach { it.reply.error("cancelled","Cleanup engine closed",null) }
        if(owner === channel) owner=null
        if(foreground === channel) {
            foreground=null; val callbacks=detached.toList();detached.clear();callbacks.forEach { it() }
        }
        admit()
    }
    fun jobStarted() { runningJobs++ }
    fun jobFinished(context:Context) { runningJobs--; check(runningJobs>=0); applySchedule(context) }
    private fun applySchedule(context:Context) {
        if(runningJobs!=0)return // Do not replace/cancel an admitted pass.
        val prefs=context.getSharedPreferences("rom-cache-schedule",Context.MODE_PRIVATE)
        val scheduler=context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        if(!prefs.getBoolean("enabled",false)) { scheduler.cancel(PERIODIC_ID);scheduler.cancel(EXPIRY_ID);return }
        val periodic=ComponentName(context,RomCacheJobService::class.java)
        val old=scheduler.getPendingJob(PERIODIC_ID)
        if(old?.service!=periodic || !old.isPeriodic || old.intervalMillis!=PERIOD || !old.isPersisted) {
            check(scheduler.schedule(JobInfo.Builder(PERIODIC_ID,periodic).setPersisted(true)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(PERIOD).build())==JobScheduler.RESULT_SUCCESS)
        }
        val due=prefs.getLong("due",-1)
        if(due<0) { scheduler.cancel(EXPIRY_ID);return }
        val expiry=ComponentName(context,ExpiryRomCacheJobService::class.java)
        val scheduled=scheduler.getPendingJob(EXPIRY_ID)
        if(scheduled?.service==expiry && scheduled.extras.getLong("due",-1)==due)return
        val extras=PersistableBundle().apply { putLong("due",due) }
        check(scheduler.schedule(JobInfo.Builder(EXPIRY_ID,expiry).setPersisted(true)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setMinimumLatency((due-System.currentTimeMillis()).coerceAtLeast(0))
            .setExtras(extras).build())==JobScheduler.RESULT_SUCCESS)
    }
}
