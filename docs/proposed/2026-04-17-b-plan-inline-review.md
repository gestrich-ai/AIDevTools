## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — ensures review service and model layers land in the right place |
| `ai-dev-tools-code-organization` | Swift file and type organization conventions |
| `ai-dev-tools-composition-root` | How shared services are wired in the Mac app |
| `ai-dev-tools-enforce` | Post-change enforcement of all project standards |

## Background

After a plan executes, the resulting code changes are hard to assess for correctness and quality. PR Radar already solves an adjacent problem: it runs AI-driven rules against a pull request's diff and produces inline comments on specific lines. This plan introduces a similar review capability for local plan output — without requiring a GitHub PR.

The idea: after plan execution (or on demand), run a review against the plan's `GitDiff` using AI rules. The result is a set of **annotations** (file path, line number, feedback text, severity) that appear inline in the diff view built by the `2026-04-17-a-plan-diff-view.md` plan.

**Relationship to PR Radar:**

PR Radar's review pipeline (`PrepareUseCase`, `TaskCreatorService`, rule evaluation) operates on `PRDiff`/`PRModel` and is tied to GitHub pull requests. The plan review feature is conceptually similar but operates on local git diffs with no PR context. These are currently separate — this plan does not attempt to merge them. However, the data models and annotation display layer should be designed with eventual convergence in mind.

**Dependency:**

This plan builds on `GitDiffView` and `CommitListDiffView` from `2026-04-17-a-plan-diff-view.md`. That plan must be complete (or at least Phase 2) before this one begins.

## Phases

## - [ ] Phase 1: Define the `PlanReviewAnnotation` model

**Skills to read**: `ai-dev-tools-architecture`

Define a `PlanReviewAnnotation` struct in an appropriate service or models layer (not in the UI):

```swift
public struct PlanReviewAnnotation: Identifiable, Sendable {
    public let id: UUID
    public let filePath: String
    public let lineNumber: Int?      // nil = file-level annotation
    public let feedback: String
    public let severity: Severity    // info, warning, error

    public enum Severity: String, Sendable { case info, warning, error }
}
```

Also define `PlanReviewResult` — the output of a review run — containing a list of `PlanReviewAnnotation` objects and summary metadata (total count, run duration, model used).

## - [ ] Phase 2: Build `PlanReviewService`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Add `PlanReviewService` that takes a `GitDiff` and a set of review rules (initially a simple hardcoded set; rule loading can be generalized later) and returns a `PlanReviewResult`.

The service:
1. Formats the `GitDiff` as context for the AI (file paths, added/changed lines)
2. Sends it to Claude with a prompt describing what to look for (architecture violations, obvious bugs, style issues)
3. Parses the structured response into `[PlanReviewAnnotation]`
4. Returns `PlanReviewResult`

Use the existing AI provider infrastructure (the same provider selection already in `PlanDetailView`). Keep the rule set simple initially — the goal is establishing the pipeline, not comprehensive rule coverage.

## - [ ] Phase 3: Display annotations inline in `GitDiffView`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-organization`

Extend `GitDiffView` (from the diff plan) to optionally accept `[PlanReviewAnnotation]`. When annotations are present:

- After each `DiffLineRowView` whose `newLineNumber` matches an annotation's `lineNumber`, insert an annotation card below it. Style it similarly to `InlineCommentCard` from `RichDiffViews.swift` — reuse that component if possible, or mirror its visual design (colored left border, rounded card, padding).
- File-level annotations (no `lineNumber`) appear below the file header.
- The file sidebar shows an annotation count badge next to files that have annotations, matching the style of PR Radar's violation badges.

`GitDiffView`'s annotations parameter is optional (`[PlanReviewAnnotation]? = nil`) — the view works without annotations and this feature is purely additive.

## - [ ] Phase 4: Add review trigger to `PlanDetailView`

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

Add a "Review" button to `PlanDetailView`'s header bar (alongside the existing Execute button). The button:
- Is enabled when the plan has completed phases and is not currently executing
- On tap, calls `PlanReviewService` with the diff of the plan's completed commits
- Shows a progress indicator while running
- On completion, passes the `PlanReviewResult` annotations into the diff view

Store `planReviewResult` as `@State` in `PlanDetailView`. Pass it down to `CommitListDiffView` → `GitDiffView`.

## - [ ] Phase 5: Validation

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`

**Automated tests:**
- `PlanReviewService` returns correctly structured `PlanReviewAnnotation` objects for a stubbed AI response
- `GitDiffView` renders annotation cards below the correct lines given a known `GitDiff` and annotation list
- File sidebar shows correct annotation counts

**Manual checks:**
- Execute a plan with a few phases; click "Review"; verify annotations appear inline in the diff
- Verify file sidebar shows annotation badges on affected files
- Verify `GitDiffView` without annotations (normal diff usage) is unaffected
- Verify no PR Radar functionality is broken

**Enforce:**
Run `/ai-dev-tools-enforce` on all files changed across all phases before marking this plan complete.
