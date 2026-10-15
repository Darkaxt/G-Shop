package com.retro.rshop

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.emunix.unipatcher.helpers.ResourceProvider
import org.emunix.unipatcher.patcher.PatchBaseExtractor
import org.emunix.unipatcher.patcher.RShopPatchEngine
import java.io.File
import java.io.InterruptedIOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One foreground patch worker. Cancellation joins its real completion. */
class PatchWorkChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.retro.rshop/patches")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val workRoot = File(context.filesDir, "patch-work")
    private class Work(val id: String) {
        val cancelled = AtomicBoolean(false)
        @Volatile var thread: Thread? = null
        val cancellationReplies = mutableListOf<MethodChannel.Result>()
    }
    @Volatile private var active: Work? = null

    init { channel.setMethodCallHandler(::handle) }

    private fun job(call: MethodCall): File {
        val id = call.argument<String>("jobId") ?: throw IllegalArgumentException()
        require(id.matches(Regex("[a-zA-Z0-9_-]{1,96}")))
        return File(workRoot, id)
    }
    private fun privatePath(root: File, value: String): File {
        val file = File(value).canonicalFile
        require(file.path.startsWith(root.canonicalPath + File.separator))
        return file
    }
    private fun handle(call: MethodCall, reply: MethodChannel.Result) {
        try {
            if (call.method == "revision") {
                reply.success(RShopPatchEngine.REVISION)
                return
            }
            val root = job(call)
            if (call.method == "reopen") {
                require(root.isDirectory)
                reply.success(root.path)
                return
            }
            if (call.method == "prepare") {
                require(!root.exists() && root.mkdirs())
                reply.success(root.path)
                return
            }
            if (call.method == "cancel") {
                val work = active
                if (work == null || work.id != root.name) { reply.success(null); return }
                work.cancellationReplies.add(reply)
                work.cancelled.set(true)
                work.thread?.interrupt()
                return
            }
            if (call.method !in listOf("extract", "copy", "apply")) {
                reply.notImplemented()
                return
            }
            if (active != null) { reply.error("busy", "A patch is already running", null); return }
            require(root.isDirectory)
            val input = privatePath(root, call.argument<String>("input") ?: "")
            val output = privatePath(root, call.argument<String>("output") ?: "")
            require(input.isFile && !output.exists())
            val work = Work(root.name)
            active = work
            worker.execute {
                work.thread = Thread.currentThread()
                var code: String? = null
                try {
                    if (work.cancelled.get()) throw InterruptedIOException("cancelled")
                    if (call.method == "extract") {
                        PatchBaseExtractor.extract(input,
                            call.argument<String>("member") ?: "",
                            call.argument<Number>("size")?.toLong() ?: 0, output)
                    } else if (call.method == "copy") {
                        PatchBaseExtractor.copyRaw(input,
                            call.argument<Number>("size")?.toLong() ?: 0, output)
                    } else {
                        val patch = privatePath(root, call.argument<String>("patch") ?: "")
                        require(patch.isFile)
                        val resources = object : ResourceProvider {
                            override val tempDir = root
                            override fun getString(resId: Int) = context.getString(resId)
                            override fun getAsset(fileName: String) = context.assets.open(fileName)
                        }
                        RShopPatchEngine.apply(call.argument<String>("format") ?: "",
                            patch, input, output, resources,
                            call.argument<List<String>>("preprocessing") ?: emptyList())
                    }
                    if (work.cancelled.get()) throw InterruptedIOException("cancelled")
                } catch (_: InterruptedIOException) {
                    code = "cancelled"
                } catch (_: IllegalArgumentException) {
                    code = "invalid_patch_request"
                } catch (_: Exception) {
                    code = if (work.cancelled.get()) "cancelled" else "patch_failed"
                } finally {
                    Thread.interrupted() // Clear only this completed pool worker's flag.
                    main.post {
                        if (active === work) active = null
                        if (code == null) reply.success(mapOf("output" to output.path,
                            "engineRevision" to RShopPatchEngine.REVISION))
                        else reply.error(code, "Patch operation did not complete", null)
                        work.cancellationReplies.forEach { it.success(null) }
                        work.cancellationReplies.clear()
                    }
                }
            }
        } catch (_: Exception) {
            reply.error("invalid_patch_request", "Invalid patch operation", null)
        }
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        active?.let { it.cancelled.set(true); it.thread?.interrupt() }
        worker.shutdown()
    }
}
