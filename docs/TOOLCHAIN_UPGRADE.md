# Installed Gradle 9.x upgrade

Authority: SPECIFICATION.md, QA-04. Implementation explicitly authorized
2026-10-11. Scope is build maintenance only, not S7 migration or an app release.

## Compact stage and acceptance mapping

TM1 — Upgrade and verify the Android toolchain: COMPLETE. All four acceptance
items below are reconciled with the inspected evidence and this verified change's
commit. No product stage is closed by this maintenance work. S7/S10 remain
BLOCKED on the scoped execution hold; their unfinished criteria are unchanged.

QA-04 acceptance:

1. Reuse an installed stable Gradle version newer than 9.0 and pin its official
   distribution checksum.
2. Review plugin/JDK/Flutter compatibility; retain application identity, signing,
   SDK/NDK versions and native build limits.
3. Through QA-01's shared gate, pass Android JVM tests and build a debug APK.
   Inspect actual worker/JVM/test/native settings and memory failures.
4. Reconcile evidence and warnings, clean expendable task outputs, and commit.

No tracked deferrals. No deployment, device use or release is authorized/needed.

## Reviewed selection

- Before: Gradle 8.14-all, AGP 8.11.1, Kotlin Gradle plugin 2.2.20.
- Selected: installed Gradle 9.1.0-bin, AGP 8.13.2, KGP 2.3.21. Both selected
  plugins also already have artifacts in the host's module cache.
- Flutter remains the installed 3.47.2; do not modify its included plugin build.
- Gradle runtime uses the existing JDK 21; app Java/Kotlin bytecode remains 17.
- Gradle's major-upgrade guide requires AGP >=8.4 and KGP >=2.0. Kotlin's matrix
  puts KGP 2.3.20–2.3.21 in Gradle 7.6.3–9.3.0 and AGP 8.2.2–9.0.0. Therefore 9.1.0
  avoids the extra plugin/AGP migration needed to target newer installed versions.
- The separate Android class-file/dexer review requires R8 8.13.19 for Kotlin
  2.3. AGP 8.13.2 bundles that version; retaining 8.11.1 would not satisfy that
  requirement. This corrects the initial AGP-unchanged selection before build
  admission; the build's dependency evidence must confirm the final selection.
- Flutter's included build pins KGP 2.2.20 (outside Kotlin's fully-tested Gradle
  range); this is upstream-controlled and must be validated by actual compilation,
  not represented as a fully vendor-matrix-tested combination.
- Migrate the app's deprecated kotlinOptions to compilerOptions/JVM_17 without
  changing bytecode level. Retain assessed in-process compilation, the 3 GB
  Gradle budget, two workers/no parallelism and CMake compile/link pools of one.
- Official 9.1.0-bin SHA-256:
  a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806.

Sources: [Gradle 9 migration](https://docs.gradle.org/current/userguide/upgrading_major_version_9.html),
[Kotlin compatibility](https://kotlinlang.org/docs/gradle-configure-project.html),
[AGP 8.13.2 Kotlin support](https://developer.android.com/build/releases/agp-8-13-0-release-notes),
[Android Kotlin/dexer requirements](https://developer.android.com/build/kotlin-support),
[official distribution checksum](https://services.gradle.org/distributions/gradle-9.1.0-bin.zip.sha256).

## Verification — 2026-10-11

All four QA-04 acceptance items are satisfied for this bounded maintenance scope.
The installed 9.1.0 distribution was actually used, not merely selected in a file.

Command (through the installed gradle-build-gate launcher, not direct Gradle):

```text
run --project C:/Users/darka/Documents/Projects/Android/R-Shop/android
    --kotlin-strategy in-process --
    :app:testDebugUnitTest :app:assembleDebug
    -Ptarget-platform=android-arm64 --warning-mode=all --stacktrace
```

- FIFO ticket 569, ID `080c6bee37d84c0bbbc507ad9c1fb7be`: the supervisor
  acquired `Local\Darka.AndroidGradleBuildGate`, inspected existing activity and
  waited before starting. Completion is verified in its support record; exit 0,
  no cancellation or interruption. This is participating-launcher coordination,
  not a claim that Android Studio universally honors the mutex.
- Build log:
  `C:/Users/darka/AppData/Local/Tools/gradle-build-gate/logs/f77c502c9b234b6f84b2dd193d6415af.log`.
  It ends `BUILD SUCCESSFUL in 11m 25s`; Kotlin compilation, app JNI builds,
  debug JVM tests, dexing, signing and APK packaging actually executed.
- Fresh XML reports in `build/app/test-results/testDebugUnitTest` are dated
  2026-10-11 13:19:23 +03:00: 55 tests, zero failures and errors, covering the
  existing archive/grant/publication, companion and save-boundary logic. This
  verifies build compatibility, not the unfinished S7/S10 product criteria.
- Runtime profile markers verify two workers, parallel=false, JVM maximum heap
  3,221,225,472 bytes, with 1 GB metaspace and 256 MB code-cache arguments retained.
  Kotlin in-process was explicitly selected and the existing project setting
  agrees; no project task-specific override was found. No separate Kotlin heap
  was needed. Test markers are configuration-time evidence for one fork/512 MB,
  failFast=true and ignoreFailures=false; the fresh reports prove execution, not
  a measured peak test-process memory budget.
- Generated Ninja rules verify `rshop_native` depth=1 with compile/link use for
  the app's ARM64, ARMv7 and x86_64 builds and the rebuilt audio plugin. JNI plugin
  builds also ran; `target-platform=android-arm64` does not suppress every native
  dependency's ABI tasks. The worker limit and per-Ninja pools are not a universal
  host memory cap. No memory-related failure or budget increase occurred.
- Inspected `build/app/outputs/apk/debug/app-debug.apk`: 145,895,355 bytes,
  SHA-256 `0f1ffe0660b6a00dc2b5e40cb9a97772a1c0b55b828198af346cd695ffde4c06`.
  The Flutter APK copy has the same digest. Package remains
  `com.darkaxt.rshop.debug`, version 1.7.0 (12), min SDK 24/target SDK 36.
  `apksigner verify --print-certs` succeeds with the Android debug certificate
  SHA-256 `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Release identity and signing configuration are unchanged; no release build or
  device installation is claimed.
- Transactional cleanup `c86b79120c75e20bfaa90870ea840d13` reviewed the two exact
  APK output directories and applied with zero eligible files. Those paths
  pre-existed and were preserved under the helper's protection; no unrelated
  build cache, prior artifact or user data was deleted. Test/build evidence remains
  available for review. `git diff --check` passes.

### Reviewed warnings and remaining scope

Flutter's included Gradle plugin compiled successfully despite its Kotlin DSL
version warning. Flutter warns that AGP 8.13.2 support will eventually be dropped
in favor of AGP >=9.0.1. Dependency plugins emit Gradle 10/Groovy deprecations,
manifest namespace warnings, SDK XML-version warnings and existing audio C++
warnings. These do not fail this Gradle 9.1 build; no warning suppression,
version-check bypass, shared Flutter SDK edit or Pub-cache patch was introduced.
An AGP 9/Gradle 10 migration is not part of this request. There are no blockers
or tracked deferrals for TM1. S7/S10 and the overall fork remain unfinished.
