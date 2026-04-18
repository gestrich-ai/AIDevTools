## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — ensures new context logic lands in the right layer |
| `ai-dev-tools-composition-root` | How shared services are wired in the Mac app |
| `ai-dev-tools-enforce` | Post-change enforcement of all project standards |

## Background

The chat inspector panel currently uses a single `GlobalChatContext` with a fixed identifier (`"global"`) and a working directory that is captured once at init time and never updated. This causes two problems: (1) Codex/Claude sessions always start with `cwd: /` instead of the selected repo path, and (2) switching tabs or repos silently reuses the same chat session rather than giving each context its own isolated conversation.

The goal is:
- Each tab + repo combination gets its own independent chat panel state (messages, session ID, working directory).
- The panel open/closed state persists per tab across app restarts and is restored on launch.
- When the panel reopens for a tab it was previously open on, it resumes the last session for that repo.
- Session history shows only sessions for the current repo (this comes for free once the working directory is correct, since session lookup uses the working directory).
- The working directory shows in the header and can be changed before a session starts, then locks once the first message is sent.

This plan incorporates the earlier working-directory-selector work into a single cohesive set of changes.

## Phases

## - [x] Phase 1: Per-tab, per-repo panel isolation via `.id`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-enforce`
**Principles applied**: Kept the change in the Apps layer, used SwiftUI view identity to isolate per-tab/per-repo state, and derived a stable chat context identifier from the tab plus working directory instead of introducing extra coordination state.

**Skills to read**: `ai-dev-tools-architecture`

The fastest, most reliable way to give each tab+repo its own isolated state is to use SwiftUI's `.id()` modifier on `RightExecutionPanelView`. When the id changes, SwiftUI destroys and recreates the view tree including all `@State` — so `GlobalChatContext` is re-initialized with the new working directory and a new `chatContextIdentifier`.

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/WorkspaceView.swift`**

1. Add `.id("\(selectedTab)-\(model.selectedRepository?.id.uuidString ?? "")")` to `RightExecutionPanelView` in the `.inspector` modifier.
2. Ensure the `workingDirectory:` argument already passes `model.selectedRepository?.path.path(percentEncoded: false) ?? ""` (it does — verify no regression).

```swift
.inspector(isPresented: Bindable(executionPanelModel).isVisible) {
    RightExecutionPanelView(
        workingDirectory: model.selectedRepository?.path.path(percentEncoded: false) ?? ""
    )
    .id("\(selectedTab)-\(model.selectedRepository?.id.uuidString ?? "")")
    .environment(executionPanelModel)
}
```

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/Chat/RightExecutionPanelView.swift`**

Update `GlobalChatContext.chatContextIdentifier` from the hardcoded `"global"` to a value derived from a `tab` parameter passed into `RightExecutionPanelView.init`. The working directory is already stored on the context; combine with it to produce a stable, unique identifier per context:

```swift
// RightExecutionPanelView.init now accepts tab name too
init(tab: String, workingDirectory: String) {
    _chatContext = State(initialValue: GlobalChatContext(tab: tab, workingDirectory: workingDirectory))
}
```

```swift
final class GlobalChatContext: ViewChatContext {
    let chatContextIdentifier: String   // e.g. "plans-/Users/bill/.../AIDevTools"
    let chatWorkingDirectory: String
    let chatSystemPrompt = "..."

    init(tab: String, workingDirectory: String) {
        self.chatContextIdentifier = "\(tab)-\(workingDirectory)"
        self.chatWorkingDirectory = workingDirectory
    }
}
```

Pass `tab: selectedTab` from `WorkspaceView` when constructing `RightExecutionPanelView`.

**Result**: Switching tabs or repos destroys/recreates the panel → each combination has isolated `ChatModel` state and `cwd`.

---

## - [x] Phase 2: Persist panel open/closed state per tab+repo

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Persisted only view-layer UI state in `UserDefaults`, keyed it by the existing tab+repo identity, restored it on launch and context switches, and forced unsupported contexts closed so visibility cannot leak across tabs or repos.

**Skills to read**: (none specific — standard SwiftUI AppStorage/UserDefaults pattern)

The toolbar button only appears for `"claudeChain"` and `"plans"` tabs. Each of those tabs (per repo) should remember its own open/closed state.

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/WorkspaceView.swift`**

1. Add helpers to read/write visibility keyed by `"\(tab)-\(repoID)"`:

```swift
private func panelVisibilityKey(tab: String, repoID: UUID?) -> String {
    "chatPanelVisible_\(tab)_\(repoID?.uuidString ?? "none")"
}

private func savePanelVisibility(_ visible: Bool) {
    guard let repo = model.selectedRepository else { return }
    UserDefaults.standard.set(visible, forKey: panelVisibilityKey(tab: selectedTab, repoID: repo.id))
}

private func restorePanelVisibility() {
    guard let repo = model.selectedRepository else { return }
    let key = panelVisibilityKey(tab: selectedTab, repoID: repo.id)
    executionPanelModel.isVisible = UserDefaults.standard.bool(forKey: key)
}
```

2. Call `restorePanelVisibility()` in:
   - The `.task` body (after the repo is loaded from AppStorage)
   - `.onChange(of: selectedTab)` to restore visibility when switching tabs
   - `.onChange(of: model.selectedRepository?.id)` to restore when repo changes

3. Call `savePanelVisibility(executionPanelModel.isVisible)` in `.onChange(of: executionPanelModel.isVisible)` so any toggle (toolbar button or programmatic) is persisted.

**Result**: After restart, each tab opens with the panel in the same state it was left.

---

## - [x] Phase 3: Auto-resume last session when panel opens

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Kept the change local to chat panel model creation, enabling last-session resume only for this contextual panel flow without introducing extra persistence or cross-layer coordination.

**Skills to read**: (none specific)

When a chat panel is freshly created for a tab+repo it has visited before, it should resume the most recent session for that working directory.

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/Chat/ContextualChatPanel.swift`**

In `rebuildChatModel()`, change `settings.resumeLastSession` from `false` to `true`:

```swift
let settings = ChatSettings()
settings.resumeLastSession = true   // was false
```

`ChatModel.init` already handles this: if `resumeLastSession == true`, it calls `resumeLatestSession(workingDirectory:)` which finds the most recent session in that directory. If none exists, it stays idle — so this is safe for first-time contexts.

**History already filtered by repo**: `listSessions()` → `ListSessionsUseCase` → looks up sessions keyed to the working directory. Once the working directory equals the repo path (Phase 1), session history is automatically repo-scoped.

---

## - [x] Phase 4: Working directory selector in chat header

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Kept the selector local to the app-layer chat panel, rebuilt the chat model only while the session is still pre-start, and used the existing session-start signal to lock the working directory once conversation state exists.

**Skills to read**: (none specific)

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift`**

Expose `hasStartedSession` so the chat panel can lock the selector after first message:

```swift
// Change line ~32:
public private(set) var hasStartedSession: Bool = false
```

**File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/Chat/ContextualChatPanel.swift`**

1. Add state:
```swift
@State private var customWorkingDirectory: String? = nil
```

2. Add computed properties:
```swift
private var effectiveWorkingDirectory: String {
    customWorkingDirectory ?? context.chatWorkingDirectory
}

private var isSessionLocked: Bool {
    chatModel?.hasStartedSession == true
}
```

3. Reset on context change — in `.task(id: context.chatContextIdentifier)`, add `customWorkingDirectory = nil` before `rebuildChatModel()`.

4. Update `rebuildChatModel()` line 304:
```swift
workingDirectory: customWorkingDirectory ?? context.chatWorkingDirectory
```

5. Add folder button to `headerBar` (between `Text("Chat")` and `Spacer()`):
```swift
Button(action: selectWorkingDirectory) {
    Label(
        URL(fileURLWithPath: effectiveWorkingDirectory).lastPathComponent,
        systemImage: "folder"
    )
    .font(.caption)
    .foregroundStyle(isSessionLocked ? .tertiary : .secondary)
}
.buttonStyle(.plain)
.disabled(isSessionLocked)
.help(
    isSessionLocked
        ? "Working directory locked: \(effectiveWorkingDirectory)"
        : "Working directory: \(effectiveWorkingDirectory)\nClick to change"
)
```

6. Add action:
```swift
private func selectWorkingDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: effectiveWorkingDirectory)
    panel.prompt = "Select"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    customWorkingDirectory = url.path
    rebuildChatModel()
}
```

---

## - [x] Phase 5: Validation

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Validated the shipped Phase 1-4 behavior against the enforce practice rules, confirmed the Mac app target and Swift package still build successfully, and kept Phase 5 scoped to verification and documentation because the validation pass did not expose any additional code changes in the affected files.

**Skills to read**: `ai-dev-tools-enforce`

Run enforce on all changed files before marking complete.

**Manual checks:**
1. Build succeeds with no warnings in changed files.
2. Select a repo → open the Plans tab → open the chat panel. Folder button shows the repo name.
3. Run a Codex session. Inspect `~/.codex/sessions/2026/04/<day>/` — verify `cwd` in `session_meta` matches the repo path (not `/`).
4. Switch to the Chains tab — chat panel resets (blank, new context). Switch back to Plans — chat resumes the prior session.
5. Switch repos — chat panel resets to the new repo's context.
6. Close the chat panel on Plans tab. Quit and relaunch the app. Navigate to Plans — panel should remain closed. Open it — panel opens and resumes prior session.
7. Open panel on Chains tab. Quit and relaunch. Navigate to Chains — panel should be open and session resumed.
8. Open session history (clock icon) — verify only sessions from the current repo's path appear.
9. Click the folder button — NSOpenPanel appears. Pick a different directory. Folder label updates.
10. Send a message — folder button grays out (locked). Start a new conversation (pencil icon) — folder button re-enables.
