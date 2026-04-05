# Fix Apps Layer Model Compliance

You are given a Swift model file from the Apps layer (`AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/`). Refactor it — and any other files in the repo required to support the change — so it fully complies with the apps-layer architecture rules.

## Architecture Rules

Read `.agents/skills/ai-dev-tools-architecture/references/apps-layer.md` for the full reference. Key rules:

1. **`@MainActor @Observable class`** — every model must have both annotations
2. **No orchestration** — models must not call multiple SDK/service objects in sequence; extract that logic into a use case in `AIDevToolsKit/Sources/Features/`
3. **Enum-based state** — replace scattered `var isLoading`, `var error`, `var result` properties with a single `ModelState` enum
4. **Depth over width** — one user action = one use case call
5. **Error catching** — errors must be caught and set as state, not swallowed via `print` or empty catch blocks

## Process

1. Read the model file at the path listed below
2. Identify every violation of the rules above
3. If there are no violations, make no changes and stop
4. For each violation, make the minimum change to bring it into compliance:
   - Orchestration → extract to a new use case in `AIDevToolsKit/Sources/Features/<FeatureName>/`; update Package.swift if a new target is needed
   - Scattered state → introduce a `ModelState` enum; migrate properties one at a time
   - Swallowed errors → set error state instead
   - Missing `@MainActor` or `@Observable` → add the annotations
   - If other files (views, CLI commands, tests) break due to the model change, fix them too
5. Build: `swift build --package-path AIDevToolsKit 2>&1 | grep -E "error:" | head -20`
6. Run tests: `swift test --package-path AIDevToolsKit 2>&1 | tail -20`
7. Run /ai-dev-tools-enforce on every file you changed

## Important

- Do not refactor code unrelated to the violations found
- If a suitable use case already exists, use it rather than creating a duplicate
- Keep changes minimal and focused
