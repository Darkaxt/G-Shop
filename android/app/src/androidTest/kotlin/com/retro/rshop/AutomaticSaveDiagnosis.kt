package com.retro.rshop

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Read-only installed-state diagnosis. Reports predicates, never private IDs. */
object AutomaticSaveDiagnosis {
    fun observe(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val config = File(context.dataDir, "app_flutter/config.json")
        check(config.length() <= 1048576)
        val sources = JSONObject(config.readText()).getJSONArray("sources")
        val result = JSONArray()
        SQLiteDatabase.openDatabase(context.getDatabasePath("rshop.db").path, null,
            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
            check(db.isReadOnly)
            db.rawQuery("SELECT record_json,enabled,requested,handled,outcome,issue FROM automatic_save_backups WHERE enabled=1 LIMIT 4097", null).use { rows ->
                check(rows.count <= 4096)
                while (rows.moveToNext()) {
                    check(rows.getString(0).length <= 16384)
                    val mapping = JSONObject(rows.getString(0))
                    if (mapping.optString("route") != "retroarch") continue
                    val artifact = mapping.getJSONObject("artifact")
                    val client = mapping.getString("clientId")
                    val account = mapping.getString("accountId")
                    val artifactKey = JSONArray().put(artifact.getString("providerId"))
                        .put(artifact.getString("sourceId")).put(artifact.opt("accountId"))
                        .put(artifact.getString("providerFileId")).toString()
                    val key = JSONArray().put(client).put(account).put(mapping.getString("editionId"))
                        .put(artifactKey).put(mapping.getString("platform")).toString()
                    val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
                        .joinToString("") { "%02x".format(it.toInt() and 255) }
                    val slotKey = "flutter.save_retroarch_mapping_v1_$digest"
                    val slot = JSONObject(prefs.getString(slotKey, "{}")!!)
                    val configured = (0 until sources.length()).any { i ->
                        val source = sources.getJSONObject(i)
                        val drive = source.optJSONObject("drive")
                        drive != null && source.optBoolean("enabled", true) &&
                            source.optString("id") == artifact.getString("sourceId") &&
                            drive.optString("account_id") == account &&
                            drive.optString("server_client_id") == client
                    }
                    val area = prefs.all.entries.filter { it.key.startsWith("flutter.rshop_save_backup_area_v1:") }
                        .mapNotNull { (it.value as? String)?.let(::JSONObject) }
                        .any { it.optString("areaId") == mapping.getString("areaId") && it.optBoolean("ready") }
                    val observation = JSONObject().put("platform", mapping.getString("platform"))
                        .put("enabled", rows.getInt(1)).put("requested", rows.getLong(2)).put("handled", rows.getLong(3))
                        .put("outcome", if (rows.isNull(4)) JSONObject.NULL else rows.getString(4))
                        .put("issue", if (rows.isNull(5)) JSONObject.NULL else rows.getString(5))
                        .put("configured", configured).put("areaReady", area).put("slotPresent", prefs.contains(slotKey))
                        .put("directoryMatches", slot.optString("directory") == mapping.getString("directory"))
                        .put("nameMatches", slot.optString("name") == mapping.getString("slot"))
                    if (mapping.getString("platform") == "n64") {
                        val jobIdentity = JSONArray().put(client).put(account).put(mapping.getString("areaId"))
                            .put(mapping.getString("editionId")).put("n64-battery").toString()
                        val jobKey = MessageDigest.getInstance("SHA-256").digest(jobIdentity.toByteArray())
                            .joinToString("") { "%02x".format(it.toInt() and 255) }
                        db.rawQuery("SELECT record_json FROM save_backup_game_jobs WHERE job_key=? LIMIT 1", arrayOf(jobKey)).use { jobs ->
                            if (jobs.moveToFirst()) {
                                check(jobs.getString(0).length <= 3 * 1048576)
                                val job = JSONObject(jobs.getString(0))
                                val verified = job.optJSONObject("lastVerified")
                                val members = verified?.getJSONArray("members") ?: JSONArray()
                                val receipts = JSONArray()
                                for (i in 0 until members.length()) {
                                    val member = members.getJSONObject(i)
                                    receipts.put(JSONObject().put("sizeBytes", member.getLong("sizeBytes"))
                                        .put("sha256", member.getString("sha256")))
                                }
                                observation.put("jobState", job.getString("state"))
                                    .put("verifiedAt", verified?.getString("createdAt") ?: JSONObject.NULL)
                                    .put("members", receipts)
                            }
                        }
                    }
                    result.put(observation)
                }
            }
        }
        return JSONObject().put("readOnly", true).put("mappings", result).toString()
    }
}
