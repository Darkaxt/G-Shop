# S7 private migration audit

`thor_migration_audit.py` is a read-only, one-time inventory aid, not a ROM
downloader, migration executor or ownership/adoption command. It compares exact
SD artifacts with the normal app's published Drive-cache records and streams
hashing on the device. It never reads ROM bodies into the Windows process.

Use an explicitly inspected console directory and keep its output outside Git:

```powershell
python -B scripts/thor_migration_audit.py --adb <adb.exe> --serial bfa98654 `
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

Config reads are capped at 1 MiB, database observations at 64 MiB, and device
shell output at 8 MiB. Inconsistent catalogue observations fail without repair
or automatic retry. One client runs at a time; there are no arbitrary deadlines.

For a local inventory before cloud/retention verification, append
`--inventory-only`. This mode does not read the app database/config or hash ROMs:
it records exact paths, sizes and before/after file stats. ROM records explicitly
say `cloud_not_observed` (or `local_changed`); non-ROM files remain preserved.
The private journal has no cloud identity/digest proof and cannot authorize a
removal. It works independently of an unpublished scan or a catalogue larger
than the comparison mode's 64 MiB observation cap. Do not increase that cap or
copy a live database to pretend this inventory proves recovery. The separate
cloud comparison still requires a consistent, bounded cache observation.

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
