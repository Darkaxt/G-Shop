package com.retro.rshop

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.google.android.gms.auth.GoogleAuthUtil
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Same silent cache invalidation in UI and headless engines; no account UI. */
internal object DriveTokenCacheChannel {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun attach(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.retro.rshop/drive_authorization")
            .setMethodCallHandler { call, result ->
                if (call.method != "clearTokenIfMicroG") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val token = call.argument<String>("token")
                if (token.isNullOrBlank()) {
                    result.error("invalid_arguments", "Missing token", null)
                    return@setMethodCallHandler
                }
                val microG = try {
                    context.packageManager.getServiceInfo(ComponentName("com.google.android.gms",
                        "org.microg.gms.auth.credentials.identity.AuthorizationService"), 0)
                    true
                } catch (_: PackageManager.NameNotFoundException) { false }
                if (!microG) result.success(false)
                else worker.execute {
                    try {
                        @Suppress("DEPRECATION")
                        GoogleAuthUtil.clearToken(context.applicationContext, token)
                        main.post { result.success(true) }
                    } catch (_: Exception) {
                        main.post { result.error("unavailable", "Token cache clear failed", null) }
                    }
                }
            }
    }
}
