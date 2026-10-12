package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch

/** Read-only settings discovery through the actual app UID/root channel.
 * Parser cases stay in memory; no settings/save/cloud/ROM mutation. */
internal object MelonSaveSettingsProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        fun parse(xml: String) = MelonSaveSettings.parse(xml.toByteArray(Charsets.UTF_8))
        val custom = "content://com.android.externalstorage.documents/tree/primary%3ASaves%2FDS"
        val selected = parse("<map><boolean name=\"use_rom_dir\" value=\"false\"/>" +
            "<boolean name=\"save_file_use_srm_extension\" value=\"true\"/>" +
            "<set name=\"sram_dir\"><string>$custom</string></set></map>")
        check(selected.getString("mode") == "custom" && selected.getString("extension") == "srm" &&
            selected.getString("directory") == "/storage/emulated/0/Saves/DS")
        val stale = parse("<map><set name=\"sram_dir\"><string>$custom</string></set></map>")
        check(stale.getString("mode") == "rom" && stale.isNull("directory") && stale.getString("extension") == "sav")
        for (xml in listOf(
            "<!DOCTYPE map [<!ENTITY x SYSTEM 'file:///rshop-must-not-read'>]><map>&x;</map>",
            "<map><boolean name=\"use_rom_dir\" value=\"false\"/><boolean name=\"use_rom_dir\" value=\"true\"/></map>",
            "<map><string name=\"use_rom_dir\">false</string></map>",
            "<map><boolean name=\"use_rom_dir\" value=\"false\"/><set name=\"sram_dir\"><string>$custom</string><string>$custom</string></set></map>",
            "<map><boolean name=\"use_rom_dir\" value=\"false\"/><set name=\"sram_dir\"><string>content://other.provider/tree/private</string></set></map>")) {
            check(runCatching { parse(xml) }.isFailure)
        }
        val service = SaveCaptureService(context)
        val done = CountDownLatch(1)
        var result: Any? = null
        var failure: String? = null
        try {
            service.handle(MethodCall("melonSaveSettings", null), object : MethodChannel.Result {
                override fun success(value: Any?) { result = value; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await()
            check(failure == null) { failure ?: "settings_missing" }
            val row = result as Map<*, *>
            check(row.keys == setOf("mode", "directory", "extension"))
            val direct = SaveSourceStorage.melonSettings(context)
            check(row["mode"] == direct.getString("mode") && row["extension"] == direct.getString("extension"))
            check(row["directory"] == if (direct.isNull("directory")) null else direct.getString("directory"))
        } finally {
            val closed = CountDownLatch(1)
            service.shutdown { closed.countDown() }; closed.await()
        }
        return "PASS app-UID/root Melon settings discovery: configured custom-tree resolution, ROM-relative/stale-custom separation, extension/default policy, duplicate/type/DTD/ambiguous-tree rejection, normal capture-channel result matches live settings; read-only, no private settings export/save/ROM/cloud mutation"
    }
}
