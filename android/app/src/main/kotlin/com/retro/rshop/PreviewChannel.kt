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
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Owns only the R-Shop non-focusable window. Never manipulates another task. */
class PreviewChannel(private val activity: Activity, messenger: BinaryMessenger) :
    DisplayManager.DisplayListener {
    private val displays = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val channel = MethodChannel(messenger, "com.retro.rshop/preview")
    private var presentation: PreviewPresentation? = null
    private var payload: Map<String, Any?>? = null
    private var resumed = true
    private var disposed = false
    private val debug = activity.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0

    init {
        displays.registerDisplayListener(this, Handler(Looper.getMainLooper()))
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(display() != null)
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
                    "displayId" to presentation?.display?.displayId, "rendered" to presentation?.rendered,
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

    private fun show() {
        if (!resumed || disposed || payload == null) return
        val display = display() ?: run { dismiss(); return }
        if (presentation?.display?.displayId != display.displayId) dismiss()
        if (presentation == null) {
            val view = PreviewPresentation(activity, display,
                onAction = { action -> channel.invokeMethod("action", action) },
                onPlaying = { state ->
                    if (state["actionEpoch"] == payload?.get("actionEpoch") && state["video"] == payload?.get("video"))
                        channel.invokeMethod("playing", state)
                })
            try {
                view.show()
                view.window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
                presentation = view
            }
            catch (_: WindowManager.InvalidDisplayException) { view.release() }
        }
        presentation?.update(payload!!)
    }
    private fun dismiss() { presentation?.let { it.dismiss(); it.release() }; presentation = null }
    fun resume() { resumed = true; show() }
    fun pause() { resumed = false; dismiss() }
    private fun changed() {
        channel.invokeMethod("availability", display() != null)
        if (display() == null) dismiss() else show()
    }
    override fun onDisplayAdded(displayId: Int) = changed()
    override fun onDisplayRemoved(displayId: Int) = changed()
    override fun onDisplayChanged(displayId: Int) = changed()
    fun dispose() {
        disposed = true; payload = null; dismiss()
        displays.unregisterDisplayListener(this)
        channel.setMethodCallHandler(null)
    }

    private class PreviewPresentation(activity: Activity, display: Display,
        private val onAction: (Any?) -> Unit,
        private val onPlaying: (Map<String, Any?>) -> Unit) : Presentation(activity, display) {
        private var engine: FlutterEngine? = null
        private var flutterView: FlutterView? = null
        private var channel: MethodChannel? = null
        private var ready = false
        private var latest: Map<String, Any?>? = null
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
            // Rendering needs only a file-backed player. Do not attach account,
            // database, foreground-download or save plugins to this engine.
            val renderer = FlutterEngine(context, null, false)
            renderer.plugins.add(io.flutter.plugins.videoplayer.VideoPlayerPlugin())
            engine = renderer
            channel = MethodChannel(renderer.dartExecutor.binaryMessenger, "com.retro.rshop/preview_view").also { bridge ->
                bridge.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "ready" -> { ready = true; latest?.let { bridge.invokeMethod("snapshot", it) }; result.success(null) }
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
                            val completed = waiters.filter { matches(it) }
                            waiters.removeAll(completed.toSet())
                            completed.forEach { it.result.success(rendered) }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
            flutterView = FlutterView(context).also { view ->
                view.attachToFlutterEngine(renderer)
                setContentView(view)
            }
            renderer.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(), "previewMain"))
            renderer.lifecycleChannel.appIsResumed()
        }
        fun update(value: Map<String, Any?>) {
            latest = value
            if (ready) channel?.invokeMethod("snapshot", value)
        }
        fun togglePlayback(result: MethodChannel.Result) {
            channel?.invokeMethod("togglePlayback", mapOf("actionEpoch" to latest?.get("actionEpoch")), result)
                ?: result.error("preview_hidden", "Preview is hidden", null)
        }
        fun release() {
            latest?.let { onPlaying(mapOf("actionEpoch" to it["actionEpoch"], "video" to it["video"], "playing" to false)) }
            waiters.forEach { it.result.error("preview_hidden", "Preview was hidden", null) }; waiters.clear()
            rendered = null; playback = null
            ready = false; latest = null
            channel?.setMethodCallHandler(null); channel = null
            engine?.lifecycleChannel?.appIsDetached()
            flutterView?.detachFromFlutterEngine(); flutterView = null
            engine?.destroy(); engine = null
        }
    }
}
