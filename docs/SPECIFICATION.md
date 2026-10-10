# Google Drive, metadata expansion, companions, save backups and managed ROM cache

Authoritative specification, revision 17, 2026-10-10.

Status: implementation authorized on 2026-09-08; acceptance tracked in the ledger.
Upstream baseline: `AverageConsumer/R-Shop` at
`d615f87277617cbf3a12a6445b3c71d42cf72539`.

## 1. Objective and authorization

Turn R-Shop into an on-demand browser for a private cloud ROM library: inspect
games and their fresh metadata, install selected games locally for ordinary
emulator use, and remove owned local installations manually or through the
configured managed-cache policy without changing cloud originals or saves.
The primary target is an Android handheld with an
SD card (AYN Thor); existing R-Shop sources must remain usable.

The user authorized implementation after preparation with "go ahead then" on
2026-09-08. Implement and verify the two features through the staged plan.
Google and ScreenScraper access are entirely new setup; do not assume existing
credentials. Account consent remains user-controlled. Required live tests and a
fresh metadata pass are part of acceptance; no release is authorized. The user
also requested a final live SD-library migration retaining a small offline
sample: Top 25 games per console. That migration remains a one-time reviewed
operation; the separately authorized CACHE-01 now covers ongoing cache rotation.
Neither operation permits modifying the cloud archive.

Scope extension authorized on 2026-10-02: add S8 for per-ROM companion launching
on the Thor, with the ROM/emulator on the top display and its linked Android
application on the bottom display. Review Cocoon Launcher's source and reuse
terms when S8 starts; do not begin that implementation during earlier stages.

Scope extension authorized on 2026-10-04: add a final S9 visual-coverage audit
for every supported cartridge console and older floppy/tape/card formats. It is
not a prerequisite for earlier functional stages. Generate additional accurate
physical-media shapes as needed, using the established raster style, rather than
preemptively generating a complete console-art catalogue during S5.

Scope extension authorized on 2026-10-05: implement emulator save-backup sync
inside R-Shop, rather than relying on FolderSync's limited emulator coverage.
Add S10 after the existing stages; S7 remains the sole ACTIVE stage. Leave
FolderSync installed and its existing folder pairs/schedules unchanged. This
authorizes the separate SAVE-01 backup feature, not SD-card mirroring or writing
to the ROM archive. Actual backup setup and additional Google consent remain
explicit in the normal app workflow; no cloud backup is initiated by this spec.

Conditional handover authorized on 2026-10-07: once R-Shop's replacement save
sync satisfies SAVE-01's native backup/restore and installed-emulator coverage
criteria, uninstall the old device sync app (user calls it "Drive Sync"; identify
the actual package rather than assuming FolderSync) and stop/disable the laptop
scheduled task whose action invokes `sync-retrobat-saves.ps1`. This supersedes
the earlier keep-installed rule only at that verified handover. Until then,
preserve both mechanisms unchanged. Preserve saves, cloud backups, unrelated
tasks/apps and the laptop script; no ROM/SD mirroring is authorized.

Scope change authorized on 2026-10-07: indefinite accumulation of on-demand ROMs
conflicts with the user's anti-littering/SD-space objective. Add configurable
managed cache persistence and rotation to the existing Settings panel, including
a persistence time window, rotation queue and unified or per-console scope.
This explicitly supersedes the former exclusion of automatic ROM eviction,
subject to CACHE-01's ownership, recovery and protection safeguards. S11 owns this
feature after S10; S7 remains the sole ACTIVE stage. Its pending implementation
does not excuse or alter any S7 migration/recovery acceptance criterion.

User decisions incorporated:

- Shared metadata persistence and ES-DE integration (2026-10-05): keep expensive
  scraped facts and artwork in durable, user-selected shared storage, reusable
  without ES-DE being the main launcher. Refresh from the remote catalogue even
  when ROMs are absent locally, and keep compatible ES-DE metadata current.
  Credentials remain private; this does not authorize Drive writes, ROM stubs,
  importing old scores as fresh evidence, or changing ES-DE user settings.
- Google Drive and metadata expansion are the two features.
- Per-ROM dual-display companion launching is the additional S8 feature.
- Emulator-aware save/save-state backup is the additional S10 feature. ROM
  catalogue/download access remains read-only; narrowly scoped backup writes are
  a separate opt-in capability, never a general Drive write permission.
- Physical-media fallback selection (2026-10-04): use Systematic's colored
  `-content.png` raster icons from libretro/retroarch-assets, pinned to
  `b177f250e42948708e753d30809bd4dd9c0a2cdc`. Only game-media icons are selected,
  not console/controller icons or the theme's fonts/backgrounds/UI styling.
  Retain required source/creator attribution and the upstream CC BY 4.0 notice.
  Keep the existing S5 verification gates and final S9 coverage audit; selecting
  a theme is not evidence that its app integration or complete mapping passes.
- Use the supplied standard ScreenScraper account; do not require the user to
  obtain a developer account. Verify actual provider access rather than assuming
  missing developer fields alone prove that access is blocked.
- After provider-side application-authentication rejection was verified, the
  user authorized handling the legitimate fork API application request through
  the logged-in ScreenScraper account and updating the ignored local environment
  file when credentials are issued. Approval does not itself prove API access.
- A desktop PC, RomM server, or public Drive sharing link must not be required.
- Historical scraped metadata is outdated. A complete fresh scrape is required;
  importing an old `gamelist.xml` is not a substitute.
- Reuse sourced review scores and add cover overlays; do not invent a new
  popularity/ranking formula. Include metadata-backed Top-N and content filters
  in the same implementation: the user's overlay suggestion was not an instruction
  to defer filters that naturally share the metadata foundation.
- Calculate Top-N dynamically from the overall game scores present in the user's
  current collection, not static curated lists or a provider's global catalogue.
  Top 25 means membership among that scope's best 25 games: calculate rank before
  tag/search/installed filters, then intersect. Do not backfill lower ranks.
- The ranking input must credibly reflect wider critical/community reception.
  Download counts, a handful of extreme votes or picking the highest available
  provider score do not establish that a title belongs in the Top.
- `T-Eng`, `Dub`, `Undub` and `Uncensor` are separate, combinable tags alongside
  `Hack`; none of them grants automatic extra membership outside a Top limit.
- Hacks and translations need correct identities and classification, not the
  original game's rating silently presented as their own.
- Cloud archival selection, browsing filters, and device residency are different
  policies. This work must not change existing archive/device Top lists.

## 2. Scope and architectural boundaries

Keep the upstream Flutter/Riverpod UI, source configuration, queue, and SQLite
cache. Add Google Drive through the normal Sources workflow, not a separate shop
or console catalogue. Introduce an independent metadata-provider layer usable by
Drive, local, Web, SMB, FTP, and RomM-backed games.

```text
Drive / existing file providers -> file catalogue -> game + edition identity
                                                        |
ScreenScraper / existing RomM adapter -> metadata store --+-> shared cards/details
                                                        |
selected files -> persistent transfer -> verification -> owned local installation
```

These are boundaries to implement, not a requirement for a service or class for
every box. Prefer small extensions of existing code where the contract permits.

### Core records

- `RemoteArtifact`: source/account identity, provider file ID, parent ID,
  display path/name, size, modification/version information, provider checksums,
  download capability. An expiring URL is not an identity.
- `GameIdentity` and `EditionIdentity`: canonical platform, game/provider IDs,
  release/region/language, content tags, base-game relationship when relevant,
  revision/patch identity, disc/bundle members, match evidence/confidence.
- `MetadataRecord`: identity, field provenance, provider ID, fetch time, refresh
  generation, match status, descriptions/artwork/genres/date/credits and scores.
- `Rating`: source label/ID, original value and scale, nullable vote count,
  normalized display value, score kind, retrieval time. Unknown stays unknown.
  A game's effective overall rating references one eligible sourced overall score
  and is shared by its overlay, details and dynamic Top query.
- `TransferRecord`: source version/checksum, exact artifact and destination,
  stage path, durable offset, lifecycle state and error; never persisted tokens.
- `InstalledArtifact`: exact owned paths, game/edition members, verified hashes,
  source reference and installation state. Library presence is not ownership.

Proposed names may change during implementation; these distinctions may not.

## 3. Shared requirements

### CORE-01 — Separate files, metadata, and device residency

Browsing and scraping must work for remote games without downloading ROM bodies.
Metadata failures must not block browsing or downloading already identified files.
Removing a local install must leave the remote library entry, metadata, favorites,
and remote source intact. No bulk mirroring is introduced. Automatic local ROM
eviction is confined to the explicitly configured CACHE-01 policy; browsing,
scraping and filtering do not themselves authorize it.

Acceptance: a remote-only game can be scraped and browsed with zero ROM payload
requests; it remains visible after removal of its local installation.

### CORE-02 — Exact identities and platform mappings

Persist provider IDs, not just cleaned filenames. Map folder aliases to canonical
R-Shop systems using explicit, testable mappings and user-correctable assignments.
Duplicate filenames across folders/accounts must remain distinguishable. Group
region/revision/disc variants without merging distinct games, hacks, or patches.
Unknown platforms and ambiguous matches must be visible, not silently guessed.

Acceptance: fixtures cover Nintendo/Sony/Sega/Microsoft folder aliases, duplicate
names, two regions, two discs, a translation and a same-base hack. Only systems
actually supported by the app become active; unsupported mappings are reported.

S7 catalogue eligibility detail (2026-10-08): a normally mapped console's
descendant `Patches` folder declares patch resources, not playable game entries.
The live collection exposed 32-byte palette `.bin` files in patch source trees
being counted and scraped as Mega Drive games. Exclude that resource subtree
from the console's game projection using actual published folder IDs/ancestry,
not display-path splitting, numeric-title rejection or a global `.bin` ban.
Keep the complete published Drive snapshot and all cloud/local files unchanged.
The explicitly selected mapping folder is the boundary: selecting a folder
inside such a subtree deliberately establishes a new scope; an ancestor outside
that mapping must not silently exclude it. Ordinary Hacks/T-Eng folders and
genuine numeric ROM filenames remain eligible. A folder with a slash in its
Drive name is not two folders. Saved metadata jobs retain their captured members,
requests and outcomes; later normal cache reconciliation does not rewrite them.
Verify real SQLite provider traversal, nested/paged resource trees, explicit
mapping boundaries and normal native refresh without ROM-body requests/deletion.

### CORE-03 — Compatible migrations

Migrate current config, SQLite metadata, queue, favorites and installed references
without dropping existing sources or user selections. A legacy anonymous rating
may be retained as legacy/stale data but cannot count as a fresh verified score.
Removing a provider or revoking access must not delete local games or saves.

Acceptance: migration/restart fixtures preserve upstream records; old ratings do
not satisfy a fresh scrape or acquire invented provenance.

## 4. Feature A: Google Drive

### DRIVE-01 — Native, read-only account authorization

S7 token-lifecycle detail: retain a successful account-bound read-only grant only
in process memory. Background Drive operations must not repeat native scope
authorization while that grant remains usable. Check the connected account before
reuse; retire the grant on explicit interactive connection or sign-out, and renew
on a real API token rejection. Concurrent rejection of an older token must not
retire a newer successful grant. Do not persist credentials, add timer-based token
leases, bypass consent or silently select another account.

Cold process restart and signer-preserving app updates must restore authorization
for the previously explicitly selected Android account without opening account
selection. Persist only its private account ID/email reference, scoped to the
OAuth client, not authentication/authorization tokens. Use account-bound native
authorization with prompting disabled; a missing reference, revoked consent or
account mismatch requires explicit connection. Explicit sign-out/revocation clears
the reference so restart cannot resurrect the disconnected selection. This
clarifies DRIVE-01 session continuity, not permission to persist bearer tokens.

Authorization-service/network unavailability is not evidence of missing consent.
Preserve the saved account reference and report a retryable service failure,
not "Reconnect in Sources". Only an actual interaction/setup/account-selection
requirement enters the authorization-needed queue state. Do not hide outages
by clearing credentials, initiating consent automatically or adding timed retries.

Use native Android Google authorization behind a Flutter adapter and Drive API
v3. Support account selection, sign-out/revocation, token renewal and an explicit
reauthorization state. Do not persist bearer tokens in catalogues, exported config
or queue records. Do not borrow another application's OAuth client or secrets.

For an existing personal library use `drive.readonly`. Explain that this grants
account-wide read access: the selected library folder is an app-enforced boundary,
not a folder-scoped OAuth permission. `drive.file` must not be represented as
automatically granting every existing descendant of a selected folder.

Acceptance: consent/decline, renewal, revoked access and offline two-account
isolation tests; native live authorization evidence before feature completion.
On 2026-10-04 the user explicitly waived the live second-account isolation check:
do not require adding another account to a device or the Google project, and do
not let that check block delivery. Offline isolation contracts remain required.
This waiver is not live isolation evidence. ROM catalogue/download operations
invoke no Drive mutation methods. SAVE-01 separately defines the only authorized
backup-write boundary; it does not expand the ROM source's permissions.

### DRIVE-02 — Folder selection and paginated catalogue

Provide a native-app folder-selection flow and explicit per-console mappings.
Opening the mapping editor preserves existing assignments and empty selections.
Unique observed folder aliases are passive suggestions, not selected mappings;
saving one explicitly chosen console must not enable other suggested consoles.
Verify unchanged save, explicit addition, clear/cancel and preservation of other
sources' mappings through the normal configuration write path.
Enumerate the selected personal My Drive subtree using IDs and pagination; allow
nested folders. Do not traverse the whole account or read file bodies for indexing.
Persist a refresh checkpoint and publish a new catalogue snapshot only after a
successful traversal. An interrupted/error refresh must not look like an empty
library or remove existing entries. Reflect renamed/moved/deleted entries on a
successful refresh without changing existing installed files.

S7 traversal implementation detail (2026-10-06): next-folder scheduling retains
durable insertion order, exact scope/generation and the saved page cursor. Use
the pending-work index and a work-first lookup rather than scanning/sorting the
whole catalogue for each folder. Existing databases receive the additive index
without resetting active/pending generations or changing entries/checkpoints.
Publication and final folder-boundary validation remain unchanged.

S7 publication transport detail (2026-10-07): recheck every observed folder in
bounded Drive v3 metadata batches of at most 100 exact IDs. Use the documented
fixed-origin batch endpoint with read-only inner GETs, bounded response bytes,
exact response-ID reconciliation and the existing account/cancellation rules.
Every folder's identity, name, parent and supported-folder status must still
match; missing, changed, malformed or failed replies prevent publication. Keep
the current generation/cursors and old published snapshot on interruption.
Batching reduces HTTP round trips, not quota usage, and supplies no subtree
snapshot transaction or file recovery/removal authority.

S7 published-catalogue query detail (2026-10-07): root pages use the indexed
scope/generation of the validated traversal snapshot, excluding its root record,
without rebuilding the descendant tree for every page. Subfolder pages still
traverse only that folder's descendants, using an indexed parent lookup for each
visited folder and an exact file lookup for returned records. Preserve published
generation checks, supported-root validation, ordering and page boundaries. This
also applies to the existing source exclusion report and folder-mapping reads;
it does not infer membership across sources or unpublished generations.

Expand only actual folder rows in that recursive walk. Select the bounded,
ordered child-entry page from those folders, including nested folders and binary
files in the same existing order. ROM leaves cannot have children and must not
inflate recursive expansion work. Verify the actual production CTE's expansion
count on a dense multi-folder fixture, alongside returned pages and query plans;
this optimization must not change membership or introduce a latency timeout.

First scope: ordinary binary files in a selected personal My Drive subtree.
Shared Drives, Workspace document export and shortcut traversal are not supported
initially; surface them explicitly instead of following them outside the root.

Acceptance: multi-page/nested fixtures, duplicate names, rename/move, deleted file,
lost access and interrupted refresh; no root escape or false deletion on failure.

### DRIVE-03 — Normal queue integration

Drive must appear alongside existing sources in setup, source badges, connection
health, catalogue refresh and the existing persistent download queue. Retain queue
ordering/concurrency controls. Token resolution occurs at request time and on
authorized renewal, not by saving an authenticated download URL. Avoid alternate
provider fallback unless exact artifact identity is established.

Acceptance: enqueue/reorder/restart/cancel with mixed existing and Drive sources;
no provider choice or special console menu is needed to use Drive files.

### DRIVE-04 — Verified, resumable streaming

Use binary media downloads and bounded streaming buffers (at most 4 MiB of
application transfer buffers per active stream; no whole-ROM buffering).
Persist resumable bytes only on the Android device in app-owned staging excluded
from emulator/library scans. Prefer staging on the destination volume; measure
actual peak space when a cross-volume copy is unavoidable. Never create partial
files in Google Drive or the host archive.

Append only when artifact identity/version still matches and the HTTP range
response starts at the durable offset with a consistent total. A changed source,
wrong range, ignored range, truncation or checksum mismatch must not produce an
installed game. A full-response restart must explicitly discard the old partial
for that transfer, never concatenate it. Check available size and provider checksum
before publication; absent trusted checksum is a visible verification blocker,
not silently equivalent to verified. Compare source metadata again to detect
mid-transfer changes. Compute hashes by streaming.

Acceptance: valid resume, HTTP 200/206/416, wrong range, truncated response,
changed source, missing/mismatched checksum and restart/crash fixtures; a large
file test demonstrates bounded buffers independent of ROM size.

### DRIVE-05 — Durable lifecycle and truthful completion

Represent queued, transferring, paused, awaiting authorization, verifying,
publishing, completed and failed states explicitly. Cancellation waits for
resource shutdown and durable checkpointing; late callbacks cannot publish after
cancellation. Reconcile an interrupted publication from durable state, rather
than declaring success from filename existence alone. Keep an old valid target
until its replacement is verified and safely published. Use atomic rename only
where the filesystem actually supports it; otherwise implement a journaled
publication protocol and verify recovery on the target storage API.

Acceptance: cancellation at transfer/verify/publish boundaries, process death,
relaunch, existing-target collision and cross-volume recovery tests. Completion
appears only after installed-state commit; cancellation does not rely on sleeps.

### DRIVE-06 — Usable, save-safe local installations

S7 mixed-catalogue integration detail (2026-10-07): download availability belongs
to the exact selected entry, not its console's configured providers. A missing
local cache row without a source is unavailable; never borrow a namesake's
provider or Drive identity. Keep installed local management available. In mixed
variant pickers, touch/controller selection must queue only variants with their
own source; unavailable variants stay visible and explicitly labelled. Drive
entries also require the exact artifact and must respect a declared denial of
download capability. A missing source must not create a failed queue item.

Install already emulator-ready files supported by the mapped system (including
CHD/RVZ/WUA where supported). Do not add Android media conversion. Preserve
multi-disc/bundle dependencies and playlists using safe relative paths; no bundle
is marked ready while a required member is missing. Unsafe or unsupported archive
layouts are reported, not installed optimistically.

Manual local removal is explicit; automatic removal requires a configured
CACHE-01 policy. Both are limited to installation-manifest-owned ROM paths.
Revalidate file identity against the installed manifest immediately before removal;
ownership recorded in the past is insufficient if another app replaced the file.
Preserve changed or ambiguous files and report a conflict. Reject path escapes and
links that would redirect a removal outside the recorded installation boundary.
Do not recursively delete a guessed game folder or delete saves, emulator
configuration, BIOS, unrelated files, or cloud originals. Existing unmanaged
files require deliberate adoption with identity checks before managed removal.
Show the planned files and space reclaimed. Do not apply LoLSuite device-sync
retirement rules to R-Shop installations; document how to avoid an external sync
refilling an intentionally removed on-demand game.

S7 adoption detail (2026-10-06): the existing exact-byte review may explicitly
adopt one supported, standalone emulator-ready file after a new current
local/cloud comparison. A saved observation alone cannot adopt it. Close native
reads, recheck the public identity, then atomically record the exact installation
and target owner with explicit adoption provenance; do not pretend a download,
stage creation or rename occurred. Conflicting owners, changed bytes, cancellation
before commit and failed commits preserve the unmanaged file without an ownership
claim. Bundles and archive extraction remain outside this single-file route.
S7 archive recovery detail (2026-10-06): a Game Gear ZIP may be treated as one
emulator-ready file only through the explicit Game Gear mapping and a validated
single safe `.gg` member. Preserve the exact cloud archive bytes and filename;
do not extract or rename it to a guessed ROM extension. Validate its bounded
ZIP structure, matching local/central headers, member size and CRC before
publication/adoption, on recovered publication and before emulator handoff.
Reject encrypted, multi-member, unsafe-path, ZIP64 and malformed layouts.
Persist the explicit archive platform in the immutable transfer intent; old
untyped archive intents cannot silently acquire format approval. Prove the
normal queue -> verified installation -> existing RetroArch core -> offline
use -> exact removal/re-download workflow before this format permits migration.
The RetroArch route uses a document-shaped read-only grant for the single owned
ZIP leaf, retaining its filename through RetroArch's SAF VFS. It grants neither
directory/prefix/persistable access nor writes; root, sibling and nested document
requests are rejected. The existing installation and pinned-object checks remain
mandatory at every open. Other emulator URI routes remain unchanged.
Adoption does not delete anything or waive MIGRATE-01's ranking, format-restore,
save/sync and execution-time revalidation gates. Reuse the existing verified owned
installation/removal path rather than introducing an alternate deletion engine.

S7 observed Sega ZIP recovery detail (2026-10-08): the existing SD inventory also
contains Mega Drive, Master System and SG-1000 single-cartridge ZIPs. Current
read-only directory checks and one native listing per console confirm `.md`,
`.sms` and `.sg` members respectively. Extend the existing bounded ZIP validator,
exact transfer/publication, separate read-only observation and RetroArch grant
route for these explicit platform/member pairs, retaining its single-member,
path/CRC/size/layout checks and work budgets. Reuse the installed Genesis Plus GX
core without changing its settings, installing a core or treating 32X as supported
by that core. A ZIP suffix alone never supplies the console mapping. Raw-member
identifiers may serve fresh metadata matching only after the complete local
container matches the current Drive artifact; they never prove cloud-container
equivalence or grant ownership. Verify normal online/offline/identical-restore
workflows on the Thor before claiming these format gates satisfied. Bundles,
unknown members, current cloud readability, retention and removal gates remain
unchanged. This is required MIGRATE-01 format integration within S7, not S8 work.

S7 N64 archive recovery detail (2026-10-06): explicitly mapped standalone N64
7z/ZIP files may retain their exact archive bytes and filename when validation
finds exactly one safe `.z64`, `.n64` or `.v64` member with matching N64 byte-order
signature. Reuse the owned installation and exact document-leaf RetroArch grant,
using the installed Mupen64Plus-Next core. Do not extract, convert or mutate ROMs.
For 7z, admit only single-stream COPY/LZMA/LZMA2 layouts, plain or encoded headers,
with bounded metadata, dictionary and decompression work and verified CRCs. Reject
encryption, multiple members/streams, unsafe paths, unsupported filters, malformed
ranges and trailing data before installation. Valid single-LZMA RomVault archives may contain the
documented 32-byte `RomVault7Z01`/`RomVault7Z02` structured metadata block immediately
before the encoded next header. Admit it only when its CRC, absolute header
position and header size exactly agree with the validated signature/next header;
do not ignore arbitrary gaps or add trailing-data tolerance. This preserves the
requested source archive bytes, rather than repacking an otherwise valid archive.
ZIP keeps the existing strict
single-member layout rules. Persist `n64` as immutable archive mapping, never infer
approval for legacy untyped archives. Host validation is not live recovery proof:
the normal queue/offline boot/removal/re-download gate remains required before
this format can permit migration.

S7 Game Boy recovery detail (2026-10-07): extend the existing owned archive route
to explicitly mapped standalone `gb` 7z files, with one safe `.gb` member within
the existing 16 MiB streamed validation budget. Preserve the exact archive bytes
and name; do not extract, repack or infer approval for ZIP, GBC, GBA, bundles or
legacy untyped transfers. Validate the pinned object before publication, recovery
and each handoff using the existing complete stream/CRC and namespace checks.
Persist `gb` in the immutable transfer intent. Use the exact read-only document
leaf grant and installed RetroArch SameBoy core; no directory/prefix/write or
persistable grant. Prove normal queue download, actual online and fresh offline
boot, exact owned test removal and identical re-download in an isolated target.
Preserve original ROMs, saves, BIOS and emulator settings. Metadata identification
alone does not satisfy this independent restoration requirement or authorize SD
removal; every MIGRATE-01 ranking/current-byte/review gate remains applicable.

S7 SNES archive recovery detail (2026-10-07): explicitly mapped standalone SNES
7z files use the same bounded single-member decoder and exact owned document
leaf. Require one safe `.sfc` or `.smc` member, complete stream/CRC checks and the
existing 16 MiB raw budget. Preserve all raw bytes, including any copier header;
do not normalize, repack or invent a universal SNES magic/header test. Container
validation establishes bounded readable bytes, not game identity or bootability.
Bind streamed raw digests to the current cloud container for normal metadata
identification. Persist `snes` in the immutable transfer intent, require the exact
console mapping, and revalidate before publication, adoption and offline open.
Use RetroArch's Snes9x core through the existing read-only owned leaf route.
Prove normal download, actual online/cold-offline boot, exact owned removal and
identical re-download in an isolated destination before migration approval.
ZIP, multi-member MSU/PCM bundles and untyped transfers are not approved by this
single-ROM path. Preserve original ROMs, saves, BIOS, settings and unresolved
bundles; all MIGRATE-01 ranking/current-byte/review gates still apply.

Acceptance: download -> verify -> open in existing emulator -> offline use ->
explicit local removal -> re-download; multi-disc, replaced-owned-file,
redirected-path and save-preservation fixtures,
plus an actual target-device proof using a user-authorized test artifact.

## 5. Feature B: independent metadata and cover ratings

### META-01 — Fresh full scraping, not a historical import

Provide fresh full-library, per-system, per-game and failed/unmatched retry jobs.
The first full pass operates on a stable catalogue generation and fetches current
provider data for every game identity, including games not installed locally.
Old `gamelist.xml` scores/descriptions must not seed the new trusted baseline or
let items be skipped. Existing old files remain untouched; no destructive purge
is needed to create a new metadata generation.

Acceptance: seed a legacy cache, run a fresh job, and prove every eligible identity
was requested or has an explicit unresolved/setup/error outcome. Report requested,
matched, ambiguous, unmatched, failed and rated counts separately. Finished
traversal does not mean all games have metadata or reliable ratings.

### META-02 — Real standalone provider access

Implement ScreenScraper as the initial independent metadata provider, retaining
the existing RomM integration as an optional adapter. RomM is not a dependency.
Supply descriptions, genres, release information, developer/publisher, artwork,
screenshots and ratings where returned. Model provider capabilities and platform
IDs explicitly; missing data must remain missing. No hardcoded score dataset,
HTML challenge bypass, or scraping of a user's historical browser state.

Use the user's supplied standard ScreenScraper credentials; a developer account
is not a user prerequisite. Provider application authentication, if enforced by
the API, remains a distinct integration responsibility: verify the standard-account
route and resolve legitimate application access without extracting/reusing
RetroBat's credentials or claiming a rejected request succeeded. A provider-side
rejection must identify the exact failing boundary, not imply the user's standard
account password is wrong. Keep user credentials in secure storage and any
application configuration out of version control. Redact query-string credentials
from all HTTP logs and errors. Do not claim secrets embedded in a distributed
APK are confidential; distribution policy must be resolved before release.

Acceptance: authenticated live lookup with the fork's legitimate API access;
offline fixture contract tests, bad credentials and unsupported-platform behavior.

S7 platform detail (2026-10-08): the authenticated `systemesListe.php` response
explicitly lists Nintendo DSi/NDSi/DSi as common names for provider platform 15.
Map R-Shop `dsi` requests to that verified provider ID while retaining distinct
DSi game/edition/platform identities, source mappings and saved requests. Do not
infer a DSi-to-NDS collection merge, official classification, reliable score,
archive restoration or SD removal eligibility from the provider alias. All
existing wrong-platform, edition, ambiguity and migration checks still apply.

### META-03 — Evidence-based matching

Prefer verified provider IDs or compatible known ROM identifiers; otherwise use
platform/title/release evidence and preserve candidate confidence. Container
checksums (CHD/ZIP/etc.) must not be treated as raw-ROM hashes. Do not download or
decompress every remote ROM to compute identifiers. Ambiguous matches require
review and must not silently publish a score. Persist manual corrections without
losing them on refresh. A conversion or rename must not duplicate the game.
Cached review must show the original artifact filename/folder and disc/patch
labels alongside the cleaned search title, so edition classification can be
checked without guessing or requesting ROM bytes.

Catalogue lookup detail (S7, 2026-10-06): when release facts are absent, a single
standalone artifact's explicit, unambiguous filename region tag may narrow the
provider request. Legacy entries use their original cached filename, not their
cleaned title. Never parse a folder path as a filename or choose one of several
regions; bundles remain unresolved by this hint. Existing release facts and
explicitly cleared manual regions take precedence. The hint is not an assigned
region, content classification, verified match, score or removal authority. Saved
jobs keep their captured requests; new capture does not rewrite running work.

NDS catalogue-title detail (S7, 2026-10-07): the observed four-digit retail and
`z` plus three-digit catalogue numbers before ` - ` are listing ordinals, not
game-title words. Omit that narrowly shaped leading prefix in NDS provider search
and exact candidate-title comparison. Preserve the original captured title,
raw-ROM filename, game/edition identity and request JSON; record the derived
search title/method when a qualified match is published. Do not alter other
platforms or actual game numbers lacking this prefix shape. This is title
discovery only: unknown/modified editions remain reviewable, and existing
classification, regional evidence, ambiguity, score and migration gates apply.

Acceptance: ordinary releases, punctuation/localization variants, wrong-platform
matches, container hashes, conversion/rename and conflicting candidates; false
matches are rejected and correction survives re-scraping.

S7 identification detail (2026-10-06): a supported DVD CHD v5 header can supply
its declared original ISO SHA-1 and logical size, never the container or combined
metadata checksum. Treat this as lookup evidence, not validation of the CHD body.
Unsupported/CD/parent-dependent layouts remain unresolved. The shared provider
must retain the actual requested ISO size. Live API v2 responses for two large
PS2 DVDs returned an exact original SHA-1 but capped `romsize` at 2,147,483,647;
this is observed wire behavior, not a documented provider guarantee. Only a
raw-ISO request larger than that boundary with an exact nonzero SHA-1 and every
other supplied hash agreeing can record `rawRomSha1AndCappedSize`. It must not
claim exact size verification. Other size/hash/platform conflicts still fail;
classification, patch ownership, reception, transfer and migration gates remain
unchanged. This does not authorize downloading every remote ROM or replacing
strict cloud/local integrity checks with a CHD header declaration.

Normal collection identification detail (2026-10-06): for a mapped, explicitly
supported uncompressed standalone ROM/ISO, the versioned Drive file's MD5/SHA-1
can describe that ROM directly. Do not promote checksums of ZIP/CHD/RVZ or other
containers, ambiguous multi-member editions, unsupported formats or stale manual
raw assertions. An exact cryptographic raw match may establish an otherwise
unclassified official release only when ScreenScraper explicitly returns
`notgame=false` and all five `hack/trad/demo/unl/beta` flags as zero. Missing
flags, CRC-only evidence, manual unknown/corrections, patch/base relationships
and declared modifications stay reviewable. Persist the provider facts and
current identity/metadata/item binding together, including durable shared-store
recovery. Rename-only changes preserve those facts; replacement bytes retire
automatic classification and assigned release facts, without deleting manual
evidence. This supplies metadata identity, not reliable reception or Top rank.

S7 standardized identification policy (2026-10-06, explicitly authorized by
the user: "Yes—standardize matching"): replace the former requirement for
identical developer/publisher wording and full regional dates with deterministic
evidence tiers. Exact raw cryptographic evidence and explicit identity corrections
retain their existing priority. Otherwise, an already classified unmodified
official edition may match a uniquely agreeing, bounded provider result using a
nonempty exact normalized title, mapped platform and explicit compatible region.
ScreenScraper title discovery requires an exact regional (or worldwide) title and
regional release evidence; it must not claim raw-byte verification. IGDB requires
current bound ScreenScraper release facts and a matching regional release year.
Day/month disagreement or different/missing company wording alone is not a veto.
Known year, region, platform, edition and modification conflicts still reject;
missing required evidence, truncated results and multiple qualifying candidates
remain reviewable. Official ports, remakes, remasters and bundles may match their
own provider records, never a parent's score. No fuzzy title, invented confidence
weight, highest-score selection or title-only classification of unknown editions.
Keep hacks, translations, audio/restoration editions, revisions and base-linked
editions separate. Persist the matching method and captured source facts, including
the source fingerprint; revalidate current binding before atomic publication and
retain provenance through shared-store recovery. Saved requests remain immutable.
Reception, vote-count, ownership, freshness, canonical grouping and exact
recoverable cloud-byte requirements for SD deletion are unchanged.

S7 local archive identification detail (2026-10-06): the existing bounded N64
7z/ZIP and Game Gear ZIP validators may supply streamed raw member identifiers
from an already present exact leaf under the configured console target. Verify
the complete container size and all supplied cryptographic Drive checksums,
revalidate the current rooted Drive artifact before/after reading, and reject
local namespace/content changes. No extraction, remote ROM-body request, target
creation, installation/adoption or removal is authorized by a metadata read.
Persist raw-member evidence bound to that exact versioned artifact atomically
with the job request; changed bytes retire it, while manual/modified/ambiguous
editions remain protected. This identifies bytes, not reception or migration
authority, and does not turn container digests into raw-ROM digests.

S7 nested local identification detail (2026-10-09): root-level archive copies
retain priority. If that exact leaf is absent, the same metadata-only reader may
check one exact nested parent beneath the configured console target, derived from
the artifact's validated cached ancestor IDs/names up to the selected Drive
folder ID. Never derive local paths from display paths, search other SD folders,
follow links or accept unsafe path components. Inaccessible, changed, unsupported
or checksum-mismatched root files do not permit an alternate lookup. Retain all
complete-container, raw-member, current-cloud and atomic job-binding checks;
journal the actual inspected parent/leaf without granting installation ownership
or removal authority. Existing saved job membership/completed outcomes stay intact.

S7 Game Boy archive identification detail (2026-10-07): extend that same
read-only, exact-local-leaf workflow to explicitly mapped Game Boy/Game Boy Color
7z artifacts already present on the SD card. Reuse the bounded single-member
7z decoder with a 16 MiB raw-member budget (plus the existing bounded header
overhead for the complete file), unchanged header/dictionary
limits and complete CRC/stream validation. A Game Boy member must have .gb;
Game Boy Color permits .gb/.gbc. Reject other platforms, unsafe names, extra
members, unsupported layouts/codecs and changed local/cloud bindings. Keep raw
member digests separate from the complete container's Drive digests. Extension
validation itself establishes neither official classification nor console
identity; the normal exact provider-match/explicit-flags rules still apply.
This identifies existing bytes for META-01/META-03. It does not add archive
installation/emulator/removal support or authorize remote ROM-body downloads,
extraction, ownership inference, ranking/removal exceptions or rewriting saved
job membership/completed requests. Verify the normal persisted worker and real
already-local multi-entry provider workflow before claiming native integration.

S7 GBA archive identification detail (2026-10-07): the current GBA census contains
hundreds of exact local/cloud container matches. Extend the proven metadata-only
7z route to explicitly mapped GBA archives with one safe `.gba` member and a
32 MiB raw work budget. Reuse complete stream/CRC validation and the existing
header/dictionary bounds, container checksums, local/rooted-cloud revalidation,
atomic version-bound evidence and explicit modification/manual-state protection.
The suffix does not establish provider identity or official classification.
Unsupported ZIP/other layouts remain unresolved. No extraction, remote ROM body,
installation/adoption/removal support, completed-request rewrite or new scoring
exception follows. Verify the native decoder, ordinary persisted provider/shared
recovery path and real multi-entry already-local workflow. NES/SNES profile
expansion is not implemented merely because the same decoder could support it.

S7 NES archive detail (2026-10-07): the completed NES census has 1,498 exact
local/cloud archive-byte matches, but the existing owned archive route cannot
identify or restore this actual collection. Complete that required migration
boundary with an explicit NES 7z profile: one safe `.nes` member, a 16 MiB raw
budget, a valid iNES/NES 2.0 signature and unchanged bounded header/dictionary,
complete stream/CRC and pinned-file checks. Existing local metadata identification
retains exact container/cloud checks and version-bound publication, with no
remote ROM-body request or saved-request/membership rewrite. Installation,
adoption and offline reopen retain immutable NES mapping and the exact owned
read-only leaf grant. Use the installed RetroArch FCEUmm core after verifying its
actual availability. Prove the normal download/online and cold offline boot,
owned removal and identical re-download cycle in an isolated target. Wrong
members, mixed mappings, unsupported layouts and unproved bundles stay rejected;
no SNES expansion, inferred official classification or ranking exception follows.
Preserve original ROMs, saves, BIOS and emulator settings. This is an ordinary
format integration for META-01/META-03 and MIGRATE-01 in the sole ACTIVE S7.

### META-04 — Hacks, translations and score ownership

Support distinct content tags for `Hack`, `T-Eng`, `Dub`, `Undub`, `Uncensor`,
homebrew, demo and unmodified official releases, with unknown/provenance where
uncertain; tags may overlap. Preserve general translation status and translated
language separately: `T-Eng` means an English translation, not merely an official
English-language release. `Dub` and `Undub` describe audio modifications;
`Uncensor` describes restored/uncensored content, not an age-rating category.
Normalize known tag aliases but do not infer patch features from a base game's
language or title alone. A release may, for example, be `T-Eng + Undub + Uncensor`.
Keep the base-game relationship separate from the modified release's identity.
Use a hack-specific score only when that project is matched. A translation can
show an original-game score only explicitly labelled as such, never as a rating
of translation quality. If only an uncertain base match exists, omit the overlay.

Acceptance: a highly rated base title cannot give an unrelated hack its rating;
two patches and translated/unmodified editions remain distinguishable; unrated
hacks remain browsable and are not declared poor quality. Fixtures distinguish
official English from `T-Eng`, `Dub` from `Undub`, and independent `Uncensor` status,
including a release with several tags and a genuinely unknown tag classification.

### META-05 — Sourced ratings, not invented popularity

Store original scale, provenance and nullable vote count. Normalize valid scores
to a common display scale without changing their meaning: ScreenScraper documents
a score out of 20, so 17/20 can display as 85/100. Validate endpoints, missing and
out-of-range values; do not convert missing values to zero. Preserve the raw value
for inspection. Do not call a community/unknown aggregate a critic score or a
popularity statistic. Do not attach other providers' logos to it, fabricate vote
counts, select the highest provider score, or invent a cross-provider weighted
formula. Prefer an externally defined overall/consensus score whose meaning and
sample support can be established. A score may be displayable without yet being
an acceptable basis for claiming a consensus-aligned Top.

Acceptance: scale/provenance/null fixtures and representative live records.
Users can see source, original score, retrieval date and vote count when known;
unknown count is explicit. Scraping freshness is not proof of rating reliability.
Before enabling Top claims, evaluate the ranking basis against independent
critical/community reception for a recorded representative sample of at least
20 matched games across four consoles, including high, middle and low reception,
older titles and modified releases where independent evidence exists. Record
source coverage, sample support, edition mismatches and material disagreements;
resolve unexplained disagreements instead of hardcoding individual title boosts.
Include a low-vote extreme-score fixture that cannot masquerade as well-supported
consensus. Missing sample information requires an explicit confidence assessment,
not an invented vote count or blanket reliability claim.

ScreenScraper is the first candidate score source, not a pre-approved reliable
ranking oracle. If it cannot support this gate, integrate an appropriate legitimate
aggregate-score source (such as IGDB, with its documented critic/community counts)
through the same metadata interface. Resolve that dependency in S4 before S5 Top
acceptance. This is required remediation when needed, not an optional deferral.
Any additional API access remains subject to authorization/credential rules.

### META-06 — Persistent bounded scrape jobs and cache

S7 pause detail (2026-10-07): when a Drive header/local-archive identifier read
reports typed cancellation for the owning job's cancellation signal, join the
read and finish with the existing durable Paused outcome, not an operation
failure. Keep the current item pending without publishing raw evidence or
starting its provider lookup; Resume retains the saved job and completed items.
Cancellation without that signal and other errors racing with Pause remain
errors. This normalizes the existing cancellation contract, not provider retry,
job membership or matching policy.

Store per-item progress and refresh generation; cancellation/relaunch resumes the
same job without repeating its completed items. Explicit full re-scrape starts a
new generation. Coalesce duplicate game lookups. Respect provider-reported quota,
concurrency and throttling instructions; default to one metadata request worker.
Show quota/auth/offline failures with actionable resume states, not busy loops.
Keep metadata and artwork caches separate from ROM residency. An unsuccessful
refresh cannot wipe usable cached data; old/stale scores must be labelled.

Saved-job recovery detail (2026-10-06): normal collection settings must allow
selection of an older saved metadata job for the selected provider, with bounded
keyset-paged local reads. A newer console pass must not make an older paused pass
unreachable. Selection loads the existing report and linked artwork only; it
does not create a generation, perform lookup requests or infer a new scope from
the Fresh re-scrape console selector. Resume uses the selected persisted ID and
does not repeat completed items. Reject jobs belonging to another provider and
standalone artwork IDs; keep existing selected-game refresh scope unchanged.

Acceptance: quota exhaustion, offline mode, duplicate demand, pause/restart and
provider outage fixtures. No per-card network requests occur while scrolling;
metadata storage, work queue and buffers stay bounded for a 30,000-game fixture.

### META-07 — Shared metadata-backed query and ranking semantics

Implement the query/filter contract with metadata persistence, before wiring the
UI. Library and per-system views must use the same semantics for content tags,
genres and rating order, while preserving existing region/language, installed,
favorite, search and shelf constraints. Index/query cached fields; filtering must
not trigger scraping or ROM downloads. Use a bounded paged result rather than
loading full metadata/artwork records for the entire library on each keystroke.

Establish collection membership and the explicit console/collection scope first,
select eligible game/project groups, then order by the accepted effective overall
score shown on the covers and assign stable ranks. Apply the Top-N membership
predicate before content tags, genre, search, installed, favorite and shelf-view
filters. Those filters intersect the existing ranked membership; they never
promote a lower-ranked game or refill the list. These are dynamic database results,
never persisted fixed lists or copies of the provider's global Top games. Recompute when a
successful collection refresh, score refresh or explicit ranking-scope change
affects the ranking; other filter changes only recompute the intersection.
Preserve focus by game identity when visible membership/order changes. Use
stable identity-based tie breaking. Rank one canonical game/project once, not
once per region, revision or disc; matching editions remain selectable. Respect
edition-specific score ownership and never choose a base score for a hack just
to qualify it for a Top result.

The initial candidate overall score is ScreenScraper's normalized game score,
subject to META-05's reception-validation gate. For existing RomM-backed games,
use an identified, current overall score only when the primary score is absent
and the basis is comparable/accepted under that gate; document deterministic
source precedence and retain attribution on the card/details. Anonymous legacy
averages are not fresh evidence. There is no required provider-choice step and no
new weighted-average formula: select a credible sourced overall score, do not
manufacture one. The same effective overall score selection must be used for
display and ranking. Unknown/stale/untrusted scores remain available in ordinary
browsing but do not receive an invented ranked position.
Show actual ranking coverage and label rankings provisional when missing or
unresolved scores prevent a defensible whole-collection claim. Do not pretend
25 scored results prove all unscored games rank below them. Show fewer than N
results when only fewer eligible games or intersecting filter matches exist.
Unknown vote count stays visible; it does not imply a large voting sample.

Provide 'Match any' and 'Match all' for selected content tags, with 'Match any' as
the default, and AND with other filter dimensions. 'Match all' supports browsing
`T-Eng + Undub + Uncensor` specifically. Thus 'T-Eng + Top 25' means the T-Eng
members of the collection scope's Top 25, possibly zero or fewer than 25 results;
it is neither the best 25 translations nor Top 25 plus uncapped translations.
Translation/hack tags can overlap; unmodified official releases are a distinct
filter value. Unknown classifications have their own visible option.

Acceptance: matching library/per-system query results, rank-before-tag-filter,
multi-disc/region deduplication, overlapping tags, no unrequested extras,
stable ties, collection-only membership, score/add/remove-driven recomputation,
any/all tag matching, sparse/unrated coverage, restart persistence and indexed-query
resource tests on the large fixture. No network requests while filtering.

### META-08 — Durable shared metadata and ES-DE publication

Persist credential-free scraped records and validated artwork outside the
uninstall-scoped app directory, in an explicitly selected shared location.
Keep exact source/account/artifact and edition/provider bindings, provenance,
retrieval dates and schema/generation information with that data. Keep secrets,
tokens and operational installation/transfer state private. The internal metadata
and query projections must be rebuildable from the durable records without
repeating completed provider lookups or artwork downloads. Reconnecting access
and reselecting a shared directory after reinstall are not loss of scraped data;
do not claim recovery of settings or installations not included in this store.
Handle revoked storage permission, unavailable/remounted storage and interrupted
publication explicitly without replacing the last usable generation. App-private
metadata already present must migrate without dropping verified facts or files.

Settings and library readers join the same catalogue-aware recovery operation.
Reopening settings or switching metadata providers must not independently repeat
a full unchanged-catalogue rebuild. A real catalogue notification, including one
arriving during an earlier recovery, must still schedule recovery of that newer
snapshot; do not coalesce different catalogue states at the raw-store boundary.

Artwork recovery detail (2026-10-07): rebuild the immutable artwork receipt
projection in bounded transactions without opening every image body during
metadata/settings startup. A receipt is not proof that a file is currently
available. Every image consumption must validate its bounded current length and
content-addressed SHA-256 before returning a cover/screenshot path. Missing,
same-size replaced or oversized bodies produce the normal fallback without a
network request or erasing usable text/score metadata. Keep full validation at
publication, migration and ES-DE export boundaries.

Use the published remote catalogue, not local ROM presence, as the membership
input for scraping and shared metadata updates. A successful catalogue/provider
refresh updates exact affected identities and their current metadata; an outage
or incomplete refresh cannot publish an empty collection or erase usable data.
The ROM catalogue remains read-only: changes come from Drive metadata, rich facts
from the legitimate metadata providers. No ROM body requests are needed.

Reuse existing ES-DE covers/screenshots only after validating their console,
edition and expected relative ROM-path association. ES-DE filename conventions
are not sufficient evidence to merge two games, regions, revisions or patches.
Never treat an old gamelist score or description as a fresh provider response.
Keep R-Shop's richer identity/provenance records alongside, rather than using
gamelist.xml as the authoritative provider cache.

Publish supported current fields into the selected ES-DE gamelist/media layout
for explicitly mapped remote editions, including ROMs absent from local storage.
Resolve their expected local paths from the established installation mapping,
never guessed filenames or cloud URLs. Retain unrelated game/folder entries,
favorites, play counts/history, emulator overrides, unknown fields and manual
metadata edits; update only mapped provider-owned fields with recorded ownership
and report conflicts rather than overwrite them. Persist R-Shop-only provenance
in its own records, not invented ES-DE rating semantics. Coordinate with ES-DE's
own writers and revalidate the file before publication; interruption/conflict
must leave a parseable last-good gamelist and a recoverable pending update.
Do not delete shared artwork when a ROM is removed. Do not create placeholder
ROMs, change ES-DE launch/scanning settings, or claim absent ROMs are launchable.

Acceptance: fixture plus Thor evidence for a remote-only title's metadata/artwork
refresh and ES-DE-compatible publication with zero ROM payload requests; valid
identity-based media reuse avoids redundant requests; ambiguous paths cannot
overwrite another edition. Preserve seeded ES-DE user/unknown fields and manual
edits. Cover changed remote metadata, interrupted publication, concurrent edits,
provider outage, storage loss/regrant and database rebuild from durable records.
Verify reinstall persistence using an expendable test package or isolated
fixture, never uninstalling the owner's valuable app as a test technique. A
fresh full scrape remains required by META-01; stale imports cannot satisfy it.

## 6. UI requirements

### UI-01 — Shared cover overlays

Feed cached nullable rating data into the shared cover component used by library,
per-system views and shelves. Render a small source-labelled score badge in the
UI, not burned into cover image files. Preserve title visibility, focus outline,
platform/favorite/achievement badges and download progress. No badge for unknown
or untrusted matches; stale and original-game scores must not look current or
hack-specific. Allow rating overlays to be disabled.

Compact source presentation authorized on 2026-10-04: use the bundled IGDB
service icon instead of the visible IGDB text in cover badges to reduce their
width. Preserve the full source name, score basis and provenance in semantics,
tooltip and details, and retain source text for providers without an approved
icon. Never fetch service icons while rendering cards. Verify offline decoding,
compact/large layout and unchanged score, stale/original/project distinctions.

Scope addition authorized on 2026-10-04: never leave a blank black cover square
while artwork is unresolved. Use bundled, consistently styled raster artwork
representing the original platform's physical media (cartridge, game card,
optical disc, UMD or another supported format) immediately during loading and
when artwork is missing, failed or unavailable offline. Use explicit supported
platform/media mappings, not the download provider or archive/container suffix:
a CHD or ZIP is not the original physical format. Prefer exact known media;
where a platform supports multiple formats and no release evidence identifies
one, use its generic media-family illustration, not a fabricated exact edition.
Unsupported/unknown mappings receive a consistent neutral game-media fallback.

Select one coherent licensed raster asset family, recording source/license and
required attribution; if existing artwork cannot cover the formats consistently,
use the image-generation tool with one shared style/reference. Do not draw or
generate the artwork manually with SVG, Canvas, code or similar mechanisms.
Preserve titles, focus, platform/favorite/achievement/rating/progress badges and
existing cover aspect ratios. A valid resolved cover replaces the fallback;
fallback selection must not initiate scraping, artwork or ROM network requests.

Acceptance: widget/golden tests for compact and large grids, selected/unselected
cards, missing covers, all existing badge combinations, long titles, stale scores
and unrated games; controller and touch proof on target device. Also verify
physical-media mappings, immediate loading/missing/error/offline fallback,
replacement by a resolved cover, and no extra requests or badge/title collisions
in the shared Library, console and shelf card callers on the Thor.

### UI-02 — Metadata controls and details

Settings presentation rule reaffirmed on 2026-10-09: new settings work must not
recreate a single long scrolling form. Keep persistent left-hand section
navigation with independently scrollable focused content, following the metadata
settings pattern. This applies to SAVE-01 and subsequent CACHE-01 controls as
they are implemented; it does not open another ACTIVE stage. Preserve operation
state when changing sections and keep inactive controls out of focus traversal.

S7 navigation refinement (2026-10-08, user-authorized): replace the metadata
settings' single long scrolling form with persistent left-hand section navigation.
ScreenScraper and IGDB each have a focused provider page with a Credentials
button opening a secure editor dialog and a Scraping button opening its focused
workspace (console/game scope, saved jobs, refresh/pause/resume/retry, coverage,
latest-game preview and quota). Shared storage and ES-DE publication have their
own sections. Switching sections must not change provider credentials, recreate
a saved job or stop an active worker. Back closes the editor/workspace before
leaving settings. Preserve exact-game scope, controller/touch access, error and
reconnect actions, localization and compact-screen usability. Verify these
paths in focused widget checks and normal Thor UI without changing owner data.

S7 console browsing refinement (2026-10-08, user-authorized): the Library must
provide direct console tabs instead of treating the entire multi-console archive
as its default browsing grid. The global view is a console dashboard, not an
unbounded All games grid: show cached per-console catalogue-entry counts,
installed/downloadable/favorite counts and known source/managed-local storage.
Distinguish unknown size coverage from zero and source size from local disk use;
do not infer canonical game counts from filenames or initiate network/ROM scans
for metrics. Selecting a dashboard console opens its games. First entry opens
the dashboard; subsequent entry restores the last available console or dashboard.
Explicit cross-console search/filtered shortlists remain available. Installed, Favorites, shelves,
search and metadata filters operate within the selected console. Console scope
is applied before Top ranking, not as a post-Top filter with missing results.
Remember the selected scope across reopening; preserve existing filter and shelf
state, keep every available console reachable by touch and controller, and avoid
header/card overlap at compact and large sizes. Verify scope, persistence,
ranking intersections and normal Thor navigation without modifying ROMs.

S7 library refinement (2026-10-08, user-authorized): improve the tiny game-title
labels and present an exact local/cloud game as one stable selectable identity,
not duplicate cards or selectable local/cloud variants. Prefer its local file
when present and its cloud source when absent; retain metadata and favorites
across availability changes. Show a truthful SD-card/cloud availability icon
on the cover. Filename similarity alone cannot establish exact equivalence,
installation ownership or permission to remove an unmanaged file. This is
required unfinished S7 integration, not a later-stage deferral.

S7 availability lifecycle detail (2026-10-08): a source-less local scan observes
residency; it must not overwrite an existing exact object's cached cloud source,
rename or content version during an offline refresh fallback. Both ordinary and
bulk local enumeration must retain verified committed leaves below a mapped
containing root without exposing their enclosing directory as a legacy game.
These observations do not establish equivalence for unmanaged namesakes or
authorize adoption/removal. Preserve saved refresh requests and identity keys.

Exact unmanaged-copy evidence may reuse a normal metadata archive read only
when it verifies the complete container against the current Drive object's
trusted checksums and size, revalidates that object's account/source/version
binding, and returns the unchanged native file identity after read closure.
Persist that historical evidence separately from raw-member metadata and owned
installations. No extra ROM-body request is needed for this comparison. Raw-ROM
hashes, a filename match or an old observation alone cannot authorize current
availability, emulator grants, adoption or removal; current local identity and
artifact binding must be checked at the relevant consumer boundary.

S7 consumer detail: an exact read-only copy uses a distinct observation-bound
leaf URI within the existing content provider, never a fabricated installation.
Recheck the bounded latest byte evidence, current cached artifact/platform,
ownership reservations and pinned native object before handoff and every external
open. Reject changed, missing, superseded or ambiguous evidence. Grant read-only
access to the exact leaf only; the normal primary action opens a supported local
copy. Owned removal remains a separate freshly reviewed action. Persist favorite
and manual-shelf identity migration atomically and retain explicit unfavorites
through reload; do not rewrite immutable catalogue/refresh membership.

Add provider setup, refresh progress and re-scrape controls to existing settings
and game details, with accessible/localized labels. Keep the common detail model
and expose provenance, original scale, available vote count, match correction and
content tags. A score is advice, not permission to download/delete or a change to
the archive/device curation profiles.

The user approved white labels on darker-red primary filled buttons on
2026-10-04: use `#C62828` with white, retaining existing disabled/tonal styling
and the brighter accent used elsewhere. Verify normal and interaction-state
label contrast without changing authentication or refresh behavior.

User-requested scraping feedback (2026-10-06), delivered in the currently ACTIVE
S7 recheck: beneath the metadata progress report, show the most recently processed
game's title, platform and truthful lookup outcome with its parsed cover preview
when available. Refresh this display on a fixed three-second UI cadence, keeping
only the latest pending preview; the cadence must never control job completion,
cancellation, retry or provider requests. Label an unverified candidate as such;
do not promote preview facts into accepted identity, metadata or ranking. Use
provider-returned media and the existing bounded image/authentication path or an
exact current cached cover, with the physical-media fallback when unavailable.
Do not perform additional game lookups just to update the preview. Stop display
updates when the screen is disposed, without stopping the background job.

Descriptive preview detail (2026-10-06): show an already-returned synopsis with
the latest parsed cover, preferring the UI language, then English, then an
unqualified or available provider language. Keep it bounded and transient.
A sole unverified candidate's description remains explicitly unverified; it
must not publish a metadata record, classify an edition, or establish a score
or Top rank. Ambiguous or changed-identity outcomes cannot select a description.

Alongside the preview, expose ScreenScraper's reported daily request allowance,
used/remaining attempts and observation time, plus its separate failed-request
limit when supplied. Retain provenance for any locally reserved/decremented
budget instead of presenting it as a new provider observation. Missing quota
fields mean unknown, not unlimited; only an explicit documented unlimited
response may be labelled unlimited. Preserve provider rate/exhaustion enforcement
and never infer a daily reset from the device's local midnight.

Additional acceptance: focused worker/controller/widget checks demonstrate the
latest-result preview, fixed display cadence, disposal and provider/job isolation,
image failure/fallback and unverified-candidate labels; quota checks cover known,
missing, exhausted and stale observations. Verify the normal Thor feedback using
the real provider without altering ROMs, saved jobs, mappings or credentials.

Acceptance: coherent controller/touch navigation, no dead-end authentication UI,
clear pending/error states and a details view that explains the overlay's score.

### UI-03 — Integrated discovery filters

Expose the shared query through the existing filter/sort controls, not a new shop
or a separate catalogue workflow. Provide the independent `Hack`, `T-Eng`, `Dub`,
`Undub`, `Uncensor` and other content tags with any/all matching, genre and dynamic
best-rated limits of 10, 25, 50, 100 or All, alongside
existing filters. Preserve A-Z and unfiltered browsing as options. Label this
'Best rated in my collection' with its score basis and scope, rather than implying
a curated Top list or ranking of games outside the user's collection.

Within a console, the limit applies to that console. In the cross-system library,
it applies once across the currently selected scope and the UI must say so; do
not silently multiply the cap per console. Persist settings in their existing
view/system context, show active filters/result counts and provide Clear filters.
Manual shelf order remains unchanged unless a rating sort is explicitly selected.
Filters never install, retire or delete games and never alter cloud or device
Top profiles (including their franchise/sports eligibility rules).

Acceptance: controller/touch/widget tests for dynamic Top 10/25, independent tag combinations,
scope labels, empty/unrated results, clear/restore, manual shelves and identical
logic in library/per-system views. Overlays and filters ship in the same UI stage
after META-07 has passed, rather than requiring a second metadata implementation.

## 6a. Final live migration

### MIGRATE-01 — Fresh metadata and Top-25 offline sample on AYN Thor

After integrated feature verification, perform the fresh collection-wide metadata
pass and live on-demand round trip on the actual Thor. Keep the best 25 canonical
games per console as the offline sample, using the same validated overall-score
and identity rules as META-05/META-07. Preserve required disc/bundle members; do
not count each disc as a game or add uncapped translation/hack/tag bonuses. Fewer
than 25 games are valid for smaller collections. An incomplete/untrustworthy
ranking cannot justify deleting unranked games; report and defer that console
until its retention set is defensible.

User clarification, 2026-10-10: Top 25 is an upper limit, not a quota. A smaller
reliably scored sample (for example nineteen games) needs no padding, fabricated
scores or wait for additional votes. Preserve unranked/uncertain games rather
than treating missing scores as poor reception. Console outcomes are independent:
an unresolved console must not prevent eligible cleanup of another console.
Game Gear may be preserved in full because its storage cost is small. Record
preserved exceptions explicitly; do not use them as a whole-SD blocking gate.
This clarification does not waive exact cloud recovery, local identity,
save/settings preservation or the required fresh metadata work.

Inventory exact existing SD ROM paths and prove each removal candidate has an
identical, complete, readable cloud artifact (stable provider ID/version and
matching cryptographic digest), with a tested restore route for its format.
Do not upload, replace or delete H:/Drive originals. Existing unmanaged ROMs need
deliberate identity-checked adoption or an equally strict one-time migration
manifest; never infer ownership from a directory name. Revalidate local and cloud
identity immediately before each removal. Preserve changed files, unknown files,
missing cloud copies, saves, BIOS, emulator configuration and unrelated content.

Produce a private reviewed keep/remove/preserve manifest with game counts and
bytes; execute only its exact eligible paths after recovery and ranking gates
pass. Keep a durable per-file journal for interruption/restart. No recursive
game-folder wipes. Arrange the existing external sync policy so it cannot silently
refill removed games, without changing archival download profiles or broadening
this into a LoLSuite rewrite. Verify actual retained sets, free space and a restore
of a removed test game through R-Shop, then return that test to its planned state.

S7 PS1 recovery detail: use the existing owned installation/content-grant path
for standalone CHDs and the installed RetroArch PCSX ReARMed route. Only the
exact ready leaf receives a read grant; no directory, archive, CUE or bundle
support is inferred. Verify normal download, actual online/offline emulator
boot, owned removal and identical re-download in an isolated target. Preserve
original ROMs, emulator settings and existing save files.

S7 Dolphin recovery detail: retain the existing exact owned content URI for
emulator-ready GC/Wii files. Dolphin 2606 finishes its exported launcher before
its non-exported emulation activity opens the ROM, so an activity-owned intent
grant alone does not span the required workflow. Give only installed Dolphin an
explicit read grant for that exact preflight-validated installation URI. No
directory/prefix, write or persistable permission is granted; the provider still
rechecks durable ownership, publication and current native object on every open,
rejecting removed/changed installations. Prove each format/console's normal
download, online and cold offline boot, owned removal and identical usable
re-download in an isolated target before granting its migration eligibility.
GC RVZ proof is not Wii or other-format proof. Restore owner configuration and
preserve original ROMs, emulator settings and existing saves.

S7 PSP recovery detail: the current standalone PSP CHD collection uses the same
owned committed-leaf/document-shaped read grant with installed official PPSSPP.
Its exported Android VIEW route receives only the exact ready installation URI,
not a directory, writable/persistable grant or guessed local path. Recheck durable
ownership and standalone/no-bundle constraints before launch and external open.
Missing PPSSPP must report the emulator prerequisite, not imply a successful
boot. Prove normal download, online and fresh offline boot, exact owned removal
and identical re-download in an isolated destination. Do not infer PSP archive,
ISO/CSO/PBP or bundle recovery from this CHD proof; unresolved formats remain
preserved during migration. Preserve original ROMs and existing saves/settings.

S7 PS2 recovery detail: standalone PS2 CHDs use the existing owned committed-leaf
document read grant and installed NetherSX2's explicit EmulationActivity route.
Its bootPath receives only the exact owned content URI, not a guessed local path
or directory grant. Revalidate ownership and standalone/no-bundle constraints
before handoff and external open. The emulator's normal setup/import owns BIOS
configuration; R-Shop does not copy, obtain or mutate BIOS/settings. Verify normal
download, actual online and fresh offline boot, owned removal and identical
re-download in an isolated target. Missing emulator/BIOS remains a prerequisite,
not a boot claim. Unproved archive/ISO/bundle formats remain preserved.

S7 handheld archive recovery detail: extend the existing Game Boy single-member
7z route to explicitly mapped GBC/GBA installations. Reuse its pinned-descriptor
decoder, complete stream/CRC checks and exact owned document-leaf grant; require
one matching `.gbc` or `.gba` member, with the existing 16/32 MiB raw budgets.
Use installed RetroArch SameBoy for GB/GBC and mGBA for GBA. Preserve immutable
console mapping through queue, publication, crash recovery and offline reopen;
unknown/mixed mappings, wrong members and unsupported codecs/bundles remain
rejected. Prove each normal queue -> actual online/cold offline boot -> exact
owned removal -> identical re-download cycle in an isolated target before
approving that console's migration. Metadata identification alone is not proof
of restoration, ranking or removal eligibility. Preserve original saves/settings.

S7 Wii U recovery detail: prove the observed standalone WUA collection through
installed Cemu's exported EmulationActivity VIEW route and the existing exact
owned document-leaf read grant. Require current ready standalone ownership with
no dependencies, bundle owner or archive mapping before launch and external
open. Preserve URI flags and download/checksum/publication/removal gates. Prove
normal download, actual online and cold offline boot, owned removal and identical
re-download in an isolated destination. WUD/WUX/RPX, external bundles and other
formats remain unproved; do not add conversion, keys or emulator configuration
changes. This resolves existing DRIVE-06/MIGRATE-01 recovery scope, not a new stage.

Acceptance: actual-device fresh scrape coverage, per-console retained Top-25
identities, all bundle members, before/after space, saved-data preservation and
cloud-restore evidence. Blocked/preserved exceptions remain explicit. Completion
requires no unresolved required migration work; do not call a partial cleanup
complete or publish private inventories in Git.

## 6b. Per-ROM companions (S8)

### COMPANION-01 — Linked Android application on the bottom display

Allow an explicit optional companion application association for each ROM/edition,
using its stable identity rather than a filename-only or console-wide association.
Provide select/change/clear controls in the existing game settings/details flow
and persist the association across restart and catalogue refresh. A ROM without
an association keeps ordinary emulator launching; companions are not mandatory.

Launching an installed, ready ROM with a companion opens that ROM in the chosen
emulator on the Thor's top display and the linked installed Android application
on the bottom display. Resolve actual display identities/capabilities rather
than assuming hardcoded display numbers. Preserve the established ROM URI grants,
emulator settings, saves and existing applications. Selecting a companion does
not install an APK or grant permission to kill other applications.

Report missing/unlaunchable companion apps, unavailable second displays and
rejected display placement truthfully; do not claim a successful pair when either
launch failed. Keep supported ordinary ROM launch available and avoid duplicate
launches from repeated activation. Do not add sleep-driven launch ordering,
require a PC/ADB during normal use or silently switch ROM/companion associations.

At S8 entry, inspect Cocoon Launcher's applicable source, revision and license
for its companion/display-launch mechanism. Verify Android behavior on the Thor
before choosing the implementation; reuse only license-compatible code.

Acceptance: association persistence and edition isolation; select/change/clear
controller/touch proof; actual Thor ROM on top plus linked APK on bottom;
independent associations for two ROMs; repeated launch, missing app, launch
rejection and unavailable-display coverage; ordinary launch without a companion;
save/settings preservation and both displays switched off after live testing.
Reconcile all S1-S11 requirements before overall completion. S8 being planned is
not implementation or acceptance evidence.

## 6c. Final original-media visual audit (S9)

### ART-01 — Complete supported physical-format coverage

After S8, audit the current supported-platform list against bundled fallback
artwork. Every cartridge-based console must resolve to a recognizable,
physically appropriate cartridge shape; consoles sharing that shape may share
an asset. Do not represent N64 with the generic handheld cartridge. Inspect the
older game-card, floppy and cassette families too, including materially distinct
disk formats where supported. Record the original formats and their evidence;
archive/container suffixes do not establish an original release medium.

Keep the same visual family. Source or generate missing raster shapes only when
the audit identifies a real supported-format gap; no hand-generated SVG/Canvas
illustrations. Preserve S5's immediate loading/error/offline fallback, valid-cover
replacement, badges/focus and bounded decode behavior. Mixed/unknown release
formats retain honest generic/neutral fallbacks rather than fabricated claims.

Acceptance: a complete platform-to-original-format-to-asset matrix for the then
supported systems, no unresolved cartridge or legacy-format gaps, provenance for
added assets, decoded/bundled/mapping checks and visual review of compact/large
cards on the Thor. Recheck cover replacement and badge/focus preservation, switch
both displays off, and reconcile the delivered requirements. Overall completion
also requires the subsequently authorized S10 save-backup and S11 managed-cache
stages.
S9 is required at final closure, but does not retroactively block earlier stages
or permit their existing acceptance criteria to be weakened.

## 6d. Emulator-aware save-backup sync (S10)

### SAVE-01 — Save and save-state backup without ROM mirroring

Acceptance scope revised by the user on 2026-10-09: a restored save must be
published at the location the configured emulator expects. Verify the destination
binding and completed file write; gameplay, in-emulator save loading and deep
save-content inspection are not acceptance gates. The user will report later
emulator-use issues. This replaces the former emulator-load proof requirement,
not the backup/write boundaries, preservation or overwrite safeguards below.
The user's accompanying condition explicitly retains conflict handling and its
verification: divergent local/cloud generations must preserve both versions and
require an explicit resolution choice. Never silently overwrite the remote
generation or select a winner solely by timestamp. Skipping deep save-content
checks does not waive conflict, last-good recovery or overwrite-safety checks.

Add backup sync to R-Shop's normal settings and game/emulator workflow. As new
controls are added, keep settings in persistent left-hand
section navigation rather than one long scrolling form (user instruction,
2026-10-09). Separate backup-area setup, game backup, restore/conflicts and
status. Only the selected section's controls are visible/focusable; section
changes preserve the selected save, confirmation and running operation. Reuse
the metadata settings' responsive/controller navigation pattern. Verify narrow
and handheld layouts, touch/controller section changes and operation continuity.
At stage entry, audit the emulators installed on the Thor and their supported save-memory
and save-state locations, formats and permission routes. Provide a visible
per-emulator coverage matrix and explicit user-selected path mappings; do not
claim RetroArch-only coverage is sufficient. Start with a real RetroArch plus
standalone-emulator vertical slice, then implement the remaining accessible
installed-emulator routes. Protected or unidentifiable storage is visibly
unsupported until a legitimate export/import or user-granted route is available;
do not bypass Android storage protections or require root/ADB for normal use.
The user's coverage target is most installed emulators, not just the initial
pair. Reconcile the full installed package inventory, including differently named
forks and multi-core/embedded emulators. Every accessible installed-emulator route
must be implemented and verified; record save and state coverage separately, with
the exact permission/export limitation for any unsupported route. An uninvestigated
route is unfinished work, not a justified unsupported classification. Refresh the
inventory at S10 entry and closure rather than freeze today's installed apps.

Bind backups to the account, device, emulator/core, console and reviewed
game/edition identity. Separate portable battery/in-game saves from save states;
record emulator/core and state-format compatibility rather than restore an
incompatible state into another emulator. Unknown associations remain unresolved.
Include required related save files as a group, not ROMs, BIOS, shaders, arbitrary
app data, credentials or emulator settings. Custom paths require explicit mapping
and the same file/identity safeguards; never scan and upload the entire SD card.

Use a dedicated Google Drive backup area with separately consented, least-privilege
write access to app-created/explicitly authorized backup files (initial candidate
`drive.file`, subject to actual native verification). A folder selection alone
does not authorize all existing descendants. Keep the ROM provider read-only and
enforce the backup boundary in code even if an account grant includes both scopes.
No public sharing, full-Drive write scope, ROM upload or cloud-original deletion.
Keep existing external sync configuration untouched until the authorized
verified handover; do not import its secrets or silently alter its jobs while
implementing the replacement.

After explicit enablement, back up changed saves through persistent bounded work,
including emulator-return and Android-supported background synchronization.
Expose per-emulator/game progress, last verified backup and permission/offline/
quota errors. Capture stable file identities and complete coherent groups without
killing an emulator or using an arbitrary delay as proof that writing finished.
Stream digests, validate uploaded bytes and publish only a complete recoverable
generation. Cancellation, interrupted upload, changed source or revoked access
must preserve the last-good backup and resume without duplicate workers.

Provide an explicit restore path, also discoverable when installing a game on
demand. Verify cloud identity/digests, compatible formats and destination grants
before atomic local publication. Preserve the current local generation for a
defined rollback procedure. Use recorded ancestry/digests, not timestamps alone,
to reconcile divergent local/cloud saves; surface conflicts for explicit choice.
Never silently overwrite a newer save, propagate local/cloud deletions, or remove
backups when a ROM/source is removed or the app is uninstalled. Retained versions
must be independently discoverable after reconnect/reinstall. Version pruning is
not authorized by this scope; do not add unlimited polling or a general sync engine.

Acceptance: native Thor backup/download/digest verification and completed
restoration at the configured emulator's expected save location for RetroArch
and a standalone emulator, followed by the installed-emulator coverage audit. Demonstrate save
versus state compatibility, multiple ROM/edition isolation, changed files/groups,
conflicts, offline/relaunch/cancellation/revocation and lost/regranted storage.
Prove last-good recovery after interrupted publication and reconnect/reinstall
with expendable fixtures, without uninstalling the owner's app or damaging real
saves. Verify no ROM/BIOS/settings transfers or archive writes. Controller/touch
setup, status and restore must work. After these replacement criteria pass,
resolve the old device sync application's exact package and the scheduled task's
exact identity by its `sync-retrobat-saves.ps1` action. Join any active old sync
operation safely before handover; do not terminate an in-progress write blindly.
Uninstall only that package, stop/disable only that task, and verify package
absence, task disabled/not running and a subsequent working R-Shop save backup
and restore to the expected save location. Preserve existing save files/cloud backup data and
the laptop script; unrelated apps/tasks remain unchanged. Record evidence and
switch both displays off before S1-S10 reconciliation. S11 remains required for
overall completion. If exact target
identity is ambiguous, resolve it before removal; do not guess from display names.

## 6e. Configurable managed ROM cache (S11)

### CACHE-01 — Persistence window, rotation queue and console scope

On-demand installations must not silently become an indefinitely accumulating
permanent library. Add a normal Settings -> ROM cache section, with accessible
controller/touch controls and credential-free configuration persistence/export.
Keep this policy distinct from download queue concurrency, archival Top lists,
metadata filters and the one-time MIGRATE-01 operation. S11 is the delivery owner;
do not start it while S7-S10 has an ACTIVE stage. Reuse the existing owned
installation and durable removal workflow rather than a second deletion engine.

Settings must expose:

- Automatic managed-cache cleanup enablement and an explicit keep-until-manually-
  removed choice. Upgrade must not silently authorize eviction of pre-existing
  unmanaged files or overwrite saved policy. Ordinary initial cache configuration
  makes its automatic removal effects clear; it is not a development approval gate.
- A configurable persistence window in days since the last recorded successful
  R-Shop emulator handoff, falling back to verified installation completion for a
  never-launched game. Include explicit Never and custom-duration choices. Show
  the usage basis: launches outside R-Shop may not be observed; file modification,
  directory presence, metadata browsing or a failed launch is not evidence of use.
  Unknown usage history must not be advertised as verified inactivity.
- Rotation queue size (maximum eligible unpinned games), eviction order (least
  recently used by default or first installed/first out), and an optional byte
  budget. Count one installed game/edition group with its complete required
  bundle, not separate discs. Show actual eligible game count and bytes. A byte
  budget prevents a count-only policy from treating tiny cartridges and large
  optical games as equivalent storage demands.
- Scope: one Unified pool across configured consoles, or independent Per-console
  pools. Unified limits apply once to the combined pool; per-console limits apply
  separately and allow console-specific duration/queue/budget settings with clear
  inheritance from defaults. Changing mode retains inactive settings and never
  silently reinterprets a global limit as a multiplied per-console allowance.
- Per-game pin/unpin and clear protection/status/reason labels. Keep the approved
  Top-25 offline sample and explicitly pinned games outside the rotation queue.
  Protected bytes remain visible in total SD usage and cannot be purged to meet a
  budget. Top protection uses the existing validated ranking semantics; an
  incomplete ranking does not supply new removal authority for legacy files.

Expiry and capacity are independent configured eligibility triggers: the window
can make an unused unpinned install due for cleanup even below the queue limit;
exceeding a queue/byte budget chooses eligible unpinned victims in the configured
order even before their age window expires. Never disables age expiry, not an
independently enabled capacity rule. Explain this in Settings. Resolve ties by
stable installation identity. Show the effective scope, protected/unpinned counts,
bytes, next due candidates and blocked reasons before policy activation/change.

Only exact currently owned, unchanged, complete and demonstrably recoverable
local ROM installations may be rotated. Revalidate the exact current cloud
identity/version, readable complete copy and cryptographic integrity immediately
before removal; retain the proven format-specific restore route. Offline, revoked
access, missing/stale/truncated cloud data, changed local bytes, ambiguous identity
or an unproved format preserves the file and reports why cleanup is blocked.
No guessed folder deletion, unmanaged adoption, source failover by name or cloud
write follows from enabling the policy. Preserve saves/states, BIOS, emulator
settings, metadata/artwork, favorites, credentials and remote catalogue entries.

Never evict a pinned/protected, actively launched/in-use, transferring, verifying,
publishing or removing installation, or partially remove a required bundle. Join
and serialize decisions with existing ownership/lifecycle operations. If safe
space cannot be reclaimed, report the unmet limit or pause the new download; do
not delete protected/ambiguous data, overpromise available space or cancel another
operation merely to satisfy a budget. Recheck policy, protection and identity at
execution, not only when a candidate list was calculated. Record durable per-
installation decisions and outcomes so restart/cancellation cannot double-delete
or lose the last truthful installed state. Scope/configuration changes are not
permission to bypass these checks.

Reconcile cleanup on normal application/queue/emulator-return events and through
legitimate Android background scheduling when needed for the selected persistence
window. Configured retention expiry is a product requirement, not a lifecycle
timeout: use actual completion/cancellation signals and framework scheduling,
never arbitrary sleeps, polling races or deadline-based lock stealing. Record
last-use/protection/policy state durably and evaluate age boundaries against an
explicit clock; clock anomalies must not accidentally purge an installation.

Acceptance: focused policy/configuration/migration tests and controller/touch
Settings proof cover custom/Never durations, exact expiry boundary, successful
versus failed handoff and unknown/external usage, LRU/FIFO/ties, game-versus-disc
counting, queue/byte limits, unified versus per-console isolation, inheritance,
scope changes, pins/Top-25 protection and oversized protected samples. Verify
offline/revoked/missing/changed cloud and local files, active-use/transfer races,
bundle atomicity, cancellation/restart and storage loss without save or cloud
mutation. Prove on Thor: configure policy -> normal owned test downloads -> actual
usage -> deterministic expiry/capacity-driven rotation -> remote entry/metadata
still available -> identical re-download and usable emulator launch. Use isolated
test destinations; restore owner configuration and switch both screens off.
Do not count manual deletion, unit fixtures or a displayed Settings form as proof
of automatic native rotation. Reconcile S1-S11 before overall completion.

## 7. Quality and delivery requirements

### QA-01 — Deterministic resource-safe verification

Use small deterministic fixtures and one test workload at a time. Do not use
timeouts/sleeps as lifecycle, cancellation or success mechanisms. Protocol-mandated
timeouts and provider retry-after delays stay at their transport boundary.
Bound retries and preserve state when exhausted; no spin on unavailable work.
Record process/resource evidence for large-catalogue and large-transfer tests.

For remaining Windows verification, the supervising process must acquire
`Local\Darka.AndroidGradleBuildGate` before checking wrapper clients, Android
Studio builds, daemon identities, connections and lifecycle logs. Retain it
through any wait and the Gradle command's confirmed exit. Active or ambiguous
builds must finish without interruption; neither an abandoned mutex, low CPU nor
an old log proves completion. The Local mutex covers cooperating launchers in
the current Windows session, not uncoordinated external launchers.
Start with two workers, no parallel projects and explicit 3 GB Gradle/separate
Kotlin heaps, preserving other required JVM arguments. Assess the actual plugin
versions before using in-process Kotlin; limit test forks and native build jobs.
Raise only a diagnosed insufficient budget, and record observed effective
settings, actual gate acquisition and any memory failure with the next required
focused verification. Do not modify another task's configuration or interrupt
its build to enforce this constraint.

### QA-02 — Regression and end-to-end evidence

Cover existing file providers, source merge/configuration, queue persistence,
metadata migrations, cover performance and controller navigation. Demonstrate
the two features together with no RomM/PC dependency, an offline relaunch and
save-safe local removal. Tests must not upload/download a real library by default.
Use synthetic/homebrew or explicitly authorized test content for live proof.

### QA-03 — Privacy, scope and delivery gates

No account creation/consent, public sharing, cloud writes, SD cleanup or live
deployment during preparation. Never commit private file inventories, account
data or credentials. Keep a separate stable signing identity before any device
test build; do not uninstall or overwrite a differently signed upstream app.
Build/install debug artifacts only when live testing is authorized/required by
the implementation outcome. No release or pre-release without explicit request.

Release identity decision (2026-10-02): retain the upstream APK filename and
`R-Shop` application display name. Distinguish the fork only by its custom Android
application ID (`com.darkaxt.rshop`). The isolated development variant may retain
its debug suffix/label. This naming requirement does not authorize a release.
Acceptance: inspect the processed release manifest for the display name and
package ID; preserve the existing APK naming route without a fork-specific rename.

### QA-04 — Specification reconciliation

Every requirement must map to a stage with evidence and status. Reconcile the
authoritative specification after each stage. A required gap is a blocker or
tracked deferral with an owner stage, never silently removed. Implementation
completion requires fresh integrated verification and zero unresolved required
blockers/deferrals. Preparation completion is not feature completion.

## 8. Non-goals for this scope

- Streaming ROM content directly into emulators; games are downloaded first.
- ROM/BIOS uploads, archive mutation, remote deletion and public share-link
  download workarounds. SAVE-01's separately authorized save-backup uploads are
  the sole write exception; there is no SD-card or arbitrary-folder mirroring.
- Android CHD/media conversion, a general downloader rewrite, or new ROM sites.
- Rewriting LoLSuite or changing archival Top lists. The explicit one-time Top-25
  migration and separately configured CACHE-01 local rotation are in scope;
  neither authorizes arbitrary SD cleanup or ROM/cloud mirroring.
- Reusing outdated scraped files as the new metadata baseline.
- A recommendation engine or replacement for curated archive/device Top lists.
  Metadata-backed browsing filters and the score-source remediation required by
  META-05 are in scope; speculative unrelated provider expansion is not.
- Mandatory server deployment, RomM installation, public app publication, iOS or
  desktop Drive authentication in the first Android feature scope.

## 9. External constraints and evidence

These sources establish API capabilities, not proof that this fork works.

- [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth):
  read-only versus per-file authorization and scope classification.
- [Android authorization](https://developer.android.com/identity/authorization):
  native authorization/renewal; package and signer setup must be validated.
- [Drive file resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/files)
  and [media downloads](https://developers.google.com/workspace/drive/api/guides/manage-downloads):
  IDs, binary metadata/checksums, download capability and partial downloads.
- [ScreenScraper API v2](https://www.screenscraper.fr/webapi2.php): developer/user
  authentication, game identification, 20-point score and account quota fields.
- [IGDB API](https://api-docs.igdb.com/#game): critic/community aggregate fields
  and rating counts, if needed to meet the score-reliability gate.
- [Upstream source](https://github.com/AverageConsumer/R-Shop/tree/d615f87277617cbf3a12a6445b3c71d42cf72539):
  the verified code baseline. See [implementation plan](IMPLEMENTATION_PLAN.md)
  for extension points and [status](IMPLEMENTATION_STATUS.md) for actual evidence.
