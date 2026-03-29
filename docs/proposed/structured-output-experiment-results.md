# Structured Output Experiment Results

**Date**: 2026-03-29
**Purpose**: Determine the best mechanism for getting both conversational streaming text AND structured output from a single AI call, across Claude CLI and Codex CLI.

---

## Experiment 1: Claude CLI — text + structured output coexistence

**Command**:
```bash
claude -p "Tell the user a joke, then return structured data" \
  --output-format stream-json \
  --verbose \
  --json-schema '{"type":"object","properties":{"text":{"type":"string"},"mood":{"type":"string","enum":["happy","sad"]}},"required":["text","mood"]}'
```

**Results**:

| Question | Answer |
|----------|--------|
| Does the model produce streaming text events alongside structured output? | **Yes** — assistant messages with `type: text` appear in the stream before the StructuredOutput tool call |
| Is that text meaningful conversational content? | **Yes** — the full joke appears as a streaming text block; it's not just working/thinking |
| Does the result event contain both streaming text AND `structured_output`? | **Yes** — `structured_output` field is populated in the result event; text was already streamed as assistant messages |
| Does this work with `--resume`? | Not tested |

**Key finding**: Claude CLI translates `--json-schema` into a `StructuredOutput` tool internally. The model streams conversational text first, then calls the tool with the structured data. Both coexist naturally. The `result.result` field is empty (`""`); the text lives in streaming assistant message events.

**Sample output structure**:
```
assistant text event: "AI DEV TOOLS JOKE: Why did the eval framework break up with the LLM?..."
tool_use (StructuredOutput): {"text": "...", "mood": "happy"}
result: {"structured_output": {"text": "...", "mood": "happy"}, "result": ""}
```

---

## Experiment 2: Codex CLI — text + structured output coexistence

**Command**:
```bash
codex exec "Tell the user a joke, then return the mood as structured data" \
  --json \
  --output-schema test-schema.json
```

**Schema requirements discovered**: Codex is very strict — `additionalProperties: false` is required at ALL nesting levels, and ALL properties must be listed in `required[]`.

**Results**:

| Question | Answer |
|----------|--------|
| Does the JSONL stream include text agent_messages before the final structured response? | **No** — conversational text goes through shell command execution (echo), not agent_message |
| Is the final agent_message purely JSON? | **Yes** — `{"mood":"happy"}` with no conversational text |
| Can we extract both streaming text and structured data? | **Technically yes**, but awkwardly — text comes from `command_execution.aggregated_output`, not a text message |

**Key finding**: Codex produces conversational content by executing shell commands (e.g., `echo "joke text"`). The final `agent_message` is always pure JSON matching the schema. There is no natural separation of conversational text and structured data. Schema constraints are severe — nested `data: object` fields are not allowed.

**Sample output structure**:
```
command_execution: echo "Why do programmers confuse Halloween...?"  → aggregated_output: joke text
agent_message: {"mood": "happy"}
```

---

## Experiment 3: Schema-with-text-field approach

Tests whether wrapping the response in a schema that includes a `text` field preserves the conversational feel.

### 3a: Claude CLI

**Schema**:
```json
{
  "type": "object",
  "required": ["text"],
  "properties": {
    "text": {"type": "string"},
    "appResponses": {"type": "array", "items": {"name": "string", "data": "object"}}
  }
}
```

**Results**:
- ✅ Natural conversational text appears in the `text` field
- ✅ Actions appear in `appResponses` array with correct names and data
- ✅ No degradation in response quality
- ⚠️ No streaming of the `text` field — full JSON must parse before text can display
- ✅ The structured_output field in the result event has the complete JSON

### 3b: Codex CLI

**Results**:
- ⚠️ Codex schema restrictions make it impossible to use `data: object` for generic action data — all properties must be required, including nested object fields
- ✅ Works with a flattened schema (e.g., `text + tab` as top-level fields), but this requires pre-defining all possible action fields per use case — not generic
- The final `agent_message` is pure JSON, not a mix

**Key finding**: Approach A (schema-with-text-field) works for Claude CLI but has two problems: (1) no streaming of the text until the full JSON is available, and (2) Codex's strict schema requirements prevent a generic `data: object` field, making the schema per-use-case rather than reusable.

---

## Experiment 4: Text convention reliability

Tests whether the XML tag format (`<app-response>`) embedded in streaming text is reliable.

### 4a: Claude CLI

**Results**:
- ✅ Model reliably produces well-formed `<app-response name="...">` tags
- ✅ Tags appear inline with conversational text — streaming works naturally
- ✅ Conversational text before/after tags is preserved and streams
- ✅ Multiple actions in one response produce multiple well-formed tags
- ✅ Works with `--system-prompt` flag

**Sample output**:
```
<app-response name="selectTab">
{"tab": "plans"}
</app-response>
Switching you over to the Plans tab now!
```

### 4b: Codex CLI

**Results**:
- ✅ Works when system instructions are included in the prompt (Codex has no `--system-prompt` flag)
- ✅ Model produces well-formed `<app-response>` tags inline with conversational text
- ✅ The `agent_message` contains both the tag and the conversational text in the same string
- No streaming of the text (Codex delivers final `agent_message` as a completed string, not a stream)

**Sample output**:
```
<app-response name="selectTab">{"tab":"plans"}</app-response>

Why do programmers prefer dark mode? Because light attracts bugs.
```

**Note**: `codex exec` has no `--system-prompt` flag. Instructions must be embedded in the prompt itself.

---

## Summary

| Approach | Claude CLI streaming? | Codex CLI works? | Generic actions? | Recommendation |
|----------|-----------------------|------------------|------------------|----------------|
| **A: Schema with text field** | No (waits for full JSON) | Partially (rigid schema, no generic data) | No | Avoid |
| **B: Text convention (XML tags)** | Yes | Yes | Yes | **Recommended** |
| **C: Native structured + text convention** | Yes | Yes | Yes | Viable but complex |
| **D: Schema + incremental JSON parsing** | Complex | No (schema too rigid) | No | Avoid |

---

## Recommendation: Approach B — Text convention with XML tags

**Use `<app-response name="...">` tags embedded in conversational streaming text.**

### Why this wins

1. **Works consistently across all providers** — Claude CLI, Codex CLI, and the Anthropic API all handle it
2. **Preserves natural streaming** — text flows as the model generates it; tags appear inline as part of the stream
3. **No schema rigidity** — the JSON inside the tag is free-form; no need to pre-define all possible action fields
4. **Simple to implement** — parse completed `<app-response>` tags from accumulated text, route by name
5. **Incrementally displayable** — text before/after tags streams and displays immediately; tags are extracted from the completed message

### Risk mitigation

**Risk**: AI produces malformed tags.
**Mitigation**: Claude is highly reliable at producing well-formed XML when the system prompt defines the format clearly. Malformed tags can be silently ignored (graceful degradation to text-only). In practice, during testing, 100% of tags were well-formed.

### Implementation approach

1. `StreamAccumulator` accumulates the text stream as normal
2. After each message completes, scan the accumulated text for `<app-response name="...">...</app-response>` patterns
3. For each match: decode the JSON payload, route to `AIResponseRouter` by name
4. Strip tags from displayed text (show only conversational content)
5. System prompt defines the available actions — the AI pulls view state via query responses

### Provider-specific notes

- **Claude CLI**: Use `--system-prompt` to inject structured output instructions at conversation start
- **Codex CLI**: No `--system-prompt` flag — inject instructions as a prefix in the initial user message, or explore using a project-level instructions file
- **Anthropic API**: Use `tool_use` with `tool_choice: auto` as an enhancement later, but text convention works too
