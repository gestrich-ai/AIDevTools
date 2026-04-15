---
name: ai-provider
description: Reference for where Claude and Codex provider data is stored on disk — session logs, raw output, thinking/reasoning availability, and format differences between the two providers. Use whenever investigating provider output, debugging missing thinking blocks, reading session history, or asking "where does X get stored for Claude vs Codex?"
---

# AI Provider Storage Reference

## Claude

### Session logs
`~/.claude/projects/<path-based-id>/<session-id>.jsonl`

The path-based ID is derived from the working directory (e.g., `-Users-bill-Developer-personal-AIDevTools`). Each line is a structured JSONL event covering tool calls, text output, thinking, and metrics.

### App-level logs
`~/Library/Logs/AIDevTools/aidevtools.log`

Structured JSON log used by the Mac app and CLI. Filter with `jq` by `label` field.

### Eval artifacts (raw provider output)
`~/Desktop/ai-dev-tools/services/evals/AIDevTools/artifacts/raw/claude/<suite>.<case-id>.stdout`

Only written during eval runs, not during chat sessions.

### Thinking blocks
Claude thinking blocks **are** present in the exec stream as plain text events and are fully parseable. The `ClaudeStreamFormatter.formatStructured()` emits `.thinking(text)` events which the Mac app renders as purple collapsible blocks.

---

## Codex

### Native session logs
`~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`

Codex writes a session file for every invocation — both from the native TUI (`originator: "codex-tui"`) and from `codex exec` (`originator: "codex_exec"`). Each line is a rich event object.

Key event types in the native format:
- `session_meta` — session ID, model, cwd, CLI version
- `turn_context` — model, effort, sandbox policy
- `event_msg` / `agent_message` — final text responses
- `response_item` / `reasoning` — **encrypted** thinking content (see below)
- `event_msg` / `token_count` — usage stats

### Eval artifacts (raw exec stream output)
`~/Desktop/ai-dev-tools/services/evals/AIDevTools/artifacts/raw/codex/<suite>.<case-id>.stdout`

Only written during eval runs. Uses the `codex exec --json` stream format (different from the native session format).

### Chat sessions from the Mac app and CLI
`CLIClient` always passes `stdin: Data()` (a pipe with immediate EOF). Codex detects the non-TTY stdin and skips writing both the session rollout file and the `session_index.jsonl` entry.

To work around this, `CodexProvider+AIClient.run()` manually appends an entry to `session_index.jsonl` after each successful run, using the `thread_id` parsed from the `thread.started` exec stream event. This makes sessions appear in the history picker.

**What works**: history listing, session resuming (thread_id is returned as `AIClientResult.sessionId`).  
**What doesn't**: loading full message content from a past session — the rollout file in `~/.codex/sessions/` is never written, so `loadMessages` returns empty.

### Thinking/Reasoning blocks
Codex reasoning is **encrypted** and **not available** in the `codex exec --json` stream:

- In native session files: appears as `{"type":"response_item","payload":{"type":"reasoning","encrypted_content":"gAAAAA..."}}` — the content is opaque ciphertext, cannot be decrypted or displayed.
- In `codex exec --json` stream output: reasoning events are **not emitted at all** — only `item.completed` and `turn.completed` appear.

**Conclusion: Codex thinking blocks cannot be displayed.** Do not attempt to infer thinking from `agent_message` content.

---

## Format comparison: exec stream vs native session

The `codex exec --json` stream (what `CodexStreamFormatter` parses) uses a different format than the native session JSONL:

| Event | Exec stream format | Native session format |
|-------|-------------------|----------------------|
| Text response | `{"type":"item.completed","item":{"type":"agent_message","text":"..."}}` | `{"type":"event_msg","payload":{"type":"agent_message","message":"..."}}` |
| Tool execution | `{"type":"item.completed","item":{"type":"command_execution",...}}` | Similar but in `response_item` |
| Thinking | Not present | `{"type":"response_item","payload":{"type":"reasoning","encrypted_content":"..."}}` |
| Usage | `{"type":"turn.completed","usage":{"input_tokens":N,"output_tokens":N}}` | `{"type":"event_msg","payload":{"type":"token_count","info":{...}}}` |

### agent_message text format
For plain chat, `text` is plain string: `"Hello."`

For structured/schema-driven output (evals), `text` is JSON-wrapped: `{"result":"AI DEV TOOLS JOKE: ..."}`

`CodexStreamFormatter` must handle both. Extract `result` from the JSON wrapper when present; fall back to raw text otherwise.

---

## Quick reference: finding a session

```bash
# List today's Codex sessions
ls ~/.codex/sessions/$(date +%Y/%m/%d)/

# Read a session's user messages
grep -o '"message":"[^"]*"' ~/.codex/sessions/YYYY/MM/DD/<file>.jsonl | head -10

# Check if a session came from the Mac app vs native TUI
grep '"originator"' ~/.codex/sessions/YYYY/MM/DD/<file>.jsonl | head -1
# "codex_exec" = Mac app / CLI invocation
# "codex-tui"  = native Codex terminal UI
```
