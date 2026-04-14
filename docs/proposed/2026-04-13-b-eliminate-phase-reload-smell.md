## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Architecture violations — layer placement and dependency direction |
| `ai-dev-tools-code-quality` | Code quality issues including duplicated logic and fallback anti-patterns |
| `ai-dev-tools-enforce` | Post-change standards enforcement; run on all changed files at the end |
| `ai-dev-tools-swift-testing` | Swift test conventions |

## Background

`PRModel` manages the pipeline phases (diff, prepare, analyze, report) by calling use cases that stream `PhaseProgress<Output>` events. Every use case already emits `completed(output: Output)` carrying the phase result — but several phase handlers ignore the payload and instead call `reloadDetail()` to read the result back from disk.

This "write to disk, reload from disk to get your own data back" pattern is a code smell that:
- Creates unnecessary async round-trips
- Introduces timing bugs (the reload is fire-and-forget, so callers reading state immediately after may see stale data — exactly the bug that caused "Analyze All" to run with 0 tasks)
- Obscures data flow (the source of truth appears to be disk, not the operation that just ran)

The correct pattern — already used correctly by `runComments` — is to capture the output from the `.completed(output:)` event and apply it directly to in-memory state. Disk writes remain for persistence across launches; reading back what you just wrote is eliminated.

**Affected handlers in `PRModel`:**
- `runPrepare` — ignores `PrepareOutput`, currently calls `await reloadDetailAsync()` (the bug fix applied earlier)
- `runAnalyze` — ignores `PRReviewResult`, relies on `completePhase(.analyze)` → `reloadDetail()`
- `runFilteredAnalysis` — ignores `PRReviewResult`, calls `reloadDetail()` directly
- `runReport` — ignores `ReportPhaseOutput`, relies on `completePhase(.report)` → `reloadDetail()`
- `refreshDiff` — partially uses `SyncSnapshot` (commitHash only), still calls `reloadDetail(commitHash:)`

**Correct pattern (already in `runComments`):**
```swift
case .completed(let output):
    comments = output   // applied directly, no reload
    commentPostingState = .completed(logs: logs)
```

The refactor also covers `completePhase`, which unconditionally calls `reloadDetail()` for all phases. Once each phase handler applies its own output directly, that call becomes dead code and should be removed.

## Architectural Principles for This Refactor

> These apply across every phase of implementation.

### Layer responsibilities — do not cross them

`PRModel` is Apps layer (`@Observable`, `@MainActor`). Use cases are Features layer. The boundary is:
- **Use cases produce output** — they stream it, they do not touch model state
- **`PRModel` consumes output** — it stores what use cases return, it does not orchestrate

The refactor must not drift into `PRModel` calling multiple use cases in sequence to compensate for missing data. If output is missing from a use case payload, fix the use case — don't patch the model.

### All new stored properties must be `private(set)`

The architecture rule: views must not mutate model state directly. Every phase output property added to `PRModel` needs `private(set)`. Without it, any view that imports the model can set `preparation`, `analysis`, etc., bypassing the phase machinery.

### `applyDetail` must not overwrite in-progress state

`applyDetail` is called both on launch (disk restore) and after `reloadDetail()` fire-and-forgots complete. After this refactor, it will also set the new stored properties. If a phase is currently running when `applyDetail` fires, it must not overwrite that phase's in-progress or just-written output. `applyDetail` already guards `phaseStates` this way:

```swift
if case .running = phaseStates[phase] { continue }
if case .refreshing = phaseStates[phase] { continue }
```

Apply the same guard to `preparation`, `analysis`, `report`, and `syncSnapshot`. Only update them from `applyDetail` if the corresponding phase is not currently running.

### `inProgressAnalysis` and `analysis` are distinct — preserve the merge

The current computed property:
```swift
var analysis: PRReviewResult? { inProgressAnalysis ?? detail?.analysis }
```

`inProgressAnalysis` is the live streaming accumulator — it shows partial results in the UI while the analyze phase runs. `analysis` is the finalized result after completion. When converting `analysis` to a stored property, preserve this semantics. The public-facing computed property should remain:

```swift
var analysis: PRReviewResult? { inProgressAnalysis ?? _savedAnalysis }
```

where `_savedAnalysis` (or similar private name) is the stored property set from the use case payload. Do not collapse `inProgressAnalysis` into `analysis` — they serve different roles and both are visible to the UI.

### `PRDetail` is the disk-restore container — keep it intact

`PRDetail` is populated by `LoadPRDetailUseCase` and used as the source for the on-launch restore path. Do not remove fields from it or repurpose it as a runtime container. It represents "what was persisted to disk," not "what is currently happening." The new stored properties on `PRModel` are the runtime view; `PRDetail` remains the disk snapshot.

### Use cases must not be modified to update model state

Use cases are Features layer — they must not import anything from the Apps layer or hold references to `PRModel`. The output flows one way: use case → stream → model. If a use case seems to need a reference back to the model, that is a sign the design is wrong.

## Phases

## - [x] Phase 1: Add stored output properties to PRModel

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`
**Principles applied**: Added `private(set)` stored properties for `syncSnapshot`, `preparation`, `report`, and a private `_savedAnalysis` backing property; `analysis` remains a computed property merging `inProgressAnalysis ?? _savedAnalysis` to preserve streaming behavior. `applyDetail` populates stored properties only when the corresponding phase is not `.running`. Cleared stored properties in `resetAfterDataDeletion` and `switchToCommit` to avoid stale UI state when those methods nil out `detail`.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

`PRModel` currently exposes phase outputs as computed properties that read through `detail`:

```swift
var syncSnapshot: SyncSnapshot? { detail?.syncSnapshot }
var preparation: PrepareOutput? { detail?.preparation }
var analysis: PRReviewResult? { inProgressAnalysis ?? detail?.analysis }
var report: ReportPhaseOutput? { detail?.report }
```

Convert these to stored properties with `private(set)`. The public names stay the same except for `analysis` — see below.

**`analysis` requires a private backing property.** Because `inProgressAnalysis ?? detail?.analysis` must remain the public computed value (see architectural note above), introduce a private stored property for the finalized result:

```swift
private(set) var syncSnapshot: SyncSnapshot?
private(set) var preparation: PrepareOutput?
private var _savedAnalysis: PRReviewResult?
private(set) var report: ReportPhaseOutput?

// Public merge — preserves streaming behavior for views
var analysis: PRReviewResult? { inProgressAnalysis ?? _savedAnalysis }
```

**Update `applyDetail` to populate these stored properties from disk**, but only when the corresponding phase is not running. Use the same pattern as the existing `phaseStates` guard:

```swift
// Only restore disk-backed outputs when not in the middle of running them
if case .running = phaseStates[.prepare] {} else { preparation = newDetail.preparation }
if case .running = phaseStates[.analyze] {} else { _savedAnalysis = newDetail.analysis }
if case .running = phaseStates[.report]  {} else { report = newDetail.report }
// syncSnapshot follows .diff phase
if case .running = phaseStates[.diff] {} else { syncSnapshot = newDetail.syncSnapshot }
```

No behavior changes yet — phase handlers still call `reloadDetail()` at this point.

## - [x] Phase 2: Fix prepare phase handler

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Captured `PrepareOutput` from `.completed(let output)` and assigned it directly to `preparation`, removing the `await reloadDetailAsync()` disk round-trip. The payload is the source of truth; no reload needed.

**Skills to read**: `ai-dev-tools-code-quality`

In `runPrepare`, capture the `PrepareOutput` payload and apply it directly:

```swift
case .completed(let output):
    prepareAccumulator = nil
    prepareStreamModel?.finalizeCurrentStreamingMessage()
    preparation = output
    logger.info("Prepare phase completed", metadata: ["tasks": "\(output.tasks.count)"])
    completePhase(.prepare)
```

Remove the `await reloadDetailAsync()` call added as the temporary fix. The payload is the source of truth — no disk round-trip needed.

**What to watch for:** `preparation` is read by `runAnalyze` and `runFilteredAnalysis` on the very next iteration of the phase loop. Setting it here directly — before `completePhase` marks the phase complete — is the correct and sufficient ordering.

## - [x] Phase 3: Fix analyze phase handlers

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Captured `PRReviewResult` from `.completed(let output)` in both `runAnalyze` and `runFilteredAnalysis`. Assigned directly to `_savedAnalysis` and called a new private `updateAnalysisState(from:)` helper to set `analysisState` from the payload. Removed the standalone `reloadDetail()` call from `runFilteredAnalysis`. Extracted the helper to eliminate duplicated logic between these handlers and the `applyDetail` disk-restore path.

**Skills to read**: `ai-dev-tools-code-quality`

Both `runAnalyze` and `runFilteredAnalysis` ignore the `PRReviewResult` payload. In both:

```swift
case .completed(let output):
    analyzeStreamModel?.finalizeCurrentStreamingMessage()
    inProgressAnalysis = nil
    for key in evaluations.keys { evaluations[key]?.accumulator = nil }
    _savedAnalysis = output
    analysisState = updateAnalysisState(from: output.summary)
    completePhase(.analyze)
```

Remove the standalone `reloadDetail()` call in `runFilteredAnalysis`. The `completePhase` reload is handled in Phase 6.

**`analysisState` must be set here, not from `applyDetail`.** Currently `analysisState` is populated in `applyDetail` by reading `analysisSummary` from disk. Since `PRReviewResult.summary` already carries `PRReviewSummary` inline, set `analysisState` from `output.summary` at this point. Extract a private helper to keep the logic in one place rather than duplicating it between this site and `applyDetail`'s disk-restore path.

**Do not add orchestration logic here.** Setting `_savedAnalysis` and updating `analysisState` from the payload is appropriate model work. Adding calls to other use cases, spawning Tasks, or triggering further phase transitions from inside this handler is not — that belongs in `runAnalysis`.

## - [x] Phase 4: Fix report phase handler

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Captured `ReportPhaseOutput` from `.completed(let output)` and assigned it directly to `report`, removing the implicit reload via `completePhase`. No other state updates needed — `analysisState` is owned by Phase 3.

**Skills to read**: `ai-dev-tools-code-quality`

`runReport` ignores `ReportPhaseOutput`:

```swift
case .completed(let output):
    report = output
    completePhase(.report)
```

No other state updates are needed here — `analysisState` is already handled in Phase 3 (set when analyze completes), and `report` is the only field `runReport` owns.

## - [x] Phase 5: Fix diff phase handler

**Skills used**: `ai-dev-tools-code-quality`, `ai-dev-tools-architecture`
**Principles applied**: Added `storedEffectiveDiff: GitDiff?` to `SyncSnapshot` (Features → Services dependency, correct direction). Updated `FetchPRUseCase.parseOutput` to load it from disk via `PhaseOutputParser.loadEffectiveDiff`, keeping the disk read inside the use case. In `refreshDiff`, replaced `reloadDetail(commitHash:)` with direct assignment of `syncSnapshot` and `resolvedDiff` from the snapshot payload. Changed `currentCommitHash` to prefer `syncSnapshot?.commitHash ?? detail?.commitHash` so subsequent phases (analyze, report) use the correct commit hash without a disk round-trip.

**Skills to read**: `ai-dev-tools-code-quality`, `ai-dev-tools-architecture`

The diff phase is the most complex because `SyncSnapshot` is missing one field: `storedEffectiveDiff: GitDiff?`.

**What `SyncSnapshot` carries:** `prDiff`, `files`, comment counts, `commitHash` — enough to build `resolvedDiff` using the fallback path (`prDiff.toEffectiveGitDiff()`).

**What's missing:** `storedEffectiveDiff` — the pre-parsed effective diff written to `effective-diff-parsed.json` by `PRAcquisitionService.acquire`. It is computed in memory during `acquire()` but not returned in `AcquisitionResult`, and not included in `SyncSnapshot`.

**Fix:** Extend `FetchPRUseCase.parseOutput` to read `storedEffectiveDiff` from disk (via `PhaseOutputParser.loadEffectiveDiff`) and include it in `SyncSnapshot`. This keeps the disk read contained within the use case as an implementation detail — the consumer (`PRModel`) still receives a complete payload. Also add `storedEffectiveDiff: GitDiff?` to `SyncSnapshot`.

**Layer check:** `SyncSnapshot` is in the Features layer (`PRReviewFeature`). `GitDiff` is in the Services layer. Adding `storedEffectiveDiff: GitDiff?` to `SyncSnapshot` is a downward dependency (Features → Services) — correct.

Then in `PRModel.refreshDiff`:
```swift
case .completed(let snapshot):
    syncSnapshot = snapshot
    resolvedDiff = ResolvedDiff(prDiff: snapshot.prDiff, storedEffectiveDiff: snapshot.storedEffectiveDiff)
    phaseStates[.diff] = .completed(logs: logs)
    // remove reloadDetail(commitHash:)
```

**What `refreshDiff` must not do:** It must not call `LoadPRDetailUseCase` or read from disk to supplement what `SyncSnapshot` is missing. If something is genuinely missing from `SyncSnapshot`, fix `SyncSnapshot` — don't patch the model handler.

Note: `baseRefName` and `availableCommits` are also currently read from `PRDetail` (populated by `LoadPRDetailUseCase`). These are not in `SyncSnapshot`. Check whether any view depends on them being updated immediately after the diff phase, or whether the on-launch `applyDetail` path is sufficient. If they're needed at runtime, they belong in `SyncSnapshot`, not in a supplemental reload.

## - [x] Phase 6: Remove reloadDetail() from completePhase

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Verified all callers of `completePhase` (runPrepare, runAnalyze, runFilteredAnalysis, runReport) already apply their output directly to stored properties before calling it. Removed the now-dead `reloadDetail()` call from `completePhase`. Audited remaining `reloadDetail()` call sites — `resetPhase`, `switchToCommit`, `resetAfterDataDeletion`, `loadDetail`, and `runSingleAnalysis` — all are legitimate disk-restore or post-user-action uses and were left intact.

**Skills to read**: `ai-dev-tools-code-quality`

Once all phase handlers apply their output directly (Phases 2–5), the `reloadDetail()` call in `completePhase` is dead code:

```swift
private func completePhase(_ phase: PRRadarPhase) {
    let logs = runningLogs(for: phase)
    reloadDetail()   // ← remove this
    phaseStates[phase] = .completed(logs: logs)
}
```

Verify no remaining callers of `completePhase` depend on the side-effect reload. If any do, make those callers set their state explicitly before calling `completePhase`.

Also audit remaining call sites of `reloadDetail()` — in `resetPhase`, `switchToCommit`, `resetAfterDataDeletion`, `loadDetail`. These are legitimate uses (restoring from disk after user actions, not after writes) and must stay as-is.

**`reloadDetail` itself stays.** The fire-and-forget method is still needed for the sync call sites (`resetPhase`, `switchToCommit`, `resetAfterDataDeletion`, `loadDetail`) that cannot await. Do not delete the method — only remove the call inside `completePhase`.

## - [ ] Phase 7: Validation

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`

- Run `swift build` in `AIDevToolsKit/` — no new errors or warnings
- Run `swift test` in `AIDevToolsKit/` — all tests pass
- Run the app and trigger "Analyze All" — verify each PR actually runs evaluations (previously broken by the reload timing bug)
- Open an individual PR and run Analyze — verify it still works
- Open the app cold (no cached state) and verify each phase loads correctly from disk on launch (the `applyDetail` path)
- Verify `analysis` still shows streaming results mid-run (the `inProgressAnalysis ?? _savedAnalysis` merge)
- Run `ai-dev-tools-enforce` on all files changed during this plan
