# S7 private migration audit

`thor_migration_audit.py` is a read-only, one-time inventory aid, not a ROM
downloader, migration executor or ownership/adoption command. It compares exact
SD artifacts with the normal app's published Drive-cache records and streams
hashing on the device. It never reads ROM bodies into the Windows process.

Use an explicitly inspected console directory and keep its output outside Git:
inspect its actual archive extensions as well (for example, N64 on this Thor
uses `.7z`, not `.zip`). A completed non-ROM-only inventory is not ROM comparison
proof when an incorrect extension selector excluded the ROMs.

```powershell
python -B scripts/thor_migration_audit.py --adb <adb.exe> --serial bfa98654 `
  --cache-helper /data/local/tmp/rshop-s7-cache-snapshot.jar `
  --platform gamegear --root /storage/75D7-DC5F/Roms/gamegear `
  --extension .zip --output D:\RShopPrivate\Migration\<unique-audit>.jsonl
```

The private JSONL contains scoped cloud IDs, versions, digests, exact local paths
and file observations. Do not commit or publish it. Exclusive creation preserves
existing journals; an interrupted run has no completed summary. Every record's
disposition is **preserve**, including checksum matches. A cached comparison is
not a live revalidation or restore proof. Canonical identity, defensible retention,
restore, save/sync safety and execution-time revalidation remain required before
the separate reviewed migration can remove anything.

Config and native projection reads are each capped at 1 MiB; device shell output
is capped at 8 MiB. The audit no longer copies/deserializes a live database. The
fixed native helper opens the app cache READONLY under `run-as` and produces
128-artifact keyset pages with catalogue generations in one statement per page,
including WAL state. Each bounded page fits one cursor window. Configuration is
read before and after; changed config/count/generation, invalid/repeated cursors,
incomplete pages, oversized output or a helper failure aborts before a journal
is created. Pages are observations, not an atomic whole-collection snapshot;
same-count mutations cannot be ruled out and execution must independently
revalidate each exact artifact. No automatic retry or repair occurs.
One client runs at a time; there are no arbitrary deadlines.

Prepare the helper once for the current source before cached comparisons:

```powershell
$taskNative = 'D:\Temp\rshop-s7-cache-snapshot'
New-Item -ItemType Directory -Path $taskNative -Force | Out-Null
javac -J-Xmx256m -cp '<Android SDK>\platforms\android-36\android.jar' `
  -d $taskNative scripts\RShopMigrationCacheSnapshot.java
# Use the same JDK for d8; bound its VM independently (no Gradle build required).
$env:JAVA_OPTS = '-Xmx256m'
& '<Android SDK>\build-tools\36.0.0\d8.bat' `
  --lib '<Android SDK>\platforms\android-36\android.jar' `
  --output "$taskNative\rshop-s7-cache-snapshot.jar" `
  "$taskNative\RShopMigrationCacheSnapshot.class"
adb -s bfa98654 push "$taskNative\rshop-s7-cache-snapshot.jar" `
  /data/local/tmp/rshop-s7-cache-snapshot.jar
```

Require each command to exit zero; do not push an older jar after compilation
failure. The helper accepts only a validated platform and nonnegative 64-bit row
cursor, no SQL or database path. Its `rshop.s7.cache.v2` contract limits each page
to 128 artifacts / 900,000 UTF-8 input bytes and catalogue states to 256 / 65,536
bytes before constructing the result; oversized pages are rejected, not silently
truncated. The 1 MiB transport cap remains unchanged. A 100,000-row census bound
guards pagination, not a larger response buffer. The host retains only exact
names enumerated under the inspected SD root, bounded to 16 MiB of serialized
artifact records; all other records are discarded after validation. No ROM body
enters Windows memory. Plain SQL concatenates already-serialized records; the
host validates complete JSON and exact ordered row cursors. Android's SQLite on
this Thor has no JSON aggregation functions, so they are not required. Recompile
the helper from current source before use; v1 output is deliberately rejected.

For a local inventory before cloud/retention verification, append
`--inventory-only`. This mode does not read the app database/config or hash ROMs:
it records exact paths, sizes and before/after file stats. ROM records explicitly
say `cloud_not_observed` (or `local_changed`); non-ROM files remain preserved.
The private journal has no cloud identity/digest proof and cannot authorize a
removal. It works independently of an unpublished scan or a catalogue larger
than a host database-copy buffer. Never copy a live database to pretend this
inventory proves recovery. The separate cloud comparison requires the prepared
native helper for a consistent, bounded cache observation.

Inventory-only mode also permits an explicitly inspected SD `.../Roms` root;
use a noncanonical scope label such as `--platform sd-inventory` there. Directory
and extension counts are observations, not game identities or Top membership.
Paths are NUL-enumerated and stat requests are sent in batches of at most 64
paths / 16 KiB of UTF-8 command data. Android's `find -exec ... +` may exceed its
argument limit, so it is not used for the stat stage. Each response must return
every exact requested path in order; malformed/missing/out-of-root observations
abort without a completed journal. Spaces, quotes and embedded newlines remain
path data, not commands. Links and changed files are preserved.

Focused host contracts (synthetic, no device/network):

```powershell
cd scripts
python -B -m unittest test_thor_migration_audit
```

The classification lookup's focused, network-free scalability contract runs via
`python -B -m unittest test_catalogue_classification_query`. It extracts the actual
LibraryStore SQL/schema and observes completed SQLite VM steps, not elapsed time
or a cancellation deadline. Unpublished catalogue growth must not make a single
published-artifact lookup scan the whole collection; exact scope/generation and
ambiguous-root semantics must remain unchanged.

## Bounded canonical retention observation

`RShopRetentionSnapshot.java` observes the exact production retention SQL on the
native app cache. Compile/push it like the cache helper above, substituting this
class and `rshop-s7-retention-snapshot.jar`. It accepts only a platform slug and
numeric page offset through 100,000 (fixed page size 128), uses the fixed READONLY
app database, and rejects identities over 4 KiB or output over 1 MiB. Run javac,
D8 and the native observer with explicit 128 MiB heaps; no Gradle is required.
Keep its private output
outside Git; only aggregate counts belong in the public verification ledger.

```powershell
adb -s bfa98654 exec-out sh -c "run-as com.darkaxt.rshop.debug sh -c 'CLASSPATH=/data/local/tmp/rshop-s7-retention-snapshot.jar app_process -Xmx128m /system/bin RShopRetentionSnapshot psx 0'"
```

Validate the complete JSON and schema `rshop.s7.retention.v2`; Android's shell
exit status alone is not reliable evidence of helper success. An error object,
dirty projection counts or incomplete binding/rating coverage is not a valid
retention decision. The helper does not refresh the projection; only the normal
app query does that. No automatic retry, repair or provider request is performed.
Canonical ranks identify group membership, not borrowed edition ratings. This
observation cannot authorize removals even when the cache is current: exact
local/cloud identity, tested recovery and all other MIGRATE-01 gates still apply.

The host validates every page and duplicate edition identity across the complete
console scope, but the normal audit retains bindings only for exact cloud keys
associated with the inspected SD artifacts. The census is capped at 100,000
members, observed edition identities at 16 MiB, and retained serialized bindings
at 16 MiB; these are independent of the 1 MiB per-page transport cap. Changed
summary counts, duplicates, malformed identities, oversized pages or incomplete
coverage abort the observation even for discarded unrelated rows. Pages remain
separate observations, not an atomic collection snapshot or deletion authority.
Normally pause/join the metadata writer before this native read, then resume the
same saved job afterwards; do not overlap an external reader with app writes.
## S25 classified packaging collection

`prepare_packaging_resources.py` prepares one console's existing, distinct ranked
Top 25 (or the smaller eligible set) from a stopped-app, read-only projection.
The first supported console is GBA. It does not change rankings, create games,
write ROMs or upload directly to Drive. Use `fixtures/packaging_collection_snapshot.py`
for the exact device-bound snapshot; keep the projection and reports private.

```powershell
python -B scripts/prepare_packaging_resources.py --system gba `
  --projection <private-projection.db.gz> --launchbox <Metadata.zip> `
  --env .env.local --output <gba-packaging.zip>
```

LaunchBox's official metadata index supplies exact-platform/title matches and
same-region front/back/spine candidates. For each needed/replacement face, request
both LaunchBox and ScreenScraper candidates and select the better compatible image,
retaining original bodies, hashes and selection reasons. ScreenScraper also supplies
available PDF manuals using the already bound provider ID. PDF pages
become ordered, bounded PNGs. Horizontal spines are normalized upright, with the
original source hash and rotation retained. Missing resources remain missing.
The stored ZIP contains a versioned identity-bound manifest and hash-addressed
normalized PNGs, never API keys or ROM bytes. Sources and the retained original
PDFs stay in the desktop reference cache. NintAndBox print/fold templates require
classified panels; never stretch an entire sheet onto one face or mix editions.

In Game metadata > Storage, **Import prepared resources** streams the reviewed ZIP
through the existing shared metadata store. Its normal Drive publisher places
`box.png`, `box-back.png`, `box-spine.png`, `outer-box-*.png` and ordered
`manual-page-001.png` resources beneath the existing per-game resource directory.
The cache keeps its existing 2 GiB default. Browsing a cover does not fetch all
manual pages; opening Resources recovers missing gallery media from Drive with
digest verification. Collect media also retains ScreenScraper's extra packaging
faces through the same durable/cloud lane.

`fixtures/packaging_resource_sheet.py` makes diagnostic contact sheets of a pack
for visual review. These sheets are evidence, not replacement product artwork.

# Signed Android release

Set `JAVA_HOME` to the existing compatible JDK. Create the private signing identity
once with `./scripts/release_signing.ps1 -Create`; never regenerate it for an
update. Retain the keystore and recoverable password privately. The generated
credential XML is Windows-user/DPAPI bound, so copying that XML to a different
computer alone is not a portable password backup.

Run `./scripts/build_release.ps1 -FlutterCommand <flutter launcher> -ThreadName
'<actual conversation title>'`. It performs Flutter's official release
`--config-only` preparation (without `--no-pub`, which skips plugin regeneration),
rejects a stale debug-plugin registrant, loads private signing and submits the
release tests/assembly once through the installed shared Gradle gate. Observe
that original request to completion. Do not invoke Gradle directly.

Keep `app-release.apk`, display name `R-Shop` and package `com.darkaxt.rshop`.
Verify APK version, non-debuggable manifest, signer, hash and absence of private
credentials; publish from an exact committed source/tag and independently verify
the downloaded GitHub asset. Provider credentials and source configuration are
per-device, never compiled into the public APK. The private signing environment
is not an application API-credential injection mechanism.

# Explicit Windows metadata crawling

`run_metadata_crawl.ps1` runs the existing ScreenScraper adapter under standalone
Dart, without a running APK or Flutter engine. It uses the Android bounded 7z
validator's actual Java source, shared matching models, PNG integrity checks and
physical-label ambiguity rules. No provider logic or credentials are compiled
into an APK for this operation. The optional Android collector remains available.

Prepare a private manifest with `prepare_metadata_crawl.py --cohort <JSON>
--artifacts <read-only-NDJSON> --root "nes=<mounted ROM root>" --root
"gba=<mounted ROM root>" --output <private E: manifest>`. The artifact snapshot
must finish with an explicit read-only end record. The recorded source-relative
path distinguishes repeated archive basenames; missing recorded copies and genuinely
ambiguous names remain gaps rather than selecting another copy. Nested Disk System
media inside the NES root remains inventoried but cannot acquire an automatic NES
cartridge binding. Parenthesized/bracketed modification markers also constrain
automatic binding without inventing a classification. The helper lists filenames
only and does not open ROM bodies.

Then invoke `run_metadata_crawl.ps1 -Manifest <manifest> -OutputDirectory
<E: cache> -RuntimeDirectory <task-owned D: scratch> -DartCommand <installed Dart>
-JavaHome <installed JDK> -XzJar <existing pinned org.tukaani:xz 1.12 jar>`.
The existing ignored `.env.local` or process environment supplies ScreenScraper
credentials; do not pass their values on the command line or publish outputs.
Run the launcher again with the same manifest/output to resume. It binds the
checkpoint to the exact manifest, locks its output, preserves successful lookups
and per-resource outcomes, and checks retained content hashes before reuse.
Current output/checkpoint version 2 includes bracketed ScreenScraper support
selectors. Version 1 outputs were parsed before this correction and cannot resume
as current resource coverage: retain them as evidence and use a new output folder
to recollect affected matched records. The input manifest remains version 1.
Validated raw evidence has its own artifact-bound receipt, written before provider
requests, so an interrupted artwork phase reuses that evidence without spending
the ROM-read budget again. A reserved read interrupted before evidence is committed
still consumes its conservative budget; use a deliberate new run if more reads
are required.

H: is cloud backed Google Drive, not an offline ROM disk. Persistent crawler
cache/checkpoints/artwork belong on E:. Default `-MaxArchiveBytes 0` performs only
metadata requests. An explicit positive budget permits targeted archive evidence
reads within the cumulative sum of selected compressed archive sizes. This is a
logical input-size budget, not measurement or a guarantee of actual network
traffic: DriveFS owns hydration and caching. Archive contents are streamed and
never installed, extracted to disk, changed or copied into metadata publication.
Before using a raw member identifier, the reader verifies the complete container
against every known Drive digest/size, validates its archive/ROM structure, and
rechecks the container after reading. Modified/aftermarket/prototype filename
markers restrict automatic raw binding; they do not assign official status.

The worker prints committed processed/total/remaining item counts. Provider API
calls are not resource coverage. Protocol rate/quota waits remain enforced;
authentication, transient or quota failures retain the original operation and
return a non-success status instead of automatically retrying. Saved review and
unmatched outcomes are retained, not promoted to matches. Use a new deliberate
manifest/output for a changed request or read budget.

Outputs are private acquisition receipts, records and content-addressed validated
PNG bodies. Carton faces retain their source region; a preferred reference face
is not proof of an exact retail printing. Genuine personalized-label ambiguity
remains unresolved. This worker does not directly rewrite application SQLite,
change saved Android jobs or write arbitrary `metadata.json` into H:. Final
resources still pass the existing identity-owned import/publication/recovery
lane, including Drive ownership/app-property/digest checks, before they count as
integrated. Never place cache files, credentials or ROM inventories on H: as a
substitute for this final gate. Preserve NintAndBox carton construction in the
separate packaging collector; a metadata crawl does not supersede carton preparation.

Prepare completed archive-bound results for the normal application lane with
`prepare_desktop_crawl_import.py --census <complete clean read-only NDJSON>
--manifest <same crawl manifest> --crawl <E: output> --output <new E: pack folder>`.
It captures the committed checkpoint, verifies exact artifact/image ownership and
writes stored ZIP batches of at most 25 games. In Settings / shared metadata
storage, **Import prepared resources** accepts multiple packs sequentially. The
app rechecks current identities and artifact versions, performs normal fresh
provider matching using the validated raw evidence and publishes through its
existing metadata/Drive lane. Imported image reuse stays edition/artifact scoped;
it is not relabelled as a fresh provider-body response. Existing saved jobs remain
unchanged. A paused/blocked import stops the batch and retains its normal job.
Preparation, a successful import and final verified publication/recovery are
different outcomes; never count pack membership as usable coverage.

For an actual completed exact raw-ROM response, `--reuse-lookup` additionally
retains its captured request/record/evidence and excludes ratings. The current app
validates those facts against the current artifact/edition and runs the normal
durable metadata and artwork jobs without a second provider access/lookup. The
original retrieval time remains unchanged; only the local job generation changes.
This explicit mode pauses if its retained response or required body is missing
or changed. It never silently spends another request. Legacy packs still use
fresh provider matching; existing saved jobs are not rewritten. Publication and
recovery remain the same required normal lane.

After a resumed crawl adds results to a previously committed preparation, repeat
`--edition-id <current manifest edition>` to prepare only the verified delta.
Selection rejects missing, duplicate or stale current editions before producing
output. The receipt retains the unchanged full checkpoint, total manifest count,
selected membership and unselected identity reviews; a subset is never reported
as full coverage. Verify the earlier preparation's source/pack identities and its
normal commit receipt before excluding those editions. This does not complete or
cancel an earlier publication, alter its saved job, or authorize a second crawl.

When review disproves a provider identity despite its reported raw-hash match,
use `--review-holds <JSON>` with `{"version":1,"holds":[{"key":"<item SHA-256>",
"sourceSha256":"<retained result SHA-256>","reason":"<observed conflict>"}]}`.
Preparation retains the original checkpoint, excludes that exact record from
import, and records the hold separately from missing artwork. Changed source
bytes, unowned keys and unused selected reviews fail rather than silently reusing
a stale decision. Reviews outside an explicit edition subset remain recorded as
unselected reviews. Do not replace the provider ID from an artwork title alone.

For needed/replacement box faces, `prepare_packaging_resources.py` now acquires
both LaunchBox and ScreenScraper candidates. It preserves original image bodies
in the E: HTTP cache, reports dimensions/detail measurements, all candidate hashes
and the chosen source. `--quality-review <private JSON>` supplies reviewed choices
as `{gameId: {role: {sourceId, sourceSha256, reason}}}`. A changed/missing reviewed
image fails explicitly. Otherwise the measured nomination remains labelled as
requiring the visual sample; it is not a claim of accepted quality. Review real
legibility, cropping, damage/glare, printing and colour continuity; resolution
alone cannot decide. The existing NintAndBox donor/colour path remains in place.
Blank/transparent provider placeholders are rejected before nomination, including
solid green images with at most two levels of channel noise. This check does not
reject explicitly reconstructed plain carton faces. When no valid original-region
carton face remains, the collector checks the same resolved LaunchBox game's US/EU
faces and preserves source-region/composite provenance. That fallback never binds
labels, changes ROM identity or proves an exact physical printing.
Donor composition preserves the selected face; distinct English alternatives
must be resolved upstream instead of being reordered by provider during fitting.
LaunchBox names canonicalize No-Intro's relocated articles (also before subtitles)
without deleting them, changing console scope or resolving ambiguous IDs by guess.
The fixed public image origin accepts validated `.jpg`, `.jpeg` and `.png` leaves.
`--crawl-artwork <completed Windows output>` seeds validated acquired face bodies
into that response cache to avoid repeat API requests. It does not import facts,
classifications, acceptance or publication. Support textures and shell-inclusive
cartridge pictures remain different roles.

### Reuse audited catalogue IDs

For advance filename-only mapping across supported systems, use
`prepare_collection_catalogue.py`. Its explicit `catalogue_platforms.json` names
LaunchBox namespaces and mounted-folder aliases; app system IDs, ROM extensions
and ScreenScraper IDs are checked against the current Dart registries. H: is read
for filenames only. Use existing local indexes, successful cached provider
responses and reviewed decisions before requesting missing remote evidence.
Temporary acquisition stays in exact E: task scratch; maintained mapping data
and its required hash-bound inputs belong on D:. No device, APK, ROM bodies,
artwork or per-ROM API requests are needed for the local filename pass.

```powershell
python -B scripts/prepare_collection_catalogue.py inventory --root <mounted-rom-root> --output <inventory.json>
python -B scripts/prepare_collection_catalogue.py indexes --inventory <inventory.json> --launchbox <Metadata.zip> --cache <E-cache> --output <indexes.json>
python -B scripts/prepare_collection_catalogue.py match --inventory <inventory.json> --index <indexes.json> --output <mappings.json>
python -B scripts/prepare_collection_catalogue.py match --inventory <inventory.json> --index <indexes.json> --title-aliases <reviewed-rules.json> --output <reviewed-mappings.json>
python -B scripts/prepare_collection_catalogue.py verify --mapping <mappings.json>
```

Repeated `inventory --exclude-system <id>` preserves independently reviewed
systems. Every included source retains its exact system/relative path, provider
IDs/platform, index hashes and a candidate or unresolved outcome. The verifier
rechecks complete source membership and exact canonical/declared-alias evidence;
`verify --system <id> --source-path <folder/relative-file>` resolves one source.
NES `Disk System` files resolve in FDS, including when the standalone FDS folder
is empty; promotion retains their NES owner and FDS media namespace. Report
LaunchBox, ScreenScraper, both, either and neither separately across the full
census. Candidate bindings do not establish physical-edition or artwork coverage.
Matcher version 2 also uses provider-declared `romNames` when title
matching is unresolved. It keeps revision/region tokens and supports typed
e-Reader card codes/names in namespace 119. The input index and review evidence
must own those names; no ROM bodies are needed. e-Reader rows are `card-data`,
so normal cartridge-artwork owner promotion leaves them explicitly unpromoted.
Older maps without `matcherVersion` replay version 1. Publisher/author qualifiers and SG-1000/SC-3000 collisions are resolved
only with explicit source tags or the library platform, retaining unresolved
same-platform collisions. A generic matching improvement must not invalidate an
immutable older map's replay.
Current producer output records matcher version 9. Version 3 adds exact whole-token
multi-letter Roman/Arabic sequel spelling and HTML entity decoding while
preserving single-letter I/V/X and literal trailing `#` editions. Direct lookup
and cross-provider corroboration share that spelling key; exact canonical
corroboration runs first and cannot be displaced by an expanded candidate set.
It does not strip subtitles, hack/DX/EX words or attach Download Play/Multiboot
components through these spelling repairs. Ambiguous expanded results remain
unresolved. Version 4 applies explicit publisher/author qualifiers to both
providers and tries a separate lookup without trailing numeric three-part
version/date annotations only after ordinary unresolved matching. Exact version
records take precedence; named modifications and Download Play/Multiboot sources
are not simplified. Version 5 permits missing-provider Game Boy lookups only for
GBC program sources explicitly tagged `(GB Compatible)`. Native GBC resolution
and corroboration run first, and an ambiguous native result or explicit exclusion
cannot be replaced. The provider retains its actual GB platform and records
`catalogueNamespace: gb`; the library source and promoted owner remain GBC.
Consumer admission rejects unrelated or untagged namespace overrides. Versions
1 through 4 retain their original replay semantics. Version 6 permits an evidenced
exact-source correction with the single rejected ID in `replacesProviderIds`;
ordinary reviews still cannot replace a unique canonical heading. Version 7
admits source-scoped GB/GBC programme namespace reviews with hashed evidence,
actual provider platform fields and preserved library ownership. It cannot
replace native resolution or restore an excluded provider. Version 8 preserves
canonical-before-alias priority within expanded numeral/entity keys, including
numeric release-annotation lookup. A colliding alias must not hide a unique
canonical heading; duplicate canonical headings remain unresolved. Versions 1
through 7 keep their immutable replay semantics. Version 9 can resolve a complete
canonical heading formed from the source title and one explicitly present source
tag after an unmatched/spacing result. This handles qualified catalogue headings
that declare no unqualified alias, including publisher and Family BASIC variants.
It does not infer a missing tag, replace a unique native match or expand Download
Play/Multiboot/firmware lookups. Version 8 replay remains unchanged.
Duplicate catalogue representatives require an exact-source review with retained
full records/ROM lists. Equal filenames with different hashes are not byte-identity
proof; a regional programme reference does not establish its physical packaging.
Scoped parsing handles DS numeric and x/z scene release numbers, 3DS title-ID/
container decorations, short country tags, PSP Minis and tagged 64DD translations.
SNES collection indexes also retain Nintendo Satellaview; broadcast lookup must
not replace an established SNES canonical match without an explicit reviewed
episode refinement. Real word boundaries, numeric operators and non-Latin titles
survive. Blank index rows stay diagnosed without discarding the platform;
duplicate IDs fail. Firmware, updates, DLC, modified programs, auxiliary archives
and unrecognised app containers remain distinct, visible source entries.

LaunchBox alternate-name regions are retained and can disambiguate an exact
regional alias. Review actionable spacing, segmentation and reordered-subtitle
candidates rather than leaving them indefinitely unresolved. Record decisions in
the optional version-1 `--title-aliases` JSON: `evidence` contains path/SHA-256
receipts; each `rules` entry names `system`, `sourceTitle`, `reason` and
`providers` (provider name to exact `id`/`title`). Optional `regions`, `tags` and
`sourcePaths` restrict a decision to its actual release/revision and exact source
membership. Use exact source paths for retail versus demo/Download Play records;
matching title text alone must not spread a reviewed choice to those variants.
`blockedProviders` excludes a
documented contradictory provider grouping. Rules cannot override an existing
unique canonical/declared-alias result, reference foreign platform IDs or overlap
for the same source. The mapping captures the rules hash; verification checks its
evidence and replays every decision. Do not globally remove word boundaries or
reorder title words. A provider hash match with a compressed-size discrepancy, or
a name-only fallback with different hashes, must retain that distinction in its
review evidence instead of claiming an exact raw-ROM match.

When retained catalogue exports omit a release, a current official platform search
can supply additional canonical/regional-name evidence. Keep the response hash,
actual platform ID and review decision with the projected record; a search result
alone is not acceptance. Filter foreign-platform results even when the request was
platform-scoped. Empty result sentinels and rejected short queries are distinct
from a proved absent game. Preserve exact-source negative decisions so a later
alias import cannot restore a previously rejected edition. Replay the complete
consumer and account for every changed old ID, including documented refinements
from a series record to its exact episode. Keep prior delivered maps immutable.

When a real owner census exists, reuse the result through the normal producer:

```powershell
python -B scripts/prepare_catalogue_bindings.py --filename-mapping <mappings.json> --census <clean-census.ndjson> --launchbox <Metadata.zip> --output <owner-bindings.json>
```

Promotion requires a unique current Drive artifact and edition, preserving their
version/checksums/owner. Missing owners stay unpromoted; firmware, updates, DLC and
auxiliary archives cannot become program-artwork owners. The collector's edition,
modification, resource-review and publication gates remain. A title candidate is
neither a raw-ROM match nor accepted physical-resource coverage.

`prepare_catalogue_bindings.py` joins a complete private title-index audit to the
actual clean native census by current Drive artifact and edition membership. It
checks provider IDs/titles against the captured LaunchBox platform index and
ScreenScraper public `screenscraper-<platform>-gameslist.csv` exports beside the
title index. It retains every source as a candidate binding or an unresolved
result. Optional reviewed manual overrides are JSON, with exact archive SHA-256,
reason and hash-bound evidence; ambiguous/loose matches are never guessed.

```powershell
python -B scripts/prepare_catalogue_bindings.py --audit <title-match-details.json> `
  --census <clean-census.ndjson> --launchbox <Metadata.zip> `
  --title-index <launchbox-title-index.json> --manual <reviewed-manual.json> `
  --output <private-bindings.json>
python -B scripts/prepare_packaging_resources.py --system nes --selection collection `
  --catalogue-bindings <private-bindings.json> --binding-census <clean-census.ndjson> `
  --launchbox <Metadata.zip> --http-cache <existing-E-response-cache> `
  --env .env.local --output <private-packaging.zip>
```

The binding JSON supplies the exact provider ID, including NES sources routed to
the Famicom Disk System catalogue, while output keeps the original library
platform/game/edition and owner identity. Changed index/census/source/edition
bindings, foreign IDs and changed titles fail before acquisition. Without
`--projection`, collection selection reuses the captured clean native query and
metadata rows; it never copies a running SQLite database. With `--projection`,
the existing selection must agree with the captured binding identity.

An artwork candidate does not overwrite existing ROM-matched metadata, ratings
or classification. A conflicting retained ScreenScraper identity remains visible
in the report. A bound, unmodified game with unknown edition region may acquire
reference carton faces under the existing composite policy: the original edition
regions stay empty, imported reference art uses `wor`, and actual source regions
remain in provenance. This does not resolve physical printing, permit cartridge
labels/manuals under an unknown region, or count as native acceptance. Modified
sources and absent bindings retain their explicit unresolved gates. Prepared packs
still require review, normal import/publication, recovery and native validation.

The producer also fills a missing provider from the other provider's exact
canonical/declared name, within the same platform. It retains the anchor ID and
word boundaries; a loose name collision or absent anchor does not become a match.
This links both artwork catalogues without another search/download or a new ROM
identity claim. Reviewed original donor faces also supply absent flat gallery
roles, preserving their prepared pixels and provenance when no replacement exists.

`--prepared-resources <reviewed-preparation.json>` keeps complete previously
reviewed packs in their existing delivery queue. It verifies pack content hashes,
current owner identity and all nine carton/gallery roles before skipping duplicate
acquisition. Its report says those resources still await delivery; it does not
claim that preparation is publication. Use retained NintAndBox `--panel-layouts`
for the remaining bound donors before provider acquisition.

After a reviewed binding correction, repeat `--edition-id <current-edition-id>`
with `--selection collection` to acquire only the affected real query members.
Unknown/duplicate IDs fail before acquisition. The selection and batch receipts
retain `coverageScope: selected-editions`, the full `collectionSelected` count and
the exact `editionFilter`; this subset never replaces the full collection census
or establishes full-collection completion. Resume checks the unchanged filter as
well as the original source/index/owner inputs.

LaunchBox artwork country names retain their own region codes (including
Australia/Canada and individual European/Asian countries). If the target-region
and existing English/world reference tiers have no usable face, a compatible
same-game regional donor can supply a reference face. Preserve its source region
and composite provenance; never relabel that printing as English or as the target
SKU. Broad unmapped areas such as Oceania/South America are not silently assigned
to a particular country. Cartridge labels remain outside this carton-only rule.

`--resume` continues the same full-collection output at its committed 25-item
boundary. Selection, index/review inputs, report identities and every committed
pack's bytes/hash must agree. Changed inputs or an uncommitted output require
inspection. Completed packs are kept byte-for-byte, while cached responses from
an interrupted tail remain reusable. No arbitrary retries or alternate job are
started automatically.

Model-baking preparation uses `normalize_role_image(role, body)` from the same
collector to keep horizontal-spine rotation and normalized PNG bytes together.
An explicit hash-bound quality review may include `rotationDegrees` to correct
an inspected selected source face. Pass it as `clockwise_rotation` when using
the helper directly; retain its original-source digest and returned rotation.
Preserve its returned rotation in provenance. The colour-cast helper also requires
its held-out prediction to beat a constant-colour baseline; otherwise a low-detail
regional back can spuriously reward erasing the selected artwork's contrast.

The Windows crawl can reuse exact typed provider-image receipts with
`run_metadata_crawl.ps1 -ReuseArtworkDirectory <completed version-2 crawl>`
(`crawl_metadata.dart --reuse-artwork`). It verifies size/hash before reuse and
keeps provider, region and indexed member identity separate; conflicting cached
bodies require a fresh request. Each ROM still receives its own matching evidence.
Reused images retain their source receipt rather than claiming a fresh response.
`prepare_metadata_crawl.py` records source-path `physicalResourceFamily` separately
from `allowRawBinding`: a program match does not establish retail media for GBA
Multiboot/e-Reader or Disk System inside NES.

Carton OCR is advisory: `prepare_console_model.py` always writes `model.json`
and records `cartonTextOrientation`; on `CARTON_TEXT_REVIEW_SUGGESTED`, look at
the retained `text-orientation/` views and fix only genuine panel faults.

`prepare_retained_nes_panels.py` carries unchanged selected NES cartons through
the same packaging import lane. Supply the selected catalogue, retained source
library, actual native manifest/hash receipt, reconciled binding list and a new
output directory. It checks source GLB, native manifest and every crop digest,
then prepares the six outer faces plus matching flat front/back/spine roles.
The optional `--panel-review` supplies model-ID entries with `manifestSha256`,
`reason`, `nativeAssembledEvidence` and per-face `sourcePanel`, `sourceSha256`
and orthogonal `clockwiseDegrees`. Use it only after inspecting the actual mapped
native faces; a compensating UV/name mapping must not be undone in the mesh.
Preparation does not establish canonical ownership, publication or native acceptance.
Compare existing complete packaging choices and bind these candidates only to a
fresh clean census through the normal import and Drive verification workflow.

The full catalogue residual review preserves exact source paths when applying
manual naming decisions. DS `xNNN`/`zNNN` prefixes are scene decorations only in
the DS namespace; tagged 64DD translations keep their hardware namespace. SNES
includes the original Nintendo Satellaview records with broadcast-scoped name
corroboration, so their aliases cannot leak into an ordinary retail source.
`source_kind` retains firmware/DLC/update/auxiliary roles, including the untagged
SNES SuFami Turbo BIOS. Provider name-search candidates supplement an index only
after actual platform/ID validation; they do not establish raw ROM or physical
printing identity. Hash-bound exact-source review rules and the full mapping
consumer remain the delivery boundary.

# Windows catalogue publication

The Drive metadata tree is the shop catalogue (CATALOGUE-READONLY-01). Publish
it from Windows into the Google Drive for desktop folder; clients only read it.
`GSHOP_STORE` is a copy of the shared store (`metadata.sqlite`, `artwork/`,
`preview-videos/`, `records/`). Unchanged resources (name, sha256, bytes and
on-disk size) are skipped; replaced and stale role files move to `_previous/`.

```powershell
$env:GSHOP_STORE = 'D:\RShopPrivate\CatalogueStore'
$env:GSHOP_CATALOGUE = 'H:\My Drive\R-Shop Metadata'
$env:GSHOP_PLATFORMS = 'gba,psx'   # optional
$env:GSHOP_DRY_RUN = '1'           # optional: report only
$env:GSHOP_SUMMARY = 'D:\RShopPrivate\catalogue-summary.json'  # optional
flutter test tool/publish_catalogue_test.dart
```

`D:\RShopPrivate\CatalogueStore` is the Windows master store (first copied from
Thor's `ES-DE/RShopMetadata`, hash-verified). Run tests and these tools with
`--concurrency=1` through the pipeline gate.

## Windows prepared-pack import

Prepared packaging packs are imported on Windows into the master store, then
published. The importer validates each pack against a library projection
database (`library_editions`/`library_game_identities`) and fails closed per
pack if the collection changed since preparation. Desktop-evidence packs made
with `prepare_desktop_crawl_import.py --reuse-lookup` run the app's
`desktop-provider-import` metadata and artwork jobs from the retained exact
response, with no ScreenScraper request (the tool's provider has no
credentials). A stopped job blocks the remaining packs. Packs that would need
a live lookup are reported, not imported. Each pack takes about 40 s after a
~1 min projection restore; import at most ~10 packs per gated run.

```powershell
$env:GSHOP_STORE = 'D:\RShopPrivate\CatalogueStore'
$env:GSHOP_PROJECTION = 'D:\Temp\<task>\projection.db'   # decompressed private projection
$env:GSHOP_PACKS = 'D:\RShopPrivate\ResourceCandidates\<delivery>'
flutter test --concurrency=1 tool/import_packs_test.dart
```

## Windows artwork hydration

`tool/hydrate_artwork_test.dart` downloads the ScreenScraper image bodies the
master store records but never fetched (the publisher's "missing local body"
list; videos excluded). It runs the app's artwork jobs with the real account
from `.env.local`, so the job runner's quota pacing applies (20,000 requests a
day on the current account). A quota block ends the run cleanly; rerun later and
the missing set is recomputed from the store. Optional: `GSHOP_PLATFORMS`
(comma list, default all), `GSHOP_BATCH` (editions per job, default 100),
`GSHOP_MAX_JOBS`. flutter_test fakes every HTTP request with status 400, so the
tool clears `HttpOverrides.global`. Do not read the store or projection
databases while it runs (a reader's lock fails its commits); read a copy.

```powershell
$env:GSHOP_STORE = 'D:\RShopPrivate\CatalogueStore'
$env:GSHOP_PROJECTION = 'D:\Temp\<task>\projection.db'
$env:GSHOP_CREDENTIALS = '<repo>\.env.local'
flutter test --concurrency=1 tool/hydrate_artwork_test.dart
```

## Windows archive identification

`tool/identify_archives_test.dart` gives never-installed 7z ROMs the same
checksum evidence the device reads from a locally installed archive
(OwnedN64SevenZip): the file on the read-only Drive mount must match the
catalogue artifact's size and checksums and hold exactly one ROM member, whose
CRC32/MD5/SHA-1 are computed in full. The normal ScreenScraper metadata job then
runs with unchanged matching rules; accepted records bind the editions (run
hydration afterwards for their image bodies). Translations, hacks and other
tagged editions stay excluded by the job itself. `GSHOP_EDITIONS` = JSON list
of edition ids; optional `GSHOP_ROMS` (default `H:\My Drive\Roms`), `GSHOP_7Z`,
`GSHOP_BATCH`. Same store/projection/credentials setup as hydration; never run
both at once (shared projection, one ScreenScraper thread).

## Windows facts import

`tool/import_facts_test.dart` writes sourced "Did you know?" facts (spec
revision 190, COVERAGE-FACTS-01) as one `facts` record per edition from
`GSHOP_FACTS` = `{"editions": {"<editionId>": [{"text": "...", "source":
"https://..."}]}}`. Every fact needs an https source. The app shows the facts in
the idle "Did you know?" rotation; the census counts e-Reader and Multiboot
entries once they have one. Same `GSHOP_STORE`/`GSHOP_PROJECTION` setup; publish
afterwards.

`tool/import_references_test.dart` gives a digital re-release that lacks a
carton or cartridge label the original retail edition's already-selected media,
as one `reference` record, from `GSHOP_REFERENCES` = `{"editions":
{"<editionId>": {"referenceEdition": "<retail editionId>", "roles": ["carton",
"label"]}}}`. Faces come from one provider record; the media are unchanged, so
they reuse the retail bodies. The app ranks `reference` first and skips the
re-release's region filter for it; the edition's facts say the carton is the
retail release shown as a reference.

## Host model readiness check

`scripts/check_models.py ROOT` validates a private models tree in the device
layout (`RShop/models/...`) without the APK: mesh geometry hash, surface and
index ranges, texture presence/receipts/hashes, motion data per model, NES box
catalogue and Game & Watch variants resolution, and every model key the app
expects (NES cartridge styles are read from `nes_cartridge_model.dart`). Exit 1
lists each problem. Run through the pipeline gate.
