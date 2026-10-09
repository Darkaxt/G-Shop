package com.retro.rshop

import android.content.Context

/** App-UID Android boundary proof: no ROMs, files, preferences or app launches. */
internal object CompanionProof {
    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val apps = CompanionLauncher.applications(context)
        check(apps.isNotEmpty())
        val emulator = context.packageManager.getLaunchIntentForPackage("com.retroarch.aarch64")
            ?: error("Installed emulator required")
        val companion = apps.firstOrNull {
            it["component"]?.startsWith("com.retroarch.aarch64/") == false
        } ?: error("Independent installed companion required")
        fun rejected(code: String, action: () -> Unit) {
            try { action() } catch (error: CompanionLaunchFailure) {
                check(error.code == code) { "Wrong failure ${error.code}" }
                return
            }
            error("Accepted $code")
        }
        rejected("companion_missing") {
            CompanionLauncher.prepare(context, "com.rshop.nonexistent/.Absent", emulator)
        }
        rejected("companion_unlaunchable") {
            CompanionLauncher.prepare(context, "${context.packageName}/com.retro.rshop.MainActivity", emulator)
        }
        val pair = CompanionLauncher.prepare(context, companion.getValue("component"), emulator)
        check(pair.top != pair.bottom)
        // Invalid display rejection occurs before any companion/emulator can start.
        rejected("companion_launch_denied") {
            CompanionLauncher.launch(context,
                CompanionLauncher.Plan(pair.top, Int.MAX_VALUE, pair.companion), emulator)
        }
        return "PASS app-UID installed app enumeration; exact preflight top=${pair.top} bottom=${pair.bottom}; missing/unlaunchable companion and rejected placement; no activities started"
    }
}
