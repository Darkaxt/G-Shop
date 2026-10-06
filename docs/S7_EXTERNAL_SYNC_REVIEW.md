# S7 external device-sync review

Inspection and narrowly scoped guard implementation, 2026-10-06. This serves
MIGRATE-01 but is not a completed migration or permission to remove SD files.
S7 remains ACTIVE. The observed-behavior section records the pre-change audit;
the implementation section records its subsequent remediation.

## Observed current behavior

The inspected LoLSuite Manager lives at `H:\My Drive\Roms\LoLSuite Manager`.
It is not a Git worktree. During the initial audit no source, configuration or
ownership manifest was changed, and no plan/bootstrap/apply command was executed.

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

## Narrow device-only exclusion — implemented and host-verified

The deployed manager now accepts an optional `device.on_demand_folders` list in
`profiles/device-targets.json`. Entries are exact relative folders beneath the
configured ROM root, not archive collection names or selection caps. Absent or
empty preserves previous behavior. Invalid/duplicate normalized paths fail
validation. A configured folder and overlapping parent/child targets cannot be
synced; sibling folders remain available.

- Both planners reject excluded targets before archive resolution or ADB.
- Both apply bindings reject old immutable plans under the current configuration.
  The coverage CLI also rejects before loading the plan or policy. Both
  ownership-bootstrap routes reject excluded targets too.
- Plan-all reports exclusions and continues other targets. The normal menu and
  post-download planning offer omit them; explicit UI selection reports disabled
  sync without creating a plan.
- Operational exclusions are outside selection fingerprints. Independent
  comparisons with the previous serialization verified identical profile and
  coverage revisions for unaffected targets. Archive acquisition settings,
  rankings and ownership journals are unchanged.

The first focused configuration regression failed before implementation because
the field was unsupported. The exclusion and existing configuration, coverage
command and manager-UI checks then passed in one bounded serialized Python
process. Actual parsing/planners/binding/CLI/menu behavior is exercised; ADB and
transfer boundaries are isolated, so no live ROM mutation is claimed. No
download-manager/provider-block test or full suite was run.

A separate real CLI `coverage-plan` using a temporary current-config copy with
`gc` excluded rejected the target with the on-demand reason, creating no output
directory. The live configuration is unchanged: SHA-256
`7fe858f27c80af51fd6467371a6676f591c3c2effae988f7237d7dfdc6531b2e`.
The coverage-registry digest above is unchanged. No exclusion was activated in
the owner's live configuration and no actual SD removal occurred.

Source changes and focused tests are versioned as
[`on_demand_sync.patch`](../integrations/lolsuite/on_demand_sync.patch), because
the manager itself is not a Git repository. The source hunks' forward applicability
against exact pre-change copies and reverse applicability against deployed source
were checked;
this patch is also the defined exact recovery path
for these changes. Do not apply/reverse it against changed source without an
applicability check. Reproduce host verification from the manager directory:

```powershell
python -B -m unittest tests.test_device_sync_exclusion tests.test_device_sync.DeviceTargetConfigurationTests tests.test_device_sync.CoverageCommandTests tests.test_device_sync_manager_integration.DeviceSyncManagerIntegrationTests -q
```

Deployed source SHA-256 identities:

| File | SHA-256 |
| --- | --- |
| `device_sync.py` | `9827856f5f3e8ab81cb0f596cb2568e69541c0cd70e9098a87048449333cf365` |
| `device_policy.py` | `c1499deaab4dce835fc3742d125e344cccac3df89d67cad08e0c4f5cd502c47f` |
| `lolroms_downloader.py` | `a3b743112f3d706096470538520e6840cdd0bf85a788a714c5b8f286cc9a1d15` |
| `tests/test_device_sync_exclusion.py` | `210b80dde613dcb6917e69f3f03a62e05e5725904f0fbeeda7b34d1c4a1f90fd` |

The execution review must still activate only its reviewed target folders in the
live configuration, verify rejection of its exact affected plans, check for an
already active transfer, and revalidate before removals. This guard does not
control alternative configurations, unmodified script copies or other sync apps.
Save protection, complete ranking and all other removal gates remain required;
the guard's availability alone does not close MIGRATE-01.

Reviewed cleanup `607cee57ce722902ffe2a4b426bce653` removed only the temporary
before-images, validation copies and disabled-config fixture (1,033,689 bytes;
permanently removed). Their recovery purpose is now supplied by the versioned
patch. The persistent tests create self-cleaning fixtures beneath existing
`D:\Temp`; they were freshly verified after the temporary working tree was
removed and do not depend on it. No user file or ongoing S7 observer was cleaned.
