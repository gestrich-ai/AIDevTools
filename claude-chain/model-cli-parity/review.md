# Review Guidelines

## Step 1: Re-read the Architecture Guidelines

Before reviewing the just-completed work, use the `swift-app-architecture:swift-architecture` skill to re-read the architecture guidelines. Pay particular attention to the parity principle — CLI and Mac app are both entry points into the same use cases, and any API-level operation in one should be accessible in the other.

## Step 2: Check for Missing Parity

Review the changes made in the task. For each model that was audited:

- Verify that every API-level operation in the model has a corresponding CLI command.
- Verify that every CLI command has a corresponding operation accessible from the model.
- If any gaps were missed, add the missing CLI command or model operation now.

Focus on API-level operations only — use case calls, repository reads/writes, service calls. Do not add CLI commands for UI-only concerns like loading state, enum-based view transitions, or presentation logic.
