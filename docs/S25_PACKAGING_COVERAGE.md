# S25 packaging feasibility and coverage

Review date: 2026-10-18. Authority: SPECIFICATION.md revision 78.
Current implementation checkpoint: S25 is ACTIVE for the generic resource
explorer and individual model verification. The automatic cinematic transition
is expressly not being implemented yet. See [S25_VERIFIED_MODELS.md](S25_VERIFIED_MODELS.md)
for final-asset evidence; the source review below remains candidate research.
This source review was prepared before implementation, not as another stage.
S24 is released. The initial review byte-inspected one small public CC0 model
pack in memory. Subsequent acquired archives and the owner-provided GLB are
recorded below; none of these new third-party models is accepted on Android.
The owner has
separately authorized downloading the full NintAndBox archive. The latest storage
instruction keeps reference sources on E: and uploads only final classified
resources to private Drive, not the archive. Acquisition is not Android implementation.

## Product direction

Support the owner's **Box -> Cover -> Cartridge** presentation where resources
exist: outer packaging, protective case/cover, then the physical cartridge/card/
disc. Treat these as distinct available layers, not proof that every original
release contained both a cardboard box and a plastic case. Disc/UMD is the final
medium for optical platforms. Missing layers must not prevent browsing or launch.

Three viable approaches were considered:

1. One resized generic model for everything: simple, but conflates a cardboard
   outer box with a hinged plastic protector and a jewel case.
2. Asset-complete original packaging for every game: strongest physical fidelity,
   but would need missing scans, regional variants and models not established by
   this review. Do not make that a universal blocker.
3. **Recommended: a small set of reusable, parameterized families.** A simple
   six-surface outer box changes width/height/depth and face mapping per edition;
   plastic keep-cases, jewel cases and platform-specific protectors remain separate.
   Preserve original/custom/reconstructed provenance. Show only applicable layers,
   retain the flat default and existing imported cartridge path. In the owner's
   Switch example, use case/cover -> card, without a fictitious outer cardboard box.

Image aspect establishes a panel's width/height ratio, not physical depth or
millimetres. Use a known console/region/packaging preset, compatible measured spine,
or an explicitly generic depth. Do not blindly resize hinges, latches, wall
thickness and cartridge sockets with the whole model. A simple closed outer-box
mesh need not be rigged; opening parts are relevant only to an actual opening case.
Six named face UVs, orientation and correct image crops matter more than detail.

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

Additional owner-supplied candidates, checked against Sketchfab's public model
API on 2026-10-18 (listing metadata only; neither downloaded nor native-verified):

| Candidate | Verified listing facts | Unverified integration properties |
| --- | --- | --- |
| [Cover Games — T-Art](https://sketchfab.com/3d-models/cover-games-8ed2020f02bc4d14854ba8dcef88be26) | Downloadable, CC BY 4.0, 1,418 faces, two materials/textures, zero animation clips | Separate lid/interior geometry, pivots, UV replacement and useful platform fit require file inspection |
| [Kittella Genesis Case — warpnik](https://sketchfab.com/3d-models/kittella-genesis-case-0ad483dab1c84c50bfd6f266762cdc75) | Downloadable, CC BY 4.0, 1,320 faces, three materials/textures, zero animation clips; author describes concept-game packaging | Genesis-case geometry, opening support and replaceable sleeve require file inspection; concept artwork is not collection artwork |
| [DVD/Game Case — Raphael Frei](https://sketchfab.com/3d-models/dvdgame-case-d5c542e24bee490fbdf130413983f124) | Downloadable, CC BY 4.0, 1,335 faces, seven materials/six textures, zero animation clips; author states fully UV-mapped with separate disc reverse texture and optional fingerprint layer | PS2/DVD-style candidate only: inspect actual lid/interior/hinge and sleeve mapping before accepting opening support; disable cosmetic fingerprints if they obscure collection artwork |
| [Xbox Game case — Tonino](https://sketchfab.com/3d-models/xbox-game-case-3011f68dc849456f82500e9dd7acfee2) | Downloadable, CC BY 4.0, 37,684 faces, seven materials/two textures, zero animation clips; author explicitly says open/closed and replaceable inlay, made in Blender 4.2.3 | Reference only: Xbox One is not a current supported console. Inspect whether open/closed are separate poses/objects or an actual hinge; listing claims are not native animation evidence |
| [Splatoon Game Box — DerpBox](https://sketchfab.com/3d-models/splatoon-game-box-b088d4263eab4d47ad6e34383cd967de) | Downloadable, CC BY 4.0, 28 faces/24 vertices, two materials/six textures, zero animation clips | Wii U closed-box candidate; very small geometry count is not evidence of an interior, hinge or opening support |
| [Game Boy Super Mario Land box — Frank Rennau](https://sketchfab.com/3d-models/game-boy-super-mario-land-box-b4515d780a3b4b02a50d20bdec70a5a0) | Downloadable, CC BY 4.0, 102 faces/104 vertices, one material/two textures, zero animation clips | Original GB, not GBA. Inspect cardboard fold/crease geometry versus baked texture details before adapting panels |
| [Gameboy Advance Cartridge — luigi_30](https://sketchfab.com/3d-models/gameboy-advance-cartridge-25bd1b56c5b94d59884abd077156bde4) | API reports 12,264 faces, no clips, downloads disabled and no download licence. The owner subsequently supplied a self-contained exported GLB; structural inspection is recorded below | Cartridge and fitted protector are acquired reference geometry, not native-accepted models. Opening, game-label replacement and materials still require adaptation/verification; no public redistribution permission is inferred |
| [Sega Cartridge Box — Caracticus](https://sketchfab.com/3d-models/sega-cartridge-box-3124c02b4f8e4b5bb8edd57d62ffd28a) | API reports one animation, 8,450 faces, three materials/six textures, **downloads disabled**, no download licence | Motion reference only; not an available animated asset or a reason to block a downloadable/generic alternative |

The API endpoints are `https://api.sketchfab.com/v3/models/<model-id>`.
Zero animation clips does not prove that rigid parts cannot be animated; it also
does not establish an opening hinge. Keep both in candidate research, not the
verified-model ledger. These additions do not start Sega implementation or replace
the active first-console GBA acceptance work.

The owner authorized expanding the reference model collection from Sketchfab,
using [their liked models](https://sketchfab.com/Darkaxt-Remaxku/likes) as the
shortlist and the [cartridge search](https://sketchfab.com/search?q=cartridge&type=models)
for remaining coverage gaps. Do not change likes or bulk-download unrelated hits.
Downloaded originals remain in the owner's requested `D:/Downloads`; keep later
prepared geometry/reference processing on E:. Do not bundle concept-game artwork or add new
console support merely because its case is available. Preserve acquisition and
export provenance, then inspect actual meshes, materials, pivots, UVs and
opening behavior before admitting a model to S25_VERIFIED_MODELS.md. Source
collection does not bypass the one-console-at-a-time native review checkpoint.

Original archives acquired through the signed-in normal download flow:
`cover-games.zip` (SHA-256 `9f604edd9de1c4fca21d4e72a63e5926fa1cddc01b792d9abe66ba5fa5c38012`),
`kittella-genesis-case.zip` (`e256b49bcd5d550fb8187fe3e019fc99b64d57eee7373e8b99a0d19ddbb9a85c`),
and `dvdgame-case.zip` (`c9fe0569ce40a633a98f4cab5ab625e50370370faa0322971935e66545ea9803`).
Acquisition does not establish renderer/animation acceptance. Other liked sources
remain to be downloaded/inspected after the current GBA checkpoint.

### Owner-provided GBA cartridge and protector GLB — 2026-10-18

Source: `D:/Downloads/Gameboy_Advance_Cartridge-25bd1b56.glb`, preserved unchanged.
Size: 9,974,256 bytes. SHA-256:
`17d1fa5c2cc20954afccdb6b809bd585ab65175ffe36e0c587534f526c0baec1`.
Its embedded provenance identifies luigi_30, Sketchfab model
`25bd1b56c5b94d59884abd077156bde4`, exporter
`sketchfab-osgjs-converter` 1.0.0 and converter commit
`79290fa0cfb4714f4c0d7ba617b0e3b2b1296149`; the licence field is null.
Keep this owner-provided original/private reference out of public release assets.

Fresh read-only binary inspection verifies a glTF 2.0 GLB with exact declared
container length, in-bounds buffer views/accessors, finite geometry attributes,
matching position/normal/UV counts and valid triangle indices. The 12,264
triangles divide into four separate meshes: cartridge (2,880), screw (580),
protector base (4,256) and lid (4,548). Both materials have base colour, packed
metallic/roughness, normal and emissive maps: eight decodable 2048x2048 PNGs,
all embedded. No external buffer/image, required extension, animation clip or
skin is present. The protector material uses alpha blending.

The cartridge is offset beside the open protector and node transforms are baked
into vertex positions; this is not a closed assembly or an authored hinge rig.
The separate lid/base permit investigating a rigid-part opening adaptation,
but no opening action is verified. Remaining GBA admission work: normalized fit
and orientation, actual hinge/pivot, correct transparency and matte-plastic
appearance, replaceable game-label UV/mask, and native inspection.
Do not infer metallic plastic merely from `metallicFactor: 1`: the case's packed
metallic channel is zero and the cartridge map is predominantly nonmetallic.
No cinematic or second-console implementation was started by this inspection.

Desktop rendering subsequently passed in official portable Blender 5.2.2 LTS
(`D:/Tools/Blender/blender-5.2.2-windows-x64`). Its Windows ZIP matched the
[official SHA-256 list](https://download.blender.org/release/Blender5.2/blender-5.2.2.sha256):
`3849d17a682cba006075aaa3f3597ecb5c9c30ec31035b2e092c53e40679b535`.
The background, factory-startup inspection disables auto-execution and uses two
CPU threads. `scripts/fixtures/s25_gba_blender_inspection.py` imported all four
parts/eight images and completed three renders with the original GLB hash
unchanged. Front/back assembly and detailed cartridge renders were visually
inspected: upright readable source label, textured housing/screw and transparent
protector, without visibly scrambled textures. The source housing is glossy;
this is not acceptance of the required matte finish or another game's label.
No MCP server, global PATH/file associations or existing model was changed.
Private retained report/renders are under
`E:/R-Shop Reference Assets/Sketchfab/25bd1b56c5b94d59884abd077156bde4/inspection-20261018`.
Desktop source rendering is not Thor integration, opening-animation verification
or a replacement for the current GBA collection acceptance checkpoint.

### Box scans and sleeves

- [NintAndBox Archive](https://archive.org/details/nintandbox-2026): the public
  [item metadata](https://archive.org/metadata/nintandbox-2026) lists one
  `Nintandbox.org.7z`, **42,436,388,695 bytes**. New header-only inspection reads
  599,996 bytes in nine validated HTTP 206 ranges per pass and parses the real 7z
  file table. It contains 50,470 entries: 8,083 directories, 42,367 JPGs and 20 TXT
  files, with 43,433,487,229 declared uncompressed bytes. No image-content or
  payload-CRC validation follows from filenames. The uploader's "5,700+ scans"
  is not 5,700 distinct games or complete boxes. Metadata's `filecount=42182`
  disagrees with the inspected table; use the inspected counts below.
- The archive contains only the eight Nintendo families below, not Sony/Sega/
  Atari. It is LZMA2, **solid, six compression blocks**. Header/index range reads
  are cheap; independent image extraction is not demonstrated to be cheap.
  Download/import once on the desktop, then serve normalized individual resources
  from Drive. Do not make the Thor repeatedly fetch/decompress the solid archive.
  Public checksums: SHA-1 `1830d151c710090b75c73a758aa99cf161eff4dd`, MD5
  `1fc7eb0f2f29d4729de9ff3db0a361a1`. No reuse licence is supplied by item metadata.
- [NintAndBox.es Sapphire](https://www.nintandbox.es/gameboy-advance/pokemon-zafiro)
  describes a complete printable flat box with front, rear and side flaps, labelled
  Spanish/PAL-Spain. Downloads require an account; some items require credits.
  This verifies the listing, not downloaded bytes, panel coordinates or compatibility
  with a US edition. Restored/printable art is not automatically an untouched scan.
  Do not assume the .es catalogue and the archived .org collection are identical.
- The [current .es index](https://www.nintandbox.es/) lists seven Nintendo
  families: Game & Watch 14, GB 103, GBC 27, GBA 80, NES 123, SNES 112, N64 64;
  custom categories are separate. Counts are listings, not unique-game coverage.
  [Store](https://www.nintandbox.es/store): 100/600/1500 credits cost
  EUR 2.49/4.99/9.99; accounts are required and some downloads spend credits.
  Per-item cost, automated API access and daily quota were not established.
  Do not interpret absent quota documentation as unlimited access. No purchase.
- Treat archive `.org`, the `.es` service and historic `.net` as different sources.
  The current `.net` page serves unrelated gambling content; exclude it. The `.org`
  root supplies no usable catalogue in this pass. Neither proves the archive or
  `.es` is unavailable. `.es` mentions newer systems in promotional text but its
  actual listed categories here do not establish non-Nintendo coverage.
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

### Inspected NintAndBox file-table coverage

"Box titles" means title directories containing a filename typed `-Box`, not a
canonical-game match against the owner's library. "Box sets" are resource folders
including regional variants/customs. A front/back filename pair may be two halves
of a printable net; it does not prove six separately mapped textures.

| Archive family | All title folders | Box titles | Box sets | Box JPGs | Manual pages | Label JPGs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Game & Watch | 61 | 61 | 85 | 170 | 851 | 0 |
| Game Boy | 342 | 164 | 192 | 384 | 1,934 | 377 |
| Game Boy Advance | 208 | 185 | 192 | 384 | 260 | 57 |
| Game Boy Color | 112 | 95 | 102 | 204 | 580 | 56 |
| NES / Famicom | 506 | 460 | 623 | 1,247 | 17,877 | 498 |
| Nintendo 64 | 375 | 331 | 473 | 946 | 1,902 | 415 |
| SNES / Super Famicom | 737 | 674 | 846 | 1,693 | 11,522 | 680 |
| Virtual Boy | 12 | 12 | 15 | 30 | 0 | 0 |
| Total | 2,353 | 1,982 | 2,528 | 5,058 | 34,926 | 2,083 |

GBA box filenames divide into EUR 336, AME 30 and ASI 18 (192 folders total).
This is a strongly Europe-weighted source, not complete US/Japan GBA coverage.
Customs and product codes must remain explicit; AME/ASI are archive labels, not
an automatic proof of a particular release region. Names may differ across
resources. Match platform, edition/product code and region, not title alone.

### Other manufacturers and acquisition limits

| Source | Useful coverage / data | Integration decision / limits |
| --- | --- | --- |
| [The Cover Project](https://www.thecoverproject.net/) | Broad Nintendo/Sega/Sony/Atari/NEC/SNK and computer categories; retail/custom wraps, raw scans, disc art and some manuals | Important supplemental source. Indexed primary entries expose region and **case type**: [Genesis example](https://www.thecoverproject.net/view.php?cover_id=16186) targets a Universal Game Case; [Saturn example](https://www.thecoverproject.net/view.php?game_id=6499) is custom DVD packaging; [PS2 example](https://thecoverproject.net/view.php?cover_id=3083) targets a standard DVD case. Fit that template, not an assumed original box. Direct pages return HTTP 403 here; indexed catalogue evidence is not successful authenticated byte retrieval. API, bulk permission and daily limits are unverified; no bypass or unlimited-access claim. |
| [Sega Retro](https://segaretro.org/Category:Box_scans) | Sega hardware families and cross-platform physical scans, including box fronts/backs/spines and media scans | Valuable original-edition supplement, not a ready scraper. Categories contain accessories/hardware, bad scans and alternate editions. No automatic crawl is planned; current robots restrictions must be respected. |
| [LaunchBox](https://gamesdb.launchbox-app.com/) | Broad platform/game identities and typed artwork; original and reconstructed categories differ | Preserve the already specified primary box-face role. Public index/image retrieval still needs real end-to-end verification. A Box-3D picture is not a mesh. No key/quota/unlimited claim is inferred from a public page. |
| [ScreenScraper API](https://www.screenscraper.fr/webapi2.php) | Front/back/side/wrap/source scans, physical labels, PDF manuals and other existing metadata/media | Existing authenticated fallback; honor returned account limits. Typed selectors alone do not establish media availability. Keep roles and regional bindings. |
| [GameTDB Wii/GameCube](https://www.gametdb.com/Wii/HomePage), [DS](https://www.gametdb.com/DS), [Switch](https://www.gametdb.com/Switch/HomePage) | ID-keyed regional cover/wrap/disc/label resources; Wii U/PS3 are also advertised | Strong supplementary lead for exact product IDs. Site says downloads need no signup and packs update weekly; that is not proof of unmetered API use or every game's six faces. No new provider implementation is authorized by this review. |
| [PSX Data Center](https://psxdatacenter.com/games/P/S/SCES-02430.html) | Sony serial/region-bound front/back/interior/disc examples; PS2 entries also available | Curated supplement with explicit missing scans; no API/bulk contract established. |
| [Atarimania](https://www.atarimania.com/) | Active Atari 2600 and ST scans/catalogue | Suitable specialist lead, not proof of coverage for every Atari console. |
| [Generation MSX](https://generation-msx.nl/) | MSX releases, media and documentation | Specialist lead; exact selected-edition resources and automated access remain unverified. |
| [EmuMovies](https://emumovies.com/files/file/2388-neo-geo-pocket-color-2d-boxes/) | Additional front-cover packs, manuals and pre-rendered sets | Optional curated import; account/download tier may apply. PNG "3D box" packs are not rotatable models. [Atari ST pack](https://emumovies.com/files/file/3911-atari-st-3d-boxes-pack/) explicitly reuses/recreates art across platforms, so do not present it as original-edition evidence. |

The Cover Project also lists Xbox families, but they are absent from the current
66-platform catalogue. Record this as source reach, not new Xbox support. Other
computer/obscure-console rows below remain gaps where no specialist was verified.
Do not substitute gameplay screenshots from general museum pages for packaging.

### Extra resources and manual presentation

The archive also names **213 flyer images, 48 map pages, 15 inner-tray images,
13 accessory-box images, eight hardware-box images and three audio-CD images**.
The 20 remaining files are TXT; they are not artwork. Hardware/accessory boxes
must not enter a game's box animation. Labels do not prove protector geometry.

Owner addition: evaluate readable manuals and including them in the package
presentation. Proposed behavior is an optional manual/booklet prop revealed
between case and medium when the correct language/edition manual exists, plus a
separate page/PDF viewer with touch/controller page navigation and zoom. This
does not require modelling every page or implementing a page-turning physics rig.
Missing manuals skip that layer; they must not block launch or box/cartridge
acceptance. Maps/flyers can live in the Media/Documents gallery without being
mistaken for covers. A scanned inner tray is reference imagery, not a 3D mesh.

Keep original ordered JPG pages; a PDF may be an additional derived reading
artifact with original page provenance. Cover scan JPGs must not become manual
pages merely because their sizes resemble one. Language preference and explicit
original/reconstructed status apply to documents as well as artwork. Documents
use the existing Drive-backed resource/cache direction, not an uncapped SD mirror.

### Reference preservation versus final classified Drive content

Latest owner instruction: keep the original archive and reference-only material
under **E:/R-Shop Reference Assets/NintAndBox/2026-03**. Do not upload the archive
or a raw, unclassified copy of all scans. Temporary acquisition scripts remain
task-owned D:/Temp output; the E: reference is intentional persistent content.

S25 ingestion should map archive console folders to current IDs, then retain the
exact edition/product code, archive region label, language, custom/original status
and source filename. A title-folder count is not an automatic canonical-game map.
Inspect actual image content and printable-panel layout before admitting final
front/back/spine/outer-net/label roles. In particular, `Box(Front)`/`Box(Back)`
filenames can describe parts of a printable layout, not final cover crops.

Publish only matched, classified resources through the existing normalized
console/game-or-edition/typed-resource tree and its metadata/index integrity
records. Preserve existing valid S24 resources; do not overwrite a cover with a
whole dieline, a foreign edition, a screenshot or a manual page. Keep ordered
manual pages/PDF separate from game covers. Unresolved identity, role, layout or
language remains local reference, not a guessed entry uploaded to the active tree.
The integrated S25 plan owns this classification/publication and verifies remote
bytes plus actual viewer consumption; archive acquisition alone does not satisfy it.

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
installation or model redistribution was performed for this review. The full
archive download is now separately owner-authorized; its result is tracked
below, not inferred from this listing research.

### Additional simple geometry candidates

| Key | Candidate | Verified listing/API facts | Decision |
| --- | --- | --- | --- |
| B | [Kenney Furniture Kit closed cardboard box](https://kenney.nl/assets/furniture-kit) | **Actual ZIP inspected**, CC0; closed/open box in GLB/OBJ/DAE/FBX/STL. Closed OBJ has 20 positions, 34 UV entries and 120 face records; bounds 0.2125 x 0.281 x 0.2125 in source units | Recommended simple starting outer shell. Its palette materials are named wood/woodDark; replace/remap those for matte printed cardboard and six role-specific artwork surfaces. Existing UVs are not a game-box dieline recipe. No rig/opening acceptance. |
| B-alt-1 | [Spectacular outer box](https://www.blendkit.com/asset-gallery-detail/4e49dd6b-2a91-4894-a83e-2ee847a6ef2c/) | Free listing, 510 polygons, 20.1 MiB, Royalty Free; outer box only | Candidate resizable closed cardboard shell. Need six editable surface UVs and remove example artwork. A board-game shape is not automatic original Nintendo geometry. |
| B-alt | [Splatoon Game Box](https://sketchfab.com/3d-models/splatoon-game-box-b088d4263eab4d47ad6e34383cd967de) | Public API: downloadable, CC BY, 28 faces, zero animations | Minimal closed rectangular display-shell alternative; actual UVs/material separation still uninspected. Not an opening rig or cardboard-authenticity claim. |
| K | [DVD/Game Case](https://sketchfab.com/3d-models/dvdgame-case-d5c542e24bee490fbdf130413983f124) | Public API: downloadable, CC BY, 1,335 faces, zero animations; creator states UV mapped | Prefer inspecting this and the existing NateSquared case for the broad closed keep-case. Neither establishes an opening animation. |
| K-alt | [DVD/PS2/Wii case](https://sketchfab.com/3d-models/dvdps2wii-case-60c2e703f9764cd6885811452802b3aa) | Public API: downloadable, CC BY, 4,288 faces, zero animations | More specific closed-case lead; artwork examples are not included automatically. |
| J | [CD jewel case](https://sketchfab.com/3d-models/cd-jewel-case-1d8cd4cc061e44e3a6ae3eabd4746647) | Public API: downloadable, CC BY, 2,567 faces, zero animations | Candidate jewel-case family for compatible releases; thick PAL/multidisc variants need different presets/parts. |
| J-alt | [Low-poly jewel case](https://sketchfab.com/3d-models/low-poly-jewel-case-free-c1dea15b643d4b6da3b9104a067d9ffc) | Public API: downloadable, CC BY, 946 faces, one material/256px example texture, zero animations | Lightweight alternative; inspect face separability/UVs before choosing. |
| S | Switch Blendkit model above | Actual case/card and rig are advertised | Best specific protector lead, not a cardboard outer-box model. File/rig conversion remains unverified. |
| P | PSP Fab model above | Case and UMD-style holder with opening mechanisms advertised | Strong specific case lead; checkout/price and actual parts need inspection before acquisition. No purchase. |
| G | GB/GBC/GBA MakerWorld model above | Printable replacement protector | Geometry lead only; not original packaging, UV-ready art or an animation. |

Kenney source ZIP: 5,130,729 bytes, SHA-256
`e67652d0932cee41683f74711c03d3e192a2af9979ef8e6b237711f5482d46b0`;
original `License.txt` and actual matching model entries were present. Inspection
was in memory only, with no new installed runtime, generated image or disk copy.
This is stronger than a listing, but not conversion/rendering acceptance.

Rejected false positives: [Nintendo Game Box](https://sketchfab.com/3d-models/nintendo-game-box-028905dbefa44054980df3a43a20d30e)
is described as a multi-game carrying case; [Kittella Genesis Case](https://sketchfab.com/3d-models/kittella-genesis-case-0ad483dab1c84c50bfd6f266762cdc75)
is a fictional package design. Neither proves the requested original retail
protector. DS searches also returned console shells, shelf holders and multi-card
organizers; these are not accepted DS retail cases. No dedicated DS, 3DS, Vita,
Mega Drive or Master System opening case has been verified in this pass.

CC BY candidates require attribution. [Blendkit licensing](https://www.blendkit.com/docs/licenses/)
allows higher-level derivative works but restricts standalone asset resale;
Royalty Free is not CC0. Resolve the actual asset's redistribution terms before
bundling. Preserve the existing original-APK import boundary for Socket models.

## Per-platform availability checklist

Fresh source inspection: `SystemModel.supportedSystems` contains **66 IDs**.
`PhysicalMediaFormat.forSystem` explicitly binds **20 IDs** (19 console families
plus DSi's physical-card alias) to **16 imported media variants**. All 66 have
the existing flat fallback coverage documented in S9. That does **not** mean 66
console-specific 3D cartridge models or complete packaging sequences.

**All 66 current IDs are listed individually.** These are source leads and existing
final-medium bindings, not 66 newly accepted 3D packages. `Flat` means the current
flat fallback, not an unusable game. `Gap` means no suitable protector file was
verified; `B/K/J/S/P/G` refer to the candidate families above, not installed assets.

Artwork keys: `N` inspected NintAndBox archive (box-title count in parentheses);
`E` .es catalogue; `T` The Cover Project indexed category; `R` Sega Retro category;
`D` GameTDB; `X` PSX Data Center; `A` Atarimania; `M` Generation MSX. `L/Scr`
means the broad LaunchBox/ScreenScraper candidate path, **not** verified complete
face/document availability. Refer to source access limitations above.

An outer `B?` is optional reconstructed packaging only when the selected edition
has applicable art; do not automatically add it outside every plastic case.
Case `K?`/`J?` is a proposed adaptation, not an original-platform fit claim.

### Nintendo

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `nes` NES/Famicom | N (460), E, T, L/Scr | B | Sleeve gap | NES cartridge | N manuals, labels, maps, flyers |
| `snes` SNES/SFC | N (674), E, T, L/Scr | B | Gap | US/PAL cartridge variants | N manuals, labels, maps, trays |
| `n64` Nintendo 64 | N (331), E, T, L/Scr | B | Gap | N64 cartridge | N manuals, labels, trays |
| `gc` GameCube | T, D, L/Scr | B? only if supplied | K?; specific paid model listed | Shared disc | Provider/manual availability per game |
| `wii` Wii | T, D, L/Scr | Normally skip extra layer | K / K-alt | Shared disc | Provider/manual availability per game |
| `wiiu` Wii U | T, D, L/Scr | Normally skip extra layer | K? / B-alt | Shared disc | Provider/manual availability per game |
| `switch` Switch | T, D, L/Scr | Skip by default | S | Switch card | T includes manual-only entries; per-game check |
| `gb` Game Boy | N (164), E, T, L/Scr | B | G replacement; original tiny protector gap | GB cartridge | N manuals, labels, trays, maps |
| `gbc` Game Boy Color | N (95), E, T, L/Scr | B | G replacement; original protector gap | Two GBC variants | N manuals, labels, flyers |
| `gba` Game Boy Advance | N (185), E, T, L/Scr | B | G replacement; original protector gap | GBA cartridge | N manuals, labels, trays; verified S24 sample |
| `nds` Nintendo DS | T, D, L/Scr | Skip unless edition warrants | K?; specific retail-case gap | DS card | Manual source must be checked per edition |
| `virtualboy` Virtual Boy | N (12), T, L/Scr | B | Gap | Flat cartridge | N has boxes only; no manuals/labels in this archive |
| `fds` Famicom Disk System | T, L/Scr | B? | Disk sleeve/case gap | Flat disk | No separate FDS folder in N; per-game documents |
| `dsi` Nintendo DSi | D/L/Scr; T DS where physical | No physical packaging for DSiWare | DS adaptation only for physical releases | DS card binding, not proof for DSiWare | Digital manuals only if actually supplied |
| `n3ds` Nintendo 3DS | T, L/Scr | Skip unless edition warrants | K?; specific retail-case gap | 3DS card | Per-game documents |
| `gameandwatch` Game & Watch | N (61), E, L/Scr | B | No removable-game protector | Flat device/neutral | N manuals/flyer; animate device, not imaginary cart |

### Sony

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `psx` PlayStation | T, X, L/Scr | B? edition-specific | J; PAL/multidisc/longbox variants unverified | Shared disc | X front/back/interior/disc; missing pages explicit |
| `ps2` PlayStation 2 | T, X, L/Scr | Skip extra layer by default | K / K-alt | Shared disc | X and provider documents per game |
| `ps3` PlayStation 3 | T, D lead, L/Scr | Skip extra layer by default | K?; distinct Blu-ray-style geometry gap | Shared disc | No global manual coverage established |
| `psp` PlayStation Portable | T, L/Scr | Skip extra layer by default | P | UMD shell | Manual/booklet is a per-game resource |
| `psvita` PlayStation Vita | T, L/Scr | Skip extra layer by default | K?; dedicated Vita case gap | Vita card adaptation | Per-game digital/printed distinction |

### Sega

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `mastersystem` Master System | R, T, L/Scr | B? for applicable editions | Clamshell gap; K? generic only | Flat cartridge/card | R scans/manual leads |
| `megadrive` Mega Drive/Genesis | R, T, L/Scr | B for cardboard editions only | Clamshell gap; K? generic only | Genesis/Mega Drive variants | R physical scans; T UGC is not original clamshell |
| `gamegear` Game Gear | R, T, L/Scr | B? | Tiny protector gap; replacement K? | Flat cartridge | R regional media/manual examples |
| `segacd` Sega CD | R, T, L/Scr | B? selected edition | J?; longbox/regional case gap | Flat disc | R cover/disc/manual leads |
| `sega32x` Sega 32X | R, T, L/Scr | B? | Gap | Flat cartridge | Source documents per game |
| `dreamcast` Dreamcast | R, T, L/Scr | Skip extra layer by default | J; regional/multidisc differences unresolved | Shared disc | Source scans/manuals per game |
| `saturn` Saturn | R, T, L/Scr | B? | J?; longbox gap; T custom DVD uses K | Flat disc | R cover/spinecard/disc/manual examples |
| `sg1000` SG-1000 | R, L/Scr | B? | Gap | Flat cartridge/card | No global documents coverage established |

### Atari

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `jaguar` Jaguar | T, L/Scr; EmuMovies front pack | B? | Gap | Flat cartridge | Front pack is not full box/manual coverage |
| `atari2600` Atari 2600 | A, T, L/Scr | B? | Gap; T UGC replacement K? | Flat cartridge | A scans; edition differences remain distinct |
| `atari5200` Atari 5200 | T, L/Scr | B? | Gap | Flat cartridge | Provider documents per game |
| `atari7800` Atari 7800 | T, L/Scr | B? | Gap; T UGC replacement K? | Flat cartridge | T replacement case type must be retained |
| `lynx` Atari Lynx | T, L/Scr | B? | Gap | Flat card/cartridge | Provider documents per game |
| `jaguarcd` Jaguar CD | T, L/Scr | B? | J? | Flat disc | No complete packaging/document set verified |
| `atarist` Atari ST | A, L/Scr | B? | Per-edition disk box/sleeve gap | Flat legacy media | A scans; reconstructed EmuMovies pack is not original |

### NEC, SNK, Bandai and other cartridge consoles

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `tg16` TurboGrafx-16 | T, R lead, L/Scr | B? | HuCard/jewel adaptation gap | Flat card | Per-edition box/card/document check |
| `tgcd` TurboGrafx-CD | R lead, L/Scr | B? | J? | Flat disc | Regional packaging/documents unverified |
| `ngp` Neo Geo Pocket | T, L/Scr; EmuMovies front pack | B? | Protector gap | Flat cartridge | Front pack has 40 JPGs; no complete faces implied |
| `neogeocd` Neo Geo CD | T, L/Scr | B? | J? | Flat disc | Per-edition documents |
| `wonderswan` WonderSwan | T, R lead, L/Scr | B? | Protector gap | Flat cartridge | Per-edition documents |
| `colecovision` ColecoVision | T, L/Scr | B? | Gap | Flat cartridge | No full-set documents proof |
| `intellivision` Intellivision | T, L/Scr | B? | Gap | Flat cartridge | Instructions/overlays must be separate roles |
| `vectrex` Vectrex | L/Scr | B? | Gap | Flat cartridge | Screen overlay, if supplied, is not box art |
| `channelf` Fairchild Channel F | L/Scr | B? | Gap | Flat cartridge | Specialist source gap |
| `odyssey2` Odyssey 2 | T, L/Scr | B? | Gap | Flat cartridge | Per-edition documents |
| `pcfx` PC-FX | T, L/Scr | B? | J? | Flat disc | No integrated case/documents proof |
| `cdi` Philips CD-i | T, L/Scr | B? | J/K? based on actual edition | Flat disc | Case family cannot follow extension alone |
| `3do` 3DO | T, L/Scr | B? | J/K?; longbox gap | Flat disc | Per-edition documents |
| `ngage` N-Gage | R lead, L/Scr | B? | Specific case gap | Flat card | Per-edition documents |
| `arcadia2001` Arcadia 2001 | L/Scr | B? | Gap | Flat cartridge | Specialist source gap |

### Computers, arcade and virtual systems

| ID / system | Artwork inputs | Outer box | Protector/case candidate | Existing final medium | Extra-resource evidence |
| --- | --- | --- | --- | --- | --- |
| `msx` MSX | M, R lead, L/Scr | B? | Cassette/disk/cart-specific gap | Flat legacy media | Specialist media/docs; do not infer format from ZIP |
| `amstradcpc` Amstrad CPC | R lead, L/Scr | B? | Cassette/disk case gap | Flat legacy media | No new full-set source verified |
| `c64` Commodore 64 | R lead, L/Scr | B? | Cassette/disk/cart case gap | Flat legacy media | No new full-set source verified |
| `vic20` VIC-20 | R lead, L/Scr | B? | Cassette/cart case gap | Flat legacy media | No new full-set source verified |
| `amiga` Amiga | T, R lead, L/Scr | B? | Disk-box/sleeve gap | Flat legacy media | Specialist HOL unavailable in this pass |
| `zxspectrum` ZX Spectrum | R lead, L/Scr | B? | Cassette case gap | Flat legacy media | Spectrum Computing unavailable in this pass |
| `oric` Oric | L/Scr | B? | Cassette/disk case gap | Flat legacy media | Specialist source gap |
| `x68000` Sharp X68000 | R lead, L/Scr | B? | Disk case gap | Flat legacy media | Edition-specific media and documents |
| `x1` Sharp X1 | R lead, L/Scr | B? | Tape/disk case gap | Flat legacy media | Edition-specific media and documents |
| `fmtowns` FM Towns | R lead, L/Scr | B? | J? plus edition-specific disk gap | Flat legacy media | No complete set established |
| `appleii` Apple II | R lead, L/Scr | B? | Disk sleeve/case gap | Flat legacy media | No complete set established |
| `dos` DOS | T, L/Scr | B? | Disk/CD family selected by edition | Flat legacy media | Manuals/maps/copy-protection references if supplied |
| `arcade` Arcade | L/Scr | Do not fabricate retail carton | No universal consumer protector | Flat neutral/media | Flyers/manuals may be useful separate resources |
| `tic80` TIC-80 | Provider/author art only | Virtual presentation only | Not a physical protector claim | Flat virtual cartridge | Author-supplied docs if available |
| `pico8` PICO-8 | Provider/author art only | Virtual presentation only | Not a physical protector claim | Flat virtual cartridge | Author-supplied docs if available |

### Planning evidence and independent acquisition checklist

The full plan below does not depend on completing the archive download or
inspecting every model candidate. File/panel inspection belongs to implementation.
The reference transfer continues independently on E:; it is not a planning gate.

- [x] Inventory every current platform ID; distinguish 20 existing 3D bindings
  from 46 flat fallbacks and from new packaging support.
- [x] Inspect NintAndBox's real archive membership and per-family typed-file counts.
- [x] Establish Nintendo-only archive reach, regional bias and solid-block limit.
- [x] Identify broad non-Nintendo art sources, case-type metadata and access limits.
- [x] Identify small reusable outer/keep/jewel meshes and specific Switch/PSP leads.
- [x] Inspect one actual small CC0 outer-box model pack and identify its UV/material
  adaptation requirement; preserve other candidates as listing/API evidence.
- [x] Identify manuals/labels/maps/flyers/trays separately from box coverage.
- [x] Complete and hash-verify the owner-authorized full archive download on E:
  (2026-10-17, exact 42,436,388,695 bytes and required SHA-1; supervised exit 0).
  Only classified final resources go to Drive; source preservation is not ingestion.
- [ ] Inspect actual selected mesh files/UVs/materials/pivots and settle one base
  per required family; listing/API metadata is not file acceptance.
- [ ] Inspect real image panels and document order in the acquired archive; derive
  explicit layout mappings for the chosen GBA editions, not guessed crop ratios.
- [x] Define the full S25 capability contract and execution plan below, including
  manual access/optional presentation, before changing Android behavior.

## Integration recommendation and acceptance

1. Finish this review before starting S25 implementation. Keep the ledger honest
   about sourced, downloaded, converted, integrated and native-verified evidence.
2. Start with GBA and the existing real ranked sample. Prove same-edition typed
   artwork -> normalized Drive resource -> bounded local cache -> actual box/case
   surface -> cartridge label. A Spanish Sapphire listing does not authorize
   attaching that Spanish box to a US edition. Generic geometry can be reused;
   regional artwork identity cannot be guessed.
3. Start with the small CC0 outer-box shell, then the minimum applicable
   keep-case/jewel/specific protector families, with proper seam/hinge where
   appropriate. Do not model 66 bespoke boxes. Source-specific meshes are upgrades only when their actual
   files, mapping and current console requirements justify them. Existing GPU
   code draws indexed surfaces with transforms; the importer expects its pinned
   JSON/binary Socket format. It does not currently make arbitrary GLB/FBX files
   or skeletal rigs ready to use. Static face/surface conversion and rigid hinge
   transforms should be assessed before adding a general skeletal-animation
   dependency; a rigged listing does not require such an engine.
   Conversion/adaptation must preserve the existing
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

## Full S25 capability contract and execution plan

Planning checkpoint: 2026-10-17; subsequently S25 became **ACTIVE** under the
owner's explorer/model-validation-first instruction. These are
ordered work packages inside the existing S25 stage, not additional stages or
parallel fronts. No archive, model purchase, second account or complete six-face
collection is a prerequisite for defining the plan. When implementation resumes,
keep S25 ACTIVE until its complete integrated acceptance criteria pass.

### Capabilities and deterministic fallbacks

| Available input | Presentation | Required fallback / boundary |
| --- | --- | --- |
| Correct outer-box panels | Parameterized matte cardboard outer box | Missing faces use colour-matched reconstructed material, not a fictitious original scan |
| Correct front/back/spine sleeve | Plastic display case fitted to panel aspect and compatible depth | Visible seam and hinge; generic plastic on unprinted edges; distinguish display-case adaptation from original retail geometry |
| Only a front cover | Reconstructed box/display case with that real front | Neutral remaining faces; full rotation/zoom still work; never substitute screenshots |
| No cover | Existing named flat/handwritten fallback and available medium | Skip the cover-slide animation when no artwork exists to slide; no empty black square |
| Valid imported model and label | Existing 3D cartridge/card/disc with its correct label | No new dependency on acquiring Socket assets; default flat media remain usable |
| No imported/specific platform mesh | Existing flat medium with game-name fallback | No false platform-specific 3D claim; preserve all 66 current platform paths |
| Correct-language manual | Ordered page/PDF reader and optional booklet layer | Missing manual skips that layer; no page-turn physics requirement |
| Screenshots/trailers/maps/flyers | Typed Media/Documents gallery | Preserve resource identity, saved audio and bounded offline cache; never fabricate unavailable content |

Select packaging per edition, not ROM extension. Use a small set of cardboard,
keep-case and jewel-case presets; inspect Switch/PSP-specific assets as upgrades.
An unavailable specialist file does not block the owner's generic display-case
path. Do not automatically put protectors around every cartridge. Ordinary Switch
uses case -> card. GBA cardboard and a replacement display case are distinguishable
alternatives, not a claim that both shipped together. A real multilayer edition
may use outer box -> protective case -> medium, with an optional booklet.

Geometry uses six named surfaces: front, back, left, right, top, bottom. Preserve
orientation, source dimensions, crop/UV recipe, source ID/URL, edition, region,
language, checksum and original/custom/reconstructed status. Derive width/height
from the actual panel aspect and depth from a compatible spine or preset, never
the whole printable sheet. Missing faces use generic material or coherent spine
reuse. Two Japan-labelled spines do not prove two physical faces. Cardboard and
ordinary plastic are nonmetallic; disc material remains separate. Closed meshes
rotate/slide, not pretend to open. Verified rigid-part opening may be used without
requiring a general skeletal-animation engine.

### Interaction and lifecycle contract

- Compact icon-backed **Box / Cartridge / Media** modes replace the single model
  action. Remove per-entry Download Media, not central collection/scraping.
  Manuals/maps/flyers are within Media/Documents, not another settings roll.
- L1/R1 cycles modes when the viewer owns interaction. Touch drag and controller
  directional/stick input rotate; pinch and visible zoom controls change zoom.
  Provide Reset view and applicable input hints. Normal main-gallery scrolling,
  tab navigation and focus remain untouched outside explicit viewer interaction.
- Use the same selected-edition resources on single/dual screens. Preserve Thor's
  4x2 gallery, early secondary initialization, activated details and browsing focus.
- Hold the mounted cover until selected model/labels and enabled resources report
  ready; then run the existing 1.5-second full-left reveal and zoom restoration.
  Resource updates must not discard ready textures or replay the same selection.
  Changing game/edition cancels its old reveal, not the durable collector.
- Reduced Motion retains static access to all layers/modes. Missing artwork omits
  its animation. An absent optional manual does not freeze launch/browsing; a
  failed required sample resource is explicitly reported, not a passing test.
- Trailers reuse saved internal volume and background-music duck/restoration.
  Switching selection, leaving playback or hiding/launching releases playback
  appropriately. Hide R-Shop on launch without closing/reparenting the companion.
- Preserve cached browsing, five-second freshness hint and adjustable 2 GiB cache
  leases/eviction. No startup bulk sync, raw archive on SD or whole-library scrape.

### Ordered implementation work inside S25

1. **One complete real GBA viewer workflow first.** Use the supplied LaunchBox
   007 record and actual selected release. Retrieve coherent faces, validate bytes
   and roles, publish via existing typed Drive metadata, consume via bounded cache,
   render the fitted plastic case and current GBA cartridge. Include modes,
   seam/hinge, rotation/zoom, readiness/reveal and focus in this complete first
   workflow. Exercise missing/incomplete primary data with compatible ScreenScraper
   faces or reconstructed missing faces. No general artwork-provider framework.
2. **Complete packaging families and classified-reference ingestion.** Adapt the
   inspected CC0 outer shell to six semantic faces; retain any CC BY attribution.
   Convert static geometry/rigid parts to existing indexed surfaces/transforms
   through an owned-geometry path, without forging Socket import receipts or
   introducing another renderer. Finish applicable keep/jewel/display-case presets;
   inspect specialist Switch/PSP assets, using declared generic alternatives when
   unusable. For acquired archive images inspect layouts, match actual editions
   and derive validated faces/manuals/labels. Keep raw references on E:, publish
   only classified matching resources and integrity records. The full archive is
   useful here, not a prerequisite for work package 1.
3. **Finish the integrated gallery and documents.** Complete shared single/dual
   screen modes, touch/controller navigation, ordered manual reading/optional
   booklet, screenshots/trailers/Documents and every fallback above. Preserve
   launch, companion, audio, cache, regional grouping and save/root behavior.
   Do not open acquisition add-ons, change scoring providers or begin S26.
4. **Reconcile, verify and deliver the whole stage.** Pass the matrix below;
   resolve all S25 gaps and update this per-platform ledger with actual evidence.
   Commit/synchronize verified work. Use the existing GitHub signing workflow and
   certificate for the already requested production update, acceptance-test its
   artifact before publication, then verify published/installed bytes and preserved
   settings/imports. No intermediate-work-package release. Clean exact expendable
   outputs through the cleanup helper and switch both Thor screens off afterward.

### Existing integration points

| Area | Existing files / responsibility |
| --- | --- |
| Edition resources/collection | `lib/models/scraped_metadata.dart`, `lib/services/metadata/metadata_provider.dart`, `lib/services/metadata/metadata_refresh_jobs.dart`: extend current typed matching/collection for packaging and documents; box-only LaunchBox does not replace scoring/label/trailer providers |
| Drive/cache | `lib/services/metadata/metadata_cloud_library.dart`, `lib/services/metadata/drive_metadata_api.dart`, `lib/services/metadata/metadata_artwork_cache.dart`, `lib/services/metadata/preview_video_cache.dart`: reuse publish/integrity/ensure/lease/trim |
| Geometry/ownership | `lib/models/socket_media_model.dart`, `lib/widgets/socket_media_renderer.dart`, `lib/services/socket_mesh_import.dart`, `lib/services/socket_media_import.dart`: preserve original-APK imports; add only current-stage owned packaging geometry/material/pose support |
| Selection/display/input | `lib/features/preview/preview_screen.dart`, `lib/features/preview/dual_screen_preview_host.dart`, `lib/services/secondary_preview.dart`, `lib/providers/preview_providers.dart`: one selected edition/readiness owner, mode routing and cancellation |
| Entry/settings | Existing game-detail and sectioned preview/settings surfaces: remove obsolete entry button, preserve central collector and concise icon controls |
| Focused checks | Extend `test/preview_media_test.dart`, `test/secondary_preview_audio_test.dart`, `test/secondary_preview_lifecycle_test.dart`, `test/socket_media_model_test.dart`, `test/socket_mesh_import_test.dart`, `test/metadata_cloud_library_test.dart`, `test/metadata_refresh_jobs_test.dart`; native logs plus targeted visual evidence prove actual textures/motion |

A small face-map/packaging type or focused viewer widget is justified by actual
semantic data/input needs, not by speculative future providers. No new repository,
service or factory layer is required merely because this plan spans several files.

### S25 acceptance and evidence matrix

Every row belongs to S25 and remains pending implementation/verification. These
are complete-feature checks, not per-edit build checkpoints.

| ID | Required result | Evidence |
| --- | --- | --- |
| P25-01 | Real primary/fallback box pipeline | Supplied 007 selected GBA edition: LaunchBox -> typed matching/provenance -> Drive -> cache -> rendered faces; incomplete/absent primary exercises compatible ScreenScraper or declared reconstructed faces, never mixed regional designs |
| P25-02 | Applicable layers and geometry | Real GBA outer-panel set where available and fitted display case; keep/jewel presets and platform fallback dispatch; correct aspect/depth/orientation, matte materials, seam/hinge; no fictitious Switch cardboard/protector |
| P25-03 | Interactive gallery | Box/Cartridge/Media, rotation/zoom/reset, L1/R1, touch/controller, default/imported/missing model states, removed entry download button, red theme and no papyrus regression |
| P25-04 | Readiness/lifecycle | Current-game cover hold, 1.5-second full-left reveal, stable textures, rapid reselection, Reduced Motion, cached/offline/errors, secondary startup, retained focus and launch/companion ownership |
| P25-05 | Documents/playback | An actual compatible manual opens with page/zoom controls and optional booklet; missing manual skips; screenshots/trailers keep identity, saved volume and music restoration |
| P25-06 | Actual ranked GBA collection | Every distinct eligible game in saved Top 25 passes installed browsing: correct box, label/model, trailer/audio, finished reveal. Last baseline has 24 eligible games; read current selection, never fabricate 25 or count regional duplicates. Required failures block acceptance |
| P25-07 | Classified publication/preservation | Acquired scans inspected/classified; admitted resources match editions/roles and remote digests; source archive on E:, unresolved inputs reference-only; valid covers/ROMs/saves preserved, bounded cache, no startup bulk refresh |
| P25-08 | Production handoff | Affected checks/native matrix pass; GitHub-signed update retains signer/data/imports; public/installed bytes match; generic/adapted/specific ledger honest; expendable cleanup and both screens off |

The 66-platform inventory records source/model gaps without requiring 66 bespoke
meshes. Conversely, the mandatory real GBA sample, classified-resource workflow and
viewer interactions cannot be waived because an isolated model or unit test works.
No S25 requirement is deferred to S26; the rebranding evaluation remains separate.
