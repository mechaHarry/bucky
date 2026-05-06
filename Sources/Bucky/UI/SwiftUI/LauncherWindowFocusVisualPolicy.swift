import CoreGraphics

@available(macOS 26.0, *)
struct LauncherWindowFocusVisualPolicy {
    static func contentOpacity(isKeyWindow: Bool) -> Double {
        isKeyWindow ? 1 : 0.72
    }

    static func iconOpacity(isKeyWindow: Bool) -> Double {
        contentOpacity(isKeyWindow: isKeyWindow)
    }

    static func textOpacity(isKeyWindow: Bool) -> Double {
        contentOpacity(isKeyWindow: isKeyWindow)
    }

    static func dimOverlayOpacity(isKeyWindow: Bool) -> Double {
        isKeyWindow ? 0 : 0.34
    }

    static func blurRadius(isKeyWindow: Bool) -> CGFloat {
        isKeyWindow ? 0 : 1.1
    }
}
