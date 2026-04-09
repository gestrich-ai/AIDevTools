# AIDevToolsDemo Playground

The AIDevToolsDemo repo at `/Users/bill/Developer/personal/AIDevToolsDemo` (sibling to the AIDevTools repo) is a dedicated playground for testing live AIDevTools changes.

## Purpose

Use AIDevToolsDemo whenever you need to:
- Reproduce a reported issue end-to-end
- Validate that a fix actually works with real tool behavior
- Stage test PRs for PRRadar, ClaudeChain, or other pipeline features
- Test eval cases against real repository state

## What's OK Here

This repo is **purely for testing**. Feel free to:
- Create, close, and delete branches and pull requests freely
- Push commits, force-push, rebase
- Leave messy state between runs — no need to clean up

## Structure

The repo has a `src/` directory with placeholder files (`a.txt`, `b.txt`, `c.txt`, `d.txt`) and subdirectories (`alpha`, `beta`, `gamma`, `delta`). These give providers something to read and edit during evals.

## Using with PRRadar

To test PRRadar pipeline behavior against AIDevToolsDemo PRs:
1. Check that AIDevToolsDemo is configured in `~/Library/Application Support/PRRadar/settings.json`
2. Use `swift run PRRadarMacCLI config list` from `PRRadarLibrary/` to see available config names
3. Run pipeline commands against open PRs in the repo (see `pr-radar-debug.md`)
