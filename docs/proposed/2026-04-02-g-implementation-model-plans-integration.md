## Implementation Model — Plans Tab Integration & Architecture Tab Removal

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture reference for placing new types |
| `swift-app-architecture:swift-swiftui` | SwiftUI model-view patterns for wiring button state |

## Background

The Architecture tab was built around a multi-step planning flow (requirements → layer mapping → evaluation → scoring → report). Bill only uses one output from it: the **Implementation Model** — the Layer Map visualization showing which layers and modules are affected by a plan, and how many files each touches.

This plan:
1. Adds an "Implementation Model" button to the Plans tab detail view. Clicking it runs a single-node pipeline that reads the plan's phases + `ARCHITECTURE.md` and asks AI to produce an `ArchitectureDiagram` (layers → modules → file changes). The result is stored alongside the plan as `<planName>-implementation-model.json`. Once generated, the button opens `ArchitectureDiagramView` in a sheet.
2. Removes the Architecture tab entirely.

The existing `ArchitectureDiagram` type (already in `MarkdownPlannerService`) and `ArchitectureDiagramView` (already in `Views/Architecture/`) are reused directly — no new data model is needed.

**What the node does (one AI call):**
- Input: the plan's phase list (from the markdown file) + `ARCHITECTURE.md` content from the repo
- Prompt: map each phase to the architectural layer(s) it touches, the module(s) affected, and the files added/modified/deleted
- Output: `ArchitectureDiagram` (same JSON shape as the existing `-architecture.json` sidecar)

This is a strict subset of what `PlanAcrossLayersUseCase` already does — no guidelines, no requirements formation, no scoring.

**Existing infrastructure already in place:**
- `ArchitectureDiagram` / `ArchitectureLayer` / `ArchitectureModule` / `ArchitectureChange` — `MarkdownPlannerService`
- `ArchitectureDiagramView`, `LayerBandView`, `ModuleCardView`, `ModuleDetailPanel` — `Views/Architecture/`
- `MarkdownPlannerDetailView.loadArchitectureDiagram()` already reads a JSON sidecar — same pattern used for storage

---

## - [ ] Phase 1: Implement `ImplementationModelNode`

Create `ImplementationModelNode` in `MarkdownPlannerFeature/usecases/`.

**Skills to read**: `swift-app-architecture:swift-architecture`

Input/output:

```swift
struct ImplementationModelRequest: Sendable {
    let planPhases: [String]   // phase headings + body text from the markdown plan
    let repoPath: String       // to locate ARCHITECTURE.md
}
// Output: ArchitectureDiagram (existing type from MarkdownPlannerService)
```

Tasks:
- `ImplementationModelNode: UseCase` (struct conforming to `UseCase` protocol, consistent with other use cases in the feature)
- Reads `ARCHITECTURE.md` from `repoPath`; if absent, uses an empty string
- Builds a prompt: given the plan phases and the architecture doc, produce a JSON `ArchitectureDiagram` listing every layer, its modules, and the files each module adds/modifies/deletes as part of this plan
- Calls `client.runStructured(ArchitectureDiagram.self, ...)` — the existing `ArchitectureDiagram` is already `Codable`
- Returns `ArchitectureDiagram`

The JSON schema passed to `runStructured` must match `ArchitectureDiagram`'s Codable shape: `{ layers: [{ name, modules: [{ name, changes: [{ file, action, summary?, phase? }] }] }] }`.

## - [ ] Phase 2: Add `generateImplementationModel` to `MarkdownPlannerService`

Add a method to `MarkdownPlannerService` (in `MarkdownPlannerFeature`) that runs `ImplementationModelNode` and persists the result.

```swift
func generateImplementationModel(
    for plan: MarkdownPlan,
    repoPath: String,
    onOutput: (@Sendable (String) -> Void)?
) async throws -> ArchitectureDiagram
```

Tasks:
- Read plan phase content from `plan.planURL` using the existing `MarkdownPipelineSource` / file read
- Construct `ImplementationModelRequest(planPhases:repoPath:)`
- Run `ImplementationModelNode`
- Write result as JSON to `<planName>-implementation-model.json` in the same directory as the plan file (same convention as the existing `-architecture.json` sidecar)
- Return the `ArchitectureDiagram`

Storage path (mirrors existing `loadArchitectureDiagram` convention):
```
plan.planURL.deletingPathExtension().lastPathComponent + "-implementation-model.json"
```

## - [ ] Phase 3: Wire `MarkdownPlannerModel`

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add generation + loading to `MarkdownPlannerModel`.

Tasks:
- Add `var implementationModel: ArchitectureDiagram?` to `MarkdownPlannerModel`
- Add `var isGeneratingImplementationModel: Bool` to track in-flight generation
- Load from disk in the existing `loadPlan`/`onAppear` path: read `<planName>-implementation-model.json` if present (same pattern as `loadArchitectureDiagram` in `MarkdownPlannerDetailView` — but moved into the model)
- Add `func generateImplementationModel() async` that calls `MarkdownPlannerService.generateImplementationModel(...)`, sets `isGeneratingImplementationModel` during the call, and stores the result in `implementationModel` on completion

## - [ ] Phase 4: Add "Implementation Model" Button to `MarkdownPlannerDetailView`

**Skills to read**: `swift-app-architecture:swift-swiftui`

Tasks:
- Add a `@State private var showingImplementationModel = false` sheet trigger
- Add an "Implementation Model" button to the toolbar or the bottom button bar:
  - If `implementationModel == nil` and not generating: label "Implementation Model", action calls `model.generateImplementationModel()`
  - If `isGeneratingImplementationModel == true`: show a `ProgressView` in place of the button (or disabled button with spinner)
  - If `implementationModel != nil`: label "View Implementation Model", action sets `showingImplementationModel = true`
- Add `.sheet(isPresented: $showingImplementationModel)` presenting `ArchitectureDiagramView` with the diagram

Remove the existing `loadArchitectureDiagram()` call and `@State private var architectureDiagram` from `MarkdownPlannerDetailView` — that logic moves to `MarkdownPlannerModel` in Phase 3.

The existing `DisclosureGroup("Architecture", ...)` section that showed the architecture diagram in the plan content view can be removed or kept; if kept, wire it to `implementationModel` instead of the old `architectureDiagram`.

## - [ ] Phase 5: Remove Architecture Tab

Tasks:
- Remove the Architecture tab from the app's tab bar / navigation (wherever tabs are registered — likely `ContentView.swift` or the app's root view)
- Delete `ArchitecturePlannerModel.swift` from `Apps/AIDevToolsKitMac/Models/`
- Delete `Views/ArchitecturePlanner/` (`ArchitecturePlannerView.swift`, `ArchitecturePlannerDetailView.swift`, `GuidelineBrowserView.swift`)
- Remove `ArchitecturePlannerFeature` from `Package.swift` targets and any `import ArchitecturePlannerFeature` in the Mac app
- `ArchitecturePlannerService` (SwiftData models, store) can be left in place for now — removing it would require a SwiftData migration. Leave its `Package.swift` target but stop importing it in the Mac app UI layer.
- Confirm the app builds cleanly with no references to removed types

## - [ ] Phase 6: Validation

- Build and run the Mac app; confirm Architecture tab is gone from navigation
- Open a plan in the Plans tab; confirm "Implementation Model" button is visible
- Click "Implementation Model" on a plan that has no existing model; confirm it runs, shows a progress indicator, and completes
- After generation: confirm the `-implementation-model.json` file exists next to the plan file
- Click "View Implementation Model"; confirm the sheet opens showing the Layer Map with correct layers and module file counts
- Re-open the app; confirm the Implementation Model button shows "View Implementation Model" (loaded from disk), not "Implementation Model" (not generated yet)
- Run existing Plans tab tests to confirm no regressions in plan generation / execution
