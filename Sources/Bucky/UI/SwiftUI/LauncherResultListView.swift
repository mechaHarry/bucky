import SwiftUI

struct LauncherResultListLayoutPolicy {
    static let rowSpacing: CGFloat = 14
    static let contentMargin: CGFloat = 12
    static let horizontalShadowBleed: CGFloat = contentMargin
    static let verticalShadowClearance: CGFloat = 20
    static let verticalEdgeFadeLength: CGFloat = 28
    static let rowCornerRadius: CGFloat = 18
    static let rowSelectionAnimationSeconds = 0.10
    static let rowReconstructionAnimationSeconds = 0.10
}

@available(macOS 26.0, *)
struct LauncherResultList<RowID: Hashable, Content: View>: View {
    @Binding var scrollTargetID: RowID?
    let scrollTargetAnchor: UnitPoint?
    let reconstructionID: AnyHashable?
    let usesEagerRows: Bool
    @ViewBuilder let content: () -> Content

    init(
        scrollTargetID: Binding<RowID?> = .constant(nil),
        scrollTargetAnchor: UnitPoint? = nil,
        reconstructionID: AnyHashable? = nil,
        usesEagerRows: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._scrollTargetID = scrollTargetID
        self.scrollTargetAnchor = scrollTargetAnchor
        self.reconstructionID = reconstructionID
        self.usesEagerRows = usesEagerRows
        self.content = content
    }

    var body: some View {
        scrollView
    }

    private var scrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            scrollContent
        }
        .contentMargins(.horizontal, LauncherResultListLayoutPolicy.contentMargin, for: .scrollContent)
        .contentMargins(.vertical, LauncherResultListLayoutPolicy.verticalShadowClearance, for: .scrollContent)
        .scrollPosition(id: $scrollTargetID, anchor: scrollTargetAnchor)
        .scrollIndicators(.hidden)
        .scrollIndicatorsFlash(trigger: false)
        .animation(
            .smooth(duration: LauncherResultListLayoutPolicy.rowReconstructionAnimationSeconds),
            value: reconstructionID
        )
    }

    private var scrollContent: some View {
        Group {
            if usesEagerRows {
                VStack(spacing: LauncherResultListLayoutPolicy.rowSpacing) {
                    content()
                }
            } else {
                LazyVStack(spacing: LauncherResultListLayoutPolicy.rowSpacing) {
                    content()
                }
            }
        }
        .scrollTargetLayout()
        .frame(maxWidth: .infinity)
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
struct LauncherAppsResultRow<Leading: View, Details: View, Metadata: View, Action: View>: View {
    let isSelected: Bool
    let selectionTint: Color
    let selectionNamespace: Namespace.ID
    let onActivate: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let details: () -> Details
    @ViewBuilder let metadata: () -> Metadata
    @ViewBuilder let action: () -> Action

    var body: some View {
        LauncherResultRow(
            isSelected: isSelected,
            selectionTint: selectionTint,
            selectionNamespace: selectionNamespace,
            verticalPadding: 10
        ) {
            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    leading()

                    details()

                    Spacer(minLength: 12)

                    metadata()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onActivate)

                action()
            }
        }
    }
}

@available(macOS 26.0, *)
struct LauncherAppsResultSkeletonRow: View {
    @Namespace private var selectionNamespace
    @State private var isPulseVisible = false

    var body: some View {
        LauncherResultRow(
            isSelected: false,
            selectionNamespace: selectionNamespace
        ) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 156, height: 15)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.secondary.opacity(0.13))
                        .frame(width: 220, height: 11)
                }

                Spacer(minLength: 12)

                Circle()
                    .fill(.secondary.opacity(0.16))
                    .frame(width: 26, height: 26)
            }
            .opacity(isPulseVisible ? 0.48 : 0.90)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulseVisible)
            .onAppear { isPulseVisible = true }
            .accessibilityHidden(true)
        }
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
            rowGleam
        }
        .overlay {
            rowShape
                .strokeBorder(
                    rowRim,
                    lineWidth: LauncherResultListVisualStyle.rowRimLineWidth(isSelected: isSelected)
                )
        }
        .animation(rowSelectionAnimation, value: isSelected)
        .animation(rowSelectionAnimation, value: isMarked)
    }

    private var rowBase: some View {
        rowShape
            .fill(LauncherResultListVisualStyle.rowFill.opacity(0.32))
    }

    private func rowHighlight(tint: Color, opacity: Double) -> some View {
        rowShape
            .fill(tint.opacity(opacity))
    }

    private var rowGleam: some View {
        rowShape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.46 : 0.28),
                        Color.white.opacity(0.04),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LauncherResultListLayoutPolicy.rowCornerRadius, style: .continuous)
    }

    private var rowRim: Color {
        if isSelected {
            return selectionTint.opacity(LauncherResultListVisualStyle.selectionRimOpacity)
        }
        if isMarked {
            return markedTint.opacity(LauncherResultListVisualStyle.markedRimOpacity)
        }
        return LauncherResultListVisualStyle.surfaceRim.opacity(LauncherResultListVisualStyle.unselectedRimOpacity)
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
    static let unselectedRimOpacity = 0.30
    static let selectionRimOpacity = 0.44
    static let markedRimOpacity = 0.34

    static func rowRimLineWidth(isSelected: Bool) -> CGFloat {
        isSelected ? 1.25 : 1.15
    }
}
