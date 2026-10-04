# S1 acceptance reconciliation

Authority: [SPECIFICATION.md](SPECIFICATION.md). Stage status: **COMPLETE**.
This is a requirement-level index of inspected evidence, not a new execution
stage or a claim that the complete fork is ready.

| Requirement | Applicable evidence | Remaining S1 acceptance |
| --- | --- | --- |
| CORE-01 | The verified S2/S3 real Drive catalogue/install/remove workflow retains the remote entry. S4/S5 metadata publication and cached browsing operate without ROM-body requests. See the corresponding checkpoints in [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). | None; the separately required full-library scrape and migration belong to S7. |
| CORE-02 | `library_identity_test.dart` covers explicit Nintendo/Sony/Sega/Microsoft aliases, unsupported mappings, distinct account/source/object IDs, regions/discs and independent translation/hack/patch evidence. Native and live catalogue checkpoints exercise the same identities. | None. |
| CORE-03 | Actual additive SQLite upgrade/reopen fixtures preserve records and legacy score provenance; native foundation and subsequent S3/S5 migration checks exercise the Android boundary. The v33 preservation/query evidence applies to current HEAD `bf160a8`. | None. |
| DRIVE-01 | Actual native consent, decline/reconnect, remote revocation with held-grant HTTP 401, microG cache-clear/silent authorization and real root metadata are recorded in the 2026-10-02 authorization repair checkpoint. Natural rejection, different-token noninteractive renewal and real root success passed on 2026-10-04 as recorded below. Offline account-binding and privacy contracts remain. | None. The live second-account test was explicitly waived by the user on 2026-10-04; no second account was enrolled and no live isolation success is claimed. |
| META-02 | The 2026-10-03 actual production ScreenScraper adapter authenticated with legitimately issued fork application access plus the standard user account, parsed metadata/media references/sourced scores and requested no ROM bodies. Focused unsupported-platform, invalid-access and credential-redaction contracts passed. S5 exposes secure setup. | None; full fresh collection scraping belongs to S7 and reception/ranking requirements retain their own stage ownership. |
| QA-03 | Processed release manifest verification preserves `R-Shop`, `com.darkaxt.rshop` and upstream APK naming. Native test APK package/version/signer were independently inspected; private credentials remain ignored and are not distributed. Normal APK/settings restoration and protected-file hashes passed as recorded below. | None. No external release is authorized. |

## Completed live observation and restoration

The sole native verification process was PID 19140; terminal-code observer session
65017 was scoped to its exact `10-04 20:58:36.507` start marker. The held grant
returned HTTP 200 until Google's actual HTTP 401 at `21:48:58.810`. Native cache
clear entered at `21:48:58.813` and returned at `21:48:58.924`; noninteractive
authorization completed at `21:48:59.578`. Real root metadata succeeded at
`21:49:00.644`, followed by `PASS_elapsed_rejection_noninteractive_renewal_root`
at `21:49:00.645`. The proof requires the renewed token to differ from the held
token. The observer exited zero; no elapsed timer, revoke, cache invalidation
before rejection or user interaction was used to manufacture expiry.

The proof holds tokens only in memory and uses fixed sanitized diagnostic codes.
The authorization coordinator/driver/API and foundation identity code have no
changes since the inspected applicable checkpoints. The observation addition
is debug-only verification, not a production lifecycle workaround.

The native build passed through the shared Gradle gate with verified two workers,
no parallel execution, a 3 GB Gradle heap and Kotlin in-process. No test tasks ran;
configured test forks were one/512 MiB. No memory failure occurred. Scoped Dart
analysis and formatting passed for the current proof source.

Recovery passed: only SleepManager's Wi-Fi management toggle was restored to its
verified prior checked state; Bluetooth/Battery Saver remained checked. In-place
normal APK installation returned Success and the installed bytes matched SHA-256
`daa8b182c8f722f4e3dc75685ee346b8919bfefb1159c62af6cfce3ebdd7ffee`.
All seven protected database/preferences/config hashes matched the pre-test
baseline. Both task-owned UI snapshots were removed and both actual display
controllers were verified OFF. The reviewed cleanup transaction
`0cc1d229a278ebeb26fb578415f13869` is applied: two expendable proof APK copies,
266,756,648 bytes, no errors; four pre-existing entries protected. Deleted proof
outputs are reproducible, not recycle-bin recoverable. The normal recovery APK
and diagnostic evidence remain retained.

Every S1 acceptance criterion is satisfied by the applicable inspected evidence
or the expressly authorized live-second-account scope change. No S1 blocker or
tracked deferral remains. S4 still requires its own reconciliation and S6-S9 are
NOT STARTED; S1 closure does not claim overall feature completion.
