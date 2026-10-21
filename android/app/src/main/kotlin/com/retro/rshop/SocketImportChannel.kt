package com.retro.rshop

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.github.luben.zstd.Zstd
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

internal object SocketImportNative {
    init { System.loadLibrary("rshop_media_import") }
    external fun decodeTexture(bytes: ByteArray, width: Int, height: Int, format: Int): ByteArray
    external fun noise(width: Int, height: Int, settings: FloatArray): FloatArray
}

/** Reads only the user's hash-bound APK snapshot; never loads its native engine. */
internal class SocketImportChannel(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    @Volatile private var session: String? = null
    private var archive: ZipFile? = null
    private var key: ByteArray? = null
    private val channel = MethodChannel(messenger, "com.darkaxt.gshop/socket_import")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "cancel") {
                if (call.argument<String>("session") == session) cancelled.set(true)
                result.success(null)
            } else worker.execute {
                try {
                    val value = handle(call)
                    main.post { result.success(value) }
                } catch (_: ImportCancelled) {
                    main.post { result.error("cancelled", "Import cancelled", null) }
                } catch (_: Exception) {
                    main.post { result.error("invalid_socket_apk", "Could not read the selected Socket 0.7 APK", null) }
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        cancelled.set(true)
        worker.execute { archive?.close(); archive = null; key?.fill(0); key = null; session = null }
        worker.shutdown()
    }

    private class ImportCancelled : Exception()
    private fun checkCancellation() { if (cancelled.get()) throw ImportCancelled() }
    private fun handle(call: MethodCall): Any? {
        if (call.method == "startupCleanup") return startupCleanup.compareAndSet(false, true)
        if (call.method == "open") {
            check(archive == null)
            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
            val root = File(app.filesDir, "socket-media").canonicalFile
            require(file.path.startsWith(root.path + File.separator) && file.name == "source.apk")
            require(file.length() == 153715341L)
            cancelled.set(false)
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    checkCancellation()
                    val n = input.read(buffer); if (n < 0) break
                    hash.update(buffer, 0, n)
                }
            }
            require(hash.digest().hex() == APK_HASH)
            val zip = ZipFile(file)
            try {
                val native = requireNotNull(zip.getEntry("lib/arm64-v8a/libgodot_android.so"))
                val secret = ByteArray(32)
                zip.getInputStream(native).use { input ->
                    var remaining = 0x43cb858L
                    val discard = ByteArray(65536)
                    while (remaining > 0) {
                        checkCancellation()
                        val n = input.read(discard, 0, minOf(discard.size.toLong(), remaining).toInt())
                        require(n > 0); remaining -= n
                    }
                    var read = 0
                    while (read < secret.size) {
                        val n = input.read(secret, read, secret.size - read)
                        require(n > 0); read += n
                    }
                }
                key = secret; archive = zip
                session = UUID.randomUUID().toString()
                return session
            } catch (error: Exception) { zip.close(); throw error }
        }
        require(call.argument<String>("session") == session && session != null)
        if (call.method == "close") {
            archive?.close(); archive = null
            key?.fill(0); key = null; session = null
            return null
        }
        checkCancellation()
        return when (call.method) {
            "resource" -> {
                val bytes = plain(requireNotNull(call.argument<String>("member")))
                if (call.argument<Boolean>("decompress") == true) decompress(bytes) else bytes
            }
            "texture" -> {
                val bytes = plain(requireNotNull(call.argument<String>("member")))
                require(MessageDigest.getInstance("SHA-256").digest(bytes).hex() == call.argument<String>("sha256"))
                val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                require(bytes.size >= 52 && String(bytes, 0, 4, Charsets.US_ASCII) == "GST2")
                val kind = buffer.getInt(36)
                val width = buffer.getShort(40).toInt() and 65535
                val height = buffer.getShort(42).toInt() and 65535
                val format = buffer.getInt(48)
                require(kind == 0 && width == call.argument<Int>("width") && height == call.argument<Int>("height"))
                require(format == call.argument<Int>("format") && format in setOf(28, 30, 31))
                val length = ((width + 3) / 4) * ((height + 3) / 4) * if (format == 30) 8 else 16
                require(width in 1..4096 && height in 1..4096 && length <= bytes.size - 52)
                SocketImportNative.decodeTexture(bytes.copyOfRange(52, 52 + length), width, height, format)
            }
            "noise" -> {
                val settings = requireNotNull(call.argument<List<Number>>("settings"))
                require(settings.size == 14 && settings.all { it.toDouble().isFinite() })
                SocketImportNative.noise(requireNotNull(call.argument<Int>("width")),
                    requireNotNull(call.argument<Int>("height")), settings.map { it.toFloat() }.toFloatArray())
            }
            else -> throw IllegalArgumentException("Unknown media import action")
        }
    }

    private fun plain(member: String): ByteArray {
        require(member.startsWith("assets/") && !member.contains("..") && !member.contains('\\'))
        val zip = requireNotNull(archive)
        val entry = requireNotNull(zip.getEntry(member))
        require(entry.size in 40..MAX_RESOURCE.toLong())
        val envelope = zip.getInputStream(entry).use { input ->
            val output = ByteArrayOutputStream(entry.size.toInt())
            val chunk = ByteArray(65536)
            while (true) {
                checkCancellation()
                val n = input.read(chunk); if (n < 0) break
                require(output.size() + n <= MAX_RESOURCE)
                output.write(chunk, 0, n)
            }
            output.toByteArray()
        }
        val size = ByteBuffer.wrap(envelope).order(ByteOrder.LITTLE_ENDIAN).getLong(16)
        require(size >= 0 && size <= envelope.size - 40 && (envelope.size - 40) % 16 == 0)
        val cipher = Cipher.getInstance("AES/CFB/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(requireNotNull(key), "AES"),
            IvParameterSpec(envelope.copyOfRange(24, 40)))
        val plain = cipher.doFinal(envelope, 40, envelope.size - 40).copyOf(size.toInt())
        require(MessageDigest.isEqual(MessageDigest.getInstance("MD5").digest(plain), envelope.copyOfRange(0, 16)))
        return plain
    }

    private fun decompress(bytes: ByteArray): ByteArray {
        val magic = String(bytes, 0, 4, Charsets.US_ASCII)
        if (magic == "RSRC") return bytes
        require(magic == "RSCC" && bytes.size >= 16)
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(input.getInt(4) == 2)
        val blockSize = input.getInt(8); val total = input.getInt(12)
        require(blockSize > 0 && total in 1..MAX_RESOURCE)
        val count = total / blockSize + 1
        require(count <= (bytes.size - 16) / 4)
        var offset = 16 + count * 4
        val output = ByteArrayOutputStream(total)
        repeat(count) { i ->
            checkCancellation()
            val size = input.getInt(16 + i * 4)
            require(size >= 0 && size <= bytes.size - offset)
            val expected = minOf(blockSize, total - output.size())
            output.write(Zstd.decompress(bytes.copyOfRange(offset, offset + size), expected))
            offset += size
        }
        // Godot ends compressed resources with a second RSCC marker after the
        // block table payload. It is part of the envelope, not another block.
        require(output.size() == total && offset == bytes.size - 4 &&
            input.getInt(offset) == 0x43435352)
        return output.toByteArray()
    }

    private fun ByteArray.hex() = joinToString("") { "%02x".format(it.toInt() and 255) }
    companion object {
        private val startupCleanup = AtomicBoolean(false)
        private const val MAX_RESOURCE = 32 * 1024 * 1024
        private const val APK_HASH = "bccf6bf5beccf5155645638e52a20f6e6e6deed902bd23b6b69ae7060c04bd70"
    }
}
