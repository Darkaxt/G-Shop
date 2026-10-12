package com.retro.rshop

import org.junit.Assert.*
import org.junit.Test

class PcsxSaveSettingsTest {
    private val core = "/storage/emulated/0/RetroArch/config/PCSX-ReARMed"
    private val leaf = "owned%2FGame%20(USA).chd"
    private fun files(options: String = "") = mutableMapOf(
        PcsxSaveSettings.CONFIG to """
            rgui_config_directory = "/storage/emulated/0/RetroArch/config"
            savefile_directory = "/storage/emulated/0/RetroArch/saves"
            sort_savefiles_enable = "true"
            sort_savefiles_by_content_enable = "false"
            savefiles_in_content_dir = "false"
            global_core_options = "false"
            game_specific_options = "true"
            core_options_path = ""
        """.trimIndent(),
        "$core/PCSX-ReARMed.opt" to options)

    @Test fun preservesEncodedChdStemAndSeparatesSharedCardFromPerGameCard() {
        val data = files("pcsx_rearmed_memcard1 = \"libretro\"\npcsx_rearmed_memcard2 = \"shared\"")
        val layout = PcsxSaveSettings.resolve(leaf, data::get)
        assertEquals("/storage/emulated/0/RetroArch/saves/PCSX-ReARMed", layout.directory)
        assertEquals(listOf(PcsxSaveSettings.Card(1, "libretro", "owned%2FGame%20(USA).srm"),
            PcsxSaveSettings.Card(2, "shared", "pcsx-card2.mcd")), layout.cards)
    }

    @Test fun gameOptionsReplaceCoreOptionsRatherThanMergingUnspecifiedKeys() {
        val data = files("pcsx_rearmed_memcard1 = \"shared\"\npcsx_rearmed_memcard2 = \"none\"")
        data["$core/owned%2FGame%20(USA).opt"] = "pcsx_rearmed_memcard1 = \"libretro\""
        val layout = PcsxSaveSettings.resolve(leaf, data::get)
        assertEquals("libretro", layout.cards[0].mode)
        // The core's slot-2 default is shared, not the lower-precedence 'none'.
        assertEquals(PcsxSaveSettings.Card(2, "shared", "pcsx-card2.mcd"), layout.cards[1])
    }

    @Test fun folderOptionsPrecedeCoreAndRespectDisabledGameSpecificOptions() {
        val data = files("pcsx_rearmed_memcard2 = \"shared\"")
        data["$core/document.opt"] = "pcsx_rearmed_memcard2 = \"none\""
        assertEquals(listOf(1), PcsxSaveSettings.resolve(leaf, data::get).cards.map { it.slot })
        data[PcsxSaveSettings.CONFIG] = data.getValue(PcsxSaveSettings.CONFIG)
            .replace("game_specific_options = \"true\"", "game_specific_options = \"false\"")
        assertEquals(listOf(1, 2), PcsxSaveSettings.resolve(leaf, data::get).cards.map { it.slot })
    }

    @Test fun globalOptionsAndExplicitSaveDirectoryAreNotReplacedWithGuesses() {
        val data = files()
        data[PcsxSaveSettings.CONFIG] = data.getValue(PcsxSaveSettings.CONFIG)
            .replace("global_core_options = \"false\"", "global_core_options = \"true\"")
            .replace("core_options_path = \"\"", "core_options_path = \"/storage/emulated/0/RetroArch/custom.opt\"")
            .replace("sort_savefiles_enable = \"true\"", "sort_savefiles_enable = \"false\"")
        data["/storage/emulated/0/RetroArch/custom.opt"] = "pcsx_rearmed_memcard1 = \"shared\"\npcsx_rearmed_memcard2 = \"serial\""
        val layout = PcsxSaveSettings.resolve(leaf, data::get)
        assertEquals("/storage/emulated/0/RetroArch/saves", layout.directory)
        assertEquals(PcsxSaveSettings.Card(1, "shared", "pcsx-card1.mcd"), layout.cards[0])
        // A disc serial requires actual disc evidence, not the title or CHD name.
        assertEquals(PcsxSaveSettings.Card(2, "serial", null), layout.cards[1])
    }

    @Test fun relevantFrontendOverridesApplyInCoreFolderGameOrder() {
        val data = files()
        data["$core/PCSX-ReARMed.cfg"] = "savefile_directory = \"/storage/75D7-DC5F/Saves\""
        data["$core/document.cfg"] = "savefile_directory = \"/storage/75D7-DC5F/FolderSaves\""
        data["$core/owned%2FGame%20(USA).cfg"] = "savefile_directory = \"/storage/75D7-DC5F/GameSaves\""
        assertEquals("/storage/75D7-DC5F/GameSaves/PCSX-ReARMed", PcsxSaveSettings.resolve(leaf, data::get).directory)
    }

    @Test fun rejectsAmbiguityInvalidModesMalformedSettingsAndEscapingNames() {
        for (options in listOf("pcsx_rearmed_memcard1 = \"mystery\"",
            "pcsx_rearmed_memcard2 = \"libretro\"",
            "pcsx_rearmed_memcard1 = \"shared\"\npcsx_rearmed_memcard1 = \"none\"")) {
            val data = files(options)
            assertThrows(IllegalArgumentException::class.java) { PcsxSaveSettings.resolve(leaf, data::get) }
        }
        for (bad in listOf("Game.7z", "../Game.chd", "Game\\other.chd", "a".repeat(256) + ".chd")) {
            val data = files()
            assertThrows(IllegalArgumentException::class.java) { PcsxSaveSettings.resolve(bad, data::get) }
        }
        for (value in listOf("/storage/emulated/0/../Saves", "/data/user/0/other", "/storage/emulated/0//Saves")) {
            val data = files()
            data[PcsxSaveSettings.CONFIG] = data.getValue(PcsxSaveSettings.CONFIG)
                .replace("/storage/emulated/0/RetroArch/saves", value)
            assertThrows(IllegalArgumentException::class.java) { PcsxSaveSettings.resolve(leaf, data::get) }
        }
        assertThrows(IllegalArgumentException::class.java) { PcsxSaveSettings.resolve(leaf) { null } }
    }

    @Test fun disabledFrontendOverridesDoNotChangeTheDestination() {
        val data = files()
        data[PcsxSaveSettings.CONFIG] = data.getValue(PcsxSaveSettings.CONFIG) + "\nauto_overrides_enable = \"false\""
        data["$core/PCSX-ReARMed.cfg"] = "savefile_directory = \"/storage/75D7-DC5F/Other\""
        assertEquals("/storage/emulated/0/RetroArch/saves/PCSX-ReARMed", PcsxSaveSettings.resolve(leaf, data::get).directory)
    }

    @Test fun unknownIncludeAndContentUriDestinationPoliciesStayUnresolved() {
        for (change in listOf("#include \"other.cfg\"",
            "savefiles_in_content_dir = \"true\"", "sort_savefiles_by_content_enable = \"true\"")) {
            val data = files()
            val key = change.substringBefore('=') .trim()
            data[PcsxSaveSettings.CONFIG] = data.getValue(PcsxSaveSettings.CONFIG)
                .lineSequence().filterNot { it.startsWith("$key =") }.joinToString("\n") + "\n$change"
            assertThrows(IllegalArgumentException::class.java) { PcsxSaveSettings.resolve(leaf, data::get) }
        }
    }
}
