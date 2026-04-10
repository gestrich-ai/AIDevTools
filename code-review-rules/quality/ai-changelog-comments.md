---
description: Comments describing what changed rather than why the code exists
category: clarity
applies_to:
  file_patterns: ["*.swift"]
new_code_lines_only: true
---

# AI-Changelog-Style Comments

Comments that describe what was changed — rather than what the code does or why — become noise immediately after the PR merges. They belong in the commit message, not the source file.

## Requirements

Comments in source code should explain **why** the code does what it does, not what changed from a prior version. If a reviewer or future reader needs to understand the history, they can read `git log`.

## Examples

```swift
// ❌ Bad: changelog-style, meaningless after merge
// Changed X to Y for new behavior
// Added Z to support the new flow
// Previously this was a class, now it's a struct
// Updated to use the new API
// Removed old implementation and replaced with this

// ✅ Good: explains the why behind non-obvious logic
// URLSession requires the delegate to be set before the first request;
// setting it after causes the session to retain a stale delegate reference.

// ✅ Good: no comment needed — code is self-explanatory
let branch = "claude-chain-\(project)-\(hash)"
```

```swift
// ❌ Bad: describes what the diff did
func fetchUser(id: String) async throws -> User {
    // Now uses async/await instead of callback
    return try await apiClient.getUser(id: id)
}

// ✅ Good: no comment needed, or explain the non-obvious part
func fetchUser(id: String) async throws -> User {
    return try await apiClient.getUser(id: id)
}
```

## What to Check

1. Comments starting with "Changed", "Updated", "Added", "Removed", "Previously", "Now"
2. Comments comparing old vs. new behavior
3. Comments that would make no sense to a reader six months from now

## GitHub Comment

```
This comment describes what changed rather than what the code does. It will be confusing noise after the PR merges — consider removing it, or replacing it with a comment explaining *why* this approach was chosen if that's non-obvious.
```
