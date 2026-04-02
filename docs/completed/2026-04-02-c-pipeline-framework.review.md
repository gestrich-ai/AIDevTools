# Architecture Review: 2026-04-02-c-pipeline-framework.md

**File:** `docs/completed/2026-04-02-c-pipeline-framework.md`
**Detected Layer:** SDKs (proposed `PipelineSDK` target at `AIDevToolsKit/Sources/SDKs/PipelineSDK`)
**Review Date:** 2026-04-02

> **Note:** This is a design document, not a Swift source file. The review evaluates the proposed type designs against the 4-layer architecture to surface violations before implementation, not after.

---

## Finding 1 — [Severity: 8/10] `PRStep` embeds multi-step orchestration and business logic in SDK

**Location:** Phase 2 — `PRStep` section

### Guidance

> **Single-operation methods** — each method wraps one CLI command or one API call.
>
> **No business concepts** — no app-specific types, no domain logic. Generic and reusable — could be used by any project as-is.
>
> **Does a method coordinate multiple operations? → Yes = violation (belongs in Features)**

### Interpretation

`PRStep.run()` is described as performing: read AI cost metrics from context, call `gitClient` for push and branch-name detection, check open PR capacity (throwing `PipelineError.capacityExceeded`), create a draft PR via `gh` CLI, retrieve the PR number, and post a cost comment. That is at least six distinct operations coordinated in sequence — textbook use-case orchestration.

`ProjectConfiguration` (`assignees`, `reviewers`, `labels`, `maxOpenPRs`) is an app-specific business type. An SDK that accepts it cannot be "extracted to a standalone package and used in a completely different project."

Severity 8/10: this is a Feature-or-Service concern physically placed in an SDK node. Any project that imports `PipelineSDK` drags in GitHub PR workflow logic and project-management concepts.

### Resolution

Split `PRStep` responsibility:

1. Keep a thin `GitClient` method in the SDK for `push(branch:)` — single operation, already planned.
2. Keep a thin `GHClient` (or extend `CLISDK`) for `createPR(title:body:base:draft:labels:assignees:reviewers:)` and `addComment(prNumber:body:)` — each wraps one `gh` CLI call.
3. Move the orchestration (push → capacity check → create PR → comment) into a `PRUseCase` or `ClaudeChainService`. `ProjectConfiguration` lives there too.

`PRStep` can remain a `PipelineNode` that delegates to a `PRService`, but the service lives in the Services layer and the orchestration lives in a use case. The SDK nodes stay thin.

---

## Finding 2 — [Severity: 7/10] `Pipeline` actor violates the stateless struct rule

**Location:** Phase 2 — `Pipeline` Execution Engine section; Phase 3 principles ("Pipeline actor handles ReviewStep via type cast — continuation held by actor, not by the node")

### Guidance

> **Stateless `Sendable` structs** — no mutable internal state, no actors, no classes.
>
> **Does the SDK hold mutable state? → Yes = violation**
>
> If the class held mutable state, that state likely belongs in a Service.

### Interpretation

The `Pipeline` actor holds mutable execution state by design: the `CheckedContinuation` for a paused `ReviewStep`, the current node index, the running `Task` reference for cancellation. This is inherently stateful — a `Pipeline` instance is not interchangeable with another `Pipeline` instance after `run()` starts. Actors are the Swift concurrency mechanism *for* mutable state, which is the inverse of what SDKs require.

Severity 7/10: the code is placed in the right layer by name (`PipelineSDK`) but violates a core SDK principle. The practical pain is that it becomes impossible to treat `Pipeline` as a value type, complicates testing (you must manage the actor's lifecycle), and couples the SDK to the assumption that only one pipeline runs per actor instance.

### Resolution

Move `Pipeline` to the Services layer as `PipelineService` (or keep it in `PipelineSDK` as an explicitly stateful type but document it as an exception to the stateless rule).

The stateless SDK surface becomes `PipelineRunner` — a struct with a single `run(nodes:configuration:context:onProgress:)` method that accepts all inputs and returns the final context. The caller (service or use case) owns the state: the `Task`, the current index on retry, and the `CheckedContinuation` for review pausing.

```swift
public struct PipelineRunner: Sendable {
    public func run(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext
}
```

`stop()` / `approve()` / `cancel()` become methods on the wrapping service actor, not on the SDK type.

---

## Finding 3 — [Severity: 6/10] `ReviewStep` creates UI-interaction coupling in SDK

**Location:** Phase 2 — `ReviewStep` section

### Guidance

> **Generic and reusable — could be used by any project as-is.** Could another project use this SDK as-is? → Yes = correct.
>
> **No business concepts — no app-specific types, no domain logic.**

### Interpretation

`ReviewStep.run()` suspends via `CheckedContinuation` and requires the caller to later invoke `pipeline.approve()` or `pipeline.cancel()`. The design note explicitly says "The Mac app model receives a `.pausedForReview` event, shows the approval UI, then calls `pipeline.approve()`." The `ReviewStep` is therefore designed around a Mac app's approval interaction — a CLI consumer has no mechanism to call `approve()` interactively, and a server consumer has no human to ask.

Severity 6/10: it doesn't cross a dependency boundary, but it bakes a UI interaction pattern into an SDK, limits reuse to interactive Mac contexts, and requires the `Pipeline` actor to expose `approve()`/`cancel()` — surface area that exists only to serve this one node.

### Resolution

Decouple the approval mechanism from the node. `ReviewStep` emits a `.pausedForReview(resume: CheckedContinuation<Bool, Error>)` progress event and suspends. The *caller* (app model, CLI handler, or test) receives the continuation and decides how to resume it. `Pipeline` (or `PipelineService`) does not need `approve()`/`cancel()` methods; those live in the app-layer model that holds the continuation reference from the progress event.

---

## Summary

| | |
|---|---|
| **Layer** | SDKs |
| **Findings** | 3 |
| **Highest severity** | 8/10 |
| **Overall health** | The node protocol and context-passing design are well-suited to the SDK layer, but `PRStep` imports a full GitHub PR workflow into the SDK and `Pipeline` breaks the stateless struct rule. |
| **Top priority** | Refactor `PRStep` — extract the multi-step orchestration (push → capacity check → create → comment) into a service or use case, leaving only thin single-operation SDK methods for `git push` and `gh pr create`. |
