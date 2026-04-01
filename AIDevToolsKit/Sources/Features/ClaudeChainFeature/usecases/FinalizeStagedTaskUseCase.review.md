# Architecture Review: FinalizeStagedTaskUseCase.swift

**File:** `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/FinalizeStagedTaskUseCase.swift`
**Detected Layer:** Features
**Review Date:** 2026-04-01

---

## Finding 1 — [Severity: 6/10] Helper methods duplicated from RunChainTaskUseCase

**Location:** Lines 171–215 (`buildPRTitle`, `extractCost`, `parsePRNumber`, `detectRepo`)

### Guidance

> **No feature-to-feature dependencies** — shared logic goes in Services or SDKs; compose at the App layer.

### Interpretation

`buildPRTitle`, `parsePRNumber`, `detectRepo`, and `extractCost` are verbatim copies of the same private methods in `RunChainTaskUseCase`. Because they're `private` they can't be shared between the two structs, so any bug fix or behavior change must be applied in both places. The guidance says shared logic that can't live in a feature goes in Services or SDKs — these helpers are stateless utility functions that operate on strings and process state, making them a natural fit for `ClaudeChainService` or a small helper file in the feature's `services/` subdirectory. Severity 6/10 because the duplication already exists across two active, non-trivial code paths and will drift over time.

### Resolution

Extract the four helpers to a new `PRHelpers.swift` (or similar) in `ClaudeChainFeature/services/` or promote them to `internal` (non-`private`) on `RunChainTaskUseCase` and call them from `FinalizeStagedTaskUseCase`. The minimal-churn approach is to make them `internal static` on a new `PRHelpers` struct in the feature:

```swift
// ClaudeChainFeature/services/PRHelpers.swift
struct PRHelpers {
    static func buildPRTitle(projectName: String, task: String) -> String { ... }
    static func parsePRNumber(from jsonOutput: String) -> String? { ... }
    static func detectRepo(workingDirectory: String) async -> String { ... }
}
```

Both use cases call `PRHelpers.buildPRTitle(...)` instead of owning copies.

---

## Finding 2 — [Severity: 5/10] No CLI entry point for the new use case

**Location:** Whole file

### Guidance

> **Cross-Cutting Check: Entry Point Parity** — Every use case should be consumed by **both** the Mac app (via an `@Observable` model) and the CLI (via an `AsyncParsableCommand`). When reviewing a use case, check that both entry points exist and call the same use case.
>
> If either is missing, flag it — the use case exists to enable reuse across entry points, so a missing consumer means the benefit is unrealized.

### Interpretation

`FinalizeStagedTaskUseCase` is called by `ClaudeChainModel.createPRFromStaged` (Mac app) but has no corresponding CLI command. The existing `FinalizeCommand` is a GitHub Actions helper that reads environment variables and orchestrates its own logic inline — it neither calls `FinalizeStagedTaskUseCase` nor is it designed for the local staging workflow. A user who ran `run-task --staging-only` from the CLI has no CLI command to follow up with "now create the PR from my staged branch." The architectural benefit of extracting this into a use case (CLI reuse) is currently unrealized. Severity 5/10 since the Mac app path works, but the CLI is a first-class entry point in this project.

### Resolution

Add a `FinalizeS tagedCommand` (or add a `--finalize-branch` flag to `RunTaskCommand`) that calls `FinalizeStagedTaskUseCase` directly:

```swift
struct FinalizeStagedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finalize-staged",
        abstract: "Create a PR from a branch staged by run-task --staging-only"
    )

    @Option var project: String
    @Option var branchName: String
    @Option var taskDescription: String
    @Option var baseBranch: String?
    @Option var repoPath: String?

    func run() async throws {
        let repoURL = URL(fileURLWithPath: repoPath ?? FileManager.default.currentDirectoryPath)
        let useCase = FinalizeStagedTaskUseCase(client: client)
        let result = try await useCase.run(
            options: .init(repoPath: repoURL, projectName: project, baseBranch: resolvedBaseBranch,
                           branchName: branchName, taskDescription: taskDescription)
        ) { progress in
            // same handleProgress as RunTaskCommand
        }
        // print result
    }
}
```

---

## Finding 3 — [Severity: 3/10] Result typealias carries fields that don't apply to finalization

**Location:** Line 38 (`public typealias Result = RunChainTaskUseCase.Result`)

### Guidance

> **Conform to `UseCase` or `StreamingUseCase`** — use the `Options`/`Result` pair appropriate to the use case's specific contract.

### Interpretation

`RunChainTaskUseCase.Result` has `branchName: String?` and `isStagingOnly: Bool` which are meaningless for `FinalizeStagedTaskUseCase` — the finalize path always knows its branch (it was passed in) and is never staging-only. The typealias means callers must interpret a `branchName: nil` and `isStagingOnly: false` response as "these fields don't apply here" rather than having a type that expresses only what the operation actually produces. This is a minor semantic mismatch rather than a functional bug. Severity 3/10.

### Resolution

Define a dedicated `Result` struct. It only needs `success`, `message`, `prURL`, `prNumber`, and `taskDescription`:

```swift
public struct Result: Sendable {
    public let message: String
    public let prNumber: String?
    public let prURL: String?
    public let success: Bool
    public let taskDescription: String?
}
```

The `ClaudeChainModel` already constructs an `ExecuteChainUseCase.Result` from the inner result fields, so this change requires only updating that mapping.

---

## Summary

| | |
|---|---|
| **Layer** | Features |
| **Findings** | 3 |
| **Highest severity** | 6/10 |
| **Overall health** | Well-structured use case that follows the core Features patterns (struct, `UseCase` conformance, dependencies via init), but duplicates helper code that will diverge from `RunChainTaskUseCase` over time. |
| **Top priority** | Extract `buildPRTitle`, `parsePRNumber`, `detectRepo`, and `extractCost` into a shared helper to eliminate the duplication — this is the highest-risk issue given both use cases are actively evolving. |
