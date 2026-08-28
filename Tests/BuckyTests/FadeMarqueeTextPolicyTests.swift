import XCTest
@testable import Bucky

final class FadeMarqueeTextPolicyTests: XCTestCase {
    func testOverflowUsesExplicitContainerWidthWhenProvided() {
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.overflow(contentWidth: 260, containerWidth: 180), 80)
    }

    func testOverflowNeverGoesNegative() {
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.overflow(contentWidth: 100, containerWidth: 180), 0)
    }

    func testOnlyOverflowingTextMarquees() {
        XCTAssertTrue(FadeMarqueeTextLayoutPolicy.shouldMarquee(contentWidth: 260, containerWidth: 180, reduceMotion: false))
        XCTAssertFalse(FadeMarqueeTextLayoutPolicy.shouldMarquee(contentWidth: 260, containerWidth: 180, reduceMotion: true))
        XCTAssertFalse(FadeMarqueeTextLayoutPolicy.shouldMarquee(contentWidth: 180, containerWidth: 180, reduceMotion: false))
    }

    func testMarqueeWaitsForMeasuredContainerWidth() {
        XCTAssertFalse(FadeMarqueeTextLayoutPolicy.shouldMarquee(contentWidth: 260, containerWidth: 0, reduceMotion: false))
    }

    func testOffsetTravelsFullOverflowWidth() {
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.offset(forProgress: 0, overflow: 180), 0)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.offset(forProgress: 1, overflow: 180), -180)
    }

    func testScrollProgressPausesAtBothEdgesAndEasesBetweenThem() {
        let overflow: CGFloat = 240
        let cycle = FadeMarqueeTextLayoutPolicy.cycleDuration(forOverflow: overflow)
        let pause = FadeMarqueeTextLayoutPolicy.edgePauseSeconds
        let travel = FadeMarqueeTextLayoutPolicy.travelDuration(forOverflow: overflow)

        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: 0, overflow: overflow), 0, accuracy: 0.0001)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: pause * 0.5, overflow: overflow), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: pause + travel * 0.5, overflow: overflow), 0.45)
        XCTAssertLessThan(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: pause + travel * 0.5, overflow: overflow), 0.55)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: pause + travel + pause * 0.5, overflow: overflow), 1, accuracy: 0.0001)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: cycle, overflow: overflow), 0, accuracy: 0.0001)
    }

    func testEdgeFadeStrengthChangesGraduallyWithOffset() {
        let overflow: CGFloat = 120

        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.leadingFadeStrength(offset: 0, overflow: overflow), 0)
        XCTAssertGreaterThan(FadeMarqueeTextLayoutPolicy.leadingFadeStrength(offset: -8, overflow: overflow), 0)
        XCTAssertLessThan(FadeMarqueeTextLayoutPolicy.leadingFadeStrength(offset: -8, overflow: overflow), 1)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.leadingFadeStrength(offset: -40, overflow: overflow), 1)

        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.trailingFadeStrength(offset: -overflow, overflow: overflow), 0)
        XCTAssertGreaterThan(FadeMarqueeTextLayoutPolicy.trailingFadeStrength(offset: -overflow + 8, overflow: overflow), 0)
        XCTAssertLessThan(FadeMarqueeTextLayoutPolicy.trailingFadeStrength(offset: -overflow + 8, overflow: overflow), 1)
        XCTAssertEqual(FadeMarqueeTextLayoutPolicy.trailingFadeStrength(offset: 0, overflow: overflow), 1)
    }

    func testTravelDurationClampsOverflowIntoSupportedRange() {
        XCTAssertEqual(
            FadeMarqueeTextLayoutPolicy.travelDuration(forOverflow: 0),
            FadeMarqueeTextLayoutPolicy.minimumTravelSeconds
        )
        XCTAssertEqual(
            FadeMarqueeTextLayoutPolicy.travelDuration(forOverflow: 90),
            FadeMarqueeTextLayoutPolicy.minimumTravelSeconds
        )
        XCTAssertEqual(
            FadeMarqueeTextLayoutPolicy.travelDuration(forOverflow: 720),
            FadeMarqueeTextLayoutPolicy.maximumTravelSeconds
        )
    }
}
