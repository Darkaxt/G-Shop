# S8 per-edition companion launching

Authority: COMPANION-01; S8 is COMPLETE, S7 remains BLOCKED as recorded in the
current status entry. This design adds no scope or approval checkpoint.

## Source and Android boundary

The complete public tree of [CocoonFE at
17ba7aa5ef1b490c870292a0ee2baa6cd4bb81ff](https://github.com/inssekt/CocoonFE/tree/17ba7aa5ef1b490c870292a0ee2baa6cd4bb81ff)
was inspected through GitHub's non-truncated recursive tree on 2026-10-09. It
contains README, platform JSON/scripts, feedback workflows and promotional media,
not the Android launcher implementation. The repository API reports no license
and the tree contains no license file. No Cocoon code/assets are copied; do not
invent a source-review claim for its private companion implementation.

Use independently implemented public Android APIs:
[ActivityOptions.setLaunchDisplayId](https://developer.android.com/reference/android/app/ActivityOptions#setLaunchDisplayId(int))
and [ActivityManager.isActivityStartAllowedOnDisplay](https://developer.android.com/reference/android/app/ActivityManager#isActivityStartAllowedOnDisplay(android.content.Context,%20int,%20android.content.Intent)).
Thor API 33 currently exposes built-in 1920x1080 and presentation-capable
1240x1080 displays with IDs 0 and 4. IDs are observations, never configuration
constants. Resolve the default display and one eligible public presentation
display each launch; absent/ambiguous/rejected placement fails visibly. Do not
guess among multiple secondary displays or add a general display manager UI.
Native app-UID preflight and actual normal UI placement have now been verified
below; shell inventory alone was not treated as application permission proof.

## Narrow vertical slice

1. Reuse the current exact catalogue edition ID, independently of scraped score
   acceptance. Store an optional launcher component in the existing acknowledged,
   serialized selection preferences. No filename-only or console-wide keys.
2. Existing game-details quick menu opens a controller/touch app chooser with
   select/change/clear and current association. Enumerate only installed exported
   MAIN/LAUNCHER activities through scoped package visibility. No APK installation.
3. Normal Open resolves the current edition association and enters the existing
   exact owned/byte-observed ROM preflight. Reuse the same URI grants and emulator
   intents. With no association, preserve the existing native launch unchanged.
4. Pair preflight resolves both displays and the exact installed companion
   component before either activity starts. Request the companion on the lower
   display and emulator on the top. No timers, kills, root or ADB at runtime.
   Reuse in-flight handoff joining. Android activity acceptance is not a ROM boot
   claim; errors must distinguish rejected/partial pair requests. Ordinary Open
   without companion remains explicit, never silently clear the association.
5. Prove the real path on Thor before broadening: two independent ROM bindings,
   restart/refresh, touch/controller select/change/clear, actual placement,
   repeated activation, supported ordinary launch and failure cases. Preserve
   original ROM/save/settings state and finish with both screens OFF.

## Acceptance ledger

Every COMPANION-01 criterion below is satisfied by inspected evidence. S8 has no
remaining blocker or tracked deferral. S7's outstanding migration remains
required at overall reconciliation; this is not overall S1-S11 completion.

| COMPANION-01 criterion | Evidence / remaining work |
| --- | --- |
| Cocoon source/license and public Android boundary | Inspected pinned complete public tree above; no private implementation or license-compatible reuse was available. Independently implemented Android APIs. |
| Exact per-edition identity and isolation | Two existing SG-1000 ROMs independently selected through normal details. Clearing the second retained the first. Focused real SQLite catalogue replacement/rename test resolves both through the UI's cached metadata lookup and retains their distinct assignments. No filename-only binding. |
| Touch/controller select/change/clear | Touch selected Clock; injected controller D-pad/A selected Calendar and cleared it; touch changed the second assignment to Clock. Widget checks cover touch, controller change, clear, cancellation and rejected durable writes. This is injected Android controller input, not a claimed physical-controller session. |
| Actual ROM top / companion bottom | Normal Open booted both selected SG-1000 titles in RetroArch on actual display 0. Clock ran on actual display 4; both physical captures and resumed activity records were inspected. Calendar was also placed on 4 but its own first-run permission flow was not accepted. Clock's notification prompt was dismissed with Back, not granted. |
| Repeated activation | Focused pending-handoff test joins two callers into one native request. Two rapid live Open taps retained one RetroArch activity/task on top and one Clock activity/task below. Android intent acceptance alone was not used as ROM-boot proof. |
| Missing/unlaunchable app, rejected placement, unavailable display | Instrumentation under R-Shop's actual UID enumerated installed launchers, resolved 0/4, rejected a missing component, rejected R-Shop itself, and rejected an invalid display before starting either app. Native unit cases cover missing/default/ambiguous and non-contiguous display identities. |
| Ordinary launch | Explicit Open without companion booted the second ROM on top while the bottom remained its launcher. Stored association was not silently cleared. Existing emulator grant/format checks pass. |
| Restart | Paused saved worker 76 was confirmed before stopping only R-Shop for a controlled restart. PID 7070 exited; normal launch created PID 27415. Both exact assignments survived. No emulator or unrelated application was killed. |
| Catalogue refresh | Real SQLite replacement/rename check passes. Existing startup refresh completed all 26 consoles; normal Library then exposed both original exact ROM entries with their saved Change / clear companion actions. Both were inspected after refresh, not inferred from preference bytes alone. |
| Save/settings/ROM preservation | Private before/after journals contain the same 146 observed shared files (304,569,033 bytes), with no added, missing, changed or unstable file. Includes RetroArch saves/states/settings, the actual emulator used. The strict all-scope verifier exits 1 because the pre-existing PPSSPP shared path remains absent/unreadable; this is not claimed as universal save coverage. Both test ROMs were hashed; no download, adoption or deletion was performed. Configuration hash and published root remain unchanged; encrypted account-reference ciphertext can legitimately change during silent native authorization. |
| Final live cleanup | Both test-only associations cleared through normal UI, leaving an empty companion map. Normal Resume advanced unchanged job 76 from 19,947 to 19,956 requests with no chooser; published root remains active=2, pending=null and configuration hash unchanged. Thor is Asleep; both physical actual and committed display states are OFF. |

## Build and focused verification

Gated production assembly/native unit ticket 459 and Android-test assembly ticket
461 completed successfully. Both supervisors acquired
`Local\Darka.AndroidGradleBuildGate`, retained it through completion and verified
completion. Observed workers=2, parallel=false, Gradle heap=3 GiB; Kotlin 2.2.20
uses in-process compilation. Unit tests use one 512 MiB fork. No memory-related
failure or budget increase occurred. No competing build was launched.

The preserving installed production APK matches SHA-256
`a9c5f4269f151fc3041554e455622575977d9f8c73dd0448beaf985de999032f`
and the established signer. The same source has scoped Dart analysis with no
issues. Focused selection, catalogue identity, picker, handoff and existing native
grant-contract checks pass; there was no full-suite run. One combined invocation
also named a nonexistent grant test file and therefore exited 1 despite its
executed cases passing; the actual `android_owned_emulator_grant_test.dart` was
then run successfully. The new catalogue fixture initially omitted required job
schema installation; that fixture error was corrected before its passing run.

Private captures and preservation journals are verification evidence, not a
public library inventory or a backup/removal authority. No live claim above
waives S7's remaining migration or save-coverage requirements.

After recording the inspected evidence, exact temporary captures were removed:
transaction `1c400deae1944aa86827e2e88dfecf08` applied its reviewed ticket with no
residuals, deleting eleven PNG captures and their empty task directory
(3,284,702 bytes). The three exact on-device XML/PNG capture files were also
removed and verified absent. Private preservation journals and current build
evidence remain available. Cleanup does not remove ROMs or application data.
