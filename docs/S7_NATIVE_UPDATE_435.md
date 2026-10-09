# S7 preserving native update and explicit DSi mapping — 2026-10-09

Authority: CORE-02/03, DRIVE-01/02, META-03 and MIGRATE-01. S7 remains the
sole ACTIVE stage; S8-S11 are NOT STARTED. This is update/mapping evidence,
not completion of metadata, ranking or migration.

## Installed update and continuity

Normal Pause joined metadata job 76 at 15,928 requested lookups. A preserving
`adb install -r` replaced the app without clearing data. The actual installed
base APK was independently hashed again after native configuration verification:

- SHA-256: `4440a5aca0ea44ad0708c0aec1a5505c6addaee8af0bc9904e1abba20c69753b`
- Built artifact: 225,140,523 bytes; package `com.darkaxt.rshop.debug`.
- Verified signer SHA-256:
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.
- Owner changed from PID 1335 to 25097. Immediate pre/post configuration and
  both encrypted-storage digests matched. All 137 immediate protected file
  digests matched across replacement. This does not claim every historical
  runtime digest still matches: five Cemu runtime files already differed before
  replacement; the 48 original save/state/configuration entries still matched.
  No restoration or emulator-setting change was performed.
- Catalogue active=1, pending=2, next=3 and its committed checkpoint survived.
  Normal Refresh resumed the same pending generation, not a reset. Existing
  read-only observer session 68539 measured 19,476 -> 20,639 committed pages in
  PID 25097. Publication remains pending.
- Normal Resume advanced the same immutable metadata job without connection or
  account selection. Final read-only observation: job 76 Running, 16,321
  requested, 27,359 pending, no blocked status, outcome population 44,204.
  Adding DSi does not expand that saved capture.

Immediate digest equality is an installation-boundary claim. Subsequent normal
configuration/account-reference writes can change serialized/encrypted files;
they do not invalidate the immediate preservation check.

## Normal native mapping verification

An unchanged source-editor save preserved every system object, existing mapping
and all seven ordered source objects. The raw configuration digest changed on
this save; raw byte equality is not claimed. Two sources share a display name:
comparison used their actual ordered objects, not a nonunique name key.

The normal searchable selector explicitly chose the observed direct root child
`Nintendo - Nintendo DSi`. Collection mappings increased from 33 to 34. Full
semantic comparison proved only the new `dsi` system was added: no existing
system changed, no system was removed, and all sources remained exactly equal.

Normal Console Settings -> Nintendo DSi -> Storage opened Android's directory
picker. Selecting existing `Roms/nds/DSiWare` and accepting the folder grant
displayed the correct target. Back from the detail and console list persisted
it. Full comparison showed exactly one changed field, `dsi.target_folder`;
every other system, source and configuration field remained unchanged. No ROM
was moved, downloaded, adopted or removed. Historical DSiWare inventory is not
current cloud equality, successful restore or removal authority.

## Build profile and remaining acceptance

Shared-gate request 435 (`e6b24dbb3abb4e27b38c6de5ecd04153`) is completed,
exit 0, with supervisor completion verified. Observed profile: two workers,
no parallel projects, 3 GiB Gradle, assessed Kotlin 2.2.20 in-process, one
configured 512 MiB test fork (not executed by assembly), independently verified
depth-one native pools. No memory failure or budget increase occurred. No Gradle
command was launched for this configuration check. The earlier final output
truncated its gate-acquired field; this document does not infer a separately
inspected acquisition flag from the completed ticket.

Native cached Wii/Wii U policy and ordinary nested identification subsequently
passed their bounded execution checks; see `S7_NATIVE_POLICY_AND_NESTED_PROOF.md`.
Complete publication, immutable full metadata traversal,
required scoped passes, defensible canonical Top-25 retention, current cloud/
format checks and exact reviewed migration remain S7 work. No release, external
sync-policy change or SD cleanup occurred. Thor is Asleep and both observed
actual display states are OFF after verification.
