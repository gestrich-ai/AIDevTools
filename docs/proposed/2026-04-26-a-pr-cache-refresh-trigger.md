# PR Cache Refresh Trigger (Date-Range Fetch)

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement and dependency rules for this codebase |
| `ai-dev-tools-composition-root` | How shared services are wired in the Mac app and CLI |
| `ai-dev-tools-enforce` | Post-implementation standards verification |
| `swift-architecture` | Architecture guidance for planning |

---

## Background

The disk cache (`gh-pr.json` per PR) is intended to be the source of truth for PR state. The problem today is that `updatePRs(filter:)` only fetches PRs matching the caller's filter (typically `state=open`). When a PR closes, its cache entry is never updated — it stays `state=OPEN` indefinitely. This caused a bug in `GitHubPRLoaderUseCase` that was patched with a `fetchedNumbers` whitelist workaround, which is itself a symptom of the deeper problem.

The fix: inside the existing fetch path, before returning filtered results, silently refresh the cache for **all PRs updated since a stored `lastCheckedAt` timestamp**, with no state or author/branch filter. This catches PRs transitioning to closed/merged and keeps the cache authoritative.

**Key design decisions:**

- **Not a new use case or command.** The date-range cache refresh is an implementation detail baked into the existing fetch path (e.g., `GitHubPRLoaderUseCase`). Callers see no API change — they still pass a filter and receive filtered results. The cache refresh happens silently before the filtered results are returned.
- **Applies to both Mac app and CLI.** Because the change lives at the use case level, it benefits both consumers automatically.
- **Follows existing fetch scheduling.** No new trigger, timer, or background task. The refresh runs whenever the existing fetch logic decides to fetch — no scheduling changes needed.
- **Covers all configured repos.** The refresh follows the same repo scope as the existing fetch — no special per-repo selection logic.
- **Pure date-range, no config filters.** The date-range refresh ignores author, branch, and state filters. It fetches all PRs updated since `lastCheckedAt` regardless of config. The filtered results returned to the caller still respect config filters.
- **Uses `PRDateFilter.updatedSince(Date)` with no `state` filter** → GitHub API returns `state=all`, sorted by `updated_at`, with early-stop pagination (all already supported).
- **Store `lastCheckedAt` per repo** after each successful refresh. First-run fallback: `Date() - 60 days` to give the cache a meaningful baseline. Each subsequent run uses `lastCheckedAt` as the `updatedSince` date, so the window self-adjusts.
- **Enrichment is handled automatically.** `GitHubPRLoaderUseCase` already skips re-enrichment for PRs whose `updatedAt` hasn't changed (the `isUnchanged` check at line 110). PRs returned by the date-range refresh will have a changed `updatedAt`; if they also pass the caller's filter, full enrichment (comments, check runs, isMergeable) is triggered automatically. PRs that exited the filter (e.g., just closed) get their list-entry cache updated but are not enriched — that is sufficient to fix the stale-state bug.
- **Progress/UI follows existing flow.** The date-range refresh emits through the same `Event` stream as the rest of the fetch, so progress feedback is unchanged.
- **Revert `fetchedNumbers` workaround after this lands.** The `fetchedNumbers` whitelist in `GitHubPRLoaderUseCase` (lines 83–88) was a patch for the stale-state bug. Once the cache is kept current by the date-range refresh, revert to `filter.matches($0)` and add a comment explaining the invariant.

---

## Phases

## - [x] Phase 1: Add `lastCheckedAt` persistence per repo

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `CacheRefreshState` (Codable, Sendable struct) as a new file in the GitHubService layer, following the same pattern as `AuthorCache`. Added `readCacheRefreshState()` / `writeCacheRefreshState(_:)` to the existing `GitHubPRCacheService` actor with a `cacheRefreshStateURL()` helper pointing to `cache-refresh-state.json` in the repo cache root. A static `fallbackDate` property on `CacheRefreshState` returns `Date() - 60 days` for use at call sites when no stored state exists. URLs section reorganised alphabetically.

Store and retrieve a `lastCheckedAt` timestamp scoped to each repo config. Location: a small JSON file in the repo's existing cache/output directory, following the same pattern as other per-repo data files.

- Define the storage file path (e.g., `outputDir/cache-refresh-state.json`)
- Write `lastCheckedAt = Date()` after each successful date-range refresh
- Read on fetch; fall back to `Date() - 60 days` if the file is absent (first run)

## - [x] Phase 2: Add date-range cache refresh inside the existing fetch path

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `readCacheRefreshState()` / `writeCacheRefreshState(_:)` to `GitHubPRServiceProtocol` and `GitHubPRService` (delegating to the cache actor), following the same pattern as `loadAllAuthors`. Inserted the date-range refresh step in `GitHubPRLoaderUseCase.execute(filter:)` right after `makeService()` succeeds, so the subsequent `readAllCachedPRs()` call picks up the freshened cache state. The refresh is non-fatal: `readCacheRefreshState` failures fall back silently to the 60-day window; any `updatePRs` or `writeCacheRefreshState` failure is logged as a warning and the caller's filtered fetch proceeds normally.

Inside `GitHubPRLoaderUseCase.execute(filter:)`, before running the existing filtered fetch, add a silent date-range refresh step:

- Call `updatePRs` with `PRFilter(dateFilter: .updatedSince(lastCheckedAt))` — no state, no author, no branch filter
- This updates the on-disk cache for any PR that changed since the last fetch (including PRs that closed or merged)
- On success, write the new `lastCheckedAt` timestamp
- On failure, log and continue — the caller's filtered fetch still proceeds normally; a failed refresh is non-fatal
- Do not emit new `Event` cases for this step; it is transparent to callers

After this step completes, the existing fetch logic continues unchanged: `updatePRs(filter:)` is called with the caller's filter, and filtered results are returned.

## - [x] Phase 3: Revert `fetchedNumbers` workaround

**Skills used**: none
**Principles applied**: Removed the `fetchedNumbers` set and replaced `.filter { fetchedNumbers.contains($0.number) }` with `.filter { filter.matches($0) }` in `postFetchCached`. Updated the comment to explain the invariant: the date-range refresh (Phase 2) runs before each filtered fetch and keeps the cache authoritative for all state transitions.

Now that the cache is kept current by the date-range refresh, revert the `fetchedNumbers` filter in `GitHubPRLoaderUseCase` (lines 83–88) back to `filter.matches($0)`. Add a short comment explaining the invariant: the cache is authoritative because the date-range refresh runs before each filtered fetch and catches all state transitions.

## - [x] Phase 4: End-to-end test with AIDevToolsDemo

**Skills used**: none
**Principles applied**: Used `gestrich/AIDevToolsDemo` as the live test target. The correct CLI command is `ai-dev-tools-kit prradar refresh --config AIDevToolsDemo` (not `pr-radar refresh`). The cache root is `~/Desktop/ai-dev-tools/services/github/gestrich-AIDevToolsDemo/` (the CLI resolves data root from `~/Desktop/ai-dev-tools`, not `~/Library/Application Support/AIDevToolsKit/`). All five verification steps passed: `cache-refresh-state.json` was written, new PR cache files appeared, `updatedAt` timestamps advanced after mutations, `lastCheckedAt` advanced, and closing PR #19 caused its `gh-pr.json` to update to `"state": "closed"` while dropping it from the open-PR count (7→6). The date-range `state=all` fetch correctly triggered early-stop on encountering PRs older than `lastCheckedAt`.

Use `gestrich/AIDevToolsDemo` as a live test target. Its cache dir is `~/Library/Application Support/AIDevToolsKit/github/gestrich-AIDevToolsDemo/`. The CLI command for fetching is `pr-radar refresh --config AIDevToolsDemo` (run from the AIDevTools repo after `swift build`).

**Step 1 — Create sample PRs**

In the `AIDevToolsDemo` local repo (`../AIDevToolsDemo`):
- Create two branches (`e2e-test-a`, `e2e-test-b`), make a trivial commit on each (e.g., append a line to `README.md`)
- Push both branches: `git push origin e2e-test-a e2e-test-b`
- Open two draft PRs via `gh pr create --draft --repo gestrich/AIDevToolsDemo`

**Step 2 — Initial fetch (first-run, no `lastCheckedAt`)**

```
swift run --package-path AIDevToolsKit pr-radar refresh --config AIDevToolsDemo
```

Verify:
- `cache-refresh-state.json` was written to the AIDevToolsDemo cache dir, and contains a `lastCheckedAt` timestamp
- `gh-pr.json` files exist for the two new PR numbers under the cache dir
- Both PRs appear in the refresh output

**Step 3 — Mutate the PRs**

- Push a new commit to `e2e-test-a`'s branch: `git commit --allow-empty -m "trigger update" && git push origin e2e-test-a`
- Edit the description of the `e2e-test-b` PR: `gh pr edit <number> --body "updated description" --repo gestrich/AIDevToolsDemo`

**Step 4 — Second fetch (date-range should pick up only the two changed PRs)**

Run `pr-radar refresh --config AIDevToolsDemo` again.

Verify:
- The date-range refresh fetched only the two mutated PRs (check logs — the unchanged PRs from prior runs should not appear in the date-range window)
- The `gh-pr.json` files for `e2e-test-a` and `e2e-test-b` show a newer `updatedAt` than after Step 2
- `lastCheckedAt` in `cache-refresh-state.json` advanced

**Step 5 — Close a PR and verify state propagates**

- Close (do not merge) the `e2e-test-a` PR: `gh pr close <number> --repo gestrich/AIDevToolsDemo`
- Run `pr-radar refresh --config AIDevToolsDemo` again

Verify:
- The `gh-pr.json` for the closed PR now shows `"state": "closed"` (not `"open"`)
- The closed PR does NOT appear in the filtered refresh output (the caller's `state=open` filter excludes it)
- The `fetchedNumbers` revert (Phase 3) did not surface the stale-state PR in results

**Step 6 — Cleanup**

Close the remaining sample PRs and delete the test branches:
```
gh pr close <e2e-test-b-number> --repo gestrich/AIDevToolsDemo
git push origin --delete e2e-test-a e2e-test-b
```

## - [ ] Phase 5: Validation

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`

- Build succeeds: `swift build --product ai-dev-tools-kit`
- Run enforce on all files changed during this plan
