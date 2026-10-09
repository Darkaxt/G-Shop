# S7 ranking catalogue-read batching — 2026-10-09

Authority: META-07, QA-01 and the existing S7 native responsiveness criterion.
S7 remains the sole ACTIVE stage; S8-S11 are NOT STARTED.

## Evidence and correction

The installed policy rebuild's database trace showed repeated exact `games`
lookups while the projection transaction held the database. The existing real
SQLite 129-edition policy-rebuild regression was extended to observe catalogue
reads as well as writes: before correction it failed with **515** catalogue
reads against a bound of eight. This was a behavioral failure, not a compile
error. Previously batching writes alone did not remove these per-edition reads.

`LibraryStore.readCatalogueBindings` resolves at most 128 identities in the
existing transaction, using one exact indexed join for legacy rows and one for
artifact identities. Each request uses at most 384 SQL parameters and returns
at most one aggregate row per requested edition; duplicate matches remain
rejected. Projection membership/title selection and effective-score consumption
use these page reads instead of separate per-edition catalogue queries. The
outer atomic projection transaction, invalidation policy, ranking semantics,
content markers and score selection are unchanged. No schema, credential,
provider, network, ownership or removal behavior is added.

## Host verification

- The original regression now passes its eight-read/two-write-batch bound while
  retaining all 129 members, its bounded 128-item result and provisional coverage.
- Real SQLite differential checks agree with the existing single-identity guard
  for current/removed/folder/wrong-system legacy entries, replaced version or
  account, missing remote records, changed keys, duplicate artifact bindings,
  converted legacy rows, explicit non-catalogue identities and malformed or
  conflicting catalogue evidence. A changed byte binding retains its title but
  cannot supply a score. Oversized/duplicate requests are rejected.
- `EXPLAIN QUERY PLAN` runs against the actual captured production SQL and
  arguments. Legacy reads search the integer primary key; artifact reads search
  `idx_games_system_artifact`. Neither plan scans `games`.
- The affected library-query/store checks pass, including rollback of a failed
  second projection page, canonical/rank-before-filter behavior, sparse coverage,
  exact variants and score invalidation. Scoped Dart analysis and diff checks
  pass. A test fixture initially used a non-const constructor as const; that
  compile-only test error was corrected before the inspected passing run.

- Shared effective-score consumption and the existing real SQLite 3,000/30,000
  catalogue resource checks pass serially. The 30,000-entry projection took
  57,366 ms on this host; two warm filtered pages took 1,551 ms. Maximum returned
  identity/metadata pages were 128 rows. The single test process's peak RSS was
  265,932,800 bytes (about 254 MiB), not a total-host memory guarantee. Timing is
  diagnostic, not a pass deadline or evidence of native Android latency.

## Native assembly and preserving update

Shared-gate request 436 (`dcaf7608ea274aa194421822b3993646`) completed
`:app:assembleDebug`, exit 0, with supervisor completion verified. Its retained
log reports BUILD SUCCESSFUL in 1m 48s. The original tool session's final output
handle is missing; the independently inspected support record does not contain
the final gate-acquired flag. The command used the prescribed shared-gate
launcher; a separately inspected acquisition flag is not claimed.

Observed log profile: two workers, parallel=false, Gradle maximum heap
3,221,225,472 bytes (3 GiB), with existing 1 GiB metaspace/256 MiB code-cache
flags preserved. The assessed Kotlin 2.2.20 project uses in-process compilation.
JVM test tasks were configured for one 512 MiB fork and were not run by assembly.
Fresh inspection of all three app ABI Ninja outputs verifies each compile/link
block uses `rshop_native` at depth one. No memory failure or budget increase.

The 225,148,166-byte debug APK has SHA-256
`8c5d31bb0dc82a2c18e3ef30c4eed5522eae28ff7c6c9d37c9b9d5f0f7ff3567`.
APK v2 verification retained signer SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Normal `adb install -r` succeeded without uninstall/data clearing. An independent
hash of the installed `base.apk` equals that artifact; new owner PID is 7116.

Immediate pre/post replacement configuration and all nine private preference
file digests matched, including encrypted storage. The complete saved-job
observations also matched. Root generation 2 has actually published:
active=2, pending=null, nextGeneration=3; no reset/replacement traversal was used.
Configuration SHA-256 remains
`4f4e2f0c2462d60bd5259ca30045cc3497a42a61e97bb2b23daf8984745a2dd6`.

Private protected-file journals `update436-before-protected.jsonl` and
`update436-after-protected.jsonl` under `D:/RShopPrivate/Migration` contain the
same 146 paths / 304,569,033 bytes, no additions/removals, and all digest/size
pairs equal. This is not an atomic all-saves preservation claim: three RetroArch
configuration files were unstable during the pre-capture and one during the
post-capture; config membership was unstable in both. Shared PPSSPP was
absent/unreadable. The comparison correctly exits 1, not a clean safety gate;
private/custom paths are not covered. No emulator was stopped, restored or
reconfigured to force that check green. Journals remain private evidence.

## Normal Thor integration

Saved ScreenScraper job 76 was blocked on provider `unavailable` at 18,543
lookups before installation. One normal Resume continued that same immutable
44,204-item job without account selection, reaching 18,548 requests, 744 matched,
701 rated and 25,016 pending. This is actual provider recovery/publication, not
an inferred token-renewal claim or a completed full scrape. No terminal outcome
or saved request was rewritten.

Normal Library loaded Dashboard 26 / All 47,847 / Installed 3,534, explicitly
catalogue entries rather than canonical games. Opening its existing two-filter
global PSP shortlist completed the cached projection query and reports
35/334 ranked, 25 matching games, Provisional. Existing filters were unchanged.
This verifies the installed normal query path after regular catalogue/metadata
updates; no diagnostic dirty-row clear or forced policy reset was used. No
exact native latency or acceptable whole-startup performance is claimed.
Both committed displays subsequently report OFF and the Thor is Asleep.

This correction does not finish full fresh scraping, required scoped passes,
defensible canonical Top-25 retention or reviewed exact SD migration. No ROM,
save, cloud original or external sync policy was modified.
