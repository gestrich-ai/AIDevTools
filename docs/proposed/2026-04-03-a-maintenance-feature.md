## Open Questions (resolve before implementation)

1. **How deeply does ClaudeChain get refactored?** Option A is chosen (refactor ClaudeChain to use the new abstractions so Maintenance and ClaudeChain share the same pipeline infrastructure). The question is the refactoring depth: does `RunChainTaskUseCase` get rewritten to use `TaskSource`/`InstructionSource` protocols, or do we just add protocol conformances alongside the existing code with minimal disruption?

2. **Where do the new abstractions live?** `TaskSource` already partially exists in `PipelineSDK`. Should `InstructionSource` also live in `PipelineSDK`? Or does the refactored `TaskSource` (extended to include instruction building) belong in a new shared layer? Consider that `InstructionSource` for Maintenance needs to combine `spec.md` content with a file path — it may need the current task as input.

3. **`InstructionSource` protocol shape**: Does it look like `func instructions(for task: MaintenanceTask) async throws -> String`? Or is it task-agnostic: `func instructions() async throws -> String` with the file path injected at construction time (a new instance per task)?

---

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `configuration-architecture` | Guide for wiring new config through the app layers |
| `logging` | Add logging to new discovery and execution paths |
| `swift-app-architecture:swift-architecture` | 4-layer architecture — new feature spans SDK, Service, Feature, and Apps layers |

## Background

The Maintenance Feature is a new AI-driven system for continuously maintaining a codebase. Unlike Claude Chain (which has a finite, user-authored list of tasks that are marked done), maintenance tasks are **ongoing**: a task runs against a file or directory path, records the git hash when it last ran, and is re-run only when that path changes.

### Core Architectural Insight

ClaudeChain's execution pipeline has two concerns that should be abstracted:

1. **Task source** — "what runs next, and how to mark it done"
2. **Instruction source** — "what to tell the AI"

Currently both are tightly coupled to `spec.md` in ClaudeChain. Abstracting them allows Maintenance to plug in its own implementations while sharing the same pipeline infrastructure.

| Abstraction | ClaudeChain impl | Maintenance impl |
|---|---|---|
| `TaskSource` | Markdown checklist in `spec.md` — finds first `[ ]`, marks `[x]` on complete | `state.json` entry — finds first stale path (null or mismatched hash), marks complete by updating hash + date |
| `InstructionSource` | Top of `spec.md` (existing behavior, extracted as protocol) | `spec.md` (instructions only, no checklist) combined with the current task's file path |

**Option A is chosen**: ClaudeChain will be refactored to use these abstractions. Maintenance then implements the same protocols. This is a prerequisite before Maintenance is built. See Open Questions above for the refactoring depth decisions.

### Key Design Principles

- **`lastRunHash` recorded post-commit**: After the AI edits the path and commits to the feature branch, record the git hash of the path *from that branch commit*. When the PR merges cleanly, the base branch ends up with the same hash — discovery will not mark the task stale again.
- **Discovery is separate from execution**: A discovery job expands a glob, diffs against state.json, and adds/removes/updates entries. It never runs tasks.
- **Single path per task**: Each state.json entry is one file or directory path. No multi-file groups in V1.
- **Top-to-bottom execution (V1)**: Execution picks the first stale task from state.json in key-sorted order. Lexicographic starvation is acceptable for V1.
- **PR output**: Each task execution results in a GitHub PR with the AI's changes.
- **Branch naming**: `maintenance-<task-name>-<hash>` where `<hash>` is an 8-char SHA-256 of the path string. Mirrors ClaudeChain's `claude-chain-<project>-<hash>` pattern.
- **Reuse PipelineService**: Task execution pipelines use the existing `PipelineService` and `PipelineSDK`.

### File Layout Per Maintenance Task

```
maintenance/<task-name>/
  config.yaml    # maxOpenPRs, discovery glob pattern
  spec.md        # AI instructions ONLY — no checklist, no file paths
  state.json     # task source: path → {lastRunHash, lastRunAt}
```

### `spec.md` Format

Free-form AI instructions only. No checklist. This is the `InstructionSource`. The file path from the current task is appended at execution time before being sent to the AI.

```markdown
Review this file for service layer convention compliance. Remove dead code,
fix naming, and ensure protocol conformance is correct. If the file already
conforms well, make no changes and explain why in the PR description.
```

### `state.json` Schema

Machine-managed. Keys are path strings sorted alphabetically. Written by discovery and updated by the executor.

```json
{
  "Sources/Services/BarService.swift": {
    "lastRunAt": "2026-04-03T12:00:00Z",
    "lastRunHash": "abc12345"
  },
  "Sources/Services/FooService.swift": {
    "lastRunAt": null,
    "lastRunHash": null
  }
}
```

- `lastRunHash` — git blob SHA (file) or git tree SHA (directory) of the path as it existed on the feature branch **after the AI's commits**, not the pre-run base branch hash. `null` = never run.
- `lastRunAt` — ISO-8601 timestamp of last successful execution. `null` = never run. Informational; ordering is by sorted key in V1.
- The current hash is **not stored** — computed at runtime via `git rev-parse HEAD:<path>`.
- A task is stale when `lastRunHash == null` OR current hash ≠ `lastRunHash`.

### `config.yaml` Schema

```yaml
maxOpenPRs: 1
discovery:
  glob: "Sources/Services/**/*.swift"
```

### Hashing

- **File path**: git blob SHA — `git rev-parse HEAD:<path>`
- **Directory path**: git tree SHA — `git rev-parse HEAD:<dir>` — changes when any file under it is added, modified, or deleted

---

## - [ ] Phase 0: Refactor ClaudeChain to use TaskSource/InstructionSource abstractions

**Skills to read**: `swift-app-architecture:swift-architecture`

**Prerequisite for all other phases.** Extract `TaskSource` and `InstructionSource` as protocols in `PipelineSDK` (location TBD — see Open Questions). Refactor `RunChainTaskUseCase` and related ClaudeChain pipeline code to use them. ClaudeChain behavior must be unchanged after this refactor.

**`TaskSource` protocol** (extends/replaces existing partial protocol):
```swift
public protocol TaskSource: Sendable {
    func nextTask() async throws -> (any PipelineTask)?
    func markComplete(_ task: any PipelineTask) async throws
}
```

**`InstructionSource` protocol** (new):
```swift
public protocol InstructionSource: Sendable {
    func instructions(for task: any PipelineTask) async throws -> String
}
```

ClaudeChain implementations:
- `MarkdownTaskSource` — reads `spec.md` checklist, finds first `[ ]`, marks `[x]`
- `MarkdownInstructionSource` — reads top of `spec.md` (above the checklist) as the prompt

This phase should be validated with ClaudeChain's existing tests before Maintenance is built.

Files to modify:
- `Sources/SDKs/PipelineSDK/TaskSource.swift` (extend/replace existing)
- `Sources/SDKs/PipelineSDK/InstructionSource.swift` (new)
- `Sources/Features/ClaudeChainFeature/...` (refactor to use protocols)

---

## - [ ] Phase 1: Define Maintenance SDK models

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new `MaintenanceSDK` target in `Package.swift` (alphabetically placed).

**`MaintenanceStateEntry`**:
```swift
public struct MaintenanceStateEntry: Codable, Sendable {
    public var lastRunAt: Date?
    public var lastRunHash: String?   // git blob/tree SHA from feature branch post-commit. nil = never run.
}
```

**`MaintenanceState`** — `state.json` wrapper:
```swift
public struct MaintenanceState: Codable, Sendable {
    public var entries: [String: MaintenanceStateEntry]   // key = file/dir path
}
```
Includes `load(from: URL)` and `save(to: URL)` with atomic write and ISO-8601 date encoding. Keys always sorted alphabetically on save.

**`MaintenanceConfig`** — parsed from `config.yaml` via `Yams`:
```swift
public struct MaintenanceConfig: Sendable {
    public let maxOpenPRs: Int        // default: 1
    public let discoveryGlob: String
}
```

**`MaintenanceTaskSource`** — implements `TaskSource` using `state.json`:
- `nextTask()`: load state, sort keys, return first entry where `lastRunHash == nil` OR current hash ≠ `lastRunHash`
- `markComplete(_ task:)`: fetch git hash from feature branch post-commit; update `lastRunHash` and `lastRunAt`; save state

**`MaintenanceInstructionSource`** — implements `InstructionSource`:
- `instructions(for task:)`: read `spec.md` (instructions only); append the task's file path; return combined string

Files:
- `Sources/SDKs/MaintenanceSDK/MaintenanceConfig.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceInstructionSource.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceState.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceStateEntry.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTaskSource.swift`

---

## - [ ] Phase 2: Discovery Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

Create a `MaintenanceService` target. Discovery expands the glob, diffs against state.json, and updates it. Does **not** execute tasks and does **not** touch spec.md (spec.md is human-authored instructions only).

```swift
func discover(config: MaintenanceConfig, repoPath: String, taskDirectoryURL: URL) async throws -> DiscoverySummary
```

Steps:
1. Load existing `MaintenanceState` from `taskDirectoryURL/state.json` (or start empty).
2. Expand `config.discoveryGlob` against the repo using `FileManager`.
3. Diff against existing entries:
   - **New path**: add entry with `lastRunHash: nil`, `lastRunAt: nil`.
   - **Obsolete path** (no longer matched by glob): remove entry.
   - **Existing path**: no change to stored fields — staleness is evaluated at execution time.
4. Save updated state.json (keys sorted alphabetically).
5. Return `DiscoverySummary(added:, removed:, total:, pendingCount:)` where `pendingCount` is entries with null or stale hashes.

Add `Logger(label: "MaintenanceDiscoveryService")` at each step.

Files:
- `Sources/Services/MaintenanceService/DiscoverySummary.swift`
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryService.swift`
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryServiceProtocol.swift`

---

## - [ ] Phase 3: Execution Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

`MaintenanceExecutionService` uses `MaintenanceTaskSource` and `MaintenanceInstructionSource` to build and run a pipeline.

```swift
func executeNext(config: MaintenanceConfig, repoPath: String, taskDirectoryURL: URL) async throws -> MaintenanceExecutionResult
```

Steps:
1. Instantiate `MaintenanceTaskSource` and `MaintenanceInstructionSource` from task directory.
2. Call `taskSource.nextTask()`. If nil, return `.noWork`.
3. Check open PR count vs `config.maxOpenPRs`. If at or above limit, return `.atCapacity`. Check if this path's branch already has an open PR — if so, skip and try next task.
4. Verify the path still exists on disk (may have been deleted since discovery ran). If missing, skip and log warning.
5. Build pipeline using `MaintenanceTaskSource` + `MaintenanceInstructionSource`.
6. Execute via `PipelineRunner`.
7. On success: call `taskSource.markComplete(task)` — fetches post-commit hash from feature branch, updates state.json.
8. On failure: leave state unchanged. Log error.

Branch name: `maintenance-<task-name>-<8-char-sha256-of-path>`.

```swift
enum MaintenanceExecutionResult: Sendable {
    case atCapacity(openCount: Int, maxOpen: Int)
    case completed(prURL: String)
    case failed(error: any Error & Sendable)
    case noWork
}
```

Files:
- `Sources/Services/MaintenanceService/MaintenanceExecutionResult.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionService.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionServiceProtocol.swift`

---

## - [ ] Phase 4: MaintenanceFeature use cases

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a `MaintenanceFeature` target with two use cases. Each takes a task directory URL and resolves `config.yaml`, `spec.md`, and `state.json` from it.

**`RunMaintenanceDiscoveryUseCase`**
- Reads `config.yaml`; calls `MaintenanceDiscoveryService.discover(...)`
- Returns `DiscoverySummary`

**`RunMaintenanceTaskUseCase`**
- Reads `config.yaml`; calls `MaintenanceExecutionService.executeNext(...)`
- Returns `MaintenanceExecutionResult`

Files:
- `Sources/Features/MaintenanceFeature/RunMaintenanceDiscoveryUseCase.swift`
- `Sources/Features/MaintenanceFeature/RunMaintenanceTaskUseCase.swift`

---

## - [ ] Phase 5: CLI commands

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a `maintenance` subcommand to `ai-dev-tools-kit` (alphabetically in the subcommand list):

**`maintenance discover`**
```
swift run ai-dev-tools-kit maintenance discover --task <path-to-task-dir> --repo <repo-path>
```
Prints: N added, N removed, N total, N pending.

**`maintenance run`**
```
swift run ai-dev-tools-kit maintenance run --task <path-to-task-dir> --repo <repo-path>
```
Prints PR URL, "no work", or capacity message.

Files:
- `Sources/Apps/AIDevToolsKitCLI/MaintenanceCommand.swift`

---

## - [ ] Phase 6: Validation

**Skills to read**: `logging`

**Unit tests** — `MaintenanceSDKTests`:
- `MaintenanceStateTests`: round-trip `Codable` encoding; atomic save/load; keys sorted on save.
- `MaintenanceTaskSourceTests`: `nextTask()` returns nil when all hashes current; returns stale entry when hash differs.

**CLI smoke test**:
```bash
mkdir -p /tmp/test-maintenance
echo "maxOpenPRs: 1\ndiscovery:\n  glob: Sources/Services/**/*.swift" > /tmp/test-maintenance/config.yaml
echo "Review this file for service layer compliance." > /tmp/test-maintenance/spec.md

swift run ai-dev-tools-kit maintenance discover --task /tmp/test-maintenance --repo <repo>
# Verify state.json created with null hashes for all matched paths

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <repo>
# Verify PR created; state.json updated with hash + date for first path

swift run ai-dev-tools-kit maintenance discover --task /tmp/test-maintenance --repo <repo>
# Verify that completed path still shows as up-to-date (hash matches)

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <repo>
# Verify second stale path runs next
```

**Log verification**:
```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label | startswith("Maintenance"))'
```

**ClaudeChain regression** (after Phase 0):
- Run existing ClaudeChain tests to confirm behavior is unchanged after the TaskSource/InstructionSource refactor.
