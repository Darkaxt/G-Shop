# Implementation status and reconciliation ledger

Authority: [SPECIFICATION.md](SPECIFICATION.md).
Execution order: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Scope state

- Work resumed at the user's request on 2026-10-01 after the LoLRoms work.
  The Thor is connected again. Google OAuth branding was completed by the
  account owner; both OAuth test clients are registered. Live provider evidence
  remains required.
- Authorized now: implementation (2026-09-08, "go ahead then").
- Feature implementation: S1 BLOCKED on Thor network access and legitimate
  metadata access; S2-S4 BLOCKED on the required S1 live
  access gates. Their existing partial implementations are retained, not being
  worked on concurrently and not claimed complete. S5-S7 NOT STARTED.
- Google Cloud and ScreenScraper developer access are new setup, as confirmed
  by the user. No provider credentials or successful live access is assumed.
- Existing SD-library migration was missing from the implementation scope.
  User selected Top 25 per console; revision 2 adds MIGRATE-01/S7 after integrated
  live recovery and fresh metadata/rating verification. No deletion before those
  gates; saves/BIOS/settings and uncertain/unrecoverable files are preserved.
- Live account setup: Drive API enabled, both test clients created using the
  actual debug APK signer, single owner test user saved, and read-only Drive
  scope verified after reload (see DEVELOPMENT_SETUP.md). Owner-controlled
  native consent and auth lifecycle proof remain pending.
  Full scraping, live Drive ROM transfer, SD removal and releases have not been
  performed. An isolated synthetic-only debug APK has passed the native
  foundation checks on the Thor and was removed afterwards; this is not a
  deployment of the usable Drive/metadata features. On 2026-10-01 the normal
  debug app was independently inspected and installed in its isolated package
  for live setup; onboarding uses a new internal RShopLiveTest folder, not the
  existing ROM library. No real provider access is claimed by that installation.
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
| S0 | COMPLETE | 65a421b; fork main and preparation branch verified equal; clean worktree; documentation-only scope checked | None |
| S1 | BLOCKED | Additive v14/v15 migrations, native adapters and secure credentials; earlier host/native evidence below; actual debug APK inspected/installed, both OAuth clients registered, test user saved and readonly scope persisted; live package-visibility defect fixed; authorized owner account selected and offline cancellation traced | External B1: Thor has no active network and no nearby saved Wi-Fi; trusted network connection is required before consent/auth lifecycle proof. B2: legitimate ScreenScraper access/lookup remains missing |
| S2 | BLOCKED | Existing paginated catalogue, normal Sources/health/mapping UI and exact queue references retained | External B1: S1 Drive access missing prevents live selected-folder inventory; clients are registered, owner consent and auth proof remain. S5 owns final localized/controller UX |
| S3 | BLOCKED | Existing verified standalone lane, journals, installed index and native retirement evidence retained | B1 prevents required live transfer roundtrip; blocked S2 catalogue acceptance is also a dependency. Ordinary unfinished work remains: crash/reset windows, bundles, replacement/removal, achievements, emulator handoff and large-file proof |
| S4 | BLOCKED | Existing persistent refresh worker and identity-bound provenance checks retained | External B2: legitimate ScreenScraper developer/user access missing prevents authenticated samples and reception gate. Ordinary unfinished work remains: runtime membership, review/retry, quota pacing, artwork and shared query |
| S5 | NOT STARTED | None | UI-01, UI-02, UI-03 |
| S6 | NOT STARTED | None | QA-01, QA-02, QA-04 and complete integrated reconciliation |
| S7 | NOT STARTED | User retention choice recorded in revision 2 | MIGRATE-01: full fresh metadata pass, live recovery, reviewed cloud-verified removals, retained-set and space audit |

B1 blocks DRIVE-01 live authentication and dependent S2/S3 real-system evidence;
trusted Thor network access followed by account consent and verified auth
lifecycle resolve it; client registration is complete and account selection is
authorized. B2 blocks META-02's
authenticated lookup and S4's live matching/reception evidence; legitimate fork
developer access and user credentials resolve it. Neither substitutes for the
ordinary unfinished implementation listed above. No required work is dropped or
reclassified as a deferral. S1 is parked at the external network-access boundary;
no later stage is activated while waiting.

### S1 live setup checkpoint (2026-10-01)

- Authorized Android/web OAuth clients and read-only test audience are saved in
  the existing dedicated project, not a duplicate project. No billing enabled.
- Normal debug APK installed in the isolated package; internal RShopLiveTest
  destination only. No source saved, ROM transferred or SD-library file changed.
- First Connect failed before account selection. Native logs established the
  package-visibility omission: Play Store installed but reported missing.
  Manifest now declares the two required packages without broad inventory access.
  Focused regression observed failing before the fix and passing afterwards;
  targeted analysis passed; rebuilt APK package/signer/compiled manifest inspected.
- With the rebuilt APK, Connect opened the native account chooser on the real
  Thor. This is live entry proof, not granted Drive access, completed auth
  lifecycle or S1 completion.

### S1 account-selection diagnosis (2026-10-02)

- User authorized selecting `darkaxt.remaxku@gmail.com`; the actual native
  chooser was used. Selecting it reproduced the immediate cancelled result
  before Drive consent. No account email was hardcoded into the application.
- Native microG UI logs show AuthSignInActivity returning internal error 8
  with a null account, followed by AssistedSignInActivity reporting cancelled
  16. The installed microG source (v0.3.15.250932) confirms that this bridge
  maps a null account to cancellation without preserving the internal error.
  The app therefore received cancellation even though the user selected an
  account, not Cancel.
- Actual device checks established no active default network, Wi-Fi disabled,
  hostname resolution failures and an IP probe returning Network is unreachable.
  Wi-Fi was enabled for the authorized live test, but no saved network is in
  the current scan results and the Thor remains disconnected. No arbitrary
  public network was joined; DNS settings and Google services were not changed.
- B1 is external: connect the Thor to a trusted network, then repeat native
  account selection, consent and the required auth lifecycle verification.
  S1 and dependent live S2/S3 criteria remain unsatisfied. No SDK downgrade,
  speculative sign-in fallback or production behavior change was made.
- Both displays were verified OFF after the diagnosis. No source saved, Drive
  file changed, ROM transferred, or SD-library file removed.

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

### S3 owned-storage and Thor filesystem checkpoint (2026-09-09)

- Added a bounded JNI filesystem boundary and serialized Kotlin service behind
  the existing storage channel, plus its typed Dart adapter. Each operation uses
  pinned descriptors, no-follow traversal and exact native identity. File IO is
  capped at 64 KiB per operation; callers await writes rather than buffering a
  response in a sink. Namespace publication and parent-directory durability are
  separate events, so a failed sync is retried without repeating the rename.
- Actual Android traversal initially failed because `/data` allows searching but
  not listing. Ancestors now use `O_PATH`; the returned directory remains readable
  and sync-capable. Native tests cover this exact permission case, invalid paths,
  links/FIFOs/hardlinks, pinned-directory replacement, Unicode, identity, read-only
  opens, chunk/offset bounds and no-overwrite collisions. The API-24 ARM64 harness
  was compiled with `-Wall -Wextra -Werror` and passed on the Thor. The APK's ELF
  imports `dlsym`, not an unconditional API-30 `renameat2` relocation.
- Live app-UID tests established two distinct publication constraints: Android
  bind mounts can share `st_dev` but reject cross-mount rename, and this Android
  13 SD FUSE path rejects `RENAME_NOREPLACE`. Staging now prefers the actual mount
  ID from bounded descriptor metadata. Equal mount/device IDs remain hints, not
  guarantees of rename support. Neither failure was hidden with overwrite moves.
- Added the specification's explicit copy alternative at the storage boundary:
  exclusively create a destination, retain the fully verified private source,
  copy bounded chunks, flush/checkpoint, and rehash the destination before finish.
  Resume requires recorded destination identity and exact size/mtime, then a
  byte-for-byte prefix comparison against the source. This rejects same-size,
  same-timestamp edits on SD storage. No public copy API accepts network bytes;
  existing public files are never truncated. Public copies are not installed
  records and can be visible to external file browsers before commit, as recorded
  in the plan. Durable copy intent/identity/offset integration is still required.
- Host owned-storage tests: **15 passed**. Kotlin publication fault tests:
  **5 passed**, zero skipped/failures/errors, verified from the JUnit XML.
  The complete offline command `flutter test --no-pub --concurrency=1
  --exclude-tags live --reporter expanded`: **1,838 passed**, exit 0 (2 min 2 s).
  After import/bracing/explicit-null-only lint fixes, storage plus journal tests
  passed again: **34 passed**, exit 0. Fresh full analysis returns only the four
  pre-existing findings tracked above (exit 1); no new finding or suppression.
- Built an isolated debug integration APK, not a release:
  `flutter build apk --debug --no-pub --target-platform android-arm64
  -t integration_test/owned_storage_test.dart
  --dart-define=RSHOP_STORAGE_TEST_ROOT=/storage/75D7-DC5F/Download`.
  Final native build passed, exit 0 (91.9 s). Verified package
  `com.darkaxt.rshop.debug`, label `R-Shop Drive Dev`, version 1.7.0/12,
  debuggable, min SDK 24 / target 36 and the documented single debug signer.
  APK and installed `base.apk` SHA-256 both matched
  `a87a38a9a074aa5eebf3b852b66eb1abc28946c342d107792308bd029c741585`.
  Subsequent changes only removed redundant imports from the Dart app fixture
  and adapter; native implementation and fixture behavior were unchanged.
- `flutter drive --debug --no-pub -d bfa98654
  --driver=test_driver/integration_test.dart
  --target=integration_test/owned_storage_test.dart
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk
  --keep-app-running`: **six actual native cases passed**, exit 0. These cover
  private checkpoint/resume/publish, collision protection, replaced source inode,
  replaced parent, disallowed staging and the actual SD copy/resume/hash/edit
  protocol. The framework counter also includes setup/teardown, not extra cases.
  Close/reopen is not process-death recovery proof; no native bridge was mocked.
- Tests used only attributable synthetic bytes and a previously absent debug
  package. All-files app-op was granted only to this isolated test UID for the
  SD fixture. Afterwards its exact installed APK identity was checked again,
  the app was force-stopped/uninstalled and its absence verified. Five standalone
  test binaries were hash-matched to host outputs before exact-file removal;
  fixture directories and the test SD Download directory were verified empty.
  No ROMs, saves, accounts, cloud files or host archive were read or changed.
- One main-owned build/test/analyzer workload ran at a time. Gradle remains
  bounded to a 3 GiB heap, 1 GiB metaspace and two workers with in-process Kotlin.
  These primitive fixtures do not establish the integrated stream's 4 MiB peak
  buffer or large-file space bound; those measurements remain S3 acceptance work.
- Verified this checkpoint's sole Gradle 8.14 daemon idle and associated with
  the R-Shop build, then stopped it through Gradle; unrelated Java processes
  remained untouched. Reviewed transactional cleanup inspected all 7,565 entries
  under the three registered generated-output roots and removed 7,546 entries,
  reporting 1,878,939,425 bytes reclaimed (two entries were already absent).
  The build/APK and task temporary root are gone. Six protected hardlinked CMake
  command records remain under `android/app/.cxx` (11,870 summed path bytes,
  not unique allocation); their nonempty-parent removal ticket was explicitly
  revoked, not bypassed. SDK/dependency caches remain. All 24 specification
  requirements still have exactly one delivery-owner row; no missing, unexpected
  or duplicate mappings, and staged Git whitespace verification passed.

This checkpoint establishes storage primitives, not a working Drive download.
S3 still requires durable copy-phase persistence, engine/queue integration,
source-disconnect/cancellation joining, process-death recovery, bundles,
owned replacement/removal and the live offline emulator/remove/re-download
round trip. The explicit Drive payload/removal gate remains. Google/ScreenScraper
setup, S1/S2 live acceptance and S4-S7 are not waived; SD Top-25 migration must
still wait for credible fresh rankings and verified cloud recovery.

### S3 journaled transfer integration (2026-09-09, in progress)

- Builds on `a3f46f8` without changing the installed Thor application or native
  implementation. The new engine connects the production streaming verifier,
  native storage adapter and SQLite journal. Its tests inject only the remote
  protocol/native channel; they do not establish live Drive or native recovery.
- Stage identity, complete verified digests, publication method, destination
  identity/offset and confirmation are durable journal fields. New reservations
  remain pristine; legacy records stay readable without acquiring ownership by
  filename. Verified evidence and confirmed publication cannot be weakened.
- A dedicated native-resume checkpoint permits only an owned, unverified
  private stage's timestamp to be rebound at the unchanged durable offset after
  native tail truncation. Generic checkpoint matching remains strict; inode,
  volume, offset, paths and verified evidence cannot change through that API.
- Publication intent precedes rename/copy. Unsupported/cross-volume rename
  results alone select copy. Recovery hashes recorded source/destination bytes
  against both provider digests and the previously recorded local SHA-256.
  A rename without a receipt can recover only the exact original native object.
  Installed-state and completed status still commit together in SQLite.
- Cancellation joins pending writes, stream disposal and bounded prefix reads.
  Stream-disposal rejection is immediately observed and becomes a failed result,
  never an unhandled future or successful pause. API/native authorization
  cancellation is distinguished from a requirement to reauthorize. Transaction
  guards roll back installation writes on cancellation; the final synchronous
  guard is the commit linearization point. Cancellation after it may truthfully
  return completed when that transaction commits.
- The normal Drive source runtime now exposes an exact, already-reserved transfer
  entry point, with artifact-bound ancestry/version checks and request-time
  authorization. It reserves in-flight IDs and rejects pending starts crossing
  a disconnect generation. Disconnect signals and joins active transfers and
  catalogue refreshes before closing media/metadata transports; stage bytes and
  installed manifests are retained. Existing runtime constructors remain valid.
- Main independently ran the four targeted files serially: **83 passed**, exit 0
  (37 journal, 24 engine, 15 storage and 7 runtime tests). Reproduced behavioral
  failures before their fixes include verification/copy recovery, prefix-read
  cancellation, metadata/native-authorization cancellation classification,
  recorded local SHA-256 recovery, completion rollback, private-tail timestamp
  rebinding and stream-disposal rejection. One early test harness did not settle
  its own completion on an injected error; that single run was stopped, no Dart
  child remained, and the corrected finite fixture reproduced RED then GREEN.
- Required work still inside S3: normal persistent queue/progress/installation
  UI integration; native create-before-identity and copy-tail-before-checkpoint
  crash recovery; explicit owned reset for ignored HTTP ranges; private verified
  source retirement after copy commit; bundles, owned replacement/removal;
  integrated large-file buffer/space measurements and actual process-death and
  live emulator/remove/re-download proof. Existing unrecorded files remain
  preserved conflicts while those protocols are unfinished. No automatic
  adoption, public-file truncation or deletion shortcut was added.
- Fresh integrated verification: `flutter test --no-pub --concurrency=1
  --exclude-tags live --reporter expanded` passed all 1,884 tests (exit 0,
  framework duration 2m01s), after the 83-test targeted integration run. Workloads
  were serialized and their terminal results collected before starting another.
- `flutter analyze --no-pub` reported only the four previously recorded findings
  (`game_grid.dart` and `library_screen.dart` deprecated `cacheExtent`,
  `cover_preload_service.dart` return in try, `l10n_completeness_test.dart` local
  naming); exit 1 is not an analyzer-clean claim. No new finding was introduced.
  Requirement mapping remains 24/24 with no missing or duplicate owner rows;
  `git diff --check` passed.
- Transactional cleanup `814d0f3163441676db5df8beb4dd4752` reached `applied`:
  removed 475 attributed build/test entries, reclaiming 206,058,213 bytes, with
  no residuals/errors. Scope was only generated `build` and the dedicated
  `D:\Temp\rshop-transfer-engine` test directory; both are absent. No ROM,
  account, installed application or SD-library changes occurred.
- No stage acceptance, payload-gate removal, fresh metadata coverage or Top-25
  SD migration is claimed here. S3 and the overall plan remain in progress.

### S3 normal queue integration checkpoint (2026-09-09)

- Continues from `e89c616` (journaled engine/source lifecycle). Drive single-file
  transfers now route through that engine before any legacy staging, extraction,
  filename-existence completion or provider fallback. Unsupported archives and
  bundles remain explicitly gated; this is not acceptance of DRIVE-04/05/06.
- Exact artifact/version/root/path reservations have deterministic IDs and are
  journaled before payload work. Queue preferences are serialized and awaited;
  false/rejected preference writes prevent a new Drive transfer from starting.
  The queue persists transfer IDs, durable progress, pending order and paused/
  authorization-needed states. Interrupted active entries restore as paused,
  requiring an explicit resume rather than repeating a download automatically.
- A Drive attempt owns its callbacks and asynchronous shutdown acknowledgement.
  Pause retains the active slot until stream/native work drains; close joins
  every Drive attempt. Only the engine result after installation commit and
  resource closure emits completion. Observer failures or synchronous row
  dismissal cannot change the committed outcome. Progress uses direct latest
  journal checkpoints, not an accumulating event stream.
- Reusing a completed transfer rechecks its exact installation manifest and
  current native file identity. An externally deleted/replaced target is not
  reported installed from a cached completed bit.
- Queue cards and the collapsed badge distinguish paused, authorization-needed,
  verifying and publishing work. All six locales include the new states and
  actions. Completed icons are not shown for pending/failed jobs or merely for
  receiving every byte. Touch arrows and controller shoulder buttons reorder
  pending jobs only, retain the focused identity and preserve concurrency.
- The actual overlay regression reproduced a disabled reorder arrow falling
  through to the parent row's Remove action. A dedicated reorder input surface
  now consumes that tap without changing the queue. All 14 overlay cases passed
  after the narrow correction. Fixture teardown closes the modal while its
  provider remains alive and flushes the existing zero-duration focus-release
  event; no sleep or lifecycle timeout was added to production.
- Reproduced and fixed immediate-pause `LateInitializationError` and false
  completion after external target replacement. The focused real-runtime tests
  cover native write draining, no-redownload resume, persistence failure,
  mixed-source queued ordering, restored authorization/paused entries, and
  completion-hook failures/row dismissal. An early reorder test helper watched
  the wrong row; only that test process was stopped, its exit collected and no
  workers remained before the corrected finite event-based fixture was rerun.
- Required S3 follow-up remains: exact manifest-based installed/discovery,
  launch/share/achievement/removal paths; hiding noncommitted public-copy intents
  from all R-Shop scans; remaining native crash/reset/retirement protocols;
  bundles/replacement/removal, large-file integrated measurements and live
  process-death/emulator/remove/re-download proof. Existing Drive detail/library
  payload and removal gates stay in place. No ROMs, SD files or accounts were
  changed at this checkpoint.
- The legacy provider audit also found game-ID-only asynchronous callbacks,
  stream-close completion and incomplete legacy shutdown joins. Preserve existing
  provider regression coverage while reconciling these shared lifecycle seams
  inside S3; the new Drive path does not inherit them and this checkpoint does
  not claim that every legacy downloader lifecycle issue has been fixed.
- The preference platform interface is now a pinned direct **test** dependency,
  retaining the already locked 2.4.2 version. Native false-return save/clear
  acknowledgements are independently tested. `collection` is explicitly declared
  at its already locked 1.19.1 version for deep artifact-snapshot comparison.
  Dependency resolution was offline; no package version changed. The storage/
  runtime integration run passed 54 tests before the full-suite check below.
- Main ran `flutter test --no-pub --concurrency=1 --exclude-tags live --reporter
  expanded`: **1,928 passed**, exit 0, framework duration 2m22s. After analyzer
  feedback corrected five brace blocks and the direct dependency declaration,
  the runtime/queue/storage/actual-overlay rerun passed **113 tests**, exit 0.
  Every workload's terminal result was collected before starting the next.
- Final `flutter analyze --no-pub` reports only the same four baseline findings:
  the two deprecated grid `cacheExtent` uses, the cover-preload unawaited return
  and the localization-test local naming lint. Exit 1 is explicitly not a clean
  analyzer claim; there are no new findings. These baseline items remain S6 work.
- Requirement mapping remains 24/24 with no missing or duplicate owner rows;
  `git diff --check` passed. Transactional cleanup
  `336451c86977781fe565401094a0d9a1` reached `applied`, deleting 482 attributed
  generated entries (229,618,632 bytes), without errors or residuals. Both the
  generated `build` root and `D:\Temp\rshop-queue-integration` are absent. Shared
  SDK/dependency caches, source files, accounts, ROMs and device data are retained.
- S3 and the full implementation remain in progress. The normal Drive detail/
  library entry gates are not removed by this tested queue checkpoint.

### S3 installed-state integration checkpoint (2026-09-09)

- Shared offline installation evidence now drives main/isolate local discovery,
  the central installed-files provider, library/game-list badges and detail
  status, plus launch/share path resolution. A matching filename is never proof
  for a managed artifact. Exact source/account/file, version, size and provider
  digests must match a committed manifest and current native object identity.
  Source renaming does not invalidate the committed local bytes.
- Publication intent excludes public copies before their first receipt and
  while paused/failed/unconfirmed. Missing or changed managed objects do not
  reappear as unmanaged files. Pristine reservations protect removal without
  hiding existing unrelated local files. Unmanaged neighbors retain legacy use.
- Roots and target claims account for case aliases only with filesystem identity
  proof; distinct case-sensitive files are not conflated. Redirected ancestor
  paths are rejected. Containing-folder legacy fallbacks cannot expose or share
  a partially published member through another valid member of that folder.
- Target reservation and legacy removal share deterministic overlapping-path
  scopes in the main isolate. Removal sees a prior committed reservation, or a
  new reservation waits for removal to finish. Disjoint paths proceed. This is
  not an external-writer lock or an implementation of managed ROM removal.
- Journal scans use 128-row keyset pages and native inspections only when needed.
  Single-artifact consumers use the artifact index, not a native scan of every
  installed ROM. Additive database v17 introduces that index; real v13-v16
  upgrade/reopen fixtures preserve earlier library/cache data.
- Exact local entries retain artifact identity during merging; unrelated legacy
  archive targets cannot suppress them. Filename-based RetroAchievements hash
  persistence remains explicitly skipped for exact artifacts until its identity
  mapping is implemented. Managed Delete remains gated; no recursive managed
  removal or fabricated successful action is enabled.
- Required S3 work remains: native crash/reset/retirement recovery, safe
  replacement/removal, bundle/playlist completeness, exact achievement mapping,
  integrated large-file measurement and actual emulator/offline/remove/reinstall
  proof. Current queue input is single-file; nested/bundle installations are not
  claimed ready. Controller/provider tests do not replace a full Library widget
  or device acceptance test. S4-S7 and live account setup remain outstanding.
- No account, ROM, H: archive, SD-card, APK or release changes were made here.
- Fresh final `flutter test --no-pub --concurrency=1 --exclude-tags live
  --reporter expanded`: **1,958 passed**, exit 0, framework duration 2m14s.
  Real SQLite/filesystem regressions reproduced publication visibility, case
  aliases, containing-folder fallback and unnecessarily broad native inspection
  before correction. Native inspection alone is faked in those host fixtures;
  no host test is presented as Android proof. No test workloads overlapped.
- Streaming fixtures used maximum 65,536-byte chunks for 32/256 MiB streams;
  sampled RSS was 181,760,000 / 186,986,496 bytes. These are fixture samples, not
  a device peak-memory or multi-gigabyte live-transfer claim.
- Final `flutter analyze --no-pub` retains exactly the four baseline findings
  listed in the preceding checkpoint (exit 1), with no new findings. All 24
  requirements retain unique stage mappings and `git diff --check` passed.
- Reviewed transactional cleanup `5e6c9f8f6919588bed76e4780961f0f2` applied
  successfully: 480 generated entries / 105,393,303 bytes removed, no errors or
  residuals. The generated build directory and task-local test/log directory
  are absent; reproducible test source and the verification summary remain.

### S3 private-stage retirement checkpoint (2026-09-09)

- Completed copied installations now retain a separate durable private-stage
  retirement intent. Cleanup runs only after installation commit and confirmed
  session closure, checks exact stage and installed-file identity, unlinks only
  the app-private entry, and synchronizes its parent. An absent stage is replayed
  safely. A changed stage, active session or changed installed object is preserved.
- Cleanup acknowledgement cannot demote a committed installation to failed or
  cause a new download. Journal/close failures remain pending maintenance. Startup
  recovery is one offline keyset-paged pass independent of saved queue entries;
  it skips active transfers and joins native work when shutdown is requested.
  Page iteration observes shutdown even when all rows are filtered out.
- Fresh integrated host suite: `flutter test --no-pub --concurrency=1
  --exclude-tags live --reporter expanded` passed **1,977 tests**, exit 0,
  framework duration 2m58s. After the brace-only test lint correction, the runtime
  file rerun passed **26 tests**, exit 0. Final analyzer reports only the same
  four baseline findings (exit 1); no new finding remains. No test/build/analyzer
  workloads overlapped.
- Fresh Linux native build (`g++ -std=c++17 -Wall -Wextra -Werror`) and actual
  filesystem contract run passed all eight reported phases, including private
  stage retirement. This does not substitute for Android filesystem evidence.
- The synthetic Android integration APK independently verified earlier in this
  checkpoint had SHA-256
  `D8EF421FE0B14A1315FAF2FDB6121B562BE0FCC354D8C6D3BAC88F16AE4DA574`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12, and the debug signer in
  DEVELOPMENT_SETUP.md. On the Thor, seven native test cases plus setup/teardown
  passed (+9), including actual SD copy publication and private-stage retirement.
  The test package was removed and its synthetic Download fixture cleaned.
  Later Dart recovery changes are covered by host tests, not by that earlier APK.
- A fresh source audit corrected stale gate descriptions: normal Library/detail
  already enqueue supported standalone Drive files into the verified queue.
  Exact-artifact absence and unsupported dependency-bearing layouts still block
  correctly. No in-app emulator-open action currently exists; file sharing is not
  launch proof. Managed removal and the actual download/offline/remove/re-download
  round trip remain unfinished. No stage or whole-feature acceptance is claimed.
- The account owner authorized the dedicated Google project; OAuth policy
  acceptance, client creation and live consent remain pending. No ScreenScraper
  access, fresh metadata pass, ROM migration or release is claimed here.
- Requirement mapping remains 24/24 without missing or duplicate owner rows;
  staged Git whitespace checks passed. Reviewed cleanup removed 7,469 generated
  entries and reported 1,814,135,974 bytes reclaimed across the initial and
  replacement-file tickets. The initial ticket was revoked after its safe
  replacement/lock skips, and the four replaced Flutter test outputs were
  independently reviewed and removed. The verified task-owned Gradle daemon
  (last command completed in this repository, then idle) was stopped, releasing
  its approximately 3.0 GiB private memory and its own performance-data file.
  Six pre-existing protected CMake command records remain; they were not forced
  through cleanup. SDK/dependency caches and unrelated processes were retained.

### S4 persistent metadata job checkpoint (2026-09-09)

- Additive v18 jobs/items/provider-backoff tables preserve prior cached games and
  metadata. Database startup changes interrupted running jobs to paused; it does
  not start scraping or reset an independently active worker.
- Callers supply explicit collection generation and edition membership; snapshots
  never infer membership from historical metadata. A fresh job allocates a new
  generation and does not skip items because an older score exists. Equivalent
  request/release/patch evidence coalesces; arbitrary filenames and container
  digests do not establish ROM identity. Metadata writes and per-edition outcomes
  share one SQLite transaction, in pages of at most 128 items.
- Pause cancels and joins the provider call. Completed pages survive; pending
  items resume. Identity corrections and newer generations remain protected.
  Invalid IDs/provenance and an unlabelled base-game response for a separately
  identified derived game cannot publish a score. Unknown candidate confidence
  remains unknown; title matching is not promoted into a fabricated confidence.
- Account/offline/quota outcomes stop without a busy retry loop or cache purge.
  Explicit provider retry-after boundaries persist across jobs and restarts.
  Full provider rate-window/account-quota scheduling remains required before live
  bulk scraping; current daily-quota observations alone do not satisfy META-06.
- Remaining S4 work includes runtime collection/identity population, compatible
  raw-ROM evidence where actually available, corrected/failed-item review and
  retry entry points, artwork resolution/cache, shared indexed metadata queries,
  and the live reception/source reliability gate. These are required work, not
  waived by the standalone job tests. S5 controls and S7 migration remain pending.
- Fresh full host suite: `flutter test --no-pub --concurrency=1 --exclude-tags
  live --reporter expanded` passed **1,999 tests**, exit 0, framework duration
  2m07s. This includes v13-v17 upgrade/reopen, interrupted-job startup recovery,
  provider/backoff isolation, commit rollback and identity/provenance fixtures.
  The prior interrupted run had no completion result and is not counted.
- The coalescing resource fixture completed 30,000 editions with one equivalent
  provider lookup and 128-item commit pages in 30,630 ms. Observed test-process
  RSS rose from 159,932,416 to a peak 246,509,568 bytes. This is an edition/job
  resource test, not the still-required 30,000-canonical-game query/ranking proof.
  Its initial run reached the framework's default 30-second test deadline;
  the fixture now waits for completion rather than using a correctness deadline.
- Final `flutter analyze --no-pub` reports only the four pre-existing findings
  in game_grid, library_screen, cover_preload_service and l10n_completeness
  (exit 1, 4.0s). The eight findings initially introduced in the job file were
  corrected and do not appear in the final run. Workloads were serialized.
- No live metadata, Drive ROM download, SD deletion or release is claimed.

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
