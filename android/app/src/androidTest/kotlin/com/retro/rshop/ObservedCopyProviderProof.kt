package com.retro.rshop

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Exclusive synthetic bytes/rows only. Tests real SQLite, provider and pinned
 * native reads, never an emulator boot or ownership of an existing ROM. */
internal object ObservedCopyProviderProof {
    fun exercise(context: Context) {
        exercise(context, "gc", "rvz", byteArrayOf(4, 8, 15, 16, 23, 42))
        for ((platform, member) in listOf("megadrive" to "md", "mastersystem" to "sms", "sg1000" to "sg")) {
            val out = java.io.ByteArrayOutputStream()
            java.util.zip.ZipOutputStream(out).use { zip ->
                zip.putNextEntry(java.util.zip.ZipEntry("synthetic.$member"))
                zip.write(ByteArray(8192) { (it % 251).toByte() })
                zip.closeEntry()
            }
            exercise(context, platform, "zip", out.toByteArray())
        }
    }

    private fun exercise(context: Context, platform: String, extension: String, bytes: ByteArray) {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val token = "copy-proof-${UUID.randomUUID()}"
        val root = File(context.getExternalFilesDir(null), token)
        check(root.mkdir())
        val file = File(root, "synthetic.$extension")
        val db = SQLiteDatabase.openDatabase(context.getDatabasePath("rshop.db").path, null, SQLiteDatabase.OPEN_READWRITE)
        val ids = mutableListOf<Long>()
        var gameRow: Long? = null
        try {
            check(file.createNewFile()); file.writeBytes(bytes)
            val dir = OwnedStorageNative.openRoot(root.path)
            val native: LongArray
            try { native = OwnedStorageNative.entryIdentity(dir, file.name) }
            finally { OwnedStorageNative.close(dir) }
            val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date(native[3] * 1000)) + "." + (native[4] / 1000).toString().padStart(6, '0') + "Z"
            val identity = JSONObject().put("volumeId", native[0].toString()).put("fileId", native[1].toString())
                .put("sizeBytes", native[2]).put("modifiedAt", stamp).put("modifiedNanoseconds", native[4])
            fun digest(algorithm: String) = MessageDigest.getInstance(algorithm).digest(bytes)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
            val remoteId = JSONObject().put("providerId", "drive").put("sourceId", token)
                .put("accountId", token).put("providerFileId", token)
            val key = JSONArray().put("drive").put(token).put(token).put(token).toString()
            val checksums = JSONObject().put("md5", digest("MD5")).put("sha256", digest("SHA-256"))
            val artifact = JSONObject().put("id", remoteId).put("displayName", file.name)
                .put("displayPath", file.name).put("version", "1").put("sizeBytes", bytes.size)
                .put("canDownload", true).put("providerChecksums", JSONObject().put("md5", digest("MD5")))
            val saved = JSONObject().put("schema", 1).put("artifact", artifact).put("destinationRoot", root.path)
                .put("relativePath", file.name).put("localIdentity", identity).put("sizeBytes", bytes.size)
                .put("checksums", checksums).put("observedAt", stamp)
            fun observe(record: JSONObject = saved): Long = db.insertOrThrow("migration_byte_observations", null,
                ContentValues().apply { put("artifact_key", key); put("destination_root", root.path)
                    put("relative_path", file.name); put("record_json", record.toString()) }).also { ids.add(it) }
            val first = observe()
            gameRow = db.insertOrThrow("games", null, ContentValues().apply {
                put("systemSlug", platform); put("filename", "$token.$extension"); put("displayName", token); put("url", "")
                put("artifact_key", key); put("remote_artifact", artifact.toString())
            })
            val uri = OwnedRomContentProvider.localCopyUri(context, first, platform, file.name, extension == "zip")
            fun read() = context.contentResolver.openFileDescriptor(uri, "r")!!.let {
                ParcelFileDescriptor.AutoCloseInputStream(it).use { stream -> stream.readBytes() }
            }
            fun denied(action: () -> Unit) {
                try { action(); error("Invalid copy grant accepted") }
                catch (_: FileNotFoundException) { }
            }
            check(read().contentEquals(bytes))
            denied { context.contentResolver.openFileDescriptor(uri, "rw")?.close() }
            val wrongConsole = OwnedRomContentProvider.localCopyUri(context, first, "wii", file.name, false)
            denied { context.contentResolver.openFileDescriptor(wrongConsole, "r")?.close() }
            artifact.put("version", "2")
            db.update("games", ContentValues().apply { put("remote_artifact", artifact.toString()) }, "id=?", arrayOf(gameRow.toString()))
            denied { read() }
            artifact.put("version", "1")
            db.update("games", ContentValues().apply { put("remote_artifact", artifact.toString()) }, "id=?", arrayOf(gameRow.toString()))
            check(read().contentEquals(bytes))
            db.insertOrThrow("transfer_target_owners", null, ContentValues().apply {
                put("destination_root", root.path); put("relative_path", file.name); put("transfer_id", token)
            })
            denied { read() }
            db.delete("transfer_target_owners", "transfer_id=?", arrayOf(token))
            check(read().contentEquals(bytes))
            val newer = observe()
            denied { read() }
            db.delete("migration_byte_observations", "observation_id=?", arrayOf(newer.toString()))
            check(read().contentEquals(bytes))
            file.writeBytes(byteArrayOf(1))
            denied { read() }
            check(file.delete())
            denied { read() }
            db.rawQuery("SELECT COUNT(*) FROM installed_artifacts WHERE destination_root=?", arrayOf(root.path)).use {
                check(it.moveToFirst() && it.getInt(0) == 0)
            }
        } finally {
            db.delete("transfer_target_owners", "transfer_id=?", arrayOf(token))
            for (id in ids) db.delete("migration_byte_observations", "observation_id=?", arrayOf(id.toString()))
            if (gameRow != null) db.delete("games", "id=? AND artifact_key=?", arrayOf(gameRow.toString(),
                JSONArray().put("drive").put(token).put(token).put(token).toString()))
            db.close()
            check(!file.exists() || file.delete()); check(root.delete())
        }
    }
}
