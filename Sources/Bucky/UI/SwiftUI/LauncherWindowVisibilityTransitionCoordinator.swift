import AppKit

@available(macOS 26.0, *)
enum WindowVisibilityState: Equatable {
    case hidden
    case showing
    case shown
    case hiding
}

@available(macOS 26.0, *)
enum WindowVisibilityIntent: Equatable {
    case show
    case hide
}

@available(macOS 26.0, *)
enum LauncherWindowShowTransitionDecision: Equatable {
    case materialize
    case replaceAnimation
    case synchronous
}

@available(macOS 26.0, *)
enum LauncherWindowShowTransitionPolicy {
    static func decision(
        priorPhase: WindowVisibilityState,
        isMaterialized: Bool
    ) -> LauncherWindowShowTransitionDecision {
        switch priorPhase {
        case .showing, .hiding:
            return .replaceAnimation
        case .hidden:
            return isMaterialized ? .synchronous : .materialize
        case .shown:
            return .synchronous
        }
    }
}

@available(macOS 26.0, *)
@MainActor
final class LauncherWindowVisibilityTransitionCoordinator {
    typealias AnimationCompletion = @MainActor () -> Void

    private let alphaDriver: any LauncherWindowAlphaAnimationDriver
    private let animationTiming: @MainActor () -> LauncherAnimationTiming
    private let didShow: @MainActor () -> Void
    private let didHide: @MainActor () -> Void

    private(set) var generation = 0
    private(set) var intent: WindowVisibilityIntent?
    private(set) var phase: WindowVisibilityState = .hidden

    init(
        alphaDriver: any LauncherWindowAlphaAnimationDriver,
        animationTiming: @escaping @MainActor () -> LauncherAnimationTiming,
        didShow: @escaping @MainActor () -> Void = {},
        didHide: @escaping @MainActor () -> Void = {}
    ) {
        self.alphaDriver = alphaDriver
        self.animationTiming = animationTiming
        self.didShow = didShow
        self.didHide = didHide
    }

    @discardableResult
    func request(_ intent: WindowVisibilityIntent) -> Int {
        generation += 1
        self.intent = intent
        phase = intent == .show ? .showing : .hiding
        alphaDriver.cancelAndNormalize()
        return generation
    }

    var targetAlpha: CGFloat {
        intent == .show ? 1 : 0
    }

    @discardableResult
    func startAnimation() -> Bool {
        startAnimation(completion: nil)
    }

    @discardableResult
    func startAnimation(completion: @escaping AnimationCompletion) -> Bool {
        startAnimation(completion: Optional(completion))
    }

    @discardableResult
    private func startAnimation(completion: AnimationCompletion?) -> Bool {
        guard let intent else { return false }
        let expectedPhase: WindowVisibilityState = intent == .show ? .showing : .hiding
        guard phase == expectedPhase else { return false }

        let expectedGeneration = generation
        let timing = animationTiming()
        let duration = LauncherWindowPresentationAnimationPolicy.duration(for: timing)
        let timingFunction = LauncherWindowPresentationAnimationPolicy.timingFunction(for: timing)
        let didStart = alphaDriver.animate(
            to: targetAlpha,
            duration: duration,
            timingFunction: timingFunction,
            completion: { [weak self] in
                if let completion {
                    completion()
                } else {
                    self?.complete(
                        generation: expectedGeneration,
                        intent: intent,
                        phase: expectedPhase
                    )
                }
            }
        )
        guard didStart else {
            alphaDriver.alphaValue = targetAlpha
            if let completion {
                completion()
            } else {
                complete(
                    generation: expectedGeneration,
                    intent: intent,
                    phase: expectedPhase
                )
            }
            return false
        }
        return true
    }

    func complete(
        generation: Int,
        intent: WindowVisibilityIntent,
        phase: WindowVisibilityState
    ) {
        guard self.generation == generation,
              self.intent == intent,
              self.phase == phase else {
            return
        }

        switch intent {
        case .show:
            self.phase = .shown
            didShow()
        case .hide:
            self.phase = .hidden
            didHide()
        }
    }
}

@available(macOS 26.0, *)
enum LauncherWindowPresentationAnimationPolicy {
    static func duration(for timing: LauncherAnimationTiming) -> TimeInterval {
        switch timing {
        case .smooth:
            return 0.20
        case .snappy:
            return 0.10
        }
    }

    static func timingFunction(for timing: LauncherAnimationTiming) -> CAMediaTimingFunction {
        switch timing {
        case .smooth:
            return CAMediaTimingFunction(name: .easeInEaseOut)
        case .snappy:
            return CAMediaTimingFunction(name: .easeOut)
        }
    }
}
