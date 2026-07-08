# Faster Window Animation Timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce launcher window open and close animation latency by changing smooth duration to 0.20 seconds and snappy duration to 0.10 seconds while preserving their existing timing functions and all cold-open behavior.

**Architecture:** Keep the existing shared `LauncherWindowPresentationAnimationPolicy` as the sole source of window presentation duration and timing functions for both open and close. Update only its two duration literals and the strict source-based expectations that protect the policy; leave the existing cold-open scheduler, transition IDs, visibility checks, completion guards, non-animated materialization, focus retries, indexing, mode routing, and surface lifecycle unchanged.

**Tech Stack:** Swift 5.9, AppKit `NSAnimationContext`, SwiftUI Liquid Glass, XCTest, Swift Package Manager, macOS 26.

---

## File Structure

- Modify `Tests/BuckyTests/LauncherModeRoutingTests.swift`: update the strict smooth/snappy duration expectations while preserving the timing-function and shared-policy assertions.
- Modify `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`: change only the two literals returned by `LauncherWindowPresentationAnimationPolicy.duration(for:)`.
- Do not modify the existing cold-open scheduler, its tests, or any other source, test, spec, or plan document.

## Scope Check

The approved spec covers one shared animation policy and its focused tests, so one implementation task is sufficient. Existing cold-open scheduling and tests remain unchanged; no new setting, UI, animation abstraction, persistence, network access, credential handling, or logging is added.

### Task 1: Quicken Shared Launcher Window Timing Policy

**Files:**
- Modify `Tests/BuckyTests/LauncherModeRoutingTests.swift` at `testWindowOpenCloseAnimationUsesConfiguredPresentationPolicy()`.
- Modify `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift` at `LauncherWindowPresentationAnimationPolicy.duration(for:)`.

- [ ] **Step 1: Modify the strict policy test expectations first**

In `Tests/BuckyTests/LauncherModeRoutingTests.swift`, replace only the old duration assertions with these exact snippets, preserving the surrounding assertions for the shared policy, timing function method, open/close duration use, and the negative legacy constant check:

```swift
XCTAssertTrue(source.contains("case .smooth:\n            return 0.20"))
XCTAssertTrue(source.contains("case .snappy:\n            return 0.10"))
XCTAssertTrue(source.contains("case .smooth:\n            return CAMediaTimingFunction(name: .easeInEaseOut)"))
XCTAssertTrue(source.contains("case .snappy:\n            return CAMediaTimingFunction(name: .easeOut)"))
```

The complete strict policy portion must continue to assert the shared policy and both animation consumers:

```swift
XCTAssertTrue(source.contains("private enum LauncherWindowPresentationAnimationPolicy"))
XCTAssertTrue(source.contains("static func duration(for timing: LauncherAnimationTiming) -> TimeInterval"))
XCTAssertTrue(source.contains("case .smooth:\n            return 0.20"))
XCTAssertTrue(source.contains("case .snappy:\n            return 0.10"))
XCTAssertTrue(source.contains("static func timingFunction(for timing: LauncherAnimationTiming) -> CAMediaTimingFunction"))
XCTAssertTrue(source.contains("case .smooth:\n            return CAMediaTimingFunction(name: .easeInEaseOut)"))
XCTAssertTrue(source.contains("case .snappy:\n            return CAMediaTimingFunction(name: .easeOut)"))
XCTAssertTrue(source.contains("context.duration = LauncherWindowPresentationAnimationPolicy.duration(for: model.animationTiming)"))
XCTAssertTrue(source.contains("context.timingFunction = LauncherWindowPresentationAnimationPolicy.timingFunction(for: model.animationTiming)"))
XCTAssertFalse(source.contains("static let duration: TimeInterval = 0.12"))
```

- [ ] **Step 2: Run the focused test and verify the intentional RED**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testWindowOpenCloseAnimationUsesConfiguredPresentationPolicy
```

Expected output: the focused test fails because the production source still contains `return 0.24` and `return 0.12`, while the test requires `return 0.20` and `return 0.10`. The existing timing-function assertions remain passing or unchanged.

- [ ] **Step 3: Modify only the production duration switch**

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`, replace only the duration switch body with this exact code. Do not change the timing-function switch or any scheduler, transition, visibility, completion, focus, indexing, mode, or lifecycle code:

```swift
static func duration(for timing: LauncherAnimationTiming) -> TimeInterval {
    switch timing {
    case .smooth:
        return 0.20
    case .snappy:
        return 0.10
    }
}
```

The timing-function policy must remain exactly:

```swift
static func timingFunction(for timing: LauncherAnimationTiming) -> CAMediaTimingFunction {
    switch timing {
    case .smooth:
        return CAMediaTimingFunction(name: .easeInEaseOut)
    case .snappy:
        return CAMediaTimingFunction(name: .easeOut)
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testWindowOpenCloseAnimationUsesConfiguredPresentationPolicy
```

Expected output: `Test Case ... passed` and `Test Suite ... passed`, with zero failures. The test must still verify the shared policy is used for both open and close and that smooth/snappy retain distinct `easeInEaseOut`/`easeOut` curves.

- [ ] **Step 5: Run the complete automated verification set**

Run each command from the repository root in order:

```bash
swift test --quiet
make perf
./package.sh
git diff --check
```

Expected output:

- `swift test --quiet`: exits `0`; all Swift tests pass.
- `make perf`: exits `0`; the existing launcher performance guard passes without changing its baseline.
- `./package.sh`: exits `0`; the packaged `build/Bucky.app` is produced successfully.
- `git diff --check`: exits `0` with no whitespace error output.

- [ ] **Step 6: Live verify the cold and subsequent presentation paths**

After packaging, cleanly quit any running Bucky instance, launch the newly packaged app, trigger the global hotkey once, and inspect the first cold open with the existing macOS observation tooling. Confirm the first open reaches WindowServer alpha `1` after the deferred fade, with no blank or stuck surface. Then close and reopen the launcher and confirm both directions complete and retain distinct settings: smooth uses `0.20` with `easeInEaseOut`, and snappy uses `0.10` with `easeOut`.

Run:

```bash
osascript -e 'tell application "Bucky" to quit'
./package.sh
open build/Bucky.app
```

Expected result: the app restarts cleanly; the first hotkey open reaches visible alpha `1`; a subsequent close completes; a subsequent reopen completes; no blank, prematurely removed, or stuck launcher surface appears; and changing the existing animation preference keeps the two duration/curve pairs distinct. Existing cold-open scheduler behavior and race guards remain observable and unchanged.

- [ ] **Step 7: Self-check the implementation diff and create the signed granular commit**

Run:

```bash
git diff -- Tests/BuckyTests/LauncherModeRoutingTests.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift
git diff --check
git status --short
git add Tests/BuckyTests/LauncherModeRoutingTests.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift
git commit -S -m "fix(launcher): quicken window animation timing"
git rev-parse --short HEAD
```

Expected result: the diff contains only the two test duration expectation changes and the two production duration literals; `git diff --check` is clean; no cold-open scheduler or test changes appear; staging includes only the two implementation files; the signed commit succeeds with message `fix(launcher): quicken window animation timing`; and `git rev-parse --short HEAD` prints the new commit SHA.

Do not create a separate design or documentation commit as part of implementing this plan.

## Plan Self-Review

- Spec coverage: the plan covers the 0.20/0.10 duration changes, preserves both timing functions and their distinction, preserves the shared open/close policy, preserves cold-open scheduling and tests, runs focused/full/performance/package/whitespace checks, and includes clean-restart live verification of first open, close, and reopen.
- Completeness scan: no unfinished or unspecified implementation step remains; every code change has exact Swift snippets and every command has an expected result.
- Type consistency: `LauncherAnimationTiming`, `LauncherWindowPresentationAnimationPolicy.duration(for:)`, `CAMediaTimingFunction`, and the existing source-based test contract match the current production and test signatures.
- Scope guard: this plan owns only the implementation test/source files during feature execution and does not authorize changes to other docs or the existing cold-open scheduler/tests.
