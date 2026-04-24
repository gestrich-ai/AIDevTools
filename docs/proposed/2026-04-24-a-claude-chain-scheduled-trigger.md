## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Checks Swift code for 4-layer architecture violations (layer placement, dependencies, orchestration) |
| `ai-dev-tools-code-quality` | Checks for force unwraps, raw strings, duplicated logic, fallback values |
| `ai-dev-tools-composition-root` | Guidance for how CLI commands construct and wire their services |
| `ai-dev-tools-enforce` | Enforces project standards after code changes |

## Background

Claude Chain has two active GitHub workflows (`claude-chain.yml` and `claude-chain-status.yml`) and an `AIDevToolsDemo` repo as a live sandbox. Currently, new chain tasks are only triggered when a PR merges (continuous) or via manual `workflow_dispatch`. There is no automated scheduler that proactively finds chains with open capacity and fires jobs for them.

This plan adds:

1. A `scheduled-trigger` CLI subcommand that, in one run, discovers all chains with available capacity and triggers `workflow_dispatch` jobs for them.
2. A `claude-chain-scheduled-trigger.yml` GitHub workflow that calls the command on an hourly cron.
3. Validation in `AIDevToolsDemo` to confirm end-to-end behavior.

### Key constraints

- **GitHub async limit**: GitHub silently drops a 3rd concurrent `workflow_dispatch` for the same workflow; never trigger more than 2 per project in one run.
- **Global cap**: A configurable `--max-triggers` argument (default: 5) prevents runaway PR creation if there is a bug.
- **Branch targeting**: Chains can target non-default branches via `configuration.yml`. `ChainProject.baseBranch` already captures this from the remote listing; use it when dispatching.
- **No new capacity logic**: Reuse `ClaudeChainService`, `AssigneeService`, `PRService`, and `WorkflowService` — no reimplementing what they already do.
- **Workflow file name fix**: `WorkflowService.triggerClaudeChainWorkflow` currently hardcodes `"claudechain.yml"`, but all deployed workflows use `"claude-chain.yml"`. The new command needs a configurable `--workflow-file` argument, and `WorkflowService` needs to accept it.

## Phases

## - [x] Phase 1: Make `WorkflowService` accept a configurable workflow file name

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`, `ai-dev-tools-enforce`
**Principles applied**: Kept workflow dispatch configuration flowing through existing app-to-feature boundaries, reused the existing `WorkflowService` API instead of introducing parallel trigger logic, and added focused tests to lock in the default and custom workflow file behavior.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

`WorkflowService.triggerClaudeChainWorkflow` currently hardcodes the workflow ID as `"claudechain.yml"`. All deployed workflows (in this repo and `AIDevToolsDemo`) use `"claude-chain.yml"`. Fix this before adding the new command so the new command works correctly and doesn't inherit the bug.

**Changes**:

- In `WorkflowService.swift`, add a `workflowFileName: String` parameter to both `triggerClaudeChainWorkflow` and `batchTriggerClaudeChainWorkflows`, defaulting to `"claude-chain.yml"`. Replace the hardcoded `"claudechain.yml"` string.
- Update `AutoStartCommand.swift` to pass a `--workflow-file` option (default `"claude-chain.yml"`) through to `WorkflowService`. This fixes the latent bug in `auto-start` as well.

## - [ ] Phase 2: Add `ScheduledTriggerCommand`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`, `ai-dev-tools-code-quality`

Create `AIDevToolsKit/Sources/Apps/ClaudeChainCLI/ScheduledTriggerCommand.swift`.

**Command declaration**:
```
claude-chain scheduled-trigger
  --repo <owner/name>         # falls back to GITHUB_REPOSITORY env var
  --repo-path <path>          # checked-out repo path, for reading configs; falls back to CWD
  --max-triggers <n>          # global PR cap, default 5
  --label <string>            # PR label for capacity check, falls back to PR_LABEL env var, then "claudechain"
  --workflow-file <filename>  # workflow file to dispatch, default "claude-chain.yml"
```

**Run logic** (inside a single `async run()`, following the pattern of `AutoStartCommand`):

1. Resolve options from arguments then env vars (`GITHUB_REPOSITORY`, `PR_LABEL`).
2. Initialize services:
   - `PRService(repo: repo)`
   - `AssigneeService(repo: repo, prService: prService)`
   - A `GitHubPRServiceProtocol` via `GitHubServiceFactory.createPRService(repoPath:resolver:dataPathsService:)` (same pattern as `StatusCommand`)
   - `ClaudeChainService(client: ClaudeProvider(), repoPath: repoURL, prService: prService)`
   - A `WorkflowService` using `GitHubServiceFactory.make(token:owner:repo:)` (same pattern as `AutoStartCommand`)
3. List all chains: `chainService.listChains(source: .remote)`.
4. Filter to projects with `pendingTasks > 0`.
5. Sort alphabetically by project name (consistent, deterministic ordering).
6. Loop through filtered projects, tracking `remainingBudget = maxTriggers`:
   a. Load `ProjectConfiguration` via `ProjectRepository(repo: repo).loadLocalConfiguration(project:)`.
   b. Call `assigneeService.checkCapacity(config: config, label: label, project: project.name)`.
   c. Compute `slotsAvailable = max(0, capacityResult.maxOpenPRs - capacityResult.openCount)`.
   d. If `slotsAvailable == 0`: record as "skipped — at capacity" and continue.
   e. `triggersForProject = min(2, slotsAvailable, remainingBudget)`.
   f. For each trigger (1…triggersForProject): call `workflowService.triggerClaudeChainWorkflow(projectName:, baseBranch: project.baseBranch, checkoutRef: "HEAD", workflowFileName: workflowFile)`.
   g. Record success/failure for each trigger; deduct successes from `remainingBudget`.
   h. If `remainingBudget == 0`: record all remaining projects as "skipped — global max reached" and break.
7. Write step summary markdown using `GitHubActions().writeStepSummary(text:)` that includes:
   - Total open chains found and how many had pending tasks.
   - For each project: status (triggered N, at-capacity skip, global-max skip, or no pending tasks).
   - Total triggered vs. identified-but-not-triggered, with reason.
8. Print the same summary to stdout.
9. Exit 0 even on partial trigger failures (failed projects are logged but don't abort the run).

Register the command in `ClaudeChainCLI.swift` — insert `ScheduledTriggerCommand.self` in alphabetical position in the `subcommands` array.

## - [ ] Phase 3: Add `claude-chain-scheduled-trigger.yml` workflow to AIDevTools

**Skills to read**: none

Create `.github/workflows/claude-chain-scheduled-trigger.yml` using `claude-chain-status.yml` as the template (it has the right minimal setup steps; `claude-chain.yml` is heavier and runs Claude itself).

**Triggers**:
```yaml
on:
  schedule:
    - cron: '0 * * * *'  # Hourly
  workflow_dispatch:
    inputs:
      max_triggers:
        description: 'Maximum PRs to trigger this run (default: 5)'
        required: false
        default: '5'
```

**Permissions** — needs `actions: write` to dispatch `workflow_dispatch` events on `claude-chain.yml`:
```yaml
permissions:
  actions: write
  contents: read
  pull-requests: read
```

**Steps** — follow the exact pattern of `claude-chain-status.yml` (Checkout repository → Checkout AIDevTools → Mark workspace safe → Build AIDevTools CLI), then add:
```yaml
- name: Run Claude Chain scheduled trigger
  run: |
    cd aidevtools/AIDevToolsKit
    swift run -c release ai-dev-tools-kit claude-chain scheduled-trigger \
      --repo "${{ github.repository }}" \
      --repo-path ${{ github.workspace }} \
      --max-triggers "${{ github.event.inputs.max_triggers || '5' }}"
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Add a top-of-file comment block (matching style of other Claude Chain workflows) explaining that this workflow runs hourly, finds chains with available capacity, and triggers up to `max_triggers` workflow_dispatch jobs.

## - [ ] Phase 4: Add `claude-chain-scheduled-trigger.yml` to AIDevToolsDemo and set up validation chains

**Skills to read**: none

**Goal**: Run the scheduled trigger against real chains in `AIDevToolsDemo` to confirm it triggers PRs for projects with capacity and skips projects at capacity.

1. Copy the new `claude-chain-scheduled-trigger.yml` into `AIDevToolsDemo/.github/workflows/`.

2. Update `AIDevToolsDemo/claude-chain/hello-world/configuration.yml` to set `maxOpenPRs: 2` so it can accept 2 PRs and show multi-slot triggering behavior.

3. Add `AIDevToolsDemo/claude-chain/hello-world-2/` with:
   - `spec.md` — 3 simple tasks (e.g., create output files)
   - `configuration.yml` — `maxOpenPRs: 1`

4. Add `AIDevToolsDemo/claude-chain/at-capacity/` with:
   - `spec.md` — 2 tasks that are all still pending
   - `configuration.yml` — `maxOpenPRs: 1`
   - Manually open one draft PR with the correct label so it registers as at-capacity (OR use `maxOpenPRs: 0` as a test stand-in if a manual PR isn't feasible without running full workflow)

5. Manually trigger `Claude Chain Scheduled Trigger` via GitHub UI (`workflow_dispatch`) on `AIDevToolsDemo`.

6. Verify the GitHub Actions step summary shows:
   - `at-capacity`: skipped — at capacity
   - `hello-world`: triggered 2 jobs
   - `hello-world-2`: triggered 1 job
   - Total: 3 triggered of 5 max budget

7. Verify that the triggered `claude-chain.yml` workflow runs begin (they will start Claude, which requires `ANTHROPIC_API_KEY` — confirm that secret is set in `AIDevToolsDemo`).

## - [ ] Phase 5: Enforce and validate

**Skills to read**: `ai-dev-tools-enforce`

After all code changes:

1. Run `ai-dev-tools-enforce` on all changed Swift files:
   - `WorkflowService.swift`
   - `AutoStartCommand.swift`
   - `ScheduledTriggerCommand.swift`
   - `ClaudeChainCLI.swift`

2. Build the CLI locally to confirm no compiler errors:
   ```
   cd AIDevToolsKit && swift build -c debug --product ai-dev-tools-kit
   ```

3. Run `claude-chain scheduled-trigger --help` to verify the argument surface looks correct.

4. Confirm `ClaudeChainCLI.swift` subcommand list remains alphabetically sorted after adding `ScheduledTriggerCommand.self`.
