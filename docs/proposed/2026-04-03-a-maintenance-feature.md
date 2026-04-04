## Relevant Skills

| Skill | Description |
|-------|-------------|
| `configuration-architecture` | Guide for wiring new config through the app layers |
| `logging` | Add logging to new discovery and execution paths |
| `swift-app-architecture:swift-architecture` | 4-layer architecture — new feature spans SDK, Service, Feature, and Apps layers |

## Background

The Maintenance Feature is a new AI-driven system for continuously maintaining a codebase. Unlike Claude Chain (which has a finite, user-authored list of tasks that are marked done), maintenance tasks are **ongoing**: a task runs against a file or directory path, records the git hash when it last ran, and is re-run only when that path changes.

Key design principles:

- **Reuse ClaudeChain's spec.md model**: spec.md has AI instructions at the top and a checklist of paths below. Execution reads it identically to ClaudeChain — first `[ ]` entry wins. Discovery manages the checkbox state.
- **Skip if unchanged**: Discovery checks `[x]` when the path's current git hash matches `lastRunHash`. It unchecks to `[ ]` when stale. Execution marks `[x]` on success (same as ClaudeChain).
- **Discovery is separate from execution**: A discovery job expands a glob, diffs against the current path list, updates spec.md checkboxes and state.json. It never runs tasks.
- **Single path per task**: Each checklist entry is one file or directory path. No multi-file groups — simplicity over flexibility for V1.
- **PR output**: Each task execution results in a GitHub PR with the AI's changes.
- **Branch naming**: `maintenance-<task-name>-<hash>` where `<hash>` is an 8-char SHA-256 of the path string. Mirrors ClaudeChain's `claude-chain-<project>-<hash>` pattern.
- **Reuse PipelineService**: Task execution pipelines are built using the existing `PipelineService` and `PipelineSDK`.
- **`lastRunHash` recorded post-commit**: After the AI edits the path and commits to the feature branch, record the git hash of the path *from that branch commit*. When the PR merges cleanly, the base branch ends up with identical content and the same hash — discovery will not mark the task stale again.

### File Layout Per Maintenance Task

Modeled after ClaudeChain's layout. Each maintenance task lives in a directory with three files:

```
maintenance/<task-name>/
  config.yaml    # Execution settings + discovery glob pattern
  spec.md        # AI instructions at top + checklist of file/directory paths
  state.json     # Machine-managed: path → {lastRunHash, lastRunAt}
```

### `spec.md` Format

Identical to ClaudeChain's spec.md. Free-form AI instructions at the top, followed by a markdown checklist where each item is a file or directory path. Discovery re-sorts entries lexicographically on every run.

```markdown
Review each file for service layer convention compliance. Remove dead code,
fix naming, and ensure protocol conformance is correct.

- [x] Sources/Services/BarService.swift
- [ ] Sources/Services/FooService.swift
```

- `[x]` — up to date (current hash matches `lastRunHash`)
- `[ ]` — needs to run (hash differs, or never run)

### `state.json` Schema

Machine-managed. Keys are path strings sorted alphabetically.

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

- `lastRunHash` — git blob SHA (file) or git tree SHA (directory) of the path as it existed on the feature branch after the AI's commits, not the pre-run base branch hash. `null` = never run.
- `lastRunAt` — ISO-8601 timestamp of last successful execution. `null` = never run. Informational only; ordering is positional in spec.md.
- The current hash is **not stored** — computed at runtime via `git rev-parse HEAD:<path>`.

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

## - [ ] Phase 1: Define SDK models

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new `MaintenanceSDK` target in `Package.swift` (alphabetically placed). Define the core value types:

**`MaintenanceStateEntry`** — state for one path:
```swift
public struct MaintenanceStateEntry: Codable, Sendable {
    public var lastRunAt: Date?
    public var lastRunHash: String?   // git blob/tree SHA from feature branch post-commit. nil = never run.
}
```

**`MaintenanceState`** — top-level `state.json` wrapper:
```swift
public struct MaintenanceState: Codable, Sendable {
    public var entries: [String: MaintenanceStateEntry]   // key = path
}
```
Includes `load(from: URL)` and `save(to: URL)` helpers using `.atomic` write and ISO-8601 date encoding.

**`MaintenanceConfig`** — parsed from `config.yaml`:
```swift
public struct MaintenanceConfig: Sendable {
    public let maxOpenPRs: Int     // default: 1
    public let discoveryGlob: String
}
```
Parsed via `Yams` (already a dependency).

All types: `Codable`, `Sendable`, `public`.

Files:
- `Sources/SDKs/MaintenanceSDK/MaintenanceConfig.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceState.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceStateEntry.swift`

---

## - [ ] Phase 2: Discovery Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

Create a `MaintenanceService` target. The discovery service expands the glob, diffs against the current spec.md, and updates both spec.md and state.json. It does **not** execute tasks.

```swift
func discover(config: MaintenanceConfig, repoPath: String, taskDirectoryURL: URL) async throws -> DiscoverySummary
```

Steps:
1. Load existing spec.md (parse checklist entries) and state.json from `taskDirectoryURL`.
2. Expand `config.discoveryGlob` against the repo using `FileManager`.
3. For each discovered path, compute current git hash (`git rev-parse HEAD:<path>`).
4. Diff against existing spec.md entries:
   - **New path**: add `- [ ]` entry to spec.md; add entry to state.json with null hash/date.
   - **Obsolete path** (no longer matched by glob): remove from spec.md and state.json.
   - **Existing path**: compare current hash to `lastRunHash` in state.json.
     - Different or `lastRunHash == nil` → uncheck: `[x]` → `[ ]`
     - Same → check: `[ ]` → `[x]`
5. Re-sort all spec.md checklist entries lexicographically.
6. Write spec.md and state.json atomically.

Add `Logger(label: "MaintenanceDiscoveryService")` at each step.

Files:
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryService.swift`
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryServiceProtocol.swift`

---

## - [ ] Phase 3: Execution Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

`MaintenanceExecutionService` reads spec.md identically to ClaudeChain — finds the first `[ ]` entry — and runs it via `PipelineService`.

```swift
func executeNext(config: MaintenanceConfig, repoPath: String, taskDirectoryURL: URL) async throws -> MaintenanceExecutionResult
```

Steps:
1. Parse spec.md. Find first `[ ]` entry (top-to-bottom). If none, return `.noWork`.
2. Check open PR count vs `config.maxOpenPRs`. If at or above limit, return `.atCapacity`. Also check if this path's branch already has an open PR — if so, skip it and try the next `[ ]` entry.
3. Verify the path still exists on disk (may have been deleted since discovery ran). If missing, skip and log a warning.
4. Build pipeline:
   - AI step: instructions from top of spec.md + the target path
   - `PRStep` with `maxOpenPRs` from config
5. Execute via `PipelineRunner`.
6. On success:
   - Fetch git hash for the path **from the feature branch after AI commits** (not base branch).
   - Update state.json: set `lastRunHash` and `lastRunAt` for this path.
   - Mark `[ ]` → `[x]` in spec.md (same as ClaudeChain).
7. On failure: leave state unchanged. Log error.

Branch name: `maintenance-<task-name>-<hash>` where `<hash>` is 8-char SHA-256 of the path string.

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
- Reads `config.yaml` from task directory
- Calls `MaintenanceDiscoveryService.discover(...)`
- Returns `DiscoverySummary` (counts of added, removed, updated, pending)

**`RunMaintenanceTaskUseCase`**
- Reads `config.yaml` from task directory
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
Prints: N added, N removed, N updated, N pending.

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
- `MaintenanceStateTests`: round-trip `Codable` encoding; verify atomic save/load.

**CLI smoke test**:
```bash
mkdir -p /tmp/test-maintenance
cat > /tmp/test-maintenance/config.yaml <<EOF
maxOpenPRs: 1
discovery:
  glob: "Sources/Services/**/*.swift"
EOF
cat > /tmp/test-maintenance/spec.md <<EOF
Review each file for service layer convention compliance.
EOF

swift run ai-dev-tools-kit maintenance discover --task /tmp/test-maintenance --repo <some-test-repo>
# Verify spec.md has [ ] entries for all matched files
# Verify state.json has null hashes for all paths

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <some-test-repo>
# Verify PR created; spec.md has [x] for first entry; state.json updated with hash + date

swift run ai-dev-tools-kit maintenance discover --task /tmp/test-maintenance --repo <some-test-repo>
# Verify [x] entries remain [x] (hashes match)

swift run ai-dev-tools-kit maintenance run --task /tmp/test-maintenance --repo <some-test-repo>
# Verify second task runs (next [ ] entry)
```

**Log verification**:
```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label | startswith("Maintenance"))'
```
