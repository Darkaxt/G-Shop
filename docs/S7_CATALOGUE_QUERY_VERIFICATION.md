# S7 mapped-folder query verification — 2026-10-08

Authority: DRIVE-02 and QA-01/02 in SPECIFICATION.md. S7 remains ACTIVE;
this closes the bounded query correction, not full startup or migration.

The previous recursive CTE put every ROM leaf on its expansion queue, although
only folders can have children. The regression executes the production CTE
over eight nested folders and 2,048 ROM leaves. It reproduced 2,057 expansions;
the correction performs nine folder expansions while returning the same ordered,
bounded child page. Both folder and binary entries remain visible. Scope,
published generation, parent membership and page offsets are unchanged.

Focused catalogue/provider checks cover the real SQLite query plan, membership,
snapshot replacement, indexed parent/exact lookups and excluded-resource scopes.
The work budget is an actual expansion count, not an arbitrary deadline.

Build-gate ticket 431 completed debug assembly with verified completion. The
observed profile was two workers/no parallel projects/3 GiB Gradle, assessed
Kotlin in-process, one configured 512 MiB test fork (not executed by assembly)
and depth-one native pools. No memory failure or budget increase occurred.
The final result's gate-acquisition field was truncated; its exact value was
not independently recovered, so no separate field-verification claim is made.
The signer-preserving installed APK matched the built artifact; immediately
pre/post installation configuration and protected storage matched.

After normal joined Pause, a fixed read-only diagnostic executed the revised
production SQL on the Thor's Android SQLite, with the same 500-row page bound:

| Console subtree | Returned rows | Payload bytes | Observed query time |
| --- | ---: | ---: | ---: |
| Nintendo DS | 500 | 290,102 | 43 ms |
| NES | 500 | 273,980 | 141 ms |
| SG-1000/SC-3000 | 500 | 260,534 | 10 ms |

The actual plans use exact scope/generation/file-ID lookups for the anchor and
returned payloads, and the parent index for folder expansion and child pages.
Only bounded CTE/page results are scanned; there is no whole-generation entry
scan in these plans. Published generation 1 and pending generation 2 were
unchanged before/after; these are per-query observations, not a transactional
snapshot of the whole catalogue or current cloud verification. The diagnostic
read no ROM bodies and made no database/configuration/cloud writes.

Normal Resume retains the same saved metadata job and its captured membership.
All 49 protected save/state/emulator-configuration hashes and the original
SG-1000 ROM digest match after verification. Cold startup still took several
minutes across other initialization work; these query measurements do not prove
total-startup latency fixed. Full fresh coverage, defensible Top-25 retention,
remaining format/current-cloud checks and reviewed migration remain S7 work.
