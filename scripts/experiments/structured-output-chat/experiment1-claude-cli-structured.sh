#!/usr/bin/env bash
# Experiment 1: Claude CLI — text + structured output coexistence
# Questions:
# - Does the model produce streaming text events BEFORE/ALONGSIDE structured output?
# - Is that text meaningful conversational content or just working/thinking?
# - After completion, does result contain BOTH streaming text AND structured_output?
# - Does this work with --resume?
#
# Requires --verbose when using --output-format stream-json with --print (-p)

set -e

SCHEMA='{"type":"object","properties":{"text":{"type":"string"},"mood":{"type":"string","enum":["happy","sad"]}},"required":["text","mood"]}'

echo "=== Experiment 1: Claude CLI with --json-schema ==="
echo ""
echo "Running: claude -p 'Tell the user a joke, then return structured data' --output-format stream-json --verbose --json-schema ..."
echo ""

claude -p "Tell the user a joke, then return structured data" \
  --output-format stream-json \
  --verbose \
  --json-schema "$SCHEMA" 2>&1
