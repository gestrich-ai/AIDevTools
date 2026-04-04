## Relevant Skills

| Skill | Description |
|-------|-------------|
| `configuration-architecture` | Guide for wiring new config through the app layers |
| `logging` | Add logging to new discovery and execution paths |
| `swift-app-architecture:swift-architecture` | 4-layer architecture — new feature spans SDK, Service, Feature, and Apps layers |

## Background

The Maintenance Feature is a new AI-driven system for continuously maintaining a codebase. Unlike Claude Chain (which has a finite, user-authored list of tasks that are marked done), maintenance tasks are **ongoing**: a task runs against one or more target files, records the file hashes when it last ran, and is re-run only when those files change.

Key design principles:

- **Skip if unchanged**: A task is skippable when every file's `latestHash == lastRunHash`. If `lastRunHash` is absent, the task has never run and must execute.
- **Discovery is separate from execution**: A daily discovery job scans the repo and updates `execution.json`. It never runs tasks — it only updates which files exist and their current hashes.
- **Async-safe tracking**: `execution.json` is written atomically. Async executors read it independently — they do not also run discovery.
- **Multi-file task groups**: A task can target one or more files. If any file in the group has changed, the whole task re-runs.
- **PR output**: Each task execution results in a GitHub PR with the AI's changes.
- **Branch naming**: `maintenance-<task-name>-<hash>` where `<hash>` is an 8-char SHA-256 of the sorted file paths joined by `|`. Mirrors the ClaudeChain pattern (`claude-chain-<project>-<hash>`).
- **`lastRunHash` recorded post-commit**: After the AI edits the target file(s) and commits them to the feature branch, record the blob SHA of each file *from that branch commit* — not the pre-run base branch SHA. When the PR merges cleanly, the base branch ends up with identical content and therefore the same blob SHA, so discovery will not mark the task stale again.
- **Reuse PipelineService**: Task execution pipelines are built using the existing `PipelineService` and `PipelineSDK`.

### File Layout Per Maintenance Task

Modeled after ClaudeChain's layout (`spec.md` + `config.yaml`). Each maintenance task lives in a directory with four files:

```
maintenance/<task-name>/
  config.yaml       # Execution settings (maxOpenPRs, etc.) — mirrors ClaudeChain's config.yaml
  discovery.md      # Free-form AI prompt describing how to find target files
  execution.json    # Tracked state: all file paths + their hashes (written by discovery, read by executor)
  spec.md           # Free-form AI prompt describing what maintenance to perform on each file
```

### `execution.json` Schema

```json
{
  "tasks": [
    {
      "files": [
        {
          "lastRunHash": "<git-blob-sha-at-last-run>",
          "path": "Sources/Foo.swift"
        }
      ],
      "lastRunAt": "2026-04-03T12:00:00Z"
    },
    {
      "files": [
        {
          "lastRunHash": null,
          "path": "Sources/Bar.swift"
        },
        {
          "lastRunHash": null,
          "path": "Sources/Baz.swift"
        }
      ],
      "lastRunAt": null
    }
  ]
}
```

- `lastRunHash` (per file) — the **git blob SHA of that specific file** recorded from the feature branch after the AI's commits (not the pre-run base branch SHA). `null` if never run. This is the per-file content hash (`git rev-parse HEAD:<path>`), not the repo's commit SHA.
- `lastRunAt` (per task) — ISO-8601 timestamp of when the task last executed successfully. `null` if never run. Used to determine round-robin position: the executor picks the next task after the most recently run one in the sorted list.
- The current blob SHA is **not stored** — computed at runtime via `git rev-parse HEAD:<path>` only when the executor is about to run a task
- A task needs to run when `lastRunHash == null` OR any file's current blob SHA differs from `lastRunHash`
- No `status`, `key`, or `taskVersion` fields

### `config.yaml` Schema

```yaml
maxOpenPRs: 1
```

---

## - [ ] Phase 1: Define SDK models

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new `MaintenanceSDK` target in `Package.swift` (alphabetically placed). Define the core value types:

**`MaintenanceFileEntry`** — one file within a task group:
```swift
public struct MaintenanceFileEntry: Codable, Sendable {
    public let path: String
    public var lastRunHash: String?   // git blob SHA of this file when last run (git rev-parse HEAD:<path>), not the repo commit SHA. nil = never run.
}
```

**`MaintenanceTaskEntry`** — one task (group of files):
```swift
public struct MaintenanceTaskEntry: Codable, Sendable {
    public var files: [MaintenanceFileEntry]
    public var lastRunAt: Date?   // nil = never run; used for round-robin selection

    // currentHashes: computed at runtime by fetching git blob SHAs for each path
    public func needsRun(currentHashes: [String: String]) -> Bool {
        files.contains { file in
            file.lastRunHash == nil || file.lastRunHash != currentHashes[file.path]
        }
    }

    // Sort key: sort file paths within the task, join with "|"
    public var sortKey: String {
        files.map(\.path).sorted().joined(separator: "|")
    }
}
```

**`MaintenanceExecutionState`** — top-level `execution.json` wrapper:
```swift
public struct MaintenanceExecutionState: Codable, Sendable {
    public var tasks: [MaintenanceTaskEntry]
}
```
Includes `load(from: URL)` and `save(to: URL)` helpers using `.atomic` write and ISO-8601 date encoding.

**`MaintenanceConfig`** — parsed from `config.yaml`:
```swift
public struct MaintenanceConfig: Sendable {
    public let maxOpenPRs: Int     // default: 1
}
```
Parsed via `Yams` (already a dependency).

All types: `Codable`, `Sendable`, `public`.

Files:
- `Sources/SDKs/MaintenanceSDK/MaintenanceConfig.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceExecutionState.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceFileEntry.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTaskEntry.swift`

---

## - [ ] Phase 2: Discovery Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

Create a `MaintenanceService` target. The discovery service reads `discovery.md`, invokes Claude CLI to identify target file groups, diffs them against the current `execution.json`, and writes the updated state. It does **not** execute tasks.

```swift
func discover(discoveryMD: String, config: MaintenanceConfig, repoPath: String, executionStateURL: URL) async throws -> MaintenanceExecutionState
```

Steps:
1. Load existing `MaintenanceExecutionState` from `executionStateURL` (or start empty).
2. Invoke Claude CLI with `discovery.md` as the prompt, asking it to return a JSON array of file groups (each group is an array of relative file paths).
3. For each discovered group:
   - **New**: add a `MaintenanceTaskEntry` with `lastRunHash: nil` and `latestHash` fetched from git.
   - **Obsolete** (no longer returned by discovery): remove entry.
   - **Existing**: update `latestHash` for each file from git (do not touch `lastRunHash`).
4. Write updated state atomically to `executionStateURL`.

Add `Logger(label: "MaintenanceDiscoveryService")` at each step.

Files:
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryService.swift`
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryServiceProtocol.swift`

---

## - [ ] Phase 3: Execution Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

`MaintenanceExecutionService` picks the first task where `needsRun == true`, runs it via `PipelineService`, and updates `execution.json` on completion.

```swift
func executeNext(specMD: String, config: MaintenanceConfig, repoPath: String, executionStateURL: URL) async throws -> MaintenanceExecutionResult
```

Steps:
1. Load `MaintenanceExecutionState`. Sort tasks lexicographically by `sortKey`. Find the task with the most recent `lastRunAt` — that is the last executed position. Starting from the task immediately after it in sorted order (wrapping around), find the first task where `needsRun == true` by fetching current blob SHAs. Tasks with `lastRunAt == nil` are treated as oldest (run first). If no task needs to run, return `.noWork`.
2. Verify all files in the selected task still exist on disk. If any are missing (deleted since discovery ran), skip the task and log a warning — do not error.
3. Check open PR count against `config.maxOpenPRs` (same pattern as ClaudeChain's `AssigneeService.checkCapacity`). Count open PRs with the maintenance label. If at or above the limit, return `.atCapacity`. Also check if this specific task's branch already has an open PR — if so, skip it and advance to the next eligible task.
4. Build pipeline:
   - AI step: `spec.md` prompt with the task's file paths appended
   - `PRStep` with `maxOpenPRs` from config
4. Execute via `PipelineRunner`.
5. On success: fetch the git blob SHA for each file **from the feature branch after the AI's commits** (not the base branch). Set `lastRunHash` to those SHAs, set `lastRunAt` to now, and write state atomically. This ensures the stored hash matches what lands on the base branch after the PR merges cleanly.
6. On failure: leave state unchanged (will retry next run). Log error.

```swift
enum MaintenanceExecutionResult: Sendable {
    case atCapacity(openCount: Int, maxOpen: Int)
    case completed(prURL: String)
    case failed(error: any Error & Sendable)
    case noWork
}
```

If a task's branch already has an open PR, the executor skips it and tries the next candidate. If *all* pending tasks have open PRs, returns `.atCapacity`. If the base branch changes while a PR is open, no action is needed — the next discovery run will update `lastRunHash` values and re-queue the task naturally.

Files:
- `Sources/Services/MaintenanceService/MaintenanceExecutionResult.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionService.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionServiceProtocol.swift`

---

## - [ ] Phase 4: MaintenanceFeature use cases

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a `MaintenanceFeature` target with two use cases. Each resolves its inputs from the task directory path (e.g. `maintenance/clean-service-layer/`):

**`RunMaintenanceDiscoveryUseCase`**
- Reads `discovery.md` and `config.yaml` from the task directory
- Derives `execution.json` URL from the same directory
- Calls `MaintenanceDiscoveryService.discover(...)`
- Returns updated `MaintenanceExecutionState`

**`RunMaintenanceTaskUseCase`**
- Reads `spec.md` and `config.yaml` from the task directory
- Derives `execution.json` URL from the same directory
- Calls `MaintenanceExecutionService.executeNext(...)`
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
Runs discovery. Prints: N added, N removed, N updated, N pending.

**`maintenance run`**
```
swift run ai-dev-tools-kit maintenance run --task <path-to-task-dir> --repo <repo-path>
```
Executes next pending task. Prints PR URL or "no work".

Files:
- `Sources/Apps/AIDevToolsKitCLI/MaintenanceCommand.swift`

---

## - [ ] Phase 6: Validation

**Skills to read**: `logging`

**Unit tests** — `MaintenanceSDKTests`:
- `MaintenanceTaskEntryTests`: verify `needsRun` is true when any `lastRunHash` is nil or differs from `latestHash`, false when all match.
- `MaintenanceExecutionStateTests`: round-trip `Codable` encoding, verify atomic save/load.

**CLI smoke test**:
```bash
# Create a task directory
mkdir -p /tmp/test-maintenance
echo "Find all Swift files in Sources/Services/ and return them as single-file groups." > /tmp/test-maintenance/discovery.md
echo "Review this file for service layer convention compliance." > /tmp/test-maintenance/spec.md
echo "maxOpenPRs: 1" > /tmp/test-maintenance/config.yaml

swift run ai-dev-tools-kit maintenance discover --task /tmp/test-maintenance --repo <some-test-repo>
# Verify execution.json created with lastRunHash: null entries

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <some-test-repo>
# Verify PR created, lastRunHash updated to match latestHash

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <some-test-repo>
# Verify "no work" (all hashes match)
```

**Log verification**:
```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label | startswith("Maintenance"))'
```
