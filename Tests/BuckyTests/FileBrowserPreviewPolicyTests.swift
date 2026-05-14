import AppKit
import XCTest
@testable import Bucky

final class FileBrowserPreviewPolicyTests: XCTestCase {
    func testPreviewSurfaceUsesAvailableVerticalSpace() {
        let surfaceSize = FileBrowserPreviewLayoutPolicy.surfaceSize(
            for: .nativeThumbnail,
            availableSize: CGSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(surfaceSize.height, 800)
        XCTAssertGreaterThan(surfaceSize.width, 560)
    }

    func testPreviewSurfaceClampsToAvailableSpace() {
        let surfaceSize = FileBrowserPreviewLayoutPolicy.surfaceSize(
            for: .video,
            availableSize: CGSize(width: 700, height: 500)
        )

        XCTAssertLessThanOrEqual(surfaceSize.width, 668)
        XCTAssertLessThanOrEqual(surfaceSize.height, 500)
    }

    func testPreviewAreaLeavesRoomForTitleAndPath() {
        let surfaceSize = FileBrowserPreviewLayoutPolicy.surfaceSize(
            for: .codeText,
            availableSize: CGSize(width: 1_000, height: 800)
        )
        let contentSize = FileBrowserPreviewLayoutPolicy.contentSize(surfaceSize: surfaceSize)
        let usedHeight = FileBrowserPreviewLayoutPolicy.previewAreaHeight(
            for: .codeText,
            contentSize: contentSize
        ) + FileBrowserPreviewLayoutPolicy.previewTextStackHeight

        XCTAssertLessThanOrEqual(usedHeight, contentSize.height)
    }

    func testNativeImagePreviewUsesFullContentHeightWithOverlaidMetadata() {
        let contentSize = CGSize(width: 680, height: 380)

        XCTAssertEqual(
            FileBrowserPreviewLayoutPolicy.previewAreaHeight(for: .nativeThumbnail, contentSize: contentSize),
            contentSize.height
        )
        XCTAssertTrue(FileBrowserPreviewLayoutPolicy.overlaysMetadata(for: .nativeThumbnail))
        XCTAssertFalse(FileBrowserPreviewLayoutPolicy.overlaysMetadata(for: .codeText))
    }

    func testActiveTraversalRowHasDistinctIndicatorWhenRowsAreMarked() {
        XCTAssertGreaterThan(FileBrowserRowFocusIndicatorPolicy.activeIndicatorWidth, 0)
        XCTAssertGreaterThan(
            FileBrowserRowFocusIndicatorPolicy.activeSelectionOpacity,
            FileBrowserRowFocusIndicatorPolicy.markedSelectionOpacity
        )
    }

    func testActionPaneBoundsSelectionTextAndListsIndividualItems() {
        let directory = URL(fileURLWithPath: "/Users/test/Very/Long/Directory")
        let urls = (0..<6).map {
            directory.appendingPathComponent("long-file-name-\($0)-that-should-marquee.jpg")
        }
        let rows = FileBrowserActionPaneSelectionPolicy.rows(for: urls)

        XCTAssertEqual(FileBrowserActionPaneLayoutPolicy.width, 268)
        XCTAssertEqual(
            FileBrowserActionPaneLayoutPolicy.contentWidth,
            FileBrowserActionPaneLayoutPolicy.width - FileBrowserActionPaneLayoutPolicy.padding * 2
        )
        XCTAssertFalse(FileBrowserActionPaneLayoutPolicy.usesCardStack(selectionCount: 1))
        XCTAssertTrue(FileBrowserActionPaneLayoutPolicy.usesCardStack(selectionCount: 2))
        XCTAssertEqual(rows.visible.map(\.lastPathComponent), Array(urls.prefix(4)).map(\.lastPathComponent))
        XCTAssertEqual(rows.remainingCount, 2)
    }

    func testCodePreviewThemeUsesDarkBackgroundAndLightText() {
        XCTAssertLessThan(FileBrowserCodePreviewTheme.background.perceivedBrightness, 0.2)
        XCTAssertGreaterThan(FileBrowserCodePreviewTheme.foreground.perceivedBrightness, 0.75)
    }

    func testCodeTextPreviewLoaderBoundsBytesAndWrapsLongLines() {
        XCTAssertLessThanOrEqual(FileBrowserTextPreviewLoader.maxPreviewBytes, 64 * 1024)

        let longLine = String(
            repeating: "a",
            count: FileBrowserTextPreviewLoader.maxRenderedLineLength * 3 + 17
        )
        let wrapped = FileBrowserTextPreviewLoader.wrapLongLines(longLine)
        let lineLengths = wrapped.split(separator: "\n", omittingEmptySubsequences: false).map(\.count)

        XCTAssertTrue(lineLengths.allSatisfy { $0 <= FileBrowserTextPreviewLoader.maxRenderedLineLength })
        XCTAssertGreaterThan(lineLengths.count, 1)
    }

    func testCodeTextPreviewLoaderReadsLargeFilesAsBoundedWrappedSnippet() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuckyLargePreview-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let longLine = String(repeating: "x", count: FileBrowserTextPreviewLoader.maxPreviewBytes * 4)
        try longLine.write(to: url, atomically: true, encoding: .utf8)

        let snippet = try FileBrowserTextPreviewLoader.loadSnippet(from: url)
        let lines = snippet
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("preview truncated") }

        XCTAssertTrue(snippet.contains("preview truncated"))
        XCTAssertLessThan(snippet.count, longLine.count)
        XCTAssertTrue(lines.allSatisfy { $0.count <= FileBrowserTextPreviewLoader.maxRenderedLineLength })
    }

    func testRowsExposeFileURLsForNativeDragging() {
        let url = URL(fileURLWithPath: "/Users/test/image.png")

        XCTAssertEqual(FileBrowserDragPolicy.draggedURL(for: url), url)
    }

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

    func testProvidedDragURLsFallBackToRowURLWhenEmpty() {
        let url = URL(fileURLWithPath: "/Users/test/image.png")

        XCTAssertEqual(
            FileBrowserDragPolicy.nonEmptyDraggedURLs(rowURL: url, providedURLs: []),
            [url]
        )
    }

    func testNativeRowDragStartsAfterSmallPointerMovementAndDisablesWindowDragging() {
        XCTAssertFalse(FileBrowserDragPolicy.mouseDownCanMoveWindow)
        XCTAssertFalse(FileBrowserDragPolicy.shouldBeginNativeDrag(delta: CGSize(width: 1, height: 1)))
        XCTAssertTrue(FileBrowserDragPolicy.shouldBeginNativeDrag(delta: CGSize(width: 4, height: 0)))
    }

    func testNativeRowDragImageFramePreservesIconProportionsInsteadOfRowBounds() {
        let rowBounds = CGRect(x: 0, y: 0, width: 480, height: 42)
        let frame = FileBrowserDragPolicy.draggingImageFrame(
            in: rowBounds,
            iconSize: CGSize(width: 128, height: 64),
            pointerLocation: CGPoint(x: 120, y: 21)
        )

        XCTAssertEqual(frame.width, 48)
        XCTAssertEqual(frame.height, 24)
        XCTAssertEqual(frame.midX, 120)
        XCTAssertEqual(frame.midY, 21)
        XCTAssertLessThan(frame.width, rowBounds.width)
    }

    func testNativeRowDragImageOffsetIsCappedForLargeSelections() {
        XCTAssertEqual(
            FileBrowserDragPolicy.draggingImageOffset(forItemAt: 99),
            FileBrowserDragPolicy.draggingImageOffset(forItemAt: 3)
        )
    }

    func testTrashUsesSingleNativeTrashSymbolInsteadOfBadgedFolderArtwork() {
        XCTAssertEqual(
            FileBrowserIconPolicy.systemSymbolOverride(for: URL(fileURLWithPath: "/Users/test/.Trash")),
            "trash"
        )
        XCTAssertNil(FileBrowserIconPolicy.systemSymbolOverride(for: URL(fileURLWithPath: "/Users/test/Documents")))
    }
}

private extension NSColor {
    var perceivedBrightness: CGFloat {
        let color = usingColorSpace(.deviceRGB) ?? self
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }
}
