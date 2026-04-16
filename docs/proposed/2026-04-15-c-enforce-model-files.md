## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Orchestrates all six practice skills — architecture, config arch, build quality, code org, code quality, swift testing |
| `ai-dev-tools-architecture` | 4-layer architecture rules — layer boundaries, dependency direction, orchestration |
| `ai-dev-tools-build-quality` | Compiler warnings, TODO/FIXME, dead code, debug artifacts |
| `ai-dev-tools-code-organization` | File and type organization conventions |
| `ai-dev-tools-code-quality` | Force unwraps, raw strings, fallback values, duplicated logic |

## Background

The project has 32 model files spread across three layers. Running `/ai-dev-tools-enforce` on each surfaces violations so we can incrementally clean up the worst offenders. The goal is not a ground-up rewrite but bounded, incremental fixes targeting severity 5–10 issues first.

Model file inventory:

| Group | Files | Location |
|-------|-------|----------|
| Large App Models (200+ lines) | ClaudeChainModel, ChatModel, PlanModel, ArchitecturePlannerModel, EvalRunnerModel, WorkspaceModel | `Apps/AIDevToolsKitMac/Models/` |
| Small App Models | CredentialModel, PipelineModel, WorktreeModel, LogsModel, ActivePlanModel, MCPModel, ExecutionPanelModel, SettingsModel, ExperimentalSettings, ChatSettings, PlansChatContext, ProviderModel, AppModel, LogItem, RepositoryEvalConfig | `Apps/AIDevToolsKitMac/Models/` |
| PRRadar Models | AllPRsModel, PRModel, AuthorOption | `Apps/AIDevToolsKitMac/PRRadar/Models/` |
| Service Models | EvalSummary, EvalSuite, CaseResult, SkillCheckResult, GradingModels, EvalCase, SkillContent | `Services/*/Models/` |
| Feature Models | WorktreeStatus | `Features/WorktreeFeature/Models/` |

## - [x] Phase 1: Analyze — inventory all violations

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Used enforce analyze-mode conventions to produce a single ranked report in `reviews/2026-04-15-enforce-model-files-phase-1-analysis.md`, prioritized architecture and hidden-side-effect issues over cosmetic noise, and recorded zero-finding files explicitly so later phases can work from a complete inventory.

**Skills to read**: `ai-dev-tools-enforce` (Analyze mode)

Run enforce in **analyze mode** on every model file to produce a full violation inventory before touching any code. This gives a prioritized list so we fix the highest-severity issues first rather than discovering them file by file.

Files to analyze (pass all at once or in two batches):

**Batch A — App Models:**
```
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ActivePlanModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/AppModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ArchitecturePlannerModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ChatSettings.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/CredentialModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/EvalRunnerModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ExecutionPanelModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ExperimentalSettings.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/LogItem.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/LogsModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/MCPModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/PipelineModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/PlanModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/PlansChatContext.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/ProviderModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/RepositoryEvalConfig.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SettingsModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorktreeModel.swift
```

**Batch B — PRRadar + Service + Feature Models:**
```
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Models/AllPRsModel.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Models/AuthorOption.swift
AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Models/PRModel.swift
AIDevToolsKit/Sources/Features/WorktreeFeature/Models/WorktreeStatus.swift
AIDevToolsKit/Sources/Services/EvalService/Models/CaseResult.swift
AIDevToolsKit/Sources/Services/EvalService/Models/EvalCase.swift
AIDevToolsKit/Sources/Services/EvalService/Models/EvalSuite.swift
AIDevToolsKit/Sources/Services/EvalService/Models/EvalSummary.swift
AIDevToolsKit/Sources/Services/EvalService/Models/GradingModels.swift
AIDevToolsKit/Sources/Services/EvalService/Models/SkillCheckResult.swift
AIDevToolsKit/Sources/Services/SkillService/Models/SkillContent.swift
```

**Expected output**: A ranked violation report sorted by severity. Use this to determine the fix order for Phases 2–5.

## - [x] Phase 2: Fix — large App Models (severity 7–10)

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`
**Principles applied**: Moved Claude chain orchestration out of the App-layer model into focused Feature-layer use cases for chain loading, detail enrichment, execution, and staged finalization. Kept `ClaudeChainModel` as the UI reducer that manages observable state, chat output, and pipeline presentation while preserving the existing view-facing API.

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`

Target the large App Models that are most likely to have architectural violations given their size and complexity:

- `ClaudeChainModel.swift` (542 lines)
- `ChatModel.swift` (450 lines)
- `PlanModel.swift` (328 lines)
- `ArchitecturePlannerModel.swift` (287 lines)
- `EvalRunnerModel.swift` (267 lines)
- `WorkspaceModel.swift` (228 lines)

Run enforce in **fix mode** on these files. Focus on severity 7–10 first:
- Models orchestrating multiple service/SDK calls directly (should delegate to use cases)
- Inline use case construction with default parameters (inject via init instead)
- Upward dependencies or feature-to-feature imports
- Independent state booleans/data outside a `State` enum

After fixing, build the project to confirm it compiles.

## - [x] Phase 3: Fix — large App Models (severity 5–6)

**Skills used**: `ai-dev-tools-build-quality`, `ai-dev-tools-code-quality`, `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-code-organization`, `ai-dev-tools-swift-testing`
**Principles applied**: Centralized `PlanModel`'s plan-loading/detail/completion/template-append wiring behind a single dependency container created at initialization so method-level dependency construction no longer drifts. Replaced `EvalRunnerModel`'s empty-string provider fallback with an explicit configuration error state, preserving existing behavior everywhere a real provider is available and keeping the current worktree build-compatible.

**Skills to read**: `ai-dev-tools-code-quality`, `ai-dev-tools-build-quality`

Second pass over the same six large App Models, now targeting severity 5–6:
- Force unwraps
- Error swallowing
- Raw `String`/`[String:Any]` where typed models should exist
- `var` properties that are never mutated after init → `let`
- Compiler warnings

Build after changes.

## - [x] Phase 4: Fix — small App Models + PRRadar Models

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-configuration-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Removed hidden persistence side effects from the small settings models by making writes explicit at the view boundary, injected small use-case dependencies into `PipelineModel` and `SettingsModel`, and shifted full PR review pipeline sequencing onto the existing Feature-layer `RunPipelineUseCase` so `PRModel` mainly reduces stream progress into UI state.

**Skills to read**: `ai-dev-tools-enforce`

Run enforce in **fix mode** on the remaining App layer files:

Small App Models (all severity levels):
- ActivePlanModel, AppModel, ChatSettings, CredentialModel, ExecutionPanelModel, ExperimentalSettings, LogItem, LogsModel, MCPModel, PipelineModel, PlansChatContext, ProviderModel, RepositoryEvalConfig, SettingsModel, WorktreeModel

PRRadar Models:
- AllPRsModel, PRModel, AuthorOption

These are smaller (20–90 lines each) so a single enforce pass should cover all severity levels at once. Build after changes.

## - [x] Phase 5: Fix — Service + Feature Models

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`
**Principles applied**: Kept the Service and Feature models as plain, lower-layer value types, and tightened `CaseResult` to immutable copy-on-write semantics so Feature-layer code no longer mutates Service-layer model state directly.

**Skills to read**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`

Run enforce in **fix mode** on the non-App layer model files. Pay extra attention to layer correctness — Service and Feature models must not import App-layer types, must be `Sendable` where shared across concurrency domains, and should avoid mutable state unless justified.

Files:
- `Services/EvalService/Models/`: CaseResult, EvalCase, EvalSuite, EvalSummary, GradingModels, SkillCheckResult
- `Services/SkillService/Models/`: SkillContent
- `Features/WorktreeFeature/Models/`: WorktreeStatus

Build after changes.

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-build-quality`

1. Build the full project — confirm zero new warnings introduced
2. Run the existing test suite to confirm no regressions
3. Spot-check the Phase 1 analyze report: verify the highest-severity findings from that report have been addressed
