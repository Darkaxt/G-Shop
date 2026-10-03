# S4 requirement reconciliation

Authority: `SPECIFICATION.md`, revision 3. Reviewed against source at `172920a`
and the following test-only observation changes on 2026-10-03. No specification
requirement is removed. Current stage states are in `IMPLEMENTATION_STATUS.md`;
its chronological checkpoints describe their respective earlier states.

## Required backend workflows

| Requirement | Inspected behavior and evidence | Remaining boundary |
| --- | --- | --- |
| META-01: fresh full/system/game membership, legacy isolation and explicit outcomes | `metadata_catalogue_jobs_test.dart` snapshots actual `games` rows, excludes folders, scopes systems and preserves immutable membership. `metadata_refresh_jobs_test.dart` seeds legacy ratings, proves fresh requests despite existing facts, reports requested/matched/rated separately and explicit unsupported-platform outcomes. `metadata_retry_jobs_test.dart` preserves successful members and old reports while creating explicit selective retry generations. The recorded live ScreenScraper catalogue/review/cache workflow used the normal worker. | S5 owns visible controls/progress; S7 owns the actual entire-collection pass. Neither is claimed performed by these fixture jobs. |
| META-03: matching, corrections, raw/container distinction and exact releases | Catalogue checks preserve manual identity through equal-byte rename/reinsertion; changed bytes require review without deleting correction evidence. `library_verified_match_grouping_fixture.dart` exercises real adapter -> persistent worker -> publication -> offline grouping/query, including exact raw hashes/size, conflicting reviewed IDs, revisions, region/language and malformed/container evidence. `igdb_provider_fixture.dart` requires review for title candidates and rejects wrong platforms/base IDs. Production migrations retain bindings. Both shared fixtures passed Android's actual SQLite plugin in the inspected native ownership run. | No remote ROM hashing/decompression or silent filename equivalence is introduced. Normal correction UI is S5. |
| META-04: independent tags and original/project ownership | Reviewed catalogue tags, exact patch identities and finite alias normalization retain `T-Eng`, `Dub`, `Undub`, `Uncensor`, Hack, official/homebrew/demo and unknown classifications. Query/selector checks distinguish ordinary English, contradictory/unknown evidence and overlapping any/all tags. The actual worker/native ownership fixture verifies labelled original facts for reviewed modifications and separate project scores; hacks cannot acquire their base game's score. | S5 must expose these independent values and ownership labels; no unlimited tag extras or residency-policy changes. |
| META-05: scale/provenance/null/counts and reception gate | `scraped_metadata_test.dart` covers endpoints, missing/out-of-range values, source/date/scale and unknown counts. `SCORE_RECEPTION_ASSESSMENT.md` records 26 real matched identities across older/newer consoles and projects, independent comparisons and disagreements. The real production offline query log confirms 3 collection games/1 supported rank, preserving the exact IGDB user score. Shared host/Android production-policy fixtures reject low-vote extremes and use the identical community object for display/rank. | Only the assessed PS1/PS2/GBA/GameCube/Switch scope with known >=20 user ratings is accepted. Other scopes/counts remain advisory; no critic/total fallback. S5 owns visible scale/count/source/scope/confidence presentation. |
| META-06: durable jobs, budget, recovery, artwork and bounded resources | Refresh/retry/rate/artwork fixtures exercise joined cancellation, committed-item preservation, restart, offline/auth/quota outcomes, exclusive worker ownership, provider-wide daily/minute limits and explicit access recovery. Artwork uses the same budget, bounded PNG validation/native decoding and immutable publication; failed refresh cannot erase usable cache. The inspected native report proves 30,000 distinct selectors, 65,536-byte chunks, one transport, two blobs, reopen/offline replay and zero offline requests. | The earlier isolated Windows host wait remains unexplained. Its root-cause requirement is not satisfied by the successful native or repeat host workflows; see below. S5 owns actual scrolling/card wiring. |
| META-07: shared dynamic collection query | `library_query_test.dart` covers collection-only membership, canonical/disc/region/project grouping, stable ties, system/cross-system scope, rank-before-tag/genre/search/view intersection, any/all tags, no extras/backfill, sparse coverage and score/add/remove/refresh-driven invalidation. Shared selector/cache gives display and rank the same exact score. Production upgrade/reopen preserves facts/settings; query resource fixture inspects indexes and bounded pages. The inspected 30,000-game Android report records 128-row bounds, no filter projection writes/network requests and stable Top membership. | S5 must connect actual library/system/shelf state and focus/persistence to this same contract. The backend fixtures do not claim that UI wiring is delivered. |

These are requirement-relevant workflows, not a progress percentage or test-count
measure. Current source was compared with the fixture assertions and inspected
native/live reports. Existing verification remains applicable only to unchanged
code and boundaries; changed resource-fixture observation is verified separately.

## Unresolved original host wait

The first Windows process stopped advancing after request 9,027; its preserved
pre-recovery database has 9,026 matched and 20,974 pending items. There was no
provider quota/backoff state or virtual-memory exhaustion. SQLite integrity and
recovery were verified separately. A native CDB capture showed waiting threads,
but its nearest-export labels are not a Dart async stack and do not identify the
outstanding Future. The process was deliberately stopped before another workload.

Subsequent cache-only, debugger-assisted, read-only-VM-observed and Android runs
completed. None identifies the original cause. The installed Dart ReceivePort
implementation closes its underlying port on stream cancellation; the FFI use of
`recvPort.first` is not evidence of a port leak. The production image cache and
artwork loop were compared with the original-run commit: there is no relevant
production fix to credit for these successful repeats.

The opt-in host observer now works without a VM service: bounded sanitized FFI
summaries plus active cache-download state are available through GET on an
ephemeral IPv4 loopback listener. It never pauses an isolate, forces GC, changes
database/provider state, retries, times out or decides completion. It is confined
to the synthetic test; the normal app and default resource fixture are unchanged.
Its listener is closed in `finally`. A focused real-loopback contract verifies
GET/read-only observation and rejection of POST. Flutter's test HTTP override is
preserved; only that local contract uses the actual client.

The original VM-service-disabled configuration was rechecked in session 55923;
the actual tester command included `--disable-vm-service` and `Service.getInfo`
returned null. It completed 30,000 items, 600,308 acknowledged FFI operations,
database close/reopen and offline replay, with no pending operation or cache
download. Capture took 21,440 ms, total 641,259 ms, peak RSS 206,770,176 bytes,
maximum chunk 65,536 bytes and one active transport. The tester exited, loopback
listener closed and its exact fixture directory was absent; original evidence
remains. The default unobserved 256-item shared fixture also passed, including
offline reopen/replay (session 65153). Neither success is an original-cause finding.

### B5 — missing original wait evidence

- Blocked acceptance: S4's recorded original-host-wait investigation under
  META-06/QA-01. Current large native/host behavior passes, but the historical
  counterexample is not diagnosed or claimed fixed.
- Concrete missing evidence: the original live Dart async/FFI acknowledgement
  state was not captured before its process was stopped. CDB's unsymbolicated
  waiting-thread trace and database snapshot cannot reconstruct the outstanding
  Future. The available repeat runs do not reproduce it.
- Classification: external evidence availability, **not** a claim that the
  unidentified defect is external or that ordinary unfinished work is blocked.
  Creating more metadata components or repeating an identical passing stress
  workload cannot recover the missing original runtime state.
- Resolution: a live recurrence with its pending operation/cache phase and
  actual async/native call state, or additional exact original diagnostics that
  establish the cause; then a justified fix and relevant regression verification.
  The opt-in observer is ready for that recurrence without enabling VM debugging.
- Dependency: S4 cannot become COMPLETE, and S6/final reconciliation cannot close
  while B5 is unresolved. It remains owned by S4, not deferred to a later stage.
  Return to S4 first when evidence becomes actionable.

S4 is parked BLOCKED at B5. S5's dependencies are the now-verified provenance,
cache/query contracts and existing setup states, not a claim that the old Windows
tester wait is fixed. UI work may become the sole ACTIVE stage without dropping
this requirement or authorizing S6/S7 closure.
