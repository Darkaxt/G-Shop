# S7 external device-sync review

Read-only inspection, 2026-10-06. This is MIGRATE-01 evidence, not a completed
migration safeguard or permission to remove SD files. S7 remains ACTIVE.

## Observed current behavior

The inspected LoLSuite Manager lives at `H:\My Drive\Roms\LoLSuite Manager`.
It is not a Git worktree. No source, configuration or ownership manifest was
changed, and no plan/bootstrap/apply command was executed.

- `device_sync.py:2459`, `build_sync_actions`, resolves the archive selection
  against current device files. An absent desired file is an `add`, whether or
  not it still has a managed-file record. Removing an ownership entry is
  therefore not an exclusion from future transfers.
- `retirement_mode=preserve-all` changes retirement of present undesired files;
  it does not suppress additions. PS2's current preserve-all setting would not
  prevent refill either. Archive selection caps are not R-Shop's dynamic Top-25.
- `lolroms_downloader.py:8052`, `offer_post_job_device_sync`, offers planning or
  exit after an archive job. The reviewed-plan UI separately requires **Apply
  reviewed plan**. Both CLI transfer entry points, `apply` and `coverage-apply`,
  require `--confirm-transfer`. No automatic apply was found in these paths.
- The coverage registry has no target opt-out field. Its parser rejects unknown
  fields and requires bidirectional root/target references; deleting a target
  entry alone or inserting an invented flag is not a valid configuration change.

The Windows inspection found zero matching scheduled-task actions, zero matching
HKCU/HKLM Run values and zero active manager processes. Matching was limited to
`lolroms`, `lolsuite`, `device_sync` and `r-shop` in task/startup commands, and the
actual manager script names in process command lines. This does not establish
absence of unrelated launchers, indirect scripts or device-side sync services.
FolderSync was not inspected or changed.

Inspected file SHA-256 identities:

| File | SHA-256 |
| --- | --- |
| `device_sync.py` | `ee553fb80cabf77953b52da7db6ff7b72e65e3ceed93e97e7e603d9184d3cce7` |
| `lolroms_downloader.py` | `14ef6fb30538c42bb91f7c49f2c06155011c96297bf33635249cf3cf0440a8d2` |
| `profiles/device-coverage.json` | `e49cbfad68b14b9676457bb145ee5caaa56802a8d434d80611489cb1816f4ced` |

## Migration boundary

No current silent LoLSuite refill was found, but a later explicitly approved
LoLSuite plan can restore intentionally removed ROMs. The existing archive
profiles and ownership journals cannot be treated as an on-demand retention
policy or edited to manufacture migration completion.

Before exact reviewed migration execution, reconcile its actual console targets
with the external sync workflow. Establish and verify the target-specific
no-refill arrangement, repeat the relevant launcher/activity inspection, and
record it in the private execution review. Keep archive download profiles and
FolderSync unchanged. Do not apply old LoLSuite device plans to migrated targets.
The arrangement must be real and verified, not merely an operator warning in
this document. Its implementation and execution-time verification remain S7
work; no new stage, general LoLSuite rewrite or required-criterion waiver is
created by this review.
