# S7 live metadata and Thor migration

Authority: `SPECIFICATION.md` revision 6, MIGRATE-01. Status: **ACTIVE**, the
sole ACTIVE stage. S6 is COMPLETE at `ea63586`; S8/S9 are NOT STARTED.

## Required acceptance

| Boundary | Current evidence | Remaining work |
| --- | --- | --- |
| Real collection membership and fresh metadata | Three rooted cloud mappings now publish 585 entries (GameCube, Game Gear and PSP), not the complete SD collection. The fresh provider traversals cover only the earlier 316-entry two-console generation. Initial read-only SD census confirms additional occupied consoles and multi-file MSU content. | Reconcile explicit cloud/console mappings and eligible game membership; run the stable-generation fresh pass, including explicit unmatched/ambiguous/failed/rated coverage. |
| Defensible Top-25 retention per console | S4 validated the score contract; S6's one real ScreenScraper score remains advisory. No full-library ranking proof exists. | Gather accepted current scores, audit canonical game/disc/bundle groups, preserve unresolved consoles/games until ranking is defensible. |
| Identical cloud recovery and exact paths | S6 proves one normal SD on-demand restore/remove/re-download and offline Dolphin path. Existing SD files are not thereby owned by R-Shop. | Inventory private exact paths, file identities, cloud IDs/version/digests; prove applicable restore routes; build/review the strict one-time manifest and interruption-safe journal. |
| Preserve saves/BIOS/settings/unknown content and prevent refill | No existing SD paths have been removed or adopted. Current LoLSuite device manifests exist and must be reconciled, not treated as removal authority. | Establish save/config baselines and on-demand sync coordination without changing H: archival profiles; revalidate each eligible removal. |
| Actual migration outcome and final reconciliation | No bulk scrape or SD migration is claimed complete. | Execute only eligible reviewed removals, verify retained sets/free space/save safety and restore a removed test game through R-Shop, return it to its planned state, then reconcile/commit. |

Private file inventories, accounts, cloud IDs and migration manifests must stay
out of Git. Expendable task outputs use D:; durable migration state must survive
process interruption and remain available until recovery and closure are verified.
No blocker or tracked deferral is identified at stage entry; the remaining items
above are ordinary unfinished work, not grounds to open S8.

## Live execution — 2026-10-05

- The reported logo hang was not reproduced. The current normal APK cold-started
  in 1992 ms, displayed its All Games home tile, and opened the actual 316-entry
  Library with controller A. No app data or credentials were cleared.
- Normal settings completed ScreenScraper job 7 on a stable snapshot of all 316
  currently mapped entries: 316 requested, one matched/rated, 220 needing review,
  60 ambiguous, 35 unmatched, zero failed/unsupported or pending. Its follow-on
  artwork job 8 completed both images. Mappings stayed unchanged during the pass.
- Normal settings then completed IGDB job 11 on that same 316-entry scope:
  316 requested, one matched/rated, 237 needing review, 64 ambiguous, 14 unmatched,
  zero failed/unsupported or pending. Both traversals are real authenticated
  provider work, not whole-SD coverage or a defensible retention ranking.
- Explicit normal review accepted one exact Game Gear identity/classification.
  ScreenScraper job 9 rechecked it successfully and artwork job 10 completed two
  images. IGDB job 12 independently rechecked the offered Game Gear identity;
  its fresh overall score has only six votes. A sparse score is not promoted
  into a trusted consensus claim. Other unresolved candidates remain review/
  ambiguous/unmatched, not published scores. No ROM was downloaded by these jobs.
- An attempted host copy of the database while it was being written was not a
  consistent snapshot and could not be queried. No repair, restart or duplicate
  job was attempted. Subsequent reads showed the same job advancing; the idle
  completed database passed SQLite quick_check. Failed UI idle observation also
  did not restart a job or supply stale coordinates for a later action.
- Read-only SD census distinguishes game artifacts from metadata and bundle
  members: Game Gear has 366 ZIPs; GameCube has 80 RVZs (nine in Translations);
  PS1 has 86 CHDs; PSP has 169 CHDs including 94 in T-En and five Minis; PS2 has
  23 CHDs. SNES includes 559 7z files plus 220 SFC/MSU pairs and 7477 PCM tracks.
  These are raw file counts, not canonical-game or retention counts.
- Game Gear's mapped host Drive folder contains 182 ZIPs. All 182 have exact
  namesakes on SD: 180 match SHA-256 (35,066,195 bytes), two do not. Another 184
  SD ZIP names have no counterpart in that mapped host root. This is an inspected
  host-filesystem/SD comparison, not live Drive ID/version/digest revalidation or
  cloud-restore proof. Neither filename equality nor this partial audit grants
  removal authority. Differing and missing copies stay protected.
- Added a PSP-only source using the existing native Google account and read-only
  folder picker. Its single normal refresh completed and published generation 1:
  2708 observed entries, including 364 folders, with no pending generation or
  remaining work. This traversed metadata only, not ROM bodies. The normal
  mapping editor saved only the PSP root assignment; the two existing sources,
  systems, mappings and targets remained unchanged by object comparison.
- The normal library sync now exposes 585 artifacts: GameCube 134, Game Gear
  182, PSP 269. PSP includes 260 CHDs, two PBPs, two 7z and five ZIP files; these
  are artifact counts, not reviewed canonical-game membership or fresh PSP
  metadata coverage. Patch/tool archives require membership review before a
  retention claim. PSP's newly created target remains the normal internal
  default; an SD restore destination must be explicitly established and verified
  before migration. No installation, adoption or removal was triggered.
- With all metadata jobs and the single transfer completed, a second normal cold
  launch took 1919 ms. Controller Left selected All Games and A opened the real
  585-entry Library with one installed item. The complete current configuration
  remained identical across that cold launch. This is current startup/navigation
  evidence, not a reproduction or root-cause fix for the earlier reported hang.
- Both physical Thor displays were verified OFF after this device session. Only
  the task-owned UI dump was removed; no ROMs or persistent app data were cleared.
  No Gradle build or test workload was launched in this session, so no new gate
  acquisition or effective build-profile verification is claimed.
- No cleanup/adoption of user ROMs, H:/Drive original mutation, external sync
  policy change or public release has occurred. Full metadata coverage, candidate
  review, trusted Top-25 retention and the strict migration manifest/journal
  remain required work in this ACTIVE stage.

## Subsequent S7 execution — 2026-10-05

- Normal per-console ScreenScraper job 13 completed the PSP-only 269-artifact
  generation: 269 requested, 144 needing review, 35 ambiguous, 90 unmatched,
  zero matched/rated, failed/unsupported or pending. Its follow-on artwork job
  14 completed with zero requests. No duplicate metadata worker was launched;
  the confirmed live owner and the same job were observed through completion.
- Created the bounded read-only audit command in `scripts/`. The focused
  contracts exercised changed files, duplicate candidates, missing identity/
  version/digest, path boundaries and cached-match non-authorization. The first
  live read exposed an extra adb exec-out quoting layer; it was reproduced,
  corrected and verified before journaling. No source/app state was repaired.
- Its private exclusive-create Game Gear journal contains 369 exact SD file
  observations: 180 cached Drive size/MD5 matches (35,066,195 bytes), two size
  mismatches (330,866 bytes), 184 ZIPs without cloud candidates (32,458,894 bytes),
  and three preserved non-ROM files. Every disposition is preserve and every
  removal authorization is false. An independent streaming reader reconciled
  the terminal summary against all records. The updated bounded adb reader also
  passed a live stable-file/checksum comparison without any ROM body transfer.
  This journal is a required private review artifact outside Git, not evidence
  of live cloud revalidation, ranking, restoration or migration completion.
- Found the next internal classification gap: all 269 PSP lookup requests had
  empty content tags, including the 96 artifacts under the explicit T-En source
  bucket (94 CHDs and two archives). `LibraryStore.catalogueEditions` creates
  editions without carrying catalogue classification evidence. S7 must resolve
  this provenance gap while preserving manual corrections and uncertain
  classifications; it must not infer translation from official English or
  promote a guessed provider match. This remains ordinary current-stage work,
  not an external blocker or a deferral to S8.
- Final idle app database quick_check passed; all metadata jobs and the single
  transfer were completed. Both physical displays were verified OFF and the
  exact expendable UI dump was removed. The private journal remains available
  for the required migration review. No Gradle command, SD removal, app-data
  clearing or external publication occurred.

## Published source classification — 2026-10-05

- Reproduced the missing folder facts in a test before implementation. Catalogue
  capture now follows actual published Drive parent IDs in the exact source/account
  generation, rather than splitting a display path or guessing from filenames.
  Explicit Hack, T-Eng, Dub, Undub and Uncensor declarations can overlap. General
  Translations does not imply English. Ordinary English releases remain unknown.
  Generated facts have source-folder provenance; manual corrections and unchanged
  identity bindings are preserved. Moving an artifact changes only owned facts.
- Focused catalogue/query/identity/grouping/migration regression verification
  passed. The final opaque encoded scope regression and scoped Dart analysis also
  passed. No full-suite run or additional test worker was needed.
- The first normal native refresh failed before creating a job. Android's actual
  SQLite log established `no such function: json_extract`; host SQLite tests had
  not demonstrated that native extension. The query was replaced with exact
  bound JSON-tuple-prefix matching using core SQLite `substr` and `length`.
  Escaped quotes, Unicode and similar-but-different accounts have regression
  coverage. This failed native attempt is not recorded as a passing gate.
- The corrected normal APK installed in place with its existing package/signing
  identity. Cold startup reached Home in 2675 ms; controller navigation opened the
  real 585-artifact Library. The reported logo hang was not reproduced and no
  speculative startup patch was made. Existing configuration and secure credential
  fingerprints remained unchanged; no uninstall, clearing or secret re-entry was
  performed. Post-launch metadata/database and filter preferences changed normally;
  regenerable thumbnail cache differences are not claimed as exact preservation.
- A single normal PSP Fresh re-scrape created job 15 and captured all 269 requests.
  Native Library PSP scope plus T-Eng reported 96 matching artifacts, with zero
  trusted ranked games, and rendered real PSP translation entries. The unfiltered
  Library view was restored afterward. Folder evidence does not approve a provider
  match, classify patch archives as games, or authorize removal.
- The same native job 15 completed: 269 requested, 144 needing review, 35
  ambiguous, 90 unmatched, zero matched/rated, failed/unsupported or pending.
  Its follow-on artwork job 16 completed with zero requests. The idle database
  passed quick_check; all 96 T-Eng facts are present in the captured provider
  requests, with no active metadata or transfer worker. Configuration still
  matches its pre-update fingerprint. A live host copy made during writes was
  inconsistent and was discarded, not treated as production corruption or
  repaired; subsequent idle inspection is the applicable database evidence.
- After job completion, normal cold startup took 1975 ms and controller Left/A
  opened the unfiltered 585-artifact Library. No current-owner fatal, JSON1 or
  unhandled exception appeared in the inspected native log. Both physical
  displays were confirmed OFF. The exact task-owned UI XML was removed; the
  current normal APK and required diagnostic evidence are retained.
- Build tickets 146 and 147 acquired `Local\Darka.AndroidGradleBuildGate` and held
  it through exit zero. Observed settings: workers 2, parallel false, Gradle heap
  3 GiB; Kotlin 2.2.20 in-process shares that heap. Tests were configured for one
  fork/512 MiB but not executed by these builds; app native pool was one. Plugin
  native tasks were up-to-date, so fresh full-plugin concurrency is not claimed.
  No memory failure, budget increase or interruption of another build occurred.
  Corrected APK SHA-256:
  `0e002253682c049711713b231b89b611fbd42a70e564ce3b518eb7d35016c2f3`.
- S7 remains ACTIVE. Whole-SD mappings, reviewed eligible membership, defensible
  per-console retention and live cloud/restore verification remain unsatisfied.
  No ROM has been moved, deleted or adopted by this change.
