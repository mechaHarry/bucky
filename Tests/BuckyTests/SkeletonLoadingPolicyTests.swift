import XCTest
@testable import Bucky

final class SkeletonLoadingPolicyTests: XCTestCase {
    func testEachSurfaceProvidesTheConfigurationConsumedBySkeletonView() {
        let configurations = [
            SkeletonLoadingPolicy.configuration(for: .launcherResults, label: "Loading apps"),
            SkeletonLoadingPolicy.configuration(for: .fileResults, label: "Loading files"),
            SkeletonLoadingPolicy.configuration(for: .filePreview, label: "Loading preview"),
            SkeletonLoadingPolicy.configuration(for: .compact, label: "Loading files")
        ]

        XCTAssertEqual(configurations.map(\.rowCount), [4, 5, 3, 1])
        XCTAssertEqual(configurations.map(\.rowHeight), [54, 54, 54, 10])
        XCTAssertEqual(configurations.map(\.rowSpacing), [8, 8, 8, 8])
        XCTAssertEqual(configurations.map(\.horizontalPadding), [12, 12, 12, 0])
        XCTAssertEqual(configurations.map(\.cornerRadius), [12, 12, 12, 0])
        XCTAssertEqual(configurations.map(\.accessibilityLabel), [
            "Loading apps", "Loading files", "Loading preview", "Loading files"
        ])
    }

    func testSkeletonConfigurationUsesLifecycleBoundRepeatingAnimation() {
        let configuration = SkeletonLoadingPolicy.configuration(
            for: .filePreview,
            label: "Loading preview"
        )

        XCTAssertEqual(configuration.animation.lifecycle, .appearToStartDisappearToStop)
        XCTAssertTrue(configuration.animation.autoreverses)
        XCTAssertGreaterThan(configuration.animation.duration, 0)
    }

    func testPreviewSkeletonIsShownOnlyWhileNativeOrVideoContentLoads() {
        XCTAssertTrue(FileBrowserPreviewLoadingPolicy.shouldShowSkeleton(
            for: .nativeThumbnail,
            readiness: .loading
        ))
        XCTAssertTrue(FileBrowserPreviewLoadingPolicy.shouldShowSkeleton(
            for: .video,
            readiness: .loading
        ))
        XCTAssertFalse(FileBrowserPreviewLoadingPolicy.shouldShowSkeleton(
            for: .nativeThumbnail,
            readiness: .ready
        ))
        XCTAssertFalse(FileBrowserPreviewLoadingPolicy.shouldShowSkeleton(
            for: .nativeThumbnail,
            readiness: .failed
        ))
        XCTAssertFalse(FileBrowserPreviewLoadingPolicy.shouldShowSkeleton(
            for: .codeText,
            readiness: .loading
        ))
    }
}
