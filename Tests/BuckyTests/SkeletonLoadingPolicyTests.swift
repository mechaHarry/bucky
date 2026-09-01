import XCTest
@testable import Bucky

final class SkeletonLoadingPolicyTests: XCTestCase {
    func testLoadingSurfacesHaveStableSkeletonCountsAndGeometry() {
        XCTAssertEqual(SkeletonLoadingPolicy.rowCount(for: .launcherResults), 4)
        XCTAssertEqual(SkeletonLoadingPolicy.rowCount(for: .fileResults), 5)
        XCTAssertEqual(SkeletonLoadingPolicy.rowCount(for: .filePreview), 3)
        XCTAssertEqual(SkeletonLoadingPolicy.rowCount(for: .compact), 1)
        XCTAssertEqual(SkeletonLoadingPolicy.resultRowHeight, 54)
        XCTAssertEqual(SkeletonLoadingPolicy.rowSpacing, 8)
        XCTAssertEqual(SkeletonLoadingPolicy.cornerRadius, 12)
    }

    func testSkeletonLoadingContractIsAccessibleAndLifecycleBound() {
        XCTAssertTrue(SkeletonLoadingPolicy.exposesAccessibleLabel)
        XCTAssertTrue(SkeletonLoadingPolicy.repeatsAnimation)
        XCTAssertTrue(SkeletonLoadingPolicy.stopsAnimationOnDisappear)
        XCTAssertFalse(SkeletonLoadingPolicy.usesTask)
        XCTAssertFalse(SkeletonLoadingPolicy.usesTimer)
        XCTAssertGreaterThan(SkeletonLoadingPolicy.animationDuration, 0)
    }
}
