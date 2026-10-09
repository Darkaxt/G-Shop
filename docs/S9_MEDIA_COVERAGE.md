# S9 original-media coverage audit

Authority: ART-01, UI-01 and QA-04 in SPECIFICATION.md. Audit date: 2026-10-09.
Status: COMPLETE after final reconciliation below. S7 remains BLOCKED; this audit does
not approve retention, ROM removal, save handover or overall completion.

## Scope and evidence

The current `SystemModel.supportedSystems` contains 66 canonical platform IDs.
`platformMediaFamilies` explicitly covers that exact set, using 49 physical-media
illustrations and one neutral illustration. All 50 bundled PNGs were individually
opened and visually inspected during this audit, not merely accepted from their
filenames. Each is the unchanged, decoded 256px raster from the pinned Systematic
content family. The outlined shapes, palette and margins are consistent. N64 has
its curved, wide cartridge; it is not a Game Boy cartridge. The neutral rocket
represents game content, not a controller or a physical storage device.

Evidence key A: the platform-labelled original PNG and blob identity in
`assets/media_fallbacks/systematic/SOURCES.json`, pinned to
[retroarch-assets b177f250e42948708e753d30809bd4dd9c0a2cdc](https://github.com/libretro/retroarch-assets/tree/b177f250e42948708e753d30809bd4dd9c0a2cdc/xmb/systematic/png),
plus direct inspection of its actual pixels. License, credits, unchanged-byte
provenance and offline attribution are in `assets/media_fallbacks/PROVENANCE.md`,
`NOTICE.md` and `COPYING`. No additional art or generated illustration was needed.

The table describes **platform physical-media families**, not proof that an
individual homebrew, digital release, prototype or converted archive was sold in
that packaging. Regional shell colours and labels need not be reproduced. Optical
discs share recognizable geometry; these are icons, not a physical-size scale.
GameCube's mini-disc and PSP's cased UMD remain distinct platform illustrations.
DSi's icon represents its physical game-card branch, not a claim that DSiWare was
distributed on cards. Likewise cartridge-console digital/homebrew releases do not
acquire a fabricated physical release record from the fallback.

Evidence keys M1-M13 below are inspected MAME source at immutable revision
`1ddcb581da648c49696d11b126bcf783379a2bd8`. They establish hardware/software-list
media families, **not edition-specific release evidence**. No game is assigned a
floppy or tape from `.zip`, `.7z`, `.chd`, snapshot or disk-image suffixes. Mixed
computers therefore deliberately remain neutral. This is the ART-01 neutral case,
not an unimplemented per-file media resolver or an excuse to add unused assets.

## Complete platform / original-media / asset matrix

The last column records the reviewed shape or the reason for neutrality.
The focused audit contract checks that these rows stay aligned with the complete
supported-platform set and the production mapping.

| Platform ID | Original media family | Bundled asset | Evidence and reviewed result |
| --- | --- | --- | --- |
| `nes` | NES cartridge | `nes.png` | A; tall ribbed shell and label recess |
| `snes` | SNES cartridge | `snes.png` | A; wide shell, upper recess and lower slots |
| `n64` | N64 cartridge | `n64.png` | A; wide curved top, distinct from handheld carts |
| `gc` | GameCube optical mini-disc | `gc.png` | A; platform disc illustration, not a claimed scale |
| `wii` | Wii optical disc | `wii.png` | A; optical disc with central hub |
| `wiiu` | Wii U optical disc | `wiiu.png` | A; optical disc with outlined rim |
| `switch` | Switch game card | `switch.png` | A; small rounded game-card housing |
| `gb` | Game Boy cartridge | `gb.png` | A; stepped shell, ribbing and label recess |
| `gbc` | Game Boy Color cartridge | `gbc.png` | A; rounded translucent-style shell and contacts |
| `gba` | Game Boy Advance cartridge | `gba.png` | A; short wide shell and upper lip |
| `nds` | Nintendo DS game card | `nds.png` | A; notched game card |
| `virtualboy` | Virtual Boy cartridge | `virtualboy.png` | A; distinctive rounded tall shell |
| `fds` | Famicom Disk System disk card | `fds.png` | A; yellow disk-card housing, hub and exposed slot |
| `dsi` | DSi physical game-card branch; digital DSiWare also exists | `dsi.png` | A; game card, not asserted DSiWare packaging |
| `n3ds` | Nintendo 3DS game card | `n3ds.png` | A; game-card shell with projecting tab |
| `psx` | PlayStation CD | `psx.png` | A; optical disc and hub |
| `ps2` | PlayStation 2 CD/DVD | `ps2.png` | A; shared optical-disc geometry |
| `ps3` | PlayStation 3 Blu-ray disc | `ps3.png` | A; optical disc and hub |
| `psp` | PSP cased UMD | `psp.png` | A; recognizable UMD outer housing |
| `psvita` | PlayStation Vita game card | `psvita.png` | A; small stepped game-card shell |
| `mastersystem` | Master System cartridge; Sega Card branch also exists | `mastersystem.png` | A; primary cartridge shell, not an edition assertion |
| `megadrive` | Mega Drive cartridge | `megadrive.png` | A; broad rounded lower edge and label recess |
| `gamegear` | Game Gear cartridge | `gamegear.png` | A; rounded upper label recess and lower notch |
| `segacd` | Sega CD optical disc | `segacd.png` | A; optical disc and hub |
| `sega32x` | Sega 32X cartridge | `sega32x.png` | A; wide raised shell and side grips |
| `dreamcast` | Dreamcast GD-ROM | `dreamcast.png` | A; optical disc, platform-specific label |
| `saturn` | Saturn CD | `saturn.png` | A; optical disc and hub |
| `sg1000` | SG-1000 cartridge; My Card branch also exists | `sg1000.png` | A; primary cartridge shell, not an edition assertion |
| `tg16` | TurboGrafx-16 / PC Engine HuCard | `tg16.png` | A; thin card with exposed contact strip |
| `tgcd` | TurboGrafx-CD optical disc | `tgcd.png` | A; optical disc and hub |
| `ngp` | Neo Geo Pocket cartridge | `ngp.png` | A; upper lip, ribs and label recess |
| `neogeocd` | Neo Geo CD optical disc | `neogeocd.png` | A; optical disc and hub |
| `wonderswan` | WonderSwan cartridge | `wonderswan.png` | A; wide short shell and exposed contacts |
| `colecovision` | ColecoVision cartridge | `colecovision.png` | A; tall shell and upper ribs |
| `intellivision` | Intellivision cartridge | `intellivision.png` | A; tapered tall shell and ribs |
| `vectrex` | Vectrex cartridge | `vectrex.png` | A; upper insertion arrow and lower label |
| `msx` | Cartridge, cassette and floppy families | `neutral.png` | M1; no edition-specific medium binding |
| `amstradcpc` | Cassette, 3-inch floppy; model/expansion variations | `neutral.png` | M2; do not substitute a 3.5-inch icon for every disk |
| `channelf` | Fairchild Channel F cartridge | `channelf.png` | A; tall coloured shell and lower grips |
| `odyssey2` | Odyssey 2 cartridge | `odyssey2.png` | A; prominent carrying handle |
| `jaguar` | Atari Jaguar cartridge | `jaguar.png` | A; broad upper grip/handle |
| `atari2600` | Atari 2600 cartridge | `atari2600.png` | A; rectangular shell and front label |
| `atari5200` | Atari 5200 cartridge | `atari5200.png` | A; chamfered shell and side ribs |
| `atari7800` | Atari 7800 cartridge | `atari7800.png` | A; upper label and rectangular shell |
| `lynx` | Atari Lynx game card | `lynx.png` | A; thin housing with contact strip |
| `jaguarcd` | Atari Jaguar CD | `jaguarcd.png` | A; optical disc and hub |
| `atarist` | 3.5-inch floppy; cartridge branch | `neutral.png` | M3; model support does not identify this release |
| `pcfx` | PC-FX CD | `pcfx.png` | A; optical disc and hub |
| `c64` | Cartridge, cassette and 5.25-inch floppy | `neutral.png` | M4; no release-medium assumption from a container |
| `vic20` | Cartridge, cassette and floppy families | `neutral.png` | M5; no edition-specific medium binding |
| `amiga` | 3.5-inch floppy and later expanded storage | `neutral.png` | M6; archive/HDF does not establish original packaging |
| `zxspectrum` | Cassette and model-specific floppy families | `neutral.png` | M7; +3 3-inch and expansion media remain distinct |
| `oric` | Cassette and expansion floppy families | `neutral.png` | M8; inspected 3-inch option, no release binding |
| `x68000` | 5.25-inch floppy and expanded storage | `neutral.png` | M9; inspected HD floppy route, no release binding |
| `x1` | Cassette and 5.25-inch floppy | `neutral.png` | M10; both families explicitly supported |
| `fmtowns` | CD-ROM and 3.5-inch floppy | `neutral.png` | M11; CD image/container alone is not release evidence |
| `cdi` | CD-i optical disc | `cdi.png` | A; optical disc and hub |
| `3do` | 3DO optical disc | `3do.png` | A; optical disc and hub |
| `appleii` | Cassette and floppy families | `neutral.png` | M12; original/compatible floppy lists and cassette |
| `ngage` | N-Gage MMC game card | `ngage.png` | A; chamfered card, not a DS cartridge |
| `arcadia2001` | Arcadia 2001 cartridge | `arcadia2001.png` | A; tall cartridge with stepped upper shell |
| `arcade` | Integrated boards; varied system-specific media | `neutral.png` | No universal removable consumer medium |
| `dos` | Floppy, optical and installed/download distributions | `neutral.png` | M13; PC family is not one physical release format |
| `gameandwatch` | Integrated handheld game | `neutral.png` | No removable game cartridge implied |
| `tic80` | Virtual cartridge | `neutral.png` | Virtual distribution is not a physical cartridge |
| `pico8` | Virtual cartridge | `neutral.png` | Virtual distribution is not a physical cartridge |

## Legacy-family source review

Base URL for M1-M13:
[MAME source at the inspected revision](https://github.com/mamedev/mame/tree/1ddcb581da648c49696d11b126bcf783379a2bd8/src/mame).
These findings are deliberately bounded to the routes actually inspected;
they are not an exhaustive history of every aftermarket expansion.

| Key | Source below `src/mame/` | Inspected evidence |
| --- | --- | --- |
| M1 | `msx/msx.cpp` | `msx1_cart`, `msx1_cass`, `msx1_flop`, MSX2 compatible lists |
| M2 | `amstrad/amstrad.cpp` | Cassette configuration; `FLOPPY_3_SSDD` and 3.5-inch expansion options |
| M3 | `atari/atarist.cpp` | `FLOPPY_35_DD`, `st_flop`, `st_cart` |
| M4 | `commodore/c64.cpp` | `c64_cart`, `c64_cass`, `flop525_orig`, `flop525_misc` |
| M5 | `commodore/vic20.cpp` | `vic1001_cart`, `vic1001_cass`, `vic1001_flop` |
| M6 | `amiga/amiga.cpp` | `FLOPPY_35_DD`, original OCS/ECS/AGA floppy lists |
| M7 | `sinclair/spectrum.cpp`, `sinclair/specpls3.cpp` | Cassette; +3 `FLOPPY_3_SSDD`, 3.5-inch option and `specpls3_flop` |
| M8 | `tangerine/oric.cpp` | Cassette, `oric1_cass`, `FLOPPY_3_DSDD` |
| M9 | `sharp/x68k.cpp` | `FLOPPY_525_HD`, `x68k_flop`, compatible 5.25-inch list; SCSI CD route |
| M10 | `sharp/x1.cpp` | `FLOPPY_525_DD`, `x1_cass`, `x1_flop` |
| M11 | `fujitsu/fmtowns.cpp` | `FLOPPY_35_HD`, original floppy lists and CD-ROM device |
| M12 | `apple/apple2.cpp` | Original/compatible Apple II floppy lists, cassette device/list |
| M13 | `pc/pc.cpp` | PC system family, not a single release-medium catalogue; R-Shop also admits installed executables |

The initial `commodore/amiga.cpp` request returned 404; its accidental stale
loop-variable output was discarded. The successful `amiga/amiga.cpp` request
above is the evidence. Fetches in the corrected loop fail closed per source.

Thus the audit explicitly considered 3-inch, 3.5-inch and 5.25-inch families,
cassettes, disk cards and thin game cards. It did not silently relabel all old
disks as one modern floppy. None of the currently asserted physical-console
families lacks its reviewed raster. Mixed computer releases remain intentionally
unasserted; ART-01 explicitly requires neutral treatment in this case. There is
no new unused asset pack, medium inference framework or network dependency.

## Verification and reconciliation

- Fresh focused `media_cover_fallback_test.dart` completed with exit 0. It checks
  exact supported-ID coverage, unknown/mixed neutrality, actual Flutter decoding,
  nonempty alpha, unchanged Git blob identity, bundled offline attribution,
  immediate failed/loading fallback and decoded-cover replacement with no sockets.
- Native normal Library on the connected Thor used the installed production-debug
  app, not a test-only gallery. FDS resolved covers retain titles, platform badges,
  cloud/SD badges and focus. N64's normal 007 variant cards show the curved cartridge
  beside actual decoded covers. Controller-injected Right moves focus to a
  fallback card; its white outline remains visible.
- Normal L1/R1 controls exercised both extremes: three columns (595px card bounds)
  and eight columns (209px card bounds). Captures at both extremes were opened and
  inspected. The same selected N64 fallback, titles and status badges remain
  identifiable; no black loading square or generic handheld cartridge appears.
  Eight columns necessarily truncates long titles; this audit does not claim
  untruncated captions or a changed layout contract.
- Layout restored to the original effective four columns through normal controls.
  The preference now explicitly stores 4 instead of relying on the absent-key
  default; no claim of byte-identical preferences is made. No ROM operation,
  companion change, account reconnect, metadata-job pause or installation occurred.
- The live metadata worker was observed at 20,098 requests before review; its
  operation was left running. Screen-off completion and cleanup are recorded at
  closure, not inferred from the first asynchronous sleep request.
- No production code/assets changed, so no Gradle build, gate claim or APK update
  is required for this audit. Current host checks cover replacement; existing
  S5 native replacement evidence remains applicable to the unchanged renderer.
  The live observations above prove presentation, not a newly instrumented
  per-card network/decode transition.

### Final ART-01 reconciliation

| Acceptance criterion | Inspected evidence | Result |
| --- | --- | --- |
| Complete current platform / original-format / asset matrix | All 66 rows above; focused contract checks exact ID equality and each runtime asset | Satisfied |
| Recognizable cartridges, including N64; legacy-format review | All 50 rasters individually inspected; thin cards, FDS disk card and M1-M13 review distinguish 3/3.5/5.25-inch and cassette families; neutral cases explicit | Satisfied |
| Consistent raster family and provenance for any added assets | Existing pinned Systematic bytes/hash/license checks pass; no new image needed | Satisfied |
| Bundle/decode/mapping, immediate fallback and valid-cover replacement | Fresh focused media checks, actual Flutter decoder and offline cached-cover replacement; unchanged S5 native renderer evidence remains applicable | Satisfied |
| Compact/large Thor presentation, badges and focus | Normal native three/eight-column N64 and FDS review above; focused caption/status/rating/transfer layout and metadata-badge checks pass | Satisfied |
| Preservation, screens off and final reconciliation | No ROM/emulator/cloud writes or app update; original effective layout restored; same process 27415; power Asleep and both physical actual/committed states OFF | Satisfied |

Scoped analysis reports no issues; `git diff --check` passes. The focused audit
test was added to prevent a later platform/mapping change silently invalidating
the reviewed matrix. No production behavior was rewritten to satisfy the audit.

Five expendable host captures and their empty directory were removed through
reviewed transaction `43c1a5248c8901857fd0e042cd1472fd`: state `applied`, six members,
5,306,439 bytes, no errors. The two exact task-created device captures were also
removed and independently observed absent. No user file or permanent source was
included; these diagnostic captures can be regenerated, not undeleted by the app.

S9 blockers: none. S9 tracked deferrals: none. S7's retention/metadata/migration
work and the S10/S11 requirements remain unchanged and required. This closes
ART-01 only, not the overall implementation or a release.
