import Foundation

@MainActor
protocol FileBrowserWorking {
    func run<Value>(_ operation: @escaping () throws -> Value, completion: @escaping (Result<Value, Error>) -> Void)
}

/// The model admits one operation at a time; blocking work runs on a serial worker.
@MainActor
final class FileBrowserWorker: FileBrowserWorking {
    private let queue = DispatchQueue(label: "local.bucky.files.operations", qos: .userInitiated)

    func run<Value>(_ operation: @escaping () throws -> Value, completion: @escaping (Result<Value, Error>) -> Void) {
        queue.async {
            let result = Result { try operation() }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// At most one running job and one pending job. New pending work replaces obsolete work.
final class FileBrowserLatestWorkQueue: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: (() -> Void)?
    private var scheduled = false

    init(queue: DispatchQueue) { self.queue = queue }

    func submit(_ job: @escaping () -> Void) {
        lock.lock()
        pending = job
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule { queue.async { [self] in drain() } }
    }

    func cancelPending() {
        lock.lock()
        pending = nil
        lock.unlock()
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            job()
        }
    }
}
