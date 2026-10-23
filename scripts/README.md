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
same-region front/back/spine images. ScreenScraper supplies compatible missing
faces and available PDF manuals using the already bound provider ID. PDF pages
become ordered, bounded PNGs. Horizontal spines are normalized upright, with the
original source hash and rotation retained. Missing resources remain missing.
The stored ZIP contains a versioned identity-bound manifest and hash-addressed
normalized PNGs, never API keys or ROM bytes. Sources and the retained original
PDFs stay in the desktop reference cache. NintAndBox print/fold templates require
classified panels; never stretch an entire sheet onto one face or mix editions.

In Game metadata > Storage, **Import artwork pack** streams the reviewed ZIP
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
must finish with an explicit read-only end record. Missing/duplicate exact names
remain gaps; they are never resolved by picking the first file. The helper lists
filenames only and does not open ROM bodies.

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
substitute for this final gate. Keep NintAndBox/LaunchBox precedence in the separate
packaging collector; a metadata crawl does not supersede carton preparation.
