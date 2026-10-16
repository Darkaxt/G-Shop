# Dual-screen preview and acquisition extensions

Authoritative extension to SPECIFICATION.md revision 58, 2026-10-16.
Authorization: already_authorized. The owner approved the dual-screen/media
preview design and requested implementation, followed by a general website
acquisition/add-on integration based on H:\My Drive\Roms\LolSuite Manager.
No new public release is authorized by this implementation request. Real scoped
device verification is authorized; preserve production settings/data and leave
both Thor screens off after use.

## PREVIEW-DELIVERY — Authorized Thor update, 2026-10-16

The owner explicitly requested deployment to the Thor after S22 closure.
Package the verified preview as signed 1.9.2/code 16, update the existing
com.darkaxt.rshop installation in place, and verify installed bytes, startup and
preserved settings, credentials, catalogue and imported resources. Do not
uninstall, clear data, scrape the collection or publish a GitHub release.
Keep a rebuildable local APK for this requested delivery; remove expendable
verification intermediates through reviewed cleanup and leave both screens OFF.

## PREVIEW-01 — Dual-screen browsing (S22)

Detect a usable second physical/presentation display by actual capabilities,
not hardcoded display IDs. When enabled and available, keep console/library ROM
browsing on the main display with a full-width four-column, two-visible-row
cover gallery at the Thor's landscape viewport. Remove its inline media pane;
retain title/rating/local-cloud indicators, sorting, categories and controller
navigation. Single-screen/disabled mode retains the current usable layout.

The other display shows the selected ROM's existing flat/imported 3D physical
media, proper cartridge/disc label and existing cover-reveal animation. Retain
handwritten missing-label fallback, no reveal without box artwork, reduced-motion
behavior, red theme and imported-resource privacy. Do not duplicate the library,
credentials, database, source traversal or download/save owners in the renderer.

Activating the selected main-screen cover or secondary media shows the same
ROM's metadata and explicit launch/download readiness on the secondary screen.
The main gallery keeps controller focus and position. Moving to another ROM
returns the secondary screen to its new media preview. Back closes details before
leaving the gallery. Details actions use the existing download/owned-launch,
variant/patch/save/conflict paths, not a parallel launch or installation owner.
Touch actions and a controller-accessible action affordance must be usable
without automatically stealing focus from gallery navigation.

Actual ROM launch hides R-Shop's browsing UI and dismisses only its secondary
window, exposing the existing application beneath. This preview feature must not
close, restart, relaunch, move or alter the companion. Existing explicitly
configured per-ROM companion behavior remains owned by the ordinary launcher;
the preview adds no new companion action. Background save/download owners keep
their existing lifecycle. Returning to R-Shop restores its selected gallery and
preview. Hidden/disconnected views release playback/rendering resources.

## PREVIEW-02 — Gameplay backgrounds and settings (S22)

Behind the sharp physical-media foreground, offer Off / Screenshot / Slideshow /
Video preferred. Video preferred uses an available cached gameplay clip, then
screenshots, then the red background; missing media never blocks browsing or
launch. Details dims the background for readable text. Blur and brightness apply
only to the background. Preserve source aspect ratio without stretching.

Use sectioned Preview settings, short labels/icons, touch/controller navigation
and L1/R1 sections: Background, Appearance, Playback, Storage. Persist enablement,
background mode, blur/brightness/model visibility, autoplay/loop/audio/volume,
download policy (manual, Wi-Fi, any network), source/normalized video preference
where the provider actually offers it, and a bounded configurable video cache.
Default dual-screen behavior is automatic when supported, video-preferred with
audible playback at the existing Audio music-volume setting (soft default 30%),
Wi-Fi-only acquisition, and a 512 MiB video-cache budget. The owner's 2026-10-16
audio clarification supersedes the earlier muted-video default. Trailer sound
respects the global Sound switch and its own Playback sound toggle; do not add
a second volume control for the same internal media level. Actual trailer
playback temporarily suppresses launcher music, without changing its saved
volume/enabled preference. Pause, completion, error, selection change, hide,
disconnect and ROM handoff release suppression; only the currently owned player
may change it. A settings change during playback must not re-enable music early.
Do not silently download an entire collection merely by opening Preview settings.
Use current selected/cached metadata and the existing explicitly requested scrape
scope; an explicit per-game media download is available when not cached.

Extend ScreenScraper's existing authenticated metadata/media transport for its
documented video endpoint, respecting current matching, credentials, quota,
cancel/ownership and secret-redaction contracts. Cache verified media under the
durable shared media root alongside images, with size/integrity and actual decoder
readiness checks. Do not place authenticated URLs in renderer payloads, public
recipes or logs. Offline cached playback must work. Cache eviction removes only
owned unused preview media, not imported resources, original user media, ROMs or
saves. Include settings/shared cached media in existing full migration behavior.

Only the selected ROM may play. Selection, hide, disable and display removal
settle/dispose the original player; stale asynchronous completion cannot replace
the new selection. No scraping on every highlight, uncontrolled player queue,
arbitrary synchronization delay or companion-process manipulation.

### S22 acceptance

1. Real Thor shows eight main-screen covers and correct flat/3D preview on its
   other display, with actual viewport evidence and primary controller focus.
2. Normal activation shows matching metadata/readiness below; navigation resets
   to the newly selected ROM; touch/controller actions and existing launch paths
   work without stale game identities or altered single-screen behavior.
3. Real selected-game screenshot/video acquisition through ScreenScraper caches
   and plays correctly, including offline fallback; settings and cache limits
   apply, with no credential disclosure or unrequested collection-wide scrape.
   Trailer audio uses the existing internal music volume, launcher music is
   suppressed only during actual playback, and stopping restores current user
   settings without unmuting disabled sound.
4. Launch hides/dismisses R-Shop only and preserves the companion task/state;
   returning restores gallery selection. Hidden/removed display has no playback.
5. Focused host/native lifecycle, selection, settings, media/integrity, ownership
   and relevant existing library/launch/migration checks pass. Debug-only readiness
   and rendered-state evidence supplement representative visual captures; no
   screenshot polling or general remote-control framework.
6. Reconcile this complete feature, document behavior/settings, perform required
   signed assembly through the host-wide gate, clean attributed verification
   artifacts, commit and synchronize the existing branch. Public release remains
   separately authorized.

## ACQUIRE-01 — General website acquisition add-ons (S23)

After S22 closes, port reusable acquisition behavior from LolSuite Manager into
R-Shop's existing sources/catalogue/download infrastructure. LoLRoms is one
add-on, not the application identity or a mandatory intermediary for other sites.
Inventory the current manager's providers, curation/options, resume/integrity,
format processing and publication behavior before selecting port boundaries;
record any required unsupported platform dependency instead of silently dropping it.

Provide versioned reviewable add-on definitions and sectioned per-site mapping
settings: canonical console/category identity and explicit aliases, site roots,
listing/detail/pagination/file-name/size/date parsing and host/URL constraints.
Reuse common declarative behavior; genuinely site-specific session/resolver code
belongs to that site's adapter, not growing conditionals in the core. Configuration
must be editable/importable without recompiling for ordinary mapping changes.
Preserve canonical game/file identity across provider spellings, regions/editions,
hacks/translations and archive names; do not infer interchangeable ROM bytes from
similar names. A website outage or unsupported console cannot block unrelated
providers or local collection validation.

Use one R-Shop queue/installation owner with per-provider capacity, actual provider
availability and scoped retries/cooldowns. Preserve the learned RomsDL one-active-
file restriction without imposing it on every source. Resume requires compatible
identity/range/size validation, and final readiness requires verified bytes and any
required processing. A provider choice is not proof that another site's partial
archive can be resumed. Keep existing Drive, patches, metadata, save/cache and
companion paths working. Do not expose credentials or invent silent bypasses of
normal user authentication/challenges.

### S23 acceptance

Prove the narrow real flow first: configured site -> mapped console/category ->
actual selected item -> existing R-Shop queue -> verified installed/launchable
result. Then complete the current LolSuite-supported site adapters required by the
inventory, editable mappings, provider isolation/capacity and relevant existing
selection/validation/processing contracts. Verify outage/missing-console behavior,
duplicate/changed-archive identity, interruption/resume and explicit human
authentication when required, with scoped real provider checks and focused
regressions. Document how add-ons/mappings are added and maintained. No empty
extension framework, separate downloader UI, whole-collection acquisition, Drive
reorganization or unrelated desktop tooling port counts as completion.

## METADATA-CLOUD-01 — Drive-backed metadata and local cache (S24)

Owner-approved implementation, 2026-10-16; ACTIVE and not part of the Thor
1.9.2 delivery. Store durable credential-free scraped records and artwork in a
separate metadata tree on Google Drive, outside the ROM folders, with canonical
console/game/edition bindings and equivalent collection organization. Preserve
existing scraped data; this is not an instruction to scrape everything again.

Keep the local text/score/tag query projection for immediate browsing, search and
rankings. Download thumbnails and selected-game artwork/screenshots/video in the
background into one bounded local artwork/media cache, default 2 GiB, adjustable
in Settings. Evict older unused cached media rather than deleting the cloud
master. Do not implement this as an uncapped full-folder mirror or a network
request for every focus event. Offline cached browsing and the configured offline
retention policy remain usable; this media budget does not include ROM payloads,
saves or imported Socket resources. Retain artwork-role and exact identity/hash
validation, provider provenance and secret-redaction boundaries.

Acceptance: existing scraped metadata/media published to and recovered from the
selected private Drive metadata root without repeated scraping; real cache-miss
background acquisition, local/offline cache hit and bounded eviction at the
configured 2 GiB default; text/rankings stay available offline and box/cartridge
media roles remain correct. No cloud or local migration occurs merely by recording
this design. S24 is a separate requested outcome, not a deferral of S22/R22.

Owner-corrected visible design, 2026-10-16: use a private app-created
`R-Shop Metadata` Drive root, separate from ROM and save roots, with canonical
console/game-or-edition folders and typed resource names (`box.png`,
`cartridge.png` or `disc.png`, `screenshot-01.png`, `trailer.mp4`, `metadata.json`).
The earlier mixed hash-named artwork tree is superseded, not accepted as this
requirement. Keep exact role/provenance and digests in metadata/index receipts;
hash-addressed local cache bodies remain an internal implementation detail. Reuse
the existing Google account and app-file consent lane, with a metadata-specific
typed API; ROM access remains read-only. Reserve creation IDs durably, verify
remote ownership/size/digest before admitting eviction, and keep interrupted or
offline publication resumable without deleting unuploaded originals. Keep text
records and receipt projections locally; recovery must retain exact edition and
provider bindings and existing provenance rules. Background reads belong only to
mounted cards or the selected game, never the whole-console cover lookup. One
serialized cache/publication owner coordinates reads, migration, active-file
leases and eviction. Existing ES-DE files and imported resources remain outside
cache deletion. A full migration retains account/root/budget configuration but
rebuilds destination-specific cache paths. Settings stay sectioned with short
icon actions and existing touch/controller/L1/R1 navigation.

Pre-existing content-addressed media left by earlier refreshes must not disappear
from accounting. Include it in local usage; preserve validated unbound bodies
outside normalized game folders until they can be classified, never inventing a
game, edition or resource role. Preserve the first unpublished/migrating local
copies until normalized remote publication is verified. First prove one complete
Nintendo console resource/rendering workflow before the broader collection pass.
The former mixed hash-named Drive folders are preserved under `_legacy/console`
after successful normalized publication, with recovery still supported. Normal
Drive-backed resource collection includes the preferred validated gameplay clip,
not just a trailer reference. Publication yields between games so selected-media
cache requests are not held behind the entire library upload; settings report
completed/total game publication progress.
Resource-only collection snapshots existing matched records for the selected
console/manufacturer, reuses valid cached resources, and does not repeat title
lookups. It has the existing durable pause/resume/saved-job controls. Newly
collected visible-game resources can be published ahead of the unrelated bulk
migration; repeated focus on an already mapped resource remains local-only.

Owner-requested rendering corrections, 2026-10-16: the cover-to-media reveal must
be a slow visible leftward slide (2.4 seconds total: 600 ms hold, 1.8 seconds
sliding/growing), not the prior 600 ms flash. All cartridge housings and UMD shells
must read as molded plastic, with no metallic response and a .75 roughness floor.
Preserve actual optical-disc parts, exposed contacts/boards/screws and game labels,
as well as source geometry. This owner extension supersedes the initial GB-only
correction. These corrections are included in S24 verification
and the requested Thor deployment/Nintendo collection rendering checks.

## Execution

Owner reset instruction, 2026-10-16: the existing collected resources are to be
discarded, not recycled into the normalized layout. Preserve matched local facts
and configuration; discard obsolete app-owned Drive exports and collected local
image/video bodies and receipts, then republish facts and collect fresh typed
resources. A persisted reset intent resumes before cloud publication after an
interruption. This explicit reset supersedes the old-copy retention/archive
requirements above for the discarded generation only. Ordinary cache eviction
still requires verified cloud masters and respects active leases.

Drive mutation boundary: v3 is retained for listing, initial publication and
reads. Conditional updates, moves and explicit trash use Drive's documented v2
File.etag and patch representation, with the same account/app-file scope and
fresh ownership/name/parent/digest/size validation. There is no unguarded update
fallback when a required version cannot be established. References:
https://developers.google.com/workspace/drive/api/reference/rest/v2/files
and https://developers.google.com/workspace/drive/api/reference/rest/v2/files/patch.
Explicit rebuild trashes individually verified app-owned descendants before
their empty folders, rather than depending on Drive's populated-folder child
access check. Visible foreign children reject the cascade; interrupted resets
resume from the remaining live objects without broadening the OAuth grant.

S22 is COMPLETE with host/native acceptance, signed verification, reviewed cleanup
and remote source delivery recorded in IMPLEMENTATION_STATUS.md. R22's signed
1.9.2 in-place Thor delivery is COMPLETE. S23 is NOT STARTED; S24 is ACTIVE. Each is a separately requested
following outcome, not a deferral excusing any S22 acceptance criterion. Earlier
S0-S21/QA/release results remain applicable except where changed integration is
explicitly reverified. Every required gap is kept in the existing status ledger.
