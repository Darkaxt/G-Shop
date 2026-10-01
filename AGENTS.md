# Fork development contract

This fork is preparing two features: native Google Drive on-demand game storage,
and independent, freshly scraped metadata with rating overlays and integrated
metadata-backed filters.
An additional authorized S8 adds per-ROM companion launching: emulator/ROM on
the Thor's top display, linked installed Android app on the bottom. Review Cocoon
source/licensing when that stage starts, not during earlier-stage implementation.

- Read `docs/SPECIFICATION.md` as the authority, then
  `docs/IMPLEMENTATION_PLAN.md` and `docs/IMPLEMENTATION_STATUS.md`.
- Implementation was authorized after preparation on 2026-09-08. Use the staged
  plan without adding routine approval gates. The plan cannot weaken the
  specification. Standard metadata account credentials have been supplied;
  provider access must be verified, not inferred from credential presence.
- Preserve upstream behavior, licenses, and existing user data. Work on
  `codex/` branches. No forced pushes or unrelated refactoring.
- Google Drive is read-only. Do not publish ROMs, private library inventories,
  OAuth tokens, account credentials, signing material, or diagnostic exports.
- Old scraped metadata is not the baseline. Fresh scraping is required.
- Keep game identity, file identity, metadata provenance, transfer state, and
  installation ownership distinct. Never borrow a base game's score for a hack.
- No bulk downloads, library cleanup, account changes, device installation,
  release builds, or releases during preparation.
- During implementation, run one test workload at a time. Use bounded fixtures,
  deterministic events/cancellation, and streaming IO. Do not start another test
  process while the previous process is still running.
- Prefer `D:\Temp` for attributable temporary work; keep permanent source here.
  Remove only task-owned temporary artifacts after verification.
- Reconcile each implemented stage against the specification and record fresh
  evidence. Do not call implementation complete with required deferrals or
  failed acceptance criteria. Commit verified work when applicable; deployment
  and release require their own authorization.
