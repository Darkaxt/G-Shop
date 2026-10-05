# S6 integrated reconciliation

Authority: `SPECIFICATION.md`, revision 6. Status: **ACTIVE**, the sole ACTIVE
stage. Base: `145b5a3`, following S4 closure. S7-S9 are NOT STARTED; this document
does not declare the fork complete.

## Current verified scope — 2026-10-05

| Acceptance boundary | Evidence | Remaining S6 acceptance |
| --- | --- | --- |
| QA-02 existing providers, configuration, queue and additive migration | Serial focused command `6503ef` / `39478f` exited zero: Web/FTP/SMB/native-SMB, RomM API/pairing/mapping, provider factory/config, source contract, config parse/persistence/bootstrap, mixed queue, transfer journal, exact Drive runtime/bundles/authorization/verification and library upgrades. Stream checks retained 65536-byte chunks for 32/256 MiB bodies without whole-file buffering. | Combined current normal-device workflow and private-state preservation still required. These tests are not real provider/device proof. |
| QA-02 metadata/UI integration and current interface | S4 closure covers normal shared-store/publication/artwork/query integration. S6 corrected the details fixture's override to forward the new artwork parameter. Its real empty cache is isolated; host readiness/IO and UI run in one real clock with actual operation joins and existing offline fonts. `a2d461` / `c990af` passed all three viewport detail/retry/exact-game refresh paths. Console/Library/normal cover workflow `83432c` / `967d6b` passed, retaining original pixel cache distances with the supported ScrollCacheExtent API. | Normal-device recheck of the S6 source, including real on-demand installation, offline relaunch and save-safe owned removal. |
| QA-01 async error boundary | Full source analysis identified an unawaited RA-cover fallback inside try/catch. Regression `d834ac` reproduced the escaped asynchronous database error. Awaiting that fallback keeps the existing failure-to-unavailable contract; the regression and affected preload/localization tests passed within `4ece12` / `07e9cb`. Current source analysis and gated normal APK build/startup are verified below. | Combined native on-demand verification remains; the startup check alone does not close S6. |
| QA-03 read-only/privacy | Source inspection confirms Drive metadata/media use read-only operations, request-time authorization and sanitized exception categories. Credential stores remain private and redacted. Shared facts/artwork contain exact bindings but no tokens, credentials or operational installation ownership. `metadata_credentials_test.dart` and existing boundary/config tests pass in the focused regression command. | Recheck current APK identity and real workflow's state/save preservation before S6 closure. No release is authorized. |
| QA-04 full specification mapping | S1/S4/S5 reconciliations and S3 native checkpoints retain their distinct real versus synthetic proof. META-08 is implemented and verified, not moved out of S4. Full collection fresh scraping/Top-25 migration belongs to S7, companion launching to S8 and full media-format audit to S9. | Complete integrated result reconciliation after the remaining real workflow. S7-S9 must later reconcile again before overall completion. |

## Failed attempts retained honestly

- Full analysis `91a8dc` / `c87861` found the new details-test override error
  and the four previously recorded analyzer findings. They were not suppressed.
- The first affected run `4ece12` / `07e9cb` passed preload/localization checks
  but failed details fake-clock settling and grid compilation because the new
  rendering type needed an explicit import. That invocation is not wholly green.
- A runAsync experiment (`9d801b`) could not join a future already owned by the
  fake-clock scope. It was explicitly stopped (`010d13`); its process tree was
  confirmed absent before another test launched. No concurrent workload or
  timeout-based production behavior was introduced.
- The real-clock attempt `c2e01a` exposed the fixture's unresolved public fonts.
  It failed rather than discard the exception. The corrected host fixture uses
  the existing named font cache with runtime fetching disabled, then passes.
- These failed host attempts did not install a test entrypoint over the owner.
  Subsequent normal-device startup verification is recorded below; it is not
  evidence for the still-required combined on-demand workflow.

## Current normal APK and owner preservation

Full current-source analysis `8e021d` / `10e42d` exited zero with no issues.
Normal `lib/main.dart` build `44924b` / `23a16f` exited zero. Gate ticket 143
acquired `Local\Darka.AndroidGradleBuildGate` and held it through completion.
Inspected log `a13a94fd5479431abf065426b49c7d4b.log` reports workers 2,
parallel false, Gradle maximum heap 3221225472 bytes. Assessed Kotlin 2.2.20 /
AGP 8.11.1 uses in-process compilation, sharing that heap. Test tasks were
configured one fork / 512 MiB, not executed. App native pools are configured
at one; full plugin native concurrency is not claimed measured. No memory
failure or heap-budget increase occurred.

Retained normal verification artifact:
`D:\Temp\rshop-s6-normal-20261005\app-debug.apk`, SHA256
`bbb07c08455c92fcc5a9a62adb8d5268597d84fb5a3c9ea726ecaa6a4de78729`.
Independent inspection confirmed the normal owner package/activity, version
1.7.0+12 and unchanged signer. In-place install `1cc59b` succeeded. The valid
full pre/post-install comparison (`f50b4d` / `c2d522`) retained all 46 private
file paths and hashes except Android's `files/profileInstalled` marker.
Configuration, database, credential and artwork hashes were unchanged before
launch. No owner uninstall, clear or credential re-entry occurred.

Fresh cold launch `a7e9b7` returned Status ok, COLD, TotalTime 2336 ms. Actual
accessibility hierarchy showed `182 / 1 / ALL GAMES / Library`, not the logo.
The exact task-owned UI XML was removed after inspection. Both physical display
devices subsequently reported OFF / committedState OFF (`19aed0`).

No external S6 blocker or tracked deferral is identified. Remaining real-device
verification is ordinary unfinished current-stage work, not a reason to open S7.
