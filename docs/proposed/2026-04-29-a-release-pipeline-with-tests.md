## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |
| `ai-dev-tools-swift-testing` | Test style guide and conventions |

## Background

The binary release pipeline was built and `v0.1.0` was published (see `2026-04-26-b-binary-release-pipeline.md`). However the `test` job in `release.yml` never actually ran tests — it ran `swift build -c release --product ai-dev-tools-kit` as a workaround because `swift test` was broken at the time (deadlocks, parallel-runner exhaustion, pre-existing test failures).

Today (2026-04-29), all of those test issues were fixed:
- `swift test --no-parallel` on macOS resolves the cooperative thread-pool deadlock
- `swift test --no-parallel` on Linux was added and passes green
- All pre-existing test failures were fixed: `CostBreakdownTests`, `ExecuteChainUseCaseTests`, `ClaudeSchemasTests`, `GitHubAppTokenServiceTests`, `SkillScannerTests`
- `ci.yml` now runs `swift test --package-path AIDevToolsKit --no-parallel` on both platforms and passes

The goal is to update `release.yml` so the `test` job runs real tests on both macOS and Linux. Upon both passing, the binary is built and tagged. Proof of success: trigger a new release (e.g. `v0.2.0`), watch tests pass on both platforms, confirm the release assets are published, then trigger `test-binary.yml` in `AIDevToolsDemo` to confirm the new binary downloads and runs cleanly.

## - [x] Phase 1: Update release.yml test job to run actual tests

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Replaced the `Build CLI` step with per-platform `Install system dependencies`, `Test (macOS)`, and `Test (Linux)` steps using `if: matrix.os` conditionals — mirroring `ci.yml` exactly so both platforms run `swift test --package-path AIDevToolsKit --no-parallel`.

**Skills to read**: `ai-dev-tools-swift-testing`

Replace the current `test` job's `Build CLI` step with `swift test --no-parallel`, mirroring exactly what `ci.yml` does. The Linux step also needs `Install system dependencies` (libcurl4/libxml2) which `ci.yml` already has.

**File:** `.github/workflows/release.yml`

Change the `test` job steps from:

```yaml
- name: Build CLI
  run: swift build -c release --product ai-dev-tools-kit --package-path AIDevToolsKit
```

To separate per-platform test commands (same pattern as `ci.yml`):

```yaml
- name: Install system dependencies
  if: matrix.os == 'ubuntu-latest'
  run: sudo apt-get install -y libcurl4-openssl-dev libxml2-dev

- name: Test (macOS)
  if: matrix.os == 'macos-latest'
  run: swift test --package-path AIDevToolsKit --no-parallel

- name: Test (Linux)
  if: matrix.os == 'ubuntu-latest'
  run: swift test --package-path AIDevToolsKit --no-parallel
```

No other changes — `build-macos`, `build-linux`, `release` jobs are correct as-is.

## - [ ] Phase 2: Trigger a new release and watch it pass

**Skills to read**: none

Run `./scripts/release.sh v0.2.0` from the AIDevTools repo root. Watch the `release.yml` workflow in GitHub Actions and confirm:

1. `Test (macos-latest)` passes (tests run, not just build)
2. `Test (ubuntu-latest)` passes
3. `Build macOS` and `Build Linux` jobs complete
4. GitHub Release `v0.2.0` is created with all three assets:
   - `ai-dev-tools-kit-macos-arm64.tar.gz`
   - `ai-dev-tools-kit-linux-x86_64.tar.gz`
   - `checksums.txt`

If the test job fails for any reason (new test failure exposed only in release/build mode), fix it and re-tag.

Note: `scripts/release.sh` guards against a dirty working tree and duplicate tags. Make sure Phase 1 changes are committed before running it.

## - [ ] Phase 3: Verify AIDevToolsDemo uses the new binary

**Skills to read**: none

Trigger `test-binary.yml` in `gestrich/AIDevToolsDemo` with version `v0.2.0`:

```
gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=v0.2.0
```

Then watch it complete:

```
gh run watch --repo gestrich/AIDevToolsDemo
```

Confirm:
- Binary downloads successfully
- Checksum verifies
- `ai-dev-tools-kit --help` exits 0
- `ai-dev-tools-kit prradar --help` exits 0

This is the proof-of-completion: a release was gated on real tests passing on both platforms, published, and consumed successfully by a downstream repo.

## - [ ] Phase 4: Add GitHub Attestations for build provenance

**Skills to read**: none

### Why attestations instead of a checksum or source-info.txt

The existing `checksums.txt` proves **integrity** (bytes haven't changed in transit), but not **provenance** (who built it, from what code, via what workflow). GitHub Attestations solve both:

- Cryptographically ties the binary to the exact Actions workflow run that produced it
- Records the source commit SHA, repo, and workflow ref in a signed statement stored on GitHub's transparency log
- Verifiable by any client with `gh attestation verify` — no GPG keys, no side-car files to maintain
- Directly answers "what commit is this binary from?" without a manual `source-info.txt`

This makes the commit-SHA pinning question moot: instead of encoding the commit in a filename or side-car, the attestation IS the cryptographic proof of provenance.

### Changes to release.yml

In the `build-macos` and `build-linux` jobs, add an attestation step after packaging. The `build-macos` job needs `id-token: write` and `attestations: write` permissions:

```yaml
permissions:
  contents: write
  id-token: write
  attestations: write
```

Then after the `Package` step in each build job:

```yaml
- name: Attest build provenance
  uses: actions/attest-build-provenance@v2
  with:
    subject-path: 'ai-dev-tools-kit-*.tar.gz'
```

### How clients verify

After downloading a release asset:

```bash
gh attestation verify ai-dev-tools-kit-linux-x86_64.tar.gz \
  --repo gestrich/AIDevTools
```

Output includes the commit SHA, workflow name, and run ID — proving the binary was produced by a legitimate workflow run from a specific commit in `gestrich/AIDevTools`, not just uploaded by someone with repo write access.

### README update (AIDevTools)

The top-level `README.md` should add a **Verifying the binary** section under the existing Installation section. It should:

- Explain that every release is attested via GitHub's build provenance
- Show the exact `gh attestation verify` command with the correct `--repo` flag
- Note that this is optional but recommended for security-sensitive environments
- Mention it requires the `gh` CLI (already required for the install script workflow)

### AIDevToolsDemo test-binary.yml update

Add a `gh attestation verify` step after the download and before running the binary, so automated consumers also verify provenance as part of their pipeline.

## - [ ] Phase 5: Validation

**Skills to read**: `ai-dev-tools-enforce`

- Run `ai-dev-tools-enforce` on `.github/workflows/release.yml`
- Confirm `ci.yml` still passes green (no regressions from this work)
- Confirm `v0.2.0` appears in `gh release list --repo gestrich/AIDevTools`
- Confirm `test-binary.yml` in AIDevToolsDemo passed for `v0.2.0`
- Confirm attestations are present: `gh attestation verify ai-dev-tools-kit-linux-x86_64.tar.gz --repo gestrich/AIDevTools` returns the correct commit SHA and workflow
- Confirm `test-binary.yml` in AIDevToolsDemo includes the `gh attestation verify` step and it passes
- Confirm README has a **Verifying the binary** section with the correct command
