# Staged implementation plan

Authority: [SPECIFICATION.md](SPECIFICATION.md), revision 5.
Actual progress and reconciliation: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

Implementation is already authorized (2026-09-08, "go ahead then"). Execute S1-S9
without new routine approval gates. Provider account setup is new; fixtures do
not replace the required live evidence. The user selected Top 25 per console as
the final offline sample; S7 applies the reviewed, cloud-verified migration.
S8 was added by the user on 2026-10-02; it must not open a second active stage.
S9 was added on 2026-10-04 as the final cartridge/legacy-media visual audit;
its status is NOT STARTED. It does not open another implementation front in S5.

## S0 — Fork and specification preparation

Objective: preserve upstream and provide a complete, traceable development entry.

- Fork upstream under the user's authenticated GitHub account; retain MIT license.
- Keep `origin` as the fork and `upstream` as AverageConsumer/R-Shop.
- Prepare a `codex/` branch, authoritative specification, staged plan and ledger.
- Review requirements and scope, validate documentation links/mapping, inspect the
  final diff, commit and push documentation only. Do not open an upstream PR.

Evidence: fork parent/default-branch identity, upstream base commit, complete
requirement mapping, clean documentation diff, commit and remote branch equality.
No Flutter build or feature test is necessary to validate documentation-only work.

## S1 — Shared identity, migrations and external-access setup

Requirements: CORE-01, CORE-02, CORE-03, DRIVE-01, META-02, QA-03.
Depends on: S0 and authorization to implement.

- Establish Android development SDK/runtime and baseline test status. Resolve
  package/signing identity before OAuth registration or any installation.
  Under QA-03, preserve the upstream APK naming route and release display name
  `R-Shop`, with only the fork-specific application ID; verify the processed
  release manifest without implying publication authorization.
- Add provider-independent game/edition/remote-artifact identities, rating
  provenance and database/config migration contracts, with tests first where
  behavior is reproducible. Inventory every SourceType/ProviderType switch.
- Add Android authorization adapter and credential-store interfaces; complete
  authorized Google client and standard ScreenScraper account setup. Do not ask
  the user to obtain a developer account. Verify the standard-account API route
  and resolve legitimate application authentication if the provider enforces it.
  Do not borrow
  other applications' embedded developer credentials. Use fixture clients until
  legitimate live access is available, without calling those fixtures live proof.
- Create the metadata-provider contract and a functional ScreenScraper adapter;
  retain RomM as an optional adapter and preserve existing source behavior.

Evidence: migration and identity regression tests; consent/cancel/renewal/account
isolation proof; redaction tests; live authenticated metadata lookup. Missing API
access blocks the corresponding acceptance criterion, not unrelated fixture work.

### S1 Thor native authorization boundary (2026-10-02)

The actual Thor runs microG 0.3.15.250932. Its identity authorization service does
not advertise `auth_api_credentials_clear_token`, so the modern SDK awaits missing
feature resolution without dispatching the clear handler. Select microG's supported
native GoogleAuthUtil cache-clear operation by its installed authorization-service
component before calling that SDK method; ordinary Play Services retains the
endorsed route. No timeouts, sleeps, SDK downgrade or account-provider replacement.
Evidence: matching [microG service feature list](https://github.com/microg/GmsCore/blob/v0.3.15.250932/play-services-core/src/main/kotlin/org/microg/gms/auth/credentials/CredentialsService.kt),
[authorization service implementation](https://github.com/microg/GmsCore/blob/v0.3.15.250932/play-services-core/src/main/kotlin/org/microg/gms/auth/credentials/identity/AuthorizationService.kt)
and the actual device dispatch trace.

The same microG revision's revokeAccess only invalidates local consent; a live
probe demonstrated the previous grant still authorized Drive (HTTP 200). Explicit
Revoke must first confirm Google's fixed OAuth revocation POST, with the ephemeral
token in a form body, then disconnect native consent. Failures remain sanitized
and must not report remote revocation. This is account-wide/project-wide grant
revocation, not deleting a source or mutating Drive files. Keep credentials in
memory only and preserve the retry binding on server failure.
The HTTP success contract follows [Google's OAuth revocation protocol](https://developers.google.com/identity/protocols/oauth2/native-app#tokenrevoke).

Required evidence: reproduce both failures on the actual native adapter; focused
redaction/ordinary-GMS/microG/account-binding/revoke-failure contracts; native cache
clear plus silent authorized metadata; prior grant rejected after server revoke;
scope decline/reconnect; unchanged sources/files and both displays OFF. Cache
invalidation proof does not become elapsed-expiry or second-live-account proof.

## S2 — Drive catalogue and source integration

Requirements: DRIVE-02, DRIVE-03.
Depends on: S1 identities, migrations and Drive authorization.

- Add Drive configuration, normal Sources UI/factory/resolver and source health.
- Implement folder-ID selection, explicit system aliases/mappings and paginated
  checkpointed traversal with transactional catalogue publication.
- Feed exact remote artifacts to the existing queue; resolve authorization at
  request time. Preserve existing mixed-source queue options.

Evidence: pagination/nesting/duplicate-name/cross-account fixtures; refresh failure
and rename/move reconciliation; live selected-folder inventory; no ROM body reads
and no traversal outside the selected subtree.

## S3 — Verified transfer and owned installations

Requirements: DRIVE-04, DRIVE-05, DRIVE-06.
Depends on: S2 exact artifacts/queue and S1 migrated state.

- Add durable stage/publication records and version-bound range validation.
- Stream hashes; gate installation on size/checksum; account for real staging
  space and capability restrictions. Test lifecycle transitions with explicit
  events, including cancellation and process recovery.
- Track installed path ownership; protect existing targets, bundles and saves.
  Revalidate identity before local removal and preserve files replaced by another
  app; reject redirected paths rather than trusting a stale ownership entry.
  Refactor common transfer code only as needed by these contracts, retaining
  existing-provider regressions. No arbitrary full-downloader rewrite.

Evidence: fault-injected HTTP/state/storage tests, large-file bounded-buffer
measurement, missing-checksum blocker, multi-disc consistency and exact-file
removal tests including replaced-owned-file and redirected-path conflicts.
Live transfer/verify/offline emulator/remove/re-download proof is
required, using a deliberately chosen test artifact and destination.

### S3 implementation sequence and reviewed storage boundary

The source audit at `b8052d4` established the following implementation seams.
These refine S3; they do not replace its acceptance criteria or authorize a
general rewrite of legacy providers.

1. Add exact source/ancestor revalidation, binary HTTP range validation, bounded
   streaming hashes and an additive transactional transfer/installation journal.
   The transport must propagate writer backpressure and cancellation to the
   original input stream; `ResponseType.stream` alone does not establish that.
2. Add an Android owned-storage adapter behind the existing storage channel.
   Prefer persistent app-owned external-files staging on the destination volume,
   excluded from ROM scans. Flush bytes before persisting their durable offset.
   Use safe relative paths and descriptor-pinned, no-follow traversal. The public
   Java `Os` API lacks the necessary `*at` primitives; a small JNI adapter is the
   reviewed path to `openat`, `fstatat`, `renameat2` and `unlinkat`. Feature-detect
   operations and preserve older Android behavior; do not link an API-30 symbol
   unconditionally into the existing API-24 path.
3. Journal publication intent before no-replace publication, then sync and verify
   the resulting object before the installation/completed transaction. Existing
   targets remain conflicts unless an explicit ownership-checked replacement
   protocol applies. Never call the legacy delete-before-move helper for Drive.
   Test the actual app-UID Android/data-to-ROM move on the selected SD filesystem;
   equal device IDs alone do not establish supported atomicity or durability.
4. For cross-volume copies, retain the verified source, journal an exclusive
   destination-volume staging copy, hash/sync it, publish there and only then
   retire the recorded source. Include both copies and any old valid installation
   in peak-space checks. Recover every interrupted journal phase by identity and
   digest, not by filename existence or age/suffix cleanup.
5. Integrate a typed Drive handle before legacy cache staging/extraction. Extend
   visible lifecycle states and join cancellation/resource shutdown. Scope queue
   callbacks and disposal to an attempt identity, never only a reusable game ID.
   Stream closure is not completion; only the installed-state commit can trigger
   the completed callback. Include active transfers in source-disconnect draining.
   Implement/persist required queue reordering without changing source concurrency.
6. Route exact-artifact installation status, launch/share/achievement paths and
   removal through the manifest. For removal, journal an exclusive move into owned
   quarantine and validate the moved object before unlinking individual verified
   ROM members. Preserve changed objects and attempt no-clobber restoration on a
   conflict; no recursive game-folder removal. Do not claim an advisory lock or a
   pre-move stat prevents every possible already-open external writer.
7. Complete bundle/playlist, replacement, cancellation, process-death and native
   filesystem proof, then the authorized emulator/offline/remove/re-download
   round trip. Until the engine and native publisher are integrated and verified,
   the existing explicit Drive payload/removal gate remains in place.

### S3 target-storage finding and journaled copy route

The live Thor test established that an equal `st_dev` can hide different Android
bind mounts. Staging selection therefore prefers the descriptor's actual mount
ID; neither device nor mount equality is an atomic-publication capability claim.
The Thor's Android 13 SD FUSE path rejected `RENAME_NOREPLACE`. The corresponding
[AOSP Android 13 handler](https://android.googlesource.com/platform/packages/providers/MediaProvider/+/refs/heads/android13-release/jni/FuseDaemon.cpp)
also rejects nonzero rename flags. Do not replace this with check-then-rename or
an overwrite-capable move. DRIVE-05 already requires a journaled alternative.

For unsupported rename or cross-mount publication, the engine must journal a
copy intent, exclusively create the final destination through the pinned parent,
persist its exact native identity, and copy only from the retained verified
app-private stage in bounded chunks. No network writer may target the public
copy. Flush before each copied-offset/identity checkpoint; compare a resumed
public prefix against the verified source before appending, because SD timestamp
precision can hide same-size edits. Rehash the entire destination and sync its
parents before the installation transaction. Retain the source through that
transaction and any interrupted recovery. Never truncate or replace an existing
public file by filename; unjournaled identity/size changes and the create-before-
identity-record crash gap remain preserved conflicts, not automatic adoption.

Unlike an atomic rename, a public destination copy may be visible in an external
file browser while publication is incomplete. It is not resumable network staging
and must not be advertised as installed by R-Shop or handed to an emulator until
the journal's installed-state commit. Queue/legacy discovery integration must
enforce that distinction. Existing valid-target replacement remains separately
gated until an ownership-checked protocol preserves the old installation through
verification and commit. Native copy primitives alone do not satisfy these
engine, process-death, bundle, removal or replacement acceptance criteria.

### S3 post-commit private-stage retirement

A completed copy and its exact stage identity are the durable cleanup intent.
Retire that app-private copy only after the installation commit and confirmed
session closure, then synchronize its pinned parent before acknowledging cleanup
in the journal. An absent private entry is a replayable post-unlink crash state,
not permission to touch a public ROM. Native retirement checks the current
installed object, private stage identity and inactive sessions; changed or
redirected objects remain preserved conflicts.

Track cleanup acknowledgement separately from download completion. Failed
cleanup, directory synchronization or journal acknowledgement cannot undo a
committed installation or require another ROM download. An unconfirmed close
defers retirement. On app startup, one bounded keyset-paged offline journal pass
recovers pending completed copies independently of the saved queue; shutdown
signals the pass to stop between entries and joins any in-flight native call.
No timer retry or age/suffix-based scan is used.

This private-stage retirement primitive is **not** public owned-ROM removal.
The subsequent actual app-UID SD probe established that ordinary public-to-private
rename succeeds, although public `RENAME_NOREPLACE` remains unsupported. Removal
therefore journals intent before moving the exact owned file into a random,
app-exclusive private staging name. The serialized native boundary forbids an
existing private destination and active matching handles. This narrowly owned
private namespace permits ordinary rename; it is not a public check-then-rename
publisher and cannot authorize overwriting public files. Public restoration still
requires kernel no-clobber; unsupported restoration preserves the conflict.

After quarantine, compare exact native identity, stream SHA-256, recheck identity
and confirm handle closure before durable deletion intent and private unlink.
Retain ownership on conflict. Unlink acknowledgement precedes atomic manifest/
target-claim release, so an absent private entry is recoverable only with prior
deletion intent. Additive v19 journals preserve existing installations. Startup
serially finishes stage retirement then one keyset-paged removal pass, even with
an empty queue and no authorized account. Shutdown joins in-flight mutation;
there is no timer retry. The real SD synthetic install/lost-move-receipt/startup-
removal/reinstall test proves this boundary, not live Drive or emulator acceptance.

### S3 internal shared-storage removal restriction (2026-10-02)

An actual app-UID probe found different mount IDs between internal shared storage
and private external-files staging. `renameat` returned EXDEV (18), leaving the
public synthetic file unchanged and private destination absent. The SD-card probe
on the same device succeeded. Do not replace quarantine with a public
check-then-unlink or silently claim deletion. Preview and explicit removal reject
known cross-mount plans before recording intent. Existing EXDEV intents terminate
as `retained` only after fresh exact public identity and absent private quarantine
evidence; the installation, transfer and target owner remain intact. The failed
attempt remains audited, while readiness is no longer blocked by an impossible
pending removal. Additive v20 updates the active-removal index without dropping
any records. This capability restriction does not waive DRIVE-06's actual
supported-target round-trip proof or its other unfinished acceptance criteria.

### S3 valid-target replacement route (2026-10-02)

Updates retain the exact previous manifest and transactionally claim its owner.
Publish a verified new version to a distinct deterministic path retaining its ROM
extension, rather than overwriting the old public entry on SD FUSE. The old ROM
and ownership remain through network, verification, publication and cancellation.
After the new installed-state commit and closed handles/private-stage retirement,
freshly hash the new target, then retire only the recorded old owner through the
existing durable quarantine/hash/unlink protocol. Record cleanup separately from
successful download; changed objects and unsupported removal are preserved,
visible conflicts. Offline startup performs one paged recovery pass, not retries
or directory scans. Native process-stop proof remains required before closing
this boundary; bundle/playlist support is still unfinished within S3.

### S3 explicit bundle installation route (2026-10-02)

Selected UTF-8 M3U and binary FILE/BINARY CUE manifests resolve dependencies by
exact relative names inside the published, folder-ID-rooted catalogue. Duplicate
names, parent traversal, absolute paths, URLs, cycles, unsupported formats and
missing provider checksums fail before installation. Indexing still reads no
payloads. Manifest planning is cancellable and joined at disconnect; it reads
only selected headers (256 KiB each, 1 MiB aggregate), not disc bodies.

Persist the immutable flattened dependency graph before creating member transfers.
Limit it to 256 members. A dedicated full-identity bundle namespace preserves the
original relative layout and header bytes; a dependency-version change creates a
new graph even when the playlist version did not change. Children share the normal
queue slot and stream sequentially, with aggregate progress. Restore the durable
graph and exact completed members, not a filename-derived guess.

Additive v22 ownership excludes member transfers from independent installation
discovery. Commit the root only with every exact member installation and retired
private stage; normal consumers and native read grants revalidate those members.
Retained old bundles do not outrank their committed replacement. Removal previews
list every exact member and total bytes. Parent-authorized child removal has a
bounded deterministic SHA-256 journal/staging name and recovers independently of
the source. Never recursively remove public directories or neighboring saves.
Sharing streams pinned exact members into a private temporary tree and STORE ZIP,
not a guessed public game folder. Its handles close even on output-open failure.

Required proof: actual queue/native SD process-stop after a member commit and
quarantine before receipt; no repeated completed-disc media request; missing-disc
readiness rejection; exact sharing/removal/save preservation; native grant checks;
upgrade/restart of normal data. Synthetic disc bytes prove these boundaries, not
an actual multi-disc emulator boot. The real RVZ/Dolphin round trip supplies the
separate actual emulator acceptance evidence.

## S4 — Fresh metadata pipeline and score semantics

Requirements: META-01, META-03, META-04, META-05, META-06, META-07.
Depends on: S1 provider/identity contracts; S2 remote catalogue for integration.

Classification reconciliation normalizes only finite known tag spellings/case
(including `T-En`, `Dubbed`, `Undubbed`, `Uncensored`) through the existing edition
identity and shared request/query/review boundaries. Preserve unfamiliar labels,
classification evidence, general translation status and translated languages;
never infer tags from a title, ordinary English language or age rating. Unknown
or contradictory official classifications remain browsable under Unknown.
Backfill only rebuildable canonical/query projections on upgrade, retaining
original stored identity JSON, metadata bindings/facts and in-flight job records.
Verify explicit review -> retry -> worker publication -> offline filters and
production upgrade/reopen; normalization alone does not approve a match or Top.

- Implement persistent full/per-system/per-game refresh generations, correction
  preservation, deduplicated work, quota control and fresh coverage reports.
- Ignore historical gamelist data as a trusted baseline. Revisit every game
  identity, with explicit no-match/failure outcomes instead of fake completeness.
- Validate platform/release/hash matching; distinguish container identifiers,
  hacks, `T-Eng`, `Dub`, `Undub`, `Uncensor`, base-game ratings and unknown
  classifications. Test independent/combined tags and official-English distinction.
- Retain provider scales/provenance/count availability and separate cache from
  installation residency. Do not invent a popularity aggregate or fixed Top list.
- Validate overall-score reliability against broader critical/community reception
  under META-05. Resolve inadequate source evidence through a legitimate aggregate
  score adapter when needed, before claiming Top membership is meaningful.
- Implement indexed, shared metadata query/filter behavior at the same time as
  persistence. Test category/genre constraints, any/all tag combinations, dynamic
  collection-only Top-N using the displayed accepted overall score, recomputation
  on score/catalogue changes, rank-before-tag-filter intersection with no backfill,
  scope/limits and
  game grouping before UI wiring; do not duplicate library and console semantics.

Evidence: stale-cache refresh, duplicate demand, ambiguous/hack matching,
normalization, quota/pause/restart/offline and rank-before-tag-filter tests; a
30,000-game bounded fixture with paged query and deduplication measurements;
fresh live samples including older and newer consoles and modified releases.
Unmatched provider coverage is reported honestly and does not authorize false
matches. Run the full fresh library pass only within authorized live scope.

The [2026-10-03 live reception assessment](SCORE_RECEPTION_ASSESSMENT.md)
records older/newer releases and independently identified projects. ScreenScraper
and IGDB's blended total are not approved. The legitimate IGDB capture resolved
B4 and establishes the labelled game-level community average with known >=20
user votes in the assessed PS1/PS2/GBA/GameCube/Switch scope. Preserve its actual
community kind; it is an overall assessment of the game, not a critic component
silently substituting for an absent total. Query/display integration and remaining
S4 reconciliation must still pass before stage closure.

### S4 provider budget and explicit recovery boundary

Persist the single selected metadata provider's reported request cadence across
jobs/relaunch. Reserve request slots before network access, retain the exclusive
worker claim through protocol waits, and join cancellation without per-item
listener accumulation. Persist daily/unmatched exhaustion, including exhaustion
observed on a job's final item. A user-requested access recheck uses the documented
account-status endpoint and complete fresh quota counters; do not invent a local
reset timer or poll. Retain Retry-After and current identity checks. Account status
does not publish game metadata. Artwork-body fetches must use the same provider
budget before META-06 can be closed.

### S4 artwork publication boundary

Capture only current owned media selectors and metadata generations. Image jobs
share the exclusive worker, persisted cadence and daily request balance with game
lookups, including cancellation/relaunch and explicit access recovery. Publish
bounded, CRC-valid and natively decoded single-frame PNG bodies to immutable
content-addressed app-private files, then commit current bindings in bounded pages.
Failed refreshes retain usable cache pointers; scrolling/offline reads never
initiate requests. Persist selectors and relative hashed filenames, not credential
URLs. Resolve ScreenScraper images at its fixed documented endpoint. Normalize
only the exact live-observed IEND-plus-ASCII-1 endpoint framing; the cache still
rejects arbitrary appended bytes. Native integration and the full large-fixture
artwork/resource assessment remain acceptance work, not inferred from host proof.

### S4 canonical grouping boundary

Maintain an indexed edition-to-group projection in the identity transaction,
backfilled in bounded pages on upgrade. Verified ScreenScraper and IGDB game IDs
plus the platform identify ordinary/known translated/audio/restored editions; candidate
IDs, titles, container hashes and unknown classification do not merge identities.
Hack projects without verified project-specific identity remain under their
explicit stable game identity, never the base provider ID. Keep exact editions,
patches, discs, metadata bindings and installation ownership unchanged. Bounded
edition selection validates live catalogue bytes and current identity bindings;
grouping does not authorize borrowing ratings. Additional provider/raw-identifier
reconciliation and the accepted-score/rank-before-filter query remain S4 work.

The additive v29 projection records only these implemented, reviewed provider
assertions. Multiple assigned IDs on one eligible edition establish a bridge;
titles, provider candidates and hack base IDs do not. Resolve connected assertions
in SQLite and keep affected editions/components in transaction-local tables,
with bounded identity pages rather than a full-library Dart graph. Capture old
component members before replacing assertions so a corrected/removed bridge can
split them; include new neighbours when joining components. Existing query
mutation triggers invalidate every changed member. Preserve exact original
identity/metadata/artwork/installation records and view membership during upgrade.

The additive v30 migration extends this same projection for current,
provenance-consistent ScreenScraper
`rawRomHashAndSize` results and IGDB `verifiedProjectId` results, using the shared
ownership validator. Raw results join the ordinary provider-game namespace;
verified projects use a distinct namespace and cannot join their base game.
Bind those assertions to the exact current edition/provider metadata identity,
not to equal filenames or container checksums. Reindex publication/correction
within the identity transaction; an indexed base dependency permits correction
of a linked original to invalidate project assertions without scanning all games.
Backfill existing current assertions additively, preserving exact records.
The refresh worker may consume an explicitly recorded `rawRomIdentifier` evidence
value in the existing typed identifier format; it never computes a remote hash or
promotes a provider-file checksum. Conflicting/malformed evidence cannot establish
a raw match. Verify real adapter-to-worker publication, grouping, correction,
query no-backfill and production upgrade/reopen before claiming this gap closed.
Assigned ordinary-game aliases also reject conflicting edition-level provider
IDs and translation assertions not explained by the reviewed `T-Eng` classification.
Keep the exact edition facts for review; correcting them reindexes grouping in
the existing transaction rather than discarding metadata or changing the file.

Release reconciliation preserves both reviewed game IDs and exact raw evidence.
ScreenScraper documents that `gameid` lookups omit ROM information. When an
explicit raw identifier is supplied, use the hash/size lookup instead, validate
every supplied hash and size, and cross-check any reviewed game ID against its
response. Exact compatible raw evidence may identify a revision-bearing edition;
an ID-only revision request remains unresolved rather than guessing from names.
Verify adapter -> persistent worker -> current metadata/grouping -> offline query,
including wrong hash/size/game/platform and conflicting region/language results.
No remote ROM-body reads or archive hash promotion are introduced.

### S4 aggregate-source assessment boundary

Metadata, lookup snapshots and artwork ownership bind the exact edition and the
owning provider's assigned IDs/manual assertions. An independently reviewed
second provider must not erase the first provider's verified facts or images.
All shared platform, artifact, raw-ROM, release, patch, classification and uncertain
evidence remains bound; unrelated provider assertions are not equivalence proof.
The v26 upgrade converts only still-current, full-identity v25 bindings in bounded
pages, without refreshing dates or promoting stale records. Canonical grouping
continues to use its complete identity projection; this does not supply source
precedence, cross-provider equivalence or ranking approval.

ScreenScraper remains the first candidate, not an approved ranking oracle. The
standalone IGDB adapter reuses the existing explicit RomM/IGDB platform mapping
and normal refresh/review worker. It retains IGDB's supplied `total_rating` and
`total_rating_count`, alongside separately labelled critic and community scores
and counts; it never computes a replacement average or chooses the largest score.
Title search yields review candidates, not approved ratings. Project scores need
a verified project ID and mod/fork classification, never a base-game ID.
Reviewed `T-Eng`/`Dub`/`Undub`/`Uncensor` editions may retrieve the verified
global original's facts, with original-game ownership rather than patch quality.
An explicit base relation must identify that same verified original on the same
platform and be revalidated in the publication transaction; unknown/contradictory
classification and a hack's base ID remain rejected. This does not approve Top.
Request-time application credentials and in-memory expiry-bound tokens remain
outside catalogues/exported configuration. Live access, the representative
reception comparison, source precedence and native secure setup remain S4/S5
acceptance work. No imported approval flag or successful image fetch enables Top.

### S4 effective overall-score boundary

Use one selector for cached card/detail scores and ranking eligibility. Select
one sourced overall, not the highest value or an average of provider components.
The application supplies benchmark-established source precedence and scope only
after META-05's live assessment passes; provider/import JSON cannot supply that
policy. The recorded IGDB community assessment supplies the initial production
basis, with no critic/total or unknown-count fallback. Each accepted basis retains its evidence
reference, original scale/kind, assessed platform coverage and assessed sample
support. Unknown counts require their separately recorded confidence assessment;
known counts below the assessed threshold cannot become ranked consensus.

Before acceptance, ordinary score display uses current ScreenScraper, identified
IGDB overall, then identified RomM overall in fixed order, with retained legacy
generations only after current records. A newer requested refresh for the same
edition/provider binding marks retained facts stale until current publication;
pending or blocked refreshes do not keep old scores ranking-eligible. Artwork
and unrelated providers do not supersede that binding. No age timer is used.
This order is display-only, not source
reliability approval. Accepted, supported sources take their assessed precedence
for both display and ranking. Omit uncertain identities/classifications and
conflicting provider IDs; label a verified original-game score on a known
translation/audio/restoration separately from a verified modification project's
score. Never qualify a hack using its base-game score.

Page-level cache reads are capped at 128 requested exact editions and revalidate
owning-provider identity bindings plus current catalogue bytes/removal inside one
SQLite transaction. The additive v27 edition/job index supports that generation
check without replacing stored facts or job progress. These reads do not establish
collection membership, canonical ranks
or filter intersection. The indexed collection-scoped Top/filter query, large
ranked fixture and native integration remain required S4 acceptance work.

### S4 indexed collection query

Keep a compact, rebuildable edition/facet/score projection, not copied artwork or
fixed Top lists. SQLite mutation triggers mark affected identities dirty; refresh
only dirty identities in bounded pages using the same effective-score selector.
Changing the application-owned assessment invalidates the projection. Actual
current cache rows establish membership, never provider search results. Rank
canonical groups within the selected system scope before intersecting tag,
genre, region/language, search or explicit view membership. Conflicting accepted
scores within a group remain unresolved rather than selecting a highest score.
Persist view-membership projections separately from favorites/shelf/installation
ownership; S5 will supply their existing authoritative state, not replace it.
Return bounded pages and pre-filter coverage, preserving source attribution and
stable identity ties. Additive migration preserves original metadata and settings.
Verify real SQLite mutation/reopen, source and edition ownership, no-backfill,
multi-disc/region grouping, sparse coverage and the indexed 30,000-game query.
These host checks do not replace reception assessment or native/UI acceptance.

The S4 native query/artwork resource entrypoint and its safety/measurement
contract are documented in [S4_NATIVE_VERIFICATION.md](S4_NATIVE_VERIFICATION.md).
It uses the same host assertions with Android's real database factory; writing
the entrypoint is not native acceptance and does not close the unexplained host
artwork wait. Obtain the user's requested Thor-testing handoff before deploying.

The focused `integration_test/metadata_ownership_test.dart` entrypoint reuses
the host provider/grouping assertions with Android SQLite: catalogue -> reviewed
lookup/retry -> exact metadata publication -> canonical grouping -> offline
query. It checks raw revisions, invalid identities, original/project ownership,
classification aliases and normal provider access recovery without production
source bootstrap or real accounts/ROMs. Native fixture results are distinct from
live API/reception assessment and S5's normal metadata controls; they cannot
approve a ranking source or substitute for those later real boundaries.

## S5 — Cover overlays, filters and unified metadata UX

Requirements: UI-01, UI-02, UI-03.
Depends on: S4 provenance/cache and S1/S2 setup states.

- Feed batched cached ratings into all shared-card callers, not network/database
  calls per frame or a library-only implementation.
- Add optional source-labelled overlays, stale/base-game labeling and accessible
  details/correction/refresh controls in existing screens.
- **S5-FORMAT-FALLBACK (UI-01, required, verification in progress):** replace blank
  unresolved covers with bundled stylized physical-media raster assets. Inspect
  licensed artwork first, then use the image-generation tool for one consistent
  family if a complete coherent family cannot be sourced. Do not hand-generate
  SVG/Canvas/code illustrations. Map known platform/media families explicitly;
  never infer the physical format from `.7z`, ZIP, CHD or the source provider.
  Keep a neutral fallback for unknown media, render immediately for loading and
  unavailable covers, and let a valid cover replace it. Verify offline behavior,
  mappings, compact/large grids, all badge/title/focus states and shared Library/
  console/shelf device behavior without extra network requests.
  Selected family (2026-10-04): colored **Systematic `-content.png`** media icons
  from [libretro/retroarch-assets](https://github.com/libretro/retroarch-assets/tree/b177f250e42948708e753d30809bd4dd9c0a2cdc/xmb/systematic/png),
  pinned to `b177f250e42948708e753d30809bd4dd9c0a2cdc`. Bundle only the required
  unchanged raster subset, with source/creator attribution and the upstream
  CC BY 4.0 notice. Do not use console/controller icons or import the theme's UI.
  Replace the generated app asset copies, inspect compact/large cards and rerun
  affected cover-state/offline checks before claiming the replacement verified.
  Complete per-platform cartridge/legacy-format coverage remains required in S9.
- Match review uses bounded cache-only pages of the newest outcome per exact
  edition/provider, including remaining outcomes from earlier full jobs after a
  one-game retry. Show the original platform/release context, candidate identity
  evidence and independent edition tags; require explicit selection/classification.
  Accept through the existing atomic correction/retry transaction and worker,
  never publish a candidate's score. Verify restart continuity, scope isolation,
  stale/foreign candidates, cancellation and normal controller/touch navigation.
- Exact-game settings also let an already matched game be reconsidered. Snapshot
  the current cache-row/edition binding and search without its disputed saved
  provider/base/raw identifier. Keep existing facts; even a confident result is
  offered for explicit review, not published automatically. Persist this job
  mode through pause/retry/restart, and verify the selected replacement through
  the normal worker. Subsequent ordinary refresh must retain the correction.
  Verify additive v31-to-v32 migration, rejected stale bindings and the normal
  touch/controller correction workflow with Android SQLite on the Thor.
- Wire the tested shared queries into existing filters: `Hack`, `T-Eng`, `Dub`,
  `Undub`, `Uncensor` and other content tags, any/all matching, genres, and dynamic
  Best rated 10/25/50/100/All within the user's collection with explicit scope,
  score basis and ranked coverage. Persist choices and support Clear filters.
- Preserve controller focus, touch, title/RA/favorite/platform/download badges and
  existing library tabs. Implement filters alongside overlays in this stage.

Evidence: widget/golden tests for badge collisions and score states; scrolling
with network disabled and measured request counts; actual handheld screenshots
and controller navigation proof, including combined filters and manual shelf
order. No burnt-in artwork or metadata-only ROM fetches.

## S6 — Final reconciliation and remediation

Requirements: QA-01, QA-02, QA-04; integrated recheck of S1-S6 requirements,
with final QA-04 reconciliation repeated after S7, S8 and S9.
Depends on: S1-S5, including all required live acceptance evidence.

- Re-read the full specification, not just this plan. Resolve every required
  blocker and tracked deferral; rerun the affected and integrated verification.
- Verify existing sources/config/queue/migrations and the combined on-demand
  workflow without a PC or RomM dependency. Verify cloud/read-only and save safety.
- Reconcile fresh metadata coverage and stale/unmatched handling after relaunch.
- Review security-sensitive paths, secret redaction and test/build resource use.
- Commit tested work and update the ledger. Release/deployment is a distinct
  authorized outcome; do not auto-publish an APK at each stage.

Evidence: requirement-by-requirement pass/fail for feature stages S1-S6 with
commands, fixture identifiers, source commit and device/build identity. S7,
S8 and S9 are still required before overall completion. Public evidence must not contain
private inventories or credentials.

## S7 — Live metadata pass and reviewed Thor migration

Requirements: MIGRATE-01; recheck META-01/META-05/META-07, DRIVE-04/05/06,
QA-02/03/04. Depends on: S1-S6 integrated acceptance and live provider access.

- Run the fresh full metadata pass and record real coverage/match/rating results.
  Establish defensible Top-25 retention per console; no fabricated scores or
  automatic deletion of unresolved games. Count canonical games, retain bundles.
- Prove Drive restoration on the Thor, inventory exact SD files and cloud
  IDs/version/digests, and build a private keep/remove/preserve manifest.
- Preserve saves/BIOS/settings, uncertain paths and files without identical
  recoverable cloud copies. Revalidate at execution; journal per-file results.
- Apply the exact reviewed removals only after recovery gates pass, ensuring
  external sync will not refill them and archival profiles remain unchanged.
- Verify retained sets, bytes/free space, save safety, and restore a removed
  test game via R-Shop before returning it to the intended retention state.
- Reconcile the entire specification including migration, commit verified code
  and sanitized evidence only. No public release is implied.

Evidence: bounded migration fault/restart/identity-change tests, private live
manifest, fresh metadata coverage, Top-25 retention audit, before/after space,
actual recovery proof and no unresolved S1-S7 blockers/deferrals. S8 and S9 remain
required before overall completion.

## S8 — Per-ROM dual-display companion launching

Requirements: COMPANION-01; recheck CORE-02, DRIVE-06, QA-02/03/04.
Depends on: S1-S7 acceptance and the established ordinary emulator handoff.

- Inspect Cocoon Launcher's source/revision/license at stage entry, then verify
  the relevant Android display-launch behavior on the Thor. Do not add a general
  launcher rewrite, APK downloader or companion marketplace.
- Persist an optional installed companion package/activity per stable ROM/edition
  identity. Add select/change/clear controls to existing game settings/details;
  preserve independent associations through restart and catalogue refresh.
- Route the ready ROM/emulator to the actual top display and its linked app to
  the bottom display. Preserve URI grants, ordinary launch and save/settings
  state; do not require ADB/PC, timers or killing unrelated applications.
- Verify missing/unlaunchable apps, display absence/placement rejection and repeat
  activation without false paired-launch success or duplicate launches.
- Prove two independently linked ROMs and actual top/bottom placement with
  controller/touch on the Thor, then switch both displays off.
- Reconcile the revision-5 requirements delivered through S8, including S7
  migration. ART-01 belongs to the final S9; no S8 criterion is waived. Verify
  and commit completed scope. Publication remains separate.

Evidence: persistence/identity and native launch contract tests, Cocoon source and
license review, actual Thor display-placement/controller proof, failure-path and
ordinary-launch regression evidence, save/settings preservation and final
S1-S8 reconciliation with zero unresolved required blockers/deferrals for those
stages. Overall completion still requires S9.

## S9 — Final cartridge and legacy-media visual coverage

Status: NOT STARTED.
Requirements: ART-01; recheck UI-01 and QA-04.
Depends on: S1-S8 acceptance. This is the last stage, not a second ACTIVE stage.

- Inventory the then-supported cartridge consoles and their actual physical
  shapes, plus older game cards, floppy sizes/types and cassette formats.
  Create the evidence-backed platform/format/asset matrix; shared correct shapes
  need not be duplicated per console. Unknown/mixed releases stay honest.
- Review every mapped asset for recognizability and consistency. Generate/source
  additional raster artwork only for observed gaps, using the existing style
  anchor and recording provenance. No manually generated SVG/Canvas/code art.
- Verify bundling/decoding/mappings and the normal compact/large cover states,
  cover replacement and badges/focus on the Thor; preserve settings/ROMs and
  switch both displays off after testing.
- Resolve every ART-01 gap, reconcile all S1-S9 requirements, perform applicable
  final verification and commit. No publication is implied.

Evidence: complete format/asset matrix, zero unfilled supported cartridge or
legacy-format gaps, asset provenance, inspected renders and native behavior,
full-spec reconciliation with zero unresolved required blockers/deferrals.

## Source extension map (baseline, not implemented classes)

| Area | Existing entry points | Required consideration |
| --- | --- | --- |
| Source registration | `lib/models/config/source.dart`, `provider_config.dart`; `lib/services/provider_factory.dart`, `source_resolver.dart`, `source_provider.dart` | Both source/config layers and UI must recognize Drive |
| Native auth | `android/app/src/main/kotlin/com/retro/rshop/MainActivity.kt`; Android build/config | Dedicated adapter with signer/account-aware authorization |
| Catalogue | `lib/services/unified_game_service.dart`, `library_sync_service.dart`; `lib/models/game_item.dart` | Stable identity and transactional refresh, not name-only merging |
| Transfer | `lib/services/download_handle.dart`, `download_service.dart`, `download_queue_manager.dart`; `lib/utils/file_utils.dart` | Request-time auth, validated resume, journaled publication |
| Installed files | `lib/services/rom_manager.dart`; `lib/providers/installed_files_provider.dart` | Exact ownership; existing folder-name deletion is not a safe contract |
| Metadata | `lib/models/game_metadata_info.dart`; `lib/services/database_service.dart`, `providers/romm_provider.dart`, `romm_api_service.dart` | Currently one nullable rating imported from RomM |
| Artwork | `lib/services/thumbnail_index_service.dart`, `thumbnail_service.dart` | Existing Libretro covers are distinct from a rich metadata scraper |
| Card data/UI | `lib/providers/game_providers.dart`; `lib/widgets/base_game_card.dart`; `lib/features/library/library_screen.dart` | Cached scores must reach every card caller |
| Filters | `lib/features/game_list/logic/filter_state.dart`, `game_list_controller.dart`; `lib/features/library/library_screen.dart` | Existing filters are separate; share metadata query semantics before adding UI controls |
| Details | `lib/features/game_detail/widgets/game_info_card.dart`, `metadata_badges.dart` | Explain source/scale/staleness and modified-game identity |

### S1 switch and identity-boundary inventory

The 2026-09-08 review found 27 source/provider enum switches across 14 files.
S2 must update both configuration layers, not merely add a provider enum value:

- Models: `models/config/source.dart`, `provider_config.dart`, `app_config.dart`.
- Services: `config_parser.dart`, `source_resolver.dart`, `sources_notifier.dart`,
  `provider_factory.dart`, `remote_folder_scanner.dart`.
- UI/shared presentation: `core/util/source_color.dart`,
  `features/settings/sources_screen.dart`,
  `features/sources/manual_source_add_screen.dart`, and onboarding's
  `widgets/welcome_chooser_step.dart`, `widgets/provider_form.dart`,
  `onboarding_state.dart`.

Also update source health and persisted folder-ID corrections. `GameItem` and
`DownloadItem` currently lack exact artifact references. The existing
`UnifiedGameService` and `GameMergeHelper` merge filenames, the game cache has
`UNIQUE(systemSlug, filename)`, and queue IDs use system name plus filename.
These are **required integration changes**, not equivalence evidence for Drive
files. Preserve scoped IDs through all of them. A failed/incomplete refresh must
not reach `LibrarySyncService` as a complete orphan-deleting snapshot.
`DownloadService.resolveDownload` is the existing request-time authorization seam.
The new standalone models/store do not by themselves satisfy those runtime gates.

## Verification operating procedure

During implementation, discover the installed Flutter SDK before using it. Do
not install/upgrade a toolchain merely to claim the preparation is complete.
Capture existing failures before changing behavior. Run targeted tests first,
then the relevant integration/regression suite as one workload, for example
`flutter test --concurrency=1`. Await its real process completion. Inspect output
before starting a new workload; use bounded fakes instead of infinite providers.
`flutter analyze` and native authorization/storage tests are separate evidence.
Build and device success cannot be inferred from a source review or a unit test.

## Requirement-to-stage map

Each requirement has one delivery owner; dependent stages must still maintain it.

| Requirement | Owner | Acceptance evidence |
| --- | --- | --- |
| CORE-01 | S1 | File/metadata/residency isolation tests; combined S6 proof |
| CORE-02 | S1 | Identity/platform/variant fixtures |
| CORE-03 | S1 | Existing-state migration/restart fixtures |
| DRIVE-01 | S1 | Native auth, account isolation, read-only and redaction proof |
| DRIVE-02 | S2 | Paginated rooted catalogue and failed-refresh tests |
| DRIVE-03 | S2 | Normal source UI and mixed persistent queue tests |
| DRIVE-04 | S3 | Range/version/checksum and large-file resource tests |
| DRIVE-05 | S3 | Cancel/crash/publication lifecycle recovery tests |
| DRIVE-06 | S3 | Ownership, bundles, saves and live reinstall proof |
| META-01 | S4 | Fresh generation ignores old cache; explicit coverage outcomes |
| META-02 | S1 | Legitimate standalone provider setup and live lookup |
| META-03 | S4 | Match/correction/container-hash fixtures |
| META-04 | S4 | Hack/T-Eng/Dub/Undub/Uncensor tags and base-score isolation tests |
| META-05 | S4 | Provenance/scale/null/count tests, reception benchmark, low-vote outlier and source-remediation gate |
| META-06 | S4 | Quota/offline/resume/30,000-game bounded job tests |
| META-07 | S4 | Shared paged query; dynamic overall-score Top; any/all tags intersect ranks without backfill; grouping and scope tests |
| UI-01 | S5 | All shared-card callers, widget/golden and device proof |
| UI-02 | S5 | Setup/refresh/details/controller acceptance |
| UI-03 | S5 | Integrated Top/category/genre filters, scope, persistence and controller proof |
| QA-01 | S6 | One-workload, deterministic lifecycle and resource evidence |
| QA-02 | S6 | Existing-provider regressions and combined live workflow |
| QA-03 | S1 | Privacy/authorization/signing gates, rechecked at S6 |
| QA-04 | S6 | Full-spec reconciliation; no unresolved required gaps |
| MIGRATE-01 | S7 | Fresh live scrape, defensible Top-25 sample, exact cloud-verified removals and Thor restore/space/save proof |
| COMPANION-01 | S8 | Per-ROM association persistence/isolation; live ROM-top/APK-bottom launch, failure paths and ordinary-launch/save-safety regressions |
| ART-01 | S9 | Complete supported cartridge/legacy-format asset matrix; consistent accurate shapes, raster provenance, bundled mapping checks and Thor visual/cover-state proof |
