package com.retro.rshop

import android.content.Context
import android.os.Process
import dalvik.system.PathClassLoader
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest

/** Root is needed only for this namespace commit on devices whose public FUSE
 * rejects RENAME_NOREPLACE. Payloads and paths travel as data, never shell code.
 * The existing capture worker owns admission, staging, cancellation and receipts. */
internal object RootSavePublication {
    fun request(context: Context, operation: String, record: JSONObject,
                stage: String, review: JSONObject? = null): JSONObject {
        val apk = context.applicationInfo.sourceDir
        fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
        val command = "CLASSPATH=${quote(apk)} /system/bin/app_process -Xmx64m /system/bin " +
            "com.retro.rshop.RootSaveProcess ${quote(apk)}"
        val input = JSONObject().put("operation", operation).put("source", record.getString("source"))
            .put("name", record.getString("name")).put("stage", stage)
            .put("format", record.getString("format")).put("size", record.getLong("size"))
            .put("sha256", record.getString("sha256"))
        if (review != null) input.put("review", review)
        val process = try { ProcessBuilder("su", "-c", command).redirectErrorStream(true).start() }
            catch (_: IOException) { throw IOException("root_unavailable") }
        try {
            process.outputStream.use { it.write(input.toString().toByteArray(Charsets.UTF_8)) }
            // Drain even unexpected diagnostics so a child cannot block on a full
            // pipe. Retain only a bounded tail; never log paths or save payloads.
            val tail = StringBuilder()
            process.inputStream.bufferedReader().use { reader ->
                val buffer = CharArray(1024)
                while (true) {
                    val n = reader.read(buffer)
                    if (n < 0) break
                    tail.append(buffer, 0, n)
                    if (tail.length > 16384) tail.delete(0, tail.length - 16384)
                }
            }
            val exit = process.waitFor()
            val reply = tail.lines().lastOrNull { it.startsWith("{") }
                ?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (exit != 0 || reply == null || reply.optInt("rshopRootSave") != 1) throw IOException("root_unavailable")
            reply.optString("error").takeIf(String::isNotEmpty)?.let { throw IOException(it) }
            return reply.getJSONObject("result")
        } catch (error: IOException) {
            if (error.message in setOf("source_changed", "root_unavailable") ||
                error.message?.matches(Regex("owned_storage:[0-9]+")) == true) throw error
            throw IOException("root_unavailable")
        } finally {
            process.outputStream.close(); process.inputStream.close(); process.errorStream.close()
            // No detached commit or timeout-based success. Join the exact child,
            // including a lost pipe response; its durable intent allows recovery.
            process.waitFor()
        }
    }
}

/** Fixed app-owned entrypoint, with an APK-native-library aware class loader. */
object RootSaveProcess {
    @JvmStatic fun main(args: Array<String>) {
        val reply = JSONObject().put("rshopRootSave", 1)
        try {
            require(Process.myUid() == 0 && (args.size == 1 ||
                args.size == 2 && args[1] in setOf("source", "watch")))
            val apk = File(args[0])
            require(apk.isFile && apk.isAbsolute && apk.canonicalFile == apk.absoluteFile)
            val loader = PathClassLoader(apk.path, apk.path + "!/lib/arm64-v8a",
                ClassLoader.getSystemClassLoader().parent)
            if (args.size == 2) {
                val worker = if (args[1] == "watch") "RootSaveWatchWorker" else "RootSaveSourceWorker"
                Class.forName("com.retro.rshop.$worker", true, loader)
                    .getMethod("serve").invoke(null)
                return
            }
            val bytes = System.`in`.readBytesBounded(16384)
            val worker = Class.forName("com.retro.rshop.RootSavePublicationWorker", true, loader)
            val result = worker.getMethod("execute", String::class.java)
                .invoke(null, bytes.toString(Charsets.UTF_8)) as String
            reply.put("result", JSONObject(result))
        } catch (error: Throwable) {
            val cause = (error as? java.lang.reflect.InvocationTargetException)?.cause ?: error
            val code = (cause as? IOException)?.message
            reply.put("error", if (code in setOf("source_changed", "root_unavailable") ||
                    code?.matches(Regex("owned_storage:[0-9]+")) == true) code else "root_unavailable")
        }
        println(reply.toString())
    }

    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(1024)
        while (true) {
            val size = read(buffer)
            if (size < 0) break
            require(output.size() + size <= limit)
            output.write(buffer, 0, size)
        }
        return output.toByteArray()
    }
}

object RootSavePublicationWorker {
    @JvmStatic fun execute(input: String): String {
        require(Process.myUid() == 0)
        val request = JSONObject(input)
        val source = request.getString("source")
        val name = request.getString("name")
        val format = request.getString("format")
        val size = request.getLong("size")
        val digest = request.getString("sha256")
        val baseName = if (format == "mgba-battery" && name.endsWith(".rtc")) name.dropLast(4) + ".srm" else name
        require(SaveCaptureService.validRestoreBinding(baseName, size, format, source))
        require(digest.matches(Regex("[a-f0-9]{64}")))
        val stage = request.getString("stage")
        require(stage.matches(Regex("\\.rshop-save-restore-[a-f0-9]{32}")))
        val backing = if (source.startsWith("/storage/emulated/0/"))
            "/data/media/0/" + source.removePrefix("/storage/emulated/0/") else {
            val match = Regex("^/storage/([A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/(.+)$").matchEntire(source)
                ?: throw IOException("root_unavailable")
            "/mnt/media_rw/${match.groupValues[1]}/${match.groupValues[2]}"
        }
        val parent = OwnedStorageNative.openRoot(backing)
        try {
            val parentIdentity = OwnedStorageNative.identity(parent)
            val operation = request.getString("operation")
            require(operation in setOf("review", "publish", "verify"))
            val review = request.optJSONObject("review")
            if (operation != "review") {
                require(review != null)
                if ((0..1).any { parentIdentity[it] != review.getJSONArray("parent").getLong(it) })
                    throw IOException("source_changed")
            }
            val leaf = if (operation == "verify") name else stage
            val file = OwnedStorageNative.openFile(parent, leaf, false, false)
            try {
                val identity = OwnedStorageNative.identity(file)
                if (identity[2] != size) throw IOException("source_changed")
                if (review != null && (0..2).any { identity[it] != review.getJSONArray("stage").getLong(it) })
                    throw IOException("source_changed")
                val sum = MessageDigest.getInstance("SHA-256")
                var offset = 0L
                while (offset < size) {
                    val bytes = OwnedStorageNative.read(file, offset, minOf(65536L, size - offset).toInt())
                    if (bytes.isEmpty()) throw IOException("source_changed")
                    sum.update(bytes); offset += bytes.size
                }
                if (sum.digest().joinToString("") { "%02x".format(it) } != digest ||
                    !identity.contentEquals(OwnedStorageNative.identity(file)) ||
                    !identity.contentEquals(OwnedStorageNative.entryIdentity(parent, leaf))) throw IOException("source_changed")
                val currentParent = OwnedStorageNative.openRoot(backing)
                try {
                    if (OwnedStorageNative.identity(currentParent).take(2) != parentIdentity.take(2))
                        throw IOException("source_changed")
                } finally { OwnedStorageNative.close(currentParent) }
                if (operation == "publish") {
                    // Kernel no-replace is the arbiter if a new local save appears.
                    // Never unlink the destination or substitute ordinary rename.
                    OwnedStorageNative.renameNoReplace(parent, stage, parent, name)
                }
                if (operation != "review") OwnedStorageNative.sync(parent)
                return JSONObject().put("parent", JSONArray(parentIdentity.take(2)))
                    .put("stage", JSONArray(identity.toList())).toString()
            } finally { OwnedStorageNative.close(file) }
        } finally { OwnedStorageNative.close(parent) }
    }
}
