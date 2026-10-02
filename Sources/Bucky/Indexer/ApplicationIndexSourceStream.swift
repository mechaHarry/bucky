import CoreServices
import Foundation

struct ApplicationIndexWatchPolicy {
    static let appSupportIndexedFilenames: Set<String> = [
        "settings.json",
        "inclusions.json",
        "exclusions.json"
    ]

    static func watchURLs(
        applicationRoots: [URL] = ApplicationIndexer.defaultRoots,
        includedPaths: Set<String> = [],
        appSupportDirectory: URL = BuckyPaths.appSupportDirectory,
        systemSettingsResourcesDirectory: URL = URL(
            fileURLWithPath: "/System/Applications/System Settings.app/Contents/Resources",
            isDirectory: true
        ),
        systemSettingsExtensionRoots: [URL] = SystemSettingsIndexer.defaultExtensionRoots
    ) -> [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []

        let includedParents = includedPaths.sorted().map {
            URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent()
        }
        for url in applicationRoots + [systemSettingsResourcesDirectory] + systemSettingsExtensionRoots + [appSupportDirectory] + includedParents {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            urls.append(url)
        }

        return urls
    }

    static func existingWatchURLs(for urls: [URL], fileManager: FileManager = .default) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            var ancestor = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            while !fileManager.fileExists(atPath: ancestor.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                let parent = ancestor.deletingLastPathComponent()
                guard parent.path != ancestor.path else { return nil }
                ancestor = parent
            }
            return seen.insert(ancestor.path).inserted ? ancestor : nil
        }
    }

    static func shouldTriggerChange(
        eventPath: String,
        watchURLs: [URL],
        appSupportDirectory: URL = BuckyPaths.appSupportDirectory
    ) -> Bool {
        let eventURL = URL(fileURLWithPath: eventPath)
        let eventPath = eventURL.standardizedFileURL.path
        let appSupportPath = appSupportDirectory.standardizedFileURL.path

        if eventPath == appSupportPath || eventPath.hasPrefix(appSupportPath + "/") {
            return appSupportIndexedFilenames.contains(eventURL.lastPathComponent)
        }

        return watchURLs.contains { watchedURL in
            let watchedPath = watchedURL.standardizedFileURL.path
            guard watchedPath != appSupportPath else { return false }
            return eventPath == watchedPath || eventPath.hasPrefix(watchedPath + "/")
                || watchedPath.hasPrefix(eventPath == "/" ? "/" : eventPath + "/")
        }
    }
}

struct ApplicationIndexSourceStreamPolicy {
    static let queueLabel = "local.bucky.application-index-source-stream"
    static let queueQoS: DispatchQoS = .utility
}

final class ApplicationIndexSourceStream {
    private let baseURLs: [URL]
    private var urls: [URL]
    private var includedPaths: Set<String> = []
    private let debounceInterval: TimeInterval
    private let fileManager: FileManager
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var pendingChange: DispatchWorkItem?
    private var isStarted = false
    private var actualWatchPaths: [String] = []
    private var changeGeneration = 0

    init(
        urls: [URL] = ApplicationIndexWatchPolicy.watchURLs(),
        debounceInterval: TimeInterval = 0.35,
        fileManager: FileManager = .default,
        queue: DispatchQueue = DispatchQueue(
            label: ApplicationIndexSourceStreamPolicy.queueLabel,
            qos: ApplicationIndexSourceStreamPolicy.queueQoS
        ),
        onChange: @escaping @MainActor () -> Void
    ) {
        self.urls = urls
        baseURLs = urls
        self.debounceInterval = debounceInterval
        self.fileManager = fileManager
        self.queue = queue
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStarted = true
            self.restartOnQueue()
        }
    }

    /// Controller calls this after reindexing and inclusion changes.
    func updateIncludedPaths(_ paths: Set<String>) {
        queue.async { [weak self] in
            guard let self, paths != self.includedPaths else { return }
            self.includedPaths = paths
            let parents = paths.sorted().map {
                URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent()
            }
            var seen = Set<String>()
            self.urls = (self.baseURLs + parents).filter { seen.insert($0.standardizedFileURL.path).inserted }
            if self.isStarted { self.restartOnQueue() }
        }
    }

    private func restartOnQueue() {
        stopOnQueue()
        let paths = ApplicationIndexWatchPolicy.existingWatchURLs(for: urls, fileManager: fileManager).map(\.path)
        actualWatchPaths = paths
        guard !paths.isEmpty else { return }

        let callbackContext = ApplicationIndexCallbackContext(owner: self)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackContext).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<ApplicationIndexCallbackContext>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<ApplicationIndexCallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let stream = withExtendedLifetime(callbackContext, {
            FSEventStreamCreate(
            kCFAllocatorDefault,
            applicationIndexSourceStreamCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            )
        }) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) { stopOnQueue() }
    }

    func stop() {
        onQueue {
            isStarted = false
            stopOnQueue()
        }
    }

    private func stopOnQueue() {
        changeGeneration += 1
        pendingChange?.cancel()
        pendingChange = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handleEvent(paths: [String], mustRescan: Bool = false) {
        guard isStarted else { return }
        let nextPaths = ApplicationIndexWatchPolicy.existingWatchURLs(for: urls, fileManager: fileManager).map(\.path)
        let coverageChanged = nextPaths != actualWatchPaths
        if coverageChanged { restartOnQueue() }
        guard mustRescan || coverageChanged || paths.isEmpty || paths.contains(where: {
            ApplicationIndexWatchPolicy.shouldTriggerChange(eventPath: $0, watchURLs: urls)
        }) else {
            return
        }

        scheduleChange()
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        changeGeneration += 1
        let generation = changeGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.onQueue({ self.isStarted && self.changeGeneration == generation }) else { return }
                self.onChange()
            }
        }
        pendingChange = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func onQueue<Value>(_ operation: () -> Value) -> Value {
        if DispatchQueue.getSpecific(key: queueKey) == true { return operation() }
        return queue.sync(execute: operation)
    }
}

private final class ApplicationIndexCallbackContext {
    weak var owner: ApplicationIndexSourceStream?
    init(owner: ApplicationIndexSourceStream) { self.owner = owner }
}

private let applicationIndexSourceStreamCallback: FSEventStreamCallback = { _, info, numberOfEvents, eventPaths, flags, _ in
    guard let info else { return }
    guard let stream = Unmanaged<ApplicationIndexCallbackContext>.fromOpaque(info).takeUnretainedValue().owner else { return }

    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        .compactMap { $0 as? String }
    let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
    let mustRescan = (0..<numberOfEvents).contains { flags[$0] & rescanFlags != 0 }
    stream.handleEvent(paths: Array(paths.prefix(numberOfEvents)), mustRescan: mustRescan)
}
