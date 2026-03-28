# ClaudeChainKit — Remaining Work

Tracked items from the Python→Swift port. Each item includes what needs to be done.

---

## CLI Command Implementations

All CLI commands have argument definitions but their `run()` methods are stubs that print "not implemented" and `throw ExitCode.failure`. Each needs its business logic ported from the corresponding Python command.

- [x] **AutoStartCommand.swift** — Port `run()` from `cli/commands/auto_start.py`

  This is a complex 4-step workflow: detect changed spec files via git diff, evaluate auto-start decisions per project, trigger workflow dispatches, and write GitHub Actions outputs (`triggered_projects`, `trigger_count`, `failed_projects`). Requires environment variable handling for `repo`, `base-branch`, `ref-before`, `ref-after`, and `auto-start-enabled` (with boolean conversion logic). References `AutoStartService`, `GitOperations`, and `GitHubActions`.

- [x] **CreateArtifactCommand.swift** — Port `run()` from `cli/commands/create_artifact.py`

  Reads 9+ environment variables (no CLI args), parses cost breakdown JSON, creates `TaskMetadata` with AI task entries, writes artifact files to a temp directory, and outputs `artifact_path`/`artifact_name` via GitHub Actions. The Swift stub is also missing all environment variable argument definitions.

- [x] **DiscoverReadyCommand.swift** — Port `run()` from `cli/commands/discover_ready.py`

  Finds projects that have capacity (no open PRs exceeding limit) and available tasks. Orchestrates `ProjectRepository`, `AssigneeService`, and `TaskService` to produce a list of ready projects with GitHub Actions outputs.

- [x] **FinalizeCommand.swift** — Port `run()` from `cli/commands/finalize.py`

  Handles post-Claude cleanup: commits changes, creates PR (or updates existing), generates summary prompt, and writes GitHub Actions outputs. Complex flow involving `GitOperations`, `PRService`, and `GitHubOperations`.

- [x] **FormatSlackNotificationCommand.swift** — Port `run()` from `cli/commands/format_slack_notification.py`

  Formats a Slack notification message for a created PR using `SlackBlockKitFormatter` or `SlackFormatter`. Reads environment variables for PR details and outputs formatted message.

- [x] **ParseClaudeResultCommand.swift** — Port `run()` from `cli/commands/parse_claude_result.py`

  Parses Claude's JSON output using `_extract_structured_output()` helper which handles both clean JSON and JSON embedded in markdown/text. Writes parsed fields as GitHub Actions outputs. The extraction logic is non-trivial — it searches for JSON blocks and validates against the schema.

- [x] **ParseEventCommand.swift** — Port `run()` from `cli/commands/parse_event.py`

  Parses GitHub webhook event JSON into structured context using `GitHubEventContext`. Takes 4 CLI args: `event-name`, `event-json`, `project-name`, `default-base-branch`. The Swift stub has argument definitions but no implementation.

- [x] **PostPRCommentCommand.swift** — Port `run()` from `cli/commands/post_pr_comment.py`

  Posts a unified PR comment combining summary text and cost breakdown. Reads environment variables, fetches existing comments to update rather than duplicate, and uses `GitHubOperations` for the API call.

- [x] **PrepareCommand.swift** — Port `run()` from `cli/commands/prepare.py`

  The most complex command. Orchestrates full preparation: loads project config from repo, validates spec format, checks assignee capacity, finds next available task, detects orphaned PRs, creates branch, checks out code, and writes extensive GitHub Actions outputs. Multiple early-exit paths with different output combinations.

- [x] **PrepareSummaryCommand.swift** — Port `run()` from `cli/commands/prepare_summary.py`

  Prepares the prompt for PR summary generation. Reads environment variables, assembles context (diff, spec, task description), and outputs the formatted prompt for Claude to summarize the PR.

- [x] **RunActionScriptCommand.swift** — Port `run()` from `cli/commands/run_action_script.py`

  Executes pre/post action scripts via `ScriptRunner`. Takes 2 required args: `type` (choices: pre/post) and `project-path`. Handles script-not-found gracefully and writes results to GitHub Actions outputs.

- [x] **SetupCommand.swift** — Port `run()` from `cli/commands/setup.py`

  Interactive setup wizard. Takes a `repo_path` positional arg, creates directory structure, generates initial config and spec files. Includes interactive prompts for configuration values.

- [x] **StatisticsCommand.swift** — Port `run()` from `cli/commands/statistics.py`

  Collects and formats project statistics. Takes 7 CLI args including `format` (markdown/slack/json), `days-back`, and `show-assignee-stats`. Supports Slack webhook posting. The Swift stub has partial argument definitions but is missing `workflow_file` (required).

---

## Missing CLI Subcommand

- [x] **AutoStartSummaryCommand** — Verify argument definitions match Python

  The command file was created but needs verification that its arguments and `run()` logic match the Python `auto-start-summary` subcommand. In Python, this generates a formatted GitHub Actions step summary from auto-start results.

---

## Missing Test Builders

- [x] **ArtifactBuilder / TaskMetadataBuilder** — Port from `tests/builders/artifact_builder.py`

  Python has `TaskMetadataBuilder` and `ArtifactBuilder` with fluent interfaces used across multiple test files. No Swift equivalent exists. These are needed for comprehensive service-layer testing.

- [x] **Shared test fixtures (conftest.py)** — Port from `tests/conftest.py`

  Python's `conftest.py` provides shared pytest fixtures used across test files. Swift has no equivalent shared test helpers beyond the existing `TestBuilders.swift` files.

---

## Missing Integration Tests

- [ ] **Port integration tests from Python**

  Python has 8 integration test files in `tests/integration/` covering end-to-end command workflows with mocked services. Swift has no equivalent integration test coverage. These tests validate that CLI commands correctly wire up services and produce expected outputs.

---

## Test Mocking Infrastructure

- [ ] **Implement mocking infrastructure for service tests**

  Multiple Swift test files note `TODO: Restore once we have proper mocking infrastructure`. Currently, `PRService`, `TaskService`, and `AssigneeService` tests can't fully mock their dependencies. Consider creating protocol abstractions for remaining services (similar to `GitHubOperationsProtocol`) to enable proper DI-based mocking.

  Affected locations:
  - `Tests/Services/Core/AssigneeServiceTests.swift:51` — skipped tests needing mocked PRService
  - `Tests/Services/Core/AssigneeServiceTests.swift:125` — additional mocking TODOs
  - `Tests/Services/Core/PRServiceTests.swift:165` — tests requiring mocked infrastructure
  - `Tests/Services/TaskHashingTests.swift:229,232` — tests requiring mocked PRService

---

## Test Coverage Gaps

- [x] **Git operations tests** — Add Swift tests for `ensureRefAvailable`, `detectChangedFiles`, `detectDeletedFiles`

  Python tests extensively mock subprocess calls for these. Swift tests skip them due to environment dependencies. Consider using protocol-based DI for `Process` calls to enable testing without real git repos.

- [x] **GitHub operations test coverage analysis**

  Python has `test_operations.py` with extensive mocking of `gh` CLI calls. A detailed comparison against Swift's `GitHubOperationsTests.swift` hasn't been completed to identify specific missing test cases.

- [x] **AutoStartService detailed review**

  This service file exists and appears fully ported, but no detailed line-by-line comparison was performed against the Python source. Test coverage is unknown.

- [x] **WorkflowService detailed review**

  Same as AutoStartService — file exists but no detailed comparison was performed. Test coverage is unknown.

---

## Source Code Items

- [x] **ReportFormatter.swift:91** — `fatalError` for unknown element types

  Uses `fatalError("Unknown element type: \(type(of: element))")` which will crash at runtime. The Python equivalent raises `ValueError`. Consider throwing an error instead, or ensuring the type system makes this unreachable.

---

## Items Already Fixed (for reference)

These were identified in the review but have been resolved:

- ~~TableFormatter border bug (extra dashes)~~ ✅ Fixed
- ~~Unicode width for █ block characters~~ ✅ Fixed (now width 1, matching Python)
- ~~download_artifact_json ZIP extraction~~ ✅ Implemented
- ~~TaskMetadata.assignee property missing~~ ✅ Added
- ~~Main.swift CLI routing~~ ✅ Fixed (routes to ClaudeChainCLI.main())
- ~~AutoStartSummaryCommand missing~~ ✅ Created
- ~~StatisticsReport missing methods~~ ✅ Added
- ~~CostBreakdown test gap (84 vs 26)~~ ✅ Ported (now 82 tests)
- ~~5 missing AssigneeService tests~~ ✅ Added
