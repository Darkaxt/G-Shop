# S12 — 3D physical-media frontend

Status: ACTIVE (2026-10-14), after S10/S11 acceptance and verified S11 remote sync.
Authority: SPECIFICATION.md, revision 42, section 6f.
Authorization: owner requested review on 2026-10-12 and authorized implementation
through the all-12-stages objective update on 2026-10-13.
Scheduling: after S10 and S11; neither stage's acceptance depends on this proposal.

## Owner direction and source boundary

Reviewed all five available turns of
["Identify AYN Thor Frontends"](https://chatgpt.com/c/6acd147a-1e08-83ed-8fae-e071ea0912be).
The owner
considers R-Shop's presentation dated, wants to keep its red theme, and is
interested in studying Socket and reproducing the physical-media experience.
The explicit correction is important: actual 3D cartridge models, rotation and
insertion animations are not equivalent to ScreenScraper cartridge images or
tilted 2D cards. The observed reference includes an upper-screen cartridge and
a lower-screen insertion destination. Owner clarification, 2026-10-13: that
bottom-screen presentation is not required. Apply the main frontend's design
features to modernize R-Shop, not replace it. This supersedes the earlier
two-display rendering requirement without changing existing S8 companions.

The conversation's assistant proposed rendering frameworks and described other
products. Those claims have not been independently verified. No renderer,
framework upgrade or unrestricted public asset reuse follows from those claims.
The owner's subsequent 2026-10-13 direction explicitly authorizes private APK
inspection and reverse engineering of the supplied August reference. Models and
animations in our adaptation must match the APK, not just its general concept.
Reference study must capture geometry/proportions, material/label placement,
motion paths/timing/easing on the main display with comparison
evidence. Distribution still requires suitable provenance and reuse rights;
independently recreated or appropriately licensed assets are valid adaptations.

Concrete supplied file resolved locally: `D:/Downloads/Android/socket_release_0.3.2.apk`
(144362294 bytes; SHA-256
`ba00e36c189f9f8f024af6aac94c68913652d07bd7204aa9a385e7b332a4d0b1`).
This records the inspected file identity, not a rendering study or S12 start.
Do not commit the APK or private extraction outputs. The owner offered to pay
for version 0.7 if needed. Start with this reference and establish a concrete
missing requirement before recommending a purchase or newer reference.

## Initial static reference inspection — 2026-10-13

This is bounded source/reference investigation, not S12 implementation or stage
closure. S10 remains the sole ACTIVE implementation stage. No app installation,
Gradle invocation, APK modification or device operation was needed. Archive
members were inspected in memory; no extraction directory was created.

Fresh APK identity checks confirm the size and SHA-256 above. Android SDK
`aapt2 dump badging` identifies package `com.depmots.socket`, version name
`0.3.2`, minimum SDK 29 and target SDK 36. Thus the filename is not being used
as the sole version evidence.

### Concrete assets and entry points

The archive contains `lib/arm64-v8a/libgodot_android.so`,
`lib/arm64-v8a/libaynthor_native.so` and `assets/assets.sparsepck`.
It is a Godot application, not a library of pre-rendered cartridge pictures.
The ZIP inventory exposes thirteen exported `cart_*.scn` scene names:

- GB, GBC, GBC dual-mode, GBA, N64, NES, SNES PAL and SNES US;
- DS, 3DS, Switch, PSP and disc.

There are also thirteen imported model scene names, including
`n64_cartridge.fbx`, `uploads_files_3322711_GBA_Cartridge.fbx`,
`nds_cartridge_v2.glb`, `compact_disc.fbx` and `umd_dis.fbx`.
These are imported `.scn` resources with source-model names, **not recovered
original FBX/GLB files**. A filename is not proof of topology, UV coordinates,
dimensions, platform assignment or reuse rights.

Named resources include opaque, clear, translucent, metallic and glitter
casings; `sticker_paper`, foil sticker and separate disc-sticker materials;
and normal, roughness, metallic and ambient-occlusion textures. Relevant compiled
scripts include `scripts/cartridge.gdc`, platform-specific cartridge scripts,
`scenes/cartridge_carousel.gdc`, `scenes/platform_select_carousel.gdc`,
`scenes/transition.gdc` and `scenes/render_scale_3d.gdc`.
This identifies where model appearance and motion should be studied; it does
not yet establish animation duration, easing or transforms.

The native Thor library exposes
`Java_org_godot_plugins_aynthor_AynThorPlugin_nativeSetSurface` and
`..._nativeRemoveSurface`, and references Android native-window and Vulkan
surface functions. This is concrete evidence of a native surface bridge, not
proof of the exact upper/lower-screen choreography or of a reusable Flutter
integration. Do not import the whole engine merely because the reference uses it.

### Resource encoding and remaining evidence

Five representative members were checked: exported N64, GBA and disc scenes,
the cartridge-carousel script and the N64 platform-model script. Each has the
40-byte prefix plus 16-byte-padded payload length used by Godot's no-magic
encrypted-file envelope. For example, N64 declares 7,451 payload bytes in a
7,496-byte member; the carousel declares 8,567 in an 8,616-byte member.
This matches the layout in Godot's official
[encrypted-file implementation](https://github.com/godotengine/godot/blob/master/core/io/file_access_encrypted.cpp).
It is evidence consistent with encryption, **not successful decryption**.
No exported `script_encryption_key` symbol was found in the engine's ELF symbol
tables; no key, model geometry or decoded script has been recovered.
That was the initial inspection result; the subsequent recovery below supersedes
it, without changing the APK or relying on a newer version.

The next S12 reference work is to recover or observe the relevant geometry,
label placement and main-display motion curves, recording a
reproducible comparison before selecting the smallest rendering integration.
Private inspection remains authorized. Keep recovered proprietary material out
of the public fork unless its redistribution rights have been established.

### Verified resource recovery — 2026-10-13

The supplied build is sufficient for further reference work. A bounded scan of
the native engine's ELF `.data` section located its embedded resource key.
Candidates were tested against a scene header, then accepted only after full
AES-256-CFB decryption matched the envelope's MD5. The same key independently
validated every one of the APK's 371 `.scn`/`.gdc` envelopes. The checksum is
format-integrity evidence, not a signature or permission to redistribute assets.
Neither the key nor decrypted proprietary files were written to the fork.

GDScript tokenizer version 101 was decompressed with Zstandard and decoded using
the matching official token layout. Identifier/constant tables, token counts and
complete buffer consumption were checked. Representative binary scenes identify
Godot 4.7 and resource format 6. Their property tables, transforms, external
references and packed-scene bundles are readable; the earlier encryption finding
is no longer an obstacle to studying the animation logic.

All thirteen imported model scenes also decompressed and parsed successfully.
They include Vita geometry in addition to the exported media families listed
above; this does not establish a usable Vita frontend or platform mapping.
The visible N64, GBA and disc meshes have these concrete reference inventories
(shadow meshes are excluded from these totals):

| Reference | Visible vertices | Triangle indices | Surface roles |
| --- | ---: | ---: | --- |
| N64 | 1,420 | 3,150 | Casing and label/logo |
| GBA | 1,156 | 3,276 | Casing, cover and insides |
| Disc | 6,912 | 24,192 | Disc body and cover |

The decoded resources contain vertex/index buffers, attribute buffers, bounds,
material references and applicable LOD data. For example, N64's untransformed
casing bounds are approximately 0.045 x 0.0075 x 0.030 model units; the exported
scene then applies its own scale/orientation. These are model units, not verified
physical dimensions. Original FBX/GLB source files have not been reconstructed,
and no geometry conversion or render-comparison acceptance is claimed.

Decoded motion reference, before any runtime setting/scene overrides:

- Carousel selection defaults to 0.3 seconds. Position uses exponential ease-out;
  the selected rotation and scale use back ease-out. Selected scale is 1.4 and
  resting rotation is (-70, 0, 20) degrees. Idle motion is sinusoidal rather than
  a fixed rotating picture.
- N64 insertion begins with a 0.15-second lift/back movement and a parallel
  0.2-second rotation, followed by a 0.3-second exponential ease-in descent.
  A parallel squash and 0.2-second elastic ease-out rebound complete the sequence.
- GBA shares that structure, but its realistic-insertion setting changes the
  rotation target. An adaptation must not accidentally choose one mode while
  comparing captures of the other.
- Disc insertion adds two full cover rotations over 0.3 seconds and a final
  0.8-second linear descent, so it is not interchangeable with the cartridge
  animation.
- The transition script drives shader progress with 0.3-second sine ease-in/out
  phases. These are intentional animation intervals, not implementation wait or
  synchronization timeouts.

The main-menu launch path awaits the selected media's insertion animation before
calling its existing game launcher. The Thor manager separately initializes main
and secondary viewports, receives connection/input events, obtains the secondary
display size and supports display swapping. This establishes concrete code paths
to study, but not observed two-display choreography or a Flutter renderer choice.
Our adaptation must preserve the existing R-Shop launch pipeline and the specified
skip/reduced-motion behaviour, not copy reference coupling blindly.

Reproduction requires the exact APK hash above: inspect ELF data candidates,
validate complete encrypted envelopes, decompress GDSC/RSCC payloads with the
official formats, then read properties and token streams. The bounded inspection
ran in memory using Python 3.14's Zstandard support and the installed cryptography
library. Only its task-owned scratch inspection script was created; no recovered
assets, new dependencies, Gradle build or device installation were required.
Public records retain findings rather than proprietary code/assets or key bytes.
Runtime captures, asset provenance/reuse decisions, label composition and actual
R-Shop integration remain S12 work after S10/S11; this reference investigation
does not satisfy or close those acceptance criteria.

### Changelog review — 2026-10-13

Reviewed the creator's release posts through 0.7.0 and the visible 0.3.2
re-upload comment. These are **Socket-reported defects and changes**, not
confirmed R-Shop defects or evidence that our implementation already handles
them. They inform the existing S12 fidelity, input, identity and lifecycle
checks; they do not add unrelated Socket features to our specification.

| Relevant area | Reference evidence | Implication for our existing acceptance |
| --- | --- | --- |
| Model coverage and proportions | [0.7](https://www.patreon.com/SocketLauncher/posts/socket-0-7-0-171412020) adds regional Genesis/Mega Drive models; [0.5](https://www.patreon.com/SocketLauncher/posts/socket-0-5-0-and-168380695) corrects N64 label proportions. | Study the newer geometry for Sega coverage; do not reproduce the old N64 label defect as visual fidelity. |
| Label refresh and build identity | [0.6](https://www.patreon.com/SocketLauncher/posts/socket-0-6-0-169429662) fixes image-picker label refresh; the creator's [0.3.2 post](https://www.patreon.com/SocketLauncher/posts/socket-0-3-2-166847366) comment reports a same-version re-upload correcting 3DS labels. | Check artwork replacement on the existing model. Bind comparisons to APK hashes, not version names alone; our supplied hash's re-upload identity is not established. |
| Rendering and zoom | [0.4](https://www.patreon.com/SocketLauncher/posts/socket-0-4-0-167472008) reworks glitter as a shader and optimizes materials, marquee and platform switching; 0.7 separates model zoom from spacing. | Measure actual Thor rendering and rapid navigation; compare model scale and layout separately. No imported engine or material architecture is implied. |
| Controller and touch | 0.5 fixes joystick mapping and slider/scroll gesture collisions; 0.7 fixes PlayStation button mapping and release events leaking into a newly opened screen. | Exercise controller mappings, screen transitions and competing touch gestures in the integrated frontend. |
| Launch lifecycle | [0.2](https://www.patreon.com/SocketLauncher/posts/socket-0-2-0-166177192), 0.3.2 and 0.6 report external-SD launch, second-game black-screen and sleep-related RetroArch fixes respectively. | Verify our existing launch handoff from SD, repeated launches and sleep/resume, without copying Socket's launcher or reopening deep save/gameplay testing. |
| Catalogue identity | 0.7 fixes disc tracks appearing separately and missed uppercase extensions. | Preserve R-Shop's canonical game/disc grouping and existing identities; no duplicate carousel entries or parallel catalogue. |
| Dual-display evidence | [0.0.1](https://www.patreon.com/SocketLauncher/posts/socket-0-0-1-165147792) explicitly removes the bottom-screen presentation. No reviewed later changelog announces its restoration. | Native Thor bridge code is not proof of an active dual-screen UI. The owner does not require bottom-screen presentation for S12; this is not a reference gap or blocker. Preserve existing S8 companion handoff separately. |

Socket's emulator-definition updater, Android-app carousel, palette collection
and optional duplicate-filled carousel are not new R-Shop requirements. The 0.4
post heading and attachment also differ (0.4.0 versus 0.4.1), reinforcing the
exact-artifact comparison rule. Changelog reports do not substitute for observing
the relevant reference behavior on the actual APK.

### Revised version decision and fallback contract

The changelog **changes the initial recommendation**: 0.7 is worth obtaining as
the final reference because it adds Genesis/Mega Drive geometry absent from the
supplied model inventory and includes later label, rendering and input fixes.
The supplied 0.3.2 remains sufficient for the first cartridge/motion study.
Obtaining 0.7 is not a prerequisite for S10/S11 or for that initial S12 slice;
no purchase, membership change or newer APK download was performed by the agent.
Record the newer APK's actual identity before using it, and compare the intended
appearance/motion without reproducing documented defects from the older build.
The creator's [official page](https://depmots.com/socket) independently confirms
Godot, platform-specific 3D models and insertion animations; it does not license
those assets for redistribution. Purchasing access alone does not establish
asset redistribution rights. The reviewed changelog does not establish that
0.7 restores dual-screen presentation.

### Owner-supplied 0.7.0 artifact — 2026-10-13

The owner subsequently downloaded the newer reference beside the original:
`D:/Downloads/Android/socket_release_0.7.0.apk`, 153715341 bytes, SHA-256
`bccf6bf5beccf5155645638e52a20f6e6e6deed902bd23b6b69ae7060c04bd70`.
Fresh Android SDK `aapt2 dump badging` identifies `com.depmots.socket`,
version name `0.7.0`, target SDK 36 and arm64-v8a. All ZIP members pass their CRC
checks. This is artifact identification/integrity, not runtime verification or a
claim of signer provenance.

The newer inventory has sixteen exported media scenes versus thirteen in 0.3.2.
Added scenes are `cart_genesis`, `cart_megadrive` and `cart_android`; imported
models rise from thirteen to fifteen with Genesis/Mega Drive and Android models.
Regional casing materials and color/normal/roughness textures corroborate the
changelog's additional Sega reference coverage. The Android model does not add
Android-app carousel support to R-Shop's scope.

Use this exact newer artifact for final S12 comparisons, retaining the older
hash-bound findings as historical evidence. The earlier decrypted geometry and
motion measurements apply only to 0.3.2: encrypted archive bytes differ, which
alone cannot distinguish a semantic change from encryption/export differences.
No 0.7 geometry decoding, model conversion, animation measurement, installation
or live comparison is claimed in this inventory check. Those comparisons belong
to S12, after the current S10 and S11 work.

The handwritten-title fallback stays part of FRONTEND-01: compose the title as
a label on the same media object, with a stable per-game readable sticker color,
then replace that label when artwork becomes available. This must cover missing,
pending, failed and offline artwork, preserve long-title readability and never
change game identity or flicker colors on rebuild. No generated substitute art
or new renderer has been introduced during this investigation.

## FRONTEND-01 — Required behavior and acceptance

These criteria implement the owner's direction under the authorized S1-S12
contract. They do not change S10/S11 acceptance:

- Preserve the recognizable red/dark identity and existing R-Shop game identity,
  catalogue, installation, metadata, save and companion workflows. Do not create
  a parallel catalogue or launch pipeline for the visual frontend.
- Owner clarification, 2026-10-14: preserve the red/dark theme in backgrounds
  as well as controls. Do not adopt Socket's grey dotted background. Console
  colors and cover artwork may complement the presentation but must not replace
  its red/dark background identity. Verify the actual main library, game details,
  settings and empty/loading/artwork-missing states with representative captures;
  red buttons on an otherwise grey or console-colored screen do not satisfy this.
- Render real physical-media geometry with rotation and insertion transitions.
  Reuse a model per console/media format with optional cached game-label artwork;
  a missing cover must still yield a recognizable physical object. Use a
  handwritten game-title sticker on that model for missing or pending artwork,
  with stable per-game variation from a readable sticker-color palette to evoke
  a homemade/knock-off label. Long titles remain readable. Do not show a black
  square, flickering random colors, or a different media model while scraping;
  transition to the actual label when resolved. Verify missing, pending, failed
  and offline artwork cases. Do not require a cartridge photograph or fresh
  network scraping per game. Compare models and animations against the supplied
  APK with reproducible reference captures, not only screenshots of our own app.
- Owner correction, 2026-10-14: physical labels use the edition/region-bound
  support texture, never box art or a whole-cartridge photograph. Box art remains
  the ordinary cover/grid presentation. Missing physical textures use the same
  handwritten sticker. Gather/cache them through normal metadata/artwork refresh,
  without browse-time API calls; verify both actual texture rendering and cover
  rejection in detail and selected-library paths.
- First demonstrate one cartridge's normal selection -> optional existing Drive
  installation -> animation -> real emulator launch on Thor. Only then expand to
  representative N64/Game Boy cartridge and PlayStation disc formats. Record how
  additional currently supported formats map to models or truthful alternatives;
  do not claim complete media coverage from these three examples.
- Modernize the existing main-screen R-Shop view, not a replacement frontend.
  No bottom-screen presentation or coordinated dual-display 3D scene is required.
  Preserve the existing emulator-top/linked-companion-bottom handoff and do not
  make it depend on adding a second rendering surface.
- Keep large collections usable through console navigation, search, dynamic Top
  and tag filters, and fast list/grid access rather than a mandatory linear
  cartridge carousel. Preserve clear cloud versus local residency indicators and
  readable titles. Keep the existing view available during the rendering proof.
- Support controller and touch navigation. Animation must be skippable and offer
  reduced motion; it must not gate download completion, error reporting or launch
  correctness. Failed/cancelled operations remain truthful and recoverable.
- Owner assignment, 2026-10-13: include the remaining save-management settings
  input/layout acceptance here, rather than in S10. Verify setup, status,
  restore/conflict controls and section navigation by touch/controller at the
  relevant layouts, preserving save mapping and active-job state. Retain concise
  controls and persistent sections, not a long scrolling settings roll.
- Measure frame pacing, memory, texture/model residency and lifecycle behavior on
  the actual Thor, including rapid navigation and display/app background changes.
  Set justified measurable budgets from the first proof before broad integration;
  do not claim performance from desktop previews or choose arbitrary thresholds.
- Verify the integrated view with and without artwork/network connectivity and
  preserve existing Drive, save-conflict and companion behavior. Turn both device
  screens off after live work. No release/publication is authorized here.

## Decisions to resolve when S12 becomes actionable

Lower-priority owner preference (2026-10-14): the handwritten fallback should
eventually look more careless, like a hurried marker label rather than neat
handwriting. This is a visual refinement candidate, not a blocker ahead of the
physical-texture correction or the required stage acceptance.

Choose rendering integration only after checking the project's actual Flutter,
Android and plugin versions and proving the first workflow on Thor. Assess the
smallest viable integration; do not rewrite the application or import a second
engine solely because the reference may use it. Determine model/animation asset
sources, label composition and main-display rendering/lifecycle behavior from
the observed reference and real proof. These are ordinary S12 design decisions,
not reasons to stop S10 or S11.

### First integrated slice — 2026-10-14

The 0.7.0 hash was freshly rechecked. Its 392 encrypted scene/script envelopes
pass their embedded checksums; private inspection reuses the earlier parser,
without publishing keys, topology, textures or decompiled code. Game Boy's
exterior bounds are 0.0564107 x 0.0648228 x 0.0074225 model units; its label is
0.0439713 x 0.0390049. The scene uses the shared cartridge insertion behavior:
0.15-second lift alongside a 0.2-second rotation, 0.2-second descent, 0.12-second
rebound alongside 0.25-second elastic scaling, then 0.2-second settle. These
supersede the older N64-oriented timing for this first Game Boy slice.

Design choice: start with an independently constructed exterior mesh projected
through Flutter's existing renderer, with a perspective-correct widget label.
This retains the existing artwork/cache pipeline and avoids importing Godot or
an additional native renderer before Thor evidence justifies one. A new engine
and a 2D tilted cover were considered: the former adds an unproved lifecycle
boundary; the latter cannot meet the geometry requirement. The first mesh is an
adaptation requiring visual comparison, not a claim of recovered/exact topology.
An OFL-licensed bundled Kalam font makes handwritten labels work offline. Its
source is Google's fonts repository (`ofl/kalam/Kalam-Regular.ttf`); copyright
and the complete OFL text are retained in `assets/fonts/Kalam-OFL.txt`, bundled
and exposed alongside the existing artwork attribution through Licenses.

The existing Game Boy detail view selects this presentation while retaining a
cover-view toggle. A per-view reduced-motion control respects Android's disabled
animations setting. Insertion joins the existing launch preparation/handoff,
has explicit skip/dispose/background completion, and does not change downloads,
save-conflict decisions, ownership or companions. No other media is implemented
until the first native workflow passes. Host widget/geometry checks and scoped
analysis pass; they are diagnostic evidence, not native feature acceptance.

Reference captures use the top display only. The newly installed supplied Socket
reference is not made the device's Home app; no owner launcher setting changes.
The actual R-Shop first packaging request 1041 ended before build/gate acquisition:
an unrelated elevated UniGetUI .NET installer made the helper's process-event
subscription fail. The original installer was observed to exit without being
interrupted. Request 1042 compiled successfully, but its helper post-build
process-event subscription failed; verified daemon exit was not established.
No direct Gradle or custom lock was used. The later current package verification
is recorded in the implementation ledger; do not treat 1042 as full helper success.

The actual Game Boy card and Download control queued one 32,917-byte Drive
archive. Its normal transfer reached completed, and the existing installation
watcher made Open available. The actual measured Open control then awaited the
new insertion and used the existing verified native RetroArch handoff. Android
reported RetroActivityFuture on the top display, and a host-only capture showed
the selected game's title/copyright screen. No gameplay/save audit was added.
This establishes the first download/animated-launch path, not full FRONTEND-01.

Actual 0.7 reference rendering was obtained through its normal setup with one
isolated test-ROM folder, not the whole owner library. Comparison exposed a
stepped shell, side grip ribs and recessed header absent from the initial
approximation; the independent geometry was revised accordingly. Texture/material
fidelity and matched motion captures remain acceptance work. No recovered
proprietary geometry or textures were added to the fork.

The red-background regression first failed against the old console-color
backgrounds. Shared backgrounds now use an opaque dark-red gradient; detail
artwork is subordinate at 12 percent opacity. A real Thor capture confirms the
red detail backdrop with the handwritten missing-artwork label. Representative
settings/library and artwork-state visual acceptance remains required.

The subsequent integrated background correction removes opaque grey Settings/
console-configuration overlays, the black library scaffold and console-colored
ScreenLayout glow. Headers use a matching dark-red scrim. A fresh packaged Thor
check confirms Home, Settings and library loading/populated dashboard backgrounds;
the detail missing-artwork capture retains the same red base. Host regressions
cover the green-console accent, Settings overlays and library loading/identity/
filter/configuration paths. This closes the observed background overrides, not
the remaining media formats, artwork-state transitions or whole S12 acceptance.

The capture helper initially rejected supported display selection because this
device prints screenrecord help on stderr. Its installed Codex/Claude copies now
check the combined successful help output; the stderr-boundary fixture and actual
host-only recording pass. No alternate device-storage recording was introduced.
Both initial recording sample sets omitted the launch interval, so they do not
prove insertion fidelity. Debug Flutter frame timings are diagnostic only;
they include VM-observation overhead and are not release-performance acceptance.

## Reconciliation

### Integration budget and layout contract — 2026-10-14

The measured first Game Boy proof establishes the renderer baseline before
library integration. Target the Thor's supported 60-Hz presentation budget:
steady-state build and raster P95 each below 16.67 ms, measured separately (their
percentiles are not additive FPS proof). Final measurements must include rapid
navigation/background recovery and identify debug/observer overhead.
Keep exactly one animated selected-media preview, shared immutable geometry per
format (at most 256 exterior faces for the current three formats), and the
existing 640-pixel selected-label decode limit. This bounds the label bitmap to
1,638,400 RGBA bytes; it is not a cap on the whole shared artwork cache or app.
Compare integrated native memory/residency with the recorded first-slice baseline;
do not claim model-only memory from aggregate app PSS.

Landscape library layouts at least 720 logical pixels wide use a selected-media
panel beside the existing virtualized grid. Its width is 28 percent of available
content width; the grid retains the user's actual column count and its existing
focus/index/search/Top/tag behavior. Smaller/portrait views retain the fast grid,
with the same media available in details. Persisted Display settings offer 3D
media/classic view and reduced motion; Android's disabled animations also wins.
This is one existing catalogue/identity and detail/launch path, not a second
carousel, download engine or per-card animated mesh.

Current format map (representative coverage, not every console's 3D shell):

| Systems | Presentation |
| --- | --- |
| Game Boy (`gb`) | Independent cartridge with recessed header and grip ribs. |
| Nintendo 64 (`n64`) | Independent curved cartridge with seams and connector recess. |
| PlayStation/PlayStation 2 (`psx`, `ps2`) | Optical disc with a real centre hole and clear hub. |
| Other supported systems | Existing cover or licensed Systematic physical-media fallback; never substitute an incorrect Game Boy shell or ordinary disc for UMD/mini-disc/other cartridge formats. |

The N64/disc meshes follow the native 0.7 silhouette/label/hub comparison, while
using independent geometry and shading rather than redistributing Socket assets.
Their fixtures are non-playable renderer references, not emulator-launch evidence.

Source review and proposal recording are complete. FRONTEND-01 implementation
is now ACTIVE; remaining integration and runtime acceptance are unfinished.
The first real download/launch and red detail-background evidence above do not
close geometry/material/motion, format coverage or performance acceptance.
The owner explicitly assigned save-management
touch/controller and responsive-layout verification to S12; it remains required
for overall completion but is not a prerequisite for S10 closure. No other work
is deferred from S10/S11 into S12.
