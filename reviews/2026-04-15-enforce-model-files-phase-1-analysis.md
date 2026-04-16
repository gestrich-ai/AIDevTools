# Enforce Model Files Phase 1 Analysis

## Findings

## [Severity 8/10] PR review pipeline orchestration lives in the app model — PRModel.swift

**Location:** Lines 502–535, 744–999

**Why this is a problem**
`PRModel` coordinates the full review pipeline itself: it decides phase order, manages phase transitions, constructs phase use cases, streams AI output into chat models, merges task progress into UI state, and refreshes saved comments at the end. That is multi-step workflow orchestration in an `@Observable` app model, which the architecture guide assigns to a Feature-layer use case. Keeping the pipeline in the model makes the Mac UI the only first-class caller, increases test surface area in the view model, and makes CLI parity harder because the orchestration logic is not centralized behind one reusable use case.

**How to fix**
Extract the end-to-end PR review workflow into a Feature-layer streaming use case that owns phase sequencing and emits typed progress events. Keep `PRModel` focused on reducing those events into UI state and binding stream output to `ChatModel`.

## [Severity 8/10] Claude Chain execution still mixes UI state with multi-step workflow orchestration — ClaudeChainModel.swift

**Location:** Lines 93–171, 182–310

**Why this is a problem**
`ClaudeChainModel` does more than present state: it resolves repo slug and GitHub services, builds chain/detail/finalize use cases on demand, computes worktree options, starts execution strategies, creates pipeline models, and reloads detail after completion. That is app-layer orchestration across Features, Services, and SDK-backed operations. The architecture guide calls for those workflows to live behind use cases so the app model becomes a thin reducer and the same behavior can be reused from CLI entry points without duplicating control flow.

**How to fix**
Introduce feature use cases for the remaining workflows: one for loading/enriching chains and one for staged-finalization/execution. The model should inject those use cases and only translate their progress/result events into `State`, `taskPipelines`, and `executionChatModel`.

## [Severity 6/10] Preference writes are hidden inside property observers — ChatSettings.swift

**Location:** Lines 6–19

**Why this is a problem**
Every mutable property in `ChatSettings` performs persistence inside `didSet`. That creates hidden side effects: any caller that thinks it is just changing in-memory state is also writing to `UserDefaults`. The code-quality guide explicitly calls out I/O in property observers because it makes state changes harder to reason about, harder to batch, and harder to test.

**How to fix**
Store the values plainly and expose explicit update methods, for example `updateEnableStreaming(_:)` and `updateResumeLastSession(_:)`, that both mutate the property and persist the change. Callers that need persistence can use the explicit methods instead of triggering disk writes implicitly.

## [Severity 6/10] Experimental preference writes are hidden inside property observers — ExperimentalSettings.swift

**Location:** Lines 9–18

**Why this is a problem**
`ExperimentalSettings` has the same hidden-side-effect pattern as `ChatSettings`, except it mixes `UserDefaults` writes with `AppPreferences` writes. That means simple state mutation implicitly performs persistence and couples the observable object directly to storage APIs.

**How to fix**
Replace the `didSet` observers with explicit update methods that mutate state and persist it intentionally. That keeps persistence visible at the call site and aligns the model with the code-quality guidance against property-observer I/O.

## [Severity 6/10] Summary parsing failures are silently downgraded to “unavailable” — PRModel.swift

**Location:** Lines 111–126

**Why this is a problem**
`loadSummary()` uses `try?` to parse the saved analyze summary. A missing file and a malformed summary file both collapse into the same `.unavailable` state, so the UI cannot distinguish “there is no summary yet” from “the saved analysis data is broken”. That is a fallback that hides failure and makes corruption harder to diagnose.

**How to fix**
Handle parse errors explicitly. A missing summary file can still map to `.unavailable`, but decoding or schema failures should set an error-bearing state or at least log the parse failure before falling back.

## [Severity 5/10] Plan execution dependencies are rebuilt inline instead of being injected once — PlanModel.swift

**Location:** Lines 73–80, 129–170, 193–229, 291–292

**Why this is a problem**
`PlanModel` reconstructs `PlanService`, `LoadPlansUseCase`, `GetPlanDetailsUseCase`, `CompletePlanUseCase`, and `AppendReviewTemplateUseCase` inside methods. The enforce guidance treats inline use case construction as structural drift because dependency wiring becomes scattered across call sites and is harder to keep consistent with composition-root rules.

**How to fix**
Inject the service and use cases through `init`, or group them into a private dependency container created once at initialization time. Then methods can call stable dependencies instead of rebuilding them ad hoc.

## [Severity 5/10] Eval runner falls back to an empty provider name when no provider is resolved — EvalRunnerModel.swift

**Location:** Lines 122–126

**Why this is a problem**
The initial running state uses `providerFilter?.first ?? registry.defaultEntry?.name ?? ""`. If neither a filter nor a default provider exists, the model records an empty string as the provider name. That hides the configuration failure and pushes an impossible “running with no provider” state into the UI.

**How to fix**
Replace the empty-string fallback with explicit failure handling. Resolve the provider name before entering `.running`, and if none exists, set an error state or throw a dedicated configuration error.

## [Severity 4/10] PipelineModel constructs its use case inline during execution — PipelineModel.swift

**Location:** Lines 33–47

**Why this is a problem**
`PipelineModel.run` creates `RunBlueprintUseCase()` inline on every execution. This is a smaller version of the same dependency-construction issue called out by the enforce guide: the model owns wiring instead of receiving the dependency, which makes substitution and testing harder.

**How to fix**
Inject `RunBlueprintUseCase` through `init` or store it in a private dependency container so the model does not construct it inside `run`.

## [Severity 4/10] Data-path use cases are constructed inline inside the settings model — SettingsModel.swift

**Location:** Lines 12–24

**Why this is a problem**
`SettingsModel` directly creates `LoadDataPathUseCase` and `SaveDataPathUseCase` instead of receiving them. This is a bounded structural issue, but it still spreads dependency wiring into the model and works against the composition-root conventions used elsewhere in the app.

**How to fix**
Inject the load/save use cases through `init`, with default arguments if needed for convenience. That keeps wiring explicit and makes the model easier to test.

## [Severity 4/10] The selected architecture-planning job is writable directly from views — ArchitecturePlannerModel.swift

**Location:** Lines 17–22

**Why this is a problem**
`selectedJob` is observable model state but is not `private(set)`, and the current view layer mutates it directly. The architecture guide flags this pattern because direct view mutation bypasses model methods, making it harder to enforce invariants when selection needs to coordinate with other state.

**How to fix**
Make `selectedJob` `private(set)` and add an explicit selection method such as `selectJob(id:)` or `selectJob(_:)`. Views can call that method instead of mutating model state directly.

## Summary

| File | Findings | Highest severity |
|------|----------|-----------------|
| `ActivePlanModel.swift` | 0 | 0/10 |
| `AllPRsModel.swift` | 0 | 0/10 |
| `AppModel.swift` | 0 | 0/10 |
| `ArchitecturePlannerModel.swift` | 1 | 4/10 |
| `AuthorOption.swift` | 0 | 0/10 |
| `CaseResult.swift` | 0 | 0/10 |
| `ChatModel.swift` | 0 | 0/10 |
| `ChatSettings.swift` | 1 | 6/10 |
| `ClaudeChainModel.swift` | 1 | 8/10 |
| `CredentialModel.swift` | 0 | 0/10 |
| `EvalCase.swift` | 0 | 0/10 |
| `EvalRunnerModel.swift` | 1 | 5/10 |
| `EvalSuite.swift` | 0 | 0/10 |
| `EvalSummary.swift` | 0 | 0/10 |
| `ExecutionPanelModel.swift` | 0 | 0/10 |
| `ExperimentalSettings.swift` | 1 | 6/10 |
| `GradingModels.swift` | 0 | 0/10 |
| `LogItem.swift` | 0 | 0/10 |
| `LogsModel.swift` | 0 | 0/10 |
| `MCPModel.swift` | 0 | 0/10 |
| `PRModel.swift` | 2 | 8/10 |
| `PipelineModel.swift` | 1 | 4/10 |
| `PlanModel.swift` | 1 | 5/10 |
| `PlansChatContext.swift` | 0 | 0/10 |
| `ProviderModel.swift` | 0 | 0/10 |
| `RepositoryEvalConfig.swift` | 0 | 0/10 |
| `SettingsModel.swift` | 1 | 4/10 |
| `SkillCheckResult.swift` | 0 | 0/10 |
| `SkillContent.swift` | 0 | 0/10 |
| `WorktreeModel.swift` | 0 | 0/10 |
| `WorktreeStatus.swift` | 0 | 0/10 |
| `WorkspaceModel.swift` | 0 | 0/10 |

The highest-priority follow-up is to extract the remaining end-to-end workflows out of `PRModel` and `ClaudeChainModel`, because those two files still concentrate the most architecture risk and will keep growing unless the orchestration moves into Feature-layer use cases.
