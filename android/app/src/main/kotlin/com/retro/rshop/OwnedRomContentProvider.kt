package com.retro.rshop

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileNotFoundException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Per-installation read grants, not an arbitrary public-path FileProvider.
 * Re-check the committed owner and current object at every external open, even
 * after a process restart. Removed/replaced namesakes cannot reuse an old URI. */
class OwnedRomContentProvider : ContentProvider() {
    override fun onCreate() = true
    override fun getType(uri: Uri): String { manifest(providerContext(), uri); return "application/octet-stream" }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    private fun providerContext() = context ?: throw FileNotFoundException("Owned ROM unavailable")

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val saved = manifest(providerContext(), uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(columns.map { when (it) {
                OpenableColumns.DISPLAY_NAME -> saved.getString("relativePath").substringAfterLast('/')
                OpenableColumns.SIZE -> saved.getLong("sizeBytes")
                DocumentsContract.Document.COLUMN_MIME_TYPE -> "application/octet-stream"
                DocumentsContract.Document.COLUMN_DOCUMENT_ID -> "${saved.getString("id")}/${saved.getString("relativePath").substringAfterLast('/')}"
                DocumentsContract.Document.COLUMN_FLAGS -> 0
                else -> null
            } })
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read-only ROM grant")
        return openCommitted(providerContext(), uri)
    }

    companion object {
        fun uri(context: Context, id: String, filename: String): Uri = Uri.Builder()
            .scheme("content").authority("${context.packageName}.owned-roms")
            .appendPath("installation").appendPath(id).appendPath(filename.substringAfterLast('/')).build()

        // RetroArch's SAF VFS converts a generic content URI to an unnamed root.
        // A document-shaped leaf retains its ZIP extension and member metadata.
        // Grant this exact URI only: no prefix/persistable or directory access.
        fun gameGearUri(context: Context, id: String, filename: String): Uri {
            val tree = DocumentsContract.buildTreeDocumentUri("${context.packageName}.owned-roms", id)
            val result = DocumentsContract.buildDocumentUriUsingTree(tree, "$id/${filename.substringAfterLast('/')}")
            OwnedRomGrantPath.parse(result.pathSegments)
            return result
        }

        /** Historical byte evidence grants only a currently revalidated leaf.
         * This namespace never creates or substitutes installation ownership. */
        fun localCopyUri(context: Context, observationId: Long, platform: String,
            filename: String, document: Boolean): Uri {
            val id = "copy:$observationId:$platform"
            val result = if (document) gameGearUri(context, id, filename)
                else Uri.Builder().scheme("content").authority("${context.packageName}.owned-roms")
                    .appendPath("copy").appendPath(id).appendPath(filename.substringAfterLast('/')).build()
            OwnedRomGrantPath.parse(result.pathSegments)
            return result
        }

        private fun manifest(context: Context, uri: Uri, bundleOwner: String? = null,
            requiredArchivePlatform: String? = null, requiredStandaloneChd: Boolean = false,
            requiredStandaloneWua: Boolean = false, requiredStandaloneNds: Boolean = false): JSONObject {
            if (uri.scheme != "content" || uri.authority != "${context.packageName}.owned-roms" ||
                uri.query != null || uri.fragment != null) throw FileNotFoundException("Invalid ROM grant")
            val grant = OwnedRomGrantPath.parse(uri.pathSegments)
            val db = SQLiteDatabase.openDatabase(context.getDatabasePath("rshop.db").path,
                null, SQLiteDatabase.OPEN_READONLY)
            try {
                if (grant.observationId != null) {
                    if (bundleOwner != null ||
                        (requiredArchivePlatform != null && requiredArchivePlatform != grant.platform) ||
                        (requiredStandaloneChd && grant.platform !in setOf("psx", "psp", "ps2")) ||
                        (requiredStandaloneWua && grant.platform != "wiiu") ||
                        (requiredStandaloneNds && grant.platform != "nds")) {
                        throw FileNotFoundException("Local copy mapping changed")
                    }
                    return observedCopy(db, grant)
                }
                db.rawQuery("""SELECT i.record_json, t.record_json, i.transfer_id,
                    i.destination_root, i.relative_path, t.bundle_owner FROM installed_artifacts i
                    JOIN transfer_target_owners o ON o.installation_id=i.installation_id
                      AND o.transfer_id=i.transfer_id AND o.destination_root=i.destination_root
                      AND o.relative_path=i.relative_path
                    JOIN transfer_records t ON t.transfer_id=i.transfer_id
                      AND t.destination_root=i.destination_root AND t.relative_path=i.relative_path
                    WHERE i.installation_id=? AND t.lifecycle='completed'
                      AND NOT EXISTS(SELECT 1 FROM owned_removals r
                        WHERE r.transfer_id=i.transfer_id AND r.phase NOT IN ('completed', 'retained'))""",
                    arrayOf(grant.installationId)).use { cursor ->
                    if (!cursor.moveToFirst()) throw FileNotFoundException("Installation not ready")
                    val result = JSONObject(cursor.getString(0))
                    val transfer = JSONObject(cursor.getString(1))
                    val publication = transfer.getJSONObject("publication")
                    val checksums = result.getJSONObject("verifiedChecksums")
                    val owner = if (cursor.isNull(5)) null else cursor.getString(5)
                    if (owner != bundleOwner) throw FileNotFoundException("Bundle member has no independent grant")
                    if (owner != null && publication.optString("method") == "copy" &&
                        !transfer.optBoolean("stageRetired")) throw FileNotFoundException("Bundle member stage pending")
                    if (result.getString("id") != grant.installationId ||
                        result.getString("transferId") != cursor.getString(2) ||
                        transfer.getString("id") != cursor.getString(2) ||
                        result.getString("destinationRoot") != cursor.getString(3) ||
                        transfer.getString("destinationRoot") != cursor.getString(3) ||
                        result.getString("relativePath") != cursor.getString(4) ||
                        transfer.getString("relativePath") != cursor.getString(4) ||
                        cursor.getString(4).substringAfterLast('/') != grant.filename ||
                        transfer.getString("lifecycle") != "completed" ||
                        !publication.getBoolean("confirmed") || checksums.length() == 0 ||
                        !sameJson(result.getJSONObject("artifact"), transfer.getJSONObject("artifact")) ||
                        !sameJson(checksums, transfer.getJSONObject("verifiedChecksums")) ||
                        !sameJson(result.getJSONObject("fileIdentity"), publication.getJSONObject("destinationIdentity")) ||
                        result.getLong("sizeBytes") != result.getJSONObject("fileIdentity").getLong("sizeBytes")) {
                        throw FileNotFoundException("Installation changed")
                    }
                    val dependencies = result.optJSONArray("dependencies") ?: JSONArray()
                    val members = transfer.optJSONArray("bundleMembers") ?: JSONArray()
                    val filename = grant.filename.lowercase(Locale.ROOT)
                    val platform = transfer.optString("archivePlatformId")
                    val supportedArchive = (platform in setOf("gamegear", "megadrive", "mastersystem", "sg1000") && filename.endsWith(".zip")) ||
                        (platform in setOf("gb", "gbc", "gba", "nes", "snes") && filename.endsWith(".7z")) ||
                        (platform == "n64" && (filename.endsWith(".7z") || filename.endsWith(".zip")))
                    val standaloneChd = OwnedRomGrantPath.standaloneChd(filename, platform,
                        owner != null, dependencies.length(), members.length())
                    val standaloneWua = OwnedRomGrantPath.standaloneWua(filename, platform,
                        owner != null, dependencies.length(), members.length())
                    val standaloneNds = OwnedRomGrantPath.standaloneNds(filename, platform,
                        owner != null, dependencies.length(), members.length())
                    if (requiredArchivePlatform != null && platform != requiredArchivePlatform) {
                        throw FileNotFoundException("Archive mapping changed")
                    }
                    if (requiredStandaloneChd && !standaloneChd) {
                        throw FileNotFoundException("Unsupported standalone CHD grant")
                    }
                    if (requiredStandaloneWua && !standaloneWua) {
                        throw FileNotFoundException("Unsupported standalone WUA grant")
                    }
                    if (requiredStandaloneNds && !standaloneNds) {
                        throw FileNotFoundException("Unsupported standalone DS grant")
                    }
                    if (grant.document && !supportedArchive && !standaloneChd && !standaloneWua && !standaloneNds) {
                        throw FileNotFoundException("Unsupported document grant")
                    }
                    if ((filename.endsWith(".zip") || filename.endsWith(".7z") || filename.endsWith(".rar")) &&
                        (!supportedArchive || owner != null ||
                            dependencies.length() != 0 || members.length() != 0)) {
                        throw FileNotFoundException("Unsupported archive intent")
                    }
                    if (dependencies.length() > 256 || dependencies.length() != members.length() ||
                        (bundleOwner != null && dependencies.length() != 0)) {
                        throw FileNotFoundException("Bundle graph changed")
                    }
                    for (i in 0 until dependencies.length()) {
                        val child = dependencies.getJSONObject(i)
                        val member = members.getJSONObject(i)
                        if (child.getString("destinationRoot") != result.getString("destinationRoot") ||
                            member.getString("transferId") != child.getString("transferId") ||
                            member.getString("relativePath") != child.getString("relativePath") ||
                            !sameJson(member.getJSONObject("artifact"), child.getJSONObject("artifact"))) {
                            throw FileNotFoundException("Bundle member changed")
                        }
                        val childUri = OwnedRomContentProvider.uri(context, child.getString("id"), child.getString("relativePath"))
                        if (!sameJson(child, manifest(context, childUri, result.getString("transferId")))) {
                            throw FileNotFoundException("Bundle ownership changed")
                        }
                        openCommitted(context, childUri, result.getString("transferId")).use { }
                    }
                    if (supportedArchive) result.put("_validatedArchivePlatformId", platform)
                    return result
                }
            } finally { db.close() }
        }

        private fun observedCopy(db: SQLiteDatabase, grant: OwnedRomGrantPath): JSONObject {
            val id = grant.observationId ?: throw FileNotFoundException("Invalid copy grant")
            val saved: JSONObject
            val key: String
            val root: String
            val relative: String
            db.rawQuery("""SELECT artifact_key, destination_root, relative_path,
                CASE WHEN length(CAST(record_json AS BLOB))<=16384 THEN record_json END
                FROM migration_byte_observations WHERE observation_id=?""", arrayOf(id.toString())).use {
                if (!it.moveToFirst() || it.isNull(3)) throw FileNotFoundException("Copy unavailable")
                key = it.getString(0); root = it.getString(1); relative = it.getString(2)
                saved = JSONObject(it.getString(3))
            }
            val artifact = saved.getJSONObject("artifact")
            val identity = saved.getJSONObject("localIdentity")
            val size = saved.getLong("sizeBytes")
            val tuple = JSONArray(key)
            val remoteId = artifact.getJSONObject("id")
            if (saved.getInt("schema") != 1 || saved.getString("destinationRoot") != root ||
                saved.getString("relativePath") != relative || relative != grant.filename ||
                relative != artifact.getString("displayName") || !root.startsWith('/') || root == "/" ||
                root.contains('\\') || root.contains('\u0000') ||
                root.split('/').drop(1).any { it.isEmpty() || it == "." || it == ".." } ||
                relative.contains('\\') || relative.contains('/') || relative.any { it.isISOControl() } ||
                size < 0 || size != artifact.getLong("sizeBytes") || size != identity.getLong("sizeBytes") ||
                artifact.getString("version").isEmpty() || !artifact.getBoolean("canDownload") ||
                tuple.length() != 4 || tuple.getString(0) != "drive" || remoteId.getString("providerId") != "drive" ||
                tuple.getString(1) != remoteId.getString("sourceId") ||
                tuple.getString(2) != remoteId.getString("accountId") || tuple.getString(2).isEmpty() ||
                tuple.getString(3) != remoteId.getString("providerFileId")) {
                throw FileNotFoundException("Copy evidence changed")
            }
            val digests = saved.getJSONObject("checksums")
            val expected = artifact.getJSONObject("providerChecksums")
            val lengths = mapOf("md5" to 32, "sha1" to 40, "sha256" to 64)
            if (!digests.has("sha256") || digests.keys().asSequence().any {
                    val length = lengths[it]
                    length == null || !Regex("[0-9a-f]{$length}").matches(digests.getString(it))
                } || expected.keys().asSequence().none { lengths.containsKey(it) } ||
                expected.keys().asSequence().filter { lengths.containsKey(it) }.any {
                    val value = expected.getString(it).lowercase(Locale.ROOT)
                    !Regex("[0-9a-f]{${lengths[it]}}").matches(value) || digests.optString(it) != value
                }) throw FileNotFoundException("Copy bytes unverified")

            // Latest evidence for every identity at this path is bounded before decoding.
            // Another matching identity or malformed evidence cannot select an arbitrary ROM.
            var matching = 0
            var current = false
            db.rawQuery("""SELECT o.observation_id, CASE WHEN length(CAST(o.record_json AS BLOB))<=16384
                THEN o.record_json END FROM migration_byte_observations o
                WHERE o.destination_root=? AND o.relative_path=? AND NOT EXISTS (
                    SELECT 1 FROM migration_byte_observations n WHERE n.artifact_key=o.artifact_key
                    AND n.destination_root=o.destination_root AND n.relative_path=o.relative_path
                    AND n.observation_id>o.observation_id)""", arrayOf(root, relative)).use {
                while (it.moveToNext()) {
                    if (it.isNull(1)) throw FileNotFoundException("Copy evidence unavailable")
                    val other = JSONObject(it.getString(1))
                    if (sameJson(other.getJSONObject("localIdentity"), identity)) matching++
                    if (it.getLong(0) == id) current = true
                }
            }
            if (!current || matching != 1) throw FileNotFoundException("Copy evidence superseded or ambiguous")
            val path = "$root/$relative"
            db.rawQuery("SELECT destination_root, relative_path FROM transfer_target_owners", null).use {
                while (it.moveToNext()) {
                    val owned = "${it.getString(0)}/${it.getString(1)}"
                    if (owned == path || owned.startsWith("$path/") || path.startsWith("$owned/")) {
                        throw FileNotFoundException("Copy is reserved by an installation")
                    }
                }
            }
            db.rawQuery("""SELECT CASE WHEN length(CAST(remote_artifact AS BLOB))<=16384
                THEN remote_artifact END FROM games WHERE artifact_key=? AND systemSlug=? LIMIT 2""",
                arrayOf(key, grant.platform)).use {
                if (!it.moveToFirst() || it.isNull(0)) throw FileNotFoundException("Copy catalogue unavailable")
                val remote = JSONObject(it.getString(0))
                if (!sameJson(remote.getJSONObject("id"), remoteId) || remote.optString("version") != artifact.getString("version") ||
                    remote.getLong("sizeBytes") != size || !sameJson(remote.getJSONObject("providerChecksums"), expected) ||
                    it.moveToNext()) throw FileNotFoundException("Copy catalogue changed")
            }
            val filename = relative.lowercase(Locale.ROOT)
            val platform = grant.platform
            val archive = (platform in setOf("gamegear", "megadrive", "mastersystem", "sg1000") && filename.endsWith(".zip")) ||
                (platform in setOf("gb", "gbc", "gba", "nes", "snes") && filename.endsWith(".7z")) ||
                (platform == "n64" && (filename.endsWith(".7z") || filename.endsWith(".zip")))
            val supported = archive ||
                (platform in setOf("psx", "psp", "ps2") && filename.endsWith(".chd")) ||
                (platform == "wiiu" && filename.endsWith(".wua")) ||
                (platform == "nds" && filename.endsWith(".nds")) ||
                (platform in setOf("gc", "wii") && listOf(".rvz", ".iso", ".gcm", ".wbfs").any(filename::endsWith))
            if (!supported) throw FileNotFoundException("Unsupported copy format")
            return JSONObject().put("id", grant.installationId).put("destinationRoot", root)
                .put("relativePath", relative).put("sizeBytes", size).put("fileIdentity", identity)
                .put("_validatedArchivePlatformId", if (archive) platform else "")
        }

        // Match the Dart InstallationIndex contract without depending on JSON
        // member ordering. This provider also runs when Flutter is not alive.
        private fun sameJson(a: Any?, b: Any?): Boolean = when {
            a is JSONObject && b is JSONObject -> a.length() == b.length() &&
                a.keys().asSequence().all { b.has(it) && sameJson(a.get(it), b.get(it)) }
            a is JSONArray && b is JSONArray -> a.length() == b.length() &&
                (0 until a.length()).all { sameJson(a.get(it), b.get(it)) }
            else -> a == b
        }

        fun openCommitted(context: Context, uri: Uri, bundleOwner: String? = null,
            requiredArchivePlatform: String? = null, requiredStandaloneChd: Boolean = false,
            requiredStandaloneWua: Boolean = false, requiredStandaloneNds: Boolean = false): ParcelFileDescriptor {
            var root = -1; var parent = -1; var file = -1; var checkedRoot = -1; var checkedParent = -1
            try {
                val saved = manifest(context, uri, bundleOwner, requiredArchivePlatform,
                    requiredStandaloneChd, requiredStandaloneWua, requiredStandaloneNds)
                val rootPath = saved.getString("destinationRoot")
                val relative = saved.getString("relativePath")
                val pieces = relative.split('/')
                if (pieces.any { it.isEmpty() || it == "." || it == ".." || it.contains('\\') } ||
                    !rootPath.startsWith('/') || relative.contains('\u0000')) {
                    throw FileNotFoundException("Invalid installation path")
                }
                val directory = pieces.dropLast(1).joinToString("/")
                root = OwnedStorageNative.openRoot(rootPath)
                parent = if (directory.isEmpty()) OwnedStorageNative.openRoot(rootPath)
                    else OwnedStorageNative.openDirectory(root, directory, false)
                file = OwnedStorageNative.openFile(parent, pieces.last(), false, false)
                val expected = saved.getJSONObject("fileIdentity")
                val timestamp = expected.getString("modifiedAt")
                if (!timestamp.endsWith("Z") || timestamp.length < 20) {
                    throw FileNotFoundException("Invalid native timestamp")
                }
                val seconds = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC"); isLenient = false
                }.parse(timestamp.substring(0, 19))!!.time / 1000
                val identity = longArrayOf(expected.getString("volumeId").toLong(),
                    expected.getString("fileId").toLong(), expected.getLong("sizeBytes"),
                    seconds, expected.getLong("modifiedNanoseconds"))
                if (!OwnedStorageNative.identity(file).contentEquals(identity)) {
                    throw FileNotFoundException("Installation object changed")
                }
                val platform = saved.optString("_validatedArchivePlatformId")
                if (platform.isNotEmpty()) {
                    val path = "/proc/self/fd/$file"
                    if (platform == "gamegear") OwnedGameGearZip.validate(path)
                    else if (platform in setOf("megadrive", "mastersystem", "sg1000")) OwnedGameGearZip.validate(path, platform)
                    else if (relative.lowercase(Locale.ROOT).endsWith(".7z")) OwnedN64SevenZip.validate(path, platform)
                    else OwnedGameGearZip.validateN64(path)
                    if (!OwnedStorageNative.identity(file).contentEquals(identity)) {
                        throw FileNotFoundException("Archive changed during validation")
                    }
                }
                checkedRoot = OwnedStorageNative.openRoot(rootPath)
                checkedParent = if (directory.isEmpty()) OwnedStorageNative.openRoot(rootPath)
                    else OwnedStorageNative.openDirectory(checkedRoot, directory, false)
                fun sameObject(a: Int, b: Int): Boolean {
                    val x = OwnedStorageNative.identity(a); val y = OwnedStorageNative.identity(b)
                    return x[0] == y[0] && x[1] == y[1]
                }
                if (!sameObject(root, checkedRoot) || !sameObject(parent, checkedParent) ||
                    !OwnedStorageNative.entryIdentity(checkedParent, pieces.last()).contentEquals(identity)) {
                    throw FileNotFoundException("Installation path changed")
                }
                // Recheck durable ownership after opening the pinned object.
                if (!sameJson(manifest(context, uri, bundleOwner, requiredArchivePlatform,
                        requiredStandaloneChd, requiredStandaloneWua, requiredStandaloneNds), saved)) {
                    throw FileNotFoundException("Installation ownership changed")
                }
                val result = ParcelFileDescriptor.adoptFd(file)
                file = -1
                return result
            } catch (_: Exception) {
                throw FileNotFoundException("Owned ROM unavailable")
            } finally {
                for (fd in listOf(file, checkedParent, checkedRoot, parent, root)) {
                    if (fd >= 0) OwnedStorageNative.close(fd)
                }
            }
        }
    }
}
