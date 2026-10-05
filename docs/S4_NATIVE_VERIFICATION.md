# S4 native resource verification

Authority: [SPECIFICATION.md](SPECIFICATION.md), META-06/META-07 and QA-01.
Execution remains S4; this does not open S5 or approve any real ranking source.

## Revision-6 shared metadata workflow

### Normal startup and mapping correction (2026-10-05, after 10:22)

The normal owner APK at `D:\Temp\rshop-normal-onboarding-20261005\app-debug.apk`
has SHA256 `739cf1c11c0977cb2d4460d2224b571f463665f013b89bcd4ef18428ac92e83d`.
The reported logo was the integration-test entrypoint, not proof that normal
startup hung. The normal entrypoint was installed in place, with the same signer,
without uninstall or data clear. A later explicit cold launch returned `Status:
ok`, `LaunchState: COLD`; fresh native UI subsequently rendered the library with
182 remote Game Gear games and one existing local GameCube game.

Reconstruction exposed an independent onboarding defect: the mapping editor
committed the Game Gear system correctly, then invalidated its view snapshot.
Final onboarding read that transient empty snapshot and replaced committed
console settings with its older local-only state. The controller now loads the
committed source/configuration before completion. A red/green regression uses
the real source notifier, an empty view snapshot, and save/reload to verify exact
console target/provider/mapping preservation. The affected onboarding, source
notifier and mapping-widget checks passed (`c0d36d`, exit 0); focused analysis
passed (`948a49`, exit 0). Fresh native onboarding was not reset/repeated: the
existing owner was preserved and its Game Gear mapping saved through the normal
mapping editor, then verified through cold-start library enumeration.

Build ticket 138 (`38126c` / `7bfa41`, exit 0) acquired the shared Windows gate
through command completion. Observed workers 2, parallel false, Gradle heap 3 GiB;
Kotlin configured in-process with cached compiler tasks; test configuration one
fork / 512 MiB, not executed. App native pools configured at one. No memory
failure or budget raise. Gate log `1ee74976ee3b4811885a86e12700fb41.log`.
The pre-launch in-place-update comparison preserved all fingerprinted private
data except Android's disposable shader cache. This is not recovery of B7 data.

Normal settings selected `/storage/emulated/0/ES-DE` through the Android folder
picker, creating only its isolated `RShopMetadata/metadata.sqlite` namespace.
Existing ES-DE directories were not replaced or edited. A subsequent cold-start
credential check exposed differing secure-storage Android options between
startup and metadata. The subsequent corrected APK recovered existing
credentials after cold launch and completed a one-title native IGDB workflow;
see [normal startup recovery](NORMAL_STARTUP_RECOVERY_20261005.md) for the exact
APK/build profile and evidence. S4 stays
ACTIVE; no full fresh scrape, migration or stage-closure claim follows from this
startup evidence.

### Normal application reconstruction checkpoint (2026-10-05)

The corrected normal `lib/main.dart` APK, not an integration-test entrypoint,
is retained at `D:\Temp\rshop-normal-shared-20261005\app-debug.apk`, SHA256
`4f4d320ec2dc29a01a348c6b33941e88d633e65efb252dc36089a91b61454f87`.
Independent inspection verified `com.darkaxt.rshop.debug`, version 1.7.0+12,
the existing debug signer, and a valid v2 signature. `adb install -r` succeeded
without uninstall or data clear. Before first launch, private-file comparison
found no changed or added files; only Android's disposable Vulkan shader cache
`code_cache/flutter.impeller.vkcache` was invalidated. Existing databases,
preferences and other fingerprinted private files retained their bytes.

The first normal-build invocation failed because PowerShell split an unquoted
`-Ptarget=lib/main.dart` into two arguments (`Task '.dart' not found`). Quoting
the property corrected that invocation; no production workaround was added.
The corrected build (`38909` / `c8dbc8`, exit 0, ticket 133) acquired and held
`Local\Darka.AndroidGradleBuildGate` through its confirmed exit. Observed workers
2, parallel false, and Gradle maximum heap 3,221,225,472 bytes; required JVM
arguments were retained. Kotlin was configured in-process, with cached compiler
tasks. Test configuration was one fork / 512 MiB, not executed. App native
compile/link pools were configured at one; cached plugin outputs do not prove
their full-load concurrency. No memory failure or budget increase occurred.
Gate log: `3ca438f661d440fe996d101f69f24633.log`.

Normal owner PID 17025 rendered onboarding, completed native authorization with
the previously authorized default account, and selected the existing isolated
download folder and a rooted Drive subtree. At 10:09 the selected subtree's
enumeration had completed and final folder-boundary validation was still running;
publication and console mapping were not yet complete. Diagnostic-only in-memory
database observations are not consistent recovery snapshots and are not backups.
Both display power controllers were confirmed OFF while the network job continued;
the current default Wi-Fi network was still validated. These are reconstruction
steps, not recovery of the private data lost in B7 or S4 closure.

### Current native result (2026-10-05, 09:30–09:40)

The combined APK `D:\Temp\rshop-shared-portable-20261005\app-debug.apk`
has SHA256 `e7369db378ffe9d9a45fb08b1d7c5e5f97530dd3531a37f43ba7475c3cf71956`.
Independent package/signature inspection verified `.sharedproof`, version 1.7.0+12,
and signer SHA256 `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
It contains both Android compatibility corrections described below. The joined
gated build (`5393` / `32c6c1`, exit 0) acquired
`Local\Darka.AndroidGradleBuildGate`; observed workers 2, parallel false, Gradle
heap 3,221,225,472 bytes. Kotlin was configured in-process; cached tasks do not
prove a new compiler memory workload. Test forks were configured 1 / 512 MiB,
not executed; native compile/link pools 1 were configured, but cached native
outputs do not establish plugin concurrency. No memory failure or budget raise.
Gate log: `3546a6f3477e4c87a41e05163b8c7b4a.log` under the host helper log root.

All successful phases used the dedicated nonempty-report driver attached to an
observed existing VM service, with `--keep-app-running`, and its exit was joined.
No driver installed or uninstalled the owner's package.

| Boundary | Thor evidence | Inspected result |
| --- | --- | --- |
| `/workflow` | PID 21557; driver `45113` / `9dbaae`, exit 0 | Normal remote-only refresh and ES-DE publication; seeded user/manual fields preserved; exact media reuse; fresh private projection restored facts, cover and screenshot with no recovery requests or ROM directory |
| Android SQLite rebuild | Same workflow report | 129 restored/ranked; Top membership 25; restore 3,204 ms, query 667 ms, replay 450 ms, total 4,683 ms; peak RSS 511,201,280 bytes; diagnostic native measurement, not a UI latency guarantee |
| `/seed` | PID 24691, start ticks 29660160; `75791` / `9e27ee`, exit 0 | Newly absent shared/private namespaces reserved; durable hashes recorded; zero network clients |
| `/restart` | Prior PID absent; PID 27047, start ticks 29667308; `57391` / `a4ad4d`, exit 0 | Private sentinel retained; durable hashes unchanged; replay restored 0; no network requests |
| Storage unavailable | PID 3243; driver `a853df`, exit 0 | Exact synthetic selected root reversibly detached; private cached facts retained, shared open rejected and artwork unavailable; no replacement namespace |
| Storage restored | Prior PID absent; PID 6287; driver `5f30f2`, exit 0 | Exact root restored, access allowed; all durable hashes unchanged; artwork usable; replay 0 and no network |
| `/reinstalled` | Actual `.sharedproof` uninstall without `-k`, package absent; identical APK reinstalled; private child absent; PID 9368; driver `124de2`, exit 0 | Fresh private projection restored 1 exact record plus artwork under a recreated local source binding, with all durable hashes unchanged and no provider/artwork requests |

Permission evidence is deliberately narrower than storage-loss evidence.
`MANAGE_EXTERNAL_STORAGE` was confirmed `deny`, legacy read/write grants were
false and their app-ops ignored. Nevertheless this firmware still allowed the
fixture's database to open. The first denial attempt (PID 29214) and a second
attempt after shell republication of the exact synthetic database/artwork (PID
693) failed the unavailable-storage assertion. Their results are **not passes**.
The shell republication retained both SHA256s; no owner files were targets.
Successful `/denied` instead moved only the synthetic root to the previously
absent `RShopSharedProof-20261005-portable-detached`, then `/regrant` restored its
exact original path. This proves native storage loss/remount handling, not that
permission denial alone made these files inaccessible. The legacy report key
`permission_unavailable_asserted` must be interpreted with this supervisor
evidence, not as independent permission proof. Do not weaken the requirement or
silently close the separate permission-verification gap.

The owner's `.debug` package remained installed, never cleared or overwritten.
All 20 private-file fingerprints matched the pre-test baseline after the lifecycle
sequence and before normal launch. The expendable package was then removed and
all task-owned ADB forwards removed. Normal `.debug` launch rendered its existing
welcome/setup screen (not a library-restoration claim); the logo was the non-UI
fixture, not this normal launch. Both actual display power states 0 and 4 were
confirmed OFF with screenReady true. Synthetic external evidence is retained
until its exact cleanup review. S4 remains ACTIVE: B7 and final reconciliation
are not retroactively satisfied by these isolated checks.

### Native startup defect and result capture (2026-10-05)

The user authorized the connected Thor handoff. The first lifecycle seed in
`.sharedproof` failed before refresh at `SharedMetadataStore.open`. Inspection of
that exact task-owned database found application_id/user_version 0 and only
`android_metadata(locale TEXT)` with `en_US`. Android creates this locale table
before `onConfigure` ([Android SQLiteConnection source](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/database/sqlite/SQLiteConnection.java));
the shared-store guard incorrectly treated it as foreign application data.
The focused regression reproduced the failure, then passed after excluding the
Android bookkeeping table. A foreign database containing that table plus actual
user data still rejects without changing its data/version/application ID.

The initial plain `test()` also bypassed IntegrationTest's widget-bound failure
capture: native logs reported failure while the attached driver printed success
with null report data. That driver result is invalid acceptance evidence.
Both current native entrypoints now use binding-owned `testWidgets()`; the
dedicated `test_driver/shared_metadata_driver.dart` also rejects missing/incomplete
reports. Verify a deliberate invalid-route failure before the corrected seed.
These isolated test entrypoints do not paint the normal library UI, so the Android
splash can remain visible; it is not evidence of a normal-app launch hang.
The owner's `.debug` package is not an installation/uninstall target. Both physical
power controllers were confirmed OFF while the corrected APK was built.

After the first guard correction, the native seed exposed a second incompatibility
before any provider request: `no such function: json_extract` in the temporary
catalogue projection built by `SharedMetadataStore.restore`. A debugger attached
to a start-paused, expendable test process captured that exact caught exception;
no production error logging or retries were added. Host regression rejects SQL
JSON1 calls while executing the same real SQLite rebuild. The projection now
decodes 128-row catalogue pages using the existing artifact model and inserts
bounded batches into its indexed temporary table, inside the same transaction.
Exact account/file/content checks and source-reselection rules remain unchanged.
The focused 129-edition restore/rank/replay passes without JSON1 or network calls;
the changed large-fixture/resource and native lifecycle proof remain required.

The portable-SQL focused run (`22776` / `4dcf51`, exit 0) also completed the
changed 30,000-edition resource fixture. Restored/ranked 30,000; Top membership
25; bounded records/catalogue pages 128 and identity reads 1; network 0. Restore
564,223 ms, query 127,272 ms, replay 111,276 ms, total 832,646 ms; peak RSS
270,249,984 bytes. These are host diagnostic measurements, not native UI latency
or a timeout budget. Unchanged store/lifecycle/controller regressions passed in
the same joined workload. Focused analysis found no issues. No overlapping test
was started and the synthetic host root was removed by joined fixture teardown.

`integration_test/shared_metadata_test.dart` selects the existing workflow with
`/workflow`, otherwise the existing lifecycle entrypoint. This single expendable
APK allows the workflow to complete and clean its newly reserved parent before
`/seed` reserves the same absent parent, with no recompilation between actual OS
lifecycle phases. Both entrypoints retain their package/path guards. Use the
dedicated non-empty-report driver for every phase, attaching only to the observed
existing VM service with `--keep-app-running`.

`integration_test/shared_metadata_workflow_test.dart` exercises Android SQLite
and an explicitly reserved external-storage fixture through the same normal
metadata controller used by the host ES-DE check. It refreshes a synthetic
remote-only title, publishes current text/covers/screenshots, preserves launcher
user fields and manual-edit conflicts, reuses exactly reviewed media, and rebuilds
facts/artwork into a fresh private projection without another lookup or image
request. The second check runs the shared-record/query rebuild with 129 editions
on Android SQLite. This focused native check does not repeat the 30,000-record
host workload or claim that a synthetic provider is a live API.

Supply `RSHOP_SHARED_TEST_PARENT` only as a **new**, direct external-volume child
named `/storage/<volume>/RShopSharedProof-<run-id>`. The native entrypoint rejects
an existing directory, library root and app-scoped path before creating files.
Helpers close their handles and remove only their owned children; parent cleanup
is non-recursive and occurs only after successful reservation and an empty-parent
check. It never bootstraps the owner's sources/database or uses their ES-DE files.

Before deployment, obtain the requested Thor handoff and use the shared Gradle
gate for the exact-target APK with `-PrshopSharedMetadataProof=true`. This opt-in
debug package is `com.darkaxt.rshop.sharedproof`, not the owner's `.debug` app;
the entrypoint refuses the owner package. Ordinary debug/release identity and
labels remain unchanged when this property is absent. Independently verify the
processed APK package, signer and hash before installation. Install only this
expendable package and attach the driver to its observed existing VM service.
Do not install this entrypoint over the owner application or use its private data.
Switch both displays off afterwards. This document's older `.debug` resource
procedures are historical evidence, not permission to reuse their owner-package
deployment for the new shared workflow.

At preparation time this harness did not prove revoked-storage permission/regrant,
process restart or uninstall persistence. The current result above supersedes
that pending status for the verified boundaries only. Permission enforcement
remains explicitly unproven; the remaining META-08 reconciliation is required.
reinstall verification must use an expendable package or isolated fixture, never
uninstall the owner's application. Writing this entrypoint closes no acceptance
criterion by itself.

### Lifecycle probe protocol (prepared, not device evidence)

`integration_test/shared_metadata_persistence_test.dart` runs in the same
expendable `.sharedproof` package, never the owner `.debug` package. A single APK
uses explicit `/seed`, `/restart`, `/denied`, `/regrant`, `/reinstalled` launch
routes. FlutterActivity's existing `route` intent extra supplies the initial
route; no native production test-control API or timer is added. The exact installed
Flutter engine source confirms this (`FlutterActivityLaunchConfigs.java` and
`FlutterActivity.getInitialRoute`); see also the
[official FlutterActivity API](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html).
An ordinary launcher route is rejected before fixture creation.

The shared path validator accepts only a normalized direct child of
`/storage/emulated/0` or a UUID-form removable volume, named
`RShopSharedProof-<run-id>`. The earlier guard accidentally rejected the compiled
internal-storage path because it allowed only one component after `/storage`.
Host regression reproduces the rejection and covers valid internal/SD paths plus
library/app-data/nested/path-traversal rejection. The validator uses POSIX syntax
on the Windows host too. The old workflow APK recorded below must **not** be used
as current native evidence: its compiled path fails that old guard. Rebuild its
changed entrypoint if that separate workflow is needed at device handoff.

Lifecycle phases, in order:

1. `/seed`: reserve an absent external proof directory and absent private child;
   normal controller refresh creates synthetic current facts, cover/screenshot
   and mapped ES-DE publication. Preserve favorite/custom fields and prove no
   ROM directory. Close all handles, then record hashes of every durable file
   and a private sentinel. Keep this exact synthetic state for later phases.
2. After the joined driver's success, terminate **only** the expendable package
   and confirm its process exit. Launch `/restart` in a newly observed process;
   require the sentinel/private database and unchanged durable hashes. Replay
   restores zero records, with no provider or image requests.
3. Revoke shared-storage access **only** for the expendable package; inspect the
   actual grant/app-op state and restart into `/denied`. It must still read the
   private cached description, fail opening existing shared storage, return no
   unavailable cover, and not create a replacement shared namespace. Capture the
   Android denial evidence separately; a generic filesystem exception alone
   does not establish Android permission revocation.
4. Restore that test package's access, inspect effective grants, restart into
   `/regrant` and verify all durable hashes and cached artwork with zero lookup
   or image requests. The phase requires the prior private `denied` sentinel.
5. Only after inspected success, verify exact test package/signature again,
   uninstall **only** `com.darkaxt.rshop.sharedproof` without retaining data,
   confirm package absence, and reinstall the identical inspected APK. Regrant
   test access and launch `/reinstalled`. The probe requires the private child
   to be absent before creating a fresh operational database. Republish the
   same synthetic Drive account/file/content under a new local source ID and
   rebuild one record plus artwork offline. All durable hashes must still match.

Attach the integration driver to each launch's observed VM service, rather than
using Flutter's binary-install/teardown route. Inspect and join each driver result
before the next lifecycle action; record old/new native process identity and
grant/package evidence. No sleeps or elapsed deadlines classify completion.
Network-client creation is prohibited during every phase. The host counterpart
validates the same assertions with a remount/private-root-removal simulation;
that is not OS restart, grant or uninstall proof. It deliberately rejects a false
reinstall when private state still exists.

On failure, preserve exact synthetic evidence. On successful final recovery,
review/hash the task-owned synthetic files, remove only those exact members and
empty parents, and remove only the expendable package. Never recursively clean
the shared storage root, owner app, ROMs or existing ES-DE layout. Switch both
displays off and release the Thor. This protocol does not reconstruct B7 or prove
restoration of credentials, settings or installation ownership; the durable
metadata store intentionally contains none of those.

Prepared lifecycle APK (local build only):
`D:/Temp/rshop-shared-persistence-20261005/app-debug.apk`, SHA-256
`01dfb3655c1e721546ed8dc028262fbe27a0c934f77bbda67ff0ab3589a3e412`.
Badging/signature checks confirm `.sharedproof`, R-Shop Shared Proof, 1.7.0+12,
and debug certificate SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
The compiled external parent is
`/storage/emulated/0/RShopSharedProof-20261005-persistence`; `/seed` requires
it absent. Reinspect APK, package absence/identity and exact parent at handoff.
Gate ticket 120 acquired/held through build exit 0; observed workers 2,
no parallel projects, 3 GiB Gradle heap and required JVM flags. Kotlin configured
in-process but cached/no-source, test tasks configured one 512m fork and not run,
app Ninja compile/link pool depth 1 per ABI. Native app/plugins had no compile
work, so environment hints do not prove plugin concurrency under new load.
No memory failure/budget increase occurred. Host phase/path/controller assertions
and focused analysis pass; native phase results remain absent.

### Corrected local shared-workflow artifact (2026-10-05)

The corrected path-guard workflow APK was built through shared gate ticket 121,
held to exit 0, with the same observed low-memory profile as ticket 120 above.
Kotlin tasks were cached/no-source; configured test forks were not executed;
native app/plugin build outputs had no work. No memory failure or budget increase.
Independent badging/v2 signature/hash checks confirm `.sharedproof`, R-Shop Shared
Proof, 1.7.0+12 and the established debug signer. Preserved corrected artifact:
`D:/Temp/rshop-shared-workflow-corrected-20261005/app-debug.apk`, SHA-256
`3e9e468742376563e7f40fc84ee2bec47e99fa900a272ea0f81d094edec66461`.
It uses `/storage/emulated/0/RShopSharedProof-20261005-workflow`; check it absent
on the actual device before first use. This replaces the earlier invalid-guard
artifact below for future workflow execution, not the separate lifecycle APK.
Native handoff remains pending; S4 is BLOCKED at external B8, not COMPLETE.
No device installation/test occurred and no build remains running.

### Earlier local shared-workflow artifact (2026-10-05, superseded)

The exact shared entrypoint was built through Gradle gate ticket 119, acquired
and held to confirmed exit 0. Verified Gradle profile: workers 2, no parallel
projects, maximum heap 3 GiB with the required other JVM flags retained. Kotlin
is configured in-process; its incremental compilation was cached, not measured
under new load. Test tasks have one configured 512m fork and were not executed.
The app's generated Ninja compile/link pool has depth 1 per ABI; native tasks had
no compilation work. Plugin concurrency is not proven by environment hints.
No memory failure/budget increase occurred.

Preserved APK: `D:/Temp/rshop-shared-native-20261005-0556/app-debug.apk`.
SHA-256: `c40fa665b92932593e6998c437d23562af30d154ded73fbd31150f525ed7bb2d`.
Independent badging/signature inspection confirms `com.darkaxt.rshop.sharedproof`,
`R-Shop Shared Proof`, 1.7.0+12, and the established debug signer
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
The compiled fixture parent is
`/storage/emulated/0/RShopSharedProof-20261005-workflow`; confirm it is a new
absent path on the actual device before using this artifact. No installation or
native test has occurred; the Thor remains released. Recheck artifact identity
at handoff. This does not supply permission/regrant/uninstall evidence or B7
reconstruction, and is not a published application.

`integration_test/metadata_resource_test.dart` runs the existing shared resource
assertions against Android's actual SQLite plugin, private filesystem and Flutter
image decoder. It rejects non-Android, non-debug and non-isolated package IDs
before creating fixtures. It does not bootstrap production sources, contact an
account/provider, enumerate the user's collection or read SD ROMs.

The tests run sequentially:

1. Seed 30,000 synthetic collection identities with attributed overall scores;
   build the production compact query projection; verify bounded reads, index
   use, stable page ranks and rank-before-genre intersection without backfill.
   The assessment is explicitly synthetic, not approval of IGDB or ScreenScraper.
2. Snapshot 30,000 distinct edition-owned image selectors; run the real persistent
   artwork worker with one synthetic transport, including a real 4,002,288-byte
   PNG and native decoding; verify complete outcomes, bounded chunks and two
   content-addressed blobs. Close/reopen SQLite and close the transport before
   offline lookup and completed-job replay; neither may issue another request.

Both return measurements through the integration driver's `reportData`: RSS,
durations, row/chunk bounds and request results. Measurements are diagnostics,
not completion deadlines. Each fixture closes its database before deleting only
its validated, newly created private temporary child. The normal application
database, preferences, credentials, saved artwork and forensic fixture are not
targets. Host wrappers call these same assertions with the FFI factory; focused
256-artwork/3,000-query checks validate fixture extraction without repeating the
full unchanged host stress run.

## Device handoff

The user requested a pause and question before Thor testing. Obtain that handoff
before any device installation, launch or wake. Follow the signer/package and
non-uninstalling installation/driver-attachment procedure in
[DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md). Build with the explicit target
`integration_test/metadata_resource_test.dart`, not `lib/main.dart`; inspect that
exact APK before installation. Do not uninstall or clear an existing debug app's
data. Restore the normal debug APK without uninstalling after the run and switch
both displays off. Preserve diagnostics on failure; do not start a second test
while the first remains live.

This harness being written or passing host checks is not native acceptance.
Native results must be inspected before META-06/META-07 device resource evidence
can be marked verified. A successful repeat also does not explain or fix the
earlier host artwork stall. Its original private forensic fixture remains kept.

## Inspected native result — 2026-10-03

The owner authorized the connected Thor run. The APK/signature was inspected,
installed without uninstalling, and the existing driver attached to its observed
VM service. Both full-size checks passed (terminal exit 0). The query retained
128-row read bounds and no filter backfill; artwork completed, closed/reopened
SQLite and replayed offline with no extra request. See the current checkpoint in
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for measured results and
artifact identity. The exact prior normal APK was restored; normal database and
credential/preferences fingerprints were unchanged. Both displays were confirmed
OFF. This verifies the resource harness, not the unresolved META-05 source gate
or the complete user-facing metadata integration.

## Focused native metadata ownership — 2026-10-03

`integration_test/metadata_ownership_test.dart` runs the same provider/job/
grouping assertions as the host `igdb_provider_test.dart` and
`library_verified_match_grouping_test.dart`, with Android's actual SQLite
factory. Its package/platform/debug guards precede the tests. Synthetic wire
responses reach the real adapters and normal persistent jobs, manual review,
raw-release validation, edition/project grouping and offline queries. Every
database is in-memory and closed; the normal app/database is not bootstrapped.
This is not real API access, UI acceptance or ranking-source approval.

The authorized Thor run passed, including rejection of conflicting hashes,
release fields and provider IDs, correction-preserving re-scrape, reviewed
translation aliases with original-game labels and project/base separation.
Driver session 35561 exited 0; the private report and device logs were inspected.
The exact normal APK was restored without uninstalling; normal data fingerprints
were unchanged, the task forward was removed and both displays confirmed OFF.
See the current status checkpoint for artifact/evidence identity and remaining
S4 requirements. Build with this explicit target for focused ownership checks;
do not rerun the unchanged 30,000-game resource target for this extraction.

## Production score assessment integration — 2026-10-03

The shared ownership entrypoint now additionally exercises the application's
assessed community-score policy, not an injected synthetic ranking approval.
Synthetic PS1 wire responses pass through catalogue review, normal adapter/jobs,
publication, current cache selection and offline queries on Android SQLite.
The supported community rating is shared by display and rank. A low-vote
100-point project cannot enter Top or backfill a tag-filtered result; lowering
the supported count below the assessed threshold invalidates its cached rank
without a provider request. Missing ratings remain missing and coverage provisional.

The authorized Thor run and attached driver passed; exact normal APK/data
fingerprints were restored/preserved, task forward removed and both displays
confirmed OFF. See IMPLEMENTATION_STATUS.md for the inspected artifact/report.
This is integrated native policy evidence, distinct from live reception evidence
and the still-required S5 UI controls. It does not explain the earlier host wait.
