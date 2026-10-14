package com.retro.rshop

import android.content.Context
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException

/** Exact manifest-derived ROM paths; root reads kernel metadata only. No app
 * command/status protocol, signals, file writes or arbitrary scan roots. */
internal object RootRomCacheScan {
    fun inUse(context: Context, members: List<JSONObject>, emulator: String): Boolean {
        require(members.size in 1..514)
        val paths = members.map { member ->
            File(member.getString("destinationRoot"), member.getString("relativePath")).absolutePath
        }
        val input = JSONObject().put("paths", JSONArray(paths)).put("emulator", emulator)
            .toString().toByteArray(Charsets.UTF_8)
        require(input.size <= 1024 * 1024)
        val apk = context.applicationInfo.sourceDir
        fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
        val command = "CLASSPATH=${quote(apk)} /system/bin/app_process -Xmx64m /system/bin " +
            "com.retro.rshop.RootSaveProcess ${quote(apk)} rom-cache"
        val process = try { ProcessBuilder("su", "--mount-master", "-c", command)
            .redirectErrorStream(true).start() } catch (_: IOException) { throw IOException("root_unavailable") }
        try {
            process.outputStream.use { it.write(input) }
            val tail = StringBuilder()
            process.inputStream.bufferedReader().use { reader ->
                val buffer = CharArray(1024)
                while (true) {
                    val count = reader.read(buffer); if (count < 0) break
                    tail.append(buffer, 0, count)
                    if (tail.length > 16384) tail.delete(0, tail.length-16384)
                }
            }
            val exit = process.waitFor()
            val reply = tail.lines().lastOrNull { it.startsWith("{") }
                ?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (exit != 0 || reply?.optInt("rshopRomCache") != 1 || reply.optBoolean("failed", true))
                throw IOException("root_unavailable")
            return reply.getBoolean("inUse")
        } finally {
            process.outputStream.close(); process.inputStream.close(); process.errorStream.close()
            process.waitFor()
        }
    }
}

object RootRomCacheWorker {
    @JvmStatic fun serve() {
        val reply = JSONObject().put("rshopRomCache", 1)
        try {
            require(Process.myUid() == 0)
            val bytes = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            while (true) {
                val count = System.`in`.read(buffer); if (count < 0) break
                require(bytes.size()+count <= 1024*1024)
                bytes.write(buffer,0,count)
            }
            val request = JSONObject(bytes.toString("UTF-8"))
            require(request.length() == 2)
            val paths = request.getJSONArray("paths")
            require(paths.length() in 1..514)
            val emulator = request.getString("emulator")
            require(emulator.isEmpty() || emulator.matches(Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+")))
            var inUse = false
            for (index in 0 until paths.length()) {
                val path = paths.getString(index)
                require(path.length <= 4096 && path.startsWith("/storage/") &&
                    path.split('/').drop(1).all { it.isNotEmpty() && it != "." && it != ".." })
                val file = File(path)
                val public = file.parentFile!!.path
                val backing = if (public == "/storage/emulated/0" || public.startsWith("/storage/emulated/0/"))
                    "/data/media/0" + public.removePrefix("/storage/emulated/0")
                    else "/mnt/media_rw/" + public.removePrefix("/storage/")
                val directory = OwnedStorageNative.openRoot(backing)
                try {
                    if (OwnedStorageNative.romCacheHasReaders(directory,file.name,public,backing,emulator)) {
                        inUse = true; break
                    }
                } finally { OwnedStorageNative.close(directory) }
            }
            reply.put("inUse",inUse).put("failed",false)
        } catch (_: Exception) { reply.put("failed",true) }
        println(reply.toString())
    }
}
