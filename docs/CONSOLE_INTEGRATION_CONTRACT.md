# Console presentation, resource and validation contract

Owner-approved integration requirements, 2026-10-21. Included by
[SPECIFICATION.md](SPECIFICATION.md); that specification and later explicit owner
instructions govern scope. This contract applies when a console integration is
authorized. It does not activate every console or another implementation stage.

## Resource gate — CI-01

Inventory required resources against the actual ROM collection before implementing
the affected presentation: console/hardware editions, boxes, cartridge/media
families, labels, sleeves/protective cases, controllers, displays and animations.
Distinguish absent files, invalid assets, uncertain physical bindings and resources
that genuinely do not apply. A ROM revision is not automatically another exterior;
a game title or CRC does not establish a physical printing, colour or shell.

If any required resource is absent, invalid or cannot be identified sufficiently
to integrate faithfully, **pause the affected console integration**. Record the
exact resource/game/edition, blocked acceptance criterion, available evidence and
what would resolve it. Resume dependent implementation only after the owner:

- supplies the required model/artwork/resource;
- explicitly approves a concrete workaround; or
- explicitly acknowledges the named limitation for the current scope.

Silence, elapsed time, a plan, a worker report or a generic substitute is not
acknowledgement. Do not fabricate a custom cartridge, recolour an unrelated shell,
substitute a generic console/box/label or silently omit a required prop. Propose
such a workaround with its fidelity and behavior limits before using it. Capture
the owner's decision and affected scope in the specification/reconciliation
ledger. Do not call a blocked integration complete or release a partial outcome.

Existing runtime handling of missing/corrupted resources may preserve access to
an owned game. It does not satisfy missing resource acceptance or authorize
continuing implementation past this gate. Internal work that can resolve the gap
remains actionable; do not misclassify research or a fixable binding defect as an
external impediment. Documentation and diagnosis may establish the concrete gap.

## Upper library gallery — CI-02

Use the matching reconstructed NintAndBox carton as the game card's 3D object
where a valid physical edition is bound. Retain every available carton edition in
the private resource library; show one chosen representative per library card.
Expose alternate editions in the game scene/contextual selector rather than
duplicating cards. No physical printing is inferred from title alone.

Preserve the established GBA presentation: upright selected carton, restricted
**-30 to +30 degree yaw sweep**, selection scale and soft accent back glow around
the object's transparent silhouette. Unselected cards stay still. Reduced Motion
retains the selected glow and legible selection without the sweep. Gallery motion
must not expose a blank edge, turn the box upside down or reload its geometry.
Use the **same shared resting yaw as GBA** (currently -0.70 radians, about -40
degrees), so unselected and Reduced Motion cartons visibly show a side face and
depth. Do not add a flatter per-console rest override, such as the former G&W
-0.20-radian pose. Shared selection animation alone is insufficient parity;
compare the actual idle, selected and Reduced Motion frames with GBA.
Full model inspection has separate rotation controls; the restricted gallery sweep
does not limit the inspector. Preserve existing responsive layout and touch/
controller selection. A required missing box invokes CI-01; do not quietly replace
the card with an unrelated object.

## Lower console composition — CI-03

The console-section preview is a large rotating composition of the applicable
console models and representative games/accessories. Preserve provided collector
props and original scenes; hide only specifically approved staging objects, such
as Game & Watch's display table/board. Add editions in a shallow semicircle, with
readable silhouettes and consistent relative scale, rather than an arbitrary row.
Keep labels out of the overview; show edition names and information on inspection.

Default camera framing reserves **10–15% on each edge for text and buttons**:
target a centered 75% width/height composition rectangle (12.5% margins). Fit the
whole visible arrangement, including opened flaps, extracted contents, controllers
and cables, while retaining shared physical proportions. The limiting axis fills
that rectangle; preserve aspect ratio even if the other axis leaves extra space.
Do not compound fixed model-width limits with another arbitrary small scale.
Apply to collector and game browsing/unboxing views, including the shallow arc;
upper gallery cards keep CI-02. Explicit inspection zoom and the final intentional
launch zoom into the display can leave this default framing.

An external TV sharing the console's support level sits **beside the console**,
as in the supplied TV/NES reference composition. Do not place the console directly
in front of the same-level screen. Keep the full screen and insertion path clear
from the actual launch camera, retain common physical scale/grounding, and fit the
camera around both objects. The controller remains centered in front of its own
console, with its cable at the right; moving the television does not move the pad
to the television's center. Recalibrate the final screen zoom after placement.

When browsing a game, show its valid physical editions together in a shallow arc.
Use associated boxes behind the handhelds/media, with the extracted device/media
resting in front. Keep one exact primary binding and distinguish visual-only
alternatives. A program shared by different exteriors does not erase their
physical identity. Sequentially unbox the applicable editions; do not play every
animation simultaneously or remove an edition just to simplify composition.

## Browsing, inspection and information — CI-04

Continue the selected game's actual box opening into extraction of its contents.
Use the correct flap/hinge and source artwork orientation; do not pull contents
through a closed wall. Include a dust sleeve, protective case, booklet or other
accessory when it applies and is available under CI-01. Preserve the chosen
cartridge colour/material and personalized label. For GBA, retain the established
cartridge-then-booklet extraction, closed box and settled composition.

Zoom/inspect the selected cartridge or handheld. The corner Info action opens
game metadata over it; console/device inspection exposes hardware history where
available. Use a partially translucent, scrollable panel with the model visible
and slowly rotating underneath. Reduced Motion stops rotation. B closes info/
inspection before leaving the game. Do not restore permanent white edition labels
or a separate ordinary Resources/trailers/images browser. Retain useful resource,
manual, emulator, variant and save actions contextually or in settings.

## Physical scale, cables and contacts — CI-05

Every object that sits alongside another uses a **shared physical scene scale**
where real measurements are obtainable: consoles, hardware editions, handhelds,
cartons, media, controllers, cables and other props. Use one unit convention for
the composition, calibrate each imported asset from documented dimensions and
retain that conversion in its receipt. Do not independently normalize them to
the same displayed width/height. Fit or move the camera to show the arrangement;
do not stretch the models to fill equal slots. Preserve relative dimensions in
both the collector and per-game/launch scenes. Independent gallery-card framing
is allowed because separate cards are not a shared physical arrangement.

Record source dimensions, units, applied uniform scale and the physical reference
or measurement method. Where reliable dimensions cannot be obtained, mark the
scale as estimated/unverified and surface the limitation; do not imply measured
accuracy. If that uncertainty prevents a required faithful composition, apply
CI-01 and obtain the owner's resource/workaround/limitation decision.

For every wired model, establish the applicable controller/hardware edition and
reference cable length. **Do not apply one universal length**: regional Famicom,
NES and other controllers can differ. Calibrate the model against a known physical
dimension; distinguish an author-declared unit from a measured physical scale.
Measure the transformed **curved centerline arc length**, including Bezier handles
and all slack, rather than endpoint distance or the sum of control-point chords.

Keep a receipt with scale basis, reference URL/evidence, nominal target, measured
length, units and uncertainty. Unknown reference dimensions remain unverified;
report them rather than claiming factory accuracy. The current front-loader's
230 cm target is rounded from a firsthand report of 7 ft 5.5 in (227.33 cm),
[TASVideos measurement](https://tasvideos.org/Forum/Topics/13185). It is not a
factory tolerance or a rule for the NES-101 or another controller.

Retain the correct matching controller and plug, seated in the correct port. For
the current NES composition, the controller rests flat and centered directly in
front of the console; only the excess cable is loosely coiled on the right.
Validate cable diameter, plausible bends, crossings with vertical clearance,
attachment at both ends, support-plane contact and absence of intersections with
the hardware/controller. Grounding must be checked on actual transformed mesh
vertices and curve geometry, not only bounding boxes or a pleasing camera angle.
Keep the original collector/source intact when preparing a launch derivative.

## Launch and input ownership — CI-06

A launches an installed game directly from its 3D scene; a cloud-only game keeps
its existing install action. Continue the unboxing into insertion into a compatible
console, appropriate power-on/startup and screen zoom, then the real emulator.
Choose randomly once among available **validated compatible** console bodies and
hold that choice, slot and pose through the attempt. Exclude decorative collection
scenes and electrically/physically incompatible media. Preserve physical edition
choices and the exact ROM/revision.

Keep the existing ROM/save/permission/companion launcher as the sole handoff owner.
The main engine owns selection and the attempt; the secondary engine only renders
local/public facts and returns token-bound readiness/final-frame acknowledgements.
An animation duration or watchdog never authorizes native handoff. Two additional
A presses skip the visuals of the same pending launch, without bypassing checks.
B/Back cancels an uncommitted handoff and restores the selected scene. Selection,
route and lifecycle changes invalidate stale work. Preserve offline play, Reduced
Motion and touch/controller access; do not cancel an already committed Android
handoff as though it were still a pending animation.

## Generation-specific requirements — CI-07

| System | Required physical behavior and review |
| --- | --- |
| NES front loader | Correct 72-pin shell and printing; sleeve where applicable; lid clears the cartridge, insertion follows the raised tray, tray presses down, then the lid closes. Matching wired controller in player 1. External display; no invented universal Nintendo BIOS/logo. |
| NES-101 | Matching dogbone/plug, vertical 72-pin insertion through the actual dust flap; keep the occupied flap open. Validate each admitted shell family separately. No front-loader tray or invented front-loader power LED. Use this edition's cable reference. |
| Famicom/regional bodies | Preserve their actual cartridge interface, markings and controller attachment/cable differences. Do not put a 72-pin NES cartridge into an incompatible 60-pin slot or treat a regional name as proof of an identical shell. |
| GBA | Use compatible AGB/SP hardware and the selected shell, including required special hardware such as sensors/rumble. Preserve label/material, booklet and box sequence. Calibrate the slot and actual screen; coordinate authentic startup with emulator/BIOS settings so the boot is not duplicated. Do not pretend the two hardware bodies have the same slot/hinge geometry. |
| Game & Watch | Bind the exact selected physical handheld and approved visual editions; documented MCU-only revisions may reuse an exterior. No fictitious cartridge insertion. Use correct opening controls/hinges, LCD activation/Game A behavior, and the selected device's screen placement. Preserve transparent Crystal apertures, Panorama optics and multi-screen geometry. Multiple matching editions unbox sequentially into the shallow arc. |
| Other authorized systems | Establish media/drive/slot, packaging/accessories, power/startup, display, controls and physical variants from applicable evidence before coding the animation. Apply CI-01 to missing required resources. Do not infer these from another generation. |

## Acceptance and evidence — CI-08

Reconcile the complete authorized console workflow with SPECIFICATION.md and the
single active stage. Authoring/format/geometry probes are implementation
diagnostics; they do not validate an unfinished feature or complete a stage.

For the integrated result, inspect actual source provenance/mesh/texture hashes,
reversible animations, UV orientation, aperture and collision clearance, labels,
scale, cables and all required hardware editions. Exercise the normal library
selection, lower composition, per-game sequence, inspection/info, real emulator
handoff, skip/cancel, lifecycle/selection invalidation, offline behavior, Reduced
Motion and incomplete-resource runtime handling. Use focused host checks and real
device evidence, including Thor's 1920x1080 upper and 1240x1080 lower display and a
smaller ordinary single-screen layout. Check actual rendered frames and physical
input; a loader success or build alone is insufficient.

Check default projected composition bounds against the central 70–80% viewport
at closed, extraction, settled and rotating poses. Text/buttons remain in the
reserved edge areas with usable targets; no flap, cable or edition may clip during
the ordinary sequence. Review single and multiple-edition layouts and both tall
and wide viewports; a bounding-envelope check complements actual rendered review.

Keep the existing visual contract: theme/typography, compact title/corner actions,
at least 44 logical-pixel touch targets, safe-area information panel with 16-pixel
insets/radius and readable scroll. Check contact/grounding from more than one
view and review transition frames for clipping, popping, unintended spins or
flashes. Distinguish GPU-frame evidence from physical-display timing.

Record each required item as verified, unresolved, blocked or validly deferred to
a named stage. Include exact evidence and owner-approved resource limitations.
Inventory ROM revisions matched, physical designs available and boxes available
separately. Preserve derivative attribution/licenses even after extensive edits;
run the final Socket dependency/provenance review in its authorized S26 order.
No partial console release: complete the authorized integrated scope, final checks,
commit and one normal signed release with independent delivery verification.

## Current implementation pointers

Use these existing components; do not introduce another preview/launch owner:

- Gallery: `lib/widgets/library_model_presentation.dart` and the existing card.
- Physical scenes: `lib/widgets/physical_media_view.dart`,
  `lib/widgets/socket_media_renderer.dart`, and `lib/models/*_unboxing_scene.dart`.
- Ordinary/dual ownership: `lib/features/game_detail/game_detail_screen.dart`,
  `lib/features/preview/dual_screen_preview_host.dart` and `preview_screen.dart`.
- Launch handoff: `lib/features/game_detail/open_managed_game.dart` and
  `lib/services/owned_emulator_launcher.dart`.
- Evidence/status: `docs/S25_VERIFIED_MODELS.md` and
  `docs/IMPLEMENTATION_STATUS.md`; private per-file inventories stay private.

The reusable agent technique is versioned in
`docs/agent-skills/gshop-console-integration/SKILL.md`. That skill routes to this
contract; it does not supersede it or grant authority to start another console.
