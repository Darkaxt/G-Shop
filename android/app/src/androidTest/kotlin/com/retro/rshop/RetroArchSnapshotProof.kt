package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Exclusive saves only. No emulator launch, UDP endpoint, Drive or settings. */
internal object RetroArchSnapshotProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val service = SaveCaptureService(context)
        val captures = mutableListOf<String>()
        fun id() = UUID.randomUUID().toString().replace("-", "")
        fun capture(route: String, name: String, expected: String? = null): Map<*, *>? {
            val captureId = id().also(captures::add)
            val done = CountDownLatch(1)
            var receipt: Map<*, *>? = null
            var error: String? = null
            service.handle(MethodCall("captureRetroArch", mapOf("captureId" to captureId,
                "retroArchRoute" to route, "name" to name)), object : MethodChannel.Result {
                override fun success(result: Any?) { receipt = result as Map<*, *>; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                override fun notImplemented() { error = "not_implemented"; done.countDown() }
            })
            done.await()
            check(error == expected) { "capture: $error (expected $expected)" }
            if (expected != null) check(!File(context.filesDir, "save-captures/$captureId/capture.json").exists())
            return receipt
        }
        fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        try {
            for (route in listOf("n64", "gba", "nes", "snes")) {
                val directory = File(requireNotNull(RetroArchSaveBoundary.saveDirectory(route)))
                check(directory.isDirectory && directory.canonicalFile == directory.absoluteFile)
                val initialNames = directory.list()!!.toSet()
                val file = File(directory, "RShopSnapshot-${id()}.srm")
                val clock = File(directory, file.name.dropLast(4) + ".rtc")
                val clockBytes = if (route == "snes") ByteArray(20) { (it + 1).toByte() } else byteArrayOf(1, 2, 3, 4)
                check(file.createNewFile())
                val bytes = ByteArray(if (route == "n64") 296960 else 32768) { (it + 17).toByte() }
                fun write(target: File, value: ByteArray) {
                    FileOutputStream(target).use { it.write(value); it.fd.sync() }
                }
                try {
                    write(file, bytes)
                    // An idle writable descriptor still blocks; read handles do not.
                    FileOutputStream(file, true).use { capture(route, file.name, "source_changed") }
                    FileInputStream(file).use {
                        val receipt = requireNotNull(capture(route, file.name))
                        val member = (receipt["files"] as List<*>).single() as Map<*, *>
                        check(member["sha256"] == digest(bytes))
                        check(File(member["path"] as String).readBytes().contentEquals(bytes))
                    }
                    SaveSourceStorage.open(context, directory.path).use { storage ->
                        storage.beginRetroArchSnapshot(context, file.name)
                        write(file, bytes) // Same content and size still invalidate capture.
                        repeat(2) {
                            try { storage.verifySnapshot(); error("Accepted overlapping writer") }
                            catch (error: IOException) { check(error.message == "source_changed") }
                        }
                    }
                    if (RetroArchSaveBoundary.includesRtc(route)) {
                        SaveSourceStorage.open(context, directory.path).use { storage ->
                            storage.beginRetroArchSnapshot(context, file.name)
                            check(clock.createNewFile())
                            write(clock, clockBytes)
                            try { storage.verifySnapshot(); error("Missed newly created clock") }
                            catch (error: IOException) { check(error.message == "source_changed") }
                        }
                        FileOutputStream(clock, true).use { capture(route, file.name, "source_changed") }
                        val members = requireNotNull(capture(route, file.name))["files"] as List<*>
                        check(members.map { (it as Map<*, *>)["name"] }.toSet() == setOf(file.name, clock.name))
                        members.forEach {
                            val member = it as Map<*, *>
                            check(member["sha256"] == digest(File(directory, member["name"] as String).readBytes()))
                        }
                    }
                    check(directory.list()!!.toSet() == initialNames + file.name + if (RetroArchSaveBoundary.includesRtc(route)) setOf(clock.name) else emptySet())
                } finally {
                    check(file.readBytes().contentEquals(bytes)); check(file.delete())
                    if (clock.exists()) { check(clock.readBytes().contentEquals(clockBytes)); check(clock.delete()) }
                    check(directory.list()!!.toSet() == initialNames)
                }
            }
        } finally {
            val closed = CountDownLatch(1)
            service.shutdown { closed.countDown() }; closed.await()
            for (captureId in captures) {
                val directory = File(context.filesDir.canonicalFile, "save-captures/$captureId")
                if (!directory.exists()) continue
                check(directory.canonicalFile == directory.absoluteFile)
                val members = directory.listFiles()!!
                check(members.all { it.isFile && it.canonicalFile == it.absoluteFile &&
                    it.name in setOf("capture.json", "capture.json.part", "member-0", "member-1") })
                members.forEach { check(it.delete()) }; check(directory.delete())
            }
        }
        return "PASS root filesystem RetroArch N64/GBA/NES/SNES capture without frontend replies; writable handles rejected, read-only handles admitted, overlapping writes and newly created RTC rejected, paired digests verified; exclusive fixtures removed"
    }
}
