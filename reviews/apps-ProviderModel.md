# Architecture Review: ProviderModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ProviderModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 6/10] Duplicated registry construction logic with CLI factory

**Location:** Lines 20-26

### Guidance

> **Depth Over Width** — App-layer code calls **ONE** use case per user action.
> The use case orchestrates everything internally.
>
> **Cross-Cutting Check: CLI Parity** — The whole point of extracting orchestration
> into a use case is reuse across entry points. If the model calls a use case but the
> CLI command duplicates the logic inline (or doesn't exist), the architectural benefit
> is unrealized.

### Interpretation

`buildRegistry()` in ProviderModel constructs [ClaudeProvider, CodexProvider, optional AnthropicProvider] — nearly identical to `makeProviderRegistry()` in CLIRegistryFactory. The only difference is the API key source (UserDefaults vs environment variable). If a new provider SDK is added, both factories must be updated independently. Severity 6/10 because this is design friction that increases the risk of divergence, but both are in the Apps layer and the duplication is small (~6 lines).

### Resolution

Parameterize `buildRegistry()` to accept the Anthropic API key as a `String?` parameter rather than reading it inline. This makes the construction logic reusable and testable. A shared factory across targets could be added later if more providers are introduced.

---

## Finding 2 — [Severity: 5/10] Direct UserDefaults access hardcoded in model

**Location:** Lines 22

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows.
>
> App-layer models should have their dependencies injected, making them testable and
> decoupled from global singletons.

### Interpretation

The model reads `UserDefaults.standard.string(forKey: "anthropicAPIKey")` directly inside `buildRegistry()`. This couples the model to a global singleton and a hardcoded key string, making it impossible to test with different configurations or swap the key source. The same key string `"anthropicAPIKey"` is also used in GeneralSettingsView, creating a fragile implicit dependency. Severity 5/10 because it's a testability and coupling issue but has limited blast radius for this simple model.

### Resolution

Inject a closure that provides the API key, defaulting to the UserDefaults lookup. This allows tests to supply a fixed key and decouples the model from the global singleton.

---

## Finding 3 — [Severity: 3/10] Model performs factory work requiring 4 SDK imports

**Location:** Lines 1-6, 20-26

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows.

### Interpretation

The model imports AIOutputSDK, AnthropicSDK, ClaudeCLISDK, and CodexCLISDK solely to construct concrete provider instances in `buildRegistry()`. This is factory/configuration work, not model state management. The imports are a symptom of the model taking on construction responsibility. Severity 3/10 because this coupling is contained and doesn't affect behavior, but it means the model changes whenever a provider SDK changes its public API.

### Resolution

This is a consequence of findings 1 and 2. Once the construction is parameterized and the API key injected, the model's coupling to concrete SDKs is at least justified by its factory role. A further step would be to move construction to CompositionRoot, but the current approach is acceptable for this small model.

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 3 |
| **Highest severity** | 6/10 |
| **Overall health** | Small, focused model with no orchestration violations. Main issues are direct UserDefaults coupling and duplicated factory logic with the CLI target. |
| **Top priority** | Inject the API key source to decouple from UserDefaults and make the construction logic testable and reusable. |
