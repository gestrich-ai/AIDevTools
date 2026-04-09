---
name: ai-dev-tools-configuration-architecture
description: "Guide for adding, modifying, or reviewing configuration in this Swift app. Use when adding credentials or API keys, creating a new config file, adding a ServicePath case, setting up a service that reads settings, wiring configuration through the Apps layer, reviewing whether config is injected correctly (resolved values vs raw services), asking 'where should this config go?', or adding per-repo feature settings. Also use when working with SecureSettingsService, CredentialResolver, SettingsService, DataPathsService, or RepositoryConfiguration anywhere in the codebase."
user-invocable: true
---

# Configuration Architecture

Three services handle all configuration. All are created at the **Apps layer** and injected
downward — never instantiated inside features, services, or SDKs.

| Service | Purpose | Backend |
|---|---|---|
| `CredentialResolver` | All GitHub (and Anthropic) credential resolution | Keychain → named env → unnamed env → explicit token |
| `SettingsService` | Non-sensitive app and feature settings | JSON files via `DataPathsService` |
| `DataPathsService` | Type-safe file system paths | File system |

---

## DataPathsService — File Paths

Provides type-safe, auto-created directory paths via `ServicePath`. Always receives its
`rootPath` from `ResolveDataPathUseCase` at the Apps layer.

```swift
let dataPathsService = try DataPathsService(rootPath: resolvedRoot)
let outputPath = try dataPathsService.path(for: .prradarOutput("my-repo"))
```

### Data Directory Structure

The data root (default `~/Desktop/ai-dev-tools/`) mirrors the code architecture:

```
ai-dev-tools/
  services/          ← data owned by Services-layer modules
    evals/<repo>/
    github/
    pr-radar/
    architecture-planner/
    ...
  sdks/              ← data owned by SDK-layer modules
    anthropic/sessions/
    ...
```

This means **where data lives on disk matches where the code that owns it lives in the package**. If you're looking for data produced by a service, look under `services/<service-name>/`. If it's from an SDK, look under `sdks/<sdk-name>/`.

### Adding a new data location

Add a case to `ServicePath` with the appropriate prefix, keeping cases sorted alphabetically:

```swift
public enum ServicePath {
    case mySDKCache                // → "sdks/my-sdk/cache"
    case myServiceOutput(String)   // → "services/my-service/<name>"
    // ...
}
```

Then call `dataPathsService.path(for: .myServiceOutput("repo"))` — the directory is created automatically. The `ServicePath` case is both the API and the documentation for where data lives.

### Root path resolution

`ResolveDataPathUseCase` determines the data root in priority order:
1. Explicit `--dataPath` CLI argument
2. UserDefaults (`org.gestrich.AIDevTools.shared`, key `AIDevTools.dataPath`)
3. Default: `~/Desktop/ai-dev-tools`

---

## Credential Resolution — Use CredentialResolver

**All credential resolution logic lives in `CredentialResolver`.** Never implement fallback chains, keychain scanning, or account guessing in models, use cases, or factories. Those concerns belong in the resolver.

The resolution order for GitHub auth (enforced inside `CredentialResolver`, nowhere else):
1. Explicit token (CLI `--github-token`) — strict, no fallback
2. Named keychain entry for the configured account
3. Named `.env` key (`GITHUB_TOKEN_<account>`)
4. Unnamed `.env` / env var (`GITHUB_TOKEN`, `GH_TOKEN`)
5. Throw `CredentialError.notConfigured` — no silent scanning

### Mac app

Each `RepositoryConfiguration` has a `credentialAccount: String?` that names which stored credential to use. Features resolve from there via `CredentialResolver`. If `credentialAccount` is nil the feature should surface a clear error, not guess.

### CLI commands

Use `resolveGitHubCredentials(githubAccount:githubToken:)` from `CredentialFeature` — every CLI command that touches GitHub goes through this. It returns a `CredentialResolver` with:

- `resolver.getGitHubAuth()` / `resolver.requireGitHubAuth()` — get the resolved auth
- `resolver.gitEnvironment` — `["GH_TOKEN": token]` dict to pass to child processes

```swift
let resolver = resolveGitHubCredentials(githubAccount: githubAccount, githubToken: githubToken)
let registry = makeProviderRegistry(credentialResolver: resolver)
let gitClient = GitClient(environment: resolver.gitEnvironment)
```

When `githubToken` is provided it is used directly with no fallback. When nil, the resolver uses the keychain/env for the given account (falling back to the first stored account if none specified).

### Credential types

| Type | Keychain key | Env var |
|---|---|---|
| GitHub PAT | `github-token` | `GITHUB_TOKEN` / `GH_TOKEN` |
| GitHub App ID | `github-app-id` | `GITHUB_APP_ID` |
| GitHub App Installation ID | `github-app-installation-id` | `GITHUB_APP_INSTALLATION_ID` |
| GitHub App Private Key | `github-app-private-key` | `GITHUB_APP_PRIVATE_KEY` |
| Anthropic API Key | `anthropic-api-key` | `ANTHROPIC_API_KEY` |

### Account scoping

Credentials are scoped to named accounts (e.g., `"gestrich"`, `"bill_jepp"`). Keys are
stored as `{account}/{type}` in the keychain. The configured `credentialAccount` on
`RepositoryConfiguration` names which account to use. Named env vars follow the same
pattern: `GITHUB_TOKEN_<account>` takes priority over the flat `GITHUB_TOKEN`.

### Adding a new credential type

1. Add a case to `CredentialType` in `CredentialService`
2. Map it to a keychain key and env var name inside `CredentialResolver`
3. Expose a typed accessor on `CredentialResolver` (e.g., `getAnthropicKey()`)
4. Resolve at the Apps layer; pass the resolved value downward — not the resolver itself

---

## SettingsService — Non-Sensitive Settings

Loads and saves feature settings as JSON in the data directory. The primary entity is
`RepositoryConfiguration` — all per-repo feature settings live here.

### RepositoryConfiguration

```swift
public struct RepositoryConfiguration: Codable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var credentialAccount: String?   // which stored credential to use

    // Per-feature settings — nil until configured for this repo
    public var prradar: PRRadarRepoSettings?
    public var eval: EvalRepoSettings?
    public var planner: MarkdownPlannerRepoSettings?
}
```

Adding settings for a new feature = add one optional property here. All `RepositoryConfiguration` objects are stored together in `repositories.json` via `DataPathsService`.

### What does NOT belong in SettingsService

- Sensitive credentials → `CredentialResolver` / `SecureSettingsService`
- Ephemeral UI state → `@AppStorage` / `UserDefaults` directly in the view layer

---

## Apps Layer: Initialization

All services are created once at the entry point. Features and services receive
**resolved values** (a token string, a `URL`, an initialized client) — never the
services themselves.

### Mac app (CompositionRoot)

```swift
static func create() throws -> CompositionRoot {
    let dataRoot = ResolveDataPathUseCase().resolve(explicit: nil).path
    let dataPathsService = try DataPathsService(rootPath: dataRoot)
    let secureSettings = SecureSettingsService()
    let settings = SettingsService(dataPathsService: dataPathsService)

    let appModel = try AppModel(
        secureSettings: secureSettings,
        settings: settings,
        dataPathsService: dataPathsService
    )
    return CompositionRoot(appModel: appModel)
}
```

### CLI command

```swift
struct MyCommand: AsyncParsableCommand {
    @Option var githubAccount: String?
    @Option var githubToken: String?

    func run() async throws {
        let dataPathsService = try DataPathsService.fromCLI(dataPath: nil)
        let resolver = resolveGitHubCredentials(githubAccount: githubAccount, githubToken: githubToken)
        let useCase = MyUseCase(
            outputPath: try dataPathsService.path(for: .myServiceOutput("repo"))
        )
    }
}
```

---

## Runtime Credential Changes (No Restart Required)

Services that depend on credentials are wrapped in optional child models on `AppModel`.
When a credential is absent, the model is `nil` and its UI is not shown. When the user
saves a new credential, `AppModel` rebuilds just the affected child model.

```swift
@Observable class AppModel {
    var githubModel: GitHubModel?   // nil until GitHub token is available
    var aiModel: AIModel?           // nil until Anthropic API key is available

    func applyCredentialChange(_ type: CredentialType) {
        switch type {
        case .githubToken:
            githubModel = buildGitHubModel()
        case .anthropicAPIKey:
            aiModel = buildAIModel()
        }
    }
}
```

The credential-editing UI calls `appModel.applyCredentialChange(_:)` after saving.

**Don't show views that require a credential until the model exists.**

---

## Checklist: Adding configuration to a feature

- [ ] New data directory? → Add a `ServicePath` case; prefix with `services/` or `sdks/` to match the owning layer
- [ ] GitHub credential needed? → Use `CredentialResolver` — never write fallback logic outside it
- [ ] New credential type? → Add to `CredentialType`, add resolution logic inside `CredentialResolver` only
- [ ] Per-repo feature settings? → Add an optional property to `RepositoryConfiguration`
- [ ] App-wide non-sensitive setting? → `SettingsService`, stored as JSON in data dir
- [ ] Use cases / services receive resolved values, not the service objects themselves
- [ ] Missing required credential: surface a clear error, not a silent wrong-account fetch
