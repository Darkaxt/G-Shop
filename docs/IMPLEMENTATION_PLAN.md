# Staged implementation plan

Authority: [SPECIFICATION.md](SPECIFICATION.md), revision 1.
Actual progress and reconciliation: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

Preparation is authorized and is the current endpoint. Stages S1-S6 describe
future implementation, not work performed by writing this plan. Once that scope
is authorized, proceed through it without new routine stage-approval gates.

## S0 — Fork and specification preparation

Objective: preserve upstream and provide a complete, traceable development entry.

- Fork upstream under the user's authenticated GitHub account; retain MIT license.
- Keep `origin` as the fork and `upstream` as AverageConsumer/R-Shop.
- Prepare a `codex/` branch, authoritative specification, staged plan and ledger.
- Review requirements and scope, validate documentation links/mapping, inspect the
  final diff, commit and push documentation only. Do not open an upstream PR.

Evidence: fork parent/default-branch identity, upstream base commit, complete
requirement mapping, clean documentation diff, commit and remote branch equality.
No Flutter build or feature test is necessary to validate documentation-only work.

## S1 — Shared identity, migrations and external-access setup

Requirements: CORE-01, CORE-02, CORE-03, DRIVE-01, META-02, QA-03.
Depends on: S0 and authorization to implement.

- Establish Android development SDK/runtime and baseline test status. Resolve
  package/signing identity before OAuth registration or any installation.
- Add provider-independent game/edition/remote-artifact identities, rating
  provenance and database/config migration contracts, with tests first where
  behavior is reproducible. Inventory every SourceType/ProviderType switch.
- Add Android authorization adapter and credential-store interfaces; complete
  authorized Google client and ScreenScraper developer/user setup. Do not borrow
  other applications' embedded developer credentials. Use fixture clients until
  legitimate live access is available, without calling those fixtures live proof.
- Create the metadata-provider contract and a functional ScreenScraper adapter;
  retain RomM as an optional adapter and preserve existing source behavior.

Evidence: migration and identity regression tests; consent/cancel/renewal/account
isolation proof; redaction tests; live authenticated metadata lookup. Missing API
access blocks the corresponding acceptance criterion, not unrelated fixture work.

## S2 — Drive catalogue and source integration

Requirements: DRIVE-02, DRIVE-03.
Depends on: S1 identities, migrations and Drive authorization.

- Add Drive configuration, normal Sources UI/factory/resolver and source health.
- Implement folder-ID selection, explicit system aliases/mappings and paginated
  checkpointed traversal with transactional catalogue publication.
- Feed exact remote artifacts to the existing queue; resolve authorization at
  request time. Preserve existing mixed-source queue options.

Evidence: pagination/nesting/duplicate-name/cross-account fixtures; refresh failure
and rename/move reconciliation; live selected-folder inventory; no ROM body reads
and no traversal outside the selected subtree.

## S3 — Verified transfer and owned installations

Requirements: DRIVE-04, DRIVE-05, DRIVE-06.
Depends on: S2 exact artifacts/queue and S1 migrated state.

- Add durable stage/publication records and version-bound range validation.
- Stream hashes; gate installation on size/checksum; account for real staging
  space and capability restrictions. Test lifecycle transitions with explicit
  events, including cancellation and process recovery.
- Track installed path ownership; protect existing targets, bundles and saves.
  Revalidate identity before local removal and preserve files replaced by another
  app; reject redirected paths rather than trusting a stale ownership entry.
  Refactor common transfer code only as needed by these contracts, retaining
  existing-provider regressions. No arbitrary full-downloader rewrite.

Evidence: fault-injected HTTP/state/storage tests, large-file bounded-buffer
measurement, missing-checksum blocker, multi-disc consistency and exact-file
removal tests including replaced-owned-file and redirected-path conflicts.
Live transfer/verify/offline emulator/remove/re-download proof is
required, using a deliberately chosen test artifact and destination.

## S4 — Fresh metadata pipeline and score semantics

Requirements: META-01, META-03, META-04, META-05, META-06, META-07.
Depends on: S1 provider/identity contracts; S2 remote catalogue for integration.

- Implement persistent full/per-system/per-game refresh generations, correction
  preservation, deduplicated work, quota control and fresh coverage reports.
- Ignore historical gamelist data as a trusted baseline. Revisit every game
  identity, with explicit no-match/failure outcomes instead of fake completeness.
- Validate platform/release/hash matching; distinguish container identifiers,
  hacks, `T-Eng`, `Dub`, `Undub`, `Uncensor`, base-game ratings and unknown
  classifications. Test independent/combined tags and official-English distinction.
- Retain provider scales/provenance/count availability and separate cache from
  installation residency. Do not invent a popularity aggregate or fixed Top list.
- Validate overall-score reliability against broader critical/community reception
  under META-05. Resolve inadequate source evidence through a legitimate aggregate
  score adapter when needed, before claiming Top membership is meaningful.
- Implement indexed, shared metadata query/filter behavior at the same time as
  persistence. Test category/genre constraints, any/all tag combinations, dynamic
  collection-only Top-N using the displayed accepted overall score, recomputation
  on score/catalogue changes, rank-before-tag-filter intersection with no backfill,
  scope/limits and
  game grouping before UI wiring; do not duplicate library and console semantics.

Evidence: stale-cache refresh, duplicate demand, ambiguous/hack matching,
normalization, quota/pause/restart/offline and rank-before-tag-filter tests; a
30,000-game bounded fixture with paged query and deduplication measurements;
fresh live samples including older and newer consoles and modified releases.
Unmatched provider coverage is reported honestly and does not authorize false
matches. Run the full fresh library pass only within authorized live scope.

## S5 — Cover overlays, filters and unified metadata UX

Requirements: UI-01, UI-02, UI-03.
Depends on: S4 provenance/cache and S1/S2 setup states.

- Feed batched cached ratings into all shared-card callers, not network/database
  calls per frame or a library-only implementation.
- Add optional source-labelled overlays, stale/base-game labeling and accessible
  details/correction/refresh controls in existing screens.
- Wire the tested shared queries into existing filters: `Hack`, `T-Eng`, `Dub`,
  `Undub`, `Uncensor` and other content tags, any/all matching, genres, and dynamic
  Best rated 10/25/50/100/All within the user's collection with explicit scope,
  score basis and ranked coverage. Persist choices and support Clear filters.
- Preserve controller focus, touch, title/RA/favorite/platform/download badges and
  existing library tabs. Implement filters alongside overlays in this stage.

Evidence: widget/golden tests for badge collisions and score states; scrolling
with network disabled and measured request counts; actual handheld screenshots
and controller navigation proof, including combined filters and manual shelf
order. No burnt-in artwork or metadata-only ROM fetches.

## S6 — Final reconciliation and remediation

Requirements: QA-01, QA-02, QA-04; integrated recheck of every requirement.
Depends on: S1-S5, including all required live acceptance evidence.

- Re-read the full specification, not just this plan. Resolve every required
  blocker and tracked deferral; rerun the affected and integrated verification.
- Verify existing sources/config/queue/migrations and the combined on-demand
  workflow without a PC or RomM dependency. Verify cloud/read-only and save safety.
- Reconcile fresh metadata coverage and stale/unmatched handling after relaunch.
- Review security-sensitive paths, secret redaction and test/build resource use.
- Commit tested work and update the ledger. Release/deployment is a distinct
  authorized outcome; do not auto-publish an APK at each stage.

Evidence: requirement-by-requirement pass/fail with commands, fixture identifiers,
source commit and device/build identity; zero unresolved required blockers and
deferrals. Public evidence must not contain private inventories or credentials.

## Source extension map (baseline, not implemented classes)

| Area | Existing entry points | Required consideration |
| --- | --- | --- |
| Source registration | `lib/models/config/source.dart`, `provider_config.dart`; `lib/services/provider_factory.dart`, `source_resolver.dart`, `source_provider.dart` | Both source/config layers and UI must recognize Drive |
| Native auth | `android/app/src/main/kotlin/com/retro/rshop/MainActivity.kt`; Android build/config | Dedicated adapter with signer/account-aware authorization |
| Catalogue | `lib/services/unified_game_service.dart`, `library_sync_service.dart`; `lib/models/game_item.dart` | Stable identity and transactional refresh, not name-only merging |
| Transfer | `lib/services/download_handle.dart`, `download_service.dart`, `download_queue_manager.dart`; `lib/utils/file_utils.dart` | Request-time auth, validated resume, journaled publication |
| Installed files | `lib/services/rom_manager.dart`; `lib/providers/installed_files_provider.dart` | Exact ownership; existing folder-name deletion is not a safe contract |
| Metadata | `lib/models/game_metadata_info.dart`; `lib/services/database_service.dart`, `providers/romm_provider.dart`, `romm_api_service.dart` | Currently one nullable rating imported from RomM |
| Artwork | `lib/services/thumbnail_index_service.dart`, `thumbnail_service.dart` | Existing Libretro covers are distinct from a rich metadata scraper |
| Card data/UI | `lib/providers/game_providers.dart`; `lib/widgets/base_game_card.dart`; `lib/features/library/library_screen.dart` | Cached scores must reach every card caller |
| Filters | `lib/features/game_list/logic/filter_state.dart`, `game_list_controller.dart`; `lib/features/library/library_screen.dart` | Existing filters are separate; share metadata query semantics before adding UI controls |
| Details | `lib/features/game_detail/widgets/game_info_card.dart`, `metadata_badges.dart` | Explain source/scale/staleness and modified-game identity |

## Verification operating procedure

During implementation, discover the installed Flutter SDK before using it. Do
not install/upgrade a toolchain merely to claim the preparation is complete.
Capture existing failures before changing behavior. Run targeted tests first,
then the relevant integration/regression suite as one workload, for example
`flutter test --concurrency=1`. Await its real process completion. Inspect output
before starting a new workload; use bounded fakes instead of infinite providers.
`flutter analyze` and native authorization/storage tests are separate evidence.
Build and device success cannot be inferred from a source review or a unit test.

## Requirement-to-stage map

Each requirement has one delivery owner; dependent stages must still maintain it.

| Requirement | Owner | Acceptance evidence |
| --- | --- | --- |
| CORE-01 | S1 | File/metadata/residency isolation tests; combined S6 proof |
| CORE-02 | S1 | Identity/platform/variant fixtures |
| CORE-03 | S1 | Existing-state migration/restart fixtures |
| DRIVE-01 | S1 | Native auth, account isolation, read-only and redaction proof |
| DRIVE-02 | S2 | Paginated rooted catalogue and failed-refresh tests |
| DRIVE-03 | S2 | Normal source UI and mixed persistent queue tests |
| DRIVE-04 | S3 | Range/version/checksum and large-file resource tests |
| DRIVE-05 | S3 | Cancel/crash/publication lifecycle recovery tests |
| DRIVE-06 | S3 | Ownership, bundles, saves and live reinstall proof |
| META-01 | S4 | Fresh generation ignores old cache; explicit coverage outcomes |
| META-02 | S1 | Legitimate standalone provider setup and live lookup |
| META-03 | S4 | Match/correction/container-hash fixtures |
| META-04 | S4 | Hack/T-Eng/Dub/Undub/Uncensor tags and base-score isolation tests |
| META-05 | S4 | Provenance/scale/null/count tests, reception benchmark, low-vote outlier and source-remediation gate |
| META-06 | S4 | Quota/offline/resume/30,000-game bounded job tests |
| META-07 | S4 | Shared paged query; dynamic overall-score Top; any/all tags intersect ranks without backfill; grouping and scope tests |
| UI-01 | S5 | All shared-card callers, widget/golden and device proof |
| UI-02 | S5 | Setup/refresh/details/controller acceptance |
| UI-03 | S5 | Integrated Top/category/genre filters, scope, persistence and controller proof |
| QA-01 | S6 | One-workload, deterministic lifecycle and resource evidence |
| QA-02 | S6 | Existing-provider regressions and combined live workflow |
| QA-03 | S1 | Privacy/authorization/signing gates, rechecked at S6 |
| QA-04 | S6 | Full-spec reconciliation; no unresolved required gaps |
