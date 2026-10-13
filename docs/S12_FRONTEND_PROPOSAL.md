# S12 — 3D physical-media frontend

Status: NOT STARTED.
Authority: SPECIFICATION.md, revision 39, section 6f.
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

Choose rendering integration only after checking the project's actual Flutter,
Android and plugin versions and proving the first workflow on Thor. Assess the
smallest viable integration; do not rewrite the application or import a second
engine solely because the reference may use it. Determine model/animation asset
sources, label composition and main-display rendering/lifecycle behavior from
the observed reference and real proof. These are ordinary S12 design decisions,
not reasons to stop S10 or S11.

## Reconciliation

Source review and proposal recording are complete. FRONTEND-01 implementation,
integration and runtime acceptance are not started. No candidate runtime
criterion is claimed satisfied. The owner explicitly assigned save-management
touch/controller and responsive-layout verification to S12; it remains required
for overall completion but is not a prerequisite for S10 closure. No other work
is deferred from S10/S11 into S12.
