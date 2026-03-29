#!/usr/bin/env bash
# Experiment 4: Text convention reliability
# Tests XML tag approach without native structured output.
# Questions:
# - How reliably does the AI produce well-formed tags?
# - Does it work across Claude CLI and Codex CLI?
# - Does streaming work naturally (text flows, tags appear inline)?
# - Is parsing robust enough (handling edge cases like tags split across chunks)?
#
# Note: Codex exec has no --system-prompt flag; inject via prompt prefix instead.

set -e

SYSTEM_INSTRUCTIONS='When you need to trigger an app action or respond to a query, use XML format inline in your response:

<app-response name="ACTION_NAME">
{"key": "value"}
</app-response>

Available actions:
- selectTab: Switch to a tab. Data: {"tab": "plans"|"evals"|"chains"|"skills"}
- selectPlan: Select a plan by name. Data: {"name": "plan-name"}

Always include your conversational text alongside any app-response tags.'

echo "=== Experiment 4a: Text convention via Claude CLI (stream-json) ==="
echo ""
echo "Test 1: Basic action with conversational text"
claude -p "Take me to the plans tab and tell me a quick joke." \
  --output-format stream-json \
  --verbose \
  --system-prompt "$SYSTEM_INSTRUCTIONS" 2>&1

echo ""
echo "Test 2: Multiple actions"
claude -p "Select the plan called 'feature-x' and also take me to the evals tab." \
  --output-format stream-json \
  --verbose \
  --system-prompt "$SYSTEM_INSTRUCTIONS" 2>&1

echo ""
echo "=== Experiment 4b: Text convention via Codex CLI ==="
echo "Note: codex exec has no --system-prompt; injecting via prompt prefix."
echo ""
echo "Test 1: Basic action with conversational text"
printf '%s\n\nUser request: %s' "$SYSTEM_INSTRUCTIONS" "Take me to the plans tab and tell me a quick joke." | \
  codex exec - --json 2>&1
