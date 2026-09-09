package com.retro.rshop

/** Namespace mutation and durability are different events. A failed sync must
 * remain retryable without attempting a second rename or claiming a checkpoint. */
internal class OwnedPublication(renamed: Boolean = false) {
    var renamed = renamed
        private set

    fun publish(rename: () -> Unit, syncParents: () -> Unit) {
        if (!renamed) {
            rename()
            renamed = true
        }
        syncParents()
    }

    fun checkpoint(syncFile: () -> Unit, syncParents: () -> Unit) {
        syncFile()
        if (renamed) syncParents()
    }
}
