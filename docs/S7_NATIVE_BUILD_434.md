# S7 combined native build — 2026-10-09

Authority: QA-01, DRIVE-02 and META-05/META-07. S7 remains the sole ACTIVE
stage. This is assembly/signature evidence, not native user-flow acceptance.

## Scope and command

Assembled the current preserving S7 worktree, including committed explicit
mapping selection (`628919e`) and Wii/Wii U ranking scope (`ec4f8a2`). Existing
uncommitted S7 integration changes remain in the worktree; this APK is not claimed
to be a clean-checkout reproduction of either commit alone. No source or build
configuration was changed by this build.

```powershell
python C:\Users\darka\.agents\skills\gradle-build-gate\scripts\invoke_gradle_build_gate.py run --project C:\Users\darka\Documents\Projects\Android\R-Shop\android --kotlin-strategy in-process -- :app:assembleDebug
```

## Observed verification

- Request 434 (`564fc462e2e4415893da78c7db24ca6e`) completed exit 0;
  supervisor confirms completion and `gate_acquired=true` for
  `Local\Darka.AndroidGradleBuildGate`. Its preflight identified the existing
  compatible daemon as idle with no client connection. This does not assert
  exclusion of future nonparticipating launchers or other Windows sessions.
- Effective workers=2, parallel=false, Gradle maximum heap=3 GiB. Existing
  metaspace=1 GiB and reserved code cache=256 MiB are preserved. Kotlin 2.2.20
  retains the previously assessed in-process strategy, sharing Gradle's heap;
  no separate compiler-daemon heap is claimed. Gradle ran with existing Zulu 21.
- Test tasks report one 512 MiB fork, fail-fast and no ignored failures.
  Assembly did not execute JVM tests. The affected Dart ranking/query checks and
  scoped analysis were verified before this build; they are not native UI proof.
- Current app/SoLoud/JNI Ninja files were independently inspected: all 281
  compile/link blocks in eleven ABI files use the shared depth-one native pool.
  Obsolete `android/app/.cxx/Debug/k3s70183` output is not the current app build;
  its active configuration is `build/.cxx/debug/334d1i5j`.
- No memory-related failure or budget increase. Existing Flutter toolchain
  deprecation/Kotlin-DSL compatibility warnings were not suppressed or treated
  as a memory error. No toolchain upgrade is part of this verification.
- Private supervisor log:
  `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/ac6123ce843a42a39530b89f8ddeffd5.log`.

## Artifact and remaining native acceptance

`build/app/outputs/apk/debug/app-debug.apk`: 225,144,352 bytes; SHA-256
`b142bc809e2037c5018133cc9d97ed1058701ee81f3a2dcfd71b3a66f59ec436`.
APK v2 signature verifies with unchanged certificate SHA-256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
Package `com.darkaxt.rshop.debug`, version 1.7.0/code 12, includes arm64-v8a,
armeabi-v7a and x86_64. This normal default-ABI assembly is larger than the earlier
artifact; no custom release name/package change or external publication occurred.

The APK is not installed. Read-only inspection confirms the existing Thor
process 1335 and advancing root refresh (5,889 committed pages; active generation
1, pending generation 2). No worker interruption, account operation, ownership
adoption or ROM removal occurred. Both displays are OFF.

After a normal worker boundary, verify the signer-preserving update and actual
mapping editor/policy integration, preserving configuration, protected storage,
saves and job 76's captured membership/outcomes. Full fresh coverage, defensible
per-console retention, current-cloud verification and reviewed exact SD migration
remain required. S8-S11 remain NOT STARTED.
