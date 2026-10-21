package org.emunix.unipatcher.helpers

import java.io.File
import java.io.InputStream

/** Headless kernel boundary; G-Shop supplies its operation-private scratch. */
interface ResourceProvider {
    val tempDir: File
    fun getString(resId: Int): String
    fun getAsset(fileName: String): InputStream
}
