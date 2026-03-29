#!/usr/bin/env bash
# Experiment 3: Schema-with-text-field approach
# Tests whether a schema that includes a `text` field preserves conversational feel.
# Questions:
# - Does the AI produce natural conversational text in the `text` field?
# - Can we incrementally parse and display the `text` field while the JSON streams?
# - Does the quality of the conversational response degrade when constrained to JSON?
#
# Finding: Works with Claude CLI. Codex requires very strict schemas (all props required,
# additionalProperties:false everywhere) so generic action data objects are not possible.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Schema for Claude CLI (allows generic data object)
CLAUDE_SCHEMA='{
  "type": "object",
  "additionalProperties": false,
  "required": ["text"],
  "properties": {
    "text": {"type": "string", "description": "Your conversational response to the user"},
    "appResponses": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name", "data"],
        "properties": {
          "name": {"type": "string"},
          "data": {"type": "object", "additionalProperties": true}
        }
      }
    }
  }
}'

echo "=== Experiment 3a: Schema-with-text-field via Claude CLI ==="
echo ""
claude -p "Tell the user a joke. Also return an appResponse named 'selectTab' with data {\"tab\": \"plans\"}." \
  --output-format stream-json \
  --verbose \
  --json-schema "$CLAUDE_SCHEMA" 2>&1

echo ""
echo "=== Experiment 3b: Schema-with-text-field via Codex CLI ==="
echo ""

# Codex requires flat, fully-required schemas (no flexible data:object nesting)
CODEX_SCHEMA_FILE="$SCRIPT_DIR/text-field-schema.json"
cat > "$CODEX_SCHEMA_FILE" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["text", "tab"],
  "properties": {
    "text": {"type": "string", "description": "Your conversational response to the user"},
    "tab": {"type": "string", "description": "Tab to navigate to", "enum": ["plans", "evals", "chains", "skills", ""]}
  }
}
EOF

codex exec "Tell the user a joke. Navigate to the plans tab." \
  --json \
  --output-schema "$CODEX_SCHEMA_FILE" 2>&1
