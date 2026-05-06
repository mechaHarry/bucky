import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct NativeFileDragSourceView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NativeFileDragSourceNSView {
        let view = NativeFileDragSourceNSView()
        view.url = url
        return view
    }

    func updateNSView(_ nsView: NativeFileDragSourceNSView, context: Context) {
        nsView.url = url
    }
}

@available(macOS 26.0, *)
final class NativeFileDragSourceNSView: NSView, NSDraggingSource {
    var url: URL?
    private var mouseDownEvent: NSEvent?
    private var didBeginDrag = false

    override var mouseDownCanMoveWindow: Bool {
        FileBrowserDragPolicy.mouseDownCanMoveWindow
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag,
              let mouseDownEvent,
              let url,
              FileBrowserDragPolicy.shouldBeginNativeDrag(delta: dragDelta(from: mouseDownEvent, to: event)) else {
            return
        }

        didBeginDrag = true
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let pointerLocation = convert(event.locationInWindow, from: nil)
        let draggingItem = NSDraggingItem(pasteboardWriter: FileBrowserDragPolicy.draggedURL(for: url) as NSURL)
        draggingItem.setDraggingFrame(
            FileBrowserDragPolicy.draggingImageFrame(
                in: bounds,
                iconSize: icon.size,
                pointerLocation: pointerLocation
            ),
            contents: icon
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        didBeginDrag = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    private func dragDelta(from start: NSEvent, to current: NSEvent) -> CGSize {
        let startPoint = convert(start.locationInWindow, from: nil)
        let currentPoint = convert(current.locationInWindow, from: nil)
        return CGSize(width: currentPoint.x - startPoint.x, height: currentPoint.y - startPoint.y)
    }
}
