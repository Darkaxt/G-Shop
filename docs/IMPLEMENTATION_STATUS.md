# Implementation status and reconciliation ledger

Authority: [SPECIFICATION.md](SPECIFICATION.md).
Execution order: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Scope state

### S7 PSP standalone CHD owned recovery — 2026-10-06

- Added the PSP CHD route to the existing verified committed-leaf handoff.
  Installed official PPSSPP receives an explicit VIEW intent and only the exact
  document-shaped read URI. Ownership and standalone/no-bundle checks run before
  handoff and external open. No directory/write grant, guessed path or inferred
  PSP ISO/CSO/PBP/archive support was added. The menu identifies PPSSPP.
- Normal DOWNLOAD published a 43,841,741-byte PSP test CHD in the initially absent
  isolated `RShopProof-PSP-20261006` destination. Device SHA-256
  `b7c09f4f2c959ada163afb23168eb61169642d75929e195db7280be04a001f46`
  matched the unchanged H: original. Normal R-Shop handoff reached the actual
  game title screen. A cold emulator launch reached that screen with Wi-Fi
  disabled: the first process was stopped after leaving the game, PID absence
  was observed, and the offline launch had a new PID. Intent acceptance alone
  was not counted as boot proof.
- Normal DELETE removed only the reviewed isolated leaf. Normal re-download
  recovered identical bytes; the read-only journal confirmed completed copy
  publication, retired staging, one installation and one owner. Final normal
  DELETE left zero isolated-root transfers/installations/owners and two completed
  issue-free removal journals. The empty proof directory was removed
  non-recursively and absence verified. Original ROM folders were not modified.
- Official [PPSSPP 1.20.4](https://www.ppsspp.org/download/) was a missing live
  prerequisite and was installed without replacing an existing same-package app.
  Official APK SHA-256
  `dd702a31270ecd68db37afee311d6efe08b1d4da9601d2750ce1a73bbd316c3f`,
  verified signer SHA-256
  `c5342629df16762391907b3297aad122b4c1a8a9e608dfb94217a08e3bbf13a2`.
  It remains installed. Missing-emulator reporting uses the existing native
  prerequisite failure path; it was not forced again after installation.
- Focused owned-launch Dart regressions and scoped analysis passed. The new PSP
  regression failed before implementation and passed after it. Native exact-leaf
  grant JUnit XML has no failures/errors. No full suite was run. Gated native-test
  and debug packaging ticket 221 acquired `Local\Darka.AndroidGradleBuildGate`
  (`gate_acquired=true`) and exited 0. Inspected effective profile: two workers,
  parallel=false, 3-GiB Gradle heap; required 1-GiB Metaspace/256-MiB code cache
  preserved. Kotlin 2.2.20 was assessed/requested in-process, sharing that heap;
  no independent task-level strategy marker is claimed. Tests were configured
  for one 512-MiB fork; runtime fork heap was not independently measured. Actual
  app arm64 Ninja compile/link pool depth is one; complete plugin-native coverage
  is not claimed. No memory failure or budget increase occurred. Retained log:
  `1a95779983764c31b87a4be6ae4320f6.log` in the shared gate log directory.
- Same-signer in-place R-Shop installation succeeded; APK SHA-256
  `1a0af3d5464cf9113273ec349db36d7e615b0e34db8afcea0a051add8542349f`.
  The normal PSP folder picker restored `/storage/75D7-DC5F/Roms/psp`; fresh full
  source-configuration SHA-256 returned to the exact baseline
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Normal Drive reconnect and same-transfer resume resolved the post-install
  authorization pause without replacing the queued item. Normal Saved jobs
  resumed SAME N64 job 70: running, pending 1,043 -> 961, accepted/rated/raw-bound
  41 -> 55. Root Refresh retained SAME generation 1 and nextGeneration=2:
  observations 151,289 -> 152,247, pending folders 8,549 -> 8,215, active=null.
  These show progress, not completed scrape or catalogue publication.
- PSP-only Best-25 view is restored: 35/269 ranked, 25 results, explicitly
  Provisional. Wi-Fi is enabled and both physical displays are freshly committed
  OFF. No original ROM, save, BIOS, FolderSync setting or cloud file was edited.
  Exact task-owned device XML/PNG captures are verified absent. Reviewed cleanup
  `331360f780b87b522b9c481b08c956de` removed only expendable host captures, the UI
  helper and official installation APK (46,814,094 bytes);
  the installed apps, R-Shop APK/build log and bounded read-only S7 observer
  remain required for the active stage.
- S7 remains the sole ACTIVE stage. Complete fresh metadata, defensible per-console
  Top-25, root publication, other formats and reviewed save/space-safe migration
  remain required. The bulk LoLSuite-provenance classification decision remains
  pending; unknown editions are not silently classified or ranked. S8-S10 remain
  NOT STARTED. No external release occurred.

### S7 account-bound Drive token reuse and checkpoint resume — 2026-10-06

- Traced redundant native authorization to `DriveAuthorization.acquire`: every
  request called the native scope authorization service despite a usable grant.
  The prior live pause coincided with microG `IssueToken` crashes; causation of
  those service crashes by request frequency is not established. The corrected
  serialized lane retains a grant in memory for its connected account, retires
  it on reconnect/sign-out/account mismatch, and renews on actual rejection.
  Concurrent stale rejections cannot retire a newer grant. No timer lease,
  persisted token, additional retry or consent bypass was added.
- Focused authorization/API/media regression checks passed, including concurrent
  rejection, reconnect, account isolation and sign-out. Scoped analysis and
  whitespace checks passed. The reuse/rejection regressions failed before the
  implementation. No full suite was run.
- Gated debug packaging ticket 220 succeeded. The installed supervisor executes
  its wrapper inside `Local\Darka.AndroidGradleBuildGate`; the inspected current
  log `047159a2309241d588f295434ca5b12b.log` records successful wrapper completion
  and effective two workers, parallel=false and 3-GiB Gradle heap. The final
  supervisor JSON was truncated in tool output, so its separate acquisition flag
  is not retained as direct evidence. Kotlin 2.2.20 was requested in-process;
  configured tests use one 512-MiB fork (none ran in this packaging invocation).
  Required Metaspace/code-cache arguments were preserved. Existing app Ninja
  pools remain depth one per ABI; complete plugin-native concurrency is not
  claimed. No memory failure or budget increase was observed.
- Normal same-signer in-place installation succeeded. APK SHA-256:
  `9dd923876d707e0d2c1ac574c5a44d7ea590996bf3414c91b94e897a8b0d9f9e`.
  Normal default-account reconnection succeeded; Back without Save preserved the
  complete source configuration SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
- Normal Saved jobs selection resumed SAME N64 job 70. Read-only observations
  show running and pending 1,128 -> 1,118, with 34 accepted/rated raw-identified
  editions. Normal Refresh resumed SAME root generation 1: observations
  150,515 -> 150,630, pending folders 8,803 -> 8,765, nextGeneration=2. This is
  live resumed progress, not completed traversal, classification or ranking.
  Provider rejection renewal is host-verified; a new real token expiry/rejection
  was not forced in this native check.
- Both physical displays are freshly committed OFF. No original ROM, save,
  BIOS, FolderSync setting or cloud file was edited. The exact task-owned device
  UI dump was removed and absence verified; no host capture was created. Build
  logs/APK and the bounded read-only S7 observer remain required evidence.
- S7 remains the sole ACTIVE stage. Full fresh metadata, defensible per-console
  Top-25, root publication, remaining formats and reviewed save/space-safe
  migration remain required. The bulk LoLSuite-provenance classification policy
  question is pending; unknown editions are not silently classified or ranked.
  S8-S10 remain NOT STARTED. No external release occurred.

### S7 PS1 standalone CHD owned recovery — 2026-10-06

- Added the missing standalone PS1 CHD route to the existing committed-leaf
  RetroArch handoff. Native guards reject archive mappings, bundle members,
  dependencies and non-leaf paths. External opens still verify durable ownership,
  publication and pinned identity. No directory/write grant or speculative
  PS1 archive/bundle support was added. The normal menu identifies RetroArch.
- Normal DOWNLOAD published the 30,778,396-byte USA test CHD in the initially
  absent `RShopProof-PSX-20261006` destination. SHA-256
  `d1ea36aafbecb1c650d35b07c3fc50aff239108ccbe3844aa4f35678547917d0`
  matched the H: original. The installed RetroArch lacked a PS1 core; normal
  official Core Downloader installed PCSX ReARMed. Normal R-Shop handoff reached
  the actual Tactics Ogre title screen. After normal Quit and absent PID, a new
  process reached the title screen with Wi-Fi disabled. Intent acceptance alone
  was not counted as boot proof.
- Normal DELETE reviewed and removed only the isolated owned leaf. Normal
  re-download recovered the same full hash. The read-only journal confirmed
  completed copy publication, `stageRetired=true`, one installation and one owner.
  Final normal DELETE left zero isolated-root transfers/installations/owners and
  two completed issue-free removal journals. The now-empty test folder was removed
  non-recursively and absence verified; original ROM folders were not modified.
- The normal folder picker restored `/storage/75D7-DC5F/Roms/psx`. Complete
  configuration SHA-256 returned to the exact baseline
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both RetroArch configuration files and all seven inspected PS1 BIOS hashes
  matched their pre-launch values. RetroArch created its normal test memory-card
  files; they are preserved, not deleted through ROM cleanup. No save, BIOS,
  FolderSync setting or cloud file was edited by this implementation.
- Focused Dart owned-launch tests and scoped analysis passed. The PS1 route
  regression failed before implementation and passed afterwards; native grant
  JUnit XML reported no failures/errors. No full suite was run. Build 216 ran the
  focused native grant test plus normal debug packaging. Build 219 packaged the
  corrected menu label. Both acquired `Local\Darka.AndroidGradleBuildGate` and
  exited successfully. Observed profile: two workers, no parallel projects,
  3-GiB Gradle heap, preserved 1-GiB Metaspace/256-MiB code cache. Kotlin 2.2.20
  was requested in-process, sharing that heap; configured tests use one 512-MiB
  fork, not independent runtime heap measurement. The app's actual Ninja files
  used by the build specify a shared compile/link pool of depth one per ABI;
  complete plugin-native/task override coverage is not claimed. No memory failure
  or heap increase occurred. Build 219 waited for existing ambiguous activity;
  it did not interrupt that build. Logs `a4fe4d9836b74502a6c23d3f0e4b574a.log`
  and `78922612ea524093aff095305fd042cf.log` remain required verification evidence.
- Latest normal APK SHA-256
  `3143d86445c886276a35e05b85742502ed4fa51b8e7f22bae360062d1aa9ceaa`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12, unchanged debug signer.
  In-place installation preserved the full configuration hash; the corrected
  PS1 menu was inspected natively. Normal default-account reconnection and Back
  without Save preserved sources/mappings. The SAME saved N64 job 70 resumed:
  inspected running, 229 outcomes, 1,162 pending, 27 accepted/rated with 27 exact
  local raw bindings classified official. Root generation 1 also resumed:
  149,434 observations / 9,162 pending folders, active=null, nextGeneration=2.
  Those are in-progress observations, not terminal scrape/catalogue success.
- Both physical displays are freshly confirmed committed OFF. Reviewed cleanup
  `0b0806b691852ac17595f12866162508` removed only expendable host captures
  (130,765 bytes); exact device XML/PNG captures are verified absent. The installed
  APK, build logs and bounded read-only S7 observer remain required. S7 is the sole
  ACTIVE stage: complete fresh metadata, defensible per-console Top-25, root
  publication, remaining format proofs and the reviewed save/space-safe migration
  remain unfinished. S8-S10 are NOT STARTED. No external release occurred.

### S7 standardized already-local archive identification — 2026-10-06

- Existing bounded N64 7z/ZIP and Game Gear ZIP validators now return streamed
  raw-member MD5/SHA-1/CRC/size, separately from the container digests. Metadata
  reads pin the exact existing leaf, compare container bytes before/after parsing,
  reject namespace/content changes and revalidate the current rooted Drive
  artifact before/after the read. They neither extract nor request remote ROM
  bodies, create stages, adopt installations or remove files.
- The normal persistent metadata worker atomically binds that observation to its
  immutable request and exact artifact version. Replacement bytes retire old
  evidence; unchanged observations survive restart/shared-store recovery. Manual
  unknown classifications, modification tags, patches and base-game links remain
  protected. `integrityVerified=false` explicitly prevents this lookup evidence
  from being interpreted as current-cloud recovery or SD-removal authority.
- Focused native validator/path regression checks and Dart runtime/catalogue/
  shared grouping/CHD/control checks passed. Native raw-hash assertions failed
  before implementation and passed afterwards. A focused fixture lacked the real
  catalogue's filename column; aligning that fixture with the actual schema fixed
  its failure without a production workaround. Scoped analysis and whitespace
  checks passed; no full suite was run.
- Gated native-test/debug build 214 succeeded with mutex acquisition, observed
  two workers/no parallel projects/3-GB Gradle heap, preserving 1-GB Metaspace and
  256-MB code cache. Kotlin 2.2.20 was requested in-process, sharing that heap;
  tests were configured for one 512-MB fork, not independently heap-measured.
  The subsequent debug diagnostic build 215 also succeeded through the gate.
  No memory failure or heap increase occurred. Native concurrency is configured
  with one compile/link slot per ABI; no fresh effective Ninja-pool measurement
  is claimed for these builds. Logs: `0c47dc23b3e04ffdbd501c42552d9ac6.log` and
  `64c1011938d04abd8b40239a6dd5ff22.log` in the shared build-gate log directory.
- The normal debug APK was installed in place with the unchanged signer. Latest
  APK SHA-256 `65b8caf5f6851a760c90e0939dfd4e33088b658485604376d24263ea3bf82f63`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12. Its assertion-only diagnostic
  logs the exception type, never messages, bodies, credentials or identifiers.
  The final restricted import is namespace-only; focused controls/analysis passed.
- One normal N64 Fresh re-scrape captured 1,391 current editions as job 70.
  Initial native access required normal default-account reconnection; Back without
  Save preserved configuration. An uninstrumented attempt paused after eight
  outcomes; its exact exception was not captured and is not assigned a guessed
  cause. After diagnostic APK replacement, a resume reported the sanitized
  `DriveAuthorizationException` type. Normal reconnection and resume advanced
  the SAME saved job past that pending archive: latest inspected state running,
  57 outcomes, 1,334 pending, five matched/rated and five persisted exact local
  raw bindings independently confirmed as official. Ambiguous/unidentified
  entries remain unapproved. This proves the real standardized path, not terminal
  job success, full metadata coverage, defensible Top-25 or MIGRATE-01 closure.
- An auxiliary read-only query joining an unbounded catalogue was killed; it was
  replaced by primary-key reads from a three-row pending page. No host-memory
  cause is inferred. The remaining-gates observer is retained for S7; expendable
  captures/probe output are reviewed for exact cleanup. Original N64 ROM bytes and
  complete source configuration remain hash-identical to the pre-test baseline.
  No save, BIOS, FolderSync setting or cloud file was changed. S7 remains the sole
  ACTIVE stage; S8-S10 remain NOT STARTED.
- Both physical displays are freshly confirmed committed OFF; the single saved
  metadata worker is left running. Reviewed cleanup transaction
  `7c7e480f300434f4bb8904784adfb71d` removed only task captures and the expendable
  read-only host probe (1,336,987 bytes); both exact device XML/PNG captures are
  verified absent. The installed APK and bounded S7 observer remain required.

### S7 N64 archive queue / offline launch / removal / recovery — 2026-10-06

- Explicit standalone N64 ZIP/7z mappings now participate in the normal queue,
  immutable transfer record, pre-publication native validation, installation
  journal and exact-leaf read-only RetroArch handoff. Unsupported/untyped archives,
  multi-file layouts, unsafe names, malformed CRCs and excessive output/dictionary
  budgets remain rejected. No extraction or original-archive rewrite is performed.
- The real source exposed two layout differences missing from the first synthetic
  fixtures: RomVault's documented, header-bound 32-byte structured marker and LZMA
  streams with both a known size and an end marker. The narrow parser now validates
  those structures explicitly using XZ 1.12; it does not ignore generic padding or
  swallow corruption. Focused native regression tests and the unchanged real host
  archive passed before the corrected APK was installed.
- APK SHA-256 `c27fbd0dce378c999ce7bbb05436fc919db742c512bf1b9f5f54b95f6534e03a`
  was installed in place with the unchanged debug signer. The original failed queue
  item was retried, not deleted/recreated. Normal default-account reconnection was
  required after APK replacement; no source was saved or remapped during consent.
- Normal DOWNLOAD published the 5,670,365-byte USA 7z into the initially absent,
  isolated `RShopProof-N64-20261006` directory. SHA-256
  `851a51ea358fbbe59e5f818b418f428d8fc3b18888fb400295ee2ef0ae3e6277`
  matched the source. Normal Open in RetroArch reached the actual Super Mario 64
  title screen in Mupen64Plus-Next. After normal emulator Quit, its PID was absent;
  a new emulator process reached the title screen again with Wi-Fi disabled.
  Activity acceptance alone was not treated as boot evidence.
- Normal DELETE showed the exact isolated leaf and removed only the owned copy.
  A second normal DOWNLOAD published identical bytes. The read-only journal audit
  confirmed `archivePlatformId=n64`, completed publication, one installation/owner
  and `stageRetired=true`. A second inspected normal DELETE and Clear Done left
  zero test-root transfers/installations/owners and two completed, issue-free
  removal journals. The original SD archive remained hash-identical throughout.
- The normal folder picker restored `/storage/75D7-DC5F/Roms/n64`. Complete source
  configuration SHA-256 returned to the exact baseline
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Wi-Fi is enabled; PSP-only Best 25 remains 35/341 ranked, 25 results, Provisional,
  with zero favorites. The empty test directory was removed non-recursively and
  absence verified. Both physical displays are freshly confirmed committed OFF.
- Focused Dart queue/journal/adoption/handoff tests and analysis passed. Both native
  builds acquired `Local\Darka.AndroidGradleBuildGate`; the first waited behind an
  existing build without interruption or overlap. Latest build log
  `7034c6896cd243bda43ccb3c5dd403bc.log` verifies two workers, no parallel projects
  and a 3-GB Gradle heap. Kotlin was requested in-process, sharing that budget;
  tests were configured for one 512-MB fork. Current app Ninja rules use a depth-1
  compile/link pool per ABI. No memory failure or budget increase occurred; test
  fork heaps and Kotlin runtime strategy were not independently measured.
- Root catalogue generation 1 is still pending (148,325 observations, 9,524 pending
  folders at the inspected checkpoint; nextGeneration 2). Classification and
  whole-collection Top-25 coverage remain unresolved. This verifies one real N64
  recovery workflow, not every archive/console or MIGRATE-01 closure. S7 remains
  the sole ACTIVE stage; S8-S10 remain NOT STARTED. No original ROM, save, BIOS,
  FolderSync setting or cloud file was changed. A microG stopping dialog occurred
  while offline and was dismissed; no claim of its cause or remediation is made.
- Reviewed cleanup transaction `e74eb43e735482aec7a01ff513060c9d` removed only the
  task-owned host capture/probe/compiler output (1,885,661 bytes). The exact device
  XML/PNG captures are verified absent. The bounded read-only journal observer is
  retained for the remaining S7 diagnosis; the installed APK is intentionally kept.

### S7 matching recheck / durable recovery evidence / root resume — 2026-10-06

- Fresh focused `regional` ScreenScraper/IGDB checks passed for revision-9 matching,
  including the persistent two-provider workflow. Company wording and day/month
  differences do not veto an otherwise qualified match; region/year conflicts,
  ambiguity and unknown or modified editions remain protected. This does not
  certify collection-wide ranking or waive any migration gate.
- The prior read-only observer failed because Thor SQLite lacks `json_extract`,
  as confirmed by its native exception. A bounded read-only Java JSON scan now
  confirms both Game Gear test removal journals completed without issues and
  no test-root transfer, installation or owner remains. No memory cause or
  production defect is inferred from that diagnostic failure.
- Normal Refresh resumed root generation 1 without replacing the checkpoint:
  144,619 -> 145,160 observations, 10,667 -> 10,499 pending folders, unchanged
  nextGeneration 2. Publication is still unfinished. N64 format counts demonstrate
  that ZIP-only recovery would not cover the predominantly 7z collection;
  no N64 format approval or recovery implementation is claimed.
- No Gradle command, build, APK replacement or original-ROM/cloud/save operation
  was performed. Configuration hash remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Fresh display-state evidence confirms both physical displays committed OFF.
  S7 remains ACTIVE; S8-S10 remain NOT STARTED.

### S7 Game Gear normal download / offline / removal / re-download — 2026-10-06

- On unchanged normal debug APK 206, a newly created, initially absent test
  directory isolated the real Game Gear ZIP queue proof from existing SD ROMs.
  Only Game Gear's target folder changed through normal Console Settings and
  Android's folder picker; an in-memory comparison confirmed exactly one changed
  configuration field and unchanged sources. No original ROM was moved/deleted.
- Normal DOWNLOAD completed and published the 58,610-byte ZIP. Its SHA-256
  matches `2fc171b6ba8de52d9ce3572531fd37f8bf10326ae04470a82e56438908c34e11`.
  Normal Open in RetroArch reached the actual game's title screen, then a cold
  second launch with Wi-Fi disabled reached that screen again. Activity dispatch
  alone was not used as launch evidence; both emulator renders were inspected.
- Normal DELETE displayed the exact task-root leaf and reclaimed-size plan.
  Confirmation removed only the owned test copy: its folder was empty, the
  detail returned to DOWNLOAD, and the original SD archive remained hash-identical.
  One new normal DOWNLOAD completed into the same test root with the same digest.
  That expendable second copy was removed by another inspected, ownership-checked
  normal DELETE. Clear Done cleared its terminal queue row through the ordinary UI.
  This is real queue/remove/re-download proof, distinct from earlier adoption.
- A bounded READONLY auxiliary journal observer was killed twice without a
  result; no durable-journal/stage-retirement observation is claimed for that
  diagnostic. Normal UI and exact filesystem/digest evidence above succeeded.
  No memory-exhaustion cause is inferred from an auxiliary process being killed.
- Wi-Fi is restored to enabled. The normal folder picker restored the original
  Game Gear target; configuration SHA-256 exactly equals the pre-test baseline
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Structural configuration/source equality was independently checked without
  printing private values. PSP-only Best 25 is restored (35/341 ranked, 25 results,
  Provisional), favorites zero. No save, FolderSync or cloud-original operation
  occurred. The now-empty test directory was removed non-recursively and absence
  verified. Both physical displays are confirmed committed OFF.
- Reviewed cleanup transaction `3c1449e401e4e0ddf0a8edde2807ab86` removed the
  final task-only host capture (129,018 bytes); both exact device capture files
  are verified absent. The existing private diagnostic helper remains retained
  for the unresolved live S7 investigation, not as a requested public deliverable.
- No Gradle command, build, production edit or APK replacement was needed;
  unchanged APK 206 verification remains applicable. S7 is still the sole ACTIVE
  stage: defensible collection rankings/classifications, other format recovery,
  execution-time migration checks and actual reviewed SD migration remain
  unfinished. S8-S10 remain NOT STARTED; no required criterion was waived.

### S7 GameCube IGDB breadth / saved catalogue resume — 2026-10-06

- Normal metadata settings started the omitted full GameCube IGDB pass, job 69,
  once. Its current 205-edition capture completed: 132 needsReview, 67 ambiguous,
  six unmatched, zero matched/rated, pending or failures. Captures contain 194
  unknown, one official and ten other-tagged editions. No classifications,
  corrections or scores were invented; completed traversal is not retention proof.
- The existing Collection source reported `interactionRequired` after the debug
  APK replacement. Normal Connect/configure and the already-authorized default
  account restored native read-only authorization. Returning without saving kept
  the source, folder and mappings unchanged. One ordinary Refresh resumed the
  existing checkpoint: pending generation 1 / nextGeneration 2 are unchanged;
  observations increased from 144,225 to 144,255 and pending folders decreased
  from 10,765 to 10,755. These are observed progress, not final publication.
- No extra build, APK replacement, ROM download/removal, classification import,
  cloud-original mutation, save or FolderSync operation was performed. Source
  configuration SHA-256 remains unchanged. The normal PSP-only Best 25 drawer
  again shows 35/341 ranked / 25 results / Provisional; favorites remain zero.
  Both displays are confirmed committed OFF. Reviewed cleanup
  `75f368fd319dd9f9ca5904405b4fca79` removed the inspected host capture
  (1,872,736 bytes); both task-only device captures are verified absent.
  The diagnostic helper stays retained for the running root checkpoint.
  S7 is still the sole ACTIVE stage;
  ranking/classification, full recovery and reviewed migration remain unfinished.

### S7 Game Gear ZIP validation and real emulator handoff — 2026-10-06

- Game Gear IGDB job 68 completed its unchanged 548-edition capture: two
  matched/rated, 442 needsReview, 79 ambiguous, 25 unmatched, zero pending.
  ScreenScraper job 66 remains completed with the recorded outcomes below.
  The Game Gear query still has zero score-qualified groups; traversal is not
  defensible Top-25 coverage. The latest root snapshot is still unpublished at
  144,225 observations / 10,765 pending folders, not evidence of an active scan.
- The explicit mapped Game Gear ZIP path now preserves the exact archive name
  and bytes. Immutable transfer intent, pinned native single-member structure/
  CRC validation, normal queue publication, adoption and recovered publication
  are integrated. Encrypted, multi-member, unsafe, malformed and untyped legacy
  archives remain rejected. Focused runtime/engine/journal/launcher checks passed;
  native ZIP and exact document-leaf tests passed without skipped cases.
- A real normal queue attempt correctly preserved an existing unmanaged target
  collision. Its terminal test row was cleared through the ordinary UI. A fresh
  full local/cloud comparison then deliberately adopted one identical ZIP;
  adoption is not reported as a download. No original ROM was removed.
- The installed RetroArch initially lacked its private Genesis Plus GX core.
  Normal Install/Restore Core installed the already-existing shared core. After
  that prerequisite, the generic content-URI route caused a reproducible native
  core crash, while the same local ZIP booted directly. The fix retains the ZIP
  filename through RetroArch SAF using one document-shaped owned-leaf read grant;
  it exposes no directory, sibling, write, prefix or persistable access.
- Final normal APK 206 booted the adopted ZIP through Open in RetroArch, then
  booted it again cold with Wi-Fi off. The archive SHA-256 stayed
  `2fc171b6ba8de52d9ce3572531fd37f8bf10326ae04470a82e56438908c34e11`.
  This verifies adoption/handoff/offline use, not removal/re-download or migration.
  Saves, FolderSync, cloud originals and R-Shop source mappings were not changed.
- Build-gate ticket 206 (`2830c31e2bb84b94a1befdb2c892f8e5`) acquired the shared
  mutex and exited successfully. Observed profile: two workers, parallel false,
  Gradle maximum heap 3 GiB; evaluated Kotlin in-process compilation shares that
  heap. Test tasks use one fork / 512 MiB; native per-ABI pools remain one, not a
  verified universal host concurrency cap. No memory failure or budget increase.
  Current APK SHA-256 is
  `b71bd5884d3b433ddfce650eb7beabf34929c4dff0209ff349910d4ead42052c`;
  its existing debug signer was preserved and installation was in-place.
- Wi-Fi was restored, the PSP-only Best 25 view and zero favorites restored,
  configuration SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`,
  and both displays are freshly confirmed committed OFF. One PSP projection was
  dirty in the latest read-only observation; do not label all projections clean.
  Reviewed cleanup transaction `0eb8b48e3b4755c3b6ab0680abe5ebf4` removed only
  the obsolete host capture/debug config (128,667 bytes); the corresponding two
  device captures and task-created debug config are verified absent. The bounded
  diagnostic helper remains necessary and retained; unrelated files are preserved.
  S7 is still the sole ACTIVE stage. Classification/coverage, defensible retention,
  full format recovery and reviewed execution remain unfinished; S8-S10 stay
  NOT STARTED. No required criterion was deferred or marked complete.

### S7 Game Gear completed traversal / IGDB breadth — 2026-10-06

- Normal ScreenScraper job 66 completed its unchanged 548-edition capture:
  one matched/rated, 377 needsReview, 63 ambiguous, 106 unmatched, one
  invalidResponse and zero pending. Normal settings and the fixed READONLY
  diagnostic agree. This is traversal, not trustworthy ranking coverage.
- A bounded authenticated diagnostic reproduced the failed short-title lookup:
  HTTP 200 with a 49-byte plaintext missing-information error, not a JSON game
  response. The same authentication/platform with a control search returned valid
  JSON and nine candidates. This identifies the provider-response boundary, not
  a documented minimum search length. No guessed ID, per-title alias, automatic
  retry or parser relaxation was introduced; the outcome remains unresolved.
- After ScreenScraper and linked artwork finished, normal settings started the
  missing full Game Gear IGDB pass, job 68, on 548 editions. Latest persisted
  observation: running, two matched/rated, 143 needsReview, 22 ambiguous, six
  unmatched, 375 pending, no failures. Continue that ID without recreating it.
- Root catalogue generation 1 keeps advancing: 143,655 observations / 10,938
  pending folders, still unpublished / nextGeneration 2. No second refresh or
  reconnect was needed. This is progress, not final collection coverage.
- Read-only restore investigation found the Drive queue/adoption reject archives
  and Game Gear's cloud selection is ZIP-based. Installed RetroArch/Genesis Plus
  GX and archive documentation are not tested R-Shop recovery. Safe archive
  recovery remains ordinary S7 work, not a later-stage deferral or external
  blocker. No rejection was removed or emulator configuration changed.
- No production change, Gradle command, APK install, ROM payload, classification
  import, ownership/removal, save/FolderSync or cloud-original mutation occurred.
  Config SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both displays are confirmed committed OFF. The existing private helper/capture
  remain registered under transaction `df179c1d8993cfe821d879429c8cc50a` for the
  ongoing live outcome. S7 stays the sole ACTIVE stage; S8-S10 stay NOT STARTED.
  Required rankings, restoration and reviewed SD migration remain unfinished.

### S7 remaining-gate audit and Game Gear breadth — 2026-10-06

- A fixed bounded READONLY native diagnostic inspected actual persisted jobs
  and the six current projections. Before the new pass, all projections were
  clean: eligible canonical groups are PS2 59/220, PSP 35/341, GameCube 0/205,
  PS1 0/405, N64 0/1543 and Game Gear 0/548. These are observed group keys, not
  proof that every unclassified duplicate is already correctly canonicalized.
  Missing coverage is not an updating/dirty-projection explanation for migration.
- Persisted bulk captures explain a major remaining identity boundary:
  GameCube job 51 captured 195 unknown / one official / ten other-tagged editions;
  PS1 job 50 captured 401 unknown / four official; N64 jobs 31/33 captured 1,518
  unknown / 25 other-tagged. None had supported raw identifiers. Filename/title
  matches, ZIP/7z/RVZ container digests or absence of patch tags cannot silently
  establish official classification. The owner's reviewed LoLSuite profile
  describes retail selections but does not itself bind a current converted cloud
  blob cryptographically. No classifications or curated rankings were imported.
  An explicit classification-source decision was asked; it does not block the
  independently required scrape currently running and is not stage completion.
- The audit found Game Gear's earlier native jobs covered only one entry each.
  Normal settings started exactly one Game Gear-only ScreenScraper pass, job 66,
  on 548 current editions. Latest authoritative observation: running, 77 checked,
  one matched/rated, 50 needsReview, ten ambiguous, 16 unmatched, 471 pending,
  zero failures. Captures have 546 unknown / two official and 311 region hints.
  Continue this same persisted ID; do not recreate it after an observer failure.
  No second metadata job was started. Final traversal/IGDB coverage remains
  unfinished, not a blocker or evidence that S7 has closed.
- An auxiliary app_process observation while the screens were off was killed;
  it is not terminal-job evidence. Subsequent normal UI and a successful fixed
  READONLY foreground observation confirmed job 66 and its increasing progress.
  The app remained alive; no memory-exhaustion cause is claimed from that kill.
  The private helper/source and current capture remain at
  `D:\Temp\rshop-s7-remaining-gates-20261006` until this live job's outcome is
  verified (cleanup transaction `df179c1d8993cfe821d879429c8cc50a`).
- No Gradle build, app replacement, source remapping, ROM payload, ownership,
  removal, cloud write, FolderSync or save operation occurred. Configuration hash
  remains `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both physical displays are confirmed committed OFF while job 66 continues.
  S7 remains the sole ACTIVE stage; S8-S10 remain NOT STARTED. Required metadata,
  defensible retention, recovery and actual reviewed migration are unfinished.

### S7 standardized matching — PS2 breadth verification, 2026-10-06

- On unchanged build 193 / implementation `f270427`, the normal settings flow
  started one fresh IGDB pass scoped to PS2. All 225 captured requests completed:
  74 matched, 91 needsReview, 28 ambiguous, 32 unmatched, zero failed/unsupported
  or pending; 72 responses carry ratings. The previous PS2 pass matched twenty.
  No per-game approvals, classification changes or saved-request rewrites occurred.
- The ordinary native Library Best 25 filter, scoped only to PS2, shows
  **59/220 ranked, 25 matching games, Provisional**, using the existing assessed
  IGDB community average / 20+ vote rule. The 225 requests are editions/artifacts;
  the query denominator is 220 canonical groups. This demonstrates real bulk
  publication and grouping, not complete coverage or safe eviction. The original
  PSP Best 25 filter was restored and again showed 35/341 ranked / 25 results.
- Config SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  No ROM bodies, local installations, ownership, saves, FolderSync, mappings or
  cloud originals changed. No Gradle build or deployment was needed: this pass
  exercised the already-installed, verified final implementation.
  Both displays are confirmed committed OFF. The inspected temporary host
  screenshot was transactionally removed (1,150,550 bytes), and the two exact
  task-only device capture files were removed and verified absent.
- S7 remains the sole ACTIVE stage. Full defensible rankings, format recovery,
  execution-time byte checks and actual reviewed SD migration remain unfinished;
  S8-S10 remain NOT STARTED. Sparse Top coverage is not deletion authority.

### S7 authorized standardized matching — 2026-10-06

- Specification revision 9 records the explicit authorized evidence-tier policy.
  Exact title/platform/region and compatible regional year replace exact company
  wording and full-date vetoes. Ports/bundles/remakes/remasters keep their own IDs;
  wrong platform/region/year, ambiguous/capped results, unknown classifications
  and modification/edition conflicts remain reviewable. Names do not verify ROM
  bytes or waive score/removal safeguards. Old saved captures keep their original
  policy and serialization, including legacy title/date semantics.
- Focused regressions, normal two-provider worker publication, offline grouping/
  ranking, source-change rejection and shared-store recovery passed. A real
  deterministic cohort of twelve previously rejected current PSP releases
  yielded ten IGDB matches and two needsReview; four meet the unchanged community
  vote floor. No title-specific corrections or provider-ID guesses were used.
  The same real cohort matched all twelve through ScreenScraper regional name
  confidence, without raw-classification claims. An initial failed live check
  exposed missing search-response `notgame`/ROM fields; a reproduced regression
  fixed this only for already-official editions, retaining explicit conflicts
  and all unknown raw-classification requirements.
- Normal Thor PSP job 64 completed: 341 requests, 75 matches (old job 45: twelve),
  177 needsReview, 39 ambiguous, 50 unmatched, zero failed/unsupported/pending.
  On final build 193 the ordinary PSP Best 25 query displays 35/341 ranked and
  25 matching games, Provisional; the old projection had six eligible groups.
  This proves publication into the native collection query, not full coverage
  or safe SD eviction. No individual entries were manually approved.
- Final debug APK: 223,625,058 bytes, SHA-256
  `1d60472e3232f1d4faf9842710fc57630a886906ef646a2243f00a96c6bd976c`,
  package `com.darkaxt.rshop.debug`, same verified signing certificate.
  Install -r preserved data; configuration SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both displays are confirmed committed OFF. ROMs, cloud originals, saves,
  FolderSync and ownership claims were unchanged; no release occurred.
- Build 193 exited zero with the shared gate acquired (FIFO ticket 196).
  Observed workers=2, parallel=false, Gradle maximum heap=3 GiB; assessed Kotlin
  2.2.20 in-process shares that heap, required JVM flags remain. Test forks are
  configured one/512 MiB (none ran during assemble); native task pools are one,
  not a measured total-host cap. No memory failure/increase. Evidence log:
  `D:\Temp\rshop-s7-standardized-build193-20261006.log`; bounded private cohort:
  `D:\Temp\rshop-standardized-cohort-20261006.json`.
  Six exact task-only host diagnostics/compiler/UI outputs were transactionally
  removed (30,211 bytes), together with three task-only device probe/capture
  copies. Current APK/log and the private cohort remain. A final auxiliary
  READONLY aggregate process was killed by Android; its incomplete output is
  not counted as evidence. The app remained alive, and subsequent normal UI
  confirmed the complete cached PSP query on the final build after restart.
- S7 remains the sole ACTIVE stage; defensible full collection rankings,
  restoration coverage and reviewed safe SD migration remain unfinished.
  S8-S10 remain NOT STARTED. The matching-policy change does not close S7.

### S7 explicit standardized adoption — 2026-10-06

- Normal local/cloud byte review now offers a separate deliberate adoption
  action for supported standalone emulator-ready files. It performs a new full
  comparison, closes reads, rechecks current Drive/public-file identity, and
  atomically records the existing installation/target owner with `adopt`
  provenance. It creates no staged ROM, rename or deletion. Archives and
  dependency manifests are not admitted to this single-file route. No saved
  observation, title match, candidate metadata or score grants ownership.
- Focused runtime, journal and dialog checks passed, including owner conflicts,
  cancellation/namespace/version changes, transactional rollback, installation
  resolution and the existing exact owned-removal workflow on synthetic bytes.
  Scoped analysis is clean; the changed journal test passed again after its
  analyzer-only brace correction. No full suite was run.
- Signature-checked build 189 was installed with -r, preserving app data.
  Normal Thor UI first rejected expired authorization without claiming a file,
  then, after normal default-account reconnect without saving/remapping sources,
  completed adoption of the existing 20,131,764-byte RVZ against Drive version 2.
  Normal details changed from download to managed installation. A bounded
  READONLY journal probe before/after app-process restart found the same completed
  adoption, one target owner, no stage identity, confirmed publication and the
  independently unchanged SHA-256
  `0d7aeb487d665ce3fceffc25ea8041afeffe44faf223640e84f5f8dcb4f2578f`.
  Native deletion was deliberately not performed. Config hash remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both displays are confirmed committed OFF. Saves/cloud originals/FolderSync
  and ROM bytes were unchanged; only the deliberate private ownership claim
  was added. This is reusable workflow proof, not individual-game curation.
- Build 189 exited zero through the acquired shared Gradle gate. Observed
  workers=2, parallel=false, Gradle heap=3 GiB with preserved metaspace/code-cache
  flags. Assessed Kotlin 2.2.20 used in-process compilation within that heap.
  Test forks were configured one/512 MiB but none ran during assemble; native
  pools remain one per task, not a measured host-wide cap. No memory failure or
  budget increase occurred. APK: 223,625,546 bytes, SHA-256
  `292282f4d9ac552a312f5ee2f2a0bce211b4af8ce64c83add927411fe09b176f`,
  package `com.darkaxt.rshop.debug` v1.7.0/code 12, unchanged debug signer.
  Build log remains at `D:\Temp\rshop-s7-adoption-build189-20261006.log`.
  Exact task-only host diagnostics/compiler/probe outputs were transactionally
  removed (8,252 bytes); their two task-only device copies were also removed
  after inspection. Current APK/log and required private migration evidence stay.
- S7 remains the sole ACTIVE stage. Full defensible ranking, recovery/save/sync
  gates, reviewed execution manifest and actual SD migration remain unfinished.
  Adoption does not waive these criteria. S8-S10 remain NOT STARTED; no release.

### S7 standardized descriptive preview — 2026-10-06

- Collection-wide aggregate diagnosis, not individual curation, confirmed that
  finished lookups still leave insufficient reliable Top coverage. PS1/GameCube
  have no eligible ranking groups; PS2 has 12 and PSP six. The current root scan
  continues progressing. A bounded live six-container ScreenScraper cohort did
  not return exact stored MD5/size matches; no container/raw shortcut was added.
- The shared scraping preview now carries already-returned synopses from both
  metadata adapters and accepted records. A sole unverified candidate remains
  labelled unverified and cannot publish a score or Top rank. Ambiguity clears
  descriptive context. Payload/language handling is bounded, and entities are
  decoded once at display time without interpreting HTML or requesting media.
  There are no title-specific rules or individual match approvals.
- Focused adapter and normal controller-to-widget checks passed, including
  multiple entries and accepted/unverified/ambiguous transitions. Scoped
  analysis passed. Native build 187 verified both accepted and unverified
  previews through normal scoped scraping; build 188 verified another unverified
  entry with cover/synopsis and zero published rating. No individual match or
  classification was approved. Visual inspection found provider-escaped quotes;
  the final decoder is verified for one-pass entities/literal markup on the host.
  Native screenshots stay private, not in Git.
  Both builds completed through the acquired shared Gradle gate with observed
  two workers, parallel false and 3 GiB Gradle maximum heap. Kotlin 2.2.20 used
  the already-assessed in-process strategy; required JVM flags remained. Test
  forks are configured one/512 MiB (none ran during assemble); native compile/
  link pools are configured one slot per task, not a measured total-host cap.
  No memory failure or budget increase occurred. Final APK is 223,610,227 bytes,
  SHA-256 `4c402688a0544e8a9783c4a898fcbbb504dee541dc8e9ad9384950d6dbe6e7a3`,
  package `com.darkaxt.rshop.debug` v1.7.0/code 12, same debug signer. Verified
  install -r preserved app data; config SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both screens are committed OFF. Same pending root generation 1/next 2 reached
  140,365 observations / 11,756 pending folders; no source remap or restart was
  requested. ROMs/saves/cloud originals/FolderSync are unchanged; no release.
  Superseded diagnostic jars/compiler intermediate were transactionally removed
  (12,902 host bytes) and corresponding task-only device captures/probe removed.
  A second reviewed transaction removed the superseded 1,554,629-byte host
  screenshot; the final native preview, build logs and reproduction helpers
  remain available. No user files were cleanup targets.
  S7 is the sole ACTIVE stage; full ranking, reviewed execution/adoption and
  actual migration remain unfinished. S8-S10 are NOT STARTED.

### S7 restart-safe byte observations — 2026-10-06

- Successful exact local/cloud checks now append bounded validated evidence to
  the existing private journal only after native read closure. Database 36 adds
  the observation table/index without rewriting cache, metadata jobs, transfers,
  ownership or removal records. Lookup is exact account/source/file/root/path,
  bounded and offline. Past checks are not current verification, format recovery,
  adoption, ranking evidence or deletion authority. No title-specific rule exists.
- Focused runtime/dialog/persistence and affected migration/journal checks passed;
  scoped analysis passed. Actual production v35-to-v36 upgrade, database reopen,
  failure/cancellation drain and account/path isolation were exercised. Existing
  synthetic downgrade fixtures needed removal of a newer index before dropping
  its column; another assertion was corrected to accept SQLite's observed valid
  indexed plan while still proving the required index and unchanged rating facts.
  No production fallback or full-suite run was introduced.
- Build 186's normal Thor UI verified the existing 20,131,764-byte RVZ against
  cloud version 2 at 2026-10-06 07:18:55.561600, then a process restart retained
  the same observation. Reopening showed "Past byte match" and "not rechecked
  now", with no current-success claim. Independent local SHA-256 remains
  `0d7aeb487d665ce3fceffc25ea8041afeffe44faf223640e84f5f8dcb4f2578f`.
- Build 186 completed through the acquired host-wide Gradle gate: observed two
  workers, no parallel project execution, 3 GiB Gradle heap, assessed Kotlin
  2.2.20 in-process sharing that budget. Required JVM flags remained; test forks
  are configured one/512 MiB (none ran in assemble), native one-slot pools are
  configured rather than a measured total-host cap. No memory failure/increase.
  Signature-checked install -r preserved data; no release occurred.
- Existing default-account authorization was restored through normal UI after
  APK update/restart, without saving or remapping a source. The same root scan
  resumed, reaching 138,771 observations / 12,099 pending folders, generation 1 /
  next 2, unpublished. PS1 50 and linked artwork 53 remain completed. Config
  SHA-256 remains `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Both displays are committed OFF. The reviewed task UI dump was removed; current
  APK/build log remain verification evidence. ROMs/saves/cloud originals/FolderSync
  are unchanged. S7 remains the sole ACTIVE stage; full ranking coverage, strict
  reviewed execution/adoption and migration are unfinished. S8-S10 NOT STARTED.

### S7 reusable current local/cloud byte verification — 2026-10-06

- Normal Drive details now expose an explicit "Check local/cloud bytes" action.
  Opening it performs no network work. Verification pins the exact native local
  file, streams both local and current rooted Drive bytes, revalidates cloud
  identity/version before and after, then rereads and rechecks local identity.
  Cancellation and disconnect await read closure. No new copy, transfer journal,
  installed claim, adoption or deletion is created. No title-specific rule exists.
- Focused runtime/dialog contracts and scoped analysis passed. Native testing
  exposed the published-read protocol's required durable offset equal to file
  size; its fixture was tightened to reproduce the failure before correcting the
  caller. Corrupt bytes, changed version/namespace, same-size overwrite, missing
  files and joined cancellation are covered. No full suite was run.
- Normal Thor build 185 verified the existing 20,131,764-byte RVZ against current
  cloud version 2. The independently observed local SHA-256 before/after agrees
  with the app's full comparison:
  `0d7aeb487d665ce3fceffc25ea8041afeffe44faf223640e84f5f8dcb4f2578f`.
  A second actual running comparison was cancelled with controller B and returned
  to normal details. Default-account authorization was restored through normal
  UI without saving a new source, mapping or scope. This is current byte proof,
  not durable migration/removal authority or completed format-specific recovery.
- Builds 184 and 185 ran sequentially through the acquired shared Gradle mutex.
  Observed workers=2, parallel=false, Gradle heap=3 GiB; assessed Kotlin 2.2.20
  ran in-process within that heap. Existing metaspace/code-cache flags remained.
  Test fork=1/512 MiB and native one-slot pools are configuration evidence, not
  a measured total-host cap; no forked test JVM ran in assembly. No memory-related
  failure or budget increase occurred. Signature-checked install -r preserved data.
- PS1 metadata job 50 completed its existing 405 entries; linked artwork 53 also
  completed. Root generation 1/next 2 continues at 137,544 observations / 12,466
  pending folders, still unpublished. Both displays are committed OFF and config
  SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  ROMs/saves/cloud originals/FolderSync remain unchanged. S7 remains the sole
  ACTIVE stage: complete collection/ranking coverage, strict reviewed execution
  journal and actual migration remain unfinished. S8-S10 are NOT STARTED.

### S7 exact artifact-to-retention review — 2026-10-06

- The existing private read-only migration audit now joins exact normal-cache
  artifact keys to the unchanged shared canonical ranking SQL. It reports
  keep/preserve observations, outside-sample candidates, edition/member IDs,
  file/byte counts and distinct bound game counts. No title-specific exception,
  adoption or removal capability was added. Cached byte identity and a lower
  rank never grant deletion authority; every existing recovery/save/sync and
  execution-time revalidation gate remains. Per-page observations are explicitly
  not an atomic execution snapshot; changing summaries, incomplete pages and
  conflicting bindings are rejected or preserved rather than guessed.
- Focused audit contracts passed, including actual native SQL/key joins, dirty
  and incomplete rankings, conflicts, canonical member counting, exclusive
  journal creation and footer semantics. The updated READONLY helper compiled
  and executed on the Thor; host/device SHA-256 agrees. No Gradle build, APK
  installation or full-suite run occurred. javac/d8 used requested 256 MiB
  budgets; the running audit's observed Python peak working set was 33,107,968
  bytes. No memory-related failure or budget increase occurred.
- Real N64 review completed and independently reconciled its terminal footer:
  322 exact paths / 3,267,753,332 bytes, 320 matching cached digests and canonical
  bindings, two preserved non-ROM files. Every path remains preserve and every
  row has removalAuthorized=false. Current projection dirty counts and zero
  ranked games prevent a defensible sample. This is not live cloud recovery,
  an executable removal manifest, adoption or finished migration.
- Normal saved-job UI confirmed GameCube 51 completed all 206 lookups and its
  linked artwork 52 completed. Selecting PS1 50 and Resume continued its original
  405-entry snapshot, reaching 274 requested / 133 pending / 272 processed. Root
  Refresh continued generation 1/next 2 at 135,665 observations / 13,062 pending
  folders without recreating the source or scope. No individual game was curated.
- Transactional cleanup removed only the reproducible 8,223-byte helper class
  and its empty compiler directory. The private review and helper jar remain
  needed by S7. ROMs/saves/cloud originals/FolderSync remain unchanged; S7 is
  the sole ACTIVE stage and S8-S10 are NOT STARTED.
- Final observation confirms both displays OFF, unchanged config SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`,
  the same root at 135,824 observations / 13,002 pending folders, and PS1 50
  running at 293 requests / 114 pending / 291 processed. The task UI dump was
  removed. No required migration criterion is declared complete by this review.

### S7 standardized filename region capture — 2026-10-06

- The normal catalogue snapshot dropped explicit filename region tags: a
  focused reproduction for `(Europe)` observed region=null. New captures now
  use a single unambiguous filename tag as a provider lookup hint. Explicit
  release facts and manually cleared regions win; multiple/conflicting regions,
  folder labels, absent evidence and bundles do not become guessed facts.
  Capture leaves identities, classification and score eligibility unchanged;
  existing jobs retain their saved requests. No title-specific exception exists.
- Focused catalogue, persistent-job and ScreenScraper adapter checks passed;
  scoped Dart analysis reports no issues. The existing bounded large-snapshot
  contract completed with a measured 228,442,112-byte peak RSS, not an unbounded
  test process. One host test workload ran at a time; no full suite was run.
- Build 183 succeeded through the shared supervising gate, workers=2,
  parallel=false, observed Gradle heap=3 GiB, preserved metaspace/code-cache
  flags and assessed Kotlin 2.2.20 in-process configuration. Test fork=1/512 MiB
  markers are configuration evidence only; native one-slot pools are configured,
  not a verified total-host cap. No memory failure or budget increase occurred.
- The APK signature/digest were checked before update; normal `adb install -r`
  preserved package/data. PS1 job 50 was explicitly paused at 259 requests / 147
  pending; its 405 captured requests still have no region hints. Root generation
  1/next generation 2 and the exact config digest survived the update. Normal
  default-account connection restored Drive access without saving a different
  folder or modifying config; Refresh resumed the same pending root.
- Actual normal GameCube job 51 captured 206 entries: 172 region hints (162 us /
  ten jp), all with empty assigned edition regions. Its first seven completed
  lookups returned six needs-review / one ambiguous / zero ratings. This proves
  the shared hint reaches real saved work, not reliable ranking or automatic
  approval. It remains running; resume saved PS1 job 50 after it completes.
- Root advanced to 135,175 observations / 13,228 pending folders after update.
  Both displays are OFF. ROMs/saves/Drive originals/FolderSync were not modified.
  S7 remains the sole ACTIVE stage; S8-S10 remain NOT STARTED.

### S7 automatic PS1 breadth and indexed classification — 2026-10-06

- The normal ScreenScraper settings selected psx and began saved job 50 on the
  stable 405-entry scope. The same live app PID 13676 reached 57 processed /
  348 pending: 29 need review, 22 ambiguous, six unmatched, zero matched/rated.
  This is running automatic coverage, not finished matching or defensible
  reception. No individual title was reviewed or corrected. The collection
  generation also continued without replacement: 133,041 observations / 13,921
  pending folders, still unpublished generation 1 / next generation 2.
- A reproducible scalability defect in snapshot classification scanned pending
  catalogue entries per artifact. The actual SQL's observed work grew from 59
  to 60,039 SQLite VM steps after adding 20,000 unpublished entries. Iterating
  published state first now probes the existing scope/generation/file primary
  key; no extra index, schema migration or identity exception was introduced.
  The same fixture observed 61/41 steps before/after expansion. Scope, published
  generation and ambiguity semantics remain covered by focused host checks.
- The focused catalogue-job, LibraryStore and Drive-catalogue checks passed;
  Dart analysis reports no issues. Normal debug build 182 succeeded under the
  actual shared gate, with workers=2, parallel=false, Gradle heap=3 GiB and
  assessed Kotlin 2.2.20 in-process configuration. Test fork/512 MiB markers are
  configuration evidence, not executed tests; native one-slot pools remain
  configured, not an observed total-host cap. No memory failure/budget increase.
  The first build attempt ended on an incorrectly unquoted PowerShell property
  argument (`.dart` interpreted as a task); quoting it resolved the invocation.
- The APK identity/signature and digest were inspected; it is retained for the
  next safe device verification boundary, not installed over running work.
  Build evidence and digest are in the S7 reconciliation. Both displays are OFF;
  no ROM removal, cloud mutation, FolderSync change or release occurred. S7
  remains the only ACTIVE stage; S8-S10 are NOT STARTED.

### S7 standardized retention membership — 2026-10-06

- Collection-wide retention planning now shares the normal Library's canonical
  ranking SQL, source precedence, conflict rejection and stable ties. A bounded
  per-console page includes unscored members of ranked games; their membership
  does not fabricate an edition rating. No search/tag/installed filters or
  uncapped extras alter the Top-25 selection. Missing bindings or incomplete
  score coverage preserve every member outside the provisional sample.
- Focused Library query/migration/invalidation checks passed, and Dart analysis
  reported no issues. The audit's fixed READONLY native query is checked against
  the exact production SQL and its focused host contracts passed. The installed
  APK was not replaced: native evidence verifies Android SQLite compatibility
  and current data, not execution of the new Dart API in an updated APK.
- Opening the normal Library refreshed its stale projection without restarting
  the app or any provider job. Native observations then showed zero dirty rows:
  PS1 0/405 ranked canonical games, PSP 6/341, PS2 12/220 (225 members), N64
  0/1,543, GameCube 0/206 and Game Gear 0/548. All six had zero unbound artifacts;
  all remained incomplete and removalAuthorized=false. Root generation 1 is
  still unpublished, advancing to 124,117 observations / 14,130 pending folders.
- No per-game curation, ROM removal, Drive mutation, FolderSync change, Gradle
  build or release occurred. Both displays are OFF. S7 remains the sole ACTIVE
  stage; full publication/metadata coverage, defensible ranking, current cloud
  recovery and reviewed migration remain required. S8-S10 are NOT STARTED.

### S7 native cached comparison and completed PSP recovery — 2026-10-06

- Replaced the audit's raw live-database copy with a fixed READONLY native query.
  Artifacts/generations share one statement snapshot; the host checks config
  before/after and validates bounded complete JSON. The six mapped-console
  projections passed on Thor; largest was N64 at 838,891 bytes, under the 1 MiB
  transport cap. Its 836,435 artifact bytes justified a 900,000-byte input guard;
  no database-copy cap, process heap or removal gate was raised. Android's missing
  SQLite JSON functions were diagnosed and the query uses plain SQL instead.
- The corrected N64 audit exited zero and independent row/footer reconciliation
  verified 320 stable archives with matching cached size/digests (3,267,752,208
  bytes), plus two preserved non-ROM files (1,124 bytes). The first .zip-selected
  invocation was a configuration mistake on a .7z directory, not comparison
  proof; it is excluded. The correct private journal is
  `D:\Temp\rshop-s7-n64-native-cache-audit-v2-20261006.jsonl`. Every disposition is
  preserve and removalAuthorized=false. This is not current recovery authority.
- Focused host contracts, including the shipped SQL and bounds, passed. The
  helper was compiled with javac/d8 using requested 256 MiB budgets, pushed and
  verified by matching SHA-256. No Gradle build, APK update or release was needed.
  Compiled host intermediates are expendable; the device helper is retained for
  remaining S7 audit work, with its hash in the reconciliation ledger.
- Older PSP metadata 44 completed its 341 edition items with no pending work;
  its normal linked artwork 49 also completed. No replacement metadata pass or
  per-title correction occurred. Root generation 1 remains unpublished at
  92,021 observations / 14,445 pending folders, next generation 2. Both displays
  are OFF; ROMs, saves, Drive originals and FolderSync remain unchanged.
- S7 remains the sole ACTIVE stage; full collection publication/coverage,
  defensible Top-25 retention, current identical recoverable copies and reviewed
  migration are unfinished. S8-S10 remain NOT STARTED.

### S7 saved metadata history and native recovery — 2026-10-06

- Saved jobs now exposes bounded local history for the selected provider;
  a newer console refresh no longer hides older unfinished progress. Selection
  does not call providers or create a generation. Explicit Resume uses the
  selected stored job and existing linked artwork. Focused host verification
  covers keyset paging, provider/artwork isolation, pending-only resume and
  touch/controller selection; scoped analysis reports no issues.
- Normal Thor settings selected PSP job 44 behind completed PS2 job 46 with no
  new job/generation. The same generation 44 progressed from 57 pending / 284
  processed to 50 pending / 291 processed. The first attempt paused after one
  item while Drive reported interactionRequired. Default-account Connect and
  Resume restored progress; without a retained exception the first pause is
  not independently attributed beyond that observed authorization state.
  Completed results remain intact, and no individual-title corrections were made.
- Normal same-signer build 180 was installed in place; the installed APK hash
  matches 957fbddd0204c9fb453091b3fbc07c27aa3a1ee890a3d248620e559cff590698.
  Source/mapping configuration and secure-storage file hashes are unchanged.
  The shared-gate supervisor exited zero with observed workers=2, parallel=false,
  Gradle heap=3 GiB and assessed Kotlin in-process strategy. Test configuration
  is one fork / 512 MiB (not executed in assembly); app native pools are depth
  one. No memory failure/increase occurred. The acquisition field was truncated
  from the tool response and is not claimed as an independently retained receipt.
- Ordinary Refresh catalogue resumed root generation 1 after native Connect;
  next generation remains 2. Latest inspected snapshot: 89,436 observations /
  14,832 pending folders, still unpublished. Existing PS2 artwork 47 completed.
  Both Thor displays are confirmed OFF. No ROM removal, Drive-original mutation,
  FolderSync change, account registration or release occurred.
- S7 remains the sole ACTIVE stage. Full collection publication and fresh
  coverage, defensible Top-25 retention, identical recoverable cloud-copy proof
  and reviewed SD migration are unfinished. S8-S10 remain NOT STARTED.

### S7 whole-SD inventory and automatic PS2 outcomes — 2026-10-06

- The read-only native whole-SD inventory exited zero. Independent streaming
  reconciliation verified its header, 15,964 unique stable observations and final
  summary: 722,865,729,304 bytes, all preserved. The 15,053 extension-classified
  artifacts include bundle tracks; 911 other files are preserved. No cloud copy,
  hash, canonical-game ownership or removal authority is inferred. The private
  journal is `D:\Temp\rshop-s7-full-sd-inventory-v2-20261006.jsonl`.
- Android's oversized `find -exec ... +` failure is fixed with count/UTF-8-byte
  bounded stat batches and exact response verification. Focused host contracts
  pass, including long quoted/Unicode paths, missing responses and preservation
  boundaries. Only one host verification workload ran at a time.
- Normal PS2 ScreenScraper job 46 completed 225 editions: 122 matched, 32 review,
  4 ambiguous, 67 unmatched and 113 rated. Normal IGDB job 48 completed the same
  scope: 20 matched/rated, 127 review, 46 ambiguous, 32 unmatched. Neither has
  pending or failed/unsupported work. Eighteen IGDB publications are automatic
  corroborations; ten meet vote support. No individual-game correction was used.
- Normal Resume saved job resumed existing linked artwork 47. The collection
  generation remains unpublished at the observed 86,091 entries / 12,862 pending
  folders. These are not complete ranking, recovery or migration evidence.
- Both displays are confirmed OFF. No Gradle build, ROM removal, cloud mutation,
  FolderSync change or release occurred. S7 is ACTIVE; S8-S10 are NOT STARTED.

### S7 automatic breadth and independent SD inventory — 2026-10-06

- The completed normal PSP IGDB job 45 requested all 341 editions: 12 matched,
  222 review, 57 ambiguous, 50 unmatched; 11 rated. Ten accepted records use
  automatic official-release corroboration, with ten current identity bindings
  and source fingerprints. Six meet the existing vote floor. No manual per-title
  corrections or scores were introduced; this is not a defensible full Top set.
- Root collection generation 1 resumed through native default-account connect
  and ordinary Refresh catalogue, without replacing its checkpoint or changing
  the six console mappings. It reached 78,195 observations / 7,538 pending
  folders. Normal fresh PS2 ScreenScraper job 46 is running: at 51 requests,
  28 current matched/raw-identifier records and 40 header bindings are persisted;
  175 items remain pending. This verifies a standardized multi-entry workflow,
  not completed collection coverage.
- The SD audit's local inventory no longer requires copying the full growing
  database. Observed `rshop.db` is 156,856,320 bytes; the existing comparison
  reader's 64 MiB bound is deliberately not raised. `--inventory-only` reads exact
  file paths/stats with no catalogue/config read and no ROM hashing/payload read.
  It explicitly records absent cloud evidence and retains every removal gate.
  Focused host contracts pass, including unstable and non-ROM preservation.
- Real private inventories completed for PSP (169 ROMs, 129,899,079,437 bytes,
  one non-ROM), PS1 (86 ROMs, 30,900,237,652 bytes, one non-ROM) and PS2 (23 ROMs,
  45,166,984,325 bytes, one non-ROM). All 281 observations are stable and preserved;
  the terminal summaries, absent digests and empty cloud candidates were inspected.
  Journals are
  `D:\Temp\rshop-s7-psp-inventory-20261006.jsonl` and
  `D:\Temp\rshop-s7-psx-inventory-20261006.jsonl` and
  `D:\Temp\rshop-s7-ps2-inventory-20261006.jsonl`, retained for exact later
  revalidation, never published. Every disposition is preserve; no checksum,
  canonical ownership, live cloud recovery or deletion proof is inferred.
- No Gradle build, APK installation, account creation, cloud mutation, ROM/save
  removal, FolderSync change or release occurred. S7 remains the sole ACTIVE
  stage; collection publication, fresh breadth, defensible retention and reviewed
  migration are still required. S8-S10 remain NOT STARTED.

### S7 standardized cross-provider corroboration — 2026-10-06

- Removed the need for per-title manual IGDB assignments only where current,
  exact-hash ScreenScraper facts uniquely corroborate an unmodified official
  release. Title, platform, full regional date, developer and publisher roles
  must agree. Missing/conflicting facts, uncertain search completeness, modified
  editions and manual identity corrections do not auto-match.
- The normal persistent job carries a source-record fingerprint and revalidates
  it inside the publication transaction. Matching does not rewrite the source
  metadata or assign a manual game ID. Existing provenance, score support,
  canonical grouping, refresh generation and Top policy remain unchanged.
- Focused provider/worker/ownership/grouping/query regressions passed. A shared
  cache close/reopen and private projection rebuild preserves the corroborated
  record, evidence and existing eligible Top query. Changing source facts during
  lookup rejects publication. Scoped analysis reports no issues; no full suite
  or concurrent host test workload was used.
- A bounded live IGDB check used the first eight current matched records from
  the normal PSP job, not handpicked titles. Outcomes: one corroborated match,
  two needing review and five unmatched. The matched record lacks the required
  vote support, so zero ranked games and provisional coverage are correct.
  This verifies real API -> normal worker -> persistence, not full collection
  coverage or migration readiness. No individual-title workaround was added.
- Native read-only follow-up observed 110 automatic ScreenScraper matches and
  125 header bindings in PSP job 44. That job is BLOCKED on provider unavailable
  with 57 pending; its existing progress remains saved. The unpublished root
  collection generation advanced to 76,519 observations. Both displays were OFF.
- Normal same-signer debug build 179 passed and was installed in place. The
  independent installed APK SHA-256 is
  `5b8d65735af53d72c6fb74f8869db9f33b6adf5b11a99530bc6bcf9be7faf10d`;
  source/mapping configuration SHA-256 remains unchanged. The ordinary Sources
  settings -> IGDB -> PSP -> Fresh re-scrape created normal job 45 with 341
  editions. Read-only native observation at 74 requests found three automatic
  corroborated records, three current identity bindings and three source
  fingerprints; two records meet the existing vote-support floor. The job was
  still running with 268 pending. This proves native publication, not completed
  coverage or final collection ranking. Both displays were switched OFF.
- Build 179 actually acquired `Local\Darka.AndroidGradleBuildGate`, used observed
  two workers/no parallel/3 GiB Gradle heap, and retained the assessed in-process
  Kotlin strategy (compilation tasks were up-to-date). Tests are configured for
  one fork/512 MiB but were not executed by assembly. Project-local CMake options
  now give native plugin compile/link rules the same depth-one shared Ninja pool
  as the app, independently verified in generated rules for flutter_soloud and
  jni. Thus native compile/link jobs are bounded per task, not merely requested
  by an environment hint. No memory-related failure or heap increase occurred.
  Successful supervisor log: `33b3bafbe14a45aeaea70298d91d2b6f.log`.
- S7 remains the sole ACTIVE stage. Full collection publication/mapping, fresh
  metadata breadth, defensible Top-25 retention, restore and reviewed migration
  are still required. S8/S9/S10 remain NOT STARTED.

### S7 automatic CHD matching in the normal Thor job — 2026-10-06

- The shared DVD-CHD path is now wired into normal ScreenScraper refresh jobs.
  It reads exactly bytes 0-139 through the existing enabled, mapped Drive source
  and account lane, revalidating the exact artifact before and after the read.
  An ignored or incorrect range is rejected without buffering the ROM. No
  staging file, installation journal, decoded ISO or whole-ROM request is used.
- The worker atomically persists the original-ISO identifier, exact source/version
  evidence and updated job identity/lookup keys. Unchanged refreshes and shared-
  cache recovery reuse that evidence; changed bytes retire it. Manual unknown,
  explicit raw assertions, modified releases and unsupported layouts remain
  protected. A declared CHD hash is metadata lookup evidence, not integrity proof.
- Focused media/runtime/worker/controller/grouping/mapping checks passed, including
  cancellation/disconnect drain, post-read source changes, shared-store reopen,
  replacement-byte invalidation and unsupported-layout handling. Scoped analysis
  reports no issues. The bounded worker fixture joined normally with observed
  peak RSS 256,368,640 bytes; no full repository suite or overlapping test run.
- Normal same-signer debug build 178 was installed in place. Installed APK SHA-256
  independently matches
  `bd32cc038ca2918d97c29cfc8b88e1f8c211c828ca14d06784b973e7153a9daf`.
  Source/mapping configuration bytes are unchanged. The normal default-account
  connection resumed the existing collection generation and saved PSP job 44,
  not a per-game fixture. Read-only native evidence observed 35 header bindings,
  31 matched/current metadata bindings and 31 raw-identifier match methods in
  that 341-entry job. It was still running with 254 pending; these are automatic
  workflow observations, not full coverage or trusted Top ranking.
- Build 178 acquired `Local\Darka.AndroidGradleBuildGate`; effective workers=2,
  parallel=false and Gradle heap=3 GiB. Kotlin is configured in-process, sharing
  that budget; its compilation tasks were up-to-date. Forked-test settings were
  limited to one/512 MiB, but assemble did not execute those tests. Native command
  files contain no explicit Ninja `-j`; an environment budget was requested, not
  independently proven as effective native concurrency. No memory failure or
  budget increase occurred. Build 177 exited on a PowerShell-split `.dart` task
  argument before the corrected build started. Successful gate log:
  `597b76fa54004710a64c6b24c8da0320.log`.
- The same unpublished collection generation advanced to 74,498 observations;
  no traversal restart or duplicate worker was requested. Both physical displays
  were confirmed OFF. The exact task-created temporary UI XML was removed after
  inspection; the read-only probe is retained for S7 verification. No ROM removal,
  cloud write, FolderSync change or release.
- **Remaining:** full collection publication/mappings/fresh metadata, normal
  PS2 breadth, defensible canonical Top-25 retention, restore and exact reviewed
  migration. S7 remains the sole ACTIVE stage; S8/S9/S10 remain NOT STARTED.
  Earlier checkpoints below are historical, not outstanding CHD-wiring claims.

### S7 automatic raw-Drive matching — 2026-10-06

- Stopped individual-entry curation. The normal catalogue job now uses current
  Drive MD5/SHA-1 and size only for a versioned, mapped uncompressed standalone
  format. Containers, wrong platforms, missing versions/hashes and stale manual
  raw assertions are excluded. No ROM-body request is added by this path.
- A reproduced publication defect left an exact provider match's edition
  unclassified. The worker now commits explicit provider-ROM official facts,
  assigned release fields, current metadata and the item's new identity binding
  together. All five unmodified flags plus notgame=false and a nonzero MD5/SHA-1
  are required. Existing manual unknown, patch/base and modified facts win.
- The real adapter -> normal catalogue job -> SQLite -> query fixture verifies
  automatic grouping/advisory score, unchanged rename/sync, shared-store close/
  reopen and identity restoration without another lookup, and changed-byte
  invalidation. A second regression failed before generated classification was
  retired on blob replacement. Modified folder declarations also retire it;
  manual raw evidence remains stored but cannot identify replacement bytes.
- Focused provider/catalogue/worker/grouping/ownership checks and scoped analysis
  passed. A fresh real ScreenScraper lookup on two existing supported host DVD
  CHDs returned description/media and explicit official facts from otherwise
  unknown classification, reading only 140 bytes per file. No per-game IDs, full
  ROM downloads or artwork fetches were introduced. The live-tag configuration
  warning predates this change. This is real provider evidence, not native
  automatic collection scraping or a trusted Top score.
- Native installation is unchanged. A current read-only catalogue observation
  found 71,041 entries / 11,225 folders / 5,210 pending folders in the same
  unpublished generation 1, with active=null. Do not restart that traversal or
  treat observations as published games. No Gradle build/gate claim, ROM
  removal, cloud write, FolderSync action or release occurred.
- **Remaining:** normal-device integration, automatic supported-CHD extraction,
  full collection publication/mappings/fresh metadata, defensible canonical
  Top-25 retention, restore and exact reviewed migration. S7 remains the sole
  ACTIVE stage; S8/S9/S10 remain NOT STARTED.

### S7 shared original-ISO identification — 2026-10-06

- Individual-entry curation remains stopped. A bounded parser accepts the
  supported DVD CHD v5 layout from 140 bytes and extracts its declared original
  ISO SHA-1/logical size. It ignores the combined checksum and rejects CD,
  parent-dependent, malformed and unsupported layouts. This declaration is not
  verification of archive integrity. Reference: MAME `src/lib/util/chd.h`.
- A real PSP lookup succeeded with its original hash/size. A large PS2 lookup
  initially failed because the real provider returned `romsize=2147483647`
  despite the matching original SHA-1. Two large PS2 samples independently
  reproduced that cap; API documentation does not promise this behavior.
  The adapter now isolates that exact raw-ISO/nonzero-SHA-1 case as
  `rawRomSha1AndCappedSize`, keeping the true requested size. Other supplied
  hashes, platform and release evidence must agree. CRC/MD5-only, zero/wrong
  SHA-1, other bad sizes and non-ISO requests cannot use the exception.
- The positive cap regression failed before correction. Focused parser/provider,
  score ownership and real SQLite worker/grouping/query checks passed after it.
  Two exact editions group as one game and display a sourced advisory score;
  they acquire no rank. Unknown/modified classifications remain unaccepted.
  Scoped analysis reports no issues. The opt-in real-provider test passed for
  four existing host CHDs: PSP, a smaller PS2 ISO and two large PS2 ISOs, reading
  only 140 header bytes each. It returned description/media facts by hash with
  a deliberately non-game search title. No images or full ISO were downloaded.
- **Still unfinished:** automatic extraction/persistence bound to the normal
  current collection's exact artifacts and versions, then broad fresh metadata,
  defensible ranking, restore proof and reviewed migration. The parser/live
  lookup is not native automatic scraping or whole-collection acceptance.
  S7 remains the sole ACTIVE stage; S8/S9/S10 remain NOT STARTED.
- Normal default-account connection and Refresh resumed the same pending
  collection generation after interactionRequired was observed. Its subsequent
  read-only observation advanced from 66,984 to 69,114 entries, 10,283 folders
  and 5,027 pending folders, still unpublished. The existing configuration hash
  remains unchanged. No duplicate worker, ROM removal, cloud mutation, APK
  install, Gradle build, FolderSync action or release occurred. Both physical
  displays were confirmed OFF.

### S7 regional metadata correction — 2026-10-06

- The normal exact-game PS1 workflow now has real single-unverified-candidate
  cover feedback evidence: its title/platform/Needs review label appeared with
  a parsed candidate image, without publishing a score. Explicit identity and
  ordinary-release review then completed the lookup/artwork job. The normal
  details screen showed description, genre, developer/publisher, screenshot and
  a sourced advisory ScreenScraper 85/100 score. This closes the outstanding
  candidate-feedback observation, not whole-collection ranking or migration.
- Native inspection exposed a separate defect: the provider's first regional
  cover was displayed for a USA artifact while its reviewed edition had no
  region. Review did not offer a regional correction. The focused regression
  reproduced both the foreign-first cover selection and missing review control.
  Review now records an explicitly entered region in the existing atomic
  correction/retry transaction; leaving it unchanged preserves existing evidence,
  clearing it records Unknown, and invalid input creates no orphan retry.
  A filename or provider-ID choice never supplies verified regional evidence.
- ScreenScraper snapshots cover selectors for the reviewed region, falling back
  only to neutral/world art when that region is absent, or the physical-media
  fallback if only foreign art exists. Screenshots and other facts remain.
  Focused provider, normal review/controller, catalogue/retry persistence,
  artwork and durable shared-recovery checks passed; scoped analysis reports no
  issues. Normal build 176 was installed in place and its installed SHA-256
  independently matched `b618b41376fd2f1e36d9e4e705c395241faa0916a4ac363ca55a44b3fdccc271`.
  Native normal review displayed the regional field and accepted USA input.
  The subsequent save/provider/artwork result was not confirmed; the user
  explicitly redirected effort away from individual-entry walkthroughs.
  Do not claim a native regional-artwork fix from this partial observation.
  The shared provider selection and atomic correction are host-verified;
  whole-collection integrated verification remains ordinary S7 work.
- Build 176 acquired `Local\Darka.AndroidGradleBuildGate`; effective workers=2,
  parallel=false and Gradle heap=3 GiB. Kotlin was configured in-process,
  sharing that budget; required JVM flags were preserved. Test fork/heap limits
  are configuration evidence, not executed native test proof. All-plugin native
  concurrency remains unverified. No memory failure or budget increase occurred.
  The preceding build 175 exited with a PowerShell-split `.dart` task argument,
  not memory exhaustion; the corrected invocation started only after it exited.
  Successful gate log: `52051adeaa0f422487b93a7ea2d260e7.log`.
- Collection generation 1 was observed advancing at 66,984 entries / 9,405
  folders / 5,030 pending folders, still unpublished. The same counts survived
  build 176's update, as did the configuration hash; no continued traversal is
  claimed solely from this unchanged observation. Its current metadata
  artwork job 41 was completed. No duplicate worker, ROM removal, source change
  or FolderSync action was started. Both displays were confirmed OFF.
  S7 remains the sole ACTIVE stage. Subsequent verification must prove shared
  collection behavior rather than repeatedly curate one game.

### Native feedback and checkpoint recovery — 2026-10-06

- S7 remains ACTIVE; S8/S9/S10 are NOT STARTED. Normal debug build 174 was
  installed in place with `adb install -r`, without uninstalling, clearing data,
  signing out, or resetting the source. Its installed APK SHA-256 matches
  `a318cf7b1a08d56ee8dae4a982003f165da35a993a2b69db9e7581979dc75515`.
  Configuration bytes and completed N64 job 33 were unchanged across installation.
  Collection generation 1 retained all committed entries: 64,604 before the
  update, 64,616 immediately afterward. A focused catalogue recovery check passed
  before installation. No Gradle command or additional build was launched.
- The normal Connect action renewed access through the previously authorized
  default account. Exiting setup without saving preserved source settings. The
  collection source's normal Refresh action resumed the same pending generation,
  subsequently observed at 65,300 entries / 8,563 folders / 5,030 pending folders.
  This is verified checkpoint recovery and continued traversal, not publication.
- A single exact PS1 game was refreshed through normal details/settings. The
  real ScreenScraper response remained ambiguous and published no rating; the
  latest-result panel rendered its title, platform, truthful outcome and disc
  fallback. Normal cached review then distinguished the original game from its
  sequel, explicitly classified the ordinary release and rechecked the selected
  provider identity. The resulting matched panel rendered its validated parsed
  cover. Private screenshots were visually inspected; no ROM download/removal
  or cloud mutation was initiated by these metadata actions.
- The normal panel displayed ScreenScraper's actual reported daily 20,000/20,000
  remaining allowance and separate 2,000/2,000 failed-request allowance, including
  observation date/time. After image work it separately displayed local remaining
  budget 19,998, rather than misrepresenting it as a new provider counter. The
  transient initial unconfigured labels resolved after secure configuration load;
  credentials were not changed. Native unverified single-candidate image feedback
  still needs a real-provider check; host candidate/isolation/cadence checks remain
  applicable. Broad match coverage and defensible Top-25 migration are unfinished.
- Both physical displays were confirmed OFF. FolderSync, ROMs and save paths were
  untouched. Private screenshot evidence is retained outside Git. No release or
  overall completion is claimed.

### Current authoritative checkpoint — 2026-10-06

- S7 remains the sole ACTIVE stage. UI-02's latest processed-game feedback is
  integrated in normal metadata settings: a three-second display-only cadence,
  coalesced latest preview, explicit unverified-candidate label and the existing
  physical-media fallback. ScreenScraper candidate covers use one serial,
  quota-reserved authenticated image request and the existing bounded PNG policy;
  they are transient, not accepted facts or permanent cache entries. Current
  accepted covers reuse the owned cache/artwork path. No extra game search or
  preview-history store is introduced.
- Provider daily counters and their observation time are persisted additively in
  database v35. Missing fields are Unknown, never unlimited; locally reserved
  remaining budget is separately labelled. Missing later responses, reopen and
  local midnight do not invent a fresh quota observation or reset enforcement.
  Credential changes clear the displayed observation, not operational budgets.
- Focused normal-screen, worker, provider parsing, image bounds/cancellation,
  quota exhaustion, provider/job isolation, migration and existing artwork/job
  checks passed. The intentional progress-layout golden was visually reviewed,
  regenerated alone and passed a normal comparison run. Scoped analysis reports
  no issues. These are host checks; the new feedback is NOT yet verified on the
  Thor and S7 migration/ranking requirements remain unresolved.
- Required normal debug build 174 passed after FIFO gate acquisition, with
  observed workers=2, parallel=false, Gradle maximum heap=3 GiB, required JVM
  flags preserved, and the previously assessed Kotlin 2.2.20 in-process strategy.
  Test tasks report one fork/512 MiB at configuration time (not executed here).
  Native environment budget is two; project native source configures single-slot
  compile/link pools, but this incremental build does not establish effective
  concurrency for every plugin. No memory failure or heap increase occurred.
  APK identity/signature are independently verified; SHA-256 is
  `a318cf7b1a08d56ee8dae4a982003f165da35a993a2b69db9e7581979dc75515`.
  It is not installed over the ongoing collection traversal; no release occurred.
- Normal N64 IGDB job 33 completed its 1,543-item snapshot: 953 need review,
  304 are ambiguous, 286 unmatched, no pending items or accepted ratings. This
  is fresh traversal coverage, not a trustworthy Top-25 retention set. The
  collection-rooted source was observed still advancing at 62,562 entries and
  7,574 folders, with 5,043 pending folders and generation 1 unpublished. No
  restart, settings mutation, ROM removal or FolderSync action was performed.
- Reviewed golden failure captures were transactionally removed after the
  passing comparison; the tracked baseline and private migration/export evidence
  remain. The live feedback check and the rest of MIGRATE-01 are ordinary
  unfinished S7 work; S8/S9/S10 remain NOT STARTED.

### Current authoritative checkpoint — 2026-10-05

- A seventh normal read-only Drive source rooted at the ROM collection is saved,
  with no mappings and its first catalogue traversal still unpublished. Fresh
  object comparison confirms the six existing sources and every console setting
  unchanged. The N64 metadata job remains running, not blocked or restarted.
  The extra console setup serves S7's whole-collection migration, not initial
  feature proof. Final console/source settings must be privately exported and
  their import verified before any separately authorized release handoff;
  credentials/consent and the shared-directory selection remain package-local.
  Existing focused Drive config checks passed, but native debug-to-release
  transfer is not claimed. Required gated build 170 passed at the two-worker,
  no-parallel, 3 GiB in-process profile without a memory failure; its verified
  normal debug APK is not yet installed over the live jobs. Both Thor displays
  were confirmed OFF. See the latest S7 reconciliation for exact evidence.

- The sixth (N64) source now has a verified published catalogue and normal
  mapping. Normal folder selection and exiting console settings persisted the
  actual SD targets for N64 and GameCube; object comparison found only those two
  target fields changed. The normal Library now contains 3,268 artifact rows:
  2,497 remote and 771 additional local rows across six consoles. These are not
  canonical-game counts or managed-installation ownership. Read-only audits
  reconciled 320 N64 archives and 80 GameCube RVZs against cached Drive sizes and
  digests; all remain preserved. N64 ScreenScraper job 31 is running, not complete;
  no additional metadata worker was started. Normal Library/details navigation
  refreshed the dirty PS2 projection and verified the second reviewed PS2 score
  (90.2/100, 28 IGDB user ratings); both reviewed PS2 projections are eligible.
  Whole-collection coverage, canonical ranking and migration remain unfinished.
  No ROM removal/adoption, cloud write or FolderSync action occurred.

- S7's recorded reception assessment now extends the existing IGDB community
  basis to N64/PSP, retaining exact current identities and the twenty-vote floor.
  Live public capture and offline production-query verification passed; the
  unsupported/sparse Game Gear sample remains unapproved. The focused boundary
  fixture failed before the change and passed after it, and scoped query checks,
  analysis and diff checks passed. This is host-verified, not yet installed on
  the Thor: the current native APK is unchanged while N64 job 31 runs. Native
  integration remains ordinary unfinished S7 work, not a stage-completion claim.
  Both physical displays were confirmed OFF while that same job advanced.

- While extending S7 coverage, native source-name entry exposed application
  search/favorite shortcuts intercepting typed letters. The two Drive setup
  fields now use the existing folder-mapper text-input protection. The regression
  failed before the fix; focused setup/mapping checks and analysis passed. Gated
  build 167 acquired the shared mutex, used the observed two-worker/no-parallel/
  3 GiB in-process profile and passed without a memory failure. Native entry now
  retains the full console name. The in-place update preserved source/console
  configuration, secure credentials, all 29 terminal jobs and metadata records.
  A sixth source was saved through the normal N64 folder picker using the same
  read-only account/client; all five prior sources and console objects remain
  unchanged. Publication and mapping were subsequently verified as recorded
  above; the five-console scope below is earlier evidence, not the current count.

- S7's fifth normal Drive source/mapping and SD restore target now cover PS2.
  Its first catalogue generation published 1,482 observations/463 folders,
  preserving the prior four source/console objects. Stable cached scope is
  1,106 remote plus 547 local rows across five consoles, not reviewed canonical
  membership. The PS2 read-only audit completed: 23 exact SD artifacts match
  cached Drive size/digests and one non-ROM is preserved; no removal is authorized.
  Fresh ScreenScraper job 25 paused before lookup when hotel access expired.
  Normal Android portal authorization restored access and one Resume saved job
  action resumed the same 225-row job. ScreenScraper and the subsequent IGDB
  pass both completed that scope; unresolved matches remain unpublished.
  A normal exact-game IGDB review exposed an unchanged-evidence ordering defect
  during Home sync. The focused fix passed regression checks and native build
  166; a fresh one-game lookup now retains its rating and ranking eligibility
  after the same Home sync. Canonical membership/ranking and migration remain
  unfinished.
  See S7_ACCEPTANCE_RECONCILIATION.md. No FolderSync action or S10 implementation
  occurred; focused tests, not the full repository suite, verified this fix.

- Revision 7 records the user-authorized S10 emulator save/save-state backup
  feature. S10 is NOT STARTED; S7 remains the sole ACTIVE stage and S8/S9 remain
  NOT STARTED. FolderSync must stay installed with its existing configuration.
  Backup writes will require a separate explicit native setup/consent and exact
  backup-file boundary; ROM access remains read-only. No backup implementation,
  additional OAuth grant, save upload or FolderSync sync is claimed. Overall
  completion now requires S1-S10 reconciliation, not just the earlier stages.
  The follow-on user instruction makes most installed emulators the coverage
  target. Full package discovery was read-only; it neither proves save access nor
  authorizes uploads. S10 must reconcile forks/embedded cores and verify every
  accessible route, with evidenced limitations rather than skipped investigations.

- S4 closure is committed locally as `145b5a3`. S6's current source/provider/
  queue/migration and details/artwork checks are recorded in
  [S6_ACCEPTANCE_RECONCILIATION.md](S6_ACCEPTANCE_RECONCILIATION.md). A reproduced
  async RA-cover error now stays inside its existing failure handler; the details
  fixture correctly forwards artwork and joins real IO without fake-clock waits.
  S6 is now COMPLETE: the normal Thor workflow independently gathered fresh
  metadata/artwork, installed one authorized game on an isolated SD destination,
  booted Dolphin online/offline, removed only the owned ROM and re-downloaded it
  while preserving metadata and saves. The source editor's misleading setup
  heading was corrected and verified with real connection state.

- S0, S1, S2, S3, S4 and S5 are COMPLETE against their assigned criteria.
  S4's current requirement-by-requirement closure is in
  [S4_ACCEPTANCE_RECONCILIATION.md](S4_ACCEPTANCE_RECONCILIATION.md): normal
  refresh/artwork/offline rendering, durable shared rebuild, actual permission
  denial/regrant and expendable-package reinstall, exact ES-DE publication/reuse,
  supported score semantics and bounded query/resource evidence are verified.
- S6 is COMPLETE with no remaining assigned acceptance, blocker or tracked
  deferral, committed as `ea63586`. S7 is now the sole ACTIVE stage. S8 and S9
  are NOT STARTED. S7's normal fresh ScreenScraper and IGDB traversals completed
  against the stable 316-entry GameCube/Game Gear catalogue, with explicit
  unresolved outcomes and a normal reviewed recheck. This is not yet whole-SD
  coverage. A third PSP-only source completed its read-only catalogue traversal
  and normal mapping; the Library now opens with 585 artifacts after a 1919 ms
  cold launch. The earlier source addition preserved existing settings; subsequent
  normal configuration now saves PSP and Game Gear's actual SD restore folders,
  with only the two target fields changed. This does not adopt existing files.
  Exact reviewed
  migration, eligible membership and remaining console mappings are unfinished;
  no ROM removal has begun. See S7_ACCEPTANCE_RECONCILIATION.md.
  PSP's normal ScreenScraper pass now also completed with 269 explicit unresolved
  outcomes and no accepted scores. The private exact Game Gear audit journal
  records 180 cached cloud digest matches, protects all files and is not removal
  authority. Explicit published Drive folder declarations now reach catalogue
  editions, lookup requests and the normal Library filter, with provenance and
  manual corrections preserved. Native PSP scope plus T-Eng displays 96 matching
  artifacts; this does not establish canonical-game membership or trusted scores.
  The first native attempt exposed Android SQLite's missing JSON1 extension;
  the exact encoded source/account lookup now uses core SQLite and the corrected
  normal refresh starts successfully. No later stage has been opened.
  PSP's IGDB Fresh pass also completed with explicit unresolved outcomes; two
  normal reviewed rechecks preserved the unrated PSP port and advisory ten-vote
  score distinctions. The private PSP audit finished with 169 cached size/digest
  matches; none authorizes removal. PS1's first catalogue generation published
  5,162 observations, including 1,336 folders. Its normal PS1-only mapping and
  SD restore destination are now saved. Normal ScreenScraper job 20 has now
  completed all 405 PS1 rows: 214 need review, 136 are ambiguous and 55 unmatched,
  with zero accepted/rated results. Its artwork job 21 completed with zero items.
  Stable device-before/device-after/host database digests agreed and quick_check
  passed. This scope includes 319 remote artifacts and 86 local rows; completion
  of traversal is not canonical membership, a defensible ranking or S7 closure.
  The independent normal IGDB job 22 also completed those 405 rows: 233 need
  review, 135 are ambiguous and 37 unmatched. Two normal exact reviews/rechecks
  then accepted supported community ratings, without borrowing a different
  platform or critic/overall score. The reproduced cached-review context gap is
  now fixed and verified on the Thor: original filename/folder/disc/patch labels
  accompany the cleaned title, while stale candidates remain blocked. The normal
  in-place update preserved configuration, secure credential fingerprints,
  completed jobs, reviewed ratings and Library membership. Gated build 165 exited
  zero with observed workers 2, no parallel projects and Gradle 3 GiB; Kotlin is
  assessed in-process sharing that heap. No memory failure or heap increase.
  Its earlier attempt failed from reproduced PowerShell argument splitting, not
  memory pressure. Focused regression/backend checks and scoped analysis passed;
  no full suite was run. These outcomes do not complete S7's retention/migration.
  A reproduced mapping-screen overflow/ANR was traced to repeated all-folder
  dropdowns and corrected with one searchable, lazy picker. The same native
  source now scrolls, clears the unrelated PSP suggestion and saves normally.
  The Library exposes 904 remote artifacts and 524 additional local rows;
  these are not reviewed canonical games or managed installations.
  These observations do not close S7's whole-collection, retention
  or recovery criteria. See S7_ACCEPTANCE_RECONCILIATION.md for the boundaries.
- B7's alternative owner-directed reconstruction is verified and its operational
  blocker resolved. The seven historically lost private files are not recovered,
  and the failed preservation attempt is not retroactively passed. Normal APK
  cold launch reaches the 183-record Library with persisted setup/credentials;
  current in-place updates preserve private fingerprints except shader cache.
  B8 handoff and the actual shared-permission criterion are resolved.
- Current focused verification: `ff42bc` / `069831` passed its backend/widget
  checks but exited nonzero from missing cover-fixture font-cache configuration.
  Corrected cover-only `4adc91` / `c6658c` passed the normal console/Library/shelf
  refresh-to-decoded-artwork and offline-restore workflow. Final catalogue/job/
  quota/grouping/score/store checks `5b4c68` / `64e0ba` exited zero. Scoped analysis
  `e2a8df` / `726ad5` has no errors/warnings, with two existing deprecation infos.
- No new Gradle command was needed for S4 closure. Subsequent normal S6 ticket
  145 held the shared mutex through exit zero: observed workers 2, parallel false,
  Gradle 3 GiB, assessed Kotlin in-process sharing that heap; configured tests one
  fork/512 MiB (not executed), app native pools one. Full plugin native concurrency
  is not claimed measured. No memory failure or budget increase occurred.
- Historical owner normal S6 APK `d9563f4` cold offline launch reached
  the Library in 2350 ms. All 37 inspected private files retained hashes before
  launch; the separately read app_flutter configuration exactly matched its
  pre-update source/mapping/target object. No uninstall or secret re-entry occurred.
  Both physical Thor screens were verified OFF. Expendable task screenshots,
  synthetic save fixture, UI XML and superseded APK were cleaned. The authorized
  normal test installation and current APK remain. S7's provider traversals cover
  the earlier two-console generation; no whole-collection scrape, SD migration
  or external release has occurred. The overall plan remains incomplete: S7-S10
  must still satisfy their own criteria. The reported logo hang was not reproduced;
  no historical root cause or speculative startup fix is claimed.
- The current normal mapper-fix APK is installed in place with the same package
  and signer. The final cold launch took 2635 ms and controller navigation opened
  the 1,428-row Library. The first in-place update preserved 37 inspected private
  file hashes; the final update preserved all 29 files in its own pre-update
  inspection and the separately checked configuration before first launch.
  Tickets 148, 149 and 151 held the shared Gradle gate through exit zero with observed workers
  2, parallel false and Gradle 3 GiB; assessed Kotlin 2.2.20 ran in-process in
  that heap. Test forks were configured one/512 MiB but not executed; app native
  pools were one and unchanged plugin native tasks were up-to-date. No memory
  failure or budget increase occurred. Detailed scope and evidence are in S7's
  reconciliation; this does not claim the earlier intermittent logo issue fixed.

### Historical checkpoints

The following checkpoints retain their original observations and stage states.
They do not supersede the current authoritative checkpoint or reconciliation
ledger. Failed attempts remain failed; later verification is identified explicitly.

- Latest checkpoint (2026-10-05): actual Android permission denial/regrant,
  process restart and expendable-package reinstall now pass against the
  permission-aware shared IO implementation. Shared files stay unchanged,
  denied strict IO fails and private cached facts remain readable. A fresh
  Thor normal-controller publication/artwork/offline rebuild passes. The normal
  owner APK is restored in place and a further cold launch reaches the real
  183-record Library; current private data was preserved. Both physical screens
  are OFF. S4 remains the sole ACTIVE stage for final source/specification
  reconciliation, not for the now-verified permission gap. Chronological entries
  below retain their historical states and do not supersede this checkpoint.

- Current normal-owner reconstruction checkpoint (2026-10-05): the normal
  `lib/main.dart` APK passes a fresh Thor cold launch and renders 182 rooted
  remote Game Gear records plus the existing local GameCube record. The saved
  Game Gear mapping now survives onboarding completion in the real-store
  regression. Native reconstruction saved the mapping without resetting owner
  onboarding. Shared metadata was selected through the Android picker at
  `/storage/emulated/0/ES-DE/RShopMetadata`, without replacing ES-DE data.
  Native restart exposed metadata/startup secure-storage mode mismatch; the
  corrected normal APK now reads both providers' existing credentials after
  cold launch, without re-entry. A normal one-title IGDB lookup/review/recheck
  produced fresh advisory facts, persisted in the shared namespace. S4 remains
  the only ACTIVE stage. See S4_NATIVE_VERIFICATION.md for current and historical
  evidence; normal startup does not close B7 or the remaining META-08 criteria.
- Work resumed at the user's request on 2026-10-01 after the LoLRoms work.
  The user handed over the connected Thor on 2026-10-05; isolated S4 device work is active. Google OAuth branding was completed by the
  account owner; both OAuth test clients are registered. Live provider evidence
  remains required.
- Authorized now: implementation (2026-09-08, "go ahead then").
- Feature implementation: S1 COMPLETE after actual elapsed rejection, silent
  renewal and verified normal-app/settings restoration on 2026-10-04;
  B6 connectivity was verified resolved after hotel authorization on 2026-10-04.
  The user waived live second-account verification on 2026-10-04; B3 is resolved
  by authorized scope change, not by live proof. ScreenScraper access
  B2 is resolved by the actual adapter's authenticated live lookup on 2026-10-03.
  Additional required authorization evidence is retained below. First online
  authorization, cancellation/reconnect and QA-03 release naming are verified.
  S2 COMPLETE: rooted live refresh, explicit mapping, exact cached game references
  and offline cold-start browsing are verified. S3 COMPLETE against DRIVE-04/05/06:
  verified transfer, native process recovery, bundles and owned installations.
  S4 is ACTIVE; B8 handoff is resolved by the user's go-ahead and live connection.
  META-08 native verification exposed Android's locale-table guard and missing
  SQLite JSON1 defects. Both corrections now pass the focused host checks and
  Thor shared workflow/rebuild. Native restart, actual storage loss/remount and
  expendable-package reinstall recovery also pass with inspected driver reports.
  Permission denial alone did not prevent fixture-file access on this firmware;
  that attempt is not a permission-enforcement pass. See S4_NATIVE_VERIFICATION.md.
  B7 remains an unresolved historical data-loss incident after the native verification teardown deleted the debug
  application's private state (incident below). B4 application authentication is resolved by the authorized
  dedicated Twitch app and a real review/publication/offline-consumption check.
  The representative older/newer/project reception assessment now supplies a
  scoped IGDB community basis, verified through the real worker/cache/offline
  query, including Android SQLite's reviewed production-policy workflow. The
  earlier unexplained host artwork wait is retained as diagnostic uncertainty,
  not claimed fixed. Its missing historical runtime cannot be an additional
  specification acceptance requirement. Current resource-contract verification
  and the requirement-level reconciliation remain ordinary S4 work.
  Unassessed console scopes remain advisory, not silently approved. S5 is
  COMPLETE, using verified provenance/cache/query/setup contracts. No stage is
  ACTIVE other than S4; B7 is not retroactively passed by reconstruction. Live second-account
  verification no longer blocks delivery.
  S6-S9 NOT STARTED; no parallel ACTIVE stage is opened.
- Current S4 normal artwork integration (2026-10-04): metadata refresh now owns a
  durable artwork child and normal card/details readers consume its private
  cache. Focused host/migration/normal-UI evidence `18343` and real ScreenScraper
  controller sample `4585` pass. Native normal-workflow verification remains
  complete for the synthetic provider workflow, but its teardown failed the
  protected-data restoration check. B7 prevents closure. This is not S4
  completion or the S7 entire-collection scrape. No hotspot was needed.
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
  consent, Drive API access and the required auth lifecycle are verified;
  current S1 closure evidence is recorded below.
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

### Current S4 handoff boundary and corrected workflow APK (2026-10-05)

- Previous goal turn was progress: lifecycle fixture, path-guard regression/fix,
  inspected host results and a verified gated lifecycle APK. This turn completed
  the required corrected workflow APK; it did not rerun unchanged host suites.
- Corrected shared workflow build `9ff470` / session `97867` joined exit 0,
  BUILD SUCCESSFUL in 28s. Gate ticket 121 actually acquired/held the shared
  mutex; inspected preflight proved the matching daemon idle without a connected
  client. Observed workers 2, no parallel projects, Gradle heap 3 GiB, retained
  required JVM flags. Kotlin configured in-process, all Kotlin tasks cached or
  no-source. Test tasks configured one 512m fork, not run. Generated app Ninja
  compile/link pool depth 1 per ABI; app/soloud/JNI native outputs had no work.
  No memory failure/budget increase; new-load plugin concurrency is not inferred.
- Independent package/label/v2 signer inspection and matching built/copied hashes
  passed `b85d88`. Corrected workflow APK:
  `D:/Temp/rshop-shared-workflow-corrected-20261005/app-debug.apk`, SHA-256
  `3e9e468742376563e7f40fc84ee2bec47e99fa900a272ea0f81d094edec66461`.
  Its compiled parent is `/storage/emulated/0/RShopSharedProof-20261005-workflow`.
  Both this and the distinct lifecycle APK are preserved for the requested native
  handoff. Neither has been installed or executed on the Thor.
- **S4 BLOCKED, B8 external:** META-08 requires actual Thor remote-only shared
  refresh/ES-DE publication, storage loss/regrant, restart and expendable-package
  reinstall proof. The user released the Thor; the testing availability question
  has no new handoff response. Device use cannot proceed until that response.
  Resolution: user reconnects/makes the Thor available, then inspect and execute
  the prepared native protocol, reconstruct current setup under B7, and reconcile
  all S4 criteria. Availability alone resolves the scheduling boundary, not the
  unexecuted acceptance checks or historical B7 failure. No goal-completion or
  native-success claim is made.
- No ACTIVE stage remains. S6 depends explicitly on complete S1-S5/live evidence
  and cannot start around this gap; S6-S9 remain NOT STARTED. Required work is
  neither dropped nor relabelled a tracked deferral. No ADB/device operation,
  publication or release occurred; no build/test remains running. No additional
  availability question is issued while the existing one is pending.

### Earlier S4 lifecycle acceptance preparation (2026-10-05)

- S4 is still the only ACTIVE stage; Thor remains RELEASED, with no ADB, wake,
  installation, account or SD-library operation. Local work prepares the exact
  remaining META-08 lifecycle boundary, not another stage.
- The new expendable-package entrypoint uses one APK and explicit launch routes
  for seed/restart/denial/regrant/reinstalled assertions. The shared domain fixture
  runs normal refresh, cover/screenshot publication and ES-DE mapping, records
  immutable external hashes, and keeps an independent private sentinel. Reinstall
  verification requires that sentinel/database namespace to have disappeared;
  it then republishes exact current catalogue identities and rebuilds offline.
  No fixture deletes private state to pretend Android uninstalled it.
- The host counterpart simulates remount/private loss and explicitly rejects a
  false reinstall. Initial lifecycle check `3d0d2f`/`550e7d` exited zero. Native
  analysis identified a nonexistent HttpOverrides getter; it was corrected before
  any build. No native result is claimed from host execution.
- Preparing the native workflow exposed its previous path validator rejecting
  the compiled `/storage/emulated/0/...` parent. Regression `30d412` failed; the
  first extraction also exposed host-platform normalization (`865cd7`/`ae7511`).
  The corrected common POSIX validator accepts direct internal/UUID-SD children
  and rejects library/app-data/nested/traversal paths. Path/lifecycle/normal
  controller checks passed `c89081` (exit 0); the final affected path/lifecycle
  check after closing an unexpectedly opened shared handle passed `976419`.
  Focused analysis of both native entrypoints and new fixtures passed `1e59cb`.
- The earlier `c40fa...` workflow APK is preserved evidence, not a ready corrected
  artifact: its compiled parent would fail its old guard. See the native protocol
  document for the new lifecycle sequence and required independent Android
  process/grant/uninstall evidence. Device execution, B7 setup reconstruction
  and final S4 reconciliation remain unmet acceptance, not tracked deferrals.
- Required lifecycle APK build `f86a9a` / session `52261` joined exit 0
  (`e3cef9`, BUILD SUCCESSFUL in 32s). Gate ticket 120 actually acquired and held
  `Local\Darka.AndroidGradleBuildGate`; preflight identified the reusable 8.14
  daemon idle with no client connection. Observed workers 2, parallel false,
  heap 3,221,225,472 bytes; required metaspace/code-cache flags retained. Kotlin
  is configured in-process for the assessed toolchain; all Kotlin tasks were
  cached/no-source, not a new compiler-load measurement. Tests configured one
  512m fork, none executed. Current generated Ninja compile/link pool depth is
  1 per app ABI; app/soloud/JNI native outputs had no work. Plugin recompilation
  concurrency is not proven by this incremental build. No memory failure or
  heap increase. No competing build was interrupted.
- Independent badging/signature inspection `a889ed`/`2993c2` verifies the
  `.sharedproof` package, R-Shop Shared Proof label, 1.7.0+12 and established
  debug signer. Preserved test APK:
  `D:/Temp/rshop-shared-persistence-20261005/app-debug.apk`, SHA-256
  `01dfb3655c1e721546ed8dc028262fbe27a0c934f77bbda67ff0ab3589a3e412`.
  Its hash equals both built output copies. The compiled parent is
  `/storage/emulated/0/RShopSharedProof-20261005-persistence`, reserved only
  on the future device handoff. No install/device proof occurred. APK/log are
  intentionally retained for that verification; host fixture roots auto-cleaned
  and their absence was checked. The initial guessed build-tools path was absent;
  inspection used the discovered installed 36.0.0 tools instead.

### Earlier S4 shared rebuild resource checkpoint

- S4 remains the only ACTIVE stage. The new shared rebuild fixture creates a
  real durable producer record, validates the synthetic bulk format against it,
  republishes exact remote identities under a reselected local source, and
  restores a fresh file-backed private SQLite database. It exercises the normal
  collection query and completed-record replay, not a mock restore or provider
  workload. No inherited private metadata/projection is supplied.
- The 129-edition extraction passed `da566e` / session `57679`, terminal
  `55dc04` (exit 0): 129 restored/ranked, Top 25 membership, 128-row durable
  read bound, zero network clients, 2,690 ms restore, 1,764 ms query, 480 ms
  replay, peak RSS 254,808,064 bytes. This is not the 30,000-edition result.
- The first 30,000-edition workload (`620b5a` / session `85602`) was stopped
  after identifying a fixture defect: its hand-built catalogue omitted the
  production `idx_games_system_artifact` access path, causing repeated identity
  table scans. No timing/completion result from that run is accepted. Only the
  exact confirmed test process was stopped; its launcher was joined to terminal
  exit 1 (`4404fe`) before another test began. This was defect-driven cancellation,
  not a timeout or memory failure. Its owned fixture is retained for reviewed
  cleanup; no user or device file was involved. The preceding interrupted-context launch's result was
  unavailable; the absence of its processes was confirmed before the inspected
  129-edition run. No success is inferred from that missing output.
- The corrected fixture installs the same partial unique catalogue indexes as
  DatabaseService and asserts the actual artifact query plan uses that index.
  Its host observer now dispatches real SQLite through the established
  databaseFactoryFfiNoIsolate method, retaining real transactions/results and
  row/request measurements without isolate message overhead. This is host
  SQLite evidence, not a native transport result or a claimed B5 stall fix.
  Corrected 129 extraction `16f090` / `d779f1` restored/ranked 129 with 128-row
  bounds and zero clients: restore 1,764 ms, query 1,187 ms, replay 302 ms,
  peak RSS 249,835,520 bytes. The same workload exposed the added ES-DE fixture
  opening the same in-memory database twice; those facts/artwork assertions were
  not accepted until producer and rebuilt projections used separate file-backed
  private databases. The corrected normal controller/recovery checks passed
  `53d0f9` / session `35419`, terminal `2bd1e3` (exit 0), including zero repeated
  lookup/body requests and unchanged unrelated controller contracts.
- The corrected full-size workload `70071` (`b7cf94`) was joined to terminal
  exit 0 (`344fae`): 30,000 restored/ranked, Top 25 membership, 128-row durable
  reads, maximum one identity row, zero network clients, 2,942,474 acknowledged
  SQLite operations. Restore took 374,756 ms, query 133,924 ms, replay 51,939 ms,
  total 576,506 ms; peak process RSS 330,465,280 bytes. These are measured host
  costs, not completion deadlines, native timings or a memory-cap guarantee.
  It proves full-size correctness/bounds for the pre-optimization implementation;
  changed catalogue-capture behavior below requires its own current measurement.
  A preceding filter-argument mistake (`5147a0` / `70c1f5`) ran no
  tests and is not verification. Focused analysis of the five new/affected
  fixture/native paths and diff check passed `58cd0d` with no issues.
- A focused native shared workflow entrypoint is prepared, reusing the normal
  controller/ES-DE contract with an Android database factory and a newly reserved
  external fixture parent. It also checks private rebuild/artwork recovery and
  never uninstalls the valuable owner package. Host verification of the added
  recovery assertions now pass on the host; native execution is still pending. The entrypoint
  itself is not acceptance evidence. See S4_NATIVE_VERIFICATION.md.
- No ADB or Gradle command occurred; the Thor remains RELEASED. The gate/profile
  have not been exercised. Native permission/regrant/persistence, B7 setup
  reconstruction and S4 reconciliation remain required; S6-S9 are NOT STARTED.

### S4 unchanged-catalogue capture and safe native packaging (2026-10-05)

- Investigation of the shared rebuild/query path found catalogue capture always
  replaced identical artifacts/game/edition rows and reindexed their canonical
  claims, even when restore had already built the exact current identities.
  SQLite trigger observation reproduced these redundant writes in `fd2135`
  (exit 1). The preceding fixture compile failure `c88665` is not that red.
- Catalogue capture now compares exact persisted rows inside the existing caller
  transaction. Identical rows do not write or reindex; actual content/identity
  changes retain the previous correction and component-invalidation path. It
  preserves raw tag bindings, reviewed matches and fresh-job membership; it does
  not skip new provider generations or completed/current-content validation.
- Targeted regression passed `02d802` (exit 0). The affected catalogue/store/
  query/shared-store checks and 129-edition recovery passed `222406` / session
  `26692`, terminal `3d6020` (exit 0), including reselected sources, multi-member
  base relationships, changed-content rejection and rank-before-filter behavior.
  The 129 measurement restored/ranked all entries with zero clients and 128-row
  bounds: restore 1,156 ms, query 243 ms, replay 171 ms; total 2,703 ms, peak RSS
  179,228,672 bytes. Different process baselines preclude claiming a measured
  full-library speedup from this extraction alone.
- The changed-source full-size check `82953` (`eecb4c`) was joined to terminal
  exit 0 (`e5683b`): 30,000 restored/ranked, Top 25 membership, 128-row durable
  reads, at most one identity row, zero network clients, 2,342,475 acknowledged
  operations. Restore took 250,837 ms, query 46,375 ms, replay 49,884 ms,
  total 355,480 ms; peak process RSS 260,501,504 bytes. The same host fixture's
  query cost fell from 133,924 ms and total from 576,506 ms. Actual correctness
  assertions, not elapsed-time thresholds, determine completion. Native timings
  and permission/persistence evidence are still outstanding. Selected analysis
  and diff check passed `4b0811`, with no issues in the five affected Dart paths.
- New shared native fixtures are restricted to opt-in debug package
  `com.darkaxt.rshop.sharedproof` (`-PrshopSharedMetadataProof=true`). They reject
  the valuable `.debug` owner app. Default debug/release identities are unchanged.
  Native packaging passed the shared build supervisor: session `55834`
  (`32e263`), ticket 119, joined to exit 0 after `BUILD SUCCESSFUL`. The returned
  supervisor result confirms gate acquisition and verified Gradle workers 2,
  parallel false and maximum heap 3,221,225,472 bytes, retaining metaspace/code
  cache arguments. Kotlin is configured in-process with the existing Kotlin
  2.2.20 / AGP 8.11.1 route and shares that heap; Kotlin compile tasks were
  UP-TO-DATE/NO-SOURCE, so this incremental invocation is not a new compiler-load
  measurement. Test tasks were configured for one 512m fork but were not run.
  The generated app Ninja compile/link pool is depth 1 per ABI (`597831`);
  app/soloud/JNI native tasks had no work. The helper's two-job environment is
  not claimed as verified parallelism for plugin recompilation. No memory failure
  or budget increase occurred. The helper retired only a verified-idle different-
  version daemon through its native lifecycle; no active build was interrupted.
  This is cooperating-session exclusion, not a universal lock on Android Studio.
  No test workload overlapped the build.
- Independent APK inspection (`948911`) confirms `.sharedproof`, label
  `R-Shop Shared Proof`, 1.7.0+12 and the unchanged debug signer SHA-256
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  APK SHA-256 is `c40fa665b92932593e6998c437d23562af30d154ded73fbd31150f525ed7bb2d`.
  Its preserved copy and build log are under
  `D:/Temp/rshop-shared-native-20261005-0556/`; copy equality was verified
  (`d79df9`). The fixture parent define is
  `/storage/emulated/0/RShopSharedProof-20261005-workflow`, which still must be
  confirmed absent before authorized device use. This is a test APK, not a usable
  feature release. No install, permission change, account access or device
  operation occurred. Thor remains RELEASED; native results are still missing.
- Reviewed cleanup transaction `1553560bb3e8f176e6cd4a5f558607ee` removed only the
  cancelled invalid benchmark's synthetic SQLite/journal tree
  `D:/Temp/rshop-test-runtime/rshop-shared-resource-e0d0aead`: six exact members,
  532,751,320 bytes, terminal applied (`6d99e2`). These are reproducible expendable
  fixtures, not original wait evidence, owner app state, APKs, artwork or ROMs.
- S4 stays ACTIVE. Native shared-storage/regrant/persistence, B7 reconstruction
  and final S4 reconciliation remain required. No later stage has started.
- The verified unchanged-capture fix and its regression were committed locally
  as `1a95f4e05fd1de3e8bd21d588d8a3e6dce4610a7` (`7d5526`). Only those two
  previously clean paths were included. Existing META-08/UI work, new native
  fixtures/packaging and this ledger remain in the preserved worktree pending
  their required integration/native verification. This is not a final stage
  commit, release, push or S4 completion claim.

### S4 shared-storage failure/read separation (2026-10-05)

- S4 remains the sole ACTIVE stage. CORE-01/META-08 require a storage outage to
  preserve usable private projections, not turn a metadata dependency into a
  browsing prerequisite. A fresh remount fixture reproduced the normal card
  reader failing at shared-store open (`b88ee0`). A second assertion reproduced
  settings losing catalogue choices and committed job progress (`1657a2`).
- Normal console/Library filters, cached scores and exact details now join
  available shared recovery but retain the actual failure as AsyncError data.
  They may read the last usable private facts when recovery fails. Artwork reads
  use only the recorded root/manifest, returning missing images without creating
  a replacement cache. Refresh/publication still use the strict store/cache
  futures: no network retry, private write fallback or fabricated restore success.
- Settings retains independent catalogue/credentials/progress reads and shows a
  localized storage-unavailable/reconnect message. Selecting the same remounted
  directory does not await the failed old worker futures. The host fixture proves
  unchanged facts, absent-root preservation, same covers after regrant/reopen,
  and no additional provider lookup or artwork request.
- The widget boundary also exposed an early failed Future escaping before load
  awaited it (`2178dc`). The controller now immediately observes its owned store
  and artwork futures, without replacing them or suppressing failures from later
  awaits. The exact failed future remains reportable. The reconnect message and
  reachable ordinary shared-folder action pass the widget reproduction
  (`e4a12d`, terminal `b2c0c8`).
- Final focused store/controller/query/settings/Library/normal-cover/ES-DE checks
  passed `040043` / session `31072`, terminal `72a8e4` (exit 0). This includes
  decoded cover/screenshots and offline restore in console, Library Top and shelf
  callers, and unchanged settings goldens. Affected analysis `4f2e60` / `eca7cd`
  exited 0 with only the existing Library cacheExtent deprecation info; no errors
  or warnings. No new 30,000-edition shared-rebuild measurement is claimed.
- Verification setup correction: the first cover run lacked
  RSHOP_TEST_FONT_CACHE (`428073`); the existing isolated font-cache directory was
  supplied rather than changing product fonts. One subsequent test launch was
  mistakenly attempted while that cover run was still live; Flutter rejected it
  before tests started due to the locked sqlite3.dll (`b032ea`). The live run was
  joined to confirmed exit (`29a2ba`) before further launches. This violated the
  single-workload launch rule, is not a passing run, and did not cause a
  memory-related failure. Later launches were conditional on terminal exit.
- No ADB, Gradle, emulator, cloud mutation, ROM download, SD deletion, release or
  commit occurred. The Gradle gate/profile were not exercised. Thor remains
  released to the owner. Large shared-rebuild resource evidence, safe native
  permission/reinstall persistence and B7 reconstruction remain required S4 work;
  S6-S9 remain NOT STARTED. No blocker or deferral is waived by these host results.

## Repository baseline

### S4 META-08 field and recorded-layout checkpoint (2026-10-05)

- S4 remains ACTIVE and is the sole ACTIVE stage; the Thor remains RELEASED.
  Normal ES-DE publication now joins the cards/Top effective-score selector in
  128-edition pages. It exports only accepted current game/project scores in
  the supported 0..1 format. Low-vote extremes, stale/unassessed scores and
  original-game scores that ES-DE cannot label are not exported as edition scores.
  Rich provenance and original-game labels remain in R-Shop's records. Omission
  does not erase last-good/manual launcher facts or fabricate a zero.
- Details and ES-DE select release facts by exact edition region, independently
  of UI language/provider response order. Conflicting, invalid and insufficiently
  precise dates are not invented; full calendar dates export as YYYYMMDDT000000.
  Normal controller publication of regional dates and an independently refreshed
  IGDB community score passes, including preservation/conflict on a manual rating.
- Shared schema v6 adds an expected installation-layout receipt, containing only
  exact remote artifacts and entry/member paths. It reuses the existing normal
  transfer journal's plan without starting transfers, reading ROM payloads,
  creating ROM directories or exporting operational state. Explicit replacement
  paths and playlist graphs are supported; no guessed namespace or archive layout.
  Every dependency is checked against the current catalogue. Ambiguous plans
  block rather than choose a path; ordinary cached filenames must agree with
  their artifact. A saved expected layout survives private journal loss, without
  restoring installation/transfer ownership or claiming absent ROMs launchable.
- Evidence: behavioral red 81d94b proves mislabelled original-game score export;
  red 10056a proves rejection of a valid recorded bundle. Field/controller/query/
  store checks passed caedd5/2b44c6. Expanded entry-only/reviewed-member/single-path,
  ambiguous-plan, changed-dependency, shared-only-layout and v4/v5 upgrade checks
  passed 80b117/7990a7. The initial query check failed because its provider fixture
  reached unconfigured platform preferences (a60005); explicit fixture storage
  isolation and the exact-region details assertion pass e20894/60236c. An
  inconsistent cached rename was caught 0d3c99 and corrected at the layout's
  catalogue coherence check, not by weakening the assertion.
  Final affected publication/control/store/query/date/artwork-job/settings
  verification passed 1761dd/1b69e8, including unchanged settings goldens.
  Full affected-item analysis passed 2dea13/3d6366 after fixing brace-style
  diagnostics; no production/test compiler failure or memory failure remained.
- These are host fixture results, not live Thor/ES-DE/provider acceptance. Still
  required in S4: native shared-storage loss/regrant/rebuild/reinstall evidence
  using expendable state, B7 reconstruction, and current integrated resource
  verification. S6-S9 remain NOT STARTED. No ADB, Gradle, cloud mutation, ROM
  payload, SD deletion, release or commit occurred in this checkpoint; no memory
  failure was observed. No Gradle gate/profile claim is made (no build invoked).

### S4 META-08 normal artwork publication/reuse (2026-10-05)

- S4 remains ACTIVE, the only ACTIVE stage. Normal settings explicitly selects
  the console's actual media directory; publication writes validated cover and
  screenshot PNGs at the exact install-derived ROM-relative stem without ROM IO.
  ES-DE must remain closed. The OS lock coordinates R-Shop publishers only.
- Shared schema v5 preserves image ownership and recovery journals independently
  from XML. Manual/unowned/alternate-format images and different editions are
  conflicts. Owned partial stages and rename-before-ack interruptions recover
  from verified immutable images. A media conflict does not erase published
  facts or report the complete operation as successful.
- Normal exact-edition settings adds explicit artwork review/confirmation.
  PNG/JPG/WebP reuse validates console/edition/provider/artifact/install/path,
  records local origin/hash/import date, and leaves the original launcher-owned.
  Fresh facts still use provider lookups. Reuse is edition-scoped and never a
  fresh provider-body receipt or authority to import old scores/descriptions.
  Decode is bounded to 4 MiB / 4,194,304 source pixels before normalization to
  a single-frame cache PNG. Changed bytes/selectors/mappings cannot reuse it.
- Behavioral reds 2a8d14 (missing publication) and 836b4a (redundant body after
  review) led to the implementation. Final focused import/controller/publication/
  shared-store/settings/artwork-job checks passed cbea9f/47be09; expanded normal
  cover-plus-screenshot workflow passed 183124. v4 upgrade preserves text
  ownership/mappings; v1/v2 recovery remains verified. Native PNG/JPG/WebP decode,
  body/pixel budgets and unchanged settings goldens pass. Analysis 944a63 has no
  issues in affected code/tests. These are host fixtures, not Thor/provider proof.
- Remaining S4 work at this earlier checkpoint: score/release selectors, explicit bundle paths, native
  storage/regrant/rebuild/reinstall, B7 reconstruction and post-integration
  resource reconciliation. S6-S9 remain NOT STARTED. No Thor/ADB, Gradle, cloud
  mutation, ROM payload, SD deletion, release or commit occurred; no memory
  failure was observed. No Gradle gate/profile claim is made (no build needed).

### S4 META-08 normal ES-DE text publication (2026-10-05; earlier checkpoint)

- S4 is ACTIVE, still the only ACTIVE stage. Shared metadata schema v4 adds exact
  ES-DE mappings, pending text updates, per-field ownership and publication journals.
  Earlier v1/v2 upgrades still retain facts/artwork and bounded identity recovery.
  No credentials, ROM payloads or operational installation state are exported.
- The normal per-edition metadata screen maps the cached artifact to its existing
  configured install destination and an explicitly selected ES-DE console ROM/
  gamelist folder. The normal controller uses that mapping after fresh refreshes;
  the existing settings screen exposes pending publication with localized labels
  in all six locales. Publication requires ES-DE to remain closed throughout.
- Current host evidence proves normal remote catalogue -> provider refresh ->
  durable pending fields -> real filesystem gamelist publication, preserving
  favorites/history/custom fields and comments without creating a ROM directory,
  placeholder or installation schema. Changing the configured install root or
  exact queue filename rejects the old mapping. Publication pins the catalogue
  in a transaction and makes no provider/image requests itself.
- Journal fixtures cover prepare-before-replace, interruption during a stage
  flush, rename-before-private acknowledgement, reopen recovery, path ambiguity,
  changed identities and external edits. Manual fields remain conflicts. An
  explicit subsequent publish can rebase a previously reported changed-file/
  pending-generation preparation without overriding manual edits; missing prior
  storage or modified unowned stages cannot be converted into an empty list.
  Same-directory replacement preserves the prior XML until the prepared file
  is flushed; actual Android storage behavior is not yet verified.
- Behavioral red evidence: ce7535 reproduced an interrupted stage incorrectly
  remaining blocked, 6752fe reproduced publication under an obsolete queue
  filename, and d5cfc9 reproduced an unrecoverable changed-file preparation.
  Current focused publication/controller/shared-store/settings verification
  passed 09b92f/2a4a66. Selected changed-code analysis passed 020c63. The preceding
  compilation and incorrect nonexistent-install-table assertions are fixture/
  setup errors, not product regression evidence.
- Golden failure 846b50/5c18b7 was inspected: the new footer increased the maximum
  scroll offset by one row, shifting the progress capture while preserving the
  form geometry. The reviewed progress golden was updated; the setup golden's
  SHA256 remained unchanged. The final non-update run passed the golden and the
  closed-window/disabled-unmapped controls. Only four attributable comparison
  PNGs and their empty failure directory were transactionally removed (ddca18);
  the intended goldens and older incident/recovery evidence were preserved.
- This narrow text slice exports title/description/developer/publisher/genre,
  not yet the full score/release/media projection. Identity-validated ES-DE media
  reuse/publication, explicit bundle paths, native storage/regrant/reinstall
  proof and the post-integration resource check remain ordinary S4 work. The
  OS lock excludes cooperating R-Shop publishers, not ES-DE; the documented
  closed-writer maintenance condition is not cross-writer CAS.
- The Thor remains released, with no device use during this work. No Gradle
  command ran, so no new gate acquisition or JVM profile is claimed. One focused
  test workload at a time was used; no memory-related failure was observed. No
  cloud mutation, ROM download, SD deletion, release or commit occurred. B7 and
  the full-spec gaps remain recorded; S6-S9 are NOT STARTED.

### S4 META-08 normal shared-cache slice (2026-10-05)

- S4 remains ACTIVE, the sole implementation stage. Normal settings now selects
  shared storage and migrates current owned metadata/artwork before changing its
  saved root. Normal refresh/readers use that same root; private tokens,
  installation/transfer ownership and source settings are not exported.
- Focused host verification 84fe88 proves normal controller -> durable records/
  blobs -> cleared private projections -> exact-identity offline recovery without
  extra provider/artwork requests. It also verifies joined resume of a committed
  same-generation response, fresh-generation lookups, changed-edition/cross-account
  rejection, failed selection retaining the old root, and normal settings/ES-DE
  merge behavior. 1c0b7f additionally verifies missing-root and unrelated-database
  preservation. Selected analysis cda27e reports no issues.
- Fresh operational-database fixtures now recover reviewed single-member Drive
  identities after catalogue publication, including a re-created local source ID
  and both ScreenScraper/IGDB assignments. Account/file/content evidence is required;
  missing/changed/ambiguous inputs and current manual edits do not inherit facts.
  Normal query/cover/detail consumers join projection recovery without interrupting
  the store worker. v1/v2-to-v3 cache migration preserves facts and PNGs.
- Durable artwork response replay passes the lost-private-acknowledgement fixture;
  explicit fresh generations remain fresh. The real public ScreenScraper normal
  review/artwork/shared-cache/offline check passed initially 686e39 and again on
  current source 3aa452. Focused host recovery passed a24c9e; final controller,
  artwork, catalogue, per-system and Library checks passed 791953;
  settings/golden/Library passed 1036a0 and selected analysis passed 2f0e3e.
  Subsequent tests explicitly use --concurrency=1; no parallel tester workloads.
- v3 additionally persists exact edition/base identity snapshots, not fabricated
  base metadata. Reopened host fixtures recover a two-disc translated edition
  and its reviewed, unscraped original, including a source change only for that
  original. Changed/missing disc/base objects and newer manual base corrections
  cannot restore stale relationships. 53b11d, b85ca6/26392f and 825f69 reproduced
  the stale-base, unchanged-primary/member and independent-base-ID failures;
  production corrections pass ff09eb/e6cb5c and final reopened/manual-correction
  cases pass 8cedfd. v2 migration/reselected-catalogue recovery of 129 distinct
  editions crosses the bounded upgrade/restore page boundary (4a11c5/f9084f).
  Selected store/test analysis passed 641f43 and the final expanded fixture
  analysis passed 383242/5485e6. This is host evidence,
  not native storage lifecycle or a new 30,000-edition resource proof.
- This is not META-08 completion. Validated ES-DE media reuse,
  writer-coordinated publication and real Thor storage/regrant/
  reinstall proof remain S4 work. S6-S9 are NOT STARTED. B7 is unresolved;
  no lost prior private bytes are claimed recovered.
- Authorized native reconstruction restored normal onboarding/default-account
  authorization and selected-root Drive traversal before the device was released.
  The last inspected traversal had a committed checkpoint and was still pending;
  neither catalogue completion nor provider-credential reconstruction is claimed.
  Both displays were confirmed OFF (058b8f). No device use followed release.
- No Gradle build was launched, so no new gate/profile verification is claimed.
  One host test invocation at a time was used; the bounded runner measured peak
  RSS 274,649,088 bytes with no memory failure. No deployment/release, cloud write,
  bulk ROM download or SD deletion occurred. Golden-failure renders are the only
  expendable cleanup targets; APK/incident/recovery evidence is retained.

### Revision 6 — shared persistent metadata and ES-DE sync (2026-10-05)

- The owner requested reusable shared metadata/artwork and keeping ES-DE metadata
  current for remote games without locally installed ROMs. META-08 records the
  behavior, safety boundaries and acceptance tests; S4 is its delivery owner,
  with S6 integration and S7 full-pass rechecks. This is required unfinished work,
  not delivered functionality or a tracked deferral.
- At the time this requirement was added, facts were private in rshop.db and
  artwork in metadata-artwork; the current implementation/evidence is recorded
  in the shared-cache section above.
  Read-only Thor inspection confirmed ES-DE/gamelists and downloaded_media under
  /storage/emulated/0/ES-DE, including Game Boy gamelist and media-type directories.
  This is layout evidence, not proof of per-game identity or export compatibility.
- B7 remains recorded: the owner has no app-data backup. Existing .env.local
  credentials enable setup reconstruction but cannot restore the lost private
  database/settings bytes. No scope waiver or recovered-state claim is made.
  The new requirement does not open a second ACTIVE stage. No device/shared
  files, cloud records, credentials or settings were modified by this update.

### B7 — native test teardown deleted debug application state (2026-10-05)

- The focused native artwork workflow passed in console, Library Top-10 scope
  and manual shelf (`c67901`): normal controller -> persistent jobs -> owned
  files -> decoded cover/screenshots -> offline restore. Its private report
  records no production bootstrap, provider network socket or ROM request.
- The supervising command omitted `--keep-app-running` and used the install/
  launch route instead of attaching to an explicitly launched existing app.
  Flutter's installed `drive.dart` defaults to `driverService.stop()` on this
  route; `drive_service.dart` stops and uninstalls the package. This is a main-
  agent execution error, not an artwork/SQLite product defect. The existing
  DEVELOPMENT_SETUP.md already documents the safe direct install/attach route;
  no new timeout, retry, production fallback or speculative fix is justified.
- The normal APK was restored, but all seven previously fingerprinted private
  files were absent afterwards: database/journal, ordinary preferences, both
  secure-storage preference files, Google sign-in preferences and config.
  The freshly reinstalled debug directory contains only cache/code_cache.
  Hashes are evidence, not recovery copies. Host filename searches and bounded
  device recovery discovery found no app-data recovery archive. Android backup
  is disabled by the manifest. Exact previous-state recovery is not established.
- The restored on-device APK hash equals the retained normal APK
  `daa8b182c8f722f4e3dc75685ee346b8919bfefb1159c62af6cfce3ebdd7ffee`.
  Both retained internal/SD round-trip save files match their earlier hash
  (`ff7087`), and both actual displays are OFF. These limited checks do not
  claim that the lost private database/config/credentials have been restored.
- Blocked requirement: standing installed-data/settings preservation and the
  S4 native-workflow restoration gate. Cause: internal test-launch error;
  resolution requires a verified previous-state recovery source, or explicit
  owner direction for handling the irreversible lost state followed by real
  reconstruction verification. Reconstruction must not be called byte-preserving
  restoration or retroactively turn this failed execution into a pass.
  S4 is BLOCKED; no later stage is activated. S6 integration, subsequent native
  testing and S7 migration cannot be considered complete through this incident.
- Build ticket 69 completed successfully (`be4f97`), with the shared mutex
  actually acquired, observed workers 2/parallel false/3,221,225,472-byte heap,
  in-process Kotlin configured, and no memory-failure evidence. JVM test markers
  show one fork/512m at configuration time; this assemble ran no JVM tests.
  Native effective concurrency is not claimed proved by the helper's environment
  hints. APK package/signer were checked before installation (`79c658`).
  No external release, bulk metadata scrape or SD cleanup occurred.

### S4 resource pass and actual missing artwork integration (2026-10-04)

- Focused current-source artwork fixture session 1132 exited zero (`e927bd`):
  30,000 distinct matched selectors; 41,880 ms capture, 674,057 ms total;
  208,420,864-byte peak RSS, 65,536-byte maximum chunk, one transport, two
  immutable image bodies; database reopen/offline replay passed with no extra
  transport. VM service was absent. All 600,315 observed FFI operations returned,
  with no pending cache operation. Tester PID 88528 and loopback listener 50091
  were absent afterwards; its exact D: fixture directory was also absent.
  This does not diagnose or claim a fix for the historical wait.
- Inspection then found real unfinished normal-app integration: the only
  `createArtwork` and `MetadataArtworkCache` constructor occurrences under `lib`
  are their definitions. `MetadataControlsController._run` runs only the metadata
  phase; no artwork cache or image job is supplied. No normal consumer calls
  `MetadataArtworkCache.fileFor`; cards still consume legacy cached-cover fields.
  The previous decoded-cover fixture injected a valid file into those fields,
  proving the renderer but not refresh -> artwork publication -> consumption.
- S4 remains the sole ACTIVE stage for this META-06 integration. The compact
  normal-artwork route and acceptance are recorded in IMPLEMENTATION_PLAN.md.
  No additional feature/stage, credential setup, imagined external blocker or
  speculative fix for the historical tester wait is introduced. S5's demonstrated
  visual/filter/control contracts remain verified, but not proof of this link.
- Cleanup transaction `9b343ba3553287b726de42ebff7fb6ed` reviewed all 514 exact
  generated asset/cache entries (57,732,439 bytes), no excluded/errors. Ticket
  `70992a014985603ba370689df8e88f1e23227bcebf95503466ef2286b8b99ed9`
  is issued but not applied: these outputs remain useful for required focused
  integration tests. Clean expendable output after those checks, retaining
  original forensic/native/recovery evidence. No Gradle command ran in this check.

### S4 current-source reconciliation resumed (2026-10-04)

- S1 is COMPLETE at `68695d7`; S4 is now the sole ACTIVE stage. No later stage
  is opened. Applicable source/evidence is being reconciled after S5's v32/v33
  migrations, review-mode additions and shared query changes.
- The old B5 resolution condition demanded recovering a terminated process's
  missing async state and diagnosing its unreproduced Windows tester wait.
  That extra condition was introduced in the derived ledger, not META-06/QA-01
  or S4's authoritative acceptance. It is retired as a delivery blocker without
  changing the specification, suppressing an observed current failure or claiming
  the historical anomaly fixed. Original forensic evidence and opt-in diagnostics
  remain preserved. A current recurrence would immediately fail verification and
  require investigation, not a timeout, restart or guessed production patch.
- Current META-06/QA-01 still require bounded 30,000-game work/cache plus joined
  lifecycle and offline/recovery behavior. Relevant production schema/worker
  changes invalidate wholesale reuse of the earlier large artwork run; one
  focused current-source fixture is required. Existing inspected current query,
  migration, native ownership and real provider/reception evidence remains
  applicable where its code and conditions are unchanged. S4 is not COMPLETE.

### S1 closure: actual renewal and verified restoration (2026-10-04)

- Native PID 19140 held the initially valid token without native invalidation
  or revocation until Google's HTTP 401 at `21:48:58.810`. Native cache clear
  returned at `21:48:58.924`, noninteractive authorization completed at
  `21:48:59.578`, and real root metadata succeeded at `21:49:00.644`.
  `PASS_elapsed_rejection_noninteractive_renewal_root` followed at
  `21:49:00.645`; observer session 65017 exited zero (`7db79d`). The proof
  requires a different renewed token; elapsed time alone cannot pass.
- Restoration was verified, not merely requested: SleepManager's Wi-Fi toggle
  is checked true again, while Bluetooth/Battery Saver remain checked (`4fb8d8`).
  In-place normal APK install succeeded (`e64c88`); installed SHA-256 equals the
  preserved normal recovery APK, and all seven protected file hashes match
  (`0b24e3`). Both task-owned UI dumps were removed and a fresh display check
  confirmed both actual controllers OFF (`4d3992`). No second account was added.
- Transaction `0cc1d229a278ebeb26fb578415f13869` was reviewed, ticketed and
  applied (`24ef9f`): only two expendable proof APK copies, 266,756,648 bytes,
  were removed; four pre-existing entries were protected and no error remains.
  Proof APKs are reproducible, not recycle-bin recoverable; retained recovery
  APK/logs remain available. No additional Gradle build or test workload ran
  during the observation. Ticket 49's already verified gated low-memory profile
  remains the applicable build evidence; no memory-related failure occurred.
- [S1_ACCEPTANCE_RECONCILIATION.md](S1_ACCEPTANCE_RECONCILIATION.md) maps every
  assigned requirement to inspected evidence. S1 is COMPLETE with no remaining
  blocker or tracked deferral. S4 remains parked pending its own reconciliation;
  S6-S9 are NOT STARTED. Overall completion is not claimed.

### S1 elapsed-renewal verification resumed (2026-10-04)

- Requirement-level reconciliation is recorded in
  [S1_ACCEPTANCE_RECONCILIATION.md](S1_ACCEPTANCE_RECONCILIATION.md). Current
  remaining acceptance is the live renewal observation and verified restoration,
  not account enrollment or a new network setup. PID 19140 still returned HTTP
  200 at `10-04 21:08:40.894`; observer session 65017 remains running.

- Latest native observation start: device log time `10-04 20:58:36.507`, native
  PID 19140, terminal-code log observer session 65017 (`db3f25`). The observer
  uses that exact start marker, so earlier failed attempts cannot be mistaken
  for this attempt's result. Actual Wi-Fi is connected and both display
  controllers are OFF (`6d511e`). No elapsed-renewal success is claimed yet.
- Screen-off attempts exposed a real environment dependency: SleepManager is
  active and its Wi-Fi management toggle was checked true, explicitly labelled
  "Turn off during sleep. Restore previous state on wake." Device Wi-Fi became
  Disabled after screen-off, removing the default network and DNS. The earlier
  observations terminated `FAILED_unclassified` before expiry evidence; their
  production authorization adapter is unchanged. Re-enabling Wi-Fi alone was
  insufficient while that management policy remained enabled.
- Temporary live-test adjustment: only SleepManager's Wi-Fi management toggle
  was switched from checked true to checked false and verified (`f4f8e1`).
  SleepManager itself remains active; Bluetooth/Battery Saver/other preferences
  were not changed. REQUIRED recovery after observer success/failure/cancellation:
  wake Thor, reopen SleepManager Home/System controls, restore that Wi-Fi toggle
  to checked true and verify it; restore the normal R-Shop APK, verify protected
  hashes, remove the two task-owned UI dumps, then switch both screens off and
  verify both actual controllers OFF. No persistent settings change is intended.

- Actual live observation now started (`e2291a`, `b51938`): selecting the existing
  default account succeeded with the unchanged authorization adapter and real
  root-folder API response. The debug proof holds an HTTP-200-valid grant only
  in memory and records `START_held_grant_valid_HTTP200`. Native process 19140
  is alive; both display controllers are OFF. Renewal is not yet verified;
  only actual server rejection followed by noninteractive renewal can pass.
- The resumed gated build ticket 49/session 99901 exited zero (`ba7aa9`), with
  actual gate acquisition, safe preflight, two workers/no parallel, 3 GB Gradle
  heap and Kotlin in-process; configured test forks one/512 MiB, no test task
  executed and no memory failure. The resulting proof APK hash matches the
  previously independently inspected bytes exactly. No new account or consent
  registration was required. Normal recovery APK remains preserved for restore.
- Reviewed cleanup removed the two expendable offline-attempt APK copies
  (266,756,648 bytes) and the temporary failed hotspot probe (3,375 bytes);
  original recovery APK and diagnostic build logs remain. Resumed-build APK
  cleanup is registered in transaction `0cc1d229a278ebeb26fb578415f13869` and
  must wait until native observation is terminal and normal restoration verified.

- Hotel connectivity subsequently resolved B6 (`2ee048`): the actual default
  Wi-Fi network is VALIDATED, Google DNS resolves and a device reachability
  probe succeeds. The user authorized hotel access. S1 resumes ACTIVE with
  unchanged verification code; S4 is parked BLOCKED at B5 before that resume.
  No hotspot service, network configuration or Google-account setup was changed.

- Earlier offline attempt (superseded by the verified recovery above): native
  verification was parked BLOCKED at B6, not running.
  The Thor's current network is CAPTIVE_PORTAL rather than VALIDATED;
  `accounts.google.com` fails device DNS resolution. Selecting the authorized
  default account produced microG internal error 8/null account, reported as
  cancellation 16. No expiry observation began. The laptop has internet, but
  its hotspot service is Disabled and enabling it was denied by Windows;
  the service remains Stopped/Disabled. No hotspot or account was added.
- B6 is external and blocks only the remaining live elapsed-renewal acceptance:
  resolve with a validated Thor connection (or an available authorized laptop
  hotspot), then require actual held-token rejection and silent renewal. It is
  not resolved by an elapsed timer or another cached-token test. S1/final closure
  remains dependent on that evidence; S4 is now ACTIVE for reconciliation.
- Gated build ticket 47/session 72454 completed successfully (`35da74`): mutex
  acquired, preflight safe, two workers/no parallel, actual 3 GB Gradle heap,
  Kotlin in-process, test tasks configured one fork/512 MiB (not executed),
  native SoLoud Ninja pool depth one; no memory failure. Scoped analysis and
  unchanged formatting passed (`331098`). Proof APK SHA-256
  `C04D79BABD05EC882EF0652BE3FF98AEC2E7888D73291ADEB1AFE1090CAFD945`
  retained the existing debug package/version/signer before in-place installation.
- Normal APK was restored and its installed bytes verified (`393a6a`), SHA-256
  `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  All seven protected database/preferences/config hashes matched the pre-test
  baseline. Both actual display controllers were OFF. The task-owned device UI
  snapshot was removed; no ROM, catalogue, settings or source was changed.

- S1 ACTIVE for real elapsed-token evidence, not another credential rotation.
  The debug-only native proof adds a read-only held-grant observation: first
  establish HTTP 200, retain that token only in memory, inspect root status once
  per minute, and require Google's actual HTTP 401 before native cache clear,
  noninteractive renewal and real root success. An elapsed timer alone cannot
  pass. No revoke, scope change, catalogue/ROM request or source write occurs.
- Cancellation cancels monitoring and joins any in-flight read-only request;
  build/native verification remains unfinished. On 2026-10-04 the user explicitly
  declined second-account enrollment and waived that live test, emphasizing
  delivery of features. B3 is resolved by that scope change; offline isolation
  contracts remain required and no live second-account success is claimed.
  No account was added to the Thor or Google project. The task-owned audience
  inspection tab was closed. S4 stays BLOCKED at B5; S6-S9 remain NOT STARTED.

### S5 closure and compact service-icon proof (2026-10-04)

- S5 COMPLETE: all UI-01/UI-02/UI-03 acceptance criteria are reconciled in
  S5_ACCEPTANCE_RECONCILIATION.md. Earlier chronological statements below retain
  their then-current status. S6-S9 remain NOT STARTED; S1/B3 and S4/B5 are not waived.
- The shared card uses bundled pinned Simple Icons IGDB artwork instead of
  visible source text, retaining tooltip/accessibility/details provenance and
  text labels for other providers. No runtime favicon/network requests or score
  policy changes. Host affected checks/golden comparison passed (`fe6c0b`);
  scoped analysis passed (`fa0161`).
- Updated native driver `490d62` passed all normal console/Library/shelf cover
  replacement and independent filters/unrated paths, plus localized compact/
  large/source/transfer badge geometry. Inspected report and actual-font native
  screenshots; zero network sockets, ROM and resolved-cover requests.
- Gate ticket 43 was acquired; actual Gradle heap 3,221,225,472 bytes, two workers,
  no parallel projects, required JVM flags retained. Kotlin in-process was
  configured; compiler tasks UP-TO-DATE/NO-SOURCE. One 512 MiB test fork was
  configured but not executed by assemble; actual native Ninja pool depth 1.
  No memory-related failure or budget increase.
- Normal APK restored to exact SHA-256
  `daa8b182c8f722f4e3dc75685ee346b8919bfefb1159c62af6cfce3ebdd7ffee`;
  seven protected data hashes match and both actual display controllers OFF
  (`0da336`). Removed only this fixture's ADB forward. No release/deployment.
- Reviewed cleanup transactions `88890acbc26163be92cf9ae8f032e80c` and
  `e3ac1007bf4e1048ee79c4f4486486ea` are APPLIED, zero errors: removed
  468,366,709 bytes of rebuildable test APK/assets/cache and 709,508 bytes of
  disposable public font copies. Source/assets/goldens and private reports,
  screenshots, logs and normal-APK recovery remain; these deletions are
  reproducible outputs, not user ROMs or application data.

### S5 shared resolved-cover host proof (2026-10-04)

- S5 remains the sole ACTIVE stage. The focused normal-screen fixture now proves
  decoded cached artwork replaces Systematic fallback in console, Library and
  manual shelf callers, with the same title, sourced score and Library/shelf
  selection. Independent Hack/T-Eng/Dub/Undub/Uncensor any/all controls, genre,
  empty ranked results and ordinary unrated browsing also pass in that workflow.
  Host run `1d8518` passed; eight-file scoped analysis `d190a9` found no issues.
- The earlier fixture mounted filesystem-backed image streams under the host's
  fake-clock zone. Moving mounting/refresh and actual decode joining into the
  real-I/O zone corrected the failure without changing production behavior.
  Theme fonts are loaded from the existing public font cache before isolating
  cover storage; engine-retained fonts no longer lock copies in fixture cleanup.
  The fixture rejects HTTP before sockets and seeds only a private test cache.
- Native acceptance remains unfinished. Gated ticket 33 acquired the mutex,
  verified two workers/no parallel/3 GB Gradle heap and test configuration of one
  fork/512 MB, then failed because Flutter resolves its target relative to the
  repository root, not `android`. No APK was installed and no OOM occurred.
  The corrected quoted `-Ptarget=integration_test/resolved_cover_test.dart`
  invocation passed as ticket 35/session 61491 (`875de1`, exit 0). It held the
  shared gate throughout the confirmed wait and build. Observed two workers,
  no parallel projects, 3 GB Gradle heap, retained metaspace/code-cache flags,
  one 512 MiB test-fork configuration and app Ninja pool depth 1. Kotlin used
  in-process mode; compiler tasks were UP-TO-DATE/NO-SOURCE. No OOM occurred.
  The original quoted-path correction separately avoids PowerShell splitting.
  Normal APK recovery and seven protected device-file hashes were reverified;
  the fixture then passed native driver `022c2e` with decoded cached pixels in
  all three normal callers and independent controls/unrated paths. Inspected
  seven screenshots and the native report: zero sockets/ROM/cover-URL requests.
  Exact normal APK and all seven protected file hashes were restored unchanged;
  only its ADB forward was removed and both display controllers report OFF.
  Reviewed cleanup removed three failed
  fixture directories (1,799,787 bytes), retaining logs, normal recovery and the
  reusable host-font cache. No S6-S9 implementation has started.

- The user's subsequent compact-source request remains S5 work: replace visible
  IGDB badge text with a bundled, pinned service icon while retaining full
  semantics/tooltip/details and other providers' labels. Specification and plan
  record the authorized change. Icon decoding, layout and updated native proof
  remain required; S5 is still ACTIVE, not prematurely closed.

### S5 normal game-details native proof and acceptance audit (2026-10-04)

- S5 remains the sole ACTIVE stage. The normal dark-theme game detail screen,
  exact cached edition/provider and common Game Info path passed on Android
  SQLite (`5ef060`, exit 0). Inspected report and four actual-font screenshots
  show the same IGDB community score, raw scale/vote count/source/date, independent
  tags, pending/error/retry and exact-game refresh completion/Back. Existing ROM
  actions remain independent; no real accounts or ROM operations were involved.
- The first native fixture (`9fd5bc`, exit 1) reached every screenshot but inspected
  a null job report after prematurely pausing immediately after a tap. The corrected
  fixture settles the visible scroll, asserts the enabled button actually starts
  its owning job and joins the controller's durable completed-job event. No
  production timeout, delay, retry or refresh change was introduced.
- Host routing checks also exposed a distinct fixture cadence issue: Start
  events were 139/124 ms apart, below the existing 150 ms real-time input debounce.
  Host-only routing checks isolate that cooldown; native proof retains the actual
  production debouncer. This does not diagnose or close S4/B5's original wait.
  Affected host checks passed (`8d1be3`); three-file analysis passed (`93d4a9`).
- Corrected assembly (`34d5ed`, exit 0) held shared gate ticket 28; observed two
  workers, no parallel projects and 3,221,225,472-byte Gradle maximum heap with
  other flags preserved. Kotlin was in-process, with relevant tasks UP-TO-DATE/
  NO-SOURCE; no fresh Kotlin compiler-memory claim. Test configuration remains
  one 512 MiB fork; assemble did not execute it. Current app Ninja pools have
  depth 1. No memory failure or budget increase occurred.
- Corrected fixture SHA-256:
  `ee185f654d318831acbc9d2ddf8fbbe9671df75a9f48b63bab7f84c0c8ed5001`.
  Exact normal APK/signature was restored; installed SHA-256 and all seven
  protected DB/preferences/credential/config fingerprints match. Removed only
  its ADB forward; both actual display controllers report OFF. No release.
- Cleanup `bd271a3b949586153eabec6839a70dfd` is APPLIED: 467,054,804 bytes reclaimed,
  zero failures, only reviewed rebuildable test APKs/assets/cache. Normal recovery
  APK, source/goldens and private diagnostic reports/screenshots/logs are retained.
- Current requirement-by-requirement state is consolidated in
  [S5_ACCEPTANCE_RECONCILIATION.md](S5_ACCEPTANCE_RECONCILIATION.md). Native resolved
  cover replacement and the final independent-control/unrated UI audit remain
  ordinary unfinished S5 work. S1/B3 and S4/B5 remain BLOCKED; S6-S9 NOT STARTED.

### S5 shared-card layout and native proof (2026-10-04)

- S5 remains the sole ACTIVE stage. Regression checks reproduced independent
  source-dot/title/footer overlap, enlarged rating/achievement overlap on compact
  cards and transfer indicators painted underneath the caption. The owning card
  now measures header, transfer indicator and caption in one bounded layout;
  footer labels and capped source dots share a row. Title line count uses actual
  scaled line metrics; fonts/text scaling are not clamped. Localized installed
  labels retain their full semantics while ellipsizing in available space.
- Focused shared-card/media/Library/console host checks passed (`f1c088`, terminal
  `02fddd`, exit 0), including comparison of the inspected golden without update
  mode. After the native fixture correction, the affected layout checks and
  four-file analysis passed (`9c7a16`, exit 0). Production was unchanged between
  these results. No full-suite rerun was needed for this isolated layout contract.
- The first native fixture failed because it treated fractional glyph-selection
  boxes as the paragraph's rounded paint bounds. Tracing RenderParagraph/TextPainter
  established the measurement mismatch; the corrected assertion measures a full
  first line with the actual paragraph font, locale, scale and configuration.
  It does not weaken the visibility criterion or change production behavior.
- Corrected native driver passed (`2b31d2`, exit 0). The inspected private report
  and all eleven screenshots verify compact/large selected/unselected cards,
  six localized enlarged-label configurations, every active transfer state and
  normal console/Library/manual-shelf focus/filter/cache-refresh workflows. Real
  Android SQLite is used with synthetic data, not the user's library. All 321
  console cover attempts were rejected before sockets; Library attempted none.
  Pure fallback cards, metadata and ROMs initiated zero requests.
- Required assembly passed (`16d8a4`, exit 0); gate ticket 26 actually acquired
  Local\\Darka.AndroidGradleBuildGate. Observed two workers, no parallel projects
  and a 3,221,225,472-byte Gradle heap with other JVM flags preserved. In-process
  Kotlin shares that budget, but tasks were UP-TO-DATE/NO-SOURCE, not fresh compiler
  memory evidence. Tests retain one 512 MiB fork (not executed by assemble);
  current Ninja app compile/link pools retain depth 1. No memory failure, budget
  increase or interruption of another build occurred.
- Corrected fixture SHA-256 was
  `27829896977b5240db050aa31852bdb22ee29a6b5f7d3c23af3024fe9930d240`.
  Existing package/signature matched before installation. Restored the exact
  normal APK and verified its installed SHA-256 plus all seven protected data
  fingerprints unchanged. Removed only the fixture forward and confirmed both
  display controllers OFF; no normal bootstrap, release or real-provider scrape.
- Reviewed transactional cleanup `db59a5274ea2726d00f8396502afcd56` is APPLIED:
  475,408,117 bytes reclaimed, zero failures. Only two rebuildable fixture APK
  copies and generated test assets/cache were removed. Source assets, goldens,
  recovery APK, private reports/screenshots and logs remain. The cleanup does not
  remove user ROMs or settings and those compiler outputs can be regenerated.
- Card geometry/localization/transfer-state proof is now satisfied. S5 still
  requires final UI-01/02/03 reconciliation, including normal native details and
  bounded offline scrolling evidence. S1/B3 and S4/B5 remain BLOCKED; S6-S9 remain
  NOT STARTED. This verified checkpoint is not overall feature completion.

### S5 Sources touch/controller menus and native proof (2026-10-04)

- S5 remains the sole ACTIVE stage. Focused screen regressions reproduced dead
  touch actions/type tiles, horizontal overflow of Drive action labels, vertical
  overflow in a short landscape viewport and off-screen controller selection.
  The owning menus now use their existing activation callbacks for touch,
  bounded scrolling, wrapping labels and event-driven selected-row visibility.
  Overlay keyboard focus and cancel/return behavior remain unchanged; no source,
  authentication, catalogue or queue lifecycle changes were made.
- Four Drive action labels and three source-type hints now use the existing
  localization system in all six supported languages. Navigation hints reuse
  existing localized strings. Existing tonal/disabled styling is retained.
- Focused host menu checks and existing Sources screen regressions passed
  (`427369`); the corrected native-viewport fixture also passed on the host
  (`7384ee`). Final affected-path analysis passed (`74df8f`) and whitespace checks
  passed. No broad-suite rerun was required for these isolated menu contracts.
- The first native attempt failed because the fixture tapped an off-screen row
  and retained screenshot-conversion state across cases, although Flutter resets
  that state in each case's teardown. The actual hit-test warning and framework
  teardown established those causes. Only the fixture changed: scroll before
  tapping, and convert the screenshot surface in each case.
- Corrected native driver passed (`1b3d4c`, exit 0). Its inspected report and
  three screenshots prove normal Sources screen/notifier touch enable/persistence,
  controller wrap/scroll/cancel and restored card focus, large-text Spanish labels,
  and source-type controller scrolling plus touch routing. Synthetic config and
  mocked platform preferences isolate user data; zero HTTP clients were created.
  This is real-device UI proof, not real provider authorization or scraping.
- Both required assemblies passed with the shared named gate acquired. Corrected
  build ticket 24 verified two workers, no parallel projects and a 3,221,225,472-byte
  Gradle heap. Existing JVM arguments were preserved. In-process Kotlin shares that
  budget, but its tasks were UP-TO-DATE/NO-SOURCE, not a new compiler measurement.
  Test configuration retains one 512 MiB fork (not executed by assemble); current
  generated Ninja rules retain depth-one app compile/link pools per ABI. No memory
  failure, budget increase or interruption of another build occurred.
- Corrected fixture SHA-256 was
  `a9dee873c80f1397b9b1f4bc57904251035024254d385422ac64c9e55f5831fa`;
  package and signer matched the existing debug application. Restored the exact
  normal APK, verified its installed hash and all seven protected database/config/
  preference/secure-storage hashes unchanged, removed only the fixture ADB forward,
  and confirmed both display controllers OFF. No normal app bootstrap was launched.
- Transactional cleanup removed only two disposable fixture APK copies, reclaiming
  359,180,724 bytes with zero errors. They are rebuildable; recovery APK and private
  reports/screenshots/build evidence remain in `D:/Temp/rshop-s5-native-20261004`.
- Sources menu touch/controller/localized-action behavior is now verified. UI-01
  badge/title/localization/resource reconciliation and remaining integrated S5
  acceptance are still unfinished. S1/B3 and S4/B5 remain BLOCKED; S6-S9 remain
  NOT STARTED. This checkpoint does not close S5 or the full specification.

### S5 normal console refresh and v33 migration proof (2026-10-04)

- S5 remains the sole ACTIVE stage. The normal console fixture exposed a real
  cached-catalogue refresh failure: SQLite's outer UPSERT conflict policy overrides
  `OR IGNORE` inside invalidation triggers. Overlapping OLD/NEW edition bindings
  therefore attempted duplicate dirty keys and aborted the refresh. A minimal
  host reproduction and the new cache-UPSERT regression failed with the original
  unique-constraint error before the production fix; this is not Android-only.
- Indexed `NOT EXISTS` guards now coalesce invalidations inside the owning write
  transaction. The additive v33 migration replaces only these named triggers,
  preserving cached games, identities, metadata, jobs, shelves and pending dirty
  work. Production upgrade from reconstructed faulty v32 triggers, two reopens,
  unchanged saved rows and repeated normal `saveGames` refresh passed on both
  host and Android SQLite. No retry, exception suppression or timing workaround.
- Focused query/migration/console checks passed (`72129`). The affected legacy
  migration checks and Library workflow passed in `60147`; that workload's only
  failure was the console fixture treating host `pumpAndSettle` as background-I/O
  completion. The fixture correction retains direct real cache UPSERT assertions
  and additionally verifies the normal screen's committed sync timestamp on
  Android. One attempted fake-zone wait was stopped and its process exit checked
  before another workload; no overlapping test runs were launched.
- Corrected console and query-resource checks passed (`63856`). The 30,000-game
  query retained 128-row identity/metadata bounds; peak RSS was 261,652,480 bytes,
  and the two warm queries took 669 ms. Affected-path analysis passed (`93854`).
  Existing migration results remain applicable: production did not change after
  those checks. No full-suite rerun was needed for this isolated trigger contract.
- The gated native assembly passed (`63776`, 22 seconds): actual mutex acquisition,
  two workers, no parallel projects and 3,221,225,472-byte Gradle heap. Existing JVM
  flags were preserved; in-process Kotlin was requested, but its tasks were
  UP-TO-DATE/NO-SOURCE, not a fresh compiler-memory measurement. Test configuration
  retains one 512 MiB fork (not run by assemble). Actual current Ninja files under
  `build/.cxx/debug/334d1i5j` show depth-one `rshop_native` compile/link pools for
  all app ABIs; the older `android/app/.cxx` tree is not this build's output.
  No memory failure, heap increase or interruption of another build occurred.
- The inspected native report and four screenshots verify the normal console
  screen/provider/cache/query/card workflow: controller Top 10, touch sparse
  Top 25, console scope, independent any/all tags, no backfill after score changes,
  persisted/cleared filters, identity-preserving focus, large grid and Systematic
  media with cached score overlays. The fixture uses a synthetic Drive snapshot;
  all 321 existing cover attempts were blocked before socket creation, with zero
  metadata or ROM requests. This is not real Drive access or a collection scrape.
- Restored the exact normal APK (SHA-256 matched the recovery file), preserving
  all seven protected database/config/preferences/secure-storage fingerprints.
  Removed only the task's ADB forward and confirmed both display controllers OFF.
  Transactional cleanup removed two disposable fixture APK copies, reclaiming
  362,084,066 bytes with zero failures. Recovery APK, report, logs and screenshots
  remain under `D:/Temp/rshop-s5-native-20261004`; no release was produced.
- Console discovery and refresh are now verified against synthetic data on the
  Thor. UI-01's remaining badge/title/localization/resource acceptance and UI-02's
  Sources action-menu navigation/localization remain ordinary unfinished S5 work.
  S1/B3 and S4/B5 remain BLOCKED; S6-S9 NOT STARTED. This checkpoint does not close
  S5 or the full specification.

### S5 exact-game match correction and native proof (2026-10-04)

- S5 remains the sole ACTIVE stage. UI-02 previously could refresh a saved
  provider ID or review unresolved outcomes, but could not reconsider an already
  matched wrong ID. Exact-game settings now offer localized **Find another
  match**. A durable correction job searches without the disputed provider/base/
  raw identifier; saved identities and metadata remain intact before review.
- Even a confident provider response is an offered identity, not publication.
  Explicit candidate/classification selection creates the existing normal
  verification job. Fresh facts publish only through that worker. Ordinary
  refresh thereafter uses the corrected ID. No ROM/body lookup is introduced.
- Focused host verification passed: exact-game touch search -> cached review ->
  controller approval -> verified replacement -> ordinary refresh, plus retry/
  restart mode preservation, confident-response review-only behavior and atomic
  rejection of stale cache-row/edition bindings. Existing controls/review/settings/
  detail checks passed (`19072`, exit 0). The adapted dark-theme correction
  fixture passed in `17026`; that workload's only failure was a wrong table name
  in the new migration fixture, corrected without production changes.
- Production v31-to-v32 upgrade/reopen then passed (`88189`, migration exit 0):
  actual v31 job-column layout, seeded saved manual identity/facts and lookup
  item, unchanged existing rows, default normal-refresh mode, and second reopen.
  Existing v25/v26/v27/v29/v30 preservation checks also passed in `17026`.
  The directly affected shared production migration fixture also passed from
  v13/v14/v15/v16/v17/v18/v20/v21/v22/v23/v24 through upgrade and reopen.
  Affected-path analysis found no issues after using the existing sqflite
  dependency, with no new dependency added. Diff whitespace check passed.
- The first native fixture failed because its pause/join shortcut opened review
  before a resumed lookup committed. The inspected screenshot showed an empty
  review, not a missing or clipped card. The fixture now waits for a new job's
  actual completed/idle event; no sleep, production change or weakened assertion.
  The corrected host workflow passed, then native driver completed with exit 0.
  Its inspected report and three screenshots prove Android SQLite plus normal
  touch search, cached review, controller approval, worker publication and a
  subsequent refresh retaining the corrected ID. Provider responses are synthetic;
  no real account/provider/socket/ROM access or collection scrape is claimed.
- Both required assemblies (`66718`, `12313`) passed after actual host-wide gate
  acquisition. Observed two workers, no parallel projects and 3,221,225,472-byte
  Gradle heap, preserving metaspace/code-cache/JVM flags. In-process Kotlin was
  requested, but Kotlin tasks were UP-TO-DATE or NO-SOURCE: no fresh compiler
  memory-use claim. Test tasks configure one 512 MiB fork (not run by assemble);
  actual generated Ninja compile/link rules retain depth-one `rshop_native`
  pools per ABI. No memory failure or budget increase occurred. Workloads ran
  sequentially; no existing build was interrupted.
- Restored the exact normal APK (installed SHA-256 matched the recovery file).
  All seven database/config/preferences/secure-storage fingerprints are unchanged.
  Removed only the two fixture ADB forwards and confirmed both displays OFF.
  Final affected-path analysis and diff whitespace checks passed. Native private
  evidence remains under `D:/Temp/rshop-s5-native-20261004`.
  The two regenerated fixture APK copies were removed transactionally after
  restoration, reclaiming 290,237,854 bytes with zero failures. Recovery APK,
  source and diagnostic/screenshot evidence remain; no release artifact is made.
- UI-02's wrong-match correction is now implemented and verified against a
  synthetic provider on the real Thor. Remaining UI-01 console/badge/localization/
  resource proof and other integrated S5 acceptance remain unfinished. S1/S4
  blockers and S6-S9 are unchanged; this does not close S5 or the overall fork.

### S5 Systematic media integration and native proof (2026-10-04)

- S5 remains the sole ACTIVE stage. The selected upstream family now replaces
  generated app artwork: 50 unchanged Systematic `-content.png` icons, with
  exact pinned Git blob identities in `systematic/SOURCES.json`. The explicit
  mapping covers the current supported IDs; mixed-media computers without
  release-format evidence and unknown platforms use upstream neutral content,
  not a fabricated medium. N64 cartridges, handheld cards, PSP UMDs, optical
  discs and Famicom disks retain their own shapes. S9's final coverage audit is
  still NOT STARTED.
- Source/creator attribution, filename-only changes, no-endorsement notice and
  full upstream CC BY 4.0 text are bundled. Main registers the license provider;
  normal About -> Licenses opens the offline notice through Flutter's localized
  license page. The focused About group passed (`38991`, exit 0).
- Current focused asset/cover/Library checks passed (`4679`, exit 0): pinned
  bytes, actual Flutter decoding (including upstream 16-bit grayscale-alpha
  PNGs), immediate missing/error/suppressed art, explicit caller overrides,
  resolved cached cover replacement without HTTP, compact/large overlay golden
  verification and normal Library/shelf behavior. Scoped analysis (`13303`)
  found only the two pre-existing cacheExtent deprecation infos; the final
  affected-path analysis (`68536`, exit 0) confirms the same result. No new
  production dependency, image rewrite or image generation was introduced.
- Native normal-Library verification initially failed because the fixture
  assumed a lower filter row was mounted at the Thor's smaller logical viewport.
  Production uses a lazy ListView. The shared fixture now traverses its real
  scroll controller until the keyed option is mounted, makes it visible and
  taps it; it does not change production filters or weaken assertions. The
  corrected focused host check passed (`72836`, exit 0).
- Native assembly passed (`65704`, exit 0). The host-wide gate was acquired;
  observed two workers, no parallel projects and 3,221,225,472-byte Gradle heap.
  Kotlin in-process strategy was requested to share that heap; Kotlin tasks in
  this incremental build were UP-TO-DATE or NO-SOURCE, so it does not establish
  fresh compiler memory usage. Configured test tasks
  report one 512 MiB fork (not run by assemble); generated Ninja compile/link
  rules use the `rshop_native` pool at depth 1 per ABI, alongside Gradle's
  two-worker task limit. No memory failure or budget increase occurred. The
  earlier absolute-target invocation failed before compilation; the supported
  Flutter project-relative target was used for the successful builds.
- The current fixture APK's existing package/signature was checked before
  in-place installation. The Thor driver completed with exit 0 and its inspected
  report verifies actual Android SQLite, normal Library controller Top 10,
  touch sparse Top 25, one cross-console cap, scope/tag intersections without
  backfill, publication-driven recomputation, manual shelf preservation,
  explicit rating order/focus and filter persistence. Four inspected native
  screenshots show Systematic PS1/PS2 discs beside the real title/rating layers.
  This is synthetic cache proof, not a real collection metadata pass: all 335
  existing cover attempts were rejected before socket creation; no provider or
  ROM access occurred. The fallback itself starts no requests.
- Restored the exact previous normal APK (SHA-256 matched), with all seven
  database/config/preferences/secure-storage fingerprints unchanged. Removed
  only the two task-created ADB forwards and confirmed both display controllers
  OFF. No ROM, source settings, account credentials or release was changed.
- Removed the eight superseded generated app PNG copies transactionally:
  8,787,487 bytes reclaimed, zero failures; original image-tool outputs remain.
  Current source, recovery APK and native evidence are preserved. Native fixture
  artifacts/report/screenshots are under `D:/Temp/rshop-s5-native-20261004`.
- Remaining UI-01 per-console native proof, full badge/title/size combinations,
  localization and resource acceptance, plus UI-02 wrong-match correction and
  remaining UI-03 integrated acceptance remain ordinary unfinished S5 work.
  This checkpoint does not close S5, S9 or the overall fork.

### S5 upstream media-theme selection (2026-10-04)

- User requested an existing RetroArch asset family instead of generated artwork,
  clarified `-content` (media, not console/controller icons), and delegated theme
  selection. Selected **Systematic's colored media PNGs**, pinned to
  `b177f250e42948708e753d30809bd4dd9c0a2cdc`; S5 remains sole ACTIVE.
- Compared N64 media PNGs from Systematic, RetroActive, NeoActive, FlatUI,
  RetroSystem, Daite, Pixel and Dot-art against the current dark card golden.
  Systematic supplies recognizable flat shapes with a contrast border, without
  RetroSystem's label branding or Pixel/Dot-art's deliberately pixelated style.
  Its N64 PNG and RetroActive's are byte-identical (SHA-256
  `7a2e544d09506c500c18cdd01674816afca2382da8fc4442c9efb882ebdc92a3`).
- Complete, untruncated directory trees at that revision contain 242 Systematic
  `-content` entries versus 198 RetroActive, 177 NeoActive and 56 FlatUI entries.
  These counts inform source selection, not product progress or proof of complete
  R-Shop platform coverage. Visually inspected Systematic's N64 cartridge, DS
  card, PlayStation disc, PSP UMD, C64 cassette and generic content icon too.
- Upstream Systematic/RetroActive documentation establishes the intended flat
  style and contrast border; root COPYING supplies CC BY 4.0. Asset provenance,
  attribution, source subset replacement, refreshed goldens and app/device proof
  remain required. The generated-asset checkpoint below is historical, not
  verification of the newly selected upstream artwork. S9 is NOT STARTED.

### S5 bundled-media host verification (2026-10-04)

- S5 remains the sole ACTIVE stage. The shared card/detail cover now uses bundled
  generated raster media artwork during loading and missing/error/offline states;
  explicit caller fallbacks are preserved. Library/shelf and console callers pass
  canonical platform IDs. Original media is never inferred from provider names
  or archive suffixes. The distinct N64 shape is integrated; final per-console
  cartridge and legacy-format visual completeness remains ART-01/S9 work.
- The inspected generated family and exact prompts are recorded in
  `assets/media_fallbacks/PROVENANCE.md`. Runtime fallback decoding is capped at
  256 pixels wide with shared image-cache keys, not full 1280-pixel decodes per
  card. Host checks verify every supported system has an explicit mapping and
  every mapped PNG is decodable, nonempty and transparent.
- Focused host verification (`82490`, terminal exit 0) verifies immediate
  suppression/error media art, caller override preservation, a decoded real
  cached cover replacing the fallback with zero network requests, compact/large
  rating goldens without update mode, and the normal Library/shelf offline media
  art alongside rank-before-filter, scope, recomputation, focus and persistence.
  Cache-fixture filesystem work must start and complete in the real IO zone;
  the first new check's fake-time/IO wait was stopped before another run, with
  process exit confirmed. This was a fixture correction, not a production change.
- Scoped analysis (`78179`) reports only two pre-existing `cacheExtent`
  deprecation notices in the Library/console grids, confirmed in HEAD; no new
  diagnostics. Native assembly (`76906`, ticket 4) completed with exit 0 and
  BUILD SUCCESSFUL. Its inputs still contain the generated artwork; do not
  install it as proof of the newly selected Systematic asset set. Native proof,
  per-console callers and remaining S5 badge,
  localization, independent-tag and resource acceptance are not yet satisfied.

### S9 visual-coverage scope addition (2026-10-04)

- Revision 5 adds ART-01 and final S9 at the user's request: audit every supported
  cartridge console and the older card/floppy/cassette formats, then fill actual
  visual gaps using the same raster family. S9 is NOT STARTED, not an ACTIVE
  stage or an excuse to defer existing S5 acceptance. S5 remains sole ACTIVE.
- The user explicitly allows new shapes to be generated as needed; no full
  console-art catalogue is being generated during S5. A distinct N64 silhouette
  is being integrated in the current fallback task after its mapping assertion
  reproduced the generic-cartridge mismatch.
- S9 requires the complete format/asset matrix, recognizable accurate shapes,
  provenance, bundled checks and Thor compact/large cover-state proof. Overall
  completion still requires ART-01 and final S1-S9 reconciliation.

### S5 normal Library native-verification checkpoint (2026-10-04)

- The user added required task S5-FORMAT-FALLBACK under UI-01. Specification
  revision 4 and the S5 plan now require a consistent physical-media raster
  fallback while covers load or remain unavailable; no hand-generated SVG/code
  illustrations. Online disc/cartridge sources are recorded as research, not an
  adopted asset set. The task has not been implemented or verified. It remains
  ordinary unfinished S5 work, not a later-stage deferral or an additional stage.
- S5 is still ACTIVE. The existing normal Library assertion sequence is now
  reusable with Android SQLite and the device's real display metrics, rather
  than a replacement grid. Host verification (`72272`, exit 0) covers cached
  overlays, controller Best 10, sparse Best 25, one cross-console cap, scope
  changes, tag intersection without backfill, score-change recomputation,
  manual shelf order, identity-preserving explicit rating sort and restored
  filters. These assertions do not yet cover every independent tag combination,
  per-console UI, localization, badge combination or scrolling-resource gate.
- The native entrypoint uses only an in-memory synthetic catalogue, mock settings
  and a network boundary rejecting requests before opening sockets. It does not
  bootstrap normal user sources, accounts or ROM operations. Four checkpoints
  capture the actual normal Library; screenshots/report are verification evidence,
  not feature acceptance until the device run passes and is inspected.
- Scoped entrypoint/driver/shared-check analysis (`94116`, exit 0) passed after
  correcting two SDK API assumptions from the installed source. The required
  native assembly (`89890`, exit 0) subsequently acquired the shared gate and
  completed in 1m with two workers, parallelism off and a 3 GB Gradle heap. No
  memory failure was reported. Kotlin compilation was up-to-date; test-fork
  markers establish configuration, not test execution. App native depth-one pools
  remain in place, not a verified universal native-job or host-memory cap.
- Actual Thor run of APK SHA-256
  `B9F7A1504A02E87B394A6400990A2F9B6F57B462A612D6E803E8F19F1E505A32`
  failed at the fixture's first membership assertion: it counted mounted widgets
  as the entire result, but the actual-density lazy grid mounted 8 of 12 cards.
  Production was not changed. The fixture now checks the real grid item count and
  scrolls actual positions to inspect every rendered card/overlay in order;
  focused host verification (`45168`, exit 0) passed. Corrected native proof is
  still required. Normal APK restoration (`47710`, exit 0) verified its original
  digest and all seven protected fingerprints; both displays are OFF/asleep.

### S5 cached candidate review and shared Windows build gate (2026-10-04)

- S5 remains the sole ACTIVE stage. Normal metadata settings and the exact
  selected game's metadata action now expose a bounded cached-review page.
  Latest outcomes are selected per provider/edition across jobs, so correcting
  one game does not hide the other unresolved games from an earlier full job.
  Console/exact-edition scope, cursor pages, changed artifact identities and
  newer pending generations are checked without provider or ROM requests.
- Review shows the original release/platform context and candidate evidence.
  Selection and independent classification are explicit; a candidate alone never
  publishes a rating. Acceptance uses the existing atomic identity correction,
  one-edition retry snapshot and verified worker publication. Wrong-platform,
  duplicate, unoffered and superseded candidates cannot overwrite current data.
  Remaining reviews survive correction and controller recreation.
- The focused host catalogue/controller/settings/review/details run (`29316`)
  passed, including landscape controller selection, portrait touch selection,
  independent T-Eng/Undub/Uncensor tags and Back after a reviewed card disappears.
  Route-event evidence traced the Back defect to restoration focus outside the
  screen action boundary. An opt-in local scope includes the restoration node;
  existing unrelated callers retain their prior behavior. The inspected updated
  progress golden was rerun without update mode. Initial scoped analysis found
  only three style findings; their corrected files passed analysis (`36534`).
- Final reconciliation reproduced an exact-game entry defect (`92873`): without
  a previously published metadata ID, review stayed disabled after scraping.
  Cache-row scope now resolves through the same artifact/platform identity rule
  as snapshot capture, with no identity creation or catalogue mutation on read.
  The corrected landscape/portrait/exact-game workflow and affected backend
  checks passed (`60408`); bounded missing/stale/uncaptured-row assertions passed
  (`af9f0f`). Exact scope never falls back to the full queue. Changed source and
  native fixture analysis passed (`4558`). Updated native exact-scope verification
  passed on 2026-10-04: the required queued build (`13453`) completed without
  interrupting the other builds. Its standard-name APK has SHA-256
  `A3DEF3F52643D9CF41F98E15577DA7A19754CC39F0D23370E83413FA99E2E483`.
  The native fixture and directly attached standard integration driver (`af4533`)
  passed, including exact cache-row review without a previously published metadata
  ID. Actual-font evidence is `D:/Temp/rshop-s5-native-20261004/native-review-exact.png`;
  the retained report records the exact-scope assertion. These remain synthetic
  cache/provider checks, not a fresh live-library scrape.
  The first host attachment was cancelled after process evidence showed Flutter
  discovering an unrelated emulator; the same running Thor VM was then attached
  directly through its verified endpoint, with no emulator interruption or test
  restart. Normal APK restoration (`57248`) verified its original digest and all
  seven protected data fingerprints, with both displays OFF/asleep.
- The Thor's actual native SQLite/normal UI fixture passed in logcat and attached
  driver (`16338`): settings entry, touch setup, pause/resume, cached candidate
  selection, independent tags, verified publication, remaining reviews and Back.
  The inspected standard-name test APK has SHA-256
  `5443DB951ED959F0212729DA5908EFD2A5D149D69F535AA202C3620D172B6510`
  and the existing debug signer/package. Actual-font evidence is
  `D:/Temp/rshop-s5-native-20261004/native-review.png`. Data/provider access was
  synthetic and in-memory; this is not a fresh real-library scrape.
- Both required Gradle attempts acquired `Local\Darka.AndroidGradleBuildGate`
  through the installed supervisor. Its preflight used daemon lifecycle/log
  identities and no active client connections, not CPU or age. The first build
  failed because PowerShell split the unquoted C: target argument; a read-only
  argv reproduction established the cause. The quoted retry (`29958`) passed.
  No existing build was interrupted and neither attempt reported a memory error.
  Observed Gradle profile: two workers, parallel projects off, 3,221,225,472-byte
  maximum heap; required 1 GB metaspace/256 MB code-cache flags were retained.
  Kotlin was configured in-process for the existing Kotlin 2.2.20/AGP 8.11.1
  project; compiler tasks were up-to-date, so no fresh compiler-memory proof is
  claimed. A separate daemon's configured ceiling remains 3 GB. Test tasks were
  observed configured for one 512 MB fork; this assembly did not execute them.
  Generated app Ninja files verify depth-one shared compile/link pools for its
  ABI tasks, bounding app native concurrency under two Gradle workers. Existing
  audio-plugin Ninja logs remained dated 2026-10-01: no audio compilation occurred.
  This is not a total host-memory cap or exclusion of uncoordinated launchers.
- Normal APK restoration was verified against
  `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`;
  all seven original database/preferences/credential/config fingerprints match.
  The test-only forward was removed, both screens report OFF and power state is
  Asleep. Transactional cleanup removed only four obsolete host golden diagnostic
  images and their empty folder (1,354,027 reported bytes). Evidence and the
  defined normal-APK recovery copy remain available.
- Ordinary unfinished S5 work: rediscover/correct an already matched wrong ID,
  cached media/details, normal Library overlays/filter/manual-shelf/controller
  acceptance, and localized/compact/badge/offline-scroll measurements. Existing
  S2 source-action layout/touch/localization deferrals remain assigned to S5.
  S1/B3 and S4/B5 remain BLOCKED; S6-S8 remain NOT STARTED. No acceptance criterion
  or required deferral has been waived and no stage/full-feature closure is claimed.

### S5 normal metadata setup and refresh controls (2026-10-04)

- S5 remains the sole ACTIVE stage. Existing General settings and the exact
  selected game's quick menu now open the same localized metadata controls.
  Opening reads only cached scope/job state and secure configuration. Saving
  credentials neither authenticates silently nor claims access was verified;
  forgetting a provider removes only its separate secure credentials.
- ScreenScraper user/application access and IGDB private application access have
  distinct setup fields and secure stores. No credentials were regenerated,
  copied into the APK, exported to ordinary configuration or committed.
  Full/system/exact-file re-scrape, durable latest-job restoration, pause/resume
  and failed/unmatched retry use the existing worker and normal catalogue.
- Progress comes from committed bounded-page deltas and a terminal SQL report,
  not a polling timer or a per-card/frame request. Requested, matched, review,
  ambiguous, unmatched, failed, pending and rated counts stay separate; completed
  traversal explicitly does not claim rated coverage.
- Reproduced and repaired two lifecycle defects: an observer failure could leave
  the durable worker claim running, and pause during snapshot creation could
  still start provider requests. Focused regressions verify claim release and
  preservation of pause intent through snapshot publication without a timeout.
  Shutdown joins a failing/cancelled lookup before closing its adapter.
- Host normal settings, exact game controls at landscape/portrait resolutions,
  secure storage and finite job controls passed (`70680`, `75094`, `11592`). The
  dark-layout goldens verify geometry with Flutter's test font, not real-font
  readability. Screenshot-test waits were reproduced at a cross-zone Future
  boundary and resolved by keeping each fixture's SQLite/controller futures in
  one async zone. This is not evidence for the earlier S4/B5 artwork wait's cause.
- A native Back failure was reproduced on the host after field unfocus: focus
  fell to the route scope outside the screen's actions. A screen-local FocusScope
  preserves the action boundary; its regression passed (`8214`). The affected
  settings/details/credentials/job checks passed (`79910`) and scoped analysis
  reported no issues (`7956`). That run also verified the bounded snapshot at
  about 239 MB peak RSS, one lookup and 128-item commit pages.
- The native Thor workflow now passes controller entry, touch credential setup,
  snapshot pause without provider requests, in-flight pause/same-job resume,
  distinct coverage and Back. The inspected test APK has SHA-256
  `C54B82DF33376090DAC0E94E934D7D6E1758FB67CCC0C67ACFB2B6115D460EBA`;
  native logcat and attached driver (`97322`) both report success. Actual-font
  evidence is `D:/Temp/rshop-s5-native-20261004/native-focus-fixed.png`. This is
  synthetic in-memory SQLite/provider verification, not a real-provider scrape.
- The original normal APK was restored and its on-device SHA-256 matches
  `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  All seven original database/preferences/credential/config fingerprints match.
  The test-only ADB forward was removed; both displays report OFF and the device
  reports Asleep. No Samsung installation occurred when the Thor disconnected.
  Match-correction/media UI and remaining S5 acceptance work remain ordinary
  unfinished work in S5, not deferrals or completed criteria.
- After the user's approval, primary filled metadata and Drive setup/mapping
  actions now share white labels on `#C62828`. Brighter accents, tonal actions
  and disabled defaults remain unchanged. The rendered metadata button regression
  failed before the change (`76952`); focused settings/source widgets and
  normal/hover/focus/pressed contrast checks pass (`5219`). Host goldens were
  updated for the approved palette; this color change has not been installed on
  the Thor. No Gradle command was required or launched for this verification;
  gate acquisition and an effective Gradle/Kotlin resource profile are not claimed.

### S5 exact cached game-details integration (2026-10-03)

- S5 remains the sole ACTIVE stage. The normal detail screen and Game Info
  action now read the selected file/artifact's identity-bound cached metadata,
  rather than the first metadata-bearing sibling. Details, covers and Top use
  the same effective sourced score and unchanged production reception policy.
  Raw scale, available/unknown count, retrieval date, ownership and stale/advisory
  state are exposed in visible details and accessibility/tooltip text.
- The common detail model carries current summary, genres, release/credits,
  field provenance and independent content tags. It validates provider-scoped
  identities/provenance before consuming records. Unrated or ambiguous current
  bindings remain unrated; they cannot inherit a sibling or anonymous legacy
  score. Contradictory official classification is handled identically by details
  and discovery. Cache reads do not start scraping or fetch ROM payloads.
- Reproduced failures before fixing: normal details returned legacy 99 instead
  of cached 82, the existing detail card omitted sourced-score explanations,
  and contradictory official/hack tags differed from discovery. Focused
  regressions pass, including cross-console duplicate filenames, duplicate
  selection rejection, independent translation/audio/censorship tags, requested
  language, per-field provenance and stale generation after a refresh job.
- Fresh normal-screen host proof (`788183`, exit 0; included in `60537`, exit 0)
  uses SQLite and the actual screen/provider path at landscape desktop, 1280x720
  and portrait 720x1280: pending indicator, controller Start to normal menu,
  touch Game Info, sourced explanation/tags/provenance, controller close,
  cache-error state and retry restoration. ROM actions remain independent.
  External containers remain alive during route disposal. Synthetic fixtures
  use Flutter's no-network test boundary; this is not Thor/live-provider proof.
- Focused query/details/model/badge/database/discovery regression run `60537`
  passed. Additional exact-selection checks `46673` passed. An initial command
  referenced a nonexistent grid test path; it was corrected, not counted as a
  pass. Scoped analysis `86088` exited 0 with no issues; formatting and Git
  whitespace checks pass. No test/analyzer workload remains running.
- Transactional cleanup `30cc22ad2c65a9ecc7656b5f01c9e6aa` permanently removed
  only generated build/unit_test_assets and build/test_cache (82,637,373 bytes),
  terminal APPLIED, no errors. All manifest candidates were inspected. These
  compiler outputs are reproducible; source, goldens, credentials and retained
  forensic/native evidence remain untouched. No accounts, secrets, device,
  ROMs, cloud files, release or deployment were changed.
- UI-02 is not COMPLETE: normal provider setup, refresh/re-scrape progress,
  match correction and remaining cached media/detail integration still require
  implementation/verification. UI-01/UI-03's remaining handheld/controller,
  compact/localized and offline-scroll/request evidence also remains required.
  These are unfinished S5 acceptance items, not later-stage deferrals. S1/B3
  and S4/B5 remain BLOCKED; S2/S3 COMPLETE; S6-S8 NOT STARTED. The user's two
  accepted renewals do not authorize another secret rotation or consent request.

### S5 integrated discovery filters checkpoint (2026-10-03)

- S5 is the sole ACTIVE stage. Existing console filters and the library/shelf
  panel now share the cache-only SQLite discovery query. Best 10/25/50/100/All,
  independent content tags, any/all matching, genres and explicit rating order
  persist in their existing console or library/tab/shelf contexts. Cross-system
  scope is selectable and the UI states that one cap applies across that scope.
  Scope/ranking precede search, installed, favorites and shelf intersections;
  filtering never backfills or adds uncapped extras.
- Query pages retain every matching edition while counting/ranking a canonical
  game once. The UI bridge binds exact console plus file/artifact identities,
  rejects ambiguous duplicate bindings and removes its transaction-local view.
  It reads lightweight cached query rows, not whole metadata/artwork records or
  provider APIs. Genre choices are available before selecting a Top filter.
  Accepted score policy is unchanged; unsupported scopes remain unranked/advisory.
- Console query publication is generation-coalesced. A reproduced listener-time
  filter change previously left a pending generation unpublished; the regression
  now passes. Top membership does not implicitly change manual shelf order:
  that reproduced defect is fixed, and only explicit rating sort reorders it.
  Library publication refreshes coalesce catalogue reloads. Focus is retained by
  exact game/group identity rather than position. Clear restores normal browsing.
- Fresh focused host verification (66752, exit 0) covers the actual library
  screen and production score policy: one cross-console Top cap, changed scope,
  tag no-backfill, empty results after score publication, restoration after
  publication, per-view persistence/relaunch, unchanged shelf storage, manual
  order and identity focus through rating sort. Console/controller/shared-query,
  touch/controller filter panel, legacy grid and cover golden checks also pass.
  Synthetic fixtures and Flutter's test HTTP boundary make no real ROM/provider
  requests. The external test container remains alive while routes unmount, as
  in the app, so existing deferred focus callbacks do not target disposed state.
- Scoped analysis of changed production/tests (27c55f, exit 0) reports only the
  two pre-existing grid cacheExtent deprecation infos, verified against HEAD;
  no errors/warnings. Formatting and Git whitespace checks pass. Workloads ran
  sequentially; no credential renewal, browser/account mutation, deployment,
  release or Thor/ROM/SD mutation occurred.
- Reviewed cleanup a0d9b6092300f59670483210acd6e559 permanently removed only
  regenerated build/unit_test_assets and build/test_cache: 93,048,845 bytes,
  terminal APPLIED, no errors/residuals. Every manifest item was inspected;
  source, goldens, credentials and existing forensic/native evidence are kept.
  These compiler outputs are reproducible; no test/analyzer workload remains.
- UI-03 is not COMPLETE: native handheld/controller scope/filter/manual-order
  proof, exact console-screen focus and badge cases, compact/localized layout,
  and offline-scroll/request measurements remain required. UI-01's remaining
  screen/native checks and UI-02's normal setup/refresh/details integration also
  remain ordinary unfinished S5 work. No acceptance is deferred to another stage.
  S1/B3 and S4/B5 remain BLOCKED; S2/S3 COMPLETE; S6-S8 NOT STARTED.

### S5 cached cover overlays and preference integration (2026-10-03)

- S5 remains the sole ACTIVE stage. Both existing shared-card callers (console
  grid and library/shelves) now receive nullable, exact-edition cached ratings.
  One view-scoped provider reads keyset pages of at most 128 rows, preserves
  console/artifact identity and rejects duplicate bindings. It uses the same
  effective-score selector as ranking, without requests per card or frame.
  Loading/error generations hide previous score maps; empty console views do
  not start score reads. No provider credentials or cloud files were changed.
- The pure card overlay labels the source and normalized score, exposes raw
  scale/count/retrieval/ownership through semantics and tooltip, and distinguishes
  stale/original/project/advisory scores. Existing artwork is not rewritten.
  The normal Display settings tile persists the overlay preference. Acknowledged
  writes are serialized in tap order; failure preserves the prior value and shows
  the existing localized save error. Subsequent retry remains usable.
- Host checks passed for optional/unrated/disabled/stale/original states, compact
  and large selected crowded cards, full achievement-badge geometry, accessible
  provenance, preference persistence/rapid taps/failure/retry, exact cache lookup
  and publication refresh. The reference golden was generated, visually inspected
  and then compared without update (`92852`, exit 0). The affected legacy grid
  checks also passed (`0d9287`, exit 0). Found defects were reproduced first:
  unconstrained footer text, a fixed favorite-to-achievement offset and concurrent
  preference writes. Tests exercise these boundaries rather than reporting them
  as already working.
- Scoped analysis of the changed production/tests reported only the two existing
  `cacheExtent` deprecation notices in the console/library grids (`77155`, exit 1
  for infos); their unchanged HEAD definitions were inspected. There were no new
  errors/warnings. Formatting and Git whitespace checks were inspected.
- UI-01 is not COMPLETE: actual screen offline-scroll/request measurements,
  additional badge/controller cases and Thor readability/touch/controller proof
  remain. UI-02 provider setup/refresh/details and UI-03 shared-query filter/sort
  controls, scope/coverage/persistence/clear/manual-order integration remain
  ordinary unfinished S5 work, not later-stage deferrals. S1/B3 and S4/B5 remain
  BLOCKED as previously recorded; S6-S8 are NOT STARTED.
- Reviewed cleanup `b2b4cbf4ec4c45136c417053aa191909` permanently removed only
  regenerated `build/unit_test_assets` and `build/test_cache` output: 103,212,965
  bytes, terminal APPLIED, no errors/residuals. These are reproducible compiler
  outputs. The golden, source, credentials, native and original forensic evidence
  remain preserved. No test/analyzer workload remains running; no deployment,
  publication or Thor mutation occurred in this scope.

### S4 VM-disabled observation and explicit parked evidence gap (2026-10-03)

- The original native CDB trace and installed FFI/ReceivePort implementations
  were inspected. There is no captured Dart async stack; nearest-export symbols
  do not identify the outstanding Future or prove engine shutdown. Provider quota
  and memory exhaustion were absent. The original stopped process cannot supply
  the missing state, and its preserved database is not a substitute for it.
- A test-only loopback GET observer exposes at most 64 sanitized FFI summaries,
  pending acknowledgements and active production cache download. POST is rejected.
  No production hooks, timers, retries, garbage collection, provider requests,
  credential changes or database mutations are introduced by observation. The
  focused loopback contract passed (d27248); the initial contract failure was
  Flutter's deliberate test HttpClient replacement, corrected only for that
  exact loopback client without changing the global override.
- One full diagnostic workload used the actual `--disable-vm-service` tester
  (92308), with `Service.getInfo` returning null. Session 55923 exited 0:
  30,000 matched selectors, 600,308 acknowledged operations, no pending operation
  or download; 21,440 ms capture, 641,259 ms total, 206,770,176-byte peak RSS,
  65,536-byte maximum chunk and one transport. Offline reopen/replay passed.
  This disproves that an enabled VM service is necessary for progress; it does
  not reproduce or explain the original wait. Its tester/listener exited and
  exact private fixture was absent. Original forensic evidence remains.
- The default unobserved 256-item shared fixture passed (65153), including the
  unchanged native production cache/worker and offline reopen/replay. Its optional
  test-only cache factory leaves the default Android fixture path unchanged.
- Scoped analysis of the three changed diagnostic/fixture files exited 0 with
  no issues (98813). Dart formatting and `git diff --check` passed. The default
  fixture's exact private directory was also absent after its terminal result.
  Reviewed transaction 550e88c33d712b969f318c858e7408ba removed only regenerated
  `build/unit_test_assets` and `build/test_cache` output: 56,910,629 bytes,
  terminal APPLIED, no errors or residuals. Source, credentials, native reports
  and original forensic evidence were preserved.
- S4's full backend requirement reconciliation is in
  [S4_ACCEPTANCE_RECONCILIATION.md](S4_ACCEPTANCE_RECONCILIATION.md). B5 records the
  exact remaining acceptance, missing state, evidence-availability boundary,
  resolution and final dependencies. S4 is BLOCKED, not COMPLETE; B5 is not
  renamed a deferral or claimed to be an external application fault. A recurrence
  or additional original runtime evidence returns priority to S4.
- S5 becomes the sole ACTIVE stage. Its actual dependencies—verified provenance,
  cache/query semantics and current setup states—are available. It owns the
  still-undelivered card/details/setup/filter/controller integration. S1 remains
  BLOCKED at B3/elapsed renewal; S2/S3 COMPLETE; S6-S8 NOT STARTED. Final closure
  and SD migration remain gated by the unresolved required earlier-stage work.

### S4 production-score native proof and bounded wait diagnostics (2026-10-03)

- S4 remains the sole ACTIVE stage. The shared host/Android fixture now verifies
  catalogue discovery -> explicit candidate review -> actual IGDB adapter ->
  persistent publication -> production score selection -> offline Top query.
  Its three synthetic PS1 identities include a supported community score, a
  low-vote extreme-score project and an unrated original. The exact community
  object is used by display and ranking; critic/blended-total values do not
  substitute. Low-vote projects remain browsable with project attribution, not
  ranked. Tag intersection cannot backfill. Changing the known count from 20 to
  19 invalidates rank through the normal cache/projection with no new request.
  This is native transport-fixture proof; real API/reception evidence remains
  the preceding live assessment, not a synthetic claim of consensus.
- The focused host check exited 0 (`8f3587`). Initial fixture setup used the
  wrong IGDB platform ID and discovery outcome; only fixture data was corrected
  against the existing explicit platform mapping and adapter contract. Review
  association uses candidate evidence, not edition-ID/insertion-order assumptions.
- The Android ownership entrypoint built successfully (`89812`), and the exact
  artifact was independently inspected: `com.darkaxt.rshop.debug`, 1.7.0/12,
  unchanged registered debug signer; SHA-256
  `37E623DDB2706B3E4079958E63B2663ACAEE4C3B8F551C5AB7D1A4A32BEBD06B`.
  Native logs show the production-policy workflow and existing raw-release/
  project/review/classification checks passing. The driver attached to the
  observed VM service without uninstall/rebuild and exited 0 (`43156`). Private
  report and device trace: `D:\Temp\rshop-s4-score-native-20261003`.
- The exact normal APK was restored without uninstall; its on-device SHA-256
  again equals `DAA8B182C8F722F4E3DC75685EE346B8919BFEFB1159C62AF6CFCE3EBDD7FFEE`.
  Normal database/journal, secure storage/key preferences, ordinary preferences
  and Google sign-in preferences retained their exact pre-test fingerprints.
  App and task log listener stopped, task forward removed, both physical display
  states confirmed OFF and device asleep. No normal-source bootstrap, account
  request, ROM payload, library mutation or credential rotation occurred.
- A single opt-in host diagnostic (`53821`) completed the unchanged 30,000-game
  artwork workload through the same SQLite FFI isolate boundary. The test-only
  trace keeps at most 64 sanitized summaries and bounded pending operations;
  no rows, SQL arguments, retries, timers or production hooks were introduced.
  Read-only VM inspection did not pause the isolate or force garbage collection.
  Terminal report: 600,308 operations acknowledged, none pending; capture
  27,319 ms, complete workflow 706,214 ms, peak RSS 224,997,376 bytes,
  65,536-byte maximum chunk and one active stream. Offline reopen/replay passed.
- That run did not reproduce the earlier wait at item 9,027. The original
  pre-recovery snapshot remains intact, with 9,026 committed items, 20,974
  pending and no throttle/quota state. Success with observation enabled is not
  evidence of its root cause or a production fix. The original wait investigation
  and requirement-by-requirement S4 reconciliation remain unfinished; no later
  stage was activated and no required work was silently deferred.
- Scoped analysis of the changed host wrappers/helper, shared provider fixture
  and Android entrypoint exited 0 with no issues (`52153`). Git whitespace checks
  pass. No production runtime/schema changed during this verification scope.
  Reviewed cleanup `30dac0471b2c62c1c3e6cb633a8753ac` and
  `092f497abfec0ddfa0ce103cf87e1848` are terminal APPLIED without errors: generated
  test assets/cache (57,408,517 bytes) and the restored recovery APK copy
  (250,598,905 bytes) were removed. These reproducible outputs are permanently
  deleted; native report/log and original forensic database remain preserved.

### S4 live reception remediation and shared production score (2026-10-03)

- Real IGDB capture requested public games only: twenty older-console releases,
  four Switch releases and two distinct hacks. All 26 identities were matched;
  24 had sourced ratings and two remained unrated. Final Fantasy VII initially
  stayed ambiguous among three offered IDs; an explicit single-title benchmark
  review selected original 427 without changing production matching. No ROM
  payload, owner collection, artwork, Drive or Thor storage was involved.
- `SCORE_RECEPTION_ASSESSMENT.md` records IDs, separate raw score/count bases,
  independent reception, port/project differences, coverage and limitations.
  The blended IGDB total can give one critic half the result despite thousands
  of user votes. It is not approved merely from its combined count. The supplied
  game-level community average is the assessed basis, explicitly preserving
  `communityAggregate` / `IGDB users`, not pretending it is critics or inventing
  a local average. Its current scope is PS1/PS2/GBA/GameCube/Switch with known
  >=20 user ratings. This operational floor is not statistical certainty.
- The shared selector/store/indexed query now apply that same application-owned
  assessment by default. An explicit empty assessment remains available to verify
  unapproved capture semantics. Unsupported scope, unknown/small count, stale
  generation, conflicting identity and wrong original/project ownership cannot
  rank. The actual community object drives display and rank; no higher total or
  critic fallback gains approval. Existing query-policy fingerprints invalidate
  projections when the basis changes, without persisted fixed Top lists.
- The focused regression failed against the prior selector's rejection of a
  community game-level assessment, then passed after integration. Score/cache,
  exact identity, indexed query/no-backfill, production upgrade/reopen and normal
  IGDB worker checks passed, exit 0. New checks cover the real one-critic trap,
  null/two/nineteen/twenty vote support, stale scope, shared display/Top and a
  count change invalidating current ranked membership. Scoped analysis of all
  six changed Dart source/test files passed without findings, exit 0.
- Fresh real three-item provider -> review -> publication -> provider closed ->
  production offline query passed, exit 0. Final Fantasy VII used its actual
  90.6648675637598 community score/1,630 votes, not total 87.8324337818799.
  Unbound's thirteen-vote project remained advisory; Crimson Echoes stayed
  unrated and did not borrow Chrono Trigger. The query reported 3 collection
  games, 1 ranked, 1 Top match and provisional coverage. This is actual provider
  and host SQLite proof, not target UI/device proof. The public diagnostic logs
  are retained under `D:\Temp\rshop-reception-20261003` as required evidence.
- Transactional cleanup inspected the signed manifest for only regenerated
  `build/unit_test_assets` and `build/test_cache`; ticket application reached
  `applied`, deleting 56,982,037 bytes with no warnings or errors. These outputs
  are reproducible by the focused Flutter checks. Live capture evidence, earlier
  host-stall diagnostics, APK deliverables, source assets and credentials remain.
- S4 remains ACTIVE; no S5 implementation, release, SD migration, account change,
  repeated secret renewal or new monitoring occurred. S1 is still BLOCKED at
  B3/elapsed renewal, S2/S3 COMPLETE, S5-S8 NOT STARTED. The unassessed platform
  scope and unexplained earlier host artwork wait cannot be concealed by this
  successful narrow score workflow.

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
| S1 | COMPLETE | S1_ACCEPTANCE_RECONCILIATION.md; additive identity/migration preservation, native consent/decline/reconnect, actual natural HTTP401 followed by different-token silent renewal/root, remote revocation, offline isolation/privacy contracts, legitimate standalone ScreenScraper lookup and release identity verified; normal APK/settings/protected hashes restored | None. B3 resolved by explicit user waiver of live second-account verification, not live isolation proof; B6 resolved by working hotel connectivity |
| S2 | COMPLETE | Focused rooted/paging/failure/identity/mixed-queue contracts pass; real selected Game Gear subtree published after resumed traversal; normal mapping/library shows 182 exact archive entries, retained through cold restart with Wi-Fi disabled and controller browsing | No unmet S2 criteria. Named final source-action touch/layout/localization work belongs to UI-02/S5; verified payload/offline emulator/removal belongs to S3 |
| S3 | COMPLETE | Real Drive/SD/Dolphin/offline/remove/reinstall; native publication and replacement process-stop recovery; bounded large-file streams/measured copy space; exact achievement identity/hash; normal queue bundle resume/readiness/share/removal/save proof and native member grant gates; additive v22 preservation | No unmet S3 criteria. S5 owns the separately named final source-action UX work; it does not replace S3 acceptance |
| S4 | COMPLETE | S4_ACCEPTANCE_RECONCILIATION.md: current normal artwork, matching/tags/assessed score/query, durable bounded shared rebuild, exact ES-DE fields/media and actual Thor permission/restart/expendable-reinstall workflows verified; owner-directed setup reconstruction verified | None for assigned S4 criteria. B7's old private bytes remain irreversibly lost, not claimed recovered; its operational reconstruction resolution is verified. Other score scopes remain explicitly advisory, not silently accepted |
| S5 | COMPLETE | Normal native shared-card layout/overlays/media and pinned IGDB service icon, decoded cached cover replacement in console/Library/shelf, independent tags/unrated paths, filters/focus/restore, setup/refresh/review/correction, details/provenance/error/retry and localized Sources menus verified; consolidated evidence in S5_ACCEPTANCE_RECONCILIATION.md | None for UI-01/UI-02/UI-03; S9 owns the expressly named final complete cartridge/legacy-platform asset coverage |
| S6 | COMPLETE | ea63586; S6_ACCEPTANCE_RECONCILIATION.md: combined normal real Drive/metadata/artwork/SD/emulator/remove/re-download/offline workflow and focused integration/privacy/resource checks | None for assigned S6 criteria; no bulk scrape or SD migration claimed |
| S7 | ACTIVE | S7_ACCEPTANCE_RECONCILIATION.md; both fresh provider traversals completed on the earlier two-console/PSP/PS1 scopes and the 225-row PS2 scope; five mappings expose 1,106 remote plus 547 local rows; PS2 cached checksum audit preserves all files; unchanged-evidence binding regression reproduced/fixed and a fresh reviewed score survives normal Thor Home sync | MIGRATE-01: whole-collection coverage, reviewed identities and defensible ranking, live cloud recovery, exact reviewed removals, retained-set and space audit |
| S8 | NOT STARTED | User companion-launch choice recorded in revision 3 | COMPANION-01: per-ROM association, actual top/bottom display launching, failure paths and ordinary-launch/save-safety verification |
| S9 | NOT STARTED | User complete physical-media coverage choice recorded in revision 5 | ART-01: complete cartridge/legacy-media asset matrix and native cover-state audit; final integrated reconciliation |
| S10 | NOT STARTED | User save-backup and most-installed-emulator coverage instructions recorded in revision 7; initial read-only package discovery, not save-access proof | SAVE-01: every accessible installed-emulator route, evidence for inaccessible routes, separate backup consent, real backup/restore/emulator-load workflows, conflicts and last-good recovery; leave FolderSync unchanged |

B1 (offline Thor) was resolved on 2026-10-02: the online native flow granted
read-only authorization and returned the real Drive root/folder response. This
did not alone satisfy DRIVE-01 auth lifecycle acceptance. B2 blocked META-02's
authenticated lookup and S4's live matching/reception evidence; legitimate fork
application credentials and a successful live lookup resolved it on 2026-10-03. Neither substitutes for the
ordinary unfinished implementation listed above. No required work is dropped or
reclassified as a deferral. S1 is COMPLETE after actual renewal and verified restoration,
with B3 resolved by the user's explicit scope change; S4, S5 and S6 are COMPLETE; S7 is ACTIVE. Earlier chronological
checkpoints retain their then-current state.
S3's explicit dependencies were S2 exact artefacts/queue
and S1 migrated state, not ScreenScraper lookup. S1 auth lifecycle criteria are now
satisfied; S6-S9 still require their own closure before overall completion.

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
