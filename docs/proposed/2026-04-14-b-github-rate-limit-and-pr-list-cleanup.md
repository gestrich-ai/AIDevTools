## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-code-quality` | Code quality review — force unwraps, duplicated logic, raw strings, fallback values |
| `ai-dev-tools-enforce` | Post-change verification: enforces architecture and code quality standards on all modified files |
| `ai-dev-tools-swift-testing` | Test style guide and conventions |

## Background

Two issues were reported in the AIDevTools MacApp PR Radar feature:

1. **GitHub API rate limiting**: After switching from a PAT to GitHub App credentials, rate limits are being hit more aggressively. The root cause is that `GitHubServiceFactory.resolveToken()` calls `GitHubAppTokenService().generateInstallationToken(...)` on every invocation with no caching. Each token generation call costs secondary rate-limit points (separate from the primary 5,000/hr limit). GitHub's own documentation recommends caching installation tokens, which are valid for 1 hour. Additionally, `createPRService(repoPath:resolver:dataPathsService:)` contains its own token generation call that is also uncached.

2. **Ambiguous orange badges in PR list view**: The `PRListRow` view shows multiple orange/colored indicators that are visually indistinguishable to the user:
   - `buildStatusBadge` — shows CI check run counts (green/red/orange) and merge conflict indicator
   - `reviewStatusBadge` — shows review approval/rejection counts and pending-review clock
   - `postedCommentsBadge` — shows green count of posted analysis comments
   - `analysisBadge` — shows orange pending-violation count OR a green checkmark if analysis loaded with no violations
   - `ProgressView` — spinner shown during in-flight operations

   Bill's request: the PR list should show **only** the orange pending-violations badge. The CI check run data, review status, posted comments count, and operation spinner are all noise at the list level. Check runs and review status are already shown in `SummaryPhaseView` (the detail view), so no information is lost by removing them from the list.

## Phases

## - [x] Phase 1: Cache GitHub App installation tokens in GitHubServiceFactory

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Added a file-private `InstallationTokenCache` actor with a 55-minute TTL. Wired it into both token-generation call sites — `resolveToken` (keyed by `"\(githubAccount)/\(installationId)"`) and `createPRService(repoPath:resolver:dataPathsService:)` (keyed by `"app/\(installationId)"`). Used `await` on actor methods since `GitHubServiceFactory` is a `Sendable` struct with static methods.

**Skills to read**: `ai-dev-tools-code-quality`

File: `AIDevToolsKit/Sources/Services/GitHubService/GitHubServiceFactory.swift`

Add a file-private Swift actor `InstallationTokenCache` that caches tokens with a 55-minute TTL (safely under GitHub's 1-hour expiry). Wire it into both token-generation call sites:

1. **`resolveToken(githubAccount:explicitToken:)`** — wrap the `.app` case with a cache lookup by key `"\(githubAccount)/\(installationId)"` before calling `generateInstallationToken`; store the result on success.

2. **`createPRService(repoPath:resolver:dataPathsService:)`** — same pattern; build the cache key from `installationId` in the `.app` case.

Cache implementation (same actor-based pattern already proven in the `pr-radar` repo):

```swift
private actor InstallationTokenCache {
    private struct Entry {
        let token: String
        let expiry: Date
    }
    private var entries: [String: Entry] = [:]

    func get(key: String) -> String? {
        guard let entry = entries[key], entry.expiry > Date() else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.token
    }

    func set(token: String, key: String) {
        entries[key] = Entry(token: token, expiry: Date().addingTimeInterval(55 * 60))
    }
}
```

Add a `private static let tokenCache = InstallationTokenCache()` to `GitHubServiceFactory`.

For `createPRService(repoPath:resolver:dataPathsService:)`, the `installationId` is available from the `.app` case — use `"app/\(installationId)"` as the cache key (no account prefix needed since this method takes a full `CredentialResolver`).

## - [x] Phase 2: Clean up PRListRow — remove ambiguous badges

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Removed `buildStatusBadge`, `reviewStatusBadge`, `postedCommentsBadge`, the `ProgressView` spinner, `countBadge` helper, and `reviewStatus` computed var. Simplified `analysisBadge` to only show the orange pending-violations count. Removed unused `ClaudeChainService` import. HStack now contains only `stateIndicator`, `Spacer()`, `analysisBadge`, and the relative timestamp.

**Skills to read**: `ai-dev-tools-code-quality`

File: `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/PRListRow.swift`

Remove these elements entirely from the view (delete their call sites in `body` and their `@ViewBuilder` computed property implementations):

- `buildStatusBadge` and its backing `countBadge` helper — **only if** `countBadge` is not used by any remaining badge; if it is only used by `buildStatusBadge` and `reviewStatusBadge`, remove it too
- `reviewStatusBadge` and `reviewStatus` computed var
- `postedCommentsBadge`
- `ProgressView()` block (`if prModel.operationMode != .idle`)

Simplify `analysisBadge` to remove the `else if case .loaded` green-checkmark branch — only the orange violations count should remain:

```swift
@ViewBuilder
private var analysisBadge: some View {
    if prModel.pendingCommentCount > 0 {
        Text("\(prModel.pendingCommentCount)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.orange, in: Capsule())
    }
}
```

After removing the badge call sites from `body`, the HStack should only contain: `stateIndicator`, `Spacer()`, `analysisBadge`, and the relative timestamp.

## - [x] Phase 3: Validation

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`
**Principles applied**: `swift build` passes clean. All 1343 tests pass with `swift test`. Enforce analysis found only pre-existing violations (lines 80/137 in GitHubServiceFactory.swift, lines 52/80 in PRListRow.swift) — none introduced by Phases 1 or 2. The new `InstallationTokenCache` code uses intentionally different cache key namespaces (`"app/<id>"` vs `"<account>/<id>"`) matching the two different call sites' scoping needs. Mac app UI verification (steps 4–5) requires interactive launch and was not automated.

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`

1. Run `swift build` from `AIDevToolsKit/` to confirm no compiler errors.
2. Run `swift test` to confirm no regressions.
3. Run `ai-dev-tools-enforce` on all modified files:
   - `AIDevToolsKit/Sources/Services/GitHubService/GitHubServiceFactory.swift`
   - `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/PRListRow.swift`
4. Build and launch the Mac app; open a repository config; confirm the PR list shows only the orange pending-violations badge (no CI indicators, no spinner, no green checkmark).
5. Confirm `SummaryPhaseView` still shows CI check runs and review status in the detail panel.
