import SwiftUI

struct FadeMarqueeTextLayoutPolicy {
    static let edgePauseSeconds: TimeInterval = 0.72
    static let minimumTravelSeconds: TimeInterval = 1.8
    static let maximumTravelSeconds: TimeInterval = 7.5
    static let pointsPerSecond: CGFloat = 72
    static let fadeActivationDistance: CGFloat = 22

    static func overflow(contentWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        max(0, contentWidth - containerWidth)
    }

    static func shouldMarquee(contentWidth: CGFloat, containerWidth: CGFloat, reduceMotion: Bool) -> Bool {
        containerWidth > 1
            && overflow(contentWidth: contentWidth, containerWidth: containerWidth) > 1
            && !reduceMotion
    }

    static func travelDuration(forOverflow overflow: CGFloat) -> TimeInterval {
        let unclamped = TimeInterval(max(0, overflow) / pointsPerSecond)
        return min(max(unclamped, minimumTravelSeconds), maximumTravelSeconds)
    }

    static func cycleDuration(forOverflow overflow: CGFloat) -> TimeInterval {
        edgePauseSeconds * 2 + travelDuration(forOverflow: overflow) * 2
    }

    static func scrollProgress(elapsed: TimeInterval, overflow: CGFloat) -> CGFloat {
        let travelDuration = travelDuration(forOverflow: overflow)
        let cycleDuration = cycleDuration(forOverflow: overflow)
        guard cycleDuration > 0 else { return 0 }

        var phase = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        if phase < 0 {
            phase += cycleDuration
        }

        if phase < edgePauseSeconds {
            return 0
        }

        phase -= edgePauseSeconds
        if phase < travelDuration {
            return easedProgress(CGFloat(phase / travelDuration))
        }

        phase -= travelDuration
        if phase < edgePauseSeconds {
            return 1
        }

        phase -= edgePauseSeconds
        if phase < travelDuration {
            return 1 - easedProgress(CGFloat(phase / travelDuration))
        }

        return 0
    }

    static func offset(forProgress progress: CGFloat, overflow: CGFloat) -> CGFloat {
        -max(0, overflow) * min(1, max(0, progress))
    }

    static func leadingFadeStrength(offset: CGFloat, overflow: CGFloat) -> Double {
        guard overflow > 1 else { return 0 }
        return Double(min(1, max(0, -offset / fadeActivationDistance)))
    }

    static func trailingFadeStrength(offset: CGFloat, overflow: CGFloat) -> Double {
        guard overflow > 1 else { return 0 }
        return Double(min(1, max(0, (overflow + offset) / fadeActivationDistance)))
    }

    private static func easedProgress(_ progress: CGFloat) -> CGFloat {
        0.5 - 0.5 * cos(min(1, max(0, progress)) * .pi)
    }
}

@available(macOS 26.0, *)
struct FadeMarqueeText: View {
    let text: String
    var font: Font = .body
    var constrainedWidth: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var animationStartDate = Date()

    var body: some View {
        let measuredContainerWidth = constrainedWidth ?? containerWidth
        let overflow = FadeMarqueeTextLayoutPolicy.overflow(
            contentWidth: contentWidth,
            containerWidth: measuredContainerWidth
        )

        Group {
            if FadeMarqueeTextLayoutPolicy.shouldMarquee(
                contentWidth: contentWidth,
                containerWidth: measuredContainerWidth,
                reduceMotion: reduceMotion
            ) {
                animatedMarqueeText(overflow: overflow, measuredContainerWidth: measuredContainerWidth)
            } else {
                marqueeText(offset: 0, overflow: overflow, viewportWidth: measuredContainerWidth)
            }
        }
        .readContainerWidth($containerWidth)
        .onAppear {
            animationStartDate = Date()
        }
        .onChange(of: text) {
            animationStartDate = Date()
        }
    }

    @ViewBuilder
    private func animatedMarqueeText(overflow: CGFloat, measuredContainerWidth: CGFloat) -> some View {
        TimelineView(.animation) { timeline in
            marqueeText(
                offset: offset(at: timeline.date, overflow: overflow),
                overflow: overflow,
                viewportWidth: measuredContainerWidth
            )
        }
    }

    private func marqueeText(offset: CGFloat, overflow: CGFloat, viewportWidth: CGFloat) -> some View {
        let explicitWidth = viewportWidth > 0 ? viewportWidth : constrainedWidth

        return Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .frame(width: explicitWidth, alignment: .leading)
            .frame(maxWidth: explicitWidth == nil ? .infinity : nil, alignment: .leading)
            .clipped()
            .background(alignment: .leading) {
                measuredText
            }
            .mask {
                fadeMask(offset: offset, overflow: overflow)
            }
    }

    private var measuredText: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .readContentWidth($contentWidth)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func offset(at date: Date, overflow: CGFloat) -> CGFloat {
        let elapsed = date.timeIntervalSince(animationStartDate)
        let progress = FadeMarqueeTextLayoutPolicy.scrollProgress(elapsed: elapsed, overflow: overflow)
        return FadeMarqueeTextLayoutPolicy.offset(forProgress: progress, overflow: overflow)
    }

    private func fadeMask(offset: CGFloat, overflow: CGFloat) -> some View {
        let leadingFadeStrength = FadeMarqueeTextLayoutPolicy.leadingFadeStrength(offset: offset, overflow: overflow)
        let trailingFadeStrength = FadeMarqueeTextLayoutPolicy.trailingFadeStrength(offset: offset, overflow: overflow)

        return LinearGradient(
            stops: [
                .init(color: .black.opacity(1 - leadingFadeStrength), location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .black.opacity(1 - trailingFadeStrength), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

@available(macOS 26.0, *)
private struct ContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@available(macOS 26.0, *)
private struct ContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@available(macOS 26.0, *)
private extension View {
    func readContentWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ContentWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ContentWidthPreferenceKey.self) { nextWidth in
            width.wrappedValue = nextWidth
        }
    }

    func readContainerWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ContainerWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ContainerWidthPreferenceKey.self) { nextWidth in
            width.wrappedValue = nextWidth
        }
    }
}
