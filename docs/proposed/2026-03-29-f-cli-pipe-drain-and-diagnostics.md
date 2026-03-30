## Background

Plan phases report "Phase N failed: Claude CLI returned no result event" even when Claude actually completed the work, committed changes, and returned `{"success": true}`. This leads to painful debugging because the phase is marked failed even though the git commit exists.

## Root Cause

`CLIClient.execute()` in SwiftCLI uses `readabilityHandler` to stream stdout into a `StdoutAccumulator`. This handler is GCD-dispatched on a background thread. The sequence that causes data loss:

1. Claude CLI writes its final events (StructuredOutput call, result event) to the pipe
2. `process.waitUntilExit()` returns — the process is gone
3. `readabilityHandler = nil` is set — **this fires immediately, before GCD delivers the last readability notifications**
4. The final events never reach `stdoutAccumulator`
5. `ClaudeStructuredOutputParser.findResultEvent()` scans `result.stdout` and finds no `type=result` line
6. `noResultEvent` error is thrown and the phase is logged as failed

The data was written to the pipe by Claude. It just wasn't read before the handler was removed.

### Evidence From the Failing Run (2026-03-29, session 99f4b1cd)

The session JSONL at `~/.claude/projects/-Users-bill-Developer-personal-AIDevTools/99f4b1cd-94bd-4161-9c12-155f29e0bf41.jsonl` showed:

- Line 262: TodoWrite tool result ("Todos have been modified successfully...") — **this was the last event in `stdout_tail`**
- Lines 263–275: document update, git commit, StructuredOutput `{"success": true}`, and the result event
- The plan runner's `result.stdout` had 515 lines and 1.6MB — ending at session line 262, missing the final 13 events

The `stdout_tail` in the error log showed the TodoWrite result as the last captured content, confirming the accumulator stopped before the session ended.

## The Fix

### SwiftCLI — `CLIClient.swift` (commit `ee7f06b`)

After `waitUntilExit()`, nil the handlers first (which waits for in-flight GCD callbacks to drain), then synchronously read any remaining bytes from the pipe:

```swift
process.waitUntilExit()
timeoutTask?.cancel()

// Nil handlers first — waits for any in-flight GCD callbacks to complete
outputPipe?.fileHandleForReading.readabilityHandler = nil
errorPipe?.fileHandleForReading.readabilityHandler = nil

// Drain remaining bytes that arrived after the last readabilityHandler invocation
if let outPipe = outputPipe,
   let text = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
   !text.isEmpty {
    stdoutAccumulator.append(text)
    if shouldPrint { print(text, terminator: "") }
}
if let errPipe = errorPipe,
   let text = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
   !text.isEmpty {
    stderrAccumulator.append(text)
}
```

**Note:** The drained bytes are added to `stdoutAccumulator` (so `result.stdout` and `result.stderr` in `ExecutionResult` include them) but are **not** forwarded to the stream callbacks (`commandContinuation`, `globalOutputStream`, `clientOutputStream`). This means the phase `.stdout` log file will still be missing the final events — but the parser will find the result event and the phase will succeed.

### AIDevTools — `ClaudeStructuredOutputParser.swift`

Improved diagnostics logged to `~/Library/Logs/AIDevTools/aidevtools.log` under label `ClaudeStructuredOutputParser`.

**Envelope decode failures** now log `line_preview` (500 chars, up from 200) and `line_length` (full character count):
```
label: ClaudeStructuredOutputParser, level: error
message: Failed to decode event envelope: ...
metadata: { line_preview: "...", line_length: "12483" }
```

**Result event decode failures** are now tracked separately. Previously, if a `type=result` line was present but failed `decode(ClaudeResultEvent.self)`, it was silently swallowed — the phase would fail with `noResultEvent` even though a result line existed. Now:
- `resultEventDecodeFailures` counter added to `ProcessDiagnostics`
- Appears as `result_decode_failures=N` in the error log message
- Logged at error level with `line_preview` and `line_length`

**`stdout_tail`** now captures the last 1000 characters of stdout (instead of joining the last 5 lines and taking 500 chars). The old approach could show an early event if the last few lines were very long; the new approach always shows the true end of the stream.

## How To Debug Next Time

### Step 1 — Check the structured error log

```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log \
  | jq 'select(.label == "MarkdownPlanner" and .level == "error")'
```

Key fields in the `noResultEvent` message:
- `events=[assistant:X system:Y user:Z]` — if `result` is absent from this list, the result event was not captured at all (pipe drain issue or process died early)
- `result_decode_failures=N` — a result line existed but couldn't be decoded; look at the `ClaudeStructuredOutputParser` logs for what the line contained
- `json_failures=N` — N lines in the stream weren't valid JSON; likely a truncated final write if N=1
- `stdout_tail` — now shows the last 1000 chars; if this ends mid-JSON or shows a much earlier event than expected, the pipe was drained too early

### Step 2 — Check the parser decode failures

```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log \
  | jq 'select(.label == "ClaudeStructuredOutputParser" and .level == "error")'
```

- `line_length` tells you how long the failing line actually was — a length of 200 (the old cap) was ambiguous; now you can tell if it was truncated mid-write (short) vs a legitimately malformed event (arbitrary length)
- `line_preview` gives 500 chars of context

### Step 3 — Cross-reference with the session JSONL

The session ID is in the error log (`session=<uuid>`). Find the session:

```bash
ls ~/.claude/projects/-Users-bill-Developer-personal-AIDevTools/<session-id>.jsonl
```

Check the last few lines to confirm whether Claude completed and returned StructuredOutput:

```bash
tail -5 ~/.claude/projects/-Users-bill-Developer-personal-AIDevTools/<session-id>.jsonl \
  | jq '.message.content[]? | select(.type == "tool_use" and .name == "StructuredOutput") | .input'
```

If StructuredOutput with `success: true` is present, Claude finished — the failure was in the capture layer (pipe drain), not in Claude's execution. Check the SwiftCLI fix is in place.

### Step 4 — Check the phase stdout log

```bash
cat ~/Desktop/ai-dev-tools/AIDevTools/plan-logs/<plan-name>/phase-N.stdout | tail -50
```

If the log ends well before where the session JSONL ends (e.g., cuts off at an early tool result), the drain bytes were still not forwarded to the stream callbacks. This is a known limitation of the current fix — the drain reaches `result.stdout` but not the phase log file.

## Known Remaining Gaps

1. **Drained bytes not forwarded to stream callbacks** — the phase `.stdout` log file will still be missing final events even after the fix. The parser will succeed, but the log won't show Claude's summary or the StructuredOutput call. A future improvement would forward drained bytes through the same stream pipeline.

2. ~~No drain byte count in diagnostics~~ — **Fixed (2026-03-30).** `ExecutionResult.drainByteCount` added to SwiftCLI (commit `39e0a4d`). Threaded through `ProcessDiagnostics` in AIDevTools and emitted as `drain_bytes=N` in the `MarkdownPlanner` error log.

## Second Failure (2026-03-30) — Drain Fix Did Not Prevent Truncation

The drain fix (ee7f06b) was in place but the failure recurred: session `8f86fc8f` (plan `2026-03-29-h-mcp-server-and-unix-socket-ipc.md`, Phase 6). Claude returned `{"success": true}` (confirmed via session JSONL), but the plan runner still threw `noResultEvent`.

### What the logs showed

```
Phase 6 failed: ... exit=0, stdout=331 lines/897675 bytes,
events=[assistant:189 system:16 user:125], json_failures=1,
session=8f86fc8f-...
stdout_tail: ...{"type":"assistant",...,"stop_reason":null,...}
             {"type":"assistant","name":"TodoWrite","input":{"todos":[...,"activeForm":"Making handleCallTool i
```

- `json_failures=1` — one JSONL line was truncated (partial TodoWrite event, 372 chars)
- No `result` in `events` list — result event was never captured
- `stdout_tail` ends mid-JSON at that 372-char boundary
- Session JSONL confirmed Claude completed with `{"success": true}`

### Hypothesis: `readabilityHandler = nil` does not synchronize in-flight GCD callbacks

The drain fix assumes that setting `readabilityHandler = nil` blocks until all in-flight GCD callbacks finish before `readDataToEndOfFile()` runs. This may not hold. The suspected sequence:

1. A GCD readability callback fires and calls `handle.availableData`
2. `availableData` reads ALL remaining bytes from the kernel pipe buffer (including the result event)
3. `readabilityHandler = nil` is set — cancels future dispatches but does NOT wait for step 2 to finish
4. `readDataToEndOfFile()` runs — kernel pipe buffer is now empty → returns 0 bytes
5. The GCD callback from step 2 eventually finishes and appends its bytes to `stdoutAccumulator`...
6. ...but `stdoutAccumulator.value` was already read into `result.stdout` before step 5 completes
7. Result: the result event is in the accumulator but was never included in `result.stdout`

### What to check next time this happens

**Step 1 — Check `drain_bytes` in the error log:**

```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log \
  | jq 'select(.label == "MarkdownPlanner" and .level == "error")'
```

Look for `drain_bytes=N` in the message:

- **`drain_bytes=0` + `json_failures>0`** → confirms the race: the kernel pipe buffer was empty when the drain ran, meaning a concurrent GCD callback already consumed the bytes. The hypothesis is correct — fix `readabilityHandler` synchronization.
- **`drain_bytes>0` + `json_failures>0`** → the drain captured bytes but the result event is still missing. The problem is downstream of the drain (e.g., the drained bytes are malformed, or the parser has a bug). Look at the `ClaudeStructuredOutputParser` logs.
- **`drain_bytes>0` + no `json_failures`** → drain worked, but the result event still wasn't found. Check `result_decode_failures`.

**Step 2 — Confirm Claude actually finished (session JSONL):**

The session ID is in the error log. Check whether Claude returned `StructuredOutput`:

```bash
tail -5 ~/.claude/projects/-Users-bill-Developer-personal-AIDevTools/<session-id>.jsonl \
  | jq '.message.content[]? | select(.type == "tool_use" and .name == "StructuredOutput") | .input'
```

If `{"success": true}` is present, Claude finished — the failure is purely in the capture layer, not in Claude's execution. The committed changes are real and the phase can be re-run (or the plan markdown updated manually).

### If `drain_bytes=0` is confirmed — the proper fix

`readabilityHandler = nil` alone is not a synchronization barrier for in-flight callbacks. The correct fix in SwiftCLI's `CLIClient` is to dispatch the readabilityHandler on a **dedicated serial `DispatchQueue`**, then call `queue.sync {}` on that same queue after niling. Because the queue is serial, `queue.sync {}` will not return until any currently-executing callback block completes:

```swift
// Setup
let outputQueue = DispatchQueue(label: "com.swiftcli.stdout-drain")
outPipe.fileHandleForReading.readabilityHandler = { handle in ... }  // dispatches on outputQueue

// After waitUntilExit():
outPipe.fileHandleForReading.readabilityHandler = nil
outputQueue.sync {}  // blocks until any in-flight callback on this queue finishes

// Now drain is safe — no concurrent reader
if let text = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
   !text.isEmpty {
    stdoutAccumulator.append(text)
}
```

Once this fix is implemented and confirmed stable, `ExecutionResult.drainByteCount`, `ProcessDiagnostics.drainByteCount`, and the `drain_bytes` summary entry can all be removed.
