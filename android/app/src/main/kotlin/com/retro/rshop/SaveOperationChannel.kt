package com.retro.rshop

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal object SaveOperationChannel {
    private val gate = SaveOperationGate()
    fun attach(messenger: BinaryMessenger, owner: String): MethodChannel =
        MethodChannel(messenger, "com.darkaxt.gshop/save_operation").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val id = call.argument<String>("id").orEmpty()
                if (!id.matches(Regex("[a-f0-9]{32}"))) {
                    result.error("invalid_operation", "Invalid save operation", null)
                } else try {
                    when (call.method) {
                        "acquire" -> {
                            val migration = call.argument<Boolean>("migration") == true
                            if (MigrationChannel.busy && !migration) {
                                result.error("migration_in_progress", "Migration in progress", null)
                            } else gate.acquire(owner, id) { granted ->
                                if (granted && MigrationChannel.busy && !migration) {
                                    gate.release(owner, id)
                                    result.error("migration_in_progress", "Migration in progress", null)
                                } else if (granted) result.success(null)
                                else result.error("cancelled", "Save operation cancelled", null)
                            }
                        }
                        "release" -> result.success(gate.release(owner, id))
                        "cancel" -> result.success(gate.cancel(owner, id))
                        else -> result.notImplemented()
                    }
                } catch (_: IllegalArgumentException) {
                    result.error("invalid_operation", "Duplicate or excessive save operation", null)
                }
            }
        }
    fun detach(owner: String) = gate.detach(owner)
}
