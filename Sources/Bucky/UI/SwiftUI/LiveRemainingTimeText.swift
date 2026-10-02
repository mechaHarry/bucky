import SwiftUI

// Only the visible time text ticks; stable row metadata and launcher inputs never do.
@available(macOS 26.0, *)
struct LiveRemainingTimeText: View {
    let target: Date
    @State private var isVisible = false
    @State private var isComplete = false

    var body: some View {
        Group {
            if isComplete {
                Text(CountdownRemaining.zero.displayString)
            } else {
                TimelineView(.animation(minimumInterval: Double(CountdownStone.refreshIntervalNanoseconds) / 1_000_000_000,
                                        paused: !isVisible)) { context in
                    Text(CountdownRemaining(until: target, now: context.date).displayString)
                        .onChange(of: context.date >= target) { _, complete in
                            if complete { isComplete = true }
                        }
                }
            }
        }
        .monospacedDigit()
        .transaction { $0.animation = nil }
        .onAppear {
            isComplete = Date() >= target
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onChange(of: target) { _, target in isComplete = Date() >= target }
    }
}
