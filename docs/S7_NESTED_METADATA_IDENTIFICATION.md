# S7 nested local archive identification — 2026-10-09

Authority: META-01/META-03 and MIGRATE-01. S7 remains ACTIVE; this correction
does not establish full coverage, defensible retention or removal eligibility.

## Observed cause

The normal archive callback supplied only `configuredTarget/artifact.displayName`.
The native validator intentionally reads an exact leaf, rather than searching
the SD card. Consequently a byte-identical archive already in a nested directory
was invisible to this metadata path. The existing private completed censuses
show substantial nested storage; these historical comparisons are not current
cloud proof and do not authorize migration.

A fixed, read-only native diagnostic inspected at most 128 job-76 `needsReview`
items per console, with bounded JSON and a 128 MiB VM. It queried exact edition
members/artifacts and observed file presence only, without ROM reads, provider
requests, ownership changes or private identity output:

| Console | Sampled review items | Root leaf present | Exact nested layout present, root absent |
| --- | ---: | ---: | ---: |
| GB | 128 | 3 | 1 |
| GBC | 128 | 3 | 4 |
| GBA | 128 | 5 | 4 |
| NES | 128 | 1 | 5 |
| SNES | 128 | 2 | 0 |

These observations establish a real location gap for fourteen sampled entries,
not the cause of every review outcome. File presence is not checksum equivalence
or provider identity. Unknown classification and absent raw identifiers account
for the broader review boundary; accepting title candidates alone would weaken
the existing modified-game and score-ownership requirements.

## Correction and focused verification

The existing Drive boundary returns its already-validated cached ancestor chain.
When, and only when, the root leaf is absent, the metadata reader may inspect one
exact nested parent beneath the console target. It derives components from that
chain up to the selected folder ID, not from a display path. Unsafe components
are rejected; there is no SD search, filename normalization or new remote ROM
download. Native pinned-descriptor and namespace checks, full container checksums,
raw-member validation and before/after live cloud revalidation remain required.
The historical byte observation records the actual parent/leaf, not ownership.

Regression-first checks failed on the absent nested lookup. The correction passes
exact nested binding, unsafe-path rejection, container mismatch, changed source,
root-copy priority, access-denied preservation and refusal to bypass a mismatched
root namesake. They exercise the real catalogue, boundary, runtime and journal
with bounded synthetic native/transport seams; no stage-wide native claim follows.
The affected runtime/boundary checks and scoped Dart analysis pass. No full-suite
run was required for this bounded change.

Shared-gate request 435 (`e6b24dbb3abb4e27b38c6de5ecd04153`) completed debug
assembly with exit 0 and supervisor-confirmed completion. Its final output
verified two workers, no parallel projects and a 3 GiB Gradle heap; Kotlin uses
the assessed in-process strategy. JVM tests were configured as one 512 MiB fork,
not executed by assembly. Independent inspection of the current eleven Ninja
files verified depth-one pools for all 281 compile/link edges. No memory failure
or budget increase occurred. The final output was truncated before its
gate-acquired field; this record does not claim independent inspection of that
field. The request used the installed shared-mutex launcher, not a detached build.
The private build log is
`%LOCALAPPDATA%/Tools/gradle-build-gate/logs/9929adbe10594611a5d24b95afff2dd0.log`.

The resulting 225,140,523-byte debug APK has SHA-256
`4440a5aca0ea44ad0708c0aec1a5505c6addaee8af0bc9904e1abba20c69753b`.
APK signature verification preserves signer SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
This artifact has not been installed; normal Thor verification remains required.
Read-only observation confirms the existing refresh advanced from 7,226 to 7,630
committed pages, with the device asleep. The existing
process is not replaced during its advancing rooted refresh. Saved job 76's
membership and terminal outcomes are not rewritten; this change applies to normal
future identifier reads. Full collection coverage, native policy/mapping checks,
defensible canonical Top-25 retention and reviewed migration remain S7 work.
S8-S11 remain NOT STARTED. No ROM, save, sync mechanism or account was changed.

Completed diagnostic helpers were removed through reviewed transaction
`380b6f0d6fa666339f4e2a58b1aec1f1`: eight exact local members, 24,493 bytes,
no warnings/errors/residuals. The two device jars were hash-matched to their
host counterparts, removed by exact name and verified absent. Source changes,
verification evidence, the APK and unrelated diagnostics remain preserved.
