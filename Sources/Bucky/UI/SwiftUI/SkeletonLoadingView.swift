import SwiftUI

enum SkeletonLoadingSurface: Equatable {
    case launcherResults
    case fileResults
    case filePreview
    case compact
}

enum SkeletonLoadingPolicy {
    static let launcherResultRowCount = 4
    static let fileResultRowCount = 5
    static let filePreviewRowCount = 3

    static let resultRowHeight: CGFloat = 54
    static let compactRowHeight: CGFloat = 10
    static let rowSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let animationDuration: TimeInterval = 0.95
    static let restingOpacity = 0.34
    static let activeOpacity = 0.68

    static let exposesAccessibleLabel = true
    static let repeatsAnimation = true
    static let stopsAnimationOnDisappear = true
    static let usesTask = false
    static let usesTimer = false

    static func rowCount(for surface: SkeletonLoadingSurface) -> Int {
        switch surface {
        case .launcherResults:
            launcherResultRowCount
        case .fileResults:
            fileResultRowCount
        case .filePreview:
            filePreviewRowCount
        case .compact:
            1
        }
    }

    static var animation: Animation {
        .easeInOut(duration: animationDuration)
            .repeatForever(autoreverses: true)
    }
}

@available(macOS 13.0, *)
struct SkeletonLoadingView: View {
    let label: String
    let surface: SkeletonLoadingSurface

    @State private var isAnimating = false

    private var rowCount: Int {
        SkeletonLoadingPolicy.rowCount(for: surface)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SkeletonLoadingPolicy.rowSpacing) {
            ForEach(0..<rowCount, id: \.self) { index in
                skeletonRow(at: index)
            }
        }
        .padding(surface == .compact ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(isAnimating ? SkeletonLoadingPolicy.activeOpacity : SkeletonLoadingPolicy.restingOpacity)
        .animation(SkeletonLoadingPolicy.animation, value: isAnimating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }

    @ViewBuilder
    private func skeletonRow(at index: Int) -> some View {
        if surface == .compact {
            Capsule(style: .continuous)
                .fill(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: SkeletonLoadingPolicy.compactRowHeight)
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(width: titleWidth(for: index), height: 10)
                    Capsule(style: .continuous)
                        .fill(.quaternary)
                        .frame(width: subtitleWidth(for: index), height: 7)
                }

                Spacer(minLength: 0)

                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 24, height: 8)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: SkeletonLoadingPolicy.resultRowHeight)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(
                cornerRadius: SkeletonLoadingPolicy.cornerRadius,
                style: .continuous
            ))
        }
    }

    private func titleWidth(for index: Int) -> CGFloat {
        index.isMultiple(of: 3) ? 156 : 124
    }

    private func subtitleWidth(for index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? 92 : 68
    }
}
