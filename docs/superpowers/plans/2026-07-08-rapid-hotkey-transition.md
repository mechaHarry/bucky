# Rapid Hotkey Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every rapid launcher hotkey intent replace the active AppKit alpha fade so the newest show or hide request wins promptly and deterministically.

**Architecture:** Add a small `@MainActor` `LauncherWindowVisibilityTransitionCoordinator` at the window-presentation boundary. It owns the existing generation (`visibilityTransitionID`), latest intent, and visibility phase/state, and depends on one narrow injectable alpha-animation driver. The native driver cancels an in-flight fade by assigning the current alpha through `window.animator()` inside an `NSAnimationContext` with duration `0`, then starts the replacement fade using the existing shared duration and timing-function policy. The controller remains responsible for materialization, model state, focus, the deferred cold-open scheduler, and `orderOut`; it delegates transition ownership and stale-completion acceptance to the coordinator.

**Tech Stack:** Swift 5.9, AppKit `NSWindow`/`NSAnimationContext`, SwiftUI, XCTest, Swift Package Manager, macOS 26.

---

## File Structure

Create:

- `Sources/Bucky/UI/SwiftUI/LauncherWindowAlphaAnimationDriver.swift`: the `@MainActor` injectable driver protocol and weak-window AppKit implementation.
- `Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift`: the real `@MainActor` coordinator owning generation, latest intent, phase, cancellation/replacement, and guarded completion.
- `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`: deterministic fake-driver tests exercising the real coordinator for rapid sequences, stale callbacks, failure, teardown, and ownership.

Modify:

- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift:50-320,953-1008`: construct the real coordinator, route show/hide paths through it, and preserve materialization, scheduler, focus, model, terminal actions, and policy.
- `Tests/BuckyTests/LauncherModeRoutingTests.swift`: source integration assertions for driver wiring, scheduler retention, shared policy, and no dropped hide.

No other file may be modified.

## Baseline And Constraints

- Approved spec: `docs/superpowers/specs/2026-07-08-rapid-hotkey-transition-design.md`.
- Existing deferred scheduler: `LauncherWindowOpenAnimationScheduler` at controller lines 8-46. Retain it and its tests unchanged; the coordinator must expose its current generation/state to the scheduler's existing guards.
- Existing policy: `LauncherWindowPresentationAnimationPolicy` at controller lines 1020-1038. Change only `private enum LauncherWindowPresentationAnimationPolicy` to internal `enum LauncherWindowPresentationAnimationPolicy` so the new coordinator file can compile against it. Retain smooth `0.20`, snappy `0.10`, `.easeInEaseOut`, and `.easeOut`.
- Do not debounce, suppress, drop, log, persist, retry, block, alter indexing, alter focus retry, alter hotkey settings, or alter mode/surface lifecycle. Do not introduce a test-only coordinator or a second model of production state.
- All driver and completion callbacks are `@MainActor`. Callback closures capture the controller weakly. The driver holds only a weak window reference.

### Task 1: Add The Injectable Native Alpha Driver

**Files:**
- Create: `Sources/Bucky/UI/SwiftUI/LauncherWindowAlphaAnimationDriver.swift`
- Create: `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`

- [ ] **Step 1: Write the failing contract test and fake driver**

Create `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`:

```swift
import AppKit
import XCTest
@testable import Bucky

@available(macOS 26.0, *)
@MainActor
final class FakeLauncherWindowAlphaAnimationDriver: LauncherWindowAlphaAnimationDriver {
    struct Operation {
        let targetAlpha: CGFloat
        let duration: TimeInterval
        let timingFunctionName: CAMediaTimingFunctionName
        let completion: @MainActor () -> Void
        var isCanceled = false
    }

    var alphaValue: CGFloat
    var operations: [Operation] = []
    var cancelCount = 0
    var failNextAnimation = false

    init(alphaValue: CGFloat = 0) {
        self.alphaValue = alphaValue
    }

    func cancelAndNormalize() {
        cancelCount += 1
        for index in operations.indices {
            operations[index].isCanceled = true
        }
    }

    @discardableResult
    func animate(
        to targetAlpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard !failNextAnimation else {
            failNextAnimation = false
            return false
        }
        operations.append(Operation(
            targetAlpha: targetAlpha,
            duration: duration,
            timingFunctionName: timingFunction.name,
            completion: completion
        ))
        return true
    }

    func completeOperation(at index: Int) {
        let operation = operations[index]
        if !operation.isCanceled {
            alphaValue = operation.targetAlpha
        }
        operation.completion()
    }
}

@available(macOS 26.0, *)
@MainActor
final class LauncherWindowVisibilityTransitionTests: XCTestCase {
    func testNativeDriverUsesZeroDurationAnimatorAssignmentToNormalizeAlpha() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherWindowAlphaAnimationDriver.swift")
        XCTAssertTrue(source.contains("NSAnimationContext.runAnimationGroup"))
        XCTAssertTrue(source.contains("context.duration = 0"))
        XCTAssertTrue(source.contains("window.animator().alphaValue = currentAlpha"))
        XCTAssertTrue(source.contains("window.animator().alphaValue = targetAlpha"))
    }

    private func source(named path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter LauncherWindowVisibilityTransitionTests/testNativeDriverUsesZeroDurationAnimatorAssignmentToNormalizeAlpha
```

Expected: compilation fails because `LauncherWindowAlphaAnimationDriver` is not defined.

- [ ] **Step 3: Implement the exact AppKit driver**

Create `Sources/Bucky/UI/SwiftUI/LauncherWindowAlphaAnimationDriver.swift`:

```swift
import AppKit

@available(macOS 26.0, *)
@MainActor
protocol LauncherWindowAlphaAnimationDriver: AnyObject {
    var alphaValue: CGFloat { get }
    func cancelAndNormalize()

    @discardableResult
    func animate(
        to targetAlpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor () -> Void
    ) -> Bool
}

@available(macOS 26.0, *)
@MainActor
final class LauncherWindowAlphaAnimationDriverImpl: LauncherWindowAlphaAnimationDriver {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }

    var alphaValue: CGFloat {
        window?.alphaValue ?? 0
    }

    func cancelAndNormalize() {
        guard let window else { return }
        let currentAlpha = window.alphaValue
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().alphaValue = currentAlpha
        }
    }

    @discardableResult
    func animate(
        to targetAlpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let window else { return false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            window.animator().alphaValue = targetAlpha
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                completion()
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Run the focused driver test and verify GREEN**

Run:

```bash
swift test --filter LauncherWindowVisibilityTransitionTests/testNativeDriverUsesZeroDurationAnimatorAssignmentToNormalizeAlpha
```

Expected: the test passes with zero failures and confirms the SDK-documented zero-duration animator assignment.

### Task 2: Implement And Test The Real Presentation Coordinator

**Files:**
- Create: `Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift`
- Modify: `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`

- [ ] **Step 1: Write the failing real-coordinator test**

Replace the planned `TestVisibilityCoordinator` harness with tests that instantiate the production `LauncherWindowVisibilityTransitionCoordinator` using `FakeLauncherWindowAlphaAnimationDriver`. The test must observe the coordinator's public/internal `visibilityTransitionID`, `latestIntent`, `visibilityState`, and the injected `didShow`/`didHide` actions. Do not duplicate coordinator logic in the test target.

Use this exact production API in the tests:

```swift
let coordinator = LauncherWindowVisibilityTransitionCoordinator(
    driver: driver,
    animationTiming: { .smooth },
    didShow: { showCount += 1 },
    didHide: { hideCount += 1 }
)
let transitionID = coordinator.request(.show)
XCTAssertEqual(coordinator.latestIntent, .show)
XCTAssertEqual(coordinator.visibilityTransitionID, transitionID)
```

The first test should fail because `LauncherWindowVisibilityTransitionCoordinator` does not exist.

- [ ] **Step 2: Implement the coordinator's exact state and transition API**

Create `Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift`:

Before adding this file, change the existing controller declaration from:

```swift
private enum LauncherWindowPresentationAnimationPolicy {
```

to:

```swift
enum LauncherWindowPresentationAnimationPolicy {
```

Make no other policy change. The coordinator file is a separate source file, so leaving the enum `private` would make the exact `LauncherWindowPresentationAnimationPolicy.duration(for:)` and `timingFunction(for:)` calls below fail to compile.

```swift
import AppKit

@available(macOS 26.0, *)
enum LauncherWindowVisibilityIntent: Equatable {
    case show
    case hide
}

@available(macOS 26.0, *)
enum WindowVisibilityState: Equatable {
    case hidden
    case showing
    case shown
    case hiding
}

@available(macOS 26.0, *)
@MainActor
final class LauncherWindowVisibilityTransitionCoordinator {
    typealias CompletionAction = @MainActor () -> Void

    private let driver: LauncherWindowAlphaAnimationDriver
    private let animationTiming: @MainActor () -> LauncherAnimationTiming
    private let didShow: CompletionAction
    private let didHide: CompletionAction

    private(set) var visibilityTransitionID = 0
    private(set) var latestIntent: LauncherWindowVisibilityIntent?
    private(set) var visibilityState: WindowVisibilityState = .hidden

    init(
        driver: LauncherWindowAlphaAnimationDriver,
        animationTiming: @escaping @MainActor () -> LauncherAnimationTiming,
        didShow: @escaping CompletionAction,
        didHide: @escaping CompletionAction
    ) {
        self.driver = driver
        self.animationTiming = animationTiming
        self.didShow = didShow
        self.didHide = didHide
    }

    @discardableResult
    func request(_ intent: LauncherWindowVisibilityIntent) -> Int {
        visibilityTransitionID += 1
        latestIntent = intent
        visibilityState = intent == .show ? .showing : .hiding
        driver.cancelAndNormalize()
        return visibilityTransitionID
    }

    @discardableResult
    func startAnimation(completion: @escaping @MainActor () -> Void) -> Bool {
        guard let intent = latestIntent else { return false }
        let targetAlpha: CGFloat = intent == .show ? 1 : 0
        let timing = animationTiming()
        return driver.animate(
            to: targetAlpha,
            duration: LauncherWindowPresentationAnimationPolicy.duration(for: timing),
            timingFunction: LauncherWindowPresentationAnimationPolicy.timingFunction(for: timing),
            completion: completion
        )
    }

    func complete(transitionID: Int) {
        guard visibilityTransitionID == transitionID,
              let intent = latestIntent,
              visibilityState == (intent == .show ? .showing : .hiding) else {
            return
        }

        if intent == .show {
            visibilityState = .shown
            didShow()
        } else {
            visibilityState = .hidden
            didHide()
        }
    }
}
```

The coordinator owns generation, latest intent, phase/state, cancellation, policy selection, and stale-completion acceptance. It does not own indexing, model materialization, focus retry, or `orderOut`; those remain completion actions supplied by the controller.

- [ ] **Step 3: Run the real-coordinator test and verify GREEN**

Run:

```bash
swift test --filter LauncherWindowVisibilityTransitionTests
```

Expected: the coordinator construction test passes and the suite still fails only for tests not yet migrated from the duplicate harness.

### Task 3: Wire The Existing Controller Through The Real Coordinator

**Files:**
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift:50-320,953-1008`
- Modify: `Tests/BuckyTests/LauncherModeRoutingTests.swift`

- [ ] **Step 1: Write failing source integration tests**

Append to `Tests/BuckyTests/LauncherModeRoutingTests.swift`:

```swift
func testRapidVisibilityUsesDriverAndKeepsColdOpenScheduler() throws {
    let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
    XCTAssertTrue(source.contains("private var visibilityTransitionCoordinator: LauncherWindowVisibilityTransitionCoordinator!"))
    XCTAssertTrue(source.contains("LauncherWindowVisibilityTransitionCoordinator("))
    XCTAssertTrue(source.contains("LauncherWindowAlphaAnimationDriverImpl(window: window)"))
    XCTAssertTrue(source.contains("visibilityTransitionCoordinator.request(.show)"))
    XCTAssertTrue(source.contains("visibilityTransitionCoordinator.request(.hide)"))
    XCTAssertTrue(source.contains("visibilityTransitionCoordinator.startAnimation(completion:"))
    XCTAssertTrue(source.contains("LauncherWindowOpenAnimationScheduler"))
    XCTAssertTrue(source.contains("animateWindowOpen(transitionID: transitionID)"))
    XCTAssertTrue(source.contains("enum LauncherWindowPresentationAnimationPolicy"))
    XCTAssertFalse(source.contains("private enum LauncherWindowPresentationAnimationPolicy"))
    XCTAssertTrue(source.contains("LauncherWindowPresentationAnimationPolicy.duration(for: model.animationTiming)"))
    XCTAssertTrue(source.contains("LauncherWindowPresentationAnimationPolicy.timingFunction(for: model.animationTiming)"))
    let coordinator = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift")
    XCTAssertTrue(coordinator.contains("LauncherWindowPresentationAnimationPolicy.duration(for: timing)"))
}

func testHideDoesNotDropAnIntentWhileAlreadyHiding() throws {
    let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
    XCTAssertFalse(source.contains("guard visibilityState != .hidden,\n              visibilityState != .hiding else"))
}

func testVisibilityStateAndTransitionIDRemainCompletionGuards() throws {
    let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
    let coordinator = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift")
    XCTAssertFalse(source.contains("private var visibilityState: WindowVisibilityState = .hidden"))
    XCTAssertFalse(source.contains("private var visibilityTransitionID = 0"))
    XCTAssertFalse(source.contains("private func beginVisibilityTransition"))
    XCTAssertFalse(source.contains("private func finishShow(transitionID:"))
    XCTAssertTrue(source.contains("private func completeHidePresentation()"))
    XCTAssertTrue(coordinator.contains("private(set) var visibilityTransitionID = 0"))
    XCTAssertTrue(coordinator.contains("private(set) var latestIntent: LauncherWindowVisibilityIntent?"))
    XCTAssertTrue(coordinator.contains("private(set) var visibilityState: WindowVisibilityState = .hidden"))
    XCTAssertTrue(coordinator.contains("guard visibilityTransitionID == transitionID"))
}
```

- [ ] **Step 2: Run the source tests and verify RED**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testRapidVisibilityUsesDriverAndKeepsColdOpenScheduler
swift test --filter LauncherModeRoutingTests/testHideDoesNotDropAnIntentWhileAlreadyHiding
```

Expected: the driver-wiring assertion fails and the no-dropped-hide assertion fails against the current controller.

- [ ] **Step 3: Construct the real coordinator and remove duplicate controller state**

Add beside `window`:

```swift
private var visibilityTransitionCoordinator: LauncherWindowVisibilityTransitionCoordinator!
```

Extend the existing initializer after `hotKeyChangeHandler`:

```swift
alphaAnimationDriverFactory: ((NSWindow) -> LauncherWindowAlphaAnimationDriver)? = nil
```

After `super.init()`, construct the coordinator with the native or injected driver and weak controller callbacks:

```swift
let alphaAnimationDriver = alphaAnimationDriverFactory?(window)
    ?? LauncherWindowAlphaAnimationDriverImpl(window: window)
visibilityTransitionCoordinator = LauncherWindowVisibilityTransitionCoordinator(
    driver: alphaAnimationDriver,
    animationTiming: { [weak self] in self?.model.animationTiming ?? .smooth },
    didShow: {},
    didHide: { [weak self] in self?.completeHidePresentation() }
)
```

Remove the controller's duplicate state properties and the obsolete `beginVisibilityTransition(_:)` and `finishShow(transitionID:)` methods. The coordinator is now the sole owner of generation, latest intent, and phase/state:

```swift
private(set) var visibilityTransitionID = 0
private(set) var latestIntent: LauncherWindowVisibilityIntent?
private(set) var visibilityState: WindowVisibilityState = .hidden
```

The three properties above belong only in `LauncherWindowVisibilityTransitionCoordinator.swift`, not in the controller. Update `toggle()`, `showSettings()`, `showHelp()`, and every existing state/ID read to use `visibilityTransitionCoordinator.visibilityState` and `visibilityTransitionCoordinator.visibilityTransitionID`. In `showSettings()` and `showHelp()`, replace `beginVisibilityTransition(.showing)`/`finishShow(transitionID:)` with `let transitionID = visibilityTransitionCoordinator.request(.show)` and `visibilityTransitionCoordinator.complete(transitionID: transitionID)` after their existing synchronous materialization and focus work.

- [ ] **Step 4: Route normal and interrupted show/hide paths through the coordinator**

In `show(mode:)`, capture the pre-request phase, then call `request(.show)` immediately after stopping the settings hotkey and before deciding materialization. Preserve positioning, focus, transaction, and the existing deferred cold-open scheduler. The `shouldMaterialize` branch remains the cold-open path. The non-materializing path must distinguish a normal already-shown request from an interrupted hide:

```swift
let wasHiding = visibilityTransitionCoordinator.visibilityState == .hiding
let transitionID = visibilityTransitionCoordinator.request(.show)
if shouldMaterialize {
    // Existing non-animated materialization, then schedule the deferred fade.
    animateWindowOpen(transitionID: transitionID)
} else if wasHiding {
    // Do not set alpha to 1 or call finishShow synchronously. request(.show)
    // already canceled/normalized the hide; replace it with a real fade.
    animateWindowOpen(transitionID: transitionID)
} else {
    visibilityTransitionCoordinator.complete(transitionID: transitionID)
}
```

The `wasHiding` value must be captured before `request(.show)` changes the phase, or equivalent pre-request phase data must be passed into this branch. For an already `.shown` window, preserve the synchronous completion path; for an interrupted `.hiding` window, never assign `window.alphaValue = 1` directly and never call `finishShow()` before the replacement animation completes.

Inside `animateWindowOpen(transitionID:)`, retain the scheduler and its state guards. Its `startAnimation` closure must call the coordinator:

```swift
startAnimation: { [weak self] completion in
    guard let self else { return }
    let started = visibilityTransitionCoordinator.startAnimation(completion: completion)
    if !started {
        window.alphaValue = 1
        visibilityTransitionCoordinator.complete(transitionID: transitionID)
    }
},
```

The scheduler's existing completion guard must call `visibilityTransitionCoordinator.complete(transitionID: transitionID)` only for the winning transition. The coordinator's own generation/intent/state guard remains the final acceptance check.

In `hide()`, replace the current two-condition guard with:

```swift
guard visibilityTransitionCoordinator.visibilityState != .hidden else {
    return
}
```

After the existing hide cleanup, call `let transitionID = visibilityTransitionCoordinator.request(.hide)`. This request always replaces an in-flight show or hide. Replace the direct `NSAnimationContext` fade with:

```swift
let started = visibilityTransitionCoordinator.startAnimation { [weak self] in
    self?.visibilityTransitionCoordinator.complete(transitionID: transitionID)
}

if !started {
    window.alphaValue = 0
    model.isPresented = false
    visibilityTransitionCoordinator.complete(transitionID: transitionID)
}
```

The coordinator sets `.shown` before invoking `didShow`; production `didShow: {}` is intentional because the existing `activateAndFocusWindow()` call remains before animation in `show(mode:)` and must not be claimed as a completion action. After the coordinator accepts a winning hide, production `didHide` calls the guard-free controller method `completeHidePresentation()`, which sets `model.isPresented = false`, calls `window.orderOut(nil)` exactly once, resigns key, and performs the existing hide cleanup. No controller terminal method repeats the generation/state guard. Every show/hide intent calls coordinator cancel/replace, including show while hiding and hide while showing.

Replace the controller's guarded `finishHide(transitionID:)` with this guard-free terminal cleanup method; only the coordinator's accepted `didHide` callback may call it. The coordinator's `complete(transitionID:)` owns the final `.hidden` assignment before invoking this callback:

```swift
private func completeHidePresentation() {
    window.makeFirstResponder(nil)
    window.orderOut(nil)
    window.resignKey()
    model.hideSettings()
}
```

- [ ] **Step 5: Run the source tests and verify GREEN**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testRapidVisibilityUsesDriverAndKeepsColdOpenScheduler
swift test --filter LauncherModeRoutingTests/testHideDoesNotDropAnIntentWhileAlreadyHiding
swift test --filter LauncherModeRoutingTests/testVisibilityStateAndTransitionIDRemainCompletionGuards
```

Expected: all three tests pass with zero failures; the scheduler and policy remain present.

### Task 4: Test Latest-Intent Ordering Through Production Code

**Files:**
- Modify: `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`

- [ ] **Step 1: Replace the duplicate harness with production-coordinator tests**

Delete the planned `TestVisibilityCoordinator` type. Each test must instantiate the real `LauncherWindowVisibilityTransitionCoordinator` with `FakeLauncherWindowAlphaAnimationDriver`, call its `request` and `startAnimation` APIs, and deliver retained fake completions out of order. No production transition logic may be reimplemented in the test target.

- [ ] **Step 2: Add rapid latest-intent and stale-completion tests**

Use this exact test shape:

```swift
func testShowHideShowHideEndsHiddenWithOneWinningOrderOut() {
    let driver = FakeLauncherWindowAlphaAnimationDriver()
    var showCount = 0
    var hideCount = 0
    let coordinator = LauncherWindowVisibilityTransitionCoordinator(
        driver: driver,
        animationTiming: { .smooth },
        didShow: { showCount += 1 },
        didHide: { hideCount += 1 }
    )

    for intent in [LauncherWindowVisibilityIntent.show, .hide, .show, .hide] {
        let transitionID = coordinator.request(intent)
        _ = coordinator.startAnimation {
            coordinator.complete(transitionID: transitionID)
        }
    }

    driver.completeOperation(at: 0)
    driver.completeOperation(at: 2)
    driver.completeOperation(at: 1)
    driver.completeOperation(at: 3)

    XCTAssertEqual(coordinator.visibilityState, .hidden)
    XCTAssertEqual(coordinator.latestIntent, .hide)
    XCTAssertEqual(coordinator.visibilityTransitionID, 4)
    XCTAssertEqual(driver.alphaValue, 0)
    XCTAssertEqual(showCount, 0)
    XCTAssertEqual(hideCount, 1)
    XCTAssertEqual(driver.cancelCount, 4)
}

func testHideShowHideShowEndsShownWithOneWinningShow() {
    let driver = FakeLauncherWindowAlphaAnimationDriver(alphaValue: 1)
    var showCount = 0
    var hideCount = 0
    let coordinator = LauncherWindowVisibilityTransitionCoordinator(
        driver: driver,
        animationTiming: { .snappy },
        didShow: { showCount += 1 },
        didHide: { hideCount += 1 }
    )

    for intent in [LauncherWindowVisibilityIntent.hide, .show, .hide, .show] {
        let transitionID = coordinator.request(intent)
        _ = coordinator.startAnimation {
            coordinator.complete(transitionID: transitionID)
        }
    }

    driver.completeOperation(at: 3)
    driver.completeOperation(at: 1)
    driver.completeOperation(at: 0)
    driver.completeOperation(at: 2)

    XCTAssertEqual(coordinator.visibilityState, .shown)
    XCTAssertEqual(coordinator.latestIntent, .show)
    XCTAssertEqual(driver.alphaValue, 1)
    XCTAssertEqual(showCount, 1)
    XCTAssertEqual(hideCount, 0)
    XCTAssertEqual(driver.operations[3].duration, 0.10)
}

func testStaleOutOfOrderAndDuplicateCompletionsCannotChangeWinningResult() {
    let driver = FakeLauncherWindowAlphaAnimationDriver()
    var showCount = 0
    var hideCount = 0
    let coordinator = LauncherWindowVisibilityTransitionCoordinator(
        driver: driver,
        animationTiming: { .smooth },
        didShow: { showCount += 1 },
        didHide: { hideCount += 1 }
    )

    let firstID = coordinator.request(.show)
    _ = coordinator.startAnimation {
        coordinator.complete(transitionID: firstID)
    }
    let winningID = coordinator.request(.hide)
    _ = coordinator.startAnimation {
        coordinator.complete(transitionID: winningID)
    }

    driver.completeOperation(at: 0)
    driver.completeOperation(at: 0)
    XCTAssertEqual(coordinator.visibilityState, .hiding)
    XCTAssertEqual(showCount, 0)
    XCTAssertEqual(hideCount, 0)

    driver.completeOperation(at: 1)
    driver.completeOperation(at: 1)
    XCTAssertEqual(coordinator.visibilityState, .hidden)
    XCTAssertEqual(showCount, 0)
    XCTAssertEqual(hideCount, 1)
}
```

- [ ] **Step 3: Add synchronous failure, teardown, and weak-ownership tests**

Use the real coordinator and verify the controller-facing terminal callback remains guarded:

```swift
func testSynchronousDriverFailureCompletesTheWinningShow() {
    let driver = FakeLauncherWindowAlphaAnimationDriver()
    driver.failNextAnimation = true
    var showCount = 0
    let coordinator = LauncherWindowVisibilityTransitionCoordinator(
        driver: driver,
        animationTiming: { .smooth },
        didShow: { showCount += 1 },
        didHide: {}
    )

    let transitionID = coordinator.request(.show)
    XCTAssertFalse(coordinator.startAnimation {
        coordinator.complete(transitionID: transitionID)
    })
    coordinator.complete(transitionID: transitionID)

    XCTAssertEqual(coordinator.visibilityState, .shown)
    XCTAssertEqual(showCount, 1)
    XCTAssertEqual(driver.operations.count, 0)
}

func testStaleGenerationCannotCompleteAfterAReplacement() {
    let driver = FakeLauncherWindowAlphaAnimationDriver()
    var showCount = 0
    var hideCount = 0
    let coordinator = LauncherWindowVisibilityTransitionCoordinator(
        driver: driver,
        animationTiming: { .smooth },
        didShow: { showCount += 1 },
        didHide: { hideCount += 1 }
    )

    let staleID = coordinator.request(.show)
    let winningID = coordinator.request(.hide)
    coordinator.complete(transitionID: staleID)

    XCTAssertEqual(coordinator.visibilityState, .hiding)
    XCTAssertEqual(showCount, 0)
    XCTAssertEqual(hideCount, 0)

    coordinator.complete(transitionID: winningID)
    XCTAssertEqual(coordinator.visibilityState, .hidden)
    XCTAssertEqual(hideCount, 1)
}

func testCompletionDoesNotRetainProductionCoordinatorAfterTeardown() {
    let driver = FakeLauncherWindowAlphaAnimationDriver()
    weak var weakCoordinator: LauncherWindowVisibilityTransitionCoordinator?

    do {
        let coordinator = LauncherWindowVisibilityTransitionCoordinator(
            driver: driver,
            animationTiming: { .smooth },
            didShow: {},
            didHide: {}
        )
        weakCoordinator = coordinator
        let transitionID = coordinator.request(.show)
        _ = coordinator.startAnimation { [weak coordinator] in
            coordinator?.complete(transitionID: transitionID)
        }
    }

    XCTAssertNil(weakCoordinator)
    driver.completeOperation(at: 0)
}

func testNativeDriverDoesNotRetainWindow() {
    weak var weakWindow: NSWindow?

    do {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        weakWindow = window
        _ = LauncherWindowAlphaAnimationDriverImpl(window: window)
    }

    XCTAssertNil(weakWindow)
}
```

- [ ] **Step 4: Run the focused production-coordinator tests**

Run:

```bash
swift test --filter LauncherWindowVisibilityTransitionTests
```

Expected: all tests exercise the real coordinator; rapid inverse sequences, stale/out-of-order/duplicate completions, synchronous failure, teardown, and weak ownership pass with zero failures.

### Task 5: Full Verification, Live Check, And Self-Review

**Files:** No additional files.

- [ ] **Step 1: Run focused regression suites**

Run:

```bash
swift test --filter LauncherModeRoutingTests
swift test --filter LauncherWindowOpenAnimationSchedulerTests
swift test --filter LauncherWindowVisibilityTransitionTests
```

Expected: all focused suites pass; cold-open deferral, stale scheduler guards, and weak scheduler callbacks remain covered.

- [ ] **Step 2: Run the full test suite and performance guard**

Run:

```bash
swift test --quiet
make perf
```

Expected: both commands exit `0`; all tests pass and the existing launcher performance baseline is unchanged.

- [ ] **Step 3: Package and validate the app**

Run:

```bash
./package.sh
git diff --check
```

Expected: `build/Bucky.app` and its zip/checksum are produced successfully; `git diff --check` prints no whitespace errors.

- [ ] **Step 4: Live verify both rapid hotkey sequences**

Run:

```bash
osascript -e 'tell application "Bucky" to quit'
./package.sh
open build/Bucky.app
```

Use the existing global hotkey for `show-hide-show-hide`, then `hide-show-hide-show`, issuing each sequence faster than the `0.20`-second fade. Expected: the final intent wins; hidden ends alpha `0` and ordered out once; shown ends visible at alpha `1` with normal focus; no delayed opening, blank surface, stuck alpha, premature ordering out, dropped input, or indexing interruption occurs.

- [ ] **Step 5: Self-review the implementation diff**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Expected: only the four named implementation/test paths are changed. Confirm no scheduler, policy, package, baseline, unrelated source, or unrelated test file changed. Search the implementation diff for `TBD`, `TODO`, `FIXME`, and `placeholder`; none may remain.
