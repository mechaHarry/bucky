import SwiftUI

struct LauncherResultListLayoutPolicy {
    static let rowSpacing: CGFloat = 10
    static let contentMargin: CGFloat = 0
    static let rowCornerRadius: CGFloat = 18
    static let rowSelectionAnimationSeconds = 0.18
    static let rowReconstructionAnimationSeconds = 0.18
}

struct LauncherAetherEdgePolicy {
    static let edgeBandHeight: CGFloat = 28
    static let edgeGlassOpacity = 0.52
    static let edgeFadeStop = 0.72
}

@available(macOS 26.0, *)
struct LauncherResultList<RowID: Hashable, Content: View>: View {
    @Binding var scrollTargetID: RowID?
    let scrollTargetAnchor: UnitPoint?
    let reconstructionID: AnyHashable?
    let appliesAetherEdgeTreatment: Bool
    @ViewBuilder let content: () -> Content

    init(
        scrollTargetID: Binding<RowID?> = .constant(nil),
        scrollTargetAnchor: UnitPoint? = nil,
        reconstructionID: AnyHashable? = nil,
        appliesAetherEdgeTreatment: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._scrollTargetID = scrollTargetID
        self.scrollTargetAnchor = scrollTargetAnchor
        self.reconstructionID = reconstructionID
        self.appliesAetherEdgeTreatment = appliesAetherEdgeTreatment
        self.content = content
    }

    var body: some View {
        Group {
            if appliesAetherEdgeTreatment {
                scrollView
                    .launcherAetherEdgeTreatment()
            } else {
                scrollView
            }
        }
    }

    private var scrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            scrollContent
        }
        .contentMargins(.horizontal, LauncherResultListLayoutPolicy.contentMargin, for: .scrollContent)
        .contentMargins(.vertical, LauncherResultListLayoutPolicy.contentMargin, for: .scrollContent)
        .scrollPosition(id: $scrollTargetID, anchor: scrollTargetAnchor)
        .scrollIndicators(.hidden)
        .scrollIndicatorsFlash(trigger: false)
        .animation(
            .smooth(duration: LauncherResultListLayoutPolicy.rowReconstructionAnimationSeconds),
            value: reconstructionID
        )
    }

    private var scrollContent: some View {
        LazyVStack(spacing: LauncherResultListLayoutPolicy.rowSpacing) {
            content()
        }
        .scrollTargetLayout()
        .frame(maxWidth: .infinity)
    }
}

@available(macOS 26.0, *)
extension View {
    func launcherAetherEdgeTreatment() -> some View {
        self
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: LauncherAetherEdgePolicy.edgeFadeStop)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: LauncherAetherEdgePolicy.edgeBandHeight)

                    Rectangle()
                        .fill(.black)

                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 1 - LauncherAetherEdgePolicy.edgeFadeStop),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: LauncherAetherEdgePolicy.edgeBandHeight)
                }
            }
            .overlay(alignment: .top) {
                LauncherAetherEdgeOverlay(edge: .top)
            }
            .overlay(alignment: .bottom) {
                LauncherAetherEdgeOverlay(edge: .bottom)
            }
            .clipped()
    }
}

@available(macOS 26.0, *)
private enum LauncherAetherEdge {
    case top
    case bottom
}

@available(macOS 26.0, *)
private struct LauncherAetherEdgeOverlay: View {
    let edge: LauncherAetherEdge

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [Color.white.opacity(0.20), Color.white.opacity(0)]
                : [Color.white.opacity(0), Color.white.opacity(0.20)],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(.regularMaterial)
        .opacity(LauncherAetherEdgePolicy.edgeGlassOpacity)
        .frame(height: LauncherAetherEdgePolicy.edgeBandHeight)
        .allowsHitTesting(false)
    }
}

@available(macOS 26.0, *)
struct LauncherResultRow<Content: View>: View {
    let isSelected: Bool
    var isMarked = false
    var selectionTint = LauncherResultListVisualStyle.selectionFill
    var markedTint = LauncherResultListVisualStyle.markedFill
    let selectionNamespace: Namespace.ID
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 10
    var minHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background {
                LauncherResultRowBackground(
                    isSelected: isSelected,
                    isMarked: isMarked,
                    selectionTint: selectionTint,
                    markedTint: markedTint,
                    selectionNamespace: selectionNamespace
                )
            }
            .contentShape(RoundedRectangle(
                cornerRadius: LauncherResultListLayoutPolicy.rowCornerRadius + 2,
                style: .continuous
            ))
    }
}

@available(macOS 26.0, *)
private struct LauncherResultRowBackground: View {
    let isSelected: Bool
    let isMarked: Bool
    let selectionTint: Color
    let markedTint: Color
    let selectionNamespace: Namespace.ID

    private var rowSelectionAnimation: Animation {
        .smooth(duration: LauncherResultListLayoutPolicy.rowSelectionAnimationSeconds)
    }

    var body: some View {
        ZStack {
            rowBase

            if isMarked && !isSelected {
                rowHighlight(
                    tint: markedTint,
                    opacity: FileBrowserRowFocusIndicatorPolicy.markedSelectionOpacity
                )
                .transition(.opacity)
            }

            if isSelected {
                rowHighlight(
                    tint: selectionTint,
                    opacity: FileBrowserRowFocusIndicatorPolicy.activeSelectionOpacity
                )
                .overlay {
                    rowShape
                        .strokeBorder(selectionTint.opacity(0.42), lineWidth: 1)
                }
            }
        }
        .overlay {
            rowShape
                .strokeBorder(rowRim, lineWidth: isSelected ? 1.15 : 1)
        }
        .animation(rowSelectionAnimation, value: isSelected)
        .animation(rowSelectionAnimation, value: isMarked)
    }

    private var rowBase: some View {
        rowShape
            .fill(LauncherResultListVisualStyle.rowFill.opacity(0.44))
    }

    private func rowHighlight(tint: Color, opacity: Double) -> some View {
        rowShape
            .fill(tint.opacity(opacity))
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LauncherResultListLayoutPolicy.rowCornerRadius, style: .continuous)
    }

    private var rowRim: Color {
        if isSelected {
            return selectionTint.opacity(0.34)
        }
        if isMarked {
            return markedTint.opacity(0.28)
        }
        return LauncherResultListVisualStyle.surfaceRim.opacity(0.18)
    }
}

@available(macOS 26.0, *)
enum LauncherResultListVisualStyle {
    static let rowFill = Color(nsColor: .windowBackgroundColor)
    static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)
    static let markedFill = Color(nsColor: .controlAccentColor)
    static let surfaceRim = Color(nsColor: .separatorColor)
    static let selectionRim = Color(nsColor: .selectedContentBackgroundColor)
    static let markedRim = Color(nsColor: .controlAccentColor)
}
