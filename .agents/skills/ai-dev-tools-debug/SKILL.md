---
name: ai-dev-tools-debug
description: >
  Debugging guide for AIDevTools (evals, plan runner, Mac app, PRRadar). Shows how to
  discover configured repositories, eval cases, artifact paths, plan storage, log files,
  and CLI commands for troubleshooting. Use this skill when: the user reports a bug, asks
  to check eval data, shares a screenshot of eval results or the Mac app, mentions a
  failing case, wants to inspect provider output, needs to debug plan generation or
  execution, or is debugging PRRadar behavior (pipeline output, rule evaluation, Mac app
  issues). Screenshots of the Mac app are a strong signal to invoke this skill — they
  mean the user wants you to reproduce or investigate using the CLI.
---

# AIDevTools Eval System — Debugging & Data Access

This skill gives you access to the user's real eval data so you can run CLI commands to troubleshoot bugs, inspect results, and reproduce issues. AIDevTools runs coding evals against AI providers (Claude, Codex) and grades output using deterministic checks and rubric-based AI grading.

## Step 1: Build the CLI

The Swift package lives in this repo at `AIDevToolsKit/`. All commands run from there:

```bash
cd <repo-root>/AIDevToolsKit
swift build
swift run ai-dev-tools-kit <subcommand>
```

### Environment setup

The CLI loads environment variables from a `.env` file (searched from `AIDevToolsKit/` upward). Provider commands that use the Anthropic API require `ANTHROPIC_API_KEY`. Check that `AIDevToolsKit/.env` exists and contains the key before running commands with `--provider anthropic-api`.

## Step 2: Discover Configured Repositories

The user's repository configurations live in `repositories.json` inside their **data path** (default: `~/Desktop/ai-dev-tools/`). List them:

```bash
swift run ai-dev-tools-kit repos list
```

This prints each repo's **UUID**, **name**, **path**, and **cases directory**. Use this output to get the actual paths — never assume them.

**IMPORTANT:** When the user mentions a repo by name (e.g. "ios-26"), match it to a configured repo here to find its **path**. Skills for that repo live at `<repo-path>/.claude/skills/` (or `<repo-path>/.agents/skills/`). Always resolve repo paths through `repos list` — do not search for files across the filesystem.

### Repository Configuration Shape

Each entry in `repositories.json`:
```json
{
  "id": "<uuid>",
  "path": "<absolute-path-to-repo>",
  "name": "<display-name>",
  "casesDirectory": "<absolute-or-relative-path>"
}
```

- `casesDirectory` can be absolute or relative (resolved against `path`)
- The **output directory** is auto-derived: `<dataPath>/<name>/`

## Step 3: Find Eval Cases

Cases live under the repo's configured `casesDirectory`:

```
<casesDirectory>/
  cases/
    <suite-name>.jsonl       # One JSON object per line
```

List cases with the CLI:

```bash
# List all cases for a repo
swift run ai-dev-tools-kit list-cases --repo <repo-path>

# Filter by suite
swift run ai-dev-tools-kit list-cases --repo <repo-path> --suite <suite-name>

# Filter by case ID
swift run ai-dev-tools-kit list-cases --repo <repo-path> --case-id <case-id>

# Or use --cases-dir directly instead of --repo
swift run ai-dev-tools-kit list-cases --cases-dir <cases-directory-path>
```

Each case prints its qualified ID, mode, task, assertions, and grading config.

### Eval Case Modes

- `"structured"` (default): Provider returns JSON only, no file edits
- `"edit"`: Provider edits files in the repo AND returns structured output

## Step 4: Find Artifacts & Results

Artifacts are in the **output directory** (`<dataPath>/<repoName>/`):

```
<outputDir>/
  artifacts/
    <provider>/                              # "claude" or "codex"
      summary.json                           # Run summary (total/passed/failed/skipped)
      <suite>.<case-id>.json                 # Per-case grading result
      <suite>.<case-id>.rubric.json          # Rubric result (if rubric configured)
    raw/
      <provider>/
        <suite>.<case-id>.stdout             # Raw provider output (JSONL stream)
        <suite>.<case-id>.stderr             # Raw error output
        <suite>.<case-id>.rubric.stdout      # Rubric grader output
        <suite>.<case-id>.rubric.stderr      # Rubric grader errors
  result_output_schema.json
  rubric_output_schema.json
```

### Reading Results

After discovering paths via `repos list`, read the actual files:

```bash
# Summary for a provider
cat <outputDir>/artifacts/<provider>/summary.json

# Specific case result
cat <outputDir>/artifacts/<provider>/<suite>.<case-id>.json

# Rubric grading result
cat <outputDir>/artifacts/<provider>/<suite>.<case-id>.rubric.json

# Raw provider output (tool calls, responses)
cat <outputDir>/artifacts/raw/<provider>/<suite>.<case-id>.stdout
```

### Summary Shape

```json
{
  "provider": "claude",
  "total": 5,
  "passed": 3,
  "failed": 1,
  "skipped": 1,
  "cases": [
    {
      "caseId": "suite.id",
      "passed": true,
      "errors": [],
      "skipped": [],
      "providerResponse": "...",
      "toolCallSummary": { "attempted": 10, "succeeded": 10, "rejected": 0, "errored": 0 }
    }
  ]
}
```

## Step 5: Running Evals

```bash
# Run a specific case
swift run ai-dev-tools-kit run-evals --repo <repo-path> --case-id <case-id> --provider claude

# Run all cases in a suite
swift run ai-dev-tools-kit run-evals --repo <repo-path> --suite <suite-name> --provider claude

# Run with debug output (shows exact CLI args passed to provider)
swift run ai-dev-tools-kit run-evals --repo <repo-path> --case-id <case-id> --provider claude --debug

# Available providers: claude, codex, both
```

Use `--repo` (not `--cases-dir`) for edit-mode cases so the provider runs in the actual repository.

## Plan Runner CLI Commands

```bash
# Generate a plan from voice/text input (matches repo automatically)
swift run ai-dev-tools-kit plan-runner plan "add dark mode support"

# Generate and immediately execute
swift run ai-dev-tools-kit plan-runner plan "add dark mode support" --execute

# Execute phases from an existing plan
swift run ai-dev-tools-kit plan-runner execute --plan <path-to-plan.md>

# Execute with custom time limit
swift run ai-dev-tools-kit plan-runner execute --plan <path> --max-minutes 60

# Delete a plan and its job directory
swift run ai-dev-tools-kit plan-runner delete --plan <path-to-job-dir-or-plan.md>

# Interactive delete (shows list of all plans)
swift run ai-dev-tools-kit plan-runner delete
```

### Plan Storage

Plans are stored at `~/Desktop/ai-dev-tools/<repoId>/<job-name>/plan.md`. Each job directory may also contain a `worktree/` directory and `*.log` files.

### Plan Execution Logs

Each plan phase execution writes two types of logs:

**1. AI output logs** — the full Claude output for each phase:
```
<dataPath>/<repoName>/plan-logs/<plan-name>/phase-<N>.stdout
```

Example: `~/Desktop/ai-dev-tools/AIDevTools/plan-logs/2026-03-22-f-consolidate-slash-commands-into-skills/phase-2.stdout`

These are written on both success and failure (partial output is captured even when a phase fails). One file per phase, overwritten on re-execution.

**2. Structured error logs** — phase start/complete/fail events written to the app-wide log via `Logger(label: "PlanRunner")`:
```bash
# Filter plan execution errors
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label == "PlanRunner")'

# Just errors (includes underlying error message and path to the .stdout log file)
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label == "PlanRunner" and .level == "error")'
```

Error log entries include a `logFile` metadata field pointing to the corresponding `.stdout` file for cross-referencing.

## Other CLI Commands

```bash
# Show formatted output from a completed run
swift run ai-dev-tools-kit show-output --repo <repo-path> --provider claude

# Delete all prior artifacts
swift run ai-dev-tools-kit clear-artifacts --repo <repo-path>

# List skills for a repo
swift run ai-dev-tools-kit skills <repo-path>

# Manage repos
swift run ai-dev-tools-kit repos add <path>
swift run ai-dev-tools-kit repos remove <uuid>
swift run ai-dev-tools-kit repos update <uuid>
```

## Grading Layers

1. **Response text:** `must_include` / `must_not_include` on the provider's structured output
2. **Deterministic checks:** `filesExist`, `filesNotExist`, `fileContains`, `fileNotContains`, `diffContains`, `diffNotContains`, `traceCommandContains`, `traceCommandNotContains`, `traceCommandOrder`, `maxCommands`, `maxRepeatedCommands`, `skillMustBeInvoked`, `skillMustNotBeInvoked`, `referenceFileMustBeRead`, `referenceFileMustNotBeRead`
3. **Rubric grading:** AI evaluator with `overall_pass`, `score`, and per-check results

## Edit-Mode Grading Order

1. Provider runs and edits files
2. Git diff captured
3. Deterministic file/diff assertions run
4. Rubric grading runs (can read live repo state)
5. Git reset cleans up changes

## Permissions

- Edit-mode cases pass `--dangerously-skip-permissions` to Claude CLI automatically
- Structured-mode cases do not (no file edits needed)

## Tool Call Summary

Both providers produce a `toolCallSummary`:
- **Claude:** Correlates `tool_use`/`tool_result` events by ID. "rejected" = permission denied.
- **Codex:** Counts `command_execution` items by exit code. No "rejected" concept.
- **Hallucination detection:** Warning added if diff is empty but provider claims changes.

## Logs

Logs are the primary tool for troubleshooting CLI and Mac app behavior. For reading logs, filtering output, and adding log statements for debugging, use the logging skill:

`.agents/skills/logging/SKILL.md`

## Playground: AIDevToolsDemo

When reproducing issues or validating that something works end-to-end, use the AIDevToolsDemo repo as a playground. It is safe to create, close, and delete branches and PRs there freely — it exists purely for testing. Read the reference doc for details:

`references/aidevtools-demo-playground.md`

## PRRadar Debugging

PRRadar's MacApp (GUI) and PRRadarMacCLI (CLI) share the same use cases and services, so any issue seen in the Mac app can be reproduced with CLI commands.

### Discovering Configurations

Settings live at:
```
~/Library/Application Support/PRRadar/settings.json
```

List configurations:
```bash
cd PRRadarLibrary
swift run PRRadarMacCLI config list
```

Or read the JSON directly to see repo paths, rule paths, diff source, GitHub account, and default base branch:
```bash
cat ~/Library/Application\ Support/PRRadar/settings.json
```

### Output Directory

Output location is defined per-config in settings. Inspect the settings JSON to find it. Output is organized as `<outputDir>/<PR_NUMBER>/` with subdirectories for each pipeline phase.

### CLI Commands

Run from `PRRadarLibrary/`:

```bash
# Fetch diff
swift run PRRadarMacCLI diff <PR_NUMBER> --config <config-name>

# Generate focus areas and filter rules
swift run PRRadarMacCLI rules <PR_NUMBER> --config <config-name>

# Run evaluations
swift run PRRadarMacCLI evaluate <PR_NUMBER> --config <config-name>

# Generate report
swift run PRRadarMacCLI report <PR_NUMBER> --config <config-name>

# Full pipeline (diff + rules + evaluate + report)
swift run PRRadarMacCLI analyze <PR_NUMBER> --config <config-name>

# Check pipeline status
swift run PRRadarMacCLI status <PR_NUMBER> --config <config-name>
```

Use `--config <config-name>` to select the repository. Run `config list` to see available names. If `--config` is omitted, the default config is used.

### PRRadar Debugging Tips

- **Phase order:** METADATA → DIFF → PREPARE (focus areas, rules, tasks) → EVALUATE → REPORT
- **Phase result files:** Each phase writes a `phase_result.json` indicating success/failure. Check `<outputDir>/<PR>/` for JSON artifacts.
- **Rule directories:** Rule paths are defined per-config in settings. Some are relative to the repo, others are absolute.
- **Build and test:** Run `swift build` and `swift test` from `PRRadarLibrary/` to verify changes.
- **Daily review script:** `scripts/daily-review.sh` runs the `run-all` pipeline on a daily basis (via cron or launchd). Supports `--mode` and `--lookback-hours` flags.

### Cost Tracking

**Two separate output directories exist — check the right one:**

- **CLI output** (used by `ai-dev-tools-kit prradar` and `daily-review.sh`): `~/Desktop/ai-dev-tools/services/pr-radar/repos/<repo-name>/`
- **Mac app output** (used by the GUI, from `~/Library/Application Support/PRRadar/settings.json`): defined per-config in that settings file (e.g. `~/Desktop/code-reviews/`)

Cost is only tracked in the CLI output directory. The Mac app directory may be stale or have zero costs if it predates cost tracking.

**Where cost lives in the CLI output:**

```
<dataPath>/services/pr-radar/repos/<repo-name>/
  <PR_NUMBER>/
    analysis/<commitHash>/
      evaluate/
        phase_result.json          # totalCostUsd for the whole PR evaluate phase
        summary.json               # totalCostUsd, totalTasks, violationsFound
        data-<taskId>.json         # per-rule: analysisMethod.costUsd (AI only; regex/script = 0)
```

**Compute today's total cost:**

```bash
find ~/Desktop/ai-dev-tools/services/pr-radar/repos/ios-auto -path "*/evaluate/phase_result.json" | python3 -c "
import sys, json
total = 0.0
for path in sys.stdin:
    path = path.strip()
    try:
        with open(path) as f: d = json.load(f)
        ts = d.get('completed_at','')
        cost = d.get('stats',{}).get('cost_usd', 0) or 0
        if 'YYYY-MM-DD' in ts:  # replace with today's date
            total += float(cost)
    except: pass
print(f'Total: \${total:.4f}')
"
```

**Cost is only non-zero for AI rules** (rules with no `violation_script` or `violation_regex`). Script and regex rules always report `$0`.

## Debugging Tips

- **Provider didn't edit files?** Check raw stdout for permission errors. With `--debug`, verify CLI args include `--dangerously-skip-permissions` for edit-mode cases.
- **Empty diff for edit-mode?** Check `toolCallSummary.rejected` or search raw stdout for `"is_error":true`.
- **Permissions flag missing?** Verify `"mode": "edit"` in the JSONL case definition.
- **Rubric grading failed?** Read the rubric result JSON — per-check `notes` explain what the grader found.
- **Rubric check IDs mismatch?** `required_check_ids` must match what the grader returns. If unpredictable, omit and use `require_overall_pass` + `min_score`.
- **diffNotContains false positive?** Git diffs include 3 context lines. Nearby code may contain the forbidden string even though the provider didn't add it.
- **Wrong cwd?** Check `"cwd"` in the first line of raw stdout (`"type":"system","subtype":"init"`).
- **Stale artifacts?** Artifacts are overwritten each run. Use `--keep-traces` to preserve JSONL traces.
- **Plan phase failed?** Check the AI output log at `<dataPath>/<repoName>/plan-logs/<plan-name>/phase-<N>.stdout` for Claude's full output, then check `~/Library/Logs/AIDevTools/aidevtools.log` filtered by `label == "PlanRunner"` for the structured error with the underlying cause.
