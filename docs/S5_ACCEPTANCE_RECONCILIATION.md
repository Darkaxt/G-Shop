# S5 requirement reconciliation

Authority: `SPECIFICATION.md`, revision 5. Reviewed on 2026-10-04 against
`656172e` and the normal shared-caller verification changes in the working tree.
S5 is COMPLETE. This document consolidates the chronological
checkpoints; their older remaining-work statements are not current status.

## Shared UI acceptance

| Requirement | Inspected evidence | Remaining acceptance |
| --- | --- | --- |
| UI-01: nullable trusted source-labelled overlays, stale/original distinction, preference and accessible score explanation | `cover_rating_test.dart`, `metadata_badges_test.dart`, `game_metadata_info_test.dart` and the normal Display preference checks exercise the production selector and shared component. The compact IGDB service icon retains full semantics/tooltip/details; other providers keep text. Updated golden was visually inspected and the subsequent unchanged-reference comparison passed (`fe6c0b`). Normal console, Library and shelf native screenshots show exact cached scores; native details explain the same cached score. | No remaining boundary for this score-display contract. No base score is silently assigned to a hack. |
| UI-01: compact/large, focus, titles and existing favorite/platform/achievement/source/transfer badges | `cover_card_layout_test.dart` and the inspected native layout report/screenshots prove bounded caption/footer geometry, selected/unselected cards, six enlarged localized labels and all active transfer states. Native driver `2b31d2` passed; host regression/golden comparisons and scoped analysis passed at the recorded checkpoint. | No remaining layout defect is identified by this evidence. |
| UI-01: immediate physical-media loading/missing/error/offline fallback, explicit mapping and licensed raster family | `media_cover_fallback_test.dart` checks every supported mapping, unknown/mixed-media neutrality, decoder bounds and unchanged upstream raster hashes/license. Normal native console/Library/shelf traversals assert media fallbacks for every mounted card. Systematic `-content.png` is pinned and bundled, not generated or fetched during fallback selection. Native drivers `022c2e` and `490d62` prove decoded replacement in all three callers. | None for current mappings and replacement. Full cartridge/legacy-platform artwork coverage is explicitly ART-01/S9, not a waiver of present mappings. |
| UI-01: valid resolved artwork replaces fallback without extra requests | The normal console/Library/shelf host workflow proves decoded replacement, unchanged title/score/selection (`1d8518`). Native driver `022c2e` passed the identical normal caller boundary on Android SQLite. Updated icon-native driver `490d62` passed all replacement, filter and compact/large/localized/transfer geometry checks. Report and actual-font screenshots inspected; zero sockets/cover-URL/ROM requests. | None. |
| UI-01: actual offline scrolling and bounded request behavior | Both normal screen fixtures traverse actual lazy-grid scroll positions and assert every member's score/media. The inspected native combined report records 321 existing console boxart attempts rejected before sockets, zero Library attempts and zero metadata/ROM requests. Pure shared fallback cards initiate no requests. Batched cache reads use the existing 128-row shared query rather than reads per frame/card. | These are measured UI request/scroll evidence, not a whole-host memory guarantee. Current backend resource acceptance and historical uncertainty are recorded separately in S4's reconciliation. |
| UI-02: existing settings, secure provider setup, refresh progress, re-scrape, pending/error and controller/touch navigation | The inspected native settings/review reports prove controller entry, touch setup, pause-before-lookup, joined same-job pause/resume, distinct coverage, cached candidate review/acceptance and Back. Exact-game correction report proves preservation of old facts, explicit replacement and subsequent ordinary refresh retaining the correction. Sources menus also have native localized touch/controller/focus proof. Corrected normal-details native driver `5ef060` passed through exact-game refresh completion and Back. | No remaining boundary identified for these UI controls. No live scrape is claimed by synthetic provider tests; actual adapter access has separate S4 evidence. |
| UI-02: common score details, raw scale/votes/source/date, tags and ROM independence | Normal details host fixture uses the production dark theme, exact edition/cache provider and common Game Info model. Corrected native report and all four inspected screenshots prove cached score/provenance/tags, pending/error/retry and exact-game controls/refresh, with ROM actions independent. Native retains the actual input debounce; the host fixture isolates its real-time cooldown from fake-clock routing checks. | No remaining boundary identified for normal details. The first native failure was in the fixture's premature pause/report inspection, not a production defect; final verification joins the actual completed-job event. |
| UI-02: white primary labels on darker red with retained disabled/tonal styles | Recorded primary-button regression and interaction-state contrast checks passed; native setup/source screenshots were inspected. Production uses the shared `#C62828`/white style without altering authentication or worker behavior. | None for this color contract. |
| UI-03: existing filters, collection-owned dynamic Top 10/25, scope, tags/genre and shared semantics | Normal console and Library native tests prove controller Best 10, sparse Best 25, console versus single cross-system scope, tag any/all intersection, no backfill and score-change recomputation. Native driver `022c2e` additionally verifies independent Hack/T-Eng/Dub/Undub/Uncensor any/all controls, canonical genre selection, sparse Top exclusion of unrated entries, wholly unrated empty Top and ordinary unrated browsing; report/screenshots inspected. | No remaining filter boundary identified. |
| UI-03: clear/restore, active status, focus and manual shelf order | Normal native console clear/reopen, Library restored filters, manual shelf order and explicit score sorting are asserted and captured. Selected game identity survives reorder; saved manual IDs remain unchanged. | None identified for these demonstrated paths. Filters do not alter transfer, retirement or archive/device profiles. |

## Closure boundary

All UI-01/UI-02/UI-03 acceptance criteria above are satisfied by inspected host
and native evidence. S5 is COMPLETE, including the subsequent compact IGDB
service-icon change. No required S5 blockers or tracked deferrals remain.
No S6-S9 implementation has started; overall feature completion is not claimed.

The service asset is unchanged Simple Icons `igdb.svg`, pinned to revision
`98820a4dc8c363ca72fa2c0d294ea4a0a9bba75d` (CC0 notice bundled), SHA-256
`a24c84cb2707b03d663f632afbd47ad46f8877fa47bd324297dc1967de5ecd2c`.
It is not a runtime favicon request or a hand-generated illustration. Host
affected checks passed (`fe6c0b`), scoped analysis passed (`fa0161`), and native
driver exited successfully (`490d62`). Its fixture APK SHA-256 was
`e382d76f8925a832eb870a7e0101f4bbbfc5d4e2e10b82b1c3cab929c5745ccc`.
Gate ticket 43 acquired `Local\\Darka.AndroidGradleBuildGate`; observed two
workers/no parallel, 3,221,225,472-byte Gradle heap, preserved JVM arguments,
Kotlin in-process configuration (compiler tasks UP-TO-DATE/NO-SOURCE), one
512 MiB test-fork configuration (not executed by assemble), and native Ninja
pool depth 1. No memory failure or budget increase occurred.
Exact normal APK and all seven protected device-file hashes match after
restoration (`0da336`); only the fixture forward was removed, both actual display
controllers are OFF. Private reports/screenshots/recovery are retained outside
Git. No usable-feature deployment or release is claimed.

Current dependency reconciliation (2026-10-04): S1 is COMPLETE after actual
elapsed rejection/silent renewal and verified restoration. The user explicitly
waived live second-account enrollment; offline isolation remains verified.
S4 is ACTIVE for current-source resource verification and reconciliation; its
historical tester wait is not claimed fixed or added to specification acceptance.
Full fresh collection metadata and reviewed Top-25 SD migration remain
MIGRATE-01/S7. Synthetic native UI proofs preserve accounts, normal installed APK,
ROMs and settings; they do not claim the full live migration or a usable release.
