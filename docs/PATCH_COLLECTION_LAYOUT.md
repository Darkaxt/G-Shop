# Collection layout and portable patch recipes

R-Shop reads the collection's existing **schema 2** JSON indexes. Originals,
playable hacks and patch resources are different things; a `.ips` is not a game.
No changes to the current Drive folders are required for this layout.

## Folders

Paths below start at the configured ROM collection root, not the console folder,
Windows drive letter or Android SD mount. Console names are your configured names.

```text
<Console>/Original Game (Region).7z
<Console>/Hacks/<Project>/<Playable ROM>
<Console>/T-En/<Translated ROM>
<Console>/Patches/index.json
<Console>/Patches/<Game>/game.json
<Console>/Patches/<Game>/<Source>/index.json
<Console>/Patches/<Game>/<Source>/<Patch>/<extracted patch files>
```

Direct files under `Hacks` work too. Configure folder/category mappings for other
names; do not rename a working collection just to copy this example. Commercial
shows originals, Hacks shows playable modified games, and Patches shows supported
original games with their available patches. Utilities/readmes are not playable.

## Indexes

- `Patches/index.json`: `schema_version: 2`, a `games` list containing a producer's
  public `source_game_id`, `title` and root-relative `rom_root_relative_path` to
  each game index.
- Game index: the same schema/game ID, and `sources` entries containing `source`
  and a root-relative path to each source index.
- Source index: `source`, `source_game_id`, `sections.hacks` and/or
  `sections.translations`. Each entry has `source_id`, `source_fields` (title,
  version and description), and `rom_files` describing exact compatible bases.
- A base has `rom_root_relative_path`, `member_size`, `member_hashes`, and an
  `archive_member` when the original is inside an archive. Hash the uncompressed
  selected ROM member, not its `.7z` wrapper. Supported hash keys are `sha256`,
  `sha1`, `md5`, `crc32`; supply a cryptographic hash where available.
- `payloads` bind `section`/`source_id` to `patch_folder_relative_path` and
  `extraction: {status: "extracted", files: [...]}`. Each extracted file has
  relative `relative_path`, byte `size` and `sha256`. An unextracted installer
  cannot be used as a patch. Patches support the reviewed UniPatcher formats;
  unknown binaries remain unselectable, and readmes stay auxiliary.

Use `/` separators. Absolute paths, drive letters, `..`, backslashes and ambiguous
duplicate references are rejected. Keep existing producer fields when updating
an index; R-Shop does not rewrite your original JSON. Update patch versions,
payload hashes and base member fingerprints together when their bytes change.
Do not declare compatibility merely because two titles look alike. Current
indexes without dependency fields describe individual patches against an original.

## Dependent patches

Schema 2 accepts an optional `requires_patch` on a hack/translation entry. It pins
one immediate predecessor; prerequisites can themselves declare a predecessor.
This describes an ordered chain, not arbitrary combinations of independent mods.
The chain root retains `rom_files` for the original. Dependent entries can leave
`rom_files` empty; their input is the declared predecessor's verified output.

```json
"requires_patch": {
  "patch": {
    "source": "Example source", "section": "translations", "sourceId": "10",
    "version": "1.2", "format": "bps",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "options": {}
  },
  "output_size": 4194304,
  "output_hashes": {
    "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
}
```

The hashes above are illustrative, not compatibility declarations. Use reviewed
producer instructions and actual bytes when populating them. The predecessor
must be uniquely present in this game's indexed sources, with matching version,
format and patch SHA-256. Missing/ambiguous dependencies and cycles disable the
build. Never derive ordering from titles, file listing order or readme wording.
Every intermediate is checked against the successor's expected input before the
next application. Recipes retain those input contracts and the entire order.
EBP canonical preparation remains an explicit checkbox recorded in the recipe;
in a chain it applies only to EBP steps, never other formats or the original file.

## Suggestions before launch

Explicit console sync and Patches browsing prepare source/version-bound index
metadata locally. Launch checks use that cache and exact original artifact
references; they perform no network scan. A compatible offer precedes the launch
animation: original, installed build, or patch selection/build. Choosing an
installed result verifies it again, and matching complete recipes reuse output.
Original play remains available when catalogue evidence is unavailable. A missing
cache is unknown, not evidence that no patches exist; open Patches or sync to
prepare it. Existing modified ROMs with no proven base lineage remain accessible
in Hacks without guessed original-game suggestions.

Remembered choices are bound to the original's content version. Changed/missing
preferred builds return to selection rather than silently launching a different
game. Use **Reset launch suggestions** on this console's Patches page to clear its
saved choices. Cancel returns without starting the launch animation or emulator.
Patched outputs retain their own saves, companions and metadata. The distinct
hack-specific 3D animation is explicitly postponed; generation launch behavior
remains shared for now.

The [synthetic example](examples/patch-collection) contains indexes only, no ROMs,
patch binaries or private inventory. Its pretend four-byte ROM and hash values
illustrate the fields, not a downloadable game. The files can be placed beneath
any collection root without editing their relative references.

## Share or import a recipe

Open a game's Patches page, switch to **My builds**, and choose the share icon.
Android shares one `rshop.patch-recipe` JSON file. Import it using the file icon
on a console's Patches page; then **Check requirements** resolves the destination's
own configured collection. Choose **Build** only when the required original,
exact patch version and engine are available. Existing verified output is reused.
An imported recipe does not claim that a game is already installed.

Normalized recipes and verified result fingerprints live in `patch_recipes` in
the selected shared metadata folder's `metadata.sqlite`. Reconnect that folder
to recover them. Local installation/build/transfer recovery remains in the
device's private database. If shared storage disconnects, the ready local game
remains playable and its recipe publication is pending until reopening after
reconnection. A conflicting verified result is reported, never overwritten.

Public recipes contain only platform, producer game/patch IDs, names, relative
references, engine/preparation/options, content fingerprints and optional verified
output size/SHA-256. They contain **no ROM, payload binary, API key, OAuth token,
Drive file/account/source ID, signed URL, device path or installation/transfer
state**. Patch payload redistribution is not automatic. This is not whole-folder
cloud sync or the encrypted private migration feature.
