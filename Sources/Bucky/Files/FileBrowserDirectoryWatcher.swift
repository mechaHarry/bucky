import Darwin
import Foundation

final class FileBrowserDirectoryWatcher: FileBrowserDirectoryObserving {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "com.mechaHarry.bucky.file-browser.directory-watcher", qos: .utility)) {
        self.queue = queue
    }

    func observe(
        directory: URL,
        onChange: @escaping @MainActor () -> Void
    ) -> FileBrowserDirectoryObservation? {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: queue
        )
        let observation = VnodeDirectoryObservation(source: source)

        source.setEventHandler {
            Task { @MainActor in
                onChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        return observation
    }
}

private final class VnodeDirectoryObservation: FileBrowserDirectoryObservation {
    private let source: DispatchSourceFileSystemObject
    private var isCancelled = false

    init(source: DispatchSourceFileSystemObject) {
        self.source = source
    }

    deinit {
        cancel()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        source.cancel()
    }
}
