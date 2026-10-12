package com.retro.rshop

import android.app.Activity
import android.app.Instrumentation
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Real provider/SQLite/native-descriptor contract. No application bootstrap,
 * accounts, source requests or user ROMs. Uses only an exclusive synthetic file
 * and exact test-owned rows in the existing migrated application database. */
class OwnedRomInstrumentation : Instrumentation() {
    private var mountProbe = false
    private var companionProbe = false
    private var saveRouteProbe = false
    private var saveGroupProbe = false
    private var melonSaveProbe = false
    private var protectedMelonSaveProbe = false
    private var melonLiveCaptureProbe = false
    private var melonSettingsProbe = false
    private var ppssppSettingsProbe = false
    private var protectedPpssppSaveProbe = false
    private var ppssppCachedExitProbe = false
    private var ppssppSavedataCaptureProbe = false
    private var ppssppRuntimeProbe: String? = null
    private var dsProviderProbe = false
    private var dsArchiveProbe = false
    private var saveWatchProbe = false
    private var missingSaveProbe = false
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        mountProbe = arguments?.getString("mountProbe") == "true"
        companionProbe = arguments?.getString("companionProbe") == "true"
        saveRouteProbe = arguments?.getString("saveRouteProbe") == "true"
        saveGroupProbe = arguments?.getString("saveGroupProbe") == "true"
        melonSaveProbe = arguments?.getString("melonSaveProbe") == "true"
        protectedMelonSaveProbe = arguments?.getString("protectedMelonSaveProbe") == "true"
        melonLiveCaptureProbe = arguments?.getString("melonLiveCaptureProbe") == "true"
        melonSettingsProbe = arguments?.getString("melonSettingsProbe") == "true"
        ppssppSettingsProbe = arguments?.getString("ppssppSettingsProbe") == "true"
        protectedPpssppSaveProbe = arguments?.getString("protectedPpssppSaveProbe") == "true"
        ppssppCachedExitProbe = arguments?.getString("ppssppCachedExitProbe") == "true"
        ppssppSavedataCaptureProbe = arguments?.getString("ppssppSavedataCaptureProbe") == "true"
        ppssppRuntimeProbe = arguments?.getString("ppssppRuntimeProbe")
        dsProviderProbe = arguments?.getString("dsProviderProbe") == "true"
        dsArchiveProbe = arguments?.getString("dsArchiveProbe") == "true"
        saveWatchProbe = arguments?.getString("saveWatchProbe") == "true"
        missingSaveProbe = arguments?.getString("missingSaveProbe") == "true"
        start()
    }

    override fun onStart() {
        val report = Bundle()
        try {
            if (dsArchiveProbe) {
                exercise(ds = true, dsZip = true)
                report.putString("result", "PASS DS ZIP document validation, unchanged archive read and live save-location review; read-only grant and native identity/ownership/publication/removal rejection; exclusive fixture cleanup; no emulator launch")
            } else if (dsProviderProbe) {
                exercise(ds = true)
                report.putString("result", "PASS DS document leaf read/name/size and launch-bound live save-location review, read-only grant and native publication/identity/ownership/removal rejection; exclusive fixture cleanup; no emulator launch")
            } else if (ppssppSavedataCaptureProbe) {
                report.putString("result", PpssppSavedataCaptureProof.exercise(targetContext))
            } else if (ppssppRuntimeProbe != null) {
                report.putString("result", PpssppProtectedSaveProof.runtime(targetContext, ppssppRuntimeProbe!!))
            } else if (protectedPpssppSaveProbe || ppssppCachedExitProbe) {
                report.putString("result", PpssppProtectedSaveProof.exercise(targetContext, ppssppCachedExitProbe))
            } else if (ppssppSettingsProbe) {
                report.putString("result", PpssppSaveSettingsProof.exercise(targetContext))
            } else if (melonSettingsProbe) {
                report.putString("result", MelonSaveSettingsProof.exercise(targetContext))
            } else if (missingSaveProbe) {
                report.putString("result", MissingSaveProof.exercise(targetContext))
            } else if (saveWatchProbe) {
                report.putString("result", SaveFileWatchProof.exercise(targetContext))
            } else if (melonSaveProbe) {
                report.putString("result", MelonSaveProof.exercise(targetContext, protectedMelonSaveProbe, melonLiveCaptureProbe))
            } else if (saveGroupProbe) {
                report.putString("result", MgbaGroupSaveProof.exercise(targetContext))
            } else if (saveRouteProbe) {
                report.putString("result", SegaSaveRouteProof.exercise(targetContext))
            } else if (companionProbe) {
                report.putString("result", CompanionProof.exercise(targetContext))
            } else if (mountProbe) {
                report.putString("result", exerciseMountBoundary())
            } else {
                exercise()
                BundleProviderProof.exercise(targetContext)
                ObservedCopyProviderProof.exercise(targetContext)
                report.putString("result", "PASS owned read, write denial, identity/ownership/publication/removal rejection; bundle ready/member grant/missing/member removal/ownership/stage/graph rejection; exact observed copy read, write/mapping/version/reservation/identity/missing/superseded rejection without ownership")
            }
            finish(Activity.RESULT_OK, report)
        } catch (error: Throwable) {
            report.putString("result", "FAIL ${error.javaClass.simpleName}: ${error.message}")
            finish(Activity.RESULT_CANCELED, report)
        }
    }

    /** Reproduce the public/private mount boundary with exclusive synthetic
     * files only. Never touch an installation, account, save or journal row. */
    private fun exerciseMountBoundary(): String {
        check(targetContext.packageName == "com.darkaxt.rshop.debug")
        val results = mutableListOf<String>()
        for (base in targetContext.getExternalFilesDirs(null).filterNotNull()) {
            val volume = base.path.substringBefore("/Android/data/")
            val id = "native-removal-proof-${UUID.randomUUID()}"
            val publicRoot = File(volume, "RShopLiveTest/$id")
            val privateRoot = File(base, id)
            check(publicRoot.mkdirs()); check(privateRoot.mkdir())
            val source = File(publicRoot, "synthetic.rvz")
            val quarantined = File(privateRoot, "synthetic.partial")
            val bytes = byteArrayOf(4, 8, 15, 16, 23, 42)
            var publicFd = -1
            var privateFd = -1
            try {
                check(source.createNewFile()); source.writeBytes(bytes)
                publicFd = OwnedStorageNative.openRoot(publicRoot.path)
                privateFd = OwnedStorageNative.openRoot(privateRoot.path)
                val expected = OwnedStorageNative.entryIdentity(publicFd, source.name)
                val sameMount = OwnedStorageNative.mountId(publicFd) == OwnedStorageNative.mountId(privateFd)
                val label = if (volume == "/storage/emulated/0") "internal" else "external"
                try {
                    OwnedStorageNative.quarantineIntoPrivate(publicFd, source.name,
                        privateFd, quarantined.name, expected)
                    check(!source.exists() && quarantined.readBytes().contentEquals(bytes))
                    results.add("$label sameMount=$sameMount quarantine=PASS")
                } catch (error: java.io.IOException) {
                    check(source.readBytes().contentEquals(bytes) && !quarantined.exists())
                    check(Regex("owned_storage:[0-9]+").matches(error.message.orEmpty()))
                    results.add("$label sameMount=$sameMount quarantine=${error.message}")
                }
            } finally {
                if (privateFd >= 0) OwnedStorageNative.close(privateFd)
                if (publicFd >= 0) OwnedStorageNative.close(publicFd)
                check(!source.exists() || source.delete())
                check(!quarantined.exists() || quarantined.delete())
                check(publicRoot.delete()); check(privateRoot.delete())
            }
        }
        return results.joinToString("; ")
    }

    private fun exercise(ds: Boolean = false, dsZip: Boolean = false) {
        check(targetContext.packageName == "com.darkaxt.rshop.debug")
        val id = "provider-proof-${UUID.randomUUID()}"
        val root = File(targetContext.getExternalFilesDir(null), id)
        check(root.mkdir())
        val rom = File(root, if (dsZip) "synthetic.zip" else if (ds) "synthetic.nds" else "synthetic.rvz")
        val raw = byteArrayOf(4, 8, 15, 16, 23, 42)
        val bytes = if (dsZip) java.io.ByteArrayOutputStream().also { output ->
            java.util.zip.ZipOutputStream(output).use { zip ->
                // Save naming is bound to the archive, not this member's name.
                zip.putNextEntry(java.util.zip.ZipEntry("different-member.nds"))
                zip.write(raw); zip.closeEntry()
            }
        }.toByteArray() else raw
        val db = SQLiteDatabase.openDatabase(targetContext.getDatabasePath("rshop.db").path,
            null, SQLiteDatabase.OPEN_READWRITE)
        try {
            check(rom.createNewFile())
            rom.outputStream().use { it.write(bytes) }
            val rootFd = OwnedStorageNative.openRoot(root.path)
            val identity: LongArray
            try {
                val fd = OwnedStorageNative.openFile(rootFd, rom.name, false, false)
                try { identity = OwnedStorageNative.identity(fd) }
                finally { OwnedStorageNative.close(fd) }
            } finally { OwnedStorageNative.close(rootFd) }
            val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date(identity[3] * 1000)) + "." + (identity[4] / 1000).toString().padStart(6, '0') + "Z"
            val native = JSONObject().put("volumeId", identity[0].toString())
                .put("fileId", identity[1].toString()).put("sizeBytes", identity[2])
                .put("modifiedAt", stamp).put("modifiedNanoseconds", identity[4])
            val artifact = JSONObject().put("fixture", "exact synthetic version")
            val digests = JSONObject().put("sha256", "fixture streaming digest")
            val installed = JSONObject().put("id", id).put("transferId", id)
                .put("destinationRoot", root.path).put("relativePath", rom.name)
                .put("sizeBytes", bytes.size).put("artifact", artifact)
                .put("verifiedChecksums", digests).put("fileIdentity", native)
            val publication = JSONObject().put("confirmed", true).put("destinationIdentity", native)
            val transfer = JSONObject().put("id", id).put("destinationRoot", root.path)
                .put("relativePath", rom.name).put("lifecycle", "completed")
                .put("artifact", artifact).put("verifiedChecksums", digests)
                .put("publication", publication)
            if (dsZip) transfer.put("archivePlatformId", "nds")
            fun saveTransfer() { db.update("transfer_records", ContentValues().apply {
                put("record_json", transfer.toString())
            }, "transfer_id=?", arrayOf(id)) }
            db.beginTransaction()
            try {
                db.insertOrThrow("transfer_records", null, ContentValues().apply {
                    put("transfer_id", id); put("artifact_key", id); put("destination_root", root.path)
                    put("relative_path", rom.name); put("lifecycle", "completed")
                    put("durable_offset", bytes.size); put("revision", 1); put("record_json", transfer.toString())
                })
                db.insertOrThrow("installed_artifacts", null, ContentValues().apply {
                    put("installation_id", id); put("transfer_id", id)
                    put("destination_root", root.path); put("relative_path", rom.name)
                    put("record_json", installed.toString())
                })
                fun owner() = ContentValues().apply {
                    put("installation_id", id); put("transfer_id", id)
                    put("destination_root", root.path); put("relative_path", rom.name)
                }
                db.insertOrThrow("transfer_target_owners", null, owner())
                db.setTransactionSuccessful()
            } finally { db.endTransaction() }
            val uri = if (ds) OwnedRomContentProvider.gameGearUri(targetContext, id, rom.name)
                else OwnedRomContentProvider.uri(targetContext, id, rom.name)
            if (ds) OwnedRomContentProvider.openCommitted(targetContext, uri,
                requiredArchivePlatform = if (dsZip) "nds" else null,
                requiredStandaloneNds = !dsZip).use { }
            if (ds) {
                val service = OwnedStorageService(targetContext)
                val done = CountDownLatch(1)
                var mapping: Any? = null
                var failure: String? = null
                try {
                    service.handle(MethodCall("reviewOwnedMelonSave", mapOf(
                        "installationId" to id, "filename" to rom.name)), object : MethodChannel.Result {
                        override fun success(value: Any?) { mapping = value; done.countDown() }
                        override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                        override fun notImplemented() { failure = "not_implemented"; done.countDown() }
                    })
                    done.await()
                    check(failure == null) { failure ?: "review_missing" }
                    val settings = SaveSourceStorage.melonSettings(targetContext)
                    val expectedDirectory = if (settings.isNull("directory")) MelonSaveBoundary.PROTECTED_SOURCE
                        else settings.getString("directory")
                    check(mapping == mapOf("directory" to expectedDirectory,
                        "name" to "synthetic.${settings.getString("extension")}"))
                } finally { service.shutdown() }
            }
            val resolver = targetContext.contentResolver
            fun read() = resolver.openFileDescriptor(uri, "r")!!.let { descriptor ->
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes() }
            }
            fun denied(label: String, action: () -> Unit) {
                try { action() } catch (_: FileNotFoundException) { return }
                error("Accepted $label")
            }
            check(read().contentEquals(bytes))
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)!!.use {
                check(it.moveToFirst() && it.getString(0) == rom.name && it.getLong(1) == bytes.size.toLong())
            }
            denied("write grant") { resolver.openFileDescriptor(uri, "rw")?.close() }
            publication.put("confirmed", false); saveTransfer()
            denied("unconfirmed publication") { read() }
            publication.put("confirmed", true); saveTransfer()
            transfer.put("artifact", JSONObject().put("fixture", "different version")); saveTransfer()
            denied("different source artifact") { read() }
            transfer.put("artifact", artifact); saveTransfer()
            transfer.put("verifiedChecksums", JSONObject().put("sha256", "different digest")); saveTransfer()
            denied("different digest") { read() }
            transfer.put("verifiedChecksums", digests); saveTransfer()
            db.delete("transfer_target_owners", "transfer_id=?", arrayOf(id))
            denied("released owner") { read() }
            db.insertOrThrow("transfer_target_owners", null, ContentValues().apply {
                put("installation_id", id); put("transfer_id", id)
                put("destination_root", root.path); put("relative_path", rom.name)
            })
            db.insertOrThrow("owned_removals", null, ContentValues().apply {
                put("removal_id", id); put("transfer_id", id); put("phase", "intent")
                put("record_json", "{}"); put("revision", 0)
            })
            denied("pending removal") { read() }
            db.update("owned_removals", ContentValues().apply { put("phase", "retained") },
                "removal_id=?", arrayOf(id))
            check(read().contentEquals(bytes))
            db.delete("owned_removals", "removal_id=?", arrayOf(id))
            check(read().contentEquals(bytes))
            rom.appendBytes(byteArrayOf(99))
            denied("changed native object") { read() }
        } finally {
            db.beginTransaction()
            try {
                db.delete("owned_removals", "removal_id=?", arrayOf(id))
                db.delete("installed_artifacts", "installation_id=?", arrayOf(id))
                db.delete("transfer_target_owners", "transfer_id=?", arrayOf(id))
                db.delete("transfer_records", "transfer_id=?", arrayOf(id))
                db.setTransactionSuccessful()
            } finally { db.endTransaction(); db.close() }
            check(!rom.exists() || rom.delete())
            check(root.delete())
        }
    }
}
