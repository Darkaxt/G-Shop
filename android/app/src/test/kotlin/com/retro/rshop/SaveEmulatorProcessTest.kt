package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class SaveEmulatorProcessTest {
    private fun status(state: String = "S", ids: String = "10123 10123 10123 10123") =
        "Name:\tworker\nState:\t$state (state)\nUid:\t$ids\nThreads:\t2\n"

    @Test fun everyLiveEmulatorUidRoleBlocksRestore() {
        for (state in listOf("R", "S", "D", "T", "t", "I", "P")) {
            for (ids in listOf("10123 0 0 0", "0 10123 0 0", "0 0 10123 0", "0 0 0 10123")) {
                assertTrue(SaveEmulatorProcess.blocksRestore(status(state, ids), 10123))
            }
        }
        assertFalse(SaveEmulatorProcess.blocksRestore(status(), 10124))
    }

    @Test fun exitedProcessesCannotWriteAndDoNotRequireForceStop() {
        for (state in listOf("Z", "X", "x")) {
            assertFalse(SaveEmulatorProcess.blocksRestore(status(state), 10123))
        }
    }

    @Test fun missingOrAmbiguousCensusEvidenceIsNotTreatedAsAnExit() {
        for (raw in listOf("", "State:\tS\n", "Uid:\t10123 10123 10123 10123\n",
                status(ids = "10123 10123"), status(ids = "-1 0 0 0"),
                status() + "Uid:\t10124 10124 10124 10124\n",
                status() + "State:\tZ\n", status(state = "?"))) {
            try {
                SaveEmulatorProcess.blocksRestore(raw, 10123)
                fail("Accepted incomplete/ambiguous process evidence")
            } catch (_: IllegalArgumentException) {}
        }
    }
}
