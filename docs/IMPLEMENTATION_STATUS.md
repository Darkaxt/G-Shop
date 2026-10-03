# Implementation status and reconciliation ledger

Authority: [SPECIFICATION.md](SPECIFICATION.md).
Execution order: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Scope state

- Work resumed at the user's request on 2026-10-01 after the LoLRoms work.
  The Thor is connected again. Google OAuth branding was completed by the
  account owner; both OAuth test clients are registered. Live provider evidence
  remains required.
- Authorized now: implementation (2026-09-08, "go ahead then").
- Feature implementation: S1 BLOCKED at the owner's second Google test-account
  choice, with elapsed-expiry verification also remaining. ScreenScraper access
  B2 is resolved by the actual adapter's authenticated live lookup on 2026-10-03.
  Additional required authorization evidence is retained below. First online
  authorization, cancellation/reconnect and QA-03 release naming are verified.
  S2 COMPLETE: rooted live refresh, explicit mapping, exact cached game references
  and offline cold-start browsing are verified. S3 COMPLETE against DRIVE-04/05/06:
  verified transfer, native process recovery, bundles and owned installations.
  S4 is ACTIVE again: B4 application authentication is resolved by the authorized
  dedicated Twitch app and a real review/publication/offline-consumption check.
  Its representative reception assessment and earlier unexplained host artwork
  wait remain required. S5-S8 NOT STARTED; no parallel ACTIVE stage is opened.
- Google Cloud and ScreenScraper developer access are new setup, as confirmed
  by the user. Drive's first real read-only authorization was verified on
  2026-10-02; ScreenScraper developer credentials are stored in the ignored local
  environment file and actual-adapter authenticated lookup is verified.
- Existing SD-library migration was missing from the implementation scope.
  User selected Top 25 per console; revision 2 adds MIGRATE-01/S7 after integrated
  live recovery and fresh metadata/rating verification. No deletion before those
  gates; saves/BIOS/settings and uncertain/unrecoverable files are preserved.
- Live account setup: Drive API enabled, both test clients created using the
  actual debug APK signer, single owner test user saved, and read-only Drive
  scope verified after reload (see DEVELOPMENT_SETUP.md). Authorized native
  consent and initial Drive API access succeeded; full auth lifecycle proof
  remains pending.
  Full scraping, existing-library migration and releases have not been performed.
  An isolated real Drive/SD/emulator round trip is now verified (see S3 live
  checkpoint below); this does not authorize bulk removal. An isolated
  synthetic-only debug APK has passed the native
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

### S4 dedicated Twitch registration and live IGDB verification (2026-10-03)

- The owner explicitly authorized a separate Twitch application and local
  configuration update, then completed sign-in. `R-Shop Metadata Private` is
  registered as Confidential/Application Integration with an unused loopback
  redirect. The existing application is untouched. Only the two IGDB keys in
  ignored `.env.local` were replaced; ScreenScraper configuration is preserved.
  No credentials or bearer tokens are embedded, committed or displayed in logs.
- Secret-generation clicks reported browser dispatch failures after opening the
  confirmation. The owner accepted two generations before the ambiguity was
  recognized. No further generation occurred; the latest displayed pair was
  saved and subsequently authenticated successfully. This was an execution error,
  not a reason to keep renewing credentials.
- The first real workflow reached authenticated IGDB HTTP 200 but exposed the
  existing scalar platform filter: `platforms = 19` excludes originals available
  on additional platforms. Searches returned single-platform mods instead;
  the original-score ownership guard correctly refused to publish a hack's score
  as official. The documented membership filter `platforms = (19)` corrects the
  discovery query without adding requests, retries or fallback branches.
- A focused multiplatform-query regression failed against the old query and
  passed after correction. The provider/normal persistent-job ownership checks
  passed. The live smoke review now selects the literal public title instead of
  punctuation-stripped equivalence, so `Super "Mario" World` cannot stand in for
  `Super Mario World`.
- Fresh real adapter -> catalogue discovery -> explicit candidate review ->
  sourced overall/critic/community scores with counts -> persisted SQLite ->
  provider closed/offline consumption passed, exit 0. The API pair is working;
  B4 is resolved. This is not approval of scores for Top membership: the broader
  META-05 reception assessment remains ordinary required S4 work. S4 is ACTIVE,
  S1 remains BLOCKED at B3/elapsed renewal, S2/S3 COMPLETE, S5-S8 NOT STARTED.
  No Thor mutation, bulk scrape, ROM transfer, migration, monitoring or release.
- Scoped analysis of the changed provider and test files passed with no issues,
  exit 0. Final Git whitespace/scope review passed. Reviewed cleanup
  `be2ef810d105f9d819d6b08c015e9df6` is terminal APPLIED: regenerated test assets
  and kernel cache only, 57,347,389 bytes removed, no warnings/errors. These are
  reproducible outputs, not source assets or APKs; credentials and prior
  diagnostics are outside the cleanup roots.

### B4 credential-boundary revalidation (2026-10-03)

- The owner correctly pointed out that IGDB credentials are already supplied.
  Both keys are present in the ignored `.env.local`, with no enclosing quotes,
  outer whitespace, inline comment or process-environment override. Presence is
  not the blocker and no replacement application/account is required by this
  finding.
- A fresh independent PowerShell form POST, outside Dart/Dio/the job worker,
  returned HTTP 403 with the fixed classification `invalid-client-secret` and
  no token. This narrows B4 to rejection of the supplied secret, not an absent
  setup, Thor availability or an inferred user-password problem. Request data,
  response bodies and credentials were not printed or persisted. The documented
  Twitch token form was rechecked; no app credential or secret was changed.
- The earlier Twitch tab is no longer present. The new existing-application
  management tab reaches Twitch's unauthenticated login form. Owner sign-in/MFA
  is needed to inspect the actual registered application and reconcile its secret.
  At that checkpoint no new app was authorized. The owner's subsequent explicit
  authorization and sign-in resolved this handoff as recorded above. Never reset
  another application's secret or reuse another service's user password.

### S4 native metadata ownership and classification reconciliation (2026-10-03)

- S4 remains the sole ACTIVE stage. The existing host ownership assertions now
  run unchanged with Android's actual SQLite factory through
  `integration_test/metadata_ownership_test.dart`. Real ScreenScraper/IGDB
  adapters, catalogue snapshots, review/retry, persistent refresh publication,
  canonical grouping and offline collection queries participate. Wire responses
  and credentials are synthetic: this is native integration evidence, not live
  ScreenScraper/IGDB API or reception-approval evidence.
- On the authorized connected Thor, wrong raw hash/size/game/platform/region/
  language responses were rejected without metadata publication; matching raw
  revisions survived fresh re-scraping with exact edition evidence preserved.
  Verified project variants grouped separately from originals, while changing
  the linked base invalidated their assertions. Reviewed `T-Eng + Undub +
  Uncensor` and finite aliases reached offline queries with explicitly original-
  game ownership, no invented rank, and no request while filtering. Normal
  provider access-error/recovery/review/publication also reached cached scores.
- Classification reconciliation is verified against META-04: focused host
  identity/catalogue/query checks (session 56479, exit 0) additionally cover two
  patches, independent translation/audio/uncensor evidence, official English
  versus T-Eng, unknown labels, contradictory official review rollback, any/all
  tag intersection and no rank backfill. Existing production migration/reopen
  evidence remains applicable; no production code or schema changed in this
  fixture extraction. No score source was approved by synthetic assertions.
- Host ownership extraction checks exited 0 (70442). Final scoped analysis
  exited 0 with no issues after using the already-declared sqflite dependency.
  Native build exited 0 (17316); its package/version/signer were independently
  inspected before `adb install -t -r`. APK SHA-256:
  `5D3D62F44C34A6C9A2148B46B957FFA841FBB79A09EF7904969800073B5B6196`.
  Actual device logs show the complete ownership workflow passing in five
  seconds. The driver attached to the observed VM service and exited 0 (35561);
  its private report was read from
  `D:\Temp\rshop-s4-ownership-20261003\reports`. Workloads were sequential.
- The exact prior normal APK was restored and its on-device SHA-256 again equals
  `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  Database, both secure-storage files, ordinary preferences and Google sign-in
  preferences retained their pre-test fingerprints during and after the run.
  App stopped, task ADB forward removed, both displays confirmed OFF. The tests
  used only in-memory synthetic databases; no source bootstrap, account access,
  ROM payload, SD-library mutation or release occurred.
- Reviewed cleanup `8471775b0c06eb8a7e890c518f8331fc` is terminal APPLIED:
  only the 250,598,905-byte recovery APK copy was removed after exact restoration.
  Native reports and the earlier host-stall forensic fixture remain preserved.
- META-03/META-04/META-07's adapter/job/identity/query path now has native fixture
  evidence. S4 is not COMPLETE: META-05's legitimate live aggregate-source and
  reception assessment remain blocked by B4, and the earlier host artwork wait
  is still unexplained, not claimed fixed by a successful native run. The existing
  Twitch setup tab still shows the owner's login form; no credential change or
  repeated invalid-client request occurred. Real external metadata access and
  later UI integration remain distinct from this synthetic transport proof.
  Reconciliation parks S4 as BLOCKED at external B4: META-05/META-07 cannot
  approve a credible overall-score ranking basis while the actual configured
  Twitch application pair is rejected and the owner login/MFA handoff is still
  pending. Resolution requires legitimate matching API credentials followed by
  live representative reception assessment, not another fixture run. S5 Top
  acceptance and S7 retention/migration cannot complete until this passes.
  The earlier unexplained host artwork wait stays recorded under S4; it is not
  renamed a deferral or claimed fixed. S1 stays BLOCKED at B3/elapsed renewal;
  S2/S3 COMPLETE; S5-S8 NOT STARTED. S5 may next use the already-verified metadata
  interfaces for normal controls/overlays/filters without approving real Top
  scores. Return to S4 when the external handoff resolves. Monitoring remains
  cancelled; no required work is silently waived.

### S4 Thor query/artwork resource acceptance (2026-10-03)

- The owner made the Thor available and authorized this run. S4 remains the sole
  ACTIVE stage; META-06/META-07 native resource checks now have actual-device
  evidence, not host inference. The shared fixtures ran sequentially against the
  Android SQLite plugin, filesystem and Impeller/native image decoder.
- The production indexed query handled 30,000 synthetic collection identities
  and scores: 25 Top members, stable bounded pages, no genre-filter backfill,
  zero projection writes during filtering, and at most 128 identity/metadata rows
  per observed read. Projection build was 317,501 ms; two warm queries 1,817 ms.
  The initial build latency is recorded, not presented as instant browsing.
- The real persistent artwork worker completed 30,000 distinct edition-owned
  selectors with one active transport and 65,536-byte maximum chunks. Snapshot
  capture took 33,377 ms; total artwork workflow 297,684 ms. It verified the real
  4,002,288-byte PNG, two content-addressed bodies, complete item outcomes,
  database close/reopen, offline consumption and completed-job replay with no
  additional request. Peak process RSS was 602,492,928 bytes (about 575 MiB).
- Native driver session 67232 exited 0 after 10m28s; its actual report was read
  from the private `D:\Temp\rshop-s4-native-20261003\reports` directory. The test
  APK was independently inspected: com.darkaxt.rshop.debug, 1.7.0/12, registered
  debug signer, SHA-256
  `85102743B1AC2C4C7FF204F1CF616DA2B49269EC6661B2DBB90CA8898B3A225D`.
  It was installed with `adb install -t -r`; the driver attached to its observed
  live VM service without installation/uninstall or rebuilding. No ROM/account
  request occurred and no real ranking source was approved by synthetic scores.
- Both validated private fixture directories were absent after completion. The
  exact previously installed normal APK was restored without uninstalling and
  its device SHA-256 equals the preserved original
  `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  Database, secure credentials/key storage, ordinary preferences and Google
  sign-in preferences retained their exact pre-test SHA-256 fingerprints through
  installation, execution and restoration. App stopped, diagnostic log listener
  stopped, the task's ADB forward removed, and both displays confirmed OFF.
- This closes the specific native query/artwork resource evidence gap. It does
  not explain the earlier isolated host wait, prove real native metadata-provider
  integration, approve reception-aligned scores or complete S4. B4/META-05 live
  assessment and remaining integrated metadata evidence stay required. S1 remains
  BLOCKED at B3/elapsed renewal; S2/S3 COMPLETE; S5-S8 NOT STARTED. Monitoring
  remains cancelled and no release or SD-library migration occurred.
- Reviewed cleanup c6606d1463eb2a68f7f80bde0c80cb36 is terminal APPLIED:
  56,954,805 bytes of generated test-cache/assets removed with no warnings/errors.
  The old host-stall forensic fixture and native report remain preserved.
- After independently verifying exact restoration, reviewed cleanup
  b91cb222ed99c03343c35cb632946dc2 is terminal APPLIED: only the 250,598,905-byte
  task-generated recovery APK copy was removed. Its defined recovery purpose
  was complete; the native report/driver trace and original forensic evidence
  remain preserved. No source, ROM, credential or application-data deletion.

### S4 native resource handoff checkpoint (2026-10-03)

- S4 remains the sole ACTIVE stage. The actual artwork-cache boundary completed
  12,000 native decoder/publication iterations on the host without reproducing
  the earlier wait: 69,998 ms, peak RSS 178,720,768 bytes. This excludes persistent
  worker/database publication and is not a root-cause finding or a bug-fix claim.
  The preserved interrupted artwork fixture remains diagnostic evidence.
- The existing indexed-query and artwork-worker resource assertions now share
  factory-injected fixtures between host FFI and the new Android entrypoint
  `integration_test/metadata_resource_test.dart`. Default native and existing
  full host checks still cover 30,000 games; no acceptance size was reduced.
  Native package/platform/debug guards precede synthetic private fixture writes.
  No normal app/source bootstrap, account access or SD-ROM operation is included.
- Focused extraction verification exited 0 (session 14260): 256 distinct artwork
  selectors completed, retained two verified blobs, reopened offline and replayed
  without a new request; 3,000 collection identities exercised the production
  indexed query, stable pages and no-backfill intersection. Artwork measured
  12,204 ms and peak RSS 169,766,912 bytes; query projection 62,632 ms, two warm
  queries 121 ms, peak RSS 228,962,304 bytes, at most 128 identity/metadata rows.
  Scoped analysis of both wrappers, both fixtures and the Android entrypoint
  exited 0 with no issues (24252). Workloads were sequential.
- These are host checks, not a native run or a complete feature build. The
  Android entrypoint has not been installed or executed. Its procedure is in
  `S4_NATIVE_VERIFICATION.md`; the requested Thor-testing handoff remains pending.
  Both large native resource results and remaining native integration acceptance
  remain unsatisfied. The earlier unexplained host artwork wait stays open.
- B4 remains the IGDB application's invalid-client boundary. The actual available
  Chrome provider-setup tab is at Twitch's owner sign-in page, verified again;
  no login, application registration, secret reset or credential change was
  performed. Owner sign-in/MFA was requested so legitimate setup can proceed.
  `.env.local` is unchanged. No repeated invalid-pair OAuth request was issued.
- Monitoring remains cancelled. S1 remains BLOCKED at B3/elapsed expiry,
  S2/S3 COMPLETE, S5-S8 NOT STARTED. No rating source was approved, no collection
  migration performed and no release created.

### S4 exact raw-release reconciliation checkpoint (2026-10-03)

- S4 remains the sole ACTIVE stage. Two focused reproductions exposed the actual
  adapter errors: a reviewed game ID bypassed supplied raw-ROM hashes/size, and
  a compatible exact raw match could never resolve a revision-bearing release.
  Both failed before the production change and pass afterwards.
- ScreenScraper's documented ID lookup omits ROM information. Explicit raw
  evidence now uses the hash/size route, validates every supplied digest and
  size, and separately checks agreement with the reviewed game ID. Its match
  evidence remains `rawRomHashAndSize`. ID-only revision requests remain review
  candidates; container checksums, names and a game ID cannot invent raw evidence.
- Normal catalogue snapshot -> actual adapter with synthetic wire responses ->
  persistent worker -> metadata -> offline query evidence rejects wrong CRC,
  MD5, SHA-1, size, game ID, platform, region and language. A corrected response
  and a subsequent fresh re-scrape preserve reviewed IDs and exact edition JSON,
  including revision, region, language and manual raw evidence. Canonical members
  remain selectable; sourced advisory scores do not acquire approved Top ranks.
  Query reads perform no requests. This is host integration, not a new live
  ScreenScraper/raw-ROM lookup or native acceptance claim.
- The affected worker/catalogue/grouping/effective-score/query checks passed in
  workload 64289. Its only failure was a newly expanded fixture's dynamic-map
  `addAll` type error, corrected in the test; the complete provider test file then
  exited 0 (19661). The production implementation was unchanged between these
  runs. Scoped analysis of all changed Dart files found no issues. The sequential
  workload also ran the unchanged bounded 30,000-edition job: 51,281 ms, peak RSS
  240,324,608 bytes, one coalesced lookup and 128-row commit pages. No second test
  workload ran while it was alive; no full-suite result is claimed.
- Reconciliation: META-03's supplied-ID/raw-release precedence and revision
  publication have integrated host evidence. S4 is not COMPLETE: remaining
  classification reconciliation, full reception/source assessment (B4), the
  earlier unexplained artwork wait, and native query/artwork/integration/resource
  acceptance remain required. S1 remains BLOCKED at B3/elapsed renewal; S2/S3
  COMPLETE; S5-S8 NOT STARTED. No required work was deferred or removed.
- No credentials, browser session, Thor, ROM payload, SD migration, release or
  monitoring configuration changed; monitoring remains cancelled.
- Reviewed transaction `4f4e524601c22884d35cc0ca4d1ab236` removed only generated
  unit-test assets and compiled test cache (54,566,445 bytes). Apply is terminal
  with no warnings/errors. Source assets, requested deliverables and the artwork
  stall's private forensic evidence remain preserved; deleted outputs rebuild.

### S4 content-tag reconciliation checkpoint (2026-10-03)

- S4 remains the sole ACTIVE stage. Edition identities, persisted lookup requests,
  candidate review and cached query filters share finite known-tag interpretation:
  case/trim variants, `T-En`, `Dubbed`, `Undubbed` and `Uncensored`. Unfamiliar
  labels remain verbatim. Normalization does not infer translation/language,
  patch features, trusted matches or ranking approval from a filename or age.
- Unknown/unfamiliar and contradictory official classifications are available
  through Unknown. Conflicting `official + Hack` facts remain stored but do not
  claim an unmodified official release or acquire a score/Top position. Any/all
  filters continue to intersect existing ranks without backfill.
- The migration reproduction exposed a second defect: catalogue capture could
  serialize normalized aliases over existing tag facts and invalidate their
  source-bound metadata. Capture now preserves the original stored tag facts;
  explicit review still writes canonical classification and its manual evidence.
  Disabling that preservation reproduced the lost-binding failure.
- Production v31 rebuilds only canonical/query projections in bounded pages.
  Actual v30 upgrade and cold reopen preserve raw game/edition JSON, metadata
  records and ownership keys, refresh jobs/requests, game files and shelf members.
  Existing v25/v26/v27/v28/v29 migration and preservation checks also pass.
- Host integration: canonical and alias reviews both traverse the normal job,
  retry and IGDB adapter wire fixture into persistent metadata and offline any/all
  query results. Original-game scores remain labelled, not project scores. No
  network requests occur during the offline reads. This is actual adapter/SQLite
  fixture evidence, not a live IGDB authorization or Thor claim.
- Verification: affected identity/request/review/query/adapter/ownership/grouping
  and migration checks exited 0 (test workload session 66358, 1m36s); after the
  final official-filter correction, query/migration/IGDB integration checks exited
  0 (66367, 6s). Scoped analysis of every changed Dart file found no issues.
  The bounded 30,000-edition job measured peak RSS 235,028,480 bytes with page
  size 128; standalone grouping measured RSS 146,587,648 -> 208,801,792 bytes.
  Workloads were sequential. No broad suite, credential changes, ROM downloads,
  device testing or release occurred; monitoring remains cancelled.
- Reviewed transaction `7fa0c27323b2f0382953857f240dff29` removed only generated
  test-cache/unit-test assets (57,756,597 bytes); apply is terminal with no warnings
  or errors. Requested deliverables and the earlier artwork diagnostic fixture
  remain preserved.
- Reconciliation: META-04 alias/unknown handling and META-07 offline filter
  interpretation have integrated host evidence; CORE-03 preservation is verified.
  S4 is not COMPLETE: release reconciliation, remaining classification evidence,
  full reception/source assessment (B4), the earlier unexplained artwork wait,
  and native query/artwork/integration/resource acceptance remain required.
  S1 stays BLOCKED at B3/elapsed renewal; S2/S3 COMPLETE; S5-S8 NOT STARTED.

### S4 verified raw/project grouping checkpoint (2026-10-03)

- S4 remains the sole ACTIVE stage. The normal catalogue/refresh worker now
  consumes one explicit typed `rawRomIdentifier` evidence value. It does not read
  or decompress a remote ROM, promote a provider-file/container checksum, or
  select between conflicting assertions. Malformed/ambiguous evidence remains
  unverified discovery, with no fabricated provider identity or rating approval.
- Current, provenance-consistent ScreenScraper `rawRomHashAndSize` metadata can
  join renamed ordinary releases without assigning IDs to their source records.
  Current IGDB `verifiedProjectId` metadata can join modification-project variants
  in a separate namespace, never their original game's namespace. Publication,
  correction and identity changes reindex in the existing SQLite transaction.
  Exact patches/discs/editions remain selectable; an explicitly assigned unscraped
  disc is not lost when its sibling gains a raw match.
- An indexed base dependency revalidates project grouping when the linked original
  changes. Invalid current bindings cannot restore a cleared assertion during
  backfill. Stored facts remain intact for review; grouping is not authority to
  borrow scores, install/remove files or qualify a source for Top membership.
- Focused reproductions also exposed ordinary aliases accepting an unexplained
  translation flag and conflicting edition/game provider IDs. Both failed before
  production changes. Grouping now rejects those assertions consistently with
  score ownership; correcting the exact edition restores its reviewed alias.
- Additive v30 backfills only current assertions. The actual production v29
  upgrade/cold-reopen fixture preserves metadata, exact editions, cached files
  and view membership, groups raw and project variants, and invalidates project
  grouping after base correction. Earlier v27/v28 query, v25 ownership and v26
  freshness upgrade/reopen fixtures passed against the current v30 implementation.
- Fresh normal worker -> actual ScreenScraper/IGDB adapters with synthetic wire
  responses -> metadata -> offline query checks passed. They demonstrate shared
  host integration, not live IGDB authorization or a real modified-project score.
  No source was granted ranking eligibility. The serialized affected grouping,
  query and migration workload exited zero (framework duration 1m13s).
- The populated file-backed 30,000-game query passed after repairing its observer's
  missing raw SQL forwarding. Both `query` and `rawQuery` reads are now measured.
  Identity/metadata reads stayed at 128 rows; filters rewrote no projections and
  ranked SQL used compact query indexes, not metadata/artwork bodies or network.
  First projection build was 219,549 ms; two warm paged/intersection queries took
  1,458 ms. Peak RSS was 239,411,200 bytes. This is bounded host evidence, not a
  native latency claim. The subsequent classification/ID guards do not alter this
  fixture's official, non-translated, non-conflicting identities. Fresh standalone
  grouping of 30,000 games measured RSS 143,749,120 -> 215,322,624 bytes.
- Scoped analysis of all changed production and regression files reported no
  issues. Git whitespace checks passed. Reviewed transactional cleanup
  `9f4bca1480f8a0809d530561ad157e09` applied all exact generated test-assets/cache
  entries, reclaiming 57,803,685 bytes with no warnings/errors. These outputs are
  rebuildable; original assets, private artwork-wait forensic evidence, credentials,
  ROMs and requested APK deliverables were not cleanup targets.
- Reconciliation: CORE-02/META-03/META-04/META-07 raw/project equivalence,
  conflict rejection and exact-edition preservation have focused host evidence;
  CORE-03 has additive production migration evidence. This does not close S4.
  Remaining release/classification reconciliation, META-05 reception remediation
  (external B4), the unexplained earlier artwork wait, and native query/artwork/
  integration/resource acceptance remain required in S4. S1 is still BLOCKED
  at B3/elapsed renewal; S2/S3 COMPLETE; S5-S8 NOT STARTED. No gap is deferred away.
  No Thor, credentials, ROM bodies, SD migration or release changed. Monitoring
  stays canceled; device testing still awaits the owner's response.

### S4 live reception assessment checkpoint (2026-10-03)

- S4 remains the sole ACTIVE stage. The normal persistent worker retrieved and
  cached fresh, explicitly reviewed identities/scores for twenty unique public
  official games across PS1, PS2, GBA and GameCube. Six initial zero-candidate
  searches required separate fixture-alias diagnostics, not automatic production
  matching. The final Wind Waker candidate was explicitly reviewed by offered
  platform/ID. Sequential runs terminated; no overlapping test worker was launched.
- [SCORE_RECEPTION_ASSESSMENT.md](SCORE_RECEPTION_ASSESSMENT.md) records raw scale,
  provider IDs, retrieval times and platform-specific independent reception.
  Every ScreenScraper vote count remains unknown and its aggregate type remains
  unknown. Scores stay sourced advisory values, not an approved Top basis; the
  capture asserts that ranking eligibility is not granted. No production rule,
  private collection, ROM payload, artwork or Thor storage changed.
- This is ordinary-release assessment evidence, not META-05 closure. Required
  newer-console and modified-project coverage, low-vote handling and legitimate
  aggregate-source comparison remain S4 work. B4 still blocks the IGDB OAuth
  boundary; no repeated request with unchanged rejected credentials was made.
- Monitoring remains canceled. Native testing awaits the owner's device-testing
  response; this host assessment did not wake or mutate the Thor.
- Focused `dart analyze test/screenscraper_live_smoke_test.dart` passed with no
  findings after directing sanitized capture evidence to stdout. The preceding
  live runs' assertions/results remain applicable: only their output sink changed.
  Git whitespace checks passed. Reviewed transactional cleanup removed only the
  attributed Flutter test assets/cache (57,102,605 bytes); forensic artwork-wait
  evidence, credentials and requested deliverables remain preserved.

### S3 live round-trip checkpoint (2026-10-02)

- S3 remains the only ACTIVE stage. The normal debug app preserved a selected
  GameCube catalogue, explicit mapping and isolated destination through settings
  navigation and cold restart. No existing SD library path was selected or
  removed. Real verification used one authorized 20,131,764-byte RVZ, not a
  synthetic payload or an emulator-intent acknowledgement.
- Settings Back previously discarded console edits. The real screen/controller
  regression reproduced this; the corrected save preserves source IDs and manual
  mappings as well as the local path. Normal Thor navigation confirmed persistence.
  The global Downloads layer also lacked an Overlay ancestor: a real tooltip
  regression reproduced the failure, and the shared overlay host fixes it without
  moving downloads beneath individual Navigator routes. Normal downloads UI works.
- Both isolated internal and SD downloads committed verified checksums matching
  the Drive provider, confirmed publication and private-stage retirement. The
  installed official Dolphin 2606 (42796) booted the SD artifact. After ordinary
  emulator exit, R-Shop was stopped/restarted with no active network; the cached
  library and fresh exact installed-manifest handoff booted the same SD game.
- Normal explicit removal preview showed only the exact SD-owned ROM and 19.2 MiB.
  Confirmation completed quarantine/deletion, removed its installation/target
  claim, and returned the game to Download while retaining the cloud catalogue.
  A neighboring 78-byte save fixture retained its SHA-256. Explicit reconnect and
  re-download then committed the same provider-verified bytes and retired staging;
  the save fixture remained unchanged. Drive originals were never mutated.
- Actual internal shared-storage removal returned EXDEV; the public ROM remained
  unchanged. A separate native app-UID probe confirmed different internal mount
  IDs and a successful SD quarantine. Known cross-mount removal is rejected before
  intent, with a truthful retained-ROM message. Additive v20 terminates a legacy
  EXDEV intent as retained only after fresh exact public/absent-private evidence;
  the actual Thor recovered that intent while keeping ownership and installation.
  Ambiguous public/private states stay pending conflicts, not false success.
- Native instrumentation passed read-only content grants, fresh object checks,
  committed artifact/digest/ownership/publication checks, pending-removal denial
  and retained-intent reads. Handoff grants an installation-bound URI, never a
  source token or arbitrary filesystem path. Fresh focused host regressions passed
  cross-mount rejection/recovery, save-safe removal, overlay and configuration
  persistence, and exact/coalesced emulator handoff. Only one workload ran at once.
- Verified normal debug APK SHA-256:
  `A59733DA0F6D88D0A0BEF6661B817B24D4A13FFD3F3B5C6AA36B781CDD92AF40`;
  version 1.7.0/12, registered debug signer, package com.darkaxt.rshop.debug.
  No external release or existing-library migration occurred. Both actual Thor
  displays (0 and 4) were confirmed OFF before host verification.
- This closes the single-artifact live round-trip gap, not S3. Publication crash
  boundaries, multi-disc/bundle/playlist installation, safe replacement, exact
  achievements and integrated large-file evidence remain required. S1/S4 B2 and
  outstanding authentication lifecycle criteria are unchanged; no other stage
  was activated and no required item was converted to an unnamed deferral.

### S3 publication process-stop evidence (2026-10-02)

- `integration_test/owned_publication_death_app.dart` exercises the production
  engine/journal/native SD copy route with a small synthetic payload, separate
  SQLite database and exclusive test root. No accounts, source requests, normal
  application database or existing ROMs are used. Event gates sit after actual
  durable/native transitions; no deadline or sleep decides completion.
- Actual Android process stops occurred at observed publication intent, durable
  copy progress, native copy finish before receipt, confirmed publication before
  installed commit, committed installation before private-stage retirement, and
  exclusive destination creation before its identity receipt. Each PID disappeared
  before relaunch; subsequent PIDs reached the next recorded gate.
- The recoverable cases completed with zero media requests on relaunch, exact
  bytes, installed-manifest readiness and retired private staging. Precommit
  states were not exposed as installed. The unrecorded empty destination returned
  a preserved collision with no installation and unchanged verified private bytes;
  it was not automatically adopted or truncated. Neighboring synthetic save
  bytes survived every case.
- Probe-only files, private stages, database and empty root were removed through
  exact fixture cleanup after verification. The normal APK was restored using
  install-replace (not uninstall); its settings/library and owned installations
  were preserved. Both actual displays remained OFF throughout this proof.
- The first probe attempt correctly rejected an incomplete synthetic source
  before publication; its missing parent identity was corrected in the fixture,
  not by relaxing production validation. The corrected probe passed all named
  transitions. S3 remains ACTIVE on its remaining bundle/replacement/achievement
  and integrated large-file requirements; this is not a stage completion claim.

### S3 large-file resource proof (2026-10-02)

- `integration_test/owned_large_transfer_app.dart` ran the production engine,
  SQLite journal and native SD publication/removal on the actual Thor. The
  transport used synthetic streamed bytes, a separate database and an exclusive
  test root; no account, cloud object, normal database or existing ROM was used.
- Sequential 8 MiB and 256 MiB files verified and committed through the copy
  route. Both observed transport/native arrays were at most 65,536 bytes and
  only one native invocation was pending. The measured stage-plus-public copy
  peak was exactly twice each payload: 16 MiB and 512 MiB respectively. This
  excludes unrelated application/database overhead and is not an RSS limit claim.
- Recorded process RSS baseline/peak bytes were 368,758,784/389,070,848 for the
  small case and 383,291,392/396,689,408 for the large case. Buffer measurements,
  not total Flutter/debug-process RSS, establish the bounded transfer contract.
- Exact installation readiness, owned removal and neighboring synthetic save
  preservation passed for each size. All fixture targets/stages/database/root
  were removed after proof; root/database absence was independently checked.
  The inspected analyzer and debug build passed. No overlapping test workload ran.
- The normal APK was restored with install-replace. Its schema remained v20,
  cached games 134, installed artifacts two and removal audit completed/retained.
  Both displays (0 and 4) were confirmed OFF. S3 remains ACTIVE; bundles/playlists,
  valid-target replacement and exact achievements are ordinary unfinished work.

### S3 exact-achievement integration (2026-10-02)

- Achievement matches now use a deterministic exact artifact/content-version key
  for Drive entries; legacy filenames remain unchanged. Favorites/shelves retain
  their stable identity. Library, grid, details and mastered updates use the same
  key, so a namesake or changed version cannot inherit another ROM's match.
- Supported raw formats are hashed through the pinned native read-only descriptor
  in bounded chunks, while verifying the complete installed SHA-256. Archives and
  unsupported hash formats are not optimistically matched. Background/post-download
  lookup rechecks committed installation readiness before saving evidence.
- Focused identity, hash, sync, transfer and detail regressions passed. The actual
  Android probe verified native hashing and SQLite exact/legacy/version isolation,
  then removed its synthetic files/database/root. The first probe exposed a missing
  published-read durable offset; the native fixture was strengthened to reproduce
  that rejection before correcting the production caller. No online achievement
  API response is claimed by this isolated proof.
- The scoped analyzer and normal debug build passed (existing grid/library
  cacheExtent deprecation notices are unchanged). Install-replace restored the
  normal app, schema v20, cached games 134, installations two and completed/retained
  removal audit. APK SHA-256:
  `2CC39BC7026DFCA9EC3529CC4DAB019ECA3A6840CA1CF5B7547B577A40BD4837`.
  Both actual displays are OFF. S3 remains ACTIVE on bundles/playlists and safe
  valid-target replacement; no later stage was activated.

### S3 safe version replacement (2026-10-02)

- A new version of the exact account/source/file reserves a separate managed
  filename, preserving its format extension. The old verified installation is
  retained through transfer, cancellation and publication. A transactional claim
  rejects competing replacements and premature explicit removal. No unmanaged
  target is adopted or overwritten by filename.
- Only after the new installed-state commit and private-stage retirement does
  cleanup freshly hash the new file and quarantine/hash/remove the exact previous
  owner. Failed cleanup preserves the old object and records a bounded warning;
  it does not falsely fail the already committed new download. Offline startup
  recovers durable replacement intents without requiring account access.
- Focused reservation, journal, engine, migration and queue/widget regressions
  passed, including changed old/new bytes, pause, competing ownership and a lost
  quarantine receipt. The scoped analyzer reported no issues.
- The actual Thor probe used production reservation, engine, journal and native
  SD storage with synthetic versions in a separate database/root. Actual process
  stops after confirmed publication, installed commit, and the old quarantine
  rename recovered on relaunch. Final exact owned removal passed; the neighboring
  save stayed unchanged. Its measured publication boundary held 196,647 logical
  payload bytes (three 65,549-byte copies), excluding directory/database overhead.
  This is native recovery evidence, not an online Drive version-update claim.
- Probe root/database absence was independently checked. The normal current APK
  was built and restored using install-replace. Its additive v21 migration retained
  134 cached games, two installations and the completed/retained removal audit;
  no replacement fixture row entered the normal database. APK SHA-256:
  `12F5F396017D0836B64C14BFCF7738ABFECF2D2D1CB04C87461BCF071AA576DE`.
  Both actual displays (0 and 4) are OFF. S3 remains ACTIVE: bundle/playlist
  installation and its integrated readiness/removal proof remain unfinished.
  No later stage, existing-library migration, push or external release occurred.

### S3 bundle and stage acceptance closure (2026-10-02)

- Selected M3U/CUE dependencies now use the normal persistent queue, rooted
  catalogue, production journal and native storage. Exact relative layout/header
  bytes are preserved; bounded cancellable planning does not read discs during
  indexing. Missing/ambiguous/unsafe/unsupported dependencies are rejected, not
  adopted by namesake. Completed members are not independent ready games.
- The actual Thor probe used synthetic playlist/CUE/disc/track bytes, a separate
  database and exclusive SD root. After the observed first-disc commit, an actual
  force-stop/relaunch restored the ordinary queue and downloaded only track/CUE/
  playlist. Root completion included exact children and retired private stages.
  Renaming a required disc made readiness fail until that exact object returned.
  The share ZIP contained precisely four ROM members, excluding a neighboring save.
- This real device test caught an overlong child-removal identifier hidden by
  earlier short-ID fixtures. The deterministic tuple SHA-256 identifier fixes the
  native staging limit without relaxing it. Full-length-ID regressions pass.
  Recovery resumed the already-quarantined root; after the actual track quarantine
  before its receipt, a second force-stop/relaunch finished exact removal offline.
  The neighboring save's SHA-256 stayed unchanged. Root/database absence was
  independently checked; no normal library/cloud file was part of the probe.
- Bundle-version replacement retains old bytes until the new graph commits.
  A completed new graph is selected even if old-byte retirement is blocked; root
  version equality cannot select an outdated dependency graph by path ordering.
  Focused regressions cover this retained-owner case and interrupted child removal.
- Actual Android instrumentation passed root reads and rejection of independent
  member grants, missing/changed members, pending child removal, changed ownership,
  unretired copy stages and graph mismatch. Its separate synthetic DB/files were
  cleaned, and no synthetic row remains in the normal DB. Existing read-only,
  publication/digest/owner/removal gates also passed. Synthetic bundle bytes are
  not proof of a multi-disc emulator boot; the real RVZ/Dolphin round trip above is
  the separate actual emulator acceptance evidence.
- Fresh affected planner/engine/runtime/journal/catalogue/provider/queue/local
  discovery/migration and details/download-overlay/exact-achievement regressions
  passed. The scoped analyzer and normal debug build passed. Install-replace
  restored the normal APK; additive v22 retained 134 cached games, two installs,
  completed/retained removal audit, no replacement or bundle fixture rows.
  Both existing 78-byte save fixtures retain SHA-256
  `91c1a8f28fe1d02d710efaf4f5b7001efab3ba585f5ef59b6d406b1a00ac929b`.
  Normal APK SHA-256:
  `31F0CDA4B3B2C6A86F7C1024E4AD5EF7DF81D08812055FF8B97ECF46E5A29680`.
  Test instrumentation package was removed; normal app data/signature/package
  were preserved. Both actual displays (0 and 4) were confirmed OFF.
- Reconciled DRIVE-04: validated 200/206/416, range/size/version/checksum and crash
  regressions plus measured native bounded large-file streaming/copy space.
  DRIVE-05: cancellation and process-stop publication recovery, no-clobber
  collision preservation, replacement and postcommit cleanup boundaries verified.
  DRIVE-06: actual online/offline Dolphin round trip and save-safe removal/reinstall,
  exact ownership/redirected/replaced-file conflicts and bundle consistency verified.
  No unmet S3 criterion or S3 deferral remains. S3 is COMPLETE, not the entire fork.
  S1's auth lifecycle/B2, S4-S8 and S5's named source-action UX work remain required.

### User-requested pause (historical checkpoint, 2026-10-02)

- Execution paused at the user's explicit request. S3 retains ACTIVE as its
  stage status but receives no work while paused; no other stage was activated.
- Uncommitted S3 changes add the first standalone GameCube/Wii Dolphin handoff
  and an installation-bound, read-only Android content provider. Focused Dart
  handoff/removal regressions passed; the Android build succeeded. This is not
  proof that a game launched or that the live round trip is complete.
- Real Android instrumentation first reproduced acceptance of an unconfirmed
  publication. After matching the native read boundary to the committed
  InstallationIndex contract, the same device test passed valid descriptor reads,
  write denial, artifact/digest/ownership/publication/removal checks and rejection
  of changed native files. Test-owned rows/files were cleaned in its finally block.
  Normal debug APK SHA-256:
  `9C3D3726CF4022D64EFA26A60320C4201909EF5291E9B71386C28E8B0288DDA5`,
  version 1.7.0/12, registered debug signer, package com.darkaxt.rshop.debug.
- Native Drive sign-in succeeded again. A separate GameCube source was added
  through the normal observed-folder picker; the Game Gear source was retained.
  Both catalogue refreshes were still unpublished at the last inspected snapshot.
  No GameCube mapping, real ROM payload, emulator launch, or local removal was
  performed during this handoff checkpoint. Existing SD ROMs/saves were untouched.
- The task's debug app was force-stopped on pause, preserving durable refresh
  checkpoints. Both Thor displays were independently confirmed OFF. No host build
  or test workload was running. No completion commit or external release was made.
- Resume S3 with the native/Dart handoff diff review, reconnect the existing owner
  account, finish the pending catalogue publication and explicit mappings, then
  prove real Drive download/verify/Dolphin/offline/remove/re-download. Remaining
  publication crash cases, bundles/replacement, exact achievements and integrated
  large-file evidence still prevent S3 closure. Expendable generated build/test
  artifacts remain registered for transactional cleanup; preserve the normal APK.

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
| S1 | BLOCKED | Additive v14/v15 migrations, native adapters and secure credentials; OAuth clients registered; actual native consent/root/folder requests, chooser cancellation/reconnect, microG token-clear plus silent authorization, remote revocation HTTP401 and scope decline/reconnect verified; processed release manifest preserves R-Shop branding/fork package; actual standalone ScreenScraper adapter live lookup, metadata/media/score parsing verified | External B3: owner must identify a second Google test account for DRIVE-01's real two-account isolation check; only the default account is selected so far. Elapsed-expiry renewal also remains required. Neither is waived by B2 closure |
| S2 | COMPLETE | Focused rooted/paging/failure/identity/mixed-queue contracts pass; real selected Game Gear subtree published after resumed traversal; normal mapping/library shows 182 exact archive entries, retained through cold restart with Wi-Fi disabled and controller browsing | No unmet S2 criteria. Named final source-action touch/layout/localization work belongs to UI-02/S5; verified payload/offline emulator/removal belongs to S3 |
| S3 | COMPLETE | Real Drive/SD/Dolphin/offline/remove/reinstall; native publication and replacement process-stop recovery; bounded large-file streams/measured copy space; exact achievement identity/hash; normal queue bundle resume/readiness/share/removal/save proof and native member grant gates; additive v22 preservation | No unmet S3 criteria. S5 owns the separately named final source-action UX work; it does not replace S3 acceptance |
| S4 | BLOCKED | Cached-catalogue snapshots/review/selective retry and byte-bound publication; shared metadata/artwork budget and explicit recovery; actual ScreenScraper metadata/cover/screenshot host workflow reaching offline collection queries; reviewed provider/raw/project canonical grouping and rank-before-filter query; exact raw-release validation across reviewed IDs and revisions; independent classification/review/unknown reconciliation; bounded edition and shared effective-score selection; additive v31 projection and disk-reopen preservation; populated 30,000-game indexed query; full 30,000-game native Thor query/artwork resource workflow with offline reopen and unchanged normal data; native production-adapter/job/identity/query ownership fixtures; interrupted-job recovery | External B4 prevents META-05/META-07 live aggregate-source/reception approval; resolve legitimate matching credentials and assess the real representative sample. Earlier host artwork wait remains unexplained. S5 Top acceptance and S7 retention cannot complete before source approval; synthetic native transport proof is not real API or UI acceptance |
| S5 | NOT STARTED | None | UI-01, UI-02, UI-03 |
| S6 | NOT STARTED | None | QA-01, QA-02, QA-04 and complete integrated reconciliation |
| S7 | NOT STARTED | User retention choice recorded in revision 2 | MIGRATE-01: full fresh metadata pass, live recovery, reviewed cloud-verified removals, retained-set and space audit |
| S8 | NOT STARTED | User companion-launch choice recorded in revision 3 | COMPANION-01: per-ROM association, actual top/bottom display launching, failure paths and ordinary-launch/save-safety verification |

B1 (offline Thor) was resolved on 2026-10-02: the online native flow granted
read-only authorization and returned the real Drive root/folder response. This
does not satisfy the remaining DRIVE-01 auth lifecycle acceptance. B2 blocked META-02's
authenticated lookup and S4's live matching/reception evidence; legitimate fork
application credentials and a successful live lookup resolved it on 2026-10-03. Neither substitutes for the
ordinary unfinished implementation listed above. No required work is dropped or
reclassified as a deferral. S1 is now parked at B3; S4 is the sole ACTIVE stage.
S3's explicit dependencies were S2 exact artefacts/queue
and S1 migrated state, not ScreenScraper lookup. The remaining S1 auth lifecycle
criteria remain required and prevent final feature completion.

### S4 provider grouping and artwork resource checkpoint (2026-10-03)

- IGDB-only region/disc variants previously kept different canonical game keys;
  independently reviewed ScreenScraper and IGDB assignments could not join them.
  Both focused reproductions failed before changing production grouping. Additive
  v29 now projects these implemented, reviewed IDs as aliases on eligible ordinary
  or known translation/audio/restoration editions. Multiple assigned IDs provide
  the bridge; ambiguous/candidate IDs, wrong platforms, unknown classification
  and a hack's base-game IDs do not. Exact editions and score bindings survive.
- Corrections capture the old component before replacing aliases, then reindex
  split components and newly joined neighbours in the same SQLite identity
  transaction. The ordinary cached collection query verifies joined/split counts,
  score ownership and Top-before-shelf filtering without lower-rank backfill.
  Real v28-without-alias-table upgrade/reopen preserves scores and view membership;
  earlier production migration fixtures preserve their source/queue/metadata data.
- The first graph backfill exposed a planner-dependent full claim-table scan for
  each component. Actual SQLite EXPLAIN showed `SCAN claim`; making the affected
  component drive the lookup showed the covering claim index instead. After that
  join-order correction, the fresh 30,000-game grouping fixture completed in about
  65 seconds, measured RSS 144,826,368 -> 218,533,888 bytes. This is host evidence,
  not an Android latency promise or a lifecycle deadline.
- Fresh serialized focused grouping, query, v27/v28 and earlier-version migration,
  metadata ownership/freshness migration and database-service checks exited zero
  (framework duration 1m25s). No full-suite run was performed. The separate
  integration assertion initially assumed missing ratings were omitted; it was
  corrected to assert the reader's nullable entries, not to weaken ownership.
  Scoped analysis of the changed production and regression files reported no
  issues (68.2 seconds). Git whitespace checks passed.
- `metadata_artwork_resource_test.dart` exercises 30,000 distinct game identities,
  current metadata selectors, the normal artwork job/cache and disk close/reopen.
  A real 4,002,288-byte PNG is decoded; writes are awaited in at most 65,536-byte
  chunks, with one active request. Content-addressed publication retained two
  image bodies and all 30,000 selectors; completed/offline reads contacted no
  provider. The debugger-assisted full run exited zero, capture 80,370 ms,
  total 701,373 ms, measured peak RSS 236,986,368 bytes. VM inspection/GC occurred;
  this does not establish native timing or resolve the earlier host wait.
- The preceding artwork fixture stopped advancing at 9,026 committed items.
  Resource observations did not show memory exhaustion. Read-only native/VM
  diagnostics did not establish its cause; only its validated tester was
  intentionally stopped before another workload began. Its exact DB/journal
  snapshot remains private diagnostic evidence. Normal interrupted-job recovery
  then completed that actual fixture: only the 20,974 pending items were requested,
  with no repeated committed selector. The in-flight uncommitted attempt explains
  requested=30,001; measured recovery peak RSS was 237,490,176 bytes, exit zero.
  Passing recovery/subsequent execution is not a claim that the wait was fixed.
- The artwork proof is applicable to the unchanged worker/cache and direct-row
  fixture; the new canonical indexing is not called by that resource workflow.
  Reviewed cleanup removed the disposable one-off recovery/query-plan helper
  (4,123 bytes) and regenerated test assets/compiled cache (75,459,381 bytes),
  with no warnings/errors. The interrupted snapshot and recovered comparison
  database/cache remain private evidence for the unresolved wait; they are not
  published or treated as expendable while diagnosis remains open.
  Raw-ROM-only equivalence and verified modification-project provider grouping
  remain ordinary S4 work, not silently covered by the implemented aliases.
  Live reception assessment/B4 and native integration remain required. S4 stays
  ACTIVE; S1 BLOCKED at B3/elapsed renewal, S2/S3 COMPLETE, S5-S8 NOT STARTED.
  No Thor, credential, ROM, SD migration or release changes occurred. Monitoring
  remains cancelled.

### S4 reviewed original-game modification checkpoint (2026-10-03)

- META-04's labelled original-game score existed in the selector, but the normal
  IGDB adapter rejected every reviewed translation/audio/restoration edition.
  An explicit base relation also failed the selector's blanket same-ID guard and
  the worker's blanket base-ID response rejection. Separate reproductions failed
  at those exact boundaries before the corresponding rules were corrected.
- Reviewed independent/combinable `T-Eng`, `Dub`, `Undub`, `Uncensor` tags may now
  retrieve a verified global original's facts. The shared selector returns
  `originalGame` ownership, not a rating of patch quality. An explicit base must
  be verified, same-platform and assigned the same original ID. Unknown,
  contradictory, revision-uncertain and project/base-score substitutions remain
  rejected. No title lookup automatically publishes a score or grants ranking.
- The normal persistent catalogue -> review -> retry -> IGDB adapter -> metadata
  publication -> offline query workflow passes with combined tags and an explicit
  base relation. Changing the base invalidates query ownership without deleting
  evidence; a new requested generation marks retained facts stale. A deterministic
  transport-boundary mutation of the base during retrieval returns
  `invalidResponse` and preserves the previous metadata generation. Publication
  revalidates that base within its SQLite transaction, including coalesced targets.
- Verification used synthetic IGDB wire responses and actual production worker,
  SQLite persistence, selector and query. It is host integration proof, not live
  IGDB access. The affected adapter/selector/store/query/refresh/catalogue/retry
  regression workload exited zero (44 seconds); scoped analysis of the three
  changed production files and two tests reported no issues (2.4 seconds).
  The included worker's bounded 30,000-edition fixture took 36,719 ms, with peak
  measured RSS 235,466,752 bytes, one coalesced lookup and 128-row commit pages.
  That fixture is not full artwork/native resource acceptance. Only one test
  workload ran at a time; no full-suite run was performed.
- Cleanup `1da35904a720e2b29dfe6126cec4313b` reviewed all 454 exact generated
  entries under `build/unit_test_assets` and `build/test_cache`; the applied ticket
  removed 57,350,029 bytes with no warnings/errors. Compilation outputs are
  rebuildable; source assets, private credentials, ROMs and APK deliverables were
  outside the cleanup roots.
- S4 remains ACTIVE: live reception assessment/B4, remaining provider/raw/release
  and classification reconciliation, full artwork/resource assessment and native
  integration remain required. S1 remains BLOCKED at B3/elapsed renewal;
  S2/S3 COMPLETE; S5-S8 NOT STARTED. No required gap was deferred away. No browser,
  credential, Thor, ROM body, SD migration or release changed. Monitoring stays off.

### S4 indexed collection-query checkpoint (2026-10-03)

- `LibraryQuery.page` establishes membership from actual committed cache rows,
  including newly indexed but unscraped files. Retained metadata-only/provider
  search identities cannot enter the collection. Mutation triggers retain dirty
  cache/identity/metadata/refresh state across restart; 128-row reconciliation
  uses the shared effective-score selector and exact catalogue/owner bindings.
  Filter-only changes read compact indexed fields, not full-library metadata or
  artwork bodies, and do not rebuild the projection or initiate provider work.
- Canonical groups receive stable score/identity ranks within the explicit system
  scope before any tag, genre, region/language, search or view intersection.
  No lower-ranked translation, hack or favorite refills a filtered Top. Any/all
  tags, overlapping modification tags, unknown classification and sparse coverage
  use the same query. One sourced effective score serves exact-edition display
  and ranking; conflicting accepted scores within a group leave it unresolved.
  Unrated editions do not inherit a rated region's rank. Manual shelves preserve
  their first matching edition and order unless rating order is explicitly chosen.
- View-membership projections preserve exact edition identities and order but do
  not replace existing favorite, shelf or installation owners. S5 must wire their
  current authoritative state and the shared query into the existing UI. No UI,
  cloud/device Top profile or installation/removal behavior was changed here.
- Reproductions failed for omitted unscraped members, invented edition ranks and
  manual-edition selection before their source rules were corrected. A further
  failing reproduction showed ambiguous raw-match metadata supplying a genre;
  the shared ownership boundary now rejects that metadata while preserving the
  ordinary collection item. Focused
  current-collection, scope/tie, any/all, source ownership, add/remove, successful
  score publication, pending refresh, conflict, page and cold-reopen checks pass.
  Production v27->v28 adds only rebuildable tables/indexes/triggers; its file-backed
  fixture preserves metadata and cached files, persists views and handles a cache
  removal recorded before restart. Earlier v13-v26 migrations also passed against
  v28. No existing score was promoted or retrieval date refreshed on upgrade.
- The normal real ScreenScraper catalogue -> review -> retry -> metadata plus
  cover/screenshot workflow now reaches this query with the provider closed.
  It returns exactly the real sourced score in ordinary browsing, no invented
  rank/Top without META-05, and a stale retained score after the explicit newer
  refresh. That focused host test exited zero (21 seconds). This is one title,
  not the required 20-game/four-console reception assessment or Thor proof.
- The file-backed 30,000-game fixture constructs the projection through normal
  catalogue capture and score ownership, with a synthetic test-only assessment.
  The inspected final run built it in 85,486 ms; two subsequent paged/intersection
  queries took 1,171 ms together, versus 3,108 ms before eliminating repeated
  rank-CTE evaluation. Peak process RSS was 241,586,176 bytes (about 230.4 MiB);
  identity and metadata reads stayed at 128 rows. Actual EXPLAIN output uses query
  indexes, and the rank SQL reads no full metadata/artwork. Filter changes produced
  no projection rewrites. This is host evidence, not native latency or full
  artwork-job resource acceptance. Only one test workload ran at a time.
- The final affected query/selector/store/migration checks and scoped analysis
  exited zero; the analyzer reported no issues. Changes after the live/resource
  runs were confined to the ambiguous/mismatched ownership rejection; their
  manually matched, exact-bound fixtures remain applicable, without repeating
  those unchanged workloads merely for a checkpoint.
- Transactional cleanup `2892f18b471b75aa34fe2e16ecd8c15a` reviewed only the
  attributed `build/unit_test_assets` and `build/test_cache` outputs. The ticket
  applied successfully: 454 generated entries, 57,447,901 bytes removed, no errors
  or warnings. Original assets/source, credentials and requested deliverables
  were outside its roots; removed compilation outputs are rebuildable.
- S4 remains the sole ACTIVE stage. META-05 assessment/B4, remaining identifier,
  release and classification reconciliation, the full artwork/resource assessment
  and native integration/capability/performance verification remain required.
  Native SQLite window-query behavior has not been tested here. S1 remains BLOCKED
  at B3/elapsed renewal; S2/S3 COMPLETE; S5-S8 NOT STARTED. Monitoring stays cancelled.
  No credentials, browser session, Thor, ROM bodies, SD migration or release changed.

### S4 shared effective-score checkpoint (2026-10-03)

- A single sourced-overall selector now preserves raw scale, attribution, count
  and ownership for shared cache consumers. Assessed source precedence, when
  eventually backed by the required live reception evidence, selects the same
  score for display and ranking. It never selects the highest provider score or
  averages critic/community components. Production accepts no ranking basis yet;
  explicit synthetic policies in tests are not a live assessment or a user option.
- Unassessed ordinary display has fixed candidate precedence, preferring current
  records over legacy generations. Imported approval flags, low sample counts,
  unknown counts without a separately recorded confidence assessment, mismatched
  basis scale/platform and stale generations cannot establish ranked membership.
  Scores remain sourced facts, not declarations that unrated games are inferior.
- Verified project ownership is distinct from explicitly labelled original-game
  scores on known combined translation/audio/restoration tags. Unknown/candidate
  identities, contradictory classification, conflicting edition/game/provider
  assignments and a hack's base ID cannot supply an overlay. Compatible verified
  raw-ROM metadata can supply an ordinary official-game score without requiring
  an unnecessary manual provider-ID correction.
- `LibraryStore.effectiveRatings` supplies an immutable page of at most 128
  requested editions in a SQLite transaction. It validates current owning-provider
  bindings and live catalogue bytes/removal; pure renames remain usable. Patch,
  provider-ID and content changes do not reuse obsolete scores, and independent
  provider records survive another provider's correction. Cache facts are retained,
  not deleted. This page reader is not the indexed collection/Top/filter query.
- A newer requested refresh for the same current edition/provider binding marks
  the retained score stale, including pending and blocked jobs after a service
  restart. It cannot remain ranking-eligible merely because its historical
  generation is positive. A current successful publication restores eligibility
  only under the separate accepted-basis gate. Artwork and unrelated owners do
  not supersede game-score generations; no age timer or automatic request runs.
  The reproduction failed before correction and now passes. Production v26->v27
  upgrade/reopen preserves metadata, dates, work-item progress and paused recovery;
  SQLite EXPLAIN confirms use of the new exact-edition/job index. Earlier v13-v25
  upgrade/reopen checks also pass against v27.
- The new behavior was checked first against failing selection cases, then real
  SQLite current-cache/correction/rename/removal fixtures. The focused selector,
  store and existing provenance/identity checks passed. Additional reproductions
  exposed stale-primary preference, conflicting edition-ID override and
  contradictory official/Hack classification; those now pass after fixing the
  actual selection rules. No full-suite run or broad resource proof is claimed.
- Real host proof used the normal ScreenScraper catalogue -> candidate review ->
  retry -> metadata/cover/screenshot pipeline. After closing its connection, the
  shared score reader returned exactly the fetched raw/provenance score, marked
  current but unranked. Its explicit next-generation request retains that exact
  score as stale, without a new network read. The final focused live test exited
  zero (7 seconds); this is
  one live title, not the required 20-game/four-console reception assessment.
  Final scoped analysis of the affected production/test files exited zero with
  no issues after the v27 generation check; the verified implementation remained
  unchanged afterwards.
- Transactional cleanup `d09a3bac1eef595ee5240f29cbdb213b` removed only reviewed,
  task-generated Flutter test assets/compiled cache (57,013,805 bytes); applied
  with no warnings or errors. Source assets, requested APKs, credentials and ROMs
  remain intact.
- S4 remains the sole ACTIVE stage. Indexed current-collection ranking/filter
  queries, remaining provider/raw/release reconciliation and classification,
  live reception assessment/B4, full large-fixture artwork/resource assessment
  and native integration remain required. S1 stays BLOCKED at B3 and elapsed
  renewal evidence; S2/S3 are COMPLETE; S5-S8 remain NOT STARTED. Monitoring stays
  cancelled. No Thor, credentials, ROMs, SD retention policy or release changed.

### S4 independent metadata ownership checkpoint (2026-10-03)

- Reproduced META-03/META-06 integration defect: reviewing a second provider ID
  invalidated the first provider's current metadata because every cache/job key
  included all providers' identities. Source-scoped bindings now retain the owning
  provider's assigned IDs/manual assertions and all shared game/edition evidence.
  They omit only unrelated provider-ID assertions, not platform, artifact bytes,
  raw-ROM checksums, release, region/language, revision, patch, classification,
  base relationship or malformed evidence. Canonical grouping retains its full
  projection. This is not cross-provider equivalence or score-reliability approval.
- The failing reproduction now passes. Normal cached-catalogue -> IGDB review ->
  sourced score -> offline SQLite consumption preserves previously verified
  ScreenScraper metadata. Pending image work and offline cached images likewise
  survive an independent provider review; a different patch still cannot consume
  them. Both proofs use the normal worker/store, not a separate test-only path.
- Production v26 upgrade/reopen proof covers current and stale v25 metadata,
  pending lookup/image snapshots across more than one 128-row page, unchanged
  requests/selectors/generations/retrieval dates and preserved provider budget.
  Only still-current complete old bindings convert; stale records remain stored
  and unusable. A second reopen cannot promote or migrate those records again.
  Existing v13-v24 upgrade/restart checks also passed against v26.
- Fresh real ScreenScraper host metadata/review/cover/screenshot/offline workflow
  passed after the binding change. It makes no ROM requests and does not enable
  consensus-ranked Top results. This is host proof, not Thor acceptance.
- Focused store, IGDB, artwork, migration, snapshot, catalogue, retry, budget and
  grouping checks passed. The combined worker command had a missing test filename
  after its selected worker tests passed; the correct `library_grouping_test.dart`
  was then run separately and exited zero. No full-suite result is claimed.
  The 30,000-edition worker check reported 59,594 ms, one request, 128-row pages
  and observed RSS endpoints 146,415,616 -> 223,129,600 bytes. Grouping reported
  endpoints 141,381,632 -> 189,042,688 bytes. Neither is ranked-query/artwork-wide
  resource proof. Focused analysis of changed production and test files exited
  zero with no issues after correcting one brace-style finding.
- Transactional cleanup 3d1b453cdbb92a9817baa12143e9617c removed only reviewed,
  regenerated Flutter test assets/compiled cache (56,975,037 bytes); applied with
  no errors. Requested APKs, source assets, credentials and ROMs remain intact.
- S4 remains ACTIVE. Shared indexed ranking/filter queries, live reception
  assessment (B4 still unresolved), remaining provider/raw/release reconciliation,
  complete classification, full large artwork assessment and native verification
  remain required. No S5 work, Thor mutation, credential change, ROM transfer,
  SD cleanup, release or monitoring recreation occurred.

### S4 aggregate-source checkpoint (2026-10-03)

- META-05: IGDB's documented externally defined overall score is retained without
  recomputing an average; critic/community scores and their independent counts
  are separately attributed. Missing totals/counts stay missing. Low-vote extreme
  scores and imported approval cannot establish consensus. This adapter is a
  candidate remediation source, not completion of the required reception gate.
- META-03/META-06: the existing worker, persistent catalogue snapshot, explicit
  candidate review and SQLite metadata publication accept the standalone IGDB
  adapter without a separate catalogue/provider-choice workflow. Synthetic wire
  plus real SQLite proof covers authentication blockage -> same pending job
  resume -> explicit review -> score publication -> provider close -> offline
  consumption. Completed jobs do not repeat HTTP. Unsupported systems, wrong
  platforms, base IDs on hacks and oversized responses cannot publish scores.
- The opt-in real host workflow did NOT pass: Twitch's token endpoint returned
  HTTP 403 with an invalid-client response before any `api.igdb.com` request.
  The pair was read from `.env.local`, no environment override was present, and
  the form-body protocol was checked against Twitch's official documentation.
  Diagnostic capture retains only fixed endpoint/status/error classifications;
  no secrets, raw errors or tokens are printed. No challenge bypass or substitute
  credentials were used. B4 is this external application-authentication gap.
  Resolution: supply a valid matching Twitch application client-ID/secret pair,
  rerun the real integrated lookup, then perform the reception comparison. The
  requested credential check remains unanswered. B4 prevents claiming live IGDB
  integration or an IGDB-backed META-05 assessment; it does not prevent the
  remaining offline S4 query/identity work, so S4 remains ACTIVE.
- Focused IGDB, platform matcher, metadata worker/catalogue and score regressions
  passed as one workload. The existing 30,000-edition snapshot check reported
  62,133 ms, one coalesced request, 128-row pages and observed RSS endpoints
  147,337,216 -> 223,436,800 bytes. That checks the existing worker, not the still
  missing ranked query or large artwork assessment. The added normal-job IGDB
  integration fixture passed separately. Changed-code analysis reports no issues.
  Live failure is recorded, not counted as passed acceptance.
- The final typed-overall-score and persistence checks passed, followed by clean
  changed-code analysis. Cleanup 080cc70d33baea2fbdbf78df65c8349b removed only
  regenerated unit-test assets/compiled cache (57,229,613 bytes, applied with no
  errors); prior requested APKs and source assets remain intact.
- No Thor testing, UI-stage work, ROM transfer, SD cleanup, credential change or
  release occurred. S4 still requires complete score reception assessment, shared
  indexed ranking/filter queries, provider/raw/release reconciliation,
  classification, full large-fixture artwork assessment and native verification.

### S4 artwork cache checkpoint (2026-10-03)

- META-01/META-03/META-06: explicit image jobs snapshot current edition-owned
  media and metadata generations. They use the same exclusive worker, persisted
  cadence and remaining daily request balance as metadata lookups. Completed
  duplicate selectors coalesce within a job; a new explicit refresh requests
  current bodies again. Cancellation and disk reopen preserve pending work;
  obsolete identities/generations cannot publish a current cache binding.
- Bounded private staging, PNG CRC/dimension/frame validation and Flutter's
  native decoder precede immutable content-addressed publication. A failed
  refresh cannot replace an older usable image. Pointer/outcome commits process
  at most 128 editions per page. Offline reads validate current metadata ownership
  and make no network/ROM requests. Credentials and authenticated URLs are absent
  from stored selectors and filenames.
- Real cached-catalogue -> ScreenScraper review -> metadata -> cover plus
  screenshot -> close provider -> offline cache reads passed in the opt-in host
  live smoke test. The API returned HTTP 200 PNG bodies with one literal ASCII
  `1` after the complete IEND; only that exact endpoint framing is normalized.
  Arbitrary appended data remains invalid, as do CRC-valid undecodable images.
  No score became consensus-validated through this artwork proof.
- Focused provider/artwork-job/quota/catalogue/retry/migration checks passed, as
  did a separate disk-close/reopen artwork checkpoint. The v25 production upgrade
  preserves v13-v24 identities, existing records, pending work and provider budget.
  Changed-code analysis reports no issues. Repository-wide analysis still reports
  four pre-existing unrelated findings; it is not claimed clean. Verification used
  one workload at a time, not another full-suite run.
- Evidence commands: `flutter test test/screenscraper_live_smoke_test.dart
  --plain-name "cached catalogue to live review, retry and offline metadata cache"
  --no-pub --concurrency=1 --reporter expanded`; focused tests in
  `screenscraper_artwork_test`, `metadata_artwork_jobs_test`,
  `metadata_rate_limit_test`, `library_migration_test`,
  `metadata_catalogue_jobs_test`, `metadata_retry_jobs_test` and
  `screenscraper_provider_test`; focused `flutter analyze --no-pub` for changed
  metadata/database/test files. All inspected terminal results exited zero.
- Transactional cleanup ad0f32b20061d8c449b72ce8e7e507f5 removed only reviewed,
  reproducible host-test assets/cache: 56,984,021 bytes; state applied, no errors.
  Existing APKs, credentials, ROMs and Thor state were untouched. S4 remains
  ACTIVE: this checkpoint does not close reception/ranking, complete native
  integration or the full large-fixture artwork assessment.

### S4 canonical grouping checkpoint (2026-10-03)

- META-03/META-07: reviewed same-platform ScreenScraper identities group regional
  and known translated/audio/restored editions once without merging exact edition,
  patch or artifact records. Explicit multi-disc/project identities remain intact.
  Candidate IDs, matching names, wrong platforms, unknown classification and
  unrelated hacks carrying a base ID cannot merge. Grouping alone publishes no
  rating and cannot establish translation/patch quality or consensus support.
- Identity writes, review acceptance and catalogue recapture update the indexed
  projection atomically. Host catalogue -> review -> group -> re-scrape proof
  verifies conversion candidates only after independent explicit identity review;
  changed bytes invalidate the old binding and return to unmatched grouping.
  This is not automatic matching by CHD/ZIP container hashes. Remaining raw/release
  and additional-provider reconciliation is still S4 work.
- Bounded canonicalEditions selects at most 128 examined rows, uses stable keyset
  cursors including omitted stale rows, validates current identity/live catalogue
  content, and fetches no metadata/artwork bodies. EXPLAIN confirms the group
  index. This exact-edition selector is not the still-required ranked library query.
- Additive v24 backfills existing editions in 128-row pages; file-backed v13-v23
  production upgrade/reopen fixtures preserve cache rows, anonymous legacy scores,
  identities, pending work and provider quota state. Focused grouping/store and
  catalogue/retry regressions pass. A 30,000-game projection/query fixture passes;
  observed worker RSS was 137,609,216 bytes before and 192,233,472 bytes after.
  These are observed endpoints, not a peak-memory claim or a full ranking proof.
- No Thor wake/install/test, ROM transfer, SD cleanup, account modification or
  release occurred. The unanswered native-test request remains the device boundary.
  S4 remains the sole ACTIVE stage; no remaining criterion has been deferred away.

### S4 selective retry and provider budget checkpoint (2026-10-03)

- META-01's explicit failed/unmatched retry captures only selected unresolved
  members in a new generation; successful members and the old report remain
  unchanged. Exact current bytes and manual corrections are recaptured. Removed
  members receive an explicit identityChanged outcome, not silent omission. Review
  decisions remain separate from failure retry; blocked pending work resumes its
  existing job rather than creating an automatic retry loop.
- META-06's worker persists provider-reported per-minute cadence and reserves the
  next protocol slot before requests. One worker keeps its database claim while
  waiting; cancellation stops/joins the protocol timer with one cancellation
  listener per run. Identity is checked again after a wait. New jobs, runner
  objects, missing later quota fields and DB reopen do not erase the budget.
- Daily/unmatched exhaustion and HTTP quota rejection apply provider-wide, even
  when the job that discovered the limit completed its final item. Normal runs
  cannot bypass them. Explicit run(recheckAccess: true) performs one documented
  ssuserInfos.php access check, subject to known cadence/Retry-After, and resumes
  pending game lookups only after complete daily counters establish recovery.
  No guessed midnight, background polling, arbitrary delay or cache purge is used.
  Zero minute/thread allowances block further game requests. Limits are currently
  conservative per provider for the app's single selected metadata account.
- Shared sanitized, bounded API decoding covers lookup and account status. The
  status endpoint's maxrequestspermin spelling and game endpoints'
  maxrequestsperdmin spelling are both recognized; incomplete/wrong-account
  responses cannot establish recovery. No game request, metadata publication or
  raw account response is hidden inside the explicit status check.
- Additive v23 creates only the provider budget table. The real v22 upgrade and
  file-backed close/reopen preserve catalogue, anonymous legacy ratings, identities,
  saved pending work and persisted quota state. Focused retry/rate/catalogue/
  provider regressions passed, including cancellation, exclusive worker ownership,
  daily bypass reproduction and explicit recovery. Scoped analysis found no
  issues; final whitespace/diff review passed before the checkpoint commit.
- Actual current API access, quota parsing and catalogue -> local review ->
  verified lookup -> persisted descriptions/artwork references/20-point score
  succeeded on the host with the legitimate ignored credentials. Consumption is
  network-free; the score remains consensus-unassessed. This is not artwork-body
  caching, native metadata UI, broad reception validation or S4 completion.
- The Thor reappeared in adb as bfa98654 during host verification. No device
  installation, wake or mutation occurred. Native testing remains required and
  follows the owner's instruction to ask at that boundary and switch screens off
  after use. The approval-monitor automation remains deleted.

### S4 cached catalogue and live review checkpoint (2026-10-03)

- Full, per-console and individual refresh entry points now derive membership
  from the normal committed `games` cache, not legacy ratings or installation
  residency. Identity capture and immutable job publication share one SQLite
  transaction; input is consumed in 128-row keyset pages. Folder records are
  excluded. Unreviewed files are not merged by cleaned names or assumed official.
- Exact account/source/object identity retains the edition and reviewed provider
  ID across equal-byte renames and cache reinsertion. A changed provider content
  digest invalidates the old verified match without deleting correction evidence.
  Container checksums never become raw-ROM identifiers. Legacy cache-row identity
  remains deliberately conservative; explicit conversion/group reconciliation is
  still required, not claimed by these checks.
- Paged local review offers only the recorded platform-bound candidates. Explicit
  candidate/classification acceptance atomically persists the correction and a new
  retry generation. Invalid candidates, contradictory official/modified tags or
  stale identity fail without either a partial correction or an orphan retry job.
  `T-Eng`, `Undub` and `Uncensor` survive independently; official classification
  does not mark an English release as an English translation.
- Cached membership/content is rechecked before HTTP, inside result publication
  and when consuming cached metadata. Removed or replaced objects cannot receive
  an in-flight old result; prior metadata evidence is retained, not erased.
- Fresh host SQLite regressions passed, including the actual normal cache writer,
  conservative legacy-score separation, correction persistence, byte
  replacement, failed-review rollback and the existing bounded refresh-worker
  behavior. The real transport workflow passed on current code: a public SNES
  cached title produces review without a score, explicit reviewed identity plus
  official classification retries, and descriptions/media references/sourced
  20-point ratings persist for network-free cache consumption. Explicit fresh
  scraping still queues the item. Consensus reliability remains unassessed.
- This proves a host catalogue/job/provider/cache slice, not normal Thor UI,
  artwork-body downloads, broad reception validation or S4 completion. S4 remains
  ACTIVE with the named required gaps above; no later stage was opened. The Thor
  disconnected before the native integration check. Per the owner's instruction,
  pause for device testing and ask for availability; no device was woken, installed
  or modified during this checkpoint. The cancelled approval monitor stays deleted.

### S1 live ScreenScraper adapter acceptance (2026-10-03)

- Reused the existing standard credentials to sign in to the existing browser
  tab, retrieved the legitimately issued application fields and added only the
  developer ID/password/software-name fields to `.env.local`. Git confirms that
  file is ignored; no account/application secret enters source or this record.
- The actual production Dart adapter, not only a direct API probe, reproduced
  missing artwork: current API responses use `neoclone.screenscraper.fr` for
  authenticated media URLs, while the parser accepted only the API hostname.
  A bounded synthetic regression failed before the narrow hostname correction.
  Both approved origins now yield identity-only media references; query secrets,
  remote hostname and the original URL are not persisted or fetched here.
  Lookalike/unknown hosts and wrong identity/selector tests remain rejecting.
- Fresh focused provider/credential/model regressions passed. The explicitly
  selected `screenscraper_live_smoke_test.dart` passed through the default real
  transport: public SNES title search stays review-only, reviewed identity lookup
  produces descriptions, genres, release dates, credits, media references and
  sourced ratings. The score remains explicitly consensus-unassessed. No ROM or
  media body was requested and no private catalogue was published.
- The browser diagnostic accidentally exposed application fields in one private
  task tool output. This was an execution error, not safe credential handling.
  Those values are not repeated in source/docs or committed; no release is
  authorized, and this credential set must not be distributed.
- The owner-requested 12-hour approval monitoring event was deleted. B2 is
  resolved. B3 is external: DRIVE-01's actual two-account isolation acceptance
  needs the owner's second test-account choice, which has not been provided.
  Supplying/selecting that account resolves the access condition; real isolation
  proof and elapsed-expiry renewal still must pass before S1/final closure.
  S1 is parked BLOCKED, S4 is ACTIVE, and S5-S8 remain NOT STARTED. S4 depends on
  the verified provider/identity contracts and complete S2 catalogue, not on a
  claimed second-account or expired-token proof. Thor displays remain off.

### S1 ScreenScraper application approval checkpoint (2026-10-02)

- The owner restored the existing browser session. The original request at
  `forumsujet.php?frub=12&fsuj=24057` now contains an administrator response dated
  2026-10-02 09:49 confirming developer-account creation. The freshly observed
  signed-in header exposes the private developer-area link. No duplicate post,
  borrowed application key or paid service was created.
- This resolves the pending approval condition, not META-02 live acceptance.
  After that observation the browser extension reported `Debugger unattached`.
  The already-authorized Playwright connection also could not obtain the target
  page. The stalled task-owned helper was cancelled and terminated; the browser
  and profile were not killed, restarted, copied or changed.
- No application credentials were read, printed or saved, and no authenticated
  API lookup occurred. S1 is parked as BLOCKED at credential retrieval/live
  verification. The owner has been asked to reconnect the extension in the same
  tab, or privately enter the issued application fields in the ignored
  `.env.local`. Existing account credentials remain unchanged.
- Resolve B2 only after retrieving the legitimate application credentials and
  passing the actual provider lookup. S4's reception gate and ordinary remaining
  implementation are not satisfied by this approval. Elapsed-expiry and actual
  second-account Drive evidence are still required. No stage is ACTIVE now.

### S1 native authorization failure and repair checkpoint (2026-10-02)

- Transactional cleanup removed 842,580,673 bytes of task-generated build output
  and the superseded 250,598,746-byte task-owned recovery APK after the verified
  normal reinstall. The build ticket retained 11 nonempty directories and 7,563
  excluded pre-existing entries; no broad recursive deletion was performed.
  These expendable outputs can be rebuilt, not recovered from a recycle bin.
- The debug-only `drive_authorization_lifecycle_app.dart` reads the primary saved
  source without config recovery or normal bootstrap. It uses the real native
  driver and fixed-origin read-only root metadata; no mock authorization, database
  writes, queue, ROM body reads or bearer-token persistence. Diagnostic output is
  fixed proof codes, never tokens, account IDs, API bodies or native exceptions.
- Before the repair, PID 18552 connected to the real root at 14:14:33, then stalled
  on native clear. Device feature diagnostics identified
  `auth_api_credentials_clear_token`; the matching microG feature list omits it.
  Its clear handler was never dispatched. PID 25706 rejected a deliberately
  foreign saved binding while retaining real default-account access, but after
  native disconnect at 14:22:21 the held previous grant still returned HTTP 200.
  This was a real remote-revocation failure, not successful revocation.
- The repair selects the actual microG native cache boundary by service component;
  ordinary GMS keeps the plugin operation. Native errors are fixed/redacted and
  calls await completion without a timeout. Explicit remote revocation uses
  Google's OAuth endpoint, form-body token and HTTP 200 before native disconnect.
  A failed server response retains the binding for explicit retry and cannot
  claim a successful revoke or remove a source/file.
- Updated actual Thor PID 2540: native cache clear entered 14:32:16.335 and returned
  14:32:16.428; noninteractive authorization and real root succeeded 14:32:17.329.
  Revoke completed 14:32:35.427, background acquisition required interaction, and
  the held prior grant was rejected by Google with HTTP 401 at 14:32:35.535.
  No account chooser or scope UI appeared during that silent renewal.
- After revocation, actual Google scope consent reappeared. Cancel was selected;
  microG returned to its warning/help flow, and Back ended authorization at
  14:35:27.818 as sanitized `unavailable`, with no grant/root success. This proves
  safe declined access, not that microG supplies the plugin's `cancelled` enum.
  Explicit reconnect to the same default account restored consent and the real
  root succeeded 14:38:42.163. No other account was selected.
- Focused native-driver/coordinator/API contracts passed, covering the supported
  microG and ordinary GMS routes, redaction, revoked background state, read-only
  account binding, token renewal and server-revoke failure preservation. Cache-
  clear regression failed before the implementation and passed afterwards. Actual
  elapsed-expiry and second-live-account proof are still required, not silently
  replaced by a fresh connection or deliberately foreign ID fixture.
- S1 is now parked as BLOCKED at external B2/META-02: legitimate fork application
  credentials and authenticated lookup still cannot be completed. The existing
  ScreenScraper tab was logged out on reload; stale visible content is not a fresh
  approval result. The owner has been asked to restore that session and choose a
  second Google test account. S4 remains BLOCKED at the same access boundary;
  S5-S8 are NOT STARTED. There is no second ACTIVE implementation stage.
- The normal (not probe) debug APK was rebuilt and installed without uninstall,
  SHA-256 `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  Normal startup PID 26680 was verified and stopped. Saved-source config hash
  remained `ddbe4fa2d045fedf91904908210feb24eae71b8bd625427f7aa7a78095d39c69`;
  normal SQLite remains schema 22, 134 games and 2 installations. Both isolated
  roundtrip saves retain their original SHA-256. The transient device UI XML was
  removed; plug-in stay-awake setting restored to 1 and both actual displays
  confirmed OFF. No normal SD library migration, release or push occurred.

### Resumption and provider-access checkpoint (2026-10-02)

- Standard ScreenScraper user credentials are present in the ignored local
  environment file. Live API requests rejected absent application credentials,
  including a probe using the standard credentials in the application fields.
  This is provider-side application authentication, not evidence of an incorrect
  standard account password. B2 is external and blocks META-02 live lookup and
  S4 live samples; issued fork credentials plus a successful lookup resolve it.
- The user authorized handling application registration. The existing logged-in
  account submitted request 24057 in forum category 12 for R-Shop-Darkaxt.
  Approval/credentials are pending; no duplicate request or invented credentials.
  A thread reminder checks every twelve hours and pauses after verified access.
- S8 is recorded in revision 3 and remains NOT STARTED. No companion source
  implementation or Cocoon reuse is claimed.
- At resumption the Thor was connected through ADB but Wi-Fi was disabled and
  there was no active network. Device connectivity must be verified before new
  live catalogue or authentication claims. Both displays were asleep.

### S2 catalogue and recovery checkpoint (2026-10-02)

- Re-enabled the existing saved Wi-Fi connection, without changing cloud files or
  the SD library. The normal native picker selected My Drive / Roms / Sega -
  Game Gear by observed IDs and saved one source into the isolated debug app.
  The local destination remains internal `RShopLiveTest`, not the existing ROM
  collection. Indexing uses only Drive metadata, never the media endpoint.
- Traversal recorded nested assets as well as binary ROMs; raw catalogue entries
  are not a game count. Sleeping the Thor was followed by disabled Wi-Fi and an
  interrupted refresh. Its unpublished generation/checkpoint survived; no active
  snapshot or false empty library was published. Live successful publication and
  browsing remain required before S2 can be COMPLETE.
- Live folder navigation reproduced retained parent scroll position. Its real
  widget regression failed at offset 201 instead of zero, then passed after
  keying the list by the current observed folder ID. Folder selection still
  saves the observed ID, not a typed path or filename.
- Recovery also exposed a pre-existing empty-home defect: Menu/Exit changed state
  but their overlays were absent from that build branch. A regression reproduced
  the missing menu; the corrected branch renders the existing menu and exit
  confirmation. Focused widget verification proves Settings is reachable and
  closing either overlay preserves the home screen; target-device proof follows.
- Focused API/catalogue/source tests passed for paging, nested identities, failed
  snapshot preservation, root confinement, factory/resolver/configuration and
  health. Runtime queue checks passed for restart-stable reservations, mixed-source
  persisted reorder, restored paused/authorization states and cancellation drains.
  These are host fixtures, not live transfer/emulator/removal proof for S3.
- Only one host verification workload was run at a time. No full suite, metadata
  scrape, ROM download, SD deletion or external release was performed.
- Native recheck passed with the rebuilt normal debug APK: controller Start now
  opens the empty-home menu, Settings opens the retained single Drive source,
  explicit Connect uses the owner account, and opening Roms resets the scrolled
  folder list. Cancelling the picker preserves the previously selected Game Gear
  root; Refresh catalogue resumes its same checkpoint rather than adding a source.
  Scoped analysis passed. Verified APK SHA-256:
  `7083516459A9930A94F244EAD69A8846E51D66FF812EB28B69C4736A6E69EC5A`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12, registered debug signer.
- Named S5 UI follow-up: the existing source-actions modal is controller-only
  and overflows at the Thor's landscape size. S5 owns its touch, scroll/layout
  and localized-label acceptance; final verification must exercise every action
  at the actual display sizes. The S2 reconnect/refresh/mapping path is currently
  controller-accessible, so this does not replace its required indexing evidence.

### S2 acceptance closure (2026-10-02)

- The interrupted refresh resumed the existing checkpoint and successfully
  published one complete selected-subtree generation: 2,728 metadata entries,
  including 537 folders. Pending traversal work was cleared only at publication.
  These are inventory counts, not game counts. The metadata-only API has no media
  endpoint; no ROM body was read for indexing and no cloud original was modified.
- The live inventory exposed an archive-filter defect: only raw system ROM
  extensions were admitted. A regression failed with only `Game.gg` instead of
  ZIP/7z/RAR plus the raw ROM; the provider now uses the existing shared archive
  allowlist. Artwork/documents/patches remain excluded, and exact scoped IDs are
  retained. Archive layout/installation validation remains required in S3.
- Cold restart exposed implicit online traversal during ordinary library reads.
  A real factory/runtime/SQLite regression reproduced an authorization failure
  despite a published catalogue. Ordinary reads and automatic startup cache
  projection now read the published snapshot. Explicit Source Refresh and
  user-triggered Sync/Scan retain online preparation, coalesced per source/session;
  refresh failures still reject publication, never become an empty success.
  Missing/foreign mappings still fail. This is explicit command/read separation,
  not a network-error fallback or hidden automatic consent.
- Saved the observed Game Gear root mapping through the normal UI. The rebuilt
  normal debug APK displayed 182 archive entries and Drive badges. After force-stop
  and relaunch with Wi-Fi disabled, all 182 remained available and controller
  navigation worked. SQLite confirmed 182 rows with 182 exact remote references,
  one active catalogue and no pending generation. Cached covers are not claimed
  as a fresh metadata scrape or reliable score evidence.
- Fresh focused provider/exact-identity regressions and scoped Dart analysis pass.
  Earlier unchanged API/catalogue/root-conflict/config/resolver/health and mixed
  persistent queue restart/reorder/cancel checks remain applicable. Native setup,
  mapping and browsing supply the live DRIVE-02/03 evidence; required download,
  publication, emulator and owned-removal proof is assigned to S3, not claimed here.
- Verified normal debug build SHA-256:
  `9A63DA5597A93D5185C1A699723D9EAC910CC9F65A2D19BA52005F8616ADC595`.
  Package/version remain `com.darkaxt.rshop.debug` / 1.7.0+12; registered debug
  signer remains unchanged. No external release, SD migration or payload download.
- S2 is COMPLETE against DRIVE-02 and DRIVE-03; S3 is now the sole ACTIVE stage.
  S1 stays BLOCKED at B2, with all outstanding auth criteria retained. S5 owns
  the explicitly named final source-action landscape/touch/localization check.

### S3 owned-removal checkpoint (2026-10-02)

- Actual app-UID public-to-private rename works on Thor SD FUSE. Public
  no-replace publication/restoration is not relaxed. Removal uses only an
  app-exclusive private quarantine with a durable intent and exact native
  identity, then streaming SHA-256, confirmed handle closure, deletion intent,
  private unlink/fsync and atomic installed-owner release. No recursive cleanup,
  cloud access or namesake adoption is available through this path.
- Additive v19 upgrade/reopen checks from v13-v18 preserve the existing library,
  identity and metadata/job state. Pending removal is not an installed game;
  conflicts retain ownership and bytes rather than becoming unmanaged games.
- Normal detail Delete resolves an exact installed manifest first, shows its
  full local path and size, defaults to Cancel, and revalidates before mutation.
  Cancelling, changing variant or disposing invalidates an asynchronous review.
  A failing long-path landscape regression exposed overflow; content now scrolls
  while Cancel/Delete stay visible. Legacy removal behavior remains separate.
- Normal startup performs one offline removal pass after stage retirement even
  without a saved queue. Focused real journal/engine/runtime tests prove lost
  move/unlink receipt recovery, changed file preservation, fresh re-download
  reservation and shutdown joining the in-flight native operation without sleeps.
- The target-device test passes on `/storage/75D7-DC5F` using actual native IO,
  SQLite, transfer engine and startup queue/runtime recovery. It installs
  synthetic bytes, simulates a lost move receipt, removes that exact fixture,
  reinstalls it and preserves an adjacent synthetic save. Exact expendable
  fixture cleanup passed. Both Thor displays were verified OFF during testing.
  This is not actual Drive media, emulator launch or OS process-death proof.
- S3 remains the only ACTIVE stage. Its remaining required workflow is a real
  Drive download, verification, existing-emulator/offline use, explicit removal
  and re-download, plus bundle/replacement/achievement/large-file and actual
  process-death integration evidence. These are unfinished requirements, not
  deferrals to S5 or S6. No SD-library migration or external release occurred.

### S3 real process-stop checkpoint (2026-10-02)

- A standalone debug-only probe uses its own SQLite database, explicitly selected
  new SD fixture directory and synthetic payload. It never reads application
  preferences, account grants, the application database or actual ROMs.
- Android `am force-stop` terminated the app at an observed durable 1,048,576-byte
  transfer checkpoint. PID absence was confirmed; the new process resumed from
  exactly that offset, verified the complete payload and committed the install.
- A second actual process stop occurred after native public-to-private quarantine
  but before its journal receipt. The next process recovered the durable intent
  offline, removed only the owned synthetic object and reinstalled from offset
  zero. The adjacent synthetic save remained byte-identical through both stops.
  The probe reported PASSED; its exact SD files, private stages and own database
  were removed, and the now-empty synthetic directory was independently absent.
- Probe APK SHA-256:
  `DD3DD5B25B4073F1E5771A5A75AC970ECD4C4D3737CB0766BD85E29C3D89BD51`.
  Normal APK replacement uses `adb install -r`, preserving debug app setup. No
  provider media request or emulator proof is claimed by this synthetic probe.
- Restored normal main.dart debug build SHA-256:
  `4148D2FFA73078B747A3DB9C1C03285F0545151F970D60AEBEBE473383052124`.
  Package `com.darkaxt.rshop.debug`, version 1.7.0/12 and registered debug signer
  were independently inspected. Focused affected host contracts, actual native
  filesystem contracts and the SD removal integration passed; scoped analysis
  including the standalone probe is clean. No full-suite workload was launched.
- Earlier Flutter integration teardown was found to uninstall the isolated debug
  package by default, clearing its setup, not the SD library. The normal app was
  reinstalled and the owner account/root saved again. Future device test commands
  require `--no-uninstall`; the standalone probe never uninstalls the package.
  The replacement catalogue is still unpublished while its rooted traversal
  resumes, so earlier S2 live evidence must not be described as a current cache.
- S3 remains ACTIVE. This checkpoint covers transfer/removal process-stop windows,
  not every publication/cancellation boundary or the actual Drive/emulator cycle.

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

- User authorized selecting the owner account; the actual native
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

### S1 first real Drive authorization (2026-10-02)

- Fresh device checks confirmed an active validated network and successful
  resolution/reachability of Google's auth endpoint. The unchanged inspected
  debug APK was used, with the user's explicitly selected default account.
- Native account selection reached Google's test-app warning and read-only
  consent. Consent disclosed only See and download all your Google Drive files.
  Completing the authorized flow returned to R-Shop with Reconnect, My Drive and
  Use this folder visible and no authorization error.
- The production setup code shows these controls only after acquiring a grant,
  receiving/validating the actual root ID via files.get and completing the
  folders-only files.list response. This is actual native authorization and API
  access evidence, not a mocked chooser or source-installation claim.
- No library source was saved, no ROM downloaded, and no SD/cloud file removed
  or changed. First consent is not expiry-driven renewal, revocation or complete
  two-account isolation proof. META-02 legitimate access is still required.
- Live cancellation/reconnect: pressed Reconnect, deliberately backed out of the
  native chooser, observed cancelled, then selected the authorized account again.
  My Drive/Use this folder returned with no new scope consent or error. This
  proves real cancel and reuse of the current grant, not expiry-driven renewal.
- Release naming: the focused regression failed on the former R-Shop Drive
  default label and passed after changing it to R-Shop. The existing explicit
  debug label/package suffix are unchanged. Gradle processReleaseMainManifest
  succeeded; its actual merged manifest was parsed and asserted to have package
  com.darkaxt.rshop and label R-Shop. No APK output rename was introduced. No
  release APK was built, installed, signed for distribution or published.
- Final device check verified both displays OFF. The live sign-in result applies
  to the already installed debug APK; release naming is verified at the processed
  manifest boundary, not claimed as a deployed release.

No feature requirement is marked satisfied by documentation. No implementation
stage has passed, so the future requirement backlog must not be reported as zero
remaining work. There are no dropped requirements or scheduled required deferrals
outside the eight implementation stages. Revision 3 has 25 requirements; the
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
| Google application configuration and consent | S1 / DRIVE-01, QA-03 | Account-owned test clients, actual native read-only consent, cancel/reconnect and initial API access verified; remaining lifecycle criteria are still required |
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
