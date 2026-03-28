# Architecture Review: CaseResult.swift

**File:** `AIDevToolsKit/Sources/Services/EvalService/Models/CaseResult.swift`
**Detected Layer:** Services
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 3/10] Two public types in one file with mismatched name

**Location:** Lines 47-70

### Guidance

> **Shared models and types** — data structures used by multiple features

### Interpretation

`CaseResult.swift` contains both `CaseResult` and `EvalSummary`. `EvalSummary` is a standalone public type used broadly across Features and Apps (RunEvalsUseCase, LoadLastResultsUseCase, EvalRunnerModel). Bundling it in a file named after `CaseResult` makes it harder to discover and breaks the one-type-per-file convention used elsewhere in this module. Severity 3/10 because it's a style/discoverability issue, not an architectural boundary violation.

### Resolution

Move `EvalSummary` to its own file `EvalSummary.swift` in the same `Models/` directory.

---

## Finding 2 — [Severity: 3/10] Mutable properties that are never mutated after init

**Location:** Lines 8-16

### Guidance

> **Shared models and types** — data structures used by multiple features

### Interpretation

Nine of CaseResult's eleven stored properties (`skipped`, `skillChecks`, `task`, `input`, `expected`, `mustInclude`, `mustNotInclude`, `providerResponse`, `toolCallSummary`) are declared `var` but are never assigned outside `init`. Only `passed` and `errors` are mutated externally (in `RunEvalsUseCase`). Using `var` for the rest over-signals mutability and weakens the value-type immutability contract. Severity 3/10 — low impact, but an easy fix that communicates intent more clearly.

### Resolution

Change the nine never-mutated properties to `let`:

```swift
public let skipped: [String]
public let skillChecks: [SkillCheckResult]
public let task: String?
public let input: String?
public let expected: String?
public let mustInclude: [String]?
public let mustNotInclude: [String]?
public let providerResponse: String?
public let toolCallSummary: ToolCallSummary?
```

Keep `passed` and `errors` as `var` since they're mutated in `RunEvalsUseCase`.

---

## Summary

| | |
|---|---|
| **Layer** | Services |
| **Findings** | 2 |
| **Highest severity** | 3/10 |
| **Overall health** | Clean services-layer model. Correct dependency direction (imports only Foundation and AIOutputSDK), no orchestration, properly Sendable and Codable. Two minor style improvements available. |
| **Top priority** | Move `EvalSummary` to its own file for discoverability. |
