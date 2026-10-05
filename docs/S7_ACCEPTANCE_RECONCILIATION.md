# S7 live metadata and Thor migration

Authority: `SPECIFICATION.md` revision 6, MIGRATE-01. Status: **ACTIVE**, the
sole ACTIVE stage. S6 is COMPLETE at `ea63586`; S8/S9 are NOT STARTED.

## Required acceptance

| Boundary | Current evidence | Remaining work |
| --- | --- | --- |
| Real collection membership and fresh metadata | Four rooted cloud mappings expose 904 remote artifacts (GameCube, Game Gear, PSP and PS1), not the complete SD collection. Normal local scanning adds 524 local rows, giving 1,428 Library rows; these are not reviewed canonical games or managed installations. Both providers completed the earlier 316-entry two-console scope and the separate 269-artifact PSP scope, with unresolved outcomes retained. PS1 generation 1 published 5,162 observations/1,336 folders and its normal PS1-only mapping is saved; no PS1 scrape is yet claimed. Initial read-only SD census confirms additional occupied consoles and multi-file MSU content. | Reconcile explicit cloud/console mappings and eligible game membership; extend fresh coverage to the remaining stable-generation console scopes, including explicit unmatched/ambiguous/failed/rated coverage. |
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

## PSP review and private checksum reconciliation — 2026-10-05

- Normal PSP IGDB Fresh job 17 completed against the same 269-artifact scope:
  178 needing review, 43 ambiguous, 48 unmatched, zero matched/rated, failed,
  unsupported or pending. Native settings and the idle database agree; no
  duplicate provider worker was started. This is fresh PSP coverage, not
  whole-collection coverage or acceptance of the offered candidates.
- Two normal manual review/recheck workflows completed. LEGO Batman's actual
  PSP-specific port ID 259254 has no score; the shared-platform parent ID 2738's
  score was not borrowed. Job 18 matched that reviewed port and remained unrated.
  Ridge Racer's reviewed PSP ID 18787 rechecked in job 19, with a score backed by
  ten votes. It remains advisory, not Top-25 evidence. Both editions were
  explicitly classified as official through the normal review form. Other
  unresolved records remain unresolved; these decisions do not approve every
  archive, release or canonical group in the PSP collection.
- The normal Library search rendered Ridge Racer's sourced score, original
  scale, ten-vote count, retrieval date and advisory status. Search was cleared;
  the actual unfiltered Library still has 585 artifacts and one owned install.
  No ROM payload was fetched by metadata/review actions.
- The single read-only PSP audit process completed and exited zero. Its private
  exclusive-create journal observes 170 exact files: 169 stable CHDs match cached
  Drive size/MD5 evidence (129,899,079,437 bytes), and one 581-byte non-ROM file is
  preserved. An independent streaming reader reconciled every file against the
  terminal counts/bytes and required every disposition to be preserve with
  removalAuthorized=false. Journal SHA-256:
  `65dab876fbae375a79136f355871b3e84eae0656d6896afc6a024f7157e2d228`.
  Accounts, cloud IDs and exact file inventories remain outside Git. Cached
  matches are not live cloud revalidation, canonical review, retention or restore
  evidence; all remaining migration gates still apply.
- The subsequent logo-hang investigation observed the running Library, then
  verified a normal cold activity launch (2552 ms), the All Games home tile and
  controller navigation into the 585-artifact Library. No startup fatal error was
  captured. Database quick_check passed while idle and the saved source/config
  fingerprint matched its pre-investigation value. The historical intermittent
  hang was not reproduced; no speculative startup change or claim of fixing it
  was made. Both physical displays were verified OFF after the investigation.
- PSP and Game Gear's restore destinations were saved through the normal console
  settings and Android folder-grant workflow. Exact before/after configuration
  comparisons verified only their respective target fields changed. Other source,
  mapping and console options were preserved. Existing ROMs remain unmanaged;
  folder grants do not prove format recovery or authorize adoption/removal.
- PS1's additional source was saved through normal read-only native
  account/folder selection. Its first catalogue generation subsequently published
  successfully: 5,162 observed entries, including 1,336 folders. The completed
  observation has active generation 1, no pending generation or work rows, and
  zero native refresh/cancellation/transfer owners. Traversal alone is not game
  membership: the root includes patch/tool material. No PS1 mapping, scrape,
  recovery route or migration is claimed complete at this checkpoint.
  The existing three sources/targets are not replaced. An inconsistent host
  database copy during catalogue writes was rejected, not repaired or used to
  restart the operation. A read-only VM inspection later confirmed the refresh
  worker had exited before publication: zero refresh and cancellation owners,
  with generation 1 retaining 1,157 completed and 77 pending folder jobs. The
  previous error was not captured, so its cause is not inferred from checkpoint
  age. One normal explicit Refresh resumed that same checkpoint; a subsequent
  VM inspection confirmed exactly one refresh/cancellation owner and zero
  transfers. No new generation, process restart or hidden retry was introduced.
  After all 1,336 folder jobs completed, a runtime inspection confirmed its
  refresh future was still pending while folder-boundary revalidation ran; the
  unchanged database during that phase was not interpreted as a stalled job.
  The same monitoring process exited zero only after verified publication. The
  native operation completed normally with both physical displays OFF. Mapping,
  fresh PS1 scraping and the remaining migration gates are ordinary unfinished
  S7 work, not a blocker or permission to begin S8.

## Reproduced mapper ANR and verified correction — 2026-10-05

- Opening the published PS1 source exposed long-label RenderFlex overflows;
  scrolling reproduced Android's actual owner-app ANR at 17:42:17 local time,
  waiting 5003 ms for a MotionEvent. The old mapper built every one of the 1,336
  folder options into a dropdown for every supported console, including hidden
  dropdown layout. The old process snapshot measured 1,517,645 KiB total PSS.
  The system-only ANR trace was not read, and this does not establish the cause
  of the separate historical logo report.
- A focused long-folder-name regression failed against the old implementation.
  The replacement retains the existing mapping/save rules and R-Shop styling:
  closed rows render only their selected label; one opened searchable selector
  lazily builds visible options. The final fixture uses 1,336 folders and verifies
  bounded rendered options, long labels, selection, clearing and cancellation.
  Unobserved persisted mappings and ambiguous aliases retain their existing rules.
- Actual native input found two remaining integration defects before closure.
  Controller A opened the dialog but B did not dismiss it; a reproducible failing
  test preceded the dialog-local B-to-DismissIntent binding. Hardware text input
  lost the letter I to the application's Library-search shortcut; a failing
  shortcut regression preceded a text-field-local pass-through binding. Neither
  change modifies application-wide input or unrelated screens. Final focused
  widget checks and scoped analysis of the two changed Dart files exited zero.
- The final native workflow opened the same published source, scrolled normally,
  entered the complete `Sony - PlayStation` search text and showed the exact root
  choice. A opened and B cancelled the selector, including from focused search,
  with the saved configuration unchanged. Before/after native captures were
  visually compared: the corrected Atari rows have no overflow stripes. The
  final process snapshot measured 521,020 KiB total PSS; last-ANR evidence still
  referred to the old 17:42:17 incident. These are snapshots, not a peak-memory
  guarantee or proof that every intermittent freeze has been resolved.
- The normal save added only PS1's root mapping. Its unrelated PSP suggestion
  was explicitly cleared before saving. Object comparison verified all existing
  sources and three existing console configurations unchanged. The PS1 SD folder
  grant then changed only the new console's target field. Existing source
  suggestion rules were not broadened or silently treated as membership review.
- Normal cached library synchronization exposes 904 remote artifacts: GameCube
  134, Game Gear 182, PSP 269 and PS1 319. Local scanning adds 524 rows (Game Gear
  366, PSP 72, PS1 86), and the actual Library opens with 1,428 rows/459 installed
  labels. The ownership journal still has exactly one owned installation. Local
  discovery is not adoption, canonical identity, a trusted ranking or removal
  authority; patch/tool material and potential edition duplicates remain subject
  to the outstanding S7 membership review. No PS1 fresh scrape is claimed.
- Builds 148, 149 and 151 ran sequentially through the shared named mutex.
  Final ticket 151 explicitly reported gate_acquired=true, exit zero and a
  verified observed profile: workers 2, parallel false, Gradle heap 3 GiB, with
  other JVM arguments preserved. Assessed Kotlin 2.2.20 is configured in-process
  sharing that heap; its compile tasks were up-to-date. Configured test forks
  were one/512 MiB, not executed by assembly; native compile tasks were also
  up-to-date, so fresh plugin/native concurrency is not claimed. The helper
  retired only a confirmed-idle incompatible daemon, not an active build. No
  memory failure, budget increase or external release occurred.
- Independent final APK/package/activity/signature inspection passed. The normal
  existing debug package was updated in place, without uninstall or data clearing.
  All 29 private files inspected immediately before that final update retained
  their hashes before first launch; the separately read configuration also
  matched exactly. Final APK SHA-256:
  `4f649c851153ab557f6ec5710f7a5eb3e993a90014037be581249ee628a77ce6`.
  Cold startup reached Home in 2635 ms; controller navigation subsequently opened
  the real Library. This verifies the current launch and reproduced mapper fix,
  not the historical logo hang's root cause.
- A fresh stable database observation passed quick_check and device-before/
  device-after/host digest agreement. All four configured source snapshots were
  published with no pending work; all metadata and transfer jobs were completed.
  An older unconfigured catalogue checkpoint was preserved, not mistaken for a
  live worker or restarted. Both physical displays were verified committed OFF.
- Transactional cleanup reviewed and removed exactly the two expendable
  comparison captures (193,978 bytes), with no residual ticket members. The
  exact task-owned device screenshot/XML were also removed and absence verified.
  Required diagnostic records, private migration journals and the current normal
  APK remain; no user files or shared metadata were cleaned.
- S7 remains the sole ACTIVE stage. Its whole-collection metadata, eligible
  canonical membership, defensible Top-25 retention and live cloud/recovery/
  migration criteria are still unfinished. No existing ROM was adopted, moved
  or removed; S8/S9 remain NOT STARTED.
