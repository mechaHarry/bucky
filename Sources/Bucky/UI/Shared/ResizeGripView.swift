import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class ResizeGripView: NSView {
    var resizeHandler: (() -> Void)?

    private let minimumSize = NSSize(width: 360, height: 300)
    private var initialWindowFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Resize"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = "Resize"
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialWindowFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        let width = max(minimumSize.width, initialWindowFrame.width + deltaX)
        let height = max(minimumSize.height, initialWindowFrame.height - deltaY)
        let frame = NSRect(
            x: initialWindowFrame.minX,
            y: initialWindowFrame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(frame, display: true)
        resizeHandler?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.tertiaryLabelColor.setStroke()

        for offset in [5.0, 9.0, 13.0] {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + offset))
            path.stroke()
        }
    }
}
