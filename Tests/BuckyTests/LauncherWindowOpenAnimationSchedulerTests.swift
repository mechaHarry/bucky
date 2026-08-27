import XCTest
@testable import Bucky

@MainActor
final class LauncherWindowOpenAnimationSchedulerTests: XCTestCase {
    private enum FakeVisibilityState {
        case showing
        case shown
        case hidden
    }

    func testQueuedMatchingStateStartsAnimationAndCompletionAdvancesState() {
        var queuedWork: [@MainActor () -> Void] = []
        var animationCompletion: (@MainActor () -> Void)?
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        var visibilityState = FakeVisibilityState.showing
        let state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var fakeAlpha = 0.0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { completion in
                fakeAlpha = 1
                animationCompletion = completion
            },
            completionAction: {
                visibilityState = .shown
            }
        )

        XCTAssertEqual(fakeAlpha, 0)
        XCTAssertEqual(queuedWork.count, 1)

        queuedWork.removeFirst()()

        XCTAssertEqual(fakeAlpha, 1)
        XCTAssertNotNil(animationCompletion)
        XCTAssertEqual(visibilityState, .showing)

        animationCompletion?()

        XCTAssertEqual(visibilityState, .shown)
    }

    func testDefaultSchedulerDefersAnimationStartToNextMainQueueTurn() async {
        let scheduler = LauncherWindowOpenAnimationScheduler()
        let completionExpectation = expectation(description: "default scheduler completes animation")
        let state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var startCount = 0
        var completionCount = 0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { completion in
                startCount += 1
                completion()
            },
            completionAction: {
                completionCount += 1
                completionExpectation.fulfill()
            }
        )

        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(completionCount, 0)

        await fulfillment(of: [completionExpectation], timeout: 1)

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testStaleTransitionSuppressesAnimationStartWhileStillShowing() {
        var queuedWork: [@MainActor () -> Void] = []
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        var state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var startCount = 0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { _ in startCount += 1 },
            completionAction: {}
        )
        state = (transitionID: 8, isShowing: true)

        queuedWork.removeFirst()()

        XCTAssertEqual(startCount, 0)
    }

    func testNonShowingStateSuppressesAnimationStartWhileIDMatches() {
        var queuedWork: [@MainActor () -> Void] = []
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        var state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var startCount = 0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { _ in startCount += 1 },
            completionAction: {}
        )
        state = (transitionID: 7, isShowing: false)

        queuedWork.removeFirst()()

        XCTAssertEqual(startCount, 0)
    }

    func testNonShowingStateDuringAnimationSuppressesCompletion() {
        var queuedWork: [@MainActor () -> Void] = []
        var animationCompletion: (@MainActor () -> Void)?
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        var state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var completionCount = 0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { completion in
                animationCompletion = completion
            },
            completionAction: { completionCount += 1 }
        )
        queuedWork.removeFirst()()
        state = (transitionID: 7, isShowing: false)

        animationCompletion?()

        XCTAssertEqual(completionCount, 0)
    }

    func testStaleTransitionDuringAnimationSuppressesCompletionWhileStillShowing() {
        var queuedWork: [@MainActor () -> Void] = []
        var animationCompletion: (@MainActor () -> Void)?
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        var state: LauncherWindowOpenAnimationScheduler.State? = (transitionID: 7, isShowing: true)
        var completionCount = 0

        scheduler.schedule(
            expectedTransitionID: 7,
            stateProvider: { state },
            startAnimation: { completion in
                animationCompletion = completion
            },
            completionAction: { completionCount += 1 }
        )
        queuedWork.removeFirst()()
        state = (transitionID: 8, isShowing: true)

        animationCompletion?()

        XCTAssertEqual(completionCount, 0)
    }

    func testOwnerIsNotRetainedByQueuedAnimationCallbacks() {
        final class Owner {}

        var queuedWork: [@MainActor () -> Void] = []
        let scheduler = LauncherWindowOpenAnimationScheduler { work in
            queuedWork.append(work)
        }
        weak var weakOwner: Owner?

        do {
            let owner = Owner()
            weakOwner = owner
            scheduler.schedule(
                expectedTransitionID: 7,
                stateProvider: { [weak owner] in
                    owner.map { _ in (transitionID: 7, isShowing: true) }
                },
                startAnimation: { [weak owner] _ in
                    _ = owner
                },
                completionAction: { [weak owner] in
                    _ = owner
                }
            )
        }

        XCTAssertNil(weakOwner)
        XCTAssertEqual(queuedWork.count, 1)
    }
}
