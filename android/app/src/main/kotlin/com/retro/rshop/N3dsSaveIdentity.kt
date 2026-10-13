package com.retro.rshop

/** Bounded NCCH/NCSD header reads, never filename/title guesses or decryption. */
internal object N3dsSaveIdentity {
    fun programId(size: Long, read: (Long, Int) -> ByteArray): String {
        fun header(offset: Long): ByteArray {
            require(offset >= 0 && offset <= size - 512) { "save_settings_unresolved" }
            return read(offset, 512).also { require(it.size == 512) }
        }
        fun magic(bytes: ByteArray) = bytes.copyOfRange(0x100, 0x104).toString(Charsets.US_ASCII)
        fun uint(bytes: ByteArray, offset: Int): Long = (0..3).fold(0L) { value, n ->
            value or ((bytes[offset + n].toLong() and 255) shl (8 * n))
        }
        val first = header(0)
        val ncch = when (magic(first)) {
            "NCCH" -> first
            "NCSD" -> {
                val offset = uint(first, 0x120) * 512
                val length = uint(first, 0x124) * 512
                require(offset >= 512 && length >= 512 && offset <= size - length)
                header(offset)
            }
            else -> throw IllegalArgumentException("save_settings_unresolved")
        }
        require(magic(ncch) == "NCCH" && (ncch[0x18f].toInt() and 4) != 0) { "save_settings_unresolved" }
        val id = ncch.copyOfRange(0x118, 0x120).reversed().joinToString("") { "%02x".format(it.toInt() and 255) }
        require(id.matches(Regex("00040000[0-9a-f]{8}")) && id.takeLast(8) != "00000000") { "save_settings_unresolved" }
        return id
    }
}
