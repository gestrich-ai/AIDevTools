---
name: ai-dev-tools-ui-tests
description: >
  Running, writing, and extracting screenshots from UI tests and interactive tests for
  the AIDevTools Mac app. Use this skill when: running XCUITests, capturing app screenshots,
  adding new screenshot tests, extracting images from .xcresult bundles, or using the
  interactive test runner (XCUITestControl) to programmatically drive the app UI.
---

# AIDevTools UI Tests

Two test targets run against the AIDevTools Mac app:

- **AIDevToolsUITests** — XCUITest suite that launches the app and captures screenshots
- **AIDevToolsInteractiveTests** — Interactive control loop for programmatic UI driving

Both targets live in the Xcode project at the repo root (`AIDevTools.xcodeproj`), not in the Swift package.

## Prerequisites

Enable automation mode once per machine (persists across reboots):

```bash
sudo /usr/sbin/DevToolsSecurity -enable
sudo automationmodetool enable-automationmode-without-authentication
```

Without these, tests hang at "Running tests..." and fail with:
> "Timed out while enabling automation mode."

Verify current state:
```bash
/usr/sbin/DevToolsSecurity -status
automationmodetool
```

## Running Screenshot Tests

```bash
# Clean any previous result bundle
rm -rf /tmp/AIDevToolsResults

# Run all screenshot tests
xcodebuild test \
  -project AIDevTools.xcodeproj \
  -scheme AIDevTools \
  -destination 'platform=macOS' \
  -only-testing:AIDevToolsUITests \
  -resultBundlePath /tmp/AIDevToolsResults

# Run a single test by name
xcodebuild test \
  -project AIDevTools.xcodeproj \
  -scheme AIDevTools \
  -destination 'platform=macOS' \
  -only-testing:AIDevToolsUITests/AIDevToolsUITests/testScreenshot07_PRRadarTab \
  -resultBundlePath /tmp/AIDevToolsResults
```

Run these commands from the repo root (`/Users/bill/Developer/personal/AIDevTools`).

### Existing Screenshot Tests

| Test method | Screenshot name |
|---|---|
| `testScreenshot01_EmptyState` | `01-empty-state` |
| `testScreenshot02_RepositorySidebar` | `02-repository-sidebar` |
| `testScreenshot03_ChainsTab` | `03-chains-tab` |
| `testScreenshot04_ArchitectureTab` | `04-architecture-tab` |
| `testScreenshot05_EvalsTab` | `05-evals-tab` |
| `testScreenshot06_PlansTab` | `06-plans-tab` |
| `testScreenshot07_PRRadarTab` | `07-pr-radar-tab` |
| `testScreenshot08_SkillsTab` | `08-skills-tab` |
| `testScreenshot09_Settings` | `09-settings` |
| `testScreenshot10_ChatPanelClosed` | `chat-panel-closed` |
| `testScreenshot11_ChatPanelOpen` | `chat-panel-open` |

Test ID format for `xcresulttool`: `AIDevToolsUITests/testMethodName()`

## Extracting Screenshots from `.xcresult`

Screenshots are saved as XCTest attachments embedded in the result bundle. Extract them with `xcresulttool`:

```bash
# 1. Find the attachment payload ID for a test
xcrun xcresulttool get test-results activities \
  --path /tmp/AIDevToolsResults \
  --test-id "AIDevToolsUITests/testScreenshot07_PRRadarTab()" \
  2>&1 | python3 -c "
import sys, json
data = json.load(sys.stdin)
def find(obj):
    if isinstance(obj, dict):
        if 'payloadId' in obj:
            print(obj['payloadId'])
        for v in obj.values(): find(v)
    elif isinstance(obj, list):
        for v in obj: find(v)
find(data)"

# 2. Export the screenshot using the payload ID
xcrun xcresulttool export object --legacy \
  --path /tmp/AIDevToolsResults \
  --output-path /tmp/screenshot.png \
  --id "<payloadId>" \
  --type file
```

Resize if needed before attaching to a PR:
```bash
sips -Z 800 /tmp/screenshot.png --out screenshots/my-feature.png
```

## Writing New Screenshot Tests

Add new tests to `AIDevToolsUITests/AIDevToolsUITests.swift`. Each test:
1. Calls `launchApp()` to get a running `XCUIApplication`
2. Navigates to the desired state using the existing helpers
3. Calls `saveScreenshot(_:name:)` to capture and embed the screenshot

```swift
@MainActor
func testScreenshot12_MyNewView() throws {
    let app = launchApp()
    selectFirstRepository(app)
    tapTab(app, label: "My Tab")
    saveScreenshot(app, name: "12-my-new-view")
}
```

Available helpers in the test class:
- `launchApp()` — launches the app and waits for the main window
- `saveScreenshot(_:name:)` — captures the app window and adds it as a kept attachment
- `selectFirstRepository(_:)` — taps the first item in the sidebar outline
- `findTab(_:label:)` — finds a tab button by label using multiple lookup strategies
- `tapTab(_:label:)` — finds and taps a tab, then waits 2s for UI to settle

Number test methods sequentially (`testScreenshot12_`, `testScreenshot13_`, ...) — xcodebuild runs them in alphabetical order.

### Element lookup

Prefer reliability order: `app.buttons["Label"]` → `app.radioButtons["Label"]` → predicate-based `descendants(matching:)`. Use `waitForExistence(timeout:)` for elements that may take time to appear. Use `sleep()` after navigation to let the UI settle.

## Interactive Tests (XCUITestControl)

The `AIDevToolsInteractiveTests` target runs `InteractiveControlLoop`, which keeps the app alive and accepts programmatic commands. This is useful for exploratory UI work where you want to drive the app step-by-step rather than writing a fixed test sequence.

```bash
# Run the interactive control loop (keeps running until you send "done")
xcodebuild test \
  -project AIDevTools.xcodeproj \
  -scheme AIDevTools \
  -destination 'platform=macOS' \
  -only-testing:AIDevToolsInteractiveTests/InteractiveControlTests/testInteractiveControl \
  -resultBundlePath /tmp/AIDevToolsResults
```

The loop polls for commands written to a JSON file. Use the `xcuitest-control` CLI (from the `xcode-sim-automation` repo) to send commands from a separate terminal while the test is running.

See `ai-dev-tools-swift-snapshot-testing` (Method 4) for the full interactive control architecture, CLI commands, and background session setup.

## When to Run

- **After any UI change** — run the affected test(s) to verify and capture updated screenshots
- **Before opening a PR** — run all UI tests to check for visual regressions
- **Attaching screenshots to PRs** — save to `screenshots/` at the repo root and reference with a relative path in the PR body
