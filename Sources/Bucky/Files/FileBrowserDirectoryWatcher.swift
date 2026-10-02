import Darwin
import Foundation

final class FileBrowserDirectoryWatcher: FileBrowserDirectoryObserving {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "local.bucky.file-browser.directory-watcher", qos: .utility)) {
        self.queue = queue
    }

    func observe(
        directory: URL,
        onChange: @escaping @MainActor () -> Void
    ) -> FileBrowserDirectoryObservation? {
        let cancellation = FileBrowserCancellation()
        let queue = queue
        queue.async { [weak cancellation] in
            guard let cancellation, !cancellation.isCancelled else { return }
            let descriptor = open(directory.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
                queue: queue
            )
            source.setEventHandler { [weak cancellation] in
                Task { @MainActor [weak cancellation] in
                    guard let cancellation, !cancellation.isCancelled else { return }
                    onChange()
                }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            cancellation.setCancelAction { source.cancel() }
        }
        return VnodeDirectoryObservation(cancellation: cancellation)
    }
}

private final class VnodeDirectoryObservation: FileBrowserDirectoryObservation {
    private let cancellation: FileBrowserCancellation

    init(cancellation: FileBrowserCancellation) {
        self.cancellation = cancellation
    }

    deinit {
        cancel()
    }

    func cancel() {
        cancellation.cancel()
    }
}
