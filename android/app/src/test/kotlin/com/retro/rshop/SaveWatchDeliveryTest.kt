package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class SaveWatchDeliveryTest {
    @Test fun eventsWaitForRegistrationAndCoalesceUntilDurableAcknowledgement() {
        val sent = mutableListOf<String>()
        val acknowledgements = mutableListOf<() -> Unit>()
        var current = true
        var lost = 0
        val delivery = SaveWatchDelivery({ current }, { key, done, _ ->
            sent.add(key); acknowledgements.add(done)
        }, { lost++ })
        repeat(1000) { delivery.changed("a") }
        assertTrue(sent.isEmpty())
        delivery.admitted()
        assertEquals(listOf("a"), sent)
        repeat(1000) { delivery.changed("a") }
        assertEquals(listOf("a"), sent)
        acknowledgements[0]()
        assertEquals(listOf("a", "a"), sent)
        current = false
        acknowledgements[1]()
        delivery.changed("b")
        assertEquals(2, sent.size)
        assertEquals(0, lost)
    }

    @Test fun earlyRegistrationLossIsReportedAfterAdmissionAndStopsDelivery() {
        var lost = 0
        var sent = 0
        val delivery = SaveWatchDelivery({ true }, { _, _, _ -> sent++ }, { lost++ })
        delivery.changed("a")
        delivery.unavailable()
        assertEquals(0, lost)
        delivery.admitted()
        delivery.unavailable()
        delivery.changed("b")
        assertEquals(1, lost)
        assertEquals(0, sent)
    }
}
