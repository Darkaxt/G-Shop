# S7 DSi metadata platform boundary — 2026-10-08

Authority: META-02/META-03 and MIGRATE-01. S7 remains ACTIVE. This closes
provider-alias verification, not DSi collection coverage or migration.

## Verified mapping

An authenticated, bounded read of ScreenScraper API v2 `systemesListe.php`
returned HTTP 200, 4,188,451 bytes and 250 platform records. Platform 15's
`noms_commun` explicitly includes `Nintendo DSi,NDSi,DSi` alongside Nintendo DS.
There is no need to infer an alias from a parent folder or similar platform.
The API contract is documented at
[ScreenScraper API v2](https://www.screenscraper.fr/webapi2.php).
No response body, credentials or account identifiers are committed.

R-Shop now sends `dsi` metadata requests to provider platform 15 while preserving
the request, game, edition and published record's separate DSi identities.
It does not merge DS/DSi libraries, classify unknown editions or approve restore,
ranking, ownership or removal. Existing platform and evidence checks still apply.

## Verification

- The regression first returned `unsupportedPlatform` for a DSi request.
  The affected provider checks now pass: verified-ID lookup retains `dsi`,
  provider platform 17 is rejected, and unknown title-only editions stay
  reviewable without publishing metadata or official-ROM evidence.
- Two explicit live DSi title lookups through the actual adapter each returned
  one exact-title candidate under `dsi`, `needsReview`, no record and no official
  classification. The existing Thor worker was normally paused during these
  requests; credentials stayed in the ignored local configuration. Only metadata
  was requested, not ROM or artwork bodies.
- Scoped analysis and `git diff --check` pass. No full suite was necessary.
- Shared-gate request 432 (`90a4bf495f3a48a584e4a732aca0f1b0`) completed exit 0
  with `gate_acquired=true` and verified completion. Observed workers=2,
  parallel=false, Gradle maximum heap=3 GiB. Kotlin uses the previously assessed
  in-process strategy and shares that heap. One 512 MiB JVM test fork was
  configured; assembly did not execute JVM tests. All 281 current compile/link
  edges in 11 app/SoLoud/JNI ABI files use depth-one native pools. No memory
  failure or budget increase occurred. Private build log:
  `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/e1b5820f0c134264aa97fc82a0b491d0.log`.
- Actual installed APK SHA-256:
  `605a82c4de8d7f911f8a9b0162b5dc96165c7325602239fa01e77c68fd1390f9`.
  Its verified v2 signer is unchanged:
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Immediate pre/post update configuration and both encrypted-storage hashes
  match. All 49 protected save/configuration baselines also match.
- Normal Pause retained saved job 76 at 13,381 lookups / 30,458 pending / 412
  rated. The replacement process resumed without an account chooser and advanced
  that same job to 13,437 / 30,401 pending / 414 rated. These are a current
  observational checkpoint, not a completed pass or reliable ranking claim.

## Still required in S7

DSi is not yet configured in the Thor's normal collection mappings. Establish
its exact observed cloud folder and existing local DSiWare boundary through
normal configuration, preserving the other mappings. Complete a scoped fresh
DSi pass after the existing provider job reaches its normal boundary; never
rewrite or expand job 76's captured membership. Provider support does not prove
the observed 7z-to-DSi restore route. Existing `.dsi` files remain preserved.
Current root catalogue generation 1 / pending generation 2 is not proof that a
refresh worker is alive or that publication finished. Finish normal refresh and
current-cloud comparisons separately. Full coverage, defensible Top-25 sets,
remaining format recovery and reviewed migration still prevent stage closure.
S8-S11 remain NOT STARTED. No ROMs were adopted or removed and no release occurred.
