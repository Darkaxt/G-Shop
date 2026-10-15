package org.emunix.unipatcher.utils

import java.io.InterruptedIOException

object PatchCancellation {
    @JvmStatic fun check() {
        if (Thread.currentThread().isInterrupted) throw InterruptedIOException("cancelled")
    }
}

fun ByteArray.bytesToHexString(): String = joinToString("") {
    (it.toInt() and 255).toString(16).padStart(2, '0')
}
