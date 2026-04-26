# PR Radar Runs Tab

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — read before placing any new type |
| `ai-dev-tools-build-quality` | Compiler warnings, dead code, debug artifacts |
| `ai-dev-tools-code-organization` | Swift file and type organization conventions |
| `ai-dev-tools-code-quality` | Force unwraps, raw strings, duplicated logic |
| `ai-dev-tools-composition-root` | How Mac app and CLI wire services — required before adding new models or services |
| `ai-dev-tools-enforce` | Run after every phase to catch violations before moving on |
| `ai-dev-tools-swift-testing` | Test file conventions |
| `swift-app-architecture:swift-architecture` | Full 4-layer overview, data flow patterns, use case → CLI → Mac Model (MV) pattern |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View conventions for this project |

## Background

PRRadar's `run-all` command processes all PRs matching a filter and writes results to disk:
- `{resolvedOutputDir}/runs/{timestamp}-{rules}.json` — a `RunManifest` capturing batch-level outcome (which PRs ran, status, failure reasons, timestamps, config/rules used)
- `{resolvedOutputDir}/{prNumber}/analysis/{commitHash}/report/summary.json` — per-PR `ReportSummary` (violations, cost, duration, AI tasks)

The CLI already has `pr-radar run-history` for viewing this data. The Mac app has no equivalent.

Currently, `run-all` from the Mac app opens `AnalyzeAllProgressView` (a modal) for live progress, driven by `AllPRsModel.analyzeAllState`. This modal will be retired in favour of the new Runs tab.

### CLI parity requirement

All functionality in the Runs tab must be accessible via CLI using the **same use cases and services** as the Mac app. No logic lives exclusively in the Mac model. The shared layer mapping is:

| Functionality | Shared layer | CLI command | Mac model |
|---|---|---|---|
| Trigger + stream run-all | `RunAllUseCase` (exists) | `pr-radar run-all` (exists) | `RunsModel` (Phase 4) |
| Load run history | `RunHistoryService` (Phase 1) | `pr-radar run-history` (Phase 2 refactor) | `RunsModel` (Phase 4) |

No new CLI commands are needed — the existing commands already cover both operations. Phases 1 and 2 ensure the CLI consumes the shared service rather than inline logic.

### Cost visibility

Total cost is displayed at every level:
- **Run list row**: total cost summed across all PRs in that run (`prEntries.compactMap(\.summary).map(\.totalCostUsd).reduce(0, +)`)
- **Run detail pane**: per-PR cost in the breakdown table
- The `run-history` CLI command already shows the same totals

### Agreed design decisions (from planning session)

1. **Tab strip** on the left sidebar — "PRs" tab (existing) | "Runs" tab (new)
2. **Runs tab shows live + historical** — in-progress run appears at top; completed runs loaded from `{resolvedOutputDir}/runs/`
3. **`AnalyzeAllProgressView` modal retired** — logs appear in the Runs tab detail pane instead
4. **Detail pane is mode-switched**: logs while running → PR breakdown table when complete
5. **Cross-tab PR navigation** — clicking a PR row in the breakdown switches to the PRs tab and selects that PR
6. **`run-all` button moves to Runs tab toolbar** — removed from PRs tab
7. **New `RunsModel`** — `AllPRsModel.analyzeAllState` and its `analyzeAll()` method move here
8. **Scoped to selected repo** — Runs tab shows history for the currently active `PRRadarRepoConfig` only

### Architecture pattern to follow

```
RunHistoryService (Services layer)
    ↓
PRRadarRunHistoryCommand (CLI — refactored to use service)
    ↓
RunsModel @Observable (Mac Apps layer)
    ↓
RunsListView / RunDetailView (Mac Apps layer)
```

---

## - [ ] Phase 1: Extract `RunHistoryService`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`, `swift-app-architecture:swift-architecture`

Extract the manifest-loading and summary-loading logic from `PRRadarRunHistoryCommand` into a new `RunHistoryService` in the Services layer so it can be shared by both the CLI and the Mac app model.

### What to create

**`AIDevToolsKit/Sources/Services/PRRadarCLIService/RunHistoryService.swift`** (or whichever Services module is most appropriate — check `ai-dev-tools-composition-root` for guidance):

```swift
public struct RunHistoryService {
    public static func loadRuns(outputDir: String, limit: Int = 50) throws -> [RunHistoryEntry]
    public static func loadReportSummary(outputDir: String, prNumber: Int) -> ReportSummary?
}

public struct RunHistoryEntry: Sendable {
    public let manifest: RunManifest
    public let prEntries: [RunAllPREntry]   // RunAllPREntry = PRManifestEntry + ReportSummary?
}
```

- `loadRuns` reads `{outputDir}/runs/*.json`, decodes each `RunManifest`, and for each PR entry calls `loadReportSummary` to produce a `RunAllPREntry`
- `loadReportSummary` is the existing logic from `PRRadarRunHistoryCommand` (metadata phase_result.json → commitHash → report/summary.json, with fallback directory scan) — move it here verbatim
- Returns runs sorted newest-first

### Notes
- This is a pure disk-read utility, not a streaming use case — a static struct with functions is appropriate
- Use `resolvedOutputDir` throughout (never the raw `outputDir` string)

---

## - [ ] Phase 2: Refactor `PRRadarRunHistoryCommand`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

Replace the inline loading logic in `PRRadarRunHistoryCommand` with `RunHistoryService`. The command's display output must remain identical.

**File**: `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarRunHistoryCommand.swift`

- Replace `loadReportSummary(outputDir:prNumber:)` private method with a call to `RunHistoryService.loadReportSummary`
- Replace the manifest-scanning loop with `RunHistoryService.loadRuns(outputDir: prRadarConfig.resolvedOutputDir, limit: limit)`
- Ensure `resolvedOutputDir` is used everywhere (the `outputDir` vs `resolvedOutputDir` bug was already fixed in a prior commit — confirm it stays fixed)
- Build and verify `pr-radar run-history` still produces correct output

---

## - [ ] Phase 3: Shared Navigation State

**Skills to read**: `swift-app-architecture:swift-swiftui`, `ai-dev-tools-composition-root`

Add a small shared navigation model at the Mac Apps layer that both the PRs tab and Runs tab observe. This enables cross-tab PR selection without coupling `RunsModel` directly to `AllPRsModel`.

**File**: `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/PRRadarNavigationModel.swift`

```swift
@Observable @MainActor
final class PRRadarNavigationModel {
    var selectedTab: PRRadarTab = .prs
    var selectedPRNumber: Int? = nil
}

enum PRRadarTab {
    case prs
    case runs
}
```

- Instantiate in the composition root / app entry point (read `ai-dev-tools-composition-root` for where)
- Pass into `PRRadarContentView` via `@Environment` or direct injection — follow existing patterns for how `AllPRsModel` is passed
- When `RunsModel` signals "navigate to PR #N", it writes `navigationModel.selectedTab = .prs` and `navigationModel.selectedPRNumber = prNumber`
- `PRRadarContentView` observes `selectedPRNumber` and updates its `selectedPR: PRModel?` accordingly

---

## - [ ] Phase 4: `RunsModel`

**Skills to read**: `swift-app-architecture:swift-swiftui`, `ai-dev-tools-composition-root`, `ai-dev-tools-architecture`

Create the `@Observable` model that owns all runs-related state. This replaces `AllPRsModel.analyzeAllState`.

**File**: `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/RunsModel.swift`

### State

```swift
@Observable @MainActor
final class RunsModel {
    // Historical
    private(set) var runs: [RunHistoryEntry] = []
    private(set) var loadState: LoadState = .idle

    // Live run
    private(set) var liveRunState: LiveRunState = .idle

    enum LoadState { case idle, loading, loaded, failed(String) }

    enum LiveRunState {
        case idle
        case running(logs: String, current: Int, total: Int)
        case completed(RunHistoryEntry)
        case failed(String)
    }
}
```

### Methods

- `func loadHistory(config: PRRadarRepoConfig) async` — calls `RunHistoryService.loadRuns(outputDir: config.resolvedOutputDir)` and populates `runs`
- `func runAll(config: PRRadarRepoConfig, filter: PRFilter, rulesDir: String, rulesPathName: String?) async` — consumes `RunAllUseCase` stream, updating `liveRunState` as events arrive; appends the completed run to `runs` on `.completed`; on `.failed` sets `liveRunState = .failed`

### Migration from `AllPRsModel`

- Remove `analyzeAllState: AnalyzeAllState`, `analyzeAll(filter:ruleFilePaths:)`, `dismissAnalyzeAllState()`, and `analyzeAllLogs` from `AllPRsModel`
- The `AnalyzeAllState` enum can be deleted once `RunsModel.LiveRunState` covers the same cases

### Composition root wiring

Read `ai-dev-tools-composition-root` to understand exactly where to instantiate `RunsModel` and how to pass it alongside `AllPRsModel` into the view hierarchy.

---

## - [ ] Phase 5: Mac Views

**Skills to read**: `swift-app-architecture:swift-swiftui`, `ai-dev-tools-code-organization`

### 5a — Tab strip in sidebar

Modify `PRRadarContentView` to show a tab strip at the top of the left sidebar:

```
[ PRs ]  [ Runs ]
```

- Controlled by `PRRadarNavigationModel.selectedTab`
- When `.prs` is selected: existing PR list renders (no change)
- When `.runs` is selected: `RunsListView` renders in place of the PR list

### 5b — `RunsListView` + `RunListRow`

**File**: `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/RunsListView.swift`
**File**: `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/RunListRow.swift`

`RunsListView`:
- Lists all `RunHistoryEntry` items from `RunsModel.runs`
- Live run (`RunsModel.liveRunState`) appears at the top when active, shown as an in-progress row
- Selecting a row updates a `@State var selectedRun: RunHistoryEntry?`

`RunListRow` displays per row:
- Start timestamp
- Config name + rules path name
- PR counts: `N PRs (X ✓  Y ✗)`
- Total violations (summed from `prEntries.compactMap(\.summary).map(\.violationsFound).reduce(0, +)`)
- Total cost (`$0.0000`)

### 5c — Runs tab toolbar

Move the "Analyze All" button from the PRs tab toolbar to the Runs tab toolbar. Wire it to `RunsModel.runAll(...)` instead of `AllPRsModel.analyzeAll(...)`. Remove it from the PRs tab entirely.

### 5d — `RunDetailView`

**File**: `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/RunDetailView.swift`

Mode-switched based on whether the selected run is complete:

**While running** (live run selected):
- Scrolling `Text` or `ScrollView` showing `RunsModel.liveRunState.logs`
- Progress indicator: "Processing PR N of M"
- Auto-scrolls to bottom as logs append

**When complete** (historical run selected):
- PR breakdown table sorted by duration (longest first)
- Each row: status icon (✓/✗), PR number, duration, AI tasks, violations, cost, title (truncated), failure reason if failed
- Tapping/clicking a row calls `navigationModel.selectedTab = .prs` and `navigationModel.selectedPRNumber = entry.prNumber`

### 5e — Retire `AnalyzeAllProgressView`

Delete `Sources/Apps/AIDevToolsKitMac/PRRadar/Views/AnalyzeAllProgressView.swift`.

Remove all references:
- `@State private var showAnalyzeAllProgress` in `PRRadarContentView`
- `.sheet(isPresented: $showAnalyzeAllProgress)` block
- `model.analyzeAllState.isRunning` checks in toolbar

---

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-build-quality`

### Automated

1. Run `swift build` in `AIDevToolsKit/` — zero errors, no new warnings
2. Run `ai-dev-tools-enforce` on all files changed during this plan
3. Run `pr-radar run-history` CLI command against a real config directory — confirm output is identical to before Phase 2

### Manual checks

1. PRs tab — PR list loads, individual PR analysis works, `run-all` button is gone from toolbar
2. Runs tab — historical runs load for the selected repo, rows show correct timestamps/counts/cost
3. Trigger `run-all` from Runs tab — live row appears at top, logs stream in detail pane, row updates to complete state with PR breakdown when done
4. Click a PR row in the breakdown — PRs tab activates and that PR is selected in the list
5. Switch repos — Runs tab refreshes to show history for the newly selected repo
