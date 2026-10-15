# Controller wiring ledger

Owner-requested review, 2026-10-15. Two sequential reviewers used the inherited
main model with explicit Low effort. Read-only source/test inspection only;
neither ran builds/tests nor touched the device, network, secrets or source.
Main owns adjudication, changes and verification. S17 INPUT-01/CACHE-UI-02 own
existing-page fixes; later patch/share pages are verified in S18/S19.

## Coverage map

Owner clarification (2026-10-15): R1/L1 are next/previous tabs on tabbed surfaces;
override conflicting global zoom actions there. All app-owned menus, nested
menus and dialogs need D-pad, confirm and back/cancel. S17 owns these checks and
repairs; S18/S19 must apply the same contract to their new menus.

| Surface | Existing source wiring | Remaining required verification |
| --- | --- | --- |
| Main settings | First content focus, list actions, L2/R2 tab actions | D-pad tab focus/activation and action ownership after route/tab changes |
| Cache/media settings | Rail/content Material activation bridge | Policy fields, numeric dialogs, lists, footer Apply and return focus |
| Metadata/review | Section actions; credentials/mapping dialogs bridged | Artwork confirmation raw dialog, collector actions and return focus |
| Save backup | Sections/content action bridge | Save selector and conflict/restore raw dialogs |
| Sources/manual source | Explicit card/input/overlay focus/actions | Representative actions/back and native picker handoff |
| Drive setup/mappings | Raw Material routes and dialogs | Missing app controller bridge; connect/folder/save/cancel reachability |
| Console configuration | Logical console/detail navigation | Advertised import/export shortcuts and swapped-content ownership |
| Home/manufacturers | Explicit directional/activate handoff, menu/search/zoom | Native filtered selection/menu regression smoke |
| Library/game list/filter | Logical selection, scroll and action handlers | Preserve tab/grid/filter/reorder behavior after shared input corrections |
| Shelf editor/picker | Logical row selection/actions | Rule removal action and selection-driven scrolling |
| Game details | Section/action/screenshot/version navigation | Physical-media icon controls and long Game Info scrolling |
| Detail child overlays | Variant/screenshot/companion/Drive review handlers | Representative activate/back/scroll regression |
| Achievements | Directional list focus/scroll and back | Preserve expected read-only row behavior |
| Onboarding | Focused chooser, login/provider forms | Advertised Select/import shortcut |
| Download queue | Explicit selection, scroll, A/B/Y/reorder | Preserve status actions and queue reorder/close |
| OS-owned account/file pickers | External Android activities | Device-specific boundary smoke, not app-owned source assertions |

## Original source findings and main adjudication

1. SettingsTabs uses GestureDetector without focus/activation
   (`lib/features/settings/widgets/settings_tabs.dart:34`). L2/R2 is present in
   SettingsScreen:62; don't assert trigger wiring is absent. Check action ancestor
   ownership on tabs/return and make headers selectable by D-pad/A.
2. Cache numeric dialog (`rom_cache_settings_screen.dart:166`) is a raw route
   outside page ScreenActionsWrapper. Global Confirm publishes a request rather
   than activating ordinary Material buttons. Existing widget test exercises
   only rail -> Consoles, not content/dialog/Apply.
3. Save selectors/conflicts/restores (`save_backup_settings_screen.dart:557,
   1709,1783,1837`) and metadata artwork confirmation
   (`metadata_settings_screen.dart:197`) have the same raw-dialog arrangement.
4. DriveSourceSetupScreen:310 and DriveSourceMappingsScreen:130 lack the app's
   action bridge; nested folder dialog:256 has raw fields/list/cancel.
5. Console config HUD import/export callbacks (`config_mode_screen.dart:197`)
   lack corresponding Start/Select overrides; onboarding Select/import
   (`onboarding_screen.dart:198`) is also touch-only in the inspected source.
6. Settings/config swap focused content without localFocusScope; the mixin
   documents action-ancestor restoration risk. Reproduce before attributing the
   reported failure to it (`console_screen_mixin.dart:126`).
7. Shelf rule removal (`shelf_edit_screen.dart:475`) exists only on long press.
   Its logical focused field changes without scroll linkage; shelf picker has
   the same offscreen selection arrangement (`shelf_picker_dialog.dart:89`).
8. Detail cover preview/reduced-motion IconButtons (`cover_section.dart:156`)
   are outside logical DetailSection navigation/activation. Confirm real route
   reachability and provide controller actions without removing touch controls.
9. Game Info overlay (`game_detail_overlay.dart:32`) binds close but not scrolling;
   parent navigation is suppressed at its overlay priority. Verify native
   framework behavior and add the missing route if confirmed.

Status: S17 COMPLETE. Findings 1-9 are integrated into the existing input paths.
Focused rendered host checks pass main header/bumper/content ownership,
cache policy/dropdowns/dialog/Apply/pins, Drive connection/mapping dialogs,
metadata/save/media sections, shelf removal/scroll and long Game Info scrolling.
The cache rail-only reproduction traced to the full-page restoration node being
a directional traversal candidate; skipTraversal preserves explicit restoration
while allowing rail -> real content. Dialogs get their own Material action scope.
Deferred focus/overlay writes respect their owning app scope's disposal.
Configuration/onboarding shortcuts are wired to their existing import/export
callbacks; detail Display aliases use the same cover/motion state as touch icons.
No second controller framework, worker or product feature was introduced.

Host evidence: controller_menu_contract_test.dart, rom_cache_settings_test.dart,
drive_source_setup_screen_test.dart, drive_source_mappings_screen_test.dart,
metadata_settings_test.dart, save_backup_settings_test.dart,
media_presentation_settings_test.dart, home_brand_filter_test.dart and
library_discovery_test.dart. Existing source_menu_navigation_test.dart and
search_navigation_priority_test.dart remain in the integrated regression scope.
Broad regression findings were adjudicated and affected checks freshly passed,
including configuration/onboarding shortcuts, existing popup/overlay paths and
metadata workflows. Android key-event smoke on Thor verifies Settings selection,
General/Audio R1/L1 switching, cache rail-to-content movement, A opening its pool
dropdown and retention dialog, B cancellation/return and R1 section switching.
Native Library checks retain manufacturer/type scope and chronological console
tabs; L1 switches Hacks to Commercial with visible category focus and the
unchanged honest Best 24 GBA prefix. No policy/pin/ROM changes were needed.
These are actual Android event/render checks, not a claim that a human exercised
every physical controller button or every OS-owned account/file picker. Host
checks cover those app-owned handoffs and remain distinct from OS behavior.
Both displays were verified OFF after this smoke. The final category/identity
correction APK passed its original gated build and in-place preservation check;
its installed SHA-256 matches the verified host artifact. No frontend/input code
changed after the applicable native smoke. S17's assigned criteria are COMPLETE;
new S18/S19 patch/share menus must retain and verify the same controller contract.
