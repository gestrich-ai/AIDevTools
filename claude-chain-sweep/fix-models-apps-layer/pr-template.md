## Apps Layer Model Compliance

**File:** {{TASK_DESCRIPTION}}

Refactors the model to comply with apps-layer architecture rules:
- `@MainActor @Observable class` annotations
- Enum-based state (no scattered `isLoading`/`error`/`result` properties)
- No orchestration in the model (use cases handle multi-step logic)
- Errors caught and set as state

## Checklist

- [ ] Model has `@MainActor @Observable class`
- [ ] State is a single enum (or model was already compliant)
- [ ] No multi-step SDK/service orchestration in the model
- [ ] Errors are caught and surface as state
- [ ] Build passes
- [ ] Tests pass
