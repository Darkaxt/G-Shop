# Fork development contract

This fork is preparing two features: native Google Drive on-demand game storage,
and independent, freshly scraped metadata with rating overlays and integrated
metadata-backed filters.
An additional authorized S8 adds per-ROM companion launching: emulator/ROM on
the Thor's top display, linked installed Android app on the bottom. Review Cocoon
source/licensing when that stage starts, not during earlier-stage implementation.
Final S9 audits supported cartridge and legacy-media artwork coverage. It must
not open a second ACTIVE stage or trigger speculative console-art generation.
Authorized S10 adds emulator-aware save/save-state backup sync inside R-Shop.
Leave the existing device save-sync app and laptop save-sync task unchanged until
S10 verifies their R-Shop replacement. Then identify and uninstall the exact old
device sync package and stop/disable only the scheduled task invoking
`sync-retrobat-saves.ps1`, as authorized on 2026-10-07. Preserve saves, cloud
backups and the laptop script. Do not start S10 while S7-S9 is ACTIVE.

- Read `docs/SPECIFICATION.md` as the authority, then
  `docs/IMPLEMENTATION_PLAN.md` and `docs/IMPLEMENTATION_STATUS.md`.
- Implementation was authorized after preparation on 2026-09-08. Use the staged
  plan without adding routine approval gates. The plan cannot weaken the
  specification. Standard metadata account credentials have been supplied;
  provider access must be verified, not inferred from credential presence.
- Preserve upstream behavior, licenses, and existing user data. Work on
  `codex/` branches. No forced pushes or unrelated refactoring.
- ROM Google Drive access is read-only. SAVE-01 separately authorizes opt-in
  backup-only writes in S10, never ROM/SD mirroring or archive mutation.
  Do not publish ROMs, private library inventories,
  OAuth tokens, account credentials, signing material, or diagnostic exports.
- Old scraped metadata is not the baseline. Fresh scraping is required.
- Keep game identity, file identity, metadata provenance, transfer state, and
  installation ownership distinct. Never borrow a base game's score for a hack.
- No bulk downloads, library cleanup, account changes, device installation,
  release builds, or releases during preparation.
- During implementation, run one test workload at a time. Use bounded fixtures,
  deterministic events/cancellation, and streaming IO. Do not start another test
  process while the previous process is still running.
- Run Windows Gradle through the installed shared build-gate helper, holding
  `Local\Darka.AndroidGradleBuildGate` through inspection, waits and command exit.
  Follow QA-01's two-worker, no-parallel, 3 GB heap and native/test-fork profile;
  report observed settings and never interrupt another build to acquire the gate.
- Prefer `D:\Temp` for attributable temporary work; keep permanent source here.
  Remove only task-owned temporary artifacts after verification.
- Reconcile each implemented stage against the specification and record fresh
  evidence. Do not call implementation complete with required deferrals or
  failed acceptance criteria. Commit verified work when applicable; deployment
  and release require their own authorization.
