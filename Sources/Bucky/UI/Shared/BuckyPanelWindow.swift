import AppKit
import SwiftUI

final class BuckyPanelWindow: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var cancelHandler: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if cancelHandler?() != true {
            orderOut(sender)
        }
    }
}

final class BuckyPanelHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hitView = super.hitTest(point) {
            return hitView
        }

        // AppKit supplies hit-test points in the superview's coordinates.
        // Convert before checking our bounds, including flipped/offset hosts.
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
