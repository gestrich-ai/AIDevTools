## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — ensures new service and view layers land in the right place |
| `ai-dev-tools-code-organization` | Swift file and type organization conventions |
| `ai-dev-tools-composition-root` | How shared services are wired in the Mac app — needed when adding new services |
| `ai-dev-tools-enforce` | Post-change enforcement of all project standards |

## Background

The planning feature executes phases sequentially, each committing changes with the message format `"Complete Phase {N}: {phase description}"`. After execution, reviewing those changes requires leaving the app to run `git diff` in a terminal. The goal of this plan is to bring that review experience in-app with an interactive diff view.

This is a **generalized diff component** — not specific to planning. The same view should be reusable wherever a diff is needed (planning, future features). It is intentionally distinct from PR Radar, which serves a different workflow (reviewing GitHub pull requests). However, it reuses PR Radar's rendering atoms for visual consistency.

**PR Radar diff architecture (confirmed):**

PR Radar uses two diff views: `DiffPhaseView` (inline, Diff tab) and `EffectiveDiffView` (sheet, after Prepare). Both render via `AnnotatedDiffContentView`, which requires non-optional `PRDiff` and `PRModel`. The rendering atoms inside it — `DiffLineRowView`, `HunkHeaderView`, `RenameFileHeaderView`, `PureRenameContentView` — are generic with no `PRModel` dependency. These atoms are what this plan reuses for visual consistency.

**Reuse vs. duplication decision:**

`AnnotatedDiffContentView`'s body is a ~30-line file→hunk→line iteration with PR-specific overlays woven in (inline comments, selective analysis per-hunk). The iteration logic is generic but inseparable from the PR overlays without modifying PR Radar. Decision: duplicate the iteration in `GitDiffView` using the same atoms, rather than touch PR Radar code for a non-PR concern.

**Confirmed supporting infrastructure:**

- `PRDiff.fromRawDiff(_:)` already exists — builds a blank `PRDiff` from a `GitDiff` with no moves
- `PRHunk.fromHunk(_:)` already exists — converts a `Hunk` into `PRLine` objects with line numbers and diff type
- `GitClient.logGrepAll(_:workingDirectory:)` — finds commits by message pattern
- `GitClient.getCurrentBranch(workingDirectory:)`, `GitService.getBranchDiff(...)` — existing git diff infrastructure
- `activePlanModel` in `PlanDetailView` already does file watching for the plan markdown

## Phases

## - [x] Phase 1: Create a shared target called `GitUIToolkit`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`
**Principles applied**: Extracted the reusable diff atoms into a dedicated UI toolkit target with one file per shared type, kept PR-specific line-info UI in the app layer via injected popover content, and reused the existing service-layer diff models instead of duplicating them.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`

Create a new Swift package target called `GitUIToolkit` in the `ui-toolkits` layer for generic, reusable diff UI components. This target will be importable by both PRRadar and the new planning diff feature — and any future feature that needs a diff view.

In `Package.swift`, add a `// UI Toolkits Layer` section and register the target:

```swift
// UI Toolkits Layer
.target(
    name: "GitUIToolkit",
    dependencies: [],
    path: "Sources/UIToolkits/GitUIToolkit"
),
```

Move the following from `PRRadar/Views/GitViews/RichDiffViews.swift` into `GitUIToolkit`:

- `DiffLineRowView` — single diff line renderer (line numbers, gutter colors, monospaced text)
- `HunkHeaderView` — `@@ -X,Y +A,B @@` hunk separator bar
- `RenameFileHeaderView` — file rename header
- `PureRenameContentView` — "File renamed without changes" placeholder
- The `diffListRow()` view modifier
- `DiffLayout` constants (gutter width etc.)

Update PRRadar to import `GitUIToolkit` instead of defining these types locally. This is a pure refactor — no behavior changes.

## - [x] Phase 2: Build `GitDiffView` in `GitUIToolkit`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`
**Principles applied**: Kept the new diff view in the `GitUIToolkit` layer with a single primary type per file, reused the shared diff atoms from Phase 1, and rendered directly from `GitDiff`/`Hunk` so the toolkit view stays independent from PR-specific app models.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`

Create `GitDiffView` in `GitUIToolkit`. It takes a single `GitDiff` and has no dependency on `PRModel`, `PRDiff`, or any PR Radar type.

**File sidebar (left panel):**
A `List` with a "Changed Files" section showing each file's last path component and hunk count. Matches the visual style of `EffectiveDiffView`'s left panel. Tapping a file sets `selectedFile` and filters the right panel.

**Diff content (right panel):**
A `List` with `listStyle(.plain)` iterating:
```
ForEach(changedFiles) {
    file path header (bold monospaced) or RenameFileHeaderView
    PureRenameContentView (if pure rename)
    ForEach(hunks) {
        HunkHeaderView(hunk:)
        ForEach(PRHunk.fromHunk(hunk).lines) {
            DiffLineRowView(lineContent:oldLineNumber:newLineNumber:lineType:)
        }
    }
}
```
No `onAddComment`, `onMoveTapped`, or `onSelectRules` callbacks (pass nil). No `prLine` (omit line info popover).

Layout: `HSplitView` with sidebar `frame(minWidth: 180, idealWidth: 220, maxWidth: 260)`, same proportions as `DiffPhaseView`.

## - [x] Phase 3: Build `CommitListDiffView` with commit selection

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Kept the commit-selection model and SwiftUI entry view in the app layer, moved reusable local diff loading into a dedicated shared service instead of wiring git commands directly in views, and left plan-specific preselection as optional input so the component stays general-purpose.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Build a combined view that pairs a commit list (top or sidebar) with `GitDiffView`. This is the main entry point for the diff feature — completely general, not plan-specific.

**Commit list entries** (in order, most recent first):
- **Unstaged changes** — `git diff HEAD` (always shown if dirty)
- **Staged changes** — `git diff --cached` (shown only if staging area is non-empty)
- **Recent commits** — last N commits from `git log` (default: 20)

**Selection behavior:**
- Single click → load and show diff for that entry
- Ctrl+click → multi-select; show combined diff across selected commits (`git diff <oldest>^..<newest>` for commits; concatenated for unstaged/staged)
- "All plan commits" button — when opened from a plan context, pre-selects all commits whose messages match the plan's phase pattern. Implemented via `GitClient.logGrepAll("Complete Phase", workingDirectory:)` filtered by the plan's phase descriptions.

**Diff loading:** Add methods to `GitService` (or a new `LocalDiffService`) for:
- `getDiff(forCommit:repoPath:)` — `git show <hash>`
- `getUnstagedDiff(repoPath:)` — `git diff HEAD`
- `getStagedDiff(repoPath:)` — `git diff --cached`
- `getCombinedDiff(commits:repoPath:)` — `git diff <oldest>^..<newest>`

## - [x] Phase 4: Disk monitoring for live diff updates

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Kept git/disk watching in a Services-layer utility that emits `AsyncStream` updates, resolved the actual git directory through `git rev-parse --git-dir` so worktrees are covered, and kept selection-aware refresh logic in the app model instead of pushing UI state into the service.

**Skills to read**: `ai-dev-tools-architecture`

The diff view should respond to changes on disk without requiring manual refresh — similar to how Tower and other git clients work.

**What to monitor:**
- The repository's working directory for file changes (detect when unstaged changes appear or disappear)
- The git index (`.git/index`) to detect staging changes

**Behavior:**
- When viewing unstaged changes: auto-refresh the diff whenever files change on disk
- When not viewing unstaged changes: add or update the "Unstaged changes" entry in the commit list to signal that new changes exist
- Use `DispatchSource.makeFileSystemObjectSource` for `.git/index` and an `FSEventStream` (or polling fallback) for the working tree

Implement this as a `GitWorkingDirectoryMonitor` service that publishes change notifications via `AsyncStream` or `Combine`. `CommitListDiffView` subscribes and refreshes accordingly.

## - [x] Phase 5: MCP context integration for chat

**Skills used**: `ai-dev-tools-composition-root`, `ai-dev-tools-enforce`
**Principles applied**: Added a single Mac-app context model in the composition root for transient chat state, updated plan and diff views to publish only active UI context into that model, and extended the existing MCP/IPC path with a focused `get_chat_context` tool instead of introducing a second transport or ad hoc service wiring.

**Skills to read**: `ai-dev-tools-composition-root`

The app already has a chat window (Claude chain view). When the diff view is open, the user should be able to ask the AI to make changes in the chat window with full context about what they're looking at.

Add new MCP resource(s) or tool(s) that expose:
- **Currently selected commit(s)** — hash(es) and commit message(s)
- **Currently selected file** in the diff — file path
- **Open plan context** — plan file path and name, completed phases

Include a description note in the MCP resource that tells the AI: when a user asks about changes visible in an open diff or asks to make edits, they are likely requesting code modifications to the files shown.

Identify the existing MCP infrastructure in the project (look for MCP server registration) to determine the correct place to add these resources. Keep the new resources scoped — they reflect transient UI state, so they should read from a shared observable state object updated by `CommitListDiffView`.

## - [x] Phase 6: Markdown editor mode and live reload for plan view

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`
**Principles applied**: Kept markdown editing in a reusable UI toolkit instead of the planning feature, saved edited content through a dedicated PlanFeature use case rather than direct view-layer file I/O, and coordinated file watching with edit mode so view mode live-reloads without overwriting in-progress edits.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`

Two improvements to the plan markdown view in `PlanDetailView`:

**Edit mode:**
Add an "Edit" toggle button to the plan view header. When toggled:
- View mode (default): shows rendered markdown (the existing `Markdown(planContent)` view)
- Edit mode: shows a `TextEditor` with the raw markdown content, editable

On leaving edit mode, write the edited content back to the plan file on disk. Place the editable markdown component in a reusable target (not inside the planning feature) since other features may want an editable markdown view.

**Live reload:**
The plan markdown file already has some watching via `activePlanModel.startWatching(url:)`. Verify this correctly re-renders the markdown view when the file changes on disk (e.g., when the AI updates it during execution). If not already working, wire the file monitor output to refresh `planContent` and trigger a re-render. The view should update automatically — no manual refresh required.

## - [x] Phase 7: Wire `CommitListDiffView` into `PlanDetailView`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`, `ai-dev-tools-enforce`
**Principles applied**: Kept `CommitListDiffView` general-purpose by passing only repository path and completed phase descriptions from `PlanDetailView`, and moved diff service/monitor construction into the composition root so view code consumes injected dependencies instead of assembling infrastructure.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Replace the simple "View Diff" button and sheet from the original design with `CommitListDiffView` embedded in or presented from `PlanDetailView`.

- Pass the plan's repository path as the working directory
- Pass the plan's completed phases so the "All plan commits" button can pre-select the right commits
- The view is a general `CommitListDiffView` — no plan-specific logic leaks into it beyond the initial commit pre-selection

Wire `GitWorkingDirectoryMonitor` (Phase 4) and the MCP state object (Phase 5) into the composition root so both are available when the view appears.

## - [x] Phase 8: Validation

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`
**Principles applied**: Added focused automated validation around the new diff toolkit, local diff service, monitor, and plan-selection flow; fixed the root-commit combined-diff edge case uncovered by validation; kept test-only seams small and reused the existing package test structure.

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`

**Automated tests:**
- `GitDiffView` renders correctly with a known `GitDiff` (snapshot or UI test)
- `LocalDiffService` methods return correctly parsed `GitDiff` for stubbed git output
- `GitWorkingDirectoryMonitor` publishes a change event when `.git/index` is modified
- "All plan commits" selection correctly identifies commits matching plan phase messages

**Manual checks:**
- Open a plan with completed phases; verify "All plan commits" pre-selects the right commits and shows a correct diff
- Ctrl+click multiple commits; verify combined diff is shown
- Select "Unstaged changes"; make a file edit externally; verify diff auto-refreshes
- Open chat while a file is selected in the diff; ask a question; verify the AI receives commit and file context
- Toggle edit mode on the plan markdown; make an edit; verify it saves and re-renders
- Verify no PR Radar diff functionality is broken

**Enforce:**
Run `/ai-dev-tools-enforce` on all files changed across all phases before marking this plan complete.
