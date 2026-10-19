package com.retro.rshop

import android.util.Log
import com.tekartik.sqflite.SqflitePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/** Close only this engine's SQLite connections, including abandoned transactions. */
class EngineOwnedSqflitePlugin : SqflitePlugin() {
    private val owner = nextOwner.incrementAndGet()
    private val handles = EngineDatabaseHandles { method, arguments, reply ->
        super.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
            override fun success(value: Any?) {
                if (method == "openDatabase" || method == "closeDatabase")
                    Log.i("RShopDatabaseOwner", "owner=$owner phase=${if (method == "openDatabase") "opened" else "closed"}")
                reply.success(value)
            }
            override fun error(code: String, message: String?, details: Any?) = reply.error(code, message, details)
            override fun notImplemented() = reply.notImplemented()
        })
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        handles.call(call.method, call.arguments, object : EngineDatabaseHandles.Reply {
            override fun success(value: Any?) = result.success(value)
            override fun error(code: String, message: String?, details: Any?) = result.error(code, message, details)
            override fun notImplemented() = result.notImplemented()
        })
    }
    fun closeOwnedDatabases() = handles.close()
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        closeOwnedDatabases()
        super.onDetachedFromEngine(binding)
    }
    companion object {
        private val nextOwner = AtomicInteger()
        fun install(engine: FlutterEngine) {
            engine.plugins.remove(SqflitePlugin::class.java)
            if (!engine.plugins.has(EngineOwnedSqflitePlugin::class.java))
                engine.plugins.add(EngineOwnedSqflitePlugin())
        }
    }
}
