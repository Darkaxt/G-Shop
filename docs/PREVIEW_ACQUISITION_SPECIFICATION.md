# Dual-screen preview and acquisition extensions

Authoritative extension to SPECIFICATION.md revision 57, 2026-10-16.
Authorization: already_authorized. The owner approved the dual-screen/media
preview design and requested implementation, followed by a general website
acquisition/add-on integration based on H:\My Drive\Roms\LolSuite Manager.
No new public release is authorized by this implementation request. Real scoped
device verification is authorized; preserve production settings/data and leave
both Thor screens off after use.

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

## Execution

S22 is the sole ACTIVE stage. S23 is NOT STARTED; it is a separately requested
following outcome, not a deferral excusing any S22 acceptance criterion. Earlier
S0-S21/QA/release results remain applicable except where changed integration is
explicitly reverified. Every required gap is kept in the existing status ledger.
