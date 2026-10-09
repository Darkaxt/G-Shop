package com.retro.rshop

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CompanionLauncherTest {
    @Test fun resolvesNonContiguousRuntimeIdsInsteadOfZeroOne() {
        assertEquals(7 to 42, CompanionLauncher.displayPair(listOf(
            CompanionLauncher.Target(42, false, true),
            CompanionLauncher.Target(7, true, false),
            CompanionLauncher.Target(1, false, false))))
    }

    @Test fun noSecondaryDisplayIsAnExplicitFailure() {
        val error = assertThrows(CompanionLaunchFailure::class.java) {
            CompanionLauncher.displayPair(listOf(CompanionLauncher.Target(7, true, false)))
        }
        assertEquals("companion_display_unavailable", error.code)
    }

    @Test fun multipleSecondaryDisplaysAreNotGuessed() {
        assertThrows(CompanionLaunchFailure::class.java) {
            CompanionLauncher.displayPair(listOf(
                CompanionLauncher.Target(7, true, false),
                CompanionLauncher.Target(42, false, true),
                CompanionLauncher.Target(88, false, true)))
        }
    }

    @Test fun noDefaultDisplayIsNotInferredFromListOrder() {
        assertThrows(CompanionLaunchFailure::class.java) {
            CompanionLauncher.displayPair(listOf(CompanionLauncher.Target(42, false, true)))
        }
    }
}
