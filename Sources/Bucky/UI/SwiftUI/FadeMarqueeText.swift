import SwiftUI

@available(macOS 26.0, *)
struct FadeMarqueeText: View {
    let text: String
    var font: Font = .body

    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let overflow = max(0, contentWidth - containerWidth)
            let offset = overflow > 1 ? -overflow * oscillation(at: timeline.date) : 0

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
        .readContainerWidth($containerWidth)
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
