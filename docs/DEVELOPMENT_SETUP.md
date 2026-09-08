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

## Android identity before consent or installation

| Variant | Application ID | Label | Signer |
| --- | --- | --- | --- |
| Development debug | `com.darkaxt.rshop.debug` | R-Shop Drive Dev | Local Android debug key |
| Future fork release | `com.darkaxt.rshop` | R-Shop Drive | Not authorized/configured for publication |

The native Kotlin namespace remains `com.retro.rshop`; that is not the installed
package identity. Separate application IDs prevent replacement of upstream
`com.retro.rshop` or migration of its private database and secure storage. Before
any install, independently inspect the APK's actual package, version and signer.
Source configuration alone is not build/device proof.

The existing local debug key was inspected, not generated or replaced. The
Android debug signing certificate SHA-1 on this host is
`F1:29:66:12:E2:FB:3F:F4:B1:5A:9B:AC:2F:A8:D1:75:2B:63:6E:5F`.
Certificate fingerprints are public identifiers, not credentials. Recompute from
the actual build signer before registration; never publish a keystore or its
private key. No release APK should be produced with upstream's debug-signing
fallback; release signing and distribution review remain a separate gate.

## Google Drive: new account-owned application setup

No Google project or OAuth client for this fork exists in the verified setup.
When the account owner performs the Google console steps:

1. Create/select their own project and enable the Google Drive API.
2. Configure consent for this application and its intended private test audience.
3. Register the **debug package and actual signing certificate** as an Android
   OAuth client. Register a web OAuth client in the same project and pass its
   public client ID as `GoogleDriveSignIn.serverClientId`.
4. Request only `https://www.googleapis.com/auth/drive.readonly` for Drive access.
   No embedded client secret, copied application credentials or write scope.

The plugin requires a web client ID when not using `google-services.json`.
Package/signer mismatches can fail even after account selection. Follow the
[endorsed Android plugin setup](https://pub.dev/packages/google_sign_in_android).
Google classifies `drive.readonly` as restricted and grants account-wide read
access; the selected-folder boundary is additionally enforced by the application,
not by that scope. Public distribution needs its own verification review under
[Google's scope guidance](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

S1 implements the injected native adapter, not the final setup UI. Tokens are
ephemeral and diagnostics sanitized. Queue requests must never open account UI:
after process restart the current adapter requires an explicit Connect action;
within a connected session it can renew authorization silently. A different
account cannot satisfy an account-bound source. Disconnect/revoke is app-wide,
not implicit source deletion; a cold process cannot claim remote revocation
without reconnecting the account first.

Still required: actual consent, cancel/denial, renewal/reconnect, account isolation
and revoke proof on the Thor. Mocked native-platform tests do not satisfy these.

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
