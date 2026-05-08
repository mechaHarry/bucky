import XCTest
@testable import Bucky

final class LauncherSpaceKeyRouterTests: XCTestCase {
    func testSpaceTapSchedulesHoldThenSendsSpaceOnKeyUp() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.keyUp(), .sendSpace)
    }

    func testSpaceHoldSendsBeginAfterDelayAndEndOnKeyUp() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.holdDelayElapsed(), .sendBeginHold)
        XCTAssertEqual(router.keyUp(), .sendEndHold)
    }

    func testSpaceRepeatIsConsumedWhilePendingOrHolding() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: true), .consume)
        XCTAssertEqual(router.holdDelayElapsed(), .sendBeginHold)
        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: true), .consume)
        XCTAssertEqual(router.keyUp(), .sendEndHold)
    }

    func testShiftSpaceSendsRangeSelectionWithoutSchedulingHold() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: true, isRepeat: false), .sendShiftSpace)
        XCTAssertEqual(router.keyUp(), .pass)
    }

    func testCancelPendingHoldResetsWithoutSendingEndHold() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.cancel(), .pass)
        XCTAssertEqual(router.keyUp(), .pass)
        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.keyUp(), .sendSpace)
    }

    func testCancelActiveHoldSendsEndHoldAndResets() {
        var router = LauncherSpaceKeyRouter()

        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.holdDelayElapsed(), .sendBeginHold)
        XCTAssertEqual(router.cancel(), .sendEndHold)
        XCTAssertEqual(router.keyUp(), .pass)
        XCTAssertEqual(router.keyDown(isShift: false, isRepeat: false), .scheduleHold)
        XCTAssertEqual(router.keyUp(), .sendSpace)
    }
}
