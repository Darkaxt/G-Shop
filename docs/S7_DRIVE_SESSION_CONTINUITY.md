# S7 Drive session continuity — 2026-10-08

Authority: DRIVE-01 in SPECIFICATION.md. S7 remains ACTIVE; this is a bounded
regression correction, not stage or overall completion.

## Cause and implementation

`GoogleDriveSignIn.authenticate(interactive: false)` returned only an in-memory
account. Cold process startup therefore returned null before any scope/token
renewal. Configuration and secure storage survived installation; no evidence
established Google grant expiry as the cause. Disabling all restoration had
incorrectly conflated silent authorization with Credential Manager's lightweight
flow, which can show a chooser in the installed Android plugin 7.2.17.

After explicit successful read-only authorization, retain only account ID/email
in the existing encrypted private storage, keyed by OAuth client. On cold start,
the coordinator checks the saved source account ID before requesting a token
through the endorsed Android platform implementation. That implementation sets
the exact account email in AuthorizationClient and disables resolution prompting.
Missing reference/consent and mismatches remain rejected. Sign-out clears the
reference. No access, ID or refresh token is persisted or exported. No additional
OAuth scope, server, native account enumeration or second-account setup is added.

Reference: [Google Android authorization](https://developer.android.com/identity/authorization).
The dependency's installed Java/Dart implementation was inspected directly for
`setAccount` and the `promptIfUnauthorized=false` PendingIntent rejection path.

## Verification

- Regression-first restart cases failed on absent persistence and wrong-account
  outcome. Current focused `google_drive_sign_in_test.dart` and
  `drive_authorization_test.dart` checks pass with concurrency one. They cover
  account/client isolation, no chooser/lightweight calls, read-only scopes,
  absent/revoked consent, restored rejection renewal, sign-out/revocation clearing,
  redaction and existing serialized grant/cancellation behavior. Scoped analysis
  and `git diff --check` pass. No full suite was needed for this isolated adapter.
- Shared-gate ticket 400 (`314905ac6c0540febdbabcfa7637aef9`) completed exit 0;
  gate acquired and profile verified. Observed workers=2, parallel=false,
  Gradle heap=3 GiB, Kotlin in-process; existing metaspace/code-cache flags kept.
  Test tasks configured one 512 MiB fork; assembly did not execute JVM tests.
  Fresh app/SoLoud/JNI Ninja compile/link blocks all use depth-one pools. No
  memory-related failure or budget increase. Log retained privately at
  `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/f17f6a2360854ca4be5359e5bf6498ba.log`.
- Actual installed APK SHA-256:
  `134b657aae6b07a52c4bf2d1ef34c17c1794cd70ed6f5a46421dd055eb80eefb`.
  APK v2 signature verifies with unchanged signer SHA-256
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
- Normal default-account Connect seeded the previously absent reference without
  saving a different source. Joined Pause -> confirmed process exit -> launch
  changed PID 14836 to 18345. Normal Resume advanced the same job 76 from
  12,194 to 12,199 lookups without a chooser.
- Joined Pause -> same-APK install-replace -> launch changed PID to 21935.
  Config and both protected storage digests matched before/after replacement.
  Normal Resume advanced 12,204 to 12,209 lookups, with 31,682 pending and 357
  rated; no intervening connection/account selection. This isolates Package
  Manager process replacement and data retention, not a future arbitrary schema
  migration. No owner sign-out/revocation or second-account live test was needed.
- Config hash remained `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
  No ROMs, source mappings, collection snapshot or ownership records were altered
  by the verification. Exact temporary UI captures were hash-rechecked, removed
  and verified absent. Thor Asleep; both actual/committed display states OFF.

Full metadata coverage, defensible retention, remaining normal format recovery
and reviewed SD migration remain S7 acceptance work; S8-S11 are NOT STARTED.
