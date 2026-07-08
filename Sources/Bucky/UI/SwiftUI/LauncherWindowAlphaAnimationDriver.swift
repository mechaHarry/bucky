import AppKit

@available(macOS 26.0, *)
@MainActor
protocol LauncherWindowAlphaAnimationDriver: AnyObject {
    var alphaValue: CGFloat { get set }

    func cancelAndNormalize()

    @discardableResult
    func animate(
        to alpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor () -> Void
    ) -> Bool
}

@available(macOS 26.0, *)
@MainActor
final class AppKitLauncherWindowAlphaAnimationDriver: LauncherWindowAlphaAnimationDriver {
    private weak var window: NSWindow?

    var alphaValue: CGFloat {
        get { window?.alphaValue ?? 0 }
        set { window?.alphaValue = newValue }
    }

    init(window: NSWindow) {
        self.window = window
    }

    func cancelAndNormalize() {
        guard let window else { return }
        let currentAlpha = window.alphaValue

        // Assigning through animator at duration zero replaces an in-flight property animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().alphaValue = currentAlpha
        }
    }

    @discardableResult
    func animate(
        to alpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let window else { return false }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            window.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                completion()
            }
        }
        return true
    }
}
