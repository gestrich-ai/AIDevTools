# Migrate RepoExplorerKit into AIDevToolsKit

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture conventions — ensures targets land in the right layer |
| `ai-dev-tools-composition-root` | How shared services are wired; needed when adding FileTreeService and updating the Mac app |
| `ai-dev-tools-enforce` | Run after all phases complete to catch violations before closing the plan |
| `swift-architecture` | Architecture reference for planning and layer placement |

## Background

`RepoExplorerKit` (`packages/RepoExplorerKit/`) was created as a temporary namespace to avoid naming collisions while migrating the git file browser from RefactorApp. Now that the feature is stable, we want to dissolve the separate package and absorb its targets into the main `AIDevToolsKit` layered structure.

**Target inventory and disposition:**

| Target | Type | Layer | Disposition |
|---|---|---|---|
| `RepoExplorerUI` | Library | Features | **Move** → `RepoExplorerFeature` in `AIDevToolsKit/Sources/Features/` |
| `RepoExplorerFileTreeService` | Library | Services | **Move** → `FileTreeService` in `AIDevToolsKit/Sources/Services/` |
| `RepoExplorerDataPathsService` | Library | Services | **Remove** — duplicate of existing `DataPathsService` |
| `RepoExplorerGitClient` | Library | SDKs | **Remove** — declared as a dep of `RepoExplorerUI` but never imported by any UI file; assess unique value against `GitSDK` before deleting |
| `RepoExplorerCLITools` | Library | SDKs | **Remove** — duplicate of `CLISDK` (external SwiftCLI package) |
| `RepoExplorerCLI` | Executable | Apps | **Integrate** — move its subcommands into `AIDevToolsKitCLI` |

**Strategy**: work top-down. Move the highest-level target first (`RepoExplorerUI`). Each phase resolves the dependencies that surface, removing duplicates along the way instead of moving them. Continue until `RepoExplorerKit` is empty and can be deleted.

---

## - [x] Phase 1: Move RepoExplorerUI → RepoExplorerFeature

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Moved the Repo Explorer UI into the `Features` layer as a shared package target, kept service construction in the Mac app composition root, and limited cross-package coupling to the existing `RepoExplorerFileTreeService` dependency for this phase.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Move the SwiftUI views and view model into the main package as a proper Features-layer target.

Steps:
- Create `AIDevToolsKit/Sources/Features/RepoExplorerFeature/` and copy all files from `packages/RepoExplorerKit/Sources/RepoExplorerUI/`
- Add `RepoExplorerFeature` target to `AIDevToolsKit/Package.swift`
  - Depends on: `RepoExplorerFileTreeService` (still cross-package for now — resolved in Phase 2)
  - **Drop** `RepoExplorerGitClient` dependency — grep confirms no UI file imports it
- Update `AIDevToolsKitMac` in `AIDevToolsKit/Package.swift` to depend on `RepoExplorerFeature` instead of `RepoExplorerUI`
- Update the `WorkspaceView` import: `import RepoExplorerUI` → `import RepoExplorerFeature`
- Delete `packages/RepoExplorerKit/Sources/RepoExplorerUI/` and remove `RepoExplorerUI` product/target from `packages/RepoExplorerKit/Package.swift`

Expected outcome: App builds; RepoExplorer tab works as before. `RepoExplorerFeature` lives in `AIDevToolsKit`; `RepoExplorerKit` still has 5 targets.

---

## - [x] Phase 2: Move RepoExplorerFileTreeService → FileTreeService, remove RepoExplorerDataPathsService

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Moved the file-tree engine into the Services layer as a first-class `AIDevToolsKit` target, rewired feature and app callers to the shared `DataPathsService` instead of a duplicate service package, and kept CLI integration out of scope for this phase.

**Skills to read**: `ai-dev-tools-architecture`

Move the file-tree engine into the Services layer, simultaneously resolving the `RepoExplorerDataPathsService` duplicate by switching to the existing `DataPathsService`.

Steps:
- Create `AIDevToolsKit/Sources/Services/FileTreeService/` and copy all files from `packages/RepoExplorerKit/Sources/RepoExplorerFileTreeService/`
- In the copied service files, replace `import RepoExplorerDataPathsService` → `import DataPathsService`; verify `DataPathsService` API is compatible (both expose a `DataPathsService` type with path-resolution methods)
- Add `FileTreeService` target to `AIDevToolsKit/Package.swift`
  - Depends on: `DataPathsService` (existing target)
- Update `RepoExplorerFeature` target in `AIDevToolsKit/Package.swift`: replace cross-package `RepoExplorerFileTreeService` dep with local `FileTreeService`
- Update import in all `RepoExplorerFeature` source files: `import RepoExplorerFileTreeService` → `import FileTreeService`
- Delete `packages/RepoExplorerKit/Sources/RepoExplorerFileTreeService/` and `packages/RepoExplorerKit/Sources/RepoExplorerDataPathsService/`; remove both products/targets from `packages/RepoExplorerKit/Package.swift`

Expected outcome: App builds; `RepoExplorerKit` now has 3 targets (`RepoExplorerGitClient`, `RepoExplorerCLITools`, `RepoExplorerCLI`).

---

## - [x] Phase 3: Remove RepoExplorerGitClient and RepoExplorerCLITools

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Removed the unused SDK-layer targets without migrating their internals because Phase 2 left no consumers, kept `GitSDK` unchanged until a real caller exists, and limited this phase to package-graph cleanup so the remaining `RepoExplorerCLI` work stays isolated for Phase 4.

**Skills to read**: `ai-dev-tools-architecture`

Neither target has live consumers after Phase 2, but both have unique content worth evaluating before deletion.

**RepoExplorerGitClient assessment**:
- `GitSDK` (existing) has: `GitCLI`, `GitService`, `GitClient`, `DiffFilter`, `WorktreeInfo`
- `RepoExplorerGitClient` adds: blame cache (`GitBlameCacheManager`), richer diff parsing (`EnrichedDiff`, `DiffReview`, `BlameInfo`), `GitRepositoryMonitor`, `GitStatusParser`, `OwnershipProvider`, branch/commit models
- Decision: if any of this content is needed by `FileTreeService`, `RepoExplorerFeature`, or other existing targets, merge the unique types into `GitSDK`. Otherwise remove.
- Check: `GitRepositoryMonitor` was used by the original `WorkingDirectoryViews` before the migration — verify whether `RepoExplorerFeature` needs it. If not, drop the target entirely.

**RepoExplorerCLITools assessment**:
- Provides `CLIService`, `CommandLineRunner`, `CLIHelpers` — the same role as `CLISDK` from the SwiftCLI external package
- `RepoExplorerGitClient` is its only consumer; once that is removed, `RepoExplorerCLITools` has no consumers
- Remove without migrating (CLISDK already covers this)

Steps:
- Grep across `AIDevToolsKit` and `packages/RepoExplorerKit` for any remaining imports of `RepoExplorerGitClient` or `RepoExplorerCLITools`
- If `GitRepositoryMonitor` or other types are needed: copy them into `GitSDK` and update callers
- Remove `packages/RepoExplorerKit/Sources/RepoExplorerGitClient/` and `packages/RepoExplorerKit/Sources/RepoExplorerCLITools/`
- Remove both products/targets from `packages/RepoExplorerKit/Package.swift`

Expected outcome: `RepoExplorerKit` has only 1 target left (`RepoExplorerCLI`).

---

## - [x] Phase 4: Integrate RepoExplorerCLI into AIDevToolsKitCLI

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-composition-root`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`
**Principles applied**: Moved the file-tree commands into the main Apps-layer CLI, routed `FileTreeService` through `CLICompositionRoot` instead of constructing `DataPathsService` inside commands, and removed the stale package dependency that blocked builds once `RepoExplorerCLI` was deleted.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

The `repo-explorer` executable has 8 subcommands (index, list, search, stats, create-file, create-folder, delete, rename). Integrate them into the main CLI.

Steps:
- Examine `AIDevToolsKitCLI`'s command registration pattern in `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/`
- Copy `TreeCommands.swift` content into a new file under `AIDevToolsKitCLI` (e.g., `FileTreeCommands.swift`), updating:
  - `import RepoExplorerFileTreeService` → `import FileTreeService`
  - Any `RepoExplorer`-prefixed types to their new names
- Register the commands in the CLI's root command group (following existing patterns)
- Delete `packages/RepoExplorerKit/Sources/RepoExplorerCLI/`
- Remove `RepoExplorerCLI` product/target from `packages/RepoExplorerKit/Package.swift`

Expected outcome: `swift run AIDevToolsKitCLI file-tree --help` (or equivalent) lists the subcommands. `RepoExplorerKit` has no remaining targets.

---

## - [ ] Phase 5: Delete RepoExplorerKit Package

**Skills to read**: none

With all targets migrated or removed, clean up the package itself.

Steps:
- Verify `packages/RepoExplorerKit/Sources/` is empty (no remaining targets)
- Remove `RepoExplorerKit` from `AIDevToolsKit/Package.swift` dependencies and any `.package(path:)` references
- Delete `packages/RepoExplorerKit/` directory
- If `packages/` becomes empty, remove that directory too

Expected outcome: `packages/RepoExplorerKit/` no longer exists; AIDevToolsKit builds without referencing it.

---

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-build-quality`

- Build `AIDevToolsKit` with `xcodebuild` — zero errors, zero warnings
- Launch the Mac app; verify RepoExplorer tab loads and the file tree works (expand folders, FSEvents reactions, Quick Open)
- Verify `AIDevToolsKitCLI` file-tree subcommands execute correctly against a local repo
- Run `ai-dev-tools-enforce` on all files changed across all phases to catch architecture or code-quality violations
- Fix any violations before marking the plan complete
