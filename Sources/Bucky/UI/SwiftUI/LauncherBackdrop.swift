import SwiftUI

// The retained launcher shell prepares this backdrop before presentation.
// Its appearance does not depend on opening, typing, or an idle timer.
@available(macOS 26.0, *)
struct LauncherBackdrop: View {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LauncherVisualStyle.resultsPaneCornerRadius,
                                     style: .continuous)
        ZStack {
            shape.fill(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : 0.25))
            if !reduceTransparency {
                shape.fill(Color.clear)
                    .glassEffect(.regular.tint(tint.opacity(LauncherVisualStyle.resultsPaneModeTintOpacity))
                        .interactive(false), in: shape)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
