# S5 requirement reconciliation

Authority: `SPECIFICATION.md`, revision 5. Reviewed on 2026-10-04 against
`834821d` and the normal-details verification changes in the working tree.
S5 is the sole ACTIVE stage. This document consolidates the chronological
checkpoints; their older remaining-work statements are not current status.

## Shared UI acceptance

| Requirement | Inspected evidence | Remaining acceptance |
| --- | --- | --- |
| UI-01: nullable trusted source-labelled overlays, stale/original distinction, preference and accessible score explanation | `cover_rating_test.dart`, `metadata_badges_test.dart`, `game_metadata_info_test.dart` and the normal Display preference checks exercise the production selector and shared component. The recorded inspected golden comparison is unchanged. Normal console, Library and shelf native screenshots show exact cached scores; native details now explain the same cached score. | No remaining boundary for this score-display contract. No base score is silently assigned to a hack. |
| UI-01: compact/large, focus, titles and existing favorite/platform/achievement/source/transfer badges | `cover_card_layout_test.dart` and the inspected native layout report/screenshots prove bounded caption/footer geometry, selected/unselected cards, six enlarged localized labels and all active transfer states. Native driver `2b31d2` passed; host regression/golden comparisons and scoped analysis passed at the recorded checkpoint. | No remaining layout defect is identified by this evidence. |
| UI-01: immediate physical-media loading/missing/error/offline fallback, explicit mapping and licensed raster family | `media_cover_fallback_test.dart` checks every supported mapping, unknown/mixed-media neutrality, decoder bounds and unchanged upstream raster hashes/license. Normal native console/Library/shelf traversals assert media fallbacks for every mounted card. Systematic `-content.png` is pinned and bundled, not generated or fetched during fallback selection. | Native resolved-cover replacement still requires proof. Full cartridge/legacy-platform artwork coverage is explicitly ART-01/S9, not a waiver of present mappings. |
| UI-01: valid resolved artwork replaces fallback without extra requests | The existing host test seeds the actual image cache, observes immediate fallback, awaits native Flutter image decoding and asserts a non-null visible decoded image with zero network attempts. | Repeat this boundary on the Thor, including the shared caller integration; ordinary unfinished S5 verification, not a deferral. |
| UI-01: actual offline scrolling and bounded request behavior | Both normal screen fixtures traverse actual lazy-grid scroll positions and assert every member's score/media. The inspected native combined report records 321 existing console boxart attempts rejected before sockets, zero Library attempts and zero metadata/ROM requests. Pure shared fallback cards initiate no requests. Batched cache reads use the existing 128-row shared query rather than reads per frame/card. | These are measured UI request/scroll evidence, not a whole-host memory guarantee. Original backend host-wait investigation remains S4/B5. |
| UI-02: existing settings, secure provider setup, refresh progress, re-scrape, pending/error and controller/touch navigation | The inspected native settings/review reports prove controller entry, touch setup, pause-before-lookup, joined same-job pause/resume, distinct coverage, cached candidate review/acceptance and Back. Exact-game correction report proves preservation of old facts, explicit replacement and subsequent ordinary refresh retaining the correction. Sources menus also have native localized touch/controller/focus proof. Corrected normal-details native driver `5ef060` passed through exact-game refresh completion and Back. | No remaining boundary identified for these UI controls. No live scrape is claimed by synthetic provider tests; actual adapter access has separate S4 evidence. |
| UI-02: common score details, raw scale/votes/source/date, tags and ROM independence | Normal details host fixture uses the production dark theme, exact edition/cache provider and common Game Info model. Corrected native report and all four inspected screenshots prove cached score/provenance/tags, pending/error/retry and exact-game controls/refresh, with ROM actions independent. Native retains the actual input debounce; the host fixture isolates its real-time cooldown from fake-clock routing checks. | No remaining boundary identified for normal details. The first native failure was in the fixture's premature pause/report inspection, not a production defect; final verification joins the actual completed-job event. |
| UI-02: white primary labels on darker red with retained disabled/tonal styles | Recorded primary-button regression and interaction-state contrast checks passed; native setup/source screenshots were inspected. Production uses the shared `#C62828`/white style without altering authentication or worker behavior. | None for this color contract. |
| UI-03: existing filters, collection-owned dynamic Top 10/25, scope, tags/genre and shared semantics | Normal console and Library native tests prove controller Best 10, sparse Best 25, console versus single cross-system scope, tag any/all intersection, no backfill and score-change recomputation. Shared query checks cover independent Hack/T-Eng/Dub/Undub/Uncensor and genre semantics; existing filter controls expose these independently. | Complete the final UI-specific audit for independent controls and unrated results before closure; query-only evidence is not substituted for UI proof. |
| UI-03: clear/restore, active status, focus and manual shelf order | Normal native console clear/reopen, Library restored filters, manual shelf order and explicit score sorting are asserted and captured. Selected game identity survives reorder; saved manual IDs remain unchanged. | None identified for these demonstrated paths. Filters do not alter transfer, retirement or archive/device profiles. |

## Closure boundary

S5 is not COMPLETE while native resolved-cover replacement and the final
UI-specific independent-control/unrated audit
remain unverified. These are current-stage unfinished work, not blockers or
later-stage deferrals. No S6-S9 implementation has started.

S1/B3 (actual second-account isolation and elapsed renewal) and S4/B5 (missing
original host-wait runtime evidence) remain parked BLOCKED and required for final
closure. Full fresh collection metadata and reviewed Top-25 SD migration remain
MIGRATE-01/S7. Synthetic native UI proofs preserve accounts, normal installed APK,
ROMs and settings; they do not claim the full live migration or a usable release.
