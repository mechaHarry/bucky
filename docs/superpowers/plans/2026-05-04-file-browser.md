# File Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a keyboard-driven native Files mode with Liquid Glass mode orbs, file browsing, pinned directories, multi-selection, staged file operations, and held-Space Quick Look-style previews.

**Architecture:** Keep file browsing isolated from the launcher search/tools logic. Add a testable Files domain under `Sources/Bucky/Files`, bridge OS-specific behavior through `MacFileServices`, and let SwiftUI render model state through focused views.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Foundation `FileManager`, XCTest, macOS 26 Liquid Glass APIs.

---

## Corrective Requirement Note

The latest requirement supersedes older plan snippets that show `LiquidGlassLauncherModel` eagerly owning `@Published var fileBrowserModel: FileBrowserModel` or `FileBrowserModel` reading directories directly from `FileSystemClient`. Apps remains the default view, and Apps/Calculator/Dictionary must not instantiate `FileBrowserModel` or touch file I/O. Files activates lazily through a `fileBrowserModelFactory`, and directory population flows through `FileBrowserDirectoryStreaming` so SwiftUI observes stable loading, empty, and loaded snapshots with stale-result generation checks.

## Baseline

- Current branch: `file-browser`
- Approved design: `docs/superpowers/specs/2026-05-04-file-browser-design.md`
- Baseline verification run: `swift test`
- Baseline result: 16 tests passed, 0 failures

## File Structure

Create:

- `Sources/Bucky/Files/FileBrowserModels.swift`: value types and enums for entries, sorting, focus state, actions, selections, pending operations, and confirmations.
- `Sources/Bucky/Files/FileSystemClient.swift`: directory enumeration, metadata loading, sorting, parent/child path helpers.
- `Sources/Bucky/Files/FileBrowserStore.swift`: JSON persistence for pins, last directory, sort mode, and traversal chain.
- `Sources/Bucky/Files/MacFileServices.swift`: AppKit/Foundation wrapper for open, reveal, pasteboard, copy, move, trash, conflict naming, and native icons.
- `Sources/Bucky/Files/FileBrowserModel.swift`: state machine for navigation, selection, focus, actions, transfer staging, confirmations, persistence, and stable stream-backed directory snapshots.
- `Sources/Bucky/Files/FileBrowserDirectoryStream.swift`: stream/shim boundary between file-browser state and filesystem enumeration.
- `Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift`: top Liquid Glass mode orbs and active pill shell.
- `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`: pinned rail, gliding columns, rows, overlays, transfer state, confirmations, and preview surface.
- `Sources/Bucky/UI/SwiftUI/FadeMarqueeText.swift`: reusable overflow text component for path and row labels.
- `Tests/BuckyTests/FileSystemClientTests.swift`
- `Tests/BuckyTests/FileBrowserStoreTests.swift`
- `Tests/BuckyTests/FileBrowserModelTests.swift`
- `Tests/BuckyTests/MacFileServicesTests.swift`
- `Tests/BuckyTests/LauncherModeRoutingTests.swift`

Modify:

- `Sources/Bucky/Models/CoreModels.swift`: expand `LauncherMode`.
- `Sources/Bucky/UI/Shared/LauncherCommand.swift`: add mode, file navigation, file selection, preview, and action commands.
- `Sources/Bucky/UI/Shared/Utilities.swift`: add command-number and file-key event helpers.
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`: lazily activates `FileBrowserModel`, mode routing, and query ownership for calculator/dictionary.
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`: replace header with `ModeSwitcherView` and route Files body to `FileBrowserView`.
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`: route `Cmd+1...4`, arrows, Return, Escape, Space down/up, Shift+Space, and alphanumeric events to the model.
- `Sources/Bucky/UI/SwiftUI/ToolResultsSnapshotPolicy.swift`: update for split calculator/dictionary modes.
- `packaging/Info.plist`: bump `CFBundleShortVersionString` to `3.0.0`.

## Task 1: Launcher Mode Routing

**Files:**
- Modify: `Sources/Bucky/Models/CoreModels.swift`
- Modify: `Sources/Bucky/UI/Shared/LauncherCommand.swift`
- Modify: `Sources/Bucky/UI/Shared/Utilities.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/ToolResultsSnapshotPolicy.swift`
- Test: `Tests/BuckyTests/LauncherModeRoutingTests.swift`
- Test: `Tests/BuckyTests/ToolResultsSnapshotPolicyTests.swift`

- [ ] **Step 1: Write failing launcher mode routing tests**

Create `Tests/BuckyTests/LauncherModeRoutingTests.swift`:

```swift
import XCTest
@testable import Bucky

final class LauncherModeRoutingTests: XCTestCase {
    func testLauncherModesAreOrderedForCommandShortcuts() {
        XCTAssertEqual(LauncherMode.ordered, [
            .applications,
            .calculator,
            .dictionary,
            .files
        ])
    }

    func testCommandShortcutNumbersResolveModes() {
        XCTAssertEqual(LauncherMode(commandNumber: 1), .applications)
        XCTAssertEqual(LauncherMode(commandNumber: 2), .calculator)
        XCTAssertEqual(LauncherMode(commandNumber: 3), .dictionary)
        XCTAssertEqual(LauncherMode(commandNumber: 4), .files)
        XCTAssertNil(LauncherMode(commandNumber: 5))
    }

    func testModePlaceholdersAreSeparated() {
        XCTAssertEqual(LauncherMode.applications.placeholder, "Search Apps Here")
        XCTAssertEqual(LauncherMode.calculator.placeholder, "Perform Calculations Here")
        XCTAssertEqual(LauncherMode.dictionary.placeholder, "Search Dictionary Here")
        XCTAssertEqual(LauncherMode.files.placeholder, "Browse Files")
    }
}
```

Update `Tests/BuckyTests/ToolResultsSnapshotPolicyTests.swift` assertions that reference `.tools`:

```swift
func testCalculatorQueriesUpdateImmediately() {
    XCTAssertEqual(
        ToolResultsSnapshotPolicy.update(for: .calculator, query: "2 + 2"),
        .immediate
    )
}

func testDictionaryQueriesUpdateImmediately() {
    XCTAssertEqual(
        ToolResultsSnapshotPolicy.update(for: .dictionary, query: "hello"),
        .immediate
    )
}

func testDictionaryToolSnapshotsUseSubtleAnimation() {
    let items = [
        ToolItem(title: "hello", subtitle: "A greeting", copyText: nil, kind: .dictionary)
    ]

    XCTAssertEqual(
        ToolResultsSnapshotPolicy.animation(for: .dictionary, items: items),
        .subtle
    )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter LauncherModeRoutingTests
swift test --filter ToolResultsSnapshotPolicyTests
```

Expected: `LauncherMode.ordered`, `LauncherMode(commandNumber:)`, `.calculator`, `.dictionary`, and `.files` are missing.

- [ ] **Step 3: Implement mode and command primitives**

Change `Sources/Bucky/Models/CoreModels.swift`:

```swift
enum LauncherMode: Int, CaseIterable {
    case applications = 1
    case calculator = 2
    case dictionary = 3
    case files = 4

    static let ordered: [LauncherMode] = [.applications, .calculator, .dictionary, .files]

    init?(commandNumber: Int) {
        self.init(rawValue: commandNumber)
    }

    var placeholder: String {
        switch self {
        case .applications:
            return "Search Apps Here"
        case .calculator:
            return "Perform Calculations Here"
        case .dictionary:
            return "Search Dictionary Here"
        case .files:
            return "Browse Files"
        }
    }
}
```

Change `Sources/Bucky/UI/Shared/LauncherCommand.swift`:

```swift
enum LauncherCommand {
    case up
    case down
    case left
    case right
    case top
    case bottom
    case open
    case close
    case reindex
    case settings
    case switchMode(LauncherMode)
    case clearHistory
    case togglePin
    case space
    case shiftSpace
    case beginSpaceHold
    case endSpaceHold
    case alphaNumeric(Character)
}
```

Add to `Sources/Bucky/UI/Shared/Utilities.swift`:

```swift
extension NSEvent {
    var commandNumberMode: LauncherMode? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              let charactersIgnoringModifiers,
              let number = Int(charactersIgnoringModifiers) else {
            return nil
        }
        return LauncherMode(commandNumber: number)
    }

    var firstAlphaNumericCharacter: Character? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty,
              let charactersIgnoringModifiers,
              let character = charactersIgnoringModifiers.first,
              character.isLetter || character.isNumber else {
            return nil
        }
        return character
    }
}
```

Change `Sources/Bucky/UI/SwiftUI/ToolResultsSnapshotPolicy.swift`:

```swift
enum ToolResultsSnapshotPolicy {
    enum Update: Equatable {
        case immediate
    }

    enum Animation: Equatable {
        case none
        case subtle
    }

    static func update(for _: LauncherMode, query _: String) -> Update {
        .immediate
    }

    static func animation(for mode: LauncherMode, items: [ToolItem]) -> Animation {
        guard mode == .dictionary,
              items.contains(where: { $0.kind == .dictionary }) else {
            return .none
        }

        return .subtle
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run:

```bash
swift test --filter LauncherModeRoutingTests
swift test --filter ToolResultsSnapshotPolicyTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Bucky/Models/CoreModels.swift Sources/Bucky/UI/Shared/LauncherCommand.swift Sources/Bucky/UI/Shared/Utilities.swift Sources/Bucky/UI/SwiftUI/ToolResultsSnapshotPolicy.swift Tests/BuckyTests/LauncherModeRoutingTests.swift Tests/BuckyTests/ToolResultsSnapshotPolicyTests.swift
git commit -m "feat: split launcher modes"
```

## Task 2: File System Client

**Files:**
- Create: `Sources/Bucky/Files/FileBrowserModels.swift`
- Create: `Sources/Bucky/Files/FileSystemClient.swift`
- Test: `Tests/BuckyTests/FileSystemClientTests.swift`

- [ ] **Step 1: Write failing file system tests**

Create `Tests/BuckyTests/FileSystemClientTests.swift`:

```swift
import XCTest
@testable import Bucky

final class FileSystemClientTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyFileSystemClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDirectoryEntriesIncludeHiddenFilesByDefault() throws {
        try "visible".write(to: temporaryDirectory.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: temporaryDirectory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name)

        XCTAssertEqual(entries.map(\.name), [".env", "visible.txt"])
        XCTAssertEqual(entries.first?.kind, .file)
    }

    func testDirectoriesSortBeforeFilesByName() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "readme".write(to: temporaryDirectory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .name)

        XCTAssertEqual(entries.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(entries.first?.kind, .directory)
    }

    func testSortBySizeOrdersFilesDescendingAfterDirectories() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try "12345".write(to: temporaryDirectory.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        try "1".write(to: temporaryDirectory.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)

        let entries = try FileSystemClient().entries(in: temporaryDirectory, sort: .size)

        XCTAssertEqual(entries.map(\.name), ["Folder", "large.txt", "small.txt"])
    }

    func testParentURLStopsAtRoot() {
        let client = FileSystemClient()

        XCTAssertEqual(client.parentURL(for: URL(fileURLWithPath: "/Users/harriche")), URL(fileURLWithPath: "/Users"))
        XCTAssertNil(client.parentURL(for: URL(fileURLWithPath: "/")))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FileSystemClientTests
```

Expected: fails because `FileSystemClient`, `FileBrowserEntry`, `FileBrowserSort`, and `FileBrowserEntry.Kind` do not exist.

- [ ] **Step 3: Create core file browser models**

Create `Sources/Bucky/Files/FileBrowserModels.swift`:

```swift
import Foundation

struct FileBrowserEntry: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case file
        case directory
        case package
        case symbolicLink
        case other
    }

    let id: URL
    let url: URL
    let name: String
    let kind: Kind
    let size: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let isHidden: Bool

    init(
        url: URL,
        kind: Kind,
        size: Int64?,
        createdAt: Date?,
        modifiedAt: Date?,
        isHidden: Bool
    ) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
    }
}

enum FileBrowserSort: String, Codable, CaseIterable, Hashable {
    case name
    case dateCreated
    case dateModified
    case size
}

struct FileBrowserDirectorySnapshot: Equatable {
    let directory: URL
    let entries: [FileBrowserEntry]
}
```

- [ ] **Step 4: Create `FileSystemClient`**

Create `Sources/Bucky/Files/FileSystemClient.swift`:

```swift
import Foundation

struct FileSystemClient {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func homeDirectory() -> URL {
        fileManager.homeDirectoryForCurrentUser
    }

    func parentURL(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        guard parent.path != standardized.path else { return nil }
        return parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        return urls
            .map { url in
                let values = try url.resourceValues(forKeys: resourceKeys)
                return FileBrowserEntry(
                    url: url.standardizedFileURL,
                    kind: kind(for: values),
                    size: values.fileSize.map(Int64.init),
                    createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate,
                    isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix(".")
                )
            }
            .sorted { lhs, rhs in
                compare(lhs, rhs, sort: sort)
            }
    }

    private func kind(for values: URLResourceValues) -> FileBrowserEntry.Kind {
        if values.isSymbolicLink == true {
            return .symbolicLink
        }
        if values.isPackage == true {
            return .package
        }
        if values.isDirectory == true {
            return .directory
        }
        return .file
    }

    private func compare(_ lhs: FileBrowserEntry, _ rhs: FileBrowserEntry, sort: FileBrowserSort) -> Bool {
        if lhs.kind == .directory, rhs.kind != .directory { return true }
        if lhs.kind != .directory, rhs.kind == .directory { return false }

        switch sort {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .dateCreated:
            return date(lhs.createdAt, isOrderedBefore: rhs.createdAt, fallbackLeft: lhs.name, fallbackRight: rhs.name)
        case .dateModified:
            return date(lhs.modifiedAt, isOrderedBefore: rhs.modifiedAt, fallbackLeft: lhs.name, fallbackRight: rhs.name)
        case .size:
            if (lhs.size ?? -1) == (rhs.size ?? -1) {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return (lhs.size ?? -1) > (rhs.size ?? -1)
        }
    }

    private func date(_ lhs: Date?, isOrderedBefore rhs: Date?, fallbackLeft: String, fallbackRight: String) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs
        default:
            return fallbackLeft.localizedStandardCompare(fallbackRight) == .orderedAscending
        }
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
swift test --filter FileSystemClientTests
```

Expected: all `FileSystemClientTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/Files/FileBrowserModels.swift Sources/Bucky/Files/FileSystemClient.swift Tests/BuckyTests/FileSystemClientTests.swift
git commit -m "feat: add file system browser client"
```

## Task 3: File Browser Persistence

**Files:**
- Modify: `Sources/Bucky/Files/FileBrowserModels.swift`
- Create: `Sources/Bucky/Files/FileBrowserStore.swift`
- Test: `Tests/BuckyTests/FileBrowserStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/BuckyTests/FileBrowserStoreTests.swift`:

```swift
import XCTest
@testable import Bucky

final class FileBrowserStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyFileBrowserStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileURL = temporaryDirectory.appendingPathComponent("file-browser.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testMissingFileLoadsDefaultState() {
        let store = FileBrowserStore(fileURL: fileURL)

        XCTAssertEqual(store.state, .defaultValue)
    }

    func testInvalidJSONFallsBackToDefaultState() throws {
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = FileBrowserStore(fileURL: fileURL)

        XCTAssertEqual(store.state, .defaultValue)
    }

    func testSaveAndReloadPersistsPinsLastDirectorySortAndTraversalChain() {
        let store = FileBrowserStore(fileURL: fileURL)
        let state = FileBrowserPersistedState(
            pinnedDirectories: [URL(fileURLWithPath: "/Users/harriche")],
            lastDirectory: URL(fileURLWithPath: "/Users/harriche/Projects"),
            sort: .dateModified,
            traversalChain: [URL(fileURLWithPath: "/Users"), URL(fileURLWithPath: "/Users/harriche")]
        )

        store.update(state)

        let reloaded = FileBrowserStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.state, state)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FileBrowserStoreTests
```

Expected: fails because `FileBrowserPersistedState` and `FileBrowserStore` do not exist.

- [ ] **Step 3: Add persisted state model**

Append to `Sources/Bucky/Files/FileBrowserModels.swift`:

```swift
struct FileBrowserPersistedState: Codable, Equatable {
    var pinnedDirectories: [URL]
    var lastDirectory: URL?
    var sort: FileBrowserSort
    var traversalChain: [URL]

    static let defaultValue = FileBrowserPersistedState(
        pinnedDirectories: [],
        lastDirectory: nil,
        sort: .name,
        traversalChain: []
    )
}
```

- [ ] **Step 4: Create store**

Create `Sources/Bucky/Files/FileBrowserStore.swift`:

```swift
import Foundation

final class FileBrowserStore {
    private let fileManager: FileManager
    private(set) var state: FileBrowserPersistedState
    let fileURL: URL

    init(
        fileURL: URL = BuckyPaths.appSupportDirectory.appendingPathComponent("file-browser.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.state = .defaultValue
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            state = .defaultValue
            return
        }

        do {
            state = try JSONDecoder().decode(FileBrowserPersistedState.self, from: data)
        } catch {
            NSLog("Bucky could not read file browser state at %@: %@", fileURL.path, error.localizedDescription)
            state = .defaultValue
        }
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
        save()
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Bucky could not save file browser state at %@: %@", fileURL.path, error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
swift test --filter FileBrowserStoreTests
```

Expected: all `FileBrowserStoreTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/Files/FileBrowserModels.swift Sources/Bucky/Files/FileBrowserStore.swift Tests/BuckyTests/FileBrowserStoreTests.swift
git commit -m "feat: persist file browser state"
```

## Task 4: File Browser Model Navigation And Selection

**Files:**
- Modify: `Sources/Bucky/Files/FileBrowserModels.swift`
- Create: `Sources/Bucky/Files/FileBrowserModel.swift`
- Test: `Tests/BuckyTests/FileBrowserModelTests.swift`

- [ ] **Step 1: Write failing model tests for navigation and selection**

Create `Tests/BuckyTests/FileBrowserModelTests.swift`:

```swift
import XCTest
@testable import Bucky

@MainActor
final class FileBrowserModelTests: XCTestCase {
    func testStartsAtPersistedDirectoryWhenAvailable() {
        let directory = URL(fileURLWithPath: "/Users/harriche")
        let model = makeModel(persisted: FileBrowserPersistedState(
            pinnedDirectories: [],
            lastDirectory: directory,
            sort: .name,
            traversalChain: []
        ))

        XCTAssertEqual(model.currentDirectory, directory)
        XCTAssertEqual(model.sort, .name)
    }

    func testStartsAtHomeWhenPersistedDirectoryIsMissing() {
        let model = makeModel(persisted: .defaultValue, home: URL(fileURLWithPath: "/Users/harriche"))

        XCTAssertEqual(model.currentDirectory, URL(fileURLWithPath: "/Users/harriche"))
    }

    func testMoveSelectionClampsToEntryBounds() {
        let model = makeModel(entries: entries(["a.txt", "b.txt", "c.txt"]))

        model.handle(.down)
        model.handle(.down)
        model.handle(.down)
        XCTAssertEqual(model.selectedEntry?.name, "c.txt")

        model.handle(.up)
        XCTAssertEqual(model.selectedEntry?.name, "b.txt")
    }

    func testFirstCharacterCyclingMovesBetweenMatchingRows() {
        let model = makeModel(entries: entries(["alpha.txt", "beta.txt", "build.log", "gamma.txt"]))

        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "beta.txt")
        model.handle(.alphaNumeric("b"))
        XCTAssertEqual(model.selectedEntry?.name, "build.log")
    }

    func testSpaceTogglesSelectionAndShiftSpaceSelectsRange() {
        let model = makeModel(entries: entries(["one.txt", "two.txt", "three.txt", "four.txt"]))

        model.handle(.space)
        model.handle(.down)
        model.handle(.down)
        model.handle(.shiftSpace)

        XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["one.txt", "two.txt", "three.txt"])
    }

    func testRightOnFileSetsPaneWobble() {
        let model = makeModel(entries: entries(["file.txt"]))

        model.handle(.right)

        XCTAssertEqual(model.wobbleReason, .cannotEnterFile)
    }

    private func makeModel(
        entries: [FileBrowserEntry] = [],
        persisted: FileBrowserPersistedState = .defaultValue,
        home: URL = URL(fileURLWithPath: "/Users/test")
    ) -> FileBrowserModel {
        let client = StubFileSystemClient(home: home, entriesByDirectory: [home: entries])
        let store = InMemoryFileBrowserStore(state: persisted)
        return FileBrowserModel(fileSystem: client, store: store)
    }

    private func entries(_ names: [String]) -> [FileBrowserEntry] {
        names.map { name in
            FileBrowserEntry(
                url: URL(fileURLWithPath: "/Users/test").appendingPathComponent(name),
                kind: name.hasSuffix("/") ? .directory : .file,
                size: 1,
                createdAt: nil,
                modifiedAt: nil,
                isHidden: name.hasPrefix(".")
            )
        }
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter FileBrowserModelTests
```

Expected: fails because the model, protocols, stubs, focus state, and selection APIs do not exist.

- [ ] **Step 3: Add protocols and model state types**

Append to `Sources/Bucky/Files/FileBrowserModels.swift`:

```swift
protocol FileSystemClientProtocol {
    func homeDirectory() -> URL
    func parentURL(for url: URL) -> URL?
    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry]
}

extension FileSystemClient: FileSystemClientProtocol {}

protocol FileBrowserPersisting: AnyObject {
    var state: FileBrowserPersistedState { get }
    func update(_ nextState: FileBrowserPersistedState)
}

extension FileBrowserStore: FileBrowserPersisting {}

enum FileBrowserFocusState: Equatable {
    case browse
    case previewActions
    case renaming
    case transferPending(FileBrowserTransfer)
    case confirming(FileBrowserConfirmation)
    case quickLook(URL)
}

enum FileBrowserAction: String, CaseIterable, Equatable {
    case open
    case rename
    case batchRename
    case revealInFinder
    case copyPath
    case copyPaths
    case copy
    case move
    case moveToTrash
}

enum FileBrowserTransfer: Equatable {
    case copy([URL])
    case move([URL])
}

enum FileBrowserConfirmation: Equatable {
    case transfer(FileBrowserTransfer, destination: URL)
    case trash([URL], step: Int)
    case conflict(source: URL, destination: URL)
}

enum FileBrowserWobbleReason: Equatable {
    case cannotEnterFile
    case noParentDirectory
}
```

Add test stubs at the bottom of `Tests/BuckyTests/FileBrowserModelTests.swift`:

```swift
private struct StubFileSystemClient: FileSystemClientProtocol {
    let home: URL
    var entriesByDirectory: [URL: [FileBrowserEntry]]

    func homeDirectory() -> URL { home }

    func parentURL(for url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    func entries(in directory: URL, sort: FileBrowserSort) throws -> [FileBrowserEntry] {
        entriesByDirectory[directory] ?? []
    }
}

private final class InMemoryFileBrowserStore: FileBrowserPersisting {
    private(set) var state: FileBrowserPersistedState

    init(state: FileBrowserPersistedState) {
        self.state = state
    }

    func update(_ nextState: FileBrowserPersistedState) {
        state = nextState
    }
}
```

- [ ] **Step 4: Create minimal `FileBrowserModel`**

Create `Sources/Bucky/Files/FileBrowserModel.swift`:

```swift
import Foundation

@MainActor
final class FileBrowserModel: ObservableObject {
    @Published private(set) var currentDirectory: URL
    @Published private(set) var entries: [FileBrowserEntry] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var selectedURLs: [URL] = []
    @Published private(set) var focusState: FileBrowserFocusState = .browse
    @Published private(set) var wobbleReason: FileBrowserWobbleReason?
    @Published private(set) var sort: FileBrowserSort

    private let fileSystem: FileSystemClientProtocol
    private let store: FileBrowserPersisting
    private var selectionAnchor: Int?
    private var recentTraversalChain: [URL]

    var selectedEntry: FileBrowserEntry? {
        guard selectedIndex >= 0, selectedIndex < entries.count else { return nil }
        return entries[selectedIndex]
    }

    init(fileSystem: FileSystemClientProtocol = FileSystemClient(), store: FileBrowserPersisting = FileBrowserStore()) {
        self.fileSystem = fileSystem
        self.store = store
        self.sort = store.state.sort
        self.recentTraversalChain = store.state.traversalChain
        self.currentDirectory = store.state.lastDirectory ?? fileSystem.homeDirectory()
        reloadEntries()
    }

    func handle(_ command: LauncherCommand) {
        switch command {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        case .left:
            moveToParent()
        case .right:
            enterSelectedDirectoryOrWobble()
        case .space:
            toggleSelection()
        case .shiftSpace:
            rangeSelect()
        case let .alphaNumeric(character):
            cycle(toFirstCharacter: character)
        case .beginSpaceHold:
            beginQuickLook()
        case .endSpaceHold:
            endQuickLook()
        case .open:
            focusState = .previewActions
        case .close:
            closeFocusedState()
        default:
            break
        }
    }

    private func reloadEntries() {
        do {
            entries = try fileSystem.entries(in: currentDirectory, sort: sort)
            selectedIndex = entries.isEmpty ? 0 : min(selectedIndex, entries.count - 1)
            pruneStaleSelections()
            persist()
        } catch {
            entries = []
        }
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = max(0, min(entries.count - 1, selectedIndex + delta))
    }

    private func moveToParent() {
        guard let parent = fileSystem.parentURL(for: currentDirectory) else {
            wobbleReason = .noParentDirectory
            return
        }
        recentTraversalChain.insert(currentDirectory, at: 0)
        currentDirectory = parent
        selectedIndex = 0
        reloadEntries()
    }

    private func enterSelectedDirectoryOrWobble() {
        guard let entry = selectedEntry, entry.kind == .directory else {
            wobbleReason = .cannotEnterFile
            return
        }
        currentDirectory = entry.url
        selectedIndex = 0
        reloadEntries()
    }

    private func toggleSelection() {
        guard let url = selectedEntry?.url else { return }
        if selectedURLs.contains(url) {
            selectedURLs.removeAll { $0 == url }
        } else {
            selectedURLs.append(url)
        }
        selectionAnchor = selectedIndex
    }

    private func rangeSelect() {
        guard !entries.isEmpty else { return }
        let anchor = selectionAnchor ?? selectedIndex
        let bounds = min(anchor, selectedIndex)...max(anchor, selectedIndex)
        let urls = bounds.map { entries[$0].url }
        selectedURLs = Array(Set(selectedURLs + urls)).sorted { $0.path < $1.path }
    }

    private func cycle(toFirstCharacter character: Character) {
        guard !entries.isEmpty else { return }
        let needle = String(character).lowercased()
        let start = min(selectedIndex + 1, entries.count)
        let orderedIndexes = Array(start..<entries.count) + Array(0..<start)
        if let match = orderedIndexes.first(where: { entries[$0].name.lowercased().hasPrefix(needle) }) {
            selectedIndex = match
        }
    }

    private func beginQuickLook() {
        guard let url = selectedEntry?.url else { return }
        focusState = .quickLook(url)
    }

    private func endQuickLook() {
        if case .quickLook = focusState {
            focusState = .browse
        }
    }

    private func closeFocusedState() {
        focusState = .browse
    }

    private func pruneStaleSelections() {
        let validURLs = Set(entries.map(\.url))
        selectedURLs.removeAll { !validURLs.contains($0) && $0.deletingLastPathComponent() == currentDirectory }
    }

    private func persist() {
        store.update(FileBrowserPersistedState(
            pinnedDirectories: store.state.pinnedDirectories,
            lastDirectory: currentDirectory,
            sort: sort,
            traversalChain: recentTraversalChain
        ))
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
swift test --filter FileBrowserModelTests
```

Expected: all current `FileBrowserModelTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/Files/FileBrowserModels.swift Sources/Bucky/Files/FileBrowserModel.swift Tests/BuckyTests/FileBrowserModelTests.swift
git commit -m "feat: add file browser navigation model"
```

## Task 5: File Browser Actions, Transfers, Pins, And Path Memory

**Files:**
- Modify: `Sources/Bucky/Files/FileBrowserModel.swift`
- Modify: `Sources/Bucky/Files/FileBrowserModels.swift`
- Test: `Tests/BuckyTests/FileBrowserModelTests.swift`

- [ ] **Step 1: Add failing action and path memory tests**

Append to `FileBrowserModelTests`:

```swift
func testActionAvailabilityChangesForSingleAndMultipleSelections() {
    let model = makeModel(entries: entries(["one.txt", "two.txt"]))

    model.handle(.space)
    XCTAssertEqual(model.availableActions, [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash])

    model.handle(.down)
    model.handle(.shiftSpace)
    XCTAssertEqual(model.availableActions, [.batchRename, .copyPaths, .copy, .move, .moveToTrash])
}

func testActionOverlayKeyboardSelectionAndReturnStartsFocusedAction() {
    let model = makeModel(entries: entries(["one.txt"]))

    model.handle(.space)
    model.handle(.open)
    model.handle(.down)
    model.handle(.down)
    model.handle(.down)
    model.handle(.open)

    XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))
}

func testCopyMoveStagePayloadAndEscapeCancelsBackToActions() {
    let model = makeModel(entries: entries(["one.txt"]))

    model.handle(.space)
    model.startTransfer(.copy)
    XCTAssertEqual(model.focusState, .transferPending(.copy(model.selectedURLs)))

    model.handle(.close)
    XCTAssertEqual(model.focusState, .previewActions)
}

func testReturnDuringTransferAsksForDestinationConfirmation() {
    let model = makeModel(entries: entries(["one.txt"]))

    model.handle(.space)
    model.startTransfer(.move)
    model.handle(.open)

    XCTAssertEqual(model.focusState, .confirming(.transfer(.move(model.selectedURLs), destination: model.currentDirectory)))
}

func testMoveToTrashUsesDoubleConfirmState() {
    let model = makeModel(entries: entries(["one.txt"]))

    model.handle(.space)
    model.requestTrashConfirmation()

    XCTAssertEqual(model.focusState, .confirming(.trash(model.selectedURLs, step: 1)))
    model.confirmTrashStep()
    XCTAssertEqual(model.focusState, .confirming(.trash(model.selectedURLs, step: 2)))
}

func testPinsPersist() {
    let model = makeModel()
    let pin = URL(fileURLWithPath: "/Users/test/Projects")

    model.togglePin(pin)

    XCTAssertEqual(model.pinnedDirectories, [pin])
}

func testRightRestoresRememberedTraversalChainAfterMovingLeft() {
    let home = URL(fileURLWithPath: "/Users/test")
    let child = home.appendingPathComponent("Projects", isDirectory: true)
    let client = StubFileSystemClient(
        home: home,
        entriesByDirectory: [
            home: [directoryEntry(child)],
            child: []
        ]
    )
    let store = InMemoryFileBrowserStore(state: .defaultValue)
    let model = FileBrowserModel(fileSystem: client, store: store)

    model.handle(.right)
    model.handle(.left)
    model.handle(.right)

    XCTAssertEqual(model.currentDirectory, child)
}

private func directoryEntry(_ url: URL) -> FileBrowserEntry {
    FileBrowserEntry(url: url, kind: .directory, size: nil, createdAt: nil, modifiedAt: nil, isHidden: false)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FileBrowserModelTests
```

Expected: failures for missing action APIs, transfer behavior, trash behavior, pins, and path-memory restoration.

- [ ] **Step 3: Add action intent type**

Append to `FileBrowserModels.swift`:

```swift
enum FileBrowserTransferKind {
    case copy
    case move
}
```

- [ ] **Step 4: Implement model action APIs**

Add to `FileBrowserModel`:

```swift
@Published private(set) var pinnedDirectories: [URL] = []
@Published private(set) var focusedActionIndex = 0

var activeSelectionURLs: [URL] {
    if selectedURLs.isEmpty, let url = selectedEntry?.url {
        return [url]
    }
    return selectedURLs
}

var availableActions: [FileBrowserAction] {
    activeSelectionURLs.count > 1
        ? [.batchRename, .copyPaths, .copy, .move, .moveToTrash]
        : [.open, .rename, .revealInFinder, .copyPath, .copy, .move, .moveToTrash]
}

func startTransfer(_ kind: FileBrowserTransferKind) {
    let urls = activeSelectionURLs
    guard !urls.isEmpty else { return }
    switch kind {
    case .copy:
        focusState = .transferPending(.copy(urls))
    case .move:
        focusState = .transferPending(.move(urls))
    }
}

func performFocusedAction() {
    guard focusState == .previewActions else { return }
    let action = availableActions[max(0, min(availableActions.count - 1, focusedActionIndex))]
    switch action {
    case .copy:
        startTransfer(.copy)
    case .move:
        startTransfer(.move)
    case .moveToTrash:
        requestTrashConfirmation()
    default:
        focusState = .previewActions
    }
}

func moveFocusedAction(by delta: Int) {
    guard focusState == .previewActions, !availableActions.isEmpty else { return }
    focusedActionIndex = max(0, min(availableActions.count - 1, focusedActionIndex + delta))
}

func requestTrashConfirmation() {
    let urls = activeSelectionURLs
    guard !urls.isEmpty else { return }
    focusState = .confirming(.trash(urls, step: 1))
}

func confirmTrashStep() {
    guard case let .confirming(.trash(urls, step)) = focusState else { return }
    focusState = .confirming(.trash(urls, step: min(step + 1, 2)))
}

func togglePin(_ url: URL) {
    if pinnedDirectories.contains(url) {
        pinnedDirectories.removeAll { $0 == url }
    } else {
        pinnedDirectories.append(url)
    }
    persist()
}
```

Update initializer:

```swift
self.pinnedDirectories = store.state.pinnedDirectories
```

Update `.open` handling:

```swift
case .open:
    if focusState == .previewActions {
        performFocusedAction()
    } else if case let .transferPending(transfer) = focusState {
        focusState = .confirming(.transfer(transfer, destination: currentDirectory))
    } else {
        focusedActionIndex = 0
        focusState = .previewActions
    }
```

Update `.up` and `.down` handling before browse selection movement:

```swift
case .up:
    if focusState == .previewActions {
        moveFocusedAction(by: -1)
    } else {
        moveSelection(by: -1)
    }
case .down:
    if focusState == .previewActions {
        moveFocusedAction(by: 1)
    } else {
        moveSelection(by: 1)
    }
```

Update `.close` handling:

```swift
private func closeFocusedState() {
    switch focusState {
    case .transferPending:
        focusState = .previewActions
    default:
        focusState = .browse
    }
}
```

Update `enterSelectedDirectoryOrWobble` before checking selected entry:

```swift
if let remembered = recentTraversalChain.first,
   entries.contains(where: { $0.url == remembered && $0.kind == .directory }) {
    recentTraversalChain.removeFirst()
    currentDirectory = remembered
    selectedIndex = 0
    reloadEntries()
    return
}
```

Update `persist()`:

```swift
store.update(FileBrowserPersistedState(
    pinnedDirectories: pinnedDirectories,
    lastDirectory: currentDirectory,
    sort: sort,
    traversalChain: recentTraversalChain
))
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
swift test --filter FileBrowserModelTests
```

Expected: all `FileBrowserModelTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/Files/FileBrowserModels.swift Sources/Bucky/Files/FileBrowserModel.swift Tests/BuckyTests/FileBrowserModelTests.swift
git commit -m "feat: add file browser action state"
```

## Task 6: Mac File Services

**Files:**
- Create: `Sources/Bucky/Files/MacFileServices.swift`
- Test: `Tests/BuckyTests/MacFileServicesTests.swift`

- [ ] **Step 1: Write failing file operation tests**

Create `Tests/BuckyTests/MacFileServicesTests.swift`:

```swift
import XCTest
@testable import Bucky

final class MacFileServicesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyMacFileServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testKeepBothURLAddsNumericSuffixBeforeExtension() {
        let destination = temporaryDirectory.appendingPathComponent("Report.txt")
        try? "old".write(to: destination, atomically: true, encoding: .utf8)

        let url = MacFileServices(fileManager: .default).keepBothURL(for: destination)

        XCTAssertEqual(url.lastPathComponent, "Report 2.txt")
    }

    func testCopyFilesCopiesIntoDestinationDirectory() throws {
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        let destination = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try "value".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try MacFileServices(fileManager: .default).copy([source], to: destination, conflict: .replace)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path))
    }

    func testMoveFilesMovesIntoDestinationDirectory() throws {
        let source = temporaryDirectory.appendingPathComponent("move.txt")
        let destination = temporaryDirectory.appendingPathComponent("Destination", isDirectory: true)
        try "value".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        try MacFileServices(fileManager: .default).move([source], to: destination, conflict: .replace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("move.txt").path))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter MacFileServicesTests
```

Expected: fails because `MacFileServices` and conflict policy types do not exist.

- [ ] **Step 3: Create Mac file services**

Create `Sources/Bucky/Files/MacFileServices.swift`:

```swift
import AppKit
import Foundation

enum FileBrowserConflictResolution {
    case keepBoth
    case replace
    case cancel
}

struct MacFileServices {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPathsToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func copy(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        for source in urls {
            let destination = resolvedDestination(for: source, in: destinationDirectory, conflict: conflict)
            guard let destination else { return }
            try replaceIfNeeded(destination)
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func move(_ urls: [URL], to destinationDirectory: URL, conflict: FileBrowserConflictResolution) throws {
        for source in urls {
            let destination = resolvedDestination(for: source, in: destinationDirectory, conflict: conflict)
            guard let destination else { return }
            try replaceIfNeeded(destination)
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    func trash(_ urls: [URL]) throws {
        for url in urls {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    func keepBothURL(for destination: URL) -> URL {
        let directory = destination.deletingLastPathComponent()
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension

        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func resolvedDestination(
        for source: URL,
        in destinationDirectory: URL,
        conflict: FileBrowserConflictResolution
    ) -> URL? {
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        switch conflict {
        case .keepBoth:
            return keepBothURL(for: destination)
        case .replace:
            return destination
        case .cancel:
            return nil
        }
    }

    private func replaceIfNeeded(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run:

```bash
swift test --filter MacFileServicesTests
```

Expected: all `MacFileServicesTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Bucky/Files/MacFileServices.swift Tests/BuckyTests/MacFileServicesTests.swift
git commit -m "feat: add native file services"
```

## Task 7: Integrate Files Into Launcher Model

**Files:**
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`
- Modify: `Sources/Bucky/UI/Shared/Utilities.swift`
- Test: `Tests/BuckyTests/LauncherModeRoutingTests.swift`
- Test: `Tests/BuckyTests/ToolResultsSnapshotPolicyTests.swift`

- [ ] **Step 1: Add failing model routing tests**

Append to `LauncherModeRoutingTests`:

```swift
@available(macOS 26.0, *)
func testSwitchingModesStoresIndependentQueries() {
    let model = LiquidGlassLauncherModel(
        settingsStore: SettingsStore(),
        inclusionStore: InclusionStore(),
        exclusionStore: ExclusionStore(),
        calculationHistoryStore: CalculationHistoryStore(),
        fileBrowserModel: FileBrowserModel(
            fileSystem: StubFileSystemClient(home: URL(fileURLWithPath: "/Users/test"), entriesByDirectory: [:]),
            store: InMemoryFileBrowserStore(state: .defaultValue)
        )
    )

    model.show(mode: .applications)
    model.query = "ray"
    model.handle(command: .switchMode(.calculator))
    model.query = "2+2"
    model.handle(command: .switchMode(.dictionary))
    model.query = "hello"
    model.handle(command: .switchMode(.applications))

    XCTAssertEqual(model.query, "ray")
}
```

Move `StubFileSystemClient` and `InMemoryFileBrowserStore` test doubles into a shared test file `Tests/BuckyTests/FileBrowserTestDoubles.swift` so this test and `FileBrowserModelTests` can both use them.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter LauncherModeRoutingTests
```

Expected: initializer and routing do not support injected `FileBrowserModel` or split mode query storage.

- [ ] **Step 3: Update launcher model initialization and mode logic**

Modify `LiquidGlassLauncherModel`:

```swift
@Published var mode: LauncherMode = .applications
@Published var fileBrowserModel: FileBrowserModel

private var applicationQuery = ""
private var calculatorQuery = ""
private var dictionaryQuery = ""
```

Update initializer signature:

```swift
init(
    settingsStore: SettingsStore,
    inclusionStore: InclusionStore,
    exclusionStore: ExclusionStore,
    calculationHistoryStore: CalculationHistoryStore,
    fileBrowserModel: FileBrowserModel = FileBrowserModel()
) {
    self.settingsStore = settingsStore
    self.inclusionStore = inclusionStore
    self.exclusionStore = exclusionStore
    self.calculationHistoryStore = calculationHistoryStore
    self.fileBrowserModel = fileBrowserModel
    animationTiming = settingsStore.settings.animationTiming
}
```

Change `placeholder`:

```swift
var placeholder: String {
    mode.placeholder
}
```

Change `resultCount`:

```swift
var resultCount: Int {
    switch mode {
    case .applications:
        return filteredItems.count
    case .calculator, .dictionary:
        return toolItems.count
    case .files:
        return fileBrowserModel.entries.count
    }
}
```

Change command handling:

```swift
case let .switchMode(nextMode):
    switchMode(nextMode)
case .left, .right, .space, .shiftSpace, .beginSpaceHold, .endSpaceHold, .alphaNumeric:
    guard mode == .files else { return false }
    fileBrowserModel.handle(command)
```

Add:

```swift
private func switchMode(_ nextMode: LauncherMode) -> Bool {
    storeCurrentQuery()
    mode = nextMode
    query = storedQuery(for: nextMode)
    selectedIndex = 0
    applyCurrentMode()
    requestSelectionScroll(anchor: .top)
    if nextMode == .applications {
        reindexAction?()
    }
    return true
}
```

Update `applyCurrentMode`, `makeToolItems`, `storeCurrentQuery`, `storedQuery`, `activateSelected`, and `resultRowID` switches so `.calculator` returns calculation results, `.dictionary` returns dictionary results, and `.files` delegates key behavior to `fileBrowserModel`.

- [ ] **Step 4: Route command number and file keys in window controller**

In `LiquidGlassLauncherWindowController.installLocalKeyMonitor`, before existing shortcut checks:

```swift
if let mode = event.commandNumberMode {
    return self.model.handle(command: .switchMode(mode)) ? nil : event
}
```

Add key cases:

```swift
case UInt16(kVK_LeftArrow):
    return self.model.handle(command: .left) ? nil : event
case UInt16(kVK_RightArrow):
    return self.model.handle(command: .right) ? nil : event
case UInt16(kVK_Space):
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
        return self.model.handle(command: .shiftSpace) ? nil : event
    }
    return self.model.handle(command: .space) ? nil : event
default:
    if let character = event.firstAlphaNumericCharacter {
        return self.model.handle(command: .alphaNumeric(character)) ? nil : event
    }
    return event
```

In `LiquidGlassWindow.performKeyEquivalent`, add command number mode routing:

```swift
if let mode = event.commandNumberMode, commandHandler?(.switchMode(mode)) == true {
    return true
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter LauncherModeRoutingTests
swift test --filter ToolResultsSnapshotPolicyTests
swift test --filter FileBrowserModelTests
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift Sources/Bucky/UI/Shared/Utilities.swift Tests/BuckyTests/LauncherModeRoutingTests.swift Tests/BuckyTests/FileBrowserTestDoubles.swift Tests/BuckyTests/FileBrowserModelTests.swift
git commit -m "feat: route files mode commands"
```

## Task 8: Liquid Glass Mode Switcher And File Browser UI

**Files:**
- Create: `Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift`
- Create: `Sources/Bucky/UI/SwiftUI/FadeMarqueeText.swift`
- Create: `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`

- [ ] **Step 1: Create fade marquee component**

Create `FadeMarqueeText.swift`:

```swift
import SwiftUI

@available(macOS 26.0, *)
struct FadeMarqueeText: View {
    let text: String
    var font: Font = .body

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.middle)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
    }
}
```

- [ ] **Step 2: Create mode switcher**

Create `ModeSwitcherView.swift`:

```swift
import SwiftUI

@available(macOS 26.0, *)
struct ModeSwitcherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(LauncherMode.ordered, id: \.self) { mode in
                if mode == model.mode {
                    activePill(for: mode)
                } else {
                    Button {
                        _ = model.handle(command: .switchMode(mode))
                    } label: {
                        Image(systemName: symbol(for: mode))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .help(mode.placeholder)
                }
            }
        }
    }

    @ViewBuilder
    private func activePill(for mode: LauncherMode) -> some View {
        switch mode {
        case .applications, .calculator, .dictionary:
            TextField(mode.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .focused($isSearchFocused)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(.regularMaterial, in: Capsule())
        case .files:
            HStack(spacing: 10) {
                FadeMarqueeText(
                    text: model.fileBrowserModel.selectedEntry?.url.path ?? model.fileBrowserModel.currentDirectory.path,
                    font: .system(size: 16, weight: .semibold)
                )
                Picker("", selection: Binding(
                    get: { model.fileBrowserModel.sort },
                    set: { model.fileBrowserModel.setSort($0) }
                )) {
                    Text("Name").tag(FileBrowserSort.name)
                    Text("Created").tag(FileBrowserSort.dateCreated)
                    Text("Modified").tag(FileBrowserSort.dateModified)
                    Text("Size").tag(FileBrowserSort.size)
                }
                .labelsHidden()
                .frame(width: 112)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(.regularMaterial, in: Capsule())
            .onTapGesture {
                MacFileServices().copyPathsToPasteboard([model.fileBrowserModel.selectedEntry?.url ?? model.fileBrowserModel.currentDirectory])
            }
        }
    }

    private func symbol(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return "square.grid.2x2"
        case .calculator:
            return "function"
        case .dictionary:
            return "text.book.closed"
        case .files:
            return "folder"
        }
    }
}
```

Add `setSort(_:)` to `FileBrowserModel`:

```swift
func setSort(_ nextSort: FileBrowserSort) {
    sort = nextSort
    reloadEntries()
}
```

- [ ] **Step 3: Create file browser UI**

Create `FileBrowserView.swift`:

```swift
import SwiftUI

@available(macOS 26.0, *)
struct FileBrowserView: View {
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                pinnedRail
                    .frame(width: 150)
                directoryColumns
            }
            .padding(10)

            if model.focusState == .previewActions {
                actionOverlay
            }

            if case let .quickLook(url) = model.focusState {
                QuickLookPreviewSurface(url: url)
            }

            if case .transferPending = model.focusState {
                transferHint
            }
        }
    }

    private var pinnedRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.pinnedDirectories, id: \.self) { url in
                Text(url.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var directoryColumns: some View {
        HStack(spacing: 10) {
            fileListColumn(title: model.currentDirectory.lastPathComponent.isEmpty ? "/" : model.currentDirectory.lastPathComponent)
        }
    }

    private func fileListColumn(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(model.entries.enumerated()), id: \.element.url) { index, entry in
                FileBrowserRow(
                    entry: entry,
                    isSelected: index == model.selectedIndex,
                    isMarked: model.selectedURLs.contains(entry.url)
                )
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)
            ForEach(model.availableActions, id: \.self) { action in
                Text(action.rawValue)
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 24)
        .padding(18)
    }

    private var transferHint: some View {
        Text("Return copies or moves into this folder. Escape cancels.")
            .font(.callout.weight(.semibold))
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
    }
}

@available(macOS 26.0, *)
private struct FileBrowserRow: View {
    let entry: FileBrowserEntry
    let isSelected: Bool
    let isMarked: Bool

    var body: some View {
        HStack(spacing: 10) {
            FadeMarqueeText(text: entry.name, font: .system(size: 15, weight: .medium))
            Spacer(minLength: 8)
            FileIconView(url: entry.url)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(isMarked ? 0.11 : 0.04)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

@available(macOS 26.0, *)
private struct FileIconView: View {
    let url: URL
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "doc")
            }
        }
        .task(id: url) {
            icon = MacFileServices().icon(for: url)
        }
    }
}
```

Add fallback preview surface to `FileBrowserView.swift`:

```swift
@available(macOS 26.0, *)
private struct QuickLookPreviewSurface: View {
    let url: URL

    var body: some View {
        VStack(spacing: 12) {
            FileIconView(url: url)
                .frame(width: 96, height: 96)
            Text(url.lastPathComponent)
                .font(.headline)
            Text(url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(24)
        .frame(width: 420, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(radius: 34)
    }
}
```

- [ ] **Step 4: Integrate views into launcher**

In `LiquidGlassLauncherView`, replace `header` body with:

```swift
private var header: some View {
    ModeSwitcherView(model: model, isSearchFocused: $isSearchFocused)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            GlassEffectContainer(spacing: 0) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
}
```

In `resultContent`, add:

```swift
case .files:
    FileBrowserView(model: model.fileBrowserModel)
```

Update existing `.tools` cases to `.calculator, .dictionary`.

- [ ] **Step 5: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/UI/SwiftUI/ModeSwitcherView.swift Sources/Bucky/UI/SwiftUI/FadeMarqueeText.swift Sources/Bucky/UI/SwiftUI/FileBrowserView.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift Sources/Bucky/Files/FileBrowserModel.swift
git commit -m "feat: add file browser glass UI"
```

## Task 9: Native Preview, Confirmation Overlays, And File Operation Execution

**Files:**
- Modify: `Sources/Bucky/Files/FileBrowserModel.swift`
- Modify: `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`
- Modify: `Sources/Bucky/Files/MacFileServices.swift`
- Test: `Tests/BuckyTests/FileBrowserModelTests.swift`
- Test: `Tests/BuckyTests/MacFileServicesTests.swift`

- [ ] **Step 1: Add failing execution tests**

Append to `FileBrowserModelTests`:

```swift
func testEscapeDismissesQuickLookWithoutChangingSelection() {
    let model = makeModel(entries: entries(["one.txt"]))

    model.handle(.space)
    model.handle(.beginSpaceHold)
    model.handle(.endSpaceHold)

    XCTAssertEqual(model.selectedURLs.map(\.lastPathComponent), ["one.txt"])
    XCTAssertEqual(model.focusState, .browse)
}

func testStaleSelectionPrunesCurrentDirectoryItems() {
    let model = makeModel(entries: entries(["one.txt", "two.txt"]))

    model.handle(.space)
    XCTAssertEqual(model.selectedURLs.count, 1)

    model.replaceEntriesForTesting(entries(["two.txt"]))

    XCTAssertTrue(model.selectedURLs.isEmpty)
}
```

Add to `FileBrowserModel` for test-only mutation:

```swift
#if DEBUG
func replaceEntriesForTesting(_ nextEntries: [FileBrowserEntry]) {
    entries = nextEntries
    pruneStaleSelections()
}
#endif
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FileBrowserModelTests
```

Expected: fails until quick look and stale selection behavior are completed.

- [ ] **Step 3: Add operation execution methods**

Add to `FileBrowserModel`:

```swift
func confirmTransfer(using services: MacFileServices = MacFileServices(), conflict: FileBrowserConflictResolution) throws {
    guard case let .confirming(.transfer(transfer, destination)) = focusState else { return }
    switch transfer {
    case let .copy(urls):
        try services.copy(urls, to: destination, conflict: conflict)
    case let .move(urls):
        try services.move(urls, to: destination, conflict: conflict)
    }
    focusState = .browse
    reloadEntries()
}

func confirmTrash(using services: MacFileServices = MacFileServices()) throws {
    guard case let .confirming(.trash(urls, step)) = focusState, step >= 2 else { return }
    try services.trash(urls)
    selectedURLs = []
    focusState = .browse
    reloadEntries()
}

func openPinnedDirectory(_ url: URL) {
    currentDirectory = url
    selectedIndex = 0
    reloadEntries()
}
```

- [ ] **Step 4: Complete keyboard-driven overlay UI states**

In `FileBrowserView.actionOverlay`, keep actions as focused rows. Do not add mouse-first action buttons in this version:

```swift
private var actionOverlay: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Actions")
            .font(.headline)
        ForEach(Array(model.availableActions.enumerated()), id: \.element) { index, action in
            Text(label(for: action))
                .font(.system(size: 15, weight: index == model.focusedActionIndex ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(index == model.focusedActionIndex ? 0.14 : 0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }
    .padding(18)
    .frame(width: 240)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .shadow(radius: 24)
    .padding(18)
}

private func label(for action: FileBrowserAction) -> String {
    switch action {
    case .open: return "Open"
    case .rename: return "Rename"
    case .batchRename: return "Batch Rename"
    case .revealInFinder: return "Reveal in Finder"
    case .copyPath: return "Copy Path"
    case .copyPaths: return "Copy Paths"
    case .copy: return "Copy"
    case .move: return "Move"
    case .moveToTrash: return "Move to Trash"
    }
}
```

Add confirmation overlay branches:

```swift
if case let .confirming(confirmation) = model.focusState {
    ConfirmationOverlay(confirmation: confirmation, model: model)
}
```

Create private overlay:

```swift
@available(macOS 26.0, *)
private struct ConfirmationOverlay: View {
    let confirmation: FileBrowserConfirmation
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Return confirms. Escape cancels.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 28)
    }

    private var title: String {
        switch confirmation {
        case .transfer:
            return "Confirm Transfer"
        case let .trash(_, step):
            return step == 1 ? "Move to Trash?" : "Confirm Trash"
        case .conflict:
            return "Name Conflict"
        }
    }

    private var message: String {
        switch confirmation {
        case .transfer:
            return "Return confirms copying or moving into the current directory."
        case .trash:
            return "Items are moved to Trash, not permanently deleted."
        case .conflict:
            return "Choose Keep Both, Replace, or Cancel from the focused action."
        }
    }

}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
swift test --filter FileBrowserModelTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Bucky/Files/FileBrowserModel.swift Sources/Bucky/UI/SwiftUI/FileBrowserView.swift Sources/Bucky/Files/MacFileServices.swift Tests/BuckyTests/FileBrowserModelTests.swift Tests/BuckyTests/MacFileServicesTests.swift
git commit -m "feat: complete file browser actions"
```

## Task 10: Version Bump And Full Verification

**Files:**
- Modify: `packaging/Info.plist`
- Modify: tests touched by previous tasks if full-suite failures expose mode split assumptions.

- [ ] **Step 1: Bump semantic version**

Change `packaging/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>3.0.0</string>
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
swift test
```

Expected: all XCTest tests pass. The performance test may report comfort, watch, or regression band in its diagnostic line; the command must exit 0.

- [ ] **Step 3: Build release bundle**

Run:

```bash
make bundle
```

Expected: `build/Bucky.app` is produced and `build/Bucky.app/Contents/Info.plist` contains `CFBundleShortVersionString` of `3.0.0`.

- [ ] **Step 4: Manual verification in app**

Run:

```bash
open build/Bucky.app
```

Verify:

- `Cmd+1` shows Apps.
- `Cmd+2` shows Calculator.
- `Cmd+3` shows Dictionary.
- `Cmd+4` shows Files.
- Files opens at home or last persisted directory.
- Up/Down move rows.
- Left/Right move out/in, with pane wobble for invalid moves.
- Tap Space selects.
- Shift+Space range-selects.
- Hold Space shows preview; release dismisses.
- Return opens actions.
- Escape closes actions.
- Copy/Move enter transfer-pending state.
- Move to Trash requires double confirmation.
- Long path and row names use faded edges.
- Native file/folder icons appear on the right of rows.

- [ ] **Step 5: Commit**

```bash
git add packaging/Info.plist
git commit -m "chore: bump version to 3.0.0"
```

## Self-Review Notes

- Spec coverage: mode orbs, `Cmd+1...4`, Files mode, hidden files, pins, sort, keyboard navigation, multi-depth selection, held-Space preview, staged copy/move, Finder-style conflicts, Trash, persistence, native icons, fade marquee, and tests each map to tasks above.
- Scope: one feature plan, split into independently committable tasks.
- Type consistency: the plan consistently uses `LauncherMode`, `LauncherCommand`, `FileBrowserModel`, `FileSystemClientProtocol`, `FileBrowserPersisting`, `FileBrowserSort`, `FileBrowserAction`, `FileBrowserTransfer`, `FileBrowserConfirmation`, and `MacFileServices`.
