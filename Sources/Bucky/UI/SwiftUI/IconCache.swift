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
    private var pendingIconWaiters: [UUID: CheckedContinuation<NSImage?, Never>] = [:]
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
        if let cachedIcon = await cachedIcon(for: url) {
            return cachedIcon
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                return fallbackIcon(key)
            }

            if let cachedIcon = await registerWaiter(id: waiterID, key: key) {
                return cachedIcon
            }

            return await waitForIcon(id: waiterID, key: key) ?? fallbackIcon(key)
        } onCancel: {
            Task.detached { [weak self] in
                await self?.cancelWaiter(id: waiterID, key: key)
            }
        }
    }

    func inFlightLoadCount() -> Int {
        inFlightLoads.count
    }

    func waiterCount(for url: URL) -> Int {
        inFlightLoads[cacheKey(url)]?.waiterIDs.count ?? 0
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

    private func waitForIcon(id: UUID, key: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            guard !Task.isCancelled else {
                continuation.resume(returning: nil)
                return
            }

            if let completedIcon = completedIconsByWaiterID.removeValue(forKey: id) {
                continuation.resume(returning: completedIcon)
                return
            }

            guard inFlightLoads[key]?.waiterIDs.contains(id) == true else {
                continuation.resume(returning: nil)
                return
            }

            pendingIconWaiters[id] = continuation
        }
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
            load.isActive = true
            let loadID = load.id
            let loader = loader
            let fallbackIcon = fallbackIcon
            load.task = Task.detached(priority: .utility) { [weak self] in
                let icon = await loader(key) ?? fallbackIcon(key)
                await self?.completeLoad(key: key, loadID: loadID, icon: icon)
            }
            inFlightLoads[key] = load
        }
    }

    private func completeLoad(key: String, loadID: UUID, icon: NSImage) {
        guard let load = inFlightLoads[key],
              load.id == loadID else {
            return
        }
        inFlightLoads.removeValue(forKey: key)

        if load.cancellationRequested, !load.waiterIDs.isEmpty {
            let replacement = InFlightLoad(waiterIDs: load.waiterIDs)
            inFlightLoads[key] = replacement
            pendingLoadKeys.append(key)

            if load.isActive {
                activeLoadCount = max(0, activeLoadCount - 1)
            }
            scheduleLoadsAfterCancellationCleanup()
            return
        }

        if !load.waiterIDs.isEmpty {
            cache.setObject(icon, forKey: key as NSString, cost: estimatedCost(for: icon))
        }

        for waiterID in load.waiterIDs {
            if let continuation = pendingIconWaiters.removeValue(forKey: waiterID) {
                continuation.resume(returning: icon)
            } else {
                completedIconsByWaiterID[waiterID] = icon
            }
        }

        if load.isActive {
            activeLoadCount = max(0, activeLoadCount - 1)
        }
        scheduleLoadsAfterCancellationCleanup()
    }

    private func cancelWaiter(id: UUID, key: String) {
        completedIconsByWaiterID.removeValue(forKey: id)
        if let continuation = pendingIconWaiters.removeValue(forKey: id) {
            continuation.resume(returning: nil)
        }
        guard var load = inFlightLoads[key],
              load.waiterIDs.remove(id) != nil else {
            return
        }

        if load.waiterIDs.isEmpty {
            pendingLoadKeys.removeAll { $0 == key }
            load.task?.cancel()

            if load.isActive {
                load.cancellationRequested = true
                inFlightLoads[key] = load
                return
            }

            inFlightLoads.removeValue(forKey: key)
            scheduleLoadsAfterCancellationCleanup()
            return
        }

        inFlightLoads[key] = load
    }

    private func scheduleLoadsAfterCancellationCleanup() {
        Task { [weak self] in
            await Task.yield()
            await self?.scheduleAvailableLoads()
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
    let id = UUID()
    var task: Task<Void, Never>?
    var waiterIDs: Set<UUID> = []
    var isActive = false
    var cancellationRequested = false

    init(waiterIDs: Set<UUID> = []) {
        self.waiterIDs = waiterIDs
    }
}
