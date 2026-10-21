package com.retro.rshop

import android.app.job.JobParameters
import android.app.job.JobService
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** One policy pass, optionally headless. No Activity, consent or screen wake. */
open class RomCacheJobService:JobService() {
    private var engine:FlutterEngine?=null
    private var storage:OwnedStorageService?=null
    private var channel:MethodChannel?=null
    private var params:JobParameters?=null
    private var stopped=false
    private var finished=false
    private var detach:(()->Unit)?=null
    override fun onStartJob(parameters:JobParameters):Boolean {
        if(MigrationChannel.active(applicationContext))return false
        MigrationChannel.jobStarted()
        params=parameters;stopped=false;finished=false;RomCacheChannel.jobStarted()
        val current=RomCacheChannel.foreground
        if(current!=null) {
            channel=current
            detach=RomCacheChannel.watchDetach(current){ finish("engine_closed") }
            run()
        } else try {
            val loader=FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext);loader.ensureInitializationComplete(applicationContext,null)
            val runtime=FlutterEngine(applicationContext);engine=runtime
            EngineOwnedSqflitePlugin.install(runtime)
            val messenger=runtime.dartExecutor.binaryMessenger
            val io=OwnedStorageService(applicationContext);storage=io
            MethodChannel(messenger,"com.darkaxt.gshop/storage").setMethodCallHandler { call,reply ->
                if(call.method.startsWith("owned")) io.handle(call,reply) else reply.notImplemented()
            }
            DriveTokenCacheChannel.attach(applicationContext,messenger)
            channel=RomCacheChannel.attach(applicationContext,messenger,false) { if(stopped)stop() else run() }
            runtime.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),
                "package:g_shop/services/rom_cache_background.dart","romCacheBackground"))
        } catch(_:Exception){finish("startup_unavailable")}
        return true
    }
    private fun run() {
        if(finished)return
        channel?.invokeMethod("run",null,object:MethodChannel.Result {
            override fun success(result:Any?)=finish(null,result)
            override fun error(code:String,message:String?,details:Any?)=finish("dispatch_unavailable")
            override fun notImplemented()=finish("dispatch_unavailable")
        })
    }
    override fun onStopJob(parameters:JobParameters):Boolean { stopped=true;stop();return parameters.jobId==RomCacheChannel.EXPIRY_ID }
    private fun stop() {
        if(finished)return
        channel?.invokeMethod("stop",null,object:MethodChannel.Result {
            override fun success(result:Any?)=finish("stopped")
            override fun error(code:String,message:String?,details:Any?)=finish("stop_unavailable")
            override fun notImplemented()=finish("stop_unavailable")
        })
    }
    private fun finish(issue:String?,summary:Any?=null) {
        if(finished)return;finished=true;detach?.invoke();detach=null
        getSharedPreferences("rom-cache-dispatch",MODE_PRIVATE).edit()
            .putString("outcome",issue ?: "completed").putLong("finishedAt",System.currentTimeMillis())
            .putInt("removed",((summary as? Map<*,*>)?.get("removed") as? Number)?.toInt() ?: 0).apply()
        val owned=storage;storage=null
        fun close() {
            if(engine!=null)RomCacheChannel.detach(channel)
            engine?.destroy();engine=null
            if(!stopped)params?.let { jobFinished(it,false) }
            params=null;channel=null;RomCacheChannel.jobFinished(applicationContext)
            MigrationChannel.jobFinished()
        }
        if(owned!=null)owned.shutdown(::close) else close()
    }
}
class ExpiryRomCacheJobService:RomCacheJobService()
