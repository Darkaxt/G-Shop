package com.retro.rshop

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** ZArchive v1's uncompressed root index, not decompression or a title cache.
 * Format reference: Exzap/ZArchive, zarchivecommon.h and zarchivereader.cpp.
 * Reads only a bounded root directory; payload identity belongs to the ROM grant.
 */
internal object WuaSaveIdentity {
    fun titleId(size: Long, read: (Long, Int) -> ByteArray): String {
        require(size > 144)
        fun bytes(offset: Long, count: Int): ByteArray {
            require(offset >= 0 && count >= 0 && offset <= size - count)
            return read(offset, count).also { require(it.size == count) }
        }
        fun buffer(offset: Long, count: Int) = ByteBuffer.wrap(bytes(offset, count)).order(ByteOrder.BIG_ENDIAN)
        val footer = buffer(size - 144, 144)
        require(footer.getLong(128) == size && footer.getInt(136) == 0x61bf3a01 && footer.getInt(140) == 0x169f52d6)
        val sections = (0 until 6).map { index ->
            val offset = footer.getLong(index * 16); val length = footer.getLong(index * 16 + 8)
            require(offset >= 0 && length >= 0 && offset <= size - 144 && length <= size - 144 - offset)
            offset to length
        }
        val present = sections.filter { it.second > 0 }.sortedBy { it.first }
        require(present.zipWithNext().all { (a, b) -> a.first + a.second <= b.first })
        val names = sections[2]; val tree = sections[3]
        require(tree.second >= 32 && tree.second % 16 == 0L && names.second > 0)
        fun name(offset: Long): String {
            if (offset == 0x7fffffffL) return ""
            require(offset >= 0 && offset < names.second)
            val length = bytes(names.first + offset, 1)[0].toInt() and 0xff
            // Wii U title directory names are short ASCII, not arbitrary paths.
            require(length <= 64 && offset + 1 + length <= names.second)
            val raw = bytes(names.first + offset + 1, length)
            require(raw.all { (it.toInt() and 0xff) in 0x20..0x7e })
            return raw.toString(Charsets.US_ASCII)
        }
        val root = buffer(tree.first, 16)
        require(root.getInt(0) >= 0 && name(root.getInt(0).toLong()).isEmpty())
        val start = root.getInt(4).toLong() and 0xffffffffL
        val count = root.getInt(8).toLong() and 0xffffffffL
        require(start >= 1 && count in 1..256 && start <= tree.second / 16 - count)
        val titles = mutableSetOf<String>()
        for (index in start until start + count) {
            val row = buffer(tree.first + index * 16, 16)
            if (row.getInt(0) < 0) continue // root-level files are not titles
            val childStart = row.getInt(4).toLong() and 0xffffffffL
            val childCount = row.getInt(8).toLong() and 0xffffffffL
            require(childStart >= start + count && childCount > 0 && childStart <= tree.second / 16 - childCount)
            val title = Regex("(00050000[0-9a-fA-F]{8})_v([0-9]{1,5})").matchEntire(name(row.getInt(0).toLong()))
                ?: continue // updates, DLC and system titles do not select a save
            require(title.groupValues[2].toInt() <= 65535)
            titles.add(title.groupValues[1].lowercase())
        }
        require(titles.size == 1) { "save_settings_unresolved" }
        return titles.single()
    }
}
