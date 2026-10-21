package com.retro.rshop

import android.app.Activity
import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/** Owns only the G-Shop non-focusable window. Never manipulates another task. */
class PreviewChannel(private val activity: Activity, messenger: BinaryMessenger) :
    DisplayManager.DisplayListener {
    private val displays = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val channel = MethodChannel(messenger, "com.darkaxt.gshop/preview")
    private var presentation: PreviewPresentation? = null
    private var payload: Map<String, Any?>? = null
    private var resumed = true
    private var disposed = false
    private var enabled = false
    private var preparation: Map<String, Any?> = emptyMap()
    private val startedAt = SystemClock.elapsedRealtimeNanos()
    private val debug = activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0

    init {
        displays.registerDisplayListener(this, Handler(Looper.getMainLooper()))
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(display() != null)
                "prepare" -> {
                    enabled = call.argument<Boolean>("enabled") == true
                    preparation = mapOf("resourceRoot" to call.argument<String>("resourceRoot"),
                        "resourceGeneration" to call.argument<String>("resourceGeneration"))
                    if (enabled) prepare() else { payload = null; dismiss(release = true) }
                    result.success(null)
                }
                "present" -> {
                    @Suppress("UNCHECKED_CAST")
                    payload = call.arguments as? Map<String, Any?>
                    show()
                    result.success(null)
                }
                "hide" -> { payload = null; dismiss(); result.success(null) }
                "playback" -> {
                    val view = presentation
                    if (view != null && call.argument<Any>("actionEpoch") == payload?.get("actionEpoch")) view.togglePlayback(result)
                    else result.error("preview_hidden", "Preview is no longer active", null)
                }
                "diagnostics" -> if (!debug) result.notImplemented() else result.success(mapOf(
                    "available" to (display() != null), "visible" to (presentation?.isShowing == true),
                    "mainFocused" to activity.window.decorView.hasWindowFocus(),
                    "displayId" to presentation?.display?.displayId, "prepared" to presentation?.prepared,
                    "rendered" to presentation?.rendered,
                    "playback" to presentation?.playback))
                "awaitRendered" -> if (!debug) result.notImplemented() else {
                    val view = presentation
                    if (view == null) result.error("preview_hidden", "Preview is hidden", null)
                    else view.awaitRendered(call.argument<String>("identity"),
                        call.argument<Boolean>("video") == true, call.argument<Boolean>("model") == true, result)
                }
                "wifi" -> {
                    val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                    result.success(capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun display(): Display? = displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        .filter { it.isValid && it.state == Display.STATE_ON && it.displayId != Display.DEFAULT_DISPLAY &&
            it.flags and Display.FLAG_PRIVATE == 0 }.singleOrNull()

    private fun prepare() {
        if (!enabled || !resumed || disposed) return
        val display = display() ?: run { dismiss(release = true); return }
        if (presentation?.display?.displayId != display.displayId) dismiss(release = true)
        if (presentation == null) {
            val view = PreviewPresentation(activity, display,
                startedAt = startedAt,
                onAction = { action -> channel.invokeMethod("action", action) },
                onPlaying = { state ->
                    if (state["actionEpoch"] == payload?.get("actionEpoch") && state["video"] == payload?.get("video"))
                        channel.invokeMethod("playing", state)
                })
            presentation = view
        }
        presentation?.prepare(preparation)
    }
    private fun show() {
        if (!enabled || !resumed || disposed || payload == null) return
        prepare()
        val view = presentation ?: return
        try {
            if (!view.isShowing) view.show()
            view.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
        } catch (_: WindowManager.InvalidDisplayException) { dismiss(release = true); return }
        presentation?.update(payload!!)
    }
    private fun dismiss(release: Boolean = false) {
        presentation?.let { it.hideRenderer(); it.dismiss(); if (release) it.release() }
        if (release) presentation = null
    }
    fun resume() { resumed = true; prepare(); show() }
    fun pause() { resumed = false; dismiss() }
    private fun changed() {
        channel.invokeMethod("availability", display() != null)
        if (display() == null) dismiss(release = true) else { prepare(); show() }
    }
    override fun onDisplayAdded(displayId: Int) = changed()
    override fun onDisplayRemoved(displayId: Int) = changed()
    override fun onDisplayChanged(displayId: Int) = changed()
    fun dispose() {
        disposed = true; payload = null; dismiss(release = true)
        displays.unregisterDisplayListener(this)
        channel.setMethodCallHandler(null)
    }

    private class PreviewPresentation(activity: Activity, display: Display,
        private val startedAt: Long,
        private val onAction: (Any?) -> Unit,
        private val onPlaying: (Map<String, Any?>) -> Unit) : Presentation(activity, display) {
        private var engine: FlutterEngine? = null
        private var flutterView: FlutterView? = null
        private var channel: MethodChannel? = null
        private var ready = false
        private var preparation: Map<String, Any?>? = null
        var prepared = false
            private set
        private var latest: Map<String, Any?>? = null
        private var selectionAt = 0L
        var rendered: Map<String, Any?>? = null
            private set
        var playback: Map<String, Any?>? = null
            private set
        private data class Waiter(val identity: String?, val revision: Any?, val video: Boolean, val model: Boolean, val result: MethodChannel.Result)
        private val waiters = mutableListOf<Waiter>()
        private fun matches(waiter: Waiter): Boolean {
            val state = rendered ?: return false
            return (waiter.identity == null || state["identity"] == waiter.identity) &&
                state["revision"] == waiter.revision &&
                (!waiter.video || state["videoReady"] == true) &&
                (!waiter.model || (state["model"] as? Map<*, *>)?.get("frameRendered") == true)
        }
        fun awaitRendered(identity: String?, video: Boolean, model: Boolean, result: MethodChannel.Result) {
            val waiter = Waiter(identity, latest?.get("revision"), video, model, result)
            if (matches(waiter)) result.success(rendered) else waiters.add(waiter)
        }
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            window?.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
            window?.decorView?.systemUiVisibility =
                android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            val renderer = engine ?: error("Preview renderer was not prepared")
            flutterView = FlutterView(context).also { view ->
                view.attachToFlutterEngine(renderer)
                setContentView(view)
            }
        }
        fun prepare(value: Map<String, Any?>) {
            if (preparation != value) {
                preparation = value; prepared = false
                if (ready) channel?.invokeMethod("prepare", value)
            }
            if (engine != null) return
            // Rendering needs only a file-backed player. Do not attach account,
            // database, foreground-download or save plugins to this engine.
            val renderer = FlutterEngine(context, null, false)
            renderer.plugins.add(io.flutter.plugins.videoplayer.VideoPlayerPlugin())
            engine = renderer
            channel = MethodChannel(renderer.dartExecutor.binaryMessenger, "com.darkaxt.gshop/preview_view").also { bridge ->
                bridge.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> {
                            ready = true
                            Log.i("GShopPreview", "renderer_ready elapsedUs=${(SystemClock.elapsedRealtimeNanos()-startedAt)/1000} showing=$isShowing")
                            preparation?.let { bridge.invokeMethod("prepare", it) }
                            latest?.let { bridge.invokeMethod("snapshot", it) }
                            if (!isShowing) renderer.lifecycleChannel.appIsPaused()
                            result.success(null)
                        }
                        "prepared" -> {
                            prepared = true
                            Log.i("GShopPreview", "resources_ready elapsedUs=${(SystemClock.elapsedRealtimeNanos()-startedAt)/1000} showing=$isShowing")
                            result.success(null)
                        }
                        "action" -> { onAction(call.arguments); result.success(null) }
                        "playing" -> {
                            @Suppress("UNCHECKED_CAST")
                            val state = call.arguments as? Map<String, Any?>
                            if (state != null) { playback = state; onPlaying(state) }
                            result.success(null)
                        }
                        "rendered" -> {
                            @Suppress("UNCHECKED_CAST")
                            rendered = call.arguments as? Map<String, Any?>
                            val selection = (rendered?.get("identity") as? String)?.let {
                                MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).joinToString("") { byte -> "%02x".format(byte) }
                            }
                            Log.i("GShopPreview", "rendered selection=$selection selectionUs=${(SystemClock.elapsedRealtimeNanos()-selectionAt)/1000} model=${(rendered?.get("model") as? Map<*, *>)?.get("frameRendered")} cover=${(rendered?.get("media") as? Map<*, *>)?.get("coverExpected")} label=${(rendered?.get("media") as? Map<*, *>)?.get("labelDecoded")} resources=${(rendered?.get("media") as? Map<*, *>)?.get("resourcesReady")} video=${rendered?.get("videoReady")} playing=${rendered?.get("videoPlaying")} volume=${rendered?.get("videoVolume")} reveal=${rendered?.get("revealStarted")} completed=${rendered?.get("revealCompleted")}")
                            val completed = waiters.filter { matches(it) }
                            waiters.removeAll(completed.toSet())
                            completed.forEach { it.result.success(rendered) }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
            renderer.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "previewMain"))
            renderer.lifecycleChannel.appIsInactive()
        }
        fun update(value: Map<String, Any?>) {
            engine?.lifecycleChannel?.appIsResumed()
            if (latest?.get("identity") != value["identity"]) selectionAt = SystemClock.elapsedRealtimeNanos()
            latest = value
            if (ready) channel?.invokeMethod("snapshot", value)
        }
        fun togglePlayback(result: MethodChannel.Result) {
            channel?.invokeMethod("togglePlayback", mapOf("actionEpoch" to latest?.get("actionEpoch")), result)
                ?: result.error("preview_hidden", "Preview is hidden", null)
        }
        fun hideRenderer() {
            latest?.let { onPlaying(mapOf("actionEpoch" to it["actionEpoch"], "video" to it["video"], "playing" to false)) }
            latest = null; rendered = null; playback = null
            waiters.forEach { it.result.error("preview_hidden", "Preview was hidden", null) }; waiters.clear()
            if (ready) channel?.invokeMethod("hide", null)
            engine?.lifecycleChannel?.appIsPaused()
        }
        fun release() {
            latest?.let { onPlaying(mapOf("actionEpoch" to it["actionEpoch"], "video" to it["video"], "playing" to false)) }
            waiters.forEach { it.result.error("preview_hidden", "Preview was hidden", null) }; waiters.clear()
            rendered = null; playback = null
            ready = false; prepared = false; latest = null
            channel?.setMethodCallHandler(null); channel = null
            engine?.lifecycleChannel?.appIsDetached()
            flutterView?.detachFromFlutterEngine(); flutterView = null
            engine?.destroy(); engine = null
        }
    }
}
