# Bucky Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Bucky launcher refinements for calculator live results, native file drag selection, persisted dictionary history, text input editing, and mode-switcher stone/pill motion.

**Architecture:** Keep changes inside existing boundaries: calculator parsing in `ArithmeticEvaluator`, launcher/tool routing in `LiquidGlassLauncherModel`, file selection in `FileBrowserModel`, native drag in `NativeFileDragSourceView`, and mode-switcher visuals in `ModeSwitcherView`. Add a dedicated `DictionaryHistoryStore` matching the calculator history store pattern instead of creating a shared abstraction.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, macOS 26 Liquid Glass APIs.

---

## File Structure

- Modify `Sources/Bucky/Models/CoreModels.swift`: add dictionary history models and `ToolItem.Kind.dictionaryHistory`.
- Modify `Sources/Bucky/Tools/Calculator/ArithmeticEvaluator.swift`: normalize trailing equals signs.
- Modify `Sources/Bucky/UI/Shared/Utilities.swift`: add text-editing command routing policy.
- Modify `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`: let native text-editing commands reach focused text fields.
- Modify `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`: inject dictionary history, scroll live calculator results, build dictionary history rows, and remove one dictionary history row.
- Modify `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`: add dictionary-history row icon and clear-row action.
- Modify `Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift`: use matched glass geometry for every mode and slide the active pill from the selected mode's compact stone slot.
- Modify `Sources/Bucky/UI/SwiftUI/NativeFileDragSourceView.swift`: accept a URL provider and begin native drags with all selected URLs when the dragged row is selected.
- Modify `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`: pass selected drag URLs into `NativeFileDragSourceView`.
- Create `Sources/Bucky/Settings/DictionaryHistoryStore.swift`: persisted, deduped dictionary history.
- Modify `Sources/Bucky/App/AppDelegate.swift`: create and pass `DictionaryHistoryStore`.
- Modify tests in `Tests/BuckyTests/LauncherModeRoutingTests.swift`, `Tests/BuckyTests/FileBrowserPreviewPolicyTests.swift`, `Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift`.
- Create `Tests/BuckyTests/ArithmeticEvaluatorTests.swift`.
- Create `Tests/BuckyTests/DictionaryHistoryStoreTests.swift`.

## Scope Check

The spec spans four UI surfaces, but all changes are launcher refinements inside one app shell and share integration in `LiquidGlassLauncherModel`. Keep them in one implementation branch, with micro-commits per task so each behavior is independently reviewable.

---

### Task 1: Calculator Equals Normalization And Live Row Scrolling

**Files:**
- Create: `Tests/BuckyTests/ArithmeticEvaluatorTests.swift`
- Modify: `Sources/Bucky/Tools/Calculator/ArithmeticEvaluator.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`
- Modify: `Tests/BuckyTests/LauncherModeRoutingTests.swift`

- [ ] **Step 1: Write failing calculator evaluator tests**

Create `Tests/BuckyTests/ArithmeticEvaluatorTests.swift`:

```swift
import XCTest
@testable import Bucky

final class ArithmeticEvaluatorTests: XCTestCase {
    func testTrailingEqualsCompletesExpression() {
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2 ="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.normalizedExpression("2 + 2=="), "2 + 2")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("2 + 2 ="), "4")
        XCTAssertEqual(ArithmeticEvaluator.evaluate("1,200 / 3 ="), "400")
    }

    func testEmbeddedEqualsRemainsInvalid() {
        XCTAssertNil(ArithmeticEvaluator.evaluate("2 = + 2"))
        XCTAssertFalse(ArithmeticEvaluator.isArithmeticInput("2 = + 2"))
    }

    func testHistoryStorageUsesNormalizedExpression() {
        XCTAssertTrue(ArithmeticEvaluator.shouldStoreInHistory("2 + 2 ="))
        XCTAssertFalse(ArithmeticEvaluator.shouldStoreInHistory("42 ="))
    }
}
```

- [ ] **Step 2: Run evaluator tests to verify they fail**

Run:

```bash
swift test --filter ArithmeticEvaluatorTests
```

Expected: FAIL because `ArithmeticEvaluatorTests` cannot find `normalizedExpression`, and trailing `=` does not evaluate.

- [ ] **Step 3: Implement calculator normalization**

In `Sources/Bucky/Tools/Calculator/ArithmeticEvaluator.swift`, replace the top of `ArithmeticEvaluator` with:

```swift
enum ArithmeticEvaluator {
    static func evaluate(_ input: String) -> String? {
        let expression = normalizedExpression(input)
        guard isArithmeticInput(expression) else { return nil }

        do {
            var parser = ArithmeticParser(expression)
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return format(value)
        } catch {
            return nil
        }
    }

    static func normalizedExpression(_ input: String) -> String {
        var expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.hasSuffix("=") {
            expression.removeLast()
            expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return expression
    }

    static func isArithmeticInput(_ input: String) -> Bool {
        let expression = normalizedExpression(input)
        guard !expression.isEmpty else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "0123456789+-*/×÷()., \t\n")
        return expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    static func shouldStoreInHistory(_ input: String) -> Bool {
        containsBinaryArithmeticOperator(normalizedExpression(input))
    }
```

Leave `containsBinaryArithmeticOperator`, `format`, and `resultFormatter` unchanged.

- [ ] **Step 4: Run evaluator tests to verify they pass**

Run:

```bash
swift test --filter ArithmeticEvaluatorTests
```

Expected: PASS.

- [ ] **Step 5: Write failing launcher model scroll test**

Append this test to `Tests/BuckyTests/LauncherModeRoutingTests.swift`:

```swift
@MainActor
@available(macOS 26.0, *)
func testCalculatorLiveResultSelectsAndScrollsToTopRowWhileTyping() {
    let model = LiquidGlassLauncherModel(
        settingsStore: SettingsStore(),
        inclusionStore: InclusionStore(),
        exclusionStore: ExclusionStore(),
        calculationHistoryStore: CalculationHistoryStore(),
        fileBrowserModel: FileBrowserModel(
            fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: ImmediateDirectoryStream()
        )
    )

    model.show(mode: .calculator)
    model.query = "1 + 1"
    model.queryDidChange()
    model.selectedIndex = 1

    model.query = "2 + 2 ="
    model.queryDidChange()

    XCTAssertEqual(model.toolItems.first?.kind, .calculation)
    XCTAssertEqual(model.toolItems.first?.title, "4")
    XCTAssertEqual(model.selectedIndex, 0)
    XCTAssertEqual(model.selectionScrollRequest?.index, 0)
    XCTAssertEqual(model.selectionScrollRequest?.anchor, .top)
}
```

- [ ] **Step 6: Run launcher model test to verify it fails**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testCalculatorLiveResultSelectsAndScrollsToTopRowWhileTyping
```

Expected: FAIL because the model does not force selection and scroll to row `0`.

- [ ] **Step 7: Normalize calculator display and history expression in model**

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`, inside `makeToolItems(for:scheduleHistory:)`, replace the calculator branch with this body:

```swift
case .calculator:
    if trimmedQuery.isEmpty {
        return calculationHistoryItems()
    }

    let expression = ArithmeticEvaluator.normalizedExpression(trimmedQuery)
    guard ArithmeticEvaluator.isArithmeticInput(expression) else {
        return [
            ToolItem(
                title: "Enter a calculation",
                subtitle: trimmedQuery,
                copyText: nil,
                kind: .message
            )
        ]
    }

    if let result = ArithmeticEvaluator.evaluate(expression) {
        let items = [
            ToolItem(
                title: result,
                subtitle: "\(expression) =",
                copyText: result,
                kind: .calculation
            )
        ] + calculationHistoryItems(excludingExpression: expression, result: result)

        if scheduleHistory, ArithmeticEvaluator.shouldStoreInHistory(expression) {
            scheduleCalculationHistory(expression: expression, result: result)
        }
        return items
    } else {
        return [
            ToolItem(
                title: "Complete the calculation",
                subtitle: trimmedQuery,
                copyText: nil,
                kind: .message
            )
        ] + calculationHistoryItems()
    }
```

- [ ] **Step 8: Force calculator live result scroll**

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`, replace `applyToolResultsSnapshot(_:)` with:

```swift
private func applyToolResultsSnapshot(_ nextItems: [ToolItem]) {
    toolItems = nextItems
    if mode == .calculator, nextItems.first?.kind == .calculation {
        selectedIndex = 0
        requestSelectionScroll(anchor: .top)
        return
    }
    clampSelection()
}
```

- [ ] **Step 9: Run Task 1 tests**

Run:

```bash
swift test --filter ArithmeticEvaluatorTests
swift test --filter LauncherModeRoutingTests/testCalculatorLiveResultSelectsAndScrollsToTopRowWhileTyping
```

Expected: PASS after Task 3 adds `DictionaryHistoryStore(fileURL:)`.

- [ ] **Step 10: Commit Task 1**

Run:

```bash
git add Sources/Bucky/Tools/Calculator/ArithmeticEvaluator.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift Tests/BuckyTests/ArithmeticEvaluatorTests.swift Tests/BuckyTests/LauncherModeRoutingTests.swift
git commit -m "feat: refine calculator live results"
```

Expected: commit succeeds.

---

### Task 2: Native Text Editing Command Pass-Through

**Files:**
- Modify: `Sources/Bucky/UI/Shared/Utilities.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`
- Modify: `Tests/BuckyTests/LauncherModeRoutingTests.swift`

- [ ] **Step 1: Write failing key-routing policy tests**

Append these tests to `Tests/BuckyTests/LauncherModeRoutingTests.swift`:

```swift
func testTextInputModesPassThroughNativeEditingCommands() {
    XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .calculator,
        fileFocusState: nil,
        charactersIgnoringModifiers: "v",
        modifierFlags: .command,
        eventType: .keyDown
    ))
    XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .dictionary,
        fileFocusState: nil,
        charactersIgnoringModifiers: "a",
        modifierFlags: .command,
        eventType: .keyDown
    ))
    XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .applications,
        fileFocusState: nil,
        charactersIgnoringModifiers: "c",
        modifierFlags: .command,
        eventType: .keyDown
    ))
}

func testLauncherCommandsDoNotPassThroughAsTextEditingCommands() {
    XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .calculator,
        fileFocusState: nil,
        charactersIgnoringModifiers: "2",
        modifierFlags: .command,
        eventType: .keyDown
    ))
    XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .applications,
        fileFocusState: nil,
        charactersIgnoringModifiers: "r",
        modifierFlags: .command,
        eventType: .keyDown
    ))
    XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .applications,
        fileFocusState: nil,
        charactersIgnoringModifiers: "p",
        modifierFlags: .command,
        eventType: .keyDown
    ))
}

func testFilesRenamePassesThroughNativeEditingCommands() {
    XCTAssertTrue(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .files,
        fileFocusState: .renaming,
        charactersIgnoringModifiers: "v",
        modifierFlags: .command,
        eventType: .keyDown
    ))
    XCTAssertFalse(LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
        mode: .files,
        fileFocusState: .browse,
        charactersIgnoringModifiers: "v",
        modifierFlags: .command,
        eventType: .keyDown
    ))
}
```

- [ ] **Step 2: Run routing tests to verify they fail**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testTextInputModesPassThroughNativeEditingCommands
```

Expected: FAIL because `shouldPassThroughNativeTextEditingCommand` does not exist.

- [ ] **Step 3: Add text editing command policy**

In `Sources/Bucky/UI/Shared/Utilities.swift`, add this method inside `LauncherKeyRoutingPolicy`:

```swift
static func shouldPassThroughNativeTextEditingCommand(
    mode: LauncherMode,
    fileFocusState: FileBrowserFocusState?,
    charactersIgnoringModifiers: String?,
    modifierFlags: NSEvent.ModifierFlags,
    eventType: NSEvent.EventType
) -> Bool {
    guard eventType == .keyDown || eventType == .keyUp else {
        return false
    }

    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags == .command,
          let key = charactersIgnoringModifiers?.lowercased() else {
        return false
    }

    let textEditingKeys: Set<String> = ["a", "c", "v", "x", "z"]
    guard textEditingKeys.contains(key) else {
        return false
    }

    let launcherReservedKeys: Set<String> = ["1", "2", "3", "4", "r", ",", "p", "[", "]"]
    guard !launcherReservedKeys.contains(key) else {
        return false
    }

    if mode.acceptsTextInput {
        return true
    }

    return mode == .files && fileFocusState == .renaming
}
```

- [ ] **Step 4: Use policy in the local key monitor**

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`, insert this block after the existing file text-editing pass-through block and before the space-key handling block:

```swift
if LauncherKeyRoutingPolicy.shouldPassThroughNativeTextEditingCommand(
    mode: self.model.mode,
    fileFocusState: self.model.mode == .files ? self.fileBrowserFocusState : nil,
    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
    modifierFlags: event.modifierFlags,
    eventType: event.type
) {
    return event
}
```

- [ ] **Step 5: Run Task 2 tests**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testTextInputModesPassThroughNativeEditingCommands
swift test --filter LauncherModeRoutingTests/testLauncherCommandsDoNotPassThroughAsTextEditingCommands
swift test --filter LauncherModeRoutingTests/testFilesRenamePassesThroughNativeEditingCommands
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
git add Sources/Bucky/UI/Shared/Utilities.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift Tests/BuckyTests/LauncherModeRoutingTests.swift
git commit -m "fix: preserve native text editing shortcuts"
```

Expected: commit succeeds.

---

### Task 3: File Drag Selection Policy And Native Drag Payloads

**Files:**
- Modify: `Sources/Bucky/Files/FileBrowserModels.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/NativeFileDragSourceView.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`
- Modify: `Tests/BuckyTests/FileBrowserPreviewPolicyTests.swift`

- [ ] **Step 1: Write failing drag selection tests**

Append these tests to `Tests/BuckyTests/FileBrowserPreviewPolicyTests.swift`:

```swift
func testSelectedRowDragUsesAllSelectedURLs() {
    let home = URL(fileURLWithPath: "/Users/test")
    let one = home.appendingPathComponent("one.txt")
    let two = home.appendingPathComponent("two.txt")

    XCTAssertEqual(
        FileBrowserDragPolicy.draggedURLs(for: one, selectedURLs: [one, two]),
        [one, two]
    )
}

func testUnselectedRowDragUsesOnlyDraggedRow() {
    let home = URL(fileURLWithPath: "/Users/test")
    let one = home.appendingPathComponent("one.txt")
    let two = home.appendingPathComponent("two.txt")
    let three = home.appendingPathComponent("three.txt")

    XCTAssertEqual(
        FileBrowserDragPolicy.draggedURLs(for: three, selectedURLs: [one, two]),
        [three]
    )
}

func testSelectedRowDragPreservesSelectionsFromOtherDirectories() {
    let home = URL(fileURLWithPath: "/Users/test")
    let other = URL(fileURLWithPath: "/Users/other")
    let one = home.appendingPathComponent("one.txt")
    let remote = other.appendingPathComponent("remote.txt")

    XCTAssertEqual(
        FileBrowserDragPolicy.draggedURLs(for: one, selectedURLs: [one, remote]),
        [one, remote]
    )
}
```

- [ ] **Step 2: Run drag policy tests to verify they fail**

Run:

```bash
swift test --filter FileBrowserPreviewPolicyTests/testSelectedRowDragUsesAllSelectedURLs
```

Expected: FAIL because `draggedURLs(for:selectedURLs:)` does not exist.

- [ ] **Step 3: Add drag selection policy**

In `Sources/Bucky/Files/FileBrowserModels.swift`, add this method inside `FileBrowserDragPolicy` after `draggedURL(for:)`:

```swift
static func draggedURLs(for rowURL: URL, selectedURLs: [URL]) -> [URL] {
    selectedURLs.contains(rowURL) ? selectedURLs : [rowURL]
}
```

- [ ] **Step 4: Update native drag source view API**

In `Sources/Bucky/UI/SwiftUI/NativeFileDragSourceView.swift`, replace the representable struct and `NSView` properties with:

```swift
@available(macOS 26.0, *)
struct NativeFileDragSourceView: NSViewRepresentable {
    let url: URL
    let urlsProvider: () -> [URL]

    func makeNSView(context: Context) -> NativeFileDragSourceNSView {
        let view = NativeFileDragSourceNSView()
        view.url = url
        view.urlsProvider = urlsProvider
        return view
    }

    func updateNSView(_ nsView: NativeFileDragSourceNSView, context: Context) {
        nsView.url = url
        nsView.urlsProvider = urlsProvider
    }
}

@available(macOS 26.0, *)
final class NativeFileDragSourceNSView: NSView, NSDraggingSource {
    var url: URL?
    var urlsProvider: (() -> [URL])?
    private var mouseDownEvent: NSEvent?
    private var didBeginDrag = false
```

- [ ] **Step 5: Create one native dragging item per URL**

In `NativeFileDragSourceNSView.mouseDragged(with:)`, replace the item creation block with:

```swift
didBeginDrag = true
let urls = urlsProvider?() ?? [url]
let pointerLocation = convert(event.locationInWindow, from: nil)
let draggingItems = urls.enumerated().map { index, draggedURL in
    let item = NSDraggingItem(pasteboardWriter: FileBrowserDragPolicy.draggedURL(for: draggedURL) as NSURL)
    let icon = NSWorkspace.shared.icon(forFile: draggedURL.path)
    let frame = FileBrowserDragPolicy.draggingImageFrame(
        in: bounds,
        iconSize: icon.size,
        pointerLocation: CGPoint(
            x: pointerLocation.x + CGFloat(index) * 4,
            y: pointerLocation.y - CGFloat(index) * 4
        )
    )
    item.setDraggingFrame(frame, contents: icon)
    return item
}
beginDraggingSession(with: draggingItems, event: event, source: self)
```

Keep the existing guard above this block, and keep `draggingSession(_:sourceOperationMaskFor:)` returning `.copy`.

- [ ] **Step 6: Pass selected URLs from file rows**

In `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`, replace the current file row overlay:

```swift
NativeFileDragSourceView(url: entry.url)
    .accessibilityHidden(true)
```

with:

```swift
NativeFileDragSourceView(
    url: entry.url,
    urlsProvider: {
        FileBrowserDragPolicy.draggedURLs(for: entry.url, selectedURLs: model.selectedURLs)
    }
)
.accessibilityHidden(true)
```

For pinned rows, replace:

```swift
NativeFileDragSourceView(url: url)
    .accessibilityHidden(true)
```

with:

```swift
NativeFileDragSourceView(url: url, urlsProvider: { [url] })
    .accessibilityHidden(true)
```

- [ ] **Step 7: Run Task 3 tests**

Run:

```bash
swift test --filter FileBrowserPreviewPolicyTests/testSelectedRowDragUsesAllSelectedURLs
swift test --filter FileBrowserPreviewPolicyTests/testUnselectedRowDragUsesOnlyDraggedRow
swift test --filter FileBrowserPreviewPolicyTests/testSelectedRowDragPreservesSelectionsFromOtherDirectories
```

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

Run:

```bash
git add Sources/Bucky/Files/FileBrowserModels.swift Sources/Bucky/UI/SwiftUI/NativeFileDragSourceView.swift Sources/Bucky/UI/SwiftUI/FileBrowserView.swift Tests/BuckyTests/FileBrowserPreviewPolicyTests.swift
git commit -m "fix: drag selected files together"
```

Expected: commit succeeds.

---

### Task 4: Dictionary History Store

**Files:**
- Modify: `Sources/Bucky/Models/CoreModels.swift`
- Create: `Sources/Bucky/Settings/DictionaryHistoryStore.swift`
- Create: `Tests/BuckyTests/DictionaryHistoryStoreTests.swift`

- [ ] **Step 1: Add dictionary history models**

In `Sources/Bucky/Models/CoreModels.swift`, add these models after `CalculationHistoryFile`:

```swift
struct DictionaryHistoryEntry: Codable, Hashable {
    let term: String
    let date: Date
}

struct DictionaryHistoryFile: Codable {
    var words: [DictionaryHistoryEntry]
}
```

Also add this case to `ToolItem.Kind`:

```swift
case dictionaryHistory
```

- [ ] **Step 2: Write failing dictionary store tests**

Create `Tests/BuckyTests/DictionaryHistoryStoreTests.swift`:

```swift
import XCTest
@testable import Bucky

final class DictionaryHistoryStoreTests: XCTestCase {
    func testAddDedupesByNormalizedTermAndMovesLatestToTop() {
        let store = makeStore()

        store.add(term: "Apple")
        store.add(term: " apple ")

        XCTAssertEqual(store.words.map(\.term), ["apple"])
    }

    func testRemoveDeletesSingleNormalizedTerm() {
        let store = makeStore()

        store.add(term: "apple")
        store.add(term: "banana")
        store.remove(term: " APPLE ")

        XCTAssertEqual(store.words.map(\.term), ["banana"])
    }

    func testHistoryPersistsAndCapsAtOneHundredEntries() {
        let fileURL = temporaryFileURL()
        let store = DictionaryHistoryStore(fileURL: fileURL)

        for index in 0..<105 {
            store.add(term: "word-\(index)")
        }

        let reloaded = DictionaryHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.words.count, 100)
        XCTAssertEqual(reloaded.words.first?.term, "word-104")
        XCTAssertEqual(reloaded.words.last?.term, "word-5")
    }

    func testMalformedFileFallsBackToEmptyHistory() throws {
        let fileURL = temporaryFileURL()
        try Data("not json".utf8).write(to: fileURL)

        let store = DictionaryHistoryStore(fileURL: fileURL)

        XCTAssertEqual(store.words, [])
    }

    private func makeStore() -> DictionaryHistoryStore {
        DictionaryHistoryStore(fileURL: temporaryFileURL())
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyDictionaryHistory-\(UUID().uuidString).json")
    }
}
```

- [ ] **Step 3: Run dictionary store tests to verify they fail**

Run:

```bash
swift test --filter DictionaryHistoryStoreTests
```

Expected: FAIL because `DictionaryHistoryStore` does not exist.

- [ ] **Step 4: Implement dictionary history store**

Create `Sources/Bucky/Settings/DictionaryHistoryStore.swift`:

```swift
import Foundation

final class DictionaryHistoryStore {
    private let fileManager = FileManager.default
    private(set) var words: [DictionaryHistoryEntry] = []
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? BuckyPaths.appSupportDirectory
            .appendingPathComponent("dictionary-history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            words = []
            return
        }

        do {
            let file = try JSONDecoder().decode(DictionaryHistoryFile.self, from: data)
            words = file.words
        } catch {
            NSLog("Bucky could not read dictionary history at %@: %@", fileURL.path, error.localizedDescription)
            words = []
        }
    }

    func add(term: String) {
        let normalizedTerm = normalized(term.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedTerm.isEmpty else { return }

        words.removeAll { normalized($0.term) == normalizedTerm }
        words.insert(DictionaryHistoryEntry(term: normalizedTerm, date: Date()), at: 0)

        if words.count > 100 {
            words = Array(words.prefix(100))
        }

        save()
    }

    func remove(term: String) {
        let normalizedTerm = normalized(term.trimmingCharacters(in: .whitespacesAndNewlines))
        words.removeAll { normalized($0.term) == normalizedTerm }
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let file = DictionaryHistoryFile(words: words)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save dictionary history at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run dictionary store tests**

Run:

```bash
swift test --filter DictionaryHistoryStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add Sources/Bucky/Models/CoreModels.swift Sources/Bucky/Settings/DictionaryHistoryStore.swift Tests/BuckyTests/DictionaryHistoryStoreTests.swift
git commit -m "feat: persist dictionary history"
```

Expected: commit succeeds.

---

### Task 5: Dictionary History Model And Row UI

**Files:**
- Modify: `Sources/Bucky/App/AppDelegate.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`
- Modify: `Tests/BuckyTests/LauncherModeRoutingTests.swift`

- [ ] **Step 1: Write failing dictionary model tests**

Append these tests to `Tests/BuckyTests/LauncherModeRoutingTests.swift`:

```swift
@MainActor
@available(macOS 26.0, *)
func testBlankDictionaryModeShowsPersistedHistoryRows() {
    let history = DictionaryHistoryStore(fileURL: URL(fileURLWithPath: "/tmp/bucky-dictionary-history-test-\(UUID().uuidString).json"))
    history.add(term: "apple")
    let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history)

    model.show(mode: .dictionary)

    XCTAssertEqual(model.toolItems.map(\.kind), [.dictionaryHistory])
    XCTAssertEqual(model.toolItems.first?.title, "apple")
    XCTAssertNil(model.emptyMessage)
}

@MainActor
@available(macOS 26.0, *)
func testDictionaryHistoryRowCanBeRemovedIndividually() {
    let history = DictionaryHistoryStore(fileURL: URL(fileURLWithPath: "/tmp/bucky-dictionary-history-test-\(UUID().uuidString).json"))
    history.add(term: "apple")
    history.add(term: "banana")
    let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history)

    model.show(mode: .dictionary)
    model.removeDictionaryHistory(model.toolItems[1])

    XCTAssertEqual(model.toolItems.map(\.title), ["banana"])
}

@MainActor
@available(macOS 26.0, *)
func testDictionaryHistoryActivationMovesTermToTop() {
    let history = DictionaryHistoryStore(fileURL: URL(fileURLWithPath: "/tmp/bucky-dictionary-history-test-\(UUID().uuidString).json"))
    history.add(term: "apple")
    history.add(term: "banana")
    let model = makeDictionaryLauncherModel(dictionaryHistoryStore: history)
    model.isPinned = true

    model.show(mode: .dictionary)
    model.selectedIndex = 1
    _ = model.handle(command: .open)

    history.load()
    XCTAssertEqual(history.words.map(\.term), ["apple", "banana"])
}
```

Add this helper near existing helpers in the same test file:

```swift
@MainActor
@available(macOS 26.0, *)
private func makeDictionaryLauncherModel(dictionaryHistoryStore: DictionaryHistoryStore) -> LiquidGlassLauncherModel {
    LiquidGlassLauncherModel(
        settingsStore: SettingsStore(),
        inclusionStore: InclusionStore(),
        exclusionStore: ExclusionStore(),
        calculationHistoryStore: CalculationHistoryStore(),
        dictionaryHistoryStore: dictionaryHistoryStore,
        fileBrowserModel: FileBrowserModel(
            fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue),
            directoryStream: ImmediateDirectoryStream()
        )
    )
}
```

- [ ] **Step 2: Run dictionary model tests to verify they fail**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testBlankDictionaryModeShowsPersistedHistoryRows
```

Expected: FAIL because `LiquidGlassLauncherModel` does not accept `dictionaryHistoryStore` and does not build dictionary history rows.

- [ ] **Step 3: Inject dictionary history store**

In `Sources/Bucky/App/AppDelegate.swift`, add:

```swift
private let dictionaryHistoryStore = DictionaryHistoryStore()
```

Pass it into `LiquidGlassLauncherWindowController(...)`:

```swift
dictionaryHistoryStore: dictionaryHistoryStore,
```

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`, add a constructor parameter:

```swift
dictionaryHistoryStore: DictionaryHistoryStore,
```

and pass it into `LiquidGlassLauncherModel`.

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`, add:

```swift
private let dictionaryHistoryStore: DictionaryHistoryStore
```

Update the initializer signature:

```swift
dictionaryHistoryStore: DictionaryHistoryStore = DictionaryHistoryStore(),
```

and assign:

```swift
self.dictionaryHistoryStore = dictionaryHistoryStore
```

- [ ] **Step 4: Build dictionary history rows**

In `LiquidGlassLauncherModel`, replace the empty dictionary input branch:

```swift
guard !trimmedQuery.isEmpty else {
    return []
}
```

with:

```swift
guard !trimmedQuery.isEmpty else {
    return dictionaryHistoryItems()
}
```

Add this helper near `calculationHistoryItems(...)`:

```swift
private func dictionaryHistoryItems() -> [ToolItem] {
    dictionaryHistoryStore.words.map { entry in
        ToolItem(
            title: entry.term,
            subtitle: "Opened \(Self.calculationHistoryDateFormatter.string(from: entry.date))",
            copyText: nil,
            kind: .dictionaryHistory
        )
    }
}
```

In `applyCurrentMode`, for `.calculator, .dictionary`, add:

```swift
dictionaryHistoryStore.load()
```

right after `calculationHistoryStore.load()`.

- [ ] **Step 5: Add row removal API and activation behavior**

In `LiquidGlassLauncherModel`, add:

```swift
func removeDictionaryHistory(_ item: ToolItem) {
    guard item.kind == .dictionaryHistory else { return }
    dictionaryHistoryStore.remove(term: item.title)
    applyToolsResults(scheduleHistory: false)
}
```

In `activate(_:)`, replace the dictionary case:

```swift
case .dictionary:
    openDictionary(term: item.title)
```

with:

```swift
case .dictionary, .dictionaryHistory:
    dictionaryHistoryStore.add(term: item.title)
    openDictionary(term: item.title)
```

- [ ] **Step 6: Update row icon and action button behavior**

In `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`, update `toolSymbol(for:)`:

```swift
case .dictionaryHistory:
    return "clock.arrow.circlepath"
```

Update `toolColor(for:)`:

```swift
case .dictionary, .dictionaryHistory:
    return .mint
```

Replace `RowActionConfiguration` with:

```swift
private struct RowActionConfiguration {
    enum Action {
        case open
        case removeDictionaryHistory
    }

    let symbol: String
    let help: String
    let action: Action
}
```

Update `toolActionConfiguration(for:)`:

```swift
case .calculation, .calculationHistory:
    guard item.copyText != nil else { return nil }
    return RowActionConfiguration(symbol: "doc.on.doc", help: "Copy result", action: .open)
case .dictionary:
    return RowActionConfiguration(symbol: "book", help: "Open in Dictionary", action: .open)
case .dictionaryHistory:
    return RowActionConfiguration(symbol: "trash", help: "Remove from dictionary history", action: .removeDictionaryHistory)
case .message:
    return nil
```

In the row action button, replace:

```swift
model.selectedIndex = index
_ = model.handle(command: .open)
```

with:

```swift
model.selectedIndex = index
switch actionConfiguration.action {
case .open:
    _ = model.handle(command: .open)
case .removeDictionaryHistory:
    model.removeDictionaryHistory(item)
}
```

- [ ] **Step 7: Run dictionary model tests**

Run:

```bash
swift test --filter LauncherModeRoutingTests/testBlankDictionaryModeShowsPersistedHistoryRows
swift test --filter LauncherModeRoutingTests/testDictionaryHistoryRowCanBeRemovedIndividually
swift test --filter LauncherModeRoutingTests/testDictionaryHistoryActivationMovesTermToTop
```

Expected: PASS.

- [ ] **Step 8: Commit Task 5**

Run:

```bash
git add Sources/Bucky/App/AppDelegate.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift Tests/BuckyTests/LauncherModeRoutingTests.swift
git commit -m "feat: show dictionary history"
```

Expected: commit succeeds.

---

### Task 6: Mode Switcher Stone And Pill Motion

Correction after visual testing: use the sliding active pill model. Each mode has
a compact ordered stone slot. The active pill expands from, slides with, and
shrinks back into the selected mode's compact stone slot. Inactive stones remain
fixed in their compact slots; the active mode's own glass identity morphs between
stone and pill without rendering a second inactive stone that pushes neighboring
stones aside.

**Files:**
- Modify: `Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift`
- Modify: `Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift`

- [ ] **Step 1: Write failing animation policy tests**

In `Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift`, replace `testTextInputModesUseSharedTextPillLayout` expectations for matched geometry and outer container with:

```swift
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .applications))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .calculator))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .dictionary))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesMatchedGeometry(for: .files))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .applications))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .calculator))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .dictionary))
XCTAssertTrue(ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: .files))
```

Add this test:

```swift
func testModeSwitcherUsesStableStoneSlotsWithActivePillOverlay() throws {
    let source = try modeSwitcherSource()

    XCTAssertTrue(source.contains("GeometryReader { proxy in"))
    XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.stoneCenterX(for:"))
    XCTAssertTrue(source.contains("ModeSwitcherLayoutPolicy.activePillFrame(for:"))
    XCTAssertTrue(source.contains(".glassEffectTransition(.matchedGeometry)"))
}
```

- [ ] **Step 2: Run mode switcher tests to verify they fail**

Run:

```bash
swift test --filter ModeSwitcherLayoutPolicyTests/testTextInputModesUseSharedTextPillLayout
swift test --filter ModeSwitcherLayoutPolicyTests/testModeSwitcherUsesStableStoneSlotsWithActivePillOverlay
```

Expected: FAIL because text input modes do not use matched geometry and the stable-slot helpers do not exist.

- [ ] **Step 3: Make all modes use matched glass transitions**

In `Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift`, replace `ModeSwitcherGlassTransitionPolicy` with:

```swift
struct ModeSwitcherGlassTransitionPolicy {
    static func usesMatchedGeometry(for mode: LauncherMode) -> Bool {
        true
    }

    static func usesOuterContainer(for mode: LauncherMode) -> Bool {
        true
    }
}
```

- [ ] **Step 4: Add sliding pill layout helpers**

In `ModeSwitcherLayoutPolicy`, add:

```swift
static var inactiveStoneSlotWidth: CGFloat { activePillHeight }
static var modeSwitcherSpacing: CGFloat { 10 }

static func stoneCenterX(for mode: LauncherMode, availableWidth: CGFloat) -> CGFloat {
    inactiveStoneFrame(for: mode, availableWidth: availableWidth).midX
}

static func inactiveStoneFrame(for mode: LauncherMode, availableWidth: CGFloat) -> CGRect {
    let modes = LauncherMode.ordered
    guard let modeIndex = modes.firstIndex(of: mode) else {
        return CGRect(x: 0, y: 0, width: inactiveStoneSlotWidth, height: activePillHeight)
    }

    let slotStride = inactiveStoneSlotWidth + modeSwitcherSpacing
    return CGRect(
        x: CGFloat(modeIndex) * slotStride,
        y: 0,
        width: inactiveStoneSlotWidth,
        height: activePillHeight
    )
}

static func activePillFrame(for mode: LauncherMode, availableWidth: CGFloat) -> CGRect {
    let modes = LauncherMode.ordered
    let reservedInactiveWidth = CGFloat(modes.count - 1) * inactiveStoneSlotWidth
    let reservedSpacing = CGFloat(modes.count - 1) * modeSwitcherSpacing
    let width = max(inactiveStoneSlotWidth, availableWidth - reservedInactiveWidth - reservedSpacing)

    return CGRect(
        x: inactiveStoneFrame(for: mode, availableWidth: availableWidth).minX,
        y: 0,
        width: width,
        height: activePillHeight
    )
}
```

- [ ] **Step 5: Rework mode switcher content to a sliding active pill overlay**

Replace `modeSwitcherContent` with a slot overlay. The active pill's leading edge
uses the selected mode's compact stone frame; inactive stones stay in compact
ordered positions that do not depend on the active mode:

```swift
private var modeSwitcherContent: some View {
    GeometryReader { proxy in
        let activeFrame = ModeSwitcherLayoutPolicy.activePillFrame(for: model.mode, availableWidth: proxy.size.width)

        ZStack(alignment: .topLeading) {
            activePill(for: model.mode)
                .frame(
                    width: activeFrame.width,
                    height: ModeSwitcherLayoutPolicy.activePillHeight
                )
                .offset(x: activeFrame.minX, y: 0)

            ForEach(LauncherMode.ordered, id: \.self) { mode in
                if mode != model.mode {
                    modeOrb(for: mode)
                        .frame(
                            width: ModeSwitcherLayoutPolicy.inactiveStoneSlotWidth,
                            height: ModeSwitcherLayoutPolicy.activePillHeight
                        )
                        .position(
                            x: ModeSwitcherLayoutPolicy.stoneCenterX(for: mode, availableWidth: proxy.size.width),
                            y: ModeSwitcherLayoutPolicy.activePillHeight / 2
                        )
                        .glassEffectID(mode, in: modeGlassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
        }
        .frame(width: proxy.size.width, height: ModeSwitcherLayoutPolicy.activePillHeight)
    }
    .frame(maxWidth: .infinity, minHeight: ModeSwitcherLayoutPolicy.activePillHeight, maxHeight: ModeSwitcherLayoutPolicy.activePillHeight)
}
```

Remove `.glassEffectID` and `.glassEffectTransition` from `modeSwitcherElement(for:)` after replacing the HStack path. Delete `modeSwitcherElement(for:)` when the compiler reports it as unused.

- [ ] **Step 6: Keep text field foreground outside the moving glass identity**

Change `TextInputModePill` to receive the namespace:

```swift
private struct TextInputModePill: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    let mode: LauncherMode
    let symbol: String
    let glassNamespace: Namespace.ID
    @FocusState.Binding var isSearchFocused: Bool
```

Pass it from `activePill(for:)`:

```swift
TextInputModePill(
    model: model,
    mode: mode,
    symbol: symbol(for: mode),
    glassNamespace: modeGlassNamespace,
    isSearchFocused: $isSearchFocused
)
```

Apply the matched identity only to the background glass surface:

```swift
.background {
    TextInputPillGlassSurface(tint: LauncherModeTintPolicy.activeColor(for: mode))
        .glassEffectID(mode, in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
}
```

Keep `TextInputPillForegroundLayer` outside that background block so the `TextField` remains outside the moving glass identity.

- [ ] **Step 7: Run mode switcher tests**

Run:

```bash
swift test --filter ModeSwitcherLayoutPolicyTests
```

Expected: PASS after updating source-based tests that still assert text input modes opt out of glass identity.

- [ ] **Step 8: Commit Task 6**

Run:

```bash
git add Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift
git commit -m "feat: morph mode stones and pills"
```

Expected: commit succeeds.

---

### Task 7: Full Verification And App Build

**Files:**
- No code files unless previous tasks reveal compile errors.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build the app bundle**

Run:

```bash
make bundle
```

Expected: exits `0` and creates `build/Bucky.app`.

- [ ] **Step 3: Manual smoke test native behaviors**

Run:

```bash
open build/Bucky.app
```

Expected:

- Option+Space opens Bucky.
- Calculator accepts `2+2=` and keeps the live `4` row visible while typing.
- Pasting text into Applications, Calculator, and Dictionary inputs works.
- Dictionary Enter on a result stores the word; blank Dictionary mode shows history; the row trash button removes one word.
- Files mode multi-select drag exports all selected file URLs when dragging a selected row.
- Mode switcher active pill expands from and shrinks back to the selected mode's compact stone slot while inactive stones remain fixed in compact ordered positions.

- [ ] **Step 4: Commit verification fixes only if needed**

If Step 1 or Step 2 required compile/test fixes, commit those fixes:

```bash
git add Sources Tests
git commit -m "fix: complete refinement integration"
```

Expected: commit succeeds only when there are actual verification fixes.

---

## Self-Review Checklist

- Spec coverage:
  - Calculator trailing `=`: Task 1.
  - Calculator live row scroll: Task 1.
  - Native text copy/paste: Task 2.
  - File drag respects multi-selection across directories: Task 3.
  - Persisted deduped dictionary history with row clearing: Tasks 4 and 5.
  - Sliding active pill anchored to each mode's compact stone slot, with inactive stone slots independent of the active mode: Task 6.
  - Full tests and app build: Task 7.
- Placeholder scan: no placeholder tasks remain.
- Type consistency:
  - `DictionaryHistoryStore(fileURL:)` is introduced before tests depend on persisted dictionary history.
  - `ToolItem.Kind.dictionaryHistory` is introduced before model and view switch statements use it.
  - `FileBrowserDragPolicy.draggedURLs(for:selectedURLs:)` is introduced before `FileBrowserView` uses it.
