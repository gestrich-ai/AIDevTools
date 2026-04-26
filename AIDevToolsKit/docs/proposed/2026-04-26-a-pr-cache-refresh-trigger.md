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

## - [ ] Phase 1: Add `lastCheckedAt` persistence per repo

Store and retrieve a `lastCheckedAt` timestamp scoped to each repo config. Location: a small JSON file in the repo's existing cache/output directory, following the same pattern as other per-repo data files.

- Define the storage file path (e.g., `outputDir/cache-refresh-state.json`)
- Write `lastCheckedAt = Date()` after each successful date-range refresh
- Read on fetch; fall back to `Date() - 60 days` if the file is absent (first run)

## - [ ] Phase 2: Add date-range cache refresh inside the existing fetch path

Inside `GitHubPRLoaderUseCase.execute(filter:)`, before running the existing filtered fetch, add a silent date-range refresh step:

- Call `updatePRs` with `PRFilter(dateFilter: .updatedSince(lastCheckedAt))` — no state, no author, no branch filter
- This updates the on-disk cache for any PR that changed since the last fetch (including PRs that closed or merged)
- On success, write the new `lastCheckedAt` timestamp
- On failure, log and continue — the caller's filtered fetch still proceeds normally; a failed refresh is non-fatal
- Do not emit new `Event` cases for this step; it is transparent to callers

After this step completes, the existing fetch logic continues unchanged: `updatePRs(filter:)` is called with the caller's filter, and filtered results are returned.

## - [ ] Phase 3: Revert `fetchedNumbers` workaround

Now that the cache is kept current by the date-range refresh, revert the `fetchedNumbers` filter in `GitHubPRLoaderUseCase` (lines 83–88) back to `filter.matches($0)`. Add a short comment explaining the invariant: the cache is authoritative because the date-range refresh runs before each filtered fetch and catches all state transitions.

## - [ ] Phase 4: Validation

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`

- Build succeeds: `swift build --product ai-dev-tools-kit`
- Run enforce on all files changed during this plan
- Manual smoke test: trigger a fetch, verify a recently-closed PR's cache entry updates to closed state
- Confirm the `fetchedNumbers` revert does not reintroduce the stale-state bug
