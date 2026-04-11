# Experimental Features

Experimental features are under active development and may be incomplete, unstable, or change without notice. They are hidden by default and can be enabled individually in **Settings → Experimental**.

## Architecture Planner

Walk a feature description through a 10-step AI pipeline that extracts requirements, maps them to your codebase's architecture, scores guideline conformance, simulates execution decisions, and produces a report with followup items.

**Enable:** Settings → Experimental → Architecture Planner toggle → shows the Architecture tab in the workspace.

### How it works

1. Describe the feature you want to build in plain language.
2. The pipeline runs up to 10 steps, each handled by an AI call:
   - Extracts requirements from the description
   - Maps requirements to your codebase's existing architecture
   - Scores conformance against bundled Swift architecture guidelines
   - Simulates execution decisions and identifies risks
   - Produces a structured report with followup items
3. Guidelines are seeded from architecture docs in your repository and can be customized per repository.

### Status

Under development. The pipeline runs end-to-end but the report format and step definitions are still evolving.
