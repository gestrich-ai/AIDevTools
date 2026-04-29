## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-swift-testing` | Test style guide and conventions |
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

`--no-parallel` was added to both test steps in `.github/workflows/ci.yml` as a blunt-instrument fix for cooperative-thread deadlocks caused by `Process().waitUntilExit()` calls in tests running in parallel on a 3-vCPU CI runner. Subsequently, all blocking tests were moved to the `SystemTests` target and disabled on CI via `.enabled(if: CI == nil)`.

Both mitigations now coexist: `--no-parallel` is used *and* blocking tests are disabled. The comment in `ci.yml` notes that parallel execution "still deadlocks on Swift 6.2 / macOS 14" even after disabling blocking tests — suggesting there may be additional parallelism issues beyond `Process().waitUntilExit()`.

This plan investigates whether `--no-parallel` is still required now that the known blocking tests are gone. Removing it would make CI test runs faster. The outcome also informs Plan g (`2026-04-29-g`), which adds `-c release` to `release.yml` and needs to know whether to include `--no-parallel` there as well.

---

## - [x] Phase 1: Remove `--no-parallel` from `ci.yml`

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Both `--no-parallel` flags were already removed from the macOS and Linux test steps in a prior commit (`dac0f1f`). The `::stop-commands::` wrapper, `--package-path AIDevToolsKit`, and all other settings remain intact. No additional code changes were required.

**Skills to read**: `ai-dev-tools-swift-testing`

**File:** `.github/workflows/ci.yml`

1. Read `ci.yml` and locate both `--no-parallel` flags — one in the macOS test step and one in the Linux test step.

2. Remove `--no-parallel` from both steps. Leave all other settings intact: the `::stop-commands::` wrapper, `--package-path AIDevToolsKit`, the Swift installation step on Linux, and the 60-minute timeout.

3. Commit and push to `main`.

---

## - [x] Phase 2: Watch CI and decide

**Skills used**: none
**Principles applied**: CI run `25137227099` (from `dac0f1f`, which removed `--no-parallel`) hit the 30-minute `timeout-minutes` on both Ubuntu and macOS test steps, confirming a deadlock. Both platforms still require `--no-parallel`. Re-added it to both steps with a comment noting `.enabled(if: CI == nil)` guards are insufficient and citing `dac0f1f` as the test evidence.

**Skills to read**: none

Wait for both `Test (macos-latest)` and `Test (ubuntu-latest)` jobs to complete:

```sh
gh run watch --repo gestrich/AIDevTools
```

**If both pass:** `--no-parallel` is no longer needed. Leave the removal in place. Update the comment in `ci.yml` to explain that blocking tests are now disabled via `SystemTests` + `.enabled(if: CI == nil)`, making parallel mode safe.

**If either fails with a deadlock or hang:** Re-add `--no-parallel` to the failing platform(s). Add a comment explaining that `.enabled(if: CI == nil)` guards are insufficient — there are parallelism issues beyond `Process().waitUntilExit()`. Note which platform(s) still require it.

Commit the final state and push to `main`.

---

## - [ ] Phase 3: Release and validate AIDevToolsDemo

**Skills to read**: none

Cut a new release to confirm the pipeline is fully healthy on both platforms and the Linux binary works end-to-end in AIDevToolsDemo.

1. Confirm the working tree is clean:
   ```sh
   git status --porcelain
   ```

2. Check the latest release tag, then run the release script with the next version:
   ```sh
   gh release list --repo gestrich/AIDevTools --limit 5
   ./scripts/release.sh vX.Y.Z
   ```

3. Watch the full Release workflow and confirm all five jobs pass:
   ```sh
   gh run watch --repo gestrich/AIDevTools
   ```
   - `Test (macos-latest)`
   - `Test (ubuntu-latest)`
   - `Build macOS`
   - `Build Linux`
   - `Create Release`

4. Trigger the end-to-end binary test in AIDevToolsDemo:
   ```sh
   gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=vX.Y.Z
   gh run watch --repo gestrich/AIDevToolsDemo
   ```

5. Confirm all steps pass: Resolve version, Download release assets, Verify checksum, Verify attestation, Install binary, `ai-dev-tools-kit --help` exits 0, `ai-dev-tools-kit prradar --help` exits 0.
