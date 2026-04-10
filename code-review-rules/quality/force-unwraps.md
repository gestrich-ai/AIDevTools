---
description: Force unwraps crash in production when the assumption is wrong
category: safety
applies_to:
  file_patterns: ["*.swift"]
  exclude_patterns: ["**/Tests/**", "**/*Tests.swift", "**/*Test.swift"]
grep:
  any: ["!", "try!", "as!"]
new_code_lines_only: true
---

# Force Unwraps

A force unwrap (`!`, `try!`, `as!`) is a bet that a value is always present. When that bet is wrong, the app crashes in production.

## Requirements

Avoid force unwraps in non-test production code. Use safe alternatives that make failure visible.

## Examples

```swift
// ❌ Bad: crashes if url is malformed or data is nil
let url = URL(string: rawURL)!
let data = try! JSONEncoder().encode(model)
let view = someObject as! UIView

// ✅ Good: handle failure explicitly
guard let url = URL(string: rawURL) else {
    throw ConfigError.invalidURL(rawURL)
}
let data = try JSONEncoder().encode(model)
guard let view = someObject as? UIView else {
    throw RenderError.unexpectedViewType
}
```

```swift
// ❌ Bad: try! in initialization discards the error
let config = try! Config.load()

// ✅ Good: propagate the error so the caller knows what went wrong
let config = try Config.load()
```

## What to Check

1. `!` after an optional — use `guard let` with a thrown error or logged warning
2. `try!` — use `try` and propagate or handle the error
3. `as!` — use `as?` with explicit nil handling, or fix the type hierarchy

## GitHub Comment

```
Force unwrap here will crash if the value is nil or the cast fails. Consider using `guard let` / `as?` with explicit error handling so failures surface instead of crashing.
```
