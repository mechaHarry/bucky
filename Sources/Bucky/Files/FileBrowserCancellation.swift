import Foundation

/// Shared by bounded workers and previews; cancellation is safe from any queue.
final class FileBrowserCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var onCancel: (() -> Void)?

    init(onCancel: (() -> Void)? = nil) { self.onCancel = onCancel }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }

    func setCancelAction(_ action: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            action()
        } else {
            onCancel = action
            lock.unlock()
        }
    }

    deinit { cancel() }
}
