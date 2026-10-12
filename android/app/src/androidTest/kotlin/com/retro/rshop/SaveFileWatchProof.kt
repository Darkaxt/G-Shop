package com.retro.rshop

import android.content.Context
import android.system.Os
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** Actual Android file events in an exclusive fixture; no account, emulator,
 * user save, configuration, ROM or cloud operation. */
internal object SaveFileWatchProof {
    fun retroArch(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val suffix = UUID.randomUUID().toString()
        val mappings = listOf("gba", "n64", "nes", "snes").mapIndexed { index, platform ->
            SaveFileWatch.Mapping(listOf("d", "e", "f", "a")[index].repeat(64),
                RetroArchSaveBoundary.saveDirectory(platform)!!,
                "rshop-watch-$suffix.srm", "retroarch-$platform")
        }
        val initial = mappings.associate { it.directory to File(it.directory).list()!!.toSet() }
        val delivered = CountDownLatch(mappings.size)
        val events = linkedSetOf<String>()
        val watch = SaveFileWatch { key ->
            synchronized(events) { if (events.add(key)) delivered.countDown() }
        }
        val owned = mutableListOf<File>()
        fun allocate(file: File): File {
            check(file.canonicalFile == file.absoluteFile && file.createNewFile())
            owned.add(file)
            return file
        }
        try {
            val publications = mappings.map { mapping ->
                // Only the mapped GBA/SNES clock leaf or N64/NES SRM should deliver.
                val leaf = if (RetroArchSaveBoundary.includesRtc(mapping.route.removePrefix("retroarch-")))
                    mapping.name.dropLast(4) + ".rtc" else mapping.name
                val target = allocate(File(mapping.directory, leaf))
                val unrelated = allocate(File(mapping.directory, "rshop-other-$suffix.srm"))
                val temporary = allocate(File(mapping.directory, "$leaf.tmp"))
                Triple(target, unrelated, temporary)
            }
            // Initial exclusive allocation precedes registration, so a target's
            // creation/close cannot masquerade as the rename under test.
            check(watch.replace(mappings).toSet() == mappings.map { it.key }.toSet())
            for ((target, unrelated, temporary) in publications) {
                FileOutputStream(unrelated).use { it.write(byteArrayOf(9)); it.fd.sync() }
                FileOutputStream(temporary).use { it.write(ByteArray(50) { 7 }); it.fd.sync() }
                Os.rename(temporary.path, target.path)
            }
            delivered.await() // Actual kernel/main-thread delivery, not elapsed time.
            synchronized(events) { check(events == mappings.map { it.key }.toSet()) }
        } finally {
            watch.close()
            for (file in owned) {
                check(file.canonicalFile == file.absoluteFile)
                if (file.exists()) check(file.isFile && file.delete())
            }
            for ((directory, names) in initial) check(File(directory).list()!!.toSet() == names)
        }
        return "PASS RetroArch exact native watches: mGBA/Snes9x clock and N64/NES SRM publications delivered; unrelated and temporary leaves excluded; joined observer cleanup; existing saves preserved; no emulator/Drive/settings changes"
    }

    fun exercise(context: Context): String {
        check(context.packageName == "com.darkaxt.rshop.debug")
        val parent = File("/storage/emulated/0/RShopLiveTest")
        val createdParent = if (!parent.exists()) { check(parent.mkdir()); true } else false
        check(parent.isDirectory && parent.canonicalFile == parent.absoluteFile)
        val root = File(parent, "save-watch-${UUID.randomUUID()}")
        check(root.mkdir())
        val directory = File(root, "PPSSPP_STATE")
        check(directory.mkdir())
        val mapping = SaveFileWatch.Mapping("a".repeat(64), directory.path, "ULUS10041_1.00_0.ppst")
        val publication = CountDownLatch(1)
        val events = mutableListOf<String>()
        val watch = SaveFileWatch { key ->
            synchronized(events) { events.add(key) }
            publication.countDown()
        }
        val temp = File(directory, "${mapping.name}.tmp")
        val other = File(directory, "Other.iso")
        val target = File(directory, mapping.name)
        try {
            val missing = SaveFileWatch.Mapping("b".repeat(64),
                File(root, "missing/PPSSPP_STATE").path, mapping.name)
            check(watch.replace(listOf(missing, mapping)) == listOf(mapping.key))
            check(temp.createNewFile() && other.createNewFile())
            FileOutputStream(other).use { it.write(byteArrayOf(1)); it.fd.sync() }
            FileOutputStream(temp).use { it.write(ByteArray(50) { 7 }); it.fd.sync() }
            // The same temp-to-published-leaf event as the reviewed PPSSPP
            // writer. Event delivery, not a quiet-period guess, releases us.
            Os.rename(temp.path, target.path)
            publication.await()
            synchronized(events) { check(events == listOf(mapping.key)) }
            check(target.length() == 50L)
        } finally {
            watch.close()
            val allowed = setOf(temp.name, other.name, target.name)
            val files = directory.listFiles()!!
            check(files.all { it.name in allowed && it.isFile && it.canonicalFile == it.absoluteFile })
            files.forEach { check(it.delete()) }
            check(directory.delete() && root.delete())
            if (createdParent) check(parent.delete())
        }
        return "PASS native exact-file watch: missing-folder mapping isolated; exact registered-key receipt; atomic published-slot rename delivered on main thread; temporary/unrelated files excluded; stopped observers and exclusive fixture cleanup; no emulator/user-save/ROM/account/cloud access"
    }
}
