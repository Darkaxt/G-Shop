package org.emunix.unipatcher.patcher

import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.emunix.unipatcher.utils.PatchCancellation
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.zip.ZipFile

/** Extract one declared member to private scratch, never an archive directory. */
object PatchBaseExtractor {
    @JvmStatic fun copyRaw(input: File, size: Long, output: File) {
        require(size > 0 && input.length() == size && !output.exists())
        input.inputStream().use { copy(it, size, output) }
    }
    @JvmStatic fun extract(archive: File, member: String, size: Long, output: File) {
        require(size > 0 && !output.exists() && member.isNotEmpty())
        PatchCancellation.check()
        when (archive.extension.lowercase(java.util.Locale.ROOT)) {
            "zip" -> ZipFile(archive).use { zip ->
                val matches = zip.entries().asSequence().filter { it.name == member }.toList()
                if (matches.size != 1 || matches.single().isDirectory ||
                    matches.single().size != size) throw IOException("base_member_mismatch")
                zip.getInputStream(matches.single()).use { copy(it, size, output) }
            }
            "7z" -> SevenZFile.builder().setFile(archive)
                .setMaxMemoryLimitKiB(64 * 1024).get().use { seven ->
                    // Enumerating metadata establishes uniqueness without
                    // extracting neighboring members or materializing ROM bytes.
                    val matches = seven.entries.filter { it.name == member }
                    if (matches.size != 1 || matches.single().isDirectory ||
                        matches.single().size != size) throw IOException("base_member_mismatch")
                    seven.getInputStream(matches.single()).use { copy(it, size, output) }
                }
            else -> throw IOException("unsupported_base_container")
        }
        PatchCancellation.check()
    }
    private fun copy(input: InputStream, size: Long, output: File) {
        if (!output.createNewFile()) throw IOException("output_collision")
        FileOutputStream(output).use { out ->
            val buffer = ByteArray(65536)
            var remaining = size
            while (remaining > 0) {
                PatchCancellation.check()
                val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                if (count < 0) throw IOException("base_member_truncated")
                out.write(buffer, 0, count)
                remaining -= count
            }
            if (input.read() != -1) throw IOException("base_member_size_mismatch")
            out.fd.sync()
        }
    }
}
