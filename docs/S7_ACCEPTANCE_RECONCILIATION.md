# S7 live metadata and Thor migration

Authority: `SPECIFICATION.md` revision 8, MIGRATE-01 and the UI-02 scraping-feedback
extension. Status: **ACTIVE**, the
sole ACTIVE stage. S6 is COMPLETE at `ea63586`; S8/S9/S10 are NOT STARTED.
S10 owns the newly authorized R-Shop save-backup feature. FolderSync remains
installed with its existing folder pairs and schedules unchanged; neither
integration with it nor SD-card mirroring is part of S7 or S10.

## Required acceptance

Standardized retention checkpoint (2026-10-06): the browsing Top predicate is
not a complete physical keep list because it requires each displayed edition's
own eligible rating. `LibraryQuery.retentionPage` instead includes all current
members of each canonical group using the same assessed-score rank CTE, within
one explicit console and a 128-row maximum page. Unscored peers have canonical
membership, not borrowed ratings. Coverage counts survive empty page offsets;
missing bindings, conflicting scores or incomplete coverage cannot label
unresolved games as a bottom-ranked removal set. Even `outsideSample` grants no
ownership/removal authority: the remaining MIGRATE-01 gates still apply.

Focused query, migration and invalidation fixtures passed, including removed
membership, pending score updates, stable ties, unscored peers, conflicting
bindings and incomplete reception. Dart analysis reported no issues. The fixed
READONLY native observer's SQL is tested for exact equality with production SQL;
its host fixture checks precedence, coverage and empty pages. After the normal
Library refreshed all pending projections, Thor's six console observations had
zero dirty rows and zero unbound artifacts. Ranked/collection counts were PS1
0/405, PSP 6/341, PS2 12/220 (225 physical members), N64 0/1,543, GameCube 0/206
and Game Gear 0/548. These are current cached projections, not complete-library
rankings or current cloud/restore proof. No member was removed.

The native helper jar's host/device SHA-256 agrees:
dd03aa299d79e12661a986ddcc05f81b146e500cd5deb077627b917f09b3475a.
It opens only the fixed app database READONLY, returns at most 128 members and
1 MiB, and reports dirty projections explicitly. It never refreshes metadata.
The actual Dart API refreshes and queries transactionally; no updated APK was
installed in this checkpoint, so that device execution is not claimed. javac/d8
used requested 256 MiB budgets; no Gradle invocation or memory failure occurred.
The earlier native read failed with SQLiteDatabaseLockedException during the
normal app refresh; it succeeded after that same operation completed naturally.
No kill, restart, timeout or automatic retry was added.

Verification commands were the focused Flutter invocation with concurrency 1
for `library_query_test.dart`, `library_query_migration_test.dart` and
`library_query_invalidation_migration_test.dart`, Dart analysis of the changed
query/test, and `python -B -m unittest test_thor_migration_audit`. All exited zero;
the repository-wide suite was not required or run. Transactional cleanup removed
only the reviewed host helper class/jar and their empty folder (11,502 bytes).
Those compiler outputs are reproducible from source; the verified device jar
and required private inventories remain retained.

Root generation 1 remains unpublished: 124,117 observations / 14,130 pending
folders / 25,528 work rows, next generation 2. The same app PID 13676 remains
live. Both physical displays are OFF. This checkpoint is collection-wide,
without manual title curation; S7 remains ACTIVE on its original required
coverage, identity, defensible ranking, recovery and reviewed migration gates.

Native cached-comparison verification (2026-10-06): the audit no longer copies
the growing live database. A fixed READONLY on-device query projects platform
artifacts and catalogue generations in one SQLite statement; configuration is
checked before/after. Row/input/output guards reject oversize or malformed
results, never silently truncate. The 1 MiB projection/transport cap remains
bounded. Thor lacks SQLite JSON functions, so the query uses portable plain-SQL
aggregation of stored serialized records, then strict host validation. All six
mapped consoles passed: PSP 269 artifacts / 172,513 bytes, PS1 319 / 191,024,
PS2 202 / 129,135, N64 1,391 / 838,891, GameCube 134 / 82,064 and Game Gear
182 / 108,651. N64's measured 836,435 artifact bytes justified a 900,000-byte
input bound within the same 1 MiB result cap (initial input guard was 512 KiB).
Focused host checks exercise the shipped SQL, framing, provider-scope validation,
config changes and all original preservation gates. No full suite or Gradle
build was needed for this helper; javac/d8 were invoked with 256 MiB budgets.

The real N64 comparison exited zero and every private journal row independently
reconciles with its terminal summary: 320 stable .7z archives have matching
cached size/MD5 (3,267,752,208 bytes); two non-ROM files (1,124 bytes) are preserved.
The exclusive journal is D:\Temp\rshop-s7-n64-native-cache-audit-v2-20261006.jsonl.
The first invocation incorrectly selected .zip for this .7z directory and
therefore proved only preservation, not ROM comparison; that expendable journal
is excluded from acceptance. The corrected invocation uses the independently
observed extension. This remains cached comparison evidence, not live cloud
version/readability, retention, ownership, tested recovery or removal authority.
The verified helper jar remains on-device for remaining S7 observations; its
SHA-256 is f94d5f9f4ea3e32a85cde37363b146b757901e38b50ad0658b04a11457ac46b5.
Transactional exact-file cleanup removed only its expendable host class/jar
outputs (5,687 bytes) and the superseded wrong-extension journal (401,360 bytes).
The corrected private journal, all prior valid inventories and device helper
are retained. No user/app data was deleted; compiler outputs are reproducible
from the committed source, and the obsolete journal was intentionally discarded.

After the same saved-job resume, PSP job 44 completed all 341 edition items with
zero pending; its normal linked artwork job 49 also completed, with zero pending.
No replacement metadata job or per-title correction was created. Root generation
1 remains unpublished at 92,021 observations / 14,445 pending folders, next
generation 2. Both displays remain OFF. S7 is the sole ACTIVE stage: full
collection coverage, defensible retention, current identical cloud-recovery
proof and reviewed migration remain unfinished.

Saved-job recovery verified (2026-10-06): the normal settings now expose a
bounded, indexed, keyset-paged local history for the selected metadata provider.
A newer console pass no longer hides an older paused pass. Selection reads its
existing report and linked artwork only; explicit Resume owns provider requests.
Focused host checks verify provider/artwork isolation, unchanged generation and
job count, pending-only resume, paging and touch/controller selection. Scoped
Dart analysis and native debug assembly pass. On Thor, Saved jobs selected PSP
job 44 behind completed PS2 job 46 with no new job or generation. Resume advanced
the same generation 44 from 57 pending / 284 processed to 50 pending / 291
processed. The first attempt paused after one item; the source UI reported Drive
interactionRequired. Normal default-account Connect restored access, and Resume
continued saved progress without replaying completed items. No raw exception was
persisted, so the first pause is not independently attributed beyond that
observed authorization state. Full PSP completion remains outstanding.

Normal build 180 was installed in place with the existing signer and an
independently matching installed APK SHA-256
957fbddd0204c9fb453091b3fbc07c27aa3a1ee890a3d248620e559cff590698.
The source/mapping configuration and secure-storage file hashes remain unchanged.
The shared Gradle-gate supervisor exited zero with an inspected effective
two-worker / no-parallel / 3 GiB Gradle profile and assessed Kotlin in-process
strategy. Forked-test configuration was one JVM / 512 MiB (not run by assembly);
app native compile/link pools are depth one. No memory failure or budget increase
occurred. The acquisition receipt field was truncated from the tool response;
it was not independently retained, and no redundant build was launched for it.
After default-account reauthorization, ordinary Refresh catalogue resumed root
generation 1 (next generation 2) without a replacement source or checkpoint.
It reached 89,436 observations / 14,832 pending folders and remains unpublished.
Linked PS2 artwork job 47 is now completed. Both physical display states are
confirmed OFF. ROMs/saves, Drive originals and FolderSync remain unchanged.
This closes the older-job recovery defect, not S7's full collection/ranking,
recovery or migration acceptance, and is not a per-title workaround.

Whole-SD inventory verification (2026-10-06): the corrected native run joined
with exit zero. Its private journal header, every observation and completed
footer reconcile exactly: 15,964 unique stable files / 722,865,729,304 bytes;
15,053 extension-classified artifacts and 911 non-ROM files. These include bundle
audio tracks and are not canonical-game counts. Every file remains preserved,
with no calculated digest or cloud candidate and removalAuthorized=false.
The earlier unbounded `find -exec ... +` exceeded Android's argument limit;
explicit batches now enforce 64 paths / 16 KiB and exact ordered responses.
Focused host verification passes, including the long quoted/Unicode byte-bound
case and incomplete/out-of-root/link/changed-file contracts. The complete journal
is retained outside Git for later revalidation, not cloud-recovery authority.

Normal PS2 ScreenScraper job 46 completed 225 editions: 122 matched, 32 review,
4 ambiguous, 67 unmatched, 113 rated and no failed/unsupported/pending items.
Its header workflow persists 175 bindings. Normal IGDB job 48 also completed all
225 editions: 20 matched/rated, 127 review, 46 ambiguous, 32 unmatched and no
pending items. Eighteen publications use automatic official-release corroboration;
ten meet the existing vote-support floor. This is not a defensible full Top set.
The normal Resume saved job control restarted the existing linked artwork job
47 after its deliberate pause, without a replacement job or individual-title
corrections. Native controls show an active operation. Collection generation 1
reached 86,091 observations / 12,862 pending folders and remains unpublished.
Both displays were confirmed OFF. No ROM removal, FolderSync change, Gradle build
or later-stage implementation occurred; S7 remains the sole ACTIVE stage.

Breadth/inventory checkpoint (2026-10-06): normal PSP IGDB job 45 completed its
341 editions: 12 matched, 222 review, 57 ambiguous and 50 unmatched; 11 carry a
rating. Ten matches use the new automatic corroboration path, all with current
identity bindings and source fingerprints; six meet the existing vote floor.
These are not whole-collection ranking or deletion authority. The same collection
generation 1 resumed after native default-account reauthorization and advanced
to 78,195 observations / 7,538 pending folders without discarding its checkpoint.
Normal PS2 ScreenScraper job 46 is running; observation at 51 requests verifies
28 matches/current bindings/raw match methods and 40 header bindings, with 175
items pending. No per-game corrections were made in this checkpoint.

Read-only SD inventory was decoupled from the published cloud comparison: the
live catalogue is 156,856,320 bytes, larger than the comparison's 64 MiB cap.
`--inventory-only` reads neither database/config nor ROM bodies and makes no
cloud-recovery claim. Focused host regression verifies preserved files, unstable
files and non-ROMs with all removal gates retained. Real PSP inventory completed
170 files: 169 ROMs / 129,899,079,437 bytes and one non-ROM; PS1 completed 87 files:
86 ROMs / 30,900,237,652 bytes and one non-ROM; PS2 completed 24 files: 23 ROMs /
45,166,984,325 bytes and one non-ROM. All 281 file observations are stable, have
no calculated digest or cloud candidates, and remain preserved. Exact private
journals remain outside Git for subsequent revalidation. No ROM,
save, cloud original or FolderSync setting was changed. Full publication, fresh
coverage, defensible retention, cloud recovery and migration remain unfinished;
S7 is still the only ACTIVE stage.

Cross-provider checkpoint (2026-10-06): current hash-bound ScreenScraper official
release facts can uniquely corroborate an IGDB main game using exact normalized
title, platform, full regional date and developer/publisher roles. The source
fingerprint is checked again in the normal publication transaction. Missing,
conflicting, modified, manual-correction and potentially truncated-search cases
remain unresolved. Focused host regressions and scoped analysis pass; shared
cache reopen/projection recovery preserves evidence and the eligible Top query.
The first eight current PSP records reached the real IGDB API through the normal
worker: one matched, two review, five unmatched. The matched record has insufficient
vote support, so no ranked game was manufactured. Normal build 179 was then
installed in place with matching signer and independent installed APK hash;
configuration bytes are unchanged. Normal settings created PSP IGDB job 45.
Read-only evidence at 74 requests verifies three automatic corroborated records,
each with a current identity binding and source fingerprint; two meet the vote
floor. The job remains running with 268 pending; full breadth, final ranking and
migration are not yet verified. Both displays were switched OFF. The build gate
was acquired with observed two-worker/no-parallel/3 GiB settings, assessed Kotlin
in-process strategy and generated depth-one native compile/link pools in app and
plugins. No memory failure or budget increase occurred.

Normal automatic-CHD checkpoint (2026-10-06): the worker now reads a finite
140-byte DVD-CHD header through the existing exact Drive source/account/platform
mapping. Source boundaries are checked before and after the read, and artifact
and identity bindings are revalidated before the atomic SQLite commit. Normal
refresh/restart/shared-cache recovery reuse current evidence; replacement bytes
invalidate it. Manual and modified-release facts remain protected. Header hashes
are not ROM/cloud integrity proof. Focused regressions and scoped analysis pass.
Normal build 178 was installed in place with matching installed APK hash and
unchanged configuration bytes. Read-only native evidence from saved PSP job 44
observed 35 automatic header bindings, 31 current matched metadata bindings and
31 raw-identifier match methods, with 254 of its 341 items still pending. This
proves the real normal-app path on multiple entries, not whole-collection match
coverage, normal PS2 breadth or trusted rankings. The same unpublished collection
generation advanced to 74,498 observations; both displays are OFF. Build 178's
gate/profile and verification evidence are recorded in IMPLEMENTATION_STATUS.md.
No ROM removal, cloud mutation, FolderSync change or release occurred. S7 remains
ACTIVE; full publication, fresh metadata, canonical ranking, recovery and reviewed
migration criteria remain unsatisfied. Earlier checkpoints are historical and
their outstanding automatic-CHD wiring claim is superseded by this observation.

Automatic uncompressed-Drive checkpoint (2026-10-06): normal catalogue snapshots
now derive compatible, version-bound MD5/SHA-1/size only from mapped standalone
formats. The real ScreenScraper adapter can establish unknown official releases
only with exact nonzero cryptographic evidence, explicit notgame=false and all
five unmodified flags. Publication revalidates the current artifact and honors
manual unknown, patch/base and modification facts. Classification, release
assignments, metadata and item identity keys commit together. Host integration
proves canonical grouping/advisory query, shared-cache close/reopen/identity
recovery, rename stability and changed-byte retirement. Folder declarations and
stale manual-raw boundaries pass. Two fresh real-provider header lookups passed
without full ROM/artwork downloads. Focused worker/store/score regressions and
scoped analysis passed; the bounded 30,000-edition worker fixture observed about
238 MB peak RSS and joined normally. No full repository suite or Gradle build
ran. Native integration/automatic CHD extraction and the full metadata/ranking/
restore/migration acceptance below remain unfinished; S7 is still ACTIVE.

Shared-identification checkpoint (2026-10-06): the supported DVD CHD header
parser and live PSP/PS2 original-ISO lookup path are verified without decoding
ROMs or using container checksums. ScreenScraper's observed large-ISO size cap
is recorded distinctly; exact supplied hashes/platform/release and existing
ownership/reception/integrity gates remain enforced. Real SQLite worker tests
verify publication, canonical grouping and unranked advisory query behavior.
The four-sample real-provider lookup is host evidence, not native automatic
collection binding. That binding and broad match/ranking/migration acceptance
remain ordinary unfinished S7 work, with no later stage opened. The same native
collection generation was observed advancing to 69,114 entries / 10,283 folders
/ 5,027 pending folders, still unpublished; source settings remain unchanged.
Both displays are OFF. No ROM removal, cloud write, FolderSync change or build
was performed at this checkpoint.

Current 2026-10-06 update: normal native feedback has now demonstrated ambiguous,
matched and single-unverified-candidate cover outcomes and actual provider quota
with observation time. Ape Escape's reviewed identity populated description,
genre, developer/publisher, screenshots and sourced advisory rating in normal
details. Those observations close the candidate-feedback gap below, not broad
match coverage or migration. A shared regional cover-selection/correction fix
is host-verified and installed as normal build 176; its native input control was
observed, but final corrected artwork was not confirmed. At the user's direction,
individual-entry curation was stopped; remaining integration verification belongs
to the collection workflow. S7 stays ACTIVE, with all other statuses unchanged.

The following checkpoints are historical; the current update above supersedes
their outstanding candidate-feedback observation.

The 2026-10-06 latest-product/cover preview and ScreenScraper daily quota display
are integrated and host-verified, but their normal Thor verification is still
required. They remain ordinary unfinished acceptance work; S8-S10 stay NOT
STARTED. Normal N64 ScreenScraper
job 31 finished and its zero-item artwork job 32 is completed. A single fresh N64
IGDB job 33 was then started through normal settings. A root-context, fixed,
read-only native query confirmed it running at 443/1543 requested, 1100 pending,
281 needing review, 85 ambiguous and 77 unmatched, with no accepted ratings.
The collection scan also advanced to 60318 observations/6496 folders, with 5044
folders pending and no published generation. These are live progress observations,
not complete coverage or a defensible retention set. An app-UID probe was killed;
the same read-only query succeeded in root context without restarting either job.
The reason for that probe exit is not established and no application fix is
claimed. Both physical displays were confirmed OFF after observation.

Later fixed read-only observation confirmed IGDB job 33 COMPLETE on its existing
1,543-item snapshot: 953 needing review, 304 ambiguous, 286 unmatched, zero
pending or accepted ratings. Collection generation 1 remained unpublished and
advanced to 62,562 observations / 7,574 folders, with 5,043 pending folders.
No job was restarted. These final metadata counts supersede the earlier running
checkpoint, not the unresolved canonical membership/ranking criteria.

### UI-02 scraping-feedback recheck — 2026-10-06

Native continuation at source `8325a3f`: same-signer normal debug build 174 was
installed in place and its installed hash independently verified. A focused
catalogue recovery check passed first. Configuration bytes and completed N64
job 33 were preserved; pending collection generation 1 survived the update
without losing committed entries. Normal default-account connection and source
refresh resumed that same checkpoint; a later observation showed 65,300 entries,
8,563 folders and 5,030 pending folders. No generation restart was requested.

The normal exact-game metadata workflow demonstrated the latest PS1 title,
platform and ambiguous outcome with the disc fallback, without accepting a
rating. An explicit original-versus-sequel cached review and provider recheck
then demonstrated the matched parsed-cover path. Both renders were captured and
visually inspected privately. The real provider's 20,000 daily and 2,000
failed-request allowances, observation timestamp, and separately reserved local
budget (19,998 after artwork) were visible. Existing credentials were retained;
initial loading defaults were not credential loss. Both displays were confirmed
OFF. No ROM payload, SD removal, cloud mutation, FolderSync action, release or
new Gradle build was performed for this check. **Still required:** a real-provider
single-unverified-candidate cover/label observation, then the remaining S7 whole-
collection, canonical-ranking, recovery and migration acceptance. The host
candidate/cadence/isolation checks are not represented as native observations.

The following earlier checkpoint records host verification before that install:

- Normal settings now display the latest title/platform/outcome and bounded cover
  context. A fixed three-second UI clock coalesces intermediate previews; leaving
  the screen cancels only that clock, not the existing app-scoped worker.
  Candidate images remain explicitly unverified and transient. They cannot
  publish a metadata record, score, identity or permanent artwork-cache entry.
  One serial candidate image request respects the same reserved provider budget
  and declared cadence; the display clock never triggers provider requests.
  Accepted images use the existing current-owned cache and artwork path.
- The v34→v35 production upgrade adds only display quota evidence. A real SQLite
  migration fixture preserves saved jobs, identities, provider next-allowed time
  and exhausted budget. Missing counters are Unknown, old observations retain
  their full date/time, and local reserved budget remains distinguishable.
  Credential replacement clears display evidence without weakening enforcement.
- Fresh focused checks cover the normal controller/settings wiring, candidate
  selector sanitization, no extra game lookup, bounded/malformed images,
  cancellation joins, exhaustion/pending preservation, latest-only display,
  provider/job isolation, disposal and known/missing/old quota. Existing metadata,
  artwork and earlier migration checks passed. The intentionally changed progress
  golden was inspected and the normal comparison rerun passed; scoped analysis
  reports no issues. The unchanged bounded 30,000-edition worker fixture observed
  a 274,898,944-byte process RSS peak; this is measured host evidence, not a
  whole-host cap or native-device memory guarantee.
- Normal debug build 174 succeeded, gate actually acquired for ticket
  `ddcce4e77daf4e828b559928deddc869`, observed workers=2 / parallel=false /
  Gradle heap=3 GiB. Kotlin's assessed in-process configuration shares that heap.
  Required metaspace/code-cache flags remain. Test fork/heap markers are
  configuration evidence only; all-plugin native concurrency remains unverified.
  No memory failure or budget increase. Gate log:
  `093b10643d3f453a95f8c78f24b6ed4a.log`.
- APK SHA-256:
  `a318cf7b1a08d56ee8dae4a982003f165da35a993a2b69db9e7581979dc75515`;
  normal `com.darkaxt.rshop.debug` / `com.retro.rshop.MainActivity`, version
  1.7.0/code 12, existing signer
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
  Not installed over the still-running collection traversal. **Remaining:**
  verify this exact new feedback through the real provider and normal Thor UI
  at a safe job boundary; then continue whole-collection/ranking/recovery and
  migration work. No stage closure, SD deletion or external release is claimed.

| Boundary | Current evidence | Remaining work |
| --- | --- | --- |
| Real collection membership and fresh metadata | Five rooted cloud mappings expose 1,106 remote artifacts (GameCube, Game Gear, PSP, PS1 and PS2), not the complete SD collection. Normal local scanning adds 547 local rows, giving 1,653 Library rows; these are not reviewed canonical games or managed installations. Both providers completed the earlier 316-entry two-console scope and the separate 269-artifact PSP scope, with unresolved outcomes retained. PS1 generation 1 published 5,162 observations/1,336 folders and its normal PS1-only mapping is saved. ScreenScraper job 20 completed 405 PS1 rows (319 remote plus 86 local): 214 need review, 136 ambiguous, 55 unmatched, zero accepted/rated. Artwork job 21 completed with zero items. IGDB job 22 completed the same 405-row scope: 233 need review, 135 ambiguous, 37 unmatched. Two exact native reviews/rechecks subsequently accepted fresh independently supported community ratings; this is not complete canonical membership. PS2 generation 1 is published and its normal mapping/SD target saved; ScreenScraper job 25 and IGDB job 27 completed the 225-row scope after hotel access was restored (all outcomes unresolved); an exact normal PS2 review/recheck subsequently accepted one fresh independently supported community rating, which survives native Home sync after the unchanged-evidence fix. Initial read-only SD census confirms additional occupied consoles and multi-file MSU content. | Reconcile explicit cloud/console mappings and eligible game membership; extend fresh coverage to the remaining stable-generation console scopes, including explicit unmatched/ambiguous/failed/rated coverage. |
| Defensible Top-25 retention per console | S4 validated the score contract; S6's one real ScreenScraper score remains advisory. No full-library ranking proof exists. | Gather accepted current scores, audit canonical game/disc/bundle groups, preserve unresolved consoles/games until ranking is defensible. |
| Identical cloud recovery and exact paths | S6 proves one normal SD on-demand restore/remove/re-download and offline Dolphin path. Existing SD files are not thereby owned by R-Shop. | Inventory private exact paths, file identities, cloud IDs/version/digests; prove applicable restore routes; build/review the strict one-time manifest and interruption-safe journal. |
| Preserve saves/BIOS/settings/unknown content and prevent refill | No existing SD paths have been removed or adopted. Current LoLSuite device manifests exist and must be reconciled, not treated as removal authority. | Establish save/config baselines and on-demand sync coordination without changing H: archival profiles; revalidate each eligible removal. |
| Actual migration outcome and final reconciliation | No bulk scrape or SD migration is claimed complete. | Execute only eligible reviewed removals, verify retained sets/free space/save safety and restore a removed test game through R-Shop, return it to its planned state, then reconcile/commit. |

Private file inventories, accounts, cloud IDs and migration manifests must stay
out of Git. Expendable task outputs use D:; durable migration state must survive
process interruption and remain available until recovery and closure are verified.
No blocker or tracked deferral is identified at stage entry; the remaining items
above are ordinary unfinished work, not grounds to open S8.

### Latest scope checkpoint — 2026-10-05

The membership row above retains the earlier five-console traversal history.
Current published/mapped scope is six consoles, with 2,497 remote artifacts and
771 additional local rows (3,268 total). N64's fresh pass is still running. The
earlier two-console GameCube pass does not cover its newly included local rows.
All other acceptance rows remain unresolved as stated; cached digest matches do
not authorize migration or replace live restore/version verification.

The seventh, collection-rooted source has now been saved through normal native
setup. Its first catalogue generation is still unpublished and it has no console
mappings. All six existing sources and all console settings remain unchanged.
It has not extended Library membership or established whole-collection coverage.

The normal console-settings Export action produced `r_shop_config.json` and
opened Android's share chooser. The chooser was cancelled without selecting a
destination. The generated JSON was read and independently compared with the
current configuration: all seven sources and all six system/mapping/target
objects are identical; no authentication fields are present. A private reusable
snapshot is retained outside Git (SHA-256
`4839d43a5fcf1c3a5b3d7291c245bdf8787941ac868435ae84fe7daf9bb6344c`).
This verifies normal native export, not native import into the release package.
The final handoff must refresh the snapshot after setup is finished and verify
its import; Google consent, secure provider credentials and storage grants are
not transferred by this file. No settings, ROMs or FolderSync state changed.

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

### Subsequent PS1 completion and scope extension — 2026-10-05

- Normal PS1 ScreenScraper job 20 completed all 405 requested rows: 214
  needsReview, 136 ambiguous and 55 unmatched, with zero accepted/rated results.
  Follow-on artwork job 21 completed with zero items. A fresh bounded read-only
  database inspection verified device-before/device-after/host digest agreement,
  quick_check, both terminal jobs and exact outcomes. The scope is 319 remote
  artifacts plus 86 local rows, not 405 reviewed canonical games. No duplicate
  refresh or fabricated ranking was used to resolve uncertain matches.
- Revision 7 adds SAVE-01/S10, with the user's subsequent instruction to cover
  most installed emulators. Full package discovery was read-only; save access,
  backup uploads and restore support are not claimed. S10 remains NOT STARTED;
  S7 is the sole ACTIVE stage, and S8/S9 remain NOT STARTED. FolderSync's pairs,
  schedules and transfers were not changed or invoked; it remains as-is.

### PS1 independent pass and safer cached review — 2026-10-05

- Normal native IGDB Fresh job 22 completed the same PS1 scope: 405 requested,
  233 needsReview, 135 ambiguous and 37 unmatched, with zero matched/rated,
  failed/unsupported or pending. One owner/worker was observed through completion;
  no duplicate refresh was started when a busy UI could not provide an idle dump.
  Stable device-before/device-after/host database digests and quick_check passed.
- Two normal native selections explicitly chose the correct PS1 identities and
  Official releases classification, then used Save match and recheck. Jobs 23
  and 24 each completed one matched/rated item. The production community basis
  has 122 votes for the first and 44 for the second; unrelated critic/overall
  values were not substituted. These are exact reviewed editions, not complete
  multi-disc groups, a whole-library Top-25 ranking or removal authority.
- Native review exposed a current-stage safety defect: the cleaned title omitted
  the source filename/folder, disc and patch labels. META-03 now documents that
  existing review context requirement. The bounded cache-only projection reads
  just the current edition's artifact members/local cache row and renders their
  labels beside the search title. It does not approve identities, infer tags,
  request provider metadata or retrieve ROM bodies.
- The regression first failed for missing labels, then passed at landscape,
  portrait and narrow portrait sizes. Existing checks also prove wrong-platform
  rejection, independent overlapping tag selection, exact-scope isolation and
  no extra provider requests. Focused metadata-job tests and scoped analysis
  passed. The existing bounded 30,000-edition fixture observed about 310 MB peak
  RSS, not an unbounded memory failure. No full repository suite was launched.
- Gated build 164 acquired the shared mutex but failed before compilation because
  PowerShell split an unquoted `-Ptarget=lib/main.dart` into two arguments. A
  separate argv reproduction established the cause; quoting each Gradle argument
  fixed the invocation. Build 165 then held the same mutex through exit zero.
  Observed workers 2, parallel false and Gradle heap 3 GiB; assessed Kotlin 2.2.20
  uses in-process compilation sharing that heap. Test tasks were configured one
  fork/512 MiB but not executed. App native pools remain one; the plugin native
  tasks ran, but their effective full concurrency is not independently measured.
  Neither attempt produced memory-failure evidence or required a budget increase.
- Independently inspected APK package/activity/signature matched the existing
  debug installation; SHA-256 is
  `30042a8a96ab482d6aaf80db1d50e0960df61d98c4118887a851afa51b6d4606`.
  Installed in place only after all metadata jobs were terminal, with no uninstall
  or clearing. Native PS1 review now displays the original CHD/disc label and an
  unmodified official title's filename. Stale ScreenScraper candidates remain
  blocked after identity correction. Opening cached review created no new jobs.
- Configuration and secure-credential fingerprints match the pre-update baseline;
  all three completed IGDB jobs, both exact reviewed ratings and the 1,428-row
  Library are preserved. A blanket private-file hash assertion also included
  regenerated Flutter binaries, a resource marker and normal startup preferences/
  database writes, so that assertion is not claimed as byte-for-byte app-data
  preservation. No ROM, save, BIOS, FolderSync configuration or cloud archive was
  changed by this fix. Required S7 membership/ranking/recovery/migration work
  remains unfinished; S7 is ACTIVE and S8-S10 are NOT STARTED.

### PS2 catalogue, interrupted connectivity and checksum audit — 2026-10-05

- The normal native Sources workflow added a fifth read-only Drive source rooted
  at the actual PS2 archive. Existing four source and console objects were checked
  unchanged; no second account, new OAuth client or backup-write grant was used.
  The source-add refresh and subsequent explicit Refresh shared the same active
  scope future rather than creating a second worker.
- Generation 1 published 1,482 observations, including 463 folders, with no
  remaining traversal work. Stable device-before/device-after/host database
  digests and quick_check passed. The mapper correctly disabled selections before
  publication. Comparison of current platform aliases with all published folder
  names offered only PS2; normal Save mappings created only that mapping.
- Normal console settings/Android folder selection saved the actual SD PS2
  directory. Object comparison verified the prior four sources/console objects
  unchanged and the new physical target/mapping correct. No existing file was
  adopted, installed, moved or removed. The stable Library now contains 202
  remote PS2 artifacts plus 23 local rows, not 225 canonical games.
- ScreenScraper Fresh job 25 was created once. It paused before the first lookup
  with blocked_status `unavailable`, preserving all 225 pending items. A current
  microG authentication crash reported Host unreachable; R-Shop's original
  process stayed alive and the selected SD target persisted. Direct Thor HTTP
  checks then proved an expired hotel captive-portal session, despite Android's
  stale validated-network report. The laptop hotspot could not start because
  icssvc was disabled; its attempted service change was denied and it remained
  disabled. No VPN, firewall, service configuration or credentials were changed.
- Android's normal Wi-Fi Sign in to network action opened the hotel portal.
  Its existing Continue to the Internet action restored access; direct Thor
  checks returned HTTP 204 for connectivity and HTTP 200 for ScreenScraper.
  One normal Resume saved job action resumed job 25, without a new generation,
  process restart or Fresh retry. Live progress subsequently processed lookups.
  This resolved connectivity incident is not an outstanding stage blocker.
  Job 25 completed 225 lookups: 118 need review, 43 ambiguous, 64 unmatched,
  zero matched/rated/failed/unsupported/pending. Artwork job 26 completed with
  zero items. The subsequent normal IGDB Fresh job 27 completed the same scope:
  142 need review, 47 ambiguous, 36 unmatched, zero accepted/rated or failures.
  Stable device/host database digests and quick_check verified terminal results.
- The single read-only PS2 checksum audit joined exit zero. Its private durable
  journal contains 24 exact SD files: 23 stable artifacts totaling 45,166,984,325
  bytes match their cached Drive size/digest identities, and one 576-byte non-ROM
  file is preserved. All dispositions are preserve and removalAuthorized=false.
  Cached checksums do not prove current cloud readability/version, canonical
  grouping, ranking or a tested format restore. Those migration gates remain.
- S7 remains the sole ACTIVE stage; S8-S10 are NOT STARTED, and FolderSync is
  untouched. The subsequent rating-binding defect and its verification follow.

### Unchanged reviewed evidence survives catalogue sync — 2026-10-05

- A normal exact PS2 review selected the original game/platform rather than an
  alternate edition, explicitly classified it as official, and rechecked it in
  job 28. The accepted community score had 1,341 votes, above the assessed floor.
  Returning to Home then removed its usable score despite unchanged source
  bytes and classification. The raw provider record remained stored.
- Reproduction traced the failure to catalogue seeding removing/reappending
  unchanged artifact evidence after manual classification. Reversing only those
  unchanged facts reproduced the saved binding; other identity facts had not
  changed. The fix preserves existing evidence order for unchanged content and
  unchanged folder declarations. Changed bytes/classification retain existing
  invalidation behavior; there is no global hash migration or stale promotion.
- The store regression failed before the fix. Focused effective-rating,
  metadata-job and library-store checks passed after correction, including
  changed-content invalidation and unchanged folder bindings. Scoped analysis
  and diff checks passed; no full suite was run.
- Build 166 ran once through the shared gate supervisor and exited zero.
  Observed workers 2, parallel false, Gradle maximum heap 3 GiB and assessed
  Kotlin 2.2.20 in-process compilation sharing that heap. Test tasks configured
  one fork/512 MiB were not executed; app native pools remain one, with native
  tasks mostly up-to-date. Full plugin-native concurrency is not measured.
  No memory-failure evidence or budget increase occurred. The supervisor's
  gate-acquired result field was truncated from the retained tool output; this
  records the successful gated invocation, not an independently captured receipt.
- APK package/activity and signing certificate matched the existing owner.
  Independently inspected SHA-256:
  `e53e507c7747090a6b21beb4b8cd25151def778c5e524d2afbb2cd056b789a1b`.
  Normal in-place installation preserved configuration, both secure credential
  fingerprints, all 28 terminal metadata jobs, three raw reviewed provider
  records and the 1,653-row Library. No uninstall or data clearing occurred.
- On the updated Thor, normal selected-game Fresh produced job 29 with one
  matched/rated lookup and no pending work. Returning through the normal Home
  sync and reopening the same details retained the 89.1/100 user score, 1,341
  votes and provenance. A stable database/quick_check observation confirmed
  score 89.12546853689747 and ranking_eligible=1 after Home sync. Already-stale
  earlier records were not silently rebound; exact fresh rechecks own recovery.
- This verifies the specific refresh regression, not whole-library identity,
  canonical ranking or migration completion. No ROM download, adoption, removal,
  cloud mutation, FolderSync change or S10 implementation occurred.

### Source setup text-input regression and next console scope — 2026-10-05

- Native keyboard entry dropped the letter used by the application's search
  shortcut from a new source label. Investigation identified inherited I/F
  search/favorite shortcuts rather than a cloud authorization failure. The
  focused widget reproduction invoked both app shortcuts while each real source
  field was focused, failing the no-navigation contract before the fix.
- The two setup fields now use the same local stop-propagation technique as the
  existing folder mapper, leaving those letters to platform text input. No global
  key map, controller behavior, provider transport or authorization was changed.
  Focused setup/mapping tests, scoped analysis and diff checks passed.
- Gated build 167's inspected receipt confirms gate_acquired=true and exit zero.
  Effective workers 2, parallel false, Gradle maximum heap 3 GiB; assessed Kotlin
  in-process shares that heap. One-fork/512 MiB test configuration was observed,
  not executed by this build. App native pools remain one; plugin native tasks
  were mostly up-to-date and full native concurrency is not independently
  measured. No memory-related failure or budget increase occurred.
- APK package/activity/signature matched the installed debug owner; independently
  inspected SHA-256:
  `bd78b692d6da0e4465281167861d7f78940d6ea04334bae2ddbb1d3a98e90e60`.
  The in-place update preserved configuration, secure credential fingerprints,
  all 29 terminal jobs, metadata records and the 1,653 cached Library rows.
- Native source entry retained the full console name, and the exact existing
  public client ID was verified before Connect. The default existing account
  connected normally; observed My Drive/Roms/N64 navigation selected that exact
  root. Save created only the sixth read-only source; object checks verified
  all five old sources and every old console object unchanged. No write grant,
  second account, ROM transfer or FolderSync operation occurred.
- Its normal refresh has not yet been verified as published. The mapper remains
  disabled without successful publication, and no mapping was saved. Read-only
  host snapshots during active database writes were rejected as unstable, not
  treated as corruption or repaired. N64 publication/mapping/fresh metadata and
  migration remain ordinary unfinished S7 work; S8-S10 remain NOT STARTED.

### N64 publication, actual SD targets and score projection proof — 2026-10-05

- The sixth source's generation 1 published successfully: 5,632 observations,
  670 folders, no pending generation or remaining catalogue work. Normal mapping
  saved the single unambiguous N64 console root. Existing mappings were preserved.
- Normal Android folder pickers selected `/storage/75D7-DC5F/Roms/n64` and
  `/storage/75D7-DC5F/Roms/gc`. Console-settings edits are persisted when exiting
  the console list, not merely its detail page. After normal exit, configuration
  comparison verified exactly those two target-field changes; all six source
  objects and every other console field remained unchanged.
- Normal Home sync and a stable SQLite/quick_check observation established:

  | Console | Library artifact rows | Remote artifacts |
  | --- | ---: | ---: |
  | Game Gear | 548 | 182 |
  | GameCube | 206 | 134 |
  | N64 | 1,543 | 1,391 |
  | PS2 | 225 | 202 |
  | PSP | 341 | 269 |
  | PS1 | 405 | 319 |
  | Total | 3,268 | 2,497 |

  These are artifacts/cache rows, not canonical games or installation ownership.
  Native Library displayed All 3,268 / Installed 695; that Installed label alone
  does not establish R-Shop ownership of existing SD files.
- Two read-only streaming audits completed and their terminal summaries were
  independently reconciled against every journal entry: N64 has 320 game
  archives matching cached Drive size/digests (3,267,752,208 bytes) and two
  preserved non-ROM files (1,124 bytes); GameCube has 80 matching RVZs
  (69,814,480,572 bytes). Every disposition remains preserve and removal authority
  false. Private exact-file journals stay outside Git. Cached checksums are not
  live cloud-version/readability or format-specific restoration proof.
- Normal N64-only Fresh was invoked once. ScreenScraper job 31 is still running
  on its 1,543-row snapshot, with no blocked status. The latest read-only native
  observation reported 445 requested, 1,099 pending, 299 needing review, 80
  ambiguous and 65 unmatched; none matched/rated. Progress persisted while the
  displays were off. No duplicate worker or N64 IGDB pass was launched.
- The second reviewed PS2 identity (IGDB 1229, exact original Disc 1) had a dirty
  query projection after sync, not a lost identity binding. Normal Library search
  and details showed 90.2/100 from 28 IGDB user ratings with scale/retrieval
  provenance. A subsequent read-only query found score 90.24511423825714,
  ranking_eligible=1 and dirty=0. The earlier IGDB 2207 record remains eligible at
  89.12546853689747. No production patch was made for the stale diagnostic read;
  Disc 2/canonical bundle review remains unfinished.
- No Gradle command, APK replacement, ROM transfer/adoption/removal, cloud write,
  FolderSync inspection/change or S10 implementation occurred in these checks.
  S7 remains ACTIVE; remaining fresh scopes, canonical identities, defensible
  ranking and actual migration are ordinary unfinished work.

### S7 score-basis extension — 2026-10-05

- Extended the existing public persistent-worker reception fixture to N64, PSP
  and Game Gear. The assessment records actual scales/counts, exact offered
  identities, independent reception, edition mismatches and ordering differences.
  N64/PSP use the same assessed IGDB community policy; no critic/total fallback,
  title boost, unknown-count exception or lower vote floor was introduced.
  Game Gear remains unassessed because its captured records are sparse/unrated
  or ambiguous. See SCORE_RECEPTION_ASSESSMENT.md for the public evidence.
- The focused boundary reproduction failed before production scope extension at
  its required twenty-vote case. Effective-score and indexed-query checks passed
  afterwards, including ownership, freshness and low/unknown support. A fresh
  real-provider capture followed by offline production query verified nine
  supported games from fifteen public fixtures, identical Top-25 membership and
  provisional incomplete coverage. Scoped analysis and diff checks passed; no
  full suite was run.
- The installed APK remains build 167. Native integration of the extended basis
  has not yet been performed, preserving the currently running N64 scrape. The
  last read-only observation of that same job 31 reported 675 requested, 869
  pending, 456 needing review, 120 ambiguous, 98 unmatched and zero matched/rated,
  with state running and no blocker status. No duplicate worker was launched.
  Both physical displays were confirmed committed OFF after native verification.
- No Gradle command was run, so this checkpoint claims no new mutex acquisition
  or effective build-profile measurement. The task-only read-only observation
  helper is retained outside Git until this active job's terminal outcome can be
  inspected; its exact registered cleanup transaction and private migration
  journals are preserved. No external release, save backup or SD removal occurred.

### Collection-root setup and configuration reuse — 2026-10-05

- Normal native setup saved one additional read-only Drive source rooted at the
  owner's ROM collection. One Refresh catalogue action started generation 1.
  The latest read-only native observation found active=null, pending=1, 56,338
  observations, 5,457 folders and 5,061 pending folder work rows. Those are
  unpublished traversal observations, not mapped games or payload downloads.
  Native configuration comparison verified all six prior source objects and
  every existing console object unchanged; the new source still has no mappings.
- The original N64 ScreenScraper job 31 remains running with no blocked status:
  1,267 requested, 277 pending, 860 needing review, 218 ambiguous, 188 unmatched,
  zero accepted/rated. No duplicate worker or new IGDB pass was started.
- The owner's configuration-reuse question distinguishes feature verification
  from S7's collection-wide metadata/migration. A PS1 workflow suffices for the
  former; additional console mappings serve the latter. Existing config export
  preserves source/account/root identities, manual folder mappings, source
  priorities and console SD targets without bearer tokens or provider secrets.
  Normal import validates that configuration before saving it. Focused Drive
  persistence/resolution checks passed on the current source, exit zero.
- Before any separately authorized release handoff, produce a private export
  of the final console/source configuration and verify its normal import without
  repeating folder selection. Do not publish that export or embed owner-specific
  mappings in an APK. The metadata/artwork bodies already use durable shared
  storage; the other package must select the same directory and regain access.
  OAuth consent and secure metadata credentials are package-local, not exported.
  Actual debug-to-release setup transfer has not yet been live-verified and is
  not claimed here; a shared cache is not automatic transfer of all preferences.
- Required normal debug build 170 passed through the shared supervisor after
  waiting its FIFO turn. Gate acquisition and observed two-worker/no-parallel/
  3 GiB Gradle profile were reported. Kotlin 2.2.20 remains configured in-process,
  sharing that heap; Metaspace 1 GiB and code cache 256 MiB were preserved.
  Test-task configuration reported one fork/512 MiB, not executed test-JVM proof.
  Full plugin-native concurrency remains a verification gap. No memory failure
  or heap increase occurred. The preceding gated attempt 168 failed because an
  unquoted PowerShell target argument produced a stray `.dart` task; the retry
  used whole-argument quoting only after that process had exited.
- The resulting normal debug APK has SHA-256
  `0bc2b340706705cf968809ecb1897d6dc726d4f3e18fd4806235680c45c50966`,
  package `com.darkaxt.rshop.debug`, version 1.7.0/12 and the unchanged debug
  signer. It has not been installed over the live jobs. Build log:
  `28f5ea42b00d4d38b826b84d867ef12f.log` in the shared build-gate log directory.
  Both physical displays were freshly confirmed OFF. S7 remains the sole ACTIVE
  stage; no FolderSync change, SD removal, save-backup implementation or external
  publication occurred.
