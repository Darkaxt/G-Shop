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
artifacts and catalogue generations in one SQLite statement, including WAL
state. Its single bounded result fits one cursor window. Configuration is read
before and after; changed config, invalid records, oversized output or a helper
failure aborts before a journal is created. No automatic retry or repair occurs.
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
failure. The helper accepts only a validated platform, no SQL or database path.
It limits artifacts to 2,000 / 900,000 UTF-8 input bytes and catalogue states to
256 / 65,536 bytes before constructing the result; excess rows are rejected, not
silently truncated. The 1 MiB transport cap remains unchanged. N64's measured
836,435 artifact bytes required a larger input bound than the initial 512 KiB;
it still fits the same output budget. Plain SQL concatenates already-serialized
records; the host validates the complete JSON before use. Android's SQLite on
this Thor has no JSON aggregation functions, so they are not required.

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
numeric page offset (fixed page size 128), uses the fixed READONLY app database,
and rejects identities over 4 KiB or output over 1 MiB. Keep its private output
outside Git; only aggregate counts belong in the public verification ledger.

```powershell
adb -s bfa98654 exec-out sh -c "run-as com.darkaxt.rshop.debug sh -c 'CLASSPATH=/data/local/tmp/rshop-s7-retention-snapshot.jar app_process /system/bin RShopRetentionSnapshot psx 0'"
```

Validate the complete JSON and schema `rshop.s7.retention.v1`; Android's shell
exit status alone is not reliable evidence of helper success. An error object,
dirty projection counts or incomplete binding/rating coverage is not a valid
retention decision. The helper does not refresh the projection; only the normal
app query does that. No automatic retry, repair or provider request is performed.
Canonical ranks identify group membership, not borrowed edition ratings. This
observation cannot authorize removals even when the cache is current: exact
local/cloud identity, tested recovery and all other MIGRATE-01 gates still apply.
