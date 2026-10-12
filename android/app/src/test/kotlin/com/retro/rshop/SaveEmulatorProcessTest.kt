package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class SaveEmulatorProcessTest {
    private val command = "org.ppsspp.ppsspp\u0000".toByteArray()
    private val closedThreads = listOf("androidInit", "binder:123_1", "RecentISOThread", "HeapTaskDaemon")
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

    @Test fun normalPpssppExitAllowsItsCachedAndroidProcess() {
        for (state in listOf("18 (CACHED_RECENT)", "19 (CACHED_EMPTY)")) {
            assertTrue(SaveEmulatorProcess.cachedPpssppClosed(120040000, command, state, closedThreads))
        }
    }

    @Test fun backgroundingOrLiveNativeWorkersAreNotShutdownEvidence() {
        for (state in listOf("2 (TOP)", "12 (TOP_SLEEPING)", "15 (LAST_ACTIVITY)",
                "16 (CACHED_ACTIVITY)", "17 (CACHED_ACTIVITY_CLIENT)", "20 (NONEXISTENT)")) {
            assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120040000, command, state, closedThreads))
        }
        for (thread in listOf("PoolW 0", "PoolW IO 15", "EmuThread", "VulkanRenderMan", "ShaderCompile")) {
            assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120040000, command,
                "18 (CACHED_RECENT)", closedThreads + thread))
        }
    }

    @Test fun unrelatedUidProcessesAndUnreviewedRuntimesCannotUseTheCachedException() {
        for (name in listOf("cat\u0000", "org.ppsspp.ppsspp:worker\u0000", "org.ppsspp.ppsspp", "")) {
            assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120040000, name.toByteArray(),
                "18 (CACHED_RECENT)", closedThreads))
        }
        assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120050000, command, "18 (CACHED_RECENT)", closedThreads))
        assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120040000, command, "18 (CACHED_RECENT)", emptyList()))
        for (state in listOf("", "18 (TOP)", "18 (CACHED_RECENT)\n2 (TOP)")) {
            assertFalse(SaveEmulatorProcess.cachedPpssppClosed(120040000, command, state, closedThreads))
        }
    }
}
