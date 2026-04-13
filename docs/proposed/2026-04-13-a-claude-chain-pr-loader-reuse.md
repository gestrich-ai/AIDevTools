## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement, use case conventions, dependency rules |
| `ai-dev-tools-composition-root` | How Mac app wires dependencies — how to pass new configs into use cases |
| `ai-dev-tools-debug` | CLI invocation paths, log locations, and how to run chain commands against a real repo |
| `ai-dev-tools-enforce` | Post-implementation standards check across all changed files |

## Background

The Claude Chain view (Chains tab) is slow on first open — 5+ seconds before any data appears. After the delay, data shows and per-project spinners appear.

**Root cause (two layers):**

**Layer 1 — Project list (spec/config files):** `listChains(source: .remote)` fetches `spec.md` and `configuration.yml` from each project's dedicated branch on GitHub via the git blob API. These files are the source of `ChainProject.tasks`. The core GitHub infrastructure already caches them by SHA (blob cache) and tree SHA (tree cache), with branch HEAD cached at a 5-minute TTL. When the Chains tab opens after that TTL expires — or on cold start — `listChains(source: .remote, useCache: true)` still hits GitHub to resolve the current branch HEAD before it can look up any cached content. This means the project names and task list don't appear until that round-trip completes.

**Layer 2 — PR enrichment:** `GetChainDetailUseCase.run()` fetches ALL 500 open PRs and ALL 500 merged PRs, filters client-side by branch prefix, then enriches every open PR by calling `gitHubPRService.reviews()` and `gitHubPRService.checkRuns()` directly — a bespoke fetch that duplicates what `GitHubPRLoaderUseCase.enrichPR()` already does. The raw review and check run data is then converted into Claude Chain-specific display types: `PRReviewStatus` (approvedBy / changesRequestedBy / pendingReviewers) and `PRBuildStatus` (a `.passing` / `.failing` / `.pending` / `.conflicting` / `.unknown` enum). These derived types are not duplicates — they are interpretive summaries computed from the raw `[GitHubReview]` and `[GitHubCheckRun]` arrays. After migration, they will be derived from the same raw data, just sourced via `PRMetadata.reviews` and `PRMetadata.checkRuns` from `GitHubPRLoaderUseCase` instead of separate calls. Everything else blocks until all enrichment is done.

**What we want:**

*For the project list (Phase 4):* A Claude Chain-owned file cache — one folder per project — that stores `spec.md` and `configuration.yml` directly on disk alongside a `project-cache.json` descriptor containing just the branch commit hash. On open, files are read from disk instantly with no GitHub call. On refresh, only a branch HEAD lookup is needed per project: if the commit hash is unchanged the cached files are used as-is; only changed projects re-download their files. The cache is entirely owned by `ClaudeChainService` with no dependency on `GitHubPRCacheService`.

*For PR enrichment (Phases 1–3):* Reuse `GitHubPRLoaderUseCase` — the same streaming use case already used by PRRadar's `AllPRsModel`. This gives:
1. **Cache-first loading**: emits `.cached([PRMetadata])` immediately from disk before any network call
2. **`updatedAt` comparison**: skips enrichment for PRs whose GitHub `updatedAt` hasn't changed — dramatically faster on refresh
3. **Granular event streaming**: emits `.fetched` (PR list without enrichment) then `.prUpdated` per PR — review/build status fills in progressively

`PRFilter` already supports `headRefNamePrefix` so we can scope each `execute(filter:)` call to a specific chain project's branch prefix (e.g., `"claude-chain-my-project-"`). The user notes we may also need GitHub label filtering (`PRFilter.labels`) if future chain projects use labels instead of branch naming conventions — this is included as an optional extension in Phase 1.

**What stays unchanged:**
- `ClaudeChainModel.chainDetails[projectName]` is already updated on every yield from `GetChainDetailUseCase.stream()` — it will naturally show partial data once the use case yields more frequently
- Merged PR handling: no enrichment needed; keep the simple list fetch for merged PRs
- `GetChainDetailUseCase.loadCached()`: preserved unchanged — reads the disk-cached PR index and individual PR/review/checkRun files

## Phases

## - [x] Phase 1: Add `GitHubServiceFactory.makeRepoConfig` factory (and optional `PRFilter.labels`)

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Added `makeRepoConfig` following the same pattern as `createPRService` — calls `createGitHubAPI`, computes `normalizedSlug` for the cache URL, derives `repoName` from `repoSlug`. Passed `token: nil` per spec (token resolved later by `GitHubPRLoaderUseCase` via account). Deferred `PRFilter.labels` — no callsite needs it yet.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

`GitHubPRLoaderUseCase` requires a `GitHubRepoConfig`. `ClaudeChainModel` currently only creates a `GitHubPRServiceProtocol` via `GitHubServiceFactory.createPRService(...)`. We need a way to produce `GitHubRepoConfig` from the same inputs (`repoPath`, `githubAccount`, `dataPathsService`).

**File:** `Sources/Services/GitHubService/GitHubServiceFactory.swift`

Add a new `async throws` factory method:
```swift
public static func makeRepoConfig(
    repoPath: String,
    githubAccount: String,
    dataPathsService: DataPathsService
) async throws -> GitHubRepoConfig
```

Implementation follows the same pattern as `createPRService`: call `createGitHubAPI(...)` to resolve the repo slug, compute `cacheURL` from `dataPathsService.path(for: .github(repoSlug: normalizedSlug))`, then return `GitHubRepoConfig(account: githubAccount, cacheURL: cacheURL, name: gitHub.repoName, repoPath: repoPath, token: nil)`.

**Optional: add `labels` support to `PRFilter`**

If chain projects will use GitHub labels as an alternative filtering mechanism, add:
- `public var labels: [String]?` to `PRFilter` (in `PRMetadata.swift`)
- A matching `init` parameter (default `nil`)
- A `matches(_:)` clause: if `labels` is non-nil, require `metadata.labels` to contain at least one matching label

Do not add this if no callsite needs it yet — defer until a concrete chain project requires label filtering. If added, keep `labels` alphabetically ordered in `PRFilter`'s property list.

## - [ ] Phase 2: Migrate `GetChainDetailUseCase` to use `GitHubPRLoaderUseCase`

**Skills to read**: `ai-dev-tools-architecture`

Replace the fetch-everything-then-yield approach in `GetChainDetailUseCase` with `GitHubPRLoaderUseCase`, giving the view progressive updates.

**File:** `Sources/Features/ClaudeChainFeature/usecases/GetChainDetailUseCase.swift`

**`init` change:**
Add `config: GitHubRepoConfig` as a parameter alongside the existing `gitHubPRService: any GitHubPRServiceProtocol`. The existing service is retained for:
- `loadCached()` (disk reads — no API client needed)
- Merged PR fetching (simple list + cache, no enrichment)

The new `config` is used exclusively to construct `GitHubPRLoaderUseCase`.

**`stream()` change:**
Replace the `run(options:)` call with a new private method `streamLive(options:continuation:)` that:
1. Creates `GitHubPRLoaderUseCase(config: config)` and calls `execute(filter: PRFilter(state: .open, headRefNamePrefix: options.project.branchPrefix))`
2. Handles events:
   - `.cached([])` — ignore (already yielded via `loadCached()` above)
   - `.cached(prs)` where `prs` is non-empty — build a basic `ChainProjectDetail` from these cached metadata and yield it (fast path even if `loadCached()` returned nil)
   - `.fetched(prs)` — build task list from basic metadata (no enrichment yet), yield `ChainProjectDetail` so tasks show without spinners
   - `.prFetchStarted(prNumber:)` — no-op (enrichment in progress; view already shows the task)
   - `.prUpdated(metadata)` — update the matching task's `EnrichedPR` with `metadata.reviews`, `metadata.checkRuns`, `metadata.isMergeable`; yield updated `ChainProjectDetail`
   - `.prFetchFailed` — log; leave the matching task without enrichment data
   - `.completed` — open-PR streaming done; proceed to merged PRs
3. After open-PR streaming completes, fetch merged PRs using the existing `gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .merged))` approach — filter by `branchPrefix`, build `EnrichedPR` with empty reviews and `.unknown` build status, merge into final detail, yield once more
4. Write the cache index (`gitHubPRService.writeCachedIndex(...)`) as before
5. Call `continuation.finish()`

**Remove the bespoke check run, review, and approval fetching:**

`GetChainDetailUseCase` currently calls `gitHubPRService.reviews(number:useCache:)` and `gitHubPRService.checkRuns(number:useCache:)` directly (lines 54–55 in the cached path, lines 108–109 in the network path). Both calls are redundant: `GitHubPRLoaderUseCase.enrichPR()` fetches exactly the same data, and the results arrive via `.prUpdated(PRMetadata)` as `metadata.reviews` and `metadata.checkRuns`. Delete both bespoke call sites. The same applies to approvals and pending reviewers — they are derived from `metadata.reviews`, not from a separate fetch.

**Add `isDraft` to `PRMetadata` (prerequisite):**

`EnrichedPR` currently copies `isDraft` from `GitHubPullRequest.isDraft`. `PRMetadata` does not yet carry `isDraft` — it is referenced in a comment (line 165) but not mapped.

- Add `public let isDraft: Bool` to `PRMetadata` (alphabetically ordered with existing properties)
- Map it in `GitHubPullRequest.toPRMetadata()`: `isDraft: isDraft`

This is a prerequisite for the `EnrichedPR` change below; do it first.

**Switch `EnrichedPR.pr` from `GitHubPullRequest` to `PRMetadata`:**

All fields accessed on `EnrichedPR.pr` across the codebase — `.number`, `.url`, `.mergedAt`, `.createdAt`, `.headRefName`, `.body` — are present on `PRMetadata`. With `isDraft` added above, `PRMetadata` covers everything.

File: `Sources/Services/ClaudeChainService/PREnrichment.swift`

Change the stored type:
```swift
public let pr: PRMetadata   // was: PRRadarModelsService.GitHubPullRequest
```

Update `init` and the derived properties:
```swift
public init(pr: PRMetadata, reviewStatus: PRReviewStatus, buildStatus: PRBuildStatus) {
    self.pr = pr
    self.isDraft = pr.isDraft
    self.reviewStatus = reviewStatus
    self.buildStatus = buildStatus
}
public var isMerged: Bool { pr.mergedAt != nil }
// ageDays: use pr.mergedAt ?? pr.createdAt (same field names, same optional pattern)
```

Update `taskHash(for:)` in `ChainProject` (currently takes `GitHubPullRequest`) to accept `PRMetadata` — the fields it accesses (`.headRefName`, `.body`) are present on `PRMetadata` with identical names.

After this change, building `EnrichedPR` from a `.prUpdated(PRMetadata)` event is direct:
```swift
EnrichedPR(
    pr: metadata,
    reviewStatus: PRReviewStatus(reviews: metadata.reviews ?? []),
    buildStatus: PRBuildStatus.from(checkRuns: metadata.checkRuns ?? [], isMergeable: metadata.isMergeable)
)
```

No re-read of `GitHubPullRequest` from the disk cache is needed.

## - [ ] Phase 3: Wire `ClaudeChainModel` to provide `GitHubRepoConfig`

**Skills to read**: `ai-dev-tools-composition-root`

**File:** `Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift`

Add a cached `gitHubRepoConfig: GitHubRepoConfig?` field alongside `gitHubPRService`.

Update `makeOrGetGitHubPRService(repoPath:)` or add a parallel `makeOrGetGitHubRepoConfig(repoPath:)` that calls `GitHubServiceFactory.makeRepoConfig(repoPath:githubAccount:dataPathsService:)` and caches the result. Reset the cached config alongside `gitHubPRService` when `currentRepoPath` changes (the `if currentRepoPath?.path != repoPath.path` guard in `loadChains`).

Update `loadChainDetail(project:)` to:
```swift
let service = try await makeOrGetGitHubPRService(repoPath: repoPath)
let config = try await makeOrGetGitHubRepoConfig(repoPath: repoPath)
let useCase = GetChainDetailUseCase(gitHubPRService: service, config: config)
```

No other changes to `ClaudeChainModel` — the existing `for try await detail in useCase.stream(...)` loop already writes each intermediate yield to `chainDetails[projectName]`, so the view sees progressive updates automatically.

**Also fix `StatusCommand` (same phase):**

`Sources/Apps/ClaudeChainCLI/StatusCommand.swift` calls `GetChainDetailUseCase(gitHubPRService: prService)` directly and uses `.run()`. After Phase 2 adds `config: GitHubRepoConfig` to the init, this call site breaks. Update `StatusCommand` to:
1. Create a `GitHubRepoConfig` via `GitHubServiceFactory.makeRepoConfig(repoPath: repoURL.path, githubAccount: resolvedAccount, dataPathsService: dataPathsService)` where `resolvedAccount` is derived from the resolved credential (same account already used for `createPRService`)
2. Pass `config` to `GetChainDetailUseCase(gitHubPRService: prService, config: config)`
3. Keep calling `.run()` — `StatusCommand` doesn't need streaming since it's a synchronous CLI output command

## - [ ] Phase 4: Add Claude Chain Project Cache (Per-Project, Commit-Hash Invalidation)

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-configuration-architecture`

Read `ai-dev-tools-configuration-architecture` before implementing — it governs `ServicePath`, `DataPathsService`, and the data directory structure.

The project list (task names, baseBranch, kind) comes from parsing `spec.md` and `configuration.yml` fetched from each project's branch. Every refresh today requires a GitHub API call before anything can be shown. This phase adds a Claude Chain-owned file cache so the app can read project data from disk instantly on open, and only re-downloads files when the branch has actually changed.

---

**Directory structure**

Each chain project gets one folder. Inside it: `project-cache.json` (a descriptor) and `file-cache/` (the cached files, mirroring their path in the repo):

```
ai-dev-tools/
  services/
    claude-chain-service/
      <repoSlug>/
        <projectName>/
          project-cache.json          ← { "commitHash": "a3f8c2d1e9b4..." }
          file-cache/
            claude-chain/
              <projectName>/
                spec.md
                configuration.yml
```

`file-cache/` mirrors the path where these files live in the repo (`claude-chain/<projectName>/`), so paths are predictable and new file types can be added later without changing the structure.

`project-cache.json` is a sibling to `file-cache/` — it describes the state of that cache, not the content:
```json
{ "commitHash": "a3f8c2d1e9b4..." }
```

---

**`ServicePath` addition**

File: `Sources/Services/DataPathsService/ServicePath.swift`

Add one case (keep alphabetically sorted):

```swift
case claudeChainProject(repoSlug: String, projectName: String)
// → "services/claude-chain-service/{repoSlug}/{projectName}/"
```

`DataPathsService.path(for:)` auto-creates the directory.

---

**New type: `ChainProjectCache`**

File: `Sources/Services/ClaudeChainService/ChainProjectCache.swift`

```swift
public struct ChainProjectCache: Sendable {
    private let projectDirectory: URL  // .claudeChainProject resolved path

    public struct Descriptor: Codable, Sendable {
        public let commitHash: String   // branch HEAD SHA at last fetch
    }

    public func readDescriptor() throws -> Descriptor?
    public func writeDescriptor(_ descriptor: Descriptor) throws

    public func readFile(at repoRelativePath: String) throws -> String?
    public func writeFile(_ content: String, at repoRelativePath: String) throws
    // repoRelativePath examples: "claude-chain/my-project/spec.md"
    //                             "claude-chain/my-project/configuration.yml"
    // Files are written to: projectDirectory/file-cache/<repoRelativePath>
}
```

- `readDescriptor()` — reads `project-cache.json`; returns `nil` on missing file or decode failure
- `writeDescriptor(_:)` — atomically writes `project-cache.json` (write to `.tmp`, rename)
- `readFile(at:)` — reads from `file-cache/<repoRelativePath>`; returns `nil` if absent
- `writeFile(_:at:)` — writes to `file-cache/<repoRelativePath>`, creating intermediate directories

No parsed model data is stored — `ChainProject` is always derived by parsing the cached files through the same path as a live fetch.

---

**Cold-open flow (no GitHub calls):**

```
1. Scan services/claude-chain-service/<repoSlug>/ for subdirectories → [projectName]
2. For each projectName:
     read project-cache.json → Descriptor (if absent: skip this project)
     read file-cache/claude-chain/<projectName>/spec.md
     read file-cache/claude-chain/<projectName>/configuration.yml
     parse both → ChainProject
3. Assemble ChainListResult → yield immediately
```

---

**Refresh flow — commit hash comparison:**

```
1. Fetch current branch HEAD commit SHA (GitHubPRService.branchHead() — one API call per project)
2. Compare with Descriptor.commitHash
   → same hash: files unchanged; parse from file-cache; no network needed
   → different hash (or no cache): download spec.md + configuration.yml from GitHub;
       write to file-cache/<path>; write new Descriptor with new commitHash
3. Parse from file-cache → yield updated ChainListResult
4. Write updated ChainProjectIndex with full project name list
```

A refresh with no branch file changes costs one branch HEAD API call per project — no file downloads.

**Where this logic lives:**  
Extend `GitHubChainProjectSource` to accept a `ChainProjectCache` per project and apply the commit-hash comparison before fetching. The cache is read and written inside the source; `ListChainsUseCase` passes the cache in but does not inspect SHA details.

---

**Wire into `ListChainsUseCase`**

File: `Sources/Features/ClaudeChainFeature/usecases/ListChainsUseCase.swift`

Replace the existing two-step `stream()` with:

```
1. Read ChainProjectIndex + ChainProjectCache per project → yield immediately (no GitHub)
2. Run listChains(source: .remote) with commit-hash comparison
   → only re-downloads files for changed/new projects
   → yield updated result; write updated ChainProjectCache entries
```

`ListChainsUseCase` receives `DataPathsService` and `repoSlug` at init. `ClaudeChainModel` already holds `DataPathsService` — pass it through.

**`StatusCommand` does not need this** — synchronous CLI tool where cold-start latency is acceptable.

## - [ ] Phase 5: Enforce + Fix Architecture

**Skills to read**: `ai-dev-tools-enforce`

Run `ai-dev-tools-enforce` in Fix mode on every Swift file modified during Phases 1–4. Address all reported violations before moving to validation. Common issues to watch for:

- Force unwraps introduced during event-mapping logic
- Raw string literals that should be constants
- Layer violations: `GetChainDetailUseCase` (in `ClaudeChainFeature`) importing `GitHubService` directly is already established; confirm no new cross-layer imports were added
- Dead code or unused variables left from the `run()` refactor
- `ChainProjectCache` placed in the correct layer (`ClaudeChainService`, not `ClaudeChainFeature` or a Mac-only target)
- Alphabetical ordering of properties/imports in modified files

Do not proceed to Phase 6 until `ai-dev-tools-enforce` reports no remaining violations.

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-debug`

Read `ai-dev-tools-debug` first to get the correct CLI binary path and invocation pattern for `claude-chain` commands.

**Build and test:**
1. `swift build` — must be clean with no new warnings.
2. `swift test` — all existing tests pass.

**CLI verification against `AIDevToolsDemo`:**

Run `claude-chain status` against the `AIDevToolsDemo` repo to verify PR status data is accurate after the migration. Use `ai-dev-tools-debug` to get the binary path and credential flags.

Expected invocation (exact flags from debug skill):
```
<claude-chain-binary> status --github-account <account> --repo-path <path-to-AIDevToolsDemo>
```

Verify the output:
- Each project's tasks appear with PR numbers
- Build status indicators (✅/❌/⏳) match the actual GitHub check run state for those PRs
- Review status indicators reflect actual approvals/pending reviewers on GitHub
- Merged tasks show `❓ Build` (`.unknown`) — confirm no enrichment is attempted for merged PRs

If `claude-chain status` is not yet wired to the new `GitHubPRLoaderUseCase` path (it still calls `.run()` directly), the output should still be correct — this command tests data accuracy, not streaming behavior.

**If a new CLI command is needed for streaming verification**, extend `StatusCommand` with a `--stream` flag that calls `GetChainDetailUseCase.stream()` and prints each intermediate yield (with a separator line between yields so intermediate states are visible). Only add this if the Mac app smoke-check is insufficient to verify the streaming path.

**Mac app smoke-check:**
- Launch the Mac app → open the Chains tab for the same `AIDevToolsDemo` repo
- **Cold cache:** delete the `claude-chain-service/` cache directory (path from `ai-dev-tools-debug`), relaunch — brief loading state, then project names/tasks appear once the first network fetch completes
- **Warm cache:** relaunch without clearing anything — project names and tasks appear instantly from `ChainProjectCache` file-cache, no GitHub call
- **PR status:** review/build badges fill in progressively per task without blocking the task list display
- **Refresh — no file changes:** trigger a manual refresh without touching any branch files — confirm via logs that no blob downloads occur (only a branch HEAD call per project)
- **Refresh — files changed:** see commit-hash invalidation test below

**Commit-hash invalidation test against `AIDevToolsDemo`:**

This test verifies the cache correctly detects when branch files change and re-downloads, but does NOT re-download when they haven't.

1. Ensure `ChainProjectCache` is populated for at least one project in `AIDevToolsDemo` (run once to warm it)
2. Record the current `commitHash` value stored in that project's `project-cache.json`
3. Run `claude-chain status` again without touching any branch files → confirm the `commitHash` is unchanged and no blob downloads occurred (check logs via `ai-dev-tools-debug`)
4. Mutate a chain project's `spec.md` on its branch in `AIDevToolsDemo` (e.g., add a comment line or a new `- [ ]` task), commit, and push to the branch
5. Run `claude-chain status` (or trigger a refresh in the Mac app) → confirm:
   - The `commitHash` in `project-cache.json` is updated to the new commit SHA
   - The updated `spec.md` content is reflected in the task list
   - Other projects whose branches were NOT touched show no blob download activity in logs
6. Revert the `spec.md` mutation and push to restore `AIDevToolsDemo` to its original state

Use `ai-dev-tools-debug` to locate the `project-cache.json` file paths and the log output showing blob fetch vs. cache-hit decisions.

**Confirm no regressions:**
- `GetChainDetailUseCase.loadCached()` still yields data on cache hit
- Merged PRs still show `.unknown` build status
- `project-cache.json` `commitHash` updates after each successful network fetch for that project
- `file-cache/` content matches the current branch files for each project
