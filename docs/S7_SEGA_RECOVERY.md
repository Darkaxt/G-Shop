# S7 Sega single-cartridge ZIP recovery — 2026-10-08

Authority: DRIVE-06 and MIGRATE-01. S7 remains the sole ACTIVE stage.
This is format recovery evidence, not a retention or migration approval.

## Mega Drive: normal device round trip verified

The normal owner debug APK from build 400 was used on the AYN Thor. Its
SHA-256 is recorded in `S7_DRIVE_SESSION_CONTINUITY.md`. No instrumentation
entrypoint, direct file placement or database mutation substituted for the UI.

- Changed only Mega Drive's destination through Console Settings to a new,
  isolated SD folder. Saved source objects and other configuration fields were
  unchanged. Original ROMs stayed in their normal folder.
- Selected an existing Drive catalogue item and used normal DOWNLOAD. The queue
  completed a single-member `.md` ZIP installation, preserving the 918,556-byte
  cloud container. Independent SHA-256 comparison matched the original SD copy.
- Normal OPEN launched the installed RetroArch Genesis Plus GX core through the
  exact owned document-shaped ZIP grant. The actual game copyright screen was
  visually inspected. Emulator sibling-extension probes were rejected by the
  provider; successful ZIP boot did not require broadening the read grant.
- With the saved metadata job already Paused, stopped only the test emulator and
  R-Shop, disabled Wi-Fi and confirmed no active default network. Cold R-Shop
  reopened its cached library and normal OPEN launched a new RetroArch process.
  The actual game's publisher splash was visually inspected without a network.
  A microG crash dialog appeared during the disconnected test and was dismissed;
  R-Shop stayed running. No Google-service data/settings were changed.
- Restored Wi-Fi and confirmed an active default network. Normal DELETE reviewed
  only the isolated ZIP, then removed it. The remote entry remained downloadable.
- Normal DOWNLOAD restored the identical container; independent SHA-256 matched.
  Normal OPEN launched a fresh emulator process and its actual title menu was
  visually inspected. This is stronger than a handed-off URI or black capture.
- Stopped only that test emulator and used normal reviewed DELETE to return the
  isolated installation to its original absent state. Restored Mega Drive's
  normal destination through Android's folder picker and Console Settings.
  The full R-Shop configuration SHA-256 exactly matched the pre-test baseline.
  Removed the now-empty task directory with a nonrecursive empty-directory call.
- The original ROM checksum, all 47 recorded RetroArch save/save-state files,
  and both RetroArch configuration checksums matched the pre-test baseline.
  No owner ROM, save, BIOS, emulator setting or cloud object was removed/changed.

The saved metadata job was observed Paused at 12,287 lookups / 31,601 pending.
Its earlier pause cause is not established. Normal Resume of the same job 76
advanced to 12,289 lookups / 31,599 pending without a sign-in chooser or fresh
capture. This proves continuation, not full fresh metadata coverage.

Temporary visual captures were inspected locally, not committed. Their exact
cleanup completed through transaction `fbd523ed4e00bdb9c5cb7895585b1cfe`: all six
task PNGs and the empty capture directory were removed, with no exclusions or
residuals. Both physical displays were confirmed OFF and the Thor Asleep.

## Menu-label correction

The normal Mega Drive menu incorrectly said “Open in Dolphin”, even though OPEN
correctly launched RetroArch. The menu's RetroArch console set omitted Mega Drive,
Master System and SG-1000; native routing already contained these explicit pairs.
The bounded source-wiring regression failed on those missing IDs before the
three-ID correction. It and the affected owned-handoff checks now pass; scoped
analysis and whitespace checks pass. No launch/grant behavior was changed.
Build 408 completed exit 0 with the shared gate acquired. Observed workers=2,
parallel=false, Gradle heap=3 GiB and Kotlin in-process (project KGP 2.2.20).
One 512 MiB test fork was configured; assembly did not execute JVM tests.
The active app/SoLoud/JNI Ninja roots contain depth-one pools on all 277 inspected
compile/link rules across 11 ABI files. An initial inspection selected obsolete
app staging rules; the actual configured staging roots were then inspected.
No memory-related failure or budget increase occurred. The private gate log is
`%LOCALAPPDATA%/Tools/gradle-build-gate/logs/d9a2b9a27cd14a038d660cd76143a079.log`.

The normal APK's SHA-256 is
`1152321f6253458f569f7099e140dd6737597ecff14f4c47e17f83b11e138174`.
Its verified signer matches the prior debug APK. Normal joined Pause at 12,359
lookups / 31,527 pending preceded signer-preserving installation; installed
base.apk matches that digest, and configuration plus both protected secure-storage
digests are unchanged. After shared metadata recovery completed, normal Resume
advanced the same saved job from 12,359 to 12,361 lookups / 31,525 pending without
sign-in or a replacement capture. The library populated normally after recovery.
Normal menu inspection passed on the newly downloaded supported Master System
installation: the installed UI exposes “Open in RetroArch”, and selecting it
launches Genesis Plus GX. The existing unmanaged Mega Drive copy correctly did
not expose that owned launcher action. No native label claim relies on the host
source-wiring assertion alone.

The remaining Master System test now uses a newly created, isolated SD directory
selected through Console Settings and Android's folder picker. The saved target
is independently confirmed; only that system's destination was changed. The
original ROM is preserved. Normal DOWNLOAD published the exact 206,628-byte ZIP;
its SHA-256 matches the original SD copy. Actual online emulator boot reached
the game's animated start screen, visually inspected. The sibling `.sms` probe
was denied while the exact ZIP URI succeeded. Before cold offline verification,
normal joined Pause stopped job 76 at 12,531 requests / 31,345 pending. Only the
test emulator and R-Shop were stopped; no active default network was confirmed
before launching the new R-Shop process. A disconnected microG crash dialog was
dismissed normally without changing Google-service data or settings. A fresh
RetroArch process then reached the actual animated start screen while Android
reported no active default network. Wi-Fi was restored before normal reviewed
DELETE and re-download. The restored ZIP matched the original checksum and
booted again through the normal OPEN action. The expendable owned copy was then
removed through the normal exact-file review.

Normal Console Settings and Android folder selection restored the Master System
target; backing out through the list saved it. The full original configuration
digest matches. The empty test target is independently absent. Fresh checks
verify the original ROM, all 47 recorded save/state files and both RetroArch
configuration files unchanged. Temporary captures were inspected privately and
removed through cleanup transaction `aa052b425dc5de5b66e418780cfb024e`: six exact
members, 809,245 bytes, no exclusions/residuals. No owner ROM or save was deleted.

Returning to the full library exposed an Android input-focus ANR in the prior
owner process. Its trace was captured before any restart; that process later
exited. A new normal launch reproduced slow loading, not the same ANR. Dart CPU
samples identify full-catalogue shared recovery followed by collection-wide
artwork hash consumption. Neither that trace nor low memory pressure establishes
the exact earlier ANR cause. The saved metadata job was safely paused at 12,531
requests / 31,345 pending. After restoration, normal Resume in the new owner
process continued the same job without a chooser: 12,542 lookups / 31,333 pending,
374 rated. It is Running while request 415 waits; join normal Pause before
installation.

## SG-1000: normal device round trip verified

The normal APK from build 421 completed the standalone single-member `.sg` ZIP
cycle. Normal DOWNLOAD published the 21,280-byte container in an isolated target;
its SHA-256 matched the original. Normal OPEN launched installed Genesis Plus GX,
and the actual animated title screen was visually inspected. The exact owned ZIP
grant succeeded while the sibling `.sg` request was denied.

With metadata job 76 already normally Paused, only the test emulator and R-Shop
were stopped. Android's active default network was confirmed absent before a
new R-Shop process loaded its cached library. Normal OPEN launched a fresh
RetroArch process; the actual animated title screen was inspected offline.

After Wi-Fi restoration, normal reviewed DELETE removed only the isolated owned
ZIP. The remote entry remained downloadable. The hotel portal then blocked Google
HTTPS despite Android's stale validated status, and microG reported
NoRouteToHostException. Normal hotel portal authorization restored connectivity:
the connectivity endpoint returned 204 and Google's authorization host answered
over HTTPS. No account, Google-service data or credentials were reset. Normal
queue Resume then completed the existing restore without an account chooser.
The restored container's SHA-256 matched the original, and normal OPEN again
booted the actual animated title screen.

The expendable restored copy was removed through normal exact-file DELETE.
Console Settings and Android's folder picker restored the original destination;
after the normal settings write completed, the full configuration digest matched
the pre-test baseline. The empty test directory is independently absent. The
original ROM and all 49 recorded save/state/RetroArch configuration digests match.
Private visual captures were inspected and removed through cleanup transaction
`bf4382afc9dddd5d0ebf191c7b20ce61`: four exact members, 402,438 bytes, no residuals.
No original ROM, save, BIOS, cloud object or emulator setting was removed.

## Remaining acceptance

The three observed Sega ZIP recovery gates are satisfied independently. They do
not establish another console/format's restoration or trustworthy ranking.
Build 428 subsequently verified normal single-card, unmanaged local-first
browsing and the exact read-only observation grant; see the S7 reconciliation
ledger. This does not grant adoption/removal ownership. Full fresh metadata
coverage, defensible per-console Top-25 retention, current cloud comparisons and
reviewed migration remain required. S8-S11 are NOT STARTED.
