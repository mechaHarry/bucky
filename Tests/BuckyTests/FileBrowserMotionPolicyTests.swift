import XCTest
@testable import Bucky

final class FileBrowserMotionPolicyTests: XCTestCase {
    func testWobbleUsesGentleDisplacement() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleAmplitude, 2.5)
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.wobbleOscillations, 1.25)
    }

    func testListReconstructionUsesAppsStyleShortAnimation() {
        XCTAssertLessThanOrEqual(FileBrowserMotionPolicy.listReconstructionAnimationSeconds, 0.22)
    }

    func testBrowsePaneDoesNotAddNestedPanelChrome() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/FileBrowserView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("        .padding(10)\n        .overlay {\n            if isTransferPending"))
        XCTAssertFalse(source.contains("        .padding(12)\n        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14"))
        XCTAssertFalse(source.contains("        .padding(10)\n        .frame(maxWidth: .infinity, maxHeight: .infinity)\n        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14"))
    }

    func testFileBrowserAppliesAetherEdgesToWholeBrowsePane() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Bucky/UI/SwiftUI/FileBrowserView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("browsePane\n                .launcherAetherEdgeTreatment()"))
        XCTAssertFalse(source.contains("LauncherResultList(\n                    scrollTargetID: $pinnedScrollTargetID,\n                    reconstructionID: pinnedReconstructionIdentity\n                ) {\n                    ForEach"))
    }
}
