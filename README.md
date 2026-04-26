# AIDevTools

AIDevTools is a macOS app and CLI toolkit for AI-assisted software development. It provides tools for evaluating AI coding agents, chatting with AI, planning and executing implementations architecturally, reviewing pull requests with rules-based analysis, and automating task chains with GitHub Actions.

## Installation

Install the `ai-dev-tools-kit` CLI binary (no Swift toolchain required):

**Quick install (latest):**
```sh
curl -fsSL https://raw.githubusercontent.com/gestrich/AIDevTools/main/scripts/install.sh | sh
```

**Pin to a specific version:**
```sh
VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/gestrich/AIDevTools/main/scripts/install.sh | sh
```

**Install to a custom directory (no sudo):**
```sh
INSTALL_DIR=~/.local/bin curl -fsSL https://raw.githubusercontent.com/gestrich/AIDevTools/main/scripts/install.sh | sh
```

> If you install to `~/.local/bin`, make sure it's on your `$PATH` (`export PATH="$HOME/.local/bin:$PATH"` in your shell profile).

**Supported platforms:** macOS arm64, Linux x86_64

## GitHub Actions

For CI use, download the binary directly instead of using the install script. This avoids `sudo` prompts and works on standard `ubuntu-latest` runners without a Swift toolchain:

```yaml
- name: Download ai-dev-tools-kit
  env:
    VERSION: v0.1.0
  run: |
    curl -fsSL "https://github.com/gestrich/AIDevTools/releases/download/${VERSION}/ai-dev-tools-kit-linux-x86_64.tar.gz" -o ai-dev-tools-kit-linux-x86_64.tar.gz
    curl -fsSL "https://github.com/gestrich/AIDevTools/releases/download/${VERSION}/checksums.txt" -o checksums.txt
    sha256sum --check --ignore-missing checksums.txt
    tar -xzf ai-dev-tools-kit-linux-x86_64.tar.gz
    chmod +x ai-dev-tools-kit
    sudo mv ai-dev-tools-kit /usr/local/bin/ai-dev-tools-kit
```

Then call the binary directly in subsequent steps:

```yaml
- name: Run PRRadar
  run: ai-dev-tools-kit prradar run 42 --config ci --diff-source github-api --mode regex
```

See [`Examples/workflows/pr-radar.yml`](Examples/workflows/pr-radar.yml) for a complete working workflow.

## Mac App and CLI

AIDevTools ships as two interfaces backed by the same shared logic:

- **Mac App** — A native macOS application with a multi-tab interface, live output panels, and persistent history.
- **CLI (`ai-dev-tools-kit`)** — A command-line tool covering the same features, suitable for scripting and CI pipelines.

## Features

### AI Chat

Chat with AI providers using a unified interface, with streaming responses, persistent session history, and image attachment support.

The embedded chat connects to an **MCP server** (`ai-dev-tools-kit mcp`) that gives the AI live access to the running app — so you can ask questions like "what's in the currently open plan?" Tools include querying UI state, selecting plans, navigating tabs, and reloading data.

See [AI Chat documentation](docs/features/chat/chat.md) for setup and usage.

### AI Planning

Describe what you want to build in plain language and get a phased implementation plan. Execute phases one at a time with live progress tracking, completion checklists, and elapsed time monitoring. Plans are stored per repository and can be created, resumed, and managed from the app or CLI.

See [AI Planning documentation](docs/features/plans/plans.md) for details.

### ClaudeChain

Automate sequences of Claude Code tasks across GitHub pull requests. Define tasks in a `spec.md` file; ClaudeChain picks the next unchecked task, creates a branch, runs Claude Code to complete it, and opens a PR. When the PR is merged, the chain advances to the next task automatically. Supports both sequential spec-based chains and batch sweep processing over files.

See [ClaudeChain documentation](docs/features/claude-chain/claude-chain.md) for setup and usage.

### PRRadar

Review pull requests against configurable markdown rule files. The pipeline fetches the PR diff, uses AI to generate focus areas, evaluates changed code against matching rules (via regex or AI), and posts inline review comments on GitHub. Integrates with GitHub Actions for automated CI review.

See [PRRadar documentation](docs/features/pr-radar/pr-radar.md) for setup and usage.

### Skill Browser

Browse, preview, and manage skills (`.agents/skills/`) available in the current repository.

See [Skill Browser documentation](docs/features/skills/skills.md) for details.

### Skill Evaluator

Run structured test cases against AI providers to measure how well they handle coding tasks. Define assertions — required text, file changes, command traces, and rubric-based quality checks — then inspect results with per-case grading details and saved artifacts. Compare providers side-by-side across suites of test cases.

See [Skill Evaluator documentation](docs/features/evals/evals.md) for details.

### Worktrees

Create and manage git worktrees — additional working directories for the same repository checked out to different branches. Used internally by ClaudeChain to run tasks in isolation without disturbing the main working tree.

See [Worktrees documentation](docs/features/worktrees/worktrees.md) for details.
