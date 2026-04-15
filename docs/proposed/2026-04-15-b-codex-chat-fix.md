## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — ensures changes stay in the right layer |
| `ai-dev-tools-code-quality` | Flags force unwraps, raw strings, fallback values |
| `ai-dev-tools-enforce` | Post-change verification step |

## Background

The app supports both Claude CLI and Codex CLI as AI providers. The Claude CLI path is fully wired: `ClaudeProvider+AIClient.run` emits `AIStreamEvent` values (text, thinking, toolUse, toolResult, metrics) that propagate through `SendChatMessageUseCase` and then to the `ChatCommand` CLI or Mac app UI.

The Codex path has two compounding problems:

**Problem 1 – Codex hangs when invoked from the app.**  
`CodexProvider.executeCodex` does not pass `stdin` to `CLIClient`. When `CLIClient` leaves stdin unset, the subprocess inherits the parent's stdin. Codex detects a non-TTY stdin and reads from it, blocking forever because the parent never writes to or closes that pipe. Fix: pass `stdin: Data()` to `CLIClient.execute` so stdin is a pipe that's immediately closed, giving Codex an EOF.

Additionally, `CodexProvider` has no inactivity watchdog. Claude has a 480-second timeout; Codex has none. Add one to fail fast if Codex silently stops producing output.

**Problem 2 – No stream events reach the chat UI.**  
`CodexProvider+AIClient.run` accepts an `onStreamEvent` callback but ignores it entirely. It only uses `onFormattedOutput`, and `SendChatMessageUseCase` passes `onOutput: nil`, so all Codex output is silently dropped. The `CodexStreamFormatter` also has no `formatStructured()` method (unlike `ClaudeStreamFormatter`), so there is no path from raw JSONL → `AIStreamEvent`.

Additionally, `command.json` is only set to `true` for structured-output runs; plain chat runs don't pass `--json`, so Codex emits interactive styled text instead of machine-readable JSONL.

**Problem 3 – `ChatCommand` only displays `textDelta` events.**  
Even for Claude, the CLI chat command prints only text. Thinking blocks, tool use, tool results, and metrics are silently dropped. Once Codex is wired up to emit events, the CLI command should render all block types so the output matches what the Mac app shows.

**Confirmed Codex JSONL event types** (from `codex exec --json`):
- `{"type":"thread.started","thread_id":"..."}` — ignored (no user-visible content)
- `{"type":"turn.started"}` — ignored
- `{"type":"item.completed","item":{"type":"agent_message","text":"..."}}` → `AIStreamEvent.textDelta`
- `{"type":"item.completed","item":{"type":"command_execution","command":"...","aggregated_output":"...","exit_code":0}}` → `AIStreamEvent.toolUse` + `AIStreamEvent.toolResult`
- `{"type":"turn.completed","usage":{"input_tokens":N,"cached_input_tokens":N,"output_tokens":N}}` → `AIStreamEvent.metrics`

## Phases

## - [x] Phase 1: Fix Codex hang — close stdin and add inactivity timeout

**Skills used**: none
**Principles applied**: Added `ConcurrencySDK` to `CodexCLISDK` package dependencies; added `CodexCLIError` with `.inactivityTimeout` case; refactored `executeCodex` to always create a `CLIOutputStream` (matching `ClaudeProvider` pattern) so activity is recorded unconditionally; passed `stdin: Data()` to give Codex an immediate EOF; mirrored the `withThrowingTaskGroup` + `InactivityWatchdog` pattern from `ClaudeProvider` verbatim with a 120s timeout.

**Skills to read**: none

Fix `CodexProvider.executeCodex` so Codex doesn't block on stdin and fails gracefully if it stops producing output.

**Tasks:**
- In `CodexProvider.executeCodex`, pass `stdin: Data()` to `CLIClient.execute`. `CLIClient` creates a pipe, writes zero bytes, then closes it immediately — Codex receives EOF and proceeds.
- Add an inactivity watchdog to `CodexProvider` mirroring `ClaudeProvider`. Use the same `InactivityWatchdog` type (already a dependency). Timeout value: 120 seconds (Codex runs are shorter than Claude's).
- Add a `CodexCLIError` enum with a `.inactivityTimeout(seconds: Int)` case (parallel to `ClaudeCLIError`).
- Wire the watchdog into `executeCodex` the same way `ClaudeProvider.run` does it (record activity on each `StreamOutput`, throw on timeout).

Files to modify:
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider.swift`

## - [x] Phase 2: Always use `--json` for chat runs and add `--color never`

**Skills used**: none
**Principles applied**: Added `--color` option to both `Codex.Exec` and `Codex.Exec.Resume` in alphabetical property order. Set `command.json = true` unconditionally (removed the conditional guards that only set it for schema runs) and set `command.color = "never"` in both `run` and `runResume`. The `runStructured` path already had `json = true` and didn't need `color` since its output is parsed structurally.

**Skills to read**: none

Without `--json`, Codex emits styled terminal output that our formatter cannot parse. Without `--color never`, ANSI escape codes can leak into JSONL.

**Tasks:**
- In `CodexCLI.swift`, add `@Option("--color") public var color: String?` to `Codex.Exec` and `Codex.Exec.Resume`.
- In `CodexProvider+AIClient.run`, set `command.json = true` unconditionally (not just when `outputSchema` is set) and set `command.color = "never"`.
- In `CodexProvider+AIClient.runResume`, set `command.color = "never"` similarly.

Files to modify:
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexCLI.swift`
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider+AIClient.swift`

## - [x] Phase 3: Add `formatStructured()` to `CodexStreamFormatter`

**Skills used**: none
**Principles applied**: Added `formatStructured()` and private `parseStreamEvents()`/`parseItemStreamEvents()` helpers mirroring the `ClaudeStreamFormatter` pattern. Reused the existing private model structs unchanged. `agent_message` maps to `.textDelta`, `command_execution` maps to `.toolUse` + `.toolResult`, and `turn.completed` maps to `.metrics(duration: nil, cost: nil, turns: nil)`. All other event types are dropped.

**Skills to read**: none

`ClaudeStreamFormatter` has both `format()` (plain text) and `formatStructured()` (`[AIStreamEvent]`). `CodexStreamFormatter` only has `format()`. Add `formatStructured()` that maps the confirmed Codex JSONL event types to `AIStreamEvent`.

Mapping:
- `item.completed` / `agent_message` → `.textDelta(text)` (skip empty text)
- `item.completed` / `command_execution` → `.toolUse(name: "bash", detail: command)` followed by `.toolResult(name: "bash", summary: aggregatedOutput, isError: exitCode != 0)`
- `turn.completed` → `.metrics(duration: nil, cost: nil, turns: nil)` (Codex reports token counts, not duration/cost/turns; all-nil is acceptable — it still signals completion)
- All other types (`thread.started`, `turn.started`, etc.) → dropped

**Tasks:**
- Add `public func formatStructured(_ rawChunk: String) -> [AIStreamEvent]` to `CodexStreamFormatter`.
- Extract a private `parseStreamEvents(_ data: Data) -> [AIStreamEvent]` to keep the logic parallel with `ClaudeStreamFormatter`.
- Update private model structs as needed to decode `turn.completed` usage and `agent_message`/`command_execution` items.

Files to modify:
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexStreamFormatter.swift`

## - [x] Phase 4: Wire `onStreamEvent` through `CodexProvider`

**Skills to read**: none

`CodexProvider` needs to call `onStreamEvent` as it streams output, just like `ClaudeProvider` does.

**Tasks:**
- Add `onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?` parameter to `CodexProvider.runFormatted` and `CodexProvider.executeCodex`.
- Inside the `onOutput` block in `executeCodex`, after calling `formatter.format(text)` for stdout, also call `formatter.formatStructured(text)` and emit each resulting event via `onStreamEvent`.
- Update `CodexProvider+AIClient.run` and `runResume` to pass through `onStreamEvent` from the `AIClient` protocol call.
- The `run(command:onOutput:)` overloads (non-formatted) do not need to change.

Files to modify:
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider.swift`
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider+AIClient.swift`

## - [x] Phase 5: Update `ChatCommand` to display all block types

**Skills used**: none
**Principles applied**: Added `printStreamEvent(_:)` private helper covering all `AIStreamEvent` cases. Metrics fields are assembled into a parts array and joined, silently omitting nil fields. Replaced the inline `if case .textDelta` checks in both `sendMessage` and `runInteractive` with calls to the new helper.

**Skills to read**: none

`ChatCommand.sendMessage` and `ChatCommand.runInteractive` only print `.textDelta` events. Thinking, tool use, tool results, and metrics are dropped. Update both paths to print all event types.

**Tasks:**
- In `ChatCommand`, add a private helper `printStreamEvent(_ event: AIStreamEvent)` that prints each event type in a human-readable format matching the Mac app's rendering intent:
  - `.textDelta(text)` → `print(text, terminator: "")` (existing behavior, no newline)
  - `.thinking(text)` → `print("\n[Thinking] \(text)")` 
  - `.toolUse(name, detail)` → `print("\n[\(name)] \(detail)")`
  - `.toolResult(name, summary, isError)` → `print("  → \(summary)")`
  - `.metrics(duration, cost, turns)` → print a summary line (e.g. `"--- \(duration)s | $\(cost) | \(turns) turns ---"`, skipping nil fields)
- Replace the inline switch in both `sendMessage` and `runInteractive` with calls to `printStreamEvent`.

Files to modify:
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/ChatCommand.swift`

## - [ ] Phase 6: CLI verification

**Skills to read**: `ai-dev-tools-debug`

Build and run the CLI to confirm the fix end-to-end.

**Tasks:**
- Build the CLI target: `swift build --target AIDevToolsKitCLI -c debug` from `AIDevToolsKit/`.
- Run a single-message chat with Codex: `.build/debug/aidevtools chat --provider codex "Say hello in one sentence."`
- Confirm: (a) no hang, (b) a text response appears, (c) the session completes.
- Run a prompt that exercises tool use: `"List the files in the current directory."` — confirm `[bash]` and tool result lines appear.
- Run the same prompts with `--provider claude` to confirm no regression.

## - [ ] Phase 7: Enforce and validate

**Skills to read**: `ai-dev-tools-enforce`

Run the enforce skill on all changed files to catch any architecture violations, code quality issues, or style problems introduced during this work.

Files changed during this plan:
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexCLI.swift`
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider.swift`
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexProvider+AIClient.swift`
- `AIDevToolsKit/Sources/SDKs/CodexCLISDK/CodexStreamFormatter.swift`
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/ChatCommand.swift`
