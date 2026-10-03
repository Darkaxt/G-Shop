# Google Drive, metadata expansion and per-ROM companions

Authoritative specification, revision 3, 2026-10-02.

Status: implementation authorized on 2026-09-08; acceptance tracked in the ledger.
Upstream baseline: `AverageConsumer/R-Shop` at
`d615f87277617cbf3a12a6445b3c71d42cf72539`.

## 1. Objective and authorization

Turn R-Shop into an on-demand browser for a private cloud ROM library: inspect
games and their fresh metadata, install selected games locally for ordinary
emulator use, and explicitly remove owned local installations without changing
the cloud originals or saves. The primary target is an Android handheld with an
SD card (AYN Thor); existing R-Shop sources must remain usable.

The user authorized implementation after preparation with "go ahead then" on
2026-09-08. Implement and verify the two features through the staged plan.
Google and ScreenScraper access are entirely new setup; do not assume existing
credentials. Account consent remains user-controlled. Required live tests and a
fresh metadata pass are part of acceptance; no release is authorized. The user
also requested a final live SD-library migration retaining a small offline
sample: Top 25 games per console. This is a one-time reviewed migration, not
automatic eviction or permission to modify the cloud archive.

Scope extension authorized on 2026-10-02: add S8 for per-ROM companion launching
on the Thor, with the ROM/emulator on the top display and its linked Android
application on the bottom display. Review Cocoon Launcher's source and reuse
terms when S8 starts; do not begin that implementation during earlier stages.

User decisions incorporated:

- Google Drive and metadata expansion are the two features.
- Per-ROM dual-display companion launching is the additional S8 feature.
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
and remote source intact. No bulk mirroring or automatic eviction is introduced.

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

### CORE-03 — Compatible migrations

Migrate current config, SQLite metadata, queue, favorites and installed references
without dropping existing sources or user selections. A legacy anonymous rating
may be retained as legacy/stale data but cannot count as a fresh verified score.
Removing a provider or revoking access must not delete local games or saves.

Acceptance: migration/restart fixtures preserve upstream records; old ratings do
not satisfy a fresh scrape or acquire invented provenance.

## 4. Feature A: Google Drive

### DRIVE-01 — Native, read-only account authorization

Use native Android Google authorization behind a Flutter adapter and Drive API
v3. Support account selection, sign-out/revocation, token renewal and an explicit
reauthorization state. Do not persist bearer tokens in catalogues, exported config
or queue records. Do not borrow another application's OAuth client or secrets.

For an existing personal library use `drive.readonly`. Explain that this grants
account-wide read access: the selected library folder is an app-enforced boundary,
not a folder-scoped OAuth permission. `drive.file` must not be represented as
automatically granting every existing descendant of a selected folder.

Acceptance: consent/decline, renewal, revoked access and two-account isolation
tests; native live authorization evidence before feature completion. No Drive
mutation methods are invoked.

### DRIVE-02 — Folder selection and paginated catalogue

Provide a native-app folder-selection flow and explicit per-console mappings.
Enumerate the selected personal My Drive subtree using IDs and pagination; allow
nested folders. Do not traverse the whole account or read file bodies for indexing.
Persist a refresh checkpoint and publish a new catalogue snapshot only after a
successful traversal. An interrupted/error refresh must not look like an empty
library or remove existing entries. Reflect renamed/moved/deleted entries on a
successful refresh without changing existing installed files.

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

Install already emulator-ready files supported by the mapped system (including
CHD/RVZ/WUA where supported). Do not add Android media conversion. Preserve
multi-disc/bundle dependencies and playlists using safe relative paths; no bundle
is marked ready while a required member is missing. Unsafe or unsupported archive
layouts are reported, not installed optimistically.

Local removal is explicit and limited to installation-manifest-owned ROM paths.
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

### META-03 — Evidence-based matching

Prefer verified provider IDs or compatible known ROM identifiers; otherwise use
platform/title/release evidence and preserve candidate confidence. Container
checksums (CHD/ZIP/etc.) must not be treated as raw-ROM hashes. Do not download or
decompress every remote ROM to compute identifiers. Ambiguous matches require
review and must not silently publish a score. Persist manual corrections without
losing them on refresh. A conversion or rename must not duplicate the game.

Acceptance: ordinary releases, punctuation/localization variants, wrong-platform
matches, container hashes, conversion/rename and conflicting candidates; false
matches are rejected and correction survives re-scraping.

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

Store per-item progress and refresh generation; cancellation/relaunch resumes the
same job without repeating its completed items. Explicit full re-scrape starts a
new generation. Coalesce duplicate game lookups. Respect provider-reported quota,
concurrency and throttling instructions; default to one metadata request worker.
Show quota/auth/offline failures with actionable resume states, not busy loops.
Keep metadata and artwork caches separate from ROM residency. An unsuccessful
refresh cannot wipe usable cached data; old/stale scores must be labelled.

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

## 6. UI requirements

### UI-01 — Shared cover overlays

Feed cached nullable rating data into the shared cover component used by library,
per-system views and shelves. Render a small source-labelled score badge in the
UI, not burned into cover image files. Preserve title visibility, focus outline,
platform/favorite/achievement badges and download progress. No badge for unknown
or untrusted matches; stale and original-game scores must not look current or
hack-specific. Allow rating overlays to be disabled.

Acceptance: widget/golden tests for compact and large grids, selected/unselected
cards, missing covers, all existing badge combinations, long titles, stale scores
and unrated games; controller and touch proof on target device.

### UI-02 — Metadata controls and details

Add provider setup, refresh progress and re-scrape controls to existing settings
and game details, with accessible/localized labels. Keep the common detail model
and expose provenance, original scale, available vote count, match correction and
content tags. A score is advice, not permission to download/delete or a change to
the archive/device curation profiles.

The user approved white labels on darker-red primary filled buttons on
2026-10-04: use `#C62828` with white, retaining existing disabled/tonal styling
and the brighter accent used elsewhere. Verify normal and interaction-state
label contrast without changing authentication or refresh behavior.

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
Reconcile all S1-S8 requirements before overall completion. S8 being planned is
not implementation or acceptance evidence.

## 7. Quality and delivery requirements

### QA-01 — Deterministic resource-safe verification

Use small deterministic fixtures and one test workload at a time. Do not use
timeouts/sleeps as lifecycle, cancellation or success mechanisms. Protocol-mandated
timeouts and provider retry-after delays stay at their transport boundary.
Bound retries and preserve state when exhausted; no spin on unavailable work.
Record process/resource evidence for large-catalogue and large-transfer tests.

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
- Google Drive uploads, remote deletion, public share-link download workarounds.
- Android CHD/media conversion, a general downloader rewrite, or new ROM sites.
- Automatic ongoing SD-card eviction, rewriting LoLSuite, or changing archival
  Top lists. The explicit one-time Top-25 device migration is in scope.
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
