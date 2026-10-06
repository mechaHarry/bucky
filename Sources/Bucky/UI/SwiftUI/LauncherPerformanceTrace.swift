import Foundation
import os

// Opt-in timings contain only fixed stage names and monotonic times, never
// queries, app names, filesystem paths, or commands.
@MainActor
final class LauncherPerformanceTrace {
    enum VisibilityEvent: String {
        case hotkeyReceived
        case toggleEntered
        case showStarted
        case panelOrderedFront
        case hideStarted
        case hideAnimationCompleted
        case panelOrderedOut
        case hiddenCleanupCompleted
    }

    enum Stage: String, Hashable {
        case visible
        case focusRequested
        case inputAccepted
        case resultsPublished
    }

    static let shared = LauncherPerformanceTrace(
        enabled: ProcessInfo.processInfo.environment["BUCKY_PERFORMANCE_TRACE"] == "1"
    )

    let enabled: Bool
    private let logger = Logger(subsystem: "local.bucky.performance", category: "input-readiness")
    private let signposter = OSSignposter(subsystem: "local.bucky.performance", category: "input-readiness")
    private var interval: OSSignpostIntervalState?
    private var startedAt: UInt64?
    private(set) var milliseconds: [Stage: Double] = [:]

    init(enabled: Bool) { self.enabled = enabled }

    func begin() {
        guard enabled else { return }
        cancel()
        startedAt = DispatchTime.now().uptimeNanoseconds
        milliseconds.removeAll(keepingCapacity: true)
        interval = signposter.beginInterval("Launcher input readiness", id: signposter.makeSignpostID())
    }

    func beginIfNeeded() {
        guard enabled else { return }
        if startedAt == nil || milliseconds[.inputAccepted] != nil { begin() }
    }

    func record(_ stage: Stage) {
        guard enabled, let startedAt, milliseconds[stage] == nil else { return }
        // A background refresh before the first keystroke is not input latency.
        guard stage != .resultsPublished || milliseconds[.inputAccepted] != nil else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        milliseconds[stage] = elapsed
        logger.info("Launcher \(stage.rawValue, privacy: .public): \(elapsed, privacy: .public) ms")
        if stage == .inputAccepted, let interval {
            signposter.endInterval("Launcher input readiness", interval)
            self.interval = nil
        }
    }

    func record(_ event: VisibilityEvent) {
        guard enabled else { return }
        let uptimeMilliseconds = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
        logger.info("Launcher visibility \(event.rawValue, privacy: .public): \(uptimeMilliseconds, privacy: .public) ms uptime")
    }

    func cancel() {
        guard enabled else { return }
        if let interval { signposter.endInterval("Launcher input readiness", interval) }
        interval = nil
        startedAt = nil
    }
}
