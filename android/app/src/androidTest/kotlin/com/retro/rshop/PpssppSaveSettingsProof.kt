package com.retro.rshop

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch

/** App-UID/root discovery only. Never rewrites a Memory Stick selection or save. */
internal object PpssppSaveSettingsProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        check(PpssppSaveSettings.configuredDirectory(
            "content://com.android.externalstorage.documents/tree/primary%3APSP/document/primary%3APSP") ==
            "/storage/emulated/0/PSP/PPSSPP_STATE")
        val service = SaveCaptureService(context)
        val done = CountDownLatch(1)
        var result: Any? = null
        var failure: String? = null
        try {
            service.handle(MethodCall("ppssppSaveSettings", null), object : MethodChannel.Result {
                override fun success(value: Any?) { result = value; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                override fun notImplemented() { failure = "not_implemented"; done.countDown() }
            })
            done.await()
            check(failure == null) { failure ?: "settings_missing" }
            val row = result as Map<*, *>
            check(row.keys == setOf("directory"))
            val configured = SaveSourceStorage.ppssppSettings(context).getString("directory")
            check(row["directory"] == configured && PpssppSaveBoundary.validDirectory(configured))
            val listed = CountDownLatch(1)
            var names: Any? = null
            service.handle(MethodCall("ppssppNames", mapOf("directory" to configured)), object : MethodChannel.Result {
                override fun success(value: Any?) { names = value; listed.countDown() }
                override fun error(code: String, message: String?, details: Any?) { failure = code; listed.countDown() }
                override fun notImplemented() { failure = "not_implemented"; listed.countDown() }
            })
            listed.await(); check(failure == null) { failure ?: "listing_missing" }
            check((names as List<*>).all { it is String && PpssppSaveBoundary.validName(it) })
        } finally {
            val closed = CountDownLatch(1)
            service.shutdown { closed.countDown() }; closed.await()
        }
        return "PASS read-only app-UID/root PPSSPP configured state-folder discovery and listing; normal channel matches installed Memory Stick setting, no settings/save/ROM/cloud mutation"
    }
}
