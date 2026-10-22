# Console integration pipeline and acceptance checklist

Use this entire checklist for each authorized console. Resolve the checkout,
specification, current plan and `docs/CONSOLE_INTEGRATION_CONTRACT.md` first.
Apply the current stage and scope; this does not authorize integrating every
console at once or create new stages, workers or approval gates.

## 1. Recover the working baseline and prior decisions

- Inspect the current GBA call chain and its retained acceptance receipts before
  designing a console-specific path. Read the relevant dated ledger entries and
  subsequent owner decisions; do not infer a missing feature from one loader.
- Distinguish already-approved reconstructed packaging from resources that still
  need an actual new model or decision. Preserve source and derivative credits.
- Record the current console's applicable requirements and acceptance boundaries
  in the existing ledger. The owner supplies resources; the integrator owns the
  acquisition, conversion, deployment, recovery and review process.

## 2. Establish the real collection and ranked cohort

- Use the canonical query, current release preferences and actual eligible
  distinct Top 25. Fewer than 25 is valid; zero selected in a populated collection
  requires diagnosis, not an empty coverage claim. Retain exact identities privately.
- Keep ROM program/revision, canonical game, physical hardware/media edition and
  carton printing distinct. Preserve exact matching and modification exclusions.
- Verify rating source/confidence/freshness upstream. Both console browser and
  Library need the ranked prefix, full alphabetical tail and visible source-labelled
  scores. Initial selection must use the finished result, not loading groups.

## 3. Inventory all required resources and applicable source paths

- Inventory console variants, physical media/shell/materials, authentic labels,
  boxes, sleeves/cases, manuals, controllers/cables, external displays, animations
  and credits. Mark genuinely inapplicable props separately from missing ones.
- For each carton/face, use the existing ordered chain:
  1. reviewed local NintAndBox unfolded scans and reconstructed models;
  2. the public low-resolution NintAndBox .es preview for incomplete dump panels;
  3. edition-compatible LaunchBox front/back/spine artwork;
  4. ScreenScraper front/back/side/unfolded texture and bound manual roles.
- Check actual supported selectors and decoded responses, not just provider URLs
  or a list of advertised roles. A failed request for one face/game does not prove
  global absence. Do not omit the ScreenScraper front role when LaunchBox has none.
- Preserve region/language/edition and source hashes at every step. Reuse verified
  resources and provider budgets. Do not scrape during ordinary browsing or expose
  credentials in URLs, output, reports or repository content.
- A missing dump catalogue binding means only that lane has no match. Investigate
  remaining sources, aliases and fixable integration defects before escalating.
  Search the original archive listing and retained edition/model/panel catalogue;
  a partial extraction directory is not the full dump inventory. For example,
  the archive's `NES - Famicom` family includes regional Kirby cartons even when
  an extracted root or selected USA-ROM binding contains none. Record the actual
  source location; do not claim an old scratch extraction still exists.

## 4. Reconstruct and review the carton

- Evaluate complete suitable English or English-containing multilingual sets
  first. Then evaluate the same game's regional/non-English NintAndBox carton
  as a donor before falling back to an entirely flat-art reconstruction. Local
  dump panels/models precede the public .es donor preview. A same-region runtime
  binding is not a prerequisite for an explicitly attributed composite. Verify
  game/alias identity and physical suitability; do not borrow a sequel's printing
  or infer a cartridge shell from the donor carton.
- Preserve donor geometry, useful sides, closures/flaps and opening animation.
  Classify actual panel roles, languages and crop/orientation; inspect unfolded
  and assembled contact sheets. Unknown language is not evidence of English.
  Retain originals and make an attributed derivative, without replacing the
  permanent source edition or changing the selected ROM identity.
- For non-English front/back, use matched English LaunchBox faces first, then
  ScreenScraper for missing faces. Fit to the donor's panel aspect without
  distorting the artwork. A different region/language alone must not discard
  the donor, demand repeated owner approval or trigger a generic carton first.
- Reuse `apply_panel_layouts`, `compose_english_faces` and `fit_panel` in
  `scripts/prepare_packaging_resources.py`; use
  `scripts/artwork_colour_cast.py::match_colour_cast` for the established
  collector-side global correction. The Sapphire decision preserves LaunchBox
  detail/text while matching the original corresponding blue packaging. Use
  corresponding artwork/verified colour-reference pixels, not unrelated art
  or merely a similar palette. Dominant colour anchors need corroboration from
  other corresponding colours; retain the helper's stability/held-out checks.
  Record applied/skipped reason, source/reference/derived hashes and, when
  applied, the single RGB transform. A rejected fit is a colour-review result,
  not permission to force a correction, selectively repaint purple pixels or
  tint the mesh at runtime. Resolve a visible mismatch before acceptance.
- Bind the same derived front to preparation/flat artwork and the 3D carton.
  Review their handoff and the assembled front/side/back colour continuity,
  text, UV alignment, closures, unboxing and inspection. Preserve per-face
  original/donor/composite provenance and source language/printing separately
  from the target edition. Do not describe a composite as an authentic USA box
  merely because it presents a USA ROM or English front.
- Reuse the established GBA best-effort path when only flat art exists. The owner
  permits plain colour-matched missing faces, coherent reuse of available spine
  art, full rotation and zoom. Default to neutral faces rather than repeated
  barcodes/text. This is permission to reconstruct, not six-original-scan evidence.
- Validate a connected opaque volume, UVs, normals, opening seams/flaps/hinges,
  interior/holder, thickness and extraction aperture. Preserve provided geometry
  where applicable; use Blender for actual authoring/mesh review.
- Preserve shared physical dimensions where known and record estimates. Fit the
  camera rather than scaling unrelated objects independently to equal sizes.

## 5. Bind media and accessories independently

- Resolve the actual compatible cartridge/disc family, colour/material and label.
  A box/front cover is not proof of shell or label identity. Preserve special
  moulds, PCB inspection and protective sleeves/cases where applicable.
- Deduplicate complete identical media references; keep distinct regional
  alternatives and disc members separate. Never count a handwritten sticker as
  an authentic decoded label, even if a texture-ready flag is true.
- Ground models together. Measure cables against source-specific length and real
  scene units; preserve controller/plug contacts and right-side cable placement.
  Keep external TVs beside consoles and paths clear. Do not apply NES dimensions
  or startup details to other hardware.

## 6. Import and publish through the existing durable lane

- Bind prepared packaging to the current game and edition identities. Validate
  all roles, regional ownership, image decoding and content hashes before import.
- Use `PackagingResourceImport` and the existing metadata/artwork cache and Drive
  publisher. Preserve source metadata and per-resource provenance. An ADB model
  copy alone does not publish its artwork or prove remote availability.
- Observe the original operation to its actual completed/failed state. Uploaded
  counts are not sync completion. Resolve failed or dirty publication through its
  existing lifecycle; do not use local-only patches to conceal incomplete Drive.
- Independently read back the configured Drive packets and required asset bodies;
  verify exact ownership, sizes and SHA-256. Keep private identities/resources out
  of published source and skill bundles.

## 7. Verify recovery and wire every rendering consumer

- Trace Drive -> shared cache -> private projection -> selected metadata -> actual
  texture -> rendered frame. Prove normal recovery using supported controls and
  preserve user data; do not clear databases or manufacture a clean-cache result.
- Verify upper cards, ordinary detail and the secondary scene all consume the
  same edition-owned packaging and labels. Check each call chain explicitly.
- Keep complete supplied box models first, then integrate collected/reconstructed
  packaging according to section 4's suitability/composition order. A supplied
  model for another language may need its approved derivative; retaining it does
  not mean silently rendering its untranslated front for the target edition.
  A console-specific early return must not bypass the shared source
  and fallback pipeline. Importing artwork without connecting consumers is incomplete.
- Reuse the existing main-engine selection/launch owner. Preserve exact ROM/save
  identity, installation/cloud actions and publication-driven refresh.

## 8. Apply the established product behavior

- Upper gallery: one representative 3D carton, shared upright/rest yaw, bounded
  selected rotation and silhouette glow; idle and Reduced Motion retain depth.
- Lower selector: supplied console/game composition, physical scale, shallow arc
  opening toward the viewer, center behind, direct model taps and no magnifiers.
- Browse: sequential box/contents extraction; correct case/sleeve/booklet; authentic
  selected media; zoom/inspection; translucent Info with local blur and slow
  rotation. Preserve the contract's 10–15% margins and idle tutorial/trivia behavior.
- Launch: generation-correct insertion/startup/screen entry, one compatible random
  console choice per launch, actual owned emulator handoff, double-A skip,
  Back/selection/lifecycle cancellation, Reduced Motion and offline behavior.
- Apply generation exceptions: G&W built-in LCD/Game A has no cartridge insertion;
  coordinate GBA BIOS; preserve NES external TV and NES-101 flap/no-LED details.

## 9. Accept the complete native outcome, then deliver

- Use a per-cohort evidence matrix in the existing ledger: selected identity,
  source/face provenance, conversion, Drive integrity, recovery, upper 3D card,
  ordinary/secondary label and scene, and unresolved requirement.
- Inspect actual pixels for the whole required resource cohort. Readiness flags,
  folder counts, sample games and historical GBA evidence cannot substitute for
  current console coverage. Separate a 2D cover fallback from a validated 3D box.
- Verify ranked order and its alphabetical boundary, score overlay preference,
  navigation/re-entry, selected label consistency and exact publication refresh
  in both entry points. Review smaller ordinary layouts too.
- Verify the complete relevant unboxing/inspection/launch workflow, interruption,
  offline/recovery and Reduced Motion on the intended device. Use diagnostics plus
  screenshots/recordings; GPU readiness is not physical-display timing.
- Keep genuine gaps explicit only after applicable sources and approved
  reconstruction paths are exhausted. Pause affected missing custom resources;
  do not blame an owner rule for an unimplemented or unverified step.
- Reconcile all required acceptance, perform the final provenance/Socket review
  at its authorized place, then the one authorized final release and independent
  delivered-package verification. Samples or successful builds are not completion.

## Existing implementation and evidence anchors

Resolve these within the current G-Shop checkout; line numbers move. They are
navigation aids and historical precedents, not claims of fresh acceptance.

- Acquisition/classification/compositing: `scripts/prepare_packaging_resources.py`,
  `scripts/prepare_unfolded_boxes.py`, `scripts/nintandbox_preview.py`.
- Colour/composite regressions: `scripts/fixtures/test_packaging_panels.py`
  (foreign-panel retention, fitting, identical derived flat/carton front and
  global cast) and `scripts/fixtures/test_artwork_colour_cast.py` (one transform,
  unchanged alpha/originals, matching-art no-op and unrelated-art rejection).
  Run affected checks when changing that behavior; source tests do not replace
  visual review of the actual newly integrated carton.
- Durable import/recovery: `lib/services/metadata/packaging_resource_import.dart`,
  `metadata_artwork_cache.dart` and `metadata_cloud_library.dart` in that directory.
- Composition/rendering: `lib/models/packaging_model.dart`,
  `lib/widgets/unboxing_preview.dart`,
  `lib/features/game_detail/widgets/cover_section.dart`, ordinary detail and dual preview.
- GBA permission: `docs/IMPLEMENTATION_STATUS.md`, historical revisions 70–73,
  especially the superseding revision 72 best-effort decision.
- Cross-collector donor permission and Sapphire correction:
  `docs/SPECIFICATION.md`, paragraphs beginning "Non-English unfolded artwork"
  and "Owner colour-cast decision". These are established owner decisions, not
  new per-console approval requirements.
- Delivered flat-art precedent: the ledger's 2026-10-18 Castlevania six-face box,
  and its GBA publication/cohort/classified-face receipts. The 2026-10-19 Sapphire
  cold-recovery and composed carton/cartridge/booklet evidence is another anchor.
- 2026-10-22 NES audit: dump-only catalogue and early-return preview bypassed the
  shared fallback path; the collector omitted ScreenScraper's front role. Check
  current source before treating those dated findings as still-unfixed defects.
