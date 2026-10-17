# S25 packaging feasibility and coverage

Review date: 2026-10-17. Authority: SPECIFICATION.md revision 74.
This is the requested pre-implementation review, not a new implementation stage.
S24 is released; expanded S25 remains NOT STARTED. No new model has been installed,
converted, purchased or accepted on Android during this review.

## Product direction

Support the owner's **Box -> Cover -> Cartridge** presentation where resources
exist: outer packaging, protective case/cover, then the physical cartridge/card/
disc. Treat these as distinct available layers, not proof that every original
release contained both a cardboard box and a plastic case. Disc/UMD is the final
medium for optical platforms. Missing layers must not prevent browsing or launch.

Three viable approaches were considered:

1. One resized generic plastic case: fastest broad best-effort presentation,
   but not an accurate original-package claim for every platform.
2. Asset-complete original packaging for every game: strongest physical fidelity,
   but would need missing scans, regional variants and models not established by
   this review. Do not make that a universal blocker.
3. **Recommended: capability-based layers.** Use a genuine template/case family
   when verified; use the approved plastic case with seam/hinge and generic missing
   faces otherwise. Preserve original/custom/reconstructed provenance. Show only
   available layers, retain the flat default and existing imported cartridge path.

Keep the planned compact Box/Cartridge/Media viewer, rotation/zoom, controller and
L1/R1 navigation, red theme, retained library focus and companion ownership. The
automatic layer sequence and manual viewer share the same selected edition and
resource readiness; moving focus cancels the old game's sequence. Reduced Motion
retains accessible static choices. No fabricated artwork or missing game blocks
the sequence; generic faces are explicitly approved best-effort material.

An opening-capable case may support a reveal when its real parts/pivots are
verified. A closed mesh supports rotation and sliding transitions, not a claim
that an opening animation exists. Do not substitute scaling a solid block for
opening a hinged case. Actual opening scope/behavior must be reconciled from the
chosen asset before implementation, without turning it into a universal prerequisite.

## Verified source review

### Box scans and sleeves

- [NintAndBox Archive](https://archive.org/details/nintandbox-2026): the public
  [item metadata](https://archive.org/metadata/nintandbox-2026) returns HTTP 200.
  It lists one `Nintandbox.org.7z`, **42,436,388,695 bytes**, plus item metadata and
  thumbnails. The uploader describes a March-2026 snapshot with over 5,700 scans
  and 42,367 images; those are uploader claims, not independently inspected files.
  No archive payload was downloaded. Per-console/per-edition membership and scan
  layouts therefore remain unverified. The metadata supplies no reuse licence.
- [NintAndBox.es Sapphire](https://www.nintandbox.es/gameboy-advance/pokemon-zafiro)
  describes a complete printable flat box with front, rear and side flaps, labelled
  Spanish/PAL-Spain. Downloads require an account; some items require credits.
  This verifies the listing, not downloaded bytes, panel coordinates or compatibility
  with a US edition. Restored/printable art is not automatically an untouched scan.
  Do not assume the .es catalogue and the archived .org collection are identical.
- The [current .es index](https://www.nintandbox.es/) lists Game & Watch, GB,
  GBC, GBA, NES, SNES and N64, including separate custom categories. Counts are
  catalogue listings, not coverage of our collection.
- [LaunchBox GBA 007](https://gamesdb.launchbox-app.com/games/details/26125-007-everything-or-nothing)
  lists region-labelled front, rear and spine images. Two Japan-labelled spines
  need physical-face/packaging inspection; their category alone proves neither
  duplicate artwork nor an additional side. The metadata ZIP responds to HEAD,
  but the current image extraction/matching integration is still unimplemented.
- ScreenScraper remains the planned fallback for compatible box faces/wraps.
  The locally inspected Mega Man Zero 3 US `box-texture` is a genuine three-panel
  spread, not six original faces. Its same-game `box-scan` returned non-image HTML.
- [FoldBoks](https://foldboks.ch/), linked by the archive uploader, advertises
  parametric packaging and 3D preview. It is a layout/reference lead, not an
  inspected source-code dependency or a ready R-Shop asset.

Use NintAndBox for compatible full outer-box templates when available, not as a
replacement score/metadata provider. LaunchBox-first/ScreenScraper-fallback remains
the case-face/wrap path. Normalize both into existing edition-bound typed Drive
resources; distinguish dielines, cover faces, sleeves and physical-media labels.
Never stretch a whole cut/fold sheet onto one rectangle or infer folds from an
arbitrary image. A template needs a verified panel/fold map. Flat front/back wraps
need a different mapping. Keep original image dimensions; fit geometry to panel
aspect, not the unfolded-sheet aspect.

### Downloadable geometry

| Candidate | What is verified now | Access/reuse and remaining evidence |
| --- | --- | --- |
| [Switch case, Blendkit](https://www.blendkit.com/asset-gallery-detail/8f414675-2cd9-4ff6-988d-dec118effbe1/) | Listing says free, textured, rigged, case plus card; 6,831 polygons and 1.5 MiB | Free account/add-on route; labelled Royalty Free, not CC0. Actual downloaded format, pivots, UVs, animation channels and redistribution terms have not been inspected. Replace example-game art rather than bundling it. |
| [Game Case, NateSquared](https://sketchfab.com/3d-models/game-case-b9f59fa49f4c465c94ec262b21898d54) | Official public model API confirms downloadable, CC Attribution, replaceable textures, zero animations; creator explicitly says it cannot open | Useful free closed-case baseline; attribution required. Actual file/UV/submesh conversion is not yet tested. Not an opening-case asset. |
| [PSP case and UMD holder, Fab](https://www.fab.com/listings/44998262-8a21-4b28-bbe3-3c0e31ff1f55) | GLB/FBX listed; creator explicitly describes opening/closing case and disc-holder mechanisms | Checkout/licence selection present; current price is not exposed by the inspected page. No purchase. Rig/pivots, topology, material and Android import remain unverified. |
| [GameCube case and disc, TurboSquid](https://www.turbosquid.com/3d-models/nintendo-gamecube-game-and-keep-case-3d-model-1867828) | Case/disc and replaceable scan templates; FBX/OBJ and other formats; 6,408 polygons | Listing shows $29 and Editorial Uses Only. Not purchased; opening/rig not established. Do not select as public bundled geometry without resolving its terms. |
| [PS4/Xbox One case, Free3D](https://free3d.com/3d-model/ps4-xbox-one-game-case-1975.html) | UV-mapped, 1,500 polygons; no rig or animation | Listing shows $19, editorial-only designation. These consoles are not in R-Shop's current platform catalogue; comparison reference, not new-system scope or an automatic purchase. |
| [Opening Xbox case, TurboSquid](https://www.turbosquid.com/3d-models/xbox-case-c4d/895983) | Rigged listing, replaceable sleeve and opening/closing controls | Paid reference, not purchased or downloaded. Xbox is not a current R-Shop platform; do not add it merely to use this model. |
| [GB/GBC/GBA DS-style case, MakerWorld](https://makerworld.com/en/models/674737-gameboy-advance-game-case-ds-style) | Printable replacement-case geometry for GB/GBC/GBA with cartridge supports/clasps | CC BY-NC-SA listed. Printing asset, not proven rendering-ready: UVs, materials, sensible mesh detail and hinge animation need adaptation. |

Listing text is not native acceptance. No purchases, account creation, add-on
installation, 40-GB download or model redistribution was performed for this review.

## Current R-Shop coverage ledger

Fresh source inspection: `SystemModel.supportedSystems` contains **66 IDs**.
`PhysicalMediaFormat.forSystem` explicitly binds **20 IDs** (19 console families
plus DSi's physical-card alias) to **16 imported media variants**. All 66 have
the existing flat fallback coverage documented in S9. That does **not** mean 66
console-specific 3D cartridge models or complete packaging sequences.

Below, "model" means the current imported final-medium binding, not a newly
verified S25 case. "Candidate" means source/listing coverage only. **No console
has the new complete three-layer S25 workflow implemented or accepted yet.**

| Platform ID | Existing final-medium model | Packaging lead / current gap |
| --- | --- | --- |
| `nes` | NES cartridge | .es outer-box catalogue; exact game/region/template and protective layer not verified |
| `snes` | US/PAL variants | .es outer-box catalogue; regional panel maps needed |
| `n64` | N64 cartridge | .es outer-box catalogue; full box/template bytes not inspected |
| `gc` | Shared disc | Paid keep-case candidate; mini-disc/case adaptation not S25-verified |
| `wii` | Shared disc | Generic closed keep-case candidate; console-specific fit/UVs not verified |
| `wiiu` | Shared disc | Generic closed keep-case candidate; console-specific fit/UVs not verified |
| `switch` | Switch card | Strong free rigged case/card listing; actual file and native animation not tested |
| `gb` | GB cartridge | .es box catalogue plus printable replacement-case candidate |
| `gbc` | Two cartridge variants | .es box catalogue plus printable replacement-case candidate |
| `gba` | GBA cartridge | Best initial complete-pipeline candidate: existing verified 24-game media sample, real wrap, listed full dielines and replacement-case lead; compatible downloaded outer nets/3D case still missing |
| `nds` | DS card | No console-specific case file inspected in this review |
| `dsi` | DS physical-card binding | Same case gap; do not invent physical packaging for DSiWare |
| `n3ds` | 3DS card | No console-specific case file inspected |
| `psx` | Shared disc | Jewel/multidisc/regional cases need their own verified geometry/layout; DVD case is not an accurate substitute claim |
| `ps2` | Shared disc | Generic closed keep-case lead; fit and selected-edition wrap integration pending |
| `ps3` | Shared disc | Generic baseline only; no verified PS3 case adaptation |
| `psp` | UMD shell | Specific Fab case/holder with opening-mechanism claim; actual asset/conversion unverified |
| `psvita` | Vita card adaptation | No case model inspected; retain existing source-scene/planar-label provenance |
| `megadrive` | Genesis/Mega Drive variants | No verified clamshell/box source in this supplied set |
| `dreamcast` | Shared disc | No verified jewel/multidisc case in this supplied set |

The remaining **46 IDs** are explicitly accounted for below. They retain flat
physical-media/neutral fallbacks; no new 3D final-medium or full packaging support
is established by the supplied case listings.

| Remaining IDs | Current review result |
| --- | --- |
| `virtualboy`, `fds`, `mastersystem`, `gamegear`, `sega32x`, `sg1000`, `tg16`, `ngp`, `wonderswan`, `colecovision`, `intellivision`, `vectrex` | Specific cartridge/card/disk geometry and box/case coverage still need sources; keep their distinct flat forms |
| `segacd`, `saturn`, `tgcd`, `neogeocd`, `jaguarcd`, `pcfx`, `cdi`, `3do` | Flat optical media; no current explicit imported 3D binding or verified console-specific case |
| `channelf`, `odyssey2`, `jaguar`, `atari2600`, `atari5200`, `atari7800`, `lynx`, `ngage`, `arcadia2001` | Flat platform-specific media; supplied models do not establish cartridge/case coverage |
| `msx`, `amstradcpc`, `atarist`, `c64`, `vic20`, `amiga`, `zxspectrum`, `oric`, `x68000`, `x1`, `fmtowns`, `appleii`, `dos` | Mixed media: original format and packaging must follow edition evidence; do not infer floppy/tape/cart from an archive extension |
| `arcade`, `gameandwatch`, `tic80`, `pico8` | No universal removable cartridge pipeline; catalogue box art may exist, but do not fabricate a physical game-medium claim |

## Integration recommendation and acceptance

1. Finish this review before starting S25 implementation. Keep the ledger honest
   about sourced, downloaded, converted, integrated and native-verified evidence.
2. Start with GBA and the existing real ranked sample. Prove same-edition typed
   artwork -> normalized Drive resource -> bounded local cache -> actual box/case
   surface -> cartridge label. A Spanish Sapphire listing does not authorize
   attaching that Spanish box to a US edition. Generic geometry can be reused;
   regional artwork identity cannot be guessed.
3. Use one legally usable closed case with proper seam/hinge for the broad
   best-effort path. Source-specific meshes are upgrades only when their actual
   files, mapping and current console requirements justify them. Existing GPU
   code draws indexed surfaces with transforms; the importer expects its pinned
   JSON/binary Socket format. It does not currently make arbitrary GLB/FBX files
   or skeletal rigs ready to use. Conversion/adaptation must preserve the existing
   original-APK importer, not spoof its hashes or add a second rendering engine.
4. Fit real outer-box dielines through explicit panel/fold recipes. Use compatible
   scans when available and generic faces otherwise. Do not wait for all 66
   platforms or six authentic scans before accepting a supported best-effort path.
5. Verify selected-game readiness, exact faces/aspect/material/seam, rotation/zoom,
   sequence cancellation/reselection, flat/default/missing/offline states, existing
   trailer audio, both screens and touch/controller navigation. Keep central
   collection; remove the per-entry download button as already specified.

All S25 user-facing acceptance remains pending. Missing console models/resources
are recorded coverage gaps, not evidence that the review itself requires an
unbounded download or that S24's already verified release failed.
