import SwiftUI

@available(macOS 26.0, *)
extension LauncherAnimationTiming {
    func animation(duration: TimeInterval, extraBounce: Double = 0) -> Animation {
        switch self {
        case .smooth:
            return .smooth(duration: duration, extraBounce: extraBounce)
        case .snappy:
            return .snappy(duration: duration, extraBounce: extraBounce)
        }
    }
}
