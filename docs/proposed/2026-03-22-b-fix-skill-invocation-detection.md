## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging guide for evals — file paths, CLI commands, artifact paths, grading pipeline |

## Background

Skills in Claude and Codex are defined as markdown files (typically in `.claude/skills/` or `.agents/skills/`) with YAML front matter. The front matter contains fields like `description` and trigger conditions that tell the AI when and why to use the skill. This front matter is exposed to the AI's main context window — it's what drives whether the AI proactively invokes the skill for a given task.

The problem is that "invocation" can happen accidentally. When an AI is researching a codebase — doing greps, reading directories, exploring file trees — it will naturally encounter skill files because they live inside the repo. If the AI does a `grep` looking for information about a topic and the skill file happens to match, the AI reads the skill content. But this is NOT the skill being invoked. The AI stumbled upon it during research, not because the front matter description triggered the AI to proactively use it.

Genuine skill invocation means the AI recognized from the front matter (in its context) that the skill is relevant to the current task and chose to activate it on its own. The log events and traces for genuine invocation likely look different from the AI simply finding and reading the skill file during a codebase search. The exact difference in how this appears may vary between Claude and Codex, since they handle skill discovery and invocation differently.

Currently, the eval grading may not distinguish between these two scenarios. If that's the case, an eval case that asserts "skill was invoked" could pass even when the AI only accidentally found the skill file, which defeats the purpose of testing whether the skill's front matter is good enough to trigger proactive use.

It's possible this already works correctly — the grading may already distinguish accidental discovery from genuine invocation. The first step is to reproduce the issue and find out.

### Test Case

This repo has an existing skill and eval case that's ideal for testing: the `what-time-is-it` skill (`.agents/skills/what-time-is-it/SKILL.md`). It has clear front matter:

```yaml
name: what-time-is-it
description: Returns the current time. Use when the user asks what time it is or wants to know the current time.
```

With a corresponding eval case (`demo-cases/cases/what-time-is-it.jsonl`) that asserts `skillMustBeInvoked: "what-time-is-it"`. The plan uses this skill directly — progressively weakening its front matter to test at what point invocation detection breaks.

---

## Phases

## - [ ] Phase 1: Research Skill Invocation Mechanics

**Skills to read**: `ai-dev-tools-debug`

Research how Claude and Codex handle skill invocation at the protocol level. Search the web for documentation on how skill front matter is defined and how invocation appears in logs/traces. Understand:

- How front matter fields (`description`, trigger conditions) work for each provider
- What log events or tool use traces are produced when a skill is genuinely invoked vs. when the file is just read during a search
- Whether Claude and Codex differ in how they report invocation

Also trace the current eval grading pipeline to understand how skill invocation is detected today.

## - [ ] Phase 2: Baseline — Run With Strong Front Matter

Run the existing `what-time-is-it` eval case as-is with the current strong front matter (`"Returns the current time. Use when the user asks what time it is or wants to know the current time."`). The prompt is simply "What time is it?" — no hints to grep.

1. Run the eval for both Claude and Codex providers
2. Capture the full AI logs/traces
3. Confirm the skill is genuinely invoked via front matter recognition
4. Confirm the `skillMustBeInvoked` assertion passes

This establishes the positive baseline: what genuine invocation looks like in the logs.

## - [ ] Phase 3: Weaken Front Matter Progressively

Modify the `what-time-is-it` skill's front matter in stages, running the same eval case at each stage to see when invocation stops. Suggested progression:

1. **Mild weakening** — Make the description vague but still somewhat related:
   `description: A utility skill for miscellaneous tasks.`
   Run eval, check if skill is still invoked.

2. **Moderate weakening** — Make the description unrelated:
   `description: Handles database migration operations.`
   Run eval, check if skill is still invoked.

3. **Severe weakening** — Remove the description entirely or make it empty:
   `description: ""`
   Run eval, check if skill is still invoked.

At each stage, capture traces for both Claude and Codex. At some point the AI should stop proactively invoking the skill — note where that threshold is.

## - [ ] Phase 4: Force Accidental Discovery

With the front matter still weakened (from Phase 3, using the version that did NOT trigger invocation), run a modified eval case where the prompt instructs the AI to grep the codebase for time-related functionality. Something like:

> "Search this codebase for any utilities or tools related to getting the current time. Read any files you find."

This should cause the AI to find and read the `what-time-is-it` skill file incidentally during its search — but NOT because the front matter triggered invocation.

1. Run this for both Claude and Codex
2. Capture the full AI logs/traces
3. Check what the `skillMustBeInvoked` assertion reports — does it say "invoked" or "not invoked"?

This is the critical test: if the grading says "invoked" here, it's the bug. The AI found the skill by accident, not through front matter recognition.

## - [ ] Phase 5: Compare Traces and Assess

Compare the log events across all runs:

- **Phase 2** (strong front matter, genuine invocation) — what does invocation look like?
- **Phase 3** (weakened front matter, no invocation) — what does non-invocation look like?
- **Phase 4** (weak front matter, accidental grep discovery) — does this look like invocation or non-invocation?

Key questions:
- Do the traces for accidental discovery (Phase 4) look different from genuine invocation (Phase 2)?
- Does the current grading already handle this correctly?
- Do Claude and Codex differ in their traces?

If the grading already works (accidental discovery is marked as "not invoked"), document why and close this plan — no fix needed.

If the grading incorrectly marks accidental discovery as "invoked", proceed to Phase 6.

## - [ ] Phase 6: Update Assertion Logic (If Needed)

Based on the trace analysis, update the skill invocation assertion to use the distinguishing signals. Ensure it checks for genuine invocation evidence rather than just the skill content appearing in the conversation.

If the traces are indistinguishable (no way to tell accidental from genuine), write a detailed analysis explaining:

- What the log events look like in each scenario (include actual log excerpts)
- Why there isn't enough information to distinguish them
- What would need to change (in the providers or in the app's tracing) to make this possible
- Whether web research on Claude/Codex skill invocation mechanics reveals any additional signals

## - [ ] Phase 7: Validation

Restore the `what-time-is-it` skill to its original strong front matter, then:

- Re-run the accidental discovery scenario (weak front matter + grep prompt) — invocation should be marked "not invoked"
- Re-run the genuine invocation scenario (strong front matter + clean prompt) — invocation should be marked "invoked"
- Test with both Claude and Codex providers
- If no fix was possible, the deliverable is the detailed analysis document with log event comparisons across all scenarios and an explanation of why the distinction can't be made with current information
