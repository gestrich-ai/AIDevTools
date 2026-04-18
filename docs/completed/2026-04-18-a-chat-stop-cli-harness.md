# Chat Stop & Session Continuity — CLI Test Harness

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-composition-root` | How CLI commands get their services |
| `ai-dev-tools-code-quality` | Force-unwrap, error handling conventions |
| `ai-dev-tools-swift-testing` | Test file conventions |

## Background

The chat stop/session feature has been broken across several dimensions:
- Hitting stop doesn't halt streaming output
- After stop, the next message starts a new session instead of resuming the current one

Every investigation required Bill to manually run the Mac app to verify behavior. The CLI `chat` command already wraps `SendChatMessageUseCase` — the same code path as `ChatModel`. The **interactive CLI mode** is the correct test harness because it mirrors the Mac app's in-process state exactly.

---

## Investigation Log

### Failed validation approaches

**Attempt 1 — OS signals (`gtimeout`, `kill -INT`)**
Sent SIGINT to the process. Does NOT trigger Swift cooperative cancellation. `withTaskCancellationHandler` never fires; `CancellationError` is never thrown; our catch blocks never run. Completely wrong code path.

**Attempt 2 — Two separate CLI invocations with `--cancel-after`**
```bash
.build/debug/ai-dev-tools-kit chat --cancel-after 5 "my color is blue..."
.build/debug/ai-dev-tools-kit chat --resume "what color?"
```
This appeared to work but was testing the wrong thing. The `--resume` flag picks up the latest session from disk. There is no race — the second process can't even start until the first one fully exits and its recovery code completes. This does not replicate what the Mac app does.

**Why this is wrong:** The Mac app and the CLI interactive loop both hold `sessionId` as an **in-process variable** that persists across turns. After a cancel, the UI is immediately unblocked — the user can send message 2 before the recovery code has set `sessionId`. Two separate CLI processes have no equivalent of this race.

### Correct test: interactive CLI mode

The interactive loop in `ChatCommand.runInteractive` is structurally identical to `ChatModel`:

```
ChatModel.sessionId                 ↔  var sessionId in runInteractive
ChatModel.cancelCurrentRequest()    ↔  Ctrl-C in the interactive loop
ChatModel.sendMessage()             ↔  typing the next line
```

The test that replicates the Mac app:

```bash
swift run ai-dev-tools-kit chat --provider claude
# > My favorite color is blue. Write a very long essay about blue in art history.
# [streaming starts...]
# Ctrl-C
# > What color did I say was my favorite?
# Expected: "Your favorite color is blue."
# Actual (broken): "I don't have context from a previous session."
```

### Root cause

`runInteractive` updates `sessionId` from `result.sessionId` after each message:
```swift
sessionId = result.sessionId ?? sessionId
```

When the message is cancelled, `useCase.run` throws `CancellationError` and never returns a result. `sessionId` stays `nil`. The next message sends with no session, starting a fresh conversation.

The same is true in `ChatModel.sendMessageInternal` — `sessionId` is only set when `result.sessionId` is available from a completed response.

### The fix

Set `sessionId` as soon as the provider's first stream event arrives with a session/thread ID — before any cancel can happen. Claude CLI emits `{"type":"system","session_id":"..."}` as its very first stdout line. Codex emits `{"type":"thread.started","thread_id":"..."}` in its first output. Capturing those IDs immediately means cancellation can never lose the session.

Add `case sessionStarted(String)` to `AIStreamEvent`. Emit it from both formatters when they see those first events. Handle it in `ChatModel.consumeStream` and in `runInteractive`'s progress callback to update `sessionId` in-place.

---

## Validation Process

Every fix attempt must pass all three steps before being called done. Step 1 is the primary gate — if it fails, the fix is wrong regardless of what else appears to work.

### Step 1 — Interactive mode, Ctrl-C, follow-up (primary gate)

```bash
swift run ai-dev-tools-kit chat --provider claude
```
In the interactive prompt:
1. Type: `My favorite color is blue. Write a very long essay about blue in art history.`
2. Press Ctrl-C after streaming starts (within the first 10 seconds)
3. Type: `What color did I say was my favorite? One sentence.`

**Pass**: Response is "Your favorite color is blue."
**Fail**: Response says it has no prior context.

Repeat for `--provider codex`.

### Step 2 — Early cancel (before first token arrives)

Same as Step 1 but press Ctrl-C within 2 seconds of sending (before any text appears). Verifies the session ID was captured from the first stream event, not from later output.

**Pass**: Follow-up still knows "blue."

### Step 3 — Confirm in Mac app

After Steps 1 and 2 pass in the CLI, run the same flow manually in the Mac app:
1. Send a long-essay prompt
2. Click Stop before any response text appears
3. Ask "What was the topic of my previous message?"
4. Confirm the AI has context

Only after all three steps pass is the fix complete.

---

## Phases

## - [x] Phase 1: Add `sessionStarted` to AIStreamEvent

**Skills to read**: `ai-dev-tools-architecture`

Add `case sessionStarted(String)` to `AIStreamEvent` in `AIOutputSDK`.

In `ClaudeStreamFormatter.formatStructured`, emit `.sessionStarted(sessionId)` when parsing `{"type":"system","session_id":"..."}`.

In the Codex formatter, emit `.sessionStarted(threadId)` when parsing `{"type":"thread.started","thread_id":"..."}`.

## - [x] Phase 2: Handle `sessionStarted` in ChatModel and runInteractive

**Skills to read**: `ai-dev-tools-code-quality`

In `ChatModel.consumeStream`, handle the new case:
```swift
case .sessionStarted(let id):
    await MainActor.run {
        self.sessionId = id
        self.hasStartedSession = true
    }
```

In `ChatCommand.runInteractive`'s progress callback, handle it:
```swift
case .sessionStarted(let id):
    sessionId = id
```

This sets `sessionId` within seconds of a message starting — before any Ctrl-C can lose it.

## - [x] Phase 3: Add Ctrl-C handling to interactive loop

**Skills to read**: `ai-dev-tools-code-quality`

Currently Ctrl-C kills the entire process. Change it to cancel only the in-flight request and loop back to the prompt, preserving `sessionId`.

1. Wrap each `useCase.run(...)` in a stored `Task`
2. Install a `DispatchSource` SIGINT handler before the loop that cancels the task and prints `\n[Cancelled]` without exiting
3. Remove the handler when the loop exits

## - [x] Phase 4: Validate with the three-step process

Run all three validation steps in order. Step 1 must pass before proceeding.

## - [x] Phase 5: Cleanup

Remove the async session-lookup recovery block from `sendMessageInternal`'s catch clause — it is racy and no longer needed once session IDs are captured early. Keep the `session_index.jsonl` writes in both provider catch blocks as a last-resort fallback (e.g., process killed before first event).

Run `swift build` and `swift test`. Confirm no regressions.
