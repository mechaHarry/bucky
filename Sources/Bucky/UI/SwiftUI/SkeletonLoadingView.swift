import SwiftUI

enum SkeletonLoadingSurface: Equatable {
    case launcherResults
    case fileResults
    case filePreview
    case compact
}

enum SkeletonLoadingAnimationLifecycle: Equatable {
    case appearToStartDisappearToStop
}

struct SkeletonLoadingAnimationConfiguration: Equatable {
    let duration: TimeInterval
    let autoreverses: Bool
    let lifecycle: SkeletonLoadingAnimationLifecycle

    var swiftUIAnimation: Animation {
        .easeInOut(duration: duration)
            .repeatForever(autoreverses: autoreverses)
    }
}

struct SkeletonLoadingConfiguration: Equatable {
    let rowCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    let accessibilityLabel: String
    let animation: SkeletonLoadingAnimationConfiguration
}

enum SkeletonLoadingPolicy {
    static let restingOpacity = 0.34
    static let activeOpacity = 0.68

    static func configuration(
        for surface: SkeletonLoadingSurface,
        label: String
    ) -> SkeletonLoadingConfiguration {
        let rowCount: Int
        let rowHeight: CGFloat
        let horizontalPadding: CGFloat
        let cornerRadius: CGFloat

        switch surface {
        case .launcherResults:
            rowCount = 4
            rowHeight = 54
            horizontalPadding = 12
            cornerRadius = 12
        case .fileResults:
            rowCount = 5
            rowHeight = 54
            horizontalPadding = 12
            cornerRadius = 12
        case .filePreview:
            rowCount = 3
            rowHeight = 54
            horizontalPadding = 12
            cornerRadius = 12
        case .compact:
            rowCount = 1
            rowHeight = 10
            horizontalPadding = 0
            cornerRadius = 0
        }

        return SkeletonLoadingConfiguration(
            rowCount: rowCount,
            rowHeight: rowHeight,
            rowSpacing: 8,
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius,
            accessibilityLabel: label,
            animation: SkeletonLoadingAnimationConfiguration(
                duration: 0.95,
                autoreverses: true,
                lifecycle: .appearToStartDisappearToStop
            )
        )
    }
}

@available(macOS 13.0, *)
struct SkeletonLoadingView: View {
    let label: String
    let surface: SkeletonLoadingSurface

    @State private var isAnimating = false

    private var configuration: SkeletonLoadingConfiguration {
        SkeletonLoadingPolicy.configuration(for: surface, label: label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: configuration.rowSpacing) {
            ForEach(0..<configuration.rowCount, id: \.self) { index in
                skeletonRow(at: index)
            }
        }
        .padding(configuration.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(isAnimating ? SkeletonLoadingPolicy.activeOpacity : SkeletonLoadingPolicy.restingOpacity)
        .animation(configuration.animation.swiftUIAnimation, value: isAnimating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(configuration.accessibilityLabel)
        .onAppear {
            if configuration.animation.lifecycle == .appearToStartDisappearToStop {
                isAnimating = true
            }
        }
        .onDisappear {
            if configuration.animation.lifecycle == .appearToStartDisappearToStop {
                isAnimating = false
            }
        }
    }

    @ViewBuilder
    private func skeletonRow(at index: Int) -> some View {
        if surface == .compact {
            Capsule(style: .continuous)
                .fill(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: configuration.rowHeight)
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
            .frame(height: configuration.rowHeight)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(
                cornerRadius: configuration.cornerRadius,
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
