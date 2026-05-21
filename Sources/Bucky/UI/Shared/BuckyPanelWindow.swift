import AppKit
import SwiftUI

final class BuckyPanelWindow: NSWindow {
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

        return bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
