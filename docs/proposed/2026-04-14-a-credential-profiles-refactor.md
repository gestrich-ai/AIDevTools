# Credential Profiles Refactor

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-composition-root` | How SharedCompositionRoot, CLICompositionRoot, and Mac CompositionRoot are wired; where credentials enter the system |
| `ai-dev-tools-architecture` | Layer rules — Services, Features, Apps boundaries; no upward dependencies |
| `ai-dev-tools-swift-testing` | Test style and conventions for this project |
| `ai-dev-tools-enforce` | Run after final phase to verify no standards violations were introduced |

---

## Background

Currently, GitHub and Anthropic credentials are lumped together under a single named "account" string (e.g., `"work"`, `"personal"`). A `RepositoryConfiguration` has one `credentialAccount: String?` field that is used to look up both its GitHub token and its Anthropic API key from the same keychain namespace.

This has two problems:

1. **Mixed concerns.** You can't share an Anthropic key across repos that use different GitHub orgs, and vice versa. Profiles should be typed and independent.

2. **Confusing GitHub auth UI.** The edit sheet has a segmented picker that lets you fill in both a token AND GitHub App fields, with the understanding that saving one clears the other. This is backwards — the type should be chosen upfront, and you only fill in one form.

**The new model:**

- A **GitHubCredentialProfile** is a named profile (e.g., `"personal-org"`) that holds *either* a personal access token *or* a GitHub App triple (app ID, installation ID, private key PEM). The type is selected at creation time; it can be changed later but only one is ever stored.

- An **AnthropicCredentialProfile** is a named profile (e.g., `"default"`) that holds one API key.

- `RepositoryConfiguration` replaces `credentialAccount: String?` with two independent optional references: `githubCredentialProfileId: String?` and `anthropicCredentialProfileId: String?`.

**No backwards compatibility required.** Bill will migrate existing keychain entries manually.

**New keychain key format:**

| Credential | Keychain key |
|---|---|
| GitHub token profile named `work` | `github-profiles/work/token` |
| GitHub App profile named `work` | `github-profiles/work/app-id`, `github-profiles/work/installation-id`, `github-profiles/work/private-key` |
| Anthropic profile named `default` | `anthropic-profiles/default/api-key` |

Profile names are discovered by scanning keychain keys for the `github-profiles/` and `anthropic-profiles/` prefixes — same pattern as today's account discovery.

---

## Phases

## - [x] Phase 1: New Core Types

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: New types (`GitHubAuthType`, `GitHubCredentialProfile`, `AnthropicCredentialProfile`) placed in the Services layer (`CredentialService`) as stateless `Sendable` structs — consistent with architecture rules. `RepositoryConfiguration` fields kept alphabetically ordered per project conventions. `CredentialStatus`/`GitHubAuthStatus` retained to avoid breaking Phase 4 callers; will be removed in Phase 4 per spec.

**Skills to read**: `ai-dev-tools-architecture`

Define the new domain types in the SDKs or Services layer. No storage logic yet.

**New types to create:**

- `GitHubAuthType` enum in `CredentialService` (or reuse/extend existing):
  ```swift
  public enum GitHubAuthType: String, Codable, Sendable {
      case token
      case app
  }
  ```

- `GitHubCredentialProfile` struct:
  ```swift
  public struct GitHubCredentialProfile: Identifiable, Sendable {
      public let id: String        // profile name, used as keychain namespace
      public let auth: GitHubAuth  // .token(...) or .app(...)
  }
  ```

- `AnthropicCredentialProfile` struct:
  ```swift
  public struct AnthropicCredentialProfile: Identifiable, Sendable {
      public let id: String
      public let apiKey: String
  }
  ```

**Update `RepositoryConfiguration`** in `Sources/SDKs/RepositorySDK/RepositoryConfiguration.swift`:
- Remove `credentialAccount: String?`
- Add `githubCredentialProfileId: String?`
- Add `anthropicCredentialProfileId: String?`

**Remove `CredentialStatus` and `GitHubAuthStatus`** — these will be replaced in Phase 4 with per-profile status types. (Or update them to be profile-aware if something needs them in the interim.)

---

## - [x] Phase 2: Keychain Storage

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: New profile-based methods added to `SecureSettingsService` using the spec's key format (`github-profiles/<id>/token`, etc.). Old public account-based methods removed; an internal `loadCredential(account:type:)` bridge retained so `CredentialResolver` continues to compile — it maps old type constants to new profile keys, deferring CredentialResolver's full rewrite to Phase 3. `EnvironmentKeychainStore` updated to parse 3-component keys and synthesise `"default"` profile keys from env vars. All callers of old public methods updated minimally to keep the build green.

Update `SecureSettingsService.swift` to read/write using the new keychain namespace format.

**New key format functions:**
```swift
private func githubProfileKey(_ profileId: String, _ suffix: String) -> String {
    "github-profiles/\(profileId)/\(suffix)"
}
private func anthropicProfileKey(_ profileId: String) -> String {
    "anthropic-profiles/\(profileId)/api-key"
}
```

**New methods to add / replace:**
- `saveGitHubProfile(_ profile: GitHubCredentialProfile)` — stores token OR app keys; removes the opposite set
- `loadGitHubProfile(id: String) -> GitHubCredentialProfile?`
- `removeGitHubProfile(id: String)`
- `listGitHubProfileIds() -> [String]` — scans keychain keys for `github-profiles/` prefix, extracts profile names

- `saveAnthropicProfile(_ profile: AnthropicCredentialProfile)`
- `loadAnthropicProfile(id: String) -> AnthropicCredentialProfile?`
- `removeAnthropicProfile(id: String)`
- `listAnthropicProfileIds() -> [String]`

**Remove the old account-based methods** (`saveGitHubAuth(_, account:)`, `saveAnthropicKey(_, account:)`, `loadGitHubAuth(account:)`, `loadAnthropicKey(account:)`, `listCredentialAccounts()`, `removeCredentials(account:)`) since no backwards compatibility is needed.

Update `EnvironmentKeychainStore` (non-macOS fallback) to map the new key patterns to environment variables.

---

## - [x] Phase 3: Credential Resolver

**Skills used**: `ai-dev-tools-composition-root`, `ai-dev-tools-architecture`
**Principles applied**: `CredentialResolver` init updated to `secureSettings:githubProfileId:anthropicProfileId:` — two independent profile IDs replace the single `account: String`. Keychain lookups now go through `SecureSettingsService.loadGitHubProfile(id:)` and `loadAnthropicProfile(id:)` directly; the Phase 2 bridge method `loadCredential(account:type:)` removed. `CredentialError.notConfigured` updated to carry `profileId: String?`. `PRRadarRepoConfig.githubAccount` renamed to `githubCredentialProfileId` and all callers updated. `resolveGitHubCredentials` parameter renamed from `githubAccount:` to `githubProfileId:` throughout both CLICompositionRoots and callers. `PRRadarConfigService.CredentialResolver` updated to use `githubProfileId` with the new profile key format. All tests updated.

**Skills to read**: `ai-dev-tools-composition-root`, `ai-dev-tools-architecture`

Rewrite `CredentialResolver` to work with separate profile IDs instead of a single account string.

**Updated initializer / factory:**
```swift
public struct CredentialResolver: Sendable {
    public init(
        secureSettings: SecureSettingsService,
        githubProfileId: String?,
        anthropicProfileId: String?,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String] = [:]
    )
}
```

**Updated resolution methods:**
- `getGitHubAuth() -> GitHubAuth?` — resolves using `githubProfileId` instead of `account`
- `requireGitHubAuth() -> GitHubAuth` — throws `CredentialError.notConfigured(profileId:)` if missing
- `getAnthropicKey() -> String?` — resolves using `anthropicProfileId` (env var `ANTHROPIC_API_KEY` still a fallback)
- `gitEnvironment: [String: String]?` — still returns `GH_TOKEN` env dict for child processes

Update the PRRadarConfigService's internal `CredentialResolver` copy at `Sources/Services/PRRadarConfigService/CredentialResolver.swift` to match, or consolidate them into one.

Update `PRRadarRepoConfig` to carry `githubCredentialProfileId: String?` instead of `githubAccount: String?`.

---

## - [x] Phase 4: Feature Use Cases

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Eight new typed use cases created in `CredentialFeature` — four for GitHub profiles (`List`, `Save`, `Remove`, `Load`) and four for Anthropic profiles. All are `struct` conforming to `UseCase` with a single `execute` method. Old use cases (`SaveCredentialsUseCase`, `RemoveCredentialsUseCase`, `ListCredentialStatusesUseCase`, `LoadCredentialStatusUseCase`, `ListCredentialAccountsUseCase`) and the `CredentialStatusLoader` helper removed. `CredentialModel` rewritten to use new use cases internally; `credentialAccounts: [CredentialStatus]` kept as a computed bridge so the existing Mac views compile unchanged until Phase 5 rewrites them. `CredentialsCommand` updated to use new use cases. `CredentialStatus`/`GitHubAuthStatus` retained as presentation types until Phase 5 removes the views that depend on them.

**Skills to read**: `ai-dev-tools-architecture`

Rewrite the use cases in `Sources/Features/CredentialFeature/` to operate on typed profiles.

**Use cases to rewrite or replace:**
- `ListGitHubProfilesUseCase` — returns `[GitHubCredentialProfile]`
- `SaveGitHubProfileUseCase` — takes `GitHubCredentialProfile`
- `RemoveGitHubProfileUseCase` — takes profile ID
- `LoadGitHubProfileUseCase` — takes profile ID, returns `GitHubCredentialProfile?`

- `ListAnthropicProfilesUseCase` — returns `[AnthropicCredentialProfile]`
- `SaveAnthropicProfileUseCase` — takes `AnthropicCredentialProfile`
- `RemoveAnthropicProfileUseCase` — takes profile ID
- `LoadAnthropicProfileUseCase` — takes profile ID, returns `AnthropicCredentialProfile?`

Remove old use cases: `ListCredentialStatusesUseCase`, `SaveCredentialsUseCase`, `RemoveCredentialsUseCase`, `LoadCredentialStatusUseCase`, `ListCredentialAccountsUseCase`.

`CLICredentialSetup` — update to accept a `githubProfileId` and resolve using the new resolver.

---

## - [x] Phase 5: Mac App UI

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: `CredentialManagementView` restructured into a two-section sidebar (GitHub Profiles / Anthropic Profiles) using `List` with `Section` headers; `SelectedProfile` enum drives the detail pane. `GitHubCredentialEditSheet` uses a dropdown `Picker` (not segmented control) to select auth type, showing only the relevant fields. `AnthropicCredentialEditSheet` is a minimal separate sheet. `CredentialModel` bridge (`credentialAccounts`) and old combined `saveCredentials`/`removeCredentials` methods removed; typed `saveGitHubProfile`, `removeGitHubProfile`, `saveAnthropicProfile`, `removeAnthropicProfile` added instead. `ConfigurationEditSheet` gains a separate Anthropic Profile picker. `RepositoriesSettingsView` detail view shows both profile IDs. `CredentialStatus.swift` and `GitHubAuthStatus` deleted — no longer referenced.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Rewrite the credential management views to show separate GitHub and Anthropic profile lists.

**`CredentialManagementView`** — restructure into two sections:
- **GitHub Profiles** — list of `GitHubCredentialProfile` names with +/- buttons
- **Anthropic Profiles** — list of `AnthropicCredentialProfile` names with +/- buttons
- Selecting a profile in either list opens its edit sheet in a detail pane

**`GitHubCredentialEditSheet`** (new or renamed):
- Profile name text field
- `authType` dropdown (Picker): "Personal Access Token" / "GitHub App" — selecting this drives which fields are shown below, NOT a segmented toggle that shows both
- If token: one `SecureField` for the token
- If app: three fields (App ID, Installation ID, Private Key PEM)
- Save / Cancel

**`AnthropicCredentialEditSheet`** (new or renamed):
- Profile name text field
- `SecureField` for API key
- Save / Cancel

**`CredentialModel`** — update to expose `gitHubProfiles: [GitHubCredentialProfile]` and `anthropicProfiles: [AnthropicCredentialProfile]` instead of the old `credentialAccounts: [CredentialStatus]`.

**`ConfigurationEditSheet`** — replace the single `credentialAccount` Picker with two Pickers:
- "GitHub Profile" — populated from `credentialModel.gitHubProfiles`
- "Anthropic Profile" — populated from `credentialModel.anthropicProfiles`

**`RepositoriesSettingsView`** — update the read-only display to show both GitHub and Anthropic profile names separately.

---

## - [ ] Phase 6: CLI Commands

**Skills to read**: `ai-dev-tools-composition-root`

Rewrite `CredentialsCommand.swift` in `Sources/Apps/AIDevToolsKitCLI/` to use subcommands per profile type.

**New command structure:**
```
credentials github add <profileId> [--token | --app-id / --installation-id / --private-key-path]
credentials github list
credentials github show <profileId>
credentials github remove <profileId>

credentials anthropic add <profileId> --api-key <key>
credentials anthropic list
credentials anthropic show <profileId>
credentials anthropic remove <profileId>
```

The `github add` subcommand takes either `--token` (PAT) or the three `--app-*` flags. Providing both should be an error. Providing neither prompts interactively or errors.

Update `CLICompositionRoot` factory methods to accept `githubProfileId` and `anthropicProfileId` instead of a single `githubAccount` string:
```swift
CLICompositionRoot.create(githubProfileId: String?, anthropicProfileId: String?)
```

---

## - [ ] Phase 7: Composition Root Wiring

**Skills to read**: `ai-dev-tools-composition-root`

Update all three composition roots to use the new profile-based resolver.

**`SharedCompositionRoot`** (`Sources/Services/ProviderRegistryService/SharedCompositionRoot.swift`):
- Change `create()` to discover the first GitHub profile ID and first Anthropic profile ID from `SecureSettingsService` (instead of a single account)
- Pass both profile IDs to `CredentialResolver`
- Pass `anthropicProfileId` to `AnthropicProvider` init

**`CLICompositionRoot`** (`Sources/Apps/AIDevToolsKitCLI/CLICompositionRoot.swift`):
- Replace `githubAccount: String?` parameter with `githubProfileId: String?`
- Remove `resolveGitHubCredentials` helper that built the old account string — just pass the profile ID directly to `CredentialResolver`

**`CompositionRoot`** (Mac, `Sources/Apps/AIDevToolsKitMac/CompositionRoot.swift`):
- Update wiring to thread `githubProfileId` through to `gitClientFactory`
- `ProviderModel` refresh logic should update when either profile list changes

---

## - [ ] Phase 8: Validation

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`

**Automated tests:**
- Update or rewrite `CredentialServiceTests` to cover:
  - `SecureSettingsService` round-trips GitHub token profiles
  - `SecureSettingsService` round-trips GitHub App profiles
  - Saving a token profile removes any existing app keys for the same profile ID (and vice versa)
  - `listGitHubProfileIds()` and `listAnthropicProfileIds()` enumerate correctly
  - `CredentialResolver` resolves GitHub auth from profile ID
  - `CredentialResolver` resolves Anthropic key from profile ID, with env var fallback
- Update `KeychainSDKTests` if any test relies on old key patterns

**Manual checks:**
- Add a GitHub token profile via CLI, verify keychain key is `github-profiles/<name>/token`
- Add a GitHub App profile via CLI, verify all three app keys are present
- Add an Anthropic profile via CLI, verify `anthropic-profiles/<name>/api-key`
- Verify removing one profile does not affect others
- Mac app: create GitHub token profile, verify only token fields are shown
- Mac app: create GitHub App profile, verify only app fields are shown (dropdown drives form)
- Mac app: create Anthropic profile, assign to a repo, confirm PRRadar picks up the right key
- Mac app: assign different GitHub and Anthropic profiles to a repo, confirm each resolves independently

Run `ai-dev-tools-enforce` on all modified files before calling the plan complete.
