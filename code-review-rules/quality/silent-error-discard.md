---
description: try? silently discards errors, making failures invisible
category: safety
applies_to:
  file_patterns: ["*.swift"]
  exclude_patterns: ["**/Tests/**", "**/*Tests.swift", "**/*Test.swift"]
violation_regex: "try\\?"
violation_message: "try? silently discards the error. Use try with explicit error handling so failures are visible."
grep:
  any: ["try?"]
new_code_lines_only: true
---

# Silent Error Discard (`try?`)

`try?` converts any thrown error into `nil`, silently discarding the failure. This makes bugs invisible — the caller never knows the operation failed.

## Requirements

Avoid `try?` except when failure is genuinely expected and handled. If you use `try?`, pair it with a fallback that communicates intent.

## Examples

```swift
// ❌ Bad: error silently discarded, nil treated as success
let result = try? riskyOperation()

// ✅ Good: error handled explicitly
do {
    let result = try riskyOperation()
    process(result)
} catch {
    logger.error("riskyOperation failed: \(error)")
}

// ✅ Also acceptable when nil is a meaningful result and the caller handles it
if let result = try? optionalLookup(id: id) {
    use(result)
}
// But: document why failure → nil is intentional here
```

```swift
// ❌ Bad: silent save failure, user never knows data wasn't persisted
try? store.save(settings)

// ✅ Good: propagate so callers can show an error
try store.save(settings)
```

## What to Check

1. `try?` on I/O operations (file reads, network, database) — these failures matter
2. `try?` followed by `?? defaultValue` — both the error and the fallback are hidden
3. `try?` where `nil` return is never checked — the result is just dropped

## GitHub Comment

```
`try?` silently discards the error here. If this fails, nothing will surface the problem. Consider using `do/catch` with explicit logging, or propagating the error with `try`.
```
