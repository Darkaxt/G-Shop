---
name: gshop-console-integration
description: Integrate and validate G-Shop console and per-game 3D presentations, including NintAndBox galleries, hardware editions, physical media, cables, unboxing and owned emulator launch. Use for G-Shop model/resource integration and its visual acceptance; not generic Blender art or unrelated emulator setup.
metadata:
  version: "0.1.12"
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

## Carry forward the complete existing pipeline

Before integrating another console, read
[the end-to-end pipeline and acceptance checklist](references/console-integration-pipeline.md).
Recover the existing GBA implementation, retained evidence and later owner
decisions before proposing another path. Map every applicable step to the current
console and existing reconciliation ledger. Reuse the working acquisition,
reconstruction, import/publication and recovery lanes; a console-specific renderer
must not bypass them. The owner supplies genuinely missing resources, not a
repeated description of the integration process. Historical evidence establishes
the precedent and permission; verify the new console's actual delivered behavior.

## Resource gate first

Bind actual ROM/revision identities separately from physical hardware, cartridge
families and carton printings. Inventory required models, labels, textures,
accessories, controllers, displays and animations. Check original sources and
private receipts; retain their hashes, artwork and attribution. Never publish ROM
inventories, private models/artwork or credentials with application changes.

For cartons, exhaust the existing applicable source chain: reviewed NintAndBox
dump panels, public low-resolution .es previews, LaunchBox, then ScreenScraper.
Consider front, back, spine and unfolded texture roles. A missing dump model or
same-region catalogue binding is not evidence that no box can be produced.
Inspect the original archive and retained model/panel catalogue as well as any
partial extraction. A regional or non-English same-game carton remains a valid
donor for the already-approved GBA composition: retain its geometry, sides and
flaps, replace the necessary front/back with matched English LaunchBox art
(then ScreenScraper), and reuse the existing collector colour-correction path.
Read section 4 of the pipeline reference for its source-selection and colour
checks. Do not reject that donor solely because its language/printing differs,
build a lower-fidelity flat-art box first, or request that approval again.
The established best-effort reconstruction approval permits available flat art,
coherent spine reuse and plain colour-matched absent faces, with per-face
provenance. It does not establish six original scans or authorize a wrong game's
printing or claim a composite is an original exact-region SKU. Apply those
existing permissions before invoking the resource gate; do
not ask the owner to approve it again. Trace fixable acquisition/binding/rendering
omissions before reporting a genuine source gap.

**Pause the affected integration when any required resource is missing, invalid
or lacks a sufficiently established physical binding.** Report the exact resource
and blocked criterion. Resume only after the owner supplies it, explicitly approves
a concrete workaround or acknowledges the specific limitation. Record that decision.
No silent generic model, guessed shell/colour/label or omitted prop. Runtime missing
file handling is not acceptance of an incomplete resource set. Diagnose/fix
actionable binding defects rather than manufacturing external blockers.
The approved carton composition/reconstruction above is an explicit exception
to generic-box substitution; it does not authorize substitute hardware or media.

## Verify upstream coverage before scene acceptance

For the authorized console, establish the actual eligible, distinct Top 25 cohort
from the app's canonical ranked query and current filters/preferences. Retain the
snapshot and exact ROM/edition identities privately; fewer than 25 eligible games
is valid. An installed game chosen for animation diagnostics is not automatically
a ranked member. Do not substitute convenient games or infer membership from names.
Check the ranked coverage denominator and accepted rating-source/freshness evidence.
A completed job with zero selected/eligible games in a non-empty collection does
not establish a populated Top 25. Diagnose missing ranking prerequisites; record
genuinely unsupported ranking or sparse coverage explicitly rather than accepting
an empty cohort or inventing ranks. Apply the authorized collection scope when a
console uses a different, explicitly approved selection rule.

Verify the configured Google Drive account/root and the cohort's metadata and
required artwork there before accepting device resource coverage. For each game,
record the required roles (including the cartridge/support label), edition/region
binding, remote resource identity and integrity evidence. A folder count, completed
job, successful upload or another console's accepted cohort does not prove coverage.
Keep provider-unavailable resources and owner-approved limitations explicit under
CI-01; a missing database row alone does not establish an absent source asset.

Trace the same resource through Drive publication, shared-cache recovery, app
projection and the rendered scene. Distinguish upstream absence, recovery failure,
binding failure and renderer failure. Before treating repeated label references
as competing editions, compare their complete stable media identities. Exact
duplicates identify one resource; distinct same-region alternatives and indexed
disc members retain their separate binding/ambiguity rules. If Drive already has
the correct resource,
repair that path rather than collecting another copy. Do not use an individual
lookup/local-only patch to conceal an incomplete Top 25 publication or recovery.
Any authorized acquisition must pass the existing Drive publication/integrity
workflow before counting as integrated coverage.

Inspect the actual texture in the native scene. A loader success, captured canvas
or `labelReady` flag can include a handwritten fallback and is not evidence that
authentic artwork resolved. Such a game may diagnose animation only; it cannot
pass personalized-label or Top 25 resource acceptance. Keep those outcomes separate
in the existing reconciliation ledger, and resolve actionable upstream/cache
defects before continuing dependent acceptance or invoking the external resource
gate. Preserve the current stage and the single final release boundary.

## Verify browsing order and score parity

Exercise both entry points: the ordinary console browser and the main Library's
console tab. Do not infer parity from their shared cards or from one working path.
By default, place up to 100 eligible canonical games first in score-rank order,
then retain the full alphabetical tail. Use the actual eligible count; preserve
explicit Top/rating filters, release preferences and manual shelf order. Browsing
must remain cache-only and must not scrape to manufacture the default ordering.
Check entry with and without a ready installation index. Initial selection and
the secondary preview must come from the finished ranked view, not provisional
alphabetical loading groups; preserve actual selection on later publications.

Verify the same accepted source, freshness, confidence and exact-edition binding
rules used by GBA, plus the visible source-labelled score badges and rating-overlay
setting. Distinguish missing rating inputs from ordering or badge-rendering defects.
Trace absent inputs through the upstream coverage workflow above; neither a shared
badge widget nor a completed job proves populated scores. Check actual native
order/badges after publication and re-entry, including the unrated tail. Do not
copy GBA's scores or claim another console's coverage from the GBA reference.

## Apply the contract to the current console

- Upper cards: matching NintAndBox box, one representative, selected upright
  bounded yaw and back glow; no rotation for unselected/Reduced Motion. Use GBA's
  shared resting yaw (currently -0.70 rad, about -40 degrees), not a flatter
  per-console override. Check visible side depth in idle and Reduced Motion as
  well as the selected +/-30-degree sweep; shared animation alone is not parity.
- Lower selector: large console/game composition; retain source props, hide only
  approved staging; shallow arc for multiple valid physical editions. Open the arc
  toward the viewer, with the central edition behind the outer editions. Keep
  its physical proportions; no priority enlargement. Tap models directly for
  inspection, without floating magnifier buttons or other extra overview controls.
  After 25 seconds unattended, use bottom-margin tutorial/trivia messages. Reset
  on touch/controller activity from either display and selection; hide during
  information, resources, launch and backgrounding. Keep facts sourced and offline,
  with no new buttons or model resizing. This is explicit presentation timing.
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
  slow rotation. Slightly blur the scene beneath the rounded information panel;
  keep text/buttons sharp and the scene outside clear. Keep useful contextual actions.
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
