# S4 native resource verification

Authority: [SPECIFICATION.md](SPECIFICATION.md), META-06/META-07 and QA-01.
Execution remains S4; this does not open S5 or approve any real ranking source.

`integration_test/metadata_resource_test.dart` runs the existing shared resource
assertions against Android's actual SQLite plugin, private filesystem and Flutter
image decoder. It rejects non-Android, non-debug and non-isolated package IDs
before creating fixtures. It does not bootstrap production sources, contact an
account/provider, enumerate the user's collection or read SD ROMs.

The tests run sequentially:

1. Seed 30,000 synthetic collection identities with attributed overall scores;
   build the production compact query projection; verify bounded reads, index
   use, stable page ranks and rank-before-genre intersection without backfill.
   The assessment is explicitly synthetic, not approval of IGDB or ScreenScraper.
2. Snapshot 30,000 distinct edition-owned image selectors; run the real persistent
   artwork worker with one synthetic transport, including a real 4,002,288-byte
   PNG and native decoding; verify complete outcomes, bounded chunks and two
   content-addressed blobs. Close/reopen SQLite and close the transport before
   offline lookup and completed-job replay; neither may issue another request.

Both return measurements through the integration driver's `reportData`: RSS,
durations, row/chunk bounds and request results. Measurements are diagnostics,
not completion deadlines. Each fixture closes its database before deleting only
its validated, newly created private temporary child. The normal application
database, preferences, credentials, saved artwork and forensic fixture are not
targets. Host wrappers call these same assertions with the FFI factory; focused
256-artwork/3,000-query checks validate fixture extraction without repeating the
full unchanged host stress run.

## Device handoff

The user requested a pause and question before Thor testing. Obtain that handoff
before any device installation, launch or wake. Follow the signer/package and
non-uninstalling installation/driver-attachment procedure in
[DEVELOPMENT_SETUP.md](DEVELOPMENT_SETUP.md). Build with the explicit target
`integration_test/metadata_resource_test.dart`, not `lib/main.dart`; inspect that
exact APK before installation. Do not uninstall or clear an existing debug app's
data. Restore the normal debug APK without uninstalling after the run and switch
both displays off. Preserve diagnostics on failure; do not start a second test
while the first remains live.

This harness being written or passing host checks is not native acceptance.
Native results must be inspected before META-06/META-07 device resource evidence
can be marked verified. A successful repeat also does not explain or fix the
earlier host artwork stall. Its original private forensic fixture remains kept.

## Inspected native result — 2026-10-03

The owner authorized the connected Thor run. The APK/signature was inspected,
installed without uninstalling, and the existing driver attached to its observed
VM service. Both full-size checks passed (terminal exit 0). The query retained
128-row read bounds and no filter backfill; artwork completed, closed/reopened
SQLite and replayed offline with no extra request. See the current checkpoint in
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for measured results and
artifact identity. The exact prior normal APK was restored; normal database and
credential/preferences fingerprints were unchanged. Both displays were confirmed
OFF. This verifies the resource harness, not the unresolved META-05 source gate
or the complete user-facing metadata integration.
