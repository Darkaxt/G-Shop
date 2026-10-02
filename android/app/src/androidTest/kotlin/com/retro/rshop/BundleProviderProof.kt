package com.retro.rshop

import android.content.ContentValues
import android.content.Context
import android.content.ContextWrapper
import android.database.sqlite.SQLiteDatabase
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Native provider contract against a private synthetic DB, not the user library. */
internal object BundleProviderProof {
    fun exercise(context: Context) {
        val id = "bundle-provider-proof-${UUID.randomUUID()}"
        val root = File(context.getExternalFilesDir(null), id)
        check(root.mkdir())
        val dbPath = File(context.filesDir, "$id.sqlite")
        check(!dbPath.exists())
        val isolated = object : ContextWrapper(context) {
            override fun getDatabasePath(name: String): File = dbPath
        }
        val db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
        val parentFile = File(root, "game.m3u")
        val childFile = File(root, "disc.chd")
        val missing = File(root, "disc.missing-proof")
        try {
            db.execSQL("CREATE TABLE transfer_records(transfer_id TEXT PRIMARY KEY,destination_root TEXT,relative_path TEXT,lifecycle TEXT,bundle_owner TEXT,record_json TEXT)")
            db.execSQL("CREATE TABLE installed_artifacts(installation_id TEXT PRIMARY KEY,transfer_id TEXT,destination_root TEXT,relative_path TEXT,record_json TEXT)")
            db.execSQL("CREATE TABLE transfer_target_owners(installation_id TEXT,transfer_id TEXT,destination_root TEXT,relative_path TEXT)")
            db.execSQL("CREATE TABLE owned_removals(transfer_id TEXT,phase TEXT)")
            check(parentFile.createNewFile()); parentFile.writeText("disc.chd\n")
            check(childFile.createNewFile()); childFile.writeBytes(byteArrayOf(4, 8, 15))
            fun snapshot(file: File, transferId: String): JSONObject {
                val fd = OwnedStorageNative.openRoot(root.path)
                val native = try { OwnedStorageNative.entryIdentity(fd, file.name) }
                    finally { OwnedStorageNative.close(fd) }
                val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.format(Date(native[3] * 1000)) + "." + (native[4] / 1000).toString().padStart(6, '0') + "Z"
                val identity = JSONObject().put("volumeId", native[0].toString())
                    .put("fileId", native[1].toString()).put("sizeBytes", native[2])
                    .put("modifiedAt", stamp).put("modifiedNanoseconds", native[4])
                return JSONObject().put("id", transferId).put("transferId", transferId)
                    .put("destinationRoot", root.path).put("relativePath", file.name)
                    .put("sizeBytes", file.length()).put("fileIdentity", identity)
                    .put("artifact", JSONObject().put("fixture", transferId))
                    .put("verifiedChecksums", JSONObject().put("sha256", "synthetic digest"))
            }
            val child = snapshot(childFile, "$id-child")
            val parent = snapshot(parentFile, id).put("dependencies", JSONArray().put(child))
            fun record(saved: JSONObject): JSONObject = JSONObject(saved.toString())
                .put("lifecycle", "completed").put("stageRetired", true)
                .put("publication", JSONObject().put("confirmed", true).put("method", "copy")
                    .put("destinationIdentity", saved.getJSONObject("fileIdentity")))
            val childRecord = record(child).put("bundleOwner", id)
            val members = JSONArray().put(JSONObject().put("transferId", child.getString("transferId"))
                .put("relativePath", childFile.name).put("artifact", child.getJSONObject("artifact")))
            val parentRecord = record(parent).put("bundleMembers", members)
            fun insert(saved: JSONObject, transfer: JSONObject, owner: String?) {
                val keys = ContentValues().apply {
                    put("transfer_id", saved.getString("transferId")); put("destination_root", root.path)
                    put("relative_path", saved.getString("relativePath"))
                }
                db.insertOrThrow("transfer_records", null, ContentValues(keys).apply {
                    put("lifecycle", "completed"); put("bundle_owner", owner); put("record_json", transfer.toString())
                })
                db.insertOrThrow("installed_artifacts", null, ContentValues(keys).apply {
                    put("installation_id", saved.getString("id")); put("record_json", saved.toString())
                })
                db.insertOrThrow("transfer_target_owners", null, ContentValues(keys).apply {
                    put("installation_id", saved.getString("id"))
                })
            }
            insert(child, childRecord, id); insert(parent, parentRecord, null)
            fun read(saved: JSONObject): ByteArray = OwnedRomContentProvider.openCommitted(isolated,
                OwnedRomContentProvider.uri(isolated, saved.getString("id"), saved.getString("relativePath")))
                .let { ParcelFileDescriptor.AutoCloseInputStream(it).use { stream -> stream.readBytes() } }
            fun denied(label: String, action: () -> Unit) {
                try { action() } catch (_: FileNotFoundException) { return }
                error("Accepted $label")
            }
            fun update(transfer: JSONObject) = db.update("transfer_records", ContentValues().apply {
                put("record_json", transfer.toString())
            }, "transfer_id=?", arrayOf(transfer.getString("id")))
            check(read(parent).contentEquals(parentFile.readBytes()))
            denied("independent member grant") { read(child) }
            check(childFile.renameTo(missing))
            denied("missing required disc") { read(parent) }
            check(missing.renameTo(childFile)); check(read(parent).isNotEmpty())
            db.execSQL("INSERT INTO owned_removals VALUES(?, 'intent')", arrayOf(child.getString("transferId")))
            denied("member removal in progress") { read(parent) }
            db.delete("owned_removals", null, null)
            db.execSQL("UPDATE transfer_records SET bundle_owner=NULL WHERE transfer_id=?", arrayOf(child.getString("transferId")))
            denied("changed member owner") { read(parent) }
            db.execSQL("UPDATE transfer_records SET bundle_owner=? WHERE transfer_id=?", arrayOf(id, child.getString("transferId")))
            childRecord.put("stageRetired", false); update(childRecord)
            denied("unretired member copy stage") { read(parent) }
            childRecord.put("stageRetired", true); update(childRecord)
            members.getJSONObject(0).put("relativePath", "wrong.chd"); update(parentRecord)
            denied("different dependency graph") { read(parent) }
            members.getJSONObject(0).put("relativePath", childFile.name); update(parentRecord)
            check(read(parent).isNotEmpty())
            childFile.appendBytes(byteArrayOf(99))
            denied("changed native member") { read(parent) }
        } finally {
            db.close()
            for (file in listOf(parentFile, childFile, missing, dbPath,
                File("${dbPath.path}-journal"), File("${dbPath.path}-wal"), File("${dbPath.path}-shm"))) {
                check(!file.exists() || file.delete())
            }
            check(root.delete())
        }
    }
}
