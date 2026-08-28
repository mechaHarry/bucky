import AppKit
import XCTest
@testable import Bucky

@available(macOS 26.0, *)
@MainActor
final class LauncherWindowVisibilityTransitionTests: XCTestCase {
    private final class FakeAlphaAnimationDriver: LauncherWindowAlphaAnimationDriver {
        struct Animation {
            let targetAlpha: CGFloat
            let duration: TimeInterval
            let timingFunction: CAMediaTimingFunction
            let completion: @MainActor () -> Void
            var isCancelled = false
        }

        var alphaValue: CGFloat
        var cancelCount = 0
        var shouldStartAnimation = true
        var animations: [Animation] = []

        init(alphaValue: CGFloat = 0) {
            self.alphaValue = alphaValue
        }

        func cancelAndNormalize() {
            cancelCount += 1
            for index in animations.indices {
                animations[index].isCancelled = true
            }
        }

        @discardableResult
        func animate(
            to alpha: CGFloat,
            duration: TimeInterval,
            timingFunction: CAMediaTimingFunction,
            completion: @escaping @MainActor () -> Void
        ) -> Bool {
            guard shouldStartAnimation else { return false }
            animations.append(Animation(
                targetAlpha: alpha,
                duration: duration,
                timingFunction: timingFunction,
                completion: completion
            ))
            return true
        }

        @MainActor
        func finishAnimation(at index: Int) {
            let animation = animations[index]
            if !animation.isCancelled {
                alphaValue = animation.targetAlpha
            }
            animation.completion()
        }
    }

    func testShowHideShowHideOnlyWinningHideCompletesAndLeavesAlphaHidden() {
        let driver = FakeAlphaAnimationDriver()
        var showCount = 0
        var hideCount = 0
        let coordinator = makeCoordinator(
            driver: driver,
            didShow: { showCount += 1 },
            didHide: { hideCount += 1 }
        )

        let showOne = coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())
        let hideOne = coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())
        let showTwo = coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())
        let hideTwo = coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())

        driver.finishAnimation(at: 3)
        driver.finishAnimation(at: 3)
        driver.finishAnimation(at: 1)
        driver.finishAnimation(at: 0)
        driver.finishAnimation(at: 2)

        XCTAssertEqual(coordinator.generation, hideTwo)
        XCTAssertEqual(coordinator.phase, .hidden)
        XCTAssertEqual(driver.alphaValue, 0)
        XCTAssertEqual(showOne, 1)
        XCTAssertEqual(hideOne, 2)
        XCTAssertEqual(showTwo, 3)
        XCTAssertEqual(hideTwo, 4)
        XCTAssertEqual(showCount, 0)
        XCTAssertEqual(hideCount, 1)
        XCTAssertEqual(driver.cancelCount, 4)
    }

    func testHideShowHideShowOnlyWinningShowCompletesAndLeavesAlphaShown() {
        let driver = FakeAlphaAnimationDriver()
        var showCount = 0
        var hideCount = 0
        let coordinator = makeCoordinator(
            driver: driver,
            didShow: { showCount += 1 },
            didHide: { hideCount += 1 }
        )

        coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())
        coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())
        coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())
        let showGeneration = coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())

        driver.finishAnimation(at: 3)
        driver.finishAnimation(at: 3)
        driver.finishAnimation(at: 0)
        driver.finishAnimation(at: 2)
        driver.finishAnimation(at: 1)

        XCTAssertEqual(coordinator.generation, showGeneration)
        XCTAssertEqual(coordinator.phase, .shown)
        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(driver.cancelCount, 4)
    }

    func testShowRequestDuringHidingCancelsHideAndIgnoresStaleHideCompletion() {
        let driver = FakeAlphaAnimationDriver(alphaValue: 1)
        var showCount = 0
        var hideCount = 0
        let coordinator = makeCoordinator(
            driver: driver,
            didShow: { showCount += 1 },
            didHide: { hideCount += 1 }
        )

        let hideGeneration = coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())
        let showGeneration = coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())

        driver.finishAnimation(at: 0)

        XCTAssertEqual(coordinator.generation, showGeneration)
        XCTAssertEqual(coordinator.phase, .showing)
        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(showCount, 0)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(hideGeneration, 1)
        XCTAssertEqual(showGeneration, 2)

        driver.finishAnimation(at: 1)

        XCTAssertEqual(coordinator.phase, .shown)
        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(hideCount, 0)
        XCTAssertEqual(driver.cancelCount, 2)
    }

    func testAnimationUsesConfiguredTimingPolicyForBothDirections() {
        let driver = FakeAlphaAnimationDriver()
        let coordinator = makeCoordinator(driver: driver, timing: .smooth)

        coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())
        coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())

        XCTAssertEqual(driver.animations.map(\.targetAlpha), [1, 0])
        XCTAssertEqual(driver.animations.map(\.duration), [0.20, 0.20])
        XCTAssertEqual(timingFunctionControlPoints(driver.animations[0].timingFunction), [[0, 0], [0.42, 0], [0.58, 1], [1, 1]])
        XCTAssertEqual(timingFunctionControlPoints(driver.animations[1].timingFunction), [[0, 0], [0.42, 0], [0.58, 1], [1, 1]])

        let snappyDriver = FakeAlphaAnimationDriver()
        let snappyCoordinator = makeCoordinator(driver: snappyDriver, timing: .snappy)
        snappyCoordinator.request(.show)
        XCTAssertTrue(snappyCoordinator.startAnimation())
        XCTAssertEqual(snappyDriver.animations[0].duration, 0.10)
        XCTAssertEqual(timingFunctionControlPoints(snappyDriver.animations[0].timingFunction), [[0, 0], [0, 0], [0.58, 1], [1, 1]])
    }

    func testAnimationTimingIsReadOncePerAnimation() {
        let driver = FakeAlphaAnimationDriver()
        var timingReadCount = 0
        let coordinator = LauncherWindowVisibilityTransitionCoordinator(
            alphaDriver: driver,
            animationTiming: {
                timingReadCount += 1
                return .smooth
            }
        )

        coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())

        XCTAssertEqual(timingReadCount, 1)
    }

    func testShowTransitionDecisionReplacesShowingAndHidingPhases() {
        XCTAssertEqual(
            LauncherWindowShowTransitionPolicy.decision(
                priorPhase: .showing,
                isMaterialized: true
            ),
            .replaceAnimation
        )
        XCTAssertEqual(
            LauncherWindowShowTransitionPolicy.decision(
                priorPhase: .hiding,
                isMaterialized: true
            ),
            .replaceAnimation
        )
        XCTAssertEqual(
            LauncherWindowShowTransitionPolicy.decision(
                priorPhase: .hidden,
                isMaterialized: false
            ),
            .materialize
        )
        XCTAssertEqual(
            LauncherWindowShowTransitionPolicy.decision(
                priorPhase: .shown,
                isMaterialized: true
            ),
            .synchronous
        )
    }

    func testSecondShowBeforeColdOpenSchedulerTurnReplacesShowingTransition() {
        let driver = FakeAlphaAnimationDriver()
        var didShowCount = 0
        var queuedWork: [@MainActor () -> Void] = []
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        let coordinator = makeCoordinator(driver: driver, didShow: { didShowCount += 1 })

        let firstGeneration = coordinator.request(.show)
        let firstDecision = LauncherWindowShowTransitionPolicy.decision(
            priorPhase: .hidden,
            isMaterialized: false
        )
        XCTAssertEqual(firstDecision, .materialize)
        scheduler.schedule(
            expectedTransitionID: firstGeneration,
            stateProvider: { (coordinator.generation, coordinator.phase == .showing) },
            startAnimation: { completion in
                XCTAssertTrue(coordinator.startAnimation(completion: completion))
            },
            completionAction: {
                coordinator.complete(
                    generation: firstGeneration,
                    intent: .show,
                    phase: .showing
                )
            }
        )

        let secondGeneration = coordinator.request(.show)
        let secondDecision = LauncherWindowShowTransitionPolicy.decision(
            priorPhase: .showing,
            isMaterialized: true
        )
        XCTAssertEqual(secondDecision, .replaceAnimation)
        scheduler.schedule(
            expectedTransitionID: secondGeneration,
            stateProvider: { (coordinator.generation, coordinator.phase == .showing) },
            startAnimation: { completion in
                XCTAssertTrue(coordinator.startAnimation(completion: completion))
            },
            completionAction: {
                coordinator.complete(
                    generation: secondGeneration,
                    intent: .show,
                    phase: .showing
                )
            }
        )

        XCTAssertEqual(queuedWork.count, 2)
        queuedWork.removeFirst()()
        XCTAssertTrue(driver.animations.isEmpty)
        queuedWork.removeFirst()()
        XCTAssertEqual(driver.animations.count, 1)
        driver.finishAnimation(at: 0)

        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(coordinator.phase, .shown)
        XCTAssertEqual(didShowCount, 1)
        XCTAssertEqual(driver.cancelCount, 2)
    }

    func testStaleDuplicateAndOutOfOrderCompletionsAreIgnored() {
        let driver = FakeAlphaAnimationDriver()
        var showCount = 0
        var hideCount = 0
        let coordinator = makeCoordinator(
            driver: driver,
            didShow: { showCount += 1 },
            didHide: { hideCount += 1 }
        )

        let showGeneration = coordinator.request(.show)
        XCTAssertTrue(coordinator.startAnimation())
        coordinator.request(.hide)
        XCTAssertTrue(coordinator.startAnimation())
        driver.finishAnimation(at: 0)
        driver.finishAnimation(at: 1)
        driver.finishAnimation(at: 1)
        coordinator.complete(
            generation: showGeneration,
            intent: .show,
            phase: .showing
        )

        XCTAssertEqual(showCount, 0)
        XCTAssertEqual(hideCount, 1)
        XCTAssertEqual(coordinator.phase, .hidden)
    }

    func testFailedStartCanBeCompletedWithTerminalTargetAndWinningCallback() {
        let driver = FakeAlphaAnimationDriver(alphaValue: 0.4)
        driver.shouldStartAnimation = false
        var didShowCount = 0
        let coordinator = makeCoordinator(driver: driver, didShow: { didShowCount += 1 })

        let generation = coordinator.request(.show)
        XCTAssertFalse(coordinator.startAnimation())

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(coordinator.phase, .shown)
        XCTAssertEqual(didShowCount, 1)
    }

    func testFailedStartWithCompletionSetsTerminalAlphaAndDefersCoordinatorCompletion() {
        let driver = FakeAlphaAnimationDriver(alphaValue: 0.4)
        driver.shouldStartAnimation = false
        var callbackCount = 0
        var didShowCount = 0
        let coordinator = makeCoordinator(driver: driver, didShow: { didShowCount += 1 })

        let generation = coordinator.request(.show)
        XCTAssertFalse(coordinator.startAnimation {
            callbackCount += 1
        })

        XCTAssertEqual(driver.alphaValue, 1)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(coordinator.phase, .showing)
        XCTAssertEqual(didShowCount, 0)

        coordinator.complete(
            generation: generation,
            intent: .show,
            phase: .showing
        )

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(coordinator.phase, .shown)
        XCTAssertEqual(didShowCount, 1)
    }

    func testFailedHideStartCanBeCompletedWithHiddenTerminalAlpha() {
        let driver = FakeAlphaAnimationDriver(alphaValue: 0.6)
        driver.shouldStartAnimation = false
        var didHideCount = 0
        let coordinator = makeCoordinator(driver: driver, didHide: { didHideCount += 1 })

        let generation = coordinator.request(.hide)
        XCTAssertFalse(coordinator.startAnimation())

        XCTAssertEqual(coordinator.generation, generation)
        XCTAssertEqual(driver.alphaValue, 0)
        XCTAssertEqual(coordinator.phase, .hidden)
        XCTAssertEqual(didHideCount, 1)
    }

    func testAppKitAlphaDriverDoesNotRetainReleasedWindow() {
        weak var weakWindow: NSWindow?
        let driver = autoreleasepool { () -> AppKitLauncherWindowAlphaAnimationDriver in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            weakWindow = window
            window.alphaValue = 0.6
            return AppKitLauncherWindowAlphaAnimationDriver(window: window)
        }

        XCTAssertNil(weakWindow)
        XCTAssertEqual(driver.alphaValue, 0)
        XCTAssertFalse(driver.animate(
            to: 1,
            duration: 0.1,
            timingFunction: CAMediaTimingFunction(name: .easeOut),
            completion: {}
        ))
    }

    func testAppKitAlphaDriverCancelAndNormalizePreservesCurrentAlpha() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.35
        let driver = AppKitLauncherWindowAlphaAnimationDriver(window: window)

        driver.cancelAndNormalize()

        XCTAssertEqual(driver.alphaValue, 0.35)
        XCTAssertEqual(window.alphaValue, 0.35)
    }

    func testCoordinatorTeardownDoesNotRetainOwnerOrInvokeCompletion() {
        let driver = FakeAlphaAnimationDriver()
        var didShowCount = 0
        weak var weakCoordinator: LauncherWindowVisibilityTransitionCoordinator?

        do {
            let coordinator = makeCoordinator(driver: driver, didShow: { didShowCount += 1 })
            weakCoordinator = coordinator
            coordinator.request(.show)
            XCTAssertTrue(coordinator.startAnimation())
        }

        XCTAssertNil(weakCoordinator)
        driver.finishAnimation(at: 0)
        XCTAssertEqual(didShowCount, 0)
    }

    private func makeCoordinator(
        driver: FakeAlphaAnimationDriver,
        timing: LauncherAnimationTiming = .snappy,
        didShow: @escaping @MainActor () -> Void = {},
        didHide: @escaping @MainActor () -> Void = {}
    ) -> LauncherWindowVisibilityTransitionCoordinator {
        LauncherWindowVisibilityTransitionCoordinator(
            alphaDriver: driver,
            animationTiming: { timing },
            didShow: didShow,
            didHide: didHide
        )
    }

    private func timingFunctionControlPoints(_ timingFunction: CAMediaTimingFunction) -> [[Float]] {
        (0..<4).map { index in
            var values = [Float](repeating: 0, count: 2)
            timingFunction.getControlPoint(at: index, values: &values)
            return values
        }
    }
}
