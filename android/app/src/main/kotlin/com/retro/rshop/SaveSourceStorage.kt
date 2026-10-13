package com.retro.rshop

import android.content.Context
import android.os.ParcelFileDescriptor
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
    private val source: String, private val child: java.lang.Process?, private val snapshotOnly: Boolean = false,
    private val pcsxLeaf: String? = null, private val pcsxCard: PcsxSaveSettings.Card? = null,
    private val pcsxRestoreId: String? = null,
    private val companionNames: List<String>? = null, private val companionRom: String? = null,
    private val companionRestoreId: String? = null, private val companionTarget: String? = null,
    private val companionConfiguration: SaveRootConfiguration? = null
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
    private var emulatorHelper: SaveSourceStorage? = null

    init {
        try {
            root = if (child == null) OwnedStorageNative.openRoot(source) else {
                call(JSONObject().put("source", source).also {
                    if (snapshotOnly) it.put("snapshotOnly", true)
                    if (pcsxLeaf != null) it.put("pcsxLeaf", pcsxLeaf).put("pcsxSlot", pcsxCard!!.slot)
                        .put("pcsxMode", pcsxCard.mode).put("pcsxName", pcsxCard.name)
                    if (pcsxRestoreId != null) it.put("pcsxRestoreId", pcsxRestoreId)
                    if (companionNames != null) it.put("companionNames", JSONArray(companionNames)).put("companionRom", companionRom)
                    if (companionConfiguration != null) it.put("saveRoot", companionConfiguration.json())
                    if (companionRestoreId != null) it.put("companionRestoreId", companionRestoreId).put("companionTarget", companionTarget)
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
            // even from an inherited root child. Discovery and protected source
            // IO enter Magisk's global namespace, including the exact package
            // UID lookup used for restore's process-exit checks.
            val arguments = if (globalMountNamespace) arrayOf("su", "--mount-master", "-c", command)
                else arrayOf("su", "-c", command)
            return try { ProcessBuilder(*arguments).start() }
                catch (_: IOException) { throw IOException("root_unavailable") }
        }
        fun isProtectedDirectory(source: String): Boolean =
            MelonSaveBoundary.isProtectedDirectory(source) || PpssppSaveBoundary.isProtectedDirectory(source) ||
                PpssppSavedataBoundary.isProtectedDirectory(source)
        fun backingDirectory(source: String): String {
            require(MelonSaveBoundary.validDirectory(source) || PpssppSaveBoundary.validDirectory(source) ||
                PpssppSavedataBoundary.validDirectory(source) || PpssppSavedataBoundary.validParent(source))
            return if (source.startsWith("/storage/emulated/0/"))
                "/data/media/0/" + source.removePrefix("/storage/emulated/0/")
            else "/mnt/media_rw/" + source.removePrefix("/storage/")
        }
        fun open(context: Context, source: String): SaveSourceStorage {
            // SAVEDATA uses one root lane for the whole-folder mutation guard,
            // descriptor census and streaming IO, avoiding FUSE and per-file su.
            if (!isProtectedDirectory(source) && !PpssppSavedataBoundary.validDirectory(source) &&
                !PpssppSavedataBoundary.validParent(source))
                return SaveSourceStorage(source, null)
            return SaveSourceStorage(source, start(context, globalMountNamespace = true))
        }
        fun openRomCompanions(context: Context, source: String, romName: String, names: List<String>,
            restoreId: String? = null, target: String? = null,
            configuration: SaveRootConfiguration? = null): SaveSourceStorage {
            require((if (configuration == null) RomCompanionBoundary.validDirectory(source) else configuration.directory == source) && names.size in 0..RomCompanionBoundary.MAX_MEMBERS &&
                names.toSet().size == names.size && names.all {
                    configuration?.acceptsFile(it) ?: RomCompanionBoundary.associated(romName, it, RomCompanionBoundary.isolated(romName, source)) })
            require(if (restoreId == null) target == null else restoreId.matches(Regex("[a-f0-9]{32}")) && target in names)
            return SaveSourceStorage(source, start(context, globalMountNamespace = true),
                companionNames = names.toList(), companionRom = romName, companionRestoreId = restoreId,
                companionTarget = target, companionConfiguration = configuration)
        }
        fun openPcsxCapture(context: Context, encodedLeaf: String, selection: PcsxSaveSettings.Selection): SaveSourceStorage {
            require(PcsxSaveSettings.validChdLeaf(encodedLeaf))
            PcsxSaveSettings.select(PcsxSaveSettings.Layout(selection.directory, listOf(selection.card)), selection.card.slot)
            return SaveSourceStorage(selection.directory, start(context, globalMountNamespace = true),
                pcsxLeaf = encodedLeaf, pcsxCard = selection.card)
        }
        fun openPcsxRestore(context: Context, encodedLeaf: String, selection: PcsxSaveSettings.Selection,
                            restoreId: String): SaveSourceStorage {
            require(PcsxSaveSettings.validChdLeaf(encodedLeaf) && restoreId.matches(Regex("[a-f0-9]{32}")))
            PcsxSaveSettings.select(PcsxSaveSettings.Layout(selection.directory, listOf(selection.card)), selection.card.slot)
            return SaveSourceStorage(selection.directory, start(context, globalMountNamespace = true),
                pcsxLeaf = encodedLeaf, pcsxCard = selection.card, pcsxRestoreId = restoreId)
        }
        fun melonSettings(context: Context): JSONObject = settings(context, MelonSaveBoundary.PACKAGE)
        fun ppssppSettings(context: Context): JSONObject = settings(context, PpssppSaveSettings.PACKAGE)
        fun standardSaveRoot(context: Context, packageName: String = StandardSaveRoots.NETHER): JSONObject {
            require(packageName in setOf(StandardSaveRoots.NETHER, StandardSaveRoots.FLYCAST, StandardSaveRoots.DOLPHIN))
            return settings(context, packageName)
        }
        fun pcsxSettings(context: Context, encodedLeaf: String): JSONObject {
            require(PcsxSaveSettings.validChdLeaf(encodedLeaf))
            return settings(context, PcsxSaveSettings.PACKAGE, encodedLeaf)
        }
        private fun settings(context: Context, packageName: String, encodedLeaf: String? = null): JSONObject {
            val child = start(context, globalMountNamespace = true)
            val input = DataInputStream(child.inputStream.buffered())
            val output = DataOutputStream(child.outputStream.buffered())
            val drain = Thread({ child.errorStream.use { stream ->
                val buffer = ByteArray(1024)
                while (stream.read(buffer) >= 0) { /* No private settings logs. */ }
            } }, "rshop-root-save-settings-stderr").apply { start() }
            try {
                output.writeUTF(JSONObject().put("settings", packageName).also {
                    if (encodedLeaf != null) it.put("encodedLeaf", encodedLeaf)
                }.toString()); output.flush()
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
                error.message in setOf("source_changed", "emulator_running", "save_settings_unresolved")) throw error
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
    fun names(): List<String> {
        val validName: (String) -> Boolean = if (companionNames != null) companionNames::contains
            else if (PpssppSavedataBoundary.validDirectory(source) ||
            PpssppSavedataBoundary.validParent(source))
            PpssppSavedataBoundary::validMember else if (PpssppSaveBoundary.isProtectedDirectory(source))
            PpssppSaveBoundary::validSourceName else MelonSaveBoundary::validName
        if (!rootAssisted) {
            val names = File(source).list() ?: throw IOException("owned_storage:13")
            require(names.size <= 4096)
            return names.filter(validName).sorted()
        }
        val count = call(request("names")).getInt("count")
        if (count !in 0..4096) throw IOException("root_unavailable")
        return List(count) { input!!.readUTF().also { require(validName(it)) } }
    }
    fun beginPpssppSavedataSnapshot() {
        require((PpssppSavedataBoundary.validDirectory(source) || PpssppSavedataBoundary.validParent(source)) && rootAssisted)
        call(request("savedataSnapshotBegin"))
    }
    fun beginRomCompanionSnapshot(name: String? = null) {
        require(companionNames != null && rootAssisted)
        require(if (companionRestoreId == null) name == null else name in companionNames)
        call(request("snapshotBegin").also { if (name != null) it.put("name", name) })
    }
    fun companionInventory(): OwnedRomContentProvider.Companion.CompanionInventory {
        require(companionNames != null && rootAssisted)
        val row = call(request("companionInventory"))
        fun identities(key: String): Map<String, List<Long>> {
            val values = row.getJSONObject(key)
            require(values.length() <= 128)
            return values.keys().asSequence().associateWith { longs(values.getJSONArray(it)).toList() }
        }
        return OwnedRomContentProvider.Companion.CompanionInventory(identities("files"), identities("directories"))
    }
    fun runtimeIdentity(): String {
        require(companionConfiguration != null && companionConfiguration.runtimeFiles.isNotEmpty() && rootAssisted)
        return call(request("runtimeIdentity")).getString("identity")
    }
    fun openSaveGroup(name: String, createExclusive: Boolean = false, anchor: LongArray? = null,
                      recoverEmpty: Boolean = false): Int {
        require(PpssppSavedataBoundary.validParent(source) && rootAssisted)
        return call(request("groupOpen").put("name", name).put("create", createExclusive).put("recoverEmpty", recoverEmpty).also {
            if (anchor != null) it.put("anchor", JSONArray(anchor.toList()))
        }).getInt("fd")
    }
    fun openSaveGroupFile(group: Int, name: String, createExclusive: Boolean, writable: Boolean): Int =
        call(request("groupFile", group).put("name", name).put("create", createExclusive)
            .put("writable", writable)).getInt("fd")
    fun saveGroupEntryIdentity(group: Int, name: String): LongArray =
        longs(call(request("groupEntry", group).put("name", name)).getJSONArray("identity"))
    fun saveGroupNames(group: Int): List<String> {
        val count = call(request("groupNames", group)).getInt("count")
        require(count in 0..PpssppSavedataBoundary.MAX_MEMBERS)
        return List(count) { input!!.readUTF().also { require(PpssppSavedataBoundary.validMember(it)) } }
    }
    fun beginSaveGroupSnapshot(group: Int) { call(request("groupSnapshotBegin", group)) }
    fun saveStageExists(name: String): Boolean = call(request("groupProbe").put("name", name)).getBoolean("exists")
    fun retireSaveGroupMember(group: Int, name: String, expected: LongArray, version: Long) {
        call(request("groupMemberRetire", group).put("name", name)
            .put("expected", JSONArray(expected.toList())).put("versionCode", version))
    }
    fun retireSaveGroup(name: String, expected: LongArray, version: Long) {
        call(request("groupRetire").put("name", name).put("expected", JSONArray(expected.toList()))
            .put("versionCode", version))
    }
    fun publishSaveGroup(stage: String, name: String, staged: LongArray, current: LongArray?, version: Long): LongArray =
        longs(call(request("groupPublish").put("stage", stage).put("name", name)
            .put("staged", JSONArray(staged.toList())).put("versionCode", version).also {
                if (current != null) it.put("current", JSONArray(current.toList()))
            }).getJSONArray("identity"))
    fun verifyPpssppSavedataSnapshot() {
        require((PpssppSavedataBoundary.validDirectory(source) || PpssppSavedataBoundary.validParent(source)) && rootAssisted)
        call(request("snapshotVerify"))
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
        beginSnapshot(context, name)
    }
    fun beginRetroArchSnapshot(context: Context, name: String) {
        RetroArchSaveBoundary.snapshotNames(source, name)
        beginSnapshot(context, name)
    }
    fun beginPpssppCompanionSnapshot(context: Context, name: String) {
        require(PpssppSaveBoundary.validDirectory(source) && PpssppSaveBoundary.validCompanionName(name))
        beginSnapshot(context, name)
    }
    fun beginPcsxSnapshot(context: Context, name: String) {
        require(rootAssisted && pcsxLeaf != null && name == pcsxCard!!.name)
        beginSnapshot(context, name)
    }
    private fun beginSnapshot(context: Context, name: String) {
        check(snapshotHelper == null)
        if (rootAssisted) call(request("snapshotBegin").put("name", name)) else {
            // Shared bytes retain direct JNI IO. Only the root writer census
            // and backing-inode guard use this one joined, read-only helper.
            val helper = SaveSourceStorage(source, start(context, globalMountNamespace = true), true)
            snapshotHelper = helper
            helper.call(helper.request("snapshotBegin").put("name", name))
        }
    }
    fun verifySnapshot() {
        val helper = snapshotHelper ?: this
        helper.call(helper.request("snapshotVerify"))
    }
    fun verifyEmulatorClosed(context: Context) {
        require(MelonSaveBoundary.validDirectory(source) || PpssppSaveBoundary.validDirectory(source) ||
            PpssppSavedataBoundary.validDirectory(source) || PpssppSavedataBoundary.validParent(source))
        val packageName = if (PpssppSaveBoundary.validDirectory(source) ||
            PpssppSavedataBoundary.validDirectory(source) || PpssppSavedataBoundary.validParent(source)) PpssppSaveSettings.PACKAGE
            else MelonSaveBoundary.PACKAGE
        @Suppress("DEPRECATION")
        val runtime = context.packageManager.getPackageInfo(packageName, 0)
        @Suppress("DEPRECATION")
        val version = if (android.os.Build.VERSION.SDK_INT >= 28) runtime.longVersionCode
            else runtime.versionCode.toLong()
        val helper = if (rootAssisted) this else emulatorHelper ?: SaveSourceStorage(
            source, start(context, globalMountNamespace = true), true).also { emulatorHelper = it }
        helper.call(helper.request("emulatorClosed").put("versionCode", version))
    }
    override fun close() {
        if (closed) return
        closed = true
        try { snapshotHelper?.close() } finally {
            snapshotHelper = null
            try { emulatorHelper?.close() } finally { emulatorHelper = null; closeSource() }
        }
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
        val groups = mutableMapOf<Int, String>()
        val writableGroups = mutableSetOf<Int>()
        var parent = -1
        var snapshot = -1
        var snapshotName: String? = null
        var clockSnapshot = -1
        var clockName: String? = null
        var snapshotInvalid = false
        val companionGuards = mutableListOf<Triple<String, List<Long>, Int>>()
        fun reply(value: JSONObject) { output.writeUTF(value.toString()); output.flush() }
        try {
            val hello = JSONObject(input.readUTF())
            if (hello.length() == 2 && hello.optString("settings") == PcsxSaveSettings.PACKAGE &&
                hello.has("encodedLeaf")) {
                val settings = try { PcsxSaveSettings.read(hello.getString("encodedLeaf")) }
                    catch (error: Exception) {
                        if (error is IOException && error.message == "source_changed") throw error
                        throw IOException("save_settings_unresolved")
                    }
                reply(settings)
                return
            }
            if (hello.length() == 1 && hello.optString("settings") in
                setOf(MelonSaveBoundary.PACKAGE, PpssppSaveSettings.PACKAGE, StandardSaveRoots.NETHER, StandardSaveRoots.FLYCAST, StandardSaveRoots.DOLPHIN)) {
                val settings = try {
                    if (hello.getString("settings") == MelonSaveBoundary.PACKAGE) MelonSaveSettings.read()
                    else if (hello.getString("settings") == StandardSaveRoots.NETHER)
                        JSONObject().put("saveRoot", StandardSaveRoots.nether()?.json() ?: JSONObject.NULL)
                    else if (hello.getString("settings") == StandardSaveRoots.FLYCAST)
                        JSONObject().put("saveRoot", StandardSaveRoots.flycast()?.json() ?: JSONObject.NULL)
                    else if (hello.getString("settings") == StandardSaveRoots.DOLPHIN)
                        JSONObject().put("saveRoot", StandardSaveRoots.dolphin()?.json() ?: JSONObject.NULL)
                    else JSONObject().put("directory", PpssppSaveSettings.read())
                } catch (error: Exception) {
                    if (error is IOException && error.message == "source_changed") throw error
                    throw IOException("save_settings_unresolved")
                }
                reply(settings)
                return
            }
            val source = hello.getString("source")
            val configuration = hello.optJSONObject("saveRoot")?.let(SaveRootConfiguration::decode)
            require(configuration == null || configuration.directory == source)
            if (configuration != null) StandardSaveRoots.verify(configuration)
            val companionRom = hello.optString("companionRom").takeIf { it.isNotEmpty() }
            val companionRestore = if (hello.has("companionRestoreId")) hello.getString("companionRestoreId").also {
                require(hello.has("companionNames") && it.matches(Regex("[a-f0-9]{32}")))
            } else null
            val companions = if (hello.has("companionNames")) {
                val selected = hello.getJSONArray("companionNames")
                require(hello.length() == (if (companionRestore == null) 3 else 5) + (if (configuration == null) 0 else 1) && companionRom != null &&
                    RomCompanionBoundary.validLeaf(companionRom) && (configuration != null || RomCompanionBoundary.validDirectory(source)) &&
                    selected.length() in 0..RomCompanionBoundary.MAX_MEMBERS)
                (0 until selected.length()).map(selected::getString).also {
                    require(it.toSet().size == it.size && it.all { name -> configuration?.acceptsFile(name) ?: RomCompanionBoundary.associated(companionRom,
                        name, RomCompanionBoundary.isolated(companionRom, source)) })
                }
            } else null
            val companionTarget = if (companionRestore != null) hello.getString("companionTarget").also {
                require(it in companions!!)
            } else null
            val pcsxLeaf = if (hello.has("pcsxLeaf")) hello.getString("pcsxLeaf") else null
            val pcsxRestoreId = if (hello.has("pcsxRestoreId")) hello.getString("pcsxRestoreId").also {
                require(pcsxLeaf != null && it.matches(Regex("[a-f0-9]{32}")))
            } else null
            val pcsx = pcsxLeaf?.let { leaf ->
                require(hello.length() == if (pcsxRestoreId == null) 5 else 6)
                val configured = try { PcsxSaveSettings.readSelection(leaf, hello.getInt("pcsxSlot")) }
                    catch (error: Exception) {
                        if (error is IOException && error.message == "source_changed") throw error
                        throw IOException("save_settings_unresolved")
                    }
                val selected = configured.first
                if (selected.directory != source || selected.card.mode != hello.getString("pcsxMode") ||
                    selected.card.name != hello.getString("pcsxName")) throw IOException("source_changed")
                configured
            }
            // Route identity comes from the reviewed selection, not a custom
            // directory accidentally resembling another emulator's layout.
            val savedata = companions == null && pcsx == null && PpssppSavedataBoundary.validDirectory(source)
            val savedataParent = companions == null && pcsx == null && PpssppSavedataBoundary.validParent(source)
            val ppsspp = companions == null && pcsx == null && PpssppSaveBoundary.validDirectory(source)
            val validName: (String) -> Boolean = if (companions != null) companions::contains
                else if (pcsx != null) { leaf -> leaf == pcsx.first.card.name }
                else if (savedata || savedataParent) PpssppSavedataBoundary::validMember
                else if (ppsspp) PpssppSaveBoundary::validSourceName else MelonSaveBoundary::validName
            val maxBytes = if (companions != null) RomCompanionBoundary.MAX_BYTES else if (pcsx != null) 131072L else if (savedata || savedataParent) PpssppSavedataBoundary.MAX_BYTES
                else if (ppsspp) PpssppSaveBoundary.MAX_STATE_BYTES else MelonSaveBoundary.MAX_BYTES
            val snapshotOnly = hello.length() == 2 && hello.optBoolean("snapshotOnly") &&
                (MelonSaveBoundary.validDirectory(source) || PpssppSaveBoundary.validDirectory(source))
            require(companions != null || pcsx != null || snapshotOnly || hello.length() == 1 && (savedata || savedataParent || SaveSourceStorage.isProtectedDirectory(source)))
            val backing = if (pcsx != null || companions != null) {
                if (source.startsWith("/storage/emulated/0/")) "/data/media/0/" + source.removePrefix("/storage/emulated/0/")
                else if (source.startsWith("/storage/")) "/mnt/media_rw/" + source.removePrefix("/storage/") else source
            } else SaveSourceStorage.backingDirectory(source)
            parent = OwnedStorageNative.openRoot(backing)
            fun companionParent(path: String, stage: Boolean = false, create: Boolean = false): Int {
                val relative = (if (stage) companionTarget!! else path).substringBeforeLast('/', "")
                if (!create) return OwnedStorageNative.openDirectory(parent, relative, false)
                var current = OwnedStorageNative.openDirectory(parent, "", false)
                try {
                    for (part in relative.split('/').filter(String::isNotEmpty)) {
                        val next = try { OwnedStorageNative.openDirectory(current, part, false) }
                            catch (error: IOException) {
                                if (error.message != "owned_storage:2") throw error
                                val owner = ParcelFileDescriptor.fromFd(current).use { Os.fstat(it.fileDescriptor) }
                                OwnedStorageNative.createSaveDirectory(current, part).also { created ->
                                    try {
                                        ParcelFileDescriptor.fromFd(created).use {
                                            Os.fchown(it.fileDescriptor, owner.st_uid, owner.st_gid)
                                            Os.fchmod(it.fileDescriptor, owner.st_mode and 511)
                                        }
                                        OwnedStorageNative.sync(created); OwnedStorageNative.sync(current)
                                    } catch (failure: Exception) { OwnedStorageNative.close(created); throw failure }
                                }
                            }
                        OwnedStorageNative.close(current); current = next
                    }
                    return current.also { current = -1 }
                } finally { if (current >= 0) OwnedStorageNative.close(current) }
            }
            // The explicit restore journal precedes this destination-only
            // preparation. Never create directories during discovery/capture.
            if (companionTarget != null) OwnedStorageNative.close(companionParent(companionTarget, create = true))
            files[1] = parent
            reply(JSONObject().put("ready", true))
            var next = 2
            fun fd(row: JSONObject) = files[row.getInt("fd")] ?: throw IOException("source_changed")
            fun validStage(leaf: String) = if (companions != null)
                companionRestore != null && leaf == ".rshop-save-restore-$companionRestore"
                else if (pcsx != null)
                pcsxRestoreId != null && leaf == ".rshop-save-restore-$pcsxRestoreId"
                else leaf.matches(Regex("\\.rshop-save-restore-[a-f0-9]{32}"))
            fun name(row: JSONObject, key: String = "name", stage: Boolean = false): String = row.getString(key).also {
                require(if (stage) validStage(it) else validName(it))
            }
            fun identity(value: LongArray) = JSONObject().put("identity", JSONArray(value.toList()))
            while (true) {
                val encoded = try { input.readUTF() } catch (_: EOFException) { break }
                require(encoded.length <= 4096)
                val row = JSONObject(encoded)
                try {
                    val operation = row.getString("operation")
                    require(companions == null || operation in (setOf("names", "identity", "currentRoot", "entry",
                        "open", "read", "close", "snapshotBegin", "snapshotVerify", "companionInventory", "runtimeIdentity") +
                        if (companionRestore == null) emptySet() else setOf("write", "sync", "rename", "replace")))
                    // Capture stays read-only. Restore can write only its exact
                    // private stage and publish only the configured card.
                    require(pcsx == null || operation in if (pcsxRestoreId == null)
                        setOf("identity", "currentRoot", "entry", "open", "read", "close", "snapshotBegin", "snapshotVerify")
                        else setOf("identity", "currentRoot", "entry", "open", "read", "write", "sync", "close", "rename", "replace"))
                    require(!savedataParent || operation in setOf("names", "identity", "currentRoot", "emulatorClosed",
                        "savedataSnapshotBegin", "snapshotVerify", "groupOpen", "groupFile", "groupEntry", "groupNames",
                        "groupPublish", "groupProbe", "groupSnapshotBegin", "groupMemberRetire", "groupRetire", "read", "write", "sync", "close"))
                    require(!snapshotOnly || operation in setOf("snapshotBegin", "snapshotVerify", "emulatorClosed"))
                    fun expected(key: String): LongArray {
                        val values = row.getJSONArray(key); require(values.length() == 5)
                        return LongArray(5) { values.getLong(it) }
                    }
                    fun groupPath(): String = "$backing/${groups[row.getInt("fd")] ?: throw IOException("source_changed")}"
                    fun pinnedParent() {
                        val fresh = OwnedStorageNative.openRoot(backing)
                        try {
                            if (OwnedStorageNative.identity(parent).take(2) != OwnedStorageNative.identity(fresh).take(2))
                                throw IOException("source_changed")
                        } finally { OwnedStorageNative.close(fresh) }
                    }
                    fun verifyPcsxSettings() {
                        if (pcsx == null) return
                        val current = try { PcsxSaveSettings.readSelection(pcsxLeaf, pcsx.first.card.slot) }
                            catch (_: Exception) { throw IOException("source_changed") }
                        if (current != pcsx) throw IOException("source_changed")
                        pinnedParent()
                    }
                    fun verifyPcsxPublication() {
                        if (companions != null) {
                            require(companionRestore != null)
                            pinnedParent()
                            if (OwnedStorageNative.saveSnapshotHasWriters(parent, companions.toTypedArray(), source, backing))
                                throw IOException("source_changed")
                        }
                        if (pcsx == null) return
                        require(pcsxRestoreId != null)
                        verifyPcsxSettings()
                        if (OwnedStorageNative.saveSnapshotHasWriter(parent, pcsx.first.card.name!!, source, backing))
                            throw IOException("source_changed")
                    }
                    fun verifySnapshot() {
                        verifyPcsxSettings()
                        if (snapshotInvalid) throw IOException("source_changed")
                        val leaf = snapshotName ?: throw IOException("source_changed")
                        val writer = if (companions != null)
                            OwnedStorageNative.saveSnapshotHasWriters(parent, companions.toTypedArray(), source, backing)
                            else !savedataParent && OwnedStorageNative.saveSnapshotHasWriter(parent, leaf, source, backing)
                        if (writer ||
                            OwnedStorageNative.saveSnapshotChanged(snapshot, leaf)) throw IOException("source_changed")
                        for ((relative, identity, watch) in companionGuards) {
                            val fresh = OwnedStorageNative.openDirectory(parent, relative, false)
                            try {
                                if (OwnedStorageNative.identity(fresh).take(2) != identity ||
                                    OwnedStorageNative.saveSnapshotChanged(watch,
                                        if (companionTarget != null) companionTarget.removePrefix("$relative/").substringBefore('/') else ""))
                                    throw IOException("source_changed")
                            } finally { OwnedStorageNative.close(fresh) }
                        }
                        clockName?.let { clock ->
                            if (OwnedStorageNative.saveSnapshotHasWriter(parent, clock, source, backing) ||
                                OwnedStorageNative.saveSnapshotChanged(clockSnapshot, clock)) throw IOException("source_changed")
                        }
                        val fresh = OwnedStorageNative.openRoot(backing)
                        try {
                            if (OwnedStorageNative.identity(fresh).take(2) != OwnedStorageNative.identity(parent).take(2))
                                throw IOException("source_changed")
                        } finally { OwnedStorageNative.close(fresh) }
                    }
                    val result = when (operation) {
                        "runtimeIdentity" -> {
                            require(configuration != null && configuration.runtimeFiles.isNotEmpty() && companionRestore == null)
                            val identities = JSONArray()
                            var total = 0L
                            for (path in configuration.runtimeFiles.sorted()) {
                                val actual = if (path.startsWith("/storage/emulated/0/"))
                                    "/data/media/0/" + path.removePrefix("/storage/emulated/0/")
                                    else if (path.startsWith("/storage/")) "/mnt/media_rw/" + path.removePrefix("/storage/") else path
                                val parentPath = actual.substringBeforeLast('/')
                                val leaf = actual.substringAfterLast('/')
                                val coreParent = OwnedStorageNative.openRoot(parentPath)
                                try {
                                    val core = OwnedStorageNative.openFile(coreParent, leaf, false, false)
                                    try {
                                        val before = OwnedStorageNative.identity(core)
                                        if (OwnedStorageNative.saveSnapshotHasWriter(coreParent, leaf,
                                                path.substringBeforeLast('/'), parentPath)) throw IOException("source_changed")
                                        require(before[2] in 1..(64L * 1024 * 1024) && total <= 64L * 1024 * 1024 - before[2])
                                        total += before[2]
                                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                                        var offset = 0L
                                        while (offset < before[2]) {
                                            val bytes = OwnedStorageNative.read(core, offset, minOf(65536L, before[2] - offset).toInt())
                                            if (bytes.isEmpty()) throw IOException("source_changed")
                                            digest.update(bytes); offset += bytes.size
                                        }
                                        if (OwnedStorageNative.saveSnapshotHasWriter(coreParent, leaf,
                                                path.substringBeforeLast('/'), parentPath) ||
                                            !before.contentEquals(OwnedStorageNative.identity(core)) ||
                                            !before.contentEquals(OwnedStorageNative.entryIdentity(coreParent, leaf)))
                                            throw IOException("source_changed")
                                        val fresh = OwnedStorageNative.openRoot(parentPath)
                                        try { if (!before.contentEquals(OwnedStorageNative.entryIdentity(fresh, leaf))) throw IOException("source_changed") }
                                        finally { OwnedStorageNative.close(fresh) }
                                        identities.put(JSONArray(listOf(path, digest.digest().joinToString("") { "%02x".format(it) })))
                                    } finally { OwnedStorageNative.close(core) }
                                } finally { OwnedStorageNative.close(coreParent) }
                            }
                            val digest = java.security.MessageDigest.getInstance("SHA-256")
                                .digest(identities.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
                            JSONObject().put("identity", "files-$digest")
                        }
                        "companionInventory" -> {
                            require(companions != null && companionRestore == null)
                            pinnedParent()
                            val inventory = OwnedRomContentProvider.companionInventory(backing, companionRom!!, {}, configuration)
                            JSONObject().put("files", JSONObject(inventory.files)).put("directories", JSONObject(inventory.directories))
                        }
                        "emulatorClosed" -> {
                            SaveEmulatorProcess.requireClosed(if (savedata || savedataParent || PpssppSaveBoundary.validDirectory(source))
                                PpssppSaveSettings.PACKAGE else MelonSaveBoundary.PACKAGE,
                                row.getLong("versionCode"))
                            JSONObject()
                        }
                        "snapshotBegin" -> {
                            require(snapshot == -1 && (companions != null || pcsx != null || MelonSaveBoundary.validDirectory(source) || ppsspp))
                            snapshotName = if (companions != null && companionRestore == null) "" else name(row)
                            if (companionTarget?.contains('/') == true) snapshotName = companionTarget.substringBefore('/')
                            snapshot = OwnedStorageNative.saveSnapshotOpen(parent)
                            if (companions != null) {
                                val inventory = OwnedRomContentProvider.companionInventory(backing, companionRom!!, {}, configuration)
                                val selectedParents = if (companionTarget == null) inventory.directories.keys.filter(String::isNotEmpty)
                                    else companionTarget.split('/').dropLast(1).let { parts ->
                                        parts.indices.map { index -> parts.take(index + 1).joinToString("/") }
                                    }
                                for (relative in selectedParents) {
                                    val folder = OwnedStorageNative.openDirectory(parent, relative, false)
                                    try { companionGuards.add(Triple(relative, OwnedStorageNative.identity(folder).take(2),
                                        OwnedStorageNative.saveSnapshotOpen(folder))) }
                                    finally { OwnedStorageNative.close(folder) }
                                }
                                val reviewed = OwnedRomContentProvider.companionInventory(backing, companionRom, {}, configuration)
                                if (reviewed != inventory) throw IOException("source_changed")
                            }
                            if (companions == null && pcsx == null && source in listOf(RetroArchSaveBoundary.saveDirectory("gb"), RetroArchSaveBoundary.saveDirectory("gba"),
                                    RetroArchSaveBoundary.saveDirectory("snes"))) {
                                clockName = RetroArchSaveBoundary.snapshotNames(source, snapshotName!!).last()
                                clockSnapshot = OwnedStorageNative.saveSnapshotOpen(parent)
                            }
                            verifySnapshot()
                            JSONObject()
                        }
                        "savedataSnapshotBegin" -> {
                            require((savedata || savedataParent) && snapshot == -1)
                            snapshotName = "" // Every group event, not one selected leaf.
                            snapshot = OwnedStorageNative.saveSnapshotOpen(parent)
                            verifySnapshot()
                            JSONObject()
                        }
                        "snapshotVerify" -> { verifySnapshot(); JSONObject() }
                        "groupSnapshotBegin" -> {
                            require(savedataParent && snapshot == -1); groupPath()
                            snapshotName = ""
                            snapshot = OwnedStorageNative.saveSnapshotOpen(fd(row))
                            verifySnapshot(); JSONObject()
                        }
                        "groupProbe" -> {
                            require(savedataParent)
                            val leaf = row.getString("name"); require(PpssppSavedataBoundary.validStage(leaf))
                            pinnedParent()
                            val found = try {
                                val opened = OwnedStorageNative.openDirectory(parent, leaf, false)
                                OwnedStorageNative.close(opened); true
                            } catch (error: IOException) { if (error.message != "owned_storage:2") throw error; false }
                            JSONObject().put("exists", found)
                        }
                        "groupOpen" -> {
                            require(savedataParent && files.size < 5)
                            val leaf = row.getString("name")
                            val stage = PpssppSavedataBoundary.validStage(leaf)
                            val create = row.getBoolean("create")
                            val recoverEmpty = row.optBoolean("recoverEmpty")
                            require(!(create && recoverEmpty) && !(recoverEmpty && row.has("anchor")))
                            require(if (create || recoverEmpty || row.has("anchor")) stage else PpssppSavedataBoundary.validMember(leaf))
                            pinnedParent()
                            val opened = if (create) OwnedStorageNative.createSaveDirectory(parent, leaf)
                                else OwnedStorageNative.openDirectory(parent, leaf, false)
                            val handle = next++
                            files[handle] = opened; groups[handle] = leaf
                            val before = OwnedStorageNative.identity(opened)
                            if (row.has("anchor") && before.take(2) != expected("anchor").take(2))
                                throw IOException("source_changed")
                            if (create || recoverEmpty) {
                                val owner = Os.stat("/data/user/0/${PpssppSaveSettings.PACKAGE}")
                                require(owner.st_uid >= 10000)
                                if (recoverEmpty) {
                                    require(File("$backing/$leaf").list()?.isEmpty() == true)
                                    val status = Os.lstat("$backing/$leaf")
                                    require(status.st_uid == 0 || status.st_uid == owner.st_uid)
                                }
                                Os.lchown("$backing/$leaf", owner.st_uid, owner.st_gid)
                            }
                            if (stage) writableGroups.add(handle)
                            pinnedParent()
                            JSONObject().put("fd", handle)
                        }
                        "groupFile" -> {
                            require(savedataParent && files.size < 5)
                            val path = groupPath()
                            val write = row.getBoolean("writable")
                            val create = row.getBoolean("create")
                            require(!(write || create) || row.getInt("fd") in writableGroups)
                            val leaf = name(row)
                            val opened = OwnedStorageNative.openFile(fd(row), leaf, create, write)
                            val handle = next++; files[handle] = opened
                            if (write) writable.add(handle)
                            if (create) {
                                val before = OwnedStorageNative.identity(opened)
                                val owner = Os.stat(path)
                                Os.lchown("$path/$leaf", owner.st_uid, owner.st_gid)
                                if (!before.contentEquals(OwnedStorageNative.identity(opened)) ||
                                    !before.contentEquals(OwnedStorageNative.entryIdentity(fd(row), leaf)))
                                    throw IOException("source_changed")
                            }
                            JSONObject().put("fd", handle)
                        }
                        "groupEntry" -> {
                            require(savedataParent); groupPath()
                            identity(OwnedStorageNative.entryIdentity(fd(row), name(row)))
                        }
                        "groupNames" -> {
                            require(savedataParent)
                            val path = groupPath()
                            val names = File(path).list()?.sorted() ?: throw IOException("source_changed")
                            require(names.size <= PpssppSavedataBoundary.MAX_MEMBERS && names.all(validName))
                            val fresh = OwnedStorageNative.openRoot(path)
                            try {
                                if (OwnedStorageNative.identity(fresh).take(2) != OwnedStorageNative.identity(fd(row)).take(2))
                                    throw IOException("source_changed")
                            } finally { OwnedStorageNative.close(fresh) }
                            reply(JSONObject().put("count", names.size)); names.forEach(output::writeUTF); output.flush()
                            continue
                        }
                        "groupPublish" -> {
                            require(savedataParent)
                            val stage = row.getString("stage"); require(PpssppSavedataBoundary.validStage(stage))
                            val target = name(row)
                            require(groups.any { (handle, leaf) -> handle in writableGroups && leaf == stage })
                            pinnedParent()
                            SaveEmulatorProcess.requireClosed(PpssppSaveSettings.PACKAGE, row.getLong("versionCode"))
                            val placed = OwnedStorageNative.publishReviewedSaveDirectory(parent, stage, target,
                                expected("staged"), if (row.has("current")) expected("current") else null)
                            OwnedStorageNative.sync(parent)
                            identity(placed)
                        }
                        "groupMemberRetire" -> {
                            require(savedataParent && row.getInt("fd") in writableGroups)
                            val path = groupPath(); val fresh = OwnedStorageNative.openRoot(path)
                            try {
                                if (OwnedStorageNative.identity(fresh).take(2) != OwnedStorageNative.identity(fd(row)).take(2))
                                    throw IOException("source_changed")
                            } finally { OwnedStorageNative.close(fresh) }
                            pinnedParent()
                            SaveEmulatorProcess.requireClosed(PpssppSaveSettings.PACKAGE, row.getLong("versionCode"))
                            OwnedStorageNative.retireReviewedSaveMember(fd(row), name(row), expected("expected"))
                            JSONObject()
                        }
                        "groupRetire" -> {
                            require(savedataParent)
                            val leaf = row.getString("name"); require(PpssppSavedataBoundary.validStage(leaf))
                            pinnedParent()
                            SaveEmulatorProcess.requireClosed(PpssppSaveSettings.PACKAGE, row.getLong("versionCode"))
                            OwnedStorageNative.retireSaveDirectory(parent, leaf, expected("expected"))
                            JSONObject()
                        }
                        "names" -> {
                            if (companions != null) {
                                val names = companions.filter { path -> try {
                                    val folder = companionParent(path)
                                    try { OwnedStorageNative.entryIdentity(folder, path.substringAfterLast('/')); true }
                                    finally { OwnedStorageNative.close(folder) }
                                } catch (error: IOException) { if (error.message != "owned_storage:2") throw error; false } }.sorted()
                                reply(JSONObject().put("count", names.size)); names.forEach(output::writeUTF); output.flush(); continue
                            }
                            val names = File(backing).list() ?: throw IOException("owned_storage:13")
                            require(names.size <= 4096)
                            // A complete group must not lose an unexpected member
                            // through a filename filter. Opening each member below
                            // rejects nested directories, links and special files.
                            if (savedata) require(names.size <= PpssppSavedataBoundary.MAX_MEMBERS && names.all(validName))
                            val selected = if (savedataParent) names.filter { leaf ->
                                if (PpssppSavedataBoundary.validStage(leaf)) return@filter false
                                require(validName(leaf))
                                val status = Os.lstat("$backing/$leaf")
                                require(!android.system.OsConstants.S_ISLNK(status.st_mode))
                                if (!android.system.OsConstants.S_ISDIR(status.st_mode)) false else {
                                    val directory = OwnedStorageNative.openDirectory(parent, leaf, false)
                                    OwnedStorageNative.close(directory); true
                                }
                            }.sorted() else names.filter(validName).sorted()
                            val fresh = OwnedStorageNative.openRoot(backing)
                            try {
                                if (OwnedStorageNative.identity(parent).take(2) != OwnedStorageNative.identity(fresh).take(2))
                                    throw IOException("source_changed")
                            } finally { OwnedStorageNative.close(fresh) }
                            reply(JSONObject().put("count", selected.size))
                            selected.forEach(output::writeUTF); output.flush()
                            continue
                        }
                        "identity" -> identity(OwnedStorageNative.identity(fd(row)))
                        "currentRoot" -> {
                            verifyPcsxSettings()
                            val fresh = OwnedStorageNative.openRoot(backing)
                            try { identity(OwnedStorageNative.identity(fresh)) } finally { OwnedStorageNative.close(fresh) }
                        }
                        "entry" -> {
                            val leaf = row.getString("name")
                            require(validName(leaf) || validStage(leaf))
                            if (companions == null) identity(OwnedStorageNative.entryIdentity(parent, leaf)) else {
                                val folder = companionParent(leaf, stage = validStage(leaf))
                                try { identity(OwnedStorageNative.entryIdentity(folder, leaf.substringAfterLast('/'))) }
                                finally { OwnedStorageNative.close(folder) }
                            }
                        }
                        "open" -> {
                            require(files.size < 5)
                            val create = row.getBoolean("create")
                            val write = row.getBoolean("writable")
                            require(companions == null || companionRestore != null || !create && !write)
                            require(pcsx == null || pcsxRestoreId != null || (!create && !write))
                            if (pcsx != null && (create || write)) verifyPcsxSettings()
                            val leaf = name(row, stage = write || create)
                            val folder = if (companions == null) parent else companionParent(leaf, stage = write || create)
                            val opened = try { OwnedStorageNative.openFile(folder, leaf.substringAfterLast('/'), create, write) }
                                catch (failure: Exception) { if (companions != null) OwnedStorageNative.close(folder); throw failure }
                            val handle = next++
                            files[handle] = opened
                            if (write) writable.add(handle)
                            if (create) {
                                val before = OwnedStorageNative.identity(opened)
                                val owner = if (companions == null) Os.stat(backing) else
                                    ParcelFileDescriptor.fromFd(folder).use { Os.fstat(it.fileDescriptor) }
                                if (before[0] != owner.st_dev ||
                                    OwnedStorageNative.identity(folder).take(2) != listOf(owner.st_dev, owner.st_ino))
                                    throw IOException("source_changed")
                                // The emulator, not root/R-Shop, owns its staged
                                // replacement. lchown never follows a substituted link.
                                if (companions == null) Os.lchown("$backing/$leaf", owner.st_uid, owner.st_gid)
                                else ParcelFileDescriptor.fromFd(opened).use { Os.fchown(it.fileDescriptor, owner.st_uid, owner.st_gid) }
                                if (!before.contentEquals(OwnedStorageNative.identity(opened)) ||
                                    !before.contentEquals(OwnedStorageNative.entryIdentity(folder, leaf.substringAfterLast('/'))))
                                    throw IOException("source_changed")
                            }
                            if (companions != null) OwnedStorageNative.close(folder)
                            JSONObject().put("fd", handle)
                        }
                        "read" -> {
                            val length = row.getInt("length")
                            val offset = row.getLong("offset")
                            require(length in 1..65536 && offset in 0..maxBytes && offset + length <= maxBytes)
                            val bytes = OwnedStorageNative.read(fd(row), offset, length)
                            reply(JSONObject().put("length", bytes.size))
                            output.write(bytes); output.flush()
                            continue
                        }
                        "write" -> {
                            require(row.getInt("fd") in writable)
                            val length = row.getInt("length")
                            val offset = row.getLong("offset")
                            require(length in 1..65536 && offset in 0..maxBytes && offset + length <= maxBytes)
                            val bytes = ByteArray(length).also(input::readFully)
                            verifyPcsxSettings()
                            OwnedStorageNative.write(fd(row), offset, bytes)
                            JSONObject()
                        }
                        "sync" -> { OwnedStorageNative.sync(fd(row)); JSONObject() }
                        "rename" -> {
                            verifyPcsxPublication()
                            val target = name(row)
                            val folder = if (companions == null) parent else companionParent(target)
                            try {
                                OwnedStorageNative.renameNoReplace(folder, name(row, "stage", true), folder, target.substringAfterLast('/'))
                                if (companions != null) OwnedStorageNative.sync(folder)
                            } finally { if (companions != null) OwnedStorageNative.close(folder) }
                            JSONObject()
                        }
                        "replace" -> {
                            verifyPcsxPublication()
                            val target = name(row)
                            val folder = if (companions == null) parent else companionParent(target)
                            try {
                                identity(OwnedStorageNative.replaceReviewedSave(folder, name(row, "stage", true), target.substringAfterLast('/'),
                                    expected("staged"), expected("current"))).also { if (companions != null) OwnedStorageNative.sync(folder) }
                            } finally { if (companions != null) OwnedStorageNative.close(folder) }
                        }
                        "close" -> {
                            val handle = row.getInt("fd"); require(handle != 1)
                            OwnedStorageNative.close(fd(row)); files.remove(handle); writable.remove(handle)
                            groups.remove(handle); writableGroups.remove(handle)
                            JSONObject()
                        }
                        else -> throw IOException("root_unavailable")
                    }
                    reply(result)
                } catch (error: Exception) {
                    val message = (error as? IOException)?.message
                    // exists() deliberately uses entry/ENOENT to represent an
                    // absent first save. That observation is not a failed
                    // snapshot. The armed kernel guard still rejects creation,
                    // removal, replacement and writes before verification.
                    val absentEntry = message == "owned_storage:2" && (row.optString("operation") == "entry" ||
                        (savedataParent && row.optString("operation") in setOf("groupOpen", "groupFile") &&
                            !row.optBoolean("create")))
                    if (snapshot >= 0 && !absentEntry) snapshotInvalid = true
                    reply(JSONObject().put("error", if (message in setOf("source_changed", "emulator_running", "save_settings_unresolved") ||
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
            companionGuards.forEach { runCatching { OwnedStorageNative.close(it.third) } }
            if (clockSnapshot >= 0) runCatching { OwnedStorageNative.close(clockSnapshot) }
            if (snapshot >= 0) runCatching { OwnedStorageNative.close(snapshot) }
            files.values.forEach { runCatching { OwnedStorageNative.close(it) } }
        }
    }
}
