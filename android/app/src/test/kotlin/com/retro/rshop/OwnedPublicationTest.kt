package com.retro.rshop

import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class OwnedPublicationTest {
    @Test fun syncFailureCanRetryWithoutRenamingAgain() {
        val state = OwnedPublication()
        var renames = 0
        var syncs = 0
        try {
            state.publish({ renames++ }, { syncs++; throw IOException("fixture") })
            fail("sync failure cannot be successful publication")
        } catch (_: IOException) {}
        assertTrue(state.renamed)
        state.publish({ renames++ }, { syncs++ })
        assertEquals(1, renames)
        assertEquals(2, syncs)
    }

    @Test fun failedPublicationCheckpointRetriesAndPropagatesSyncFailure() {
        val state = OwnedPublication()
        try { state.publish({}, { throw IOException("fixture") }) } catch (_: IOException) {}
        val events = mutableListOf<String>()
        try {
            state.checkpoint({ events.add("file") }, { events.add("parents"); throw IOException("fixture") })
            fail("checkpoint cannot skip an unconfirmed parent sync")
        } catch (_: IOException) {}
        assertEquals(listOf("file", "parents"), events)
        state.checkpoint({ events.add("file") }, { events.add("parents") })
        assertEquals(listOf("file", "parents", "file", "parents"), events)
    }

    @Test fun publishedRecoveryStillEstablishesDurability() {
        val state = OwnedPublication(renamed = true)
        val events = mutableListOf<String>()
        state.checkpoint({ events.add("file") }, { events.add("parents") })
        assertEquals(listOf("file", "parents"), events)
    }

    @Test fun failedRenameDoesNotAdvanceNamespaceState() {
        val state = OwnedPublication()
        var syncs = 0
        try {
            state.publish({ throw IOException("collision") }, { syncs++ })
            fail("rename failure must propagate")
        } catch (_: IOException) {}
        assertFalse(state.renamed)
        assertEquals(0, syncs)
    }

    @Test fun stagedCheckpointDoesNotClaimOrSyncPublication() {
        val state = OwnedPublication()
        val events = mutableListOf<String>()
        state.checkpoint({ events.add("file") }, { events.add("parents") })
        assertEquals(listOf("file"), events)
        assertFalse(state.renamed)
    }
}
