package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class SaveOperationGateTest {
    @Test fun enginesQueueUntilExactOwnerReleases() {
        val gate = SaveOperationGate()
        val events = mutableListOf<String>()
        gate.acquire("ui", "one") { events.add("one:$it") }
        gate.acquire("background", "two") { events.add("two:$it") }
        assertEquals(listOf("one:true"), events)
        assertFalse(gate.release("background", "one"))
        assertEquals(listOf("one:true"), events)
        assertTrue(gate.release("ui", "one"))
        assertEquals(listOf("one:true", "two:true"), events)
        assertTrue(gate.release("background", "two"))
    }

    @Test fun cancelledWaiterNeverAcquiresAndOwnerExitUnblocksNextEngine() {
        val gate = SaveOperationGate()
        val events = mutableListOf<String>()
        gate.acquire("ui", "one") { events.add("one:$it") }
        gate.acquire("background", "two") { events.add("two:$it") }
        gate.acquire("next", "three") { events.add("three:$it") }
        assertTrue(gate.cancel("background", "two"))
        assertFalse(gate.cancel("background", "one"))
        assertEquals(listOf("one:true", "two:false"), events)
        gate.detach("ui")
        assertEquals(listOf("one:true", "two:false", "three:true"), events)
        assertFalse(gate.release("ui", "one"))
    }

    @Test fun detachRemovesOnlyItsWaitersAndDuplicateRequestsAreRejected() {
        val gate = SaveOperationGate()
        val events = mutableListOf<String>()
        gate.acquire("first", "one") { events.add("one:$it") }
        gate.acquire("second", "two") { events.add("two:$it") }
        assertThrows(IllegalArgumentException::class.java) {
            gate.acquire("second", "two") { error("duplicate") }
        }
        gate.detach("second")
        assertEquals(listOf("one:true", "two:false"), events)
        assertTrue(gate.release("first", "one"))
    }
}
