#!/usr/bin/env bash
# Experiment 2: Codex CLI — text + structured output coexistence
# Questions:
# - Does the JSONL event stream include text agent_messages BEFORE the final structured response?
# - Is the final agent_message purely JSON, or does it include conversational text too?
# - Can we extract both streaming text and structured data from the event stream?
#
# Key finding: Codex requires strict schemas — additionalProperties:false at ALL nesting depths,
# and ALL properties must be listed in required[].

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/test-schema.json"

cat > "$SCHEMA_FILE" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["mood"],
  "properties": {
    "mood": {
      "type": "string",
      "enum": ["happy", "sad", "neutral"],
      "description": "The mood conveyed by the joke"
    }
  }
}
EOF

echo "=== Experiment 2: Codex CLI with --output-schema ==="
echo ""
echo "Running: codex exec 'Tell the user a joke, then return the mood as structured data' --json --output-schema test-schema.json"
echo ""

codex exec "Tell the user a joke, then return the mood as structured data" \
  --json \
  --output-schema "$SCHEMA_FILE" 2>&1
