# Large-environment performance and timeout review

Reviewed 2026-10-29 on `main` at `318ae09`, including the assessment accuracy changes.
This is a source review of the standard `Invoke-AdDiscoveryExport` path and its
`-IncludeSecurity` additions. It does not change runtime behavior. No customer AD
queries or load tests were run. Group nesting redesign is outside this review.

## First implementation pass

Implemented after the source review: SPN/SID-history presence filters, forest
counters and release of local identity/status datasets, batched CSV staging and
atomic publication with destination ACL preservation, and bounded ADWS probes.
`DiscoveryPerformance.Tests.ps1` covers late schema errors, interrupted producers,
concurrent destination creation, multi-valued query results, and probe budgets.

Local synthetic CSV runs completed at 10,000, 100,000, and 500,000 rows in both
PowerShell 7.6.9 and directly invoked Windows PowerShell 5.1. At 500,000 rows,
export took approximately 29 and 34 seconds, respectively; process peak working
set was approximately 210 MB and 235 MB. These are one-machine measurements of
three-column CSV serialization, not AD benchmarks or whole-run memory limits.

The findings below record the original baseline. Configurable search paging,
classified query retries, supervised dataset deadlines, and optional caching
remain outstanding. Native AD/GPO operations can still block until their native
timeouts; the new deadline covers connectivity probes, not DC enumeration.

## Findings, in priority order

### 1. A stalled external call can block the rest of the run

`Private/DiscoveryDiagnostics.ps1`, `Invoke-AdDiscoveryQuery` (line 199), invokes
queries synchronously. `Private/Invoke-AdDiscovery.ps1`, `Try-Export` (line 91),
catches errors after an action returns; it cannot enforce an elapsed deadline.
The public command exposes no toolkit-level operation deadline. GPO permissions,
object lookups, and OU ACL reads also call external cmdlets directly.

The existing two-attempt fallback limits retry count for wrapped queries. It does
not bound how long an attempt takes, and it is not used by every collector.
It also retries permission and other deterministic errors where another attempt
will usually add delay rather than recover coverage.

Recommended changes:

- Add separate limits for connection checks, individual object operations, and
  long-running dataset collection. Do not impose a two-minute deadline on an
  entire large inventory.
- Execute operations that need a hard deadline in a supervised worker process.
  A parent timer or `try/catch` around a synchronous call does not interrupt it.
  A process boundary provides a way to terminate a blocked worker without leaving
  it writing to the run folder.
- Give each attempt its own temporary output. On timeout, stop and verify worker
  termination before discarding its output or retrying. Publish a CSV only after
  successful completion; never label a timed-out export `EMPTY` or `OK`.
- Retain parent-owned failure records, original errors, selected domain/server,
  attempt duration, and progress. Continue independent datasets as the existing
  failure handling does.
- Retry transient connection and timeout failures only, with a bounded attempt
  count and total budget. Keep permission errors and target mismatches terminal.

### 2. DC selection declares a deadline that it does not enforce

`Private/Get-AdWritableDc.ps1` declares `TimeoutMs = 1500` (line 8), but never uses
that value. Its `Test-NetConnection` calls can wait much longer. It tests TCP 389
only, which does not establish availability of AD Web Services on TCP 9389.

Recommended changes:

- Implement a bounded connection probe using the declared timeout, including
  socket disposal and a limit for the whole candidate-selection stage.
- Include ADWS connectivity when selecting a DC for the AD module. Follow with
  the existing naming-context validation. An open port is a connectivity check,
  not proof that an authenticated query will work.
- Preserve explicit domain targeting and report why each candidate was rejected.

### 3. Several exports scan the domain for objects they later discard

- `Public/Get-AdAdSpns.ps1:20`: reads all users/computers, then removes objects
  with no SPNs. Add the presence requirement to the existing LDAP filter.
- `Public/Get-AdUsersSidHistory.ps1:19`: reads every user, then emits only SID
  history entries. Query `(sIDHistory=*)` instead.
- `Public/Get-AdServiceAccountCandidates.ps1:24`: reads every user, then selects
  SPN accounts, password-never-expires accounts, and name-prefix candidates.
  Preserve all three criteria when moving filtering to AD; SPNs alone would
  narrow coverage incorrectly. Compare the exact account set against the current
  client-side predicate.
- `Public/Get-AdPrivilegedPasswordAge.ps1:15` repeats privileged-account
  discovery already performed by the standard export. With security enabled,
  privileged group membership is also collected separately.
- `Public/Get-AdGpoDelegation.ps1:22` and
  `Public/Get-AdGpoInventory.ps1:23` each enumerate GPOs when security is enabled.
- `Private/Get-AdcsTemplatePermissions.ps1:10` requests security descriptors
  during enumeration, then requests each descriptor again at line 18.

Recommended changes: start with the SPN and SID-history filters. Then introduce
explicit per-domain/run reuse only where attributes, target, and completeness
match. Do not replace a failed source collection with an empty cached result.
Do not derive SID history or individual SPNs from summary counts: those counts
do not contain the raw values needed by these exports.

### 4. Memory grows with the whole forest and multiple copies of each dataset

`Private/Invoke-AdDiscovery.ps1:282` retains `$allUsers`, `$allComputers`, and
`$allGroups` across domains. Subsequent uses are only count reporting and result
counts. Repeated `+=` also copies the arrays as domains are added.

Core collectors buffer and sort raw AD objects. The query wrapper buffers its
result too. The coordinator retains transformed rows for status detail exports.
`Public/Export-AdCsvSafe.ps1:30` buffers every row again, then materializes
another complete set of projected rows at line 127. The existing property check
also creates a pipeline per row.

Recommended changes:

- Replace forest-wide row arrays with numeric totals, maintaining the existing
  semantics for collection success versus export failure.
- Release per-domain and detail datasets after their last consumer.
- Write normalized CSV rows incrementally into a temporary file and move it into
  place only after every row passes validation. Preserve header-only exports,
  column order, UTC date formatting, quoting, row-count diagnostics, and protection
  of an existing destination when a late row fails.
- Stream projection before considering removal of all collector buffering.
  Buffering currently prevents a failed first attempt from leaking partial rows
  into a successful retry. Preserve that guarantee.
- Keep current row ordering unless a separate contract change permits changing it.

### 5. Paging works today, but timeout recovery is not page-aware

Most AD searches use the module's default page size. They are already paged;
the absence of `-ResultPageSize` does not mean a single unpaged request.
`Public/Get-AdRecentlyCreatedObjects.ps1` explicitly requests 1,000-row pages.

Microsoft documents a two-minute timeout for each search page, and recommends a
smaller page size after a search timeout. The overall search can legitimately
take longer than two minutes. `Get-ADUser` defaults to 256 objects per page and an
unlimited result set.

Recommended changes:

- Offer a configurable page size on supported search cmdlets, retaining the
  current default initially. On a classified page timeout, allow one smaller-page
  retry under the total retry budget. Benchmark representative properties and DCs
  before choosing a different default.
- Keep result sets unlimited. A fixed `ResultSetSize` is truncation, not timeout
  recovery. Paging settings do not apply to every cmdlet or identity lookup.
- Log page-size policy, selected endpoint, attempt duration, rows observed, and
  last progress time. Do not infer completeness from the number received before
  a timeout. Discard incomplete attempts unless explicitly publishing a dataset
  with partial coverage.

### 6. Per-membership lookups remain a separate scaling cost

`Public/Get-AdGroupMembershipDetails.ps1:52` resolves every membership reference
through `Get-AdGroupMembershipMemberDetail`; that helper invokes `Get-ADObject`
for each reference (`Private/Get-AdGroupMembersRecursive.ps1:67`). It also stores
all detail rows for each group although only the one-member case consumes that
per-group list afterward. Overlapping memberships repeat object reads.

This remains relevant to normal exports even with nesting redesign excluded.
After the earlier priorities, consider a bounded target-specific member cache
and retaining only the one member needed for a single-member group. Preserve
per-group output rows and object-specific errors. Do not cache group-specific
detail rows as though they were account properties.

## Recommended delivery order

1. Reduce avoidable scans and memory retention; add source/output parity checks.
2. Enforce DC-probe timeouts and add configurable search paging with classified,
   bounded retries.
3. Add supervised operation deadlines, progress reporting, and atomic CSV
   publication. This is the step that prevents an unresponsive worker from
   blocking the whole run indefinitely.
4. Evaluate optional cache reuse using measured query counts and memory limits.

Keep domains sequential initially. Increasing concurrency before bounding memory
and AD load could worsen failures on a busy DC. No server-side timeout, LDAP
policy, or ADWS quota changes are proposed.

## Validation required before a large customer run

- Synthetic inventories at 10,000, 100,000, and 500,000 rows; capture elapsed time,
  query count, and peak process memory. Test security enabled and disabled.
- Exact dataset/row parity for SPNs, SID history, service candidates, GPOs, and
  privileged accounts, including null and multi-valued attributes.
- Failure injected after multiple pages: retry must neither lose rows nor emit
  duplicate rows from the incomplete attempt.
- A deliberately blocked worker: the parent must enforce its configured budget,
  terminate the worker, retain diagnostics, and continue another dataset.
- Network failures, denied access, target mismatch, delayed DC probes, unavailable
  ADWS, output-write failures, and a late schema-invalid row.
- A representative AD pilot to validate native paging and authentication under
  PowerShell 5.1 and 7. Synthetic tests cannot prove customer DC behavior.

Timeout-free collection cannot be guaranteed on an unhealthy or unreachable DC.
The intended guarantee is bounded waiting, visible incomplete coverage, and
continued collection of independent datasets.

## Microsoft references

- [AD filter timeout and paging behavior](https://learn.microsoft.com/en-us/powershell/module/activedirectory/about/about_activedirectory_filter?view=windowsserver2025-ps)
- [Get-ADUser page and result-set parameters](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-aduser?view=windowsserver2025-ps)
- [ADWS and LDAP network ports](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/service-overview-and-network-port-requirements)
