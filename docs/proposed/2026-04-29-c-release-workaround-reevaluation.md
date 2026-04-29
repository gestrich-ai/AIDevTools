## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |
| `ai-dev-tools-swift-testing` | Test style guide and conventions |

## Background

The binary release pipeline (`v0.1.0`–`v0.3.0`) was built under pressure: every
problem surfaced sequentially in a clean CI environment, so each fix was the
minimum needed to get green. This produced four changes that were explicitly
flagged as workarounds in `2026-04-29-b-release-process-change-inventory.md`:

1. **`--no-parallel` in CI/release workflows** — added to stop cooperative-thread
   deadlocks. Blocking tests were *also* disabled via `.enabled(if: CI == nil)`.
   Both mitigations coexist; it is unknown whether `--no-parallel` is still needed
   now that the blocking tests are gone.

2. **`ConfigurationEditSheet.swift` `@ViewBuilder` extraction** (`c4409f0`) — 178-line
   refactor that extracted `ForEach` bodies into helper methods to work around a
   Swift 6.2 `setLocalDiscriminator` crash. The original inline code may now compile
   cleanly if the compiler bug has been fixed.

3. **`InlineCommentView.swift` `if let` → `!= nil`** (`261e768`) — changed an
   idiomatic `if let x = x` binding to `x != nil` to avoid a Swift 6.2 internal
   crash on unused bindings.

4. **Release tests run in debug mode** — `release.yml`'s test step omits `-c release`
   because that mode triggered a signal-6 compiler crash on `AIDevToolsKitMac`. The
   published binary is built in release mode, so tests and the binary currently use
   different optimization levels.

The goal of this plan is to investigate each item in isolation, keep only what is
still required, and validate everything with a new release (`v0.4.0`) confirmed to
work in `gestrich/AIDevToolsDemo`.

**Success criterion**: `./scripts/release.sh v0.4.0` triggers a workflow where
tests pass on both platforms, the binary is published, and `test-binary.yml` in
AIDevToolsDemo confirms the Linux binary runs `--help` and `prradar --help` with
exit code 0.

---

## - [x] Phase 1: Test removing `--no-parallel` from CI

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Removed `--no-parallel` from both the Linux and macOS test steps in `ci.yml`. Also removed the stale comment on the macOS step that documented the now-removed flag's rationale. The `stop-commands` wrapper and `--package-path` settings were left intact. CI will determine whether parallel execution is safe now that the blocking tests are disabled via `.enabled(if: CI == nil)`.

**Skills to read**: `ai-dev-tools-swift-testing`

The blocking tests that caused the original deadlock are now disabled on CI via
`.enabled(if: CI == nil)` and live in the `SystemTests` target. Remove `--no-parallel`
from `ci.yml`, push to `main`, and let the CI run decide whether it is still needed.

**Files:** `.github/workflows/ci.yml`

Steps:

1. Read `ci.yml` to find both `--no-parallel` flags (one in the macOS test step,
   one in the Linux test step).

2. Remove `--no-parallel` from both test steps. Leave all other CI settings intact —
   `::stop-commands::` wrapper, `--package-path`, Swift install, etc.

3. Commit and push to `main`. Watch the `CI` workflow via `gh run watch` or the
   Actions tab. Wait for both the `Test (macos-latest)` and `Test (ubuntu-latest)`
   jobs to complete.

**Decision point:**

- **If both pass green**: `--no-parallel` is no longer needed. Leave the change in
  place and update `ci.yml`'s comments to reflect the current situation.

- **If either fails with a deadlock/hang**: Re-add `--no-parallel` to the failing
  platform(s). Add a comment explaining that `.enabled(if: CI == nil)` guards are
  not sufficient — there are additional parallelism issues beyond
  `Process().waitUntilExit()`. The investigation is still valuable: we now know
  precisely which tests deadlock in parallel mode.

Note: `release.yml` is intentionally *not* changed in this phase — validate `ci.yml`
first before touching the release workflow.

---

## - [ ] Phase 2: Investigate Swift 6.2 `ForEach` workaround in `ConfigurationEditSheet.swift`

**Skills to read**: none

Commit `c4409f0` extracted the `ForEach` bodies in `rulePathsSection` and
`runCommandsSection` into `@ViewBuilder` helper methods to avoid a
`setLocalDiscriminator` assertion failure in Swift 6.2. Determine whether this bug
is still present with the current toolchain.

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/ConfigurationEditSheet.swift`

Steps:

1. Read the current `ConfigurationEditSheet.swift` to understand exactly what was
   extracted by `c4409f0`. The helpers are `@ViewBuilder` methods called from within
   `ForEach` closures in `rulePathsSection` and `runCommandsSection`.

2. Inline the `@ViewBuilder` helper bodies back into the `ForEach` closures to
   restore the original structure. This is the pattern that previously crashed Swift 6.2.

3. Build the Mac app locally: `swift build --package-path AIDevToolsKit`. Check
   whether the build succeeds or crashes with a `setLocalDiscriminator` assertion.

**Decision point:**

- **If build succeeds**: The Swift 6.2 compiler bug is resolved in the current
  toolchain. Commit the revert.

- **If build crashes (assertion failure / signal 6)**: The bug is still present.
  Revert the test change, leave `c4409f0` in place, and add a comment to the file
  referencing the upstream Swift bug so it can be revisited in a future toolchain
  update. Document the outcome in this plan's **Principles applied** field.

Note: the extracted `@ViewBuilder` helpers may be a net readability improvement even
if the bug is fixed. Use judgment when deciding whether to revert — readability of
the result matters.

---

## - [ ] Phase 3: Investigate Swift 6.2 `if let` workaround in `InlineCommentView.swift`

**Skills to read**: none

Commit `261e768` changed an `if let x = x` pattern to `x != nil` in
`InlineCommentView.swift` to avoid a Swift 6.2 internal crash on unused `if let`
bindings. Determine whether this bug is still present.

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/GitViews/InlineCommentView.swift`

Steps:

1. Read the file and locate the `!= nil` check introduced by `261e768`.

2. Revert it to the original `if let x = x` binding pattern.

3. Build locally with `swift build --package-path AIDevToolsKit`. Check whether the
   build succeeds or crashes.

**Decision point:**

- **If build succeeds**: Commit the revert. The `if let x = x` form is more idiomatic.

- **If build crashes**: Revert, leave the `!= nil` check in place with a comment
  referencing the Swift 6.2 crash and the workaround rationale.

---

## - [ ] Phase 4: Test release-mode tests in `release.yml`

**Skills to read**: none

The `release.yml` test job currently runs `swift test --no-parallel` without
`-c release`. The binary itself is built with `-c release`. These use different
optimization levels, so a bug that only manifests in release mode could ship
undetected.

Commit `2677d3f` switched macOS tests to debug mode because `swift test -c release`
triggered a signal-6 compiler crash on `AIDevToolsKitMac`. Determine whether this
crash still occurs.

**File:** `.github/workflows/release.yml`

Steps:

1. Determine the outcome of Phase 1 (was `--no-parallel` removed or kept?). This
   phase builds on that result — apply the same `--no-parallel` decision to this
   step.

2. Modify the `Test (macOS)` and `Test (Linux)` steps in `release.yml`'s `test` job
   to add `-c release`:

   ```yaml
   - name: Test (macOS)
     if: matrix.os == 'macos-latest'
     run: swift test -c release --package-path AIDevToolsKit [--no-parallel if needed]

   - name: Test (Linux)
     if: matrix.os == 'ubuntu-latest'
     run: swift test -c release --package-path AIDevToolsKit [--no-parallel if needed]
   ```

3. To test this without publishing a real release, push a pre-release tag:
   ```sh
   git tag v0.4.0-rc.1
   git push origin v0.4.0-rc.1
   ```
   Watch the `Test` matrix jobs in the `Release` workflow. The build and release
   jobs will likely fail (draft release behavior is fine) — only the test results
   matter here. After observing, delete the test tag:
   ```sh
   git push origin --delete v0.4.0-rc.1
   ```

**Decision point:**

- **If test job passes on both platforms**: The release-mode compiler crash is
  resolved. Keep `-c release` in the test step.

- **If test job fails with a compiler crash on `AIDevToolsKitMac`**: The Swift 6.2
  bug is still present. Revert to debug mode tests, add a comment in `release.yml`
  explaining that `-c release` causes signal 6 on this module and should be retried
  when the toolchain is next updated.

---

## - [ ] Phase 5: Create release `v0.4.0` and validate AIDevToolsDemo

**Skills to read**: none

With all reevaluation decisions made in Phases 1–4, create the final release. This
is proof that the current codebase — with only the workarounds still genuinely
required — produces a working binary that downstream clients can use.

Steps:

1. Confirm the working tree is clean: `git status --porcelain` should produce no output.

2. Run the release script:
   ```sh
   ./scripts/release.sh v0.4.0
   ```

3. Watch the full `Release` workflow via `gh run watch --repo gestrich/AIDevTools`.
   Confirm all five jobs pass:
   - `Test (macos-latest)`
   - `Test (ubuntu-latest)`
   - `Build macOS`
   - `Build Linux`
   - `Create Release`

4. Confirm `v0.4.0` appears in `gh release list --repo gestrich/AIDevTools` with
   all three assets: `ai-dev-tools-kit-macos-arm64.tar.gz`,
   `ai-dev-tools-kit-linux-x86_64.tar.gz`, `checksums.txt`.

5. Trigger the end-to-end binary test in AIDevToolsDemo:
   ```sh
   gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=v0.4.0
   gh run watch --repo gestrich/AIDevToolsDemo
   ```

6. Confirm `test-binary.yml` completes with all steps green:
   - Resolve version
   - Download release assets
   - Verify checksum
   - Verify attestation (`gh attestation verify`)
   - Install binary
   - `ai-dev-tools-kit --help` exits 0
   - `ai-dev-tools-kit prradar --help` exits 0

7. Run `ai-dev-tools-enforce` on all files modified during Phases 1–4.

---

## - [ ] Phase 6: Update `release-process-change-inventory.md`

**Skills to read**: none

Update `2026-04-29-b-release-process-change-inventory.md` to reflect the outcomes
of each phase: which workarounds were removed, which were confirmed still necessary,
and what was learned. This keeps the inventory accurate as a reference for future
toolchain upgrades.

For each reevaluation candidate in the inventory, replace the **⚠️ Candidate for
reevaluation** note with a concluded status:
- If removed: "Confirmed unnecessary as of `v0.4.0` / Swift X.Y.Z, removed in commit `<sha>`."
- If kept: "Confirmed still required as of `v0.4.0` / Swift X.Y.Z. Revisit when toolchain is next updated."
