import AppKit
import Carbon
import XCTest
@testable import Bucky

/// Exercises the real SwiftUI TextField and Carbon handler with isolated fixtures
/// and an uncommon test hotkey, without scanning or launching installed apps.
/// Requires a desktop test host allowed to acquire native key windows.
@available(macOS 26.0, *)
@MainActor
final class LauncherInputReadinessTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var lastResponderState: [Int: String] = [:]
    private var originalActivationPolicy: NSApplication.ActivationPolicy!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        originalActivationPolicy = NSApp.activationPolicy()
        // CLI XCTest starts with .prohibited and cannot own key windows. An
        // accessory host exercises the same nonactivating panel as the app.
        XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
        NSApp.finishLaunching()
        NSApp.activate()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyInputReadinessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        if let originalActivationPolicy {
            NSApp.setActivationPolicy(originalActivationPolicy)
        }
        originalActivationPolicy = nil
    }

    func testColdAndRepeatedHotkeyPresentationAcceptsNativeInputAndFilters() async throws {
        let controller = makeController()
        defer { controller.window.orderOut(nil) }
        // The first open deliberately does not wait for cache publication or
        // a rendered hidden window: search must also work immediately at boot.
        for iteration in 0..<3 {
            let started = ProcessInfo.processInfo.systemUptime
            controller.toggle()
            XCTAssertTrue(controller.window.isVisible)
            XCTAssertEqual(controller.window.alphaValue, 1, "Typing must not wait for an opacity animation")
            XCTAssertEqual(controller.model.query, "", "Every hotkey open starts a new search")
            if iteration > 0 {
                // No runloop turn, sleep, or readiness helper comes between
                // the hotkey and this first native key event on warm opens.
                XCTAssertNotNil(searchEditor(in: controller.window), "Retained search must accept the first key synchronously")
                try type("z", in: controller.window)
                XCTAssertEqual(controller.model.query, "z", "Native input must reach the binding before the next render")
            }

            try await waitUntil("search field is first responder on open \(iteration)") {
                self.searchEditor(in: controller.window) != nil
            }
            let readinessMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            // A broad regression ceiling accommodates loaded CI hosts. The
            // attachment retains actual timings for performance comparisons.
            XCTAssertLessThan(readinessMilliseconds, 1_000)
            recordTiming("open \(iteration) search readiness", milliseconds: readinessMilliseconds)

            try type(iteration == 0 ? "zebra" : "ebra", in: controller.window)
            try await waitUntil("native text reaches the query and filtered rows") {
                controller.model.query == "zebra"
                    && controller.model.filteredItems.map(\.title) == ["Zebra Utility"]
            }
            recordTiming("open \(iteration) typed and filtered", milliseconds:
                (ProcessInfo.processInfo.systemUptime - started) * 1_000)

            controller.toggle()
            try await waitUntil("window finishes hiding") { !controller.window.isVisible }
        }
    }

    func testCarbonHotkeyDispatchOpensSynchronouslyAndAcceptsNativeInput() async throws {
        let controller = makeController()
        defer { controller.window.orderOut(nil) }
        let identifier: UInt32 = 0x4255434B
        var sendReturned = false
        var callbackCount = 0
        let hotKey = try HotKeyController(
            configuration: HotKeyConfiguration(
                keyCode: UInt32(kVK_F19),
                modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey),
                keyName: "F19"
            ),
            identifier: identifier
        ) {
            XCTAssertFalse(sendReturned, "Main-thread Carbon input must not add a queued Task hop")
            callbackCount += 1
            controller.toggle()
        }
        defer { withExtendedLifetime(hotKey) {} }
        var createdEvent: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                   GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent),
                                   &createdEvent), noErr)
        let event = try XCTUnwrap(createdEvent)
        defer { ReleaseEvent(event) }
        var hotKeyID = EventHotKeyID(signature: "Bcky".fourCharCode, id: identifier)
        XCTAssertEqual(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size,
                                        &hotKeyID), noErr)
        let started = ProcessInfo.processInfo.systemUptime
        let dispatchStatus = SendEventToEventTarget(event, GetApplicationEventTarget())
        sendReturned = true
        XCTAssertEqual(dispatchStatus, noErr)
        XCTAssertEqual(callbackCount, 1, "Real registered Carbon handler must complete before dispatch returns")
        XCTAssertTrue(controller.window.isVisible)
        XCTAssertEqual(controller.window.alphaValue, 1)
        try await waitUntil("Carbon-launched native search editor") {
            self.searchEditor(in: controller.window) != nil
        }
        recordTiming("Carbon hotkey search readiness", milliseconds:
            (ProcessInfo.processInfo.systemUptime - started) * 1_000)
        try type("orbit", in: controller.window)
        try await waitUntil("Carbon-launched input is accepted and filtered") {
            controller.model.query == "orbit"
                && controller.model.filteredItems.map(\.title) == ["Orbit Utility"]
        }
    }

    func testHiddenLauncherReleasesControllerWindowAndModel() async throws {
        var controller: LiquidGlassLauncherWindowController? = autoreleasepool { makeController() }
        let references = LauncherWeakReferences(try XCTUnwrap(controller))
        // Teardown does not require native focus. Keep the fixture visible
        // through startup even if another desktop app owns the key window.
        controller?.show()
        controller?.model.isPinned = true
        try await waitUntil("startup cache publication finishes") {
            controller?.model.filteredItems.count == 2
        }
        controller?.hide()
        try await waitUntil("hide completion stops visible work") {
            controller?.window.isVisible == false && controller?.model.isPresented == false
        }
        controller = nil
        do {
            try await waitUntil("controller, retained SwiftUI shell, window, and model are released") {
                references.controller == nil && references.window == nil && references.model == nil
            }
        } catch {
            print("Launcher release state: controller=\(references.controller != nil) window=\(references.window != nil) model=\(references.model != nil)")
            throw error
        }
        XCTAssertNil(references.controller)
        XCTAssertNil(references.window)
        XCTAssertNil(references.model)
    }

    func testRapidHideReversalKeepsSearchResponderAndAcceptsNewInput() async throws {
        let controller = makeController()
        defer { controller.window.orderOut(nil) }
        try await waitUntil("cached synthetic applications are available") {
            controller.model.filteredItems.count == 2
        }
        controller.show()
        try await waitUntil("initial search editor") { self.searchEditor(in: controller.window) != nil }
        try type("zebra", in: controller.window)
        try await waitUntil("first native query is filtered") {
            controller.model.query == "zebra"
                && controller.model.filteredItems.map(\.title) == ["Zebra Utility"]
        }

        // Reverse before the close animation can complete. A stale hide
        // completion must not order out the reopened window or steal focus.
        controller.hide()
        controller.show()
        XCTAssertTrue(controller.window.isVisible)
        XCTAssertEqual(controller.window.alphaValue, 1)
        try await waitUntil("reversed presentation resets the native editor") {
            self.searchEditor(in: controller.window)?.string == ""
        }
        try type("orbit", in: controller.window)
        try await waitUntil("reversed presentation accepts and filters input") {
            controller.model.query == "orbit"
                && controller.model.filteredItems.map(\.title) == ["Orbit Utility"]
        }
        // Covers completion of both animation timing options (100/200 ms).
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(controller.window.isVisible)
        XCTAssertTrue(controller.window.isKeyWindow)
        XCTAssertNotNil(searchEditor(in: controller.window))
        XCTAssertEqual(controller.model.query, "orbit")
    }

    func testWindowServerTargetsResultsViewportInsteadOfUnderlyingWindow() async throws {
        let controller = makeController(titles: (0..<100).map { "Example \($0)" })
        defer { controller.window.orderOut(nil) }
        let underlyingWindow = NSWindow(contentRect: controller.window.frame,
                                        styleMask: .borderless, backing: .buffered, defer: false)
        underlyingWindow.isReleasedWhenClosed = false
        underlyingWindow.backgroundColor = .windowBackgroundColor
        // Keep the opaque fixture above normal desktop windows without
        // interacting with any other application.
        underlyingWindow.level = .floating
        underlyingWindow.orderFront(nil)
        defer { underlyingWindow.orderOut(nil) }
        controller.show()
        controller.model.isPinned = true
        controller.window.hidesOnDeactivate = false
        controller.window.level = .screenSaver
        controller.window.orderFrontRegardless()
        let screen = try XCTUnwrap(NSScreen.screens.min { $0.frame.minX < $1.frame.minX })
        controller.window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100,
                                               y: screen.visibleFrame.minY + 100))
        try await waitUntil("scrollable fixture results") {
            controller.model.filteredItemIDs.count == 100
                && self.resultScrollView(in: controller.window.contentView) != nil
        }
        controller.window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(controller.window.contentView)
        let scrollView = try XCTUnwrap(resultScrollView(in: root))
        let clip = scrollView.contentView
        underlyingWindow.setFrame(controller.window.frame, display: true)
        controller.window.displayIfNeeded()
        // Ignore system overlays above the fixture pair. The query still
        // chooses between the real Bucky panel and the opaque window below it.
        let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let queryCeiling = windowInfo.last {
            ($0[kCGWindowLayer as String] as? Int ?? 0) > NSWindow.Level.screenSaver.rawValue
        }?[kCGWindowNumber as String] as? Int ?? 0
        // Let WindowServer publish the rendered hit region. In-process
        // NSView.hitTest alone misses transparent pixels that pass through
        // to another application's window before AppKit receives the event.
        try await waitUntil("WindowServer publishes the fixture window") {
            let center = NSPoint(x: controller.window.frame.midX, y: controller.window.frame.midY)
            return NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: queryCeiling) == controller.window.windowNumber
                && NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: controller.window.windowNumber) == underlyingWindow.windowNumber
        }
        // Cover row content, the inter-row gap, and the inset outside every row.
        let points = [
            NSPoint(x: clip.bounds.midX, y: clip.bounds.minY + 40),
            NSPoint(x: clip.bounds.midX, y: clip.bounds.minY + 85),
            NSPoint(x: clip.bounds.minX + LauncherResultListLayoutPolicy.contentMargin - 2, y: clip.bounds.midY)
        ]
        for point in points {
            let screenPoint = controller.window.convertPoint(toScreen: clip.convert(point, to: nil))
            XCTAssertEqual(NSWindow.windowNumber(at: screenPoint,
                                                belowWindowWithWindowNumber: controller.window.windowNumber),
                           underlyingWindow.windowNumber, "The underlying fixture must cover each probe")
            XCTAssertEqual(NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: queryCeiling),
                           controller.window.windowNumber,
                           "WindowServer must target Bucky at row/gap/margin: \(point)")
            let hitPoint = root.superview?.convert(point, from: clip) ?? clip.convert(point, to: nil)
            let hit = root.hitTest(hitPoint)
            XCTAssertTrue(hit === scrollView || hit?.isDescendant(of: scrollView) == true,
                          "Rows, gaps, and margins must route wheel input into the scroll view")
        }
    }

    private func resultScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView, scroll.bounds.height > 100 { return scroll }
        return view.subviews.lazy.compactMap { self.resultScrollView(in: $0) }.first
    }

    private func makeController(titles: [String] = ["Zebra Utility", "Orbit Utility"]) -> LiquidGlassLauncherWindowController {
        let cache = ApplicationIndexSnapshotCache(fileURL: temporaryDirectory.appendingPathComponent("snapshot.json"))
        cache.save(titles.map { title in
            let url = temporaryDirectory.appendingPathComponent("\(title).app")
            return LaunchItem(title: title, subtitle: "Synthetic fixture", url: url, searchText: title.lowercased())
        })
        return LiquidGlassLauncherWindowController(
            settingsStore: SettingsStore(fileURL: temporaryDirectory.appendingPathComponent("settings.json")),
            inclusionStore: InclusionStore(fileURL: temporaryDirectory.appendingPathComponent("inclusions.json")),
            exclusionStore: ExclusionStore(fileURL: temporaryDirectory.appendingPathComponent("exclusions.json")),
            calculationHistoryStore: CalculationHistoryStore(fileURL: temporaryDirectory.appendingPathComponent("calculations.json")),
            dictionaryHistoryStore: DictionaryHistoryStore(fileURL: temporaryDirectory.appendingPathComponent("dictionary.json")),
            hotKeyChangeHandler: { _ in true },
            startsBackgroundServices: false,
            applicationIndexSnapshotCache: cache
        )
    }

    private func searchEditor(in window: NSWindow) -> NSTextView? {
        let responderClass = window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil"
        let state = "visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) active=\(NSApp.isActive) running=\(NSApp.isRunning) policy=\(NSApp.activationPolicy().rawValue) mainThread=\(Thread.isMainThread) canKey=\(window.canBecomeKey) responder=\(responderClass) editor=\((window.firstResponder as? NSTextView)?.isFieldEditor == true) editable=\((window.firstResponder as? NSTextView)?.isEditable == true)"
        if lastResponderState[window.windowNumber] != state {
            print("LauncherInputReadiness state: \(state)")
            lastResponderState[window.windowNumber] = state
        }
        guard window.isKeyWindow,
              let editor = window.firstResponder as? NSTextView,
              editor.isFieldEditor, editor.isEditable else { return nil }
        return editor
    }

    private func recordTiming(_ description: String, milliseconds: Double) {
        let message = "LauncherInputReadiness: \(description): \(milliseconds) ms"
        print(message)
        let attachment = XCTAttachment(string: message)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func type(_ text: String, in window: NSWindow) throws {
        XCTAssertNotNil(searchEditor(in: window), "Input must go through SwiftUI's focused native text editor")
        let keyCodes: [Character: UInt16] = ["z": 6, "e": 14, "b": 11, "r": 15, "a": 0,
                                             "o": 31, "i": 34, "t": 17]
        for character in text {
            let keyCode = try XCTUnwrap(keyCodes[character])
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: String(character), charactersIgnoringModifiers: String(character),
                isARepeat: false, keyCode: keyCode
            ))
            window.sendEvent(event)
        }
    }

    private func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            // XCTest has no NSApplication.run loop. Deliver WindowServer key
            // ownership notifications as the real app's event loop would.
            for _ in 0..<32 {
                guard let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) else { break }
                NSApp.sendEvent(event)
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
        if !condition() { throw ReadinessError.timedOut }
    }

    private enum ReadinessError: Error { case timedOut }

    @MainActor
    private final class LauncherWeakReferences {
        weak var controller: LiquidGlassLauncherWindowController?
        weak var window: NSWindow?
        weak var model: LiquidGlassLauncherModel?

        init(_ controller: LiquidGlassLauncherWindowController) {
            self.controller = controller
            window = controller.window
            model = controller.model
        }
    }
}
