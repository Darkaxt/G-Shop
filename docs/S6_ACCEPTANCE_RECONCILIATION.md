# S6 integrated reconciliation

Authority: `SPECIFICATION.md`, revision 6. Status: **COMPLETE**.
Base: `145b5a3`, following S4 closure; current remediation starts from `a3b9c87`.
S7-S9 are NOT STARTED; this document
does not declare the fork complete.

## Earlier S6 checkpoint — 2026-10-05

The remaining-work column below records the earlier checkpoint. The subsequent
closure evidence resolves it; it is not the current stage status.

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

Earlier normal verification artifact (superseded by the inspected current APK
below and subsequently cleaned as task-generated output):
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

At that checkpoint, remaining real-device verification was ordinary unfinished
current-stage work, not a reason to open S7.

## Integrated normal-device closure — 2026-10-05

The normal owner package, not a fixture entrypoint, exercised the combined
workflow on Thor `bfa98654`. Existing source IDs and the Game Gear configuration
were preserved. The existing GameCube source was mapped through the normal
source UI; Android's directory picker selected a previously absent isolated SD
destination. No existing ROM folder was cleaned or adopted.

- Fresh normal ScreenScraper lookup, cached candidate review, explicit official-
  release classification and verified recheck completed before any ROM transfer.
  Facts generation 5/provider game 4772 was retrieved at
  `2026-10-05T10:53:20.072776Z`; its artwork job completed with two cached images.
  The same facts and artwork were independently found in the selected durable
  shared namespace. Normal details displayed the actual cover, screenshot,
  description, developer and advisory 75/100 rating. Unknown vote count remains
  explicit; this advisory score is not promoted into a reliable Top-25 basis.
- Normal Download completed the authorized 20,131,764-byte RVZ on the SD card.
  Native publication was confirmed; the completed journal contained provider
  MD5/SHA-1 and independently checked SHA-256, and its staging file was retired.
  The ordinary Open in Dolphin action reached the actual game title screen.
- Normal removal preview named exactly that installed ROM and its size.
  Confirmed removal left the remote item and its fresh metadata/artwork intact.
  The adjacent 78-byte synthetic save fixture retained its exact digest.
  Re-download completed and reproduced the original RVZ digest.
- With Wi-Fi actually disabled, a fresh process cold launch reached the normal
  Library in 2362 ms. The installed tab retained the game and advisory score;
  details decoded the cached cover/screenshot and description. Normal Open in
  Dolphin again reached the game title screen offline. The original Wi-Fi setting
  was restored. No host ROM downloader or RomM server participated.
- The 15 pre-existing Dolphin configuration/save paths remained present. The
  existing F-Zero save and all controller/configuration files retained hashes.
  Only Dolphin's TimePlayed and SRAM files changed after actual emulation;
  these are legitimate emulator writes, not a claimed byte-identical launch.
  No emulator save/settings restoration or deletion was performed.

The final database integrity check returned `ok`; metadata/artwork jobs 5/6
were completed, the transfer was completed with one exact target owner, and
both configured source refreshes had no pending catalogue work. Private file
inventories, source object IDs and credentials are intentionally not committed.

## Source-status remediation and current installed artifact

The live source editor exposed an unconditional **Setup required** heading even
for an already-configured source and after successful connection. This was a UI
state defect, not evidence of broken OAuth. The heading/help now distinguishes
new setup, existing-client connection and connected folder selection, retaining
the read-only whole-account/folder-boundary explanation.

Regression `39a02d` failed on both missing state transitions before the fix.
The first implementation run failed compilation because the local variables
were inserted into folder navigation rather than build; that failed run is not
green evidence. Corrected focused run `065b9f` / `dcd479` passed the source-screen
workflow and analysis with no issues. No authentication or transfer behavior was
changed. The actual normal Thor editor then showed **Connect to Google Drive**
with its saved client, and **Connected to Google Drive** after normal default-
account selection and real API folder listing (`92fdef`, `e648fe`). Leaving this
editor did not change the saved source or root.

Current normal artifact: `build/app/outputs/apk/debug/app-debug.apk`, SHA-256
`d9563f47301ded82f85a6b23a1675930138adc6d5b75bc6c8eb60db5d024fdd6`.
Independent package inspection confirms `com.darkaxt.rshop.debug`, normal
`com.retro.rshop.MainActivity`, version 1.7.0+12 and unchanged signer. In-place
installation succeeded (`dbf250`). Before first launch, all 37 inspected files
under files/databases/shared_prefs retained paths and hashes (`54f71d` companion
comparison). The separately read app_flutter configuration exactly matched its
pre-update object, including existing sources/mappings/targets (`813bd0`
companion comparison). No uninstall, clear or secret re-entry occurred.
The revised APK cold-started offline in 2350 ms into the real Library (`54f71d`).

Build ticket 144 acquired the shared gate but failed because PowerShell split an
unquoted `-Ptarget` argument into a `.dart` task; this was not a memory failure.
Correctly quoted ticket 145 acquired and retained the same host-wide mutex
through successful exit (`853ccd` / `ae125e`), log
`82eb23c063774e6890cc064a1a9c0780.log`. Observed workers 2, parallel false,
Gradle maximum heap 3221225472 bytes; assessed Kotlin 2.2.20/AGP 8.11.1 in-process
shares that heap. Test tasks were configured one fork/512 MiB, not executed.
App native pools remain one; unchanged plugin-native tasks were up-to-date, so
full plugin native concurrency is not claimed freshly measured. No memory
failure, budget increase or competing build interruption occurred.

The user's logo-hang report was not reproduced by the fresh normal online and
offline launches. These startup observations do not establish the historical
hang's cause, and no speculative timeout/retry/startup change was added.

## Requirement reconciliation and closure

| Required boundary | Inspected applicable evidence | Remaining S6 acceptance |
| --- | --- | --- |
| CORE-01/02/03, DRIVE-01, META-02 | S1 reconciliation retains exact identity, additive migration and actual legitimate provider/auth evidence. Current configured sources and secure storage survive the normal update; fresh metadata precedes ROM transfer. | None. |
| DRIVE-02/03 | S2 rooted pagination/source/queue checkpoints, current focused provider/config/queue regression above, and normal live mapped catalogue/download flow. Existing Game Gear source remains configured; both refreshes completed. | None. |
| DRIVE-04/05/06 | S3 range/version/checksum/resource/lifecycle/ownership/bundle checkpoints and current streaming regression, plus the current real SD verification, emulator boot, preview/removal/re-download and offline handoff above. | None. |
| META-01/03/04/05/06/07/08 | S4's requirement-level closure and current focused metadata/query/store checks remain applicable to unchanged implementations. Current real fresh review/recheck and shared facts/artwork persist across removal, cold offline launch and in-place update. Advisory scores remain advisory. Full-library fresh coverage is explicitly S7. | None for S6 integrated scope. |
| UI-01/02/03 | S5 requirement-level native/shared-caller/filter/controller proof and current affected detail/Library checks; actual fresh cover/score/details and ordinary controller/menu flow, plus the verified source-status correction above. | None. |
| QA-01/02/03 | Serial focused regressions, observed gated build profile, inspected normal APK identity/preservation, actual combined workflow and unchanged read-only/privacy implementation. S1's processed release-name evidence remains applicable; no release occurred. | None. |
| QA-04 | Complete specification reviewed against its requirement-to-stage map, the stage reconciliations and current integrated evidence. No required S1-S6 blocker or tracked deferral remains. | None for S6; overall reconciliation must be repeated after S7-S9. |
| MIGRATE-01 / COMPANION-01 / ART-01 | Assigned by the authoritative specification to S7 / S8 / S9 respectively. No bulk scrape, reviewed SD migration, companion integration or full artwork audit is claimed here. | Required later stages are NOT STARTED, not waived or S6 deferrals. |

S6 is COMPLETE against its assigned criteria. The full plan remains incomplete.
No S7 implementation has begun in this closure. Task-owned screenshots, UI XML,
synthetic save fixture and superseded APK were reviewed and cleaned; the current
APK and normal test installation remain. Both physical displays reported OFF /
committedState OFF (`958170`). No user ROM/save/BIOS/settings cleanup occurred.
