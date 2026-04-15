## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules for layer placement and dependencies |
| `ai-dev-tools-code-quality` | Avoid force unwraps, raw strings, duplicated logic |
| `ai-dev-tools-enforce` | Verify standards compliance after changes |
| `ai-dev-tools-swift-testing` | Swift test file conventions |

## Background

`PRModel` has a private `reloadReviewComments()` method called in 5 places. It fires a detached `Task` that does a full disk round-trip: load violation files → load cached GitHub comments → reconcile via `ViolationService` → apply suppression → assign `self.reviewComments`.

Four of those calls are wrong. One (live streaming) is correct.

### The 5 Call Sites

| # | Location | Root Cause | Action |
|---|----------|------------|--------|
| 1 | `applyDetail()` | `PRDetail.reviewComments` is already computed by `LoadPRDetailUseCase` but `applyDetail` ignores it and reloads | Fix: use `detail.reviewComments` |
| 2 | `refreshPRData()` | `FetchPRUseCase.parseOutput()` does all the disk work but `SyncSnapshot` carries only counts, not the reconciled list | Fix: add `reviewComments` to `SyncSnapshot` |
| 3 | `handleTaskEvent(.completed)` | `TaskProgress.completed` carries only `RuleOutcome` — same root cause as the others, use case doesn't return `[ReviewComment]` | Fix: add `reviewComments` to `TaskProgress.completed` |
| 4 | `submitSingleComment` (postNotConfirmed) | `PostSingleCommentUseCase` already tried 3 network fetches internally and failed. Reloading disk returns the same pre-post state already in `reviewComments`. No reload of any kind helps here. | Fix: remove — log only |
| 5 | `runAnalysis()` end | `reloadReviewComments()` fires a fire-and-forget `Task`, so comments update races with the function returning | Fix: await `FetchReviewCommentsUseCase` directly |

After this plan: `reloadReviewComments()` has no callers and can be deleted.

### Key Architecture Facts

- `PRDetail.reviewComments: [ReviewComment]` is populated by `LoadPRDetailUseCase` (calls `FetchReviewCommentsUseCase.execute(prNumber:commitHash:)` disk-only overload)
- `FetchPRUseCase.parseOutput()` already calls `PRDiscoveryService.loadComments()` and `ViolationService` to produce counts; it can produce the full `[ReviewComment]` with one extra call
- `FetchReviewCommentsUseCase.execute(prNumber:minScore:commitHash:)` — the disk-only overload; clients call this without knowing whether data comes from cache or network
- `ViolationService.reconcile(pending:posted:)` + `CommentSuppressionService.applySuppression(to:)` are the reconciliation pipeline (used inside `FetchReviewCommentsUseCase`, not called directly from `PRModel`)

---

## Phases

## - [x] Phase 1: Fix `applyDetail()` — use `detail.reviewComments` directly

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: `applyDetail(_:)` now assigns `reviewComments = newDetail.reviewComments` directly instead of spawning a detached `Task` via `reloadReviewComments()`. This eliminates the redundant disk round-trip since `LoadPRDetailUseCase` already computed the value. Architecture layer boundaries respected — `PRModel` (Apps) reads from use case output, not storage services directly.

**Skills to read**: `ai-dev-tools-architecture`

`LoadPRDetailUseCase.execute()` already computes `reviewComments` (stored in `PRDetail.reviewComments`). `applyDetail(_:)` receives the fully-populated `PRDetail` and then redundantly re-derives the same value from disk via `reloadReviewComments()`.

**Change** in `PRModel.swift` — in `applyDetail(_:)`, replace:
```swift
reloadReviewComments()
```
with:
```swift
reviewComments = newDetail.reviewComments
```

No type changes needed. `applyDetail` is only called from `reloadDetailAsync()` so no other call sites to update.

**Files**: `PRModel.swift`

---

## - [x] Phase 2: Add `reviewComments` to `SyncSnapshot`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: `SyncSnapshot` now carries the reconciled `[ReviewComment]` list produced by `FetchReviewCommentsUseCase` (disk-only overload) inside `FetchPRUseCase.parseOutput()`. The `.completed` handler in `PRModel.refreshDiff()` assigns directly from the snapshot, and the redundant `reloadReviewComments()` call in `refreshPRData()` is removed. App layer reads from use case output; no storage services called directly from `PRModel`.

**Skills to read**: `ai-dev-tools-architecture`

`FetchPRUseCase.parseOutput()` is the single point that assembles a `SyncSnapshot` from disk. It already calls `PRDiscoveryService.loadComments()` (to get counts). It should also produce the reconciled list so `refreshDiff()`'s completion handler can set `reviewComments` directly.

`parseOutput()` is already `static async` and receives `config`, `prNumber`, and `commitHash` — all params needed by `FetchReviewCommentsUseCase`.

**Step A** — `SyncSnapshot.swift`: Add property with default `[]` in init:
```swift
public let reviewComments: [ReviewComment]
```

**Step B** — `FetchPRUseCase.parseOutput()`: After loading `comments`, add:
```swift
let reviewComments = await FetchReviewCommentsUseCase(config: config)
    .execute(prNumber: prNumber, minScore: 1, commitHash: resolvedCommit)
```
Pass `reviewComments: reviewComments` to the `SyncSnapshot` init.

**Step C** — `PRModel.refreshDiff()`: In the `.completed(let snapshot)` handler, add:
```swift
reviewComments = snapshot.reviewComments
```

**Step D** — `PRModel.refreshPRData()`: Remove the `reloadReviewComments()` call.

Note: `LoadPRDetailUseCase` also calls `parseOutput()` (for its snapshot field) and then calls `FetchReviewCommentsUseCase` again explicitly. After this change `reviewComments` will be computed twice inside `LoadPRDetailUseCase` — both are cheap disk reads and the explicit call remains authoritative for `detail.reviewComments`.

**Files**: `SyncSnapshot.swift`, `FetchPRUseCase.swift`, `PRModel.swift`

---

## - [x] Phase 3: Await comments at `runAnalysis()` end via use case

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: `runAnalysis()` is already `async`, so `reloadReviewComments()` (which wrapped `FetchReviewCommentsUseCase` in a fire-and-forget `Task`) is replaced with a direct `await`. Comments now update before `runAnalysis()` returns, eliminating the race condition. `PRModel` calls the use case, not storage services directly.

**Skills to read**: `ai-dev-tools-architecture`

**Architectural principle**: `PRModel` never calls storage services directly (`PRDiscoveryService`, etc.). It always goes through use cases, which abstract whether data comes from cache or network. The use case is the client-facing contract; how it satisfies the request is an implementation detail.

The current `reloadReviewComments()` at call site 5 fires a **fire-and-forget `Task`**, so `runAnalysis()` returns before comments are updated. The fix is to await the use case directly in the `async` context of `runAnalysis()`.

**Change** in `PRModel.swift` — in `runAnalysis()`, replace:
```swift
reloadReviewComments()
```
with:
```swift
reviewComments = await FetchReviewCommentsUseCase(config: config)
    .execute(prNumber: prNumber, minScore: 1, commitHash: currentCommitHash)
```

`runAnalysis()` is already `async`, so no `Task` wrapper is needed. The use case handles all caching and reconciliation internally — `PRModel` just requests the data.

**Files**: `PRModel.swift`

---

## - [x] Phase 4: Add `reviewComments` to `TaskProgress.completed`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: `TaskProgress.completed` now carries `[ReviewComment]` alongside `RuleOutcome`. Both `AnalyzeSingleTaskUseCase` and `AnalyzeUseCase` (cached-replay path) call `FetchReviewCommentsUseCase` before yielding `.completed`, so `PRModel.handleTaskEvent()` assigns `reviewComments` directly from the event rather than spawning a separate `reloadReviewComments()` task. The App layer reads from use case output; no storage services called directly from `PRModel`.

**Skills to read**: `ai-dev-tools-architecture`

`TaskProgress.completed` currently carries only `result: RuleOutcome`. Same root cause as all other sites — the use case doesn't return `[ReviewComment]`, so `PRModel` reloads from disk after each task.

`TaskProgress.completed` is emitted in two places:

- **`AnalyzeSingleTaskUseCase.swift:96`** — fresh evaluations. The result is written to disk at lines 86–94 immediately before this yield. `config` is a stored property, `prNumber` and `resolvedCommit` are locals already in scope.
- **`AnalyzeUseCase.swift:224`** — cached results replayed at analysis start. `config` is a stored property; `prNumber` and resolved `commitHash` are in scope at that point.

**Step A** — `TaskProgress.swift`: Add `reviewComments` to the completed case:
```swift
case completed(result: RuleOutcome, reviewComments: [ReviewComment])
```

**Step B** — `AnalyzeSingleTaskUseCase.swift`, before `continuation.yield(.completed(...))` at line 96:
```swift
let updatedComments = await FetchReviewCommentsUseCase(config: config)
    .execute(prNumber: prNumber, minScore: 1, commitHash: resolvedCommit)
continuation.yield(.completed(result: result, reviewComments: updatedComments))
```

**Step B2** — `AnalyzeUseCase.swift`, before `continuation.yield(.taskEvent(task:event:.completed(...)))` at line 224:
```swift
let updatedComments = await FetchReviewCommentsUseCase(config: config)
    .execute(prNumber: prNumber, minScore: 1, commitHash: commitHash)
continuation.yield(.taskEvent(task: task, event: .completed(result: result, reviewComments: updatedComments)))
```

**Step C** — `PRModel.handleTaskEvent()`: assign directly, remove `reloadReviewComments()`:
```swift
case .completed(let result, let updatedComments):
    evaluations[task.taskId]?.outcome = result
    inProgressAnalysis?.appendResult(result, prNumber: prNumber)
    reviewComments = updatedComments
```

**Files**: `TaskProgress.swift`, `AnalyzeSingleTaskUseCase.swift`, `AnalyzeUseCase.swift`, `PRModel.swift`

---

## - [ ] Phase 5: Remove reload from `postNotConfirmed` handler

**Skills to read**: `ai-dev-tools-architecture`

**Skills to read**: `ai-dev-tools-architecture`

`PostSingleCommentUseCase` already made 3 network fetches inside `fetchConfirmed()` before throwing `postNotConfirmed`. Adding another disk or network read achieves nothing — `reviewComments` is already in the best-known state, which is the same pre-post cache that any reload would return.

The correct behavior: log the warning and do nothing. The comment is on GitHub. When the user hits the refresh button later, the `updatedAt` check will detect the change and pull fresh data.

**Change** in `PRModel.swift` — in `submitSingleComment`, remove `reloadReviewComments()` from the `postNotConfirmed` catch. Leave only the log:
```swift
} catch PostSingleCommentError.postNotConfirmed {
    logger.warning("submitSingleComment: postNotConfirmed", metadata: ["prNumber": "\(prNumber)"])
}
```

**Files**: `PRModel.swift`

---

## - [ ] Phase 6: Delete `reloadReviewComments()` and validate

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`

**Build**
- `swift build` from `AIDevToolsKit/` — must be clean

**Manual smoke tests**
1. **Initial PR load**: Open a PR with existing posted comments. Comments panel should populate in one pass with no visible second update.
2. **Refresh button**: With a PR open, click refresh. Comment state should update to current GitHub state after the refresh completes.
3. **Run analysis**: Run a full analysis on a PR. After completion, the comments panel should reflect the new violations without a separate reload flash.
4. **Post a comment (happy path)**: Post a comment via the inline Submit button. UI should update to show the comment as posted.
5. **Post a comment (postNotConfirmed)**: If GitHub is slow to reflect the post, the fallback `reloadReviewComments()` (site 4) should still fire correctly — no regression.

See Phase 7.

---

## - [ ] Phase 7: Enforce on all changed files

**Skills to run**: `ai-dev-tools-enforce`

Run `ai-dev-tools-enforce` on every file modified across phases 1–6:

- `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Models/PRModel.swift`
- `AIDevToolsKit/Sources/Features/PRReviewFeature/models/TaskProgress.swift`
- `AIDevToolsKit/Sources/Features/PRReviewFeature/usecases/AnalyzeSingleTaskUseCase.swift`
- `AIDevToolsKit/Sources/Features/PRReviewFeature/usecases/AnalyzeUseCase.swift`
- `AIDevToolsKit/Sources/Features/PRReviewFeature/usecases/FetchPRUseCase.swift`
- `AIDevToolsKit/Sources/Features/PRReviewFeature/usecases/SyncSnapshot.swift`

---

## - [ ] Phase 8: CLI verification against AIDevToolsDemo

Validate end-to-end that review comments populate correctly without `reloadReviewComments()` by running the PRRadar CLI against the AIDevToolsDemo playground repo (`/Users/bill/Developer/personal/AIDevToolsDemo`).

**Setup**
- Confirm a PRRadar config exists for AIDevToolsDemo in `~/Library/Application Support/PRRadar/settings.json`. The existing `test-repo` config points to a non-existent path and can be updated to target AIDevToolsDemo (gestrich account, `code-review-rules/` rules path, `main` base branch).
- PR #12 (`test/pr-radar-violations`, "Update module A and B content") is open with known violations — use it. Create a new PR in AIDevToolsDemo if a fresh slate is needed.

**Commands** (from `PRRadarLibrary/`):
```bash
cd /Users/bill/Developer/personal/AIDevTools/PRRadarLibrary
swift build

# Full pipeline: fetch diff, prepare, evaluate, report
swift run PRRadarMacCLI analyze 12 --config <config-name>

# Confirm review comments are present after the run
swift run PRRadarMacCLI status 12 --config <config-name>
```

**Pass criteria**
- Pipeline completes without errors
- `status` output shows review comments populated after the analyze run
- `reloadReviewComments` does not appear anywhere in `~/Library/Logs/AIDevTools/aidevtools.log` during the run (confirming the method is gone)
