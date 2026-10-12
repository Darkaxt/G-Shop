package com.retro.rshop

import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS

/** Exact app-private capture review, not a collector or arbitrary-path delete. */
internal object SaveCaptureRetirement {
    fun review(root: File, id: String): List<File> {
        require(id.matches(Regex("[a-f0-9]{32}")))
        require(root.canonicalFile == root.absoluteFile)
        if (!Files.exists(root.toPath(), NOFOLLOW_LINKS)) return emptyList()
        require(Files.isDirectory(root.toPath(), NOFOLLOW_LINKS))
        val directory = File(root, id)
        require(directory.canonicalFile == directory.absoluteFile)
        if (!Files.exists(directory.toPath(), NOFOLLOW_LINKS)) return emptyList()
        require(Files.isDirectory(directory.toPath(), NOFOLLOW_LINKS))
        val allowed = (0 until PpssppSavedataBoundary.MAX_MEMBERS).map { "member-$it" } +
            listOf("capture.json.part", "capture.json")
        val entries = requireNotNull(directory.listFiles())
        require(entries.all { it.name in allowed &&
            it.canonicalFile == it.absoluteFile && Files.isRegularFile(it.toPath(), NOFOLLOW_LINKS) })
        return entries.sortedBy { allowed.indexOf(it.name) }
    }
}
