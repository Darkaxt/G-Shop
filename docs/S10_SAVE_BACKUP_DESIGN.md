# S10 save backup — active implementation

Authority: SAVE-01 in SPECIFICATION.md. S10 is the sole ACTIVE stage; setup and
inventory do not satisfy SAVE-01 as a whole. S7 remains parked BLOCKED
on its independent reception/retention evidence. S11 is NOT STARTED.

## First real workflow

Prove RetroArch plus a standalone emulator before broadening coverage. On
2026-10-09, Thor `bfa98654` has shared RetroArch saves/states and a shared Azahar
user directory containing actual save data. These are candidates, not proof of
R-Shop access, reviewed edition association, coherent capture or emulator-load
restore. Use existing exact edition/artifact identities; never infer a save's
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
bounded work; real RetroArch and standalone save-load round trips; remaining
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
binding, size and unchanged Drive version before manifest publication. Manifest
read/download similarly checks its exact identity/binding/digest and bounds the
decoded document to 1 MiB. Member streams target private restore staging only:
normal EOF is required before their digest/version verification is satisfied.

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
