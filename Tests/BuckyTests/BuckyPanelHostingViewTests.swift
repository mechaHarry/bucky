import AppKit
import SwiftUI
import XCTest
@testable import Bucky

@MainActor
final class BuckyPanelHostingViewTests: XCTestCase {
    func testOffsetHostReceivesInteriorPointInSuperviewCoordinates() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let host = makeHost(in: parent)
        let point = parent.convert(NSPoint(x: 50, y: 25), from: host)

        XCTAssertNotNil(host.hitTest(point))
    }

    func testFlippedParentReceivesInteriorPointInSuperviewCoordinates() {
        let parent = FlippedParentView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let host = makeHost(in: parent)
        let point = parent.convert(NSPoint(x: 50, y: 25), from: host)

        XCTAssertNotNil(host.hitTest(point))
    }

    func testPointsOutsideOffsetHostDoNotBecomeInputTargets() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let host = makeHost(in: parent)
        // This lies inside the host's local bounds if mistakenly interpreted
        // as local coordinates, but is outside its frame in the parent.
        XCTAssertNil(host.hitTest(NSPoint(x: 25, y: 25)))

        for localPoint in [NSPoint(x: -1, y: 50), NSPoint(x: 101, y: 50),
                           NSPoint(x: 50, y: -1), NSPoint(x: 50, y: 101)] {
            XCTAssertNil(host.hitTest(parent.convert(localPoint, from: host)))
        }
    }

    private func makeHost(in parent: NSView) -> BuckyPanelHostingView<some View> {
        _ = NSApplication.shared
        let host = BuckyPanelHostingView(rootView: Color.clear.allowsHitTesting(false))
        host.sizingOptions = []
        host.frame = NSRect(x: 150, y: 200, width: 100, height: 100)
        parent.addSubview(host)
        host.layoutSubtreeIfNeeded()
        return host
    }
}

private final class FlippedParentView: NSView {
    override var isFlipped: Bool { true }
}
