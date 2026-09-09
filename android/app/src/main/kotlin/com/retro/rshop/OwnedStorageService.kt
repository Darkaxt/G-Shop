package com.retro.rshop

import android.content.Context
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
        "ownedRetireStage" -> { retireStage(call); null }
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
            if (session.published || session.copy != null || offset != session.nextOffset || bytes.size > 65536) {
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
        if (mode !in listOf("create", "resume", "published")) throw Failure("invalid_arguments")
        val offset = number(call, "durableOffset")
        if (offset < 0 || (mode == "create" && offset != 0L)) throw Failure("invalid_arguments")
        val expected = if (mode != "create") expectedIdentity(call) else null
        val fds = mutableListOf<Int>()
        fun own(fd: Int): Int { fds.add(fd); return fd }
        try {
            val rootFd = own(OwnedStorageNative.openRoot(target.root))
            val parentFd = own(OwnedStorageNative.openDirectory(rootFd, target.parent, mode != "published"))
            // Published mode is journal recovery, not a filename-only installed
            // lookup. Retain both parent handles to finish interrupted syncing.
            val stageFd = own(OwnedStorageNative.openRoot(stageRoot))
            val fileFd = own(OwnedStorageNative.openFile(
                if (mode == "published") parentFd else stageFd,
                if (mode == "published") target.name else stageName, mode == "create", mode != "published"))
            val identity = OwnedStorageNative.identity(fileFd)
            if (expected != null && (!sameObject(identity, expected) || identity[2] < offset)) {
                throw Failure("changed")
            }
            if (mode == "published") {
                if (!identity.contentEquals(expected!!) || offset != identity[2]) throw Failure("changed")
            } else {
                if (mode == "resume" && identity[2] != offset) OwnedStorageNative.truncate(fileFd, offset)
                OwnedStorageNative.sync(fileFd)
                OwnedStorageNative.sync(stageFd)
            }
            val session = Session(target, stageRoot, stageName, rootFd, parentFd, stageFd,
                fileFd, OwnedStorageNative.identity(fileFd), offset, OwnedPublication(mode == "published"))
            validateLocation(session)
            if (session.published) syncCheckpoint(session)
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

    private fun publish(call: MethodCall): Map<String, Any> {
        val session = session(call)
        if (session.copy != null) throw Failure("invalid_arguments")
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
        if (session.published || session.copy != null) throw Failure("invalid_arguments")
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
