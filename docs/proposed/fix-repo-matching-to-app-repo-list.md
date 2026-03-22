## Fix Repository Matching to Only Source Repos from App's Repo List

### Background

The feature that matches repositories from text (likely voice-transcribed or pasted text) is currently pulling in repositories that are not part of the user's configured repository list in the AIDevTools app. The matching logic appears to be sourcing repositories from somewhere other than the app's own repo store. This needs to be fixed so that repository matching only returns repositories that exist in the user's configured repo list within the app.

## - [x] Phase 1: Interpret the Request

When executed, this phase will explore the codebase and recent commits to understand what the voice transcription is asking for. The request text — "The feature to match repository from text is pulling repos that are not in my repo list in this app. I'm not sure where it is coming from. I'd like it to only source repos from this repo." — likely means:

- There is a feature that extracts/matches repository references from text input
- It is returning repositories not in the user's configured list
- The fix should constrain matching to only repositories configured in the app

This phase will find the relevant code for repository-from-text matching, identify where repositories are being sourced, and document the current behavior. It will look at recent commits and search for repository matching logic. Document findings underneath this phase heading.

### Findings

#### Repository Matching Code Flow

The "Match repository from text" feature lives in `GeneratePlanUseCase.matchRepo()` (`GeneratePlanUseCase.swift:117-152`). It:

1. Takes a `voiceText` string and a `[RepositoryInfo]` array
2. Formats the repo list (id, description, recent focus) into a prompt
3. Sends the prompt to Claude CLI via `ClaudeCLIClient.runStructured()` with a JSON schema constraining output to `{ repoId, interpretedRequest }`
4. Returns the `RepoMatch` result

**Validation:** After matching, the caller validates the returned `repoId` UUID exists in the passed `repositories` array (lines 88-91). If not found, it throws `GenerateError.repoNotFound`.

#### Where Repositories Are Sourced

- **Mac App:** `GeneratePlanSheet` passes `model.repositories` → loaded by `WorkspaceModel.load()` → `LoadRepositoriesUseCase` → `RepositoryStore.loadAll()` → reads `{dataPath}/repositories.json`
- **CLI:** `PlanRunnerPlanCommand` → `ReposCommand.makeStore()` → `RepositoryStore.loadAll()` → same `repositories.json`
- **Default data path:** `~/Desktop/ai-dev-tools` (from `RepositoryStoreConfiguration`)

Both entry points source repos exclusively from the app's `repositories.json`. The `matchRepo()` prompt only includes repos from the passed array.

#### Uncommitted Working Tree Changes

The working tree contains changes that add a `selectedRepository` bypass to the matching flow:

- `GeneratePlanUseCase.Options` gains a `selectedRepository: RepositoryInfo?` field
- `GeneratePlanUseCase.run()` skips `matchRepo()` when `selectedRepository` is provided
- `GeneratePlanSheet` adds a "Match repository from text" toggle (default off) — when off, uses the currently selected repo directly; when on, triggers Claude-based matching
- `PlanRunnerModel.generate()` accepts the optional `selectedRepository` parameter

#### Root Cause Hypothesis

The `matchRepo()` function runs Claude CLI **without a working directory** (unlike `generatePlan()` which passes `repo.path.path()`). With `dangerouslySkipPermissions = true`, `printMode = true`, and `verbose = true`, Claude CLI has filesystem access in whatever directory the process runs from. Claude may be discovering or referencing repos outside the provided list in its reasoning, even though the JSON output is schema-constrained. The existing UUID validation guard would catch truly invalid matches, but the user may be seeing Claude's verbose output reference unexpected repos.

Additionally, the prompt doesn't explicitly instruct Claude to **only** choose from the listed repos — it says "Available repositories" but doesn't say "You must choose one of these."

## - [ ] Phase 2: Gather Architectural Guidance

When executed, this phase will look at the repository's skills and architecture docs to identify which documentation and architectural guidelines are relevant to this request. It will read and summarize the key constraints. Document findings underneath this phase heading.

## - [ ] Phase 3: Plan the Implementation

When executed, this phase will use insights from Phases 1 and 2 to create concrete implementation steps. It will append new phases (Phase 4 through N) to this document, each with: what to implement, which files to modify, which architectural documents to reference, and acceptance criteria. It will also append a Testing/Verification phase and a Create Pull Request phase at the end. The Create Pull Request phase MUST always use `gh pr create --draft` (all PRs are drafts). This phase is responsible for generating the remaining phases dynamically.
