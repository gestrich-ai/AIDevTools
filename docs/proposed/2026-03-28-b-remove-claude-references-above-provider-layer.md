## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) — guides where provider-specific code belongs |

## Background

Recent completed specs (last 24 hours) have been steadily abstracting provider-specific code behind the `AIClient` protocol and `ProviderRegistry`:

- **2026-03-27-a** — Moved concrete SDK imports out of Features/EvalSDK
- **2026-03-27-b** — Provider commoditization: replaced hardcoded `Provider` enum with dynamic registry
- **2026-03-27-a (chat)** — Removed provider-specific chat code paths from Mac UI
- **2026-03-28-a** — ChatManager → Model-View architecture
- **2026-03-28-b** — Plugin-style provider architecture for evals

Despite this progress, several "claude" references remain above the provider layer. These fall into distinct categories:

### References found and their assessment

**App Layer — Hardcoded `"claude"` string defaults (REMOVE):**
1. `ChatCommand.swift:13-14` — default provider `"claude"` + help text
2. `WorkspaceView.swift:32` — `@AppStorage("chatProviderName") = "claude"`
3. `ArchitecturePlannerDetailView.swift:7` — `@AppStorage("archPlannerProviderName") = "claude"`

**App Layer — Hardcoded `ClaudeStreamFormatter()` (REMOVE):**
4. `ShowOutputCommand.swift:59` — fallback formatter
5. `ShowOutputCommand.swift:65` — rubric formatter
6. `EvalRunnerModel.swift:237` — fallback formatter
7. `EvalRunnerModel.swift:244` — rubric formatter

**App Layer — Provider-specific user-facing text (REMOVE):**
8. `MarkdownPlannerExecuteCommand.swift:125` — `"Running claude..."`
9. `MessageInputWithAutocomplete.swift:39` — `"Ask Claude anything..."`
10. `ShowOutputCommand.swift:29` — help text `"(e.g. claude, codex)"`

**App Layer — Direct `ClaudeProvider` usage in view (REMOVE):**
11. `ChatSessionDetailView.swift:74` — `ClaudeProvider().getSessionDetails()` bypasses registry

**Features Layer — Claude-specific variable names and comments (REMOVE):**
12. `GeneratePlanUseCase.swift:177,186,248-250` — `readClaudeMd`, `claudeMdContent`, `claudeMdURL`
13. `ExecutePlanUseCase.swift:266` — `// MARK: - Claude Calls`
14. `CompileFollowupsUseCase.swift:7,86` — comments "uses Claude to..."
15. `PlanAcrossLayersUseCase.swift:193` — comment "from the guidelines Claude referenced"

**SDK Layer — `.claude/` directory paths in SkillScanner (KEEP):**
16. `SkillScanner.swift:7-8,11` — `.claude/commands`, `.claude/skills`, `~/.claude/commands`
    These are **real filesystem paths** for Claude Code's directory convention. Removing them would break skill discovery. They should stay.

**App Layer — `import ClaudeCLISDK` + `ClaudeProvider()` in DI wiring (KEEP):**
17. `CLIRegistryFactory.swift`, `CompositionRoot.swift`, `ProviderModel.swift`, etc.
    These are **expected** — the App layer is where concrete SDKs are registered. This is correct per the architecture.

## - [x] Phase 1: Replace hardcoded `"claude"` string defaults with registry default provider

**Skills to read**: `swift-architecture`

Replace three hardcoded `"claude"` default strings with dynamic first-provider resolution from the registry.

**Files to modify:**

1. **`ChatCommand.swift`** (lines 13-14):
   - Change default from `"claude"` to `nil` (optional)
   - Resolve to first registered provider at runtime: `let resolvedProvider = provider ?? makeProviderRegistry().providers.first?.name ?? "claude"`
   - Update help text from `"(default: claude)"` to `"(default: first registered)"`

2. **`WorkspaceView.swift`** (line 32):
   - Change `@AppStorage("chatProviderName") private var chatProviderName: String = "claude"` to default to empty string `""`
   - At usage site, resolve empty string to `providerModel.availableProviders.first?.name ?? ""`

3. **`ArchitecturePlannerDetailView.swift`** (line 7):
   - Same pattern: change `@AppStorage("archPlannerProviderName") = "claude"` to default to empty string
   - Resolve at usage site from available providers

**Expected outcome:** No hardcoded `"claude"` strings as defaults. Users who already have `"claude"` stored in AppStorage continue working. New users get whatever provider is registered first.

## - [x] Phase 2: Remove `ClaudeStreamFormatter` hardcoding from App layer

**Skills to read**: `swift-architecture`

Four call sites in the App layer hardcode `ClaudeStreamFormatter()` as a fallback or rubric formatter. Since `EvalCapable` already exposes `streamFormatter`, these should use the registry.

**Files to modify:**

1. **`ShowOutputCommand.swift`** (lines 58-65):
   - The main formatter fallback (`?? ClaudeStreamFormatter()`) should use the matched provider's formatter or fail with an error if the provider isn't found (the provider name is required, so it should always match)
   - The rubric formatter should also come from the matched provider (rubrics are run through the same provider), or from a designated rubric provider entry in the registry
   - Remove `import ClaudeCLISDK` if no other Claude references remain

2. **`EvalRunnerModel.swift`** (lines 236-244):
   - Same pattern: resolve both `formatter` and `rubricFormatter` from the registry entry's `client.streamFormatter`
   - Remove `import ClaudeCLISDK` if no other Claude references remain

**Expected outcome:** `ClaudeStreamFormatter` is only instantiated inside `ClaudeCLISDK`. App layer uses the `streamFormatter` property from the protocol.

## - [x] Phase 3: Fix provider-specific user-facing text and direct provider usage

1. **`MarkdownPlannerExecuteCommand.swift:125`** — Change `"Running claude...\n"` to `"Running AI...\n"` or use the provider's display name if available from context

2. **`MessageInputWithAutocomplete.swift:39`** — Change `"Ask Claude anything..."` to `"Ask anything..."` or `"Send a message..."`

3. **`ShowOutputCommand.swift:29`** — Change help text from `"Provider name (e.g. claude, codex)"` to `"Provider name"` (provider names are discoverable from the registry; no need to enumerate examples)

4. **`ChatSessionDetailView.swift`** (lines 4, 11, 74, 90):
   - This view directly constructs `ClaudeProvider()` and uses the Claude-specific `ClaudeSessionDetails` type
   - The session detail reading should be abstracted: add a `SessionDetailProvider` capability (or similar) that `ClaudeProvider` can conform to, and have the view resolve the provider from context rather than constructing one directly
   - If abstracting is too large a change for this scope, at minimum get the provider from the registry/environment instead of constructing `ClaudeProvider()` directly

**Expected outcome:** No provider-specific names in user-facing strings. Session detail view doesn't directly construct a concrete provider.

## - [x] Phase 4: Rename Claude-specific variables and comments in Features layer

**Files to modify:**

1. **`GeneratePlanUseCase.swift`** (lines 177, 186, 248-250):
   - Rename `readClaudeMd` → `readProjectInstructions`
   - Rename `claudeMdContent` → `projectInstructions`
   - Rename `claudeMdURL` → `instructionsURL`
   - Keep reading the file `CLAUDE.md` — that's the real filename convention. The variable names just shouldn't carry the provider name.
   - Update the prompt interpolation label from `"CLAUDE.md contents:"` to keep it since it's describing the actual file being read (this is the file's real name, acceptable to reference in prompt text)

2. **`ExecutePlanUseCase.swift:266`**:
   - Change `// MARK: - Claude Calls` → `// MARK: - AI Calls`

3. **`CompileFollowupsUseCase.swift:7,86`**:
   - Line 7: Change "then uses Claude to identify..." → "then uses AI to identify..."
   - Line 86: Change "Use Claude to identify..." → "Use AI to identify..."

4. **`PlanAcrossLayersUseCase.swift:193`**:
   - Change "from the guidelines Claude referenced" → "from the referenced guidelines"

**Expected outcome:** No "claude" references in Features layer code or comments (outside of the `CLAUDE.md` filename string which is a real file).

## - [x] Phase 5: Validation

Run the full build and search for remaining inappropriate references:

```bash
cd /Users/bill/Developer/personal/AIDevTools && swift build 2>&1
```

```bash
# Verify no claude references remain in Features layer (except CLAUDE.md filename string)
grep -ri "claude" AIDevToolsKit/Sources/Features/ --include="*.swift" | grep -v "CLAUDE.md"

# Verify no ClaudeStreamFormatter references in Apps layer
grep -r "ClaudeStreamFormatter" AIDevToolsKit/Sources/Apps/ --include="*.swift"

# Verify no hardcoded "claude" string defaults in Apps layer
grep -rn '"claude"' AIDevToolsKit/Sources/Apps/ --include="*.swift"
```

```bash
# Run tests
swift test 2>&1
```

**Expected outcome:** Build succeeds, tests pass, grep searches return no unexpected matches. Only remaining "claude" references in non-provider code are: (1) `CLAUDE.md` filename strings in prompts, (2) `.claude/` directory paths in SkillScanner, (3) `import ClaudeCLISDK` / `ClaudeProvider()` in App-layer DI wiring.