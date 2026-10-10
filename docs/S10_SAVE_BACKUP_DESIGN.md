# S10 save backup — active implementation

Authority: SAVE-01 in SPECIFICATION.md. S10 is the sole ACTIVE stage; setup and
inventory do not satisfy SAVE-01 as a whole. S7 remains parked BLOCKED
on its independent reception/retention evidence. S11 is NOT STARTED.

Current acceptance revision, authorized by the user on 2026-10-09: verify that
restored bytes are written at the configured emulator's expected save location.
Skip gameplay, in-emulator save-load and deep save-content checks. Historical
dated checkpoints below retain their original observations but their outstanding
emulator-load gates are superseded by specification revision 15. The current
RetroArch-target publication receipt satisfies that narrow location/write check;
it does not close coverage or other unfinished S10 implementation. The standalone
PPSSPP destination/write and rollback checks below now pass as well.

## Installed-route audit and visible coverage — 2026-10-09

Current automatic-work slice, 2026-10-10: SAVE-01 requires backing up
changed saves, not publishing another immutable copy on every lifecycle event.
The previous job published identical captures repeatedly. The updated job compares
the freshly captured coherent group's format/roles,
lengths and digests with the last verified generation, and revalidate current
cloud heads through the existing account/area-bound transport. Skip publication
only when that exact verified generation is still the sole head and its contents
still agree. Missing or changed heads must not be treated as unchanged; divergent
branches retain existing explicit resolution. Recheck the current edition/launch
binding before recording unchanged completion. Preserve the durable last-good
generation and restore/rollback intents. Focused regression tests must reproduce
the duplicate, verify restart persistence and reject missing/divergent-head
shortcuts. These focused checks now pass. This remains S10 work, not a new stage
or Android scheduled-background-support claim.

The first unattended route is the explicitly mapped published PPSSPP slot:
SQLite stores opt-in per account/client/area/edition/artifact/directory/slot and
requested/handled event counters. App startup and resume dispatch a single
application-owned serial lane. Leaving Settings does not own/cancel that lane.
No timer, recursive scan, automatic restore, conflict choice or extra sign-in is
introduced. Every pass revalidates the configured source, prepared backup area,
current explicit slot mapping and edition binding, including after capture.
The existing sealed-capture/reserved-object journal supplies interrupted upload
recovery; a failed pass is shown rather than retried in an unbounded loop.
Persisted conflicts and restore intents remain explicit and block automatic
publication. Disabling the mapping persists opt-out and joins its active capture.
Controls remain inside the existing per-game Backup and Status sections, with
enablement gated by the current reviewed selection and confirmation.

Host verification covers opt-in/reopen/opt-out, unchanged and changed bytes,
divergent heads, interrupted publication/reserved-object reuse, pending restore,
mapping change during capture and serialized lifecycle events. A widget check
caught a Future-returning setState callback; the corrected synchronous callback
passes the opt-in/status/opt-out regression. Scoped analysis is clean and the
focused job/settings checks pass. The preserving production debug build, gated
request 554 (`2372051bfefa4699abf4aee1bdc15105`), completed with the gate acquired
and completion verified. Observed workers=2, parallel=false and Gradle heap=3 GiB;
assessed Kotlin 2.2.20 remains in-process. Test configuration is one 512 MiB fork
(assembly did not execute JVM tests); native environment budget=2 is not proof
of effective native concurrency. No memory failure or budget increase occurred.
Log: `105c9a2381094f20a233b5a96db5610c.log`.

The built and independently inspected installed APK agree on SHA-256
`5c27cde0501c590e4c5e1b1c7e79e0b35eae22a513a5a7c3ff74d0becf56c28c`.
The established debug signer and immediate protected preference/security hashes
were preserved. Startup now explicitly awaits SourcesNotifier readiness before
using its source snapshot; independent bootstrap completion is not proof that
the notifier has loaded. The existing catalogue refresh completed and the normal
library became responsive; an earlier lock warning was not evidence of deadlock.

Actual Thor verification used Patapon's already mapped published PPSSPP slot,
without changing its bytes. Normal Save backups selection/confirmation enabled
the return check. Leaving R-Shop for Home and returning dispatched the capture
and real Drive head review. Status completed with `Last automatic check:
unchanged; verified backup retained`, keeping the original 2026-10-09 verified
generation. Sealed capture `abc40288bcea95b698c172567946dd6e` contains 5,557,226
bytes; no new cloud generation was published by that unchanged path. Closing
and reopening the game backup screen retained both enabled state and outcome.
Normal opt-out worked after reopening without selecting/confirming again,
restoring the prior disabled policy. Before/after PSP slot and ppsspp.ini hashes
match the previously recorded values. No new sign-in, restore, emulator-settings
change or legacy-sync change occurred. Both actual/committed display states were
verified OFF afterwards. This proves app-return behavior, not a cold-process
native startup or Android scheduled-background execution claim.
Android scheduled background dispatch, other unattended emulator routes and the
rest of SAVE-01 remain ordinary unfinished S10 work, not tracked deferrals or
completed acceptance. RetroArch's UDP closed-content wait is not silently attached
to unattended events, and the old sync applications/tasks remain unchanged.

### Scheduled-dispatch implementation boundary

Use Android JobScheduler for one persisted, network-constrained periodic job per
application, installed only while an explicit automatic mapping is enabled. The
six-hour interval is a backup schedule, not a completion timeout or file-writer
delay; Android controls actual admission. No polling loop, exact alarm, screen
wake, automatic consent or foreground download-service takeover. Reconcile the
job on enable/disable and normal startup.

An existing UI engine receives the job on its existing application-owned lane.
If no UI engine exists, a dedicated Dart entrypoint loads only current backup
configuration, the existing SQLite journal and silent authorization, then exits
after the bounded mapping pass. It must not bootstrap the UI, run catalogue sync
or recover/pause unrelated metadata jobs. The background database connection
therefore omits the UI onOpen metadata-recovery hook and rejects an incompatible
schema rather than migrating it independently.

UI and headless engines share a native, process-owned save-operation admission
queue: all manual backup/restore and automatic operations take the same gate
before loading or changing their journal. Engine destruction/cancellation must
release only its owned admission; no lease expiry or guessed stale owner. Native
capture runs from application Context, but interactive emulator/settings actions
remain Activity-only. Job stop requests cancellation and joins it before engine
teardown; it does not report an unfinished pass as successful. Read current source
configuration and preferences again at capture/publication checks, not a stale
headless snapshot. Preserve existing conflict and interrupted-publication rules.

Acceptance for this slice: focused admission/cancellation and scheduler tests;
real Thor scheduled dispatch with screen off using the existing explicit slot;
unchanged backup retained; disable removes the schedule; process-cold execution
and overlapping UI/manual work must be verified before scheduled support is
claimed. These are current S10 acceptance, not another implementation stage.

Scheduled checkpoint, 2026-10-10: gated build 557, ticket
`6034b9d4a32544ec86c984d4c18d07ae`, completed successfully with the gate acquired
and completion verified. Inspected log `d6dd7a71d1f546a980820b0e665987f3.log`
records workers=2, parallel=false, Gradle heap=3 GiB, preserved 1 GiB metaspace /
256 MiB code cache and one 512 MiB test fork with fail-fast. Assessed Kotlin
2.2.20 uses in-process compilation; no separate compiler heap or memory-related
failure/budget increase. Native environment budget=2 is not universal effective
concurrency proof; the existing project CMake pool remains depth 1. Native gate
ownership, exact release, queued cancellation and owner-exit tests pass. Focused
Dart job/admission/settings checks and affected-file analysis pass.

Built and independently inspected installed APK SHA-256 agree:
`1823cf4670b585378c32da69fc8883d395799efd616a9a2f164e92ea088e7aa8`.
The established signer and immediate protected preferences were preserved by the
update. Later silent authorization can rotate secure storage; the install hash
comparison is not a claim that auth files never change during use.

Actual Thor JobScheduler inspection verified job 5395266: persisted, six-hour
periodic, network ANY, with no screen wake. Tests explicitly forced Android job
admission rather than waiting six hours; they prove its execution path, not an
elapsed-period observation. A normal app exit followed by removal of its cached
process (not force-stop) left the job registered; Android started a new process
for SaveBackupJobService with no R-Shop Activity. Screen-off headless execution
on build 557 returned the aggregate receipt enabled=1, pending=0, unchanged=1,
verified=0, attention=0 (finishedAt 1791589817611). Unlike a service completion
alone, this proves the mapped save was checked and its backup retained.

An explicit platform job-stop injection exercised onStopJob; receipt `stopped`
(1791589874002) is not backup success. The next forced admission recovered while
the UI was reopened alongside the headless engine: completed, enabled=1,
pending=0, unchanged=1, attention=0 (1791589933426). No duplicate cloud generation
was published. This proves UI/headless coexistence and cancellation/recovery;
native queue tests prove admission ordering. Direct observed manual-operation
contention remains required before claiming every overlap acceptance case.

Normal per-game opt-out without reconfirmation removed the registered job
(`get-job-state`: unknown / could not find). Status shows automatic checks
disabled and the original verified backup dated 2026-10-09 22:01:12.549938, with
the unchanged outcome. Before/after PSP slot, ppsspp.ini and both source config
hashes match. No restore, new consent, legacy sync change or archive write.
Both actual and committed physical display states were checked OFF afterwards.

Remaining bounded-work defect found during this verification: successful
unchanged checks retain redundant sealed local captures. Their directories
accumulate despite no new cloud generation. Journal-aware exact local-stage
retirement is ordinary unfinished S10 work, not cloud-version pruning or an S11
deferral. Preserve pending upload, conflict, restore/rollback and last-good
recovery references; do not blanket-delete the existing capture root.

Next accessible route under the same ACTIVE S10: Game Gear cartridge battery
saves through the already configured RetroArch Genesis Plus GX launch. Reuse the
existing closed-content capture, immutable generation transport, explicit
conflicts and one-file atomic restore/rollback. Bind the exact encoded ZIP launch
leaf, Game Gear platform, Genesis Plus GX core, distinct SRAM format and fixed
reviewed core save directory. Existing mGBA journals retain their original default
binding; neither route can replay the other's captures/restores. Unknown routes,
oversized SRAM and unexpected related files fail before publication. This does
not claim CD backup RAM, states, custom paths or other consoles are finished.

The inspected [Genesis Plus GX libretro boundary](https://github.com/libretro/Genesis-Plus-GX/blob/master/libretro/libretro.c)
exposes cartridge SAVE_RAM up to 65,536 bytes, no RTC memory type, and separate
CD BRAM handling. The installed shared core directory exists and was empty in
the read-only audit. Acceptance for this slice remains a normal game-entry
backup/download/restore/rollback at its exact emulator destination with an
expendable fixture, plus route-isolation regressions. Source inspection alone is
not native proof; no completed-route label is added before live verification.

### Game Gear cartridge route verified — 2026-10-10

The normal reviewed cloud game entry now reaches the Genesis Plus GX cartridge
backup route. Its existing local ZIP was checked through the ordinary exact-byte
review, not adopted, overwritten or redownloaded. That records a read-only copy
binding and collapses the verified local/cloud entry. The unbound local entry
correctly offered no edition-bound save action before that review.

The native launch review returned the exact encoded document leaf. A new,
disposable 50-byte SRAM fixture was placed only at that reviewed save path in
the previously empty shared core directory. Normal selection, edition
confirmation, closed-content capture and Drive publication/readback completed.
Capture `ae5abe6a389d2005edb4c13d6ed9ef87` and the independently hashed fixture
agree on SHA-256
`615ee59dcb4a9aa4c9447f9e6f0cd26cd255c4869a30dba3226088db771c0ab5` (A).

The disposable local file was then changed to B, SHA-256
`f526b1ee6e62bdc97e83b684395803dc5e2b93adab534a5c3566c827a962d41d`.
Normal explicitly confirmed cloud restore downloaded/verified A, retained B as
capture `2976105995836566838993e510b7b612`, and published A at the expected core
save path. Receipt `1b0c3879d6aa9b00ef183c87134a86d0` is `published` with matching
length/digest, namespace and rollback binding. Independently hashing the shared
destination confirmed A. Explicit retained-local rollback then published B;
receipt `7ae7a6ff6fa50f5fffb0f9767fe0d34b` is `published` and preserves replaced
A in capture `021b78fe94dd952f6dcc4c531eb9f3a1`. The destination independently
matches B. RetroArch remained contentless; foregrounding it serviced its actual
command receipts, without killing it or treating a delay as writer completion.

The disposable shared save was removed after hash-verified rollback, returning
the directory to empty. Retained captures/receipts and the test cloud generation
remain for recovery evidence; no cloud generation was deleted. These are mock
transport fixtures, not genuine game progress or an emulator-load claim. The ROM
archive, RetroArch configuration and prior PSP slot/configuration hashes stayed
unchanged. An incidental favourite/column change during UI navigation was
returned to the original zero favourites/four columns. No legacy sync app/task
was changed. No new sign-in was needed.

Focused capture/job/launcher/settings checks and scoped Dart analysis pass.
The targeted native binding test ran successfully through gated request 545;
tests were prepared first but no pre-implementation red result was observed.
Gated request 548 (`cb46a0b240c84595ba5ac80714712c0f`) then ran the complete
affected native binding/storage classes plus debug assembly successfully.
Gate acquired; observed two workers, parallel=false, Gradle heap=3 GiB,
previously assessed Kotlin 2.2.20 in-process, preserved 1 GiB metaspace/256 MiB
code cache and one 512 MiB test fork. Native environment budget is two; effective
native concurrency is not independently established by those markers. No memory
failure/budget increase. Log: `83e35affcfc34979975beeb48f548be6.log`.
The same-signer preserving installation and independent installed base.apk hash
match SHA-256 `0204aea67afcae1d962dfd522f8a4387233bf02f0fc02d615fd587660e6e4f35`.
All protected preference/security hashes matched immediately after replacement.

The post-proof coverage label now includes only the reviewed Game Gear cartridge
SRAM route, leaving other cores/states/custom paths unfinished. A focused
regression also reproduced unexpected related-file rejection being reduced to
generic `capture_unavailable`; preserving `related_group_unfinished` fixes that
status while retaining the last verified backup and making no cloud publication.
The changed checks pass after the correction. Gated assembly 551
(`125fdaeba8b841b7ad34ea19a5f80024`) completed exit zero with the shared mutex
acquired and confirmed supervised completion. Observed workers=2, parallel=false,
Gradle heap=3 GiB, Kotlin in-process with the previously assessed plugin version,
preserved metaspace/code-cache flags and configured one 512 MiB fail-fast test
fork (assembly did not execute tests). Native environment budget=2; effective
native concurrency remains unverified. No memory failure or budget increase.
Log: `c11742625a6c48d6bc79d019bc2ccc11.log`.

Preserving same-signer installation succeeded. The independent installed APK
digest equals the built artifact:
`9da09e8dab3f3db775d9516d3f04028c1c55c5704f6f352532eae8b93fef60dd`.
All three protected preference/security hashes match immediately before/after
replacement. Normal Settings -> Save backups reopened the prepared area without
sign-in; Emulators on the Thor displays the reviewed Game Gear SRAM label, with
coupled RTC restoration, states and other routes explicitly unfinished. The
fixed left rail remains visible while only the selected content scrolls. ROM and
RetroArch configuration hashes still match; the fixture directory is empty.
The task-owned UI XML was reviewed and removed; both physical displays report
committed OFF and device wakefulness Asleep. Final focused capture/job/launcher,
coverage and section-settings checks passed against this unchanged code; the
affected native XML results were inspected with no failure/error/skip.
The preceding real capture/restore/rollback proof applies to unchanged route
logic. S10 remains
ACTIVE with installed-emulator coverage, coherent related groups, automatic work,
fault/reinstall/live conflict and conditional handover acceptance still required.

A fresh read-only Thor package audit confirms the 27 known emulator, embedded
runtime, port and frontend packages represented by the coverage catalogue.
Save backups now has a separate Emulators section, independent of Drive setup.
It requests only installed package/version and advertised DocumentsProvider
authorities, on entry or explicit refresh. It neither enumerates save files nor
requests storage grants. Section changes retain the inventory and existing job;
an inventory error is not rendered as an empty/successful audit.

Coverage distinguishes saves from states. The reviewed RetroArch 1.22.2 mGBA
SRAM and PPSSPP 1.20.4 slot routes are narrowly identified; coupled RTC restore,
other cores, SAVEDATA and remaining emulator routes remain unfinished. An
unreviewed runtime update cannot inherit a verified route label. ES-DE and Cocoon
are classified as launchers, not independent save owners. Uninvestigated routes
remain unfinished rather than being falsely classified as unsupported. This is
the known-package inventory, not a claim to identify every future installed app.

Live package metadata exposes DocumentsProvider components for Dolphin, Cemu,
KenjiNX and NeoStation. Dolphin 2606 advertises authority
`org.dolphinemu.dolphinemu.user`; NeoStation advertises
`com.neogamelab.neostation.documents`. The current upstream
[Dolphin provider source](https://github.com/dolphin-emu/dolphin/blob/master/Source/Android/app/src/main/java/org/dolphinemu/dolphinemu/features/DocumentProvider.kt)
exposes user files through an exported, grantable document provider. Its rename
implementation allocates an unused destination rather than replacing an existing
entry. Therefore generic SAF rename is not evidence of atomic save replacement.
This source observation is not a pinned-runtime restore verification or a
classification that Dolphin is unsupported. Legitimate picker/export routes,
save-specific grouping and safe publication remain required implementation work.

Focused host checks verify the offline section, retained inventory, separate
save/state claims, runtime changes, malformed/substituted inventories and
provider-advertisement versus grant/support semantics. Two additional regressions
reproduced and corrected workspace unmounting on coverage navigation and an
immediate channel failure escaping before the next frame attached its listener.
The workspace now remains mounted with hidden controls excluded from focus;
failed refresh is an explicit unavailable result, never stale success or an
empty installed list. Compact/enlarged-text and controller section checks pass.

Gated assembly 539 completed but was not installed because the workspace/error
corrections postdate that artifact. Corrected assembly 542 completed successfully
through ticket `a9cdaafa73af453f8b2c388f8192756e`; the original supervisor/session
was retained through completion. Observed workers=2, parallel=false, Gradle
heap=3 GiB with preserved 1 GiB metaspace/256 MiB code cache; Kotlin uses the
previously assessed in-process strategy. Test-task configuration is one 512 MiB
fork (assembly did not run those tests); native environment budget is two, not
claimed as independently verified effective concurrency. No memory failure or
budget increase occurred. Log: `56270adfefc74128b2a355675b1102cc.log`.

The signer matched the established debug identity. Preserving installation
(`adb install -r`) and independent installed base.apk digest both verified
SHA-256 `54a561d269a76a051d25c7a8cdec7853f874af63b5bbc911b9ad5a3ef7165285`.
All three preference/security file hashes matched immediately after installation.
Normal Settings -> Save backups -> Emulators displayed actual installed Azahar,
Cemu, Cocoon and Dolphin versions, including the advertised Cemu/Dolphin document
authorities and the explicit unfinished-route/grant qualifications. Refresh and
touch scrolling worked. D-pad Up/A selected Status; Down/A returned to Emulators
with the retained inventory. The compact screen shows the fixed section rail and
only the selected section, not a combined settings roll.

The pre-existing catalogue synchronization resumed and advanced normally during
the UI check. Security/preferences containers subsequently changed, so an
unchanged-container claim is limited to the immediate preserving-install check;
the secure key-storage hash and PSP slot/configuration hashes remain unchanged.
No account reset, save mapping/write or storage grant was performed. The leftover
Clock companion test was returned to Home on the bottom display. The task-owned
UI dump was removed and both physical displays report committedState OFF with
wakefulness Asleep. This verifies native coverage presentation, not all listed
save routes. S10 remains the sole ACTIVE stage, with no acceptance reduction or
deferral. Legacy sync is unchanged.

## Standalone restore and rollback verified — 2026-10-09

Normal selected-game Save backups -> Restore & conflicts resumed the retained
Patapon fixture. The first attempt preserved its pending intent and local bytes
on `authorization_unavailable`: Android reported a hotel captive portal and
microG logged `NoRouteToHostException`. After the same network became VALIDATED,
explicit Resume obtained the existing account grant without account selection,
downloaded/verified the cloud bytes, and reached `stop_ppsspp_required`.
The slot and PPSSPP configuration hashes were still unchanged. No account reset,
timer retry, duplicate backup or emulator termination was added to recover this.

The normal PPSSPP App info button opened Android settings. With the fixture
already exited to PPSSPP's menu, explicit Force stop/OK set `stopped=true` and
the package process was absent. Returning without reopening PPSSPP and confirming
Resume completed restore at the reviewed Memory Stick slot. Native restore
`35c71799a9b2d0c63e48780041896b44` has a durable `published` receipt, bound to
`ppsspp-slot-v1` and the explicitly mapped source. Its staged inode 423763 became
the destination. The 5,557,226-byte destination, sealed cloud member and retained
rollback `afd7295466b606cbb73e12979bf83ca7` all independently hash to
`ef64997dfb2f43e04d1c9b86416b98ab61b71c189f7c37026de7ce2db735cc53`.
Identical fixture content is not claimed as a changed gameplay save; the inode
and publication receipt establish the completed replacement, not just a no-op hash.

Explicit Restore retained local save, with its own confirmation, then completed
through receipt `2568c0d6d449e3c1b257ef43638c0b88`, destination inode 463104 and
the same expected length/digest. Its replaced local generation is separately
retained in capture `8b30a51055bd1ebd3da910ee73ee6663`. Normal Status reported both
completed actions. Leaving/reopening Save backups retained the verified backup
without a pending-restore prompt or new sign-in. PPSSPP configuration SHA256
remained `17e268f3f0626d414f01b3ae2864f37686543a47698bd3edc9fa814a9170111b`;
no ROM, battery save, thumbnail or cloud original was selected for replacement.

Fresh focused host checks cover capture/staging, job persistence, PPSSPP conflict
preservation-before-restore, generic conflict ancestry/failures, settings section
isolation and exact owned-launch save review. Scoped analysis and diff checks pass.
The native binding/runtime tests and APK assembly passed through gate ticket 534
(`c7b8f3838f5a46e8b2c2af9180fc7359`), gate acquired and completion verified:
workers=2, parallel=false, Gradle heap=3 GiB, preserved 1 GiB metaspace/256 MiB
code cache, assessed Kotlin 2.2.20 in-process, one 512 MiB fail-fast test fork.
The unchanged native compile/link pool is depth one per ABI; no host-wide native
cap is claimed. No memory failure or budget increase. Build log basename
`90805e7756314625a35cf6ea27d67608.log`. Candidate and independent installed APK
SHA256 match `0e82accd4772fe8d99e0b133675a6a16e4c54b99636fd9dafb77429407964438`;
the existing signer and all three observed protected-preference digests matched
after preserving install. No subsequent production change invalidates this build.

The current native `owned_storage.cpp` and its filesystem contract were also
compiled once with NDK 28.2, C++17, warnings-as-errors and a static C++ runtime,
then executed in a new exclusive `/data/local/tmp` fixture on the Thor. The
reviewed-save replacement contract passes: changed current/staged identities
are rejected, successful replacement retains the staged inode/bytes, and the
rollback bytes remain intact. Existing traversal/link/no-replace/quarantine
contracts also pass. Its individually tracked fixture self-cleans; the exact
device binary was removed and both paths are absent. The disposable host binary
is reclaimed through the reviewed task-owned cleanup ticket, not a cache purge.

The exact temporary UI XML was removed. Both physical screens report committed
OFF and wakefulness Asleep. S10 remains ACTIVE: live divergent-conflict evidence,
remaining installed-emulator routes, background/fault/reinstall work and the
conditional legacy-sync handover are not closed by this two-emulator slice.
S7 remains BLOCKED, S11 NOT STARTED; no required deferral or waiver is introduced.

## Cloud conflict workflow — 2026-10-09, host verification

### PPSSPP restore boundary — implementation and native verification

The Thor's shared PPSSPP_STATE filesystem rejected `renameat2(RENAME_EXCHANGE)`
with EINVAL in an exclusive two-file capability fixture. The fixture was removed;
no existing slot was touched. Do not use atomic exchange or infer writer completion
from a paused activity, low CPU, a delay or a UsageStats lifecycle event.

Restore now uses the existing sealed local rollback, streamed cloud verification,
same-parent staged replacement and durable publication receipt. The native restore
journal binds the exact `ppsspp-slot-v1` format and explicitly selected state root;
legacy mGBA journals retain only their original fixed mGBA route. Replay cannot
retarget the same restore ID to another root or format. One exact mapped state slot
is restored; JPEG thumbnails, undo/temp files and SAVEDATA are not silently selected.

Before public staging and again before replacement, require Android's documented
ApplicationInfo.FLAG_STOPPED for the reviewed PPSSPP package/version. The Restore
section opens Android App info; the user exits the game safely, uses Force stop,
then returns without reopening PPSSPP until restore completes. This is explicit
user-mediated restore preparation, not an automatic emulator termination or a
capture prerequisite. Capture continues to pin/verify completed state files without
killing the emulator. R-Shop never sends a kill/force-stop command. Preserve the
rollback and pending restore on a failed precondition, so normal Resume can continue.
A lost post-rename acknowledgement reconciles the staged identity and receipt
without rewriting the slot. This retains the original SAVE-01 publication and
conflict criteria. Native compilation and the real destination/write checks are
verified above; this does not assert universal exclusion of arbitrary external
writers or authorize restarting PPSSPP during restore.

Primary references: [Android stopped-package flag](https://developer.android.com/reference/android/content/pm/ApplicationInfo#FLAG_STOPPED),
[PPSSPP 1.20.4 slot publication](https://github.com/hrydgard/ppsspp/blob/v1.20.4/Core/SaveState.cpp).

### Standalone PPSSPP backup — real Drive, 2026-10-09

The installed PPSSPP package `org.ppsspp.ppsspp`, v1.20.4, was still at its
first-run Memory Stick setup. Through its normal SAF picker, create/select
`/storage/emulated/0/PSP`; no existing save directory was moved or overwritten.
Launch the existing Patapon CHD using PPSSPP's official shortcut extra. Without
gameplay, use initially blank slot five at the title screen, then Exit to menu.
The newly published file is
`/storage/emulated/0/PSP/PPSSPP_STATE/UCUS98711_1.00_4.ppst`, 5,557,226 bytes,
SHA256 `ef64997dfb2f43e04d1c9b86416b98ab61b71c189f7c37026de7ce2db735cc53`.
PPSSPP also created its normal JPEG thumbnail; no battery save was created.
Keep this defined restore fixture and the intentional Memory Stick configuration.

The normal selected-game R-Shop Save backups workflow selected that directory
with its own folder picker, selected the exact slot, confirmed the edition
binding, and invoked Back up reviewed save. Status reached Verified backup at
2026-10-09 22:01:12.549938, one file, after the real immutable Drive transport's
upload/readback checks. No account chooser, re-consent or debug-injected upload
was used. Native sealed capture `e2a49e43312054dbb7c21649e150c80e` records the
same filename, size, digest, `ppsspp-slot-v1` format, v1.20.4 runtime and selected
root; its captured `member-0` digest independently matches the original state.
The cloud generation ID was not independently extracted, so none is asserted.
This historical checkpoint established standalone backup only. The subsequent
restore/rollback verification above supersedes its then-disabled restore state;
conflicts and the remaining SAVE-01 criteria are still separately tracked.

A subsequent read-only UI inspection still shows persistent Backup area / Back
up save / Restore & conflicts / Status navigation with only Status content in
the workspace. Fresh focused save-settings checks pass. The exact temporary
`/data/local/tmp/rshop-s10-ppsspp-ui.xml` was removed; both physical display
devices report OFF / committedState OFF and wakefulness Asleep. No Gradle build
was launched for this check. Legacy device/laptop sync is unchanged.

### Navigated save settings — specification revision 16

The user's no-long-roll settings requirement now applies explicitly to save
management and subsequent settings additions. Save management uses the metadata
screen's persistent responsive left navigation: Backup area, Back up save,
Restore & conflicts, Status. Only the selected section renders its controls.
The same game panel/state survives section changes, including a visit to Backup
area; source/account changes still retire the old binding. Section navigation
does not restart or cancel jobs. A fixed running/cancel strip remains available
when setup or capture is running, and completed/error status is directly linked
outside the scrolling content. Navigation resets only the content scroll, not
the selection or operation. Controller navigation has one focus target per
section, with no hidden controls in traversal.

Fresh focused widget/job verification passes: narrow portrait at enlarged text,
left/content separation, touch and Down/A navigation, retained selected file and
confirmation through every section, running-capture continuity without duplicate
capture/upload, and separate restore/conflict confirmation paths. Scoped Dart
analysis and diff checks pass. Native inspection of build 520 exposed that touch
section selection did not transfer focus to its single controller target. A
focused regression reproduced this without programmatically assigning focus;
explicit section-owned focus nodes correct the handoff. The updated check passes.

Gated build 521 (`37f4b4eb35954156b5c9635eec191cf0`) completed successfully,
with gate acquisition and confirmed exit: actual workers=2, parallel=false,
Gradle heap=3 GiB (1 GiB metaspace/256 MiB code cache preserved), assessed Kotlin
2.2.20 in-process. Test tasks configured one 512 MiB fail-fast fork; assembly
did not run them. Unchanged native compile/link pool is depth one; no global
native cap is claimed. No memory failure or budget increase. Private log basename
`ee50394a78224bab84036a0b7d62e3e5.log`. Candidate and independent installed APK
SHA256 `3d8c1f799917f1fcd0b75a16abb4392e6c134f415d1a0521d2c2452c6fd68b22`,
same signing certificate as ticket 515. Preserving installation succeeded and
all observed preferences/save/configuration hashes matched immediately afterward.
Normal Thor Settings -> Save backups shows the persistent four-section menu;
touching Status then D-pad Up/A selects Restore & conflicts and removes setup
controls from that workspace. The normal selected-game Save backups route also
shows separate Restore and Status pages, with the recorded verified backup
recognized without sign-in. Choosing its exact reviewed file and confirmation,
visiting Restore, Status and Backup area, then returning to Back up save retains
both selection and checked confirmation. Native screenshots were visually
reviewed. No backup/restore/cloud write was initiated for this UI check. All
observed save and emulator-configuration hashes remained unchanged. Both physical
displays are OFF. This checkpoint does not close S10's remaining acceptance criteria.

Menu recheck on the currently installed preserving candidate (gate 527),
2026-10-09 21:47 +02:00: normal Settings -> Save backups still shows the four
left-hand sections. Touch Status, then D-pad Up/A selects Restore & conflicts;
backup-area controls are absent from that workspace. Normal Game metadata still
shows its left-hand ScreenScraper / IGDB / shared metadata / ES-DE sections and
the focused ScreenScraper Credentials and Scraping actions. No settings, saves
or cloud objects were changed. The temporary device UI dump was removed and
both physical display devices report state OFF / committedState OFF.
Fresh save-settings widget checks and the focused game-job file pass, including
selection/confirmation retention and running-capture continuity. A separately
filtered run of the continuity test failed loading GoogleFonts Outfit-Bold over
the test HTTP boundary; the complete focused file passes. This is a remaining
test-fixture isolation issue, not evidence of a production navigation failure;
do not cite that filtered run as passing or claim all S10 acceptance is complete.
No Gradle command was launched for this recheck.

### Current preservation correction

The private-capture limitation in the earlier checkpoint below is now corrected
in source. Before accepting a cloud choice, publish the sealed local generation
using its already durable reserved IDs through the existing verified immutable
publication API. Do not start cloud download/local replacement if preservation
fails. Re-enumerate current heads after publication: discount only our expected
preserved branch, and reject any other change until the user reviews it again.
Keep the chosen cloud objects unchanged. Persist the resolved head set with the
cloud restore choice; the next backup incorporates those explicitly acknowledged
heads into ancestry rather than rediscovering the retained losing branch as an
unexplained conflict. Subsequent unreviewed branches still require a choice.

Test-first regressions reproduced missing preservation, restore despite failed
preservation, missing concurrent-change rejection and repeated-conflict behavior.
Fresh focused job checks pass for these behaviors, same-reserved-ID resume,
independently discoverable retained local manifests, unchanged remote objects,
and recovery of a pending capture created before the ancestry field existed.
Scoped Dart analysis and diff checks pass. Gated Android assembly 519 now
contains this correction and completed successfully; live conflict verification
is still required. No full-stage completion or independently reinstalled UI
recovery is claimed by the transport fixture.

Ticket 519 (`20f81640360e4788a6baa539b3771703`) acquired the shared gate and
completed with verified supervision/exit zero. Actual profile: two workers,
parallel=false, Gradle heap=3 GiB, preserved 1 GiB metaspace/256 MiB code cache,
Kotlin 2.2.20 in-process. Configured tests use one 512 MiB fail-fast fork; assembly
ran no tests. Unchanged native CMake compile/link pool depth is one; no global
native-cap claim. No memory failure/budget increase. Private log basename:
`9be102375c754751aa845c721e19a6e8.log`. Preserving installation succeeded; candidate
and independent installed APK SHA256:
`b4efb8a421fea8c219a0654507673b223f2c6aa99906ef589aab040df7b69784`.
Certificate SHA256 remains the one recorded for ticket 515 below.

All observed save/configuration/preferences hashes matched immediately after
installation. Normal UI backup then completed at 20:37:14 on 2026-10-09 with real
Drive publication/readback, without another consent/account prompt. This exercises
the new pending-record ancestry path, not a divergent cloud choice. After this
normal runtime work, all fourteen save hashes, global/core/remap configuration,
shared preferences and secure wrapping-key preferences still match. Encrypted
secure-storage file bytes changed during authenticated runtime work; no claim of
unchanged token ciphertext is made. No owner fixture bytes were changed for
conflict seeding. A read-only VM inspection could locate the job, but source
evaluation was unavailable without a compilation service, so no debug mutation
or synthetic second client was performed. Its temporary port forwarding was
removed. Both physical displays were confirmed OFF; the expendable screenshot
was removed through an exact reviewed cleanup ticket. Legacy sync is unchanged.

### Corrected filename build 515 — real normal backup/restore

Gated ticket 515 (`e61769afe49e4af4aa15f2b281ababa0`) completed successfully:
workers=2, parallel=false, observed Gradle heap=3 GiB, preserved 1 GiB metaspace
and 256 MiB code cache. Kotlin 2.2.20 was assessed and ran in-process. Test tasks
were configured one 512 MiB fail-fast fork; assembly ran no tests. The unchanged
native CMake compile/link pool remains depth one; generic supervisor output does
not prove a host-wide native concurrency cap. No memory failure/budget increase.
Private log basename: `b30ba4aedaa840658d4ac814667bf4f7.log`.

Preserving `adb install -r` succeeded. Candidate/independent installed APK SHA256:
`864c1fa75daedb7baed7e37b3afc0d1bdfc18e287d2784f6ba44d36aa141b5b9`.
Observed signing certificate SHA256:
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Immediately after installation, secure preferences, shared preferences, fourteen
observed mGBA save hashes, RetroArch global/core configuration and actual
`config/remaps/mGBA/mGBA.rmp` matched the pre-install observations. Normal UI
navigation afterwards can change view preferences; no claim of unchanged view
preferences after that navigation is made.

The normal Aero agent-fixture backup published/read back one 512-byte SRAM
generation at 20:10:58 on 2026-10-09, capture
`35ffdd3bd9f8fff45379bfd04322e5aa`. Normal explicit cloud restore completed with
native `published` receipt `afd57651c12e0130010243431c0ddcd3` and rollback capture
`bfd7c90aead9e85270219ab613d8d763`. Expected current-installation mGBA target:
`6b693de3f9759ed6c83983a0b19b0032b0320fae3c273e5bf3262a72c4d8196a%2FAero%20the%20Acro-Bat%20(Europe).srm`.
Capture/restored SHA256:
`610c7c8507fb95205ea7e5172031dbe176fd0fe3f51b6ee6568edbeda4ee3fc7`.
No gameplay/deep save checks were performed or required. Legacy device/laptop
sync configuration was left intact, and both physical displays were confirmed
OFF. This normal real-Drive workflow predates the preservation correction above;
it does not constitute live conflict or whole-S10 acceptance.

### Earlier checkpoint

The per-game backup previously consulted only its locally stored last-verified
generation. Immutable uploads preserved old objects, but did not discover a
newer branch from another installation. A focused regression reproduced that
missing conflict stop before implementation.

The backup transport now enumerates every page of app-owned generation objects
inside the verified backup area, validates ownership, manifest digest and exact
restore compatibility, and rejects incomplete discovery. Payload-only objects
are not publications. The job derives current branches from recorded ancestry,
not clocks, and checks before and after publication. A concurrent publication
leaves both immutable branches intact and records a conflict instead of claiming
that the local side won.

Normal UI offers explicitly confirmed captured-local or selected-cloud choices,
with Cancel focused by default. Captured-local resolution creates new reserved
objects descending from all reviewed branches; it never rewrites an existing
manifest or payload. Cloud resolution retains the local capture in the durable
conflict archive, then uses the existing rollback-preserving restore path. A
changed set of cloud branches invalidates the displayed choice. The selected
cloud restore is durable even if recording its first native restore intent fails;
backup remains blocked until that restore is resumed. Retained local conflict
captures are app-private at this checkpoint, not claimed as cloud copies.

Fresh focused host checks pass for paginated/cross-device discovery, incomplete
listing rejection, pre-publication conflict stop, both explicit choices,
unchanged prior cloud objects, changed-choice rejection, concurrent publication,
durable restore-choice recovery and confirmation/cancel UI. Existing transport
and manifest safety checks also pass. Scoped Dart analysis reports no issues;
`git diff --check` passes. This is host verification, not live conflict acceptance
or completion of SAVE-01. Android assembly request 512
(`61c2617b4d4144a19743039b426907f3`) remains supervised in the shared build queue;
no gate acquisition or native verification is claimed yet. Legacy sync remains
untouched and both Thor displays were confirmed OFF before the update.

Subsequent current-target audit found two installation-specific Aero filenames
with identical SRAM bytes. A focused regression reproduced a false conflict
when those names differed: the generic manifest digest correctly includes source
paths, but this format-specific job must compare SRAM/RTC roles independently
of installation filenames. After build 512 completed, this correction was made
without changing its in-flight inputs. Fresh job checks now pass for reinstall
equivalence and RTC divergence as well as the conflict/restore behaviors above;
scoped analysis is clean. Original transport manifests and digests are unchanged.

Build 512 completed with exit zero, acquired gate and verified supervisor
completion. Observed workers=2, parallel=false, Gradle heap=3 GiB with preserved
1 GiB metaspace/256 MiB code cache; Kotlin 2.2.20 remains in-process. Test tasks
were configured one 512 MiB fail-fast fork but were not executed by assembly.
Unchanged native compile/link configuration uses the depth-one rshop_native pool.
No memory failure or budget increase. Private log basename:
`9d6ca13b5f5842d89775a4a671751f73.log`. That APK predates the filename correction
and is not the live-test candidate; the corrected assembly is separately queued
through the same gate. Live conflict acceptance remains unfinished.

## First real workflow

Prove RetroArch plus a standalone emulator before broadening coverage. On
2026-10-09, Thor `bfa98654` has shared RetroArch saves/states and a shared Azahar
user directory containing actual save data. These are candidates, not proof of
R-Shop access, reviewed edition association, coherent capture or restore to the
expected location. Use existing exact edition/artifact identities; never infer a save's
edition solely from its basename or a similarly named catalogue game.

The narrow implementation uses the existing serialized Drive authorization lane.
An explicit backup-consent operation requests only `drive.file` for the already
bound account, without reselecting it. Silent background backup cannot request
consent. Backup grants are distinct from ROM grants; ROM metadata/media APIs keep
their read-only interfaces and scope. Persist opt-in/mappings separately from
credentials. No full-Drive write scope, source mutation, folder mirroring,
cloud deletion or external-sync configuration import is permitted.

Create a private app-owned backup area and immutable generation objects. Publish
the complete manifest only after streamed capture and uploaded-byte verification.
Record account/device/emulator/core/platform/reviewed edition, save versus state
format, related file members, digests and ancestry. Discover retained generations
by app ownership markers after reconnect/reinstall. A folder name or selection
does not authorize its existing descendants. Restore verifies exact identities,
compatibility and destination access, preserves an explicit rollback generation
and publishes coherently. Divergent ancestry/digests require explicit choice.

No general sync engine, cloud version pruning or automatic user-save removal is
part of S10. Cancellation/source changes preserve the last complete generation.
Native stable-capture evidence must establish writer quiescence or a supported
export boundary; repeated equal timestamps or arbitrary delays are not proof.

## Entry observations and unfinished route audit

Read-only package/path audit; versions were read from installed package metadata.
ADB visibility is **not** an Android application permission grant. Save/state
coverage in every row is unfinished until a normal app route is implemented and
verified. No row is classified unsupported merely because investigation remains.

| Installed emulator/runtime | Observed version | Entry path/route evidence; remaining investigation |
| --- | --- | --- |
| RetroArch `com.retroarch.aarch64` | 1.22.2_GIT | Shared `/storage/emulated/0/RetroArch/saves` and `states`; configuration sorts by core, not content directory. Actual mGBA/SameBoy/melonDS/N64/PS1 saves exist. Related RTC and shared memory cards require separate group treatment. |
| Azahar `io.github.lime3ds.android` | 263745c1d-vanilla | Shared `Games/Emulators/Azahar`; title-scoped `sdmc/Nintendo 3DS/.../title/00040000/.../data` contains actual saves. Exclude installers/content, shaders, sysdata and settings. Verify title/edition and save-container grouping. |
| PPSSPP `org.ppsspp.ppsspp` | 1.20.4 | External-files root empty; previously checked shared PSP locations absent. Resolve configured Memory Stick folder through supported UI. Official documentation supports choosing a shared PSP folder; do not silently relocate existing data. |
| MelonDualDS `me.magnum.melondualds` | 0.8.0.rc2 | External-files `saves` observed, including a zero-byte `.sav` (not valid save proof). Investigate shared/custom/export route and separate state compatibility. |
| Dusk `dev.twilitrealm.dusk` | 1.4.1.1 | No external-files root at checked location. Investigate actual fork, storage and export routes. |
| KenjiNX `org.kenjinx.android` | 2.1.0-nightly.20260920+280c427 | External-files `bis`, profiles, sdcard/system; shared Kenji-NX folder contains firmware. Investigate supported save export/import, not firmware copying. |
| Flycast `com.flycast.emulator` | v2.6 | External-files `data`, `emu.cfg`, mappings; BIOS `.bin`/`.zip` mixed in `data`. Whole-directory or extension-only backup is prohibited. Investigate configured shared save/export route. |
| NeoStation `com.neogamelab.neostation` | 0.13.0 | External `user-data` has frontend database/systems/themes. Determine embedded cores and their actual save ownership rather than assume a PS1-only emulator. |
| Dolphin `org.dolphinemu.dolphinemu` | 2606 | External-files GC/Wii/StateSaves; investigate supported user-data/export and per-game GCI versus multi-game memory-card groups. Do not copy all GC/Wii/configuration. |
| NetherSX2 `xyz.aethersx2.android` | v2.1-4248 | External-files memcards/sstates mixed beside BIOS/configuration; investigate legitimate export/shared routes and multi-game cards. |
| Cemu `info.cemu.cemu` | 0.5.2 | External-files mlc01; investigate save-only `usr/save` export/import, not whole MLC. |
| GameNative `app.gamenative` | 1.0.6 | External files expose wine logs; investigate installed containers' supported per-game save mappings. |
| WinNative `com.winnative.cmod` | v0.7.0-beta | Shared WinNative root and external logs; investigate container/user-selected per-game paths. |
| Starboard `org.force9.starboard` | 0.30.1 | Shared Starboard root observed; investigate runtime/save ownership and export. |
| DualDex `com.darkaxt.dualdex` | 1.2.0 | External-files empty; installed embedded GBA workflow requires its supported save mapping/export investigation. |
| DualSouls `io.github.darkaxt.dualsouls` | 2.0.0 | External actual user/shared `.dat` files beside logs/mods; investigate game/version grouping and legitimate shared/export route. |
| RetroHrai / Cocoon / ES-DE | 0.6.0-alpha06 / 3.07 / 3.4.1-58 | Frontend data observed. Reconcile delegated versus embedded emulation; do not claim frontend settings or scrape reports are saves. |

The complete installed inventory also includes Solarus, Picori/TMC, Zelda3,
LADXHD, Ship of Harkinian, Gen2Recomp, Pokémon Red and Balatro ports. Their
save ownership/access remains ordinary unfinished S10 work, not an unsupported
classification. Refresh the full installed inventory at closure, including any
new forks. Coverage UI must distinguish saves, states and explicit limitations.

Primary route references:

- [PPSSPP Android storage](https://www.ppsspp.org/docs/getting-started/save-data-and-storage/)
- [Android other-app storage restrictions](https://developer.android.com/about/versions/11/privacy/storage#other-apps-data)
- [Drive per-file scope](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)

## Remaining acceptance / handover

Stable streamed capture and durable
bounded work; real RetroArch and standalone backup/expected-location restore round trips; remaining
accessible routes and visible coverage; explicit conflict/restore/rollback;
fault/relaunch/regrant/reinstall recovery; touch/controller workflow; protected
ROM/BIOS/settings proof; closure inventory; then exact legacy app/task identity,
safe joined handover and a subsequent working backup/restore round trip.

FolderSync and the scheduled task invoking `sync-retrobat-saves.ps1` remain
unchanged until all replacement gates pass. Both Thor screens were observed
Asleep/OFF during read-only entry investigation. No save was uploaded or modified.

## Verified setup boundary — 2026-10-09

Normal Settings -> Save backups now explicitly prepares a separate private
app-owned Drive area. The real Thor incremental-consent screen requested only
app-specific file access (`drive.file`) for the existing default account, without
another account chooser. The ROM client remains read-only; a separate grant type
and scope-specific API enforce that boundary. No save mapping, automatic folder
scan, save upload, restore, mirroring or legacy-sync handover is enabled yet.

Area creation persists a generated opaque file ID before the remote POST, then
records readiness only after exact identity/ownership validation. A lost create
response reuses that identity. A regression reproduced rejected preferences
writes leaving an optimistic cached ID: explicit retry previously skipped the
durable intent. Every preparation now acknowledges persistence before possible
creation, including a recreated controller with that cached ID. Focused checks
verify rejection prevents every POST until persistence succeeds, and recovery
creates only the original ID. Source account/client changes retire old readiness.

Fresh scoped Flutter analysis, authorization/API/setup/widget checks and
`git diff --check` pass. Controller activation is asserted by the actual new
root-verification requests, not by an old visible error message. No full suite
was required for this bounded setup change.

Required Android assembly: shared-gate ticket 474
(`ec4b6307fa72468fba5c39eb61687107`), completed exit 0 with verified completion.
The shared gate was acquired after its wait; a confirmed-idle different-version
daemon was retired by the supervisor, not killed. Observed workers=2,
parallel=false, Gradle maximum heap=3 GiB, preserved 1 GiB metaspace/256 MiB
code cache, Kotlin 2.2.20 in-process. JVM tests were configured one 512 MiB fork
and fail-fast (assembly did not execute them). Current app Ninja compile/link
rules use the depth-one native pool. No memory failure or budget increase.
Private diagnostic log: `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/` plus
`bcb5c5638de1490480280739e45f8c99.log`. Existing toolchain deprecation warnings
were not suppressed or used to expand this stage into an upgrade.

Installed APK SHA-256:
`55a6ad95fc83f53dabf88fec4ce1682992231a9238eedad276eeadb765387afd`.
APK signature verifies with unchanged signer SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Normal joined Pause retained metadata job 76 at 20,935 lookups; preserving
`install -r` replaced PID 1533 with 16802. Immediate protected credential/settings
digests matched, installed bytes matched the built APK, and the configuration
digest still matched the earlier preserving-update baseline. The remembered
backup area verified without consent/account selection after replacement.
Normal saved-job Resume restored job 76; no new scrape was created.

Earlier scoped shared-file journals compared 146 stable files / 304,569,033 bytes
with no path/size/digest changes. Inaccessible PPSSPP/private storage remains
unverified; this is not a full SAVE-01 safety or restoration claim. No save-file
mutation code is present in this setup boundary. The expendable setup screenshot
was removed through a reviewed exact-file cleanup ticket (1,252,727 bytes);
preservation journals are retained for S10 diagnosis/reconciliation. Both actual
and committed Thor displays were freshly observed OFF/Asleep after verification.

Next required work is the actual RetroArch/standalone save-group mapping,
quiescent capture, verified cloud generation and emulator-load restore, followed
by every accessible installed route and the remaining failure/handover criteria.
These are unfinished S10 work, not deferrals or acceptance waivers.

## Save-generation transport boundary — 2026-10-09

The first save-group cloud path now has a concrete manifest and streamed
transport implementation, not yet connected to the normal Settings/game flow.
`SaveBackupManifest` retains exact account/device/emulator/core/platform and
reviewed edition associations, separates saves/states, records ancestry, and
rejects aliased/escaping member paths, duplicate cloud identities and incomplete
groups. Its content digest excludes timestamps and upload IDs. Explicit restore
comparison rejects account/edition/format mismatches and incompatible state
runtimes; it does not authorize an overwrite. The ancestry classifier requires a
caller-validated base and cannot decide conflicts from timestamps.

`DriveSaveBackupGenerationApi` uses only the separate backup authorization lane.
It verifies the exact private area and the whole captured group before remote
writes. Preallocated IDs identify immutable payloads and their final manifest;
no update/delete/sharing endpoint or arbitrary upload destination is exposed.
The resumable session URL is restricted to Google's exact HTTPS upload endpoint.
Every member requires complete SHA-256 readback plus matching ownership, parent,
binding, size and unchanged binary content revision before manifest publication. Manifest
read/download similarly checks its exact identity/binding/digest and bounds the
decoded document to 1 MiB. Member streams target private restore staging only:
normal EOF is required before their digest/content-revision verification is satisfied.

Focused host checks demonstrate corrupt/changed capture rejection, corrupt
readback and cancellation preventing publication, reserved-ID recovery after a
lost commit response without rewriting completed objects, foreign URL/object/
account rejection, independent cloud-generation/member reads, and preservation
of the previous complete generation when a newer publication fails. A reproduced
manifest/payload identity collision was rejected at the model boundary. These
checks use bounded in-memory Drive responses and exact expendable D:\Temp files;
they are not real Google upload or emulator-load acceptance evidence.

Verification: focused `save_backup_manifest_test.dart`,
`save_backup_generation_test.dart`, `save_backup_area_test.dart`,
`save_backup_setup_test.dart`, `drive_authorization_test.dart` and
`google_drive_sign_in_test.dart` passed in one concurrency-one workload. Scoped
analysis of the new model/transport/tests and `git diff --check` passed.
No Gradle build, installation, new
consent, real-save upload/restore or legacy-sync handover is part of this change.

The durable capture/job controller must persist reserved IDs and immutable
private captures before calling the transport. Native writer-boundary proof,
destination grants, coherent local publication/rollback, independently
discoverable versions, normal UI and background/emulator-return integration
remain ordinary unfinished S10 work. Do not count these transport checks as a
completed RetroArch/standalone vertical slice or S10 closure.

Native-route investigation is pinned to the installed RetroArch 1.22.2 baseline:
[SAVE_FILES implementation](https://github.com/libretro/RetroArch/blob/v1.22.2/command.c#L799)
replies after CMD_EVENT_SAVE_FILES, whereas
[state saving](https://github.com/libretro/RetroArch/blob/v1.22.2/tasks/task_save.c#L1313)
can enqueue work. A command receipt, app return, equal timestamps or a silent
background UDP endpoint must not be treated as proof that all save/state writers
have stopped. Establish and verify the actual capture/export boundary next;
do not turn diagnostic read timeouts into backup completion or failure policy.

## First normal capture/job integration — 2026-10-09

The GBA edition's normal game-details menu opens Save backups. The user explicitly
selects one shared mGBA SRAM file and confirms the exact edition association; a
same-base RTC is included if present. This is not automatic basename matching.
The current UI is a narrow slice: localization, broader mappings/coverage,
background execution and restore are still unfinished SAVE-01 work.

SQLite acknowledges the selection and random capture ID before native IO, then
the manifest/reserved cloud IDs/private member paths before publication. Explicit
resume retains those IDs and sealed bytes rather than recapturing/reallocating.
The last verified manifest is replaced only after the transport completes.
Host checks cover durable ordering, restart/replay, duplicate work joining,
cancellation and failed-new-generation preservation. They do not prove native
restore or independently discoverable reconnect/reinstall recovery.

Native capture uses the investigated RetroArch 1.22.2 writer boundary: exact
GET_STATUS CONTENTLESS replies before and after streaming the selected group,
plus no-follow source handles, complete-group identities and RTC membership
checks. Background UDP silence waits for the actual reply and remains explicitly
cancellable. Normal Open RetroArch services the queued requests; the user returns
to R-Shop afterward. Seal publication occurs last, after file fsync. Existing
sealed bytes are rehashed on replay. No emulator termination or source writes.

Real capture initially failed because the framework files-directory spelling and
its canonical path differed. A bounded regression reproduced that rejection;
normalizing only the trusted framework parent fixes it while retaining descendant
alias rejection. Shared-gate request 488
(`c7a4bbcde98b410dabeed974605bdab0`) completed exit 0. Gate acquired;
observed workers=2, parallel=false, Gradle heap=3 GiB, Kotlin 2.2.20 in-process,
preserved 1 GiB metaspace/256 MiB code cache, one executed 512 MiB test fork with
fail-fast. Current app Ninja compile/link pools are depth one. No memory failure
or budget increase. Retained private build log basename:
`363ad53d0e2d4e02bab56eaa3fdbb74d.log`.

Installed APK SHA-256
`e80e4318dc80adb7ac98ce3e7d89fcc067e76f3ffe7478b1d682db417327fcb7`
matches the build independently, with the unchanged signer. Immediate protected
settings/preferences and thirteen mGBA save digests match across replacement.
RetroArch's first Close Content observation was premature (confirmation still
open); it was completed normally and actual No Core verified before replay.
The resulting sealed 512-byte capture matches the original source SHA-256.
The subsequent real cloud publication stops at `digestMismatch`. Reserved IDs
and captured bytes remain pending for deterministic recovery; do not count this
as verified upload, complete backup or successful restore. Redacted debug-only
readback diagnostics in request 492 distinguish content/length from version
change without logging credentials, object IDs, account data or save contents.

Three task screenshots (437,227 bytes) were removed by reviewed exact cleanup
transaction `d6ceecba0f42f45cbc0554592ca28318`; exact device copies are absent.
Preservation journals and pending capture are retained. Both screens OFF/Asleep
at the checkpoint. Resume the owner's same paused metadata job after the next
update. No legacy sync change, cloud deletion or source mutation is authorized
by this enabling checkpoint; all remaining SAVE-01 criteria above still apply.

## Real cloud publication and content revision correction — 2026-10-09

Request 492's installed diagnostic identified `version_changed` after complete
length and SHA-256 had passed. Drive's general version includes metadata changes;
it is not a binary-content revision. Expanded diagnostics in request 494 did not
reproduce that intermittent rejection: normal Resume published the retained
generation, then a fresh explicitly reviewed capture also completed full cloud
readback and manifest publication. No particular metadata field was identified
as the cause of the earlier live version change. Do not claim that view-time
changes were observed causing that live failure.

The transport now requires a nonempty valid `headRevisionId` and compares it
before/after readback, while retaining complete byte length/SHA-256 and all
ownership, private-parent, account/binding and properties checks. A regression
first reproduced rejection of metadata-only changes and acceptance of a missing
content revision. The correction accepts the former and rejects the latter;
changed content revision and corrupt bytes still reject publication. Focused
transport/capture/job checks and scoped analysis passed. Request 496
(`906749fd47334adc840c9feb282a95e9`) completed exit 0 through the acquired
shared gate. Observed workers=2, parallel=false, Gradle heap=3 GiB, Kotlin
2.2.20 in-process with preserved metaspace/code-cache settings; configured test
forks=1/512 MiB (assembly did not execute JVM tests), app native pool depth=1.
No memory failure or budget increase. Build log basename:
`8fc63ca5936d4556bc271e00ae536a20.log`. No duplicate build was launched.

The two successful normal cloud generations were verified with diagnostic APK
SHA-256 `fcfad1c64ca11f98b5acc921066952f6860c3a3e36c39bbbe4a53569a12b2ca8`.
Its unchanged signer and independently installed bytes were checked. Immediate
protected preferences/configuration and thirteen mGBA save digests matched
across replacement. Cloud publication is verified for this narrow real save;
native restore/emulator-load acceptance has not passed.

The corrected request-496 APK was independently installed/hash/signature checked:
SHA-256 `08db33cf8c71aa4a62fe2cd659d1935858d6618d4fb1d1a7bfc02dd9fc0fda1b`.
Immediate four protected settings/preferences and thirteen mGBA save digests
matched across preserving replacement. A fresh normal backup completed capture,
full cloud readback and publication at 16:50:19.781623 local time. The exact Europe
ROM downloaded through R-Shop's on-demand flow for the forthcoming restore/load
check; it was not launched. Same metadata job 76 resumed and advanced from 21,754
to 21,769 lookups without sign-in. Both actual/committed displays were then OFF.
This proves the content-revision correction at the real API boundary, not restore.

Primary content-revision semantics:
[Drive File resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files).

## Next narrow restore boundary

Restore must use the real verified cloud manifest and streamed member readback,
not the capture's local copy as a substitute for downloading. Keep the exact
account/edition/emulator/core/format binding and reviewed destination name. Stage
only beneath a native-created private restore operation; reject publication
until normal EOF, native digest/length and fsync have passed. Persist the intent
and preserve the current local bytes plus identity as a named rollback generation
before any destination replacement. Require the same verified CONTENTLESS writer
boundary immediately before local publication; active content must reject, not
be killed. An explicit cloud-versus-local choice must acknowledge divergent
digests rather than choose by timestamp.

Prove the existing one-SRAM/no-RTC case first with atomic file replacement and a
durable publication receipt. Interrupted acknowledgement must reconcile the
recorded old/new identities and digests; an unexpected destination is a preserved
conflict, never an overwrite retry. A separate explicit rollback action must
verify its retained generation and preserve the replaced bytes in turn. This
narrow path must reject coupled RTC groups before mutation until coherent
multi-member restoration is implemented and verified. That restriction is
unfinished SAVE-01 work, not an unsupported classification or waiver. Continue
to the standalone emulator and full coverage only after the narrow real
backup/download/restore/emulator-load path works.

## Native restore/rollback evidence and launch association — 2026-10-09

Request 501 completed exit zero with the shared gate acquired, workers=2,
parallel=false, Gradle heap=3 GiB and Kotlin 2.2.20 in-process. One executed JVM
test fork used 512 MiB; current native compile/link pool depth was one. No
memory-related failure or budget increase. Private log basename:
`9c646245cd8448ad9bfaed7d0c9f97a6.log`. Independently installed APK SHA-256
`ad4bc0c5338ef63141eebd18099c7efee4385e8cc69ec80bc2f0e9d9aa469e70`, unchanged
signer, and immediate protected configuration/preferences plus thirteen save
digests verified the preserving replacement.

Normal cloud restore and explicit retained-local rollback both completed actual
JNI/FUSE atomic publication, with durable published receipts and matching 512-byte
SHA-256 `610c7c8507fb95205ea7e5172031dbe176fd0fe3f51b6ee6568edbeda4ee3fc7`.
All thirteen preceding mGBA save digests remained identical. Cloud restore used
real downloaded bytes; rollback retained the replaced generation separately.
This proves the narrow publication pipeline, not emulator-load acceptance.

The subsequent live load check exposed a real association gap: the explicitly
selected older Aero Europe save and the current managed installation have
different document IDs. RetroArch derives the save basename from that encoded
document ID, creating a different SRAM file on the current launch. Do not count
matching display names or a byte-pipeline receipt as proof of the game's save
consumption. Save-to-current-launch binding and persistence across reinstallation
remain required ordinary S10 implementation work.

Also, normal Close Content followed by the same Android ROM/core intent leaves
RetroArch at No Core. Pinned v1.22.2 RetroActivityFuture.onNewIntent updates the
intent without reloading when both extras are unchanged. Normal user Quit and a
cold R-Shop Open boots the game; this is diagnostic evidence, not authorization
to force-kill RetroArch or a finished relaunch fix. Preserve actual saves and use
meaningful in-game save data for the remaining load/restore proof. Legacy sync
remains untouched; no acceptance criterion is weakened or deferred.

## Current-launch save binding — 2026-10-09

The first regression reproduced the defect: an unrelated `Other.srm` was accepted
and uploaded under the selected edition. The normal game workflow now passes
its exact artifact, console and destination root into the save job. A read-only
native review shares launch's installed/local-copy ownership preflight and
`openCommitted` archive validation, returning the encoded SAF document leaf with
the pinned SRAM extension. It starts no activity and grants no new permissions.
Only this target is offered for review; the old all-save directory picker is
not used for the automatic route. Explicit custom mapping remains unfinished
SAVE-01 work, not an implicit override of exact association.

Before capture/upload and restore/publication, the job revalidates edition
membership, game identity and the current launch target. A changed installation
or reassigned edition rejects the operation while preserving pending evidence.
For a new explicit cloud restore, immutable cloud member names describe the
source; the durable restore intent separately records the current installation's
destination. A resumed restore cannot silently adopt a different destination.
Retained-local rollback remains bound to the original reviewed destination.

Focused host checks cover unrelated selection, exact launch preflight, current
reinstallation destinations, pending retarget rejection, capture-time changes,
edition reassignment and existing explicit restore/rollback UI. Scoped Dart
analysis and whitespace checks pass. Gated request 506 completed exit zero:
gate acquired, workers=2, parallel=false, Gradle heap=3 GiB, Kotlin 2.2.20
in-process; one executed 512 MiB test fork and current native pool depth one.
No memory failure/budget increase. Private log basename
`5b7acad5ed1e405bab765c1e0576ab26.log`. Focused native encoded-leaf and capture
checks passed. Preserving install-replace succeeded; installed APK SHA-256
`d58e0d5086ee69c6f697a006eb6a67096b7d94eb3af8b8705f38f9f02be6d657`,
unchanged signer. Immediate configuration, three protected preferences and all
fourteen mGBA save hashes matched before/after replacement. Live target review
and meaningful emulator-load restoration are not claimed by this checkpoint.

## Current-target publication and fixture correction — 2026-10-09

Normal cloud restore now has a freshly inspected native `published` receipt for
the current Aero Europe installation, with 512 bytes and SHA-256
`610c7c8507fb95205ea7e5172031dbe176fd0fe3f51b6ee6568edbeda4ee3fc7`.
The ordinary UI reported successful restore and retained-local rollback. This
closes the current-target publication check, not SAVE-01 emulator-load acceptance:
these bytes are still the default blank save.

Manual gameplay is not required for that acceptance check. Use a disposable,
format-valid save fixture or a copy of existing authentic save data, preserve its
original, pass the copy through the normal backup/cloud-download/restore path,
and observe the emulator consuming the expected saved data. A successful ROM
launch alone does not distinguish a consumed save from an ignored destination;
arbitrary mock bytes prove only transport and rejection handling. The owner's
2026-10-09 clarification explicitly favors fixtures over generating progress by
playing a game. Do not spend further time generating Aero progress manually.

The Aero input probes did not establish usable gameplay input. A temporary
Port-1 device selection was returned to its original Virtual selection before
Close Content; global configuration, mGBA override and remap SHA-256 values
remained identical. This is test-harness evidence, not a production input fix.
The attempted normal Minish Cap USA download failed with `storage_collision`
against an existing local title; no existing archive was overwritten. No save
fixture was copied or modified during this investigation. That failed transfer
is retained for diagnosis rather than retried or bypassed blindly. S10 remains
ACTIVE, with standalone restoration and all other SAVE-01 criteria unfinished.
