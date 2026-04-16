# Migrate Git File Browser as RepoExplorer Tab

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture conventions — ensures copied code lands in the right layer |
| `ai-dev-tools-composition-root` | How shared services are wired; use when adding RepoExplorerUI to the Mac app |
| `ai-dev-tools-enforce` | Run after all phases complete to catch violations before closing the plan |
| `swift-architecture` | Architecture reference for planning and layer placement |

## Background

RefactorApp contains a Git repository file browser — an IDE-like sidebar that shows a live file tree for a git repo and reacts to on-disk changes via FSEvents. We want to surface this as a new tab in AIDevTools.

**Strategy**: Copy the feature bottom-up, one dependency layer at a time. Because some target names from RefactorApp already exist in AIDevTools (notably `DataPathsService`), all incoming targets are namespaced under the `RepoExplorer` prefix to avoid conflicts. Deduplication against existing targets is explicitly deferred to a later pass.

All new code lives in a single new Swift package: `packages/RepoExplorerKit/` inside the AIDevTools repo. This package contains multiple targets, each named with the `RepoExplorer` prefix.

**Minimum required targets** (stripped to just the file-browser feature, no Claude/Jira/GitHub pull-in):

| Source target (RefactorApp) | New target name (AIDevTools) |
|---|---|
| `CLITools` | `RepoExplorerCLITools` |
| `DataPathsService` | `RepoExplorerDataPathsService` |
| `GitClient` (+ GitRepositoryMonitor) | `RepoExplorerGitClient` |
| `FileTreeService` | `RepoExplorerFileTreeService` |
| `GitCLI` (TreeCommands) | `RepoExplorerCLI` (executable) |
| UI layer (views + viewmodel) | `RepoExplorerUI` |

`GitService`, `GitUI`, `GithubService`, `ClaudeService`, `ClaudeUI`, `JiraService` — **not included**; they are used by other features in `GitFeatureUI` but not by the file browser itself.

---

## - [x] Phase 1: Create RepoExplorerCLITools

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Kept this phase as a leaf SDK migration only: created a standalone `RepoExplorerKit` package with a single `RepoExplorerCLITools` product, copied the source without adding cross-layer dependencies, and wired the local package into `AIDevToolsKit` without pulling later-phase targets forward.

**Skills to read**: `ai-dev-tools-architecture`

Copy `CLITools` from RefactorApp into a new target inside a new package at `packages/RepoExplorerKit/`.

Steps:
- Create `packages/RepoExplorerKit/Package.swift` with Swift tools version 6.0, macOS 14+ platform
- Add target `RepoExplorerCLITools` with sources at `Sources/RepoExplorerCLITools/`
- Copy all source files from `/Users/bill/Developer/personal/RefactorApp/sdks/CLITools/Sources/CLITools/` into that directory
- No external dependencies — this is a leaf node
- Add `RepoExplorerKit` as a local package dependency in the root `AIDevTools` or `AIDevToolsKit` Package.swift (whichever owns the Mac app target)

Expected outcome: `RepoExplorerCLITools` builds cleanly with no dependency on any other new target.

---

## - [x] Phase 2: Create RepoExplorerDataPathsService

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Kept the migration as a leaf services-layer copy: added a namespaced package target without cross-target dependencies, preserved the original service API for downstream phases, and kept the implementation isolated inside `RepoExplorerKit`.

**Skills to read**: `ai-dev-tools-architecture`

Copy `DataPathsService` from RefactorApp, renamed to avoid the conflict with AIDevTools' existing `DataPathsService`.

Steps:
- Add target `RepoExplorerDataPathsService` with sources at `Sources/RepoExplorerDataPathsService/` inside `packages/RepoExplorerKit/`
- Copy all source files from `/Users/bill/Developer/personal/RefactorApp/services/DataPathsService/Sources/DataPathsService/`
- No external dependencies — leaf node
- Update `packages/RepoExplorerKit/Package.swift` to include this target

Expected outcome: `RepoExplorerDataPathsService` builds cleanly in isolation.

---

## - [x] Phase 3: Create RepoExplorerGitClient

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Kept this phase scoped to the SDK layer by adding a namespaced `RepoExplorerGitClient` target with only the `RepoExplorerCLITools` dependency, updating copied imports to the new module name, and replacing the copied timer-bound main-actor polling with a task-based monitor so the SDK target builds cleanly under Swift 6 concurrency checks.

**Skills to read**: `ai-dev-tools-architecture`

Copy `GitClient` (which includes `GitRepositoryMonitor` — the git-status polling service).

Steps:
- Add target `RepoExplorerGitClient` with sources at `Sources/RepoExplorerGitClient/`
- Copy all source files from `/Users/bill/Developer/personal/RefactorApp/sdks/GitClient/Sources/GitClient/`
- Depends on: `RepoExplorerCLITools` (within the same package)
- Fix any import statements in copied files: `import CLITools` → `import RepoExplorerCLITools`

Expected outcome: `RepoExplorerGitClient` builds, including `GitRepositoryMonitor`.

---

## - [x] Phase 4: Create RepoExplorerFileTreeService

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Kept this phase in the services layer by adding a namespaced `RepoExplorerFileTreeService` target that depends only on `RepoExplorerDataPathsService`, copied the file-tree models and monitor into the package, and made only the minimum import and platform adjustments needed for Swift 6/macOS package builds.

**Skills to read**: `ai-dev-tools-architecture`

Copy `FileTreeService` — the core actor that indexes directories, caches trees, and drives FSEvents monitoring.

Steps:
- Add target `RepoExplorerFileTreeService` with sources at `Sources/RepoExplorerFileTreeService/`
- Copy all source files from `/Users/bill/Developer/personal/RefactorApp/services/FileTreeService/Sources/FileTreeService/`
  - `Services/FileTreeService.swift`
  - `Services/FileSystemMonitor.swift`
  - `Models/FileSystemItem.swift`
  - `Models/DirectoryCache.swift`
  - `Models/ProgressState.swift`
- Depends on: `RepoExplorerDataPathsService` (within the same package)
- Fix imports: `import DataPathsService` → `import RepoExplorerDataPathsService`

Expected outcome: Full file-tree engine builds, including FSEvents monitoring and disk caching.

---

## - [x] Phase 5: Create RepoExplorerCLI

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `RepoExplorerCLI` as an app-layer executable that depends only on `RepoExplorerFileTreeService`, kept command orchestration inside the CLI target without introducing higher-layer imports, and fixed fresh-scan file caching in the service so the CLI and future UI share the same indexing behavior.

**Skills to read**: `ai-dev-tools-architecture`

Create an executable target that exposes all `FileTreeService` capabilities from the command line. This is the primary way to verify the service layer works before touching any UI.

Subcommands to implement (modeled on `TreeCommands.swift` from RefactorApp):

| Subcommand | What it does |
|---|---|
| `repo-explorer index <path>` | Index a directory and write the disk cache |
| `repo-explorer list <path>` | List all cached files, optional `--filter` glob |
| `repo-explorer search <path> <query>` | Fuzzy file search against the cached index |
| `repo-explorer stats <path>` | Print file count, type breakdown, ignore pattern summary |
| `repo-explorer create-file <path>` | Create an empty file |
| `repo-explorer create-folder <path>` | Create a directory |
| `repo-explorer delete <path>` | Delete a file or folder (prompt for confirmation; `--force` skips) |
| `repo-explorer rename <old> <new>` | Rename a file or folder |

Steps:
- Add executable target `RepoExplorerCLI` with sources at `Sources/RepoExplorerCLI/` in `packages/RepoExplorerKit/Package.swift`
- Add `swift-argument-parser` as an external dependency in `packages/RepoExplorerKit/Package.swift`
- Target depends on: `RepoExplorerFileTreeService` only (no UI dep)
- Copy `TreeCommands.swift` from `/Users/bill/Developer/personal/RefactorApp/features/GitFeature/Sources/GitCLI/` as the starting point, fixing imports (`import FileTreeService` → `import RepoExplorerFileTreeService`)
- Wire up a `@main` entry point (`RepoExplorerCommand`) that registers all subcommands

Expected outcome: `swift run repo-explorer --help` lists all subcommands. `repo-explorer index <path>` + `repo-explorer list <path>` successfully index and print a local directory.

---

## - [x] Phase 7: Create RepoExplorerUI

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-composition-root`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`
**Principles applied**: Kept the migrated file browser in the app layer by introducing a standalone `RepoExplorerUI` target, injected `FileTreeService` into the observable view model instead of constructing services inside the UI, and trimmed the wrapper down to tree browsing, quick-open, and file preview so it does not pull in unrelated GitHub/Claude/Git UI dependencies.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Copy only the file-browser views and view model from `GitFeatureUI` — not the full GitFeature package (which pulls in Claude/Jira/GitHub).

Files to copy from `/Users/bill/Developer/personal/RefactorApp/features/GitFeature/Sources/GitFeatureUI/`:
- `DirectoryTree/DirectoryTreeView.swift`
- `DirectoryTree/DirectoryBrowserViewModel.swift`
- `DirectoryTree/FileItemRow.swift`
- `DirectoryTree/QuickFilePickerView.swift`
- `WorkingDirectoryViews.swift` — keep only the file-browser portion; strip out git-diff/staging/commit panels and `GitRepositoryMonitor` wiring for now if they pull in missing deps

Steps:
- Add target `RepoExplorerUI` with sources at `Sources/RepoExplorerUI/`
- Depends on: `RepoExplorerFileTreeService`, `RepoExplorerGitClient`
- Fix all imports to use the renamed targets
- Remove or stub out any references to `GitService`, `GitUI`, `ClaudeService`, `GithubService` — these are not being migrated

Expected outcome: `RepoExplorerUI` builds. `WorkingDirectoryViews` (or a trimmed-down wrapper) renders a working file tree for a selected directory.

---

## - [x] Phase 8: Add RepoExplorer Tab to WorkspaceView

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: Kept RepoExplorer service construction in the Mac composition root by exposing a view-model factory, then used a thin workspace tab wrapper to bind the selected repository path to the migrated RepoExplorer UI without pushing service wiring into `WorkspaceView`.

**Skills to read**: `ai-dev-tools-composition-root`

Wire the new UI into the Mac app and expose it as a new tab.

Steps:
- Add `RepoExplorerKit` as a dependency to whatever Package.swift target owns `WorkspaceView` (currently `AIDevToolsKitMac` inside `AIDevToolsKit`)
- In `WorkspaceView.swift` (at `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/WorkspaceView.swift`), add a new tab entry alongside the existing ones (Architecture, Chains, Plans, PR Radar, Skills, Worktrees)
- Tab label: "Repo Explorer" or "Files", system image: `"folder.badge.gearshape"` or `"sidebar.squares.left"`
- Tab value key: `"repoExplorer"` (follows the existing `@AppStorage("selectedWorkspaceTab")` pattern)
- Tab content: instantiate `DirectoryBrowserViewModel` and pass it to the top-level RepoExplorer view
- Provide an initial repo URL — either hardcoded to the app's working directory for now, or wired to the existing Repositories settings

Expected outcome: App builds and runs; new "Repo Explorer" tab appears and shows a live file tree.

---

## - [ ] Phase 9: Validation

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-ui-tests`

- Build the app with `xcodebuild` (or via Xcode) and confirm zero errors
- Launch the app, navigate to the new tab, and verify:
  - File tree loads for a repo directory
  - Expanding folders reveals children
  - Creating/renaming/deleting a file on disk causes the tree to update (FSEvents reaction)
  - Quick file picker (Cmd+Shift+O) opens and returns results
- Run `ai-dev-tools-enforce` on all files changed during this plan to check for architecture or code-quality violations
- Fix any violations before marking the plan complete
