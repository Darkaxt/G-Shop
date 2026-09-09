# Implementation status and reconciliation ledger

Authority: [SPECIFICATION.md](SPECIFICATION.md).
Execution order: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Scope state

- Authorized now: implementation (2026-09-08, "go ahead then").
- Feature implementation: S1-S3 in progress; no stage acceptance claimed.
- Google Cloud and ScreenScraper developer access are new setup, as confirmed
  by the user. No provider credentials or successful live access is assumed.
- Existing SD-library migration was missing from the implementation scope.
  User selected Top 25 per console; revision 2 adds MIGRATE-01/S7 after integrated
  live recovery and fresh metadata/rating verification. No deletion before those
  gates; saves/BIOS/settings and uncertain/unrecoverable files are preserved.
- Live account setup, full scraping, ROM transfer, SD removal and releases:
  not performed. An isolated synthetic-only debug APK has now passed the native
  foundation checks on the Thor and was removed afterwards; this is not a
  deployment of the usable Drive/metadata features.
- Old scraped metadata: explicitly rejected as the new trusted baseline.
- Metadata-backed best-rated-N and content/genre filters: required in this scope.
  User clarified that the overlay suggestion did not waive the recommended shared
  filtering work. S4 implements the query foundation; S5 exposes filters with
  overlays. Curated archive/device Top policies remain unchanged.
- Top-N membership is calculated dynamically from overall game scores in the
  current collection, including score/catalogue change recomputation. `T-Eng`,
  `Dub`, `Undub` and `Uncensor` are independent combinable tags, not bonus lists.
- Top membership is established before tag/search/installed filters; filters
  intersect ranks without promoting or backfilling lower-ranked games. Score
  evidence must pass META-05's broader-reception gate, not merely exist in a field.

## Repository baseline

- Upstream: `https://github.com/AverageConsumer/R-Shop`.
- Fork: `https://github.com/Darkaxt/R-Shop`.
- Baseline commit: `d615f87277617cbf3a12a6445b3c71d42cf72539`.
- Upstream default branch: `main`; preparation branch: `codex/drive-metadata-spec`.
- License retained: MIT. Baseline version: `1.7.0+12`.
- Stack: Flutter/Dart, Riverpod, SQLite; Android namespace/application ID at
  baseline is `com.retro.rshop`. Any test signer/package plan remains an S1 task.
- No `AGENTS.md` or GitHub Actions workflow was present in the baseline tree.
  This preparation adds the fork's agent entry point, not a release pipeline.
- Flutter/Dart were not found on the preparing shell's PATH. This does not prove
  they are uninstalled. SDK discovery/baseline testing belongs to S1; no dependency
  installation, `pub get`, build or feature test was performed here.

## Reconciliation ledger

| Stage | State | Evidence | Required gaps / next action |
| --- | --- | --- | --- |
| S0 | Complete | 65a421b; fork main and preparation branch verified equal; clean worktree; documentation-only scope checked | None |
| S1 | In progress | Additive v14 identity store and v15 exact game-cache integration; native auth controller/adapter, bounded ScreenScraper adapter and secure credentials; host fixtures and native foundation checks below | Installation/metadata runtime integration still required; Google/ScreenScraper account setup and live provider acceptance not available |
| S2 | In progress | Read-only paginated Drive API, checkpointed catalogue, normal Sources/health/mapping UI, exact game/cache/queue references; integration checkpoint below | Live selected-folder inventory and consent still required; S3 verified transfer replaces the explicit payload gate; S5 completes localized/controller UX |
| S3 | In progress | Binary range transport, source/ancestor and streaming checksum fixtures; v16 durable transfer/installation journal with transactional rollback tests | Native owned storage, full transfer/queue/installation integration, bundles and required live recovery proof remain DRIVE-04/05/06 gates |
| S4 | Not started | None | META-01, META-03, META-04, META-05, META-06, META-07 |
| S5 | Not started | None | UI-01, UI-02, UI-03 |
| S6 | Not started | None | QA-01, QA-02, QA-04 and complete integrated reconciliation |
| S7 | Not started | User retention choice recorded in revision 2 | MIGRATE-01: full fresh metadata pass, live recovery, reviewed cloud-verified removals, retained-set and space audit |

No feature requirement is marked satisfied by documentation. No implementation
stage has passed, so the future requirement backlog must not be reported as zero
remaining work. There are no dropped requirements or scheduled required deferrals
outside the seven implementation stages. Revision 2 has 24 requirements; the
23-requirement count below describes the completed revision-1 preparation.

### S1 foundation checkpoint (2026-09-08)

- Implementation branch: `codex/drive-metadata-implementation`. See Git history
  for its verified checkpoint commit; this is not a claim of completed features.
- Installed official checksum-verified Flutter 3.47.2 / Dart 3.13.2 in
  `D:\Tools\flutter`; Pub cache in `D:\Tools\pub-cache`. No global SDK/PATH change.
  `intl` 0.20.3 satisfies this Flutter localization dependency; the app lockfile is
  now tracked. A moved Cupertino transition class needed an explicit import.
- New game/edition/remote-artifact records and mappings are separate from legacy
  filename data. v14 tables are additive. Real v13 upgrade/reopen fixtures retain
  legacy files and anonymous scores, but do not promote old scores into fresh data.
- Metadata persistence rejects stale generations, mismatched assigned provider
  IDs, and mismatched game/edition/platform. Changing identity invalidates the
  old metadata binding without discarding the old evidence; a title-only rename
  does not invalidate it.
- Native authorization serializes account operations and invalidates pending
  consent on sign-out. Tests cover readonly scope, cancellation, renewal,
  redaction and account isolation. Review reproduced and fixed Android's
  background lightweight-auth UI possibility and cold-start revoke no-op claim.
  The current adapter requires explicit Connect after a process restart; S2 must
  expose this state and not show account UI from queue workers.
- ScreenScraper uses independent developer/user credentials, a private bounded
  streaming client and fixed HTTPS origin without redirects/log interceptors.
  It reports setup/quota/error states, retains provenance and treats title-only
  or modified-game matches conservatively. Ratings remain unapproved for Top
  membership until S4's reception gate. Authenticated artwork is persisted as
  credential-free typed selectors, not credential-bearing URLs; S4 must still
  implement authenticated resolution and caching.
- The source-switch/filename-identity audit is recorded in the plan. Models and
  isolated adapters are not yet exposed through normal Sources, catalogue,
  persistent queue, details or discovery UI. RomM behavior remains unchanged.
- Fork Android IDs are isolated from upstream: debug `com.darkaxt.rshop.debug`,
  future release `com.darkaxt.rshop`. Existing local debug certificate inspected;
  no keystore replaced. At this initial checkpoint no APK was compiled/inspected/
  installed; the subsequent native checkpoint below adds that evidence. Setup is
  in [DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md).
- Tests ran in one workload at a time. Targeted baseline/storage/config checks:
  148 passed. The first full run passed 1,703 and failed four existing Windows
  cases: slash-only folder basename parsing and real multicast socket options.
  Replaced the two basename splits with the platform path library; reproduced
  the OSError with an injected client and handled that specific startup failure.
  Marked the real LAN smoke test `live`, removing its timeout-to-empty success
  workaround. All 19 affected offline tests then passed; no production timeout,
  retry loop or queue workaround was added.
- Final integrated command `flutter test --no-pub --concurrency=1 --exclude-tags
  live --reporter expanded`: **1,707 passed**, exit 0. After the final two
  brace-only lint corrections, the nine store/actual-migration tests passed again.
  No real account access is included in that result.
- Fresh `flutter analyze --no-pub`: **zero errors**, but exit 1 for four existing
  diagnostics outside the feature files: `cacheExtent` deprecations in the two
  grids, `unawaited_return_in_try_block` in `cover_preload_service.dart`, and the
  local naming lint in `l10n_completeness_test.dart`. Analysis is **not reported
  fully green**; reconcile these before S6 acceptance rather than suppress them.
- Final 24-requirement/24-owner mapping and scoped local Markdown links verified;
  Git whitespace check passed. These checks verify the foundation checkpoint,
  not S1 live acceptance or S2-S7 implementation.
- Transactional cleanup removed the SDK download ZIP and generated test output
  (1,987,705,293 reported bytes), plus empty fixture directories. Installed SDK
  and dependency cache retained; no ROM/cloud/device files were removed.

| S1 requirement | Established foundation | Still required for acceptance |
| --- | --- | --- |
| CORE-01 | Separate metadata/artifact store; legacy cache unchanged | Actual catalogue, queue and installation residency wiring |
| CORE-02 | Scoped IDs, edition/disc evidence, explicit platform mappings | IDs survive every S2 merge/cache/queue boundary and user corrections |
| CORE-03 | Additive v13-to-v14 migration and DB reopen tests on host and Android | Integrated source/config/queue migration, process-relaunch and S6 regression proof |
| DRIVE-01 | Native-plugin adapter and deterministic authorization fixtures | Setup UI, real consent/cancel/renew/revoke and account proof on Thor |
| META-02 | Functional independent API adapter/secure credential store fixtures | Legitimate developer/user setup, live authenticated lookup and UI wiring |
| QA-03 | Redaction fixtures, inspected/installed APK identity, native synthetic secure-storage round trip | Integrated privacy and real provider-consent proof |

### Native foundation checkpoint (2026-09-08)

- The user's connected-console instruction authorized live ADB testing. Verified
  AYN Thor / Android 13 / ARM64 and no existing R-Shop package before installation.
  SD free space was about 291 GiB; no ROM inventory, transfer or deletion was run.
- Added four reproducible Android integration cases: isolated activity rendering,
  actual SQLite v13-to-v14 migration/reopen, separate developer/user credential
  secure-storage round trip, and native Google plugin configuration lookup.
  The migration fixture is shared with the host test so the native path exercises
  production database callbacks, without opening the normal app database.
- Targeted host migration/store/authorization checks: **25 passed**, exit 0.
  Scoped Dart analysis of the new/shared tests and driver: **no issues**, exit 0.
- Final `flutter test --no-pub --concurrency=1 --exclude-tags live --reporter
  expanded`: **1,707 passed**, exit 0 (2 min 43 s), after the device run.
  Fresh full `flutter analyze --no-pub` still reports exactly the four existing
  diagnostics listed above, exit 1; no new diagnostic and no analyzer suppression.
- `flutter build apk --debug --no-pub
  --target=integration_test/android_foundations_test.dart
  --target-platform=android-arm64`: **passed**, exit 0 (first build 1,506.8 s).
  SDK manager installed the existing audio plugin's NDK 23.1.7779620 and Platform
  33 prerequisites alongside existing versions. Gradle/Kotlin future-compatibility
  and dependency Java-8 deprecation warnings remain visible; no bypass added.
- `aapt dump badging` established package `com.darkaxt.rshop.debug`, label
  `R-Shop Drive Dev`, version `1.7.0` / `12`, debuggable, min SDK 24 / target 36
  and ARM64 support. `apksigner verify --verbose --print-certs` verified one signer
  matching the documented debug SHA-1. APK SHA-256:
  `7034b9395b5c3b62baf4cf45d53e9993e5352fb33db832ec00a6d996d4ad89ac`.
  The installed `base.apk` SHA-256 also matched this exact artifact.
- `flutter drive --debug --no-pub -d bfa98654
  --driver=test_driver/integration_test.dart
  --target=integration_test/android_foundations_test.dart
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk
  --keep-app-running`: **all four native cases passed**, exit 0. Framework setup
  and teardown add two entries to its progress counter; they are not extra cases.
- No native plugin was mocked. No normal app bootstrap, account picker, token,
  provider lookup, SD permission grant or ROM access was invoked. Android app-ops
  showed no all-files-access operations and default permission mode. DB reopen
  and new credential-store instances are not process-death recovery proof.
- The Google test's omitted client ID invokes the Android local configuration
  lookup. The adapter then reports `setupRequired`. This proves native plugin
  registration, **not** OAuth configuration, consent or successful Drive access.
  Real ScreenScraper credentials and rating/source validation also remain pending.
- Force-stopped and uninstalled only the newly created, test-owned debug package;
  confirmed it absent afterwards. No usable app deployment or release is claimed.
- Ran one build/test workload at a time. Gradle uses a 3 GiB heap, 1 GiB metaspace,
  two workers and in-process Kotlin. Observed native daemon private memory reached
  about 3.1 GiB in samples, with a separate wrapper around 1.2 GiB; these are
  samples, not a measured process-tree peak. System commit headroom remained
  above 40 GiB in the recorded checks. No duplicate workload was launched.
- Confirmed the build's sole Gradle 8.14 daemon idle and stopped it through
  Gradle after verification; unrelated Java processes were left alone.
- Reviewed transactional cleanup removed 8,058 generated entries and reported
  1,859,209,527 bytes reclaimed. The repository build directory, test APK and
  task-specific temporary directory are gone; installed SDK/dependency caches
  remain. Eight hardlinked CMake command records (679,014 summed path bytes,
  not unique allocation) remain protected in the audio plugin's `.cxx` cache.
  Revoked the residual directory-removal ticket rather than bypassing those
  protections or claiming the protected records had been removed.

This checkpoint adds device evidence for foundations only. S1 acceptance and
S2-S7 remain unfinished; it does not authorize skipping the cloud recovery,
fresh rating/metadata or exact-file gates before Top-25 SD migration.

### Drive catalogue and runtime checkpoint (2026-09-09)

- Work remains on `codex/drive-metadata-implementation`; see the corresponding
  Git checkpoint. This is implementation progress, not completed Drive support.
- Added fixed-origin metadata-only Drive v3 GETs with request-time account-bound
  authorization, one rejected-token renewal, bounded response pages and sanitized
  errors. No media, export, mutation or redirect-following method is exposed by
  the catalogue API.
- SQLite refresh generations persist page entries and cursor advancement in the
  same transaction. Only successful traversal/folder-boundary revalidation swaps
  the active snapshot. Failed or cancelled refreshes retain the old catalogue;
  restart resumes unfinished pages. Structural changes, deleted discovered
  folders and invalid cursors invalidate only the pending generation so a new
  explicit refresh can recover. Readers reject a replaced generation instead of
  accepting a partial empty page. No installation table is changed.
- Normal Sources/onboarding now offer Drive setup, actual folder-ID selection,
  explicit console mappings, refresh, health, Connect/configure, Disconnect and
  Revoke. Unknown/unsupported mappings are not activated by a guess. Excluded
  shortcut/Workspace/Shared Drive records are counted without following targets.
  Disconnect cancels and awaits all owned refresh operations and native sign-out;
  it retains source configuration, catalogue and local files.
- Additive v15 migration preserves existing row IDs and legacy references while
  allowing duplicate filenames under different exact remote IDs. Exact identity
  survives game/queue JSON, cache/upsert/rename, source merge, favorites/shelves,
  card/detail reconstruction and queue IDs. Filename-only artwork/metadata and
  installed-file matches cannot assign an unrelated local namesake to Drive.
- A successful system fetch explicitly identifies the Drive source scopes whose
  cache entries can be removed. This permits a verified catalogue to fall from
  100 entries to zero, without weakening the legacy incomplete-scan safeguard or
  granting deletion authority for failed/other sources. Controller callbacks and
  sync markers now follow the awaited database commit. A changed version/size/
  checksum refreshes the UI even when file ID and name have not changed.
- A multi-system sync shares one source preparation for its own lifetime; ordinary
  later refreshes do not reuse a completed/failed preparation forever. Drive
  failures prevent the mixed system result from being published as complete.
- Drive payloads and filename-based local removal remain explicitly gated until
  S3 provides verified streaming, durable publication and owned installations.
  These are required unfinished work, not a working download claim. Canonical
  game/edition matching and fresh metadata/rating query integration remain S4;
  English setup labels/controller refinement remain S5.
- Targeted cache/controller/identity/sync verification after the final authority
  fix: **157 passed**, exit 0. Setup widgets: **3 passed**, exit 0. Fresh-config
  and ambiguous-alias mapping widgets: **2 passed**, exit 0. Both actual v13 and
  v14 upgrade/reopen paths passed, including preservation of an existing v14
  canonical identity. The shared native fixture entry point now targets v15;
  that revised fixture has host proof only until the next native run.
- Final `flutter test --no-pub --concurrency=1 --exclude-tags live --reporter
  expanded`: **1,771 passed**, exit 0 (2 min 16 s), after the last source and
  fixture edits. The prior full run had 1,770 passes before adding the separate
  v14 upgrade case. Native/real-provider tests were not included.
- Full `flutter analyze --no-pub` retains four pre-existing non-error findings:
  the two grid `cacheExtent` deprecations, the cover-preload await warning and the
  localization-test naming lint. No new findings remain; analysis is not fully
  green and these four remain required S6 remediation. No suppression was added.
- Two early compile-only probes briefly overlapped during scaffolding; both
  failing processes were collected before behavioral verification. Subsequent
  targeted/full tests and analysis were serialized and agents ran no workloads.
  Recorded final-run samples showed a single Flutter test tree around 1 GiB
  aggregate working set; this is a sample, not a measured peak or a hard cap.
- ADB again returned `device` for the intended Thor. This checkpoint has no new
  APK build/install, OAuth consent, live provider inventory, ROM transfer, fresh
  metadata pass or SD deletion. The earlier native foundation proof is separate.
- Reviewed transactional cleanup removed 476 task-generated entries and reported
  104,701,164 bytes reclaimed. Only the registered `build` and S2 temporary-test
  roots were included; the ticket reached `applied` with no residual errors.
  Source, SDK/dependency caches and device/cloud files were not cleanup targets.
- The final requirement-map check found 24 requirements and exactly 24 owner
  rows, with no missing, unexpected or duplicate entries. Git whitespace checks
  passed. These static checks do not replace the remaining live acceptance gates.

| Requirement boundary | Established here | Remaining acceptance |
| --- | --- | --- |
| CORE-02/03 | Exact runtime/cache/queue identity and v13/v14-to-v15 migration fixtures | Canonical game/edition grouping, owned installations and integrated relaunch proof |
| DRIVE-01 | Normal connection/disconnect/revoke UI and controlled runtime exit | Account-owned client setup and live consent/renew/revoke/two-account proof |
| DRIVE-02 | Rooted paginated transactional catalogue, explicit mappings and recovery fixtures | Real selected-folder inventory and target-device navigation proof |
| DRIVE-03 | Normal source/factory/health integration and identity-safe persistent queue entries | S3 verified payload lane and mixed-source live queue lifecycle |
| QA-01/02/03/04 | Bounded fixtures, main-owned verification lane, scoped review and explicit ledger | Full integrated feature, resource, privacy and device gates through S6/S7 |

### S3 transport and journal checkpoint (2026-09-09)

- The binary media boundary uses fixed-origin read-only GETs and acquires an
  account-bound token per request. Exact 206 ranges, full-response restart,
  length/encoding contradictions, truncated streams, rejected authorization and
  cancellation are explicit outcomes. A 416 at the exact local length permits
  local verification only; it never declares installation.
- A regression exposed eager buffering in Dio 5.9.1's high-level response
  wrapper: requesting `ResponseType.stream` alone did not propagate upstream
  pause/cancel. Binary requests now use the native adapter's original stream.
  Tests prove no eager subscription, slow-consumer pause propagation and source
  cancellation. Native request-abort exceptions are sanitized as cancellation,
  not malformed-response errors; both failure cases were observed before fixing.
- Queued artifacts must still match the selected source/account/mapping, the
  active catalogue and live file version/size/checksums. Validation reads only
  previously observed ancestors through the selected root; it never follows a
  changed parent outside the selected subtree. The engine must invoke this
  boundary before and after transfer; engine integration remains unfinished.
- Streaming verification requires a recognized valid provider checksum and also
  computes local SHA-256. Missing, malformed or mismatched evidence cannot
  authorize completion. Generated 32 MiB and 256 MiB fixtures use fresh 64 KiB
  chunks on demand, with independently computed SHA-256 expectations. Recorded
  final-suite verifier RSS samples were about 147/151 MiB; these include runtime overhead and
  are not a native transfer peak measurement or proof of the 4 MiB application
  transfer-buffer acceptance limit. Each accepted transport chunk is at most
  1 MiB; the full engine/storage pipeline still needs resource measurement.
- Additive SQLite v16 records immutable transfer intent, exact target ownership,
  durable offsets and lifecycle revisions. Compare-and-swap rejects stale
  updates; resetting a partial requires an explicit paused/failed operation.
  Completion records the exact installation and lifecycle in one transaction.
  Injected SQLite faults after the installation insert and after the transfer
  update both roll back all writes and permit a correct retry. Reopen tests retain
  source identity and durable offset. The journal performs no filesystem IO and
  does not infer publication from a filename.
- Reviewed the journal worker's changes locally, tightened recognized checksum
  validation and replaced a hand-written fixture digest with a computed one.
  Main-run journal tests: **19 passed**, exit 0. Media tests: **20 passed**,
  exit 0. Host v13/v14/v15-to-v16 production migration/reopen cases: **3 passed**,
  exit 0, preserving legacy and exact cache rows. The shared native fixture now
  expects v16, but this revision has no new Android migration proof yet.
- After formatting, the full offline command `flutter test --no-pub
  --concurrency=1 --exclude-tags live --reporter expanded` passed **1,823 tests**,
  exit 0 (2 min 16 s). Fresh `flutter analyze --no-pub` reported no new issues and
  no errors; exit 1 remains for the same four pre-existing diagnostics recorded
  above. Those remain required S6 work, not a green analysis claim. All tests and
  analysis in this checkpoint were serialized by the main agent.
- Transactional cleanup inspected all 469 registered generated entries and
  removed them (104,483,259 reported bytes). Only the repository's test `build`
  output and `D:\Temp\rshop-drive-s3` were eligible; the transaction reached
  `applied` with no residual errors. Source, caches and device/cloud content were
  not cleanup targets. Final specification mapping still has all 24 requirements
  and exactly 24 delivery-owner rows, with no missing or duplicate entries.
- The storage/queue review is captured in S3's execution sequence. The existing
  filename-based mover/deleter and stream-closure completion path are not used
  by these new components. They must be bypassed by the upcoming verified lane;
  the existing Drive payload/removal gates deliberately remain in place until
  native owned publication and queue/manifest integration are actually working.
- ADB returned `device` again. No APK build/install, account setup, live provider
  operation, ROM transfer, metadata scrape or SD removal occurred at this
  checkpoint. Native publication, bundles, restart/cancel recovery, installed
  status/removal and the live offline/re-download round trip remain required S3
  work; S1/S2 live acceptance and S4-S7 have not been waived.

### Preparation verification (2026-09-08)

- GitHub confirmed this repository is a fork of `AverageConsumer/R-Shop`.
- A fresh local checker found 23 unique requirement headings and exactly 23
  matching delivery-owner mappings; no missing or duplicate requirements.
- Local Markdown links resolve. The upstream README's `../../releases` link is
  intentionally a GitHub route, not a missing local directory.
- Independent documentation review was completed. Its removal-time identity
  check was incorporated into DRIVE-06/S3; the final ranking/tag changes were
  re-reviewed without remaining contradictions.
- Changes are limited to the fork agent entry point, three specification/plan/
  status documents and a README navigation notice. No runtime source changed.
- Final Git whitespace/scope checks, commit and remote equality are verified at
  handoff against the resulting Git commit, without a self-referential commit ID
  embedded in this document. This record is not evidence of feature test success.

## Setup dependencies for implementation

| Dependency | Stage / requirements | Resolution and gate |
| --- | --- | --- |
| Implementation authorization | Before S1 | Satisfied: explicit "go ahead then" on 2026-09-08 |
| Flutter/Android toolchain | S1 / CORE-03, QA-01 | Flutter 3.47.2/Dart 3.13.2, host fixtures and debug APK/native foundation proof established; integrated feature/device acceptance remains required |
| Google application configuration and consent | S1 / DRIVE-01, QA-03 | New account-owned project/client setup required; package/signer plan documented, no copied secrets |
| ScreenScraper application authorization | S1 / META-02 | Obtain legitimate developer access for this fork; existing RetroBat user credentials do not establish application authorization |
| ScreenScraper user access/quota | S1 / META-02 | User enters or explicitly authorizes account setup; verify capabilities and redact all request diagnostics |
| Credible overall-score basis | S4 / META-05, META-07 | Validate reception/sample support; if insufficient, integrate a legitimate aggregate-score source before Top acceptance |
| Live content and storage target | S3, S6 / DRIVE-06, QA-02 | Select an authorized synthetic/homebrew/test artifact and exact device destination; preserve existing installations/saves |
| Public distribution credentials/policy | Only if release requested / QA-03 | Separate review of OAuth distribution, developer API terms and signing; not needed to prepare this fork |

These are concrete stage gates, not claims that access is available or that the
features are already blocked irrecoverably. Offline development can proceed where
independent; a fixture cannot replace the required live acceptance evidence.

## Evidence recording rules

For each implementation stage append: source commit, requirements reconciled,
commands/tests and exact results, device/build identity when relevant, observed
resource bounds, blockers/deferrals and their destination stage. Record only
sanitized aggregate coverage in version control. Keep account identifiers, private
catalogue data, tokens and game payloads out of the public fork.

When implementation is authorized, start at S1 after re-reading the specification.
Do not start from old metadata or restart the architectural discussion from scratch.
