package com.retro.rshop

import android.content.Context
import android.content.ClipData
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Serialized, bounded IO off the platform thread. Each session owns its FDs;
 * shutdown stops new work and closes them after the in-flight operation drains. */
internal class OwnedStorageService(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<String, Session>()
    @Volatile private var closed = false

    private class Failure(val code: String) : Exception()
    private data class Target(val root: String, val parent: String, val name: String)
    private data class StageChoice(val base: File, val volume: Long, val mount: Long)
    private data class Session(
        val target: Target, val stageRoot: String, val stageName: String,
        val targetRootFd: Int, val targetParentFd: Int, val stageDirFd: Int,
        val fileFd: Int, val anchor: LongArray, var nextOffset: Long,
        val publication: OwnedPublication,
        val privateReadOnly: Boolean = false,
    ) {
        val published: Boolean get() = publication.renamed
        var copy: PublicationCopy? = null
    }
    private data class PublicationCopy(val fd: Int, val source: LongArray,
        var observed: LongArray, var offset: Long, val requiredPrefix: Long,
        var validatedPrefix: Long = 0, var finished: Boolean = false)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("closed", "Owned storage: closed", null); return }
        try {
            worker.execute {
                try {
                    if (closed) throw Failure("closed")
                    if (call.method == "launchOwnedDolphin" || call.method == "launchOwnedRetroArchGameGear" ||
                        call.method == "launchOwnedRetroArchMegaDrive" || call.method == "launchOwnedRetroArchMasterSystem" ||
                        call.method == "launchOwnedRetroArchSG1000" ||
                        call.method == "launchOwnedRetroArchN64" || call.method == "launchOwnedRetroArchPSX" ||
                        call.method == "launchOwnedRetroArchGameBoy" ||
                        call.method == "launchOwnedRetroArchNes" ||
                        call.method == "launchOwnedRetroArchSnes" ||
                        call.method == "launchOwnedRetroArchGameBoyColor" || call.method == "launchOwnedRetroArchGameBoyAdvance" ||
                        call.method == "launchOwnedPPSSPP" || call.method == "launchOwnedNetherSX2" ||
                        call.method == "launchOwnedCemu") {
                        val gameGear = call.method == "launchOwnedRetroArchGameGear"
                        val segaPlatform = when (call.method) {
                            "launchOwnedRetroArchMegaDrive" -> "megadrive"
                            "launchOwnedRetroArchMasterSystem" -> "mastersystem"
                            "launchOwnedRetroArchSG1000" -> "sg1000"
                            else -> null
                        }
                        val gameBoy = call.method == "launchOwnedRetroArchGameBoy"
                        val gameBoyColor = call.method == "launchOwnedRetroArchGameBoyColor"
                        val gameBoyAdvance = call.method == "launchOwnedRetroArchGameBoyAdvance"
                        val nes = call.method == "launchOwnedRetroArchNes"
                        val snes = call.method == "launchOwnedRetroArchSnes"
                        val handheld = gameBoy || gameBoyColor || gameBoyAdvance
                        val handheldPlatform = if (gameBoyAdvance) "gba" else if (gameBoyColor) "gbc" else "gb"
                        val n64 = call.method == "launchOwnedRetroArchN64"
                        val psx = call.method == "launchOwnedRetroArchPSX"
                        val psp = call.method == "launchOwnedPPSSPP"
                        val ps2 = call.method == "launchOwnedNetherSX2"
                        val wiiu = call.method == "launchOwnedCemu"
                        val retroArch = gameGear || segaPlatform != null || n64 || handheld || nes || snes || psx
                        val filename = string(call, "filename").lowercase(java.util.Locale.ROOT)
                        if (((gameGear || segaPlatform != null) && !filename.endsWith(".zip")) ||
                            ((handheld || nes || snes) && !filename.endsWith(".7z")) ||
                            (n64 && !filename.endsWith(".zip") && !filename.endsWith(".7z")) ||
                            ((psx || psp || ps2) && !filename.endsWith(".chd")) ||
                            (wiiu && !filename.endsWith(".wua"))) throw Failure("unsupported_archive")
                        val observed = call.argument<Number>("observationId")
                        if (observed != null && ((observed !is Long && observed !is Int) || observed.toLong() <= 0)) {
                            throw Failure("invalid_arguments")
                        }
                        val platform = segaPlatform ?: if (gameGear) "gamegear" else if (n64) "n64" else if (nes) "nes" else if (snes) "snes"
                            else if (handheld) handheldPlatform else if (psx) "psx" else if (psp) "psp"
                            else if (ps2) "ps2" else if (wiiu) "wiiu" else if (observed != null) string(call, "platformId") else ""
                        if (observed != null && (call.hasArgument("installationId") ||
                            string(call, "platformId") != platform || (platform != "gc" && platform != "wii" && !retroArch && !psp && !ps2 && !wiiu))) {
                            throw Failure("invalid_arguments")
                        }
                        val uri = if (observed != null) OwnedRomContentProvider.localCopyUri(context,
                            observed.toLong(), platform, string(call, "filename"), retroArch || psp || ps2 || wiiu)
                        else if (retroArch || psp || ps2 || wiiu) OwnedRomContentProvider.gameGearUri(context,
                            string(call, "installationId"), string(call, "filename"))
                        else OwnedRomContentProvider.uri(context,
                            string(call, "installationId"), string(call, "filename"))
                        OwnedRomContentProvider.openCommitted(context, uri,
                            requiredArchivePlatform = segaPlatform ?: if (gameGear) "gamegear" else if (n64) "n64" else if (nes) "nes" else if (snes) "snes" else if (handheld) handheldPlatform else null,
                            requiredStandaloneChd = psx || psp || ps2,
                            requiredStandaloneWua = wiiu).use { }
                        main.post {
                            if (closed) {
                                result.error("closed", "Emulator handoff closed", null)
                            } else try {
                                val app = if (retroArch) "com.retroarch.aarch64" else if (psp) "org.ppsspp.ppsspp"
                                    else if (ps2) "xyz.aethersx2.android"
                                    else if (wiiu) "info.cemu.cemu"
                                    else "org.dolphinemu.dolphinemu"
                                val intent = context.packageManager.getLaunchIntentForPackage(app)
                                    ?: throw Failure("emulator_missing")
                                if (retroArch) {
                                    intent.setClassName(app, "com.retroarch.browser.retroactivity.RetroActivityFuture")
                                    val data = context.packageManager.getApplicationInfo(app, 0).dataDir
                                    intent.putExtra("ROM", uri.toString())
                                    val core = if (gameGear || segaPlatform != null) "genesis_plus_gx" else if (n64) "mupen64plus_next_gles3" else if (nes) "fceumm" else if (snes) "snes9x" else if (gameBoyAdvance) "mgba" else if (handheld) "sameboy" else "pcsx_rearmed"
                                    intent.putExtra("LIBRETRO", "$data/cores/${core}_libretro_android.so")
                                }
                                if (psp) {
                                    intent.setClassName(app, "org.ppsspp.ppsspp.PpssppActivity")
                                    intent.action = Intent.ACTION_VIEW
                                    intent.setDataAndType(uri, "application/octet-stream")
                                }
                                if (ps2) {
                                    intent.setClassName(app, "xyz.aethersx2.android.EmulationActivity")
                                    intent.putExtra("bootPath", uri.toString())
                                }
                                if (wiiu) {
                                    intent.setClassName(app, "info.cemu.cemu.emulation.EmulationActivity")
                                    intent.action = Intent.ACTION_VIEW
                                    intent.setDataAndType(uri, "application/octet-stream")
                                }
                                intent.data = uri
                                intent.clipData = ClipData.newRawUri("Owned ROM", uri)
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                                if (!retroArch && !psp && !ps2 && !wiiu) {
                                    // Dolphin finishes MainActivity before its non-exported
                                    // EmulationActivity reads the ROM. An intent-owned grant
                                    // dies with that launcher; retain an exact package read
                                    // grant instead. No prefix, tree, write or persistable
                                    // permission. The provider rechecks durable ownership
                                    // and the pinned object on every subsequent open.
                                    context.grantUriPermission(app, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(intent)
                                // Activity acceptance is not a claim that the ROM booted.
                                result.success(null)
                            } catch (_: Failure) {
                                result.error("emulator_missing", "Required emulator is not installed", null)
                            } catch (_: Exception) {
                                result.error("launch_denied", "Emulator launch was rejected", null)
                            }
                        }
                        return@execute
                    }
                    val value = execute(call)
                    main.post { result.success(value) }
                } catch (error: Exception) {
                    val code = errorCode(error)
                    main.post { result.error(code, "Owned storage: $code", null) }
                } catch (_: LinkageError) {
                    main.post { result.error("unsupported", "Owned storage: unsupported", null) }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("closed", "Owned storage: closed", null)
        }
    }

    fun shutdown() {
        if (closed) return
        closed = true
        worker.execute {
            sessions.values.forEach(::closeSession)
            sessions.clear()
        }
        worker.shutdown()
    }

    private fun execute(call: MethodCall): Any? = when (call.method) {
        "ownedPrepare" -> prepare(string(call, "destinationRoot"))
        "ownedOpen" -> open(call)
        "ownedInspect" -> inspect(call)
        "localCopyInspect" -> inspectExisting(call)
        "ownedReadArchiveIdentifier" -> readArchiveIdentifier(call)
        "ownedRetireStage" -> { retireStage(call); null }
        "ownedQuarantine" -> quarantine(call, false)
        "ownedRetireQuarantine" -> { quarantine(call, true); null }
        "ownedRestoreQuarantine" -> { quarantine(call, false, restore = true); null }
        "ownedCopyOpen" -> openCopy(call)
        "ownedCopyChunk" -> copyChunk(call)
        "ownedCopyValidatePrefix" -> {
            val session = session(call)
            val copy = checkedCopy(session)
            val length = number(call, "length")
            if (length !in 1..65536 || number(call, "offset") != copy.validatedPrefix ||
                length > copy.requiredPrefix - copy.validatedPrefix) throw Failure("invalid_arguments")
            val original = OwnedStorageNative.read(session.fileFd, copy.validatedPrefix, length.toInt())
            val destination = OwnedStorageNative.read(copy.fd, copy.validatedPrefix, length.toInt())
            if (original.size.toLong() != length || !original.contentEquals(destination)) throw Failure("changed")
            checkedCopy(session)
            copy.validatedPrefix += length
            copy.validatedPrefix
        }
        "ownedCopyCheckpoint" -> {
            val session = session(call)
            val copy = checkedCopy(session)
            syncCopy(session, copy)
            identityMap(copy.observed)
        }
        "ownedCopyRead" -> {
            val copy = checkedCopy(session(call))
            val offset = number(call, "offset")
            val length = number(call, "length")
            if (offset < 0 || length !in 0..65536 || offset > copy.offset || length > copy.offset - offset) {
                throw Failure("invalid_arguments")
            }
            OwnedStorageNative.read(copy.fd, offset, length.toInt())
        }
        "ownedCopyFinish" -> {
            val session = session(call)
            val copy = checkedCopy(session)
            if (copy.validatedPrefix != copy.requiredPrefix || copy.offset != copy.source[2] ||
                !copy.observed.contentEquals(expectedIdentity(call))) {
                throw Failure("changed")
            }
            syncCopy(session, copy)
            copy.finished = true
            identityMap(copy.observed)
        }
        "ownedWrite" -> {
            val session = session(call)
            val offset = number(call, "offset")
            val bytes = call.argument<ByteArray>("bytes") ?: throw Failure("invalid_arguments")
            if (session.published || session.privateReadOnly || session.copy != null || offset != session.nextOffset || bytes.size > 65536) {
                throw Failure("invalid_arguments")
            }
            OwnedStorageNative.write(session.fileFd, offset, bytes)
            session.nextOffset += bytes.size
            null
        }
        "ownedRead" -> {
            val session = session(call)
            val length = number(call, "length")
            if (length !in 0..65536) throw Failure("invalid_arguments")
            OwnedStorageNative.read(session.fileFd, number(call, "offset"), length.toInt())
        }
        "ownedCheckpoint" -> {
            val session = session(call)
            validateLocation(session)
            syncCheckpoint(session)
            identityMap(OwnedStorageNative.identity(session.fileFd))
        }
        "ownedValidateGameGearZip", "ownedValidateSegaZip", "ownedValidateN64Zip", "ownedValidateN64SevenZip", "ownedValidateGameBoySevenZip",
        "ownedValidateGameBoyColorSevenZip", "ownedValidateGameBoyAdvanceSevenZip", "ownedValidateNesSevenZip", "ownedValidateSnesSevenZip" -> {
            val session = session(call)
            validateLocation(session)
            val before = OwnedStorageNative.identity(session.fileFd)
            try {
                val path = "/proc/self/fd/${session.fileFd}"
                when (call.method) {
                    "ownedValidateGameGearZip" -> OwnedGameGearZip.validate(path)
                    "ownedValidateSegaZip" -> {
                        val platform = string(call, "platformId")
                        if (platform !in setOf("megadrive", "mastersystem", "sg1000")) throw Failure("unsupported_archive")
                        OwnedGameGearZip.validate(path, platform)
                    }
                    "ownedValidateN64Zip" -> OwnedGameGearZip.validateN64(path)
                    "ownedValidateGameBoySevenZip" -> OwnedN64SevenZip.validate(path, "gb")
                    "ownedValidateGameBoyColorSevenZip" -> OwnedN64SevenZip.validate(path, "gbc")
                    "ownedValidateGameBoyAdvanceSevenZip" -> OwnedN64SevenZip.validate(path, "gba")
                    "ownedValidateNesSevenZip" -> OwnedN64SevenZip.validate(path, "nes")
                    "ownedValidateSnesSevenZip" -> OwnedN64SevenZip.validate(path, "snes")
                    else -> OwnedN64SevenZip.validate(path)
                }
            }
            catch (_: IOException) { throw Failure("unsupported_archive") }
            validateLocation(session)
            if (!before.contentEquals(OwnedStorageNative.identity(session.fileFd))) throw Failure("changed")
            null
        }
        "ownedPublish" -> publish(call)
        "ownedClose" -> {
            sessions.remove(string(call, "session"))?.let(::closeSession)
            null
        }
        else -> throw Failure("invalid_arguments")
    }

    private fun appDirectories(): List<File> =
        (context.getExternalFilesDirs(null).filterNotNull().toList() + context.filesDir)
            .filter { it.isDirectory }.map { it.canonicalFile }.distinctBy { it.path }

    private fun prepare(destination: String): Map<String, Any> {
        if (!File(destination).isAbsolute) throw Failure("invalid_arguments")
        // Resolve the user's initial selection once; the returned explicit root
        // is what the journal must persist. Later operations reject redirection.
        val root = File(destination).canonicalPath
        val targetFd = OwnedStorageNative.openRoot(root)
        try {
            val destinationVolume = OwnedStorageNative.identity(targetFd)[0]
            val destinationMount = OwnedStorageNative.mountId(targetFd)
            val choices = appDirectories().mapNotNull { base ->
                var fd = -1
                try {
                    fd = OwnedStorageNative.openRoot(base.path)
                    StageChoice(base, OwnedStorageNative.identity(fd)[0], OwnedStorageNative.mountId(fd))
                } catch (_: IOException) { null }
                finally { closeFd(fd) }
            }.sortedBy {
                // Android bind mounts can have identical st_dev but still reject
                // a rename with EXDEV. Prefer the actual mounted namespace.
                when { it.mount == destinationMount -> 0; it.volume == destinationVolume -> 1; else -> 2 }
            }
            for ((base, volume, mount) in choices) {
                var baseFd = -1
                var stageFd = -1
                try {
                    baseFd = OwnedStorageNative.openRoot(base.path)
                    stageFd = OwnedStorageNative.openDirectory(baseFd, "rshop-transfers", true)
                    OwnedStorageNative.sync(stageFd)
                    val stageRoot = File(base, "rshop-transfers").path
                    return mapOf("destinationRoot" to root, "stageRoot" to stageRoot,
                        "destinationVolume" to destinationVolume.toString(), "stageVolume" to volume.toString(),
                        "destinationMount" to destinationMount.toString(), "stageMount" to mount.toString(),
                        "destinationFreeBytes" to StatFs(root).availableBytes,
                        "stageFreeBytes" to StatFs(stageRoot).availableBytes)
                } catch (_: IOException) {
                    // A different app-owned volume may supply staging. This is
                    // not a claim that cross-volume publication is implemented.
                } finally { closeFd(stageFd); closeFd(baseFd) }
            }
            throw Failure("unsupported")
        } finally { closeFd(targetFd) }
    }

    private fun target(call: MethodCall): Target {
        val root = string(call, "destinationRoot")
        val relative = string(call, "relativePath")
        if (!File(root).isAbsolute || File(root).canonicalPath != root ||
            relative.contains('\\') || relative.contains('\u0000') ||
            relative.split('/').any { it.isEmpty() || it == "." || it == ".." }) {
            throw Failure("invalid_arguments")
        }
        return Target(root, relative.substringBeforeLast('/', ""), relative.substringAfterLast('/'))
    }

    private fun stage(call: MethodCall): Pair<String, String> {
        val path = string(call, "stagePath")
        val name = path.substringAfterLast('/')
        val root = path.substringBeforeLast('/', "")
        if (!Regex("[A-Za-z0-9_-]{1,96}\\.partial").matches(name) ||
            appDirectories().none { File(it, "rshop-transfers").path == root }) {
            throw Failure("invalid_arguments")
        }
        return root to name
    }

    private fun open(call: MethodCall): Map<String, Any> {
        val target = target(call)
        val (stageRoot, stageName) = stage(call)
        if (sessions.values.any { it.target == target ||
                    (it.stageRoot == stageRoot && it.stageName == stageName) }) throw Failure("collision")
        val mode = string(call, "mode")
        if (mode !in listOf("create", "resume", "published", "quarantine")) throw Failure("invalid_arguments")
        val offset = number(call, "durableOffset")
        if (offset < 0 || (mode == "create" && offset != 0L)) throw Failure("invalid_arguments")
        val expected = if (mode != "create") expectedIdentity(call) else null
        val fds = mutableListOf<Int>()
        fun own(fd: Int): Int { fds.add(fd); return fd }
        try {
            val rootFd = own(OwnedStorageNative.openRoot(target.root))
            val parentFd = own(OwnedStorageNative.openDirectory(rootFd, target.parent, mode == "create" || mode == "resume"))
            // Published mode is journal recovery, not a filename-only installed
            // lookup. Retain both parent handles to finish interrupted syncing.
            val stageFd = own(OwnedStorageNative.openRoot(stageRoot))
            val fileFd = own(OwnedStorageNative.openFile(
                if (mode == "published") parentFd else stageFd,
                if (mode == "published") target.name else stageName, mode == "create", mode == "create" || mode == "resume"))
            val identity = OwnedStorageNative.identity(fileFd)
            if (expected != null && (!sameObject(identity, expected) || identity[2] < offset)) {
                throw Failure("changed")
            }
            if (mode == "published" || mode == "quarantine") {
                if (!identity.contentEquals(expected!!) || offset != identity[2]) throw Failure("changed")
            } else {
                if (mode == "resume" && identity[2] != offset) OwnedStorageNative.truncate(fileFd, offset)
                OwnedStorageNative.sync(fileFd)
                OwnedStorageNative.sync(stageFd)
            }
            val session = Session(target, stageRoot, stageName, rootFd, parentFd, stageFd,
                fileFd, OwnedStorageNative.identity(fileFd), offset, OwnedPublication(mode == "published"), mode == "quarantine")
            validateLocation(session)
            if (session.published || session.privateReadOnly) syncCheckpoint(session)
            val id = UUID.randomUUID().toString()
            sessions[id] = session
            fds.clear()
            return mapOf("session" to id, "identity" to identityMap(session.anchor))
        } finally { fds.asReversed().forEach(::closeFd) }
    }

    private fun inspect(call: MethodCall): Map<String, Any>? {
        val target = target(call)
        val (stageRoot, stageName) = stage(call)
        val published = call.argument<Boolean>("published") == true
        var rootFd = -1
        var dirFd = -1
        try {
            rootFd = OwnedStorageNative.openRoot(if (published) target.root else stageRoot)
            dirFd = if (published) OwnedStorageNative.openDirectory(rootFd, target.parent, false)
                    else OwnedStorageNative.openDirectory(rootFd, "", false)
            return identityMap(OwnedStorageNative.entryIdentity(dirFd, if (published) target.name else stageName))
        } catch (error: IOException) {
            if (errno(error) == 2) return null
            throw error
        } finally { closeFd(dirFd); closeFd(rootFd) }
    }

    /** Existing-file identity only: no stage selection, publication or ownership. */
    private fun inspectExisting(call: MethodCall): Map<String, Any>? {
        val target = target(call)
        var root = -1; var parent = -1; var file = -1
        var checkedRoot = -1; var checkedParent = -1
        try {
            root = OwnedStorageNative.openRoot(target.root)
            parent = OwnedStorageNative.openDirectory(root, target.parent, false)
            file = OwnedStorageNative.openFile(parent, target.name, false, false)
            val before = OwnedStorageNative.identity(file)
            checkedRoot = OwnedStorageNative.openRoot(target.root)
            checkedParent = OwnedStorageNative.openDirectory(checkedRoot, target.parent, false)
            if (!sameObject(OwnedStorageNative.identity(root), OwnedStorageNative.identity(checkedRoot)) ||
                !sameObject(OwnedStorageNative.identity(parent), OwnedStorageNative.identity(checkedParent)) ||
                !before.contentEquals(OwnedStorageNative.identity(file)) ||
                !before.contentEquals(OwnedStorageNative.entryIdentity(checkedParent, target.name)))
                throw Failure("changed")
            return identityMap(before)
        } catch (error: IOException) {
            if (errno(error) == 2) return null
            throw error
        } finally {
            for (fd in listOf(file, checkedParent, checkedRoot, parent, root)) closeFd(fd)
        }
    }

    /** Metadata reads neither create a stage nor claim ownership of the ROM. */
    private fun readArchiveIdentifier(call: MethodCall): Map<String, Any> {
        val target = target(call)
        if (target.parent.isNotEmpty()) throw Failure("invalid_arguments")
        val platform = string(call, "platformId")
        val name = target.name.lowercase(java.util.Locale.ROOT)
        if (!(platform in setOf("gamegear", "megadrive", "mastersystem", "sg1000") && name.endsWith(".zip") ||
                platform == "n64" && (name.endsWith(".zip") || name.endsWith(".7z")) ||
                platform in setOf("gb", "gbc", "gba", "nes", "snes") && name.endsWith(".7z")))
            throw Failure("unsupported_archive")
        var root = -1; var file = -1
        try {
            root = OwnedStorageNative.openRoot(target.root)
            val rootIdentity = OwnedStorageNative.identity(root)
            file = OwnedStorageNative.openFile(root, target.name, false, false)
            val before = OwnedStorageNative.identity(file)
            val path = "/proc/self/fd/$file"
            val container = OwnedArchiveIdentity.container(path)
            val raw = when {
                platform == "gamegear" -> OwnedGameGearZip.validate(path)
                platform in setOf("megadrive", "mastersystem", "sg1000") -> OwnedGameGearZip.validate(path, platform)
                name.endsWith(".zip") -> OwnedGameGearZip.validateN64(path)
                else -> OwnedN64SevenZip.validate(path, platform)
            }
            if (container != OwnedArchiveIdentity.container(path) ||
                !before.contentEquals(OwnedStorageNative.identity(file)) ||
                !before.contentEquals(OwnedStorageNative.entryIdentity(root, target.name)))
                throw Failure("changed")
            val currentRoot = OwnedStorageNative.openRoot(target.root)
            try {
                if (!sameObject(rootIdentity, OwnedStorageNative.identity(currentRoot)))
                    throw Failure("changed")
            } finally { closeFd(currentRoot) }
            // The descriptor and named entry were checked after both complete
            // container reads. Persistable equivalence evidence is separate
            // from installation ownership and carries the exact observed inode.
            return mapOf("raw" to raw, "container" to container,
                "localIdentity" to identityMap(before))
        } catch (error: IOException) {
            if (error.message == "unsupported_archive") throw Failure("unsupported_archive")
            if (error.message == "changed") throw Failure("changed")
            throw error
        } finally { closeFd(file); closeFd(root) }
    }

    /** Post-commit cleanup only. The public file is opened read-only and never
     * passed to an unlink primitive. Only the validated app-private stage path
     * can reach retirePrivateFile, after all matching sessions have drained. */
    private fun retireStage(call: MethodCall) {
        val target = target(call)
        val (stageRoot, stageName) = stage(call)
        val expected = expectedIdentity(call)
        val installed = call.argument<Map<String, Any>>("installedIdentity")
            ?.let(::decodeIdentity) ?: throw Failure("invalid_arguments")
        // A copied stage and its installed destination must be distinct objects.
        if (sameObject(expected, installed)) throw Failure("changed")
        fun requireInactive() {
            if (sessions.values.any { session ->
                    session.target == target ||
                    (session.stageRoot == stageRoot && session.stageName == stageName) ||
                    sameObject(session.anchor, expected) ||
                    sameObject(session.anchor, installed) ||
                    session.copy?.let { sameObject(it.observed, installed) } == true
                }) throw Failure("collision")
        }
        requireInactive()
        val fds = mutableListOf<Int>()
        fun own(fd: Int): Int { fds.add(fd); return fd }
        try {
            val rootFd = own(OwnedStorageNative.openRoot(target.root))
            val parentFd = own(OwnedStorageNative.openDirectory(rootFd, target.parent, false))
            val stageFd = own(OwnedStorageNative.openRoot(stageRoot))
            val publicFd = own(OwnedStorageNative.openFile(parentFd, target.name, false, false))
            if (!OwnedStorageNative.identity(publicFd).contentEquals(installed)) throw Failure("changed")

            // Reopen the named roots/parents and compare against the pinned
            // descriptors, so redirection cannot authorize cleanup elsewhere.
            val currentRoot = own(OwnedStorageNative.openRoot(target.root))
            val currentParent = own(OwnedStorageNative.openDirectory(currentRoot, target.parent, false))
            val currentStage = own(OwnedStorageNative.openRoot(stageRoot))
            if (!sameObject(OwnedStorageNative.identity(currentRoot), OwnedStorageNative.identity(rootFd)) ||
                !sameObject(OwnedStorageNative.identity(currentParent), OwnedStorageNative.identity(parentFd)) ||
                !sameObject(OwnedStorageNative.identity(currentStage), OwnedStorageNative.identity(stageFd)) ||
                !OwnedStorageNative.entryIdentity(currentParent, target.name).contentEquals(installed) ||
                !OwnedStorageNative.identity(publicFd).contentEquals(installed)) throw Failure("changed")
            requireInactive()
            // The primitive verifies the exact single-link regular stage and
            // syncs stageFd on success or absent-entry replay. No guessed path
            // or recursive directory cleanup is available at this boundary.
            OwnedStorageNative.retirePrivateFile(stageFd, stageName, expected)
        } finally { fds.asReversed().forEach(::closeFd) }
    }

    /** Requires a durable removal intent before invocation. The destination is
     * restricted to app-private staging; normal rename is never exposed for a
     * public destination. An exact existing quarantine is a replay, not adoption.
     * Retire is separately authorized only after verification/deletion intent. */
    private fun quarantine(call: MethodCall, retire: Boolean, restore: Boolean = false): Map<String, Any>? {
        val target = target(call)
        val (stageRoot, stageName) = stage(call)
        val expected = expectedIdentity(call)
        if (sessions.values.any { session ->
                session.target == target ||
                (session.stageRoot == stageRoot && session.stageName == stageName) ||
                sameObject(session.anchor, expected) ||
                session.copy?.let { sameObject(it.observed, expected) } == true
            }) throw Failure("collision")
        val fds = mutableListOf<Int>()
        fun own(fd: Int): Int { fds.add(fd); return fd }
        try {
            val rootFd = own(OwnedStorageNative.openRoot(target.root))
            val parentFd = own(OwnedStorageNative.openDirectory(rootFd, target.parent, false))
            val stageFd = own(OwnedStorageNative.openRoot(stageRoot))
            val currentRoot = own(OwnedStorageNative.openRoot(target.root))
            val currentParent = own(OwnedStorageNative.openDirectory(currentRoot, target.parent, false))
            val currentStage = own(OwnedStorageNative.openRoot(stageRoot))
            if (!sameObject(OwnedStorageNative.identity(rootFd), OwnedStorageNative.identity(currentRoot)) ||
                !sameObject(OwnedStorageNative.identity(parentFd), OwnedStorageNative.identity(currentParent)) ||
                !sameObject(OwnedStorageNative.identity(stageFd), OwnedStorageNative.identity(currentStage))) {
                throw Failure("changed")
            }
            if (retire) {
                OwnedStorageNative.retirePrivateFile(stageFd, stageName, expected)
                return null
            }
            if (restore) {
                if (!OwnedStorageNative.entryIdentity(stageFd, stageName).contentEquals(expected)) throw Failure("changed")
                // Public restoration MUST be kernel no-clobber. Unsupported SD
                // filesystems keep the conflict privately; never overwrite.
                OwnedStorageNative.renameNoReplace(stageFd, stageName, parentFd, target.name)
                OwnedStorageNative.sync(parentFd)
                OwnedStorageNative.sync(stageFd)
                return null
            }
            val existing = try { OwnedStorageNative.entryIdentity(stageFd, stageName) }
                catch (error: IOException) { if (errno(error) != 2) throw error; null }
            val moved = if (existing == null) {
                OwnedStorageNative.quarantineIntoPrivate(parentFd, target.name, stageFd, stageName, expected)
            } else {
                if (!existing.contentEquals(expected)) throw Failure("changed")
                existing
            }
            // Complete interrupted durability before returning the receipt.
            OwnedStorageNative.sync(parentFd)
            OwnedStorageNative.sync(stageFd)
            return identityMap(moved)
        } finally { fds.asReversed().forEach(::closeFd) }
    }

    private fun publish(call: MethodCall): Map<String, Any> {
        val session = session(call)
        if (session.copy != null || session.privateReadOnly) throw Failure("invalid_arguments")
        validateLocation(session)
        val expected = expectedIdentity(call)
        val current = OwnedStorageNative.identity(session.fileFd)
        if (!current.contentEquals(expected) || current[2] != session.nextOffset) throw Failure("changed")
        OwnedStorageNative.sync(session.fileFd)
        // A retry after rename + failed fsync finishes the durability step; it
        // must neither repeat the namespace mutation nor claim it is complete.
        session.publication.publish({
            OwnedStorageNative.renameNoReplace(session.stageDirFd, session.stageName,
                session.targetParentFd, session.target.name)
        }, { syncParents(session) })
        validateLocation(session)
        val published = OwnedStorageNative.identity(session.fileFd)
        if (!published.contentEquals(expected)) throw Failure("changed")
        return identityMap(published)
    }

    private fun syncParents(session: Session) {
        OwnedStorageNative.sync(session.targetParentFd)
        OwnedStorageNative.sync(session.stageDirFd)
    }

    private fun syncCheckpoint(session: Session) = session.publication.checkpoint(
        { OwnedStorageNative.sync(session.fileFd) }, { syncParents(session) })

    /** Explicit journaled alternative, never an automatic fallback inside rename.
     * Only copies the retained, verified private source; no network bytes accepted.
     * The caller journals intent before open and identity before the first chunk. */
    private fun openCopy(call: MethodCall): Map<String, Any> {
        val session = session(call)
        if (session.published || session.privateReadOnly || session.copy != null) throw Failure("invalid_arguments")
        validateLocation(session)
        val source = OwnedStorageNative.identity(session.fileFd)
        if (!source.contentEquals(expectedIdentity(call)) || source[2] != session.nextOffset) {
            throw Failure("changed")
        }
        val saved = call.argument<Map<String, Any>>("destinationIdentity")?.let(::decodeIdentity)
        val offset = number(call, "durableOffset")
        if (offset < 0 || offset > source[2] || (saved == null && offset != 0L)) throw Failure("invalid_arguments")
        val fd = OwnedStorageNative.openFile(session.targetParentFd, session.target.name, saved == null, true)
        var keep = false
        try {
            val actual = OwnedStorageNative.identity(fd)
            // Public copies cannot use the private-stage tail-truncation rule.
            // Any unjournaled size/mtime/identity change is a preserved conflict.
            if (actual[2] != offset || (saved != null && !actual.contentEquals(saved))) throw Failure("changed")
            val copy = PublicationCopy(fd, source, actual, offset, offset)
            session.copy = copy
            checkedCopy(session)
            syncCopy(session, copy)
            keep = true
            return identityMap(copy.observed)
        } finally {
            if (!keep) { session.copy = null; closeFd(fd) }
        }
    }

    private fun checkedCopy(session: Session): PublicationCopy {
        val copy = session.copy ?: throw Failure("invalid_arguments")
        validateLocation(session)
        val entry = OwnedStorageNative.entryIdentity(session.targetParentFd, session.target.name)
        if (!OwnedStorageNative.identity(session.fileFd).contentEquals(copy.source) ||
            !entry.contentEquals(copy.observed) ||
            !OwnedStorageNative.identity(copy.fd).contentEquals(copy.observed)) throw Failure("changed")
        return copy
    }

    private fun syncCopy(session: Session, copy: PublicationCopy) {
        OwnedStorageNative.sync(copy.fd)
        syncParents(session)
        checkedCopy(session)
    }

    private fun copyChunk(call: MethodCall): Long {
        val session = session(call)
        val copy = checkedCopy(session)
        val length = number(call, "length")
        if (copy.finished || copy.validatedPrefix != copy.requiredPrefix ||
            number(call, "offset") != copy.offset || length !in 1..65536 ||
            length > copy.source[2] - copy.offset) throw Failure("invalid_arguments")
        val bytes = OwnedStorageNative.read(session.fileFd, copy.offset, length.toInt())
        if (bytes.size.toLong() != length) throw Failure("changed")
        OwnedStorageNative.write(copy.fd, copy.offset, bytes)
        copy.offset += length
        copy.observed = OwnedStorageNative.identity(copy.fd)
        checkedCopy(session)
        if (copy.observed[2] != copy.offset) throw Failure("changed")
        return copy.offset
    }

    private fun validateLocation(session: Session) {
        var root = -1
        var parent = -1
        var stage = -1
        try {
            root = OwnedStorageNative.openRoot(session.target.root)
            parent = OwnedStorageNative.openDirectory(root, session.target.parent, false)
            if (!sameObject(OwnedStorageNative.identity(root), OwnedStorageNative.identity(session.targetRootFd)) ||
                !sameObject(OwnedStorageNative.identity(parent), OwnedStorageNative.identity(session.targetParentFd))) {
                throw Failure("changed")
            }
            val entry = if (session.published) OwnedStorageNative.entryIdentity(parent, session.target.name)
                else {
                    stage = OwnedStorageNative.openRoot(session.stageRoot)
                    if (!sameObject(OwnedStorageNative.identity(stage), OwnedStorageNative.identity(session.stageDirFd))) {
                        throw Failure("changed")
                    }
                    OwnedStorageNative.entryIdentity(stage, session.stageName)
                }
            if (!sameObject(entry, session.anchor) ||
                !sameObject(OwnedStorageNative.identity(session.fileFd), session.anchor)) throw Failure("changed")
        } finally { closeFd(stage); closeFd(parent); closeFd(root) }
    }

    private fun session(call: MethodCall) = sessions[string(call, "session")] ?: throw Failure("closed")
    private fun closeSession(session: Session) {
        session.copy?.let { closeFd(it.fd) }
        closeFd(session.fileFd); closeFd(session.stageDirFd)
        closeFd(session.targetParentFd); closeFd(session.targetRootFd)
    }
    private fun closeFd(fd: Int) { if (fd >= 0) try { OwnedStorageNative.close(fd) } catch (_: IOException) {} }
    private fun sameObject(a: LongArray, b: LongArray) = a[0] == b[0] && a[1] == b[1]
    private fun identityMap(value: LongArray): Map<String, Any> = mapOf(
        "device" to value[0].toString(), "inode" to value[1].toString(), "size" to value[2],
        "modifiedSeconds" to value[3], "modifiedNanos" to value[4])
    private fun expectedIdentity(call: MethodCall): LongArray {
        val map = call.argument<Map<String, Any>>("expectedIdentity") ?: throw Failure("invalid_arguments")
        return decodeIdentity(map)
    }
    private fun decodeIdentity(map: Map<String, Any>): LongArray {
        return longArrayOf((map["device"] as? String)?.toLongOrNull() ?: throw Failure("invalid_arguments"),
            (map["inode"] as? String)?.toLongOrNull() ?: throw Failure("invalid_arguments"),
            (map["size"] as? Number)?.toLong() ?: throw Failure("invalid_arguments"),
            (map["modifiedSeconds"] as? Number)?.toLong() ?: throw Failure("invalid_arguments"),
            (map["modifiedNanos"] as? Number)?.toLong() ?: throw Failure("invalid_arguments"))
    }
    private fun string(call: MethodCall, key: String) = call.argument<String>(key)?.takeIf { it.isNotEmpty() }
        ?: throw Failure("invalid_arguments")
    private fun number(call: MethodCall, key: String) = call.argument<Number>(key)?.toLong()
        ?: throw Failure("invalid_arguments")
    private fun errno(error: IOException) = Regex("^owned_storage:(\\d+)$").matchEntire(error.message.orEmpty())
        ?.groupValues?.get(1)?.toIntOrNull()
    private fun errorCode(error: Exception): String = when (error) {
        is Failure -> error.code
        is IOException -> when (errno(error)) {
            2 -> "not_found"; 13, 1 -> "access_denied"; 17 -> "collision"; 18 -> "cross_volume"
            20, 22, 40 -> "invalid_arguments"; 28 -> "out_of_space"; 38, 95 -> "unsupported"
            116 -> "changed"
            else -> "io_error"
        }
        else -> "invalid_arguments"
    }
}
