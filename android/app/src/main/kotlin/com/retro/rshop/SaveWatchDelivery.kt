package com.retro.rshop

/** Platform-thread admission only. At most one unacknowledged event per mapped
 * save plus one dirty bit; acknowledgement means Dart durably queued the work,
 * never that a network upload finished. No timer or retry deadline. */
internal class SaveWatchDelivery(private val current: () -> Boolean,
    private val send: (String, () -> Unit, () -> Unit) -> Unit,
    private val reportUnavailable: () -> Unit) {
    private var ready = false
    private var lost = false
    private var reported = false
    private val inFlight = mutableSetOf<String>()
    private val dirty = linkedSetOf<String>()

    fun changed(key: String) {
        if (!current() || lost) return
        if (!ready || key in inFlight) { dirty.add(key); return }
        inFlight.add(key)
        send(key, {
            inFlight.remove(key)
            if (dirty.remove(key)) changed(key)
        }, { unavailable() })
    }

    fun unavailable() {
        lost = true
        dirty.clear()
        if (ready && current() && !reported) {
            reported = true
            reportUnavailable()
        }
    }

    fun admitted() {
        ready = true
        if (lost) { unavailable(); return }
        val pending = dirty.toList()
        dirty.clear()
        pending.forEach(::changed)
    }
}
