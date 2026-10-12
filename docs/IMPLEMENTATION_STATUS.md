# Implementation status and reconciliation ledger

Authority: [SPECIFICATION.md](SPECIFICATION.md).
Execution order: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## Scope state

### Complete PPSSPP SAVEDATA capture and publication backend verified — 2026-10-12

S10 remains the sole ACTIVE stage; S11 is NOT STARTED. The working tree now
contains a complete-folder capture route, root-backed atomic directory publication,
a native exclusive-fixture proof and the Dart capture channel boundary. This is
NOT normal-UI SAVEDATA backup/restore delivery; the verified publication primitive is not
yet connected to the normal restore journal/cloud/UI workflow.

The route resolves the SAVEDATA parent from PPSSPP's existing Memory Stick
discovery and lists its child save folders through one joined root helper.
Capture guards the complete folder with inotify, checks the reviewed native-exit
boundary, streams every regular member (including empty companions), reconciles
membership/inodes and seals the existing app-private capture journal. Unexpected
or nested entries are rejected rather than silently omitted. Save-state routes
remain separate. The current utility-format capacity is 128 members and 512 MiB
aggregate; exceeding it is an explicit error, not partial capture.
An absent target folder can now produce a parent-bound restore baseline without
creating a dummy game save. Existing empty folders remain distinguishable from
missing folders. The publication route creates an exclusive emulator-owned
same-filesystem stage and uses one directory exchange (or no-replace first
publication); it has no unlink/ordinary-rename fallback. The previous complete
folder remains available for rollback. The fixture now checks membership changes,
changed-baseline refusal, exact resulting bytes and an atomic rollback. All these
checks passed on the actual Thor, including first-folder publication and refusal
to replace an existing folder through the first-publication route. Journaled publication/recovery and stage
retirement remain unfinished integration work, not delivered user features.

Focused regression request 762 (`973ca19886b2485ead69ce253b545f82`), original
command session 75447, completed with the expected failure: the old retirement
whitelist rejects a four-member capture. Production Kotlin compiled, and the
other exact-target preservation/retirement checks passed. The supervisor recorded
mutex acquisition, completion before release and exit 1. Observed workers=2,
parallel=false and Gradle heap=3 GiB; Kotlin 2.3.21 is configured in-process.
The focused test task used one 512-MiB fail-fast fork. No memory failure or heap
increase. Log: `b49fd0a32b8e44458f8f788948254904.log` in the shared gate log directory.
The retirement whitelist is now extended to the exact numbered complete-folder
members, preserving numeric order, seal-last and unexpected-entry rejection.

The focused Dart save-folder channel checks pass, including discovery, all-member
capture with empty companions and unsafe/partial receipt rejection. Focused Dart
analysis reports no issues. No full suite or overlapping test workload was run.
Gated green/native assembly request 765 (`f58cb21e85944480aa0b541da875fe6c`),
original command session 51101, completed successfully with mutex acquisition,
exit 0 and confirmed completion before release. Focused retirement/boundary checks
passed, as did owner/instrumentation assembly. Observed workers=2, parallel=false,
Gradle heap=3 GiB; reviewed Kotlin 2.3.21 runs in-process. Test concurrency is one
512-MiB fail-fast fork; generated app native compile/link pools have depth one on
all three ABIs. No memory failure or budget increase. Log:
`32ea603e6c074ca0926dd7a045586a2f.log` in the shared gate log directory.

Preserving installation and the actual `ppssppSavedataCaptureProbe` passed. Installed
owner SHA-256 `c09d93311123df69e7069c3fa341accf08d27030fd9ca8ab70eaa069560ea833`
and test SHA-256 `b63904b248a0ada0886466ec6cb22e8e38777bf25d7a510b84d731bcb0640cb6`
match the built artifacts; owner signer remains unchanged. All ten preference
digests match before/after installation. The complete folder capture, independent
bytes/digests, mutation/runtime refusal, service recreation, missing-folder baseline,
atomic membership-changing publication, changed-baseline refusal, complete rollback,
first-folder publication and exact capture retirement passed. Independent checks
found no fixture folder; both actual/committed displays remain OFF. No real save,
ROM, emulator setting or Drive object was changed by this fixture.

The manifest regression reproduced rejection of a legitimate empty companion.
Portable-save members now permit zero bytes only with SHA-256(empty); states still
reject empty payloads. Focused manifest/generation checks and analysis pass. This
is not live Drive verification of a zero-byte payload.

Next: continue complete-group restore, game/edition/ancestry integration, normal UI,
watching and the real Drive round trip in S10. Those are ordinary unfinished
requirements, not waived criteria or later-stage deferrals. No new release,
legacy handover or S10 completion claim has been made for this backend slice.

### PPSSPP normal Exit no longer requires process eviction — 2026-10-12

S10 remains the sole ACTIVE stage; S11 is NOT STARTED. This resolves the cached-
runtime caveat in the previous checkpoint, not the remaining SAVE-01 scope.

Live investigation distinguishes Back (LAST_ACTIVITY, native PoolW workers still
alive) from PPSSPP v1.20.4 Exit (same Android PID retained as CACHED_RECENT, native
workers joined). The old protected restore regression reproduced
`stop_ppsspp_required`. The reviewed normal-exit route now uses root-assisted
bounded main-process/thread metadata, stable PID start identity and joined
ActivityManager state queries around the thread census. It never treats a hidden
activity, low CPU, delay or Android's stopped flag as native shutdown. Other live
UID processes still block. No emulator signal, forced stop, settings mutation or
debugger is used. The route is versioned with the reviewed runtime; actual-process
exit remains supported for other versions. See S10_SAVE_BACKUP_DESIGN.md for the
primary lifecycle references and boundaries.

Focused native policy checks pass. Actual Thor checks pass for foreground and
Back-to-background rejection, followed by normal Exit acceptance. The exclusive
protected-file proof passes streamed capture/digest, exact watching, unrelated
live UID-process rejection, recreated-service normal-exit restore, changed-local
refusal and retained rollback. Protected Melon writer/mutation guards, watch,
capture/digest, expected-location restore and rollback also pass. The PPSSPP
fixture is independently absent. These proofs do not claim a new normal-UI cloud
round trip, gameplay/save loading, SAVEDATA groups or complete emulator coverage.

Gated requests 747/749/751 completed successfully; 749 ran the focused policy
tests and 751 assembled the final API-compatible owner/test artifacts. Request
751 (`293c176d1da44c19adafa3526cb69c6d`) has recorded mutex acquisition, build
completion before release, exit 0 and `completion_verified=true`. Its original
command handle was later absent; persisted supervisor completion, telemetry and
the build log confirmed terminal success without relaunching it. Observed
workers=2, parallel=false and Gradle heap=3 GiB; reviewed Kotlin 2.3.21 is configured
in-process, sharing that heap. The executed policy test task uses one 512-MiB
fail-fast fork. Current generated app compile/link pools have depth one on all
three ABIs. No memory failure or budget increase occurred. Final log:
`C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/6df2a21656f14a728d91d4df4748588b.log`.

Independent installed APK copies match built owner SHA-256
`f45190dff3686615c5cfb908999bd263b7e3eafd250cce8a45d657d1b02f0cd9`
and test SHA-256 `b3225ca8be0dbbbcdca6fd0a8db38fa2534c609d0fbe193b326ef5ce6cc402fc`.
Signer SHA-256 remains
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`;
all ten R-Shop preference digests match immediately before/after the preserving
installation. No real saves, ROMs or Drive objects were mutated by the fixtures.
No release or legacy-sync handover was performed.

Remaining SAVEDATA groups, accessible installed-emulator routes, acceptance
fault/reconnect evidence and conditional legacy handover remain ordinary S10
work. No acceptance criterion is waived or reclassified as an external blocker.
Both displays report actual and committed OFF after device checks.

### Root-assisted standalone restore exit evidence — 2026-10-12

S10 remains the sole ACTIVE stage; S11 is NOT STARTED. Root is available
proactively for discovery, tracking, capture and restore under specification
revision 25, not only after manual mapping or ordinary-access failure.

PPSSPP/Melon restore now checks actual emulator-UID process status before public
staging and again before publication, instead of requiring Android's stopped-app
flag. A single joined root helper is reused for the restore's checks, with bounded
kernel-status reads and explicit descriptor closure; no per-PID su calls, signals,
quiet delays or command-line/payload inspection. Live/suspended UID processes
block; actual exit does not require Force stop. Existing rollback, digest,
inode/namespace and conflict checks remain connected. Settings no longer prescribe
Force stop for every restore; App info remains available.

The focused UI regression failed before implementation and passed afterward;
scoped Dart analysis passes. Focused automatic watch persistence, pre-launch
reconciliation, DS/PSP restore, conflict-preservation and settings checks pass.
Native parser/PPSSPP path/settings checks pass.
On the actual Thor, the protected PPSSPP fixture demonstrates a live test-owned
emulator-UID process blocking publication despite `stopped=true`, unchanged local
bytes on refusal, joined process exit, recreated-service restore and retained-byte
rollback. Protected Melon capture/watch/restore/rollback regressions also pass.
No real save, ROM, emulator setting or Drive object was changed by these fixtures.
The exclusive PPSSPP fixture is independently absent afterward.

Gated request 744 (`83654aeaac32420ab817387ad9e59e89`) acquired
`Local\\Darka.AndroidGradleBuildGate`, exited 0 and confirmed supervision
completion. Observed workers=2, parallel=false, Gradle heap=3 GiB; reviewed Kotlin
2.3.21 runs in-process. The executed test task uses one 512-MiB fail-fast fork;
all three app ABI native compile/link pool definitions retain depth one. Native
objects were up-to-date in this build, not a new native compilation stress proof.
No memory failure or budget increase occurred. Log:
`C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/88a19571307c4c64a91327bf1b59da27.log`.

Preserving installs independently match built owner/test APK SHA-256
`7853c3dc5fab6bf3befae57fca133888a32174fb8f705867123679b4529cbdcf`
and `169b4d652a6cdb642033b7942b4bacad0562a930ff36aca286c30ef75612dc27`;
the signer is unchanged and all ten preference digests match immediately
before/after installation. No release or legacy-sync handover was performed.

This is actual-process exit evidence, not verification of every cached-runtime
normal-exit path: upstream PPSSPP explicitly retains its Android process after
native shutdown. That completion route, PPSSPP SAVEDATA groups, remaining installed
emulator coverage, acceptance faults/reconnect and conditional legacy handover
remain ordinary unfinished S10 work. The stage is not COMPLETE and no acceptance
criterion is waived or reclassified as an external blocker.
Both actual/committed display states are OFF. No root save helper remains;
`git diff --check` passes. No full-suite repetition was used.

### Protected PPSSPP state storage — ACTIVE, 2026-10-12

The owner's clarification is recorded in specification revision 25: root may be
used for automatic discovery, tracking, capture and restore based on correctness,
reliability and performance, without requiring manual mapping or an ordinary-
access failure first. S10 remains the sole ACTIVE stage.

The existing protected storage worker and exact-file watcher now support
PPSSPP's external-files Memory Stick, including configured subfolders and SD
volumes. Focused Dart checks pass for capture/path policy, configured-folder
discovery, settings/coverage, persisted automatic mapping, exact watch admission,
pre-launch reconciliation, conflict preservation and restore. The matching native
path/settings/watch unit checks pass. No full-suite repetition was used.

On the actual Thor, the app-UID protected PPSSPP fixture passes root-backed listing,
streamed capture with independent digest/byte comparison, exact publication-watch
delivery, joined shutdown, recreated-service atomic restore, changed-local refusal
and retained-byte rollback. Shared watch and protected Melon regressions also pass,
including mutation/writer refusal and restored destination bytes. The exclusive
PPSSPP fixture is removed. These are real native filesystem/channel proofs plus
host automatic-lane integration checks; they do not claim a new normal-UI cloud
round trip or PPSSPP SAVEDATA group support.

Original shared-gate request 740 (`19b8f95fbb1741468113626f046a18fc`) acquired
`Local\\Darka.AndroidGradleBuildGate`, completed with exit 0 and confirmed
supervision completion. Actual workers=2, parallel=false, Gradle heap=3 GiB;
reviewed Kotlin 2.3.21 is in-process and shares that heap. Executed debug unit
tests use one 512-MiB fail-fast fork; generated native compile/link pools have
depth one for all three app ABIs. No memory failure or budget increase occurred.
Log: `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/b16801a8c431450196e0237d8ad2d6ad.log`.

Preserving owner/test installs independently match built SHA-256
`67a7bcab57e512b5b31dab95da6ea627bed58d7d44eb012bce8dfca7c4d570dc`
and `e8efe651bfa7da22a02d357ab20a32963e4564400a3511ab9c667de3edfca92f`.
The signer is unchanged and all ten private preference digests match immediately
before/after installation. No real saves, emulator settings, ROMs or Drive files
were changed by these probes. Remaining accessible emulator routes, PPSSPP
SAVEDATA groups, acceptance faults and conditional legacy handover remain ordinary
unfinished S10 work; S11 remains NOT STARTED.
Scoped Dart analysis and `git diff --check` pass. No root save helper remains;
both actual display states are OFF.

### Automatic PPSSPP save-state folder discovery — 2026-10-12

S10 remains the sole ACTIVE stage; S11 is NOT STARTED. The normal PPSSPP mapping
panel now resolves the installed emulator's actual Memory Stick setting through
the joined root channel and lists its published state slots, without first
requiring a folder picker. The game/slot association still requires confirmation;
discovery does not enable backup or mutate emulator settings. Manual custom-folder
selection and retry remain available, including when Magisk access is refused.

The focused widget regression failed before implementation and passes afterward.
Affected settings/capture/coverage tests and scoped Dart analysis pass. The native
parser verifies actual tree/document URI and absolute-path resolution, PSP leaf
semantics, strict UTF-8 and escaping/foreign-provider rejection. Existing PPSSPP
slot-boundary and Melon settings parser regressions pass. No full-suite repetition
was used. Actual Thor app-UID/root channel discovery and listing pass, independently
matching the installed Memory Stick setting; the Melon root settings probe also
passes. These native channel plus host widget checks do not claim a separate new
normal-UI backup/restore round trip.

Build request 737 (`6c9cb7df2b0a4fd3ba13ada0275e26d1`) acquired
`Local\\Darka.AndroidGradleBuildGate` and completed with exit 0 and independently
confirmed supervision completion. Observed workers=2, parallel=false and Gradle
heap=3 GiB; reviewed Kotlin 2.3.21 remains in-process, sharing that heap. The
executed debug unit tests use one 512-MiB fail-fast fork. Generated compile/link
Ninja pools are depth one in all three app ABIs. No memory-related failure or
budget increase occurred. Log:
`C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/6747d6b2817945f1a3af527816d01e68.log`.

Preserving owner/test installations and independently read installed APKs match
SHA-256 `7abee2a2f7b0e98279d23d7730677029c271c0482890c24793f274021ee51363`
and `195ec1418d10f57c1ce69d56b5739a7d526709ef5a35b59f9c048a19bcdb8bf3`.
The debug signer is unchanged and all ten private preference digests match
immediately before/after installation. No settings, saves, ROMs or cloud files
were changed by these discovery probes; no root child remains and both actual and
committed display states are OFF. Remaining accessible emulator save/state routes,
PPSSPP SAVEDATA groups, acceptance faults and conditional legacy handover remain
ordinary unfinished S10 work, not unsupported classifications or waived criteria.

### Real DS watch-to-Drive and restore — 2026-10-12

S10 remains the sole ACTIVE stage; S11 is NOT STARTED. Root authorization is not
restricted to manual paths: the normal Library game menu discovered the installed
MelonDualDS standard protected save destination and absent first-save basename
from the real owned archive and live configuration. Normal launch then opened the
game. While Melon remained foreground, its genuine 8,192-byte initial save caused
the root watcher to enter the durable automatic lane and publish a verified Drive
generation. Independent local SHA-256 matched the verified cloud manifest:
`76e3bd2f0eca8dc61a1093fb2b22310cb8d00e3dcdb4a3689615f579d69a6a7e`.
Normal explicit restore subsequently completed at that configured protected path;
an independent digest matched again. The current local generation is retained for
rollback. No gameplay/deep-save parsing or artificial game save was required.

The real first launch exposed an expected-ENOENT error poisoning the root mutation
guard. Direct read-only protocol calls reproduced it on 720 and pass on 728;
only entry/ENOENT is exempted, never a writer or kernel mutation. Test artifact
730 passes shared and protected app-UID native capture, absence-baseline, writer/
mutation refusal, stopped-runtime recreated-service restore, changed-local refusal,
retained rollback and exclusive fixture cleanup. These are bounded synthetic
fault proofs, separate from the real normal-UI Drive workflow above.

The long game menu now stays inside landscape/portrait viewports and scrolls the
controller selection into view. Its DS launch label correctly says MelonDualDS.
The live restore check also reproduced stale settings state after another job
instance completed an automatic backup. The view now refreshes on automatic-lane
completion through existing save admission. Host regressions prove it enables the
open restore panel, joins an active same-game operation and does not replace a
requested backup with a read. Affected save/job, viewport/navigation, launch and
coverage checks pass; scoped analysis passes. No full-suite repetition was used.

Integrated owner build 734 (`9ab798c30c994402b37c7c50dd787fad`) waited behind the
existing build, acquired the shared host gate, then completed with exit 0 and
independently confirmed completion. Actual workers=2, parallel=false and Gradle
heap=3 GiB; reviewed Kotlin 2.3.21 remains in-process and shares that budget.
Test tasks are configured for one 512-MiB fail-fast fork, but assembly did not run
JVM tests. Generated compile/link Ninja pools are depth one in all three ABIs.
No memory failure or heap increase occurred. Log:
`C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/5961d50ce24748db9670f6d3485dfb9d.log`.

Preserving installation and independently read installed APK match SHA-256
`c07b8f5dd42fe2c7abcdb57b95b366e3ee015172e0b9b0a1ee221a63448f4f92`.
The debug signing identity is unchanged, and all ten private preference file
digests match immediately before/after installation. Test APK 730 is
`f1dd636260b6356ca051e3cb33eb904e66cb8d2d75a2eba874ca7ba597d16ffe`.
After normal startup catalogue synchronization completed, installed build 734
opened the real DS game through Library > Installed > Save backups. The same
settings instance showed “Verified backup available” and an enabled “Restore
verified cloud backup” action. This confirms native persisted-state integration;
the automatic-completion notification race is covered by the focused host
regression, not claimed as a separately reproduced native timing test.
Remaining installed-emulator routes/faults and conditional legacy handover remain
ordinary S10 work; none is waived or claimed complete by this slice.

### DS archive integration — verified slice, 2026-10-12

S10 remains the sole ACTIVE stage; S11 remains NOT STARTED. DS `.7z` and `.zip`
now use the existing typed normal queue, complete streamed validation,
publication/recovery, exact-byte adoption and offline revalidation. The owned
and separately byte-bound-copy grants use the existing read-only document route;
legacy untyped archives are not silently adopted. Save preparation still precedes
Melon handoff and conflicts prevent launch. Save review derives the basename from
the archive filename, matching Melon's compressed processor, not its member name.
There is no new extraction/cache engine, ROM rewrite or whole-ROM allocation.
The DS-only streamed work budget is 512 MiB; prior console budgets and the existing
32-MiB dictionary / 40-MiB decoder memory bounds remain unchanged.

The new launch-format regression first failed because archives were unsupported.
Focused native 7z/ZIP validation and existing-console checks pass; affected host
queue/recovery/adoption/launch tests and scoped analysis pass. Request 718
(`eb5fe437ae18452d896ea084f7c09c5a`) verified the native single-member decoder.
Integrated request 720 (`9b970e434eed45e7a298e667ddc30054`) acquired the same host
gate, passed the existing Sega ZIP checks and assembled owner/test APKs with exit
0 and independently confirmed completion. Observed workers=2, parallel=false,
Gradle heap=3 GiB, reviewed Kotlin 2.3.21 in-process; the executed debug tests use
one 512-MiB fail-fast fork. Other test-task configuration markers are not execution
evidence. Generated compile/link Ninja pools remain depth one in all three ABIs.
No memory failure or budget increase occurred. The gate log is
`C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/adaa38bfbdc04c56ae1300d9d67279d7.log`.

Preserving installation retains the debug signer. Local and independently read
installed owner/test SHA-256 values match
`360a3800862aefbc6140f4ee224e5de888120dd5aaa540f66349c02fb1ef0a26` and
`9a55897d84aeaf87113d4018ff8b573f198d844333324c72e0545500eb3e6b73`.
The actual Thor ZIP proof passes unchanged archive reads and save-location review
with a differently named member; read-only/identity/ownership/publication/removal
refusal and exclusive fixture cleanup pass. Raw DS and generic owned/bundle/
observed-copy regressions pass. Shared and protected live-runtime coherent capture
also passes on this artifact while Melon PID 4625 remains running; unsafe live
restore is refused without changing bytes. Fresh configuration/catalogue/jobs and
all current private preference hashes match the pre-update baseline. No root
helper remains and both actual/committed display states are OFF.

No real DS game or new Drive round trip was executed. The configured Thor `nds`
folder currently contains only README/empty subdirectories, not the historical
local-archive inventory. Real on-demand game/watch-to-Drive verification, remaining
installed-emulator coverage/faults and conditional legacy handover remain ordinary
S10 work. This is neither stage completion nor an acceptance waiver.

### DS launch/save integration — verified slice, 2026-10-12

S10 remains the sole ACTIVE stage. The automatic DS backup control now shares
the existing durable backup lane and appears in Backup and Status; capture no
longer instructs users to force-stop Melon. Restore retains its distinct writer
boundary. Focused UI/job checks pass enablement review and the separate restore
instructions. Gated integrated assembly 709 passed and its preserving install
matched SHA-256 `1e906a3cca94487fa41a6ef07afe0b3179797e8fd80300b9469db76997194870`.
The protected running-runtime capture proof was repeated successfully on that
artifact, not inferred from the earlier native APK.

The verified owned-file launcher now includes a standalone `.nds` handoff to
MelonDualDS, retaining fresh installation/byte-bound-copy validation and exact
read-only URI grants. Host regression proves that save preparation finishes
before the handoff, and a save conflict prevents emulator/companion launch.
Save-location review uses that same grant, actual leaf name and live emulator
settings. The external URI processor has no ROM parent; ROM-relative settings
therefore resolve the emulator's standard protected directory, rather than an
invented ROM-parent folder. Custom settings remain honored. The UI automatically
selects that exact destination/name, including an absent first save, without a
folder picker; edition review and backup opt-in remain explicit.

Focused launch/settings checks and scoped analysis pass. Request 713 passed
focused native leaf/storage checks and assembly. Final request 716
(`e4bc6557056046cc8d32c5d65ff0a29d`) acquired the shared gate and completed with
exit 0 and confirmed completion. Observed workers=2, parallel=false and Gradle
heap=3 GiB; reviewed Kotlin 2.3.21 remains in-process and shares that heap.
The earlier focused native tests ran in one 512-MiB fail-fast fork; 716 assembled
the integrated artifacts, not another unit-test run. Generated compile/link
Ninja rules retain the depth-one app pool for all three ABIs. No memory failure
or budget increase occurred.

Signer-preserving owner/test installation independently matches SHA-256
`1f9fe9796b6cb4dc5db8971d9b989b4e50eb437e20c3f3f50ba7d953de5cd5c6`
and `6da41971379509ab79ece7544e61b8d88fef2ddf30046cd245a7c4e8924036a4`.
The actual Thor DS document proof passes read/name/size and launch-bound live
save-location review, plus write/identity/ownership/publication/removal refusal.
The shared and protected running-runtime capture proofs pass on these exact
artifacts. The existing generic owned/bundle/observed-copy provider proof also
passes. All exclusive fixture files/rows are removed, no root child remains,
configuration/catalogue/jobs and all current preference hashes match the
pre-install baseline, and both actual/committed display states are OFF. This is
native grant/discovery/capture evidence, not a live ROM handoff or Drive round trip.

Remaining ordinary S10 work includes DS archive
handoff for the collection's `.7z` files, watch-to-Drive verification, remaining
installed-emulator coverage/fault cases and conditional legacy handover. This is
not a new required deferral or a waiver. S11 remains NOT STARTED.

### Coherent Melon capture without force-stop — verified slice, 2026-10-12

S10 remains the sole ACTIVE stage. Melon capture no longer requires Android's
stopped-package flag. It arms a backing-directory mutation guard before a
root-only read-only census of open writable descriptors, retains the complete
source/entry/group checks, and verifies the guard after copying. A failed guard
stays invalid. Protected captures reuse their source child; shared saves keep
direct JNI data IO with one joined snapshot-only helper. There is no emulator
signal, quiet-period timer, per-chunk process or runtime ADB dependency. Restore
retains its separate writer boundary, conflict checks and durable rollback.
This supersedes older stopped-**capture** checkpoints below, not restore rules.

The actual Thor regression first reproduced the unsafe case on request 701:
capture succeeded while an expendable save was still open for writing. Requests
704 and 705 passed focused native storage tests and owner/instrumentation
assembly. Final request 705 (`c2d2cb075b754f0395e9105ef9aab17c`) acquired the
shared gate through confirmed completion, exit 0. Observed workers=2,
parallel=false and Gradle heap=3 GiB; reviewed Kotlin 2.3.21 in-process compilation
is configured without a task-specific override and shares that heap. One
512-MiB fail-fast test fork was configured and the focused tests executed.
Actual generated app Ninja compile/link rules use a depth-one pool per ABI.
No memory failure or budget increase occurred; no universal host cap is claimed.

The preserving install independently matches owner SHA-256
`0ffd94cfd724151a299f099ed0c100f7a8fd774adbc7fa99be000126c253c840`
and instrumentation SHA-256
`40be3c34dda053c71b0ae99ef92a3766395cc04cc9acf8df0dfa9945084630f5`;
the existing signing identity is verified. On these exact artifacts, protected
and shared Thor probes pass open-writer rejection, overlapping-mutation
rejection, sticky invalidation, read-only descriptor admission, complete
capture/digest, stopped-runtime restore and rollback. Melon was then opened at
its ROM list without launching a game: PID 4625 and `stopped=false` were observed.
Both routes still captured successfully, while restore was rejected without
changing fixture bytes. All exclusive fixtures and root children are removed.

R-Shop's configuration, saved jobs and all ten private preference digests are
unchanged. Melon's preference-file digest changed after its normal app launch
(`bc40ab...` to `7a419a...`); it was not reverted or rewritten by R-Shop. Its
reviewed save settings remain `use_rom_dir=true`, `.sav` and
`save_state_location=save_dir`; the current native settings probe passes.
Both actual and committed display states are OFF.

This proves synthetic capture with the application running at its ROM list,
not a new gameplay or watch-to-Drive workflow. Automatic DS UI/launch association,
normal end-to-end Drive verification, remaining installed-emulator coverage,
fault/reconnect cases and conditional legacy handover remain ordinary S10 work.
S11 is NOT STARTED; no acceptance criterion is waived or silently deferred.

### Protected save watching — verified slice, 2026-10-12

S10 remains the sole ACTIVE stage. Protected MelonDualDS save watching now uses
kernel-confirmed inotify registration on the pinned backing directory through
one root child, with bounded binary frames and EOF-driven joined shutdown. It
uses neither ADB nor a polling/quiet-period timer at runtime. Ordinary shared
folders retain the existing FileObserver route. Exact DS mappings now enter the
existing durable automatic-backup lane with separate SRAM identity; existing
schema-1 PSP associations retain their encoding and key. Registration/close
work runs off the platform thread. Events are coalesced until Dart acknowledges
durable admission; loss of registration cannot be overwritten by an early
successful receipt. Events do not claim writer completion or choose conflicts.

The focused Melon lane regression first reproduced the missing route and now
passes, together with the affected backup-job checks and scoped Dart analysis.
Gated requests 697 and 698 passed native watch/delivery tests and APK assembly;
698 (`894307bd5222447a944cef729e37dbdf`) is the final verified build. The gate was
acquired through confirmed completion, with observed workers=2, parallel=false,
Gradle heap=3 GiB and reviewed Kotlin in-process compilation sharing that heap.
One 512-MiB fail-fast test fork executed. Actual generated Ninja compile/link
rules use a depth-one pool per app ABI; this is not a universal host memory cap.
No memory failure or budget increase occurred.

Preserving installation independently matches owner SHA-256
`e73ba68d4a9654cfb1d0c5425cdfe8b4f391938abb4c0e8ab8cd44323f73b80d`
and test SHA-256
`a9695acdf230e31e2e59710476b076e24d639c3ccff92d4a2d734244f06f6982`.
Real app-UID Thor probes pass for protected and shared Melon exact-file events,
joined shutdown, capture/digest, changed-local rejection, recreated-service
restore and retained-byte rollback. The ordinary PSP file-watch probe also
passes. Exclusive fixtures are removed. Fresh configuration/jobs and all private
and emulator preference digests are unchanged; both displays are OFF.

This verifies watching and the durable-lane integration separately, not a new
real watch-to-Drive workflow. Automatic DS UI/launch association and the normal
writer-completion route remain unfinished: current capture/publication still
requires the stopped-runtime boundary. Remaining installed-emulator routes,
fault/reconnect cases and conditional legacy handover remain S10 work. S11 is
NOT STARTED; no acceptance criterion has been waived.

### Current save-settings discovery — verified slice, 2026-10-12

The normal DS mapping view now automatically inspects the selected emulator save
settings through root. It resolves selected internal/SD external-storage custom
trees and lists their saves without a folder picker, while retaining explicit
game association and manual/custom/standard-folder controls. ROM-relative mode
does not silently substitute the fallback or a stale custom preference. Focused
Dart/UI discovery checks pass. Gated request 691 passed focused native tests and
owner/instrumentation assembly, but the real app-UID discovery probe failed with
`save_settings_unresolved`. Read-only namespace inspection traced the failure:
the app's inherited mount namespace hides the emulator's private preferences even
from UID 0; Magisk `--mount-master` exposes the same existing file. The settings
child now selects that namespace, leaving verified save IO unchanged. Corrected
build request 694 (`9b8be05b0b10438cb04ebc628141ec81`) completed with exit 0:
focused native settings tests executed/passed and owner/instrumentation assembly
passed. The shared gate was acquired through confirmed completion. Observed
workers=2, parallel=false, Gradle heap=3 GiB; reviewed Kotlin in-process shares
that heap. One 512-MiB fail-fast test fork was configured/executed. Native code
was unchanged; existing app compile/link pools remain depth one per ABI, not a
claimed universal host cap. No memory failure or budget increase occurred.
Preserving installation independently matches owner SHA-256
`6025367cb191c14d212a2e4b696166fc45417c57c6602f12fe0c88d02e958239`
and test SHA-256
`bdff6b521a60fb6178a76f0b80df933e5d5671bb2f6826ff554ea08ea93ac6fe`;
the existing signing identity is retained. The actual app-UID/root settings probe
now passes, including Android XML parser rejection cases and the normal channel's
live settings result. The protected save capture/restore/rollback regression also
passes and removes its exclusive fixture. Fresh schema, catalogue configuration,
saved jobs, all ten private preference digests and the emulator preference digest
are unchanged. Both actual and committed display states are OFF. This verifies
the discovery slice, not a second ACTIVE stage or all SAVE-01 acceptance.
Protected watching, automatic launch association, the normal watch-to-Drive
workflow and remaining installed-emulator routes/handover are still unfinished.
S11 remains NOT STARTED.

### Protected standard save-folder integration — ACTIVE, 2026-10-12

MelonDualDS's standard Android/data save folder now has a root-backed source
channel connected to the existing capture, rollback and atomic restore journals.
One joined child per operation streams bounded binary chunks; private journals
remain app-owned. The mapping view can inspect the standard folder without the
Android folder picker, while retaining custom-folder selection. Focused host
path/capture/restore and settings checks pass, scoped Dart analysis is clean, and
whitespace checks pass. Gated request 688
(`22bb09c9d425404389d2835a8ef23f8f`), original supervisor session 52646,
completed with exit 0: affected native storage/watch unit tests executed and
passed, followed by owner/instrumentation assembly. The shared mutex was
acquired and held through confirmed completion. Observed workers=2,
parallel=false and Gradle heap=3 GiB; reviewed Kotlin in-process shares that
heap. One 512-MiB fail-fast test fork was configured. App native compile/link
pools remain depth one per ABI; plugin environment budget two is not proof of
a universal native cap. No memory failure or budget increase occurred.
Signer-preserving installation independently matches owner SHA-256
`1a902a90323261bca94ad3888be2da94e96c42ac8ed87b429d7d1b8feeacc589`
and instrumentation SHA-256
`63610a9b31a0bba39def89ce4f7fc21b411392198922af131a1e3a4feab4fb48`.
The real app-UID/root protected-folder probe passed 131,073-byte multi-chunk
capture, exact binding/digest checks, changed-local rejection, service recreation,
lost publication acknowledgement and retained-byte rollback. The shared Melon,
missing-save, paired mGBA SRAM/RTC and native exact-file-watch regressions also
passed against this installed build. RetroArch reported CONTENTLESS before its
fixture checks. All exclusive fixtures were removed; fresh schema/configuration,
saved jobs and all ten private preference digests match the pre-install baseline.
Both actual and committed display states are OFF. These are synthetic native
save-byte checks, not a new Drive round trip or gameplay proof.
Automatic configured-path/name discovery, protected watching, the normal
watch-to-Drive proof and remaining installed-emulator coverage/handover still
belong to ACTIVE S10. S11 remains NOT STARTED; no release or legacy handover.

### S10 root-assisted coverage — authorized, 2026-10-12

S10 remains ACTIVE; S11 NOT STARTED. Specification revision 24 incorporates the
owner's authorization to use root for emulator save discovery, tracking, access
and restoration without a blanket manual-mapping requirement. Root-assisted
atomic no-overwrite publication on the Thor's backing F2FS filesystem passed a
bounded installed-JNI probe; the equivalent shared FUSE operation is unsupported.
The verified R-Shop debug UID had a stored Magisk DENY policy. Only that policy
was changed to ALLOW under the owner's root authorization, retaining logging and
notifications; its application-UID root check now passes. Restore-only absence
receipts and root-backed no-replace publication are implemented and connected to
explicit single/paired restore. Focused host behavior and scoped analysis pass,
including absence retries and no fake rollback/status. Gated request 673
(`bd1d814ff35e4267b15fabd6ede3778d`) passed focused native storage tests and owner/
instrumentation assembly: gate acquired through completion, workers=2,
parallel=false, observed Gradle heap=3 GiB, reviewed Kotlin in-process and one
configured 512-MiB fail-fast test fork. No memory failure or increase occurred.
Preserving installation independently matches owner SHA-256
`2cde946d860caddbd83af8ae37b9a0e9232f8b9b7de98edade0385e5c9327d9c`.
The actual app-UID/root proof passed missing-save publication, competing-local
preservation, service recreation and lost-ack recovery; all exclusive fixtures
were cleaned. Configuration/jobs/private preferences are unchanged; both screens
are OFF. This is native synthetic save-byte evidence, not a Drive round trip.
None of this closes
SAVE-01 or waives its remaining acceptance, including on-demand cloud discovery,
real launch/watch-to-cloud behavior and broader emulator coverage/handover.

Automatic pre-launch missing-save discovery now passes focused host integration:
reinstall-style job receipt loss, absent local/cloud first launch, durable failed
download resume, divergent cloud choices and changed-head rejection. No empty
backup/upload allocation or premature last-good receipt is created. Missing-copy
UI hides the nonexistent device-copy choice and exposes pending restore without
requiring a prior last-good receipt. Scoped analysis/whitespace checks pass.
Gated request 677 (`0107f36fa2284079933e136405ba851e`) completed with exit 0,
the shared mutex held through verified completion, observed workers=2,
parallel=false and Gradle heap=3 GiB; Kotlin used the reviewed in-process mode.
One 512-MiB fail-fast test fork was configured (assembly did not execute JVM tests).
App native compile/link pools remain depth one per ABI; plugin environment budget
is two, not a claimed host-wide native cap. No memory failure or increase occurred.
The preserving installed owner independently matches SHA-256
`b8485a71a78b163a5b2ff669a0a232fe760d9f00d4f54a79835ddcce5da55f10`.
Both actual app-UID proofs pass: missing-save/absence-receipt retirement and paired
SRAM/RTC root absence publication with interrupted-prefix recovery. RetroArch
reported CONTENTLESS, exclusive fixtures were removed, and the fresh before/after
configuration, saved jobs and private-preference baseline matches. Both screens
are OFF. Automatic PSP pre-launch host integration also verifies restore-before-
watch registration and first launch without a fabricated save or cloud upload.

A focused regression then exposed premature last-good promotion on explicit cloud
conflict choice: a failed download incorrectly recorded the selected cloud version
before local publication. The corrected durable restore intent retains the old
receipt and exact preserved local capture until publication; focused red/green
reproduction passes, including reload/resume without another preservation upload.
The affected job, capture and coverage integration checks and scoped analysis now
pass. A failed database transaction retains both cloud branches and the prior
receipt without pretending the rejected choice committed; fresh review can resume.
Coverage text no longer misclassifies protected Melon storage as inaccessible.
Gated request 682 (`d86156fe863f4525abe8b20b53ffd13f`) subsequently completed
with exit 0: the affected native storage/watch tests executed and passed, followed
by owner assembly. The shared mutex was acquired and retained through confirmed
completion. Observed workers=2, parallel=false, Gradle heap=3 GiB, reviewed Kotlin
in-process, one 512-MiB fail-fast test fork; no memory failure or increase.
App native compile/link pools remain depth one per ABI; the plugin environment
budget is two, not a verified universal native concurrency cap. The preserving
installed APK independently matches SHA-256
`9d72df6123cc23998b1bd18ec8512f572c0ed7e46c67cf2ff806a642601111ba` and the
existing signer. Fresh before/after schema, source configuration, saved metadata
jobs and all ten private preference digests match. This installs the later Dart
ordering/copy correction; it does not claim a new live conflict or watch-to-Drive
round trip. Original supervisor session 61472 is terminal, not still queued.
S10 remains ACTIVE, S11 NOT STARTED; no release or legacy-sync handover performed.

### S10 MelonDualDS shared-save route — verification in progress, 2026-10-11

S10 remains ACTIVE and S11 NOT STARTED. The DS game's normal save action now
supports an explicitly selected MelonDualDS shared `.sav`/`.srm` file, with
account/edition/artifact/directory binding, stopped-writer capture and restore,
the existing Drive generation/conflict transport and retained rollback. No
emulator configuration or real save has been changed. The protected default
Android/data folder is not bypassed and unattended in-place capture is not enabled.

Focused host capture/job/reopen/retry checks passed; the shared standalone mapping
view passes selection and edition-confirmation checks for both runtimes. Scoped
Dart analysis and whitespace checks pass. Shared-gate request 650,
`366abc162b274a19abda4ad4f9577ea8`, completed with exit 1 before compilation:
PowerShell split the unquoted target property and Gradle rejected task `.dart`.
Gate acquisition/completion, two workers, no parallel projects, 3-GiB Gradle
and one 512-MiB fail-fast test-fork configuration were verified. No memory
failure occurred. Corrected quoted request 653
(`6d513c67fe174c26aac191fb8b36bb14`) completed exit 0 with the gate acquired
through verified completion: two workers, no parallel projects, 3-GiB Gradle,
Kotlin in-process and one executed 512-MiB fail-fast test fork. Native app
compile/link pools remain depth one per ABI. No memory failure or budget increase.
Signer-preserving installation passed; the independently read installed owner
APK SHA-256 is `b3c379bdc8124e69361d86a55f742191cbc476d544baef149a6ccd66762ae509`.
The actual Thor app-UID proof passes exact shared-file capture/digest, format and
directory replay rejection, changed-local rejection, restore after service
recreation and retained-byte rollback. Exclusive fixtures were removed;
configuration, schema/root, saved jobs and all private preferences are unchanged.
Both displays are OFF. This fixture proof is not actual configured-folder UI,
gameplay or a new Drive round-trip evidence.

SAVE-01's remaining work includes configured-destination verification for
this route, installed-emulator coverage, changed-group reconciliation, the requested
pre-launch generation check/save watch, wider live recovery/conflict/contention
cases and the exact-target legacy handover. These are ordinary unfinished S10
requirements, not waived acceptance criteria or deferrals to S11. Details are in
S10_SAVE_BACKUP_DESIGN.md. The overall objective remains ACTIVE and incomplete.

### S10 exact save-file watchdog — native event delivery verified, 2026-10-11

An exact-file Android observer is now connected to enabled PPSSPP state mappings.
Publication/removal events persist a request in the existing serial backup lane;
temporary/unrelated files are excluded and file events do not bypass coherent
capture checks. Focused host checks pass explicit opt-in/opt-out, configuration
changes, unknown mappings and durable second-event admission during an upload.
Scoped Dart analysis and whitespace checks pass. The observer's lifetime is the
application process; startup/return and existing six-hour Android checks recover
missed events. No permanent service, quiet-period guess or general folder sync.
Gated request 658 (`55f9d11110eb4f1cacb26d64f79a03a4`) completed exit 0, with
the gate acquired through verified completion: observed workers=2, parallel=false,
Gradle=3 GiB; Kotlin in-process; one executed 512-MiB fail-fast test fork. App
native compile/link pools remain depth one per ABI. No memory failure or budget
increase occurred. Focused native watcher/storage checks passed. Signer-preserving
owner/test updates succeeded; independently read installed owner APK SHA-256 is
`28df69b6d5890e5f74b1d2afdab5acb831fcd0ddb2e1bee7854bdf715991767c`.
The actual app-UID Android event proof passed exact mapped rename delivery on
the main thread and temporary/unrelated-file exclusion. Exclusive fixtures were
removed; configuration, schema/root, saved jobs and all private preference digests
are unchanged. Both actual/committed display states remain OFF. This is native
event proof plus host durable admission, not a watch-to-cloud round trip.
The normal owned-game launch path now waits for reconciliation of an explicitly
enabled, exact artifact/edition mapping and that mapping's native watch receipt
before companion or emulator handoff. Host verification passes proven transitive
cloud advancement, divergent-byte conflict preservation, missing-ancestry
rejection, failed-download last-good preservation and resumable restore IDs.
The automatic restore reuses the exact pre-review rollback capture; it does not
recapture a potentially changed local save after cloud IO. Last-good ancestry
advances only after acknowledged native publication. Unknown/disabled games do
not implicitly enable backups or wait behind another game's cloud transfer.

A focused regression reproduced an unrelated malformed mapping blocking a valid
game with `watch_unavailable`. Watch registration now returns exact registered
keys, isolates missing/revoked folders and requires the current game's receipt,
while retaining visible errors for other mappings. Host tests pass both isolated
failure and refusal to launch without the current game's watch. The affected
job, launch, capture, coverage and settings workload passes; scoped Dart analysis
and whitespace checks pass. Android verification request 664
(`3f0a996487f34bc3a7bee1a8ac2a7a86`) completed exit 0 with actual gate acquisition
and release verified. Observed workers=2, parallel=false, Gradle=3 GiB; reviewed
Kotlin in-process and one executed 512-MiB fail-fast test fork, native app pools
depth one per ABI. No memory failure or increase. Signer-preserving owner/test
updates succeeded; independent installed owner APK SHA-256 is
`ed2acbea26a3864f713875e6d68e3d04d74d667fdae87cd188e6950a96230eb9`.
Actual app-UID native proof passes missing-folder isolation, exact registered-key
receipt, mapped rename delivery, unrelated-file exclusion and exclusive fixture
cleanup. Configuration/schema/root, saved jobs and every private preference
digest match the pre-update baseline. Both displays' actual/committed states
are OFF. This proves native observer isolation, not a real watch-to-cloud round trip.

The next regression reproduced stale automatic restore after a cloud head
advanced during download. The automatic pre-launch path now reviews cloud heads
again immediately before native publication. A changed head preserves the sealed
restore/rollback, leaves last-good ancestry unchanged and refuses launch.
Automatic retries retain that same intent; explicitly confirmed manual resume
can publish the previously selected copy without altering other cloud versions.
The confirmation warns that this copy may no longer be newest. Focused current
restore/launch/settings checks and scoped analysis pass. Integrated assembly
request 667 (`4d7be660bd56471696c3c18b20a92685`) completed exit 0 with actual
gate acquisition and verified completion. Observed workers=2, parallel=false,
Gradle=3 GiB; reviewed Kotlin in-process; tests configured for one 512-MiB
fail-fast fork (not executed by assembly). Native code was unchanged from 664;
no new native-concurrency claim. No memory failure or budget increase. The owner
signer matches, preserving update succeeded, and independent installed APK SHA-256
is `718939850caf4705c786c1b9ad846d70bee7ecbc82fbdaf143d34c9118198520`.
Configuration/schema/root, saved jobs and all private preference hashes are
unchanged. Both actual/committed displays are OFF. This does not establish the
still-unverified real launch/watch-to-cloud workflow.

Remaining ordinary S10 work includes absent-local destination restore,
the real launch/watch-to-cloud round trip,
broader accessible-emulator coverage and verified legacy handover. S10 remains
ACTIVE; none of these requirements is waived or moved to S11.

### S10 related-save publication — native proof verified, 2026-10-11

S10 remains ACTIVE, the only ACTIVE stage. The mGBA SRAM/RTC host implementation
now passes the native Thor proof. The earlier proof exposed a post-rename
mtime-only change during the final read despite correct desired bytes and
published child receipts. The corrected coordinator anchors committed files to
the receipt's device/inode/size and exact digest, retains full stable-stat checks
before replacement, and reconciles the named entry and parent. Failed forced-stat
experimentation was removed; no delay/retry or new native API remains.

Request 647 (`288f83112f894769a30c8c3ea3981ac1`) completed exit 0 with the shared
gate acquired and completion verified: workers=2, parallel=false, Gradle=3 GiB,
Kotlin in-process. Test tasks were configured for one 512-MiB fail-fast fork;
assembly did not execute them. App native compile/link pool depth is one. No
memory failure or budget increase. The signer-preserving owner/test installation
passed; the independently read installed owner APK digest matches
`8bc3b64aacb45466743ef1f7e2384b5bb98799beee6ea7f6db2ea1fc3db50f70`.

Actual app-UID SRAM/RTC capture/digests, whole-group seal, scalar bypass rejection,
changed-byte and same-byte replacement-inode rejection, interrupted-prefix resume
after service recreation, expected-location restore and retained-byte rollback
pass. Exclusive native fixtures were removed; configuration, schema/root, saved
jobs and all private preference digests are unchanged. Both displays are OFF.
No gameplay or new live Drive round trip is claimed.

Focused host checks pass both-file current-installation naming, retained-local
rollback without redownload, and explicit cloud choice preserving the local
branch. Coverage and status now describe paired clock support and specific pending
restore/changed-membership conditions. Scoped Dart analysis and whitespace review
pass. Integrated copy assembly and focused SaveCaptureStorageTest passed in
shared-gate request 648 (`ab8f281de7204d56ae8ad1373155565c`), with the same verified
worker/heap profile and one executed 512-MiB test fork, no memory failure. Its
signer-preserving installation independently matches installed APK digest
`e7482967b6494024498edb4630ce2fd2a0720a747bd5cf917c52f3014b4861f1`;
configuration, schema/root, saved jobs and every private preference remain
unchanged. Both displays remain OFF. Changed membership reconciliation, other accessible
installed routes, broader live conflict/recovery/contention checks and verified
legacy handover remain ordinary unfinished S10 work. S11 is NOT STARTED.
See S10_SAVE_BACKUP_DESIGN.md.

### S10 cartridge-save checkpoint — 2026-10-11

S10 remains the sole ACTIVE stage. The existing Genesis Plus GX save workflow now
includes Master System and Mega Drive, with separate console-bound journals and
exact owned-launch review. Focused capture, durable backup/reopen/restore/rollback,
launcher and coverage/settings checks pass. Native Thor proof confirms both
expected-location writes, retained-byte rollback and cross-console journal replay
rejection; exclusive fixtures were removed. This is not a new live Drive round
trip or gameplay/save-load claim. Details: S10_SAVE_BACKUP_DESIGN.md.

Gated assembly 638 completed exit 0; gate acquisition and completion were verified.
Observed profile: two workers, no parallelism, 3-GiB Gradle heap, Kotlin in-process;
one 512-MiB test fork configured (assembly did not execute tests). The app's ARM64
compile/link pool remains depth one. No memory failure or budget increase occurred.
Signer-preserving installation passed with independently matching installed APK
digest. Configuration, schema/root, saved jobs and private preferences are unchanged.
Both displays' actual/committed states are OFF.

Remaining S10 acceptance: related-file groups, remaining accessible installed
emulator routes, live conflict/recovery and manual/background contention cases,
then verified exact-target legacy handover. These are ordinary unfinished S10
work, not external blockers or S11 deferrals. S11 is NOT STARTED. S0-S9 remain
COMPLETE; exhaustive scraping is not required and the optional job stays paused.

### S7 COMPLETE; S10 ACTIVE — 2026-10-11

S7 is reconciled against revision 23 in S7_ACCEPTANCE_RECONCILIATION.md. Its
owner-directed cleanup, retained-set/space/protected-content checks and normal
post-cleanup restore pass. Fresh scoped provider evidence already exists;
exhaustive scraping is not required. The optional original job 76 remains paused
at 27,168 requests, with its saved capture/outcomes preserved.

The requested playback controls now pass both host checks and normal Thor
rendering/touch Resume/Pause. In Running, Pause is enabled and fresh/resume/retry
are disabled; after normal joined Pause those guards reverse appropriately.
Accessible action names are present. Controller activation is verified by the
focused widget check; native D-pad input is not claimed as separate activation
proof. The local-absence regression passes on the host, preserving full cloud
checks for present archives; the installed native storage bridge is unchanged.
This does not claim diagnosis of the earlier unrecorded Drive HTTP response.

Online assembly 634 completed exit 0 after DNS recovery, without editing shared
SDK dependencies or pinning a version merely to accommodate the offline cache.
The shared gate was acquired. Observed profile: two workers, no parallelism,
3-GiB Gradle heap; Kotlin in-process. Test tasks were configured for one 512-MiB
fork, fail-fast on, failures not ignored, but assembly did not execute tests.
The app's inspected ARM64 Ninja compile/link pool has depth one. No memory
failure or heap increase occurred; this is not a total-host memory guarantee.
Build log: `0296514162904cd2b750258382441bbe.log` under the local shared-gate logs.

Signer-preserving `adb install -r` succeeded. Installed APK SHA-256 independently
matches `ed677dc5b0a6aa4a0910fb7c21d52710c97ff631fba123f374d1273ddb5119ef`.
Immediate configuration, schema/root generation, saved-job objects and every
private preference digest agree across the update. Scoped shared-file comparison
also agrees: 159 files / 310,188,490 bytes, stable membership, no unverified scope.
This remains explicit shared-path evidence, not a claim covering all private saves.
Private visual evidence is retained outside Git; its digest-checked device-side
screenshot was removed and absence verified. Both displays' actual and committed
states are OFF. Final scoped Dart analysis and whitespace checks pass.

No S7 blocker or required deferral remains. S0-S9 are COMPLETE; S10 is now the
sole ACTIVE stage after resolution of its S7 sequencing hold; S11 NOT STARTED.
The overall eleven-stage objective is not complete. Older checkpoints below
are historical and must not restore superseded full-scrape gates or stage states.

### Owner correction: exhaustive scraping is not required — 2026-10-11

Specification revision 23 corrects the agent-created requirement to finish every
ROM's metadata lookup. The owner explicitly rejects that scope. Job 76's 15,928
pending lookups, exhaustive Wii/DSi passes and further aggregate-score gathering
are not S7 blockers, required deferrals or final-delivery gates. Preserve the
optional saved job and truthful missing-score states; do not resume it merely to
close S7. Fresh metadata capabilities and representative live checks remain.

The owner-directed SD cleanup and retained-set/space/post-cleanup restore proof
are verified. The subsequent closure above also verifies the requested controls
and integrates the local-absence correction; neither requires another full scrape.

Build checkpoint correction: assembly 630 has confirmed exit 1. Its offline
failure is missing cached version-list metadata for dynamic AndroidX runner
`1.2+`, not memory exhaustion. The gate was acquired with two workers,
no parallelism, a 3-GiB Gradle heap and Kotlin in-process. No updated APK from
625/630 has been installed. Older pending-build/full-scrape notes below are
historical and do not supersede this current checkpoint.

### Compact scraping playback controls — 2026-10-11

Update after request 625: the gate was acquired and the actual profile verified
two workers, no parallelism and a 3-GiB Gradle heap. Kotlin is in-process; test
configuration is one 512-MiB fork, not an executed test workload. Assembly failed
resolving AndroidX runner dynamic-version metadata because host DNS failed for
Google/Maven/Flutter repositories. No memory failure or heap increase occurred.
The completed failed session has been joined; the next focused assembly uses
the existing dependency cache with `--offline`, not reduced verification.

The separate disposable-copy regression is now corrected and integrated after
625 exited: mapped cached lineage supplies only local lookup hints; a read-only
native existence check precedes any cloud revalidation. Absent root/nested files
return to title discovery without Drive calls. Present files retain full current
cloud validation before/after raw hash observation, container identity checks,
root-copy priority and cancellation/persistence joining. Focused runtime/boundary
checks pass, including changed-cloud rejection, unsafe hints, inaccessible root,
nested absence, platform separation and no installation/stage/ROM-body requests.
Three obsolete native-call expectations were corrected and rerun successfully;
scoped analysis passes. Integrated host/native verification follows below when
available. This corrects the ordering dependency, not an unrecorded API response.

S7 remains the sole ACTIVE stage. Specification revision 22 assigns this bounded
UI-02 refinement to S7: the existing fresh-search, pause, resume and retry actions
use compact playback icons with their existing localized tooltips and accessible
names. The action callbacks and idle/running guards are unchanged. Saved jobs
and match review retain their text buttons.

Focused widget verification passes for the icon/tooltip/semantics contract,
48–64 logical-pixel touch targets, controller activation of the saved resume
action, idle/running guards, compact layouts, progress feedback and the three
metadata-detail screen sizes. Scoped analysis and whitespace checks pass. Only
the affected progress golden changed; no full suite was run. Native update and
visual verification are pending the already queued gated assembly request 625.
No completion or native gate/profile evidence is claimed before it returns.

The saved original ScreenScraper job 76 remains blocked on provider
`unavailable`, at 27,162 requests with 15,934 pending. One read-only account
probe and the exact next pending lookup both returned valid HTTP 200 responses;
normal Resume then advanced three requests before blocking again. The historical
failure's exact transport response is not recorded, so this is not a demonstrated
root cause or a repaired provider failure. No arbitrary retry or provider behavior
change was added. Configuration digest and root generation 2 are unchanged.
The short-lived fixed read-only diagnostic helper was removed from host/device
after use; its reviewed cleanup removed only its attributed generated files.
The original full metadata pass and the rest of S7 remain unfinished.

Subsequent normal Resume advances the same job to 27,168 requests / 15,928
pending, then pauses with an operation error, not a provider-blocked status.
Confirmed live app PID 11204 emits only the existing sanitized failure type
`DriveApiException` and application frames: `drive_api.dart:508`,
`drive_api.dart:190`, `drive_download_boundary.dart:89`, and
`drive_runtime.dart:778`. The exact Drive issue/HTTP response is not recorded;
do not call that transport failure repaired. Inspection traces this path to
`readMetadataArchive` revalidating cloud file/ancestors before observing whether
the local archive exists. After the authorized SD cleanup, absent local files
therefore still require unnecessary cloud API calls before title discovery.
The bounded next remediation is to verify local absence using observed mapped
lineage before network revalidation, while retaining every current-cloud and
byte-identity check when a local identifier actually exists. Existing nested,
changed-cloud and cancellation regressions in `drive_runtime_test.dart` define
the safety boundary. No production change has been made during queued assembly
625, so its source snapshot remains stable. Both screens were returned to sleep.

The focused regression `absent metadata archive needs no Drive requests for
title discovery` now reproduces this ordering defect: it returns no identifier
but fails its no-network assertion with two actual Drive metadata requests.
That isolated test process exited 1 and is no longer running. The production
correction remains pending assembly 625's confirmed completion; no concurrent
test process or second R-Shop build has been launched.

Later checkpoint: 625 exited unsuccessfully on the DNS failure described above.
The integrated runtime/boundary files now pass together in the maintained tree,
and scoped analysis/whitespace checks pass. Focused assembly request 630 is the
single replacement request, using cached dependencies offline with the same
gated profile. Native UI verification remains pending its confirmed completion.
The disposable validation clone was then removed by reviewed cleanup transaction
`e7aa6f84365a2cf196632ff42ccc079e`: 247,647,259 attributable bytes, no exclusions
or residual clone. Generated plugin link leaves were removed without touching
their Pub-cache targets. Both Thor displays remain OFF while the request waits.

### Plain-language UI review and post-cleanup recovery — 2026-10-11

S7 remains the only ACTIVE stage. Specification revision 21 assigns the owner's
plain-language request to UI-02 without activating S10/S11. The English
file-comparison, metadata, save-backup and companion windows now describe actions,
results and next steps in familiar terms. File hashes and error codes remain
available in collapsed Technical details. Comparison/adoption, cancellation,
ownership, backup/restore/conflict and account/storage behavior are unchanged.
Other existing translations and all localization keys/placeholders are preserved;
this is not a claim that every language has received the same editorial review.

Focused widget verification covers explicit comparison and adding an existing
download, saved versus current comparison results, mismatch/unavailable/cancelled
messages, controller cancellation, companion choice persistence/failure, save
setup/account switching, metadata navigation, quota reporting and match review.
Tests that still opened the superseded metadata layout now use its real workspace
entry. The compact match-review reproduction exposed the console scope dropdown
overflowing by 23 pixels; constraining the dropdown and its labels fixes that
specific layout defect. Fresh 480-, 720- and 1280-wide checks pass, as do the
updated metadata layout goldens and scoped analysis. No full suite was run.

The post-cleanup normal Drive download of one removed small Game Boy title
completed, and normal Open reached its RetroArch title screen. Its size and MD5
were checked independently. After closing only the test-launched emulator, the
test download was removed through R-Shop's ordinary confirmation. The accidental
favorite toggle was reversed. Fresh read-only reconciliation again matches all
247 retained tree files, the exact 40-ROM keep-list and every reviewed keep-file
stat. Free space remains 957,752,320 KiB. Saves, BIOS and metadata are preserved;
the extra full-cloud comparison attempt is not claimed as new completed evidence.
Both physical display states are verified OFF after this device check.

Native assembly ticket 617 acquired the shared gate but failed because Windows
split an unquoted `-Ptarget=lib/main.dart` argument (`Task '.dart' not found`).
After confirmed completion, corrected ticket 619 acquired the same gate and
finished successfully. Its observed profile is two workers, no parallelism and
a 3-GiB Gradle heap; Kotlin remains in-process. Test tasks were configured for
one 512-MiB fork but were not executed by assembly. No memory failure or heap
increase occurred. Existing app native compile/link pools remain depth one.
Plugin/native task-specific limits are not inferred from worker settings alone.
The signer-preserving debug update was installed without uninstall or data reset;
its installed APK digest matches
`a84edfa239a66b4c8d698ad9737315e29d2be829a08f13a46888930c3f8cac13`.
Configuration, catalogue generation and all private-preference digests match at
the update boundary. The before/after protected shared-file comparison is equal:
159 files / 310,188,490 bytes, stable membership, no unverified shared scope.
This is scoped preservation evidence, not proof of every private/custom save path.
Normal Thor navigation verifies the new metadata and save-setup labels, the
comparison popup's readable main text and expandable Technical details, and the
companion picker explanation/None choice. The dialogs were closed without
comparison, adoption, download or companion-setting changes. Both physical
display actual/committed states are OFF. Private screenshots are retained;
the expendable device-side screenshots were removed.
The full original metadata pass and other S7 acceptance remain required;
this verified copy review and restore proof do not close S7 or the overall plan.
The read-only checkpoint now shows original ScreenScraper job 76 at 27,134
lookups, 1,126 rated and 15,962 pending, stopped with provider `unavailable`.
This is progress from the resumed checkpoint, not a finished scrape. Published
root generation 2 and the full configuration digest remain unchanged. No
replacement capture or credentials edit was made.

### Current live resumption — 2026-10-11

S7 is ACTIVE. Fresh explicit-device ADB inspection finds `bfa98654` online;
the disconnected-device blocker below is resolved by current evidence. S10
remains BLOCKED on the user-directed sequencing hold and S11 NOT STARTED.
The revision-19 cloud-only policy also applies to the private read-only audit:
an exact unrated member or an unrelated unbound artifact must not restore the
superseded ranking veto. Dirty projection, ambiguous bindings and failed byte
comparisons still preserve the member. Audit output never grants removal.
Current inventory, owner-directed exact-file execution, no-refill activation and
retained-set/space reconciliation are now verified. Remaining independent S7
metadata/recovery acceptance is not reported as complete by this cleanup.

The audit regression failed first on the old unrated/global-unbound veto; the
focused `python -B -m unittest test_thor_migration_audit -q` now passes. The audit
retains its dirty-projection/identity/digest guards and every live-removal gate;
no executor or deletion permission was added. A normal native Resume continues
immutable ScreenScraper job 76 from 26,707 to 26,715 lookups without credential
entry, a replacement capture or checkpoint edits. The prior provider-unavailable
state is therefore not treated as a current external blocker. Root generation 2
remains published (pending=null); schema remains 38. Normal N64 Best-25 discovery
refreshes the projection from thousands of dirty rows to seven edition rows and
zero artifact rows in the subsequent observation. These are live observations,
not atomic removal authority or completed metadata coverage.

The whole-ROM-tree inventory completed and reconciled: 15,965 stable files,
722,867,145,438 bytes. The intentional private evidence is
`D:/RShopPrivate/Migration/s7-inventory-20261011.jsonl`. Gated assembly 607 acquired
the shared gate, verified two workers/no parallelism and the 3-GiB Gradle heap,
and completed successfully without memory-failure evidence. Kotlin was configured
in-process; assembly did not execute tests. The retained-signature debug APK was
installed as an update; installed SHA-256 matches
`75605b2a9aeba53042b6fdc62216210cbaae4ab0b43b0394a40c26ce7776c4a0`.
The pre/post shared protected-data baseline matches (159 files, 310,188,490 bytes),
as do configuration and private-preference digests at the update boundary.

The owner's subsequent explicit deletion directive is recorded in specification
revision 20. The completed one-time cleanup removed 15,718 exact ROM/game-companion
paths totaling 704,092,184,748 bytes. All removal journals reconcile against the
original 15,965-file inventory, with no duplicate removal or keep-list overlap.
A fresh device `find` matches the expected 247 remaining files exactly; all 40
remaining game files are current, present Top-25 members: N64 25, PSP 13, PS2 2.
Each retained file's full reviewed stat is unchanged. Consoles with no eligible
ranked members retain no invented sample; this includes PS1. No missing sample
members were downloaded or ratings fabricated. The other 207 files include
metadata, SNES coprocessor firmware and a preserved `.srm` save.

Actual SD free space changed from 265,588,224 to 957,752,320 KiB (about 913.4 GiB
now free; filesystem allocation savings differ from logical removed bytes).
The shared protected-data comparison is equal: 159 saves/BIOS/configuration
files, 310,188,490 bytes, stable scope membership and no unverified shared scope.
Those protected scopes were outside the removal set. This is preservation
evidence, not a new claim about private/custom save paths or cloud backups.

The private native helper stopped safely on two Android SD/FUSE identity
behaviors: close-after-unlink returned EIO, and opening/closing a raw `.gb` file
changed its exposed inode. Its journals identified every completed operation
and the one quarantined file. Resumption reconciled that exact file and used
immediate canonical regular-file stat validation followed by direct exact-path
unlink, without opening or renaming. The final journal has a verified COMPLETE
footer (14,865 files); all preceding journals reconcile into the total above.
No directory wipe or hidden quarantine remains.

Private operational evidence, manifests, helper sources and per-file journals
are retained in `D:/RShopPrivate/Migration`. Independent read-only reconciliation:
`top25-cleanup-verified-20261011.json`, produced by
`verify-top25-cleanup-20261011.py`. LoLSuite's live device-only
`on_demand_folders` guard was parsed and verified to reject every affected console
(27 distinct folders), preventing refill. Archive profiles, FolderSync, scheduled
save-sync tasks and Drive originals are unchanged. Both physical displays are
verified OFF. The owner-requested SD cleanup is finished; this does not falsely
close unrelated S7 acceptance, S10 or S11. S7 remains the sole ACTIVE stage.

### Current S7 policy authorization — 2026-10-11

S7 is BLOCKED on the disconnected Thor after completing and verifying the offline
portion of the owner's explicit cloud-only authorization, including unrated games.
No implementation stage is ACTIVE. SPECIFICATION.md revision 19 supersedes the
missing-rating preservation rule; that policy question is resolved. Exact-member
retention planning and accurate unrated review labels are implemented and verified.
Top-25 score validity, canonical membership/bundles/pins and exact current cloud
recovery remain required. S10 stays BLOCKED on the execution hold; S11 is NOT
STARTED. No other implementation stage is opened.

The Thor is disconnected according to the owner. This externally prevents
MIGRATE-01's current SD inventory, immediate byte/identity revalidation, journaled
removals and final retained-set/free-space/restore verification. Reconnection
resolves that availability blocker, not the still-unfinished migration work.
No live backup proof or SD deletion is claimed. Older execution/maintenance
states below are historical and superseded by this entry.

Offline verification: the changed regression first failed on the old `preserve`
disposition. The final serial command
`flutter test --no-pub --concurrency=1 test/library_query_test.dart test/widgets/drive_recovery_review_dialog_test.dart test/migration_byte_observation_test.dart --reporter expanded`
passed on 2026-10-11 (55 checks). It proves valid Top-25/canonical-member retention,
unrated/outside-sample planning without invented scores, exclusion of ambiguous
bindings, independence from another unbound artifact, read-only UI planning,
explicit UI initiation of byte/adoption operations, cancellation drain and durable byte-observation
validation. The existing migration test's stale schema-37 assertion was corrected
to the current production schema captured before its v35-upgrade exercise;
production schema 38 and its migration logic were not changed.

Tests used one workload at a time and a task-specific D:/Temp directory, removed
afterward through transactional cleanup `9ad1e328a1f1559b4d57524a52a86da6` (only
that empty generated directory remained). No Gradle build, gate acquisition,
APK install, Drive mutation or device operation occurred in this policy change.
Fresh metadata completion, reviewed private migration membership, current
per-file recovery proof, no-refill activation, journaled execution and final
space/retained-set/restore/save verification remain required S7 work, not tracked
deferrals. S7 and overall implementation are not COMPLETE.

### Current maintenance override — closed 2026-10-11

TM1 in TOOLCHAIN_UPGRADE.md is COMPLETE: installed Gradle 9.1.0, AGP 8.13.2
and Kotlin 2.3.21 passed gated Android JVM tests and debug APK assembly. Actual
runtime resource markers, fresh reports, APK identity/signature and bounded
cleanup were inspected; the evidence is recorded with the verified commit.
No implementation stage is ACTIVE under this maintenance request. S7 and S10
remain BLOCKED on the scoped user-directed execution hold, not a new product
defect. Their outstanding criteria and prior evidence remain unchanged; no
migration, metadata-policy waiver, hibernation, device installation or release
was performed. The dated product-stage states below are historical; this
maintenance result does not close S7, S10 or the overall fork.

### Current execution override — 2026-10-10, console-isolated S7 cleanup

The user explicitly resumed S7 and requested laptop hibernation after a safe
finish. S7 is now the sole ACTIVE stage. S10 is BLOCKED on the user-directed
execution hold while S7 is prioritized: remaining SAVE-01 work and verification
cannot proceed during this scoped request; resume it after S7/hibernation is
released. This is an external sequencing hold, not a claim of a product defect.
S0-S6/S8-S9 remain COMPLETE; S11 remains NOT STARTED.

Specification revision 17 records the authorized Top-25 cap and console isolation.
Game Gear reception is no longer a whole-stage/whole-SD blocker. Unrated games
remain preserved pending an explicit change to that policy. Actual native
inspection still finds incomplete ranking coverage outside Game Gear. The normal
ScreenScraper controls resumed immutable job 76 from its existing checkpoint;
the fresh 02:42 +02:00 observation shows Running, 23,502 lookups and 19,784 pending.
The provider reports 19,840/20,000 daily attempts remaining. No job membership,
terminal outcome, score or provider quota was rewritten. Therefore the full
fresh pass and reviewed migration are unfinished,
not already satisfied by the policy clarification. Historical blocked-state
notes below are superseded by this current override, not rewritten as success.

Current S7 acceptance reconciliation:

- Existing format round-trip evidence remains recorded in
  S7_ACCEPTANCE_RECONCILIATION.md; it is not fresh per-file removal authority.
- The fresh collection-wide pass is running, not complete. Native retained-query
  observations find no eligible ranked PS1/GameCube/Wii groups and only partial
  PS2/PSP coverage. These gaps are not exclusive to Game Gear.
- No reviewed execution manifest, current per-file cloud/local revalidation,
  journaled removal or live no-refill activation was performed in this resumption.
  Their integration/execution and final retained-set/space/restore checks remain
  ordinary required S7 work, not a tracked deferral to S10/S11.
- The private protected-data observation completed, but ten entries changed stat
  metadata while being read. It is not passing preservation evidence, and no
  content-loss claim follows from those stat changes. No ROMs or saves were removed.
- No Gradle build was launched. Read-only gate status found an idle reusable
  daemon and no pending ticket; the mutex was not acquired and no effective new
  build profile is claimed.
- Hibernation support is available. Hibernation has not been requested while S7
  remains unfinished and the cleanup-policy clarification is awaiting the user.

### Current execution state — 2026-10-09, S7 retention evidence blocked

S0-S6 and S8-S9 are COMPLETE. S7 is BLOCKED. S10 is the sole ACTIVE stage;
S11 is NOT STARTED. This current state
supersedes the dated checkpoints below. Overall implementation is not complete.

The external blocker is MIGRATE-01's defensible per-console Top-25 retention
criterion, specifically Game Gear reception coverage. A fresh authenticated,
read-only IGDB count on 2026-10-09 11:41 +02:00 still returns only 19 platform-35
records with at least twenty votes, before collection/edition binding. Completed
Thor job 75 accepts only two currently bound records meeting that floor. The
existing assessed providers do not supply a defensible whole-collection set;
an application fix cannot create the missing votes or borrow parent scores.
Alternative public sources have not established a usable, assessed replacement.
Resolution requires sufficient current, edition-correct reception evidence from
a legitimately accessible assessed source, or an explicit user requirement
change. No score floor, identity rule or migration criterion is changed here.

S7 remains parked, not complete. Its full scrape, scoped/provider passes,
identity/coverage gaps, exact migration execution and save-safety work remain
required S7 work, not deferrals into S8. The already-running job 76 is left intact:
19,603 requested / 23,908 pending / 747 rated in the read-only observation. Its
continuation is not simultaneous implementation of another stage. No ROM
removal or external sync change is authorized by this checkpoint.

S8 uses the verified S1-S6 identity/storage/emulator boundaries and does not
depend technically on S7's retained set or deletions. Its own COMPANION-01
acceptance is unchanged. Final S1-S11 reconciliation still requires S7 closure;
return to the earliest blocked stage when the external evidence becomes usable.

Tracked deferrals: none added. Blocker evidence: SCORE_RECEPTION_ASSESSMENT.md
and the live count above. Every COMPANION-01 criterion is verified, including
normal paired ROM/app placement, independent choices, touch/controller controls,
restart and completed catalogue refresh, failure cases and ordinary launch.
The observed shared saves/settings remain unchanged; pre-existing inaccessible
PPSSPP coverage is not claimed. Test-only associations/captures are cleared,
unchanged job 76 normally resumed and advanced, and both physical displays are
OFF. `S8_COMPANION_DESIGN.md` records the criterion-by-criterion evidence,
build profile and scope qualifications. S8 has no blocker or tracked deferral.
S9 is reconciled COMPLETE in `S9_MEDIA_COVERAGE.md`: all supported platforms have
reviewed mappings, legacy original-media families have explicit evidence/neutral
rationales, and actual compact/large Thor presentation plus focused decode,
replacement and layout checks pass. Both screens are OFF; task captures removed.
S9 has no blocker or tracked deferral. No S10/S11 acceptance is claimed yet.

### S10 entry — emulator-aware save backup, 2026-10-09

Scheduled checkpoint, 2026-10-10: the opt-in PPSSPP mapping now dispatches through
Android's persisted six-hour/network-constrained job, using a headless backup-only
engine when the UI is absent. Actual screen-off/cold-process checks retained the
unchanged verified backup; native aggregate receipts confirm one mapping checked,
no pending work and no errors. Platform-stop injection recorded stopped rather
than success; the next pass recovered with UI/headless coexistence. Normal
opt-out removed the Android job and restored the previous disabled policy.
Protected save/emulator/source configuration digests match; both displays OFF.
Gated build 557, focused host/native checks and affected analysis pass. Detailed
profile, APK identity and test qualifications are in S10_SAVE_BACKUP_DESIGN.md.
S10 remains ACTIVE: direct manual/background contention evidence,
remaining accessible emulator routes /
custom groups and the other SAVE-01 acceptance cases remain unfinished. These
are not tracked deferrals; the legacy save-sync apps/tasks remain untouched.

Local capture-retirement checkpoint, 2026-10-10: completed/unchanged backups now
durably nominate only their exact redundant private capture, review all live
journal/conflict references and retire it through identity-checked native IO.
Cleanup failure persists its intent and blocks another capture until recovery.
Pending uploads, retained conflicts and restore/rollback copies are preserved.
Focused failure/reopen/reference regressions and native exact-boundary checks
pass. Two screen-off automatic passes on current preserving build 559 report
unchanged completion with no attention/pending work; the exact original list of
27 capture directories returns after each pass. Historical stages are untouched.
Profile, APK identity and qualified native evidence are recorded in
S10_SAVE_BACKUP_DESIGN.md. This resolves the new redundant-capture accumulation
defect, not full S10 acceptance. S10 remains the sole ACTIVE stage.

Execution paused at the user's request, 2026-10-10, after verified local capture
retirement. Original automatic opt-out was restored through the normal UI and
its Android job is absent. Last-good backup and protected save/config hashes are
unchanged; both physical screens are OFF. No tests/builds from this checkpoint
remain running. Resume with S10's direct manual/background contention, remaining
accessible emulator routes/coherent groups and recovery/handover acceptance.
This pause does not close S10, waive S7 or start S11.

Automatic return checkpoint, 2026-10-10: explicit per-edition PPSSPP slot opt-in
now persists independently of the settings screen. Actual Thor Home/return
capture and real Drive review retained the unchanged verified backup rather than
publishing another generation. Reopening preserved opt-in/outcome; opt-out without
reconfirmation restored the previous disabled policy. PSP slot/configuration
hashes are unchanged and both displays are OFF. Focused checks, scoped analysis
and gated assembly 554 pass; preserving signer/installed digest and protected
preferences were inspected. S10 remains ACTIVE: Android scheduled dispatch,
remaining accessible emulator routes/custom groups and other SAVE-01 acceptance
remain unfinished. Legacy sync remains untouched. See S10_SAVE_BACKUP_DESIGN.md.

Game Gear cartridge checkpoint, 2026-10-10: the normal game-entry workflow now
backs up reviewed Genesis Plus GX SRAM to Drive, downloads/verifies it, restores
it at the exact encoded launch save path and explicitly rolls back to different
retained local bytes. Independently inspected native `published` receipts and
destination hashes agree. The disposable shared fixture was removed afterwards;
the original core save directory is empty again. ROM, emulator configuration and
prior PSP data hashes are unchanged; no new sign-in, adoption, archive write or
legacy-sync change occurred. Focused host/native checks, analysis and gated build
548 passed; preserving installed APK digest/signature were independently checked.
The final narrow coverage label and explicit related-group rejection status have
passing host checks. Gated assembly 551 passed; its preserving, same-signer
installation and independent installed digest match the built artifact. Actual
Thor Emulators presentation shows the revised Game Gear SRAM label with other
routes/states still unfinished; the prepared backup area reopened without sign-in.
Immediate protected preference/security hashes were unchanged. See
S10_SAVE_BACKUP_DESIGN.md for receipts, profile and mock-fixture qualifications.
This is one additional verified route, not full installed-emulator coverage or
S10 closure. The remaining SAVE-01 criteria below remain required.

Coverage checkpoint, 2026-10-09: a separate offline Emulators section now reports
the known installed emulator/port/frontend versions, save versus state coverage
and advertised document-picker providers. Unreviewed routes remain unfinished,
not unsupported; newer runtimes cannot inherit verified labels. Focused checks
verify section isolation, preserved workspace state, compact/controller use and
explicit unavailable results after failed refresh. Corrected gated assembly 542
completed and its same-signer preserving installation was verified independently
by installed APK digest. Actual Thor Settings -> Save backups -> Emulators shows
installed versions and advertised providers; refresh, touch scrolling and D-pad
Up/Down+A section changes work. Preference/security hashes matched immediately
after installation; existing catalogue sync later advanced and changed its
containers. PSP slot/configuration hashes remain unchanged. The old bottom-screen
Clock test was returned to Home, the task UI dump removed and both screens are
OFF. See S10_SAVE_BACKUP_DESIGN.md for profile and evidence qualifications. This
is native coverage presentation, not stage closure or implemented support for
every listed route. Wider save-route implementation remains required S10 work.
No legacy sync app/task or save data was changed.

Current standalone restore checkpoint, 2026-10-09: normal Thor Save backups
resumed the retained Patapon state, verified/downloaded its real Drive backup and
published it at the configured PPSSPP slot. A prior network outage and then an
open-emulator precondition preserved the pending intent/local bytes. Explicit
Android App info preparation and Resume completed publication, with matching
length/digests and a native receipt identifying the new destination inode.
Explicit local rollback also completed, preserving the replaced generation.
Normal menu reopen retained the verified backup without new sign-in. PPSSPP
settings are unchanged. Focused PSP conflict-preservation and other changed-path
checks pass; scoped analysis is clean. Gated build 534 and its preserving install
are verified, with two workers, no parallelism, 3 GiB Gradle heap, assessed Kotlin
in-process and one 512 MiB test fork; no memory failure or budget increase.
`S10_SAVE_BACKUP_DESIGN.md` records exact build/file/receipt evidence. Temporary
UI XML removed; both displays are committed OFF and device is Asleep.
This supersedes the disabled-restore state in the historical checkpoint below,
not the remaining requirements: wider installed-route coverage, background/fault/
reinstall behavior, live divergent-conflict proof and conditional sync handover
remain unfinished. S10 alone is ACTIVE; no legacy tool/task was changed.

Standalone backup checkpoint, 2026-10-09 22:01 +02:00: PPSSPP v1.20.4's
normal Memory Stick picker configured a new shared PSP directory without moving
existing data. Its initially blank slot five produced a Patapon title-screen
state, without gameplay. R-Shop's normal folder picker, exact slot selection and
edition confirmation then published a real Drive backup with verified readback,
without another account/consent prompt. The native sealed capture and original
5,557,226-byte state have identical SHA256 digests. This verifies standalone
backup only: PPSSPP restore remains unimplemented/disabled, not COMPLETE.
`S10_SAVE_BACKUP_DESIGN.md` records the exact fixture and evidence. The fixture
is retained for required restore verification; existing sync tools are unchanged.
The current installed menu still shows four independent left-hand sections;
fresh focused save-settings checks pass. The temporary UI dump was removed and
both physical display devices subsequently report OFF / committedState OFF,
with device wakefulness Asleep. S10 remains the sole ACTIVE stage.

User-authorized scope revision 2026-10-09 (specification revision 15): restoration
acceptance ends at the configured emulator's expected save location and completed
file write. Gameplay, in-emulator loading and deep save-content inspection are
no longer requirements or blockers. Historical checkpoints below describe the
then-current criteria; they do not reinstate these removed checks. No required
deferral is created. Remaining S10 feature, coverage and safety work is unchanged.
The user explicitly retained local/cloud conflict handling: preserve divergent
versions and require an explicit choice rather than silently overwriting remote
saves. Conflict verification remains required before S10 can be COMPLETE.

Current save-menu checkpoint, 2026-10-09 (specification revision 16): save
management now follows persistent left-hand Backup area / Back up save /
Restore & conflicts / Status navigation, not one long scroll. Focused verification
covers narrow/enlarged text, touch-to-controller focus, section isolation and
retained mapping/confirmation/running capture. Gated build 521 is installed;
normal Thor setup and selected-game routes verify section separation and retained
selection/confirmation, without backup/restore writes. Saves and emulator settings
remain unchanged; both screens are OFF. New settings, including S11's later
controls, must retain this presentation rule. S10 remains the sole ACTIVE stage;
no other stage is started or declared complete by this UI correction.

Current conflict checkpoint, 2026-10-09: the per-game workflow now
publishes the sealed local conflict generation through the existing immutable,
readback-verified Drive transport before a selected cloud version may replace
it. Publication failure preserves the pending choice and last-good generation;
another cloud change during preservation requires a fresh explicit choice.
The next backup records the reviewed resolution in its ancestry, so the retained
losing branch is not falsely presented as a new conflict. Unreviewed branches
still require a choice. Focused job regressions pass, including older pending
record recovery. Scoped analysis and diff checks pass. Gated assembly 519 of
this correction completed and its preserving Thor installation was independently
hash/signature checked. Normal native backup completed against real Drive at
20:37 with verified readback and no sign-in prompt. The divergent-branch ordering
remains host-verified, not yet live conflict acceptance.

Build 515 completed through the shared gate and was installed preserving app
data. The installed APK digest independently matched the candidate; protected
preferences, fourteen observed mGBA saves and RetroArch configuration/remap
hashes matched immediately after installation. Normal real-Drive Aero fixture
backup and restore then completed with a native published receipt at the
expected current mGBA path. Both displays are OFF. This verifies the normal
backup/restore path, not the subsequent conflict-preservation correction or
full S10 acceptance. Standalone, installed-route coverage, background work,
independent recovery and legacy-sync handover remain unfinished. S10 remains
the sole ACTIVE stage; no required deferral or scope change is introduced.

Earlier conflict implementation checkpoint, 2026-10-09: the per-game workflow now
discovers compatible immutable cloud generations and surfaces divergent branches
for explicit local/cloud choice. Focused host checks verify preservation of old
cloud objects, concurrent publication, changed-choice rejection, confirmation/
cancel and durable recovery between cloud selection and restore intent. Scoped
Dart analysis is clean. Live conflict verification remains unfinished; gated
Android assembly request 512 is queued and supervised, not a completed build.
Local conflict captures are retained privately; independent cloud recovery of
those local captures is not claimed. No stage status or acceptance scope changes.
The subsequent installation-rename regression reproduced a false conflict for
identical SRAM bytes. After gated build 512 completed, format-specific SRAM/RTC
role comparison corrected it. Fresh focused job checks and scoped analysis pass,
including RTC divergence. Transport manifests/digests remain unchanged. A new
gated assembly of that correction is required before live testing; no in-flight
build inputs were changed. S10 remains ACTIVE with its other work unfinished.

Current narrow checkpoint (2026-10-09, request 506): the current-launch save
association defect is implemented and focused host/native verification passes.
The automatic save review shares the exact native ROM launch preflight; an
unrelated or stale installation save cannot be uploaded under the selected
edition. Explicit cloud restore separates immutable source filenames from the
current installation's destination, with durable resume/rollback target guards.
The gated preserving Thor update succeeded and independently installed APK,
signer, configuration, protected preferences and fourteen mGBA save hashes were
verified. Subsequent normal current-target cloud restore has a freshly inspected
native published receipt and successful UI result. The current-target path/write
check is verified for this narrow RetroArch SRAM route. Blank save contents do
not block the revised acceptance. Standalone and remaining installed routes,
background work, custom mappings and remaining SAVE-01 behavior are unfinished.
`S10_SAVE_BACKUP_DESIGN.md` records the focused evidence and unchanged scope.
No stage is closed, no deferral is added, and legacy sync is untouched.

S10 is ACTIVE, beginning with the current installed-package and legitimate
save/state-path audit. Its first required real slice is RetroArch plus one
standalone emulator, with separately consented backup-only Drive writes and
verified restore to the expected save location. None of those acceptance criteria is satisfied
by the inventory alone. S7 stays BLOCKED and its reception/retention work is
unchanged; the derived S10 dependency is corrected because explicit save-group
backup does not consume the unproved Top-25 set. No later-stage work is opened.
FolderSync and the laptop task remain unchanged until the verified SAVE-01
handover. Installed-route investigation and the narrow workflow are ordinary
unfinished S10 work, not blockers or tracked deferrals.

### S10 verified backup-area setup — 2026-10-09

S10 remains the sole ACTIVE stage. Normal Settings setup has real Thor consent
for the separate app-specific `drive.file` backup scope and a verified private
app-owned area. Explicit account binding, read-only ROM access, durable reserved
identity, canceled/lost-response recovery and source-change isolation have focused
verification. A rejected preference-write retry defect was reproduced and fixed;
no remote creation is allowed until its recovery intent is durably acknowledged.
Gated assembly 474 and its preserving Thor update pass. The existing backup-area
reference survives replacement and verifies without sign-in; protected preference
hashes match immediately after replacement. Existing job 76 was normally paused
and resumed, and both physical displays are OFF. Exact evidence and qualifications
are in `S10_SAVE_BACKUP_DESIGN.md`.

No actual save capture/upload/restore is implemented by this setup; those native
RetroArch/standalone workflows, full installed-emulator route coverage, durable
background work, conflicts/recovery and conditional legacy-sync handover remain
required unfinished S10 work. FolderSync and the laptop task are unchanged.
S7 stays BLOCKED, S11 stays NOT STARTED; no tracked deferral is added and overall
implementation is not complete.

### S10 save-generation transport checkpoint — 2026-10-09

S10 remains the sole ACTIVE stage. The exact bound save-group manifest and
streamed immutable Drive upload/readback/download path now have focused host
verification, including failed-new-generation preservation of the last complete
generation and lost-response recovery using the same reserved IDs. ROM access
remains read-only; no remote update/delete or generic mirror is introduced.
This is an enabling boundary, not delivered save backup: native coherent capture,
durable jobs/mappings, Settings/game/background integration, real RetroArch plus
standalone backup/restore/emulator-load verification, full installed-route
coverage and legacy-sync handover remain unfinished. None is reclassified as a
deferral or silently waived. Exact evidence/limitations are recorded in
`S10_SAVE_BACKUP_DESIGN.md`. No Thor data or external sync configuration changed;
S7 remains BLOCKED and S11 NOT STARTED.

### S10 verified narrow cloud publication — 2026-10-09

S10 remains the sole ACTIVE stage. Diagnostic request 492 isolated a general
Drive-version change after byte length and SHA-256 passed. With request 494,
normal Resume published the retained generation and a fresh reviewed capture
also completed cloud readback and manifest publication. The earlier rejection
was intermittent; its particular metadata change was not identified live.
The corrected transport uses mandatory binary `headRevisionId`, retains every
digest/ownership/binding check, and passes regression-first metadata-only,
missing/changed revision and corrupt-byte checks. The original gated request 496
completed exit zero, with acquired gate and verified low-memory profile. Its
preserving Thor update passed independent APK/signature and protected-file checks;
a fresh normal backup completed full cloud readback/publication at 16:50 local.
Same job 76 resumed and advanced without sign-in; both displays were OFF afterward.
The earlier live-wait checkpoint is superseded, not a request to rebuild.

This proves one real RetroArch save capture/cloud backup, not native restore or
SAVE-01 completion. Restore/emulator-load, standalone and remaining installed
routes, coherent related groups, background work, conflict/recovery, coverage UI
and conditional legacy-sync handover remain required unfinished S10 work. S7
stays BLOCKED, S11 NOT STARTED, and no tracked deferral is added. See
`S10_SAVE_BACKUP_DESIGN.md` for exact evidence and the next restore boundary.

### S10 restore/rollback integration — 2026-10-09

S10 is still the sole ACTIVE stage. The former empty restore controller now
persists cloud-generation, restore and rollback identities before native work,
captures the current local SRAM first, downloads through the real cloud API,
and requires normal verified EOF/native sealing before publication. Explicit
UI confirmations distinguish cloud replacement from restoring the retained
local capture; the latter preserves the replaced save in a new capture.
Resume retains operation IDs and sealed rollback bytes, and a pending restore
prevents a new backup from replacing its recovery intent. Retargeted editions
reject before capture/download; timestamps never authorize replacement.

Focused regression-first job/adapter/widget checks pass, including failed final
stream verification, replay and explicit rollback. The C++ filesystem replacement
contract passed on Linux; this is not Android FUSE/JNI or emulator-load evidence.
Native acknowledgement ordering now releases the worker before replying so a
subsequent streamed chunk cannot race its predecessor's active flag. Required
gated Android request 501 completed exit zero through the retained supervisor,
with acquired gate and verified low-memory profile. The preserving installation
matches APK SHA-256 `ad4bc0c5338ef63141eebd18099c7efee4385e8cc69ec80bc2f0e9d9aa469e70`
and the unchanged signer; protected preferences/configuration and thirteen mGBA
save digests match across replacement. Normal cloud restore and retained-local
rollback both reached native `published` receipts with matching 512-byte SHA-256;
the thirteen saves also matched before/after those operations.

Emulator-load acceptance has not passed. Live checking exposed that the selected
older save uses a different installation document ID from the current ROM launch,
which creates another save filename. Same-ROM relaunch after normal Close Content
also remains at No Core: the pinned RetroArch Android onNewIntent route does not
reload identical ROM/core extras. A normal user Quit then cold launch boots the
game, but this diagnostic workaround is not a completed product correction.
Save/launch binding and actual emulator consumption remain unfinished S10 work;
coherent RTC groups, standalone
and full installed-route coverage, background work, recovery cases and conditional
handover remain ordinary unfinished S10 work. No new deferral or waiver, and no
legacy-sync change. S7 remains BLOCKED; S11 remains NOT STARTED.

### S10 first native capture investigation — 2026-10-09

S10 remains the sole ACTIVE stage. The normal GBA game-details Save backups
entry now supports explicit save-file selection and edition confirmation. SQLite
retains the exact capture intent before native IO and immutable generation IDs
before upload. Focused host checks cover restart/replay and publication failures;
they do not establish a working native backup or restore.

The preserving Thor installation matches diagnostic APK SHA-256
`d7c815df98ad550246479b11fdc113d678bb1ee422c54178988f2062c82b6e59`.
Live capture correctly rejected active RetroArch content. After normal Close
Content, replay failed before UDP or copying: redacted native diagnostics identify
SaveCaptureService's canonical-versus-absolute private-directory comparison at
line 172. The existing exact capture directory is an ordinary private directory;
the framework parent alias is not normalized. A focused regression now targets
normalizing that trusted parent while retaining descendant alias rejection.
No save upload/restore acceptance has passed. The selected source digest remains
unchanged, and the pending capture intent is retained for deterministic replay.

Actual coherent capture/upload, verified emulator-load restore, standalone and
remaining installed routes, background work, conflicts/recovery, and the
conditional legacy-sync handover remain unfinished S10 work. FolderSync and the
laptop task are unchanged. No tracked deferral is added; S7 stays BLOCKED and
S11 NOT STARTED.

### S10 coherent native capture and cloud readback investigation — 2026-10-09

S10 remains the sole ACTIVE stage. The private capture root now normalizes the
framework-owned parent before checking its descendants. The bounded native path
regression failed before this correction and passed afterward. Gated request 488
completed successfully; its preserving installation independently matches APK
SHA-256 `e80e4318dc80adb7ac98ce3e7d89fcc067e76f3ffe7478b1d682db417327fcb7`.
Immediate configuration/secure-preference digests and all thirteen observed mGBA
save digests match across replacement.

The earlier Close Content observation was premature: RetroArch was still at its
confirmation. The normal action was subsequently completed and the actual No
Core screen verified. Normal R-Shop replay then produced a sealed 512-byte Aero
save capture with the same SHA-256 as the original source. Capture did not alter
the source. The durable generation IDs and sealed bytes are retained after the
real cloud path reports `digestMismatch`; no verified cloud backup or restore is
claimed. Request 492 builds redacted readback diagnostics to distinguish byte
length/content failure from cloud-version change before a production correction.

The reviewed three diagnostic screenshots (437,227 bytes) and their exact device
copies are removed and verified absent; preservation journals and the pending
private capture remain. Both physical displays were observed Asleep/OFF. The
metadata owner's normally paused job 76 still needs normal Resume after the next
preserving update. Native restore/emulator load, the standalone slice, installed
route coverage, background work, recovery/conflicts and conditional legacy-sync
handover remain unfinished S10 acceptance. FolderSync and the laptop task are
unchanged; S7 stays BLOCKED, S11 NOT STARTED, with no new tracked deferral.

### S7 preserving update 451 and selection durability — 2026-10-09

S7 alone remains ACTIVE; S8-S11 are NOT STARTED. The rejected legacy-selection
and migration-version writes now retain retryable input and require durable
acknowledgment. Focused host verification and native grant/ZIP tests pass;
assembly 451 passes and its preserving installation independently matches the
built APK. Configuration, nine private preferences, published root and paused
saved jobs survive unchanged. Normal Resume advances the same job 76 from
19,284 to 19,364 without sign-in. Exact build/profile/artifact and scoped
146-file preservation evidence is in `S7_ACCEPTANCE_RECONCILIATION.md`.
Shared PPSSPP/private-save coverage remains unproved, not a passing full safety
gate. Full fresh traversal, required scoped/provider passes, defensible retention
and reviewed exact migration remain current S7 work.

### S7 Library availability ANR investigation — 2026-10-09

S7 alone remains ACTIVE. Android terminated update-436 process 7116 with an
input-dispatch ANR on sleep/focus loss, not an OOM. Its persisted `running` job
status was not a live metadata worker. The process was relaunched normally only
after confirmed termination; immutable job 76 is not recaptured or rewritten.
Fresh VM sampling of ordinary Library entry traces the main-isolate hotspot to
`InstalledFilesState.hasExactArtifact`: every collection item scans the entire
console's exact-installation list, repeatedly encoding IDs during content checks.
The regression failed on 1,311,232 ID-key reads for a bounded
512-installed/1,536-item fixture. The indexed-snapshot correction passes focused
identity/provider/dashboard/discovery checks and gated native assembly 442.
Preserving installation and normal Library/sleep/wake verification pass: the same
process 19724 and immutable job 76 advance from 18,620 to 18,744 lookups without
sign-in. Both Thor displays are OFF. Evidence and qualifications are in
`S7_LIBRARY_AVAILABILITY_INDEX.md`; indefinite unattended reliability and complete
save-safety are not claimed. Full fresh coverage, required scoped/provider work,
defensible retention and reviewed exact migration remain S7 acceptance work.

### S7 ranking read batching and published root — 2026-10-09

S7 alone is ACTIVE; S8-S11 are NOT STARTED. Root generation 2 is published
(active=2, pending=null). Preserving APK update 436 matches the built artifact
and retained immediate configuration/private-storage/saved-job state. Normal
Resume continues immutable job 76 without sign-in: 18,543 -> 18,548 requests,
701 rated / 25,016 pending. Normal Library's existing PSP shortlist completes
with 35/334 ranked, 25 matching, Provisional after the bounded catalogue-read
correction. Host regression/identity/index/resource verification and native
assembly/profile evidence are in `S7_RANKING_CATALOGUE_READS.md`.

The protected-file journals have identical 146-file digest/size sets, but their
comparison remains nonpassing because emulator config captures were unstable
and shared PPSSPP was unavailable. This is not full saved-data safety proof.
Both screens are OFF. Full fresh metadata, required scoped/provider passes,
defensible canonical retention/current-cloud checks and reviewed exact migration
remain S7 work; no ROM removal or external save-sync change occurred.

### S7 native policy and nested execution — 2026-10-09

S7 alone is ACTIVE. The installed policy projection completed through normal
Library filtering. Wii/Wii U Best-25 reports truthful zero eligible results and
provisional coverage; two ordinary nested GBA raw-ROM bindings are verified
against their exact persisted container observations. Original filters and
configuration are preserved, and both displays are OFF. Evidence and limits:
`S7_NATIVE_POLICY_AND_NESTED_PROOF.md`.

The same live root observer reports 21,857 committed pages in pending generation
2. Saved job 76 remains Running at 16,571 requested / 27,099 pending, no blocked
status. Full publication/scraping, required scoped passes, defensible retention
and reviewed exact migration remain unfinished; S8-S11 are NOT STARTED.

### S7 preserving update and native DSi mapping — 2026-10-09

S7 alone is ACTIVE; S8-S11 are NOT STARTED. APK 435 is now installed with unchanged
signer and immediate configuration/encrypted/protected-file preservation. The
normal editor's unchanged save preserved every existing mapping/system and all
seven ordered sources. Explicit DSi selection added only that system; its normal
Android folder picker then changed only its target to existing DSiWare. No ROM
was moved, adopted or removed.

Normal Refresh/Resume retained catalogue generation 2 and immutable metadata job
76 without account selection. The retained observer confirms 20,639 committed
pages in the replacement process; job 76 is Running at 16,321 requested / 27,359
pending, no blocked status. Publication and fresh coverage are not finished.
Native cached policy/nested identification, defensible canonical retention,
current-cloud proof and reviewed migration remain S7 work. See
`S7_NATIVE_UPDATE_435.md`; this supersedes older not-installed checkpoints, not
their acceptance criteria. Both screens are OFF after verification.

### S7 nested identifier location gap — 2026-10-09

S7 remains ACTIVE; S8-S11 remain NOT STARTED. Bounded read-only native observation
found fourteen sampled review entries with an exact nested local file and no
root-level copy. The metadata reader previously checked only the root leaf.
Regression-first correction now permits one exact ancestor-ID-derived nested
lookup after root absence, retaining full checksum/raw-member/live-boundary
checks and no ownership/download/removal side effects. Focused runtime/boundary
checks and scoped analysis pass; details and limitations are recorded in
`S7_NESTED_METADATA_IDENTIFICATION.md`.

Shared-gate request 435 completed debug assembly and unchanged-signer APK
verification. Observed profile: two workers, no parallel projects, 3 GiB Gradle,
assessed Kotlin in-process, one configured 512 MiB test fork (not executed),
independently verified depth-one native pools, no memory failure. The final
output's gate-acquired field was truncated; the evidence document records this
qualification rather than inferring it from the queue ticket. The APK has not
been installed; normal Thor verification remains pending. Read-only inspection
confirms root refresh advanced to 7,630 committed pages with the device asleep.
The existing app/root refresh and saved job 76 remain intact; terminal requests
are not rewritten. Consumed diagnostic helpers were identity-checked and removed
with no ROM/save changes or cleanup residuals. Complete
fresh coverage, defensible retention and reviewed SD migration are still required.

### S7 combined native assembly — 2026-10-09

The current S7 worktree, including mapping-selection and Wii/Wii U policy fixes,
passes gated native assembly and APK signature verification. Request 434 confirms
gate acquisition and completion: two workers/no parallel projects, 3 GiB Gradle,
assessed Kotlin in-process, one configured 512 MiB test fork (not executed by
assembly), and independently verified depth-one native pools. No memory failure
or budget increase occurred. See `S7_NATIVE_BUILD_434.md` for artifact, actual
scope, warnings and profile evidence.

The APK is not installed while the existing process 1335 advances root refresh;
5,889 committed pages were observed, with both screens OFF. Native editor/policy
verification, complete fresh metadata, defensible retention/current-cloud checks
and reviewed migration remain unfinished. S7 alone is ACTIVE; S8-S11 NOT STARTED.

### S7 Wii/Wii U ranking-scope reconciliation — 2026-10-09

S7 remains ACTIVE; S8-S11 remain NOT STARTED. The assessed IGDB community basis
now includes Wii/Wii U, with unchanged twenty-known-vote, exact identity,
ownership, freshness and provisional-coverage gates. The public benchmark and
independent original-platform evidence are recorded in
`SCORE_RECEPTION_ASSESSMENT.md`, including material numerical disagreement and
excluded sparse-vote records. Regression-first support boundaries, cached-policy
SQLite ranking/retention and scoped Dart analysis pass. The real serial provider
capture ranks eight of ten public releases through the offline production query;
it does not classify private games or establish whole-collection retention.

Native integration remains unfinished. No Gradle command or APK installation
was performed for this change. The existing Thor process 1335 remains live;
read-only inspection observes root generation 2 advancing to 5,405 committed
pages and saved job 76 Running at 13,919 requests. Configuration hash is unchanged
and both displays are OFF. Full fresh coverage, native mapping/policy checks,
defensible retained sets and reviewed exact migration remain S7 requirements;
no ROM removal, ownership adoption or later-stage implementation occurred.

### S7 explicit mapping selection — 2026-10-09

The editor no longer selects unique folder aliases automatically. Regression-first
widget/save-path checks, scoped analysis and gated debug assembly pass; only
explicit choices add mappings. The new APK is not installed while the existing
root refresh and saved scrape are advancing. Native editor verification and DSi
configuration remain required. See `S7_DRIVE_MAPPING_SELECTION.md` for exact
evidence/profile qualifications. S7 alone remains ACTIVE; S8-S11 NOT STARTED.

### S7 DSi provider alias — 2026-10-08

- S7 remains ACTIVE; S8-S11 remain NOT STARTED. The live authenticated platform
  catalogue explicitly aliases DSi to ScreenScraper platform 15. The adapter
  now preserves distinct R-Shop DSi identities while using that provider ID.
  Regression-first checks, two real reviewable candidate lookups and scoped
  analysis pass; unknown editions are not classified or scored by this alias.
- Shared-gate request 432 completed with gate acquired, two workers/no parallel
  projects/3 GiB Gradle, assessed Kotlin in-process, one configured 512 MiB JVM
  test fork and verified depth-one native pools. No memory failure occurred.
  Signer-preserving update matches the verified APK, retains immediate protected
  storage/configuration and all 49 save/configuration baselines. Normal Resume
  advances the same job 76 to 13,437 requests without a chooser.
- DSi normal folder mapping/scoped metadata coverage, current root publication,
  full metadata/defensible retention and reviewed migration remain S7 work.
  See `S7_DSI_PLATFORM_VERIFICATION.md`; no restore/removal eligibility is implied.

### S7 build 431 continuation — 2026-10-08

- S7 remains ACTIVE; S8-S11 remain NOT STARTED. The folder-only recursive
  traversal regression passes the actual SQL work-count and membership checks.
  Gated native assembly completed with two workers/no parallelism/3 GiB Gradle,
  assessed Kotlin in-process, one configured 512 MiB test fork (not executed),
  depth-one native pools and no memory-related failure or budget increase.
- Signer-preserving installation matches the verified APK and preserves the
  immediate pre-update configuration and protected storage. Normal shared
  metadata recovery completes, and Resume advances the same job 76 from 13,093
  to 13,099 requested lookups without sign-in or replacement capture. Normal
  Library loads its dashboard and console tabs. Read-only native query isolation
  verifies indexed 500-row pages at 43 ms (DS), 141 ms (NES) and 10 ms (SG-1000).
  Cold startup remains slow across other work; no total-latency fix is claimed.
  All 49 protected hashes and the original ROM digest match after verification.
  Full fresh coverage, defensible retention and migration stay
  open. Exact evidence and build-output qualifications are in the S7 ledger.

### S7 build 428 unmanaged local-first proof — 2026-10-08

- S7 remains ACTIVE; S8-S11 remain NOT STARTED. Build 428's normal Library now
  shows one installed SG-1000 Bank Panic card. The original unmanaged file has
  OPEN but no DELETE action. Fresh normal byte verification confirms current
  Drive version 3 and identical complete container bytes, without adoption.
- Normal OPEN launches that exact observation-bound ZIP through RetroArch's
  Genesis Plus GX core; the animated title screen was visually inspected.
  Its sibling raw-ROM probe is denied. Returning retains the single card;
  original ROM and all 49 save/state/configuration baselines match. The two
  disposable captures were transactionally removed with no residuals.
- This is actual single-card/local-first evidence, not a claimed native
  disappearance/restoration or deliberate two-to-one invalidation test.
  Notification sequencing/cancellation is covered by the focused regression.
  Cold loading eventually completes but remains slow. Full metadata coverage,
  defensible per-console retention, remaining format/current-cloud checks and
  reviewed migration still prevent S7 closure. See the acceptance ledger for
  build/profile, artifact preservation and exact native evidence.

### S7 build 423, restored connectivity and SG-1000 closure — 2026-10-08

- S7 remains the sole ACTIVE stage. The SG-1000 normal online/cold-offline/
  reviewed-removal/identical-usable-restore cycle passed. The original target and
  full configuration digest are restored; the original ROM and all 49 recorded
  save/state/emulator-config digests match. The isolated copy, empty directory
  and private captures are removed. See `S7_SEGA_RECOVERY.md`.
- The hotel captive portal, not lost Google consent, blocked Google HTTPS while
  Android still reported validated Wi-Fi. Normal portal authorization restored
  HTTP 204 connectivity and a successful Google HTTPS response. Normal queue
  Resume completed the already queued restore without an account chooser.
- A separate queue defect classified temporary native authorization-service
  unavailability as awaiting authorization. Regression-first focused engine and
  queue checks now distinguish retryable service failure from actual required
  consent/account setup; scoped analysis passes. The saved reference is preserved.
  The deliberate outage classification is host-verified, not claimed reproduced
  on the updated device after connectivity recovery.
- Ticket 423 (`6426f4306add44bb81fede39254ea2dd`) completed exit 0, with the shared
  mutex acquired and observed workers=2, parallel=false, Gradle heap=3 GiB and
  assessed Kotlin in-process compilation. JVM tests were configured as one
  512 MiB fork but not executed by assembly. Fresh inspection of the included
  Ninja rules verifies depth-one pools for all 281 compile/link rules across
  11 ABI files. No memory failure or budget increase occurred. Private build log:
  `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/6a5c7b1994444e009817b3a81c584708.log`.
- The signer-preserving update installed APK SHA-256
  `fb39a628601b97e61d09ea658fefaeccd968cd95c864be7ea09b650a23eaa15c`;
  installed base.apk matches. Immediately pre/post installation configuration
  and both protected-storage digests match. Normal UI confirmed job 76 Paused
  at 12,720 requested / 31,154 pending / 383 rated before updating. Normal Resume
  on the updated process advanced it to 12,725 requested / 31,149 pending without
  sign-in or replacement capture. It is Running, not a completed full pass.
- Full fresh coverage, defensible Top-25 retention, remaining local-first and
  recovery evidence, current cloud checks and reviewed migration remain required.
  S8-S11 remain NOT STARTED. No bulk owner-ROM removal or release occurred.

### S7 build 421 and SG-1000 recovery checkpoint — 2026-10-08

- Ticket 421 completed exit 0 through the shared gate. Observed workers=2,
  parallel=false and Gradle maximum heap=3 GiB; Kotlin uses the assessed
  in-process strategy. One 512 MiB JVM test fork was configured, not executed by
  assembly. All 281 inspected native compile/link rules across 11 active ABI
  files use depth-one pools. No memory failure or budget increase occurred.
- The signer-preserving owner update installed APK SHA-256
  `8da796da39d7fd93f6c67b5242f8967ec0fd52536f7470fb9288483950574bfc`.
  Installed base.apk matches; the immediately pre-update configuration and both
  protected-storage digests are unchanged. Normal UI confirmed saved metadata
  job 76 Paused at 12,720 requested / 31,154 pending / 383 rated before updating.
- On the new normal owner process, Library progressed from initial zero/loading
  to Dashboard 25, All 44,685 and Installed 2,855. SG-1000 shows one Bank Panic
  card with its installed marker. This verifies normal startup/navigation on the
  updated APK; controlled in-flight invalidation is covered by the regression,
  not falsely claimed as a deliberately triggered native event.
- Normal DOWNLOAD published Bank Panic's 21,280-byte ZIP into the isolated
  SG-1000 target, with SHA-256 matching the original. Normal OPEN on build 421
  launched Genesis Plus GX and the actual animated title screen was inspected.
  The exact ZIP grant succeeded; the sibling `.sg` probe was denied. Cold-offline
  launch, reviewed removal, identical usable restore and normal target restoration
  remain in progress; the original ROM folder has not been altered.
- microG separately crashes in its authorization request with
  `NoRouteToHostException: Host unreachable`; the hotel Wi-Fi remains reported
  VALIDATED but a diagnostic Google-host ping receives a packet-filter response.
  No Google data, account or credentials were reset. Laptop tethering creation
  fails with HRESULT 0x83120001 and the hotspot service is disabled; no system
  service configuration was changed. Cached browsing still populated normally.
- S7 alone remains ACTIVE. Full fresh metadata, defensible retention, remaining
  recovery/local-first evidence and reviewed migration are unfinished. S8-S11
  remain NOT STARTED; no owner ROM removal, release or later-stage work occurred.

### Current S7 startup lifecycle diagnosis — 2026-10-08

- S7 remains the sole ACTIVE stage. Ticket 415 terminated with an invocation
  error (`Task '.dart' not found`), not a memory failure. Correctly quoting the
  complete `-Ptarget=lib/main.dart` argument allowed ticket 416 to finish with
  exit 0, gate acquired and profile verified: workers=2, parallel=false, Gradle
  heap=3 GiB, Kotlin in-process, one configured 512 MiB test fork (not executed
  by assembly). Every inspected app/SoLoud/JNI native compile/link rule uses a
  depth-one pool. No budget increase or memory failure occurred.
- Signer-preserving installation of APK SHA-256
  `de4bfb3e3ba310f8d443b32b1f16fc29b767c1577caaba6f6d879526f9b7dbdb`
  preserved configuration and both protected storage digests. Normal Pause
  joined saved metadata job 76 at 12,692 requested / 31,181 pending / 382 rated.
  It was Paused before installation, not replaced. SG-1000's empty isolated recovery destination
  is configured; no SG-1000 ROM was downloaded or removed yet. Restore the normal
  target after completing its recovery proof.
- The new process still leaves Library at Dashboard/All/Installed zero. SQLite
  initially consumed 216,125 ms across startup work, including repeated cached
  subtree queries, then became idle. Read-only VM inspection identifies the
  permanent wait: `_loadDataOnce` awaits selectionContinuityProvider.future;
  that provider is invalidated, unmounted and pending with no active listener.
  InstalledFilesState already contains data. Riverpod's refresh scheduler only
  rebuilds listened providers; the discarded operation cannot complete the
  pending provider future. This is distinct from the earlier unproven ANR cause
  and from SQL latency; no speculative catalogue query rewrite was made.
- A deterministic widget regression reproduced one migration instead of the
  required rebuilt migration after catalogue invalidation. The screen now keeps
  a lifecycle-bound subscription while awaiting selection migration and closes
  it on disposal. That regression and the affected Library discovery/local-cloud
  continuity checks and scoped analysis pass. Native verification of this
  correction awaits shared-gate ticket 421 (`f1c09db5563d460684546fc57915d1d8`),
  retained command session 19661; do not claim gate acquisition, an effective
  profile or the startup defect fixed on the device before actual results.
- While that request waits, normal Resume advanced the same saved job from
  12,692 to 12,699 requested / 31,174 pending / 383 rated without a chooser.
  It is Running. Join normal Pause before installing the next APK. The old
  diagnostic UI wait was explicitly interrupted after identifying the lifecycle
  hang, its exact capture removed and absence verified, and both screens are OFF.
- Full fresh metadata coverage, defensible Top-25 retention, local-first native
  proof, SG-1000 recovery and reviewed migration remain required. S8-S11 are NOT
  STARTED. No bulk removal, release or later-stage implementation occurred.

### Current S7 Master System and scoped library reads — 2026-10-08

- Master System normal online/cold-offline/remove/identical usable restore passed.
  Original destination/full config are restored; the original ROM and 49 recorded
  save/state/emulator-config checksums match. Exact task copy, empty destination
  and private captures are removed. See `S7_SEGA_RECOVERY.md`.
- The earlier Android input-focus ANR is not declared fixed. Its previous process
  exited; a new launch reproduces slow loading but not that ANR. CPU samples
  identify shared recovery and collection-wide artwork hashing. Dashboard metrics
  do not need either game cover or score consumption; console browsing must use
  that console. A failing widget regression first reproduced the global read.
  The minimal consumer correction and existing focused Library discovery checks
  now pass, with scoped analysis clean. Native proof is pending ticket 415 /
  session 40791 through the shared gate; acquisition/profile are not yet claimed.
- S7 remains the sole ACTIVE stage. Normal Resume continued metadata job 76
  without a chooser: 12,531 -> 12,542 lookups / 31,333 pending, 374 rated. It is
  Running while the build waits; join normal Pause before installing. SG-1000
  recovery, exact local-first integration, full fresh
  coverage, defensible Top-25 retention and reviewed migration remain required.
  S8-S11 remain NOT STARTED; no bulk removal or release occurred.

### S7 Mega Drive normal recovery cycle — 2026-10-08

- S7 alone remains ACTIVE. Normal Drive DOWNLOAD -> owned RetroArch Genesis Plus
  GX online boot -> cold offline boot without any active network -> reviewed
  removal -> identical re-download -> actual title-menu boot passed on the Thor
  for one explicitly mapped single-member `.md` ZIP. This is format-specific
  recovery evidence, not trustworthy ranking or permission for bulk removal.
- The test installation was removed through normal reviewed DELETE. Its empty
  isolated folder is absent and the normal Mega Drive destination is restored.
  Full R-Shop config, the original ROM, all 47 recorded RetroArch save/state
  files and both RetroArch configs match their pre-test checksums. Wi-Fi is back
  online; no cloud object, owner ROM, BIOS or emulator setting changed.
- The saved scrape was observed Paused at 12,287 requests. Normal Resume advanced
  the same job 76 to 12,289 / 31,599 pending without a chooser or fresh snapshot.
  The earlier pause cause is not established; full coverage remains unfinished.
- The mislabeled Sega launch menu is corrected in source after a failing focused
  regression. Affected host wiring/handoff checks, scoped analysis and whitespace
  checks pass. Build 408 / session 68644 completed with the shared gate acquired:
  two workers, no project parallelism, 3 GiB Gradle heap and Kotlin in-process.
  One 512 MiB test fork was configured, not executed by assembly; active native
  compile/link rules use depth-one pools. No memory failure or budget increase.
  Installed APK matches the built artifact and retains the existing signer,
  configuration and protected storage. Normal Resume advanced the same job from
  12,359 to 12,361 requests / 31,525 pending without sign-in. Normal supported
  Master System owned-copy menu inspection now verifies “Open in RetroArch”,
  and actual online Genesis Plus GX boot is visually inspected. Its cold-offline
  / identical-restore cycle and restoration of the isolated target remain open.
- See `S7_SEGA_RECOVERY.md`. Master System/SG-1000 recovery, local-first proof,
  full metadata, defensible retention and reviewed migration remain required.
  S8-S11 remain NOT STARTED; no bulk SD migration or release occurred.

### S7 native build and cold-start authorization correction — 2026-10-08

- S7 remains the sole ACTIVE stage; S0-S6 are COMPLETE and S8-S11 are NOT
  STARTED. The queued-build statements in the checkpoints below are historical.
- Tickets 389 and 391 completed successfully through the shared build gate:
  normal debug APK and native instrumentation APK respectively. Both observed
  two workers, no project parallelism and 3 GiB Gradle heaps, Kotlin in-process;
  test tasks were configured for one 512 MiB fork, not executed by assembly.
  Generated Ninja rules for app/SoLoud/JNI place each C/C++ compile/link command
  in a depth-one pool. No memory failure or heap increase was reported.
- Signer-preserving installation of the normal APK succeeded and installed
  base.apk SHA-256 matched `a1473562ff7625845fd3b9bc4a259382f42d4800a7e58617c87cc0f85ba9c85a`.
  Config and both protected secure-storage file digests were unchanged by that
  update. Native OwnedRomInstrumentation returned PASS, including read-only
  observed-copy/provider proof for RVZ and the three observed Sega ZIP formats.
  This does not replace normal emulator/download/offline/recovery acceptance.
- Normal Resume of saved metadata job 76 on that APK encountered
  `DriveAuthorizationException` before live source validation. The adapter's
  noninteractive authentication returns its in-memory account only; process
  replacement empties that account and deterministically requires a chooser.
  This is an app lifecycle defect, not evidence of lost saved configuration or
  Google token expiration. Ordinary default-account connection succeeded;
  returning without saving preserved the complete config hash.
- Regression-first cold restart reproduced absent persistence and wrong-account
  classification. The correction saves only the explicit private account ID/email
  reference, scoped to the OAuth client, after successful authorization. It uses
  the installed endorsed Android platform API's account-bound scope request with
  prompting disabled; neither interactive nor lightweight sign-in is called on
  restoration. Tokens remain ephemeral. Sign-out clears the reference; revoked
  scopes, missing reference and account mismatch stay fail-closed.
- Focused adapter/coordinator checks and scoped analysis pass. Older adapter
  renewal assertions supplied a different token than the current cached grant;
  corrected cases now exercise rejection of the actual grant. Missing-consent
  checks use a cold adapter rather than invalidating an otherwise usable cached
  grant by fiat. No stale-rejection/coalescing production contract was weakened.
- Ticket 400 / session 12898 completed with exit 0, gate acquired and effective
  profile verified. Signer-preserving owner installation independently matches
  `134b657aae6b07a52c4bf2d1ef34c17c1794cd70ed6f5a46421dd055eb80eefb`.
  Fresh app/SoLoud/JNI generated Ninja rules, including the current pub-cache
  roots, verify depth-one pools on every C/C++ compile/link command. No memory
  failure or budget increase occurred; one 512 MiB JVM test fork is configured,
  not executed by assembly. Kotlin remains in-process under Gradle's 3 GiB heap.
- One ordinary default-account connection seeded the account reference absent
  from the old version. After joined Pause, force-stop confirmed no owner process;
  the new PID resumed the same job without a chooser, advancing 12,194 -> 12,199
  requests. A second joined Pause followed by install-replace of the same APK
  preserved config and both protected storage digests exactly. Its new process
  resumed without sign-in and advanced 12,204 -> 12,209 requests, pending=31,682,
  rated=357, provider quota=11,130/20,000. This verifies process and APK replacement
  continuity, not full collection completion or future arbitrary migrations.
- Source configuration hash remains unchanged; no account/mapping save, ROM
  mutation, sign-out/revocation of the owner's grant, new snapshot or retry pass
  was performed. Adapter/coordinator checks and analysis pass, including restored
  renewal/revocation fixtures. Exact UI captures were identity-rechecked, removed
  and verified absent; both screens are actual/committed OFF with power Asleep.
  Full saved-job coverage, defensible retention, normal format recovery and
  reviewed migration remain open. No later stage, final commit or release.

### S7 source-change interruption correction — 2026-10-08 evening

- S7 remains the sole ACTIVE stage; S0-S6 are COMPLETE and S8-S11 are NOT
  STARTED. This checkpoint supersedes the earlier running-metadata observation.
- Normal UI found the same Entire collection job Paused at 12,171 requests,
  371 matched, 4,518 review, 987 ambiguous, 6,202 unmatched, 406
  failed/unsupported, 356 rated and 31,720 pending. Normal Resume once reproduced
  the failure immediately without advancing or replacing the captured cohort.
- Sanitized debug diagnostics identify `DriveTransferException` at
  `DriveVerification.requireCurrent`, through the live
  `DriveDownloadBoundary.revalidate` call in `readMetadataArchive`. The binary no
  longer satisfies the captured source boundary; the exact differing field is
  not established. The job propagated that item-specific failure and paused the
  whole collection. No storage mutation or provider retry can repair that old
  captured identity.
- Regression-first archive and CHD-header cases reproduced the same exception.
  The worker now commits only that uncancelled item's existing `identityChanged`
  outcome, without a provider lookup, raw binding, classification or generation
  change, and continues independent captured items. Cancellation racing with a
  different failure, access errors, malformed observations and storage failures
  remain distinct; no broad exception swallowing or title fallback was added.
- The affected catalogue-job test file passes, including preserved pause/drain,
  error and identity/restart contracts. This is host verification, not native
  deployment proof: the installed older APK still pauses on that source. Leave
  its saved job intact for resumption after the pending build/update; do not
  repeat Resume against unchanged code or create another collection snapshot.
- Ticket 389 / session 99133 and its event-driven observer remain live with no
  reported gate acquisition/build result. Requested low-memory settings are not
  verified effective settings. No second build or interruption was introduced.
- Task UI dumps were hash-rechecked, removed and verified absent. Both physical
  screens are subsequently confirmed OFF with the Thor Asleep. Full scrape,
  current native integration/recovery, retention and reviewed migration remain
  required before S7 can close.

### S7 saved metadata continuation — 2026-10-08

- The normal Entire collection workspace showed Paused with an operation-failed
  notice: 8,876 requested, 247 matched, 3,129 review, 713 ambiguous, 4,696
  unmatched, 241 failed/unsupported, 238 rated and 35,178 pending. Those terminal
  counts plus pending still total the existing 44,204 captured members.
- Pressed its one observed enabled Resume saved job control once. The controller
  resumes the selected report ID; no Refresh, Retry, provider/account/mapping
  change, new job or database write through an audit tool was performed.
- Fresh normal UI then reports Running, 8,891 requested, 247 matched, 3,136
  review, 714 ambiguous, 4,703 unmatched, 241 failed/unsupported, 238 rated and
  35,163 pending. Provider-reported remaining attempts are 15,800/20,000. This
  verifies resumed traversal, not its completion or a diagnosed/fixed cause of
  the earlier operation failure. No per-game curation or ROM action occurred.
- Ticket 389's original session 99133 remains confirmed live without new build
  output. No replacement or competing build was launched. S7 remains ACTIVE;
  native proof, full coverage, retention/recovery and migration remain required.
- The exact task-created UI dumps were hash-rechecked and removed; absence was
  verified. Screens were put to sleep after each inspection; verify physical
  OFF state after the final transition rather than treating Dozing as OFF.

### Current S7 execution correction — 2026-10-08

- S7 is ACTIVE, the sole ACTIVE stage. S0-S6 remain COMPLETE; S8-S11 remain
  NOT STARTED. The preceding blocked classification below is superseded: normal
  queued Gradle waiting does not itself justify stopping implementation.
- On user-directed continuation, session 81299 is unknown and its supervising
  process 78196 is absent. Queue ticket 387 still records that dead identity;
  no build result or gate/profile proof is available. A single replacement must
  use the normal shared gate's proven-exit reclamation, never manual queue edits
  or interruption of GameNative. Retain and wait on the replacement tool handle.
- Replacement request is registered as ticket 389
  (`cb93641c7393463b88de479c50f0e922`), live tool session 99133. The launcher
  explicitly reports `queued`. Gate acquisition/effective profile are not yet
  observed. Requested settings remain two workers, no parallel projects, 3 GiB
  Gradle with Kotlin in-process; no memory failure has been reported.
- All unfinished native, full-pass, retention/recovery and actual migration
  criteria remain required. No acceptance criteria or later-stage dependencies
  have changed; this correction does not claim implementation completion.

### Current S7 blocker — 2026-10-08

- S0-S6 are COMPLETE. S7 is BLOCKED and parked; no stage is ACTIVE.
  S8-S11 remain NOT STARTED. Earlier ACTIVE checkpoints below are historical.
- Blocked criterion: current native single-card/local-first/provider and Sega ZIP
  build plus normal Thor recovery proof. The retained build request 81299 remains
  live without gate/profile/build output. Fresh exact-process inspection still
  finds the preceding GameNative supervisor, wrapper, daemon and test executor.
  Its inspected coroutine wait does not establish an idle or completed build.
- This external build exclusion condition has repeated across three consecutive
  continuation turns. No further safe independent current-stage implementation
  is identified. Resolution requires confirmed preceding-build completion/idle,
  then completion of the same retained build and required native/device checks.
  No competing build, interruption, timeout or profile claim was introduced.
- Full metadata-pass completion, defensible per-console retention, readable cloud
  recovery and reviewed SD migration remain unfinished. These are not waived or
  reassigned. S7 and dependent S8-S11 cannot be declared complete. The overall
  objective is retained, not cancelled; no final commit or release is claimed.

### S7 native verification wait — 2026-10-08

- The same request 81299 is freshly confirmed live with no gate/profile/build
  output. Process identities bind the preceding GameNative wrapper, supervisor,
  daemon and test executor to its existing gated build. A read-only JVM thread
  dump shows its Robolectric test worker waiting on the SDK main thread, which
  is inside a coroutine `runBlocking` call in `CanonicalMutationRepositoryTest`.
  This is current outstanding test activity, not proof of an idle daemon or
  authority to stop it. No competing Gradle invocation, timeout, configuration
  change or interruption was introduced.
- Current S7 native local-first/provider and Sega ZIP device verification still
  depends on completion of that existing build and then request 81299. Full
  fresh collection coverage, retention and reviewed migration also remain open.
  This is a verified wait, not a closed acceptance criterion or a new stage.
  S7 alone remains ACTIVE; S8–S11 remain NOT STARTED. No new device operation,
  owner-data mutation, commit or release occurred in this wait checkpoint.

### S7 observed Sega ZIP integration — host verified, native pending, 2026-10-08

- S7 alone remains ACTIVE. The current SD folders and one read-only archive
  listing per console confirm Mega Drive `.md`, Master System `.sms` and SG-1000
  `.sg` members. These observed ZIP profiles now reuse the existing bounded
  single-member validator, immutable transfer mapping, publication/recovery,
  explicit adoption, offline revalidation and exact RetroArch leaf routes.
  The installed Genesis Plus GX route is selected without settings/core changes;
  this does not admit 32X, generic ZIPs or unknown member formats.
- The normal metadata worker can bind these local raw hashes only after current
  complete-container equivalence. It preserves unknown/modified classification,
  records separate read-only byte evidence and makes no compensating ROM-body
  request. Focused regressions first failed on missing mapping, skipped metadata
  evidence and unsupported grant platforms. Current affected host checks pass
  for the runtime/queue, lost-receipt recovery, offline reuse, console handoff and
  metadata restart boundaries. A fixture-only hardcoded 7z name was corrected;
  the existing handheld adoption inputs remain unchanged. Scoped analysis and
  whitespace checks pass; bounded Java validator/grant tests pass at 256 MiB.
- Native dispatch, pinned-descriptor validation and owned/read-only provider
  admission are connected. The synthetic provider fixture now covers the three
  ZIPs as well as RVZ, but it has NOT been compiled/executed. Normal Thor
  online/offline/identical-restore proof remains required before migration.
  Request 81299 is still live without build/gate/profile output; no replacement
  or concurrent Gradle request was launched. Requested workers/heaps are not
  claimed effective, and no memory-related failure was observed.
- Normal Thor UI freshly reports the existing Entire collection job Running:
  requested 7,385, matched 200, review 2,536, ambiguous 575, unmatched 3,985,
  failed/unsupported 148, rated 194, pending 36,760. Provider-reported quota is
  17,890/20,000 remaining. This proves continued traversal, not full coverage or
  reliable Top-25 selection. No job, source configuration, account, ROM or ownership was changed.
  The exact task-created UI dump is absent, and both physical displays are
  confirmed committed/actual OFF with power Asleep after inspection.
- Cleanup transactions `a00133cd5128da39e1b76c1d8636bb45` and
  `2aab85b3b5d0538ceed9afe2a4dcfd4a` removed only the expendable compiler outputs
  and their empty task-created root. Exact root absence is verified; permanent
  test/source/evidence files remain. The compiler outputs are reproducible.
- S7 native single-card/local-first proof, completed fresh coverage, defensible
  retention, current cloud/format recovery and actual reviewed migration remain
  unfinished. S8–S11 remain NOT STARTED; no final commit, release or SD migration
  completion is claimed.

### S7 joined-pause matching audit — 2026-10-08

- The normal Pause control joined job 76 before the fixed READONLY audit opened
  SQLite. The audit inspected 7,147 terminal outcomes from the existing 44,204
  captured members, with bounded records/candidate samples and a 128 MiB process
  heap. It did not change requests, outcomes, identities or ownership. Normal
  Resume continued the same job: requested 7,105 to 7,107; pending 37,057 to
  37,055. These are observed cohort counters, not completed collection coverage.
- The unresolved cohort is dominated by unclassified title-only requests. For
  example, NES has 562 review and 131 ambiguous outcomes, with only 12 captured
  raw identifiers; PSP has 17 review outcomes alongside 16 matched releases.
  Exact-title candidates without an official-edition classification are correctly
  reviewable under META-03/04. Do not relabel them official, borrow a base score,
  or bypass regional/edition evidence to fill Top-25 lists. This audit establishes
  the evidence limitation, not a new production matching defect.
- The 66 captured Mega Drive resource failures remain in immutable saved-job
  history while the corresponding non-game cache rows are absent. They are not
  new failures of the already verified subtree exclusion. Required native
  local-first proof, completed fresh coverage, defensible retention and actual
  reviewed migration remain open; S7 alone is ACTIVE, S8–S11 NOT STARTED.
- Request 81299 remains a confirmed-live tool session without new build output.
  Read-only process inspection identifies another project's live wrapper/client
  and worker; it is not authority to interrupt them or launch concurrently. Gate
  acquisition and effective R-Shop build profile remain unconfirmed, with no
  reported memory failure. The same request is retained, not restarted.
- Both Thor physical displays are freshly confirmed committed/actual OFF and
  power Asleep. Exact task-created device probe/dump files were removed. Cleanup
  transaction `d696d27de4ed9df3b0a869bc344fa584` removed the two expendable host
  compiler outputs and empty output directory (12,346 bytes); absence is checked.
  Audit source and the sanitized evidence above remain; owner data is unchanged.

### S7 action eligibility and live scrape check — 2026-10-08

- Read-only local-copy availability no longer advertises the ownership-only
  Share path. Touch, controller focus and the handler use the same eligibility;
  Open remains available without adoption/removal rights. Focused detail/layout
  and real installation-journal checks pass, including owned sharing, missing
  variants and legacy sharing. Scoped detail analysis and whitespace checks pass.
- Current URI-parser source compiles and its focused JUnit checks pass with
  256 MiB compiler/test heaps. This is not Kotlin/APK/native-provider verification.
  The same request 81299 / ticket 387 is live with no gate/profile/build output.
- Normal Thor UI reports the existing Entire collection job running: requested
  7,046, matched 190, needs review 2,400, ambiguous 536, unmatched 3,832,
  failed/unsupported 127, rated 184, pending 37,119. No new job, mapping or account
  change occurred. Both physical displays are subsequently confirmed OFF/Asleep.
- Three expendable compiler classes and their empty output directories were
  reviewed/removed by cleanup transaction `5eb7881c07712a281059386d787032e6`;
  the exact directory is absent. The task-created device UI dump was also removed.
  No ROM, save, setting, ownership or release change occurred. S7 remains ACTIVE;
  native local-first proof, full scrape, rankings and reviewed migration remain
  unfinished. S8–S11 remain NOT STARTED.

### S7 single-card and local-first integration — host verified, native pending, 2026-10-08

- S7 is the sole ACTIVE stage; S8–S11 remain NOT STARTED. The normal Library host
  workflow now keeps one sourced card, artwork, favorite and manual-shelf order
  through exact-copy presence, disappearance and restoration. Raw catalogue rows
  and saved refresh membership are preserved. Changed versions, unlinked console
  namesakes and other providers remain distinct.
- Selection migration uses one acknowledged persistent favorites/shelves/receipt
  document and a serialized write sequence. Host checks verify rejected-write
  readback/retry, concurrent toggles, restart persistence, explicit unfavorites
  and another console's same-name selection. Observations never add managed bytes
  or installation/removal ownership. The normal and bulk local scan supplement
  now includes verified read-only leaves beneath a containing mapped root.
- Regression-first checks exposed the missing activity route for `localCopyInspect`
  and the launcher's ownership-only requirement. Both are connected. Supported
  exact local copies now select Open, with localized labels; removal is separate
  and still requires a reviewed owned manifest. The native content provider uses
  a distinct observation/platform leaf namespace, current catalogue/evidence and
  reservation checks, pinned file identity and read-only grants. A synthetic native
  provider fixture is prepared but NOT executed or claimed passing.
- The affected serial host run passed: metadata-read evidence, observations,
  ownership/visibility, handoff wiring, installed projection, selection migration,
  console controller, normal Library presence cycle, Open action and normal detail
  layouts. Native URI parser tests passed separately after their new namespace
  regression failed. No full suite or simultaneous test workers were used.
- Native request 81299 / ticket 387 remains live, with no acquisition/profile/build
  completion output observed. No second Gradle request was launched. Gate acquisition,
  effective workers/heaps/native settings, native compile and device behavior are
  unconfirmed for this patch; no memory-related failure is reported by that request.
  No APK was installed or device used in this continuation. Earlier OFF/Asleep proof
  is historical, not a fresh screen observation. No owner files or sync policy changed.
- This does not close S7: native single-card/local-first proof, full fresh coverage,
  defensible Top-25 sets, current cloud/restore gates and reviewed migration remain
  required. No commit, release or SD cleanup completion is claimed.

### S7 exact unmanaged-copy evidence — host verified, native build pending, 2026-10-08

- S7 remains the sole ACTIVE stage; S8–S11 remain NOT STARTED. The normal
  metadata archive read previously discarded its complete-container equivalence
  and native file identity. It now saves those together in the existing bounded
  historical byte-observation journal after native read closure and current
  Drive binding revalidation. It makes no additional ROM-body request and does
  not create a transfer, installation, target owner or removal intent.
- The regression failed on missing persisted evidence before implementation.
  The complete directly affected Drive runtime test file passes, including
  cancellation/disconnect joining a held journal write, journal failure, cloud
  version change, container mismatch and mapped archive profiles. Scoped Dart
  analysis and whitespace checks pass. One test workload ran at a time.
- Native debug assembly is requested through the shared build-gate launcher,
  live tool session 81299 / FIFO ticket 387. The last observed state is queued;
  gate acquisition, effective resource profile and build completion are NOT yet
  claimed. Retain and wait on that same session; do not relaunch the build.
- This is an enabling boundary, not delivered single-card/local-first behavior.
  Current read-only local-copy validation, cache/selection/favorite continuity
  and native emulator handoff remain required S7 integration. No new APK was
  installed, no owner files changed and no stage closed. The Thor app remains
  alive; both physical displays are confirmed OFF and power Asleep.

### S7 availability lifecycle fixes — host verified, 2026-10-08

- The full objective is not complete: S0–S6 remain COMPLETE, S7 is the sole
  ACTIVE stage, and S8–S11 remain NOT STARTED. Required single-identity integration,
  completed fresh coverage and reviewed migration remain ordinary unfinished S7
  work; neither this patch nor the dashboard closes those criteria.
- Normal same-job Resume initially failed with a typed Drive authorization
  exception. Sources reported `interactionRequired`. Reconnected the already
  authorized default account through its normal chooser without saving/changing
  source folders. Job 76 then advanced from 6,131 to 6,135 lookups, pending
  38,078 to 38,074. Full configuration SHA-256 remains
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  Power reports Asleep and both physical displays committed OFF while the worker
  continues. This proves resumption, not completion of the collection pass.
- Traced local/cloud source loss to the exact-object cache upsert used by remote
  failure fallback. A source-less local observation now leaves an existing
  sourced exact row unchanged, retaining its newer cloud version/rename, source,
  artwork and stable selection key. A real SQLite regression failed on lost
  download availability before the fix; it now verifies byte-for-byte cache and
  immutable refresh-item preservation, no query invalidation, later remote
  enrichment and subsequent authoritative remote updates.
- Traced missing owned leaves to a difference between ordinary and bulk local
  scans: the ordinary path supplemented journal-verified leaves hidden below a
  protected containing directory; the bulk path did not. Both now use the same
  existing supplement. The bounded regression failed for the bulk path before
  the fix and now verifies one exact merged identity and offline path resolution
  from either scanner. Unmanaged namesakes are not automatically merged/adopted.
- Focused database, installation visibility, ROM path, merge, exact-runtime and
  console-controller checks pass; scoped Dart analysis and whitespace checks
  pass. One test workload ran at a time. A first reproduction was stopped after
  identifying that its fixture would enumerate the host Temp parent; only that
  invocation's confirmed process tree was stopped. The corrected fixture uses
  an isolated parent. Its identified interrupted five-byte fixture and empty
  directory were reviewed and removed through cleanup transaction
  `736dfdb91fa20cdc133526fada07ea79`; absence was checked. No surviving test worker
  or full-suite run is claimed.
- These are host-verified source changes only. No new Gradle invocation, APK
  installation, device ROM/save/BIOS removal, ownership adoption, legacy-sync
  change or release occurred for this patch. Native deployment and wider
  single-identity/migration acceptance remain open in S7.

### S7 console dashboard and readable library cards — verified, 2026-10-08

- The global Library landing view is now a console dashboard instead of an
  unbounded ROM grid. Direct console tabs scope browsing, Installed, Favorites,
  shelves, search and metadata ranking; platform scope is applied before Top-N.
  Explicit global search/filtered shortlists remain available. Last console and
  per-console filters persist without inheriting conflicting global filters.
- Each console summarizes cached catalogue entries, installed entries,
  downloadable entries, favorites, known source bytes and verified managed local
  bytes. Unknown source sizes remain explicit. These are not canonical game
  counts or whole-SD usage: unmanaged files, saves and BIOS are excluded from
  managed bytes. Existing Installed-tab deduplication can produce a smaller
  browsing count than the dashboard's installed catalogue-entry count; stable
  single local/cloud identity remains unfinished S7 work, not claimed fixed.
- Shared covers have readable captions and local-first SD/cloud indicators.
  Header layout participates in normal flow rather than overlapping the cards.
  Metadata reload preserves current search/focus instead of replaying the index
  saved on an earlier route visit. Dashboard rows size naturally for larger text.
- Focused SQLite/widget checks pass for cached/unknown storage accounting,
  console-first Top-N, default dashboard, persistent scope, search/reload,
  Installed/Favorites/shelves, controller navigation and resolved covers. All six
  locales pass narrow large-text dashboard checks. Shared cover layout/rating
  golden and media-fallback checks pass on unchanged card code. Scoped analysis
  and whitespace checks pass. No full-suite run was needed for this bounded slice.
- Normal Thor checks prove the default dashboard with 25 cached consoles, touch
  opening a console, D-pad Up/Right/A switching FDS to Game & Watch, scoped ROM
  cards and Back returning to the dashboard. Storage metrics remain accessible
  by scrolling. Native captures are retained privately under
  `D:/Temp/rshop-library-card-20261008/`; no catalogue payload is committed.
- Gated normal debug assembly ticket 379 exited zero. The shared mutex launcher
  retained the gate through completion; observed workers=2, parallel=false and
  Gradle heap=3,221,225,472 bytes, with required metaspace/code-cache arguments
  retained. Kotlin 2.2.20 uses in-process compilation, sharing that heap. Test
  configuration reports one fork/512 MiB (assembly does not execute tests).
  App JNI pools remain depth one; dependency-native concurrency is not verified.
  No memory failure or budget increase occurred. Log:
  `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/2f538809c80244fa9be6f9e667a5bc20.log`.
- APK SHA-256 is
  `99071143d131a0311868714bf9af802c15ad01304e93f8ec5ff45e9505da3986`;
  package/version remain `com.darkaxt.rshop.debug`, 1.7.0/12. Signer digest
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`
  is unchanged, and preserving `install -r` succeeds. Full configuration digest
  remains unchanged after navigation. The saved metadata job was already paused
  before this update; no new capture, mapping Save or resumed scrape is claimed.
  The prior external read-only audit helper was killed twice after the earlier
  card update; it was not retried here and no new full capture-digest proof is
  claimed. Both physical displays are confirmed committed OFF, power Asleep.
- This closes only the bounded dashboard/card/navigation slice. S7 is still sole
  ACTIVE; single game identity, fresh coverage and migration gates remain open.
  No owner ROM/save/BIOS removal, legacy-sync change or external release occurred.

### S7 navigated metadata settings — verified, 2026-10-08

- Replaced the single long form with persistent left-hand ScreenScraper, IGDB,
  shared-storage and ES-DE sections. Provider overview opens a secure credential
  editor or its scraping workspace; the workspace retains scope, saved jobs,
  pause/resume/retry, coverage, preview and quota reporting. All six supported
  languages include the new navigation labels. No provider credentials are
  prepopulated into the editor or exported.
- Focused widget checks pass for touch/controller navigation, initial section
  focus, modal/workspace Back, invalid/save/cancel credential editing, saved-job
  selection, running-job preservation across section changes, compact layout
  and larger text. Updated layout goldens pass normal comparison. Exact-edition
  detail checks pass at landscape and portrait sizes. Scoped analysis reports
  no issues. The updated instrumentation navigation is analyzed but not executed
  as an instrumentation suite; real normal-app checks below are separate proof.
- First normal native build exposed missing initial controller focus despite
  working touch navigation. A failing initial-focus regression preceded the fix.
  Final normal Thor build proves Down/A selects IGDB without touching the menu,
  Up/A returns to ScreenScraper, B closes the credential dialog, and B returns
  from scraping to the overview. Shared storage and ES-DE have separate pages.
  Native evidence: `D:/Temp/rshop-metadata-menu-20261008/final-overview.png`.
- Signer-preserving `install -r` succeeds for the unchanged debug package/version.
  Final APK SHA-256:
  `85e99333188a565cbaeb9aa8f0c8d6d3103e27aff343339f42774ded3bc7f4b1`.
  Before normal Resume, a bounded READONLY audit confirms all 44,204 job-76
  members and the same ordered capture/request/outcome digest recorded below.
  Full configuration digest is unchanged after navigation and normal default
  Google-account reconnection; no source Save or mapping change was performed.
  The audit helper exits and its exact device scratch JAR is removed.
- First Resume correctly paused on Drive interactionRequired instead of
  claiming progress. Normal Connect with the existing default account succeeds;
  the same job then advances from requested=5,939/pending=38,283 to
  requested=5,947/pending=38,275, Running. The live quota reports 19,950 of 20,000
  attempts remaining at this observation; this is not an unlimited-quota claim.
  Both physical displays are confirmed committed OFF and power state Asleep.
  Running-workspace evidence: `D:/Temp/rshop-metadata-menu-20261008/final-running.png`.
- Final debug build ticket 376 acquires `Local\Darka.AndroidGradleBuildGate`.
  Observed workers=2, parallel=false, Gradle heap=3,221,225,472 bytes; Kotlin
  2.2.20 is in-process and shares that heap. Required metaspace/code-cache JVM
  arguments are retained. Test tasks configure one fork/512 MiB, but assembly
  does not execute them. App JNI compile/link pools are depth one; dependency
  native concurrency is not independently verified. No memory failure or budget
  increase. Build log:
  `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/803aa0b399f4446bbe58081db4f2c095.log`.
- Verification discipline: an overlapping host-test launch was mistakenly
  attempted while a previous golden run was alive; Flutter rejected it on the
  locked native SQLite library before tests started. Subsequent workloads were
  launched only after the prior process exited. Final focused tests and both
  normal native builds exited successfully; no memory-exhaustion event occurred.
  Superseded golden failure images were reviewed and transactionally removed;
  accepted goldens and native evidence are retained. No owner files were deleted.
- This closes only the settings-navigation slice. Readable library captions,
  one stable local/cloud identity and availability icons remain current S7 work,
  alongside fresh metadata coverage and migration gates. S7 remains sole ACTIVE;
  S8-S11 remain NOT STARTED. No release, SD migration or legacy-sync change.

### S7 patch-resource game eligibility — verified, 2026-10-08

- A fixed READONLY helper at a joined normal Pause traces 66 Mega Drive
  invalid-response items to 32-byte palette `.bin` files in Patches/source-code
  descendants and two SNES items to tiny HINTS ZIPs under Patches. The remaining
  failed translated NES ROM is a genuine game and is not excluded.
- DriveProvider now resolves published folder ancestry after all pages and
  excludes descendant Patches resources only from the mapped game projection.
  The raw source snapshot remains intact. Real SQLite regression-first tests
  cover paging, numeric ROMs, T-Eng, slash-containing folder labels and explicit
  mappings inside the resource tree. The affected provider checks and analysis
  pass. The saved-job regression also verifies deletion before/during lookup:
  membership/request stay intact, status becomes identityChanged, and a removed
  object is not queried. No full suite or bulk ROM download was run.
- Preserving debug update retains the existing package/signing identity. APK
  SHA-256 is `14ced62caead499af38012f8624dc6fe3b9fd427532a571d0bbea67ec5f0297d`.
  Normal startup reconciliation finishes. The Mega Drive cache changes from
  2,860 to 1,010 file rows; all 66 palette items and both SNES hint items are
  absent, while the genuine NES translation remains. Cache rows include local
  and remote copies; 1,010 is NOT a canonical game count.
- Before/after, saved job 76 has exactly 44,204 captured items and identical
  ordered edition/request/status SHA-256
  `7e4171ffe008d7281c679fac9982ab14eb09d6355a4b974519064a5694975d03`.
  Full configuration SHA-256 remains
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  The bounded helper exits and device scratch is removed before normal Resume.
- Gradle ticket 374 acquires Local\Darka.AndroidGradleBuildGate and the debug
  build succeeds. Observed workers=2, parallel=false, heap=3,221,225,472 bytes;
  Kotlin 2.2.20 uses the project's in-process setting. Test tasks are configured
  for one fork/512 MiB but were not executed by assembly. App JNI uses a shared
  depth-one compile/link pool; the supervisor does not verify every dependency's
  native concurrency. No memory failure or budget increase. Log:
  `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/68f5a0a1f1214814a740d92e3c2e7516.log`.
  The first gated attempt failed because an unquoted PowerShell target argument
  was split into a `.dart` task, not because of memory; it exited before retry.
- This fixes catalogue eligibility only. The native view separately exposes
  duplicated local/Drive entries and 7–9 logical-pixel unselected titles. The
  user now requires one stable game identity with local-first/cloud-fallback
  availability and an SD/cloud cover icon, not two selectable copies. That is
  current S7 integration work; do not claim it fixed by this resource patch.
  Full fresh metadata, defensible retention and reviewed migration remain
  unfinished. S7 alone stays ACTIVE; no owner ROM/cloud/save/BIOS or legacy sync
  was modified and no release occurred.

### S7 Wii RVZ native recovery — verified, 2026-10-08

- Used the unchanged installed debug APK, independently rechecked SHA-256
  `e86c6224b3a9a2123535cd7acddfdc23104518b0f1f92b768e4c56adf56aed6e`.
  No build, installation, provider-credential change or production-code edit was
  needed. The existing GC/Wii exact owned URI and explicit Dolphin package read
  grant serve the real Wii route without a broader permission or alternate engine.
- Normal native workflow: select an isolated destination in Console Settings ->
  exact Drive download -> committed installation -> matching original SHA-256 ->
  Dolphin rendering Wii/game startup screens -> normal Exit -> background-only
  process reclamation after Exit -> confirmed no Dolphin process and no active
  default network -> fresh offline launch reaching the game's profile screen ->
  normal Exit -> restore Wi-Fi -> normal owned removal -> exact file absent while
  its remote entry/cover/basic attributes remain -> normal identical re-download
  -> committed installation -> restored copy reaches the same profile screen.
  This is boot/profile-screen proof, not gameplay, save creation or all Wii formats.
  The sample has no freshly scraped rating/synopsis; this proof does not claim one.
- Both completed copies and the unchanged original are 235,528,788 bytes with
  identical SHA-256. Full size alone was not treated as completion: publication
  was allowed to finish, and normal UI reported Complete before each handoff.
  Advancing native read/write counters verified work during publication; no
  transfer was restarted or declared failed because observation took time.
- Normal final owned removal deletes only the isolated test copy. Normal Settings
  saves the original Wii destination and restores the complete configuration hash
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  The reviewed empty isolated directory is removed and confirmed absent. The
  original ROM and the previously recorded existing GC save hashes still match;
  Wii controller and graphics configuration hashes match their pre-test values.
- Emulator-state qualification: normal first Wii boot initializes NAND runtime
  files and adds a generated WirelessMac line to Dolphin.ini. Hashing the current
  config with only that line omitted exactly reproduces the recorded baseline;
  all other config bytes are unchanged. The selected game's save-data directory
  is empty. No profile/gameplay/save action or manual emulator-setting change was
  performed. NAND aggregate hashes differ, so whole-NAND byte preservation is
  NOT claimed. Leave the emulator's valid runtime initialization intact rather
  than delete or overwrite system/NAND files to manufacture a matching hash.
- Same saved metadata job pauses cleanly at requested=5,907/pending=38,314 and
  resumes normally after restoration: requested=5,910/pending=38,311, Running.
  No recapture or external DB observer. Both physical displays are committed OFF
  and wakefulness is Asleep. Device screenshot scratch is absent; required native
  captures remain private in `D:/Temp/rshop-s7-wii-proof-20261007`, not in Git.
- Wii RVZ recovery is verified separately from GC. S7 remains the sole ACTIVE
  stage: full fresh coverage, defensible Top-25 retention, other required format
  recovery, current cloud checks and reviewed migration remain unfinished.
  S8-S11 remain NOT STARTED. No original ROM/cloud object was removed or changed;
  no save/BIOS was manually edited or removed. Legacy sync and archival profiles
  remain untouched; no release occurred.

### S7 GC RVZ / Dolphin read-grant lifetime — verified, 2026-10-07

- Normal owned RVZ download completed with matching original bytes, but installed
  Dolphin 2606 (42796) rejected the URI as nonexistent. The upstream 2606
  [StartupHandler](https://github.com/dolphin-emu/dolphin/blob/2606/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/StartupHandler.kt)
  and [EmulationActivity](https://github.com/dolphin-emu/dolphin/blob/2606/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/activities/EmulationActivity.kt)
  finish the exported launcher before boot. Its intent-owned grant expires there;
  [ContentHandler](https://github.com/dolphin-emu/dolphin/blob/2606/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/utils/ContentHandler.java)
  already supports R-Shop's original URI/query shape. Only explicit Dolphin
  package permission changes: exact preflight-validated URI, read only, no
  prefix/tree/write/persistable grant. Provider ownership/publication/object
  checks and other emulator handoffs are unchanged.
- The host wiring regression fails without the explicit grant and passes with
  it; affected Dart handoff contracts and scoped analysis pass. This is wiring
  protection, not a simulated Android lifecycle test. Fresh native grant-path
  tests pass, and the real emulator proof below verifies the external boundary.
  No full suite was run.
- Gated focused native test/debug assembly succeeds, gate_acquired=true, FIFO
  ticket 354. Observed workers=2, parallel=false, Gradle maximum heap=3,221,225,472
  bytes. Kotlin 2.2.20 is configured in-process; native Kotlin compilation ran.
  The executed test task is configured one fork/512 MiB. Inspected app JNI Ninja
  rules use a shared depth-one compile/link pool for each of three ABIs. No memory
  failure or heap increase. Log:
  `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/71e00b2ccf7d4933a4677f9d5d19e3b9.log`.
- Preserving debug update succeeds with unchanged signer
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Independently matched host/installed APK SHA-256:
  `e86c6224b3a9a2123535cd7acddfdc23104518b0f1f92b768e4c56adf56aed6e`.
  Isolated-target configuration is unchanged across installation; no app-data
  reset or source remapping. The earlier failed boot left Dolphin unresponsive;
  Android's offered Close app ended that failed session before the new proof.
- Normal native proof: exact Drive queue -> complete standalone GC RVZ -> online
  title rendering -> normal Exit -> background-only Dolphin process reclamation
  after Exit -> confirmed no process/no active default network -> fresh offline
  title rendering -> normal Exit -> owned removal/absent exact test file with
  remote entry and metadata retained -> default-account reconnect -> same queued
  Resume -> completed identical SHA-256 bytes -> restored title rendering.
  No gameplay/save operation, URI-shape change, folder grant or cloud write.
- Wi-Fi is restored; the device has no phone service, so attempted mobile-data
  disable reports unsupported and its original setting remains unchanged. Normal
  final owned removal cleans the test copy. Normal Console Settings restores
  complete config SHA-256
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  Original ROM and existing save hashes match; Dolphin.ini, GCPadNew.ini and
  GFX.ini match their baselines. The empty isolated destination is removed.
  Online/offline/removed/restored captures remain private under
  `D:/Temp/rshop-s7-gc-proof-20261007`, not in Git.
- Same saved metadata job resumes normally: requested lookups 5,817 -> 5,819,
  pending 38,403 -> 38,401, Running. No external DB observer runs beside it.
  Both displays are committed OFF; wakefulness Asleep. Reviewed cleanup ticket
  `32f41c901862d72b5aeb3db4eace81ff2142bc62d1f4bb76c01c50e1fda024d0`
  removes only the expendable scratch capture (11,235 bytes), no errors.
- This verifies GC RVZ recovery only. S7 remains the sole ACTIVE stage, with Wii
  and other required formats, full fresh coverage, defensible retention/current
  cloud gates and reviewed migration unfinished. S8-S11 remain NOT STARTED;
  CACHE-01 controls/automatic rotation and SAVE-01 replacement are not claimed.

### S7 NDS catalogue-title discovery — verified continuation, 2026-10-07

- A bounded audit reproduced numbered NDS catalogue titles being sent literally
  to both title-discovery adapters. Real ScreenScraper queries for two captured
  names returned no usable game; omitting the listing ordinal returned candidates.
  The shared derivation now omits only the observed four-digit or `z`/three-digit
  prefix followed by ` - ` on NDS. Original request JSON, raw-ROM names and
  identities remain unchanged. Qualified match provenance retains the original
  title plus the derived search/method; ownership and IGDB corroboration use the
  same derivation. Other consoles and meaningful game numbers are unchanged.
- Regression-first adapter and normal persistent worker checks pass, including
  unknown/Hack/T-Eng review gates, exact-region official publication, immutable
  captures, rating ownership, subsequent current corroboration and no completed
  job replay. Focused affected provider/request and rating-store checks plus
  scoped analysis pass serially. An old SNES advisory fixture failed with and
  without this fix because SNES now has an assessed community basis; its support
  was corrected to 19 votes, below the existing floor, without changing policy.
  No full suite was run.
- Bounded real ScreenScraper checks for three public numbered NDS titles pass:
  two produce reviewable candidates and one remains ambiguous. No metadata record,
  official classification or score is fabricated. This is live host-provider proof,
  not full native collection coverage or permission to promote unknown editions.
- Shared-gate debug assembly succeeded with actual gate acquisition, FIFO ticket
  349. Observed workers=2, parallel=false and Gradle heap=3,221,225,472 bytes.
  Kotlin 2.2.20 is configured in-process; compile tasks were up-to-date. Test task
  settings are one fork/512 MiB (not executed by assembly); current app JNI compile
  and link pools have depth one for all three ABIs. No memory failure or heap
  increase occurred. Log: `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/22b09f74dea4463da22830a63e381131.log`.
- Signer-preserving debug install succeeded. Host/installed APK SHA-256 is
  `31478c76a3fcf4c870f9c16ee4b194a65fcdcdf93d4e2ca3ac6b821b57bbd03a`;
  configuration remains `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  Hotel captive-portal expiry caused microG's real NoRouteToHostException during
  reconnect; normal network sign-in restored VALIDATED internet, then normal
  default-account reconnect succeeded. No credentials/source/settings were replaced.
- The SAME saved job advanced requested=5,564 -> 5,610. Normal Pause joined cleanly;
  fixed bounded READONLY diagnostics confirm Paused and exactly 44,204 members,
  pending=38,610. Two newly processed numbered NDS entries retain their captured
  names and genuinely remain unmatched; native positive-candidate publication is
  not claimed from them. Native Resume follows diagnostic completion/removal
  and advances requested=5,652/pending=38,568, Running.
  No external database reader remains beside the writer. Both physical displays
  are committed OFF and wakefulness is Asleep.
- The exact temporary device diagnostic JAR is removed and confirmed absent.
  Reviewed cleanup ticket `33a71d48b9b3a0313af26fd7e624bff88b1ea48b9ad520196a774cc6210e1c1d`
  removed only expendable compiler output (4,722 bytes), without errors. Private
  diagnostic source/JAR and required build evidence remain for further verification.
  S7 remains the sole ACTIVE stage: full coverage, defensible retention, required
  format/cloud recovery and reviewed migration are unfinished. S8-S11 remain
  NOT STARTED; no ROM/save/BIOS removal, legacy-sync action or release occurred.

### Authorized managed-cache/settings scope — 2026-10-07

- Specification revision 13 records the user's explicit requirement for managed
  ROM persistence/rotation and Settings controls for duration, rotation queue and
  unified versus per-console scope. It supersedes the former no-automatic-eviction
  rule only within CACHE-01, preserving ownership/cloud recovery, pins/offline
  sample and saves. Configuration must distinguish time expiry from independent
  capacity rotation, show effective scope and support console overrides.
- S11 — Configurable managed ROM cache: NOT STARTED. Satisfied: requirement and
  acceptance mapping only. Remaining: production configuration/UI, policy/lifecycle
  integration, protection/usage tracking, durable exact automatic removal,
  focused verification and real Thor rotation/restore in both scope modes.
  No external blocker has been established; this is ordinary future-stage work.
- Tracked deferral CACHE-01 belongs explicitly to S11 after S10, with final focused
  policy/settings and native expiry/capacity/restore proof recorded in the plan.
  Current S7 one-time migration and recovery criteria do not depend on it and are
  unchanged. S7 remains the sole ACTIVE stage; S8-S11 are NOT STARTED. No settings
  control, eviction behavior, new deployment or SD cleanup is claimed here.
- Fresh document verification confirms one owner for every authoritative
  requirement, CACHE-01 mapped to S11, no obsolete unconditional eviction ban,
  resolving local Markdown links and clean Git whitespace checks. This is
  specification/plan verification only; no Gradle build or native cache test was
  run for this documentation change.

### S7 metadata Pause cancellation — verified continuation, 2026-10-07

- Normal Pause exposed a Drive API cancellation from the exact artifact
  revalidation inside local archive identification. The owning job persisted
  Paused but rethrew the exception, so both operation and Pause reported failure.
  The identifier boundary now translates only typed Drive API/transfer cancellation
  paired with that job's actual cancellation signal into its existing internal
  cancelled outcome. Read draining, durable pending work, immutable membership
  and atomic evidence publication are unchanged; unrelated errors are not hidden.
- Regression-first reproduction failed for both archive and header API/transfer
  cancellation. The changed tests and affected catalogue/job/runtime checks now
  pass serially, including pending-item preservation, same-job resume, actual
  drain joining and cancellation/error races. Unsignalled cancellation, denied
  access, source change, unavailable transport and malformed data remain errors.
  Focused controller Pause/error checks and scoped analysis also pass. No full
  repository suite was run; the existing bounded 30,000-edition job check reported
  a 241,610,752-byte RSS peak, not a whole-library ROM allocation.
- Gated debug assembly succeeded under actual gate acquisition (FIFO ticket 343;
  `Local\\Darka.AndroidGradleBuildGate`), with observed two workers, parallel=false
  and 3,221,225,472-byte Gradle heap. Kotlin 2.2.20 is configured in-process within
  that budget; its compile tasks were up-to-date. Configured test tasks report
  one fork/512 MiB (not executed by assembly).
  Current generated app JNI Ninja compile/link rules use the shared depth-one
  pool for all three ABIs. No memory-related failure or heap increase occurred.
  Build log: `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/c021ded84e6248d1910f837ab3b66c9f.log`.
- Preserving `adb install -r` retained the existing debug signer
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Host and installed APK SHA-256 both equal
  `21ee62b1579be65f85ebf2694b7147b023adf3cc48eca316e48ff0338aaeeba6`.
  No uninstall, data reset, manual database change or source creation occurred.
  Normal reconnect selected the already-authorized default account; Resume's
  genuine missing-grant error before reconnect remained visible, as required.
- Native controls: the SAME saved job advanced from requested=5,381 to 5,386,
  then Pause joined cleanly at requested=5,392/pending=38,825 without an operation
  error. A fixed bounded READONLY aggregate while paused confirms job 76 remains
  Paused with exactly 44,204 items. Resume then advances requested=5,400 and
  pending=38,817, Running, matched=130/rated=125. These are ordinary native
  control/progress observations; the exact typed cancellation branch and error
  races are proved by host regressions, not inferred from native timing.
- The read-only diagnostic process completed before Resume, and its exact
  temporary device JAR was removed and confirmed absent. The configuration hash
  remains `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`;
  both physical displays are committed OFF and wakefulness is Asleep. The same
  job continues; no ROM/save/BIOS/settings cleanup or cloud mutation occurred.
  This closes the Pause defect only. S7 remains ACTIVE with full fresh coverage,
  defensible retention and reviewed migration unfinished; S8-S11 are NOT STARTED.

### S7 standalone WUA recovery — verified continuation, 2026-10-07

- The required cold-offline route was observed with no Cemu process before
  launch and no active default network before/during execution. Installed Cemu
  rendered the game's credits through the exact read-only owned WUA document.
  This proves game rendering, not a gameplay session. Wi-Fi was restored before
  recovery. Normal Cemu Exit returned to R-Shop and its emulation process exited;
  the earlier transient ANR/delayed exit was not worked around with a force-stop.
- Normal owned removal left the remote entry available with DOWNLOAD. The same
  queued re-download resumed after normal default-account reconnect and completed
  at 63,106,846 bytes. Its SHA-256 again equals
  `4432be0aa9d9528274f794d9db7ed9d707549aec54e2dba669eb86ede8b67981`,
  identical to both the first download and untouched original. R-Shop reported
  INSTALLED, and normal Open in Cemu launched a fresh emulation process which
  rendered the restored copy's credits. Normal Exit completed before cleanup.
- Only the isolated owned test ROM was then removed through R-Shop. After the
  normal console-settings save completed, the Wii U target was restored to
  `/storage/75D7-DC5F/Roms/wiiu` and the full configuration hash again equals
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  The original ROM retains the hash above. Cemu settings/controller hashes remain
  `84efa61a16c0fa4752984943c938ed65daf05e735592ad05b46d7f60a3d9b2f3` and
  `a69d6add585e7ddff92c9259085749c727956049aa2f939975078b9f2744af7c`.
  No save, BIOS, emulator configuration or cloud original was removed.
- The empty exact test directory was removed with non-recursive rmdir and
  confirmed absent. The device scratch capture and reviewed host `screen.png`
  were removed; cleanup ticket `725e68fac2a7a532edb92c4267aa0f52e1f815344522bf9b5adae401bb04efca`
  applied its sole 1,126,604-byte candidate without errors. Required private
  online/offline/removal/restored captures and the installed APK are retained.
- Resume of the SAME saved scrape 76 now advances actual counters from
  requested=5,263/pending=38,954 to requested=5,283/pending=38,934, Running,
  matched=124/rated=120. No new job/source selection was created and no external
  database reader runs alongside the writer. Both displays are committed OFF
  with wakefulness Asleep. Full collection coverage, defensible Top-25,
  remaining required format recovery and reviewed migration still remain open
  in the sole ACTIVE S7. S8-S11 remain NOT STARTED; no automatic cache policy,
  legacy sync retirement, full migration or public release is claimed.
- Current production/test code is unchanged from the focused passing launcher
  and native grant verification/builds below; the final APK hash was rechecked,
  the native JUnit report inspected with zero failures/errors/skips, and the
  complete diff reviewed. Those current-task results remain applicable; no
  duplicate Gradle command or broad test suite was launched to repeat them.

### S7 standalone WUA recovery — earlier checkpoint, 2026-10-07

- The normal owned-installation route now supports standalone Wii U WUA through
  installed Cemu's exported VIEW activity and the existing exact document-leaf
  provider. Ownership/current identity checks remain mandatory; bundles, archive
  mappings and other Wii U formats are rejected. The details menu now names Cemu
  rather than Dolphin. No conversion or emulator configuration change was added.
- The directly affected Dart launcher contract reproduced the missing route
  before implementation and passes afterwards. Scoped analysis and focused native
  `OwnedRomGrantPathTest` pass; diff checks pass. Initial gated native test/build
  used ticket 322, log `e0378d765c554b5a96db13bd1c36c5a3.log`. The required
  subsequent label build used ticket 324, log
  `70ac50aa34af4fa5887f079203846de9.log`, and succeeded. Both were supervised
  through the shared build gate. Observed workers=2, parallel=false and Gradle
  maximum heap=3,221,225,472 bytes; Kotlin 2.2.20 uses the assessed in-process
  strategy. Test configuration is one fork/512 MiB; only the initial focused test
  command executed tests. App JNI compile/link pool depth remains one. No memory
  failure or budget increase occurred.
- Signer-preserving `install -r` succeeded; final host/installed APK SHA-256 is
  `e93b4ab48ab28fa9e3a573b9feceb124acd248c1ec70fc9475f32f069ece07a9`.
  Normal default-account reconnect was needed after the first update, without
  saving/replacing a source. A real queue download completed into the newly
  created isolated SD destination `RShop-Wua-Proof-20261007`. Its 63,106,846-byte
  WUA SHA-256 is
  `4432be0aa9d9528274f794d9db7ed9d707549aec54e2dba669eb86ede8b67981`.
  The original Wii U ROM directory was not modified. The temporary Wii U target
  remains selected for the unfinished recovery proof and MUST be restored to
  `/storage/75D7-DC5F/Roms/wiiu` after that proof.
- Normal "Open in Cemu" reached installed 0.5.2's EmulationActivity and rendered
  the game's credits sequence. Android observed the exact owned WUA document URI
  with mode/owned=0x1 and global/persistable/persisted=0x0. Existing unrelated Cemu
  tree grants were not changed. Private online evidence is retained under
  `D:/Temp/rshop-s7-wua-proof-20261007`. Normal Cemu Exit briefly produced an ANR
  window; it subsequently returned to R-Shop and the emulation process exited
  without force-stop. This is not an offline/recovery success claim: cold offline
  launch, normal owned removal, identical re-download, isolated cleanup and target
  restoration remain unfinished.
- Saved scrape 76 remained at requested=5,263/pending=38,954, matched=123/rated=119.
  Post-update Resume briefly reported Running then returned Paused without counter
  progress; resolve that boundary before claiming scraping resumed. S7 alone is
  ACTIVE, S8-S10 NOT STARTED. Legacy device sync and the scheduled task invoking
  `sync-retrobat-saves.ps1` remain untouched, conditional on verified S10 handover.

### S7 large-console retention audit — 2026-10-07

- A regression reproduced the audit's incorrect 2,000-member ceiling against
  the already-supported larger console catalogues. Retention observation now
  validates 128-row pages through the existing 100,000-member census bound,
  retaining only exact artifact keys associated with inspected SD candidates.
  Duplicate identities and summary drift still reject the entire observation,
  including discarded rows. Observed identity and retained-binding byte budgets
  are each 16 MiB; individual pages remain capped at 1 MiB. No ranking, ownership,
  download or removal policy changed.
- Focused host contracts pass, including 2,049-member paging, a 16,384-member
  scope retaining only three requested bindings, invalid/duplicate/drifting
  observations and byte bounds. The SQL-equivalence verifier was repaired to
  select the previously factored production retention method and instantiate
  its explicit normal-page branch; SQL tokens remain identical to the fixed
  native observer. Diff checks pass. No full suite or Gradle build was needed.
- Fresh javac and D8 compilation each used an explicit 128 MiB heap. The unique
  prepared native helper's host/device SHA-256 both equal
  `59e3c775d1a34a258fe87ce3e8d0fdc25806cbc8ed62fe9a92bd8e7a9fde3e4a`.
  Native observation uses `app_process -Xmx128m`. After normal Pause joined
  scrape 76 at requested=5,129/pending=39,088, offset 2,048 returned 128 members
  and a complete 10,100-member NES traversal terminated successfully. This
  summary-only proof retained zero bindings deliberately; it is not an SD
  keep/remove manifest or execution proof. Actual summary: 10,100 canonical
  groups/members, zero ranked/unbound artifacts, 216 dirty editions and ten dirty
  artifacts. Incomplete/dirty ranking remains unusable for removal planning.
  A mid-traversal host process observation was 22,306,816-byte working set;
  that is a diagnostic sample, not a measured peak or universal memory bound.
- Configuration SHA-256 remains
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  Normal Resume advanced the SAME immutable job to requested=5,132/pending=39,085
  with Running status; it was not recreated. No external SQLite reader remains
  alongside the writer. Both displays were confirmed committed OFF afterwards,
  with wakefulness Asleep. The unique
  device helper is retained for the next exact inspected-cohort audit; expendable
  host compiler outputs were removed by reviewed cleanup ticket (11,705 bytes,
  no residuals; they are reproducible, not backups). No ROM/save,
  cloud or legacy sync app/task changes occurred. S7 alone remains ACTIVE;
  complete fresh coverage, defensible retention, current readable cloud copies,
  remaining recovery and reviewed migration execution remain required. S8-S10
  are NOT STARTED. Legacy retirement remains conditional on verified S10.

### S7 exact-artifact retention review — 2026-10-07

- The existing recovery review now binds the full current RemoteArtifact JSON,
  unique exact cache row, canonical rank and console coverage in one owning
  transaction. The shared CTE/policy is unchanged; stale versions, duplicate
  bindings and source/platform namesakes cannot supply a decision. Unresolved
  evidence remains Preserve. This is planning evidence, not removal authority.
- Focused real-SQLite query and recovery-dialog checks pass, covering current
  rank/coverage, stale/duplicate rejection, provisional preservation, rank 25/26
  labels, explicit adoption and joined cancellation. Scoped analysis and diff
  checks pass. No repeated full-suite/resource run was needed for this isolated
  query/UI addition; the unchanged bounded projection evidence above remains
  applicable, not a new native performance guarantee.
- The required debug build passed through the shared gate, FIFO ticket 320,
  log `6c365dcd4cdc4b90b111f53631738e38.log`. Observed workers=2, parallel=false,
  Gradle heap=3,221,225,472 bytes, with required metaspace/code-cache arguments
  preserved. Kotlin 2.2.20 remains in-process (compile was up-to-date), sharing
  that budget. Test task configuration remains one fork/512 MiB, not executed
  Gradle tests in assemble. Current generated arm64 app JNI files verify
  `rshop_native` compile/link pool depth 1; no universal plugin concurrency claim.
  No memory failure or budget increase occurred. Only a confirmed-idle
  incompatible daemon was retired by the supervisor.
- Signer-preserving owner `install -r` succeeded, without reset/uninstall or
  force-stop. Host/installed APK SHA-256 equals
  `6b6170a98a3700523d3e916d12d63cdf9a501c26ecae98061cb4fe5fe86ab890`;
  actual package remains version 12/1.7.0, with unchanged signing certificate.
  Normal Library -> existing PSP filtered game -> Check local/cloud bytes shows
  `Keep · canonical rank 25 (Top 25)` and `35/341 ranked · Provisional`.
  Explicit Refresh returns the same result; normal Back returns to Library.
  The dialog states planning-only/current-execution gates. No byte verification,
  adoption, download or removal action was invoked for this UI check.
- The same saved scrape 76 advanced before the update to requested=4,923,
  matched=116, rated=112, pending=39,294, then was normally paused/joined.
  Initial post-update Resume paused after one lookup at the same silent
  account-acquisition boundary (`DriveAuthorizationException`, authorization
  line 82). Normal Connect/default-account chooser reached Connected without
  saving/replacing the source, then Resume retained the same job/capture.
  After reconnect, the SAME job reached requested=4,943/pending=39,274 with
  Running status (matched=116/rated=112). Both physical displays were then
  confirmed committed OFF and wakefulness Asleep.
- R-Shop and RetroArch configuration hashes remain respectively
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d` and
  `a42f6537446759beeb88ebf53e1c1d0bd037617ef4527c4bc2d19b884c10e54a`.
  S7 remains sole ACTIVE: collection coverage, defensible retained sets, exact
  current readable cloud copies, remaining recovery and reviewed migration
  execution remain required. S8-S10 are NOT STARTED. Original ROMs, saves,
  settings, cloud files and legacy sync app/task remain untouched. The temporary
  UI capture was removed through an exact reviewed cleanup ticket; the verified
  APK is retained. No external release occurred.

### S7 bounded projection writes and native scope check — 2026-10-07

- The normal pre-update NES/SNES Best-25 queries terminated with respectively
  `0/10100` and `0/6514` ranked, zero matching games and explicit Provisional
  coverage. Joined read-only v2 observations confirmed no unbound artifacts or
  pending projection dirt. These owner caches contain no eligible scoped scores;
  positive NES/SNES ranking remains host-verified, not native-proved. No ratings
  were injected or unranked originals removed.
- The global policy rebuild exposed per-edition SQLite bridge writes. A real
  129-edition RED check observed 129 batches; the change sends one batch per
  bounded 128-edition page inside the unchanged enclosing snapshot transaction.
  A second-page failure regression proves rollback preserves the previous full
  policy/projection/facet/dirty snapshot, followed by a successful normal retry.
  Identity, score eligibility, membership and provisional retention are unchanged.
- Focused query, effective-rating and migration checks passed. The old migration
  fixture now changes an actual cache value before expecting its broken legacy
  UPDATE trigger: identical writes intentionally perform no UPDATE. The existing
  resource fixture also needed its normal canonical-group indexing after bulk
  identity seeding; without it, the selector correctly returned zero members.
  Its observer now includes actual batched inserts. Real file-backed 3,000 and
  30,000-game checks pass, with maximum identity/metadata reads of 128 rows,
  no warm-filter projection writes and unchanged Top-25/no-refill semantics.
  The 30,000 projection measured 45,014 ms on the host, warm two queries 860 ms,
  process peak RSS 264,183,808 bytes. These are diagnostics, not native latency
  guarantees or cancellation deadlines. Scoped analysis and diff checks pass.
- The required debug build passed, acquired the shared Gradle gate, and exited
  zero; log `7fa966342ae248f6ad17bce46d67a453.log`. Observed two workers,
  parallel=false and 3,221,225,472-byte Gradle heap; Kotlin 2.2.20 in-process
  shares this budget (Kotlin compile was up-to-date). Test task configuration
  is one fork/512 MiB, not a claim tests executed in assemble. Generated app JNI
  Ninja files under `build/.cxx/debug/334d1i5j` verify compile/link pool
  `rshop_native` with depth 1 per ABI. This is not universal plugin concurrency
  proof. No memory failure or heap increase occurred.
- Signer-preserving `install -r` updated the existing owner debug package without
  reset/uninstall/force-stop. Host and installed APK SHA-256 both equal
  `1984bd54fa2233f11fc7a71ff26db2c48a9e4ea7e4232535f88d77a40fa46202`.
  Actual package version remains 12/1.7.0; numbered build labels are not APK
  versions. Normal NES Library opened on this artifact. A comparable native
  full-policy rebuild latency improvement is not yet claimed.
- The same saved scrape 76 was found paused at requested=4,607, matched=110,
  rated=106, pending=39,609 after `DriveAuthorizationException` at the silent
  account-acquisition boundary. Normal default-account Connect reached Connected;
  mappings were not saved/replaced and the immutable job was not recreated.
  After reconnect, normal Resume advanced the SAME job to requested=4,618,
  pending=39,598 with Running status. Matched=110/rated=106 remain truthful;
  this is resumed progress, not complete scraping. No external SQLite observer
  overlaps the resumed worker. Both physical displays were confirmed OFF.
- R-Shop configuration and RetroArch configuration hashes remain respectively
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d` and
  `a42f6537446759beeb88ebf53e1c1d0bd037617ef4527c4bc2d19b884c10e54a`.
  S7 is sole ACTIVE; complete fresh coverage, defensible retention, current
  readable exact cloud copies, remaining recovery workflows and reviewed
  migration execution remain unfinished. S8-S10 are NOT STARTED. Original
  ROMs/saves/BIOS/cloud files and legacy sync mechanisms remain untouched.

### S7 NES/SNES reception scope — 2026-10-07

- The real serial public benchmark captured ten reviewed original NES/SNES
  releases and compared independent original-platform reception. The recorded
  decision in SCORE_RECEPTION_ASSESSMENT.md extends the existing IGDB game-level
  community basis to these actual S7 collection scopes, retaining known twenty
  votes, actual 0–100 user average, fixed precedence, identity/ownership and
  freshness. Material Castlevania II community disagreement and global James
  Pond scope remain explicit; no blended total, critic fallback, borrowed votes,
  title boost, unknown-count exception or automatic official classification.
- RED reproduced NES/twenty-vote rejection before extension; focused effective
  rating and indexed-query checks passed after it. Fresh real-provider capture
  at 14:33:24–14:33:29 UTC yielded eight supported canonical games from ten
  reviewed public fixtures after closing the network adapter, identical Top-25
  membership and explicitly provisional coverage. A focused real-SQLite policy
  refresh check proves already-cached NES/SNES records are reprojected without
  another scrape and low-vote/provisional retention members remain preserved.
  Its initial fixture used a nonexistent retention `items` getter; that local
  compilation error was corrected to the actual members/disposition API, then
  the check passed. Production retention behavior was not changed. Scoped Dart
  analysis of the changed production and all three changed test files passed
  after that additional query fixture; diff checks passed.
- The waiting-build checkpoint is superseded by the native query and batching
  evidence above. Positive owner NES/SNES ranking is still not native-proved;
  empty provisional coverage must not authorize removal.
- S7 remains the sole ACTIVE stage. Whole-collection fresh coverage, reviewed
  identities and defensible canonical Top-25, current readable exact cloud
  copies, required remaining recovery workflows and reviewed migration execution
  remain unfinished. S8-S10 are NOT STARTED; no original ROM/save/cloud changes,
  legacy sync retirement or external release occurred.

### S7 SNES owned archive recovery — 2026-10-07

- Revision 12's explicit SNES single-member 7z profile is integrated through the
  existing pinned decoder, normal queue/publication, immutable mapping, adoption,
  offline validation, local raw metadata identification and exact read-only
  RetroArch leaf grant. Accept one safe `.sfc`/`.smc` within 16 MiB and preserve
  every raw byte/copier header. Stream/CRC validation is not game identity or
  bootability. ZIP, mixed mappings, untyped transfers and MSU/PCM bundles remain
  rejected; no classification or ranking exception was introduced.
- Regression-first Flutter/native checks reproduced missing support before the
  implementation. Focused serial runtime, metadata-job, emulator-launch,
  transfer, storage and journal checks passed; scoped analysis and diff checks
  passed. Inspected current native decoder/grant XML has zero failures/errors.
  Native metadata publication is not claimed: full fresh coverage remains open.
- Combined gated native tests/debug build 301 passed; log
  `3c1c9548fbac4e6c8342f635b5888b96.log`. The supervisor acquired
  `Local\Darka.AndroidGradleBuildGate`. Observed workers=2, parallel=false,
  Gradle heap=3,221,225,472 bytes. Kotlin 2.2.20 runs in-process in that budget;
  Metaspace 1 GiB/code cache 256 MiB remain. Test-task configuration is one
  fork/512 MiB. Native environment hint is two, but the inspected Ninja command
  lacks explicit `-j`; actual native concurrency is not verified. No memory
  failure or budget increase occurred. Earlier RED build 300 safely waited for
  external activity and retired only a verified-idle incompatible daemon.
- Signer-preserving `install -r` updated the existing debug app without reset,
  uninstall or force-stop. Host and independently inspected installed APK match
  SHA-256 `4a507062f2cae23f464888f7b4ff7f98476f5cfd1453bfd31d7d27a3b1a67997`.
  Missing Snes9x was installed through RetroArch's normal Core Downloader; normal
  running core reports Snes9x 1.63. Other cores/settings were not changed.
- Normal Drive download in a new empty isolated destination reached Complete.
  R-Shop's normal Open in RetroArch actually booted the game online (PID 17099),
  and Start advanced its title menu. Normal Quit ended that process. With Wi-Fi
  disabled and no active default network, normal Open booted the same installation
  in new PID 22487. Private online/offline captures retain actual framebuffer
  proof; gameplay/input beyond the title menu is not claimed. The aftermarket
  proof item does not establish official classification, reception or retention.
- Normal owned Delete emptied the proof directory. Re-download initially failed
  `api_unavailable`: the reconnected hotel network had no validation and system
  logs showed Google DNS failure. Android's normal Fix connectivity action
  established a new validated network; normal Retry then reached Complete with
  identical archive SHA-256. This was not a speculative production patch/retry
  loop. Hotspot diagnostics found the host service disabled; no hotspot, service
  configuration or DNS settings change occurred.
- A second normal owned Delete emptied the isolated directory. Original SNES
  destination was restored through normal folder selection; full configuration
  SHA-256 remains `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  RetroArch configuration retains its fresh baseline
  `a42f6537446759beeb88ebf53e1c1d0bd037617ef4527c4bc2d19b884c10e54a`.
  The exact empty proof directory was removed non-recursively and absence checked.
  Original ROMs/saves/BIOS, cloud files and legacy save sync remain untouched.
- Joined read-only observation before Resume confirms job 76 paused at requested
  3,848 with unchanged 44,204-item capture, active catalogue=1/pending=2/next=3.
  Normal Saved jobs selection and Resume advanced the SAME job to requested
  3,852/pending=40,363. No external SQL observer overlaps the resumed worker.
  Both physical displays are freshly confirmed committed OFF.
- S7 remains sole ACTIVE: complete fresh coverage (including scoped Wii),
  defensible canonical Top-25 sets, current readable cloud-byte proof, remaining
  format/bundle workflows and reviewed migration are unfinished. S8-S10 remain
  NOT STARTED. No external release or legacy-sync retirement is claimed.
- Continuation verification inspected the unchanged production diff, native
  decoder/grant reports and successful gated build log. Fresh serial runtime,
  metadata-job, emulator-launch, transfer-engine and storage tests passed; the
  invocation's only failure was a nonexistent journal-test filename, corrected
  by a separate successful `test/transfer_journal_test.dart` invocation. The
  scoped analysis of all changed Dart sources/tests found no issues. Host and
  freshly resolved installed APK hashes still agree with the recorded artifact.
  The live saved worker still advances: Running, requested=4,070, pending=40,145,
  matched=93/rated=90. No worker restart or external SQL read occurred. Both
  displays subsequently reached committed OFF. Transactional cleanup
  `c18bd725369b9c6ee209fe478fd56a6a` removed only the consumed `screen.png`
  diagnostic (134,573 bytes); online/offline proof captures remain private.

### S7 NES owned archive recovery — 2026-10-07

- Revision 11's explicit single-member NES 7z profile is integrated through the
  existing pinned bounded decoder, normal queue/publication, immutable mapping,
  adoption, offline validation, local metadata identification and exact read-only
  RetroArch leaf grant. Only `.nes`, a 16 MiB raw budget, minimum 16-byte header
  and `NES` signature are accepted; existing complete stream/CRC checks remain.
  No ZIP, SNES, bundle, title-based adoption or ranking exception was added.
- Regression-first host checks reproduced missing NES support before the change.
  Focused serial Flutter runtime/launch/metadata-job/transfer/storage/journal
  checks pass; scoped analysis and whitespace checks pass. Native decoder/grant
  XML reports zero failures/errors. These verify identity binding and rejection
  behavior, not completion of the collection's fresh metadata pass.
- The combined gated native test/debug build passed (log
  `ddaa1712e3f84f9bbe12f0d64c469fd5.log`). The supervisor acquired
  `Local\\Darka.AndroidGradleBuildGate`; observed workers=2, parallel=false,
  Gradle heap=3,221,225,472 bytes. Kotlin 2.2.20 ran in-process in that budget,
  preserving Metaspace 1 GiB/code cache 256 MiB. Test-task configuration was one
  fork/512 MiB. Native environment concurrency hint was two; actual Ninja
  concurrency remains unverified. No memory failure or budget increase occurred.
  The earlier RED invocation waited for confirmed external-build completion.
- Normal signer-preserving install -r updated the existing debug package, without
  uninstall/reset/force-stop. Host and installed APK SHA-256 match
  `7bf5d33b441e9c2c32350626de76fee8ec921bbc356f920e0fe9ecd628b65cd4`.
  FCEUmm was absent and was installed through RetroArch's normal Core Downloader;
  the normal Load Core list confirmed it. Other cores were not updated.
- A new empty isolated destination proved normal Drive download and actual NES
  boot, then cold new-process offline boot with Wi-Fi disabled and no active
  default network. Normal Quit ended the first emulator process; the offline
  boot used a new process. No gameplay-input or collection-retention claim is
  inferred from this prototype/aftermarket proof item.
- Normal owned removal left the isolated directory empty. Normal re-download
  produced identical archive SHA-256; a second owned removal again left it empty.
  The original destination was restored through the folder picker and its empty
  proof directory removed non-recursively. Original ROMs/saves/BIOS were not
  removed. Configuration hash and RetroArch settings hash match their baseline.
- Saved ScreenScraper job 76 remains the same 44,204-item capture. Joined Pause
  held requested=3,781; root state stayed active=1/pending=2/nextGeneration=3.
  Normal Resume actually advanced requested lookups to 3,789. No external SQL
  observer overlaps the resumed worker. Both physical displays are confirmed OFF.
- Online/offline proof captures remain private for diagnosis. S7 remains sole
  ACTIVE: full fresh coverage, defensible canonical Top-25, current complete
  readable cloud-byte proof, remaining format workflows and reviewed migration
  are unfinished. S8-S10 remain NOT STARTED. Legacy save-sync mechanisms remain
  untouched; no external release or retirement is claimed.
- Cleanup transaction `da9363a0fb91e7f03762752032ee2eb9` removed only the reviewed
  disposable 126,606-byte last-screen capture. The online/offline proof images and
  required installed-build evidence remain; no broad temporary-tree cleanup ran.

### S7 identical catalogue-write invalidation — 2026-10-07

- The normal `saveGames` upsert updated identical cached rows and therefore fired
  the membership/projection triggers for the whole console. The production-writer
  regression reproduced this with real SQLite triggers. The same atomic upsert
  now compares NULL-safe effective persisted values before updating, including
  retained artwork/thumbnail values. Actual changes and explicitly authorized
  orphan removal still invalidate their affected entries; no trigger migration,
  timer, new refresh framework or change to publication authority was added.
- The regression failed before the fix and passes afterwards. Focused serial
  database/query/migration/exact-identity checks and scoped analysis pass for the
  current code. These cover retained artwork, real identity changes and orphan
  authority, not just an empty UPDATE count. No full suite was run.
- Gated debug build 283 passed. The supervisor acquired
  `Local\\Darka.AndroidGradleBuildGate`; observed workers=2, parallel=false and
  Gradle heap=3,221,225,472 bytes. Kotlin 2.2.20 uses in-process compilation in
  that budget, retaining Metaspace 1 GiB/code cache 256 MiB. Test-task configuration
  is one fork/512 MiB, not an executed test-JVM claim. Native environment hint is
  two; actual plugin/Ninja concurrency is unverified. No memory failure or budget
  increase occurred. Log: `7138616c8aeb4288ba00747abfae0945.log`.
- The signer-preserving `install -r` update is installed; host and installed APK
  SHA-256 match `769ac73362a4d039d4d0216ae4385cc4352835ca3124fdfc277eab3911de0eaf`.
  Normal Pause joined saved job 76 at requested=3,329 before installation,
  preserving its 44,204-item capture and configuration hash
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
- The old native dirty backlog was cache=7,896 / editions=7,986. The normal Library
  query consumed it; a subsequent fixed read-only aggregate observed both queues
  empty, with cacheRows=46,818 / editions=47,307. One earlier observer process
  returned `Killed` without a result; its cause is not established and no result
  is inferred from it. No SQL observer runs alongside the ongoing refresh.
- Home's explicit GBA Sync started an online refresh of the full source, not the
  original cache-first writer path. Normal Disconnect (not Revoke) drained it;
  the terminal sync reports deliberate cancellation, not success. The retained
  catalogue is active=1/pending=2/nextGeneration=3; the partial refresh checkpoint
  is preserved, not published or discarded. Its identical 207-row local fallback
  also left both dirty queues empty.
- Native normal GBA console opening then completed its cached background write;
  Home's fresh Synced label confirms that path finished. The normal cached
  smart-sync across 13 consoles also finished before read-only observation.
  CacheRows=46,818 / editions=47,307 and both dirty queues remain unchanged at zero,
  rather than re-enqueuing the old 7,896-row GBA snapshot. This verifies the actual
  unchanged-write defect, not an online root-refresh completion or a quantitative
  global-Library latency claim. Configuration, saved job 76 and the original
  RetroArch settings hash remain unchanged.
- Normal default-account Connect reached the connected state again without
  saving/changing any source. Resume of the SAME job 76 advanced actual requested
  lookups from 3,329 to 3,339; no fresh capture or external SQL observer overlaps
  that resumed worker. Both physical displays are freshly confirmed committed OFF.
- Exact cleanup transaction `d4873e3950bd34beca46885e9ae712a4` removed only the
  consumed 2,416-byte diagnostic compiler intermediate; absence is verified.
  Reproducible observer source/jar remain. Old save-sync mechanisms, original
  ROMs/saves/BIOS and cloud files remain untouched. S7 remains sole ACTIVE;
  S8-S10 remain NOT STARTED.

### S7 exact card reads and handheld recovery integration — 2026-10-07

- Exact cached detail/rating/cover reads no longer drain the collection-wide
  ranking/facet dirty queue. A reproducible real-SQLite regression failed for
  all three readers before the change; focused checks now leave unrelated work
  pending and verify that the subsequent collection query still consumes it
  correctly. Current identity and ambiguity checks remain required. This fixes
  card-scoped projection work, not the full Library projection's latency: the
  normal post-update collection query held the database for several minutes
  before finishing. No timeout, restart or speculative global-query fix was used.
- Explicit GBC/GBA single-member 7z mappings reuse the existing pinned decoder,
  complete stream/CRC checks, 16/32 MiB raw budgets and owned read-only leaf
  handoff. Normal queue, typed recovery/adoption/offline validation, wrong-platform
  rejection and launcher fixtures pass. Existing native decoder/grant checks
  also pass. SameBoy and mGBA are the actual installed cores, not inferred from
  information files. No ZIP/bundle or mixed-platform support is claimed.
- Normal isolated Thor workflows verify GBC online boot/input and cold new-process
  offline boot/input; GBA online boot and cold new-process offline boot. Both
  verify owned removal, identical provider-verified re-download and a second
  issue-free removal, with zero remaining proof owners and two completed removal
  records each. GBA input beyond the title/high-score screens was not established;
  button highlighting is not gameplay-input evidence. No original ROM was removed.
- A source-less local cache row in a mixed remote console previously offered
  Download and created a failed queue entry. Download capability now belongs to
  the exact entry in the detail/controller/variant picker. Regression-first queue
  checks and normal detail/picker touch/controller fixtures pass: missing local
  entries are explicitly unavailable, installed local entries remain manageable,
  and Drive entries require their own artifact and respect download denial.
  Native normal GBA search confirms the installed local entry offers Delete and
  the independently identified uninstalled Drive edition offers Download. The
  missing-local rendering/queue case is host-verified, not a native missing-file
  claim. No title-based identity borrowing or automatic adoption was introduced.
- Focused serial Flutter checks cover library query/migration, artwork jobs,
  Drive runtime/transfer and owned emulator handoff, plus detail source eligibility,
  normal detail rendering, variant touch/controller behavior and exact Drive
  identity. Scoped analysis and whitespace checks pass. No full suite was run;
  unchanged checks from this task were retained rather than repeated for commit.
- Final normal debug build 280 succeeded and host/installed APK hashes match:
  `fea752ae0e946f7c8b61b5ae736aa64cca5fdc41f8fe89943f40e8503bab8426`.
  Package/version and signer remain unchanged; installation used install -r,
  without reset/uninstall/force-stop. The shared gate was acquired, with observed
  workers=2, parallel=false and Gradle heap=3,221,225,472 bytes. Kotlin 2.2.20
  runs in-process in that budget; required Metaspace 1 GiB/code cache 256 MiB stay.
  Test-task configuration is one fork/512 MiB, not an executed test-JVM claim.
  Native environment concurrency hint is two; actual plugin/Ninja concurrency
  remains unverified. No memory failure or budget increase occurred. Build log:
  `74a88734c3a7411ba9dc5b7c53ff62fc.log`. Earlier gated build 279 failed from
  PowerShell splitting the unquoted target into a stray `.dart` task; the retry
  quoted the complete argument after confirmed completion, not a memory change.
- Joined post-update observation verifies unchanged full configuration hash
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`,
  seven source objects, original console mappings and active=1/pending=null/
  nextGeneration=2. RetroArch settings retain their baseline hash. Saved job 76
  retains 44,204 items at requested=3,217: matched=74/rated=73, needsReview=997,
  ambiguous=236, unmatched=1,862, invalidResponse=39, pending=40,996.
- The first normal Resume stopped before progress with Drive interactionRequired.
  Normal default-account Connect completed, verified by the connected state and
  disappearance of source authorization errors, without saving/changing a source.
  Resume of the same job then actually advanced requested lookups to 3,226 and
  pending to 40,987. No duplicate job or external SQL observer overlaps this
  resumed worker. Both physical displays are freshly confirmed committed OFF.
- Reviewed empty isolated GBC/GBA proof directories were removed non-recursively.
  Exact-file cleanup transaction 7d5f761542108d6499c7ea5f08647585 removed only the
  consumed 4,205-byte observer compiler intermediate; absence is verified. Java
  source, deployed jar and diagnostic proof remain available. Original saves,
  BIOS, cloud files and external sync mechanisms remain untouched.
- S7 remains sole ACTIVE: full fresh coverage, defensible canonical Top-25,
  current complete readable cloud-byte proof, remaining format workflows and
  reviewed migration are unfinished. S8-S10 remain NOT STARTED. No external
  release or save-sync retirement is claimed.

### S10 conditional legacy save-sync retirement authorized — 2026-10-07

- Specification revision 10 records the user's instruction to uninstall the old
  device sync app and stop the laptop scheduled task associated with
  `sync-retrobat-saves.ps1` after R-Shop's save sync is implemented and verified.
  Exact package/task discovery and a safe, verified handover belong to S10;
  the provisional "Drive Sync" name is not an established package identity.
- Preserve both mechanisms until SAVE-01's replacement criteria pass. Then
  uninstall the exact app and stop/disable the exact task, preserving saves,
  cloud backups, the laptop script and unrelated apps/tasks. Verify their retired
  state and a subsequent R-Shop backup/restore/emulator-load round trip.
- S7 remains sole ACTIVE; S8-S10 remain NOT STARTED. This documentation update
  does not start S10 or claim any device uninstall/task change or live proof.

### S7 bounded artwork recovery and live worker continuation — 2026-10-07

- Phase diagnostics on the unchanged native catalogue isolated the cold wait:
  43,599 rooted artifact rows indexed in 3,653 ms; 917 shared bindings checked
  by 11,163 ms; final recovery took 35,574 ms. Artwork comprises 1,145 unique
  files / 468,979,309 referenced bytes. A second diagnostic separated hashing
  and per-image publication; its screen-off/mixed-state timing is not comparable
  to the awake cold-start measurement. Native query plans confirm indexed exact
  artifact/member lookups, not per-game whole-table scans.
- Recovery now rebuilds content-addressed image receipts in transactions of at
  most 128 records, without opening every image. Receipt presence does not claim
  image availability: cache consumers check current bounded size and SHA-256
  before exposing any path. Same-size replacement and missing images return the
  fallback; no network repair or metadata/score erasure. Full validation remains
  at publication, migration and ES-DE export. No catalogue/binding checks were
  skipped or replaced by raw-store coalescing.
- Regression checks failed before implementation for per-image autocommit and
  same-size replacement exposure. Focused recovery, source/account ambiguity,
  bundle/base/manual-edit rejection, artwork jobs/restart, ES-DE import and normal
  controls Pause/Resume verification pass. The 130-receipt regression verifies
  exact 128/2 batches and offline rejection/recovery of replaced bytes. Scoped
  analysis and diff checks are clean; no full-suite or large resource run.
- Required builds 251/252 (phase diagnosis) and 254 (final) ran serially through
  the shared gate; final receipt confirms gate acquired, exit=0, workers=2,
  parallel=false, Gradle heap=3,221,225,472 bytes. Assessed Kotlin 2.2.20 runs
  in-process within that heap; required Metaspace 1 GiB/code cache 256 MiB remain.
  Test-task configuration is one fork/512 MiB; native/plugin effective concurrency
  remains unverified. No memory failure or budget increase. Final build log:
  `3a1517073667477c855dae9c292d152f.log`.
- Final host and installed APK SHA-256:
  `3a74b4ad195d192e17c886472e37b3d15736b502eff99dc8314fccd34e3e6ab7`.
  Debug signer is unchanged; update used install -r, no reset/uninstall/force-stop.
  Awake normal cold recovery indexed the same 43,599 rows in 3,467 ms, checked
  917 bindings by 10,750 ms and restored all 1,145 receipts by 10,985 ms. Artwork
  recovery consumed about 235 ms rather than the former 24,411 ms. This removes
  bulk image rereading from startup, not the remaining catalogue/binding latency.
- APK updates left Drive authorization interaction-required. Normal default
  account reconnect succeeded without changing roots/mappings or saving a new
  source. Job 76 stayed paused at requested=2,552 through update, then normal
  Resume actually advanced requests/outcomes. Joined normal Pause at 2,572
  verifies unchanged configuration hash
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`,
  active=1/pending=null/nextGeneration=2. Job totals remain 44,204: matched=54
  (rated=53), needsReview=813, ambiguous=190, unmatched=1,472,
  invalidResponse=35, pending=41,640. No external SQL observer overlaps a worker.
  Normal Resume then advances again to requested=2,582 / pending=41,630; this
  continuation did not recreate the job or repeat completed outcomes.
  Both physical displays are freshly confirmed committed OFF after normal sleep.
- S7 remains sole ACTIVE. Full fresh scrape, canonical/defensible retention,
  current readable exact-cloud-byte proof, remaining format round trips and
  reviewed migration remain unfinished; S8-S10 NOT STARTED. Standardized matching
  approval is implemented by f270427; the separate classification-provenance
  proposal is not approved. No original ROM/save/BIOS, FolderSync or cloud file
  changed, no SD migration or release occurred.

Cleanup: reviewed exact-file transaction 30c103cbcdb6c54b3fe2f877ea81cb5b removed
only the consumed 6,317-byte diagnostic Java compiler intermediate. Absence is
verified; retained Java source and deployed jar reproduce it. Logs/source/jar
remain needed verification evidence; no user data or repository output was purged.

### S7 catalogue-aware settings recovery — 2026-10-07

- Traced unchanged settings loading to an independent full shared-store restore
  in addition to the library readiness restore. A real SQLite/provider regression
  failed with three passes instead of one. Settings now reads the same library
  recovery future without watching/recreating the app-scoped metadata worker.
  A second catalogue notification during recovery still gets its own pinned pass.
  Raw-store in-flight coalescing was rejected during integration review because
  it could join a newer catalogue state to an older snapshot; it is not shipped.
- Focused real SQLite recovery, changed-edition/manual-edit rejection, source and
  account ambiguity, base/bundle recovery and normal worker Pause/Resume checks
  pass. The bounded 129-edition recovery/query fixture passes without network;
  no full-suite/30,000-edition workload was run. Scoped analysis and diff checks
  are clean. Debug diagnostics report only recovery phase/count/elapsed time,
  not source/account IDs, filenames, credentials or metadata bodies.
- Final build 250 acquired `Local\Darka.AndroidGradleBuildGate` and exited zero.
  Observed workers=2, parallel=false, Gradle heap=3,221,225,472 bytes; assessed
  Kotlin 2.2.20 runs in-process within that heap. Required Metaspace 1 GiB/code
  cache 256 MiB remain. Test-task configuration is one fork/512 MiB, not an
  executed native test; full plugin-native concurrency remains unverified.
  No memory failure or budget increase. Build log:
  `45dbf9d52468465fbc7caad71d5b3155.log`. Earlier build 249 was superseded after
  rejecting raw-store coalescing; both builds ran serially through the same gate.
- Host and installed APK SHA-256:
  `06a483d719474d270655069a178df399b6aa8fa502b00ac599d3d761758d197d`.
  Package `com.darkaxt.rshop.debug`, version 1.7.0/12 and debug signer unchanged
  (`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`).
  In-place updates preserved app data; no reset/uninstall/force-stop was used.
- Before/after update observations with worker paused verify configuration hash
  `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`,
  active=1/pending=null/nextGeneration=2 and unchanged job 76: requested=2,551,
  matched=54 (rated=53), needsReview=807, ambiguous=189, unmatched=1,460,
  invalidResponse=34, pending=41,660 (44,204 total). Normal native cold recovery
  completed once with restored=0 / elapsedMs=36,038. Normal IGDB switching and
  switching back loaded saved credentials immediately without another recovery
  start. Saved jobs showed the same paused job 76; normal selection/Resume showed
  Running from that checkpoint. No external SQL observation overlaps the resumed
  worker. Both physical displays confirmed OFF after normal sleep.
- Cold full-catalogue recovery latency remains unresolved S7 work; removal of
  duplicate passes is not proof of a complete performance fix. Full fresh scrape,
  canonical/defensible retention, current recoverable cloud-byte proof, remaining
  format round trips and reviewed migration remain unfinished. S7 alone ACTIVE;
  S8-S10 NOT STARTED. No original ROM/save/BIOS, FolderSync or cloud file changed.
- Execution correction: an early compile-error test run had not yet exited when
  a second launch was mistakenly attempted. It was refused by a locked SQLite
  DLL before tests ran; the first process's completion was then confirmed before
  subsequent verification. No concurrent Gradle build or memory exhaustion
  occurred. The final verified implementation contains neither that compilation
  error nor the rejected raw-store coalescing.

### S7 Game Boy owned recovery round trip — 2026-10-07

- Extended the existing owned archive route only to explicitly mapped GB 7z:
  one safe `.gb` member, 16 MiB raw budget, bounded decoding and full stream/CRC
  validation before publication, recovery and offline open. Archive bytes/name
  remain unchanged; immutable platform mapping and exact owned read-only leaf
  grants are required. No ZIP/GBC/GBA/bundle recovery or directory/write grant
  was added. Focused launcher/runtime/transfer/storage checks and scoped analysis
  pass, including normal installation resolution after archive publication.
- Native testing exposed two concrete integration errors: missing dispatch of
  `launchOwnedRetroArchGameBoy` and selection of an uninstalled Gambatte core.
  The dispatch is now connected; the actual installed SameBoy core is selected.
  Normal R-Shop opening reached the game title screen and accepted input. After
  normal emulator Quit and confirmed process exit, Wi-Fi was disabled and the
  same owned copy opened in a new process and accepted gameplay input again.
- Normal UI removal targeted only the task-created isolated proof copy. The same
  single queued item was re-downloaded using the default existing Drive account;
  its size and SHA-256 matched the source. Native read-only observation verified
  completed installation and retired staging. A second normal removal left zero
  proof-root owners and two terminal issue-free removal records. The original
  SD ROM and RetroArch configuration retain their baseline checksums; no matching
  game save/state was created. The reviewed empty proof directory was removed,
  not any original collection directory or cloud file.
- Normal folder selection restored the original GB target. The full saved
  configuration hash equals its pre-proof baseline, preserving all seven source
  objects and console settings. Published generation remains active=1,
  pending=null, nextGeneration=2. Job 76 retained requested=2,487 and all 44,204
  saved items/outcomes at its joined Pause checkpoint. Selecting that existing
  job and normal Resume showed Running again. No external SQL observation
  overlapped the resumed worker. Both physical displays were confirmed OFF.
- Required gated builds 245/247/248 exited zero; the latest installed APK is
  SHA-256 `face361e0a6f557626e4aea0237ffb0f4ae0c4cf72423d7ce5e0036314d3c377`,
  unchanged debug package/version and signer. The shared gate was acquired;
  observed workers=2, parallel=false, Gradle heap=3,221,225,472 bytes. Assessed
  Kotlin 2.2.20 runs in-process within that heap. Test-task configuration is one
  fork/512 MiB; full plugin-native concurrency remains unverified. No memory
  failure or budget increase occurred. Latest build log:
  `58cbd817212743d98c866a3123e62430.log`. No additional Gradle command was needed
  for documentation or the focused standardized-matching recheck.
- The already-approved standardized policy remains implemented by f270427.
  Focused current ScreenScraper/IGDB regional-matching checks pass, including
  company/day wording differences, conflicting release rejection and normal
  two-provider binding/offline ranking. This does not approve the separate
  unanswered bulk-classification proposal or establish full-library coverage.
- Opening cached metadata incurred a long database/shared-projection wait during
  the online check. A warmed offline launch was prompt, but the cause and full
  performance contract remain unresolved; no timeout/retry workaround or claim
  of a performance fix is made. S7 remains sole ACTIVE: full fresh coverage,
  canonical/defensible retention, current cloud-byte proof for migration and
  remaining required format round trips/migration are unfinished. S8-S10 remain
  NOT STARTED. No original ROM/save/BIOS, FolderSync or cloud file was changed.

Cleanup: exact-file transaction d722433530f98dfabc343ab4d822a3c4 reviewed and
removed only the consumed 3,854-byte observer compiler intermediate. Its retained
source and deployed jar reproduce it; screenshots/configuration before-image,
APK and build logs remain verification evidence. The proof directory was removed
only after both owned removals and an empty-directory check; absence was verified.

### S7 GBA identification host proof and native update — 2026-10-07

- Extended the existing metadata-only exact-local 7z path to explicitly mapped
  GBA: one safe `.gba` member, 32 MiB raw work budget, unchanged bounded header,
  dictionary, complete stream/CRC, container checksums and local/cloud version
  checks. No extraction, installation/adoption/removal support, remote ROM body,
  inferred official classification or scoring exception was added.
- The new native and runtime positive regressions failed before the platform
  extension. Focused native decoding now passes, including a streamed 17 MiB raw
  fixture and rejection beyond 32 MiB, wrong-platform/path members, plus existing
  GB/GBC/N64 checks. Focused runtime, persisted normal-worker and real-adapter
  synthetic-response/shared-recovery checks pass. Scoped analysis is clean.
  These host results do not substitute for live GBA provider acceptance.
- Gate tickets 241 (expected regression failure), 242 (native verification) and
  243 (normal debug build) each acquired `Local\Darka.AndroidGradleBuildGate`.
  Observed profile: two workers, parallel=false, 3,221,225,472-byte Gradle heap;
  required Metaspace 1 GiB/code cache 256 MiB preserved. Assessed Kotlin 2.2.20
  compiles in-process in that heap. Test-task configuration is one fork/512 MiB;
  native-plugin concurrency remains unverified, not proven by environment hints.
  No memory failure or heap increase occurred. Green/build logs:
  f8e02ea7e88e4edc95b3fc9f8080bd01.log and d01059072d614d5ea8b72323295acd3a.log.
- A joined normal Pause at requested=1,998 preserved job 76's 44,204 items:
  42,210 pending / 39 matched / 634 needs-review / 148 ambiguous /
  1,144 unmatched / 29 invalid-response. Normal Disconnect preceded a
  signer-preserving in-place update. Host and installed base.apk independently
  match SHA-256 07cafa849ac3fe40c4a556cf74570708825056f761a14ded633f9be616f74d67;
  unchanged package, version 1.7.0/12 and signer. Normal reconnect succeeded;
  before/after observations verify identical configuration/source hashes,
  active=1/pending=null/nextGeneration=2 and every saved outcome unchanged.
- At the joined normal Pause checkpoint requested=2,140, two GBA entries have
  exact local/cloud-container bindings, fully validated raw identifiers and
  provider-accepted persisted metadata. Both have advisory ratings and explicit
  ScreenScraper official-release evidence: all five modification flags are zero,
  notgame=false and the exact identifier matches the saved raw request. The
  native multi-entry identification workflow is verified, not archive restore
  or Top eligibility. GB/GBC retain five/four accepted raw bindings respectively.
  Job 76 still contains 44,204 items; outcomes are 42,069 pending / 43 matched /
  683 needs-review / 155 ambiguous / 1,224 unmatched / 30 invalid-response.
  Configuration, seven sources and generation remain unchanged. Normal same-job
  Resume is verified Running again, without completed-request rewrites or a
  second worker. External SQL observers ran only at joined normal Pause
  checkpoints. No new database exception was observed after this update, but
  the previous failure's root cause remains unproven. Both physical displays
  were freshly confirmed committed OFF after the final normal Resume.
- S7 remains sole ACTIVE. Full fresh coverage, defensible canonical retention,
  exact recoverable cloud bytes, required round trips and reviewed migration
  remain open; S8-S10 remain NOT STARTED. No ROM/save/BIOS/cloud-original deletion,
  FolderSync change, SD migration or release occurred.

Cleanup: reviewed exact-file transaction be8af18395e2da508cb3c9560c9452d6
removed only the consumed 7,991-byte Java compiler intermediate. The observer
source/deployment jar, private census journals, APK and verification logs remain
needed evidence. The consumed 13,754-byte device UI dump was separately checked
for stable exact identity/hash, removed at its exact task-owned path, and absence
verified. Both intermediates are reproducible from retained source/tools; no
shared cache/build tree or user file was removed.

### S7 current raw-binding, reception and recovery checkpoint — 2026-10-07

- The approved standardized matching policy is already implemented by f270427;
  this approval does not authorize the separate unanswered bulk-classification
  provenance proposal. S7 remains the sole ACTIVE stage; S8-S10 NOT STARTED.
- The normal saved ScreenScraper job accepted and persisted two GB and two GBC
  entries
  using validated raw members from their exact already-local Drive-matching
  archives. All four have explicit official classification and advisory ratings.
  Native observations at joined Pause checkpoints verify that multi-entry
  workflow; neither container checks nor advisory ratings are a recovery/Top
  claim. No completed saved request was rewritten to manufacture acceptance.
- A native database exception stopped the worker at requested=1,689 while its
  durable state still said running. The exact cause remains unproven. Long
  external read cursors against the rollback-journal database are a possible
  contributor, not a confirmed diagnosis. Direct SQL observations now occur only
  after normal Pause joins the worker. Debug-only diagnostics add the numeric
  database result code and up to four allowlisted application source locations,
  never exception messages, SQL, account data or secrets. The red/green fixture
  verifies code retention and SQL/value redaction; runtime recovery was not
  replaced by retries, timeouts, WAL changes or state-reset shortcuts.
- The existing public reception benchmark assesses GB/GBC against independent
  same-platform community reception. The existing IGDB community basis now
  includes them with unchanged scale, precedence, freshness, ownership and
  minimum twenty-user-vote rules. The focused boundary regression failed before
  extension and passed afterwards. A fresh live capture followed by offline
  production query selected seven supported games from ten public fixtures,
  identical Top-25 membership and explicitly provisional coverage. Low-vote and
  unrated records stay unranked. This does not establish complete private-library
  ranking. See SCORE_RECEPTION_ASSESSMENT.md for the primary-source evidence.
- Required normal debug build ticket 240 passed through the shared gate. The
  observed profile was two workers, parallel=false, 3,221,225,472-byte Gradle
  heap, preserving Metaspace 1 GiB and code cache 256 MiB. Assessed Kotlin 2.2.20
  compiles in-process within that heap. Test-task configuration is one fork /
  512 MiB, not executed JVM evidence; plugin-native concurrency is not proven by
  the two-job environment hints. No memory failure or heap increase occurred.
  Inspected log: 3c33708eb453483f8f32ce4082db0c57.log. Scoped analysis and focused
  metadata controls / effective score / Library-query checks passed; no full
  suite was run.
- Normal Disconnect preceded the signer-preserving in-place update, without
  revoke, uninstall, force-stop, credential replacement or configuration Save.
  Host and installed base.apk independently match SHA-256
  3ea4987ea903dc1306aafc5bc479bf05648ac7555cfe57ae4858956a039f36e2,
  unchanged com.darkaxt.rshop.debug, version 1.7.0/12 and the established signer.
  Normal startup recovered job 76 to paused at requested=1,689, preserving every
  outcome and all 44,204 immutable items. Configuration SHA-256 remains
  eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d;
  active=1/pending=null/nextGeneration=2 and all seven sources remain unchanged.
  Default-account Connect and same-job Resume succeeded. The final joined normal
  Pause checkpoint at requested=1,759 retained 42,449 pending / 29 matched
  entries, unchanged configuration and published generation; Resume continued
  the same job with no new database exception observed. That
  recovery is not proof that the earlier failure's cause is fixed.
- The final serial supported-format census terminated successfully. Independent
  record/count/byte/disposition reconciliation verified n3ds's 113 files /
  119,245,766,194 bytes: 112 nonselected preserved observations /
  118,358,490,674 bytes and one .cci exact-name miss / 887,275,520 bytes. Wii U's
  16 files / 73,412,799,575 bytes comprise 15 cached .wua matches /
  73,412,799,323 bytes and one 252-byte non-ROM file. Every disposition is
  preserve/removalAuthorized=false. An exact-name miss is not proof of absent
  equivalent content. Cached matches do not prove current cloud readability,
  canonical Top-25 membership or tested restoration. Private journals stay
  outside Git; no census worker remains live.
- Remaining S7 acceptance work: full fresh metadata,
  classification/canonical and defensible retention reconciliation, current
  recoverable cloud bytes, required format round trips and the exact reviewed
  migration. The native failure also remains under investigation. These are
  ordinary unfinished S7 work, not later-stage deferrals or completed criteria.
  No ROM/save/BIOS/cloud-original removal, FolderSync change, second metadata
  worker, SD migration or external release occurred.
- Both physical displays were freshly confirmed committed OFF after Resume.
  Reviewed cleanup removed only the consumed 13,477-byte device UI dump; the
  exact raw-binding observers, private census journals, build log and live-test
  APK remain needed evidence. No shared build/cache directory was swept.

### S7 local GB/GBC identification and bounded subfolder paging — 2026-10-07

- Extended only the existing metadata observation route to already-local GB/GBC
  single-member 7z files. The native decoder retains its bounded header,
  dictionary, complete stream/CRC and safe-name rules, with a 16 MiB raw budget.
  Runtime checks still require the exact configured source/account/target, all
  complete-container Drive checksums and before/after current cloud lineage.
  Raw member evidence is atomically pinned to that artifact version; manual
  unknown classifications, modified/base-linked editions and completed saved
  requests remain protected. No GB/GBC installation or removal support is added.
- Focused native regressions failed on the absent profiled entry point before
  implementation and passed afterwards. Focused Dart runtime, persistent-worker
  and real ScreenScraper-adapter contract fixtures passed, including raw/container
  separation, unsupported ZIP, restart reuse, modification protection and shared
  response recovery. Adapter fixtures use synthetic responses, not real provider
  acceptance. Scoped analysis passed. The stale transport fixture now supplies
  actual-shaped folder batches and asserts authenticated access-token reuse;
  production authentication was not weakened to satisfy the old fixture.
- Actual Android database diagnostics exposed approximately eight-second
  mapped-subfolder pages during startup. The recursive query fetched record JSON
  before sorting/limiting all descendant IDs. It now selects the bounded ID page
  first, then reads only those payloads, without a schema/reset/migration or a
  MATERIALIZED keyword requirement. Exact source/generation/parent traversal,
  supported anchor, ordering and offsets remain unchanged. The strengthened
  production-SQL query-plan regression failed before the change and passed after
  it; focused catalogue/provider checks and scoped analysis also passed.
- A READONLY Android diagnostic executed token-identical production SQL against
  the actual saved GB/GBC mappings and published generation. Game Boy's 9,112
  descendant records were traversed in 72 pages / 4,406 ms (maximum page 148 ms);
  Game Boy Color's 3,082 records in 25 pages / 623 ms (maximum page 95 ms).
  These include folders and filtered files, not canonical-game counts. Ordered
  page continuity, bounded payloads and unchanged published generation passed.
  This proves the actual SQLite read path, not full end-to-end provider matching.
- Native regressions and both required normal APK builds passed through acquired
  shared gates (tickets 237-239). Observed settings were two workers,
  parallel=false and 3,221,225,472-byte Gradle heap; assessed Kotlin 2.2.20 uses
  in-process compilation sharing that heap. Required Metaspace/code-cache flags
  were preserved. Test configuration is one fork/512 MiB; full plugin-native
  concurrency is not established by the environment hints. No memory failure
  or heap increase occurred. Inspected gate logs are
  58554a55c0044294a86c509a531e9417.log,
  3dcf15944ab54818b3f2460a76a3ef7a.log and
  dba82f8a996f4646ade4d8bef71d7de9.log. The earlier red native run (ticket 236)
  failed on the expected missing method, not memory exhaustion.
- Normal Pause joined ScreenScraper job 76 before Disconnect and signer-preserving
  in-place updates. The final installed normal debug APK has SHA-256
  156caa7c9c5ba3d8fbc31196c7c7674ba84231dc9ee03b4798f3c9f1d5cf8c32,
  unchanged package com.darkaxt.rshop.debug, version 1.7.0/12 and signer from
  DEVELOPMENT_SETUP.md. Native reads retained configuration SHA-256
  eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d,
  active=1/pending=null/nextGeneration=2 and all 44,204 saved items. The same
  requested=1,285 checkpoint and outcomes survived installation. Normal default
  account reconnect and Resume advanced that same job to requested=1,310 with
  no blocked status. No fresh replacement job or duplicate worker was started.
- Real GB/GBC raw-binding/provider acceptance remains an open S7 verification
  item. The progressing job has not yet reached the next already-local archives;
  a bounded pending read observed the first local GBC/GB candidates respectively
  200/364 pending positions away. Presence is not checksum/format/identity proof.
  Do not replace the existing queue or claim native provider integration from
  synthetic fixtures. Both physical displays were confirmed committed OFF.
  S7 remains sole ACTIVE; S8-S10 NOT STARTED. No ROM/save/BIOS/cloud-original
  write/removal, FolderSync change, ranking exception or external release occurred.
- Reviewed cleanup e4545970cef093601c384e7eea7b7988 removed only six disposable
  compiler/paging-diagnostic entries (30,159 bytes). The exact device paging jar
  and UI dump were also reviewed and removed. The bounded binding observer's
  source/jar and installed device jar remain needed to observe ordinary job 76's
  upcoming GB/GBC raw evidence; private journals and the verified live-test APK
  are intentional retained outputs. No shared cache/build root was swept.

### S7 GBA and SNES terminal censuses independently reconciled — 2026-10-07

- GBA's 798 records / 6,226,878,722 bytes reconcile with its terminal journal:
  776 cached byte matches (5,974,050,983 bytes), 14 exact-name misses
  (192,835,288 bytes), seven size mismatches (59,990,457 bytes) and one non-ROM
  file (1,994 bytes). Every disposition remains preserve/removalAuthorized=false.
- SNES's 8,501 records / 108,675,215,336 bytes likewise reconcile record by
  record: 559 cached byte matches (468,163,473 bytes), 220 exact-name misses
  (526,974,976 bytes) and 7,722 preserved non-ROM observations
  (107,680,076,887 bytes). The latter includes companion content, not expendable
  files. Relationships, cloud availability and restore routes are not inferred.
- The same serial handle subsequently completed Mega Drive, SG-1000, Virtual
  Boy and FDS and exited successfully. Every record/count/byte/disposition was
  independently reconciled:

  | Console | Records | Cached byte matches | Exact-name misses | Preserved non-ROM | Total bytes |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | Mega Drive | 508 | 505 | 0 | 3 | 351,190,946 |
  | SG-1000 | 110 | 65 | 42 | 3 | 1,723,775 |
  | Virtual Boy | 85 | 83 | 0 | 2 | 33,392,682 |
  | FDS | 85 | 0 | 84 | 1 | 3,931,516 |

  All remain preserve/removalAuthorized=false. FDS misses do not prove absence
  of equivalent raw members under different formats/names. One subsequent
  serial census now covers the earlier selector's supported n3ds .cci and Wii U
  .wua omissions using verified configured SD targets; terminal results are not
  yet claimed. Cached matches do not prove current cloud readability, canonical
  Top-25 retention or tested restoration. Private journals stay outside Git.
  Metadata coverage and reviewed migration remain required work within ACTIVE
  S7, not later-stage deferrals.

### S7 NES census verified and inventory format coverage reconciled — 2026-10-07

- The serial audit's NES journal reached its terminal result. An independent
  pass reconciled every record, comparison count, byte total and disposition:
  1,498 cached byte matches (113,113,373 bytes), three ambiguous cloud candidates
  (332,143 bytes) and one non-ROM file (1,305 bytes). All 1,502 observations remain
  preserve/removalAuthorized=false. Cached matches are not current cloud
  readability, canonical ranking or restoration proof. The same serial handle
  advanced to GBA; its Python child was observed live at 21.5 MiB working set.
- The complete 15,964-record private SD inventory was reconciled against current
  configured targets and SystemModel's actual ROM/archive extensions. Its old
  selector omitted one n3ds .cci file (887,275,520 bytes) and 15 Wii U .wua files
  (73,412,799,323 bytes) despite those suffixes being supported for browsing.
  This corrects the interpretation, not the immutable original journal. Include
  these explicit formats in subsequent scoped comparisons after the current
  serial batch; do not call them verified recoverable installations.
- Additional observed exceptions need separate identity/format treatment: 566
  .dsi files reside beneath the NDS target (4,226,909,024 bytes), while .dsi is a
  DSi format, not an NDS format; 111 .zcci files beneath n3ds (118,358,489,409 bytes)
  and 11 Wii .wad files (342,127,424 bytes) are not in those systems' current
  supported suffixes. Do not silently relabel these, guess mappings, move them,
  or infer recovery from the neighbouring console folder.
- The SNES directory also contains 220 .msu files and 7,477 .pcm files, together
  107,670,794,965 bytes. Satellaview has another nine .msu and 84 .pcm files,
  together 4,948,440,212 bytes. These suffixes may represent related content;
  no bundle association was proven by counting them. Preserve them until exact
  required-member relationships and restore routes are established. The old
  non_rom_preserved label must not be read as expendability or no migration work.
- Saved ScreenScraper job 76 is still running, requested=937 at this checkpoint,
  without a blocked status. Active catalogue generation 1/no pending generation
  and configuration SHA-256 eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d
  are unchanged. Both displays are independently committed OFF. No build,
  app update, source/config change, ROM/save/BIOS removal, cloud write, FolderSync
  operation or release occurred. S7 remains sole ACTIVE; S8-S10 NOT STARTED.

### S7 Game Boy Color census completed; remaining serial audits started — 2026-10-07

- The existing Game Boy Color audit completed and every file record reconciles
  with its terminal counts/bytes: 823 cached byte matches, three size mismatches,
  seven ROMs without an exact-name candidate and one non-ROM file. All 834
  observations remain preserve/removalAuthorized=false. Actual SD format counts
  are 830 .7z archives, three .gbc files and one .txt; the selector covers every
  observed ROM format in that directory. No full metadata/ranking/recovery
  acceptance follows from these cached byte matches.
- A bounded ten-file sample from Master System's 228 exact-name misses was
  streamed through device-side MD5 and compared against the complete scoped
  published cache. All ten were stable, but none had an identical size/digest
  under another name. This does not prove the remaining 218 files differ or
  rule out equivalent raw ROM members in differently compressed containers.
  It does not justify changing matching rules or inventing a counterpart.
- One sequential audit command now covers NES, GBA, SNES, Mega Drive, SG-1000,
  Virtual Boy and FDS, using inspected configured SD roots and explicit formats.
  It starts no second audit client, overwrites no journal and stops on a failed
  command or unsafe/missing terminal result. Only NES is currently executing;
  later members are queued, not verified. The live Python process was observed
  at approximately 21.9 MiB working set. Private journals stay outside Git.
- The same saved ScreenScraper job 76 remains running (requested=618 at this
  checkpoint), with partial outcomes only. Both displays are verified committed
  OFF. No Gradle/build, app update, ROM/save/BIOS removal, source/config change,
  cloud write, FolderSync operation or release occurred. S7 is sole ACTIVE;
  metadata coverage, reliable retention, live restore/revalidation and reviewed
  migration remain unfinished. S8-S10 remain NOT STARTED.

### S7 bounded census reader and two additional SD comparisons — 2026-10-07

- The actual Game Boy projection rejected the former 2,000-row/900,000-byte
  single-result contract (2,001 sampled rows / 1,256,547 bytes). The fixed
  READONLY helper now emits validated 128-row keyset pages with unchanged 1 MiB
  response and 900,000-byte page-input bounds. Per-console count, generation,
  config and ordered cursor checks reject incomplete/drifting observations.
  Only names actually enumerated under the inspected SD root are retained,
  bounded to 16 MiB of serialized records. Cross-page reads are explicitly
  observational, not an atomic snapshot or live recovery/removal authority.
- Focused regression checks reproduce the missing page contract before the
  change and pass afterwards, covering the actual SQL, traversal beyond the old
  bound, row repeats/gaps, state/config drift, memory bounds and all unchanged
  preservation gates. Native compilation and real Thor reads verify v2 against
  2,646 Game Boy artifacts, with 128 records in the first page. The installed
  read-only diagnostic jar has SHA-256
  7364435c0ba6b37435bf9ba8c0990196d0fd1daa70c68f611cb348dcf0d46247.
  An adversarial reverse-unordered SQL check exposed implicit aggregate ordering;
  explicit ordered subqueries now align IDs/records and stable scope ordering.
- Completed private journals were independently reconciled against every file
  record and terminal aggregate: Master System has 228 cached byte matches,
  228 without an exact-name cloud candidate and three non-ROM files; Game Boy
  has 601 cached byte matches, three size mismatches, three without an exact-name
  cloud candidate and one non-ROM file. All 1,067 observations remain preserve
  with removalAuthorized=false. No absent candidate is guessed, and different
  containers/filenames do not acquire identical-byte proof.
- The one audit process was observed at approximately 21 MiB working set during
  Game Boy verification. ROM hashing stays device-side and streaming; no ROM
  bodies or database copies enter Windows. javac/d8 used explicit 256 MiB
  budgets; native diagnostic calls use 128 MiB. No Gradle command or gate claim,
  APK replacement, memory failure, source/config change, ROM removal, cloud
  write, FolderSync change or release occurred. The original ScreenScraper job
  76 remains running (requested=495, then 596); both physical
  displays remain committed OFF. S7 stays sole ACTIVE; S8-S10 NOT STARTED.
  Cleanup 73c460acfac9d1aa558d8ead612e67f9 removed only the disposable host
  compiler outputs and empty staging directory (6,637 bytes). The hash-verified
  device helper is retained for remaining S7 comparisons; private completed
  journals remain required evidence. The final ordered helper's fresh native
  traversal retained 604 exact SD-name candidates across the 2,646-row catalogue.

### S7 missing Wii mapping corrected and indexed — 2026-10-07

- Reconciliation of the private SD inventory found 50 Wii ROM observations
  outside configured consoles. A fixed OPEN_READONLY query verified one exact
  `Nintendo - Wii` direct child in published root generation 1. Normal Console
  Settings import and Back/save added only Wii, targeting the existing external
  `/storage/75D7-DC5F/Roms/wii` directory. Payload comparisons preserve all 38
  previous console objects and all seven sources; native source hashes also
  remain unchanged. Final configuration SHA-256 is
  eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d.
- Ordinary Home indexing published 212 Wii catalogue rows. These are artifact
  observations, not canonical games or proven local/cloud membership. Saved
  ScreenScraper job 76 remains running in process 610, progressing through
  requested=303 and 320 without a duplicate capture or restart. Its 44,204-item
  immutable capture predates Wii and cannot satisfy Wii coverage. Run a scoped
  Wii pass after the existing provider work reaches a safe normal boundary.
- The SD inventory's 15,964 records are not 15,964 ROMs: its terminal summary
  separates 7,263 selected ROM observations from 8,701 preserved non-ROM records.
  That selector omits some actual formats, including DSi .dsi and Wii U .wua;
  .zcci/.wad and unsupported platforms likewise remain preserved unless actual
  supported identity/restore coverage is demonstrated. Do not use selector
  absence, folder counts or mapping presence as removal authority.
- Matching approval remains limited to revision 9's standardized policy; it does
  not authorize new classification provenance or relax score/recovery gates.
  S7 remains sole ACTIVE. Fresh full coverage, reliable retention and reviewed
  migration are unfinished; S8-S10 remain NOT STARTED.
- Both displays are freshly confirmed committed OFF. Cleanup transaction
  70644e9fe8c8c2c7658dc098e36f24e6 removed only six disposable host files and their
  empty directory (1,560,751 recorded bytes including directory accounting).
  Hash-checked device import/picker copies and exact diagnostic screenshot/jar
  were removed. No ROM/save/BIOS/cloud-original/FolderSync mutation, Gradle
  invocation, APK change, release or push occurred.

### S7 whole-collection capture committed and SD targets corrected — 2026-10-07

- The same accepted capture committed as ScreenScraper job 76 with 44,204 saved
  items. OPEN_READONLY evidence observes running state and increasing requested
  work (1, then 54, then 69); no new snapshot, source refresh or process restart
  was introduced. At the 69-request checkpoint: four matched/rated, four ambiguous,
  two invalidResponse, 22 needsReview, 36 unmatched and 44,136 pending. These are
  partial outcomes, not successful whole-collection coverage or approved ranking.
- After capture commit, normal Console Settings -> Import applied exactly 32
  target-only corrections into existing SD directories. Confirmed aliases are
  jaguar -> atarijaguar, lynx -> atarilynx, tgcd -> tg-cd and sg1000 -> sg-1000;
  the other new targets use their observed same-ID SD directories. Alternate
  region aliases examined contain only systeminfo.txt, not competing ROM sets.
  Existing directory presence and non-systeminfo file counts are not ROM identity,
  recoverability, complete membership or removal evidence.
- Payload comparison before and after ordinary Back/save verifies all 38 intended
  target values and all seven source objects. The native per-object hashes of all
  six original console configurations and all seven sources remain unchanged.
  Final complete configuration SHA-256 is
  21e5f56e86a778dd42ced74a4cc3363cec45710d073a03b0fe1937762687a615.
  Published root state remains active=1, pending=null, nextGeneration=2.
- This closes the erroneous destination configuration, not the local/cloud census,
  metadata coverage, reliable Top-25 retention or reviewed migration criteria.
  Continue saved job 76; never reinterpret its immutable capture or promote
  uncertain editions to improve coverage. S7 stays sole ACTIVE; S8-S10 NOT STARTED.
- Both physical displays are freshly confirmed committed OFF. Cleanup transaction
  9f353a7209babb4333bd0bc8eb454cc6 removed only the three disposable host outputs
  (256,320 bytes). Exact device import, picker-cache copy and screenshot paths are
  confirmed absent after use. No ROM/save/BIOS/cloud-original/FolderSync mutation,
  Gradle invocation, APK change, release or push occurred.

### S7 capture wait and actual storage-target reconciliation — 2026-10-07

- The accepted whole-collection operation is still in the same app process (PID
  610). Its open writable rollback-journal descriptor, continuing database writes,
  normal busy controls and OPEN_READONLY databaseBusy result are consistent with
  the still-uncommitted capture; no new job ID or successful provider result is
  inferred. No duplicate scrape, force-stop or APK update was performed.
- Android reports Doze disabled, charging, top-sleeping/not-frozen app state and
  an active power suspend blocker. No evidence supports blaming screen-off for
  a frozen worker. Both committed physical display states remain OFF. Filesystem
  watchers were diagnostic only; both exact task-owned watcher PIDs were stopped
  after one produced excessive output. Subsequent process inspection confirms no
  inotifyd observer remains; R-Shop PID 610 is unchanged.
- Independent configuration parsing reveals the original six targets point to
  the external SD Roms root, but all 32 newly added mappings use the default
  internal /storage/emulated/0/ROMs targets. Actual SD root enumeration confirms
  existing console directories, including aliases that differ from app IDs
  (atarijaguar, atarilynx, sg-1000 and tg-cd). This is an unresolved S7
  configuration/coverage item, not an approved migration profile or a completed
  installed-game census. Do not infer all SD files are represented by 44,204
  cached rows or construct deletion candidates from those defaults.
- After the current immutable capture commits, reconcile intended destinations
  through normal settings/import, preserving existing source objects and original
  six targets. Confirm exact directory aliases and keep unmanaged original files
  protected. Reconcile local/cloud membership before claiming full metadata or
  retention coverage. This remains ordinary S7 work, not a later-stage deferral.
- Complete configuration SHA-256 is still
  2e0f5888bbef7d40e0b06e9c671a71429c0f857cbcdd7e620761109499287620.
  S7 remains sole ACTIVE; S8-S10 NOT STARTED. No Gradle/build, ROM/save/BIOS,
  cloud-original, FolderSync or storage-target mutation occurred in this check.

### S7 broader normal console mapping and catalogue capture — 2026-10-07

- The approved standardized matching policy is already authoritative in revision
  9 and implemented by f270427. It removes company-wording/day-month equality as
  a standalone veto, not platform/edition/year conflicts or modification guards.
  No new classification-provenance approval is inferred from that instruction.
- Normal root Edit mappings saved 32 additional supported console mappings once.
  Exact native OPEN_READONLY checks confirm every selected folder is an observed
  direct child of the published generation-1 root. Duplicate mappings for the
  existing consoles and an unreviewed nested Arcade suggestion were cleared.
  Ambiguous/unsupported folders remain unmapped, not silently assigned.
- All seven source objects and all six pre-existing console configurations retain
  their exact per-object SHA-256 values. The complete configuration intentionally
  changes to 2e0f5888bbef7d40e0b06e9c671a71429c0f857cbcdd7e620761109499287620;
  it now contains 38 console configurations. Root state remains active=1,
  pending=null, nextGeneration=2. No new root scan was created.
- Ordinary Home library indexing ran to terminal UI state. The subsequent native
  read reports 44,204 cached artifact rows across 29 consoles with content.
  These include revisions, archives and folder rows; this is NOT a canonical
  game count, proven metadata coverage, or proof that every mapping has supported
  content. Zero-content and still-unmapped systems remain ordinary S7 work.
- The normal ScreenScraper controls show Entire collection. Fresh re-scrape was
  invoked ONCE after indexing finished; busy/Pause state confirms the operation
  was accepted. Immutable capture and actual new-job/provider progress must still
  be observed before claiming that the full metadata pass is running or finished.
- S7 remains the sole ACTIVE stage. Whole-collection identification, defensible
  Top-25 retention and exact reviewed migration remain unfinished; S8-S10 remain
  NOT STARTED. ROMs, saves, BIOS, cloud originals and FolderSync are unchanged.
  No Gradle invocation, APK update, external publication or push was needed.
- During immutable capture the fixed read-only observer reports databaseBusy;
  that diagnostic is not treated as an app failure or absent job. No duplicate
  scrape, reset, forced stop or guessed new-job ID was introduced. The unchanged
  configuration hash was independently rechecked outside the database. Device
  app PSS/RSS measured about 585/725 MiB; no memory failure was observed.
- Both physical displays are confirmed committed OFF with the accepted operation
  left intact. Cleanup transaction 558e2ad7115c1237918e1f982d8423da removed only
  the 1,309,702-byte disposable screenshot; its exact device copy is confirmed
  absent. Diagnostic helpers remain necessary for subsequent live verification.

### S7 published-catalogue query remediation — 2026-10-07

- Android logcat traces the read-only observer's `Killed` result to an uncaught
  `SQLiteDatabaseLockedException` (SQLITE_BUSY), not an OOM or R-Shop crash.
  R-Shop remained alive with about 9.5 GiB available device memory. Production
  source inspection identifies the expensive post-refresh exclusion report;
  attribution of that specific native lock owner is an inference, not a stack
  capture. The diagnostic now reports databaseBusy without a fatal exception.
- Actual production-SQL EXPLAIN regressions reproduce generation scans in the
  recursive step. Root pages now read the indexed validated generation directly;
  subfolder traversal drives an exact scope/generation/parent lookup per node.
  Both regressions failed before the fix and passed afterwards. Focused catalogue,
  provider and source-setup checks pass, including supported-root validation,
  stale-generation rejection, scope isolation and subtree membership. Scoped
  analysis and whitespace checks pass; no full suite was run.
- Required normal debug build 235 exited successfully through the shared gate.
  The observed profile is two workers, parallel=false and 3 GiB Gradle; existing
  Kotlin 2.2.20 in-process shares that budget. Metaspace 1 GiB/code cache 256 MiB
  are preserved. Test-task configuration is one fork/512 MiB, not executed test
  JVM evidence; app Ninja pools are depth one and plugin-native concurrency is
  not established by environment hints. No memory failure or budget raise occurred.
- APK SHA-256 `aa41a576e22d4e22ad7d0d2971e34221d835a56baf74cf5cf30c51fc45e8f7c7`,
  package com.darkaxt.rshop.debug/version 1.7.0/12 and unchanged signer verified.
  Normal Disconnect, in-place update, normal startup and default-account reconnect
  passed without Save, uninstall, revocation or configuration reset. Configuration
  SHA-256 remains `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
- Fresh native OPEN_READONLY evidence now confirms active=1, pending=null,
  nextGeneration=2, 267,562 observations and zero pending folders, schema 37.
  This closes terminal root publication, without recreating the scan. Opening
  normal root Edit mappings exercises the new read path and completes with
  observed console-folder choices, without a refresh or mapping Save. Returning
  from that screen leaves the complete configuration hash unchanged.
- S7 remains sole ACTIVE. Full fresh identification, defensible whole-collection
  retention and exact reviewed migration remain required; S8-S10 NOT STARTED.
  Matching approval does not waive classification, score support or exact
  recoverable-byte requirements. No ROM/save/BIOS/cloud-original/FolderSync change,
  removal, external release or push occurred.
- Both physical displays are freshly confirmed committed OFF. Reviewed cleanup
  transaction d31467a92a3b0c14acd4dbd8171e8241 removed only the disposable native
  screenshot (126,059 bytes); its exact device copy is confirmed absent. APK,
  build logs and read-only observers remain for verification/recovery.

### S7 bounded final folder validation — 2026-10-07

- Root traversal reached 267,562 observations and zero pending folder pages in
  the SAME generation 1. Final publication still required individual HTTP GETs
  for all 37,384 observed folders. The bounded regression reproduced that
  transport behavior before the change. Final validation now uses the documented
  [Drive v3 batch protocol](https://developers.google.com/workspace/drive/api/guides/performance)
  with at most 100 read-only metadata GETs, not fewer identity checks or quota
  units. No traversal/checkpoint/schema or publication authority was changed.
- Focused API/catalogue/download-boundary/provider/source-setup checks passed;
  final scoped analysis reports no issues. Inspected regressions cover exact
  once-only response identity/order, complete framing, response/request bounds,
  cancellation, one rejected-token renewal, typed quota/access failures, old
  published snapshot preservation, same-generation resume and changed-folder
  rejection. The separate nested-HTTP framing regression failed before its CRLF
  correction and passed afterwards. No full suite or concurrent test run was used.
- Normal Disconnect (not Revoke) drained owned Drive work before the signed
  in-place debug update. Read-only streaming digests verified all 267,562 entry,
  37,384 work and 38,795 page rows unchanged after installation. An initial
  diagnostic read encountered SQLITE_BUSY during actual startup library sync;
  it was repeated only after that visible startup sync finished. This was an
  observer failure, not evidence of corrupt rows or a memory failure.
- Gated attempt 233 failed from an unquoted PowerShell target property becoming
  a stray `.dart` task; after confirmed exit, corrected attempt 234 succeeded.
  The supervisor actually acquired `Local\Darka.AndroidGradleBuildGate` and
  observed two workers, parallel=false and a 3 GiB Gradle maximum heap. Kotlin
  2.2.20 uses the existing in-process strategy within that heap; Metaspace 1 GiB
  and code cache 256 MiB remain preserved. Test-task configuration reports one
  fork/512 MiB, not executed JVM measurement. Existing app native Ninja pools
  are depth one; actual plugin-native concurrency remains unverified. No memory
  failure or budget increase occurred. Both attempt logs remain retained in
  `D:/Temp/rshop-s7-folder-batch-build-20261007`.
- APK SHA-256 is
  `0209b16fcde15ce1de80654000182f42a22af8ee851556641242413954ab1d58`;
  package com.darkaxt.rshop.debug, version 1.7.0/12, unchanged verified signer.
  Normal native startup and default-account reconnect succeeded without Save,
  uninstall, configuration reset or account revocation. Normal root Refresh
  resumed the saved generation. Latest read-only state is active=null,
  pending=1, nextGeneration=2, 267,562 observations, zero pending folder pages.
  Those persisted counts DO NOT prove that final validation is progressing or
  terminal; native batch publication remains unverified.
- The fresh read-only SD inventory reconciles every one of 15,964 records,
  unique paths, group counts and all 722,865,729,304 logical bytes. Every record
  remains preserve/removalAuthorized=false. No payload hashes, cloud binding,
  ownership, removals or reclaimed-space claims come from this inventory.
- S7 is sole ACTIVE; full fresh identification, defensible whole-collection
  ranking, exact reviewed migration and restore/removal verification remain
  required. S8-S10 remain NOT STARTED. The reviewed-manifest classification
  question remains unanswered; the approved standardized matching policy does
  not authorize that import. No ROM/save/BIOS/FolderSync/cloud-original mutation,
  external release or push occurred. Both physical screens are confirmed OFF.
  Private evidence, checkpoint helper, APK and necessary build logs are retained.

### S7 alternative-score source screening — 2026-10-07

- Bounded primary-source screening is recorded in `SCORE_RECEPTION_ASSESSMENT.md`.
  RAWG's public Game Gear page does not demonstrate sufficiently supported
  distinct-edition coverage; GameFAQs offers a potentially useful platform-specific
  aggregate, but current direct HTTP access returned 403 and the retrieved web
  representation is old. Neither source was integrated or approved on this evidence.
- The existing native observer confirmed the SAME root generation 1 advancing
  to 258,337 observations / 4,102 pending folders, with active=null and
  nextGeneration=2. This is a verified wait, not terminal publication or a new pass.
- S7 remains the sole ACTIVE stage. Fresh whole-collection coverage, defensible
  retention and exact reviewed migration remain unsatisfied; S8-S10 NOT STARTED.
  No production behavior, ranking threshold, credentials, ROMs, cloud originals,
  FolderSync settings or APK changed. No Gradle command ran, so no new gate or
  build-profile claim applies. Both physical displays were confirmed OFF.

### S7 Game Gear terminal identification and artwork — 2026-10-07

- The SAME normal ScreenScraper job 73 reached `completed`: all 546 captured
  requests have explicit terminal outcomes — 177 matched (174 rated), 260
  needs-review, 42 ambiguous, 66 unmatched and one invalid response. Its current
  request evidence contains 178 original ROM identifiers. Completion of the pass
  is not full identification or trustworthy whole-collection ranking coverage.
- Fresh read-only inspection binds 178 validated local raw-member identifiers
  to their current Drive artifacts; 176 were accepted and classified official,
  173 rated. One accepted lookup was not counted by this specific local-archive
  evidence check. These are automatic provider-backed facts, not manual tags or
  container-hash matches.
- The read-only native observer selected the exact linked artwork child, job 74,
  rather than treating metadata completion or an earlier parent's artwork as its
  completion evidence. Job 74 progressed from 28 matched/304 pending to
  `completed`, with all 332 artwork requests matched and no blocked status.
  Only after that terminal result did the normal UI request one fresh IGDB pass
  for Game Gear. Native job 75 is now `running`, without a blocked status. Its
  immutable 546-request capture includes 177 official classifications, 369
  unknown editions, 178 original identifiers and 55 current release
  corroborations. Initial observed outcomes are four matched (one rated),
  28 needs-review, four ambiguous, two unmatched and 508 pending. This proves
  the new evidence reached the normal subsequent provider pass, not its terminal
  coverage or approval of Game Gear's ranking basis.
- Root catalogue traversal remains the SAME unpublished generation 1, with
  nextGeneration 2: 241,799 observations and 1,667 pending folders. Native schema
  37 still uses the pending-work index followed by exact entry lookup. No reset,
  false empty publication or second catalogue traversal was introduced.
- Game Gear's overall-score basis remains unapproved. The public IGDB check in
  `SCORE_RECEPTION_ASSESSMENT.md` is only an upper bound of 19 potentially
  sufficiently supported provider records, not accepted collection membership.
  The fresh bound IGDB pass and reception assessment remain required before any
  scope extension; no vote-floor reduction, fabricated rank or title curation.
- S7 is the sole ACTIVE stage. Full fresh coverage, defensible canonical
  retention, root publication and reviewed SD migration remain unfinished;
  S8-S10 remain NOT STARTED. No Gradle build, APK update, ROM removal, cloud
  mutation, FolderSync change or release was needed for this continuation.
- Configuration SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`;
  R-Shop PID 1836 and unrelated NetherSX2 PID 15069 remain alive. Both physical
  displays were freshly confirmed committed OFF during the artwork continuation.
- Normal Game Gear metadata controls visibly show `Running` for the new pass;
  subsequent read-only inspection confirms the SAME job 75 advancing to 13
  matched (four rated), 133 needs-review, 20 ambiguous, seven unmatched and 373
  pending, without a block. Root generation 1 has 251,220 observations / 5,829
  pending folders; it remains unpublished. No second provider pass was started.
- Reviewed cleanup transaction `ca14b90b6d0caf74ba58f9b002a8795e` is APPLIED:
  only its disposable UI screenshot and empty directory were permanently removed
  (1,316,340 bytes), plus the exact device screenshot confirmed absent. Required
  read-only observers, APK and private migration evidence remain retained.
- Job 75 subsequently reached `completed`: 46 matched (eight rated), 402
  needs-review, 73 ambiguous and 25 unmatched account for all 546 requests, with
  no blocked status. A bounded OPEN_READONLY native query joined only this exact
  job's accepted items to same-generation, same-identity IGDB metadata: all 46
  records agree; eight have valid 0-100 community scores, six below 20 votes and
  two at least 20 votes (two distinct provider records). These are provider-record
  counts, not approved canonical Top membership or a retention manifest.
  Current Game Gear evidence does not justify whole-collection ranking or SD
  removal. No policy threshold or production ranking scope was changed.
- Standalone diagnostic javac/d8 compilation succeeded with 128-MiB heaps;
  source/target-8 compatibility warnings are not memory failures. This was not
  Gradle: no build-gate acquisition or new Gradle-profile evidence is claimed.
  Root generation 1 remains active work, not a published snapshot: 256,547
  observations / 5,885 pending folders at this terminal metadata checkpoint.

### S7 N64 terminal matching / native Top query / next fresh scope — 2026-10-06

- The same N64 IGDB job 72 is now `completed`. All 1,543 captured requests have
  terminal outcomes: 120 matched (96 rated), 866 needs-review, 286 unmatched and
  271 ambiguous. Its immutable capture retains 147 original identifiers/current
  corroborations and 147 official classifications. The read-only observer finds
  no linked artwork child; IGDB implements `MetadataProvider`, not the separate
  artwork-provider interface. No second N64 pass or per-title correction was used.
- Normal Nintendo 64 browsing -> menu -> Filter -> Best 25 -> close displays
  exactly 25 games. Reopening Filter visibly reports the accepted IGDB community
  basis (20+ ratings, assessed systems only) and `55/1543 ranked · 25 matching
  games · Provisional`. The ordinary query rebuilt all six existing projections;
  the N64 projection has 55 eligible groups and zero dirty editions. This proves
  current UI/query integration, not a defensible whole-collection retention set.
  The temporary discovery filter was cleared afterwards.
- With the previous metadata worker terminal, normal Game metadata controls
  selected ScreenScraper and `gamegear`, then created ONE fresh job 73. Its
  current capture has 546 requests (544 unknown, two official); observed state
  is `running`, with 544 pending, one matched/rated and one needs-review, without
  a blocked status. This pass uses the existing already-local archive identifier
  path; completed Game Gear jobs 66/68 are not reused as fresh coverage proof.
  No ROM body download or guessed classification was requested.
- Root traversal remains the SAME unpublished generation 1 / nextGeneration 2;
  it advanced to 181,583 observations and 2,072 pending folders. Actual schema-v37
  query evidence still starts with the pending-work index and exact entry lookup.
  Continue this generation; do not reset it because metadata scopes finish first.
- Configuration SHA-256 is unchanged from the preceding checkpoint. R-Shop PID
  1836 and unrelated NetherSX2 PID 15069 remain alive. Both physical displays are
  freshly confirmed committed OFF after UI work. No ROM/save/BIOS, cloud original,
  FolderSync configuration or external release was changed. No Gradle command was
  needed for unchanged production source; no new gate/profile claim is made.
- S7 remains the sole ACTIVE stage. Full fresh scope coverage, root publication,
  defensible canonical retention and the reviewed SD migration remain unfinished;
  S8-S10 remain NOT STARTED. These native results do not waive any migration gate.
- Subsequent screen-off observation proves the SAME Game Gear job advancing:
  pending 530, matched/rated four, needs-review ten, ambiguous two and three
  captured original identifiers. Root generation 1 reached 188,651 observations
  with 2,062 pending folders. Cleanup transaction
  `979e478fdbab85a6449475f3e4826dec` is APPLIED: only its temporary screenshot and
  empty capture directory were permanently removed (1,119,385 bytes). The exact
  device screenshot was removed and freshly confirmed absent. Required observer,
  APK and private migration evidence remain retained.

### S7 normal native upgrade and same-generation resume — 2026-10-06

- N64 ScreenScraper job 70 and linked artwork job 71 reached `completed` before
  the update. Job 70 accepted/rated 147 items; artwork 71 accepted 298 and
  retained two `invalidResponse` outcomes. Terminal traversal is not full
  identification, reliable-score coverage or migration completion.
- Fresh signer verification and SHA-256 inspection of normal debug build 225
  passed; `adb install -r` succeeded without uninstall/data reset. Ordinary
  startup reached the console carousel, not a stalled splash. Production schema
  36 -> 37 completed. Frozen pre-start and stable post-migration read-only
  streamed digests agree for all 163,203 entries, 26,841 work rows (including
  row order/page cursors) and 22,913 consumed-page rows. Metadata/artwork outcomes,
  pending generation 1 and nextGeneration 2 are unchanged.
- The installed application's actual SQLite plan uses the partial pending-work
  index first and exact entry lookup second, with no temporary sort. This proves
  native upgrade/access-path integration, not a quantified traversal speedup.
- Normal source Refresh initially required Drive interaction. The ordinary
  Connect/account chooser restored access with the existing default account;
  returned without saving any source or changing its root/mappings. Normal
  Refresh then resumed the SAME generation 1: observations 163,203 -> 163,238 ->
  164,678 -> 164,948; pending folders 4,861 -> 4,848 -> 4,431 -> 4,356.
  The root remains unpublished; nextGeneration remains 2.
- Normal Game metadata UI selected IGDB and N64 only, then created one fresh
  pass, job 72, after job 70/artwork 71 were terminal. Its immutable capture
  includes the 147 newly bound original identifiers/corroborations and official
  classifications. It is `running`, without a blocked status: pending 1,543 ->
  1,485, matched 5, rated 4. Review/ambiguity/unmatched outcomes remain explicit.
  No duplicate pass, guessed classifications, imported ranks or per-game
  corrections were introduced.
- Configuration SHA-256 remains
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  NetherSX2 PID 15069 remains alive. Both displays were confirmed OFF after
  the native actions. No ROM/save/BIOS, cloud original or FolderSync was changed.
  No new Gradle command was run; build 225's already-inspected gate/profile
  evidence remains applicable to unchanged production source.
- S7 remains sole ACTIVE: terminal root publication, full fresh coverage,
  defensible canonical Top-25 sets and reviewed preservation/migration remain
  unfinished. S8-S10 remain NOT STARTED. Native upgrade/checkpoint preservation
  and same-generation resume now have actual installed-app evidence.
- Subsequent screen-off read-only check confirms continuing work: the SAME
  IGDB job 72 has pending 1,375, matched 18 and rated 13, without a blocked
  status; root generation 1 has 165,501 observations / 4,223 pending folders.
  Reviewed cleanup `b5a6d240752264c40eaba866bdf30c53` is APPLIED, removing only
  the temporary UI capture and empty capture directory (1,085,324 bytes), plus
  its exact device screenshot. The normal APK, ongoing bounded observer and
  protected private evidence remain retained for required S7 work.

### S7 next-folder scheduling regression — 2026-10-06

- The Thor's actual schema-v36 query plan starts with catalogue entries and
  uses a temporary sort to choose one pending folder. A bounded host fixture
  reproduced lookup growth from 65 to 100,051 SQLite VM steps after 20,000
  completed folders. Added a partial pending-work index plus a work-first join;
  order, exact scope/generation and page cursors remain unchanged.
- Production schema-v37 upgrade preserves active/pending generations, entries,
  work and consumed-page checkpoints. Focused upgrade/reopen and traversal
  checks pass, including failure preservation, pagination, cancellation and
  publication boundaries. Scoped analysis passes. The exact SQL also passes
  on the Thor's SQLite engine against an isolated in-memory fixture: pending
  index first, exact entry lookup second, no temporary sort. This is not an
  installed-app migration or measured live traversal speedup.
- Final normal debug build 225 passed after the query change, through the shared
  gate with two workers, no parallel projects and a verified 3 GiB Gradle heap.
  Kotlin 2.2.20 remains in-process, sharing that budget; Metaspace 1 GiB and code
  cache 256 MiB are preserved. Test configuration reports one fork/512 MiB;
  actual native/plugin concurrency remains unverified. No memory failure or
  budget increase occurred. Build log: `fed5b9bdb2244bcbb680172b19df1bb8.log`.
  The earlier build 224 predates the final work-first query and is superseded.
- APK SHA-256 `1e9864cba565460af592278492da795c8fdea2e047594c1fb51864bd4a9d7f83`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12, unchanged debug signer
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Retained for the next native upgrade; not installed over the working jobs.
- Same N64 metadata job 70 is still running: pending 79, matched/rated 139,
  no blocked status, no linked artwork job yet. Stored provider budget reports
  max_threads=1, requests_per_minute=3072, remaining_requests=14779 and no quota
  exhaustion. Root generation 1 is still unpublished at 161,294 observations /
  5,394 pending folders; nextGeneration remains 2. These counts do not certify
  metadata completeness, canonical coverage or deletion authority.
- Both displays remain OFF. No production device database, ROM/save/BIOS,
  cloud original or FolderSync was changed. S7 remains sole ACTIVE; native
  upgrade/resume, full fresh coverage, defensible rankings and reviewed
  preservation/migration remain unfinished. S8-S10 remain NOT STARTED.
- Later read-only observation: the SAME job 70 advances to pending 31 /
  matched-and-rated 144; root generation 1 advances to 161,797 observations /
  5,239 pending folders. R-Shop/NetherSX2 PIDs remain 26853/15069 and displays
  remain OFF. Reviewed cleanup `8b3d6d8dce1771bc83a204862770029c` permanently
  removed only three temporary in-memory fixture files (10,821 bytes) and its
  exact device JAR. Regression source, build and ongoing observer are retained.
- Same N64 ScreenScraper job 70 subsequently reaches `completed`, with 147
  accepted/rated items. This is completion of its captured pass, not full
  identification or reliable-score coverage. Linked artwork job 71 is still
  `running`: matched 171, pending 128, invalidResponse 1. Root generation 1
  remains unpublished at 162,700 observations / 5,001 pending folders.
  Continue the existing artwork worker; then perform the normal APK upgrade,
  verify schema-v37/checkpoint preservation and resume the same root generation.
  The normal N64 IGDB pass must capture the newly bound release evidence only
  after the current metadata/artwork controller work ends; no duplicate pass
  has been created. All remaining coverage/migration acceptance stays open.

### S7 PSP save-location boundary — 2026-10-06

- Read-only checks found neither internal nor SD-root `PSP` path available.
  The checked internal/SD `Android/data/org.ppsspp.ppsspp/files` directories
  exist, but bounded enumeration returned no files. This does not certify
  absence of private/custom saves. Installed PPSSPP v1.20.4's ordinary activity
  displays the initial Memory Stick location chooser. No option, folder grant,
  move, save, ROM or emulator setting was selected/changed. Returned to the same
  R-Shop task without killing PPSSPP or NetherSX2; this is not S10 setup.
  [Official storage documentation](https://www.ppsspp.org/docs/getting-started/save-data-and-storage/)
  distinguishes user-selected PSP storage from app storage; neither is inferred
  from an absent default folder. PSP save coverage remains unverified/protected.
- Both displays were confirmed OFF. Same metadata job 70 remains running at
  pending 207 / matched-and-rated 123; root generation 1 advances to 159,904
  observations / 5,874 pending folders, nextGeneration=2. No terminal coverage
  is claimed. The earlier reviewed-manifest classification decision remains
  unanswered and was presented again as a precise provenance choice, separately
  from cryptographic cloud recovery and deletion authority.
- S7 remains sole ACTIVE; the complete fresh pass, defensible rankings and
  reviewed save-safe migration remain required. S8-S10 remain NOT STARTED.
  No code, APK, Gradle command or cloud original was changed.

### S7 captive-portal recovery / same-job resume — 2026-10-06

- Normal Resume kept N64 metadata job 70 intact but its access check returned
  `unavailable`, without processing another item. The current authenticated host
  ScreenScraper adapter check passed. Thor IPv4 HTTPS probes to Google and both
  ScreenScraper origins failed with `No route to host`; the ordinary HTTP
  connectivity probe returned a hotel captive-portal redirect. Android's earlier
  ever-validated state was not proof of current Internet access. No quota or
  credential failure is inferred. Windows hotspot creation was rejected; no
  hotspot configuration or credential change was made.
- The hotel's normal browser Continue action restored Thor HTTPS: Google's
  connectivity endpoint returned 204 and the unauthenticated ScreenScraper API
  returned 403, rather than a transport failure. Normal Resume then advanced the
  SAME job 70: pending 292 -> 287 -> 268 -> 263; matched/rated 115 -> 119. The
  last observation is `running`, with null blocked_status. No fresh/retry job,
  provider change or individual-game curation was introduced.
- Normal Sources -> Collection -> Refresh resumed the SAME unpublished root
  generation 1: observations 159,305 -> 159,420, pending folders 6,056 -> 6,030,
  nextGeneration remains 2. Existing published catalogues remain unchanged until
  traversal succeeds; neither terminal traversal nor full scrape is claimed.
- Both displays were freshly confirmed OFF; the later observation proves both
  workers still advance. R-Shop PID 26853 and NetherSX2 PID 15069 remain alive.
  Full configuration retains SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  No ROM/save/BIOS/cloud-original/FolderSync mutation occurred. No Gradle ran,
  so no new gate acquisition or effective build profile is claimed.
- S7 remains sole ACTIVE. Full fresh metadata/root publication, defensible
  rankings, preservation and exact reviewed migration remain required. S8-S10
  remain NOT STARTED. This supersedes the earlier unknown pause diagnosis only
  for the reproduced current access-check failure, not its historical cause.
- Final screen-off observation: job 70 remains running, pending 249 and
  matched/rated 121; root observations 159,539 and pending folders 5,988. No new
  generation was created. Reviewed cleanup `61b0e87213333566242eb5878dc2107f`
  permanently removed only the temporary capture/directory (667,027 bytes);
  its exact device PNG and temporary browser tab were also removed. Protected
  private evidence, installed APK and ongoing observer remain retained.

### S7 shared protected-file baseline — 2026-10-06

- Added bounded read-only `scripts/thor_protected_baseline.py`, reusing the
  existing ADB inventory reader. Only explicit shared saves/states/BIOS/config
  scopes are hashed on-device; file bodies do not cross ADB. Private exclusive
  JSONL evidence supports exact before/after checks. Changes, redirected scopes,
  incomplete journals and unavailable observations cannot pass. This is not a
  backup or S10 implementation.
- Live capture completed: 137 files, 304,486,395 observed bytes, 16 scopes.
  One RetroArch remap's mtime changed during hashing; PPSSPP's shared PSP path
  was absent or unreadable. The journal correctly fails self-comparison: terminal
  recording does not certify stable coverage. Private/custom paths and unknown
  SD sidecars remain unverified and protected. No emulator was stopped.
  Retained evidence: `D:\Temp\rshop-s7-protected-baseline-20261006\private\protected.jsonl`.
- Focused baseline and existing migration-audit checks passed serially. A scope
  redirect regression failed before its fix. Fresh ScreenScraper/IGDB adapter
  and persistent-worker checks revalidated approved regional confidence,
  company/date disagreement, conflict rejection, legacy-capture immutability,
  modified-score isolation and offline publication. Full coverage is not claimed.
- Same N64 job 70 reports paused, 292 pending, 115 matched/rated; blocked_status
  and not_before are null. The reason is not established; do not infer quota
  exhaustion or restart/create a new job. Diagnose/resume the existing saved job
  normally. Root generation 1 remains unpublished: 159,305 observations and
  6,056 pending folders, nextGeneration=2. R-Shop PID 26853 and NetherSX2 PID
  15069 remain alive. Current configuration retains baseline SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
- Both screens remain OFF. No original ROM/save/BIOS/settings/cloud mutation,
  FolderSync change, SD removal or release occurred. No Gradle ran: no new gate
  acquisition/profile is claimed. Diagnostic Java compilation used 128-MiB
  heaps with no memory failure. Cleanup `85ad5b981011be54792a9d1755d4bdde` removed
  only the empty expendable work directory; private evidence and observer remain.
- S7 remains sole ACTIVE; full metadata/root publication, defensible retention,
  migration-time preservation and exact reviewed execution remain required.
  S8-S10 remain NOT STARTED.

### S7 device-sync no-refill guard — 2026-10-06

- Remediated the inspected LoLSuite refill risk with an optional exact
  `device.on_demand_folders` exclusion, not altered archive caps. Both planners,
  ownership bootstraps and old-plan bindings reject excluded/overlapping folders
  before ADB. Menus omit them; plan-all continues unaffected targets. Current
  selection fingerprints remain identical under independent pre-change checks.
- The focused regression failed before implementation. Exclusion and existing
  configuration/coverage/UI checks passed serially; a real CLI with a temporary
  excluded-target config refused planning and produced no output directory.
  Live device/coverage configs and ownership remain unchanged. The guard is not
  activated until the actual reviewed migration chooses its folders.
- Because LoLSuite is not a Git repository, the applied source/test patch is
  versioned in `integrations/lolsuite/on_demand_sync.patch`; reverse applicability
  was checked. Details and exact source identities are in
  `S7_EXTERNAL_SYNC_REVIEW.md`. No ROMs, saves, FolderSync or cloud originals were
  changed. No Gradle command/build/profile change or external release occurred.
- S7 remains ACTIVE. Actual exclusion activation/exact-plan revalidation, full
  fresh metadata/reception, defensible retention, root publication and reviewed
  migration remain required. S8-S10 remain NOT STARTED.
- Fresh read-only observations revalidated the same PID 26853, N64 job 70 and
  root generation 1: pending metadata 542 -> 446, accepted/rated 98 -> 108;
  catalogue pending folders 6,780 -> 6,516. Neither worker was restarted and no
  new generation/job was created. Both displays are OFF; R-Shop's full config
  still matches its recorded baseline. These are progress, not terminal coverage.
  Reviewed cleanup `607cee57ce722902ffe2a4b426bce653` permanently removed only
  expendable before-images/validation/config copies (1,033,689 bytes). Persistent
  tests passed again after cleanup; the versioned patch provides exact recovery.

### S7 screen-off worker observation — 2026-10-06

- Revalidated the same live R-Shop PID 26853, N64 job 70 and root generation 1.
  An auxiliary READONLY observer exited 137; its actual native stack identifies
  SQLiteDatabaseLockedException while preparing its first query, followed by the
  observer's uncaught-exception kill. This is not app death, memory exhaustion,
  database corruption or proof that the saved workers stopped. No restart,
  database repair, timeout, retry loop or production patch was introduced.
- Foreground observation succeeded, then successive observations with both
  physical displays committed OFF confirmed continued progress: N64 pending
  641 -> 611, accepted/rated/raw-bound 91 -> 94; root observations 155,926 ->
  156,243 and pending folders 7,109 -> 7,000. The same PID and generation remain
  live; nextGeneration is still 2. Terminal scrape/publication is not claimed.
  Full configuration retains its recorded baseline SHA-256. Original files,
  credentials, mappings and FolderSync are unchanged. No build was run.
- Continue the same workers to their terminal outcomes. S7 remains the sole
  ACTIVE stage; rankings and reviewed migration still require their own gates.
  No required work was moved to S8-S10 or marked complete by this observation.

### S7 deterministic search/navigation ownership — 2026-10-06

- Reproduced a pending-frame race with the real searchable-screen mixin and
  search focus widget: navigation suspended before the widget's deferred claim,
  then that claim restored search priority on the detail route and blocked its
  menu. The regression failed before the production change. This establishes
  the reproducible blocking defect, not the exact timing of the earlier live
  transient. This checkpoint supersedes the preceding unresolved investigation.
- The screen now owns one exact search claim, synchronously acquired on open,
  released on suspend/close/dispose and restored only after balanced resume.
  The widget owns focus only; deferred callbacks cannot focus suspended search
  or recreate a claim. Disposal releases only its captured token after widget
  finalization. Other overlays' claims remain intact; no delay, timeout, retry
  or broad priority-release fallback was introduced.
- Focused search/navigation, overlay-priority, download-overlay and source-menu
  checks passed. The final search fixture also passed serialized, and scoped
  Dart analysis reported no issues. Pending-frame, actual Navigator/quick-menu,
  nested suspension, independent claims and disposal were exercised. No full
  suite was run. Native PS2 and Library search -> detail -> menu -> return passed
  by controller/touch without an app restart or ROM mutation.
- Build ticket 223 acquired `Local\Darka.AndroidGradleBuildGate`
  (`gate_acquired=true`) and exited 0. Inspected effective profile: two workers,
  parallel=false and 3-GiB Gradle heap, preserving 1-GiB Metaspace/256-MiB code
  cache. Kotlin 2.2.20 was assessed/requested in-process, sharing that heap;
  compile tasks were up-to-date, so execution strategy was not independently
  observed. Test tasks were configured for one 512-MiB fork but not executed in
  this packaging command. Native budget two/app pool one was configured; current
  generated Ninja runtime concurrency was not independently verified. No memory
  failure or budget increase occurred. Retained log:
  `43e73cc474b54344a5761aab227b37bc.log` in the shared-gate log directory.
- Same-signer in-place APK installation succeeded. APK SHA-256
  `64a020e66d76ec70c10d87a2cf21d2d865d28f6d9f2ace3cb0ab7f241e4a0802`,
  signer SHA-256
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Default-account reconnect succeeded after the authorization pause. Normal
  Saved jobs resumed SAME N64 job 70: running, pending 672 -> 668, accepted/rated
  90. Normal root Refresh resumed SAME generation 1: observations 155,375 ->
  155,667, pending folders 7,291 -> 7,196, nextGeneration=2. These are progress,
  not terminal scrape coverage or root publication.
- Full source configuration still matches baseline SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`;
  PSP-only Library Best-25 and PS2 Installed Only preferences are unchanged.
  Original ROMs/saves/BIOS/cloud files and FolderSync are preserved. Both physical
  screens are freshly committed OFF. Exact device captures are absent; reviewed
  cleanup `d8dc790bbedd268df9e867a040abb2ad` removed only the expendable host
  capture/helper tree (1,642,932 bytes, permanently removed). The bounded S7
  observer, current APK and build log remain intentional verification outputs.
- S7 remains the sole ACTIVE stage. Full fresh metadata/reception, defensible
  per-console Top-25, root publication, remaining formats and reviewed save/space-
  safe migration remain required. The pending bulk provenance decision is not
  silently replaced by title-based classification. S8-S10 are NOT STARTED.
  No external release occurred.

### S7 PS2 standalone CHD owned recovery — 2026-10-06

- Added standalone PS2 CHDs to the existing committed-leaf handoff. Installed
  NetherSX2 receives explicit EmulationActivity/bootPath with only the exact
  document-shaped read URI. Ownership and standalone/no-bundle constraints are
  rechecked before handoff and external open. The normal menu identifies
  NetherSX2. Archive/ISO/bundle support and directory/write grants are not inferred.
- Normal DOWNLOAD published a 62,976,347-byte test CHD in the initially absent
  isolated `RShopProof-PS2-20261006` destination. SHA-256
  `95dd3a7233f66b3f51b5b299e25b047dc54441e9c1055e51481e3276d08fa73d`
  matched the unchanged H: original. The normal menu reached actual publisher
  intro and rendered game scenes. After normal Exit Game, emulator force-stop and
  verified PID absence, a fresh process rendered the game with Wi-Fi disabled.
  Intent acceptance alone was not counted as boot proof.
- Normal DELETE, normal re-download and final normal DELETE passed. The recovered
  bytes matched the same digest; read-only journals confirmed completed copy
  publication, retired staging and one installation/owner. Final proof-root state
  had zero transfers/installations/owners and two completed issue-free removal
  journals. The empty proof directory was removed non-recursively and is absent.
- Installed maintainer NetherSX2 v2.1-4248 as a missing prerequisite, without
  replacing an existing same-package app. APK SHA-256
  `a39fe9f88de54d35a39152ce4c003ec15c9dd82064cad57b0455ac1a5cd61050`,
  signer SHA-256
  `9bf3772a94603282fb13c64ea8771d66817382f6aca9923e8a178e7219340296`.
  Its normal BIOS picker imported the existing owner-supplied BIOS; original and
  emulator-owned import independently matched SHA-256
  `f4c948e61a291d4b3f92a141e550cf8357204287a31ff784caccbedaef910c9d`.
  The temporary import copy is absent; original BIOS and emulator import remain.
- The focused owned-launch regression failed before implementation and passed
  afterward. Scoped Dart analysis and native exact-leaf grant JUnit checks passed;
  no full suite was run. Build ticket 222 acquired
  `Local\Darka.AndroidGradleBuildGate` (`gate_acquired=true`) and exited 0.
  Inspected effective profile: two workers, parallel=false, 3-GiB Gradle heap;
  required 1-GiB Metaspace/256-MiB code cache preserved. Kotlin 2.2.20 was assessed
  and requested in-process, sharing that heap; task-level strategy was not
  independently measured. Tests were configured for one 512-MiB fork, and the
  app native pool for one job; runtime fork heap and current generated Ninja pool
  were not independently verified. Complete plugin-native coverage is not claimed.
  No memory failure or budget increase occurred. Retained shared-gate log:
  `d2fe65f641524835ad91d30572d420ba.log`.
- Same-signer in-place R-Shop installation succeeded; APK SHA-256
  `dab45cee288355d07e40c7e8b5ce06af294b61d7b873db0e86e5f340a6597e46`.
  The normal picker restored `/storage/75D7-DC5F/Roms/ps2`; the full source
  configuration returned to baseline SHA-256
  `45b35fbd1c1eec0cdc5d72dff803a373e758e8229e99dcbb76c7da38ec02d4bb`.
  Normal default-account reconnect and same-transfer Resume resolved the
  post-install authorization pause without replacing the queued transfer.
  SAME N64 job 70 resumed: running, pending 794, matched/rated 73. SAME root
  generation 1 resumed: observations 153,922, pending folders 7,697,
  nextGeneration=2, active=null. These are progress, not terminal coverage or
  publication. PSP-only Best-25 remains Provisional: 35/341 ranked, 25 results.
- Both physical screens are freshly committed OFF; Wi-Fi is enabled. Original
  ROMs, saves, settings, cloud files and FolderSync are preserved. Exact task
  device captures are absent. Reviewed cleanup
  `22c48dcae9863935312c835537ae10eb` removed 21 expendable host targets,
  reclaiming 177,289,189 bytes. Installed apps/BIOS, current R-Shop artifact,
  build log and bounded read-only S7 observer remain intentional outputs.
- A transient quick-menu failure was observed during search/download-overlay
  navigation. Normal Exit Application/reopen cleared it; the verified PS2 workflow
  used Installed Only. Root cause and reproducible regression are not established.
  Reliable search-to-menu navigation remains unfinished S7 work, not a fix claim.
- S7 remains the sole ACTIVE stage. Full fresh metadata, defensible per-console
  Top-25, root publication, remaining formats and reviewed save/space-safe migration
  remain required. Bulk provenance classification remains pending; unknown editions
  are not silently classified/ranked. S8-S10 are NOT STARTED. No release occurred.

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
| S10 | NOT STARTED | User save-backup and most-installed-emulator coverage instructions recorded in revision 7; revision 10 adds conditional legacy-sync retirement; initial read-only package discovery, not save-access proof | SAVE-01: every accessible installed-emulator route, evidence for inaccessible routes, separate backup consent, real backup/restore/emulator-load workflows, conflicts and last-good recovery; exact old device app uninstall and laptop save-sync task stop/disable only after replacement verification, followed by post-handover proof |

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
