package com.retro.rshop

import android.content.Context
import android.os.Process
import android.system.Os
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.File

/** A single joined root child for one protected-save operation. Private capture
 * and restore journals remain owned/written by the app. Only source descriptors
 * cross this channel; payloads use bounded binary frames, not shell commands or
 * per-chunk su processes. Ordinary shared save paths retain direct JNI access. */
internal class SaveSourceStorage private constructor(
    private val source: String, private val child: java.lang.Process?, private val snapshotOnly: Boolean = false
) : Closeable {
    private val input = child?.let { DataInputStream(it.inputStream.buffered()) }
    private val output = child?.let { DataOutputStream(it.outputStream.buffered()) }
    private val diagnostics = child?.let { process -> Thread({
        process.errorStream.use { stream ->
            val buffer = ByteArray(1024)
            while (stream.read(buffer) >= 0) { /* Drain, never log save paths. */ }
        }
    }, "rshop-root-save-stderr").apply { start() } }
    val rootAssisted: Boolean get() = child != null
    val root: Int
    private var closed = false
    private var snapshotHelper: SaveSourceStorage? = null

    init {
        try {
            root = if (child == null) OwnedStorageNative.openRoot(source) else {
                call(JSONObject().put("source", source).also {
                    if (snapshotOnly) it.put("snapshotOnly", true)
                }); 1
            }
        } catch (error: Exception) {
            runCatching { output?.close() }
            runCatching { input?.close() }
            child?.waitFor()
            diagnostics?.join()
            throw error
        }
    }

    companion object {
        private fun start(context: Context, globalMountNamespace: Boolean = false): java.lang.Process {
            val apk = context.applicationInfo.sourceDir
            fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"
            val command = "CLASSPATH=${quote(apk)} /system/bin/app_process -Xmx64m /system/bin " +
                "com.retro.rshop.RootSaveProcess ${quote(apk)} source"
            // Android's per-app mount namespace hides other apps' private data
            // even from an inherited root child. Settings discovery must enter
            // Magisk's global namespace; ordinary/protected-save IO keeps its
            // already verified namespace and descriptor boundary.
            val arguments = if (globalMountNamespace) arrayOf("su", "--mount-master", "-c", command)
                else arrayOf("su", "-c", command)
            return try { ProcessBuilder(*arguments).start() }
                catch (_: IOException) { throw IOException("root_unavailable") }
        }
        fun open(context: Context, source: String): SaveSourceStorage {
            if (!MelonSaveBoundary.isProtectedDirectory(source)) return SaveSourceStorage(source, null)
            return SaveSourceStorage(source, start(context))
        }
        fun melonSettings(context: Context): JSONObject {
            val child = start(context, globalMountNamespace = true)
            val input = DataInputStream(child.inputStream.buffered())
            val output = DataOutputStream(child.outputStream.buffered())
            val drain = Thread({ child.errorStream.use { stream ->
                val buffer = ByteArray(1024)
                while (stream.read(buffer) >= 0) { /* No private settings logs. */ }
            } }, "rshop-root-save-settings-stderr").apply { start() }
            try {
                output.writeUTF(JSONObject().put("settings", MelonSaveBoundary.PACKAGE).toString()); output.flush()
                val reply = JSONObject(input.readUTF())
                reply.optString("error").takeIf(String::isNotEmpty)?.let { throw IOException(it) }
                return reply
            } catch (error: IOException) {
                if (error.message == "source_changed" || error.message == "save_settings_unresolved") throw error
                throw IOException("root_unavailable", error)
            } finally {
                try { output.close() } finally {
                    try { input.close() } finally { child.waitFor(); drain.join() }
                }
            }
        }
    }

    private fun call(request: JSONObject, bytes: ByteArray? = null): JSONObject {
        check(!closed)
        try {
            output!!.writeUTF(request.toString())
            if (bytes != null) output.write(bytes)
            output.flush()
            val response = JSONObject(input!!.readUTF())
            response.optString("error").takeIf(String::isNotEmpty)?.let { throw IOException(it) }
            return response
        } catch (error: IOException) {
            if (error.message?.matches(Regex("owned_storage:[0-9]+")) == true ||
                error.message == "source_changed") throw error
            throw IOException("root_unavailable", error)
        }
    }
    private fun request(operation: String, fd: Int = root) =
        JSONObject().put("operation", operation).put("fd", fd)
    private fun longs(value: JSONArray): LongArray = LongArray(value.length()) { value.getLong(it) }
    fun identity(fd: Int): LongArray = if (!rootAssisted) OwnedStorageNative.identity(fd)
        else longs(call(request("identity", fd)).getJSONArray("identity"))
    fun currentRootIdentity(): LongArray = if (rootAssisted)
        longs(call(request("currentRoot")).getJSONArray("identity")) else {
            val fresh = OwnedStorageNative.openRoot(source)
            try { OwnedStorageNative.identity(fresh) } finally { OwnedStorageNative.close(fresh) }
        }
    fun openFile(name: String, createExclusive: Boolean, writable: Boolean): Int = if (!rootAssisted)
        OwnedStorageNative.openFile(root, name, createExclusive, writable) else
        call(request("open").put("name", name).put("create", createExclusive).put("writable", writable)).getInt("fd")
    fun entryIdentity(name: String): LongArray = if (!rootAssisted) OwnedStorageNative.entryIdentity(root, name)
        else longs(call(request("entry").put("name", name)).getJSONArray("identity"))
    fun exists(name: String): Boolean = try { entryIdentity(name); true } catch (error: IOException) {
        if (error.message == "owned_storage:2") false else throw error
    }
    fun melonNames(): List<String> {
        if (!rootAssisted) {
            val names = File(source).list() ?: throw IOException("owned_storage:13")
            require(names.size <= 4096)
            return names.filter(MelonSaveBoundary::validName).sorted()
        }
        val count = call(request("names")).getInt("count")
        if (count !in 0..4096) throw IOException("root_unavailable")
        return List(count) { input!!.readUTF().also { require(MelonSaveBoundary.validName(it)) } }
    }
    fun read(fd: Int, offset: Long, length: Int): ByteArray {
        require(length in 1..65536)
        if (!rootAssisted) return OwnedStorageNative.read(fd, offset, length)
        val size = call(request("read", fd).put("offset", offset).put("length", length)).getInt("length")
        if (size !in 0..length) throw IOException("root_unavailable")
        return ByteArray(size).also { input!!.readFully(it) }
    }
    fun write(fd: Int, offset: Long, bytes: ByteArray) {
        require(bytes.size in 1..65536)
        if (!rootAssisted) OwnedStorageNative.write(fd, offset, bytes) else
            call(request("write", fd).put("offset", offset).put("length", bytes.size), bytes)
    }
    fun sync(fd: Int) { if (!rootAssisted) OwnedStorageNative.sync(fd) else call(request("sync", fd)) }
    fun renameNoReplace(stage: String, name: String) {
        if (!rootAssisted) OwnedStorageNative.renameNoReplace(root, stage, root, name) else
            call(request("rename").put("stage", stage).put("name", name))
    }
    fun replace(stage: String, name: String, staged: LongArray, current: LongArray): LongArray =
        if (!rootAssisted) OwnedStorageNative.replaceReviewedSave(root, stage, name, staged, current) else
            longs(call(request("replace").put("stage", stage).put("name", name)
                .put("staged", JSONArray(staged.toList())).put("current", JSONArray(current.toList())))
                .getJSONArray("identity"))
    fun closeFile(fd: Int) {
        if (!rootAssisted) OwnedStorageNative.close(fd) else call(request("close", fd))
    }
    fun beginMelonSnapshot(context: Context, name: String) {
        require(MelonSaveBoundary.validDirectory(source) && MelonSaveBoundary.validName(name))
        check(snapshotHelper == null)
        if (rootAssisted) call(request("snapshotBegin").put("name", name)) else {
            // Shared bytes retain direct JNI IO. Only the root writer census
            // and backing-inode guard use this one joined, read-only helper.
            val helper = SaveSourceStorage(source, start(context, globalMountNamespace = true), true)
            snapshotHelper = helper
            helper.call(helper.request("snapshotBegin").put("name", name))
        }
    }
    fun verifyMelonSnapshot() {
        val helper = snapshotHelper ?: this
        helper.call(helper.request("snapshotVerify"))
    }
    override fun close() {
        if (closed) return
        closed = true
        try { snapshotHelper?.close() } finally { snapshotHelper = null; closeSource() }
    }
    private fun closeSource() {
        if (child == null) { OwnedStorageNative.close(root); return }
        // EOF ends the exact child. Join even after a lost reply/cancellation;
        // never detach a writer or infer completion from a timer.
        try { output!!.close() } finally {
            // Break a child output write too if the reply was lost/malformed;
            // waiting before closing this pipe could deadlock on its capacity.
            try { input!!.close() } finally {
                child.waitFor()
                diagnostics!!.join()
            }
        }
    }
}

/** Fixed root-only source channel. No arbitrary paths, recursive scan, private
 * application data, ROMs or settings are accepted by this filesystem endpoint. */
object RootSaveSourceWorker {
    @JvmStatic fun serve() {
        require(Process.myUid() == 0)
        val input = DataInputStream(System.`in`.buffered())
        val output = DataOutputStream(System.out.buffered())
        val files = mutableMapOf<Int, Int>()
        val writable = mutableSetOf<Int>()
        var parent = -1
        var snapshot = -1
        var snapshotName: String? = null
        var snapshotInvalid = false
        fun reply(value: JSONObject) { output.writeUTF(value.toString()); output.flush() }
        try {
            val hello = JSONObject(input.readUTF())
            if (hello.length() == 1 && hello.optString("settings") == MelonSaveBoundary.PACKAGE) {
                val settings = try { MelonSaveSettings.read() } catch (error: Exception) {
                    if (error is IOException && error.message == "source_changed") throw error
                    throw IOException("save_settings_unresolved")
                }
                reply(settings)
                return
            }
            val source = hello.getString("source")
            val snapshotOnly = hello.length() == 2 && hello.optBoolean("snapshotOnly") &&
                MelonSaveBoundary.validDirectory(source)
            require(snapshotOnly || hello.length() == 1 && MelonSaveBoundary.isProtectedDirectory(source))
            val backing = MelonSaveBoundary.backingDirectory(source)
            parent = OwnedStorageNative.openRoot(backing)
            files[1] = parent
            reply(JSONObject().put("ready", true))
            var next = 2
            fun fd(row: JSONObject) = files[row.getInt("fd")] ?: throw IOException("source_changed")
            fun name(row: JSONObject, key: String = "name", stage: Boolean = false): String = row.getString(key).also {
                require(if (stage) it.matches(Regex("\\.rshop-save-restore-[a-f0-9]{32}")) else MelonSaveBoundary.validName(it))
            }
            fun identity(value: LongArray) = JSONObject().put("identity", JSONArray(value.toList()))
            while (true) {
                val encoded = try { input.readUTF() } catch (_: EOFException) { break }
                require(encoded.length <= 4096)
                val row = JSONObject(encoded)
                try {
                    val operation = row.getString("operation")
                    require(!snapshotOnly || operation in setOf("snapshotBegin", "snapshotVerify"))
                    fun verifySnapshot() {
                        if (snapshotInvalid) throw IOException("source_changed")
                        val leaf = snapshotName ?: throw IOException("source_changed")
                        if (OwnedStorageNative.saveSnapshotHasWriter(parent, leaf, source, backing) ||
                            OwnedStorageNative.saveSnapshotChanged(snapshot, leaf)) throw IOException("source_changed")
                        val fresh = OwnedStorageNative.openRoot(backing)
                        try {
                            if (OwnedStorageNative.identity(fresh).take(2) != OwnedStorageNative.identity(parent).take(2))
                                throw IOException("source_changed")
                        } finally { OwnedStorageNative.close(fresh) }
                    }
                    val result = when (operation) {
                        "snapshotBegin" -> {
                            require(snapshot == -1)
                            snapshotName = name(row)
                            snapshot = OwnedStorageNative.saveSnapshotOpen(parent)
                            verifySnapshot()
                            JSONObject()
                        }
                        "snapshotVerify" -> { verifySnapshot(); JSONObject() }
                        "names" -> {
                            val names = File(backing).list() ?: throw IOException("owned_storage:13")
                            require(names.size <= 4096)
                            val selected = names.filter(MelonSaveBoundary::validName).sorted()
                            reply(JSONObject().put("count", selected.size))
                            selected.forEach(output::writeUTF); output.flush()
                            continue
                        }
                        "identity" -> identity(OwnedStorageNative.identity(fd(row)))
                        "currentRoot" -> {
                            val fresh = OwnedStorageNative.openRoot(backing)
                            try { identity(OwnedStorageNative.identity(fresh)) } finally { OwnedStorageNative.close(fresh) }
                        }
                        "entry" -> {
                            val leaf = row.getString("name")
                            require(MelonSaveBoundary.validName(leaf) || leaf.matches(Regex("\\.rshop-save-restore-[a-f0-9]{32}")))
                            identity(OwnedStorageNative.entryIdentity(parent, leaf))
                        }
                        "open" -> {
                            require(files.size < 5)
                            val create = row.getBoolean("create")
                            val write = row.getBoolean("writable")
                            val leaf = name(row, stage = write || create)
                            val opened = OwnedStorageNative.openFile(parent, leaf, create, write)
                            val handle = next++
                            files[handle] = opened
                            if (write) writable.add(handle)
                            if (create) {
                                val before = OwnedStorageNative.identity(opened)
                                val owner = Os.stat(backing)
                                if (before[0] != owner.st_dev ||
                                    OwnedStorageNative.identity(parent).take(2) != listOf(owner.st_dev, owner.st_ino))
                                    throw IOException("source_changed")
                                // The emulator, not root/R-Shop, owns its staged
                                // replacement. lchown never follows a substituted link.
                                Os.lchown("$backing/$leaf", owner.st_uid, owner.st_gid)
                                if (!before.contentEquals(OwnedStorageNative.identity(opened)) ||
                                    !before.contentEquals(OwnedStorageNative.entryIdentity(parent, leaf)))
                                    throw IOException("source_changed")
                            }
                            JSONObject().put("fd", handle)
                        }
                        "read" -> {
                            val length = row.getInt("length")
                            val offset = row.getLong("offset")
                            require(length in 1..65536 && offset in 0..MelonSaveBoundary.MAX_BYTES &&
                                offset + length <= MelonSaveBoundary.MAX_BYTES)
                            val bytes = OwnedStorageNative.read(fd(row), offset, length)
                            reply(JSONObject().put("length", bytes.size))
                            output.write(bytes); output.flush()
                            continue
                        }
                        "write" -> {
                            require(row.getInt("fd") in writable)
                            val length = row.getInt("length")
                            val offset = row.getLong("offset")
                            require(length in 1..65536 && offset in 0..MelonSaveBoundary.MAX_BYTES &&
                                offset + length <= MelonSaveBoundary.MAX_BYTES)
                            val bytes = ByteArray(length).also(input::readFully)
                            OwnedStorageNative.write(fd(row), offset, bytes)
                            JSONObject()
                        }
                        "sync" -> { OwnedStorageNative.sync(fd(row)); JSONObject() }
                        "rename" -> {
                            OwnedStorageNative.renameNoReplace(parent, name(row, "stage", true), parent, name(row))
                            JSONObject()
                        }
                        "replace" -> {
                            fun expected(key: String): LongArray {
                                val values = row.getJSONArray(key); require(values.length() == 5)
                                return LongArray(5) { values.getLong(it) }
                            }
                            identity(OwnedStorageNative.replaceReviewedSave(parent, name(row, "stage", true), name(row),
                                expected("staged"), expected("current")))
                        }
                        "close" -> {
                            val handle = row.getInt("fd"); require(handle != 1)
                            OwnedStorageNative.close(fd(row)); files.remove(handle); writable.remove(handle)
                            JSONObject()
                        }
                        else -> throw IOException("root_unavailable")
                    }
                    reply(result)
                } catch (error: Exception) {
                    val message = (error as? IOException)?.message
                    if (snapshot >= 0) snapshotInvalid = true
                    reply(JSONObject().put("error", if (message == "source_changed" ||
                        message?.matches(Regex("owned_storage:[0-9]+")) == true) message else "root_unavailable"))
                }
            }
        } catch (error: Exception) {
            // Preserve filesystem errno at handshake too: an absent folder is
            // not a denied root grant. A closed peer still gets no fake success.
            val message = (error as? IOException)?.message
            runCatching { reply(JSONObject().put("error", if (message in setOf("source_changed", "save_settings_unresolved") ||
                message?.matches(Regex("owned_storage:[0-9]+")) == true) message else "root_unavailable")) }
        } finally {
            if (snapshot >= 0) runCatching { OwnedStorageNative.close(snapshot) }
            files.values.forEach { runCatching { OwnedStorageNative.close(it) } }
        }
    }
}
