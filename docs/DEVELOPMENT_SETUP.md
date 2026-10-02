# Development setup and live-access gates

Authority: [SPECIFICATION.md](SPECIFICATION.md). This records the S1 development
environment, not a claim that the on-demand features are integrated or installed.

## Reproducible local checks

Verified toolchain: Flutter 3.47.2 / Dart 3.13.2, framework `d3b14c8769`.
The application dependency lockfile is tracked. The SDK is not vendored.
On this host Flutter is at `D:\Tools\flutter`, the Pub cache at
`D:\Tools\pub-cache`, Android SDK at `%LOCALAPPDATA%\Android\Sdk`, and Java at
`C:\Program Files\Zulu\zulu-21`. No global PATH or other project's SDK changed.

Run one workload at a time, from this repository:

```powershell
$env:TEMP = 'D:\Temp\rshop-test-runtime'
$env:TMP = 'D:\Temp\rshop-test-runtime'
$env:PUB_CACHE = 'D:\Tools\pub-cache'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
& D:\Tools\flutter\bin\flutter.bat pub get --enforce-lockfile
& D:\Tools\flutter\bin\flutter.bat test --no-pub --concurrency=1 --exclude-tags live
& D:\Tools\flutter\bin\flutter.bat analyze --no-pub
```

Create the named temporary directory if absent. Await each command's exit before
starting the next. `live` tests must be selected explicitly with configured access;
excluding them is not live evidence. Do not run the whole suite against real
accounts or start another test workload to work around a stalled one.

Device integration runs MUST pass `--no-uninstall`: the current Flutter SDK's
`flutter test` defaults to uninstalling the integration app during teardown,
which clears even the isolated debug app's catalogue/source preferences. Inspect
the resulting package and restore the normal `lib/main.dart` debug APK afterwards
with `adb install -r`; never use uninstall/reinstall as a testing reset. Synthetic
fixtures already clean only their registered paths, not application data.

## Android identity before consent or installation

| Variant | Application ID | Label | Signer |
| --- | --- | --- | --- |
| Development debug | `com.darkaxt.rshop.debug` | R-Shop Drive Dev | Local Android debug key |
| Future fork release | `com.darkaxt.rshop` | R-Shop | Not authorized/configured for publication |

The native Kotlin namespace remains `com.retro.rshop`; that is not the installed
package identity. Separate application IDs prevent replacement of upstream
`com.retro.rshop` or migration of its private database and secure storage. Before
any install, independently inspect the APK's actual package, version and signer.
Source configuration alone is not build/device proof.

The 2026-10-02 user decision preserves upstream APK naming and the release display
name `R-Shop`; only the application ID distinguishes the fork. The debug label
remains isolated for testing. Do not rename the final APK to a Drive/fork-branded
filename. No release/publication is authorized by this naming decision.

The existing local debug key was inspected, not generated or replaced. The
Android debug signing certificate SHA-1 on this host is
`F1:29:66:12:E2:FB:3F:F4:B1:5A:9B:AC:2F:A8:D1:75:2B:63:6E:5F`.
Certificate fingerprints are public identifiers, not credentials. Recompute from
the actual build signer before registration; never publish a keystore or its
private key. No release APK should be produced with upstream's debug-signing
fallback; release signing and distribution review remain a separate gate.

## Google Drive: new account-owned application setup

The account owner authorized a dedicated project. `R-Shop Drive`
(`r-shop-drive-darkaxt`, project number `593016299117`) was created in the
Google Cloud console. On 2026-10-01, its API overview confirmed Drive API enabled.
OAuth branding was saved by the account owner after policy acceptance. Audience
remains External **Testing**, with the owner account saved as its single test
user. After explicit owner authorization, both private test clients were created:

| Client | Public client ID |
| --- | --- |
| Android: R-Shop Thor development | `593016299117-fq96hg8fq5k6ufbsjn0hmiq7glpseddp.apps.googleusercontent.com` |
| Web: R-Shop Android authorization | `593016299117-f4m22d2rs93mvnsj9o559aca4a7r3f36.apps.googleusercontent.com` |

The Android registration uses the verified `com.darkaxt.rshop.debug` package and
SHA-1 above. Pass the web client's public ID as `GoogleDriveSignIn.serverClientId`.
No client secret was copied or embedded. Reloading Data Access verified that its
only configured scope is `https://www.googleapis.com/auth/drive.readonly`.
No billing was enabled. On 2026-10-02, authorized native account selection and
read-only consent succeeded on the online Thor. The production setup connector
received the actual My Drive root and its folder-list response. Continue in this
existing project; do not create duplicate clients. The remaining S1 auth lifecycle
verification is not satisfied by this first live grant.

The current normal debug APK was independently inspected and installed on
Thor `bfa98654`: version `1.7.0+12`, label `R-Shop Drive Dev`, SHA-256
`7EBF7BCBF852254E0436D0F79E6F459BA7715EB096D3E25969CD54868EE32F48`.
It is not the earlier synthetic foundation-test entrypoint. Onboarding selected
the isolated internal `/storage/emulated/0/RShopLiveTest` destination; no existing
ROM folder was selected or modified. Installation and opening Sources are not
evidence of successful provider access or feature-stage closure.

The first live Connect reproduced `setupRequired`: native Google availability
checks reported Play Store missing although the package was installed. The
manifest lacked explicit package visibility for `com.android.vending` and
`com.google.android.gms`. A focused regression failed on that omission and
passed after declaring only those packages, without `QUERY_ALL_PACKAGES`.
The rebuilt APK's compiled manifest and unchanged signer were inspected before
installation. Its Connect then opened the actual native account chooser on the
Android 13 Thor (microG 0.3.15.250932). Account selection and consent were handed
to the owner, not automated. This proves the previous pre-sign-in configuration
failure is resolved. The subsequent 2026-10-02 online retry established successful
read-only consent and real Drive access after an offline failure was diagnosed.
The installed APK was unchanged during the online retry; neither an SDK downgrade
nor a Google services replacement was needed. No source was saved and no ROM
payload requested. Folder selection/catalogue, transfer and migration acceptance
remain separate requirements.

The plugin requires a web client ID when not using `google-services.json`.
Package/signer mismatches can fail even after account selection. Follow the
[endorsed Android plugin setup](https://pub.dev/packages/google_sign_in_android).
Google classifies `drive.readonly` as restricted and grants account-wide read
access; the selected-folder boundary is additionally enforced by the application,
not by that scope. Public distribution needs its own verification review under
[Google's scope guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

The source-integration checkpoint exposes Google Drive in normal Sources and
onboarding. Enter the public web client ID, explicitly Connect, navigate the
native-app folder picker, choose the actual library folder, and save the source.
Refresh publishes its ID-based catalogue; Map folders assigns observed folders to
supported consoles. Unique known aliases are suggestions, not assignments to
unsupported systems. Unknown/ambiguous mappings require an explicit choice.
Disconnect and Revoke are labelled app-wide because the native account session
is shared by all Drive sources; neither removes source settings or local files.
These screens have host fixtures, not yet live account/controller acceptance.

Tokens are ephemeral and diagnostics sanitized. Queue requests never open account UI:
after process restart the current adapter requires an explicit Connect action;
within a connected session it can renew authorization silently. A different
account cannot satisfy an account-bound source. Disconnect/revoke is app-wide,
not implicit source deletion; a cold process cannot claim remote revocation
without reconnecting the account first.

The normal detail/library flow now enqueues supported standalone Drive files
through S3's verified transfer/installation lane. Archives, folders, CUE/M3U and
other dependency-bearing layouts remain blocked until bundle support is complete.
A cached filename is not an installed game, and ordinary HTTP fallback cannot
bypass version, checksum or ownership checks. Exact manifest-owned local removal
now uses reviewed paths/size and journaled private quarantine, with offline
startup recovery and actual SD synthetic proof. Changed files remain conflicts.
There is not yet an in-app emulator-open action; sharing a file is not
evidence of emulator launch. The live download/launch/removal round trip is still
required, not established by the single-file queue implementation.

On 2026-10-02, deliberate chooser cancellation followed by reconnect also returned
the real Drive root without another scope prompt. The current grant was reused;
this does not prove renewal after expiry. Still required: scope denial,
expiry-driven renewal, account isolation and revoke proof on the Thor.
Mocked native-platform tests do not satisfy these.

## Native foundation tests (no provider accounts or ROM access)

`integration_test/android_foundations_test.dart` runs on Android's actual Flutter
activity, SQLite, secure-storage and Google Sign-In plugins. It does not start
the normal app/library/queue, read a ROM, invoke account selection or contact a
metadata provider. It requires the isolated debug package before creating any
fixtures. The shared migration fixture opens a temporary database, not `rshop.db`
in the normal database directory. Secure-storage fixtures use their own
preferences/key namespace and remove only their synthetic keys.

The Google test initializes without a client ID, exercising the native local
resource lookup, then verifies the adapter's setup-required result. This is
plugin-startup proof only: it cannot prove OAuth configuration, consent, tokens,
Drive access, or ScreenScraper access. Database reopen and a newly constructed
credential store are not process-death/relaunch proof.

After dependency resolution, build the test entrypoint explicitly in debug:

```powershell
$env:TEMP = 'D:\Temp\rshop-native-test'
$env:TMP = $env:TEMP
$env:FLUTTER_TEST_OUTPUTS_DIR = 'D:\Temp\rshop-native-test\reports'
& D:\Tools\flutter\bin\flutter.bat build apk --debug --no-pub --target=integration_test/android_foundations_test.dart --target-platform=android-arm64
```

Create the named temporary directory first and use the SDK/Pub environment above.
Project Gradle settings cap the heap at 3 GiB, metaspace at 1 GiB and workers at
two; Kotlin compiles in-process. These are component limits, not a claim that the
whole build process tree can never exceed 4 GiB. Run no second workload while it
is active. Flutter's generated `builtInKotlin=false`/`newDsl=false` settings keep
the existing Kotlin plugin/DSL route with this SDK.
The existing `flutter_soloud` 2.1.7 plugin additionally requires NDK 23.1.7779620;
the Android SDK manager installed that side-by-side component and SDK Platform 33
during the first native build. The app itself uses Flutter's NDK 28.2.13676358.
Neither installation replaces another project's SDK/NDK selection.

Before any installation, independently inspect
`build\app\outputs\flutter-apk\app-debug.apk` using SDK `aapt dump badging`,
`apksigner verify --verbose --print-certs`, and SHA-256. Require the package,
version, architecture and debug signer described above. Check the exact package
on the explicitly selected ADB device; do not replace an unrelated installation.
Then supply that **same inspected APK**, not a newly rebuilt binary:

```powershell
& D:\Tools\flutter\bin\flutter.bat drive --debug --no-pub -d bfa98654 --driver=test_driver/integration_test.dart --target=integration_test/android_foundations_test.dart --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk --keep-app-running
```

Flutter Driver otherwise uninstalls its app at exit. `--keep-app-running` prevents
that teardown, but Flutter's install-error recovery can still uninstall an
existing matching package. Use this route only for a confirmed absent or entirely
test-owned package. An existing valuable installation instead requires direct
non-uninstalling `adb install -t -r`, explicit launch and attaching the driver to
its observed VM-service URL with `--use-existing-app`.

Inspect the exit status and per-test results. Stop only the exact test package
afterwards; fixture cleanup and generated-build cleanup must not target the real
library. A foundation-test APK is not the usable Drive/metadata application.

## Actual Android process-stop proof

`integration_test/owned_process_death_app.dart` is a standalone debug probe,
not an application mode. Build it with an explicit, new direct SD-volume child
named `RShopProcessProof-<run-id>` through `RSHOP_PROCESS_TEST_ROOT`. Inspect its
APK/package/signer, install with `adb install -r`, and launch the normal activity.
At `ARMED TRANSFER` stop only `com.darkaxt.rshop.debug`, confirm PID absence and
relaunch the same APK. Repeat at `ARMED REMOVAL`. Require the final PASSED state,
which checks exact durable resume, offline lost-receipt recovery, fresh reinstall
and unchanged neighboring synthetic save. No ROM, source or app preference is
read. The probe deletes only its exact synthetic paths on success; do not use
recursive cleanup on failure. Restore the inspected normal main.dart APK with
`adb install -r` afterwards, and switch off both screens. This proof does not
replace real Drive media and emulator acceptance.

## ScreenScraper: independent application and user access

Obtain legitimate developer authorization **for this fork**, plus a user account
with its actual quotas, through [ScreenScraper](https://www.screenscraper.fr/).
An existing RetroBat login is not authorization to copy its embedded developer
ID/password. The [API documentation](https://www.screenscraper.fr/webapi2.php)
defines separate application and user parameters.

The S1 credential store persists those two sets separately in Android secure
storage. Neither belongs in source configuration JSON, repository files, logs or
chat. The adapter owns a bounded, non-logging HTTP client because this API places
credentials in its request parameters. Export only sanitized outcome categories.
S4 still owns artwork fetching/cache jobs and fresh collection-wide refresh;
persisted media references alone are not downloaded/cached covers.

Still required: real authenticated lookup and quota handling, secure-storage
device proof, fresh matching samples and the broader-reception benchmark. A
ScreenScraper numeric rating is not yet accepted as a trustworthy overall score.

## Final device migration

S7 runs only after integrated live acceptance: fresh full metadata pass, defensible
Top 25 canonical games per console, real Drive download/launch/remove/re-download,
and an exact private keep/remove/preserve manifest. Keep every required disc in a
retained game. Tags do not create unlimited extra slots. Protect all saves, BIOS,
settings, ambiguous files and games without verified recoverable cloud copies.
Do not delete unranked games just to force the target count when coverage fails.
No cloud archive cleanup or public ROM inventory is part of this workflow.
