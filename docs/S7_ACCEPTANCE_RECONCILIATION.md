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
