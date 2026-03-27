## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

The project has three AI providers (ClaudeCLISDK, CodexCLISDK, AnthropicSDK) and a shared `AIClient` protocol in `AIOutputSDK`. The recent chat unification (2026-03-25) successfully migrated both chat systems to use `AIClient`, but two other major subsystems still bypass the shared interface:

1. **ArchitecturePlannerFeature** — 5 of 6 use cases directly import `ClaudeCLISDK` and construct `Claude()` command objects. Only `ExecuteImplementationUseCase` has been migrated.
2. **EvalSDK** — `CodexAdapter` uses `CodexCLIClient` directly. `OutputService` switches on provider type to pick a concrete stream formatter.

Additionally, `+Default.swift` convenience initializers in Features and SDKs hardcode `ClaudeCLIClient()` or `CodexCLIClient()`, forcing those targets to declare concrete SDK dependencies even though their main code only needs `any AIClient`.

### Goal

After this work, the only place that references a concrete SDK is the **App layer** (CLI and Mac), where the user/CLI selects which provider to use. All Features, Services, and the EvalSDK depend only on `AIOutputSDK` for AI interactions.

### Current state

```
ArchitecturePlannerFeature → ClaudeCLISDK (5 use cases use ClaudeCLIClient directly)
PlanRunnerFeature          → ClaudeCLISDK (+Default.swift files hardcode ClaudeCLIClient)
EvalSDK                    → ClaudeCLISDK, CodexCLISDK (CodexAdapter, OutputService, +Default.swift)
```

### Target state

```
ArchitecturePlannerFeature → AIOutputSDK only
PlanRunnerFeature          → AIOutputSDK only
EvalSDK                    → AIOutputSDK only
App layer (CLI/Mac)        → concrete SDKs (for DI wiring only)
```

## Phases

## - [x] Phase 1: Migrate ArchitecturePlannerFeature use cases to AIClient

**Skills to read**: `swift-architecture`

The 5 unmigrated use cases all follow the same pattern — they construct a `Claude(prompt:)` command object, set properties on it, then call `claudeClient.runStructured()`. The already-migrated `ExecuteImplementationUseCase` shows the target pattern.

### Current pattern (all 5 files)

```swift
import ClaudeCLISDK

private let claudeClient: ClaudeCLIClient

var command = Claude(prompt: prompt)
command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
command.jsonSchema = schema
command.printMode = true
command.verbose = true

let output = try await claudeClient.runStructured(
    ResponseType.self,
    command: command,
    workingDirectory: path,
    onFormattedOutput: callback
)
```

### Target pattern (from ExecuteImplementationUseCase)

```swift
import AIOutputSDK

private let client: any AIClient

let options = AIClientOptions(workingDirectory: path)

let output = try await client.runStructured(
    ResponseType.self,
    prompt: prompt,
    jsonSchema: schema,
    options: options,
    onOutput: callback
)
```

### Files to modify

- `CompileArchitectureInfoUseCase.swift` — change `ClaudeCLIClient` property to `any AIClient`, replace `Claude()` command with `AIClientOptions`, update `runStructured` call signature
- `CompileFollowupsUseCase.swift` — same transformation
- `FormRequirementsUseCase.swift` — same transformation
- `PlanAcrossLayersUseCase.swift` — same transformation
- `ScoreConformanceUseCase.swift` — same transformation

Each file needs:
1. Replace `import ClaudeCLISDK` with `import AIOutputSDK`
2. Change property from `ClaudeCLIClient` to `any AIClient`
3. Change init parameter from `claudeClient: ClaudeCLIClient = ClaudeCLIClient()` to `client: any AIClient`
4. Remove `Claude()` command construction; build `AIClientOptions` instead
5. Update `runStructured` call to use `AIClient` signature (`prompt:jsonSchema:options:onOutput:`)

## - [x] Phase 2: Migrate CodexAdapter in EvalSDK to AIClient

**Skills to read**: `swift-architecture`

`CodexAdapter` currently uses `CodexCLIClient` directly with `Codex.Exec()` command objects — the same kind of leak the ArchPlanner has with `Claude()`. `ClaudeAdapter` is already migrated and shows the target pattern.

### Current pattern (CodexAdapter)

```swift
import CodexCLISDK

private let codexClient: CodexCLIClient

var command = Codex.Exec()
// set command properties...
let output = try await codexClient.run(command: command, ...)
```

### Target pattern (from ClaudeAdapter)

```swift
import AIOutputSDK

private let client: any AIClient

let session = OutputService.makeSession(
    artifactsDirectory: ...,
    provider: ...,
    caseId: ...,
    client: client
)
let result = try await session.run(prompt: ..., options: ..., onOutput: ...)
```

### Files to modify

- `CodexAdapter.swift` — change `CodexCLIClient` to `any AIClient`, replace `Codex.Exec()` command with `AIClientOptions`, use `AIRunSession` like `ClaudeAdapter` does

### Design consideration

`CodexAdapter` may use Codex-specific options (like `writableRoots`). Verify whether these map to `AIClientOptions` fields or if `CodexCLIClient`'s `AIClient` conformance handles them internally. If Codex-specific options are needed, they should be set via `AIClientOptions.environment` or handled inside the `CodexCLIClient` conformance.

## - [x] Phase 3: Abstract stream formatting out of EvalSDK

**Skills to read**: `swift-architecture`

`OutputService.format()` switches on `Provider` to pick `ClaudeStreamFormatter` or `CodexStreamFormatter`, forcing EvalSDK to import both concrete SDKs. This provider-specific logic should be abstracted.

### Approach

Add a `StreamFormatter` protocol to `AIOutputSDK`:

```swift
public protocol StreamFormatter: Sendable {
    func format(_ rawChunk: String) -> String
}
```

Each SDK's existing formatter already has this method signature:
- `ClaudeStreamFormatter.format(_:)` in `ClaudeCLISDK`
- `CodexStreamFormatter.format(_:)` in `CodexCLISDK`

Have each conform to the new protocol. Then `OutputService` accepts a `StreamFormatter` parameter instead of switching on `Provider`.

### Files to modify

- `AIOutputSDK` — add `StreamFormatter.swift` with the protocol
- `ClaudeCLISDK/ClaudeStreamFormatter.swift` — add `: StreamFormatter` conformance
- `CodexCLISDK/CodexStreamFormatter.swift` — add `: StreamFormatter` conformance
- `EvalSDK/OutputService.swift` — replace `format(_ raw: String, provider: Provider)` with `format(_ raw: String, formatter: StreamFormatter)`. Remove imports of `ClaudeCLISDK` and `CodexCLISDK`.
- Callers of `OutputService.format()` — pass the appropriate formatter (injected from App layer or adapter)

## - [x] Phase 4: Move +Default.swift convenience inits to App layer

**Skills to read**: `swift-architecture`

Six `+Default.swift` files hardcode concrete SDK instantiation inside Feature/SDK targets, forcing those targets to depend on concrete SDKs even though their main code only needs `any AIClient`. These convenience inits should move to the App layer.

### Files to relocate

**ArchitecturePlannerFeature:**
- `ExecuteImplementationUseCase+Default.swift` — `self.init(client: ClaudeCLIClient())`

**PlanRunnerFeature:**
- `ExecutePlanUseCase+Default.swift` — `client: ClaudeCLIClient()`
- `GeneratePlanUseCase+Default.swift` — `client: ClaudeCLIClient()`

**EvalSDK:**
- `ClaudeAdapter+Default.swift` — `self.init(client: ClaudeCLIClient())`
- `CodexAdapter+Default.swift` (if it exists after Phase 2, or create) — same pattern for Codex

### Approach

1. Remove `+Default.swift` files from Feature/SDK targets
2. In the App layer (CLI and Mac targets), create the use cases with explicit client injection:
   ```swift
   // In CLI or Mac app setup code
   let client: any AIClient = ClaudeCLIClient()  // or chosen provider
   let useCase = CompileArchitectureInfoUseCase(client: client)
   ```
3. If a convenience factory is still desired, add it as an extension in the App layer target where concrete SDKs are already imported

### Impact

This is the change that actually removes `ClaudeCLISDK` and `CodexCLISDK` from the dependency lists of Feature and SDK targets. Without this phase, the Package.swift cleanup in Phase 5 won't compile.

### Design note

The `+Default.swift` files also provide defaults for non-SDK parameters (e.g., `dataPath`, `gitClient`). Those defaults should stay — only the hardcoded `ClaudeCLIClient()` needs to move. If a file has both SDK and non-SDK defaults, split: keep the non-SDK defaults in the Feature, require `client` as a parameter.

## - [x] Phase 5: Tighten CLI command client types

**Skills to read**: `swift-architecture`

In the CLI App layer, `ChatCommand` types its `client` parameter as the concrete `AnthropicAIClient` instead of `any AIClient`. While this is technically in the App layer (not a dependency violation), it prevents the command from ever supporting multiple providers and is inconsistent with the pattern used elsewhere.

### Files to modify

- `ChatCommand.swift` — change `sendSingleMessage(_:client:)` and `runInteractive(client:)` parameter types from `AnthropicAIClient` to `any AIClient`. The concrete type is created at line 29 and can stay concrete there (that's DI), but once passed to helper methods, the protocol type should be used.

### Why

If `ChatCommand` ever supports a `--provider` flag (like eval commands do), the helpers already accept any provider. Even without that, it's consistent with how `ClaudeChatCommand` works and avoids unnecessary coupling in method signatures.

## - [x] Phase 6: Clean up Package.swift dependencies

**Skills to read**: `swift-architecture`

With all concrete SDK usage moved to the App layer, update Package.swift to reflect the new dependency graph.

### Changes

Remove concrete SDK dependencies from these targets:

- **ArchitecturePlannerFeature**: remove `ClaudeCLISDK` from dependencies (keep `AIOutputSDK`)
- **PlanRunnerFeature**: remove `ClaudeCLISDK` from dependencies (keep `AIOutputSDK`)
- **EvalSDK**: remove `ClaudeCLISDK` and `CodexCLISDK` from dependencies (keep `AIOutputSDK`)

Verify App layer targets still declare the concrete SDK dependencies they need:

- **AIDevToolsKitCLI**: keep `AnthropicSDK`, `ClaudeCLISDK`, `CodexCLISDK` (for DI wiring)
- **AIDevToolsKitMac**: keep `AnthropicSDK`, `ClaudeCLISDK` (for DI wiring)

### Verification

After changes, grep all non-App targets for imports of concrete SDKs to confirm none remain:
```bash
grep -r "import ClaudeCLISDK\|import CodexCLISDK\|import AnthropicSDK" \
  --include="*.swift" \
  AIDevToolsKit/Sources/Features/ \
  AIDevToolsKit/Sources/Services/ \
  AIDevToolsKit/Sources/SDKs/EvalSDK/
```

Expected: zero matches.

## - [x] Phase 7: Validation

**Skills to read**: `ai-dev-tools-debug`

### Automated

- Build both CLI and Mac app targets with no compile errors
- Run full test suite — all existing tests pass
- Run: `grep -r "import ClaudeCLISDK\|import CodexCLISDK\|import AnthropicSDK" --include="*.swift" AIDevToolsKit/Sources/Features/ AIDevToolsKit/Sources/Services/ AIDevToolsKit/Sources/SDKs/EvalSDK/` — expect zero matches

### Manual

- CLI: run an eval with Claude provider — unchanged behavior
- CLI: run an eval with Codex provider — unchanged behavior
- CLI: run architecture planner — unchanged behavior
- CLI: run plan runner — unchanged behavior
- Mac app: open chat with each provider — unchanged behavior

### Dependency graph audit

Confirm final dependency structure:

```
App layer (CLI/Mac)
  ├── ClaudeCLISDK, CodexCLISDK, AnthropicSDK  (concrete — for DI only)
  ├── Features (ArchPlanner, PlanRunner, Chat, Eval)
  └── AIOutputSDK

Features layer
  └── AIOutputSDK only (no concrete SDKs)

EvalSDK
  └── AIOutputSDK only (no concrete SDKs)
```
