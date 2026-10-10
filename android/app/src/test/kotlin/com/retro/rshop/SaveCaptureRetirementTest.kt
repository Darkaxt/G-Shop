package com.retro.rshop

import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import org.junit.Assert.*
import org.junit.Test

class SaveCaptureRetirementTest {
    private val id = "a".repeat(32)

    @Test fun reviewsOnlyTheExactCaptureWithSealLastAndAllowsInterruptedRetirement() {
        val temp = Files.createTempDirectory(Paths.get("D:/Temp"), "rshop-retire-").toFile()
        val root = File(temp, "save-captures").apply { mkdir() }
        val capture = File(root, id).apply { mkdir() }
        val other = File(root, "b".repeat(32)).apply { mkdir() }
        val members = listOf("member-0", "member-1", "capture.json")
        try {
            members.forEach { File(capture, it).writeText("fixture") }
            val reviewed = SaveCaptureRetirement.review(root, id)
            assertEquals(members, reviewed.map { it.name })
            assertTrue(reviewed.first().delete()) // interruption after one exact unlink
            assertEquals(members.drop(1), SaveCaptureRetirement.review(root, id).map { it.name })
            SaveCaptureRetirement.review(root, id).forEach { assertTrue(it.delete()) }
            assertTrue(capture.delete())
            assertTrue(SaveCaptureRetirement.review(root, id).isEmpty())
            assertTrue(other.isDirectory)
        } finally {
            members.forEach { File(capture, it).delete() }
            capture.delete(); other.delete(); root.delete(); temp.delete()
        }
    }

    @Test fun unexpectedEntriesAndCallerPathsAreRejectedBeforeAnyDeletion() {
        val temp = Files.createTempDirectory(Paths.get("D:/Temp"), "rshop-retire-").toFile()
        val root = File(temp, "save-captures").apply { mkdir() }
        val capture = File(root, id).apply { mkdir() }
        val member = File(capture, "member-0").apply { writeText("fixture") }
        val unexpected = File(capture, "user-file").apply { writeText("preserve") }
        try {
            for (bad in listOf("../$id", "$id/member-0", "", "A".repeat(32))) {
                assertThrows(IllegalArgumentException::class.java) {
                    SaveCaptureRetirement.review(root, bad)
                }
            }
            assertThrows(IllegalArgumentException::class.java) {
                SaveCaptureRetirement.review(root, id)
            }
            assertEquals("fixture", member.readText())
            assertEquals("preserve", unexpected.readText())
            assertTrue(unexpected.delete())
            assertTrue(File(capture, "member-1").mkdir())
            assertThrows(IllegalArgumentException::class.java) {
                SaveCaptureRetirement.review(root, id)
            }
            assertTrue(File(capture, "member-1").delete())
        } finally {
            member.delete(); unexpected.delete(); capture.delete(); root.delete(); temp.delete()
        }
    }
}
