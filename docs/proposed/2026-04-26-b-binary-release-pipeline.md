## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

Currently, clients that want to use `ai-dev-tools-kit` (the CLI) must check out AIDevTools and build it from source — a slow step visible in workflows like `gestrich/AIDevToolsDemo`'s `pr-radar.yml`. The goal is to publish pre-built binaries via GitHub Releases so clients can download and run them without a Swift toolchain or compilation step.

Design decisions agreed upon:

- **Binary:** `ai-dev-tools-kit` only
- **Platforms:** macOS arm64 + Linux x86_64
- **Release trigger:** Git tag push (`v*`) from a local `scripts/release.sh`
- **Release script guards:** clean working tree + tag doesn't already exist (no branch check — Bill frequently runs from detached HEAD)
- **CI gates:** run tests on both platforms before building
- **Release assets:** `ai-dev-tools-kit-macos-arm64.tar.gz`, `ai-dev-tools-kit-linux-x86_64.tar.gz`, `checksums.txt`
- **Install script:** detects platform, defaults to latest release, respects `VERSION` env var (pin) and `INSTALL_DIR` env var (default `/usr/local/bin`), verifies checksum before installing
- **First release:** `v0.1.0`
- **README:** clear install instructions with exact runnable commands

## - [x] Phase 1: GitHub Actions Release Workflow

**Skills used**: none
**Principles applied**: Used `swift-actions/setup-swift@v2` for Linux Swift 6.2 install; `sha256sum` runs on ubuntu-latest in the release job; `gh release create` uses `GH_TOKEN` and `--repo` for explicit repo context; macOS-only targets are skipped on Linux naturally via `#if os(macOS)` in Package.swift.

**File:** `.github/workflows/release.yml`

Triggered on `push` to tags matching `v*`.

**Structure:**

1. **`test` job** — matrix across `macos-latest` (arm64) and `ubuntu-latest` (x86_64):
   - Checkout repo
   - Install Swift 6.2 on Linux (use `swift-actions/setup-swift@v2`)
   - Run `swift test -c release --package-path AIDevToolsKit` (skip macOS-only targets on Linux)
   - Both must pass before build proceeds

2. **`build-macos` job** — `needs: test`, `runs-on: macos-latest`:
   - `swift build -c release --product ai-dev-tools-kit --package-path AIDevToolsKit`
   - Find binary at `AIDevToolsKit/.build/release/ai-dev-tools-kit`
   - Package: `tar -czf ai-dev-tools-kit-macos-arm64.tar.gz -C AIDevToolsKit/.build/release ai-dev-tools-kit`
   - Upload as artifact

3. **`build-linux` job** — `needs: test`, `runs-on: ubuntu-latest`:
   - Install Swift 6.2
   - Same build command
   - Package: `tar -czf ai-dev-tools-kit-linux-x86_64.tar.gz ...`
   - Upload as artifact

4. **`release` job** — `needs: [build-macos, build-linux]`:
   - Download both artifacts
   - Generate `checksums.txt` with `sha256sum` (Linux) / `shasum -a 256` (macOS) — run this step on `ubuntu-latest`
   - Create GitHub Release using `gh release create ${{ github.ref_name }}` with all three files attached
   - Release title: the tag name; body: auto-generated changelog or placeholder

## - [x] Phase 2: Local Release Script

**Skills used**: none
**Principles applied**: Script guards against unclean working tree and duplicate tags (local and remote) before tagging; uses `gh repo view` to dynamically resolve the repo name for the Actions URL rather than hardcoding it.

**File:** `scripts/release.sh`

Bash script Bill runs locally to tag and push, kicking off the CI workflow.

Guards (fail with a clear message if violated):
1. Working tree is clean (`git status --porcelain` is empty)
2. Tag doesn't already exist locally or on remote

Usage: `./scripts/release.sh v0.1.0`

Steps:
1. Parse version argument (require `v` prefix, error if missing)
2. Run guards
3. `git tag <version>`
4. `git push origin <version>`
5. Print the GitHub Actions URL to watch progress

## - [x] Phase 3: Install Script

**Skills used**: none
**Principles applied**: Written as POSIX `/bin/sh` (not bash) since it runs via `curl ... | sh`; SHA256 verification uses `sha256sum` (Linux) or `shasum` (macOS) with a clear mismatch error; sudo fallback uses `sh -c` to handle spaces in paths; temp dir is always cleaned via `trap ... EXIT`.

**File:** `scripts/install.sh`

Designed to be run via:
```sh
curl -fsSL https://raw.githubusercontent.com/gestrich/AIDevTools/main/scripts/install.sh | sh
```

Or with overrides:
```sh
VERSION=v0.1.0 INSTALL_DIR=~/.local/bin curl -fsSL ... | sh
```

Logic:
1. Detect OS + arch:
   - `darwin` + `arm64` → `macos-arm64`
   - `linux` + `x86_64` → `linux-x86_64`
   - Anything else → error with "unsupported platform"
2. Resolve version: if `VERSION` is unset, fetch latest from GitHub API (`https://api.github.com/repos/gestrich/AIDevTools/releases/latest`)
3. Download tarball and `checksums.txt` from the release
4. Verify SHA256 checksum — abort if mismatch
5. Extract binary and move to `${INSTALL_DIR:-/usr/local/bin}`
6. If destination requires elevated permissions, re-run the move with `sudo` (or print a helpful error)
7. Confirm: `ai-dev-tools-kit --version` (or `--help`) to verify the install worked

## - [x] Phase 4: README Update

**Skills used**: none
**Principles applied**: Installation section placed between the intro paragraph and "Mac App and CLI" section for maximum prominence; used blockquote for the `~/.local/bin` PATH note to match the spec; no existing build-from-source instructions were present so none needed removal.

Update the top-level `README.md` with a dedicated **Installation** section, placed prominently near the top.

Must include:

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

Note for `~/.local/bin` users: make sure it's on your `$PATH` (`export PATH="$HOME/.local/bin:$PATH"` in your shell profile).

**Supported platforms:** macOS arm64, Linux x86_64

Also remove or update any README instructions that tell users to build from source.

## - [x] Phase 5: End-to-End Test Workflow in AIDevToolsDemo

**Skills used**: none
**Principles applied**: Version resolution uses the GitHub API when no input is provided; checksum verification gates installation; binary smoke test uses both `--help` and `prradar --help` to confirm top-level dispatch works; no secrets required.

**File:** `../AIDevToolsDemo/.github/workflows/test-binary.yml`

This is the true end-to-end validation: download the published release binary in a real GitHub Actions environment and run a CLI command.

Trigger: `workflow_dispatch` with an optional `version` input (default: latest).

Runs on: `ubuntu-latest` (Linux x86_64 — the new path; macOS is well-tested locally).

Steps:
1. Set `VERSION` from input (or resolve latest via GitHub API)
2. Download `ai-dev-tools-kit-linux-x86_64.tar.gz` and `checksums.txt` from the release
3. Verify checksum
4. Extract and install binary to `/usr/local/bin`
5. Run `ai-dev-tools-kit --help` — success = exit code 0 and recognizable output
6. Optionally run a second meaningful subcommand (e.g., `ai-dev-tools-kit prradar --help`) to confirm subcommand routing works

This workflow does NOT require `ANTHROPIC_API_KEY` or any secrets — it's a pure binary smoke test.

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Fixed several pre-existing build blockers discovered by first-ever CI run: `StreamLogsUseCase` referenced Darwin-only `LogFileWatcher` without a platform guard; `RunAllUseCase.execute` was called with a stale `repo:` argument; `WorkflowServiceTests` mock types were missing two protocol methods (`readCacheRefreshState`/`writeCacheRefreshState`); `MCPCommandTests` accessed an internal type across module boundaries without `@testable import`. Workflow required three structural fixes: install Swift 6.2 on macOS (runner ships 6.1), split test step per-platform to avoid compiling SwiftUI targets on Linux, and switch macOS from `swift test` to `swift build` to avoid a Swift 6.2 compiler crash (signal 6) on the `AIDevToolsKitMac` module. Linux binary required `--static-swift-stdlib` + `libcurl4-openssl-dev` to be self-contained (no Swift runtime on runners). All five workflow jobs passed; `test-binary.yml` confirmed the Linux binary runs `--help` and `prradar --help` with exit code 0.

1. Run `./scripts/release.sh v0.1.0` from AIDevTools
2. Watch the `release.yml` workflow in GitHub Actions — confirm:
   - Tests pass on both platforms
   - Both tarballs build successfully
   - GitHub Release is created with all three assets attached
3. Manually trigger `test-binary.yml` in `gestrich/AIDevToolsDemo` (via GitHub Actions UI)
4. Confirm the workflow downloads the binary, verifies the checksum, and runs `--help` successfully
5. Run `ai-dev-tools-enforce` on all new/modified files
