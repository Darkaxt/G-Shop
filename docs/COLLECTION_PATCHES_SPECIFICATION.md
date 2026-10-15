# Collection navigation, rankings and reproducible ROM patching

Authoritative extension to SPECIFICATION.md revision 54. Revision 1, 2026-10-15.
Authorization: already_authorized; owner requested the full specification and
implementation, then explicitly authorized useful ROM-folder reorganization in
Google Drive and requested evaluation of UniPatcher. The owner subsequently
authorized making the combined product as open as needed, including a
GPL-compatible release, requesting Darkaxt attribution. No design-approval checkpoint.

## 1. Outcome and boundaries

Browse manufacturer -> system type -> console -> Commercial/Hacks/Patches.
Consoles appear chronologically; games feature up to the collection's best 100
before the alphabetical remainder. Patches presents compatible games, lets the
owner build and play a modified ROM, remembers its exact recipe and recognizes
an existing result. Reuse the JSON indexes already maintained beside the ROMs.
Metadata and build recipes are portable; device installation state is separate.

Preserve cloud/local merged identity, existing sources/authentication, save
conflicts, companion launching, imported media, red theme and protected cache
entries. No unrelated emulator work, full artwork scrape, ROM mirroring, private
data publication or speculative framework. Do not overwrite original ROMs.

## 2. Evidence and current defects

- The production GBA screen captured on 2026-10-15 reports 0/7674 ranked while
  advertising Best 100 / A-Z. LibraryQuery and LibraryScreen already request
  featuredTop=100; no eligible score means every entry takes the alphabetical
  remainder. This is missing useful ranking coverage plus misleading feedback,
  not evidence that 007 or numbered Disney titles rank highest.
- Production overall scores currently require fresh, exact identity-bound IGDB
  community scores with at least 20 votes on assessed platforms, including GBA.
  Preserve this policy; no invented scores, silent threshold relaxation or
  borrowing a base game's reception for a modified project.
- GBA already has Hacks, Color Hacks, T-En and Patches. Patches/index.json schema
  2 lists games and game.json pointers. Each game's source index contains
  sections, source IDs/versions/descriptions, rom_files with exact archive/member
  paths and hashes, and payloads with extracted patch files/hashes. Advance Wars
  Balance has a matching USA base and an IPS payload. Not every archive member is
  a patch: readmes, utilities and executable installers must not become ROMs.
- DriveProvider currently excludes Patches descendants from playable games but
  retains the source tree. Reuse that boundary to expose a separate patch view.
- Morphe Extended's selection payload retains patch/source versions alongside
  outputs. Use the provenance pattern, not its APK-specific identity or engine.

## 3. Required behavior and acceptance

### RANK-01 — Useful, honest featured ordering (S16)

Default console-library browsing features up to 100 canonical games using the
existing accepted overall scores, descending, then every remaining game A-Z.
Regional/revision files with verified common game identity share one card and
retain an accessible version picker. Do not collapse ambiguous editions or hacks
by title alone. One game's multiple language variants must not consume several
rank positions. Explicit alternate sorts/manual shelves remain intentional.

Provide a scoped, joined/cancellable rating-information refresh through the
existing metadata owner. It must gather identity/rating evidence without ROM
payload downloads, artwork fetching, or requiring complete descriptions/media.
Reuse provider IDs and equivalent requests where identity permits it; don't
introduce a separate scraper/scheduler. Preserve existing richer metadata/artwork.
Observe provider quotas/protocol waits and retain durable resumable outcomes.
Opening a library never silently begins a collection-wide provider operation.

Owner correction: replace Advanced's legacy Download all covers entry with the
ScreenScraper collector, labelled Get metadata & covers. Open its normal scope,
start/pause/resume workspace; do not route that entry back to Libretro/RA cover
preloading. This full metadata/artwork collector remains distinct from the scoped
IGDB ranking refresh. Verify the real entry routes and job ownership, not labels
alone. Starting provider work remains explicit in the collector.

The home quick menu also exposes Scrape this console, Scrape manufacturer (when
a manufacturer is selected), and Scrape all. Group Sync and Scrape into separate
compact submenus, retaining touch/controller navigation and back-to-parent. Each
scrape action opens ScreenScraper's same collector with its scope preselected;
manufacturer scope snapshots only that manufacturer's configured console IDs.
Opening a scope does not start scraping or interrupt an existing metadata job.
An empty manufacturer scope must never expand into an all-collection scrape.

Show known ranked/collection coverage and a concise rating-refresh action when
no usable rankings exist. Never label an entirely alphabetical fallback as an
already populated best-games list. Fewer than 100 eligible games is acceptable;
show all eligible games first, never fabricate the difference.

Acceptance: integrated database/provider/controller/widget checks cover scored
games outranking 007, unranked A-Z tail, verified regional grouping, ambiguity,
modified-game score independence, explicit sorts, zero/partial coverage and
refresh -> persisted scores -> reordered library. Demonstrate a real GBA scoped
rating refresh and resulting nonalphabetical featured order on Thor; no full
artwork scrape or ROM download is necessary. Logs/queries are primary evidence.

### NAV-01 — Manufacturer/type/chronological consoles (S17)

Below manufacturer, show All, Home consoles, Handhelds, Arcade and Computers only
where represented. Hide the entire type row if the current manufacturer scope
contains at most one type. Type is explicit platform metadata, not guessed from
release year, a filename or brand. Hybrid platforms can belong to multiple types
without duplicated console records/counts. Empty selections are not invented.

Within the selected manufacturer/type, sort consoles by first release year,
oldest first; case-insensitive console name and stable ID break ties. Use the
same membership/order in home carousel, grid and library console navigation.
Keep the current console if still available; otherwise choose the first valid
console. The dashboard remains a separate entry, not a dated console. All resets
only the corresponding filter. Manufacturer sync still covers its configured
systems; browsing filters must not rewrite mappings or silently change sync scope.

Acceptance: complete Nintendo home/handheld chronology, hybrid membership,
single-type row suppression, tie/selection/reset, carousel/grid/library agreement,
touch/controller focus and 1920x1080 plus compact viewport checks. Native smoke
checks use existing settings without triggering sync or changing sources.

### CACHE-UI-02 — Complete ROM-cache controller navigation (S17)

Owner reports that only the cache page's section tabs work with the controller.
Reproduce and repair content focus/action dispatch: policy switches, pool/order
dropdowns, retention/rotation/budget edit dialogs, console/game lists and Apply
must be reachable and operable. Support moving between rail and content, normal
back/cancel and visible focus; retain touch and unchanged-policy preservation.
Acceptance: rendered controller input traverses/operates representative policy,
console/game, dialog and Apply paths, with a native Thor smoke check. Merely
switching rail tabs does not satisfy this requirement. Do not change cache policy
or evict data merely to demonstrate navigation.

### INPUT-01 — App-wide controller wiring reconciliation (S17)

Owner requested two bounded read-only reviews of all app-owned UI after reporting
unreachable General/Audio tabs. Findings and coverage are in
CONTROLLER_COVERAGE.md. Main reproduces/adjudicates each finding and repairs
confirmed required reachability: settings tab focus/activation, nested content
and dialogs, Drive setup/mappings, advertised configuration/onboarding shortcuts,
shelf rule removal/scrolling, media controls and long game-info scrolling.
Preserve native system account/file picker boundaries; do not claim source review
proves physical-controller behavior. Use existing app action/focus contracts, not
a parallel input framework. Each reachable app-owned page/overlay must have a
usable direction/activate/back/scroll route for its advertised controls. Patch
pages added in S18 and sharing pages in S19 receive the same contract in their
owning stages. Read-only review creates no concurrent implementation stage.

Owner clarification, 2026-10-15: all app-owned menus, nested menus and dialogs
must support the controller. R1/L1 switch next/previous tabs on every tabbed
surface, including General/Audio/Advanced/About and library/settings sections.
These tab actions take precedence over conflicting global zoom shortcuts on
those surfaces. Keep D-pad tab selection/activation, content navigation, A/confirm
and B/back/cancel usable. Existing nonconflicting shortcuts may remain aliases.

Acceptance: a source-to-rendered test coverage map, focused controller regressions
for confirmed gaps, and a bounded real Thor walk through the reported main tabs,
cache controls/dialogs/Apply and representative nested routes. Explain genuine
OS-owned dialog limitations without relabelling app-owned gaps as external.

### CAT-01 — Commercial/Hacks/Patches views (S17)

Offer Commercial, Hacks and Patches below console/type navigation. Preserve
existing Installed/Favorites/search, source membership and metadata tag filters.
Commercial means normal unmodified commercial releases, not simply every file
outside a literal Hacks folder. Hacks includes ready-to-play modified editions
from Hacks, Color Hacks, translations/T-En/T-Eng, Dub/Undub and Uncensor mappings;
retain their individual canonical tags. Do not silently lose separately classified
homebrew/demos: retain an All view and explicit category membership where present.

Classify source-relative folder ancestry and supplied structured metadata; retain
original paths. Source names/paths are evidence, not canonical game identity.
Existing modified ROMs remain launchable without a known patch recipe. Patches
shows base-game cards for compatible indexed patches in the current collection;
it never presents readmes, JSON, installers, editors or patch binaries as ROMs.
Until S18's complete patch workflow is present, no dead-end patch action is exposed.

Acceptance: real-shaped folder/index fixtures separate originals, nested hacks,
translations and patch resources without double-counting cloud/local copies.
Commercial/Hacks navigation and existing tag/installed/search filters integrate;
Patches interaction is verified with PATCH-01 in S18, its named owning stage.

### PATCH-01 — Compatible game -> build -> playable result (S18)

Read schema-versioned console/game/source indexes from the existing configured
source tree. Bind relative paths to that source/root and match exact base-ROM
archive members using published fingerprints. Validate actual bytes before use;
a matching display name or a catalogue path alone is not compatibility proof.
Read indexed JSON/metadata and required patch resources on demand, not every ROM
body. Preserve hashes/provenance, handle missing/stale resources visibly and
never execute downloaded installers or utilities. Index content is data, not code.

Selecting a game in Patches opens a sectioned Available patches / My builds view.
Show version, description, type/language, required base and compatibility. Select
patches/options and Build/play using compact icon actions with clear labels and
ordinary progress/cancellation. Use the existing transfer owner for missing base
and patch resources, exact archive-member extraction and validation. Work on a
private temporary output, never overwrite the base or an unrelated existing ROM.
Register the validated result through normal installation/library/launch paths.
The result is a modified edition, visible in Hacks and that game's My builds.

Evaluate UniPatcher first: https://github.com/btimofeev/UniPatcher. Its README lists
IPS/IPS32/UPS/BPS/APS GBA/N64/PPF/DPS/EBP/XDelta and GPL-3.0. Pin reviewed source
and retain applicable notices. Owner explicitly authorizes a GPL-compatible
combined release to use the best implementation; preserve original upstream MIT
grants/notices, GPL component attribution/source obligations and Darkaxt credit.
Document the combined distribution terms accurately rather than claiming the
integrated GPL engine is MIT-only. This is not an engine-selection blocker.
Avoid hand-implementing established patch algorithms merely to avoid evaluation.

Inventory formats referenced by configured patch indexes. Required Android engine
coverage is IPS/IPS32, UPS, BPS, APS GBA/N64, PPF and XDelta where present. DPS/EBP
are required when encountered in that inventory. Archives are containers, not
patch formats. Unknown/proprietary or installer-only packages stay visible with
their actual unsupported reason; do not claim successful application or hide them.
Only compatible ordered chains can be selected together. Header adjustments and
checksum fixes must be explicit recipe steps, not silent input mutation. Changing
a recipe rebuilds from its declared base rather than blindly patching old output.

Acceptance: native indexed Advance Wars base -> IPS -> validated registered ROM
-> normal emulator launch, then second selection recognizes the existing build
without repatching. Focused engine fixtures cover every required inventoried
format, input mismatch, corrupt resources, incompatible chains, cancellation and
failed publication preserving originals/prior valid outputs. Verify one modified
edition keeps its own save/companion identity and no unrelated data is overwritten.
No deep gameplay/save correctness exercise or continuous screenshot stream.

### PATCH-02 — Persistent recipe and exact-result recognition (S18)

Persist base fingerprints, ordered patch IDs/versions/fingerprints, relevant
options/preprocessing, engine identity/version and output fingerprint. Recipe IDs
are deterministic from canonical content, not filename or device path. Keep source
attribution even if a catalogue entry disappears. Same verified recipe/result
offers Play/download/rebuild as appropriate; never overwrite a changed local file
based solely on an old receipt. Already-existing modified ROMs are adopted as a
known build only with matching output evidence; otherwise history is unknown.
Result residency is separate from the persistent recipe and game edition.

Acceptance: restart, same-recipe reuse, different-version recipe separation,
changed output rejection, legacy unknown-history handling and exact edition
library merge. Preserve recipes after managed result removal; safe reproducible
recovery must be integrated before generated results become eviction candidates.

### SHARE-01 — Portable catalogue/recipes, private residency (S19)

Existing collection JSON remains the common producer/consumer catalogue; do not
fork it into a disconnected app-only source of patch truth. Read existing schema
2, preserve unknown fields when a producer update is necessary, and document
compatible extensions rather than rewriting every existing index.

Keep normalized patch receipts/recipes in the established reconnectable shared
metadata area, not solely app-private storage. Reopening/reconnecting restores
them. Export/share a recipe using the ordinary Android sharing workflow; another
device/import resolves its own base and patches by content fingerprints and
shows missing requirements instead of importing the sender's installation state.
Retain device-local paths/account/source IDs separately. Export no ROM, credentials,
cloud IDs, signed URLs, private inventory or device path by default. Public patch
payload distribution is separate and never automatic. Existing permitted backup
transport may carry explicitly selected recipes; no new whole-folder cloud mirror.

Acceptance: two independent app-store roots restore/import the same portable
recipe, resolve different local mappings to the same bytes, and keep distinct
residency. Sharing/import/missing-resource menus work with touch/controller;
conflicting content is not silently overwritten. Inspect exported JSON for private
fields and verify reconnect persistence. A second Google account is not required.

### LAYOUT-01 — Source layout and authorized migration (S19)

Document supported layout, index fields, root-relative paths, archive members,
hashes, original versus playable-hack versus patch-resource classification and
how to add/update a patch. Include small synthetic examples, not private inventory
exports. Document actual compatible layout without requiring folder moves merely
for aesthetics. Current canonical example:

    <Console>/Original Game (Region).7z
    <Console>/Hacks/<Project>/<Playable ROM>
    <Console>/T-En/<Translated ROM>
    <Console>/Patches/index.json
    <Console>/Patches/<Game>/game.json
    <Console>/Patches/<Game>/<Source>/index.json
    <Console>/Patches/<Game>/<Source>/<Patch>/<Patch payload and metadata>

Existing direct files under Hacks and existing source project folders remain
supported. Folder names are configurable mappings/aliases, not hardcoded English
requirements. Relative-path bindings, not Windows drive letters, are shared.

Owner authorizes useful reorganization only under the Google Drive ROMs root.
Inventory exact targets and dependent mappings/index paths first; preserve file
identity/content, update references coherently and verify old/new membership and
hashes after any move. Retain a concrete reverse-move procedure if a migration is
actually performed. Do not delete ROMs, saves, BIOS, metadata or original patches,
broaden source permissions, move unrelated Drive files or publish private ledgers.
If existing structure works, retain it and document that decision.

Acceptance: committed source-layout guide and fixtures resolve from a different
root without edits, current representative real indexes parse, and any actual
move has verified mappings/references/content. No move is required to claim this
criterion if the inspected structure already meets the contract.

## 4. Integrated execution, design and delivery

S16 ranking correction is first; S17 navigation follows; S18 patch workflow uses
S17's categories; S19 sharing/layout/final integration follows S18. Only one stage
is ACTIVE. If real external verification becomes unavailable, record the precise
criterion and park it before independent later work; no prerequisite bypass.
No artificial preparation stage or per-component acceptance milestones.

Use existing sectioned settings, icon/transport actions and controller contracts.
No long single-page settings roll, paragraphs inside buttons or debug UI in the
production build. Preserve compact and Thor landscape viewport fit and OLED-off
cleanup. Logs/state are primary diagnostics; targeted screenshots prove visuals.

One test workload at a time. Native/Gradle verification uses the installed shared
build gate, conservative profile and original managed session. Reuse valid
unchanged checks; no broad-suite or per-edit native build ceremony. Use bounded
fixtures, streaming large-file IO and one patch operation at a time. Temporary
host artifacts belong under task-owned D:/Temp and use transactional cleanup.

Final closure requires every requirement's acceptance evidence, no blockers or
required deferrals, integrated native workflows, preserved accounts/ROMs/saves,
guide/README accuracy, verified commit and authorized remote synchronization.
Local signed packaging and in-place device installation for required live tests
are normal implementation verification; no new public release is authorized yet.
