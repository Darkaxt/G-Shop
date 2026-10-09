package com.retro.rshop

import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display

internal class CompanionLaunchFailure(val code: String) : Exception()

/** One explicit edition association; no file access, installation or task killing. */
internal object CompanionLauncher {
    data class Target(val id: Int, val isDefault: Boolean, val publicPresentation: Boolean)

    // Pure selection contract also exercises non-contiguous/changed display IDs.
    fun displayPair(targets: List<Target>): Pair<Int, Int> {
        val top = targets.singleOrNull { it.isDefault }
            ?: throw CompanionLaunchFailure("companion_display_unavailable")
        val bottom = targets.filter { it.id != top.id && it.publicPresentation }.singleOrNull()
            ?: throw CompanionLaunchFailure("companion_display_unavailable")
        return top.id to bottom.id
    }

    fun applications(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        return pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .filter { it.activityInfo.exported && it.activityInfo.enabled &&
                it.activityInfo.applicationInfo.enabled && it.activityInfo.packageName != context.packageName }
            .map { mapOf("component" to ComponentName(it.activityInfo.packageName, it.activityInfo.name).flattenToShortString(),
                "label" to it.loadLabel(pm).toString()) }
            .distinctBy { it["component"] }
            .sortedWith(compareBy({ it["label"]?.lowercase(java.util.Locale.ROOT) }, { it["component"] }))
    }

    data class Plan(val top: Int, val bottom: Int, val companion: Intent)

    fun prepare(context: Context, component: String, emulator: Intent): Plan {
        if (Build.VERSION.SDK_INT < 29 ||
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_ACTIVITIES_ON_SECONDARY_DISPLAYS)) {
            throw CompanionLaunchFailure("companion_display_unavailable")
        }
        val selected = ComponentName.unflattenFromString(component)
            ?: throw CompanionLaunchFailure("companion_unlaunchable")
        if (selected.packageName == emulator.component?.packageName || selected.packageName == context.packageName) {
            throw CompanionLaunchFailure("companion_unlaunchable")
        }
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(selected).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        val pm = context.packageManager
        val info = try {
            @Suppress("DEPRECATION")
            pm.getActivityInfo(selected, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            throw CompanionLaunchFailure("companion_missing")
        }
        @Suppress("DEPRECATION")
        if (!info.exported || !info.enabled || !info.applicationInfo.enabled ||
            pm.queryIntentActivities(intent, 0).none { it.activityInfo.name == selected.className &&
                it.activityInfo.packageName == selected.packageName }) {
            throw CompanionLaunchFailure("companion_unlaunchable")
        }
        val manager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val default = manager.getDisplay(Display.DEFAULT_DISPLAY)
            ?: throw CompanionLaunchFailure("companion_display_unavailable")
        val (top, bottom) = displayPair(manager.displays.filter { it.isValid }.map {
            Target(it.displayId, it.displayId == default.displayId,
                it.flags and Display.FLAG_PRESENTATION != 0 && it.flags and Display.FLAG_PRIVATE == 0)
        })
        val activities = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (!activities.isActivityStartAllowedOnDisplay(context, top, emulator) ||
            !activities.isActivityStartAllowedOnDisplay(context, bottom, intent)) {
            throw CompanionLaunchFailure("companion_display_denied")
        }
        return Plan(top, bottom, intent)
    }

    fun launch(context: Context, plan: Plan, emulator: Intent) {
        try {
            context.startActivity(plan.companion,
                ActivityOptions.makeBasic().setLaunchDisplayId(plan.bottom).toBundle())
        } catch (_: Exception) {
            throw CompanionLaunchFailure("companion_launch_denied")
        }
        try {
            context.startActivity(emulator,
                ActivityOptions.makeBasic().setLaunchDisplayId(plan.top).toBundle())
        } catch (_: Exception) {
            // Do not kill the companion to simulate rollback. Report partial acceptance.
            throw CompanionLaunchFailure("emulator_launch_denied_after_companion")
        }
        // Acceptance of both intents is not proof that either application booted.
    }
}
