package org.emunix.unipatcher.utils

import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.InterruptedIOException
import java.io.RandomAccessFile
import java.util.zip.CRC32

/** Only IO used by the vendored kernels; no device discovery or recursive sync. */
class FileUtils {
    private var closeFailure: java.io.IOException? = null
    fun checkCancelled() {
        if (Thread.currentThread().isInterrupted) throw InterruptedIOException("cancelled")
    }
    // Drain every kernel finally-close, then fail the operation if any failed.
    fun closeQuietly(value: Closeable?) {
        try { value?.close() } catch (error: java.io.IOException) {
            if (closeFailure == null) closeFailure = error
            else closeFailure!!.addSuppressed(error)
        }
    }
    fun requireClosed() { closeFailure?.let { throw it } }
    fun checksumCRC32(file: File): Long {
        val crc = CRC32()
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                checkCancelled()
                val count = input.read(buffer)
                if (count < 0) break
                crc.update(buffer, 0, count)
            }
        }
        return crc.value
    }
    fun copyFile(input: File, output: File) {
        input.inputStream().use { from -> output.outputStream().use { to -> copy(from, to) } }
    }
    fun copy(from: InputStream, to: OutputStream): Int {
        val buffer = ByteArray(65536)
        var total = 0L
        while (true) {
            checkCancelled()
            val count = from.read(buffer)
            if (count < 0) break
            to.write(buffer, 0, count)
            total += count
        }
        return if (total > Int.MAX_VALUE) -1 else total.toInt()
    }
    fun copy(from: InputStream, to: OutputStream, size: Long) {
        require(size >= 0)
        val buffer = ByteArray(65536)
        var remaining = size
        while (remaining > 0) {
            checkCancelled()
            val count = from.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (count < 0) {
                // IPS/N64 APS explicitly use zero padding when extending a ROM.
                copy(remaining, 0.toByte(), to)
                return
            }
            to.write(buffer, 0, count)
            remaining -= count
        }
    }
    fun copy(number: Long, b: Byte, to: OutputStream) {
        require(number >= 0)
        val buffer = ByteArray(65536) { b }
        var remaining = number
        while (remaining > 0) {
            checkCancelled()
            val count = minOf(buffer.size.toLong(), remaining).toInt()
            to.write(buffer, 0, count)
            remaining -= count
        }
    }
    fun copyToFile(input: InputStream, output: File) = output.outputStream().use { copy(input, it) }
    fun skipFully(input: InputStream, count: Long) {
        require(count >= 0)
        var remaining = count
        while (remaining > 0) {
            checkCancelled()
            val skipped = input.skip(remaining)
            if (skipped > 0) remaining -= skipped
            else if (input.read() < 0) throw java.io.EOFException()
            else remaining--
        }
    }
    fun truncateFile(file: File, size: Long) {
        require(size >= 0)
        RandomAccessFile(file, "rw").use { it.setLength(size) }
    }
    fun delete(file: File?) {
        // Kernel scratch is exclusively created inside the current operation.
        if (file != null && file.exists() && !file.delete()) {
            throw java.io.IOException("patch_scratch_cleanup_failed")
        }
    }
}
