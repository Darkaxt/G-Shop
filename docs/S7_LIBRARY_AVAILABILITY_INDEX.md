# S7 Library availability index — 2026-10-09

Authority: UI-02, QA-01 and the existing S7 native responsiveness requirement.
S7 remains the sole ACTIVE stage; S8-S11 are NOT STARTED.

## Root cause and bounded correction

Android terminated update-436 process 7116 with reason 6 (ANR) at 09:45:44:
focus-loss input dispatch exceeded 5,005 ms. The native main-thread stack was in
Dart code, not a Java lock. There was no OOM termination evidence. Persisted
job-76 `running` was not proof of a live worker after that process exited.

Sampling ordinary Library entry in the replacement process identified repeated
`InstalledFilesState.hasExactArtifact` full-console list scans. Header/dashboard
availability checks repeat across the collection and encode identities during
each content comparison. A bounded 512-installed/1,536-collection regression
failed before correction with 1,311,232 ID-key reads against an 8,192 bound.
This is an operation-count assertion, not a machine-dependent timeout.

Retain an immutable copy of exact installation lists and build one lazy index
per snapshot, scoped by console and exact provider/source/account/file ID. Check
only matching-ID candidates using the unchanged full content comparison.
Multiple versions remain candidates; version, size and provider digest checks
are not replaced by ID equality. No schema, score, network, ownership, removal
or saved-job behavior changes. Non-const construction follows from that index.

## Host verification

The regression passes after indexing. Focused installed-state/provider and
Library dashboard/discovery/console checks pass serially with `--concurrency=1`.
They retain account/source/provider/console isolation, changed content rejection,
rename handling, duplicate versions and immutable constructor input. Scoped Dart
analysis and diff checks pass. Existing SVG fixture and RomM migration messages
remain in test output; this is not a pristine-output or full-suite claim.

## Gated native build and preserving update

Shared-gate request 442 (`21cfa73092124aac82f3408b8cd6bb43`) completed
`:app:assembleDebug`, exit 0 and `completion_verified=true`. Its retained log
reports BUILD SUCCESSFUL in 1m 6s. The supervisor's final printed acquisition
field was truncated. The actual installed runtime was independently inspected:
`NamedMutex.__enter__` waits for ownership of
`Local\Darka.AndroidGradleBuildGate`; activity inspection, wrapper execution and
confirmed child completion are inside that owned context. The completed wrapper
therefore ran through the acquired shared gate, not merely a queue ticket.

Observed build log: workers=2, parallel=false, Gradle maximum heap
3,221,225,472 bytes, preserved 1 GiB metaspace/256 MiB code-cache arguments.
Assessed Kotlin 2.2.20 uses in-process compilation. JVM test tasks are configured
for one 512 MiB fork and are not executed by assembly. All three fresh app ABI
Ninja outputs retain depth-one `rshop_native` compile/link pools. Existing plugin
pool settings are unchanged; no new claim of a complete fresh plugin census.
No memory failure or budget increase. Existing Kotlin-DSL/Flutter toolchain
warnings remain visible, not bypassed.

The 225,142,700-byte APK has SHA-256
`1538589c0b16b133ad3993be96a7f86613420ef1ee3d1da9096532b26ffd0020`.
Its v2 signature verifies with unchanged signer SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Normal `adb install -r` succeeded without data clearing. Independent installed
`base.apk` hashing matches; the normal replacement process is 19724.
This builds/tests the current integrated S7 worktree, including earlier dirty
changes. It is not a clean-checkout reproduction of this bounded commit alone.

Immediate pre/post installation retained the configuration digest, all nine
private preference-file digests, saved-job observations and published root
active=2/pending=null/next=3. Private protected-file journals
`update442-before-protected.jsonl` and `update442-after-protected.jsonl` under
`D:/RShopPrivate/Migration` agree for 146 observed files / 304,569,033 bytes,
with stable observed membership and zero unstable files. The full comparison
still exits 1 because shared PPSSPP is absent/unreadable. Private/custom paths
are not covered; this does not pass complete save-safety acceptance. No emulator
was stopped or reconfigured to force that gate green.

## Normal native lifecycle proof

The installed Library initially displayed Dashboard 26 / All 47,845 / Installed
3,534. A comparable sampled profile reduced inclusive availability-check samples
from 4,878 to 71 and content-comparison samples from 4,779 to 14. Observation
intervals/sample totals differ; these are hotspot samples, not an end-to-end
latency guarantee. The debug VM profiler was restored to disabled afterward.

One normal Resume continued immutable job 76 without Connect/account selection.
Its normal overview advanced to 18,620 lookups. With that job running, normal
navigation entered Library, then Android sleep delivered focus loss. After the
off-screen interval, the same process 19724 remained live. Waking and normal
navigation showed job 76 Running at 18,740, then its scraping workspace showed
18,744 requested / 757 matched / 713 rated / 24,813 pending. No new capture,
terminal outcome rewrite or diagnostic worker restart was used. Library was
responsive after wake; its later All count was 47,843, not an assertion of an
immutable live cache. These entry counts are not canonical game counts.

After sleep again, the current R-Shop input connection reports NORMAL,
responsive=true, empty outbound/wait queues. Exit-info contains no process-19724
exit; its retained old process-7116 ANR is historical, not a new failure.
Both actual/committed displays are OFF and wakefulness is Asleep.
The temporary device UI capture was hash-rechecked, removed and confirmed absent;
only this check's VM forwarding port was removed. Private journals are retained.

This verifies the reproduced availability hotspot and normal sleep/wake workflow,
not indefinite unattended reliability. Full fresh metadata, scoped/provider
passes, defensible canonical Top-25 sets, current cloud/format recoverability
and reviewed exact SD migration remain S7 acceptance work. No ROM removal,
cloud mutation or external save-sync change follows from this correction.
