---
name: gshop-console-integration
description: Integrate and validate G-Shop console and per-game 3D presentations, including NintAndBox galleries, hardware editions, physical media, cables, unboxing and owned emulator launch. Use for G-Shop model/resource integration and its visual acceptance; not generic Blender art or unrelated emulator setup.
metadata:
  version: "0.1.4"
---

# G-Shop Console Integration

Locate the actual G-Shop checkout. Read `docs/SPECIFICATION.md`, the current
`docs/IMPLEMENTATION_PLAN.md` and `docs/IMPLEMENTATION_STATUS.md`, then
`docs/CONSOLE_INTEGRATION_CONTRACT.md`. The latter contains the owner-approved
CI-01..08 rules and per-generation exceptions. If this contract is unavailable,
resolve the checkout/document rather than silently inventing an equivalent.

This skill supplies integration and review technique. It does not activate a new
stage, require a worker, authorize a new console, change scope, introduce approval
ceremony or supersede user/standing instructions. Preserve existing authorization
and the sole active stage. Reload the contract when the owner changes its rules.

## Resource gate first

Bind actual ROM/revision identities separately from physical hardware, cartridge
families and carton printings. Inventory required models, labels, textures,
accessories, controllers, displays and animations. Check original sources and
private receipts; retain their hashes, artwork and attribution. Never publish ROM
inventories, private models/artwork or credentials with application changes.

**Pause the affected integration when any required resource is missing, invalid
or lacks a sufficiently established physical binding.** Report the exact resource
and blocked criterion. Resume only after the owner supplies it, explicitly approves
a concrete workaround or acknowledges the specific limitation. Record that decision.
No silent generic model, guessed shell/colour/label or omitted prop. Runtime missing
file handling is not acceptance of an incomplete resource set. Diagnose/fix
actionable binding defects rather than manufacturing external blockers.

## Apply the contract to the current console

- Upper cards: matching NintAndBox box, one representative, selected upright
  bounded yaw and back glow; no rotation for unselected/Reduced Motion. Use GBA's
  shared resting yaw (currently -0.70 rad, about -40 degrees), not a flatter
  per-console override. Check visible side depth in idle and Reduced Motion as
  well as the selected +/-30-degree sweep; shared animation alone is not parity.
- Lower selector: large console/game composition; retain source props, hide only
  approved staging; shallow arc for multiple valid physical editions.
- Lower default camera: reserve 10–15% per edge for text and buttons, targeting
  12.5%. Fit the whole animated composition to the central 75% rectangle without
  changing relative physical scales. Preserve aspect ratio, allowing extra space
  on the non-limiting axis. Check closed/extracted/settled/rotating and multi-edition
  poses. Keep explicit inspection zoom and final screen-entry zoom separate; do
  not apply this lower-scene rule to upper gallery cards.
  Reserve against the full lower safe viewport once; overlay titles/captions and
  corner controls in its edge areas instead of subtracting another header/footer.
- External TV on the same support level: place it beside the console, keeping
  the screen and insertion path clear from the launch camera. Do not put the
  console directly in front of that screen. Retain shared scale/grounding; the
  pad stays centered on its own console and the cable stays at the right. Fit
  the camera around the composition and recalibrate zoom to the moved screen.
- Game browsing: actual box/contents and applicable sleeve/case/booklet, proper
  sequential extraction, selected materials/labels, zoom and translucent info over
  slow rotation. Keep useful contextual actions.
- Wired props: correct controller/plug/contact and edition-specific cable length.
  Calibrate scale and measure transformed curve arc length. Receipt target,
  measurement, reference and uncertainty; inspect bends, crossings and grounding.
  Never copy the NES's nominal 2.3 m target to every controller.
- Shared scale: models placed together use actual dimensions where obtainable,
  one common scene unit and source-bound uniform conversions. Fit the camera,
  not each model to equal sizes. Record estimated/unverified dimensions; independent
  gallery-card framing does not establish comparative physical scale.
- Launch: compatible random choice once, stable pose/slot; actual generation's
  insertion and startup; existing owned-ROM/save/native launcher. Main-engine
  ownership and token-bound renderer replies, two extra A presses to skip, B and
  lifecycle/selection cancellation, Reduced Motion and offline support.

Read the generation table before adapting an existing animation. NES external
screen, NES-101 flap/no LED, GBA BIOS coordination and Game & Watch's built-in
LCD/Game A behavior are different requirements, not interchangeable templates.

## Build evidence at the real boundary

Use existing model loaders, Blender authoring/conversion and app diagnostics.
Retain original assets; create attributed launch derivatives where authorized.
Validate actual meshes/UVs/hinges, insertion apertures, controller/cable contacts
and screen anchors. Do not replace those measurements with bounding-box guesses
or a single attractive camera angle. Keep authoring probes separate from full
feature acceptance.

After the required feature is integrated, exercise its complete normal workflow
on the intended device: gallery, lower scene, browsing/unboxing, inspection/info,
real launch, skip/B, lifecycle/selection, Reduced Motion and offline behavior.
Review actual rendered transitions and both displays plus smaller ordinary
layouts. Use the contract's evidence matrix and existing reconciliation ledger;
do not invent a checkpoint stage for each edit. Component tests/builds and worker
reports are not delivered behavior.

Close only the authorized complete scope. Resolve required gaps/deferrals,
preserve source/derivative credits and final Socket audit order, then follow the
project's normal single final release and independent delivery verification.
