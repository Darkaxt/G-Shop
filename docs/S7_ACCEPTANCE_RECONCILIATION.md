# S7 live metadata and Thor migration

## Current acceptance matrix — S7 COMPLETE, 2026-10-11

Authority: SPECIFICATION.md revision 23, including the owner's revision-20 exact
Top-25 cleanup directive and clarification that exhaustive scraping was never
required. This matrix supersedes historical outstanding-work lists below.

| Required result | Verified evidence |
| --- | --- |
| Fresh metadata, not stale imported baseline | Actual fresh provider jobs and persisted outcomes are recorded below. Current read-only device evidence confirms completed scoped ScreenScraper job 73 and IGDB jobs 72/75, plus preserved pause/resume of job 76. Full-library completion is optional, not a gate. |
| Existing-score sample capped at 25 per console | Private reviewed keep-list and terminal reconciliation retain 25 N64, 13 PSP and 2 PS2 ROMs; no fabricated padding, unrated refill or uncapped extras. Zero eligible retained games in another scope is allowed by the owner's directive. |
| Exact reviewed cleanup and no refill | Private completed journals and `top25-cleanup-verified-20261011.json`: 15,718 removed ROM/companion files, 704,092,184,748 bytes. All 27 reviewed console targets have the no-refill guard; archival download profiles are unchanged. No new full cloud-stream proof is inferred. |
| Retained files, space and protected data | Terminal independent reconciliation: 247 files / 18,774,960,690 bytes; 40 actual retained ROMs, other files preserved. Free space 957,752,320 KiB. Latest preserving update additionally matches all 159 explicitly checked shared save/BIOS/settings files. No universal private-save coverage is claimed. |
| Normal on-demand recovery after cleanup | Removed Game Boy test archive restored through R-Shop and opened to its RetroArch title screen; independent size/digest checked; removed normally afterward and original keep-list/space reconciled. Earlier documented format-specific recovery evidence remains applicable to unchanged transfer/handoff boundaries. No deep in-emulator save testing is required. |
| Requested plain-language and playback UI | Wording update 619 and playback update 634 are installed and inspected on Thor. Icons, accessible names, touch Resume/Pause and idle/running guards pass. Focused widget checks cover controller activation, compact layouts and detail views. No fresh full scrape was started for visual verification. |
| Local-absence metadata regression | Reproduced no-network assertion before correction; focused runtime/boundary checks now pass for absent root/nested files, present-file current-cloud validation, changed identities, unsafe roots and cancellation. Native bridge is unchanged; normal integrated assembly/update passes. This does not claim repair of an unrecorded transport response. |
| Safe delivery of bounded changes | Shared-gate assembly 634 exit 0, scoped analysis and whitespace checks pass. Installed APK digest matches build; configuration/root/jobs/private preferences preserved. Original metadata job is paused and both displays are actual/committed OFF. |

Blockers: none. Required tracked deferrals: none. S10/S11 remain required under
their own criteria; S7 closure does not claim the whole project is complete.

## Current scope correction — 2026-10-11

Specification revision 23 records the owner's clarification: scraping every ROM
was never required. Full saved-job completion and exhaustive console/provider
passes are not acceptance gates. Representative fresh metadata and resume
workflows are recorded below; optional job 76 remains preserved without forced
completion. Missing scores must stay truthful, not delay verified SD cleanup.

The owner-directed cleanup, retained set, space and post-cleanup restore are
verified, as are the requested bounded controls/correction in the matrix above.
Earlier contrary requirements and historical stage statuses below are superseded
by revision 23 and the current acceptance matrix.

## Owner-directed cleanup and restored small game — 2026-10-11

The revision-20 one-time cleanup and all retained-file/space checks are recorded
in the current status ledger. After cleanup, one previously removed Game Boy
archive was downloaded normally from Drive through R-Shop and launched through
Open in RetroArch to a visible title screen. Its independently checked local
size/MD5 match the downloaded file. This establishes the small game's normal
post-cleanup recovery path, not fresh metadata coverage or every format's recovery.

The temporary installation was then removed through normal R-Shop confirmation;
its accidental favorite change was undone. A fresh read-only reconciliation of
the original inventory, completed journals and current device tree passes again:
247 remaining files, exactly the 40 retained ROMs, all keep-file stats unchanged,
no hidden quarantine and 957,752,320 KiB free. The original protected content is
preserved. Both physical screens are OFF. Private screenshot evidence is retained
outside the repository. No new successful full-cloud comparison is claimed.

Revision 21 additionally assigns the user's existing-window language review to
UI-02 in S7. Host checks pass for the revised comparison, metadata, save-backup
and companion copy, including explicit actions, failure/cancellation, conflicts,
controller access and compact layout. Assembly 617 failed on Windows argument
parsing; after its confirmed exit, corrected shared-gate assembly 619 passed with
two workers, no parallelism, a 3-GiB Gradle heap and Kotlin in-process. No memory
failure occurred. The signer-preserving debug update is installed and its APK
digest matches `a84edfa239a66b4c8d698ad9737315e29d2be829a08f13a46888930c3f8cac13`.
Configuration/private preferences and protected shared content were preserved.
Normal native navigation verified metadata/save setup, the comparison popup and
its expandable details, and the companion picker. No comparison/adoption,
download or companion change was started. Both screens are verified OFF again.
This closes the bounded wording review, not the remaining S7 acceptance criteria.

## PPSSPP protected-location observation — 2026-10-09

Read-only checks distinguish an absent legacy `/storage/emulated/0/PSP` from
unreadable save content: the directory is absent. Both installed PPSSPP
app-specific external `files` directories are present and have no descendant
directories. A normal launch of `org.ppsspp.ppsspp/.PpssppActivity` shows the
first-run memory-stick choice (choose/create PSP folder or app-private data).
No choice was made and no emulator settings, owner saves or ROMs were changed.
This does not establish absence of private or differently located saves, nor
does it invalidate the separate previously observed exact-URI game boot.

The hardcoded shared-path baseline must remain explicitly incomplete; do not
reinterpret its missing PSP scope as passing full PPSSPP saved-data coverage.
Before migration, resolve applicable save/settings preservation independently
of that nonexistent default path. S10's emulator backup/path-mapping feature is
still NOT STARTED; this S7 safety observation does not begin it. The existing
R-Shop worker remains live in process 19724. Both display actual/committed states
are OFF after the inspection; temporary diagnostic images are not deliverables.

## Exact selection migration retry — 2026-10-09

CORE-03/UI-02 review reproduced a failed legacy-favorites write retaining a
rejected migration future and discarding its pending input. The next normal
Library recovery therefore could not retry. The regression failed before the
correction; the notifier now retains pending selections until acknowledged
persistence and clears only failed migration work. No timer, automatic retry,
account reset or owner preference mutation was introduced.

Fresh serial host verification passes the affected selection/discovery/exact-copy
projection cases, plus storage/shelves, installation visibility, ROM management,
merge/list/detail actions, owned emulator grants and recovery-review integration.
Scoped analysis of the notifier/regression and `git diff --check` pass. Existing
native local-first/provider and Sega recovery evidence below remains applicable
to unchanged boundaries; it is not live injection of a preference-write failure.
Shared-gate request 449 (`ea134f7532f649bda4641efcaa8c572b`) completed the focused
`OwnedGameGearZipTest`/`OwnedRomGrantPathTest` cases and normal debug assembly,
exit 0, with gate acquisition and completion verified. Log:
`%LOCALAPPDATA%/Tools/gradle-build-gate/logs/a5e533fb6d144d48a5e6eac5ae90b927.log`.
Observed workers=2, parallel=false, Gradle heap=3 GiB, Kotlin in-process, one
512 MiB test fork with fail-fast enabled and failures not ignored. App's active
`build/.cxx/debug/334d1i5j` Ninja compile/link blocks use a depth-one pool for all
three app ABIs; stale `android/app/.cxx` files are not this build's evidence.
The active SoLoud and JNI Ninja files independently confirm depth-one pools for
all four plugin ABIs, with their compile/link blocks assigned to those pools.
No memory-related failure or heap increase occurred. Plugin/SDK/deprecation
warnings remain visible; this is not a warning-free or toolchain-upgrade claim.

An additional regression then reproduced a rejected legacy version write being
reported as successful. The installed SharedPreferences implementation changes
its process cache before platform acknowledgment, so ignoring its false result
also presents a nondurable migration version. The correction rejects false
acknowledgment and reloads durable preferences on failure. Fresh serial
selection/storage/shelf/Library checks and scoped analysis pass, including normal
retry after the first selection write committed but its version write failed.
Assembly 449 predates this final Dart correction. Subsequent assembly request
451 (`35d8170b26204ce2a23537df9282d77b`) completed exit 0, with the shared gate
actually acquired and completion/profile verified. Observed workers=2,
parallel=false, Gradle heap=3 GiB and assessed Kotlin in-process; preserved
metaspace/code-cache arguments remain. Test tasks retain one 512 MiB fork at
configuration only; assembly does not execute them. The unchanged app/SoLoud/JNI
depth-one native pools retain the separately inspected evidence above. No memory
failure, increased budget or concurrent R-Shop test workload occurred. Log:
`%LOCALAPPDATA%/Tools/gradle-build-gate/logs/674c67e6c0804bc5b86ee83467a1c3ea.log`.

The 225,138,941-byte APK has SHA-256
`d15847910026f1bf2102d58b0bd91e3d43e07c7a33e9a12ba30c52a7e726274c`;
signature verification retains the existing signer. Normal `adb install -r`
succeeded, and independently hashing installed `base.apk` matches. Immediate
pre/post-installation configuration, all nine private preference-file digests,
published root (active=2/pending=null/next=3) and paused saved-job objects agree.
Configuration digest:
`4f4e2f0c2462d60bd5259ca30045cc3497a42a61e97bb2b23daf8984745a2dd6`.
Private before/after journals under `D:/RShopPrivate/Migration` agree for all
146 observed files / 304,569,033 bytes, with zero unstable or changed files.
The comparison still fails full coverage because the default shared PPSSPP
scope is absent/unreadable; private/custom saves are not proved absent or safe
by this baseline. Preserve that qualification and resolve migration save safety.

Normal Resume in replacement process 28840 continues the same immutable job 76
without Connect/account selection: 19,284 paused before the update, 19,350
requested / 24,180 pending / 735 rated afterward, then 19,364 on the normal
provider overview. No capture or terminal outcome was rewritten. This closes
the current preserving-update/resume check, not full fresh metadata coverage.
Normal Library entry also finishes loading Dashboard 26, All 47,815 and Installed
3,537, with direct console tabs, while the same process/job remains live. These
are current entry counts, not canonical games or proof of ranking completeness.
The consumed device UI XML was digest-rechecked, removed and confirmed absent.
Both committed displays are OFF after normal sleep.

Read-only observation confirms published root 2 and the same running job 76 at
19,036 requests, 770 matched / 724 rated / 24,508 pending, with no blocked issue.
These are immutable-job observations, not complete collection/ranking coverage.
S7 alone remains ACTIVE; migration and S8-S11 have not been performed.

## Library sleep ANR — 2026-10-09

Update-436 process 7116 terminated with Android reason 6 (ANR), input focus-loss
dispatch exceeding 5,005 ms. This supersedes any inference that the persisted
job-76 `running` field proves a continuously live worker. The last post-exit
observation is 18,606 requested / 24,954 pending / 703 rated; the same immutable
job must recover and resume normally, never be replaced. Ordinary Library VM
sampling in the confirmed replacement process identifies repeated full-list
exact-installation queries/ID encoding as the UI-isolate hotspot. The bounded
availability regression fails before indexing and the focused host checks pass
afterward. Gated assembly 442, preserving update and normal Library/sleep/wake
checks now pass; same process 19724/job 76 advances 18,620 -> 18,744 without
sign-in. Both displays are OFF. See `S7_LIBRARY_AVAILABILITY_INDEX.md` for actual
profile, scoped preservation and unattended-reliability limits. S7 remains ACTIVE,
S8-S11 NOT STARTED, and no removal is authorized by this fix.

## Published root and bounded native ranking query — 2026-10-09

Root generation 2 has published (active=2, pending=null, next=3). This closes
the root-publication gate, not metadata/retention/migration acceptance. Preserving
update 436 retained exact immediate configuration/private preferences/saved-job
observations and independently matches the built APK. Normal Resume advances
the same job 76 to 18,548 requests / 25,016 pending / 701 rated without sign-in.
The normal existing PSP Best-25 query completes with 35/334 ranked, 25 matching
and provisional coverage. Host and native read-batching verification, actual
resource profile and qualified protected-file comparison are documented in
`S7_RANKING_CATALOGUE_READS.md`. Both screens are OFF.

Full fresh immutable traversal, required scoped/provider passes, defensible
canonical retained sets, exact current-cloud recovery and reviewed journaled SD
migration remain unsatisfied. Unstable emulator-config observations and unreadable
shared PPSSPP do not pass a full saved-data gate. S7 alone is ACTIVE; S8-S11 are
NOT STARTED. No ROM was adopted/removed and no external sync policy changed.

## Native policy and nested execution — 2026-10-09

Normal Library policy rebuild completed, and explicit Wii/Wii U Best-25 controls
report truthful zero eligible results with provisional coverage. A fixed bounded
READONLY join verifies two ordinary job-76 nested GBA raw-ROM bindings against
their exact post-update full-container observations. This satisfies native path
execution, not provider acceptance, complete coverage or removal permission.
Original filters/configuration remain preserved and both screens are OFF. See
`S7_NATIVE_POLICY_AND_NESTED_PROOF.md`.

Root generation 2 remains pending with 21,857 committed pages in the same live
observer session. Immutable job 76 is Running: 16,571 requested / 27,099 pending,
no blocked status. Publication, full fresh coverage, required scoped/provider
passes, defensible canonical retention and reviewed exact SD migration remain
S7 acceptance work. S7 alone is ACTIVE; S8-S11 are NOT STARTED.

## Preserving update and native DSi mapping — 2026-10-09

Installed APK 435 now supplies the normal editor: unchanged save preserved all
existing mappings/systems and seven ordered source objects; explicit DSi choice
added only that console, and normal Android folder selection changed only its
target to existing DSiWare. Immediate pre/post replacement preservation and
same-job no-chooser continuation are recorded in `S7_NATIVE_UPDATE_435.md`.
The existing observer measured generation 2 at 20,639 committed pages; job 76
is Running at 16,321 requested / 27,359 pending, no blocked status. Publication,
complete fresh metadata, native policy/nested execution evidence, defensible
retention and exact reviewed migration remain unfinished. S7 alone is ACTIVE;
S8-S11 are NOT STARTED. No ROM was adopted, moved or removed.

## Current ranking observation and PS1 identification boundary — 2026-10-09

A sequential READONLY observation used the existing bounded retention helper,
not a database export or new scrape. Its device jar matches the retained host
SHA-256 `6a72a452b5d1e5de3dbccde071d3dec3780437917d63fd1f2517e7863125fa6c`.
The helper opens the fixed database READONLY, uses a 128 MiB VM and emits at most
128 members / 1 MiB. Only the following aggregates were retained in this report:

| Console | Projected canonical groups | Ranked groups | Physical members |
| --- | ---: | ---: | ---: |
| PS1 | 372 | 0 | 372 |
| PSP | 334 | 35 | 334 |
| PS2 | 217 | 59 | 222 |
| N64 | 1,527 | 55 | 1,527 |
| GameCube | 203 | 0 | 203 |
| Game Gear | 546 | 0 | 546 |

All six observed scopes have zero unbound artifacts, but the global dirty queues
are nonempty: 1,709–1,711 edition rows and fifteen artifact rows during these
separate reads. These are observational cached counts, not an atomic snapshot,
fresh normal-query results, complete ranking coverage or deletion authority.
Normal Library projection refresh must precede the next retention review; do not
clear dirty rows through a diagnostic or interpret the global counts as per-console
defects. Every response reports `removalAuthorized=false`.

The proposed lower-bound shortcut (a current rank above 25 cannot improve when
unrated games obtain scores) assumes a fixed set of distinct canonical games.
That condition is not established here: `LibraryStore.reindexCanonicalGroups`
uses connected provider/identity claims, and resolving an edition can bridge
existing groups. Neither the normal retention page nor this observer proves
that identity set fixed. Preserve the current provisional-ranking guard in both
Dart and the private audit; a rank number alone does not justify relaxing it.

Existing completed PSP/PS2/N64/Game Gear/GameCube aggregate passes are recorded
below. Do not repeat them solely because this read-only projection is incomplete;
new passes need the current normal identity/provider boundary, not a test-count
target. PS1's zero eligible groups has a distinct identification limitation:
`MetadataRefreshJobs._bindRomIdentifier` does not accept `psx`, and the current
CHD parser deliberately requires DVD metadata and 2,048-byte units. It must not
reinterpret CD headers as original ISO hashes. The LoLSuite conversion path was
also inspected: it records archive member paths/sizes but does not retain their
raw MD5/SHA-1 as an existing provenance source. No raw identifier can be imported
from those absent facts. This explains a missing automatic identity route, not
every PS1 provider outcome or a newly approved CD decoder. Resolve identity
coverage through the existing META-03 evidence rules; preserve unresolved games
and the current CD-header rejection until an exact supported route is verified.

S7 remains the sole ACTIVE stage. No metadata requests, projection writes,
ownership changes, ROM/save operations, APK installation or account change were
performed by this audit. The existing root refresh and saved job 76 continue;
S8-S11 remain NOT STARTED.

## Nested local metadata lookup — 2026-10-09

The root-only identifier lookup misses actual nested local archives. A bounded
READONLY native sample establishes fourteen exact nested paths without root
copies, not a whole-collection identity claim. The correction checks only one
safe, validated ancestor-ID-derived parent after root absence, preserving
container/raw/current-cloud proof and no ownership or remote ROM-body request.
Regression-first runtime/boundary checks and scoped analysis pass. Gated request
435 completed native assembly with observed low-memory profile and verified
unchanged signer; its final gate-acquired field was truncated, as documented in
the evidence record. The artifact remains uninstalled while root refresh advances
to 7,630 committed pages. Normal owner workflow verification remains pending;
existing saved job 76
membership/terminal outcomes are preserved. Full fresh coverage, trustworthy
Top-25 retention and reviewed migration remain open in sole ACTIVE S7.
See `S7_NESTED_METADATA_IDENTIFICATION.md`; S8-S11 remain NOT STARTED.

## Combined native artifact — 2026-10-09

Request 434 completes actual current-worktree debug assembly, with the shared
gate acquired, effective low-memory profile verified and unchanged APK signer.
Independent current Ninja inspection verifies depth-one native compile/link
pools. No memory failure or budget increase occurred; JVM tests were configured,
not executed by assembly. Exact scope/artifact/profile: `S7_NATIVE_BUILD_434.md`.

This does not satisfy native mapping/policy acceptance. The built APK has not
replaced the advancing Thor process; root generation 2 reached 5,889 committed
pages without interruption, with both displays OFF. Same-job continuity and all
remaining fresh coverage/retention/cloud/migration gates remain required in sole
ACTIVE S7. S8-S11 remain NOT STARTED; no owner ROM was adopted or removed.

## Wii/Wii U reception and cached ranking — 2026-10-09

META-05/META-07 scope gap: existing Wii RVZ/Wii U WUA restore proof did not
approve a ranking basis. The serial public benchmark and independent reception
assessment now support extending the existing IGDB community basis to both
scopes, without changing vote support, score precedence, identity or removal
rules. The disagreement/coverage limitations are explicit in
`SCORE_RECEPTION_ASSESSMENT.md`. Regression-first boundary checks and real SQLite
cached-policy refresh/retention pass, as does scoped Dart analysis. A second real
provider capture preserves the same source facts and ranks eight supported
public releases offline; two sparse-vote records remain unranked/provisional.

Native policy/editor integration is still required, not a tracked deferral or
stage closure. No Gradle build or APK update was performed for this policy.
Read-only live inspection confirms process 1335, advancing root generation 2
(5,405 committed pages) and saved ScreenScraper job 76 Running (13,919 requests),
with unchanged configuration hash. Both displays remain OFF. Full fresh metadata
coverage, defensible per-console retained identities, current-cloud checks and
reviewed exact SD migration remain unsatisfied S7 acceptance criteria. S7 is the
sole ACTIVE stage; S8-S11 remain NOT STARTED. No owner file was removed/adopted.

## Explicit source-mapping selections — 2026-10-09

The editor's alias auto-selection defect is corrected and host-verified through
the real configuration writer, with gated debug assembly and unchanged signer.
Native verification/configuration remains unfinished while PID 1335 advances
the existing root refresh and job 76. The new APK is not installed; no interruption
or account change was performed. Evidence and remaining checks:
`S7_DRIVE_MAPPING_SELECTION.md`. S7 remains the sole ACTIVE stage.

## DSi provider alias and saved-job continuity — 2026-10-08

The live authenticated platform list explicitly names DSi under ScreenScraper
platform 15. The adapter now uses that alias while retaining separate R-Shop
identities and every classification/matching gate. Regression-first provider
checks and two actual reviewable candidate lookups pass. Gated build 432 and
signer-preserving native installation are verified, including effective memory
profile, depth-one native pools and unchanged protected data. Normal Resume
advances the same job 76 without a chooser. See `S7_DSI_PLATFORM_VERIFICATION.md`.
Normal DSi mapping/scoped coverage, root publication/current-cloud checks,
defensible retention and migration remain unfinished; S7 alone is ACTIVE.

Consumed query-cost diagnostics were transactionally removed under review
`e4b1516b81be4621b7589e53459e2d55`: five exact local members / 25,672 bytes and
two identity-rechecked device jars, with absence verified and no errors.
Verification evidence, source, private migration census and owner files remain.

## Cold subfolder traversal work regression — 2026-10-08

Build 428 eventually populated the normal Library, but native database lifecycle
evidence records repeated roughly 4.2-second recursive subfolder pages during
startup. Inspection identifies ROM leaves entering the recursive work queue even
though they cannot have children. A regression executes the actual production
recursive CTE over eight folders and 2,048 ROM leaves: it failed with 2,057
expanded nodes instead of the nine required folders. The revised CTE expands
folders only and selects the bounded ordered child-entry page separately.

The affected real SQLite catalogue/provider checks pass, including generation
replacement rejection, indexed parent/exact lookups, nested/page order, resource
subtree exclusion and snapshot failure preservation. Scoped analysis and diff
checks pass. This is host work-count/behavior evidence, not a native latency
claim. Shared-gate request 431 (`9c56d71ac9164c89a8cf968a474eb815`) / retained
session 99153 completed exit 0, with completion verified by the supervisor.
The observed profile is two workers, no parallel projects and 3 GiB Gradle;
Kotlin uses the assessed in-process strategy. One 512 MiB JVM test fork was
configured, not executed by assembly. All 281 inspected native compile/link
edges across 11 ABI files use depth-one pools. No memory failure or budget
increase occurred. The final tool output omitted the gate-acquired field through
truncation; do not infer that separately inspected field from a queue ticket.
Private log: `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/6d864e5ad2c14d5fa30224f2735c9f96.log`.

Normal joined Pause retained job 76 at 13,093 requested / 30,761 pending /
396 rated. Signer-preserving install-replace succeeded; installed base.apk
matches APK SHA-256 `7095a0af66b3ffa06f1d074eac3ca14ce03070fc22e6cd7b16583a23fa0436b9`.
Its unchanged signer verifies, and immediately pre/post configuration and both
protected-storage hashes match. New process 11960 completed normal shared
metadata recovery (1,136 bindings / 1,145 artwork receipts, 19,613 ms reported).
Normal Resume advanced the same saved job to 13,099 lookups without an account
chooser, new capture or changed provider credentials. Library progressed from
loading to Dashboard 25 / All 44,679 / Installed 2,927 on that process. These
are observed projected entry counts, not immutable canonical game counts.
Cold startup still took several minutes. A joined-Pause, fixed read-only native
diagnostic now isolates the revised production SQL: 500-row pages take 43 ms
for DS, 141 ms for NES and 10 ms for SG-1000/SC-3000. Android's actual plans use
exact anchor/payload lookups and indexed parent expansion/child pages. Active
generation 1 and pending generation 2 are unchanged before/after this bounded
observation; it is not current-cloud proof or an atomic whole-catalogue snapshot.
Normal Resume retains job 76 after that diagnostic, and all 49 protected hashes
plus the original ROM digest match. See `S7_CATALOGUE_QUERY_VERIFICATION.md`.
This closes the query-cost check, not the remaining total-startup latency.
S7 alone remains ACTIVE; full coverage, defensible retention and migration stay
open. Both displays are switched OFF between native checks.

## Native byte-review notification regression — 2026-10-08

S7 remains ACTIVE. Normal read-only verification of the original SG-1000
Bank Panic ZIP on build 423 confirmed current Drive version 3 and full SHA-256
`698061e44720f1516866104033975fd2be1a6af85a7e11b1dddf5e29d25c0471`.
The detail primary action changed to OPEN without adoption, but returning to
Library retained two cards (172 entries). The shared installed-files provider
was not invalidated: the journal-only write emits no filesystem/download event.

Regression-first dialog checks reproduced the missing shared signal after both
verification and adoption. The dialog now bumps the existing ROM-change signal
only after the actual runtime operation drains; historical reads do not signal,
and cancellation cannot signal before drain. Focused dialog, local Open and
Library identity/lifecycle checks pass; scoped analysis reports no issues.
Native build and the normal local-first workflow are now verified below. No
unmanaged file was adopted or removed.

Build 428 (`32b5e151c4304875a6619fe8485c98ba`) completed exit 0 through the shared
build-gate supervisor, with verified completion. Observed workers=2,
parallel=false, Gradle heap=3 GiB and the assessed Kotlin in-process strategy;
one 512 MiB JVM test fork was configured, not run by assembly. All 281 native
compile/link edges across 11 ABI files reference depth-one pools in their included
rules. No memory failure or budget increase occurred. Private build log:
`%LOCALAPPDATA%/Tools/gradle-build-gate/logs/4affdc94a6cf4eb6afaaab24ae9bf341.log`.
Signer-preserving installation verified APK SHA-256
`31b3f571692d77e4fa7fbf0ac8ec34ab48acf8882593edd0c5f3ff715ce7fc53`, matching the
installed base.apk. Immediately pre/post installation configuration and both
protected-storage hashes match. Normal joined Pause retained job 76 at 12,907
lookups / 30,958 pending / 390 rated. Normal Resume on the updated process shows
the same job Running without a chooser. All 49 protected save/state/configuration
hashes and the original ROM checksum still match.

On the same updated process, normal Library eventually populated Dashboard 25,
All 44,682 and Installed 2,927. SG-1000 shows 171 entries and one installed Bank
Panic card, not the prior duplicate pair. Normal detail exposes OPEN and no DELETE
action for this unmanaged file. A fresh Verify bytes operation completed at
23:03:43 device time, confirming version 3 and the complete SHA-256 above without
adoption. Returning from the dialog and later the emulator retains the single
installed card. The native test begins with persisted byte evidence; it does not
claim a deliberately triggered native two-to-one transition or disappearance.
The missing notification's red/green and lifecycle boundaries remain host-tested.

Normal OPEN dispatched the observation-bound `copy` document URI (not a fabricated
installation) to installed RetroArch Genesis Plus GX. The actual animated game
title screen was visually inspected. Its speculative sibling `.sg` URI was denied;
the exact ZIP was readable. The app's existing task was brought back to the front,
without resetting either application. All 49 original save/state/emulator-config
hashes and the original ZIP checksum still match after launch. Two private capture
files were removed through reviewed cleanup transaction
`1640741725f5d3e06ab21b5119ccdc3f` (138,178 bytes, no residuals).
This closes one normal unmanaged local-first workflow, not full S7 acceptance.
Full fresh coverage, defensible retention, remaining formats/current cloud and
reviewed migration still require completion. Cold Library population remains
slow; no startup-latency guarantee follows from eventual loading.

## Build 423 and SG-1000 recovery closure — 2026-10-08

S7 remains ACTIVE. The normal SG-1000 `.sg` ZIP online/cold-offline/removal/
identical usable restore cycle passed. Original target/full config and all
49 save/state/emulator-config digests are restored/unchanged; test artifacts are
absent. The normal queue resumed without account selection after hotel portal
authorization restored Google HTTPS. Details are in `S7_SEGA_RECOVERY.md`.

Temporary authorization-service failure no longer enters the consent-required
queue state. Focused regression-first engine/queue checks and scoped analysis
pass; a deliberate native outage was not reproduced after network recovery.
Build 423 passed with gate acquired, two workers/no parallelism, 3 GiB Gradle,
Kotlin in-process, one configured 512 MiB test fork and verified depth-one native
pools. The installed APK matches its verified signer/artifact and preserves
immediate pre-update configuration/protected storage. Normal Resume continued
saved job 76 from 12,720 to 12,725 requested / 31,149 pending without sign-in.

Full metadata/defensible retention/current cloud/local-first/remaining recovery
and reviewed migration criteria remain open. S8-S11 remain NOT STARTED. Older
checkpoints below are historical, not current build/network blockers.

## Build 421 and SG-1000 checkpoint — 2026-10-08

S7 remains ACTIVE. Build 421 passed through the shared gate with workers=2,
parallel=false, 3 GiB Gradle and Kotlin in-process. Configured JVM test forks are
one at 512 MiB; assembly did not run them. Every inspected native compile/link
rule uses a depth-one pool. No memory failure or increase occurred. The installed
APK matches the verified artifact and existing signer; immediate pre-update
configuration and both protected-storage digests are unchanged. Job 76 was
normally confirmed Paused at 12,720 / 31,154 pending / 383 rated before updating.

Normal Library startup now populates Dashboard 25 / All 44,685 / Installed 2,855,
and SG-1000 has one installed Bank Panic card. The host regression separately
proves the invalidated selection-migration subscription contract. Normal ZIP
download and actual Genesis Plus GX title-screen boot passed, with the original
ROM checksum matching the isolated copy. Cold-offline/restore/cleanup remain
unfinished. microG's separate unreachable-host crash does not establish token
expiry or loss of persisted selection; no account/data reset was performed.

Full fresh coverage, defensible retention, current cloud comparisons, remaining
local-first/recovery evidence and reviewed migration remain required. S8-S11 are
NOT STARTED. No bulk migration or release occurred.

## Current startup lifecycle checkpoint — 2026-10-08

S7 remains ACTIVE. Corrected shared-gate build 416 passed and installed without
changing signer, config or protected credential storage. The previous build 415
failed on argument quoting, not memory. Normal Resume of the same saved job 76
advanced to 12,699 requested / 31,174 pending / 383 rated without sign-in. It is
Running; join Pause before installing the next update. SG-1000's isolated target is empty and awaits its
normal recovery cycle/restoration; no new ROM change occurred.

Library startup is not yet native-verified: after SQLite becomes idle, read-only
VM inspection still finds loading=true, an empty game list, populated installation
state and an invalidated/unmounted selectionContinuityProvider with an unresolved
future. A provider read is not a subscription, so invalidation cancels the old
operation without scheduling its replacement. A regression reproduces the hang;
the minimal screen-owned subscription passes it and the affected discovery and
exact-copy continuity checks plus scoped analysis. Native verification awaits
shared-gate ticket 421 / retained session 19661. Cached SQL
latency and the earlier ANR are not falsely declared resolved by this host result.

All full-coverage, retention, current-cloud, local-first, remaining recovery and
reviewed migration gates remain in force. S8-S11 are NOT STARTED.

## Current Master System and library checkpoint — 2026-10-08

The normal `.sms` ZIP download -> online boot -> cold offline boot -> exact owned
removal -> identical usable restore -> removal cycle passed. Normal destination
and full config digest are restored. The original ROM and all 49 recorded
save/state/emulator-config baselines are unchanged; test target/captures are
absent. See `S7_SEGA_RECOVERY.md`. This satisfies only that format's recovery gate.

The earlier input-focus ANR remains unproven as fixed. The previous process exited;
new normal navigation passed after slow loading. CPU profiling identifies whole
catalogue recovery and artwork hashing for unrelated consoles. The minimal
consumer correction skips game metadata reads on dashboard and requests the
selected console only on console pages; explicit cross-console views retain
their normal scope. Regression-first dashboard/console checks and existing
ranking/intersection/shelf/selection checks pass, as does scoped analysis.
Native verification awaits shared-gate ticket 415 / session 40791. Normal Resume
continued job 76 without a chooser: 12,531 -> 12,542 lookups / 31,333 pending,
374 rated. It is Running, not completed or replaced. Join normal Pause before
installation. S7 alone
is ACTIVE; SG-1000 recovery, local-first proof, full fresh coverage, defensible
Top-25 retention and reviewed migration remain open. S8-S11 are NOT STARTED.

## Mega Drive normal recovery checkpoint — 2026-10-08

The normal mapped `.md` ZIP cycle now passes on the Thor: Drive queue/publication,
actual online boot, cold offline boot with no active default network, normal
reviewed owned removal and identical usable re-download. The test was returned
to its planned absent state; normal destination and full configuration digest
are restored, original ROM/save/state/emulator-config baselines are unchanged.
Wi-Fi is restored. `S7_SEGA_RECOVERY.md` records the bounded evidence. Native
provider instrumentation alone is no longer the only Mega Drive recovery proof.

The same saved metadata job 76 resumed normally from 12,287 to 12,289 lookups
without sign-in, with 31,599 pending. This is continuation, not full coverage or
diagnosis of its earlier pause. A separate observed menu-label defect omitted
the three Sega console IDs from the RetroArch label set. Focused regression-first
checks pass after the minimal correction. Build 408 / session 68644 completed
with the shared gate acquired and the low-memory profile verified. Its installed
APK matches the built artifact and preserves configuration/protected storage.
Normal Resume on that update advanced the same job from 12,359 to 12,361 lookups
/ 31,525 pending without sign-in. Normal owned-copy menu inspection passed for
the Master System test download and actual online Genesis Plus GX boot was
visually inspected; a legacy unmanaged copy correctly does not expose that
owned action. Cold-offline/identical-restore and target restoration remain open.

Master System/SG-1000 normal recovery, local-first UI, fresh coverage, defensible
Top-25 retention and reviewed migration remain unfinished in sole ACTIVE S7.
S8-S11 remain NOT STARTED. No owner ROM or cloud mutation/bulk migration occurred.

## Current native/session checkpoint — 2026-10-08

S7 alone remains ACTIVE. Normal APK and instrumentation builds 389/391 completed
with the shared gate acquired, observed workers=2, parallel=false and 3 GiB
Gradle heaps with Kotlin in-process. Generated app/SoLoud/JNI Ninja compile/link
rules use depth-one pools. One-fork/512 MiB test settings were configuration-time
observations, not an assembly-time JVM test run. No memory failure was reported.
The normal APK installed with the existing signer and unchanged config/secure
storage digests. Native provider instrumentation passed, including observed
read-only RVZ/Sega ZIP copies; normal local-first/recovery proof remains required.

The source-change worker correction is now installed, but Resume encountered a
different failure first: noninteractive authentication returned null because the
adapter discarded the connected account on process replacement and never
restored it. Saved source configuration was unchanged. Normal default-account
connection succeeded without saving a different source.

DRIVE-01 now explicitly records cold-start continuity: private account ID/email
reference only, no saved tokens, account-bound native authorization without
prompting, source-ID mismatch rejection, explicit sign-out clearing the reference.
Focused regression-first adapter/coordinator checks and analysis pass. Build 400
completed with gate acquired and observed low-memory profile verified; installed
APK matches SHA-256 `134b657aae6b07a52c4bf2d1ef34c17c1794cd70ed6f5a46421dd055eb80eefb`
and the existing signer. The first ordinary default-account connection seeded the
reference missing from the old implementation. Confirmed process exit/relaunch
resumed job 76 without chooser (12,194 -> 12,199 lookups). A joined Pause and
same-APK install-replace preserved config and both secure-storage digests; its
new process resumed without sign-in (12,204 -> 12,209 lookups / 31,682 pending).
No live owner revocation, account/mapping save, snapshot replacement or ROM action
was needed. Both screens are actual/committed OFF and power Asleep; exact task UI
captures are removed. This closes the cold-start regression, not all DRIVE-01 or S7.
Full metadata/retention, remaining real recovery and reviewed migration criteria
remain unfinished. S8-S11 remain NOT STARTED; no overall completion is claimed.

## Captured-source failure checkpoint — 2026-10-08 evening

S7 alone is ACTIVE. The saved Entire collection job is now Paused, not Running:
12,171 requested, 356 rated and 31,720 pending. One normal Resume reproduced a
typed source-change failure at the live Drive binary verification boundary before
another metadata lookup. The exact mismatching file field is not established;
the job incorrectly treated this captured item's rejection as a whole-worker
failure. Earlier resumed-progress observations do not prove its completion.

Archive and CHD-header regression cases first failed with that exception. The
worker now records the existing `identityChanged` outcome only for the rejected,
uncancelled item and continues independent items in the same saved snapshot.
No raw identifier, accepted metadata, official classification or fresh capture
is manufactured. The affected catalogue-job checks pass, including restart,
cancellation drain and propagation of other failures. Storage/cancellation at
the outcome commit remains transactional; no retries or deadlines were added.

The installed APK does not yet include this correction. Keep its paused job and
resume it through the normal control after the pending native build/update, then
verify real continuation past this item. Ticket 389 / session 99133 remains live;
no gate acquisition or effective profile/build proof is reported. Current native
and full metadata/retention/migration criteria remain open; S8-S11 remain NOT
STARTED. Task-created UI dumps are removed and both screens are confirmed
OFF/Asleep. No ROM, source configuration or ownership changed.

## Saved metadata continuation checkpoint — 2026-10-08

The existing Entire collection workspace was Paused with an operation-failed
notice at 8,876 requests / 35,178 pending. Normal Resume was pressed once for
that selected saved report, not Refresh or Retry. Subsequent normal UI verifies
Running at 8,891 requests / 35,163 pending, with 238 rated results and reported
quota 15,800/20,000 remaining. The outcome/pending cohort still totals 44,204.
This proves resumed progress only; the earlier operation failure's cause and
full coverage are not proved. No account/mapping, ROM or ownership changed.
Ticket 389 / session 99133 remains live without new build output. Current
native proof, full coverage, retention/recovery and migration gates remain open
in sole ACTIVE S7; S8-S11 remain NOT STARTED.

## Current stage status — ACTIVE, 2026-10-08

The user corrected the prior blocked classification: normal FIFO/mutex waiting
is ongoing execution, not a reason to stop. S7 alone is ACTIVE; S8-S11 remain
NOT STARTED. On resumption session 81299 is unknown and supervisor 78196 is
confirmed absent, while ticket 387 retains its stale exact identity. No build
result is available. Submit only one replacement through the normal shared gate,
allow its proven-exit reclamation and retain the new waiting handle. Do not
interrupt GameNative, edit queue state or treat a wait as completed verification.
All original native, metadata, retention/recovery and migration criteria remain
unfinished and required. The BLOCKED checkpoint below is superseded history.

## Current stage status — BLOCKED, 2026-10-08

S7 is parked after the same external native-build exclusion condition recurred
across three consecutive continuation turns. No stage is ACTIVE. The exact
preceding GameNative build processes remain live; request 81299 remains the
same queued live request with no observed gate acquisition or effective profile.
Current native single-card/local-first/provider and Sega ZIP device acceptance
cannot be verified until the preceding build has confirmed completion/idle and
the retained build finishes. Do not interrupt that workload or launch another.

Full fresh coverage, defensible Top-25 retention, current cloud recovery and
reviewed SD migration remain required and unfinished. Existing host evidence
does not satisfy these native/integrated criteria. S0-S6 remain COMPLETE and
S8-S11 NOT STARTED; their dependencies are unchanged. Earlier ACTIVE checkpoints
below are historical. The full implementation objective is not complete.

## Observed Sega ZIP integration checkpoint — 2026-10-08

MIGRATE-01/META-03 now include explicit Mega Drive `.md`, Master System `.sms`
and SG-1000 `.sg` single-member ZIP paths through the existing validator,
transfer/recovery/adoption, metadata worker and exact RetroArch read-only grants.
Host checks verify console-bound mapping, publication/recovery/offline reuse,
no-ownership local evidence, raw-versus-container distinction and restart
continuity without borrowing official classification. The affected runtime,
transfer, handoff and metadata job checks pass, as do bounded Java ZIP/grant
checks, scoped analysis and whitespace checks. No generic archive admission,
32X support, core installation or emulator configuration change was added.

The native provider fixture includes these ZIPs, but current Kotlin/APK/device
verification is still pending the same live build request 81299. Gate acquisition
and effective build profile are unconfirmed. Host checks do not satisfy the
normal Thor online/offline/removal/identical-restore format gate. No unmanaged
file was adopted/removed and no migration gate was waived.

The normal Entire collection workspace reports Running with 36,760 pending,
7,385 requests and 194 rated outcomes. The full pass, defensible Top-25 retention,
native local-first integration and reviewed migration remain open in sole ACTIVE
S7. S8–S11 remain NOT STARTED. Both physical screens are subsequently confirmed
OFF/Asleep; no new job or changed owner configuration is claimed.

## Joined-pause matching evidence checkpoint — 2026-10-08

Normal Pause joined saved ScreenScraper job 76 before the bounded READONLY audit
of 7,147 terminal outcomes. The capture still contains 44,204 members. Normal
Resume advanced that same job from 7,105 to 7,107 requests and reduced pending
from 37,057 to 37,055; no fresh job or per-game correction was created.

Sampled exact-title review results have neither raw identifiers nor an official
classification. They do not satisfy the standardized matching policy's evidence
tier. Preserve those results and unknown/modified edition distinctions rather
than publish scores or manufacture Top-25 membership. The captured 66 Mega Drive
resource failures are historical outcomes whose resource cache rows are already
absent, not grounds to repeat the exclusion fix. This checkpoint does not prove
full coverage or ranking: native local-first proof, fresh-pass completion,
defensible retention and reviewed migration remain required in the sole ACTIVE
S7. S8–S11 remain NOT STARTED.

## Action eligibility / current collection observation — 2026-10-08

The read-only exact-copy Open route does not imply ownership-only sharing.
Normal detail handler, touch rendering and controller focus now use one sharing
eligibility rule. Focused detail/installation/layout checks and scoped analysis
pass; current Java URI-parser checks pass under 256 MiB heaps. Kotlin/native proof
remains outstanding on the same live gated request 81299 / ticket 387, with no
observed gate acquisition or build/profile output. No new APK was installed.

The normal Thor UI confirms the existing full-collection scrape remains running
at 7,046 requested / 37,119 pending, not complete coverage. The job was not
recreated and no mappings were saved. Both displays are confirmed OFF/Asleep.
S7 remains sole ACTIVE; remaining native proof, fresh coverage, defensible
retention and actual reviewed SD migration are not waived. S8–S11 are NOT STARTED.

## Single-card/local-first host integration checkpoint — 2026-10-08

Normal Library host verification now retains one exact sourced identity, artwork,
favorite and shelf through presence/disappearance/restoration, while keeping raw
catalogue membership unchanged. Current-copy inspection, availability and the
Open primary action are integrated; selection persistence includes an atomic
migration receipt and rejected-write readback. Missing or changed copies cannot
gain ownership or removal authority. The affected serial host checks and the
separate native URI parser checks pass.

The read-only native provider/launch route is implemented but NOT yet compiled or
proved on the Thor. The synthetic provider fixture is prepared, not run. The same
live gated build request 81299 / ticket 387 has no observed acquisition, effective
profile or completion output. No APK/device/files changed in this continuation.
CORE-02's complete native workflow, full fresh scrape, defensible Top-25 retention
and reviewed migration remain unsatisfied S7 criteria. S7 remains sole ACTIVE;
S8–S11 remain NOT STARTED. No final completion or release is claimed.

## Exact unmanaged-copy evidence checkpoint — 2026-10-08

The normal metadata archive reader now retains its complete-container checksum
match and post-read native identity in the existing historical observation
journal. Raw-member metadata stays separate from cloud-container equivalence;
neither grants ownership or removal authority. Regression-first host runtime
verification and scoped analysis pass. Native assembly is still queued through
the shared gate (ticket 387, live session 81299); no build/install/device-runtime
success is claimed. See the current status ledger for the continuation handle.

This does not close CORE-02's single-identity requirement. Current copy validation,
stable selection/favorites and native local-first handoff remain ordinary required
S7 work, as do fresh coverage and reviewed migration. S7 is sole ACTIVE;
S8–S11 remain NOT STARTED. Both Thor displays are OFF; owner data is unchanged.

## Availability lifecycle checkpoint — 2026-10-08

CORE-02's existing exact identity is now retained through source-less local cache
fallback without erasing a sourced cloud row or rolling back its newer content.
Ordinary and bulk scans retain journal-verified leaves below containing roots
through the same merge path. Regression-first SQLite/scan checks, affected exact
identity/controller checks, scoped analysis and whitespace checks pass. This is
host verification only; the normal installed APK is unchanged by this patch.
No unmanaged namesake equivalence, adoption or deletion is inferred.

Normal default-account reconnection resolved `interactionRequired`; the existing
job 76 resumes with advancing counters and unchanged configuration. Both screens
are OFF. Fresh-pass completion, wider single-identity integration and migration
remain unfinished acceptance criteria in the sole ACTIVE S7. S8–S11 remain NOT
STARTED. See the current status checkpoint for exact evidence and limitations.

## Console dashboard and readable covers — 2026-10-08

UI-02's console/dashboard refinement is implemented and verified. The global
landing page summarizes cached consoles instead of rendering the whole ROM
collection. Console-scoped search, shelves, Installed/Favorites and pre-ranking
Top-N scope pass focused checks; controller/touch console opening and Dashboard
Back behavior pass in the normal Thor app. Source sizes and exact managed local
bytes are separate, unknown coverage is explicit, and counts are catalogue
entries rather than fabricated canonical-game totals. All supported locales pass
narrow/large-text checks. Readable captions and SD/cloud cover badges pass shared
card tests and normal native inspection. Build/device identities and qualifications
are recorded in IMPLEMENTATION_STATUS.md; complete configuration is preserved.

This does not close S7 or resolve its local/cloud duplicate identity requirement.
Fresh collection coverage, recovery and reviewed migration remain required. The
existing metadata job remains paused; a new full capture-digest audit and scrape
advancement are not claimed by this UI checkpoint. S7 is sole ACTIVE; S8-S11 are
NOT STARTED. No owner files, FolderSync or scheduled save-sync tasks were changed.

## Navigated metadata settings — 2026-10-08

UI-02's settings-navigation slice is implemented and verified: persistent left
sections replace the long single form; provider credentials are edited in a
secure dialog and scraping has its own workspace. Focused widget/detail checks,
normal golden comparison and scoped analysis pass. The final signer-preserving
Thor update verifies initial D-pad/A provider selection, dialog/workspace Back
and separate storage/ES-DE pages. The complete configuration and immutable
44,204-member saved capture remain unchanged before normal Resume. Exact APK,
gate/resource profile, native evidence and verification qualifications are in
IMPLEMENTATION_STATUS.md. No credential, source mapping or owner file was changed.

This is not S7 closure. Readable library titles, stable single local/cloud game
identity and SD/cloud indicators remain required current-stage work, as do full
fresh coverage and the remaining retention/recovery/migration gates. S7 remains
the sole ACTIVE stage, with S8-S11 NOT STARTED.

## Patch-resource eligibility / saved-capture preservation — 2026-10-08

The reproduced palette/HINTS resource defect is corrected at the Drive console
projection boundary, using complete published folder ancestry rather than numeric
title rejection or display-path parsing. Regression-first SQLite provider checks,
saved-job deletion guards, scoped analysis, gated debug assembly and normal
native reconciliation pass. All 68 captured resources leave the game cache;
the genuine translated NES ROM remains. The raw Drive snapshot and cloud/local
files are unchanged. Saved job 76 retains all 44,204 members and an identical
ordered request/status digest, and the complete configuration digest matches.
Exact build/device evidence and qualifications are in IMPLEMENTATION_STATUS.md.

This does not fix the newly observed local/cloud duplicate cards, tiny captions,
full fresh metadata coverage or migration gates. The user requires one stable
game identity with local-first/cloud-fallback availability and SD/cloud indicators;
that remains current S7 work, not a later-stage deferral. S7 is the sole ACTIVE
stage; S8-S11 remain NOT STARTED and no SD removal is authorized by this proof.

## Wii RVZ native recovery — 2026-10-08

The unchanged installed APK and existing exact owned Dolphin route now have real
Wii-specific proof, not an inference from GC. Normal isolated Drive download and
committed publication produce bytes identical to the original. Dolphin renders
startup online; after normal Exit, background-only process reclamation and
confirmed absence of a process/default network, a fresh offline launch reaches
the game's profile screen. Normal owned removal leaves the remote entry and its
cover/basic attributes, and a second normal download publishes identical bytes
and boots to the same screen. This does not prove gameplay, fresh scraped metadata,
archives/bundles or other Wii formats.

Final owned removal and normal Settings save restore the owner destination and
complete R-Shop configuration hash. The exact empty test target is absent; the
original ROM, recorded existing GC save and Wii controller/graphics hashes match.
Normal Wii boot initializes NAND runtime data and a WirelessMac line; omitting
only that generated line reproduces Dolphin.ini's original hash. The sample's
save-data directory is empty and no save/profile action was selected. Whole-NAND
byte equality is explicitly not claimed or manufactured by deleting runtime data.

The same saved metadata job cleanly pauses/resumes and advances real counters;
both screens are OFF/Asleep. Precise verification boundaries, counters, hashes and
private capture location are in IMPLEMENTATION_STATUS.md. No build or production
change was needed. This closes Wii RVZ recovery only: S7 remains sole ACTIVE with
full fresh coverage, defensible retention, other required formats, current cloud
checks and reviewed migration unfinished. S8-S11 remain NOT STARTED.

## GameCube RVZ / Dolphin grant lifetime — 2026-10-07

Normal owned Drive download produced complete matching RVZ bytes, but Dolphin
2606 reported its exact content URI nonexistent. Upstream StartupHandler and
EmulationActivity finish the launcher before starting emulation; the intent-owned
grant disappears with that activity. ContentHandler already supports the existing
URI and metadata columns, so changing URI shape or widening provider access is
not required. The fix gives only Dolphin an explicit read grant for the exact
preflight-validated URI. Strict ownership/publication/native-object validation
at every provider open is unchanged; no prefix/tree/write/persistable permission.

Regression-first host wiring and affected handoff contracts pass, as do fresh
native grant tests and gated debug assembly. Host wiring is not represented as
an Android lifecycle simulation: the native proof closes that boundary. On Thor,
the normal owned copy boots to the title screen online and from a fresh Dolphin
process with no active default network. Normal removal retains its remote entry
and metadata; reconnect/resume downloads identical bytes and the restored copy
boots again. This is boot/title proof, not a gameplay or whole-console coverage
claim. Original ROM, existing save and Dolphin config/controller hashes match.

Normal final removal cleans only the isolated test copy. Normal Console Settings
save restores the owner's complete configuration hash, and the empty target is
removed. The same saved metadata job resumes and advances requested/pending
counters. Both screens are committed OFF/Asleep. Private evidence and precise
build/install/control boundaries are recorded in IMPLEMENTATION_STATUS.md.

GC RVZ recovery is verified; S7 remains the sole ACTIVE stage. Wii/other-format
recovery, full fresh metadata coverage, defensible Top-25 retention, execution-time
cloud verification and reviewed migration remain unfinished. S8-S11 are NOT
STARTED. No original ROM, save, BIOS, cloud object or legacy sync was removed.

## NDS catalogue-title discovery — 2026-10-07

Literal listing ordinals prevented NDS title discovery. The narrowly shared
derivation now serves both providers, qualified rating ownership and subsequent
IGDB corroboration while preserving original captures/raw names and classification,
region, ambiguity and score gates. Regression-first adapter, real persistent worker,
affected rating/query checks and scoped analysis pass. Bounded real ScreenScraper
queries produce candidates for all three public samples without publishing an
unknown edition or manufacturing a score. The acquired-gate debug build succeeds;
the preserving native update has independently matching APK/configuration hashes.

Normal hotel-network sign-in resolves the observed microG unreachable-host crash,
and default-account reconnect permits the SAME saved job to advance. Normal joined
Pause, fixed bounded READONLY membership checks and Resume preserve its 44,204
items. Newly processed numbered NDS captures remain intact; the two reached so far
are unmatched, so native positive-candidate publication is not claimed. Diagnostic
processes/JARs finish and are removed before Resume; both displays are OFF/Asleep.
Exact counters, proof boundaries, artifact hashes, build settings and cleanup are
recorded in IMPLEMENTATION_STATUS.md.

This verifies discovery and same-job continuation, not full NDS/collection coverage
or defensible Top-25 migration. S7 remains the sole ACTIVE stage with required
coverage, retention, format recovery, current cloud gates and reviewed migration
unfinished. S8-S11 remain NOT STARTED, including CACHE-01's Settings and automatic
rotation. No original ROM/save/BIOS, cloud data or legacy sync was removed.

## Metadata identifier Pause contract — 2026-10-07

The normal local-archive read exposed typed Drive cancellation escaping as an
operation error after the job had durably paused. Regression-first remediation
translates only a typed cancellation paired with the owning job's actual signal;
it retains resource joining, pending/current item bindings and genuine errors.
Archive/header API and transfer cases, signal/error races, same-job resume and
affected runtime/controller checks pass serially; scoped analysis and shared-gate
debug assembly pass. This is an existing META-06/UI-02 control contract, not a
matching-policy change or permission to recreate saved work.

The preserving native update retains the signer/configuration. Normal reconnect,
same-job progress -> clean Pause -> same-job Resume are observed on Thor. A bounded
READONLY aggregate confirms job 76 retains exactly 44,204 members and the durable
Paused state; no database reader remains when Resume advances again. The temporary
diagnostic JAR is absent, and both displays are OFF/Asleep. Exact host/native
evidence boundaries, counters, APK/configuration hashes and build profile are in
IMPLEMENTATION_STATUS.md. Native timing does not independently prove which read
was cancelled; the exact typed branch is covered by the reproducible host tests.

This control slice is verified. S7 remains the sole ACTIVE stage: required full
fresh coverage, defensible retention, format/current-cloud gates and reviewed
migration remain unfinished. CACHE-01 Settings and actual automatic rotation are
still assigned to NOT STARTED S11, not silently implemented during S7.

## Standalone WUA recovery — 2026-10-07

The existing exact owned-ROM route now hands standalone Wii U WUA to installed
Cemu, with a correctly named details-menu action. Bundles, archive mappings,
unsafe paths and other Wii U formats do not acquire this route. Current identity,
owned publication and read-only exact-leaf grants remain mandatory. Focused Dart
and native grant contracts, scoped analysis and the shared-gate native builds
passed on the unchanged production code now tested on Thor.

The normal native workflow is verified: exact Drive download into an isolated
destination -> Cemu game rendering -> cold offline rendering with no active
default network -> normal owned removal with the remote entry retained -> same
queued identical re-download -> installed state -> Cemu rendering of the restored
copy. Rendering reached the game's credits, not a claimed gameplay session.
Cemu's normal Exit was allowed to finish, including the observed delayed exit;
no process was killed to obtain cleanup clearance.

Only the isolated owned copy and disposable captures were removed. Normal
console-settings save restored the owner's original Wii U mapping; the complete
configuration, original ROM and Cemu settings/controller hashes match their
baselines. The empty test directory is absent. The SAME saved metadata job now
advances real requested/pending counters after normal reconnect/resume, rather
than merely showing Running. Both physical displays are committed OFF and the
Thor is Asleep. Exact hashes and private evidence boundaries are recorded in
IMPLEMENTATION_STATUS.md.

This closes only the standalone WUA recovery slice. S7 remains the sole ACTIVE
stage: full fresh coverage, defensible canonical retention, remaining required
format workflows, current cloud gates and reviewed migration are unfinished.
S8-S11 remain NOT STARTED, including CACHE-01's configurable automatic rotation.
Legacy save-sync mechanisms remain untouched pending verified S10 replacement.

## Large-console retention audit — 2026-10-07

The read-only audit's 2,000-member ceiling was inconsistent with supported
catalogue sizes. Regression-first remediation preserves fixed 128-row pages,
1 MiB transport, complete duplicate/summary validation and explicit byte budgets,
while retaining only bindings for exact inspected SD/cloud artifact keys. The
production ranking and removal gates are unchanged. Focused host contracts and
the repaired production/native SQL-equivalence check pass.

Fresh bounded compilation and a hash-verified helper on the Thor prove offset
2,048 and successful traversal of the complete 10,100-member NES scope after
normal Pause joined the writer. This summary-only traversal intentionally retained
no bindings; it does not prove a reviewed SD manifest. Zero ranks and pending
projection dirt remain truthful and cannot justify removal. Configuration is
unchanged; normal Resume advances the same saved scrape. Both screens were
switched off. See IMPLEMENTATION_STATUS.md for exact observations and boundaries.
S7 remains sole ACTIVE; coverage, defensible sets, current cloud/restore gates
and reviewed execution remain required. S8-S10 are NOT STARTED; old save-sync
mechanisms stay untouched until verified S10 handover.

## Exact-artifact retention review — 2026-10-07

The normal game-detail recovery review now resolves the full current remote
artifact snapshot and its canonical rank/console coverage in one owning SQLite
transaction. It reuses the existing ranking policy, rejects stale snapshots,
duplicate cache bindings and cross-scope namesakes, and never treats missing
evidence as an outside-sample decision. The UI explicitly labels this planning
only; opening or refreshing it starts no byte check, adoption or removal.
Focused real-SQLite and widget checks plus scoped analysis pass.

The acquired-gate debug build passed and the owner update is independently
byte-verified. Normal Thor Library -> PSP game -> Check local/cloud bytes shows
canonical rank 25 and truthful `35/341 ranked · Provisional`; explicit Refresh
preserves that result and normal Back closes the review. No Verify/adopt/download
or Remove action was invoked. This proves this bounded native integration, not
complete coverage, current cloud bytes or migration execution. The same saved
scrape is preserved; its post-update silent-account failure was diagnosed and
normal default-account reconnect is used without saving/replacing a source.
Exact artifact/build, preservation and resumed-progress evidence is recorded in
IMPLEMENTATION_STATUS.md. S7 remains sole ACTIVE; S8-S10 NOT STARTED. The legacy
sync app/task remain untouched until the verified S10 handover.

## Bounded query projection remediation — 2026-10-07

One write batch per bounded 128-edition page replaces per-edition bridge writes,
without changing the enclosing snapshot transaction or eligibility rules.
Regression-first verification proves bounded transport and complete rollback
after a second-page failure. Focused query/rating/migration and existing real
file-backed 3,000/30,000-game checks pass; warm filters do not rebuild projections
or refill below Top-25. Fixture corrections restore normal canonical indexing
and actual UPDATE-trigger reproduction rather than weakening production rules.
The gated build passed and its signer-preserving owner update is independently
byte-verified; normal NES Library opens. A native full-rebuild performance
guarantee is not claimed. See IMPLEMENTATION_STATUS.md for exact evidence.

Before this batching update, normal owner NES/SNES Best-25 queries and joined
v2 read-only observations verified empty, explicitly provisional rankings with
clean bindings/projections. Eligible positive-score ranking remains host-verified,
not proved on those owner collections. The existing whole-collection job is
preserved; a silent Drive account-acquisition error required normal reconnect.
Normal Resume then advanced that same job to requested=4,618/pending=39,598;
both displays were subsequently confirmed OFF, with configuration unchanged.
Collection coverage, defensible retained sets, exact readable cloud-byte proof,
remaining recovery and reviewed migration criteria remain unfinished. S7 alone
is ACTIVE, S8-S10 NOT STARTED; legacy sync and original data stay untouched.

## NES/SNES reception scope — 2026-10-07

Host-verified extension of the existing game-level IGDB community basis retains
the twenty-known-vote floor and all identity/ownership/freshness rules. The real
public worker's cached/offline Top selects eight of ten reviewed fixtures, with
low-vote records excluded and coverage provisional. The cached-policy regression
verifies re-projection without rescraping and preservation of unresolved retention
members. See SCORE_RECEPTION_ASSESSMENT.md for sourced reception and disagreements.
Normal native NES/SNES Best-25 now verifies truthful empty/provisional behavior;
positive eligible-score membership remains host-verified. The saved live scrape
is preserved, not recreated. This is progress against META-05/MIGRATE-01,
not complete collection ranking or SD-removal authority.
S7 stays ACTIVE; remaining collection coverage, restore and migration criteria
are unchanged, and S8-S10 stay NOT STARTED.

## Explicit SNES archive recovery — 2026-10-07

Revision 12's explicit one-member SNES 7z profile uses the existing bounded
decoder and normal queue/publication, immutable mapping, adoption, offline
validation and exact owned read-only RetroArch/Snes9x grant. Preserve raw
`.sfc`/`.smc` bytes and copier headers, with complete stream/CRC validation and a
16 MiB raw budget. Regressions reject wrong members, unsafe names, mixed mappings,
oversized streams and multi-member layouts. Metadata raw evidence/publication is
host-verified, not a completed native SNES fresh-provider pass.

Normal isolated Thor workflow proves provider-verified download, actual online
boot/title-menu input and cold new-process offline boot with no active network,
owned removal, identical re-download and second removal. A temporary hotel DNS
failure was resolved with Android's normal connectivity repair; normal Retry
then completed, without a production retry workaround. Snes9x was installed
through normal core controls. Original targets/configuration were restored,
the exact empty proof directory removed, saved job 76 resumed with actual
progress and both displays confirmed OFF. See IMPLEMENTATION_STATUS.md for
artifact, process, preservation and acquired Gradle gate/profile evidence.

This closes the bounded standalone-SNES restoration integration, not collection
migration. MSU/PCM bundles/ZIP and unknown ownership remain unapproved. S7 is sole
ACTIVE; full fresh coverage, canonical defensible Top-25, current readable cloud
bytes, remaining format/bundle workflows and reviewed migration remain required.
S8-S10 are NOT STARTED. No original ROM/save/cloud mutation, legacy-sync retirement
or external release occurred.

## Explicit NES archive recovery — 2026-10-07

Revision 11's NES 7z profile now uses the existing bounded single-member decoder
and normal owned queue, publication, mapping, adoption, offline validation and
exact read-only RetroArch/FCEUmm handoff. Focused regression-first host/native
checks verify the accepted signature/budget and reject wrong members, unsafe
paths, mixed mappings, ZIP and unsupported layouts. Metadata identity publication
is host-verified; a completed fresh NES collection scrape is not claimed.

The normal isolated Thor workflow proves actual online boot and cold new-process
offline boot with no active network, owned removal, identical re-download and
second removal. FCEUmm availability was verified through normal core installation.
The prototype/aftermarket proof item creates no official classification or Top
exception. Original mappings/settings were restored exactly, the empty proof
directory removed, saved job 76 resumed with actual progress and screens switched
off. See IMPLEMENTATION_STATUS.md for artifact and Gradle resource evidence.

Only this required format integration slice is verified. S7 stays ACTIVE: full
fresh coverage, defensible canonical Top-25, current readable cloud bytes,
remaining format workflows and reviewed migration remain required. S8-S10 stay
NOT STARTED; legacy sync mechanisms and original ROMs/saves remain untouched.

## Exact-card reads and GBC/GBA recovery — 2026-10-07

Exact cached detail, rating and cover reads now resolve only their bounded exact
cache identities, leaving collection ranking/facet projection work to collection
queries. Real SQLite regressions verify unrelated dirty rows remain pending and
the later collection query still ranks correctly. This does not establish a full
Library latency fix: its post-update projection finished only after a long live
database wait, without reset, process termination or timeout-based recovery.

Explicit mapped GBC/GBA single-member 7z recovery is integrated through normal
queue/publication, typed crash and offline revalidation, ownership and exact-leaf
RetroArch launching. Host and native format/grant checks pass. Normal isolated
Thor workflows verify each actual online/cold offline boot, owned removal,
identical provider-verified re-download and second issue-free removal. GBC input
was demonstrated; GBA gameplay input was not. Original ROMs/settings were
preserved, mappings restored and the reviewed empty proof directories removed.

Mixed-console actions now use each entry's own source capability. Missing local
rows cannot enter the queue; local installed management is preserved. Host normal
detail/picker touch/controller fixtures and native installed-local/independent
Drive actions verify that distinction without merging title namesakes. The native
missing-local action is not separately claimed. See IMPLEMENTATION_STATUS.md for
current installed artifact, acquired Gradle gate/profile and preservation evidence.

Only these bounded integration slices are verified. S7 remains ACTIVE: the full
fresh job, canonical/defensible Top-25 sets, current readable exact cloud bytes,
remaining format workflows and reviewed migration are required. S8-S10 remain
NOT STARTED; no bulk deletion, save-sync retirement or publication occurred.

## Cold artwork recovery corrected — 2026-10-07

Native phase diagnostics located 24.4 seconds of the 35.6-second awake cold
recovery in rereading 447 MiB of shared artwork and per-image commits. Recovery
now restores bounded receipt batches; every image reader validates current
bounded size and exact content hash before exposing its path. Reproducible
regressions verify the former autocommit behavior and same-size replacement
exposure, exact 128/2 receipt batches, corruption/missing-image fallback, offline
recovery and unchanged binding/manual-edit/worker checks. Publication, migration
and ES-DE export retain full validation. No binding validation was skipped.

Signer-preserving build 254 matches the installed APK. Its normal awake cold
recovery completed in 10,985 ms with the same catalogue/binding/artwork counts;
artwork took about 235 ms. Remaining catalogue/binding latency is not declared
fixed. Default-account reconnect and normal saved-job Resume actually advance
job 76, not merely display Running. Joined Pause at requested=2,572 verifies
unchanged configuration/root generation and preserved job membership; see the
status ledger for inspected counts and gate/resource evidence.

S7 remains ACTIVE: full fresh scraping, defensible canonical retention, current
recoverable bytes, remaining round trips and reviewed migration remain required.
S8-S10 remain NOT STARTED; no original ROM removal or release occurred.

## Repeated settings recovery corrected — 2026-10-07

Normal settings now joins the library's catalogue-aware recovery future. Its
previous independent `restore()` calls reproduced three real SQLite recovery
passes for unchanged settings/library reads. Focused verification now proves
one unchanged pass, and a separate pinned recovery for each actual catalogue
notification, including notifications arriving during recovery. Raw-store
coalescing was rejected because it could swallow a newer catalogue state.
Changed members, account/source ambiguity, manual edits, base/bundle bindings,
durable recovery and normal worker Pause/Resume retain their existing checks.

The normal signer-preserving debug update (build 250) has matching host/installed
SHA-256 and retained configuration, seven sources, generation 1 and every saved
job 76 outcome. Native cold recovery completed once (36,038 ms); normal IGDB and
ScreenScraper switching then read the saved credentials without another recovery
start. Normal saved-job selection/Resume showed job 76 Running at its preserved
2,551-request checkpoint. Both physical displays are OFF.

This corrects duplicated recovery, not its remaining cold full-catalogue latency.
Full fresh coverage, defensible canonical retention, current recoverable cloud
bytes and remaining required recovery/migration workflows still keep S7 ACTIVE.
No S8-S10 work, original ROM removal, classification exception or release occurred.

## Game Boy owned 7z recovery verified — 2026-10-07

The explicitly mapped GB 7z route now participates in the normal queue,
validated publication/recovery, owned installation resolution and exact-leaf
RetroArch handoff. Existing bounded single-member decoding verifies one safe
`.gb` member and complete CRC/stream integrity within a 16 MiB raw budget.
Focused host checks and native checks pass. Live verification corrected the
missing native method dispatch and chose the actually installed SameBoy core,
rather than treating shared core information as proof of installed Gambatte.

The real Thor workflow verified normal cloud download, unchanged archive bytes,
online opening/input, normal emulator Quit, a cold new-process opening/input with
Wi-Fi disabled, normal removal of only the isolated owned copy, exact re-download
and a second issue-free normal removal. The original ROM and emulator settings
retain baseline hashes. Normal folder selection restored the full original
configuration; the same immutable job 76 resumed from its preserved checkpoint.
Both physical displays are OFF. See IMPLEMENTATION_STATUS.md for inspected
artifact, acquired gate/resource profile and preservation evidence.

This closes only the GB standalone 7z recovery slice, not GBC/GBA or other
unproven formats, collection-wide ranking or migration. The online cached-metadata
wait remains unresolved; warmed offline opening does not prove that issue fixed.
Full fresh metadata, defensible canonical retention, current complete readable
cloud bytes and reviewed migration remain required in sole ACTIVE S7. The fresh
focused standardized-matching checks pass without approving the separate
unanswered classification-provenance proposal. S8-S10 remain NOT STARTED.

## GBA exact-local identification integrated and verified — 2026-10-07

The metadata-only single-member 7z route now admits explicit GBA mappings with
one safe `.gba` member and a 32 MiB raw budget. Native stream/CRC, mapped-name,
budget and existing GB/GBC/N64 regressions pass; normal runtime, persistent worker
and provider-adapter/shared-recovery fixtures pass. The normal signer-preserving
Thor update retained the configuration, seven sources, published generation and
job 76's 44,204 immutable items and saved outcomes. Normal reconnect/Resume then
accepted two GBA raw bindings with exact explicit provider official-release facts
and advisory ratings. Observations were made only after normal Pause joined the
worker; no completed request or catalogue membership was rewritten.

This closes the GBA identification integration slice only. It adds no extraction,
installation/adoption/removal support, remote ROM body or scoring exception.
Full fresh coverage, canonical/defensible retention, current recoverable cloud
bytes, format round trips and reviewed migration remain open in the sole ACTIVE
S7. S8-S10 remain NOT STARTED. The previous native database failure's root cause
is still unproven, although no new exception was observed after this update.
See the status ledger for exact artifact/checkpoint and acquired build-gate
profile evidence. No ROM/save/BIOS/cloud-original deletion or release occurred.

## Local GB/GBC identification slice and paging defect — 2026-10-07

The existing exact-local archive observation supports mapped GB/GBC 7z files
with a 16 MiB raw budget and unchanged bounded stream, CRC, safe-name, complete
container-digest and local/cloud lineage checks. Persisted worker regressions and
the actual ScreenScraper-adapter/shared recovery contract pass with synthetic
responses. Native JVM decoder regressions pass. These are verified enabling
changes for META-01/META-03, not real GB/GBC provider acceptance, archive restore
approval, fabricated classification or authority to remove any files.

The native integration exposed payload-before-limit subfolder query cost. Its
production SQL now selects the bounded descendant-ID page before fetching JSON.
Query-plan/offset/scope regressions pass. A READONLY Android execution of
token-identical SQL verified complete ordered GB/GBC mapping traversal with
maximum pages of 148/95 ms, versus the previous repeated approximately eight
seconds. It preserves the current published snapshot without schema changes.
Normal APK installation, default-account reconnect and same-job Resume succeeded;
job 76's 44,204-item capture/configuration/checkpoint survived the updates.
At requested=1,689 a native database exception stopped that worker despite its
durable running state. Normal startup of the subsequent signer-preserving update
recovered it to paused with every item/outcome retained. Normal default-account
reconnect and same-job Resume are advancing it again. The exact failure cause
remains unproven; debug diagnostics expose only SQLite's numeric code and
allowlisted application source locations. Long external read cursors against the
rollback-journal database must not overlap the worker; observations require a
joined normal Pause checkpoint. See the status ledger for artifact identity and
acquired gate/effective resource-profile evidence.

Two GB and two GBC entries now have real provider-accepted, persisted
validated-raw-member bindings through the normal saved worker. Raw/container
identity separation,
explicit official classification and advisory ratings are verified; this is not
archive installation/restoration proof or a defensible Top. No completed
requests were rewritten or
second worker started to manufacture that result. Full fresh
metadata, defensible canonical retention, current cloud/recovery proof and
reviewed migration also remain S7 acceptance gates. The separate unapproved
classification-provenance change remains unapproved; standardized matching did
not authorize it. S7 remains sole ACTIVE, S8-S10 NOT STARTED; screens are OFF.

GBA and SNES terminal private comparison journals now independently reconcile
all records, counts, bytes and dispositions (798 / 8,501 files respectively).
Their 776 / 559 cached matches do not supply live recovery/ranking authority.
Every mismatch, missing counterpart and companion observation remains preserved.
That same serial audit also completed Mega Drive, SG-1000, Virtual Boy and FDS;
all terminal records/bytes/dispositions independently reconcile. The original
handle exited successfully before a serial census covered the explicitly
supported .cci/.wua selector omissions. That census has now terminated
successfully and every record/count/byte/disposition independently reconciles:
the 113-file n3ds scope preserves 112 nonselected observations and one .cci
exact-name miss; Wii U preserves 15 cached .wua byte matches and its one non-ROM
observation. An exact-name miss is not proof that equivalent content is absent
under another name or container. Private journals and all local files are
preserved; cached matches are not current cloud/recovery/ranking authority.

## NES comparison and actual format boundaries — 2026-10-07

NES's terminal private comparison reconciles 1,498 cached byte matches, three
ambiguous candidates and one non-ROM file. All 1,502 paths remain preserved;
current cloud revalidation, defensible ranking and tested restore are still
required. The same serial audit is now running GBA, not a replacement audit.

The complete SD inventory contains supported browsing suffixes omitted by its
old selector: one n3ds .cci and 15 Wii U .wua files (74,300,074,843 bytes combined).
Subsequent scoped comparisons must include them. There are also 566 DSi .dsi
files under the NDS target, unsupported .zcci/.wad observations, and substantial
.msu/.pcm content under SNES/Satellaview. Folder location and suffix counts do
not establish console/edition identity, bundle membership or restoration.
Preserve these explicit exceptions; do not call the old non-ROM classification
proof that they are unrelated or expendable. See the status ledger for exact
aggregate evidence. No private paths, hashes or provider IDs enter Git.

The same metadata job 76 continues, configuration and published generation are
unchanged, and both displays are OFF. S7 remains the sole ACTIVE stage with
coverage/retention/recovery/reviewed migration criteria open. No deletion or
stage-completion claim follows from the census.

## Third console comparison verified; census continues — 2026-10-07

Game Boy Color's completed private journal has 823 cached byte matches, three
size mismatches, seven exact-name misses and one preserved non-ROM file. Every
record and byte aggregate was independently reconciled. All paths remain
preserve with no removal authority. The actual .7z/.gbc formats were included;
neither missing counterparts nor different containers are guessed equivalent.
A ten-file Master System miss cohort had no renamed identical-byte match; this
small result does not establish whole-console differences or raw-member identity.

The remaining small-console census is executing serially (NES currently, then
GBA/SNES/Mega Drive/SG-1000/Virtual Boy/FDS), not complete. Metadata job 76 is
still live. Exact current cloud identity/readability, supported restore routes,
canonical score/retention and reviewed execution-time migration remain S7 gates.
S7 stays sole ACTIVE, later stages NOT STARTED; both displays are verified OFF.

## Larger-console census now verified through bounded reads — 2026-10-07

The old fixed projection correctly rejected Game Boy's larger catalogue. The
replacement reads 128-record keyset pages without increasing the 1 MiB transport
bound or copying a live database. Focused protocol/SQL regressions and a real
2,646-artifact Thor traversal pass. Exact SD names bound retained records;
configuration, catalogue-state/count and cursor drift fail closed. Cross-page
coherence is observational only; execution-time exact revalidation remains
mandatory. No claim of atomic full-collection capture is made.

Master System and Game Boy cached-byte comparison journals are complete and
independently reconciled. Their 829 cached matches and all unmatched/mismatching
or non-ROM files remain preserved. This advances exact local/cloud census but
does not prove current cloud readability, canonical retention or restoration of
these formats. Other console censuses and the full metadata pass remain ordinary
S7 work. S7 is sole ACTIVE; later stages remain NOT STARTED. No ROM/save/settings
or cloud-original mutation was performed. Screens are verified OFF.

## Wii coverage gap resolved at mapping boundary — 2026-10-07

The private inventory exposed Wii outside configured coverage. Normal import
added the unique observed published-root Wii folder and its existing external SD
target, preserving all 38 previous consoles and seven source objects. Normal Home
indexing now observes 212 Wii catalogue rows. Native reads verify direct-root
folder membership, unchanged active generation 1/no pending generation and the
same progressing metadata job 76. Neither row counts nor folder membership prove
canonical identities, identical local/cloud bytes or successful restoration.

Job 76's immutable 44,204-item capture excludes this new mapping. A later scoped
Wii pass remains ordinary required work inside S7, not a later-stage deferral.
The old SD inventory selector also omits real formats; absence from its selected
ROM count never authorizes deletion. Unsupported formats/platforms, unknown
membership and untrustworthy rankings remain preserved. S7 remains ACTIVE with
full metadata, defensible Top-25 sets and reviewed migration criteria open.
S8-S10 remain NOT STARTED. Both physical displays are verified OFF; transient
import/diagnostic outputs were removed without touching original games or saves.

## Capture and destination correction verified — 2026-10-07

The existing whole-collection capture committed as saved ScreenScraper job 76,
with 44,204 immutable items and progressing provider requests. Its partial
matched/review/error outcomes do not close META-01 or authorize ranked retention.
After commit, ordinary Console Settings import and Back/save corrected the 32
new internal defaults to confirmed SD targets, including the four non-identical
console aliases. All 38 target values, original six console-object hashes and
seven source-object hashes were verified after save. No private configuration or
inventory is published in Git; the transient import copies have been removed.

The earlier destination gap below is now resolved. Exact local/cloud membership,
whole-collection metadata/score coverage, defensible per-console Top-25 sets and
reviewed execution-time migration remain S7 requirements. Continue the same saved
job and preserve unresolved files; no ROM removal was performed. The published
root remains generation 1 with no pending generation. Both displays are OFF.
S7 remains ACTIVE; S8-S10 remain NOT STARTED. See the status ledger for hashes,
partial outcomes and exact cleanup evidence. No build was required.

## Actual new-mapping targets remain to be reconciled — 2026-10-07

The original six consoles retain their SD targets. The 32 newly added root
mappings currently use default internal-storage targets, not their existing SD
directories. Some SD aliases differ from application system IDs. Consequently,
the completed remote index cannot prove complete SD local membership, intended
installation destinations or a defensible migration profile. This is ordinary
unfinished S7 configuration/coverage work. Reconcile exact normal settings/import
destinations after the live immutable capture commits, preserving sources, the
original six targets and all unmanaged files; then verify actual membership.

The same capture remains live in process 610, with an open journal descriptor
and database writes. No new saved-job ID, metadata acceptance or terminal result
is inferred from those diagnostic facts. Android does not report the app frozen
or Doze-active. Both displays remain OFF; diagnostic filesystem observers have
been stopped without touching the application. S7 stays ACTIVE; S8-S10 remain
NOT STARTED. No storage-target changes or migration were performed.

## Expanded normal catalogue mapping — 2026-10-07

Normal root Edit mappings saved 32 new supported console mappings. Fixed read-only
native queries verify the exact selected folders are direct children of the
published generation-1 root. All seven source objects and the original six console
configurations are byte-for-byte equivalent at their per-object hash boundary;
only the authorized additional mappings change the whole configuration hash.
Ordinary Home indexing subsequently reached its terminal UI state. The native
cache contains 44,204 artifact rows across 29 populated consoles, not that many
canonical games. Some configured consoles have no supported cached content and
ambiguous/unsupported root folders remain unmapped; complete coverage is NOT
claimed. The root stays active=1/pending=null/nextGeneration=2.

One normal ScreenScraper Entire collection fresh operation was accepted after
indexing completed. New immutable-job capture and provider progress still require
observation. Matching uses the already approved revision-9 policy; ambiguous or
unknown modified editions are not made official merely to improve coverage.
This workflow changes no ROM/save/BIOS/cloud-original bytes or removal authority.
S7 stays ACTIVE; its metadata, reliable retention and reviewed migration criteria
remain open. S8-S10 remain NOT STARTED. See the live ledger for exact hashes.
Both physical displays are subsequently confirmed OFF; the accepted operation
is preserved and only the disposable screenshot/device copy was removed.

## Published root and indexed reads — 2026-10-07

The read-only diagnostic failure is now traced to SQLITE_BUSY, not memory
exhaustion. Production EXPLAIN regressions reproduce the repeated generation
scan/recursive descendant rebuild. The revised entries query preserves exact
scope, active-generation guards, supported-root validation, subtree membership,
order and paging while using direct root reads and parent-index traversal.
Both reproductions fail before the change and pass afterwards; affected
catalogue/provider/source-setup checks and scoped analysis pass.

Normal gated build 235 passed, preserving the signer/package and installing
in place after normal Disconnect. Native startup/default-account reconnect and
unchanged complete configuration hash are verified. OPEN_READONLY evidence
confirms terminal publication of the SAME generation 1: active=1, pending=null,
nextGeneration=2, 267,562 observations, zero pending folders and schema 37.
Root publication is no longer an unresolved S7 acceptance item. No new scan was
started. Normal root Edit mappings completes with observed console-folder choices
on the Thor. Back without Save preserves the complete configuration hash.
Both physical displays are subsequently confirmed committed OFF.

See the status ledger for the exact APK/profile and focused verification evidence.
S7 remains sole ACTIVE: full metadata coverage, trustworthy canonical retention,
exact current byte binding and reviewed migration/restore remain unfinished.
S8-S10 stay NOT STARTED; no removal or cloud/archive mutation is implied.

## Bounded publication transport and preserved native checkpoint — 2026-10-07

Root traversal reached 267,562 observations, 37,384 observed folders and zero
pending folder pages in generation 1. The original final validation performed
one HTTP GET per observed folder. The bounded regression reproduced it; the
existing API now batches at most 100 exact read-only folder GETs while preserving
every folder identity/name/parent/status check, account boundary, cancellation
and atomic publication rule. Focused affected checks and scoped analysis passed.
Google batch round trips are reduced; inner requests still consume individual
quota units and do not constitute a subtree transaction.

Normal Disconnect drained owned work before an in-place, signer-preserving debug
update. Streaming read-only digests match all entry/work/page rows before and
after installation, without a database copy, reset or schema change. Required
normal build 234 passed through the acquired shared gate with observed two
workers/no-parallel/3 GiB Gradle and existing Kotlin in-process compilation.
The preceding gated attempt 233 failed from PowerShell argument splitting, not
memory exhaustion. See IMPLEMENTATION_STATUS.md for artifact/profile evidence.

Normal default-account reconnect and root Refresh retained pending generation 1,
nextGeneration 2 and all traversal observations. The latest native state remains
active=null/pending=1; it is NOT terminal publication or proof of live batch
progress. This acceptance item remains open until actual publication or a
specific terminal failure is observed. Neither a successful build nor unchanged
checkpoint counters substitute for that external-system result.

The fresh whole-SD inventory has reconciled 15,964 unique records and exact
terminal group/byte totals. All records explicitly preserve their files; it
supplies no identity, ownership, rank or deletion authority. Full fresh metadata,
defensible canonical retention and reviewed migration/restore remain unfinished.
S7 stays sole ACTIVE; S8-S10 stay NOT STARTED. No ROM/save/BIOS/cloud-original or
FolderSync changes, removals or release occurred. Both screens are confirmed OFF.
The separate classification-provenance question is still unanswered; it was not
silently covered by the user's standardized-matching approval.

## Game Gear terminal identification and linked artwork — 2026-10-07

Normal ScreenScraper job 73 reached `completed`: 177 matched (174 rated),
260 needs-review, 42 ambiguous, 66 unmatched and one invalid response account
for all 546 captured requests. Current request evidence includes 178 original
ROM identifiers. Its actual linked artwork child 74 subsequently completed all
332 artwork requests. Only then did normal controls request one current-bound
IGDB pass. Native job 75 subsequently completed its 546 requests: 46 matched
(eight rated), 402 needs-review, 73 ambiguous and 25 unmatched. Its capture retains
177 official classifications, 178 raw identifiers and 55 release corroborations.
The bounded same-generation/same-identity read-only score check finds only two
distinct accepted provider records with at least 20 votes; six other community
scores have smaller samples. This does not approve a Game Gear ranking basis.
Neither terminal lookup outcomes nor advisory ScreenScraper scores prove
whole-collection Top membership.

Root generation 1 remains unpublished and advancing. The public IGDB support
check records only 19 potentially supported Game Gear provider records, not
collection membership or scope approval. Game Gear remains outside the approved
production ranking basis; current bound support cannot establish its defensible
whole-collection retention set.
META-01/META-05 and MIGRATE-01 remain open; S7 is sole ACTIVE, S8-S10 NOT STARTED.
No migration/removal, cloud mutation, provider-secret change or release occurred.

## N64 terminal pass and ordinary ranking view — 2026-10-06

The same IGDB job 72 is terminal: 120 matched (96 rated), 866 needs-review,
286 unmatched and 271 ambiguous account for all 1,543 requests. The normal N64
Best-25 UI returns 25 results and visibly reports `55/1543 ranked · 25 matching
games · Provisional`, with the accepted IGDB community basis and vote-count
threshold. Read-only evidence confirms 55 eligible groups and no dirty N64
projection rows. This verifies current matching/query integration while retaining
the required coverage warning; it does not prove whole-collection Top membership.

Normal controls then started the single fresh Game Gear ScreenScraper job 73,
with 546 captured requests, after N64's worker completed. It is running without
a blocked status. The same unpublished root generation 1 continues advancing,
with no configuration change or generation reset. Both physical screens are OFF.
See `IMPLEMENTATION_STATUS.md` for inspected counts and preservation evidence.

META-01 full fresh coverage and MIGRATE-01 ranking/review/execution remain open.
S7 remains the sole ACTIVE stage; S8-S10 remain NOT STARTED. No title curation,
ROM removal, cloud mutation, FolderSync action or release is implied by this proof.

## Large-catalogue next-folder scheduling — 2026-10-06

The live Thor query plan scans catalogue entries and sorts them to choose one
pending work item. A bounded production-SQL regression demonstrates completed
folder count driving lookup work. The additive v37 pending-work index and
work-first join correct that access path without changing cursor/order or
publication semantics. Focused production upgrade and traversal checks pass;
an isolated in-memory Thor SQLite experiment verifies the revised access plan.
Normal debug build 225 was subsequently signer/hash-verified and installed by
ordinary update after the metadata/artwork workers became terminal. Native
schema-v37 startup preserves streamed digests of every pending-generation entry,
work cursor and consumed page, together with terminal job outcomes and unchanged
configuration. The installed SQLite plan now starts with the pending-work index.
Normal account reauthorization (without saving a source) and Refresh advance the
same root generation 1, not a replacement. See the status ledger for inspected
counts and preserved-state proof; no quantified speedup is claimed.
Native app upgrade/resume is verified. Terminal collection publication, full
fresh coverage and MIGRATE-01 remain open; S7 remains sole ACTIVE, with S8-S10
NOT STARTED. The one normal N64 IGDB pass now captures newly bound ScreenScraper
evidence and is progressing, not complete. No acceptance criterion or deletion
gate is waived by these narrower native results.

## Current network boundary and saved-work recovery — 2026-10-06

The normal same-job resume reproduced an `unavailable` access check before any
new metadata lookup. Host authentication passed; Thor HTTPS was blocked across
Google and ScreenScraper, and its HTTP connectivity probe identified the hotel
captive portal. The normal portal Continue action restored connectivity, then
normal app Resume advanced the same N64 job 70, without changing credentials or
creating another pass. Normal source Refresh likewise advanced root generation 1,
not a replacement generation. Subsequent screen-off observations confirmed both
workers progressing. The configuration hash and app/emulator PIDs are unchanged.

This establishes the current transport cause and resumed workflow, not terminal
coverage, the historical pause cause, score reliability or migration completion.
MIGRATE-01 remains open; S7 is sole ACTIVE and S8-S10 remain NOT STARTED. See the
status ledger for inspected counts, boundary results and preserved-state proof.

## Protected shared-file evidence — 2026-10-06

The bounded read-only baseline recorded 137 files across 16 explicit shared
scopes, without copying bodies, stopping emulators or touching ROMs. A changing
RetroArch remap and unavailable PPSSPP shared path remain uncertainty; its
self-comparison correctly fails. Private/custom storage is not certified. The
private journal is retained for actual before/after migration comparison, not
published in Git. Focused parsing/comparison/capture and existing migration
checks passed. See the status ledger for evidence and current worker state.
MIGRATE-01 remains open: this records a baseline, not successful preservation,
defensible rankings or authorization to remove uncertain files. The existing
N64 job's newly paused state also needs normal-workflow diagnosis/resumption;
no quota reason or terminal collection result is inferred.

## External-sync collision review — 2026-10-06

Subsequent bounded remediation added a device-folder on-demand exclusion to the
deployed LoLSuite manager: planners/bootstrap/old-plan application reject excluded
targets before ADB, while menus omit them and unaffected targets/selection hashes
remain unchanged. Focused regression and existing route checks passed, and an
actual CLI rejected a temporarily excluded target without creating a plan. The
versioned patch and source identities are recorded in the review. No live config
exclusion is active yet; activation and exact-plan verification belong to reviewed
migration execution. This does not close MIGRATE-01.

The read-only [external-sync review](S7_EXTERNAL_SYNC_REVIEW.md) establishes that
LoLSuite's missing desired files are always additions: neither ownership-record
removal nor preserve-all retirement prevents refill. Inspected UI/CLI routes
require explicit transfer confirmation; bounded Windows task/startup/process
checks found no matching automatic launcher or active manager. That initial audit
made no changes; subsequent source remediation did not change archive settings,
ownership or FolderSync. This is not universal background-sync exclusion.

The actual target-specific no-refill arrangement and execution-time checks remain
required before reviewed SD removal. Archive profiles and ownership journals are
not replaced by R-Shop's dynamic Top-25. S7 remains ACTIVE; this review does not
close its save/sync-safety gate or authorize file deletion.

## Deterministic search/navigation ownership checkpoint — 2026-10-06

The real screen/widget regression reproduced a deferred search claim appearing
after navigation suspension and blocking the detail quick menu. Search now has
one screen-owned exact claim; the widget manages focus only. Suspension, balanced
resume, close and disposal preserve unrelated overlay claims. Deferred callbacks
cannot reclaim search priority or focus while suspended. This supersedes the
earlier unresolved search/menu investigation, without claiming instrumentation
of that historical live event's timing.

Focused host regression/overlay/navigation checks and scoped analysis passed.
Normal native PS2 and Library search -> detail -> menu -> return passed using
controller and touch, without restart or ROM mutation. Same-signer APK replacement
preserved configuration and filter preferences. Build 223 acquired the shared
gate and passed with two workers, no parallel execution and an inspected 3-GiB
Gradle heap. Kotlin was requested in-process; test-fork/native runtime concurrency
was not independently measured. No memory failure occurred. Full evidence and
artifact identity are in the status ledger.

Normal reconnect/resume restored the SAME N64 job 70 and root generation 1, with
fresh observations proving forward progress. Both physical screens are OFF;
original data, source configuration and FolderSync are preserved. Task-owned
captures/helpers were reviewed and removed; ongoing verification outputs remain.

This closes only the bounded search/navigation defect. S7 is still the sole ACTIVE
stage: full fresh metadata/reception coverage, defensible per-console rankings,
root publication, remaining formats and reviewed save/space-safe migration remain
required. The bulk provenance-classification decision remains pending. S8-S10
are NOT STARTED; no release or SD migration completion is claimed.

## PS2 standalone CHD recovery checkpoint — 2026-10-06

The existing owned-file route now hands standalone PS2 CHDs to installed
NetherSX2 using its explicit EmulationActivity and bootPath content URI. The
exact document-shaped leaf grant is read-only; ownership and standalone/no-bundle
constraints are checked before handoff and external open. No directory, archive,
ISO, bundle or BIOS acquisition support is inferred.

Normal DOWNLOAD, actual online game rendering, cold offline rendering, owned
DELETE and identical re-download passed on the Thor. The 62,976,347-byte CHD
matched the unchanged H: original SHA-256. Durable publication recorded completed
copy, retired staging and one installation/owner. Final normal DELETE left zero
proof-root transfers/installations/owners and two completed issue-free removal
journals. The empty proof directory is absent. The normal picker restored PS2
storage and the full source configuration returned to its exact baseline hash.
NetherSX2 was installed as a missing prerequisite; its normal BIOS picker imported
an existing owner-supplied BIOS, independently checksum-verified. The original
BIOS was unchanged and the temporary import copy was removed.

Focused Dart regression/analysis and native exact-leaf grant checks passed. Build
222 acquired the shared Gradle gate and passed with two workers, no parallel
execution and an inspected 3-GiB Gradle heap. Kotlin was requested in-process;
runtime test-fork heap and current generated native pool were not independently
measured. No memory failure occurred. Full evidence is in the status ledger.

The SAME N64 metadata job 70 and root generation 1 resumed. Original ROMs, saves,
settings, cloud files and FolderSync were preserved; Wi-Fi is enabled and both
physical screens are OFF. Search/menu navigation also exhibited a transient
failure to open the quick menu. Normal app exit/reopen cleared it, but root cause
and a regression fix are not yet established. This remains unfinished S7 work,
not a completed or deferred acceptance criterion.

This closes only the bounded PS2 CHD recovery workflow. S7 remains the sole ACTIVE
stage: full fresh metadata/reception coverage, defensible rankings, catalogue
publication, remaining format recovery and reviewed save/space-safe migration
remain required. S8-S10 are NOT STARTED. The bulk provenance-classification
decision remains pending.

## PSP standalone CHD recovery checkpoint — 2026-10-06

The normal owned-file route supports standalone PSP CHDs through installed
official PPSSPP. The existing exact document-shaped read grant retains the leaf
extension; no directory, write, archive-member or bundle access is inferred.
Durable ownership and standalone constraints are rechecked on external open.

Normal DOWNLOAD, actual online title-screen boot, cold offline boot, reviewed
owned DELETE and identical normal re-download passed on the Thor. The downloaded
43,841,741-byte CHD matched the H: original SHA-256. Durable publication recorded
copy completion, retired staging and one installation/owner. Final normal DELETE
left zero isolated-root transfers/installations/owners and two completed,
issue-free removal journals. The empty proof directory is absent. The normal
picker restored PSP storage, and the full source configuration returned to its
exact pre-test hash. Official PPSSPP was a missing prerequisite and remains
installed; its missing-package branch was not separately forced live.

The SAME saved metadata job and root generation resumed, not recreated. PSP-only
Best-25 remains Provisional, both screens are OFF, Wi-Fi is enabled and original
ROM/save/BIOS/FolderSync/cloud data are preserved. See the status ledger for
focused tests, gated build 221, effective resource/profile limits and APK evidence.

This verifies the bounded PSP CHD recovery workflow, not collection migration.
Full fresh metadata/reception coverage, defensible per-console rankings, root
publication, other format recovery and reviewed save/space-safe migration remain
unfinished. S7 is the sole ACTIVE stage; S8-S10 remain NOT STARTED. The bulk
provenance-classification policy decision remains pending.

## Drive authorization lifecycle checkpoint — 2026-10-06

The existing serialized authorization boundary now reuses its successful
account-bound grant in memory instead of invoking native scope authorization for
every request. Reconnect, sign-out and connected-account mismatch retire it;
actual rejected-token renewal remains at the API/media boundary. Concurrent stale
rejections preserve a newer grant. Focused authorization/API/media checks and
analysis passed; no persisted token, timer expiry or extra retry was introduced.

The same-signer normal APK installed without changing the source configuration.
Native default-account reconnect succeeded. Normal Saved jobs resumed N64 job 70
without a fresh snapshot: pending 1,128 -> 1,118, running, 34 raw-identified/rated.
Normal root Refresh resumed generation 1: observations 150,515 -> 150,630 and
pending folders 8,803 -> 8,765, nextGeneration=2. These prove resumed progress,
not full coverage or terminal success. Real expiry/rejection was not forced;
rejection concurrency is host-tested. See the status ledger for build/profile
and APK evidence, including the truncated supervisor acquisition flag limitation.

S7 remains the sole ACTIVE stage. Its complete fresh scrape, defensible rankings,
root publication, remaining formats and reviewed save/space-safe migration do not
pass yet. The requested bulk provenance-classification decision is pending;
unknown classifications and scores are not fabricated. Both screens are OFF,
original data and configuration are preserved, and S8-S10 are NOT STARTED.

## PS1 standalone CHD recovery checkpoint — 2026-10-06

The normal owned-file route now supports standalone PS1 CHDs with the installed
RetroArch PCSX ReARMed core. The existing exact document-shaped read grant retains
the extension; it does not grant a directory, archive member, bundle or write
access. Durable ownership and pinned-object checks still run on external open.
The PS1 menu now identifies RetroArch rather than Dolphin.

Normal DOWNLOAD placed a 30,778,396-byte test CHD in an initially absent isolated
destination. Its SHA-256 matched the H: original. Normal emulator handoff reached
the actual title screen; after normal Quit and verified process exit, a fresh
process reached it again with Wi-Fi disabled. Normal DELETE removed the reviewed
test leaf; normal re-download recovered identical bytes with completed publication,
retired staging, one installation and one owner. Final normal DELETE left zero
test-root transfers/installations/owners and two completed issue-free removal
journals. The empty test folder was removed non-recursively. Original ROM folders
were not altered. The normal picker restored the PS1 target and the entire source
configuration returned to its exact pre-test SHA-256.

This closes the bounded PS1 format workflow, not collection-wide migration. Full
metadata/reception coverage, defensible per-console Top-25, root catalogue
publication, remaining formats and the reviewed save/space-safe migration remain
required. S7 is the sole ACTIVE stage; S8-S10 are NOT STARTED. The same N64 metadata
job and root catalogue generation were resumed, not recreated. See the current
status checkpoint for inspected build, device and progress evidence.

## Current standardized archive-identity checkpoint — 2026-10-06

The existing bounded N64/Game Gear validators now identify actual raw members of
exact already-local archives without extraction, remote ROM-body requests or
ownership mutation. Container cryptographic checksums/size, local descriptor and
namespace stability, rooted Drive version before/after reading and atomic saved
request binding are verified. Focused native/Dart contracts cover replacement,
cancellation/drain, manual/modification protection, restart and shared recovery.
The authorized revision-9 matching/classification/reception policy is unchanged.

Normal Thor Fresh re-scrape created job 70 for 1,391 current N64 editions. Native
Drive reconnection after APK replacement preserved mappings and resumed that same
snapshot. Latest inspected state is running: 57 outcomes, 1,334 pending, five
accepted/rated raw-member matches and five corresponding official classifications
with exact local archive/version evidence. This is integrated real-provider proof,
not terminal traversal success or reliable collection-wide ranking. The earlier
uninstrumented eight-outcome pause has no captured cause; the later diagnostic
resume's authorization exception was resolved through normal reconnection.

No archive read grants installation/adoption/removal authority. Complete fresh
metadata scopes, independent defensible reception, whole-collection publication,
remaining format recovery and actual reviewed save/space-safe migration remain
required. S7 remains the sole ACTIVE stage; S8-S10 remain NOT STARTED. See the
latest implementation-status entry for build/resource/APK and preservation evidence.

## Current N64 normal recovery checkpoint — 2026-10-06

The new explicit standalone N64 ZIP/7z path is verified through the normal Thor
queue, native archive validation, exact-leaf owned emulator grant, actual online
and fresh offline title-screen boot, owned removal and identical re-download.
The original failed saved item succeeded after the parser's evidenced RomVault
marker/known-size LZMA corrections; it was not replaced to hide the failure.
See the latest implementation-status checkpoint for APK/checksum/build evidence.

The final READONLY audit confirms zero isolated-root transfers, installations and
owners, and two completed removal journals without issues. Original ROM bytes and
full source configuration are unchanged; the normal N64 target and PSP Best-25
view are restored, Wi-Fi is enabled, and both physical displays are committed OFF.
The expendable test copies and now-empty device test directory are removed.

This satisfies the bounded N64 format workflow, not collection-wide recovery or
MIGRATE-01. Generation 1 remains pending (148,325 observations / 9,524 pending
folders at the inspected checkpoint); classification, defensible full rankings,
other format recovery and reviewed save/space-safe migration remain unfinished.
S7 is the sole ACTIVE stage and S8-S10 remain NOT STARTED.

## Previous matching / recovery-journal / root-resume check — 2026-10-06

The authorized revision-9 matching implementation (`f270427`) remains installed
on unchanged APK 206. Fresh focused provider checks selected by `regional` passed,
including exact regional title selection, ambiguity/unknown-edition rejection,
company/day disagreement tolerance, conflicting regional-year rejection and the
normal persistent two-provider binding/ranking workflow. This is verification of
the shared policy, not evidence of defensible collection-wide Top-25 coverage.

The earlier auxiliary observer's native crash is now explained: Android SQLite
on this Thor does not provide `json_extract`. Replacing that diagnostic query
with a bounded, read-only Java JSON scan succeeded. The exact Game Gear test root
has no transfers, installations or target owners; both removal journals are
`completed` with no issue. The real normal download/offline/removal/re-download
cycle recorded in the implementation status therefore also has durable removal
evidence. No production change or new build was required for this diagnosis.

One normal Refresh resumed the existing root checkpoint: generation 1 remains
pending, nextGeneration remains 2, and observed progress increased from 144,619
entries / 10,667 pending folders to 145,160 / 10,499. It is not yet published.
The bounded current format audit found 1,378 N64 7z files versus 12 ZIP files;
a ZIP-only addition would not establish N64 recovery coverage. No N64 download,
adoption, emulator launch or archive approval is claimed by that audit.

S7 remains the sole ACTIVE stage. Defensible classification/ranking, remaining
format recovery, exact reviewed migration and save/space evidence remain open.
S8-S10 remain NOT STARTED. Source configuration is unchanged; no original ROM,
save, BIOS, FolderSync configuration or cloud file was changed.

## GameCube completed IGDB capture / existing root checkpoint — 2026-10-06

Normal native settings started exactly one missing GameCube IGDB job, ID 69,
on 205 current editions. Persisted terminal evidence: completed, 132 needsReview,
67 ambiguous, six unmatched, zero matched/rated, pending or failures. Its capture
has 194 unknown, one official and ten other-tagged editions. This satisfies the
omitted provider traversal, not META-05 reception or MIGRATE-01 retention.
No title-specific approval, classification import or guessed provider ID occurred.

The existing root source's native authorization required interaction after the
in-place APK replacement. Its normal Connect flow with the existing authorized
default account succeeded. Back without Save preserved all source/folder/mapping
configuration. One ordinary Refresh resumed pending generation 1 rather than
creating another: nextGeneration stays 2; observations increased 144,225 ->
144,255 and pending folders decreased 10,765 -> 10,755. This proves renewed
progress, not complete coverage/publication. No ROM, save, FolderSync or cloud
write took place and no build was required. The ordinary PSP-only Best 25 drawer
was restored and freshly showed 35/341 ranked / 25 results / Provisional, with
zero favorites and unchanged configuration hash. Both displays are committed OFF.
The inspected host capture was removed by reviewed transaction
`75f368fd319dd9f9ca5904405b4fca79` (1,872,736 bytes); the exact two device
captures are absent. The required bounded diagnostic helper remains retained.
S7 remains ACTIVE; its ranking,
classification, format recovery and exact reviewed migration criteria remain open.

## Game Gear safe ZIP / real handoff checkpoint — 2026-10-06

S7 remains ACTIVE. This closes a bounded archive/handoff defect, not MIGRATE-01.
The already-authorized standardized matching policy remains revision 9 / `f270427`;
no score, classification or SD-removal rule was relaxed in this change.

DRIVE-03/04/05/06 integration now admits only an explicitly mapped Game Gear ZIP
with one bounded safe `.gg` member. Native pinned-object validation checks exact
ZIP layout, local/central agreement, decompressed size and CRC without extraction.
The immutable transfer mapping survives restart and recovery; untyped legacy ZIPs
cannot acquire approval. Validation runs before publication/adoption, after
recovered publication and at owned emulator open. Normal queue, malformed layout,
cancellation, collision and recovered-publication host checks passed. Existing
Dolphin and ordinary file routes remain unchanged.

Live normal queue correctly rejected an unmanaged target collision without
overwriting it. Ordinary exact-byte review adopted one current cloud-identical
ZIP with truthful adoption provenance. RetroArch's missing private core was
installed through its own UI from the existing shared copy. A subsequent native
crash was isolated to the generic content-URI route by successful direct-local
boot of the same archive. The replacement single document-leaf read grant retains
the archive filename through SAF and rejects roots, siblings and nested requests;
no directory/prefix/persistable/write grant was added. Final APK 206's ordinary
Open in RetroArch action booted, and a cold second launch booted with Wi-Fi off.
SHA-256 before/after was
`2fc171b6ba8de52d9ce3572531fd37f8bf10326ae04470a82e56438908c34e11`.

Evidence: focused Dart runtime/engine/launcher/journal workload exited zero;
native `OwnedGameGearZipTest` and `OwnedRomGrantPathTest` XML report zero failures,
errors and skips. Gated native verification plus normal debug assembly succeeded
with ticket 206 / `2830c31e2bb84b94a1befdb2c892f8e5`, gate acquired, two workers,
parallel false, observed 3 GiB Gradle heap, assessed in-process Kotlin, one 512 MiB
test fork. Existing native per-ABI pools are one; global native concurrency was
not established by the worker limit. No memory failure or raised budget.
The final APK hash is
`b71bd5884d3b433ddfce650eb7beabf34929c4dff0209ff349910d4ead42052c`;
same-signer in-place installation preserved R-Shop configuration hash
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
Wi-Fi and the original PSP-only Best 25 view were restored; favorites are zero.
Both physical displays are confirmed committed OFF. No original ROM removal,
save/FolderSync change or cloud write occurred. Normal core installation is an
explicit prerequisite change, not a claim that all RetroArch files are unchanged.
Reviewed exact cleanup `0eb8b48e3b4755c3b6ab0680abe5ebf4` removed the obsolete
host capture/debug config (128,667 bytes); two device captures and the task-created
diagnostic config are verified absent. The required read-only helper is retained.

Fresh read-only metadata evidence: IGDB Game Gear job 68 completed 548 editions
with two matched/rated, 442 needsReview, 79 ambiguous and 25 unmatched. Its current
ranking has zero qualified groups. Root generation 1 remains unpublished at
144,225 observations / 10,765 pending folders; those counters do not prove liveness.
One PSP projection is dirty after the UI checks. Remaining S7 criteria include
defensible classification/Top sets, remaining format recovery, exact reviewed
migration and before/after save/space proof. The later normal Game Gear queue
download/offline/removal/re-download cycle is recorded in the implementation
status and its durable removal journals are verified above; earlier adoption
alone did not satisfy that acceptance. S8-S10 remain NOT STARTED; no required
work disappeared.

## Game Gear traversal / next provider pass — 2026-10-06

ScreenScraper job 66 completed its unchanged 548-item capture: one matched/rated,
377 needsReview, 63 ambiguous, 106 unmatched, one invalidResponse, zero pending.
Normal native settings and the bounded READONLY diagnostic agree. The failure
was reproduced at the provider boundary: the short-title search returned HTTP
200 / 49-byte plaintext missing-information error, while the same authentication
and platform with a control search returned valid JSON / nine candidates.
This does not establish an undocumented minimum search length. No per-title
alias, guessed ID, blind retry or parser relaxation was implemented.

After linked artwork finished, normal settings started the missing full Game
Gear IGDB pass, job 68, on 548 editions. Latest persisted observation: running,
two matched/rated, 143 needsReview, 22 ambiguous, six unmatched, 375 pending,
no failures. Continue that saved ID. Root catalogue generation 1 is advancing:
143,655 observations / 10,938 pending folders, still unpublished / nextGeneration
2. Neither traversal nor scored candidates prove defensible final Top-25 sets.

Read-only format investigation found the current Drive queue/adoption reject
archives and Game Gear's cloud files are ZIPs. Installed RetroArch/Genesis Plus
GX and archive documentation are enabling evidence only, not a tested R-Shop
restore route. Safe archive recovery remains required S7 work. No production
behavior, emulator configuration or ROM bytes changed.

Config SHA-256 remains
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
Both displays are confirmed committed OFF. No Gradle build, APK install,
classification import, ownership/removal, save/FolderSync or cloud write occurred.
The existing task-only bounded diagnostic/capture remain for the ongoing live
outcome under cleanup transaction `df179c1d8993cfe821d879429c8cc50a`.
S7 stays ACTIVE; S8-S10 stay NOT STARTED. No required work was dropped or deferred.

## Existing collection checkpoint resumed — 2026-10-06

The previous goal turn was a verified wait on native metadata job 66. This
continuation rechecked the same persisted job, not a replacement: 298/548
processed, one matched/rated, 212 needsReview, 29 ambiguous, 56 unmatched,
250 pending and no failures. It remains running; no fresh generation was created.

A bounded READONLY collection observation found generation 1 still unpublished
at 140,365 observations / 11,756 pending folders. These persisted counters alone
do not prove a live worker. Normal Sources showed `interactionRequired` for the
existing Drive account. Connect/configure and the existing default-account chooser
restored native read-only authorization. Returning without saving preserved the
source, folder and mappings. One normal Refresh resumed the existing checkpoint:
pending remains 1, nextGeneration remains 2, observations increased to 140,390
and pending folders decreased to 11,748. This is observed scan progress, not
publication or metadata coverage for the remaining collection.

Configuration SHA-256 is still
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
The existing task-only bounded diagnostic now reports sanitized collection
counters without titles, account/source IDs or credentials. Standalone javac/d8
used a 256 MiB compiler JVM; no Gradle build, APK update, payload download,
classification import, adoption/removal, save or cloud-original mutation occurred.
The helper remains registered under the existing cleanup transaction until these
live observations are no longer required. S7 remains ACTIVE; S8-S10 remain NOT
STARTED. The reviewed-manifest classification-source question is still unanswered;
no classification or rankings were imported from LoLSuite.

## Remaining-gate audit and omitted Game Gear pass — 2026-10-06

A fixed bounded READONLY diagnostic inspected the current six projections and
latest persisted console-wide jobs. Before new work, all six projections were
clean: PS2 59/220 score-qualified groups, PSP 35/341, GC 0/205, PS1 0/405,
N64 0/1543 and Game Gear 0/548. Unknown duplicate groups cannot be declared
canonical merely because this diagnostic counts existing keys.

GameCube job 51 captured 195 unknown / one official / ten other-tagged editions;
PS1 job 50 captured 401 unknown / four official; N64 jobs 31/33 captured 1,518
unknown / 25 other-tagged. They have no supported raw identifiers. This is not
permission to reinterpret a container digest as a raw ROM or classify by title.
The read-only host profile check found retail-selection intent, not an exact
current converted-artifact binding. No import or classification was performed;
explicit authority to use reviewed selection manifests as a classification source
was requested, separately from scores and deletion authority.

The same audit found only single-entry native Game Gear checks. Normal settings
created one new Game Gear-only ScreenScraper job, ID 66, capturing 548 editions.
Latest successful native observation: state running, 77 checked, one matched/rated,
50 needsReview, ten ambiguous, 16 unmatched, 471 pending and no failures.
Captures include 546 unknown / two official and 311 unambiguous region hints.
Do not recreate this job. A killed auxiliary observer while screens were off did
not stop the job: subsequent normal UI and a successful foreground READONLY
observation demonstrated continued progress. No cause is assigned to that kill.
The fixed helper/source and current private screenshot remain only for the live
job's outcome, registered in cleanup transaction
`df179c1d8993cfe821d879429c8cc50a` under
`D:\Temp\rshop-s7-remaining-gates-20261006`.

No Gradle invocation, deployment, ROM payload, source change, classification,
ownership claim, save operation, FolderSync action or cloud write occurred.
Configuration hash remains unchanged. S7 stays ACTIVE: the fresh traversal and
remaining full ranking/recovery/migration criteria have not passed. No required
work was deferred to S8-S10 and no later stage was opened.
Both physical displays are confirmed committed OFF while job 66 continues.

## PS2 breadth on the standardized policy — 2026-10-06

The unchanged final build 193 / implementation `f270427` completed a fresh normal
PS2-only IGDB job: 225 requests, 74 matched, 91 needsReview, 28 ambiguous,
32 unmatched, zero failed/unsupported and zero pending; 72 responses have ratings.
The previous PS2 pass matched twenty. No individual corrections, inferred official
classifications, saved-job rewrites or extra builds were used. The normal UI's
completed traversal and a freshly successful accessibility dump agree.

The native Library Best 25 query then showed PS2 only, IGDB community average
(20+ ratings; assessed systems only), **59/220 ranked / 25 matching games /
Provisional**. The request total counts editions; the query counts canonical
groups. An accepted match or rating is not automatically score-qualified.
Incomplete coverage cannot prove that unranked games are outside the best 25.
Restored the original PSP scope and verified its unchanged 35/341 / 25 result.
Config SHA-256 remains
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
No ROM payload, installation, ownership, save, FolderSync, mapping or cloud-original
mutation occurred. This closes the bounded PS2 breadth check, not S7: defensible
collection-wide retention, format restoration and reviewed migration still remain.
Both displays are confirmed committed OFF. The inspected host screenshot was
transactionally removed (1,150,550 bytes); both exact device captures are absent.

## Authorized standardized matching — 2026-10-06

Revision 9 records the user's explicit matching-policy change. The previous
cross-provider rule vetoed otherwise exact releases for company-name differences
and regional day/month disagreements. A bounded real cohort of twelve previously
rejected, current ScreenScraper-backed PSP entries now reaches the real IGDB
adapter through the normal persistent worker: ten matched, two needsReview.
Four accepted records meet the unchanged known community-vote floor; the cohort
Top remains provisional. Private capture:
`D:\Temp\rshop-standardized-cohort-20261006.json`. No individual corrections,
provider-ID guesses, invented score weights or owner ROM downloads were used.

The same real twelve-entry cohort also passed ScreenScraper name lookup: all
twelve matched with `exactRegionalOfficialTitle`, and none emitted raw-byte
classification evidence. Its initial failed pass exposed that `jeuRecherche`
omits `notgame`/ROM fields. A reproduced regression removed that requirement
only for already-classified official name matching; explicit non-game conflicts
remain rejected, and unknown raw classification still requires all original
positive flags. This is a provider-shape fix, not inferred official tagging.

Both adapters use the same exact Unicode-letter/digit title normalization.
ScreenScraper can uniquely select an already classified official release with
an exact regional/worldwide title and compatible regional date, rejecting fuzzy
neighbours, truncation, supplied raw conflicts, modifications and revisions.
It records `exactRegionalOfficialTitle`, not raw-byte verification or automatic
classification. IGDB uses the current source fingerprint, title/platform/region
and compatible regional year; company wording is descriptive, not a key. Ordinary
port/bundle/remake/remaster records may match their own IDs. Parent/version
variants without sufficient edition evidence remain reviewable.

New corroboration captures explicitly name `regionalReleaseV1`; old captures
without that field retain `exactReleaseV1` and are not rewritten. Current source
binding is rechecked atomically before publication. Unknown classifications,
hacks/translation/audio/restoration ownership, source changes, wrong region/year,
multiple qualifying candidates and capped search results cannot obtain trusted
Top ranks through this policy. Cloud/local byte, adoption and deletion gates
are unchanged.

Focused adapter regressions reproduced the original failures before the fix.
Host verification passed for the two-provider persistent workflow, offline
canonical grouping/ranking, changed-source rejection and shared-store recovery.
Affected catalogue/worker/store/rating/shared-cache checks passed; scoped analysis
is clean. A regression found and corrected a saved-job compatibility difference:
legacy captures retain their original title normalization and any-exact-date
rule, while new captures reject conflicting regional years.

Normal Thor IGDB PSP job 64 completed all 341 requests: 75 matched, 177 needsReview,
39 ambiguous and 50 unmatched, with no failed/unsupported items or pending work.
The old job 45 matched twelve. The updated library's ordinary PSP Best 25 filter
now reports 35/341 eligible canonical games and 25 matching games, truthfully
Provisional; the prior projection had six eligible groups. A completed job is not
complete collection coverage. No individual classification or match was approved.

Signature-preserving build 193 installed with -r after the job completed;
the normal library query above was rechecked on that final build after restart.
The last auxiliary READONLY aggregate process was killed by Android; its incomplete
output is not verification evidence. The app remained alive, and the normal UI
subsequently showed the complete cached result, not an error or an updating state.
Config SHA-256
remains `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
Both physical screens are confirmed committed OFF. Shared Gradle gate acquired;
observed workers=2, parallel=false, Gradle heap=3 GiB, preserved JVM flags and
assessed Kotlin 2.2.20 in-process sharing that heap. Test forks were configured
one/512 MiB (none ran during assemble), native pools remain one per task, not a
measured host-wide cap. No memory failure or budget increase. No cloud, ROM,
save, FolderSync or ownership/deletion mutation occurred.
Six exact task-only host diagnostics/compiler/UI outputs were transactionally
removed (30,211 bytes), and all three task-only device probe/capture copies were
removed after inspection. The current APK/log and bounded private cohort remain.

This is matching progress, not S7 closure: full collection ranking, archive
restoration coverage and reviewed safe migration remain required.

## Deliberate standalone adoption — 2026-10-06

The normal review now separates read-only byte checking from explicit adoption.
Adoption repeats current full local/cloud checks, awaits closed native reads,
revalidates Drive and public namespace, then commits installation, transfer
provenance and exact target owner in one existing journal transaction. It uses
the existing installation index and exact owned-removal engine, not a parallel
migration framework. No copy/stage/rename/deletion occurs during adoption.
Existing claims, cancelled or changed inputs and database failure leave the
unmanaged file intact and create no partial owner. Supported standalone formats
are supplied by normal console settings; archives/dependency manifests are
excluded. No title-specific rules or individual metadata approvals were added.

Focused runtime/journal/dialog checks passed for the current implementation;
scoped analyzer found no issues. Synthetic exact removal after adoption passed.
Normal signature-preserving build 189 install -r and UI proved the actual RVZ
comparison/adoption. An initially required authorization reconnect preserved the
file and left no claim; normal default-account reconnect changed no configuration.
The normal detail controller then recognized the managed installation. A bounded
READONLY journal check before and after process restart showed completed `adopt`,
one owner, confirmed publication, absent stage identity and truthful no-stage
retirement. Independent before/after file hashes and configuration hash agree.
Native removal was not performed. Both physical displays are committed OFF.

Build evidence: shared gate acquired, exit zero; observed workers=2,
parallel=false, Gradle maximum heap 3 GiB; assessed Kotlin in-process shares that
budget. Existing JVM flags remained. One test fork/512 MiB is configuration
evidence only, and native one-slot task pools are not a measured host-wide cap.
No memory failure/increase. APK/hash and private build-log location are recorded
in IMPLEMENTATION_STATUS.md. No release or cloud/save/FolderSync mutation occurred.

This closes the narrow standalone ownership integration detail, not S7.
Collection-wide reliable Top-25 coverage, reviewed execution/recovery/save/sync
gates, retained-set validation and actual SD migration remain unfinished. S7 is
ACTIVE; S8-S10 are NOT STARTED. A managed installation is not migration authority.

## Collection-level diagnosis and descriptive preview — 2026-10-06

The fresh bounded, read-only aggregate audit confirms that completed API jobs
are not completed metadata coverage. ScreenScraper jobs for PS1 and GameCube
had 2/405 and 1/206 matched entries respectively; current ranking projections
had zero eligible groups for both, 12 for PS2 and six for PSP. Current IGDB
corroboration has 18 matched records and ten adequately supported records.
The same root traversal continued advancing; this is not a stalled scan or an
individual-game correction problem. Do not treat request completion as a safe
Top-25 retention set or deletion authority.

A deterministic six-container cohort across N64/GameCube/PS2 was checked against
the live ScreenScraper API in two bounded sequential passes (the second used
the production response-unwrapping shape). No exact stored MD5/size pair was
returned. A name candidate is not an exact archive identification. No archive
was downloaded/decompressed, no hash was relabelled raw, and no match was
approved. This does not assert that all possible containers are unsupported.

The scraping preview previously discarded already-returned synopses, retaining
only candidate title/cover. Both production adapters now carry bounded,
transient descriptions through the existing worker preview. Accepted records
and sole unverified candidates show descriptive context; ambiguous or changed
outcomes do not choose a synopsis. The UI selects its language, English, then
an available provider language and decodes entities once as plain text. No
extra game lookup, accepted record, classification, score or rank is created
by a candidate preview. Existing cover-update copies retain this context.

Focused normal controller-to-widget verification covers multiple entries,
accepted/unverified outcomes, ambiguous-result clearing, language selection,
bounded immutable payload, entity decoding and unchanged publication/rating
gates. Adapter checks verify descriptive fields from both providers. Old IGDB
synthetic catalogue schemas lacked the production filename column/value; those
fixtures were brought into alignment without a production fallback.

Normal Thor scoped lookups in build 187 showed an accepted synopsis and a sole
unverified candidate synopsis/cover with zero published rating. Build 188 showed
a different unverified entry through the same normal workflow; visually inspected
layout is readable and bounded. No individual match/classification was approved.
The entity decoder is separately verified with host widget input reproducing the
live escaped-quote defect, including one-pass decoding and literal markup safety.
Both native builds acquired the shared gate: observed two workers, parallel false,
3 GiB Gradle heap and assessed Kotlin in-process. Test one-fork/512 MiB settings
were configuration evidence only; native one-slot task pools are configured, not
a measured host cap. No memory failure or budget increase occurred.
Final APK hash `4c402688a0544e8a9783c4a898fcbbb504dee541dc8e9ad9384950d6dbe6e7a3`
and existing signer were checked before install -r; no uninstall/release occurred.
Config hash remains unchanged and both displays are committed OFF. The same root
traversal reached 140,365 observations / 11,756 pending folders, pending generation
1 / next 2. ROMs/saves/cloud originals/FolderSync and mappings remain unchanged.

S7 remains ACTIVE. Full reliable ranking coverage, strict reviewed adoption/
execution journal and actual migration are still unfinished; this preview
change is not completion of those acceptance criteria. S8-S10 NOT STARTED.

## Durable exact-byte observations — 2026-10-06

Build 186 adds a bounded, append-only observation table to the existing private
journal (additive database 35-to-36 upgrade). A successful full check closes its
native read, awaits the evidence append and only then reports success. Cancellation
and disconnect still join the operation; a failed append cannot claim saved
success. An atomic append completed during cancellation may remain as valid
historical evidence, not a current success or ownership mutation. Record validation
binds exact Drive account/source/file/version, configured root/filename, native
identity, size and cryptographic digests. Latest lookup uses insertion order and
exact indexed keys, not clock ordering, title normalization or provider guessing.

Normal UI shows a saved check explicitly as past evidence. Its local-only read
does not require sign-in or reread a ROM/cloud body. This supports restart-safe
pre-execution review under MIGRATE-01, but does NOT satisfy the strict execution
journal, format-specific restore, adoption, complete ranking or actual removal
criteria. All execution-time checks remain required. No individual-game metadata
correction or title-specific rule was introduced.

Fresh focused runtime/dialog/record checks, affected upgrade/journal checks and
scoped analysis passed. Production v35-to-v36 upgrade preserved existing table
contents and saved jobs; database close/reopen preserved observations. Contracts
cover no evidence on failed byte/source checks, close-before-append, joined
cancellation, commit failure, exact account/source/root/path isolation and invalid
serialization. Two existing synthetic migration assertions were diagnosed: an
old-footprint downgrade must drop the newer saved-job index with its column, and
SQLite legitimately selected that index plus a composite primary key rather than
one particular alternative index. Tests retain actual index/content verification;
no production behavior or safety gate was bypassed. No full suite was run.

Actual Thor check used the same existing small RVZ as the prior standardized
protocol proof: 20,131,764 bytes, current cloud version 2, observed
2026-10-06 07:18:55.561600. It reported "Byte observation saved privately for
restart-safe review". After a process restart, opening the normal review displayed
the same timestamp/version as "Past byte match" and "not rechecked now", not current
verification. Independent local SHA-256 still agrees:
`0d7aeb487d665ce3fceffc25ea8041afeffe44faf223640e84f5f8dcb4f2578f`.

Build 186 ran through the acquired `Local\Darka.AndroidGradleBuildGate` supervisor.
Observed workers=2, parallel=false and Gradle maximum heap=3,221,225,472 bytes;
assessed Kotlin 2.2.20 ran in-process within that heap. Required metaspace=1G and
code-cache=256m arguments remained. Configured test fork=1/512 MiB (none ran in
assembly) and native one-slot pools do not establish a total-host memory cap.
No memory-related failure or budget increase occurred. Log retained at
`D:\Temp\rshop-s7-gradle-build186-20261006.log`; current APK is 179,398,509 bytes,
SHA-256 `01597b6121e0741a1cc54c6ab7348938853c9155aa4ae4fc71c2fdbcc8d40735`,
package com.darkaxt.rshop.debug / 1.7.0 code 12, signer
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Signature-checked install -r preserved app data; no publication occurred.

Normal default-account reconnect after update/restart and Refresh resumed the
same unpublished generation 1/next 2: 138,771 observations / 12,099 pending folders.
PS1 metadata 50 and linked artwork 53 remain completed. Config SHA-256 remains
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
Both displays are committed OFF. Exact reviewed task UI XML was removed; required
APK/log/private audit/probe evidence remains. No ROM/save/cloud-original/FolderSync
mutation occurred. S7 remains ACTIVE with full rankings, reviewed execution/adoption
and migration unfinished; S8-S10 are NOT STARTED.

## Reusable current local/cloud observation — 2026-10-06

The normal Drive detail menu's explicit check uses existing native read-only
storage and Drive boundaries. It requires an exact configured root and filename,
pins the local identity, streams local/cloud hashes without saving a ROM copy,
revalidates rooted catalogue/file version before and after the cloud stream, then
hashes the local file again and checks its current namespace/session identity.
Only one such review runs at once; cancellation/disconnect joins its resource
closure. Opening the dialog alone does nothing. This advances MIGRATE-01's
current-cloud byte comparison, but does not satisfy adoption, restore-format,
execution journal, complete ranking or removal criteria. Results are observations,
not reusable deletion certificates. No title-specific matching exception exists.

Focused production-runtime/boundary and dialog tests passed, as did scoped Dart
analysis. Native verification first exposed an actual protocol mismatch: published
read sessions require durableOffset=size, not zero. The fake native boundary was
tightened, the failure reproduced and the caller corrected before native success.
Missing files avoid cloud requests; changed/corrupt bytes, cloud version, local
namespace, same-size/coarse-timestamp overwrite and cancellation/disconnect drain
are tested. No production fallback, arbitrary wait or retry was introduced.

Normal Thor build 185 completed a full comparison for the existing
`/storage/75D7-DC5F/Roms/gc/Animal Crossing (USA, Canada).rvz`, 20,131,764 bytes,
cloud version 2, UI observation time 2026-10-06 06:49:28.711400. The app result and
independent local hashes before/after agree:
`0d7aeb487d665ce3fceffc25ea8041afeffe44faf223640e84f5f8dcb4f2578f`.
This one small file proves a standardized byte path, not metadata curation or
adoption. Controller A started the explicit check; controller B cancelled a
second actual running comparison and returned to normal details. Normal default
account reconnection and Refresh preserved the source/config/root generation.

Sequential debug builds 184/185 acquired `Local\Darka.AndroidGradleBuildGate`,
with verified workers=2, parallel=false, Gradle heap 3,221,225,472 bytes and assessed
Kotlin 2.2.20 in-process sharing that heap. Required metaspace=1G/code-cache=256m
flags remained. Forked-test settings are one/512 MiB (no test JVM in assemble);
native one-slot pools are configured, not a total-host guarantee. No memory failure
or budget increase occurred. Logs remain required evidence at
`D:\Temp\rshop-s7-gradle-build184-20261006.log` and
`D:\Temp\rshop-s7-gradle-build185-20261006.log`.
The independently inspected installed APK is 179,382,635 bytes, SHA-256
`407b1df151aa2f9ac6201580bf46e4cb65101d4297e858e47e248ae85b649b1b`,
package com.darkaxt.rshop.debug / version 1.7.0 code 12, signer SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Normal install -r preserved app data; no publication occurred.

Final native observation confirms PS1 job 50 completed 405 processed entries
with no pending work; its linked artwork 53 completed. Root generation 1/next 2
remains unpublished but advanced to 137,544 observations / 12,466 pending folders.
Both displays are committed OFF; config SHA-256 is unchanged at
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
No ROM/save/cloud-original/FolderSync mutation occurred. S7 remains ACTIVE;
complete fresh ranking coverage, strict durable execution/adoption and actual
reviewed migration remain unmet. S8-S10 remain NOT STARTED.

## Private exact-path retention review and bulk continuation — 2026-10-06

The existing read-only audit's optional `--retention-helper` observes the normal
canonical query, joined to `games.artifact_key` by its cache-row primary key.
It never associates ranked identities by cleaned title or filename alone. Only
the existing unique cached size/digest comparison permits a retention binding;
dirty/unbound/conflicting projections preserve the file. All required MIGRATE-01
gates remain even when a canonical rank is outside 25. An observed Top member
is a keep preview, not proof of a complete collection ranking. Per-page summary
consistency is not an atomic execution snapshot and the journal labels it so.
No adoption/removal method exists in this command.

Fresh focused host verification passed with the actual shared rank SQL and
native primary-key binding wrapper, bounded/partial/foreign pages, conflicting
identities, incomplete rankings, multi-member counting and exclusive private
review creation. Native helper `/data/local/tmp/rshop-s7-retention-review-v2.jar`
matches the host jar SHA-256:
`6a72a452b5d1e5de3dbccde071d3dec3780437917d63fd1f2517e7863125fa6c`.
It remains READONLY, 128 members / 1 MiB per page with 4 KiB identity guards.
javac/d8 used requested 256 MiB budgets; no Gradle or APK update was needed.
The observed running audit Python peak working set was 33,107,968 bytes.

Real invocation used the independently established N64 root and `.7z` extension,
the existing cache helper plus the new retention helper, and exclusive output
`D:\Temp\rshop-s7-n64-retention-review-20261006.jsonl`. It completed 322 exact
paths / 3,267,753,332 bytes: 320 matching cached digests and canonical bindings,
two preserved non-ROM files. Independent line-by-line reconciliation matched
the terminal counts/bytes/game set and confirmed no removal authority. All 320
bound paths report projection_incomplete: the observation has 1,543 canonical
games, zero eligible ranked games and 3,268 dirty edition/artifact projections.
This does not clear a retention, current-cloud or restore gate. `.7z` is rejected
by the actual normal Drive installation queue; this audit is not format support
or evidence that such an archive can be restored as an emulator-ready ROM.

Normal GameCube metadata job 51 completed its existing 206-entry scope, followed
by completed artwork 52. The normal Saved jobs UI selected PS1 50 and Resume;
native state confirmed the same ID/generation running (274 requested / 133
pending / 272 processed), not a replacement pass. Normal root Refresh continued
the original pending generation 1 / next generation 2, reaching 135,665
observations / 13,062 pending folders. No mappings or source scope were changed.
The root had not advanced during the read-only audit; its resumed checkpoint
does not establish the reason the earlier refresh stopped.

Transactional cleanup `7c398eaac2f54b29b03fb14c4db1cebf` / ticket
`c0c6e5eea3a147a9cb36fa0ce4e4717f5cbd1782f2642b62db73dfa73aa6a786`
completed exact deletion of the 8,223-byte javac class and empty classes folder.
The source, jar and required private review remain. S7 is still the sole ACTIVE
stage: full fresh coverage, defensible retention, live cloud recovery, strict
adoption/execution journal and actual reviewed migration remain unfinished.
S8-S10 remain NOT STARTED. No ROM/save/cloud-original/FolderSync mutation or
publication occurred.

Final native observation: both displays OFF; configuration SHA-256 remains
`45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
Root generation 1 advanced to 135,824 observations / 13,002 pending folders;
PS1 50 remains running at 293 requests / 114 pending / 291 processed. The exact
task UI dump was removed. These are live continuing jobs, not completed scraping.

## Standardized lookup-region capture and normal Thor proof — 2026-10-06

- META-03's filename context now participates in new lookup snapshots without
  becoming identity/classification/reception proof. A reproducible normal
  catalogue fixture failed on `(Europe)` -> null before the fix. Focused
  catalogue/job/adapter checks and scoped analysis passed after it, including
  explicit unknown/multi-region/manual correction preservation, legacy filenames,
  conflicting tags and absence of any filename-derived official match or rating.
- Native read-only aggregate observation of unchanged PS1 job 50 confirms all
  405 older requests remain unchanged (zero captured regions). New normal
  ScreenScraper GameCube job 51 contains 206 requests, 172 with region hints:
  162 us / ten jp, and 172 without assigned edition regions. First seven completed
  real lookups are six needs-review / one ambiguous / zero rated. No individual
  title was selected, corrected or used to establish a game-specific exception.
- Successful gated debug build 183, log
  `D:\Temp\rshop-s7-gradle-build183-20261006.log`, used observed workers=2,
  parallel=false and Gradle maximum heap 3,221,225,472 bytes. The supervising
  launcher owns `Local\Darka.AndroidGradleBuildGate` through inspection and
  command completion. Kotlin 2.2.20 uses the assessed in-process route, sharing
  that heap. Required MaxMetaspaceSize=1G and ReservedCodeCacheSize=256m remain.
  Test markers configure one fork / 512 MiB, but no forked tests ran in assembly;
  app/plugin one-slot native pools remain configured. No memory failure/budget
  increase. Existing toolchain/deprecation warnings were not bypassed.
- APK `build/app/outputs/apk/debug/app-debug.apk`, 179,379,550 bytes,
  SHA-256 `46f1e5fbace813c03a048dc3355414e400b7e0c05e802d0603edfe1ea2fe7f13`,
  package com.darkaxt.rshop.debug / version 1.7.0 code 12, signing SHA-256
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`, was
  independently inspected and installed with `adb install -r`, not uninstall.
  Normal app PID 4280 started. Config SHA-256 remained
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  PS1 job 50 was explicitly paused at 259 requested / 147 pending. Root
  generation 1 / next generation 2 survived and resumed after normal
  default-account authorization, reaching 135,175 observations / 13,228 pending
  folders. No new source, mapping, library folder, account or generation was
  substituted. A transient initial credentials-loading display was re-observed:
  both provider credential pairs remain saved, not re-entered.
- Fixed READONLY aggregate helper `/data/local/tmp/rshop-s7-region-probe.jar`
  SHA-256 `5d6ada9d90f70dde947b2e4a48e40af1b4c1e00c0281bfd2b5238b39ec9c25fe`
  matches its host file. It caps request rows/record bytes and emits aggregates;
  no metadata correction or arbitrary SQL interface was added. The host compiler
  intermediate is expendable; helper/source/build evidence remain needed in S7.
- The Drive connector returned normalized descriptive metadata without the
  requested version/digest/capability fields. Those absent fields are not
  mismatches or recovery authority. Use R-Shop's existing authenticated Drive
  boundary for recovery proof. No Drive write or ROM body fetch occurred.
- Both displays are OFF. No SD ROM was adopted/removed, save altered, FolderSync
  changed or release published. S7 stays ACTIVE: full collection publication,
  fresh coverage, defensible ranking, current recovery and reviewed migration are
  unsatisfied. Follow job 51, then resume existing PS1 job 50 via Saved jobs.
- Final observation in this turn: the same PID/job 51 remains running at 27
  requested / 179 pending, 19 needs-review / six ambiguous / two unmatched /
  zero rated. The same root reached 135,290 observations / 13,187 pending folders.
  Exact transactional cleanup `df386571836eaa2dd6e83872600b9d49` removed only
  the 13,720-byte host class intermediate and its empty directory; the task-only
  device UI dump was also removed. Jar/source/APK and required evidence remain.

Authority: `SPECIFICATION.md` revision 8, MIGRATE-01 and the UI-02 scraping-feedback
extension. Status: **ACTIVE**, the
sole ACTIVE stage. S6 is COMPLETE at `ea63586`; S8/S9/S10 are NOT STARTED.
S10 owns the newly authorized R-Shop save-backup feature. FolderSync remains
installed with its existing folder pairs and schedules unchanged; neither
integration with it nor SD-card mirroring is part of S7 or S10.

## Required acceptance

Automatic PS1 breadth and snapshot scalability (2026-10-06): normal settings
selected ScreenScraper/psx and created job 50 on all 405 stable current entries.
All previous saved passes were completed; no duplicate live job was launched.
Latest read-only observation on the same live PID 13676: running with 348 pending,
29 needsReview, 22 ambiguous, six unmatched, zero matched/rated (57 processed;
58 requests counted with one in flight). The raw-header cohort was zero. This
records breadth without manual title curation, not an accepted ranking. The root
scan independently advanced to 133,041 observations / 13,921 pending folders /
25,534 work rows; generation 1 is still unpublished and next generation is 2.

Preparing this normal pass exposed a per-artifact query whose entry-first join
can scan the growing unpublished catalogue. A bounded fixture executes the exact
production SQL against the actual schema and observes SQLite VM work without
canceling the query or using a wall-clock deadline. With 20,000 unpublished rows,
the old lookup grew from 59 to 60,039 steps. A state-first CROSS JOIN now probes
the existing (scope,generation,file_id) primary key (EXPLAIN confirms indexed
SEARCH e): the fixture observes 61 steps initially / 41 after expansion. Exact
source/account JSON-prefix boundary, active generation, binary-file selection
and LIMIT 2 ambiguity rejection are unchanged. No new index or schema is needed.
This is verified query scalability, not proof of the entire native snapshot's
elapsed-time improvement: the installed app still uses the older query.

`python -B -m unittest test_catalogue_classification_query` failed on the original
work-growth regression and passed after the query change. Focused Flutter checks
for metadata_catalogue_jobs_test, library_store_test and drive_catalogue_test
passed as one concurrency-1 workload; Dart analysis of LibraryStore is clean.
Normal debug `:app:assembleDebug` then exited zero, including the prior retention
API. Gate ticket 182 / 7cca3923cfde4f08a8a21299331020c8 reports gate_acquired=true,
gradle_profile_verified=true, workers=2, parallel=false and observed maximum heap
3,221,225,472 bytes. Required 1 GiB metaspace/256 MiB code-cache flags remain;
assessed Kotlin 2.2.20 uses in-process configuration, sharing the Gradle budget
(compile tasks were unchanged). Test markers report one fork/512 MiB at
configuration only; no test JVM ran in assembly. App/plugin native tasks use the
existing one-slot compile/link pool; no effective all-host concurrency guarantee
is inferred. No memory failure or raised budget occurred. The first gated attempt
(181) terminated with Task '.dart' not found after PowerShell split an unquoted
property argument; it was corrected before the next build, not run concurrently.
Existing toolchain deprecation/embedded-Kotlin warnings remain; no unrequested
toolchain upgrade or validation bypass was added.

Build log: D:\Temp\rshop-s7-gradle-build182-20261006.log. APK:
build/app/outputs/apk/debug/app-debug.apk, 179,377,946 bytes, SHA-256
901f9b635ab0b39bfed034589fa57c4bcfeff47729d75a4d5f15033316951daa.
Verified package com.darkaxt.rshop.debug, MainActivity com.retro.rshop.MainActivity,
version 1.7.0/code 12, retained signer SHA-256
06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934.
This APK/log are intentional pending-verification outputs, not disposable while
required native verification remains. No APK update/restart, ROM deletion, Drive
mutation, FolderSync action or release occurred. Both displays are OFF. S7 stays
ACTIVE; current collection coverage/identity/ranking/recovery/migration gaps are
not waived by host verification or local packaging. Next device action must
respect the same running job/checkpoint, not start another PS1 pass.

Final pre-commit observation of that same job 50: running, 70/405 processed,
335 pending, 36 needsReview, 27 ambiguous, seven unmatched, zero matched/rated;
one request remained in flight. Root observations increased to 133,155 and
pending folders decreased to 13,884. Both screens remained OFF. These continuing
jobs are a verified wait, not a blocker, completion or reason to restart them.

Standardized retention checkpoint (2026-10-06): the browsing Top predicate is
not a complete physical keep list because it requires each displayed edition's
own eligible rating. `LibraryQuery.retentionPage` instead includes all current
members of each canonical group using the same assessed-score rank CTE, within
one explicit console and a 128-row maximum page. Unscored peers have canonical
membership, not borrowed ratings. Coverage counts survive empty page offsets;
missing bindings, conflicting scores or incomplete coverage cannot label
unresolved games as a bottom-ranked removal set. Even `outsideSample` grants no
ownership/removal authority: the remaining MIGRATE-01 gates still apply.

Focused query, migration and invalidation fixtures passed, including removed
membership, pending score updates, stable ties, unscored peers, conflicting
bindings and incomplete reception. Dart analysis reported no issues. The fixed
READONLY native observer's SQL is tested for exact equality with production SQL;
its host fixture checks precedence, coverage and empty pages. After the normal
Library refreshed all pending projections, Thor's six console observations had
zero dirty rows and zero unbound artifacts. Ranked/collection counts were PS1
0/405, PSP 6/341, PS2 12/220 (225 physical members), N64 0/1,543, GameCube 0/206
and Game Gear 0/548. These are current cached projections, not complete-library
rankings or current cloud/restore proof. No member was removed.

The native helper jar's host/device SHA-256 agrees:
dd03aa299d79e12661a986ddcc05f81b146e500cd5deb077627b917f09b3475a.
It opens only the fixed app database READONLY, returns at most 128 members and
1 MiB, and reports dirty projections explicitly. It never refreshes metadata.
The actual Dart API refreshes and queries transactionally; no updated APK was
installed in this checkpoint, so that device execution is not claimed. javac/d8
used requested 256 MiB budgets; no Gradle invocation or memory failure occurred.
The earlier native read failed with SQLiteDatabaseLockedException during the
normal app refresh; it succeeded after that same operation completed naturally.
No kill, restart, timeout or automatic retry was added.

Verification commands were the focused Flutter invocation with concurrency 1
for `library_query_test.dart`, `library_query_migration_test.dart` and
`library_query_invalidation_migration_test.dart`, Dart analysis of the changed
query/test, and `python -B -m unittest test_thor_migration_audit`. All exited zero;
the repository-wide suite was not required or run. Transactional cleanup removed
only the reviewed host helper class/jar and their empty folder (11,502 bytes).
Those compiler outputs are reproducible from source; the verified device jar
and required private inventories remain retained.

Root generation 1 remains unpublished: 124,117 observations / 14,130 pending
folders / 25,528 work rows, next generation 2. The same app PID 13676 remains
live. Both physical displays are OFF. This checkpoint is collection-wide,
without manual title curation; S7 remains ACTIVE on its original required
coverage, identity, defensible ranking, recovery and reviewed migration gates.

Native cached-comparison verification (2026-10-06): the audit no longer copies
the growing live database. A fixed READONLY on-device query projects platform
artifacts and catalogue generations in one SQLite statement; configuration is
checked before/after. Row/input/output guards reject oversize or malformed
results, never silently truncate. The 1 MiB projection/transport cap remains
bounded. Thor lacks SQLite JSON functions, so the query uses portable plain-SQL
aggregation of stored serialized records, then strict host validation. All six
mapped consoles passed: PSP 269 artifacts / 172,513 bytes, PS1 319 / 191,024,
PS2 202 / 129,135, N64 1,391 / 838,891, GameCube 134 / 82,064 and Game Gear
182 / 108,651. N64's measured 836,435 artifact bytes justified a 900,000-byte
input bound within the same 1 MiB result cap (initial input guard was 512 KiB).
Focused host checks exercise the shipped SQL, framing, provider-scope validation,
config changes and all original preservation gates. No full suite or Gradle
build was needed for this helper; javac/d8 were invoked with 256 MiB budgets.

The real N64 comparison exited zero and every private journal row independently
reconciles with its terminal summary: 320 stable .7z archives have matching
cached size/MD5 (3,267,752,208 bytes); two non-ROM files (1,124 bytes) are preserved.
The exclusive journal is D:\Temp\rshop-s7-n64-native-cache-audit-v2-20261006.jsonl.
The first invocation incorrectly selected .zip for this .7z directory and
therefore proved only preservation, not ROM comparison; that expendable journal
is excluded from acceptance. The corrected invocation uses the independently
observed extension. This remains cached comparison evidence, not live cloud
version/readability, retention, ownership, tested recovery or removal authority.
The verified helper jar remains on-device for remaining S7 observations; its
SHA-256 is f94d5f9f4ea3e32a85cde37363b146b757901e38b50ad0658b04a11457ac46b5.
Transactional exact-file cleanup removed only its expendable host class/jar
outputs (5,687 bytes) and the superseded wrong-extension journal (401,360 bytes).
The corrected private journal, all prior valid inventories and device helper
are retained. No user/app data was deleted; compiler outputs are reproducible
from the committed source, and the obsolete journal was intentionally discarded.

After the same saved-job resume, PSP job 44 completed all 341 edition items with
zero pending; its normal linked artwork job 49 also completed, with zero pending.
No replacement metadata job or per-title correction was created. Root generation
1 remains unpublished at 92,021 observations / 14,445 pending folders, next
generation 2. Both displays remain OFF. S7 is the sole ACTIVE stage: full
collection coverage, defensible retention, current identical cloud-recovery
proof and reviewed migration remain unfinished.

Saved-job recovery verified (2026-10-06): the normal settings now expose a
bounded, indexed, keyset-paged local history for the selected metadata provider.
A newer console pass no longer hides an older paused pass. Selection reads its
existing report and linked artwork only; explicit Resume owns provider requests.
Focused host checks verify provider/artwork isolation, unchanged generation and
job count, pending-only resume, paging and touch/controller selection. Scoped
Dart analysis and native debug assembly pass. On Thor, Saved jobs selected PSP
job 44 behind completed PS2 job 46 with no new job or generation. Resume advanced
the same generation 44 from 57 pending / 284 processed to 50 pending / 291
processed. The first attempt paused after one item; the source UI reported Drive
interactionRequired. Normal default-account Connect restored access, and Resume
continued saved progress without replaying completed items. No raw exception was
persisted, so the first pause is not independently attributed beyond that
observed authorization state. Full PSP completion remains outstanding.

Normal build 180 was installed in place with the existing signer and an
independently matching installed APK SHA-256
957fbddd0204c9fb453091b3fbc07c27aa3a1ee890a3d248620e559cff590698.
The source/mapping configuration and secure-storage file hashes remain unchanged.
The shared Gradle-gate supervisor exited zero with an inspected effective
two-worker / no-parallel / 3 GiB Gradle profile and assessed Kotlin in-process
strategy. Forked-test configuration was one JVM / 512 MiB (not run by assembly);
app native compile/link pools are depth one. No memory failure or budget increase
occurred. The acquisition receipt field was truncated from the tool response;
it was not independently retained, and no redundant build was launched for it.
After default-account reauthorization, ordinary Refresh catalogue resumed root
generation 1 (next generation 2) without a replacement source or checkpoint.
It reached 89,436 observations / 14,832 pending folders and remains unpublished.
Linked PS2 artwork job 47 is now completed. Both physical display states are
confirmed OFF. ROMs/saves, Drive originals and FolderSync remain unchanged.
This closes the older-job recovery defect, not S7's full collection/ranking,
recovery or migration acceptance, and is not a per-title workaround.

Whole-SD inventory verification (2026-10-06): the corrected native run joined
with exit zero. Its private journal header, every observation and completed
footer reconcile exactly: 15,964 unique stable files / 722,865,729,304 bytes;
15,053 extension-classified artifacts and 911 non-ROM files. These include bundle
audio tracks and are not canonical-game counts. Every file remains preserved,
with no calculated digest or cloud candidate and removalAuthorized=false.
The earlier unbounded `find -exec ... +` exceeded Android's argument limit;
explicit batches now enforce 64 paths / 16 KiB and exact ordered responses.
Focused host verification passes, including the long quoted/Unicode byte-bound
case and incomplete/out-of-root/link/changed-file contracts. The complete journal
is retained outside Git for later revalidation, not cloud-recovery authority.

Normal PS2 ScreenScraper job 46 completed 225 editions: 122 matched, 32 review,
4 ambiguous, 67 unmatched, 113 rated and no failed/unsupported/pending items.
Its header workflow persists 175 bindings. Normal IGDB job 48 also completed all
225 editions: 20 matched/rated, 127 review, 46 ambiguous, 32 unmatched and no
pending items. Eighteen publications use automatic official-release corroboration;
ten meet the existing vote-support floor. This is not a defensible full Top set.
The normal Resume saved job control restarted the existing linked artwork job
47 after its deliberate pause, without a replacement job or individual-title
corrections. Native controls show an active operation. Collection generation 1
reached 86,091 observations / 12,862 pending folders and remains unpublished.
Both displays were confirmed OFF. No ROM removal, FolderSync change, Gradle build
or later-stage implementation occurred; S7 remains the sole ACTIVE stage.

Breadth/inventory checkpoint (2026-10-06): normal PSP IGDB job 45 completed its
341 editions: 12 matched, 222 review, 57 ambiguous and 50 unmatched; 11 carry a
rating. Ten matches use the new automatic corroboration path, all with current
identity bindings and source fingerprints; six meet the existing vote floor.
These are not whole-collection ranking or deletion authority. The same collection
generation 1 resumed after native default-account reauthorization and advanced
to 78,195 observations / 7,538 pending folders without discarding its checkpoint.
Normal PS2 ScreenScraper job 46 is running; observation at 51 requests verifies
28 matches/current bindings/raw match methods and 40 header bindings, with 175
items pending. No per-game corrections were made in this checkpoint.

Read-only SD inventory was decoupled from the published cloud comparison: the
live catalogue is 156,856,320 bytes, larger than the comparison's 64 MiB cap.
`--inventory-only` reads neither database/config nor ROM bodies and makes no
cloud-recovery claim. Focused host regression verifies preserved files, unstable
files and non-ROMs with all removal gates retained. Real PSP inventory completed
170 files: 169 ROMs / 129,899,079,437 bytes and one non-ROM; PS1 completed 87 files:
86 ROMs / 30,900,237,652 bytes and one non-ROM; PS2 completed 24 files: 23 ROMs /
45,166,984,325 bytes and one non-ROM. All 281 file observations are stable, have
no calculated digest or cloud candidates, and remain preserved. Exact private
journals remain outside Git for subsequent revalidation. No ROM,
save, cloud original or FolderSync setting was changed. Full publication, fresh
coverage, defensible retention, cloud recovery and migration remain unfinished;
S7 is still the only ACTIVE stage.

Cross-provider checkpoint (2026-10-06): current hash-bound ScreenScraper official
release facts can uniquely corroborate an IGDB main game using exact normalized
title, platform, full regional date and developer/publisher roles. The source
fingerprint is checked again in the normal publication transaction. Missing,
conflicting, modified, manual-correction and potentially truncated-search cases
remain unresolved. Focused host regressions and scoped analysis pass; shared
cache reopen/projection recovery preserves evidence and the eligible Top query.
The first eight current PSP records reached the real IGDB API through the normal
worker: one matched, two review, five unmatched. The matched record has insufficient
vote support, so no ranked game was manufactured. Normal build 179 was then
installed in place with matching signer and independent installed APK hash;
configuration bytes are unchanged. Normal settings created PSP IGDB job 45.
Read-only evidence at 74 requests verifies three automatic corroborated records,
each with a current identity binding and source fingerprint; two meet the vote
floor. The job remains running with 268 pending; full breadth, final ranking and
migration are not yet verified. Both displays were switched OFF. The build gate
was acquired with observed two-worker/no-parallel/3 GiB settings, assessed Kotlin
in-process strategy and generated depth-one native compile/link pools in app and
plugins. No memory failure or budget increase occurred.

Normal automatic-CHD checkpoint (2026-10-06): the worker now reads a finite
140-byte DVD-CHD header through the existing exact Drive source/account/platform
mapping. Source boundaries are checked before and after the read, and artifact
and identity bindings are revalidated before the atomic SQLite commit. Normal
refresh/restart/shared-cache recovery reuse current evidence; replacement bytes
invalidate it. Manual and modified-release facts remain protected. Header hashes
are not ROM/cloud integrity proof. Focused regressions and scoped analysis pass.
Normal build 178 was installed in place with matching installed APK hash and
unchanged configuration bytes. Read-only native evidence from saved PSP job 44
observed 35 automatic header bindings, 31 current matched metadata bindings and
31 raw-identifier match methods, with 254 of its 341 items still pending. This
proves the real normal-app path on multiple entries, not whole-collection match
coverage, normal PS2 breadth or trusted rankings. The same unpublished collection
generation advanced to 74,498 observations; both displays are OFF. Build 178's
gate/profile and verification evidence are recorded in IMPLEMENTATION_STATUS.md.
No ROM removal, cloud mutation, FolderSync change or release occurred. S7 remains
ACTIVE; full publication, fresh metadata, canonical ranking, recovery and reviewed
migration criteria remain unsatisfied. Earlier checkpoints are historical and
their outstanding automatic-CHD wiring claim is superseded by this observation.

Automatic uncompressed-Drive checkpoint (2026-10-06): normal catalogue snapshots
now derive compatible, version-bound MD5/SHA-1/size only from mapped standalone
formats. The real ScreenScraper adapter can establish unknown official releases
only with exact nonzero cryptographic evidence, explicit notgame=false and all
five unmodified flags. Publication revalidates the current artifact and honors
manual unknown, patch/base and modification facts. Classification, release
assignments, metadata and item identity keys commit together. Host integration
proves canonical grouping/advisory query, shared-cache close/reopen/identity
recovery, rename stability and changed-byte retirement. Folder declarations and
stale manual-raw boundaries pass. Two fresh real-provider header lookups passed
without full ROM/artwork downloads. Focused worker/store/score regressions and
scoped analysis passed; the bounded 30,000-edition worker fixture observed about
238 MB peak RSS and joined normally. No full repository suite or Gradle build
ran. Native integration/automatic CHD extraction and the full metadata/ranking/
restore/migration acceptance below remain unfinished; S7 is still ACTIVE.

Shared-identification checkpoint (2026-10-06): the supported DVD CHD header
parser and live PSP/PS2 original-ISO lookup path are verified without decoding
ROMs or using container checksums. ScreenScraper's observed large-ISO size cap
is recorded distinctly; exact supplied hashes/platform/release and existing
ownership/reception/integrity gates remain enforced. Real SQLite worker tests
verify publication, canonical grouping and unranked advisory query behavior.
The four-sample real-provider lookup is host evidence, not native automatic
collection binding. That binding and broad match/ranking/migration acceptance
remain ordinary unfinished S7 work, with no later stage opened. The same native
collection generation was observed advancing to 69,114 entries / 10,283 folders
/ 5,027 pending folders, still unpublished; source settings remain unchanged.
Both displays are OFF. No ROM removal, cloud write, FolderSync change or build
was performed at this checkpoint.

Current 2026-10-06 update: normal native feedback has now demonstrated ambiguous,
matched and single-unverified-candidate cover outcomes and actual provider quota
with observation time. Ape Escape's reviewed identity populated description,
genre, developer/publisher, screenshots and sourced advisory rating in normal
details. Those observations close the candidate-feedback gap below, not broad
match coverage or migration. A shared regional cover-selection/correction fix
is host-verified and installed as normal build 176; its native input control was
observed, but final corrected artwork was not confirmed. At the user's direction,
individual-entry curation was stopped; remaining integration verification belongs
to the collection workflow. S7 stays ACTIVE, with all other statuses unchanged.

The following checkpoints are historical; the current update above supersedes
their outstanding candidate-feedback observation.

The 2026-10-06 latest-product/cover preview and ScreenScraper daily quota display
are integrated and host-verified, but their normal Thor verification is still
required. They remain ordinary unfinished acceptance work; S8-S10 stay NOT
STARTED. Normal N64 ScreenScraper
job 31 finished and its zero-item artwork job 32 is completed. A single fresh N64
IGDB job 33 was then started through normal settings. A root-context, fixed,
read-only native query confirmed it running at 443/1543 requested, 1100 pending,
281 needing review, 85 ambiguous and 77 unmatched, with no accepted ratings.
The collection scan also advanced to 60318 observations/6496 folders, with 5044
folders pending and no published generation. These are live progress observations,
not complete coverage or a defensible retention set. An app-UID probe was killed;
the same read-only query succeeded in root context without restarting either job.
The reason for that probe exit is not established and no application fix is
claimed. Both physical displays were confirmed OFF after observation.

Later fixed read-only observation confirmed IGDB job 33 COMPLETE on its existing
1,543-item snapshot: 953 needing review, 304 ambiguous, 286 unmatched, zero
pending or accepted ratings. Collection generation 1 remained unpublished and
advanced to 62,562 observations / 7,574 folders, with 5,043 pending folders.
No job was restarted. These final metadata counts supersede the earlier running
checkpoint, not the unresolved canonical membership/ranking criteria.

### UI-02 scraping-feedback recheck — 2026-10-06

Native continuation at source `8325a3f`: same-signer normal debug build 174 was
installed in place and its installed hash independently verified. A focused
catalogue recovery check passed first. Configuration bytes and completed N64
job 33 were preserved; pending collection generation 1 survived the update
without losing committed entries. Normal default-account connection and source
refresh resumed that same checkpoint; a later observation showed 65,300 entries,
8,563 folders and 5,030 pending folders. No generation restart was requested.

The normal exact-game metadata workflow demonstrated the latest PS1 title,
platform and ambiguous outcome with the disc fallback, without accepting a
rating. An explicit original-versus-sequel cached review and provider recheck
then demonstrated the matched parsed-cover path. Both renders were captured and
visually inspected privately. The real provider's 20,000 daily and 2,000
failed-request allowances, observation timestamp, and separately reserved local
budget (19,998 after artwork) were visible. Existing credentials were retained;
initial loading defaults were not credential loss. Both displays were confirmed
OFF. No ROM payload, SD removal, cloud mutation, FolderSync action, release or
new Gradle build was performed for this check. **Still required:** a real-provider
single-unverified-candidate cover/label observation, then the remaining S7 whole-
collection, canonical-ranking, recovery and migration acceptance. The host
candidate/cadence/isolation checks are not represented as native observations.

The following earlier checkpoint records host verification before that install:

- Normal settings now display the latest title/platform/outcome and bounded cover
  context. A fixed three-second UI clock coalesces intermediate previews; leaving
  the screen cancels only that clock, not the existing app-scoped worker.
  Candidate images remain explicitly unverified and transient. They cannot
  publish a metadata record, score, identity or permanent artwork-cache entry.
  One serial candidate image request respects the same reserved provider budget
  and declared cadence; the display clock never triggers provider requests.
  Accepted images use the existing current-owned cache and artwork path.
- The v34→v35 production upgrade adds only display quota evidence. A real SQLite
  migration fixture preserves saved jobs, identities, provider next-allowed time
  and exhausted budget. Missing counters are Unknown, old observations retain
  their full date/time, and local reserved budget remains distinguishable.
  Credential replacement clears display evidence without weakening enforcement.
- Fresh focused checks cover the normal controller/settings wiring, candidate
  selector sanitization, no extra game lookup, bounded/malformed images,
  cancellation joins, exhaustion/pending preservation, latest-only display,
  provider/job isolation, disposal and known/missing/old quota. Existing metadata,
  artwork and earlier migration checks passed. The intentionally changed progress
  golden was inspected and the normal comparison rerun passed; scoped analysis
  reports no issues. The unchanged bounded 30,000-edition worker fixture observed
  a 274,898,944-byte process RSS peak; this is measured host evidence, not a
  whole-host cap or native-device memory guarantee.
- Normal debug build 174 succeeded, gate actually acquired for ticket
  `ddcce4e77daf4e828b559928deddc869`, observed workers=2 / parallel=false /
  Gradle heap=3 GiB. Kotlin's assessed in-process configuration shares that heap.
  Required metaspace/code-cache flags remain. Test fork/heap markers are
  configuration evidence only; all-plugin native concurrency remains unverified.
  No memory failure or budget increase. Gate log:
  `093b10643d3f453a95f8c78f24b6ed4a.log`.
- APK SHA-256:
  `a318cf7b1a08d56ee8dae4a982003f165da35a993a2b69db9e7581979dc75515`;
  normal `com.darkaxt.rshop.debug` / `com.retro.rshop.MainActivity`, version
  1.7.0/code 12, existing signer
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Not installed over the still-running collection traversal. **Remaining:**
  verify this exact new feedback through the real provider and normal Thor UI
  at a safe job boundary; then continue whole-collection/ranking/recovery and
  migration work. No stage closure, SD deletion or external release is claimed.

| Boundary | Current evidence | Remaining work |
| --- | --- | --- |
| Real collection membership and fresh metadata | Five rooted cloud mappings expose 1,106 remote artifacts (GameCube, Game Gear, PSP, PS1 and PS2), not the complete SD collection. Normal local scanning adds 547 local rows, giving 1,653 Library rows; these are not reviewed canonical games or managed installations. Both providers completed the earlier 316-entry two-console scope and the separate 269-artifact PSP scope, with unresolved outcomes retained. PS1 generation 1 published 5,162 observations/1,336 folders and its normal PS1-only mapping is saved. ScreenScraper job 20 completed 405 PS1 rows (319 remote plus 86 local): 214 need review, 136 ambiguous, 55 unmatched, zero accepted/rated. Artwork job 21 completed with zero items. IGDB job 22 completed the same 405-row scope: 233 need review, 135 ambiguous, 37 unmatched. Two exact native reviews/rechecks subsequently accepted fresh independently supported community ratings; this is not complete canonical membership. PS2 generation 1 is published and its normal mapping/SD target saved; ScreenScraper job 25 and IGDB job 27 completed the 225-row scope after hotel access was restored (all outcomes unresolved); an exact normal PS2 review/recheck subsequently accepted one fresh independently supported community rating, which survives native Home sync after the unchanged-evidence fix. Initial read-only SD census confirms additional occupied consoles and multi-file MSU content. | Reconcile explicit cloud/console mappings and eligible game membership; extend fresh coverage to the remaining stable-generation console scopes, including explicit unmatched/ambiguous/failed/rated coverage. |
| Defensible Top-25 retention per console | S4 validated the score contract; S6's one real ScreenScraper score remains advisory. No full-library ranking proof exists. | Gather accepted current scores, audit canonical game/disc/bundle groups, preserve unresolved consoles/games until ranking is defensible. |
| Identical cloud recovery and exact paths | S6 proves one normal SD on-demand restore/remove/re-download and offline Dolphin path. Existing SD files are not thereby owned by R-Shop. | Inventory private exact paths, file identities, cloud IDs/version/digests; prove applicable restore routes; build/review the strict one-time manifest and interruption-safe journal. |
| Preserve saves/BIOS/settings/unknown content and prevent refill | No existing SD paths have been removed or adopted. Current LoLSuite device manifests exist and must be reconciled, not treated as removal authority. | Establish save/config baselines and on-demand sync coordination without changing H: archival profiles; revalidate each eligible removal. |
| Actual migration outcome and final reconciliation | No bulk scrape or SD migration is claimed complete. | Execute only eligible reviewed removals, verify retained sets/free space/save safety and restore a removed test game through R-Shop, return it to its planned state, then reconcile/commit. |

Private file inventories, accounts, cloud IDs and migration manifests must stay
out of Git. Expendable task outputs use D:; durable migration state must survive
process interruption and remain available until recovery and closure are verified.
No blocker or tracked deferral is identified at stage entry; the remaining items
above are ordinary unfinished work, not grounds to open S8.

### Latest scope checkpoint — 2026-10-05

The membership row above retains the earlier five-console traversal history.
Current published/mapped scope is six consoles, with 2,497 remote artifacts and
771 additional local rows (3,268 total). N64's fresh pass is still running. The
earlier two-console GameCube pass does not cover its newly included local rows.
All other acceptance rows remain unresolved as stated; cached digest matches do
not authorize migration or replace live restore/version verification.

The seventh, collection-rooted source has now been saved through normal native
setup. Its first catalogue generation is still unpublished and it has no console
mappings. All six existing sources and all console settings remain unchanged.
It has not extended Library membership or established whole-collection coverage.

The normal console-settings Export action produced `r_shop_config.json` and
opened Android's share chooser. The chooser was cancelled without selecting a
destination. The generated JSON was read and independently compared with the
current configuration: all seven sources and all six system/mapping/target
objects are identical; no authentication fields are present. A private reusable
snapshot is retained outside Git (SHA-256
`4839d43a5fcf1c3a5b3d7291c245bdf8787941ac868435ae84fe7daf9bb6344c`).
This verifies normal native export, not native import into the release package.
The final handoff must refresh the snapshot after setup is finished and verify
its import; Google consent, secure provider credentials and storage grants are
not transferred by this file. No settings, ROMs or FolderSync state changed.

## Live execution — 2026-10-05

- The reported logo hang was not reproduced. The current normal APK cold-started
  in 1992 ms, displayed its All Games home tile, and opened the actual 316-entry
  Library with controller A. No app data or credentials were cleared.
- Normal settings completed ScreenScraper job 7 on a stable snapshot of all 316
  currently mapped entries: 316 requested, one matched/rated, 220 needing review,
  60 ambiguous, 35 unmatched, zero failed/unsupported or pending. Its follow-on
  artwork job 8 completed both images. Mappings stayed unchanged during the pass.
- Normal settings then completed IGDB job 11 on that same 316-entry scope:
  316 requested, one matched/rated, 237 needing review, 64 ambiguous, 14 unmatched,
  zero failed/unsupported or pending. Both traversals are real authenticated
  provider work, not whole-SD coverage or a defensible retention ranking.
- Explicit normal review accepted one exact Game Gear identity/classification.
  ScreenScraper job 9 rechecked it successfully and artwork job 10 completed two
  images. IGDB job 12 independently rechecked the offered Game Gear identity;
  its fresh overall score has only six votes. A sparse score is not promoted
  into a trusted consensus claim. Other unresolved candidates remain review/
  ambiguous/unmatched, not published scores. No ROM was downloaded by these jobs.
- An attempted host copy of the database while it was being written was not a
  consistent snapshot and could not be queried. No repair, restart or duplicate
  job was attempted. Subsequent reads showed the same job advancing; the idle
  completed database passed SQLite quick_check. Failed UI idle observation also
  did not restart a job or supply stale coordinates for a later action.
- Read-only SD census distinguishes game artifacts from metadata and bundle
  members: Game Gear has 366 ZIPs; GameCube has 80 RVZs (nine in Translations);
  PS1 has 86 CHDs; PSP has 169 CHDs including 94 in T-En and five Minis; PS2 has
  23 CHDs. SNES includes 559 7z files plus 220 SFC/MSU pairs and 7477 PCM tracks.
  These are raw file counts, not canonical-game or retention counts.
- Game Gear's mapped host Drive folder contains 182 ZIPs. All 182 have exact
  namesakes on SD: 180 match SHA-256 (35,066,195 bytes), two do not. Another 184
  SD ZIP names have no counterpart in that mapped host root. This is an inspected
  host-filesystem/SD comparison, not live Drive ID/version/digest revalidation or
  cloud-restore proof. Neither filename equality nor this partial audit grants
  removal authority. Differing and missing copies stay protected.
- Added a PSP-only source using the existing native Google account and read-only
  folder picker. Its single normal refresh completed and published generation 1:
  2708 observed entries, including 364 folders, with no pending generation or
  remaining work. This traversed metadata only, not ROM bodies. The normal
  mapping editor saved only the PSP root assignment; the two existing sources,
  systems, mappings and targets remained unchanged by object comparison.
- The normal library sync now exposes 585 artifacts: GameCube 134, Game Gear
  182, PSP 269. PSP includes 260 CHDs, two PBPs, two 7z and five ZIP files; these
  are artifact counts, not reviewed canonical-game membership or fresh PSP
  metadata coverage. Patch/tool archives require membership review before a
  retention claim. PSP's newly created target remains the normal internal
  default; an SD restore destination must be explicitly established and verified
  before migration. No installation, adoption or removal was triggered.
- With all metadata jobs and the single transfer completed, a second normal cold
  launch took 1919 ms. Controller Left selected All Games and A opened the real
  585-entry Library with one installed item. The complete current configuration
  remained identical across that cold launch. This is current startup/navigation
  evidence, not a reproduction or root-cause fix for the earlier reported hang.
- Both physical Thor displays were verified OFF after this device session. Only
  the task-owned UI dump was removed; no ROMs or persistent app data were cleared.
  No Gradle build or test workload was launched in this session, so no new gate
  acquisition or effective build-profile verification is claimed.
- No cleanup/adoption of user ROMs, H:/Drive original mutation, external sync
  policy change or public release has occurred. Full metadata coverage, candidate
  review, trusted Top-25 retention and the strict migration manifest/journal
  remain required work in this ACTIVE stage.

## Subsequent S7 execution — 2026-10-05

- Normal per-console ScreenScraper job 13 completed the PSP-only 269-artifact
  generation: 269 requested, 144 needing review, 35 ambiguous, 90 unmatched,
  zero matched/rated, failed/unsupported or pending. Its follow-on artwork job
  14 completed with zero requests. No duplicate metadata worker was launched;
  the confirmed live owner and the same job were observed through completion.
- Created the bounded read-only audit command in `scripts/`. The focused
  contracts exercised changed files, duplicate candidates, missing identity/
  version/digest, path boundaries and cached-match non-authorization. The first
  live read exposed an extra adb exec-out quoting layer; it was reproduced,
  corrected and verified before journaling. No source/app state was repaired.
- Its private exclusive-create Game Gear journal contains 369 exact SD file
  observations: 180 cached Drive size/MD5 matches (35,066,195 bytes), two size
  mismatches (330,866 bytes), 184 ZIPs without cloud candidates (32,458,894 bytes),
  and three preserved non-ROM files. Every disposition is preserve and every
  removal authorization is false. An independent streaming reader reconciled
  the terminal summary against all records. The updated bounded adb reader also
  passed a live stable-file/checksum comparison without any ROM body transfer.
  This journal is a required private review artifact outside Git, not evidence
  of live cloud revalidation, ranking, restoration or migration completion.
- Found the next internal classification gap: all 269 PSP lookup requests had
  empty content tags, including the 96 artifacts under the explicit T-En source
  bucket (94 CHDs and two archives). `LibraryStore.catalogueEditions` creates
  editions without carrying catalogue classification evidence. S7 must resolve
  this provenance gap while preserving manual corrections and uncertain
  classifications; it must not infer translation from official English or
  promote a guessed provider match. This remains ordinary current-stage work,
  not an external blocker or a deferral to S8.
- Final idle app database quick_check passed; all metadata jobs and the single
  transfer were completed. Both physical displays were verified OFF and the
  exact expendable UI dump was removed. The private journal remains available
  for the required migration review. No Gradle command, SD removal, app-data
  clearing or external publication occurred.

## Published source classification — 2026-10-05

- Reproduced the missing folder facts in a test before implementation. Catalogue
  capture now follows actual published Drive parent IDs in the exact source/account
  generation, rather than splitting a display path or guessing from filenames.
  Explicit Hack, T-Eng, Dub, Undub and Uncensor declarations can overlap. General
  Translations does not imply English. Ordinary English releases remain unknown.
  Generated facts have source-folder provenance; manual corrections and unchanged
  identity bindings are preserved. Moving an artifact changes only owned facts.
- Focused catalogue/query/identity/grouping/migration regression verification
  passed. The final opaque encoded scope regression and scoped Dart analysis also
  passed. No full-suite run or additional test worker was needed.
- The first normal native refresh failed before creating a job. Android's actual
  SQLite log established `no such function: json_extract`; host SQLite tests had
  not demonstrated that native extension. The query was replaced with exact
  bound JSON-tuple-prefix matching using core SQLite `substr` and `length`.
  Escaped quotes, Unicode and similar-but-different accounts have regression
  coverage. This failed native attempt is not recorded as a passing gate.
- The corrected normal APK installed in place with its existing package/signing
  identity. Cold startup reached Home in 2675 ms; controller navigation opened the
  real 585-artifact Library. The reported logo hang was not reproduced and no
  speculative startup patch was made. Existing configuration and secure credential
  fingerprints remained unchanged; no uninstall, clearing or secret re-entry was
  performed. Post-launch metadata/database and filter preferences changed normally;
  regenerable thumbnail cache differences are not claimed as exact preservation.
- A single normal PSP Fresh re-scrape created job 15 and captured all 269 requests.
  Native Library PSP scope plus T-Eng reported 96 matching artifacts, with zero
  trusted ranked games, and rendered real PSP translation entries. The unfiltered
  Library view was restored afterward. Folder evidence does not approve a provider
  match, classify patch archives as games, or authorize removal.
- The same native job 15 completed: 269 requested, 144 needing review, 35
  ambiguous, 90 unmatched, zero matched/rated, failed/unsupported or pending.
  Its follow-on artwork job 16 completed with zero requests. The idle database
  passed quick_check; all 96 T-Eng facts are present in the captured provider
  requests, with no active metadata or transfer worker. Configuration still
  matches its pre-update fingerprint. A live host copy made during writes was
  inconsistent and was discarded, not treated as production corruption or
  repaired; subsequent idle inspection is the applicable database evidence.
- After job completion, normal cold startup took 1975 ms and controller Left/A
  opened the unfiltered 585-artifact Library. No current-owner fatal, JSON1 or
  unhandled exception appeared in the inspected native log. Both physical
  displays were confirmed OFF. The exact task-owned UI XML was removed; the
  current normal APK and required diagnostic evidence are retained.
- Build tickets 146 and 147 acquired `Local\Darka.AndroidGradleBuildGate` and held
  it through exit zero. Observed settings: workers 2, parallel false, Gradle heap
  3 GiB; Kotlin 2.2.20 in-process shares that heap. Tests were configured for one
  fork/512 MiB but not executed by these builds; app native pool was one. Plugin
  native tasks were up-to-date, so fresh full-plugin concurrency is not claimed.
  No memory failure, budget increase or interruption of another build occurred.
  Corrected APK SHA-256:
  `0e002253682c049711713b231b89b611fbd42a70e564ce3b518eb7d35016c2f3`.
- S7 remains ACTIVE. Whole-SD mappings, reviewed eligible membership, defensible
  per-console retention and live cloud/restore verification remain unsatisfied.
  No ROM has been moved, deleted or adopted by this change.

## PSP review and private checksum reconciliation — 2026-10-05

- Normal PSP IGDB Fresh job 17 completed against the same 269-artifact scope:
  178 needing review, 43 ambiguous, 48 unmatched, zero matched/rated, failed,
  unsupported or pending. Native settings and the idle database agree; no
  duplicate provider worker was started. This is fresh PSP coverage, not
  whole-collection coverage or acceptance of the offered candidates.
- Two normal manual review/recheck workflows completed. LEGO Batman's actual
  PSP-specific port ID 259254 has no score; the shared-platform parent ID 2738's
  score was not borrowed. Job 18 matched that reviewed port and remained unrated.
  Ridge Racer's reviewed PSP ID 18787 rechecked in job 19, with a score backed by
  ten votes. It remains advisory, not Top-25 evidence. Both editions were
  explicitly classified as official through the normal review form. Other
  unresolved records remain unresolved; these decisions do not approve every
  archive, release or canonical group in the PSP collection.
- The normal Library search rendered Ridge Racer's sourced score, original
  scale, ten-vote count, retrieval date and advisory status. Search was cleared;
  the actual unfiltered Library still has 585 artifacts and one owned install.
  No ROM payload was fetched by metadata/review actions.
- The single read-only PSP audit process completed and exited zero. Its private
  exclusive-create journal observes 170 exact files: 169 stable CHDs match cached
  Drive size/MD5 evidence (129,899,079,437 bytes), and one 581-byte non-ROM file is
  preserved. An independent streaming reader reconciled every file against the
  terminal counts/bytes and required every disposition to be preserve with
  removalAuthorized=false. Journal SHA-256:
  `65dab876fbae375a79136f355871b3e84eae0656d6896afc6a024f7157e2d228`.
  Accounts, cloud IDs and exact file inventories remain outside Git. Cached
  matches are not live cloud revalidation, canonical review, retention or restore
  evidence; all remaining migration gates still apply.
- The subsequent logo-hang investigation observed the running Library, then
  verified a normal cold activity launch (2552 ms), the All Games home tile and
  controller navigation into the 585-artifact Library. No startup fatal error was
  captured. Database quick_check passed while idle and the saved source/config
  fingerprint matched its pre-investigation value. The historical intermittent
  hang was not reproduced; no speculative startup change or claim of fixing it
  was made. Both physical displays were verified OFF after the investigation.
- PSP and Game Gear's restore destinations were saved through the normal console
  settings and Android folder-grant workflow. Exact before/after configuration
  comparisons verified only their respective target fields changed. Other source,
  mapping and console options were preserved. Existing ROMs remain unmanaged;
  folder grants do not prove format recovery or authorize adoption/removal.
- PS1's additional source was saved through normal read-only native
  account/folder selection. Its first catalogue generation subsequently published
  successfully: 5,162 observed entries, including 1,336 folders. The completed
  observation has active generation 1, no pending generation or work rows, and
  zero native refresh/cancellation/transfer owners. Traversal alone is not game
  membership: the root includes patch/tool material. No PS1 mapping, scrape,
  recovery route or migration is claimed complete at this checkpoint.
  The existing three sources/targets are not replaced. An inconsistent host
  database copy during catalogue writes was rejected, not repaired or used to
  restart the operation. A read-only VM inspection later confirmed the refresh
  worker had exited before publication: zero refresh and cancellation owners,
  with generation 1 retaining 1,157 completed and 77 pending folder jobs. The
  previous error was not captured, so its cause is not inferred from checkpoint
  age. One normal explicit Refresh resumed that same checkpoint; a subsequent
  VM inspection confirmed exactly one refresh/cancellation owner and zero
  transfers. No new generation, process restart or hidden retry was introduced.
  After all 1,336 folder jobs completed, a runtime inspection confirmed its
  refresh future was still pending while folder-boundary revalidation ran; the
  unchanged database during that phase was not interpreted as a stalled job.
  The same monitoring process exited zero only after verified publication. The
  native operation completed normally with both physical displays OFF. Mapping,
  fresh PS1 scraping and the remaining migration gates are ordinary unfinished
  S7 work, not a blocker or permission to begin S8.

## Reproduced mapper ANR and verified correction — 2026-10-05

- Opening the published PS1 source exposed long-label RenderFlex overflows;
  scrolling reproduced Android's actual owner-app ANR at 17:42:17 local time,
  waiting 5003 ms for a MotionEvent. The old mapper built every one of the 1,336
  folder options into a dropdown for every supported console, including hidden
  dropdown layout. The old process snapshot measured 1,517,645 KiB total PSS.
  The system-only ANR trace was not read, and this does not establish the cause
  of the separate historical logo report.
- A focused long-folder-name regression failed against the old implementation.
  The replacement retains the existing mapping/save rules and R-Shop styling:
  closed rows render only their selected label; one opened searchable selector
  lazily builds visible options. The final fixture uses 1,336 folders and verifies
  bounded rendered options, long labels, selection, clearing and cancellation.
  Unobserved persisted mappings and ambiguous aliases retain their existing rules.
- Actual native input found two remaining integration defects before closure.
  Controller A opened the dialog but B did not dismiss it; a reproducible failing
  test preceded the dialog-local B-to-DismissIntent binding. Hardware text input
  lost the letter I to the application's Library-search shortcut; a failing
  shortcut regression preceded a text-field-local pass-through binding. Neither
  change modifies application-wide input or unrelated screens. Final focused
  widget checks and scoped analysis of the two changed Dart files exited zero.
- The final native workflow opened the same published source, scrolled normally,
  entered the complete `Sony - PlayStation` search text and showed the exact root
  choice. A opened and B cancelled the selector, including from focused search,
  with the saved configuration unchanged. Before/after native captures were
  visually compared: the corrected Atari rows have no overflow stripes. The
  final process snapshot measured 521,020 KiB total PSS; last-ANR evidence still
  referred to the old 17:42:17 incident. These are snapshots, not a peak-memory
  guarantee or proof that every intermittent freeze has been resolved.
- The normal save added only PS1's root mapping. Its unrelated PSP suggestion
  was explicitly cleared before saving. Object comparison verified all existing
  sources and three existing console configurations unchanged. The PS1 SD folder
  grant then changed only the new console's target field. Existing source
  suggestion rules were not broadened or silently treated as membership review.
- Normal cached library synchronization exposes 904 remote artifacts: GameCube
  134, Game Gear 182, PSP 269 and PS1 319. Local scanning adds 524 rows (Game Gear
  366, PSP 72, PS1 86), and the actual Library opens with 1,428 rows/459 installed
  labels. The ownership journal still has exactly one owned installation. Local
  discovery is not adoption, canonical identity, a trusted ranking or removal
  authority; patch/tool material and potential edition duplicates remain subject
  to the outstanding S7 membership review. No PS1 fresh scrape is claimed.
- Builds 148, 149 and 151 ran sequentially through the shared named mutex.
  Final ticket 151 explicitly reported gate_acquired=true, exit zero and a
  verified observed profile: workers 2, parallel false, Gradle heap 3 GiB, with
  other JVM arguments preserved. Assessed Kotlin 2.2.20 is configured in-process
  sharing that heap; its compile tasks were up-to-date. Configured test forks
  were one/512 MiB, not executed by assembly; native compile tasks were also
  up-to-date, so fresh plugin/native concurrency is not claimed. The helper
  retired only a confirmed-idle incompatible daemon, not an active build. No
  memory failure, budget increase or external release occurred.
- Independent final APK/package/activity/signature inspection passed. The normal
  existing debug package was updated in place, without uninstall or data clearing.
  All 29 private files inspected immediately before that final update retained
  their hashes before first launch; the separately read configuration also
  matched exactly. Final APK SHA-256:
  `4f649c851153ab557f6ec5710f7a5eb3e993a90014037be581249ee628a77ce6`.
  Cold startup reached Home in 2635 ms; controller navigation subsequently opened
  the real Library. This verifies the current launch and reproduced mapper fix,
  not the historical logo hang's root cause.
- A fresh stable database observation passed quick_check and device-before/
  device-after/host digest agreement. All four configured source snapshots were
  published with no pending work; all metadata and transfer jobs were completed.
  An older unconfigured catalogue checkpoint was preserved, not mistaken for a
  live worker or restarted. Both physical displays were verified committed OFF.
- Transactional cleanup reviewed and removed exactly the two expendable
  comparison captures (193,978 bytes), with no residual ticket members. The
  exact task-owned device screenshot/XML were also removed and absence verified.
  Required diagnostic records, private migration journals and the current normal
  APK remain; no user files or shared metadata were cleaned.
- S7 remains the sole ACTIVE stage. Its whole-collection metadata, eligible
  canonical membership, defensible Top-25 retention and live cloud/recovery/
  migration criteria are still unfinished. No existing ROM was adopted, moved
  or removed; S8/S9 remain NOT STARTED.

### Subsequent PS1 completion and scope extension — 2026-10-05

- Normal PS1 ScreenScraper job 20 completed all 405 requested rows: 214
  needsReview, 136 ambiguous and 55 unmatched, with zero accepted/rated results.
  Follow-on artwork job 21 completed with zero items. A fresh bounded read-only
  database inspection verified device-before/device-after/host digest agreement,
  quick_check, both terminal jobs and exact outcomes. The scope is 319 remote
  artifacts plus 86 local rows, not 405 reviewed canonical games. No duplicate
  refresh or fabricated ranking was used to resolve uncertain matches.
- Revision 7 adds SAVE-01/S10, with the user's subsequent instruction to cover
  most installed emulators. Full package discovery was read-only; save access,
  backup uploads and restore support are not claimed. S10 remains NOT STARTED;
  S7 is the sole ACTIVE stage, and S8/S9 remain NOT STARTED. FolderSync's pairs,
  schedules and transfers were not changed or invoked; it remains as-is.

### PS1 independent pass and safer cached review — 2026-10-05

- Normal native IGDB Fresh job 22 completed the same PS1 scope: 405 requested,
  233 needsReview, 135 ambiguous and 37 unmatched, with zero matched/rated,
  failed/unsupported or pending. One owner/worker was observed through completion;
  no duplicate refresh was started when a busy UI could not provide an idle dump.
  Stable device-before/device-after/host database digests and quick_check passed.
- Two normal native selections explicitly chose the correct PS1 identities and
  Official releases classification, then used Save match and recheck. Jobs 23
  and 24 each completed one matched/rated item. The production community basis
  has 122 votes for the first and 44 for the second; unrelated critic/overall
  values were not substituted. These are exact reviewed editions, not complete
  multi-disc groups, a whole-library Top-25 ranking or removal authority.
- Native review exposed a current-stage safety defect: the cleaned title omitted
  the source filename/folder, disc and patch labels. META-03 now documents that
  existing review context requirement. The bounded cache-only projection reads
  just the current edition's artifact members/local cache row and renders their
  labels beside the search title. It does not approve identities, infer tags,
  request provider metadata or retrieve ROM bodies.
- The regression first failed for missing labels, then passed at landscape,
  portrait and narrow portrait sizes. Existing checks also prove wrong-platform
  rejection, independent overlapping tag selection, exact-scope isolation and
  no extra provider requests. Focused metadata-job tests and scoped analysis
  passed. The existing bounded 30,000-edition fixture observed about 310 MB peak
  RSS, not an unbounded memory failure. No full repository suite was launched.
- Gated build 164 acquired the shared mutex but failed before compilation because
  PowerShell split an unquoted `-Ptarget=lib/main.dart` into two arguments. A
  separate argv reproduction established the cause; quoting each Gradle argument
  fixed the invocation. Build 165 then held the same mutex through exit zero.
  Observed workers 2, parallel false and Gradle heap 3 GiB; assessed Kotlin 2.2.20
  uses in-process compilation sharing that heap. Test tasks were configured one
  fork/512 MiB but not executed. App native pools remain one; the plugin native
  tasks ran, but their effective full concurrency is not independently measured.
  Neither attempt produced memory-failure evidence or required a budget increase.
- Independently inspected APK package/activity/signature matched the existing
  debug installation; SHA-256 is
  `30042a8a96ab482d6aaf80db1d50e0960df61d98c4118887a851afa51b6d4606`.
  Installed in place only after all metadata jobs were terminal, with no uninstall
  or clearing. Native PS1 review now displays the original CHD/disc label and an
  unmodified official title's filename. Stale ScreenScraper candidates remain
  blocked after identity correction. Opening cached review created no new jobs.
- Configuration and secure-credential fingerprints match the pre-update baseline;
  all three completed IGDB jobs, both exact reviewed ratings and the 1,428-row
  Library are preserved. A blanket private-file hash assertion also included
  regenerated Flutter binaries, a resource marker and normal startup preferences/
  database writes, so that assertion is not claimed as byte-for-byte app-data
  preservation. No ROM, save, BIOS, FolderSync configuration or cloud archive was
  changed by this fix. Required S7 membership/ranking/recovery/migration work
  remains unfinished; S7 is ACTIVE and S8-S10 are NOT STARTED.

### PS2 catalogue, interrupted connectivity and checksum audit — 2026-10-05

- The normal native Sources workflow added a fifth read-only Drive source rooted
  at the actual PS2 archive. Existing four source and console objects were checked
  unchanged; no second account, new OAuth client or backup-write grant was used.
  The source-add refresh and subsequent explicit Refresh shared the same active
  scope future rather than creating a second worker.
- Generation 1 published 1,482 observations, including 463 folders, with no
  remaining traversal work. Stable device-before/device-after/host database
  digests and quick_check passed. The mapper correctly disabled selections before
  publication. Comparison of current platform aliases with all published folder
  names offered only PS2; normal Save mappings created only that mapping.
- Normal console settings/Android folder selection saved the actual SD PS2
  directory. Object comparison verified the prior four sources/console objects
  unchanged and the new physical target/mapping correct. No existing file was
  adopted, installed, moved or removed. The stable Library now contains 202
  remote PS2 artifacts plus 23 local rows, not 225 canonical games.
- ScreenScraper Fresh job 25 was created once. It paused before the first lookup
  with blocked_status `unavailable`, preserving all 225 pending items. A current
  microG authentication crash reported Host unreachable; R-Shop's original
  process stayed alive and the selected SD target persisted. Direct Thor HTTP
  checks then proved an expired hotel captive-portal session, despite Android's
  stale validated-network report. The laptop hotspot could not start because
  icssvc was disabled; its attempted service change was denied and it remained
  disabled. No VPN, firewall, service configuration or credentials were changed.
- Android's normal Wi-Fi Sign in to network action opened the hotel portal.
  Its existing Continue to the Internet action restored access; direct Thor
  checks returned HTTP 204 for connectivity and HTTP 200 for ScreenScraper.
  One normal Resume saved job action resumed job 25, without a new generation,
  process restart or Fresh retry. Live progress subsequently processed lookups.
  This resolved connectivity incident is not an outstanding stage blocker.
  Job 25 completed 225 lookups: 118 need review, 43 ambiguous, 64 unmatched,
  zero matched/rated/failed/unsupported/pending. Artwork job 26 completed with
  zero items. The subsequent normal IGDB Fresh job 27 completed the same scope:
  142 need review, 47 ambiguous, 36 unmatched, zero accepted/rated or failures.
  Stable device/host database digests and quick_check verified terminal results.
- The single read-only PS2 checksum audit joined exit zero. Its private durable
  journal contains 24 exact SD files: 23 stable artifacts totaling 45,166,984,325
  bytes match their cached Drive size/digest identities, and one 576-byte non-ROM
  file is preserved. All dispositions are preserve and removalAuthorized=false.
  Cached checksums do not prove current cloud readability/version, canonical
  grouping, ranking or a tested format restore. Those migration gates remain.
- S7 remains the sole ACTIVE stage; S8-S10 are NOT STARTED, and FolderSync is
  untouched. The subsequent rating-binding defect and its verification follow.

### Unchanged reviewed evidence survives catalogue sync — 2026-10-05

- A normal exact PS2 review selected the original game/platform rather than an
  alternate edition, explicitly classified it as official, and rechecked it in
  job 28. The accepted community score had 1,341 votes, above the assessed floor.
  Returning to Home then removed its usable score despite unchanged source
  bytes and classification. The raw provider record remained stored.
- Reproduction traced the failure to catalogue seeding removing/reappending
  unchanged artifact evidence after manual classification. Reversing only those
  unchanged facts reproduced the saved binding; other identity facts had not
  changed. The fix preserves existing evidence order for unchanged content and
  unchanged folder declarations. Changed bytes/classification retain existing
  invalidation behavior; there is no global hash migration or stale promotion.
- The store regression failed before the fix. Focused effective-rating,
  metadata-job and library-store checks passed after correction, including
  changed-content invalidation and unchanged folder bindings. Scoped analysis
  and diff checks passed; no full suite was run.
- Build 166 ran once through the shared gate supervisor and exited zero.
  Observed workers 2, parallel false, Gradle maximum heap 3 GiB and assessed
  Kotlin 2.2.20 in-process compilation sharing that heap. Test tasks configured
  one fork/512 MiB were not executed; app native pools remain one, with native
  tasks mostly up-to-date. Full plugin-native concurrency is not measured.
  No memory-failure evidence or budget increase occurred. The supervisor's
  gate-acquired result field was truncated from the retained tool output; this
  records the successful gated invocation, not an independently captured receipt.
- APK package/activity and signing certificate matched the existing owner.
  Independently inspected SHA-256:
  `e53e507c7747090a6b21beb4b8cd25151def778c5e524d2afbb2cd056b789a1b`.
  Normal in-place installation preserved configuration, both secure credential
  fingerprints, all 28 terminal metadata jobs, three raw reviewed provider
  records and the 1,653-row Library. No uninstall or data clearing occurred.
- On the updated Thor, normal selected-game Fresh produced job 29 with one
  matched/rated lookup and no pending work. Returning through the normal Home
  sync and reopening the same details retained the 89.1/100 user score, 1,341
  votes and provenance. A stable database/quick_check observation confirmed
  score 89.12546853689747 and ranking_eligible=1 after Home sync. Already-stale
  earlier records were not silently rebound; exact fresh rechecks own recovery.
- This verifies the specific refresh regression, not whole-library identity,
  canonical ranking or migration completion. No ROM download, adoption, removal,
  cloud mutation, FolderSync change or S10 implementation occurred.

### Source setup text-input regression and next console scope — 2026-10-05

- Native keyboard entry dropped the letter used by the application's search
  shortcut from a new source label. Investigation identified inherited I/F
  search/favorite shortcuts rather than a cloud authorization failure. The
  focused widget reproduction invoked both app shortcuts while each real source
  field was focused, failing the no-navigation contract before the fix.
- The two setup fields now use the same local stop-propagation technique as the
  existing folder mapper, leaving those letters to platform text input. No global
  key map, controller behavior, provider transport or authorization was changed.
  Focused setup/mapping tests, scoped analysis and diff checks passed.
- Gated build 167's inspected receipt confirms gate_acquired=true and exit zero.
  Effective workers 2, parallel false, Gradle maximum heap 3 GiB; assessed Kotlin
  in-process shares that heap. One-fork/512 MiB test configuration was observed,
  not executed by this build. App native pools remain one; plugin native tasks
  were mostly up-to-date and full native concurrency is not independently
  measured. No memory-related failure or budget increase occurred.
- APK package/activity/signature matched the installed debug owner; independently
  inspected SHA-256:
  `bd78b692d6da0e4465281167861d7f78940d6ea04334bae2ddbb1d3a98e90e60`.
  The in-place update preserved configuration, secure credential fingerprints,
  all 29 terminal jobs, metadata records and the 1,653 cached Library rows.
- Native source entry retained the full console name, and the exact existing
  public client ID was verified before Connect. The default existing account
  connected normally; observed My Drive/Roms/N64 navigation selected that exact
  root. Save created only the sixth read-only source; object checks verified
  all five old sources and every old console object unchanged. No write grant,
  second account, ROM transfer or FolderSync operation occurred.
- Its normal refresh has not yet been verified as published. The mapper remains
  disabled without successful publication, and no mapping was saved. Read-only
  host snapshots during active database writes were rejected as unstable, not
  treated as corruption or repaired. N64 publication/mapping/fresh metadata and
  migration remain ordinary unfinished S7 work; S8-S10 remain NOT STARTED.

### N64 publication, actual SD targets and score projection proof — 2026-10-05

- The sixth source's generation 1 published successfully: 5,632 observations,
  670 folders, no pending generation or remaining catalogue work. Normal mapping
  saved the single unambiguous N64 console root. Existing mappings were preserved.
- Normal Android folder pickers selected `/storage/75D7-DC5F/Roms/n64` and
  `/storage/75D7-DC5F/Roms/gc`. Console-settings edits are persisted when exiting
  the console list, not merely its detail page. After normal exit, configuration
  comparison verified exactly those two target-field changes; all six source
  objects and every other console field remained unchanged.
- Normal Home sync and a stable SQLite/quick_check observation established:

  | Console | Library artifact rows | Remote artifacts |
  | --- | ---: | ---: |
  | Game Gear | 548 | 182 |
  | GameCube | 206 | 134 |
  | N64 | 1,543 | 1,391 |
  | PS2 | 225 | 202 |
  | PSP | 341 | 269 |
  | PS1 | 405 | 319 |
  | Total | 3,268 | 2,497 |

  These are artifacts/cache rows, not canonical games or installation ownership.
  Native Library displayed All 3,268 / Installed 695; that Installed label alone
  does not establish R-Shop ownership of existing SD files.
- Two read-only streaming audits completed and their terminal summaries were
  independently reconciled against every journal entry: N64 has 320 game
  archives matching cached Drive size/digests (3,267,752,208 bytes) and two
  preserved non-ROM files (1,124 bytes); GameCube has 80 matching RVZs
  (69,814,480,572 bytes). Every disposition remains preserve and removal authority
  false. Private exact-file journals stay outside Git. Cached checksums are not
  live cloud-version/readability or format-specific restoration proof.
- Normal N64-only Fresh was invoked once. ScreenScraper job 31 is still running
  on its 1,543-row snapshot, with no blocked status. The latest read-only native
  observation reported 445 requested, 1,099 pending, 299 needing review, 80
  ambiguous and 65 unmatched; none matched/rated. Progress persisted while the
  displays were off. No duplicate worker or N64 IGDB pass was launched.
- The second reviewed PS2 identity (IGDB 1229, exact original Disc 1) had a dirty
  query projection after sync, not a lost identity binding. Normal Library search
  and details showed 90.2/100 from 28 IGDB user ratings with scale/retrieval
  provenance. A subsequent read-only query found score 90.24511423825714,
  ranking_eligible=1 and dirty=0. The earlier IGDB 2207 record remains eligible at
  89.12546853689747. No production patch was made for the stale diagnostic read;
  Disc 2/canonical bundle review remains unfinished.
- No Gradle command, APK replacement, ROM transfer/adoption/removal, cloud write,
  FolderSync inspection/change or S10 implementation occurred in these checks.
  S7 remains ACTIVE; remaining fresh scopes, canonical identities, defensible
  ranking and actual migration are ordinary unfinished work.

### S7 score-basis extension — 2026-10-05

- Extended the existing public persistent-worker reception fixture to N64, PSP
  and Game Gear. The assessment records actual scales/counts, exact offered
  identities, independent reception, edition mismatches and ordering differences.
  N64/PSP use the same assessed IGDB community policy; no critic/total fallback,
  title boost, unknown-count exception or lower vote floor was introduced.
  Game Gear remains unassessed because its captured records are sparse/unrated
  or ambiguous. See SCORE_RECEPTION_ASSESSMENT.md for the public evidence.
- The focused boundary reproduction failed before production scope extension at
  its required twenty-vote case. Effective-score and indexed-query checks passed
  afterwards, including ownership, freshness and low/unknown support. A fresh
  real-provider capture followed by offline production query verified nine
  supported games from fifteen public fixtures, identical Top-25 membership and
  provisional incomplete coverage. Scoped analysis and diff checks passed; no
  full suite was run.
- The installed APK remains build 167. Native integration of the extended basis
  has not yet been performed, preserving the currently running N64 scrape. The
  last read-only observation of that same job 31 reported 675 requested, 869
  pending, 456 needing review, 120 ambiguous, 98 unmatched and zero matched/rated,
  with state running and no blocker status. No duplicate worker was launched.
  Both physical displays were confirmed committed OFF after native verification.
- No Gradle command was run, so this checkpoint claims no new mutex acquisition
  or effective build-profile measurement. The task-only read-only observation
  helper is retained outside Git until this active job's terminal outcome can be
  inspected; its exact registered cleanup transaction and private migration
  journals are preserved. No external release, save backup or SD removal occurred.

### Collection-root setup and configuration reuse — 2026-10-05

- Normal native setup saved one additional read-only Drive source rooted at the
  owner's ROM collection. One Refresh catalogue action started generation 1.
  The latest read-only native observation found active=null, pending=1, 56,338
  observations, 5,457 folders and 5,061 pending folder work rows. Those are
  unpublished traversal observations, not mapped games or payload downloads.
  Native configuration comparison verified all six prior source objects and
  every existing console object unchanged; the new source still has no mappings.
- The original N64 ScreenScraper job 31 remains running with no blocked status:
  1,267 requested, 277 pending, 860 needing review, 218 ambiguous, 188 unmatched,
  zero accepted/rated. No duplicate worker or new IGDB pass was started.
- The owner's configuration-reuse question distinguishes feature verification
  from S7's collection-wide metadata/migration. A PS1 workflow suffices for the
  former; additional console mappings serve the latter. Existing config export
  preserves source/account/root identities, manual folder mappings, source
  priorities and console SD targets without bearer tokens or provider secrets.
  Normal import validates that configuration before saving it. Focused Drive
  persistence/resolution checks passed on the current source, exit zero.
- Before any separately authorized release handoff, produce a private export
  of the final console/source configuration and verify its normal import without
  repeating folder selection. Do not publish that export or embed owner-specific
  mappings in an APK. The metadata/artwork bodies already use durable shared
  storage; the other package must select the same directory and regain access.
  OAuth consent and secure metadata credentials are package-local, not exported.
  Actual debug-to-release setup transfer has not yet been live-verified and is
  not claimed here; a shared cache is not automatic transfer of all preferences.
- Required normal debug build 170 passed through the shared supervisor after
  waiting its FIFO turn. Gate acquisition and observed two-worker/no-parallel/
  3 GiB Gradle profile were reported. Kotlin 2.2.20 remains configured in-process,
  sharing that heap; Metaspace 1 GiB and code cache 256 MiB were preserved.
  Test-task configuration reported one fork/512 MiB, not executed test-JVM proof.
  Full plugin-native concurrency remains a verification gap. No memory failure
  or heap increase occurred. The preceding gated attempt 168 failed because an
  unquoted PowerShell target argument produced a stray `.dart` task; the retry
  used whole-argument quoting only after that process had exited.
- The resulting normal debug APK has SHA-256
  `0bc2b340706705cf968809ecb1897d6dc726d4f3e18fd4806235680c45c50966`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12 and the unchanged debug
  signer. It has not been installed over the live jobs. Build log:
  `28f5ea42b00d4d38b826b84d867ef12f.log` in the shared build-gate log directory.
  Both physical displays were freshly confirmed OFF. S7 remains the sole ACTIVE
  stage; no FolderSync change, SD removal, save-backup implementation or external
  publication occurred.
