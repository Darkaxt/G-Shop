package com.retro.rshop

import org.json.JSONArray
import org.json.JSONObject

/** Exact opt-in game selection, consumed by the existing root IO/watch lane. */
internal data class SaveRootConfiguration(val directory: String, val emulator: String,
    val core: String, val kind: String, val format: String, val files: List<String>,
    val folders: List<String>, val required: List<String>) {
    companion object {
        fun decode(row: JSONObject): SaveRootConfiguration {
            require(row.keys().asSequence().toSet() == setOf("schema", "directory", "emulator", "core",
                "kind", "format", "files", "folders", "required") && row.getInt("schema") == 1)
            val emulator = row.getString("emulator")
            require(emulator.matches(Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+")))
            val directory = row.getString("directory")
            require(validDirectory(directory, emulator))
            val core = row.getString("core"); val format = row.getString("format"); val kind = row.getString("kind")
            require(core.matches(Regex("[A-Za-z0-9_-]{1,128}")) && format.matches(Regex("[A-Za-z0-9_-]{1,128}")) &&
                kind in setOf("save", "state", "companion") && row.toString().toByteArray().size <= 32768)
            fun paths(key: String, binary: Boolean = false): List<String> {
                val list = row.getJSONArray(key)
                require(list.length() <= 128)
                return (0 until list.length()).map(list::getString).also {
                    require(it.toSet().size == it.size && it.all { path -> safe(path, binary) })
                }
            }
            val files = paths("files", true); val folders = paths("folders"); val required = paths("required", true)
            require(files.size + folders.size in 1..128 && files.containsAll(required))
            return SaveRootConfiguration(directory, emulator, core, kind, format, files, folders, required)
        }
        fun validDirectory(path: String, emulator: String): Boolean = path.length <= 4096 &&
            (RomCompanionBoundary.validDirectory(path) ||
                listOf("/data/user/0/$emulator/files/", "/data/data/$emulator/files/").any {
                    path.startsWith(it) && path.length > it.length
                } && path.split('/').drop(1).all(RomCompanionBoundary::validLeaf))
        private fun safe(path: String, binary: Boolean = false): Boolean = RomCompanionBoundary.validPath(path) &&
            path.split('/').all { part ->
                val leaf = if (binary && part.endsWith(".bin", true)) part.dropLast(4) + ".sav" else part
                RomCompanionBoundary.associated("scope.rom", "scope.$leaf")
            }
    }
    fun acceptsFile(path: String): Boolean = safe(path, path in files) &&
        (path in files || folders.any { path.startsWith("$it/") })
    fun acceptsDirectory(path: String): Boolean = safe(path) &&
        (folders.any { it == path || it.startsWith("$path/") || path.startsWith("$it/") } ||
            files.any { it.startsWith("$path/") })
    fun completeGroup(present: Set<String>): Boolean = present.isEmpty() || present.containsAll(required)
    fun json(): JSONObject = JSONObject().put("schema", 1).put("directory", directory).put("emulator", emulator)
        .put("core", core).put("kind", kind).put("format", format).put("files", JSONArray(files))
        .put("folders", JSONArray(folders)).put("required", JSONArray(required))
}
