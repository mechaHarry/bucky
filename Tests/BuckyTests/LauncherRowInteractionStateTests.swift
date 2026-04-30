import XCTest
@testable import Bucky

final class LauncherRowInteractionStateTests: XCTestCase {
    func testHoverAddsMidStateWithoutReplacingSelection() {
        let idle = LauncherRowInteractionState(isSelected: false, isHovered: false)
        XCTAssertFalse(idle.usesHoverSurface)
        XCTAssertFalse(idle.revealsAuxiliaryAction)
        XCTAssertGreaterThan(idle.baseTintOpacity, 0)
        XCTAssertGreaterThan(idle.shadowOpacity, 0)

        let hovered = LauncherRowInteractionState(isSelected: false, isHovered: true)
        XCTAssertTrue(hovered.usesHoverSurface)
        XCTAssertTrue(hovered.revealsAuxiliaryAction)
        XCTAssertGreaterThan(hovered.hoverTintOpacity, idle.baseTintOpacity)
        XCTAssertGreaterThan(hovered.shadowOpacity, idle.shadowOpacity)
        XCTAssertLessThanOrEqual(hovered.hoverTintOpacity, 0.18)
        XCTAssertLessThanOrEqual(hovered.shadowOpacity, 0.16)
        XCTAssertGreaterThan(hovered.borderOpacity, idle.borderOpacity)

        let selectedAndHovered = LauncherRowInteractionState(isSelected: true, isHovered: true)
        XCTAssertFalse(selectedAndHovered.usesHoverSurface)
        XCTAssertTrue(selectedAndHovered.revealsAuxiliaryAction)
        XCTAssertGreaterThan(selectedAndHovered.selectionTintOpacity, hovered.hoverTintOpacity)
        XCTAssertGreaterThan(selectedAndHovered.shadowOpacity, hovered.shadowOpacity)
        XCTAssertLessThanOrEqual(selectedAndHovered.selectionTintOpacity, 0.24)
        XCTAssertLessThanOrEqual(selectedAndHovered.shadowOpacity, 0.20)
        XCTAssertGreaterThan(selectedAndHovered.borderOpacity, hovered.borderOpacity)
    }

    func testSelectionSurfaceUsesIndependentMaterializeTransition() {
        let selected = LauncherRowInteractionState(isSelected: true, isHovered: false)

        XCTAssertEqual(selected.selectionTransitionStyle, .materialize)
        XCTAssertFalse(selected.usesSharedSelectionGlassIdentity)
    }

    func testHeaderFocusAndIndexingIncreaseSurfaceEmphasis() {
        let idle = LauncherHeaderInteractionState(
            isHovered: false,
            isFocused: false,
            isIndexing: false
        )
        XCTAssertFalse(idle.isActive)
        XCTAssertEqual(idle.glowOpacity, 0)
        XCTAssertGreaterThan(idle.depthShadowOpacity, 0)

        let hovered = LauncherHeaderInteractionState(
            isHovered: true,
            isFocused: false,
            isIndexing: false
        )
        XCTAssertTrue(hovered.isActive)
        XCTAssertGreaterThan(hovered.glowOpacity, idle.glowOpacity)
        XCTAssertGreaterThan(hovered.tintOpacity, idle.tintOpacity)
        XCTAssertGreaterThan(hovered.borderOpacity, idle.borderOpacity)
        XCTAssertGreaterThan(hovered.depthShadowOpacity, idle.depthShadowOpacity)

        let focused = LauncherHeaderInteractionState(
            isHovered: false,
            isFocused: true,
            isIndexing: false
        )
        XCTAssertFalse(focused.isActive)
        XCTAssertEqual(focused.glowOpacity, 0)
        XCTAssertEqual(focused.tintOpacity, 0)

        let focusedAndHovered = LauncherHeaderInteractionState(
            isHovered: true,
            isFocused: true,
            isIndexing: false
        )
        XCTAssertEqual(focusedAndHovered.tintOpacity, 0)
        XCTAssertGreaterThan(focusedAndHovered.glowOpacity, focused.glowOpacity)

        let indexing = LauncherHeaderInteractionState(
            isHovered: false,
            isFocused: false,
            isIndexing: true
        )
        XCTAssertGreaterThan(indexing.glowOpacity, hovered.glowOpacity)
        XCTAssertGreaterThan(indexing.borderOpacity, hovered.borderOpacity)
    }

    func testHeaderControlHoverUsesTintAndPartialFillWhileDisabledDimsSymbol() {
        let idle = LauncherHeaderControlInteractionState(isHovered: false, isEnabled: true)
        XCTAssertEqual(idle.symbolOpacity, 1)
        XCTAssertEqual(idle.tintOpacity, 0)
        XCTAssertEqual(idle.glowOpacity, 0)
        XCTAssertEqual(idle.fillSymbolOpacity, 0)
        XCTAssertGreaterThan(idle.depthShadowOpacity, 0)

        let hovered = LauncherHeaderControlInteractionState(isHovered: true, isEnabled: true)
        XCTAssertEqual(hovered.symbolOpacity, 1)
        XCTAssertGreaterThan(hovered.tintOpacity, idle.tintOpacity)
        XCTAssertLessThanOrEqual(hovered.tintOpacity, 0.20)
        XCTAssertEqual(hovered.glowOpacity, 0)
        XCTAssertGreaterThan(hovered.fillSymbolOpacity, 0)
        XCTAssertLessThan(hovered.fillSymbolOpacity, 1)
        XCTAssertGreaterThan(hovered.borderOpacity, idle.borderOpacity)

        let disabled = LauncherHeaderControlInteractionState(isHovered: true, isEnabled: false)
        XCTAssertLessThan(disabled.symbolOpacity, idle.symbolOpacity)
        XCTAssertEqual(disabled.tintOpacity, 0)
        XCTAssertEqual(disabled.glowOpacity, 0)
        XCTAssertEqual(disabled.fillSymbolOpacity, 0)
        XCTAssertLessThan(disabled.depthShadowOpacity, idle.depthShadowOpacity)
    }

    func testResultsLayoutKeepsRowsInsetFromThePanelHole() {
        let metrics = LauncherResultsLayoutMetrics.standard

        XCTAssertGreaterThanOrEqual(metrics.rowHorizontalInset, 12)
        XCTAssertGreaterThanOrEqual(metrics.rowVerticalInset, 10)
        XCTAssertGreaterThanOrEqual(metrics.rowSpacing, 8)
        XCTAssertGreaterThanOrEqual(metrics.cornerRadius, 22)
        XCTAssertLessThanOrEqual(metrics.insetBackingTintOpacity, 0.025)
        XCTAssertLessThan(metrics.insetBackingTintOpacity, metrics.mainPanelTintOpacity)
        XCTAssertEqual(metrics.scrollIndicatorsAreVisible, true)
        XCTAssertEqual(metrics.rowTrailingInset, metrics.rowHorizontalInset)
        XCTAssertEqual(metrics.scrollbarVerticalInset, metrics.rowVerticalInset)
        XCTAssertGreaterThan(metrics.topSelectionAnchorY, 0)
        XCTAssertLessThan(metrics.bottomSelectionAnchorY, 1)
    }

    func testQueryChangesResetSelectionToTopVisibleResult() {
        let policy = LauncherQueryUpdatePolicy.standard

        XCTAssertEqual(policy.selectedIndexAfterQueryChange(resultCount: 0), 0)
        XCTAssertEqual(policy.selectedIndexAfterQueryChange(resultCount: 12), 0)
        XCTAssertFalse(policy.shouldRequestTopScrollAfterQueryChange(resultCount: 0))
        XCTAssertTrue(policy.shouldRequestTopScrollAfterQueryChange(resultCount: 12))
    }

    func testRowActionHoverAndActivationUseGlassMidState() {
        let idle = LauncherRowActionInteractionState(
            isHovered: false,
            isActive: false,
            isEnabled: true
        )
        XCTAssertEqual(idle.tintOpacity, 0)
        XCTAssertEqual(idle.fillSymbolOpacity, 0)

        let hovered = LauncherRowActionInteractionState(
            isHovered: true,
            isActive: false,
            isEnabled: true
        )
        XCTAssertGreaterThan(hovered.tintOpacity, idle.tintOpacity)
        XCTAssertGreaterThan(hovered.fillSymbolOpacity, idle.fillSymbolOpacity)
        XCTAssertLessThan(hovered.fillSymbolOpacity, 1)
        XCTAssertGreaterThan(hovered.borderOpacity, idle.borderOpacity)

        let active = LauncherRowActionInteractionState(
            isHovered: true,
            isActive: true,
            isEnabled: true
        )
        XCTAssertGreaterThan(active.tintOpacity, hovered.tintOpacity)
        XCTAssertGreaterThan(active.fillSymbolOpacity, hovered.fillSymbolOpacity)
        XCTAssertLessThanOrEqual(active.fillSymbolOpacity, 1)
        XCTAssertGreaterThan(active.borderOpacity, hovered.borderOpacity)

        let disabled = LauncherRowActionInteractionState(
            isHovered: true,
            isActive: true,
            isEnabled: false
        )
        XCTAssertEqual(disabled.tintOpacity, 0)
        XCTAssertEqual(disabled.fillSymbolOpacity, 0)
    }
}
