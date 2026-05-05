import SwiftUI

@available(macOS 26.0, *)
struct FadeMarqueeText: View {
    let text: String
    var font: Font = .body

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let overflow = max(0, contentWidth - containerWidth)

        Group {
            if overflow > 1, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    marqueeText(offset: -overflow * oscillation(at: timeline.date), overflow: overflow)
                }
            } else {
                marqueeText(offset: 0, overflow: overflow)
            }
        }
        .readContainerWidth($containerWidth)
    }

    private func marqueeText(offset: CGFloat, overflow: CGFloat) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .readContentWidth($contentWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask {
                fadeMask(offset: offset, overflow: overflow)
            }
    }

    private func oscillation(at date: Date) -> CGFloat {
        let period = 5.2
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    private func fadeMask(offset: CGFloat, overflow: CGFloat) -> some View {
        let leadingFades = overflow > 1 && offset < -1
        let trailingFades = overflow > 1 && offset > -overflow + 1

        return LinearGradient(
            stops: [
                .init(color: leadingFades ? .clear : .black, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: trailingFades ? .clear : .black, location: 1)
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
