# G-Shop update and compatibility boundaries

Authority: SPECIFICATION.md revision 133, GSHOP-01 through GSHOP-05.
Status: S26 COMPLETE in normal public v1.10.0/code 41. Host, signed in-place Thor update, live Drive, native rendering, headless save dispatch and independent public delivery acceptance pass. IMPLEMENTATION_STATUS.md records the exact source and evidence limits.

The maintained Dart package and application symbols use `g_shop` / `GShop`.
Localized app text, notifications, launcher and splash artwork use G-Shop.
The authored G mark is reproducible from `scripts/build_brand_icon.py`; the
existing dark/red interface and launch theme behavior are retained. Native and
Dart method-channel endpoints change together to `com.darkaxt.gshop/*`.
The scheduled background Dart package URIs must change with the package name.

Some old identifiers intentionally remain the installed data/protocol identity:

| Boundary | Retained identifier and reason |
| --- | --- |
| Android update and OAuth | `com.darkaxt.rshop` and the production certificate preserve updates, UID, app-private data, account authorization and grants. Rebranding does not authorize creating another app registration. |
| Android components / JNI | `com.retro.rshop` remains the native manifest, scheduled-service and JNI package ABI. Existing jobs, grants and entrypoints remain resolvable. This is separate from the installed application ID and live channel names. |
| Signing and CI | Existing `RSHOP_RELEASE_*` secret names, key alias and signing-file location remain in use. Changing names must never generate or silently select another certificate. |
| Database and credentials | `rshop.db`, existing preferences and `rshop.*` secure-storage keys remain unchanged. No blank replacement database or credential reset is created. |
| Files and imported models | Existing configured paths, `RShop/models`, emulator-family config, `RShopMetadata`, journals, stage suffixes and rollback names remain recognized. No user file or cloud folder is moved or renamed. |
| Cloud ownership | Existing `rshopMetadata`, `rshopSaveBackup` app properties and backup-area identity remain authoritative. The name change does not weaken ownership or expose unrelated objects. |
| Metadata roots | Newly created roots use `G-Shop Metadata`; both that and the legacy `R-Shop Metadata` name validate. Reconnecting an existing root preserves its ID/name and creates no duplicate root. |
| Encrypted migration | Existing `RSMIG001` format, `.rshop` extension, archive member names and rollback secrets remain supported. New exports display G-Shop; discovery recognizes both prefixes and orders their timestamps without preferring the old name. |
| Media / recipes | Existing imported model schema/version and `rshop.patch-recipe` wire IDs remain compatible. A branding change must not invalidate previously reviewed resources or recipes. |
| Background notifications | Existing notification channel ID remains stable so Android user preferences survive. Its displayed title uses G-Shop. |

Upstream names, licensing, attribution, dated reports and historical source
receipts retain their factual names. The established GitHub fork is now Darkaxt/G-Shop, with its identity, history,
releases and visibility verified unchanged. The old address resolves to the new
repository. The normal final release was independently retrieved and matches the installed Thor package. The local
checkout folder stays stable for managed project and active-consumer references.

The owner selected Google Drive only on 2026-10-21. RomM, SMB, FTP, Web and
standalone local-library setup/discovery are removed, along with executable
adapters, pairing routes and obsolete plugin dependencies. Their stored config
and provenance remain decodable and inert. The active view includes only Drive
sources and mapped consoles; edits preserve retired definitions and paths.

Downloaded/offline games, saves, metadata, imported resources and companion play
remain protected. Drive console mappings and download destinations remain editable.
Restored unfinished legacy queue entries report the retired source without
starting network access or deleting their partial files; completed history remains.
S23 acquisition is outside this work.
