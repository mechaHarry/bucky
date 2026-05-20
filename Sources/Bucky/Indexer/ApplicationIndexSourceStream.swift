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
        appSupportDirectory: URL = BuckyPaths.appSupportDirectory,
        systemSettingsResourcesDirectory: URL = URL(
            fileURLWithPath: "/System/Applications/System Settings.app/Contents/Resources",
            isDirectory: true
        ),
        systemSettingsExtensionRoots: [URL] = SystemSettingsIndexer.defaultExtensionRoots
    ) -> [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []

        for url in applicationRoots + [systemSettingsResourcesDirectory] + systemSettingsExtensionRoots + [appSupportDirectory] {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            urls.append(url)
        }

        return urls
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
        }
    }
}

struct ApplicationIndexSourceStreamPolicy {
    static let queueLabel = "com.mechaHarry.bucky.application-index-source-stream"
    static let queueQoS: DispatchQoS = .utility
}

final class ApplicationIndexSourceStream {
    private let urls: [URL]
    private let debounceInterval: TimeInterval
    private let fileManager: FileManager
    private let queue: DispatchQueue
    private let onChange: @MainActor () -> Void
    private var stream: FSEventStreamRef?
    private var pendingChange: DispatchWorkItem?

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
        self.debounceInterval = debounceInterval
        self.fileManager = fileManager
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let paths = existingWatchPaths()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            applicationIndexSourceStreamCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pendingChange?.cancel()
        pendingChange = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handleEvent(paths: [String]) {
        guard paths.isEmpty || paths.contains(where: {
            ApplicationIndexWatchPolicy.shouldTriggerChange(eventPath: $0, watchURLs: urls)
        }) else {
            return
        }

        scheduleChange()
    }

    private func scheduleChange() {
        pendingChange?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onChange()
            }
        }
        pendingChange = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func existingWatchPaths() -> [String] {
        urls.compactMap { url in
            if url == BuckyPaths.appSupportDirectory {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return fileManager.fileExists(atPath: url.path) ? url.path : nil
        }
    }
}

private let applicationIndexSourceStreamCallback: FSEventStreamCallback = { _, info, numberOfEvents, eventPaths, _, _ in
    guard let info else { return }
    let stream = Unmanaged<ApplicationIndexSourceStream>.fromOpaque(info).takeUnretainedValue()

    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        .compactMap { $0 as? String }
    stream.handleEvent(paths: Array(paths.prefix(numberOfEvents)))
}
