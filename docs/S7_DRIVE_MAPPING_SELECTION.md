# S7 explicit Drive mapping selection — 2026-10-09

Authority: CORE-02 / DRIVE-02. S7 remains the sole ACTIVE stage.

## Root cause and correction

The source mapping editor initialized saved selections, then assigned every
unique alias to any null selection. Merely opening an existing source could
therefore enable unrelated consoles, including consoles deliberately unmapped.
Saving one intended addition persisted those implicit changes through the normal
replace-all configuration writer.

Keep alias suggestions separate from selected folder IDs. Display a unique
suggestion below an unmapped selector; only explicit selection changes its value.
Existing assignments (including previously observed folders no longer listed),
empty assignments and ambiguous aliases retain their actual selection state.
No source, identity, catalogue, storage schema or authorization change is needed.

## Verified on the host

- Regression-first checks reproduced automatic selection for a unique alias and
  a previously configured source with no mapping for that console.
- Focused widget verification passes: empty/ambiguous aliases, lazy searchable
  folder choices, explicit choose/clear/controller-cancel and ordinary cancel.
- The editor's actual save path uses the real SourcesNotifier configuration
  writer with in-memory storage. Unchanged save leaves SNES disabled and does
  not create DSi; explicitly adding DSi creates only that mapping. Existing NES
  mapping, other-source SNES mapping and the source object remain intact. The
  test requires a real completed save, not just unchanged state after an error.
- Scoped Dart analysis and git diff checks pass. The existing notifier checks
  also passed during diagnosis; their pre-existing missing-databaseFactory
  purge diagnostics are not claimed as live database-purge verification.
- Shared-gate request 433 (`3032e4bc80bb41909568d53722a5f840`) completed with
  exit 0 and supervisor completion verified. Assembly succeeded in 46 seconds.
  Observed workers=2, parallel=false and Gradle heap=3 GiB; existing 1 GiB
  metaspace/256 MiB code-cache arguments are preserved. Kotlin uses the previously
  assessed 2.2.20 in-process strategy. Configured test tasks use one 512 MiB fork,
  fail-fast and no ignored failures; assembly did not execute those tests.
  The final gate-acquisition flag was omitted by tool-output truncation; the
  request used the mandatory supervisor and was not launched separately.
  All 265 inspected CXX compile/link blocks in 11 current Ninja files use the
  depth-one native pool. No memory-related failure or budget increase occurred.
  Private build log:
  `%LOCALAPPDATA%/Tools/gradle-build-gate/logs/00dd1107cd044ab4b0bc5d57ae5f83e2.log`.
- Built debug APK: 179,520,160 bytes, SHA-256
  `6d2e7178037e648fa82def408877e6a8937fb8167a46e817a7cf501ecb922ecd`.
  APK verification passes with unchanged signer SHA-256
  `06197430e1a4ba85dca54f7a2ecf8a2db5cc2c2e76eb8f7516e8acf3d1e6a934`.

## Native verification remains required

This APK has not replaced the running app. The normal collection refresh is
actually advancing in PID 1335: the fixed read-only observer measured committed
pages 3,248 -> 3,911, with active generation 1 / pending generation 2 retained.
The saved ScreenScraper job 76 also advances (13,618 requested at the latest
metadata observation), without replacing its immutable capture. Configuration
hash remains `eca976db992000116ba56c3dee089955081099952ca4dab2e63be2a53724603d`.
No sign-out, source change, ROM operation or worker restart was performed.

After a normal worker boundary, install the signer-preserving update, verify the
normal native editor and add the observed DSi mapping while checking that all
other mappings remain unchanged. Preserve the existing DSiWare files and saved
job membership. Full metadata, current publication, defensible retention and
reviewed migration remain required S7 work; S8-S11 remain NOT STARTED.
