# Normal APK startup reconstruction — 2026-10-05

Scope: the reported logo screen and defects exposed while reconstructing the
normal owner configuration. This is bounded S4 verification, not S4/S6/S7
completion or recovery of the historical B7 data loss.

## Findings and corrections

- The displayed logo belonged to an integration-test entrypoint. It did not
  demonstrate a hang in normal `lib/main.dart` startup. Install the normal
  owner APK in place; never run fixture teardown against the owner package.
- Manual source onboarding discarded committed console settings after the
  mapping editor invalidated its asynchronous view snapshot. Completion now
  loads committed configuration and preserves exact target/providers/mappings.
- Metadata used default Android secure-storage mode, whereas startup's
  `StorageService` uses encrypted preferences. Plugin 9.2.4's
  `checkAndMigrateToEncrypted` moves the prefixed values into that namespace;
  later default-mode reads consequently returned null. Metadata now uses the
  existing encrypted mode, recovering already stored credentials without
  deleting secrets, changing keys, or requesting re-entry.

## Verification

- Mapping regression: real `SourcesNotifier` save, empty invalidated view
  snapshot, final configuration save/reload and exact system comparison.
  Observed red before the fix; affected onboarding/source/mapping-widget checks
  then passed (`c0d36d`, exit 0), focused analysis `948a49`, exit 0.
- Credential/storage focused tests `fa26ff`, exit 0; analysis `ec6e9c`, exit 0.
  These host checks do not simulate Android encrypted preferences. A discarded
  host channel experiment could not select Android via a Flutter target-platform
  override because the plugin uses `dart:io Platform`; it was not used as proof.
- Native credential regression: the pre-fix normal APK saved both providers but
  showed ScreenScraper unconfigured after cold restart. The corrected APK,
  installed without clearing/uninstalling, cold-started and showed the existing
  ScreenScraper account/application and IGDB application credentials configured.
  No credential values were printed, exported or committed.
- Fresh native UI after explicit cold launch displayed 182 rooted remote Game
  Gear games plus the existing local GameCube game. A normal single-title IGDB
  refresh for *The Addams Family* discovered the Game Gear candidate #14207;
  explicit official-release classification/recheck completed with one match,
  zero pending/failures. Normal details displayed fresh description, release
  date and 71.8/100 score with 16 votes, **Advisory**, not eligible Top evidence.
  No ROM was downloaded. This is not an entire-collection scrape.
- Normal Android folder selection retained
  `/storage/emulated/0/ES-DE/RShopMetadata` across restart. Its credential-free
  shared database contains one durable record and one identity binding. Existing
  ES-DE data was not replaced; no ES-DE publication mapping was created.
- In-place-update comparison: all 69 fingerprinted private files were unchanged
  except removal of Android's disposable `code_cache/flutter.impeller.vkcache`;
  no new pre-launch private files. This is preservation of current reconstruction,
  not restoration of historically lost private files.

## Verified APK and build profile

`D:\Temp\rshop-normal-secure-20261005\app-debug.apk`

SHA256 `f27dee40c0fdce3323c6881458edc5ff7c534b56bfb7b1c75a7aba8bac91eff9`.
Independent inspection: `com.darkaxt.rshop.debug`, version 1.7.0+12,
`com.retro.rshop.MainActivity`, valid existing signer SHA256
`06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
`adb install -r` succeeded (`10ba85`). Cold launch `ffd7c8`: Status ok,
LaunchState COLD; actual rendered library `24156c`/`6ee632`.

Build ticket 139 (`68439` / `ebda0b`, exit 0) waited for the shared gate and held
`Local\Darka.AndroidGradleBuildGate` through confirmed completion. Effective
workers 2, parallel false, Gradle heap 3 GiB, preserved metaspace 1 GiB and code
cache 256 MiB. Kotlin 2.2.20/AGP 8.11.1 use the assessed in-process strategy;
`:app:compileDebugKotlin` executed within the Gradle budget. Test tasks were
configured one fork / 512 MiB, not executed. App native pools are configured at
one; plugin CMake task labels alone do not prove full native concurrency.
No memory-related failure or budget increase occurred. Log:
`5c0e8b5a636b4df9a5028b02cb714bf8.log` under the host gate log directory.

## Remaining broader work

S4 remains ACTIVE. Historical B7 is not retroactively passed. Native
permission-enforcement proof is distinct from already verified storage
loss/remount and expendable-package reinstall recovery. Full metadata gathering,
integrated acceptance, SD migration and the later stages are not declared done
by this startup/credential correction. No external release was published.
