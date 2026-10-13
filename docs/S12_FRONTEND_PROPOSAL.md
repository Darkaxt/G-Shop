# S12 — 3D physical-media frontend

Status: NOT STARTED.
Authority: SPECIFICATION.md, revision 36, section 6f.
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
a lower-screen insertion destination.

The conversation's assistant proposed rendering frameworks and described other
products. Those claims have not been independently verified. No renderer,
framework upgrade or unrestricted public asset reuse follows from those claims.
The owner's subsequent 2026-10-13 direction explicitly authorizes private APK
inspection and reverse engineering of the supplied August reference. Models and
animations in our adaptation must match the APK, not just its general concept.
Reference study must capture geometry/proportions, material/label placement,
motion paths/timing/easing and upper/lower-display sequencing with comparison
evidence. Distribution still requires suitable provenance and reuse rights;
independently recreated or appropriately licensed assets are valid adaptations.

Concrete supplied file resolved locally: `D:/Downloads/Android/socket_release_0.3.2.apk`
(144362294 bytes; SHA-256
`ba00e36c189f9f8f024af6aac94c68913652d07bd7204aa9a385e7b332a4d0b1`).
This records the inspected file identity, not a rendering study or S12 start.
Do not commit the APK or private extraction outputs. The owner offered to pay
for version 0.7 if needed. Start with this reference and establish a concrete
missing requirement before recommending a purchase or newer reference.

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
- Study the desired upper/lower-screen transition explicitly. Prove coordinated
  display rendering, then release presentation ownership for the existing
  emulator-top/linked-companion-bottom handoff. S8 companion launching alone is
  not evidence of a working dual-display 3D scene.
- Keep large collections usable through console navigation, search, dynamic Top
  and tag filters, and fast list/grid access rather than a mandatory linear
  cartridge carousel. Preserve clear cloud versus local residency indicators and
  readable titles. Keep the existing view available during the rendering proof.
- Support controller and touch navigation. Animation must be skippable and offer
  reduced motion; it must not gate download completion, error reporting or launch
  correctness. Failed/cancelled operations remain truthful and recoverable.
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
sources, label composition and dual-display coordinate/lifecycle behavior from
the observed reference and real proof. These are ordinary S12 design decisions,
not reasons to stop S10 or S11.

## Reconciliation

Source review and proposal recording are complete. FRONTEND-01 implementation,
integration and runtime acceptance are not started. No candidate runtime
criterion is claimed satisfied. No work is deferred from S10/S11 into S12.
