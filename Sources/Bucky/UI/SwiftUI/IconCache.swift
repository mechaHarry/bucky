import AppKit
import Foundation

@available(macOS 26.0, *)
actor IconCache {
    typealias Loader = @Sendable (String) async -> NSImage?
    typealias FallbackIcon = @Sendable (String) -> NSImage
    typealias CacheKey = @Sendable (URL) -> String

    static let applications = IconCache(
        countLimit: AppIconPreloadPolicy.preloadLimit,
        totalCostLimit: 128 * 1024 * 1024,
        maxConcurrentLoads: 4,
        cacheKey: { $0.path },
        loader: { path in NSWorkspace.shared.icon(forFile: path) },
        fallbackIcon: { _ in IconCache.emptyFallbackIcon() }
    )

    static let files = IconCache(
        countLimit: FileIconPreloadPolicy.preloadLimit,
        totalCostLimit: 128 * 1024 * 1024,
        maxConcurrentLoads: 2,
        cacheKey: { $0.standardizedFileURL.path },
        loader: { path in NSWorkspace.shared.icon(forFile: path) },
        fallbackIcon: { _ in IconCache.emptyFallbackIcon() }
    )

    nonisolated let countLimit: Int
    nonisolated let totalCostLimit: Int
    nonisolated let maxConcurrentLoads: Int

    private let cache = NSCache<NSString, NSImage>()
    nonisolated private let cacheKey: CacheKey
    private let loader: Loader
    nonisolated private let fallbackIcon: FallbackIcon
    private var inFlightLoads: [String: InFlightLoad] = [:]
    private var pendingLoadKeys: [String] = []
    private var completedIconsByWaiterID: [UUID: NSImage] = [:]
    private var activeLoadCount = 0

    init(
        countLimit: Int,
        totalCostLimit: Int,
        maxConcurrentLoads: Int,
        cacheKey: @escaping CacheKey = { $0.path },
        loader: @escaping Loader,
        fallbackIcon: @escaping FallbackIcon
    ) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.maxConcurrentLoads = max(1, maxConcurrentLoads)
        self.cacheKey = cacheKey
        self.loader = loader
        self.fallbackIcon = fallbackIcon
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func cachedIcon(for url: URL) -> NSImage? {
        cache.object(forKey: cacheKey(url) as NSString)
    }

    nonisolated func icon(for url: URL) async -> NSImage {
        let key = cacheKey(url)
        let currentTask = withUnsafeCurrentTask { $0 }
        if let cachedIcon = await cachedIcon(for: url) {
            return cachedIcon
        }
        guard currentTask?.isCancelled != true else {
            return fallbackIcon(key)
        }

        let waiterID = UUID()
        if let cachedIcon = await registerWaiter(id: waiterID, key: key) {
            return cachedIcon
        }

        while true {
            if currentTask?.isCancelled == true {
                await cancelWaiter(id: waiterID, key: key)
                return fallbackIcon(key)
            }

            if let icon = await completedIcon(for: waiterID) {
                return icon
            }

            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func inFlightLoadCount() -> Int {
        inFlightLoads.count
    }

    func cancelLoad(for url: URL) {
        cancelLoad(forKey: cacheKey(url))
    }

    private func registerWaiter(id waiterID: UUID, key: String) -> NSImage? {
        if let cachedIcon = cache.object(forKey: key as NSString) {
            return cachedIcon
        }
        guard !Task.isCancelled else {
            return fallbackIcon(key)
        }

        if inFlightLoads[key] == nil {
            inFlightLoads[key] = InFlightLoad()
            pendingLoadKeys.append(key)
        }

        inFlightLoads[key]?.waiterIDs.insert(waiterID)
        scheduleAvailableLoads()
        return nil
    }

    private func completedIcon(for waiterID: UUID) -> NSImage? {
        completedIconsByWaiterID.removeValue(forKey: waiterID)
    }

    private func scheduleAvailableLoads() {
        while activeLoadCount < maxConcurrentLoads,
              let key = pendingLoadKeys.first {
            pendingLoadKeys.removeFirst()

            guard var load = inFlightLoads[key],
                  !load.waiterIDs.isEmpty,
                  load.task == nil else {
                continue
            }

            activeLoadCount += 1
            let loader = loader
            let fallbackIcon = fallbackIcon
            load.task = Task.detached(priority: .utility) { [weak self] in
                let icon = await loader(key) ?? fallbackIcon(key)
                await self?.completeLoad(key: key, icon: icon)
            }
            inFlightLoads[key] = load
        }
    }

    private func completeLoad(key: String, icon: NSImage) {
        guard let load = inFlightLoads.removeValue(forKey: key) else {
            return
        }

        if !load.waiterIDs.isEmpty {
            cache.setObject(icon, forKey: key as NSString, cost: estimatedCost(for: icon))
        }

        for waiterID in load.waiterIDs {
            completedIconsByWaiterID[waiterID] = icon
        }

        activeLoadCount = max(0, activeLoadCount - 1)
        Task { [weak self] in
            await Task.yield()
            await self?.scheduleAvailableLoads()
        }
    }

    private func cancelWaiter(id: UUID, key: String) {
        completedIconsByWaiterID.removeValue(forKey: id)
        guard var load = inFlightLoads[key],
              load.waiterIDs.remove(id) != nil else {
            return
        }

        if load.waiterIDs.isEmpty {
            if let task = load.task {
                task.cancel()
                inFlightLoads[key] = load
            } else {
                inFlightLoads.removeValue(forKey: key)
                pendingLoadKeys.removeAll { $0 == key }
            }
            return
        }

        inFlightLoads[key] = load
    }

    private func cancelLoad(forKey key: String) {
        guard let load = inFlightLoads.removeValue(forKey: key) else {
            return
        }

        pendingLoadKeys.removeAll { $0 == key }
        load.task?.cancel()
        let fallback = fallbackIcon(key)
        for waiterID in load.waiterIDs {
            completedIconsByWaiterID[waiterID] = fallback
        }

        if load.task != nil {
            activeLoadCount = max(0, activeLoadCount - 1)
            Task { [weak self] in
                await Task.yield()
                await self?.scheduleAvailableLoads()
            }
        }
    }

    private func estimatedCost(for icon: NSImage) -> Int {
        let largestPixelArea = icon.representations
            .map { max(1, $0.pixelsWide) * max(1, $0.pixelsHigh) }
            .max() ?? Int(max(1, icon.size.width) * max(1, icon.size.height))

        return largestPixelArea * 4
    }

    private static func emptyFallbackIcon() -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }
}

@available(macOS 26.0, *)
private struct InFlightLoad {
    var task: Task<Void, Never>?
    var waiterIDs: Set<UUID> = []
}
