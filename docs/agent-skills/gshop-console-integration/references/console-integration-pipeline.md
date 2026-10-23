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

## 2. Establish full coverage and the separate testing sample

- Inventory **all ROM archives** for the console, not just ranked games. This
  includes retrospective GBA coverage and current NES coverage. Bind each exact
  archive to its actual game/edition and required resource roles. Deduplicate
  compatible physical resources only with evidence, retaining archive membership.
- Keep raw archive count, distinct games, physical editions, available models,
  fully bound resources, published/recoverable resources and missing/uncertain
  roles separate. A catalogue count or 24/25 successful scenes is not full coverage.
- Do not drop hacks, translations, unlicensed, aftermarket or unranked releases
  from the denominator. Their resources may differ. A genuine lack of retail
  packaging needs an evidenced inapplicability or specific owner acknowledgement;
  absence alone does not establish that packaging never existed. Do not invent
  a physical printing or silently use a base game's artwork.
- Exhaust applicable local sources, regional-donor composition and the existing
  LaunchBox/ScreenScraper reconstruction chain for actionable gaps. Continue the
  full census through identity-bound import, Drive publication and normal recovery.
  Split collections into validated import/provider batches, retaining checkpoint
  membership and reconciling every batch; a 25-game pack limit is not a scope cap.
  For desktop acquisition use `prepare_packaging_resources.py --selection collection`;
  reconcile its full `.selection.json` census and every `.batches.json` pack receipt.
  `--inventory-only` establishes membership, without acquiring/publishing artwork.
  The default ranked selection is a testing aid and cannot establish production coverage.
- Check collector progress against its committed outcome counts: total is all
  items, processed is total minus pending. Display the actual remaining count;
  API calls are a different metric. Verify metadata/artwork phases and paused or
  blocked checkpoints separately. An item processed into review/failure is not
  accepted coverage, and an empty job is not a completed collection. Preserve the
  same durable job when installing a validation candidate and resuming work.
- Do not move on to another console until required full-collection resource
  coverage is verified or each remaining limitation has explicit owner acceptance.
  Missing physical assets still use CI-01; do not disguise them as a backlog.
- Separately select the eligible canonical **Top 25 for native acceptance testing**
  and add risk-relevant edge cases outside that sample. Full-census identity,
  resource-role, content-integrity and publication/recovery checks remain required;
  the Top 25 visual sample does not substitute for them.

- Use the canonical query, current release preferences and actual eligible
  distinct Top 25. Fewer than 25 is valid; zero selected in a populated collection
  requires diagnosis, not an empty coverage claim. Retain exact identities privately.
- Keep ROM program/revision, canonical game, physical hardware/media edition and
  carton printing distinct. Preserve exact matching and the canonical query's
  modification exclusions for ranking only; excluded releases remain in the
  full resource census with their own identities and unresolved roles.
- Verify rating source/confidence/freshness upstream. Both console browser and
  Library need the ranked prefix, full alphabetical tail and visible source-labelled
  scores. Initial selection must use the finished result, not loading groups.

The explicit Windows acquisition lane is documented in `scripts/README.md`:
`prepare_metadata_crawl.py` binds an exact cohort/artifact snapshot to mounted
filenames, and `run_metadata_crawl.ps1` runs the shared provider under Dart.
Preserve its immutable manifest, hashed artwork, item outcomes, read budget and
checkpoint. H: remains cloud backed; persistent caches/checkpoints belong on E:
and compiler scratch on D:. Default zero archive-byte budget means no ROM body
reads. Positive budgets are explicit targeted logical compressed-input budgets,
not measured wire traffic. A completed metadata pass can still contain review or
unmatched items and missing labels; it does not establish integrated coverage.
Do not bypass the existing owned publication lane by dropping unregistered cache
files or arbitrary metadata JSON onto H:.

Source absence needs a correct request and a complete parsing path. In particular,
ScreenScraper returns support selectors such as `support-texture(eu)[1]` with a
separate support number. Preserve the exact indexed wire form in typed references;
cross-check region/number and verify persistence, request, single-cartridge versus
multi-disc mapping and normal publication/recovery. An unindexed `NOMEDIA` probe
does not establish absence of that indexed label. Compare contrary public-page
evidence before invoking CI-01, and invalidate parsed outcomes affected by a fix.
Windows checkpoint/output version 2 rejects the older parser's version 1 receipts;
retain old evidence and deliberately recollect into a new output directory.

## 3. Inventory all required resources and applicable source paths

- Inventory console variants, physical media/shell/materials, authentic labels,
  boxes, sleeves/cases, manuals, controllers/cables, external displays, animations
  and credits. Mark genuinely inapplicable props separately from missing ones.
- For each carton/face, use the existing ordered chain:
  1. reviewed local NintAndBox unfolded scans and reconstructed models;
  2. the public low-resolution NintAndBox .es preview for incomplete dump panels;
  3. for needed/replacement faces, acquire edition-compatible candidates from
     both LaunchBox and ScreenScraper; compare front/back/spine by role;
  4. keep unfolded textures, standalone support labels and bound manuals in their
     appropriate roles; pictures of complete cartridges are not label textures.
- Source order above protects NintAndBox carton construction; it does not make
  LaunchBox or ScreenScraper a universal quality winner. Compare original delivered
  dimensions, actual detail/text, cropping/margins, glare/damage, orientation,
  game/platform/printing compatibility and colour continuity. Same-region scans
  may depict different printings. More pixels may just enlarge blur.
  Preserve both candidates and their hashes in the E: response cache; retain
  candidate measurements and selected/rejected reasons in preparation receipts.
  `prepare_packaging_resources.py --quality-review` accepts private game-ID/role
  entries containing `sourceId`, `sourceSha256` and a concrete `reason`. A changed
  or missing reviewed hash must fail explicitly. Without a reviewed choice, the
  collector reports its measured nomination as requiring visual sample review;
  that nomination is not accepted quality or a new provider-wide ranking.
  The agent performs the review; this is not another owner approval checkpoint.
  Native Top 25 validation still checks the selected images on actual 3D models.
  Donor composition must preserve that per-role choice. Distinct English-face
  candidates need upstream quality selection; the composer rejects ambiguity
  instead of silently preferring LaunchBox again.
- Additional potential artwork fallback: [The Cover Project](https://thecoverproject.net/).
  The owner supplied [Super C, cover 28510](https://thecoverproject.net/view.php?cover_id=28510),
  inspected in the browser on 2026-10-22: Custom Cover, US/NTSC, Universal Game
  Case, credited to Thorr_Warrior. The page also distinguishes custom and retail
  alternatives. Evaluate the actual selected entry, not just the game heading.
  A replacement-case wrap is useful artwork, not evidence of original cardboard
  panels, folds, physical dimensions, shell or opening geometry. Inspect front,
  spine and back boundaries, edition/language and case format before reusing it;
  retain cover ID/URL, creator, category, hashes and derived-crop provenance.
  Prefer established applicable sources above; do not replace a suitable donor
  merely because a custom cover is available. This is a registered candidate,
  not an implemented acquisition/import provider. If used, support its true
  source identity through the normal typed import/publication lane; never relabel
  its art as LaunchBox, ScreenScraper or NintAndBox to pass existing validation.
- Check actual supported selectors and decoded responses, not just provider URLs
  or a list of advertised roles. A failed request for one face/game does not prove
  global absence. Do not omit the ScreenScraper front role when LaunchBox has none.
- Preserve region/language/edition and source hashes at every step. Reuse verified
  resources and provider budgets. Do not scrape during ordinary browsing or expose
  credentials in URLs, output, reports or repository content.
- Search LaunchBox's explicit `GameAlternateName` links as well as canonical
  `Game.Name`. Resolve their `DatabaseID` against the selected platform before
  reading images; preserve all conflicting IDs rather than taking the first.
  Alternate names expose candidates, including compilations/localized names;
  they do not establish a ROM revision, retail printing or modified-release art.
  Recheck the actual cohort against the source index after a collector correction
  and separate new candidate coverage from accepted/imported/published resources.
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
- For non-English front/back, request matched English faces from both LaunchBox
  and ScreenScraper and choose the better compatible face. Fit to the donor's panel aspect without
  distorting the artwork. A different region/language alone must not discard
  the donor, demand repeated owner approval or trigger a generic carton first.
  If a replacement is absent or cannot be prepared, retain the donor face and its
  original language/source provenance. Remove it only after a real replacement
  is prepared; a preferred-language search must not silently delete usable panels.
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
  Reject transforms that invert a primary channel's own contrast, even when a
  positive determinant and aggregate error improvement pass. Different regional
  layouts can otherwise produce a numerically plausible but visibly dark fit.
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
- Verify printing in the **assembled panel**, including its actual mesh UVs.
  A portrait raw scan can correctly map to a landscape face; a material named
  `Scanned front` can be rear-facing. Inspect the actual visible plane/artwork,
  keeping printing identity and text direction as separate checks.
- `prepare_console_model.py` requires box conversions to supply
  `--text-orientation-python` (the actual installed host Python with Pillow),
  `--orientation-title` and, when applicable, `--orientation-language`.
  `verify_carton_orientation.py` samples assembled front/back at 0/90/180/270,
  with whole-panel and source-bound detail-strip OCR through Windows OCR.
  Keep report/word/image hashes. Exact title/brand anchors are relative evidence;
  the engine supplies no confidence score. Sparse/stylized/unsupported-language
  or tied results stay review-required, without an automatic pass or rotation.
- The converter independently checks the original Blender opening against its
  converted hinges. OCR passing does not establish animation correctness, and
  a correct hinge does not establish upright printing. A rejected/uncertain box
  retains its candidate/evidence and exposes no accepted `model.json`.
  Repair a proven source/UV/axis fault, keeping normals, pivots, axes, translation
  keys and pose centres together; recheck closed/open poses and both gates.
  A gallery-only orientation transform is not that repair. Preserve the original.

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
  Paint score upper-right and availability lower-right in the actual front-face
  coordinates, as in GBA. Verify perspective/occlusion while turning and late
  metadata/preference changes; a separate card-space Stack is not equivalent.
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

- Keep a full-census coverage matrix in the existing ledger: archive/game/edition
  membership, required resource roles, source/face provenance, conversion, Drive
  integrity, recovery and unresolved requirements. Check every resource binding
  and body; reconcile all import batches before counting collection coverage.
- Separately inspect actual native pixels and complete workflows for the canonical
  Top 25 testing sample plus risk-relevant edge cases, including upper 3D cards
  and ordinary/secondary labels and scenes. Readiness flags, folder counts and
  historical GBA evidence cannot substitute for that visual acceptance. A passing
  sample cannot substitute for the full-census checks. Separate a 2D cover fallback
  from a validated 3D box.
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
