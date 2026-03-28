# Architecture Review: ActivePlanModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ActivePlanModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 6/10] Model orchestrates file watching and parsing instead of consuming a use case

**Location:** Lines 12-19

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **Depth over width** — one user action = one use case call
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case, not in an app-layer model or service.

### Interpretation

`startWatching(url:)` creates a `FileWatcher` (SDK), iterates its async stream, and transforms output by calling `MarkdownPlannerModel.parsePhases(from:)`. This is two operations coordinated in the model — the "width" pattern. If a CLI command or another entry point needed to watch a plan file and parse its phases, it would have to duplicate this logic. Severity 6/10 because it's mild orchestration (only two steps) and the transformation is simple, but it still prevents reuse from non-UI entry points.

### Resolution

Extract into a use case or feature-layer stream that yields parsed phases:

```swift
// features/PlanFeature/usecases/WatchPlanUseCase.swift
struct WatchPlanUseCase {
    func stream(url: URL) -> AsyncStream<(String, [PlanPhase])> {
        // FileWatcher + parsePhases logic here
    }
}
```

The model becomes a thin consumer:

```swift
func startWatching(url: URL) {
    watchTask?.cancel()
    watchTask = Task {
        for await (content, phases) in useCase.stream(url: url) {
            self.content = content
            self.phases = phases
        }
    }
}
```

---

## Finding 2 — [Severity: 5/10] No enum-based state; independent stored properties with no lifecycle representation

**Location:** Lines 8-10

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on model state — no separate loading/error properties.

### Interpretation

The model uses two independent stored properties (`content: String` and `phases: [PlanPhase]`) with no representation of idle, watching, or error states. The UI cannot distinguish between "hasn't started watching yet" (empty content) and "watching a file that happens to be empty." There is also no error state — if the file disappears or the stream ends, the model shows stale data silently. Severity 5/10 because the model is small and the ambiguity is limited, but the pattern prevents the UI from showing meaningful status.

### Resolution

Introduce a `ModelState` enum:

```swift
enum ModelState {
    case idle
    case watching(content: String, phases: [PlanPhase])
    case error(Error, prior: (String, [PlanPhase])?)
}

private(set) var state: ModelState = .idle
```

---

## Finding 3 — [Severity: 5/10] Cross-model static method dependency for parsing logic

**Location:** Line 17

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`

### Interpretation

`ActivePlanModel` calls `MarkdownPlannerModel.parsePhases(from:)` — a static parsing method on another `@Observable` app-layer model. Parsing markdown into structured phases is not a UI concern; it's transformation logic that belongs in a Service or SDK. Having one app-layer model reach into another for utility functions creates horizontal coupling and means the parsing logic is trapped inside an `@Observable @MainActor` class where it doesn't need to be. Severity 5/10 because it works but couples two models and misplaces parsing logic.

### Resolution

Move `parsePhases(from:)` to a service-layer or SDK-level struct (e.g., `PlanParser` in `AIOutputSDK` or a `PlanService`). Both `ActivePlanModel` and `MarkdownPlannerModel` can then call the shared parser without depending on each other.

---

## Finding 4 — [Severity: 3/10] `phases` is always derived from `content` but stored independently

**Location:** Lines 8-9, 16-17

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties

### Interpretation

`phases` is set on every iteration by parsing `content`, so it is fully derivable. Storing both separately creates a (currently theoretical) risk of them going out of sync if a future code change updates one without the other. Severity 3/10 because the current code keeps them in sync, but the design doesn't enforce it.

### Resolution

Either make `phases` a computed property:

```swift
var phases: [PlanPhase] {
    PlanParser.parsePhases(from: content)
}
```

Or consolidate both into the enum-based state from Finding 2, which naturally groups them.

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 4 |
| **Highest severity** | 6/10 |
| **Overall health** | Small, focused model with mild orchestration. The main issues are horizontal coupling to another model's parsing logic and missing state lifecycle representation. |
| **Top priority** | Extract `FileWatcher` + `parsePhases` coordination into a feature-layer use case to enable reuse from non-UI entry points. |
