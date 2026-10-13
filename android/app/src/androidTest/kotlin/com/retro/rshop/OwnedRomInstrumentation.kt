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
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch

/** Real provider/SQLite/native-descriptor contract. No application bootstrap,
 * accounts, source requests or user ROMs. Uses only an exclusive synthetic file
 * and exact test-owned rows in the existing migrated application database. */
class OwnedRomInstrumentation : Instrumentation() {
    private var mountProbe = false
    private var companionProbe = false
    private var saveRouteProbe = false
    private var n64SaveProbe = false
    private var nesSaveProbe = false
    private var snesSaveProbe = false
    private var sameBoySaveProbe: String? = null
    private var saveGroupProbe = false
    private var melonSaveProbe = false
    private var protectedMelonSaveProbe = false
    private var melonLiveCaptureProbe = false
    private var melonSettingsProbe = false
    private var ppssppSettingsProbe = false
    private var pcsxSettingsProbe = false
    private var pcsxCaptureProbe = false
    private var pcsxRestoreProbe = false
    private var pcsxWatchProbe = false
    private var protectedPpssppSaveProbe = false
    private var ppssppCachedExitProbe = false
    private var ppssppSavedataCaptureProbe = false
    private var ppssppCompanionProbe = false
    private var romCompanionProbe = false
    private var standardSaveRootProbe = false
    private var standardSaveRootPlatform = "ps2"
    private var ppssppRuntimeProbe: String? = null
    private var dsProviderProbe = false
    private var dsArchiveProbe = false
    private var saveWatchProbe = false
    private var retroArchWatchProbe = false
    private var retroArchSnapshotProbe = false
    private var automaticSaveDiagnosis = false
    private var missingSaveProbe = false
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        mountProbe = arguments?.getString("mountProbe") == "true"
        companionProbe = arguments?.getString("companionProbe") == "true"
        saveRouteProbe = arguments?.getString("saveRouteProbe") == "true"
        n64SaveProbe = arguments?.getString("n64SaveProbe") == "true"
        nesSaveProbe = arguments?.getString("nesSaveProbe") == "true"
        snesSaveProbe = arguments?.getString("snesSaveProbe") == "true"
        sameBoySaveProbe = arguments?.getString("sameBoySaveProbe")
        saveGroupProbe = arguments?.getString("saveGroupProbe") == "true"
        melonSaveProbe = arguments?.getString("melonSaveProbe") == "true"
        protectedMelonSaveProbe = arguments?.getString("protectedMelonSaveProbe") == "true"
        melonLiveCaptureProbe = arguments?.getString("melonLiveCaptureProbe") == "true"
        melonSettingsProbe = arguments?.getString("melonSettingsProbe") == "true"
        ppssppSettingsProbe = arguments?.getString("ppssppSettingsProbe") == "true"
        pcsxSettingsProbe = arguments?.getString("pcsxSettingsProbe") == "true"
        pcsxCaptureProbe = arguments?.getString("pcsxCaptureProbe") == "true"
        pcsxRestoreProbe = arguments?.getString("pcsxRestoreProbe") == "true"
        pcsxWatchProbe = arguments?.getString("pcsxWatchProbe") == "true"
        protectedPpssppSaveProbe = arguments?.getString("protectedPpssppSaveProbe") == "true"
        ppssppCachedExitProbe = arguments?.getString("ppssppCachedExitProbe") == "true"
        ppssppSavedataCaptureProbe = arguments?.getString("ppssppSavedataCaptureProbe") == "true"
        ppssppCompanionProbe = arguments?.getString("ppssppCompanionProbe") == "true"
        romCompanionProbe = arguments?.getString("romCompanionProbe") == "true"
        standardSaveRootProbe = arguments?.getString("standardSaveRootProbe") == "true"
        standardSaveRootPlatform = arguments?.getString("standardSaveRootPlatform") ?: "ps2"
        ppssppRuntimeProbe = arguments?.getString("ppssppRuntimeProbe")
        dsProviderProbe = arguments?.getString("dsProviderProbe") == "true"
        dsArchiveProbe = arguments?.getString("dsArchiveProbe") == "true"
        saveWatchProbe = arguments?.getString("saveWatchProbe") == "true"
        retroArchWatchProbe = arguments?.getString("retroArchWatchProbe") == "true"
        retroArchSnapshotProbe = arguments?.getString("retroArchSnapshotProbe") == "true"
        automaticSaveDiagnosis = arguments?.getString("automaticSaveDiagnosis") == "true"
        missingSaveProbe = arguments?.getString("missingSaveProbe") == "true"
        start()
    }

    override fun onStart() {
        val report = Bundle()
        try {
            if (standardSaveRootProbe) {
                if (standardSaveRootPlatform == "n3ds") {
                    ObservedCopyProviderProof.azahar(targetContext)
                    report.putString("result", "PASS exact synthetic ROM grant -> NCCH program ID -> live Azahar configured title save group; source worker revalidates current profile and excludes other titles/content; grant/version/path invalidation; exclusive fixtures removed; no save writes or cloud writes")
                } else report.putString("result", reviewStandardSaveRoot())
            } else if (automaticSaveDiagnosis) {
                report.putString("result", AutomaticSaveDiagnosis.observe(targetContext))
            } else if (romCompanionProbe) {
                exercise()
                report.putString("result", "PASS exact owned-ROM companion discovery, coherent multi-file capture, writer rejection, selective group restore, retained rollback, retry and binding/revocation isolation; exclusive fixtures removed; no emulator launch or cloud write")
            } else if (pcsxRestoreProbe) {
                exercise(psx = true)
                report.putString("result", "PASS exact PS1 private/shared restore, retained rollback, missing-card recovery, changed settings, wrong-card/generic publication rejection and lost-ack service recreation; isolated override/cards removed; real RetroArch CONTENTLESS")
            } else if (pcsxCaptureProbe) {
                exercise(psx = true)
                report.putString("result", "PASS exact owned PS1 private/shared card capture; full-card bytes/digests, missing baseline, writer rejection, configuration revision, stale role and cross-card journal rejection; existing shared card read-only; exclusive fixture cleanup")
            } else if (pcsxSettingsProbe) {
                exercise(psx = true)
                report.putString("result", "PASS exact owned CHD grant to live read-only PCSX card mapping; encoded per-game card and shared card roles, ownership/identity/publication/removal rejection; exclusive fixture cleanup; no emulator launch or save mutation")
            } else if (dsArchiveProbe) {
                exercise(ds = true, dsZip = true)
                report.putString("result", "PASS DS ZIP document validation, unchanged archive read and live save-location review; read-only grant and native identity/ownership/publication/removal rejection; exclusive fixture cleanup; no emulator launch")
            } else if (dsProviderProbe) {
                exercise(ds = true)
                report.putString("result", "PASS DS document leaf read/name/size and launch-bound live save-location review, read-only grant and native publication/identity/ownership/removal rejection; exclusive fixture cleanup; no emulator launch")
            } else if (ppssppCompanionProbe) {
                report.putString("result", PpssppCompanionProof.exercise(targetContext))
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
            } else if (retroArchSnapshotProbe) {
                report.putString("result", RetroArchSnapshotProof.exercise(targetContext))
            } else if (pcsxWatchProbe) {
                report.putString("result", SaveFileWatchProof.pcsx(targetContext))
            } else if (retroArchWatchProbe) {
                report.putString("result", SaveFileWatchProof.retroArch(targetContext))
            } else if (saveWatchProbe) {
                report.putString("result", SaveFileWatchProof.exercise(targetContext))
            } else if (melonSaveProbe) {
                report.putString("result", MelonSaveProof.exercise(targetContext, protectedMelonSaveProbe, melonLiveCaptureProbe))
            } else if (saveGroupProbe) {
                report.putString("result", MgbaGroupSaveProof.exercise(targetContext))
            } else if (snesSaveProbe) {
                report.putString("result", MgbaGroupSaveProof.exercise(targetContext, route = "snes"))
            } else if (sameBoySaveProbe != null) {
                check(sameBoySaveProbe in listOf("gb", "gbc"))
                report.putString("result", MgbaGroupSaveProof.exercise(targetContext, route = sameBoySaveProbe!!))
            } else if (nesSaveProbe) {
                report.putString("result", SegaSaveRouteProof.exercise(targetContext, nes = true))
            } else if (n64SaveProbe) {
                report.putString("result", SegaSaveRouteProof.exercise(targetContext, n64 = true))
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
            report.putString("frames", error.stackTrace.filter { it.className.startsWith("com.retro.rshop.") }
                .take(4).joinToString { "${it.methodName}:${it.lineNumber}" })
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

    private fun reviewStandardSaveRoot(): String {
        check(targetContext.packageName == "com.darkaxt.rshop.debug")
        val service = SaveCaptureService(targetContext)
        try {
            val done = CountDownLatch(1); var value: Any? = null; var failure: String? = null
            service.handle(MethodCall("standardSaveRoot", mapOf("platformId" to standardSaveRootPlatform)), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await(); check(failure == null) { failure ?: "No settings" }
            val config = SaveRootConfiguration.decode(JSONObject(value as Map<*, *>))
            check(SaveRootConfiguration.decode(config.json()) == config)
            val ps2 = standardSaveRootPlatform == "ps2"
            val gc = standardSaveRootPlatform == "gc"
            check(ps2 || gc || standardSaveRootPlatform == "dreamcast")
            check(config.profile == when { ps2 -> StandardSaveRoots.NETHER_PROFILE; gc -> StandardSaveRoots.DOLPHIN_PROFILE; else -> StandardSaveRoots.FLYCAST_PROFILE })
            check(config.logicalRomName == when { ps2 -> "shared-memory-cards.save"; gc -> "shared-gc-memory-cards.save"; else -> "shared-vmu-cards.save" })
            check(config.files == when { ps2 -> listOf("Mcd001.ps2", "Mcd002.ps2"); gc -> emptyList(); else -> listOf("vmu_save_A1.bin", "vmu_save_A2.bin") })
            SaveSourceStorage.openRomCompanions(targetContext, config.directory, config.logicalRomName!!,
                emptyList(), configuration = config).use { storage ->
                val names = storage.companionInventory().files.keys
                check(names.all(config::acceptsFile))
                if (ps2) check(names == config.files.toSet())
                if (gc) {
                    check(names.any { it.endsWith(".gci") })
                    check(!config.acceptsFile("SRAM.raw") && !config.acceptsFile("USA/IPL.bin"))
                }
            }
            return "PASS production settings channel resolves $standardSaveRootPlatform shared cards; source worker revalidates the profile and excludes unrelated files; read-only settings/metadata, no save capture, emulator launch or cloud write"
        } finally {
            val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await()
        }
    }

    private fun exercise(ds: Boolean = false, dsZip: Boolean = false, psx: Boolean = false) {
        check(targetContext.packageName == "com.darkaxt.rshop.debug")
        val id = "provider-proof-${UUID.randomUUID()}"
        val root = File(targetContext.getExternalFilesDir(null), id)
        check(root.mkdir())
        val rom = File(root, if (psx) "synthetic.chd" else if (dsZip) "synthetic.zip" else if (ds) "synthetic.nds" else "synthetic.rvz")
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
            val uri = if (ds || psx) OwnedRomContentProvider.gameGearUri(targetContext, id, rom.name)
                else OwnedRomContentProvider.uri(targetContext, id, rom.name)
            if (ds) OwnedRomContentProvider.openCommitted(targetContext, uri,
                requiredArchivePlatform = if (dsZip) "nds" else null,
                requiredStandaloneNds = !dsZip).use { }
            if (psx) {
                OwnedRomContentProvider.openCommitted(targetContext, uri, requiredStandaloneChd = true).use { }
                val service = OwnedStorageService(targetContext)
                val done = CountDownLatch(1)
                var mapping: Any? = null
                var failure: String? = null
                try {
                    service.handle(MethodCall("reviewOwnedRetroArchPcsxSaves", mapOf(
                        "installationId" to id, "filename" to rom.name)), object : MethodChannel.Result {
                        override fun success(value: Any?) { mapping = value; done.countDown() }
                        override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                        override fun notImplemented() { failure = "not_implemented"; done.countDown() }
                    })
                    done.await(); check(failure == null) { failure ?: "review_missing" }
                    val row = mapping as Map<*, *>
                    check(row.keys == setOf("directory", "cards"))
                    val cards = row["cards"] as List<*>
                    // This proof checks the actual installed libretro/shared
                    // configuration; it does not rewrite settings to fit it.
                    check(row["directory"] == "/storage/emulated/0/RetroArch/saves/PCSX-ReARMed")
                    check(cards == listOf(
                        mapOf("slot" to 1, "mode" to "libretro", "name" to "$id%2Fsynthetic.srm"),
                        mapOf("slot" to 2, "mode" to "shared", "name" to "pcsx-card2.mcd")))
                    if (pcsxCaptureProbe) PcsxCaptureProof.exercise(targetContext, id, rom.name, uri.encodedPath!!.substringAfterLast('/'))
                    if (pcsxRestoreProbe) PcsxRestoreProof.exercise(targetContext, id, rom.name, uri.encodedPath!!.substringAfterLast('/'))
                } finally { service.shutdown() }
            }
            if (romCompanionProbe) {
                val sidecars = listOf("synthetic.sav", "synthetic.png", "synthetic.cfg", "Other.sav", "synthetic.gba")
                    .map { File(root, it) }
                val newSidecar = File(root, "synthetic.cache")
                val service = SaveCaptureService(targetContext)
                val captures = mutableListOf<String>()
                val restoreIds = linkedMapOf<String, List<String>>()
                var companionWatch: SaveFileWatch? = null
                val nestedRoot = File(root, "synthetic")
                val nestedFolder = File(nestedRoot, "images")
                val nestedFile = File(nestedFolder, "shot.png")
                val isolatedSave = File(nestedRoot, "progress.sav")
                val isolatedRom = File(nestedRoot, rom.name)
                val mappedRoot = File(targetContext.filesDir.canonicalFile, "save-root-proof-$id")
                val mappedFolder = File(mappedRoot, "TITLE123")
                val mappedCard = File(mappedRoot, "card.bin")
                val mappedChild = File(mappedFolder, "progress.dat")
                val mappedOther = File(mappedRoot, "Other.sav")
                val mappedRuntime = File(mappedRoot, "fixture-core.so")
                val sharedOtherRom = File(root, "other-shared.rvz")
                val sharedOtherId = "$id-shared"
                fun invoke(method: String, args: Map<String, Any>, expected: String? = null): Any? {
                    val done = CountDownLatch(1)
                    var value: Any? = null; var failure: String? = null
                    service.handle(MethodCall(method, args), object : MethodChannel.Result {
                        override fun success(result: Any?) { value = result; done.countDown() }
                        override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                        override fun notImplemented() { failure = "not_implemented"; done.countDown() }
                    })
                    done.await(); check(failure == expected) { "$method: $failure, expected $expected" }
                    return value
                }
                fun snapshot(before: Map<*, *>? = null, expected: String? = null): Map<*, *>? {
                    val done = CountDownLatch(1)
                    var value: Any? = null; var failure: String? = null
                    service.handle(MethodCall("romCompanionSnapshot", mapOf("installationId" to id,
                        "filename" to rom.name) + if (before == null) emptyMap() else mapOf("before" to before)),
                        object : MethodChannel.Result {
                            override fun success(result: Any?) { value = result; done.countDown() }
                            override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                            override fun notImplemented() { failure = "not_implemented"; done.countDown() }
                        })
                    done.await(); check(failure == expected) { "companion snapshot: $failure" }
                    return value as? Map<*, *>
                }
                fun baseline(row: Map<*, *>) = row.filterKeys { it != "changed" }
                try {
                    val empty = snapshot()!!
                    val absentId = UUID.randomUUID().toString().replace("-", ""); captures.add(absentId)
                    val absent = invoke("captureRomCompanions", mapOf("captureId" to absentId,
                        "installationId" to id, "filename" to rom.name, "binding" to empty["binding"]!!,
                        "members" to emptyList<String>(), "emulatorPackage" to "com.retroarch.aarch64",
                        "restoreBaseline" to true)) as Map<*, *>
                    check(absent["localWasAbsent"] == true && (absent["files"] as List<*>).isEmpty())
                    sidecars.forEach { check(it.createNewFile()); it.writeBytes(byteArrayOf(1)) }
                    val before = snapshot()!!
                    check((before["files"] as Map<*, *>).keys == setOf("synthetic.png", "synthetic.sav"))
                    check((before["changed"] as List<*>).isEmpty())
                    val changedEvent = CountDownLatch(1)
                    companionWatch = SaveFileWatch(targetContext, changed = { key ->
                        check(key == "a".repeat(64)); changedEvent.countDown()
                    })
                    check(companionWatch.replace(listOf(SaveFileWatch.Mapping("a".repeat(64), root.path,
                        rom.name, "rom-companion"))) == listOf("a".repeat(64)))
                    sidecars.first().appendBytes(byteArrayOf(2))
                    changedEvent.await()
                    check(newSidecar.createNewFile())
                    val changed = snapshot(baseline(before))!!
                    check(changed["changed"] == listOf("synthetic.cache", "synthetic.sav"))
                    check(snapshot(baseline(changed))!!["changed"] == emptyList<String>())
                    val grant = mapOf<String, Any>("installationId" to id, "filename" to rom.name,
                        "binding" to changed["binding"]!!, "emulatorPackage" to "com.retroarch.aarch64")
                    fun capture(names: List<String>, baseline: Boolean = false, expected: String? = null): Pair<String, Map<*, *>?> {
                        val captureId = UUID.randomUUID().toString().replace("-", ""); captures.add(captureId)
                        return captureId to (invoke("captureRomCompanions", grant + mapOf("captureId" to captureId,
                            "members" to names, "restoreBaseline" to baseline), expected) as? Map<*, *>)
                    }
                    val all = listOf("synthetic.cache", "synthetic.png", "synthetic.sav")
                    val captured = capture(all)
                    val capturedFiles = captured.second!!["files"] as List<*>
                    check(capturedFiles.map { (it as Map<*, *>)["name"] } == all)
                    for (member in capturedFiles) {
                        val row = member as Map<*, *>
                        check(File(row["path"] as String).readBytes().contentEquals(File(root, row["name"] as String).readBytes()))
                    }
                    invoke("captureRomCompanions", grant + mapOf("captureId" to captured.first,
                        "members" to listOf("synthetic.png")), "invalid_capture")
                    java.io.FileOutputStream(sidecars.first(), true).use {
                        capture(all, expected = "source_changed")
                    }
                    val selected = listOf("synthetic.cache", "synthetic.png")
                    val rollback = capture(selected, baseline = true)
                    val restoreId = UUID.randomUUID().toString().replace("-", ""); restoreIds[restoreId] = selected
                    fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                    val desired = listOf(byteArrayOf(), byteArrayOf(7, 8, 9))
                    invoke("beginRestoreGroup", grant + mapOf("captureId" to restoreId, "name" to rom.name,
                        "members" to selected.indices.map { index -> mapOf("name" to selected[index],
                            "size" to desired[index].size, "sha256" to sha(desired[index])) }))
                    invoke("appendRestoreGroup", mapOf("captureId" to restoreId, "member" to 1,
                        "offset" to 0L, "bytes" to desired[1]))
                    invoke("sealRestoreGroup", mapOf("captureId" to restoreId))
                    java.io.FileOutputStream(sidecars[1], true).use {
                        invoke("publishRestoreGroup", mapOf("captureId" to restoreId,
                            "rollbackCaptureId" to rollback.first), "source_changed")
                    }
                    invoke("publishRestoreGroup", mapOf("captureId" to restoreId, "rollbackCaptureId" to rollback.first))
                    check(newSidecar.readBytes().isEmpty() && sidecars[1].readBytes().contentEquals(desired[1]))
                    check(sidecars.first().readBytes().contentEquals(byteArrayOf(1, 2)))
                    val retained = (rollback.second!!["files"] as List<*>).map { it as Map<*, *> }
                    check(File(retained.single { it["name"] == "synthetic.png" }["path"] as String).readBytes().contentEquals(byteArrayOf(1)))
                    invoke("publishRestoreGroup", mapOf("captureId" to restoreId, "rollbackCaptureId" to rollback.first))
                    val afterRestore = snapshot()!!
                    check(sidecars[1].delete())
                    check(snapshot(baseline(afterRestore))!!["changed"] == emptyList<String>()) { "removal became an upload" }
                    companionWatch.close(); companionWatch = null
                    check(nestedRoot.mkdir()); check(nestedFolder.mkdir())
                    check(nestedFile.createNewFile()); nestedFile.writeBytes(byteArrayOf(3))
                    check(isolatedSave.createNewFile()); isolatedSave.writeBytes(byteArrayOf(4))
                    check(isolatedRom.createNewFile()); isolatedRom.writeBytes(bytes)
                    check(OwnedRomContentProvider.companionInventory(nestedRoot.path, rom.name, {}).files.keys ==
                        setOf("images/shot.png", "progress.sav"))
                    val firstWatchEvent = CountDownLatch(1)
                    val deepWatchEvent = CountDownLatch(1)
                    val initial = java.util.concurrent.atomic.AtomicBoolean(true)
                    companionWatch = SaveFileWatch(targetContext, changed = { key ->
                        check(key == "a".repeat(64))
                        if (initial.getAndSet(false)) firstWatchEvent.countDown() else deepWatchEvent.countDown()
                    })
                    check(companionWatch.replace(listOf(SaveFileWatch.Mapping("a".repeat(64), root.path,
                        rom.name, "rom-companion"))) == listOf("a".repeat(64)))
                    firstWatchEvent.await()
                    nestedFile.appendBytes(byteArrayOf(5)); deepWatchEvent.await()
                    val nestedPath = "synthetic/images/shot.png"
                    val nestedSnapshot = snapshot()!!
                    check((nestedSnapshot["files"] as Map<*, *>).keys.contains(nestedPath))
                    java.io.FileOutputStream(nestedFile, true).use {
                        capture(listOf(nestedPath), expected = "source_changed")
                    }
                    companionWatch.close(); companionWatch = null
                    val nestedRollback = capture(listOf(nestedPath), baseline = true)
                    fun restoreNested(baselineId: String) {
                        val nextId = UUID.randomUUID().toString().replace("-", "")
                        restoreIds[nextId] = listOf(nestedPath)
                        invoke("beginRestoreGroup", grant + mapOf("captureId" to nextId, "name" to rom.name,
                            "members" to listOf(mapOf("name" to nestedPath, "size" to 3, "sha256" to sha(byteArrayOf(6, 7, 8))))))
                        invoke("appendRestoreGroup", mapOf("captureId" to nextId, "member" to 0,
                            "offset" to 0L, "bytes" to byteArrayOf(6, 7, 8)))
                        invoke("sealRestoreGroup", mapOf("captureId" to nextId))
                        invoke("publishRestoreGroup", mapOf("captureId" to nextId, "rollbackCaptureId" to baselineId))
                        check(nestedFile.readBytes().contentEquals(byteArrayOf(6, 7, 8)))
                    }
                    restoreNested(nestedRollback.first)
                    check(isolatedSave.readBytes().contentEquals(byteArrayOf(4)) && isolatedRom.readBytes().contentEquals(bytes))
                    check(nestedFile.delete()); check(isolatedSave.delete()); check(isolatedRom.delete())
                    check(nestedFolder.delete()); check(nestedRoot.delete())
                    val missing = capture(listOf(nestedPath), baseline = true)
                    check(missing.second!!["localWasAbsent"] == true)
                    restoreNested(missing.first)
                    // Same production pipeline, now outside the ROM directory
                    // and inside private app storage. Only exact fixture files
                    // are selected; no installed emulator/save settings change.
                    check(mappedRoot.mkdir()); check(mappedFolder.mkdir())
                    check(mappedCard.createNewFile()); mappedCard.writeBytes(byteArrayOf(10, 11))
                    check(mappedChild.createNewFile()); mappedChild.writeBytes(byteArrayOf(12))
                    check(mappedOther.createNewFile()); mappedOther.writeBytes(byteArrayOf(13))
                    check(mappedRuntime.createNewFile()); mappedRuntime.writeBytes(byteArrayOf(31, 32))
                    val configuration = SaveRootConfiguration(mappedRoot.path, targetContext.packageName,
                        "fixture", "state", "fixture-state-v1", listOf("card.bin"), listOf("TITLE123"), listOf("card.bin"),
                        listOf(mappedRuntime.path))
                    val configurationMap = mapOf<String, Any>("schema" to 1, "directory" to mappedRoot.path,
                        "emulator" to targetContext.packageName, "core" to "fixture", "kind" to "state",
                        "format" to "fixture-state-v1", "files" to listOf("card.bin"),
                        "folders" to listOf("TITLE123"), "required" to listOf("card.bin"),
                        "runtimeFiles" to listOf(mappedRuntime.path))
                    val configuredGrant = mapOf<String, Any>("installationId" to id, "filename" to rom.name,
                        "saveRoot" to configurationMap, "emulatorPackage" to targetContext.packageName)
                    val configuredSnapshot = invoke("romCompanionSnapshot", configuredGrant) as Map<*, *>
                    val configuredNames = listOf("TITLE123/progress.dat", "card.bin")
                    check(configuredSnapshot["directory"] == mappedRoot.path &&
                        (configuredSnapshot["files"] as Map<*, *>).keys == configuredNames.toSet())
                    val configuredBefore = configuredSnapshot.filterKeys { it != "changed" }
                    val configuredInitial = CountDownLatch(1); val configuredChanged = CountDownLatch(1)
                    val configuredFirst = java.util.concurrent.atomic.AtomicBoolean(true)
                    companionWatch = SaveFileWatch(targetContext, changed = {
                        check(it == "b".repeat(64))
                        if (configuredFirst.getAndSet(false)) configuredInitial.countDown() else configuredChanged.countDown()
                    })
                    check(companionWatch.replace(listOf(SaveFileWatch.Mapping("b".repeat(64), mappedRoot.path,
                        rom.name, "rom-companion", configuration))) == listOf("b".repeat(64)))
                    configuredInitial.await()
                    mappedChild.appendBytes(byteArrayOf(14)); configuredChanged.await()
                    companionWatch.close(); companionWatch = null
                    val configuredNext = invoke("romCompanionSnapshot", configuredGrant + mapOf("before" to configuredBefore)) as Map<*, *>
                    check(configuredNext["changed"] == listOf("TITLE123/progress.dat"))
                    val configuredBinding = configuredGrant + mapOf("binding" to configuredNext["binding"]!!)
                    val configuredCaptureId = UUID.randomUUID().toString().replace("-", ""); captures.add(configuredCaptureId)
                    val configuredCapture = invoke("captureRomCompanions", configuredBinding + mapOf(
                        "captureId" to configuredCaptureId, "members" to configuredNames)) as Map<*, *>
                    check((configuredCapture["files"] as List<*>).map { (it as Map<*, *>)["name"] } == configuredNames)
                    val runtimeFiles = org.json.JSONArray().put(org.json.JSONArray(listOf(mappedRuntime.path, sha(mappedRuntime.readBytes()))))
                    val expectedCore = "files-" + sha(runtimeFiles.toString().toByteArray(Charsets.UTF_8))
                    check(configuredCapture["coreVersion"] == expectedCore)
                    val expectedRuntime = mapOf("emulatorVersion" to configuredCapture["emulatorVersion"]!!,
                        "coreVersion" to expectedCore)
                    val configuredRestoreId = UUID.randomUUID().toString().replace("-", "")
                    restoreIds[configuredRestoreId] = configuredNames
                    val configuredBytes = listOf(byteArrayOf(21, 22), byteArrayOf(23, 24))
                    val configuredRestore = configuredBinding + mapOf("captureId" to configuredRestoreId,
                        "expectedRuntime" to expectedRuntime,
                        "name" to rom.name, "members" to configuredNames.indices.map { index ->
                            mapOf("name" to configuredNames[index], "size" to configuredBytes[index].size,
                                "sha256" to sha(configuredBytes[index])) })
                    mappedRuntime.writeBytes(byteArrayOf(41, 42))
                    invoke("beginRestoreGroup", configuredRestore, "incompatible_state")
                    mappedRuntime.writeBytes(byteArrayOf(31, 32))
                    invoke("beginRestoreGroup", configuredRestore)
                    for (index in configuredBytes.indices) invoke("appendRestoreGroup", mapOf(
                        "captureId" to configuredRestoreId, "member" to index, "offset" to 0L, "bytes" to configuredBytes[index]))
                    invoke("sealRestoreGroup", mapOf("captureId" to configuredRestoreId))
                    invoke("publishRestoreGroup", mapOf("captureId" to configuredRestoreId,
                        "rollbackCaptureId" to configuredCaptureId))
                    check(mappedChild.readBytes().contentEquals(configuredBytes[0]))
                    check(mappedCard.readBytes().contentEquals(configuredBytes[1]))
                    check(mappedOther.readBytes().contentEquals(byteArrayOf(13)))
                    // A physical shared card has the same native capture and
                    // restore identity when another independently owned ROM
                    // initiates the operation. Only disposable proof rows change.
                    check(sharedOtherRom.createNewFile()); sharedOtherRom.writeBytes(bytes)
                    val sharedRootFd = OwnedStorageNative.openRoot(root.path)
                    val sharedIdentity = try {
                        val fd = OwnedStorageNative.openFile(sharedRootFd, sharedOtherRom.name, false, false)
                        try { OwnedStorageNative.identity(fd) } finally { OwnedStorageNative.close(fd) }
                    } finally { OwnedStorageNative.close(sharedRootFd) }
                    val sharedStamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }.format(Date(sharedIdentity[3] * 1000)) + "." + (sharedIdentity[4] / 1000).toString().padStart(6, '0') + "Z"
                    val sharedNative = JSONObject().put("volumeId", sharedIdentity[0].toString())
                        .put("fileId", sharedIdentity[1].toString()).put("sizeBytes", sharedIdentity[2])
                        .put("modifiedAt", sharedStamp).put("modifiedNanoseconds", sharedIdentity[4])
                    for ((table, key) in listOf("transfer_records" to "transfer_id", "installed_artifacts" to "installation_id",
                        "transfer_target_owners" to "installation_id")) {
                        val values = db.query(table, null, "$key=?", arrayOf(id), null, null, null).use { cursor ->
                            check(cursor.moveToFirst()); ContentValues().also { android.database.DatabaseUtils.cursorRowToContentValues(cursor, it) }
                        }
                        values.put("transfer_id", sharedOtherId)
                        if (table != "transfer_records") values.put("installation_id", sharedOtherId)
                        else values.put("artifact_key", sharedOtherId)
                        values.put("relative_path", sharedOtherRom.name)
                        if (values.containsKey("record_json")) {
                            val record = JSONObject(values.getAsString("record_json")).put("id", sharedOtherId)
                                .put("relativePath", sharedOtherRom.name)
                            if (table == "installed_artifacts") record.put("transferId", sharedOtherId).put("fileIdentity", sharedNative)
                            else record.getJSONObject("publication").put("destinationIdentity", sharedNative)
                            values.put("record_json", record.toString())
                        }
                        db.insertOrThrow(table, null, values)
                    }
                    val sharedConfig = configuration.copy(kind = "save", format = "fixture-card-v1", resourceId = "card-1")
                    val sharedMap = configurationMap + mapOf("kind" to "save", "format" to "fixture-card-v1", "resourceId" to "card-1")
                    val sharedGrant = configuredGrant + mapOf("saveRoot" to sharedMap)
                    val otherGrant = sharedGrant + mapOf("installationId" to sharedOtherId, "filename" to sharedOtherRom.name)
                    val firstShared = invoke("romCompanionSnapshot", sharedGrant) as Map<*, *>
                    val otherShared = invoke("romCompanionSnapshot", otherGrant) as Map<*, *>
                    check(firstShared["binding"] == otherShared["binding"] && firstShared["romName"] == sharedConfig.logicalRomName)
                    val sharedCaptureId = UUID.randomUUID().toString().replace("-", ""); captures.add(sharedCaptureId)
                    fun sharedCapture(grant: Map<String, Any>) = invoke("captureRomCompanions", grant + mapOf(
                        "binding" to firstShared["binding"]!!, "captureId" to sharedCaptureId, "members" to configuredNames)) as Map<*, *>
                    check(sharedCapture(sharedGrant) == sharedCapture(otherGrant))
                    val sharedRestoreId = UUID.randomUUID().toString().replace("-", "")
                    restoreIds[sharedRestoreId] = configuredNames
                    fun sharedRestore(grant: Map<String, Any>) = grant + mapOf(
                        "binding" to firstShared["binding"]!!, "captureId" to sharedRestoreId,
                        "name" to sharedConfig.logicalRomName!!, "members" to configuredNames.indices.map { index ->
                            mapOf("name" to configuredNames[index], "size" to configuredBytes[index].size,
                                "sha256" to sha(configuredBytes[index])) })
                    invoke("beginRestoreGroup", sharedRestore(sharedGrant))
                    invoke("beginRestoreGroup", sharedRestore(otherGrant))
                    for (index in configuredBytes.indices) invoke("appendRestoreGroup", mapOf(
                        "captureId" to sharedRestoreId, "member" to index, "offset" to 0L, "bytes" to configuredBytes[index]))
                    invoke("sealRestoreGroup", mapOf("captureId" to sharedRestoreId))
                    invoke("publishRestoreGroup", mapOf("captureId" to sharedRestoreId, "rollbackCaptureId" to sharedCaptureId))
                    check(mappedChild.readBytes().contentEquals(configuredBytes[0]) && mappedCard.readBytes().contentEquals(configuredBytes[1]))
                    check(mappedOther.readBytes().contentEquals(byteArrayOf(13)))
                    snapshot(baseline(changed) + mapOf("binding" to "0".repeat(64)), "capture_unavailable")
                    db.delete("transfer_target_owners", "transfer_id=?", arrayOf(id))
                    snapshot(expected = "capture_unavailable")
                    db.insertOrThrow("transfer_target_owners", null, ContentValues().apply {
                        put("installation_id", id); put("transfer_id", id)
                        put("destination_root", root.path); put("relative_path", rom.name)
                    })
                } finally {
                    companionWatch?.close()
                    captures.forEach { captureId -> invoke("retireCapture", mapOf("captureId" to captureId)) }
                    val done = CountDownLatch(1); service.shutdown { done.countDown() }; done.await()
                    for ((table, key) in listOf("transfer_target_owners" to "installation_id",
                        "installed_artifacts" to "installation_id", "transfer_records" to "transfer_id"))
                        db.delete(table, "$key=?", arrayOf(sharedOtherId))
                    check(!sharedOtherRom.exists() || sharedOtherRom.delete())
                    for (fixture in listOf(mappedChild, mappedCard, mappedOther, mappedRuntime, mappedFolder, mappedRoot)) {
                        if (fixture.exists()) check(fixture.delete())
                    }
                    // Exact disposable fixture journals only; no user captures,
                    // rollback history or shared saves are included.
                    for ((restoreId, targets) in restoreIds) {
                        val privateRoot = File(targetContext.filesDir.canonicalFile, "save-restores")
                        val ids = listOf(restoreId) + targets.indices.map { index ->
                            MessageDigest.getInstance("SHA-256").digest("$restoreId/$index".toByteArray())
                                .joinToString("") { "%02x".format(it) }.take(32)
                        }
                        ids.forEach { child -> File(privateRoot, child).let { directory ->
                            check(directory.canonicalFile == directory.absoluteFile)
                            directory.listFiles().orEmpty().forEach { check(it.isFile && it.delete()) }
                            check(!directory.exists() || directory.delete())
                        } }
                        ids.drop(1).forEachIndexed { index, child -> File(File(root, targets[index]).parentFile!!, ".rshop-save-restore-$child").let { stage ->
                            check(!stage.exists() || stage.isFile && stage.delete())
                        } }
                    }
                    sidecars.forEach { check(!it.exists() || it.delete()) }
                    check(!newSidecar.exists() || newSidecar.delete())
                    for (file in listOf(nestedFile, isolatedSave, isolatedRom)) check(!file.exists() || file.delete())
                    check(!nestedFolder.exists() || nestedFolder.delete())
                    check(!nestedRoot.exists() || nestedRoot.delete())
                }
            }
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
