import AppKit
import Foundation

@available(macOS 26.0, *)
actor IconCache {
    typealias Loader = @Sendable (String) async -> NSImage?
    typealias FallbackIcon = @Sendable (String) -> NSImage
    typealias CacheKey = @Sendable (URL) -> String

    static let applications = IconCache(
        countLimit: 256,
        totalCostLimit: 8 * 1024 * 1024,
        maxConcurrentLoads: 4,
        cacheKey: { $0.path },
        loader: { path in IconCache.displayIcon(for: path, pixelSide: 80) },
        fallbackIcon: { _ in IconCache.emptyFallbackIcon() }
    )

    static let files = IconCache(
        countLimit: 192,
        totalCostLimit: 16 * 1024 * 1024,
        maxConcurrentLoads: 2,
        cacheKey: { $0.standardizedFileURL.path },
        loader: { path in IconCache.displayIcon(for: path, pixelSide: 144) },
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
    private let memoryPressureSource: DispatchSourceMemoryPressure

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
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        memoryPressureSource.setEventHandler { [weak self] in
            Task { await self?.removeAllCachedIcons() }
        }
        memoryPressureSource.resume()
    }

    deinit {
        memoryPressureSource.cancel()
    }

    /// NSCache handles routine eviction; release the warm cache on system memory pressure.
    func removeAllCachedIcons() {
        cache.removeAllObjects()
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
        // Sum every retained representation, rather than accounting only for the largest.
        icon.representations.reduce(0) { cost, representation in
            cost + max(1, representation.pixelsWide) * max(1, representation.pixelsHigh) * 4
        }
    }

    private static func displayIcon(for path: String, pixelSide: Int) -> NSImage? {
        // The system supplies file/app artwork; retain only a display-sized bitmap.
        autoreleasepool {
            rasterizedIcon(NSWorkspace.shared.icon(forFile: path), pixelSide: pixelSide)
        }
    }

    static func rasterizedIcon(_ source: NSImage, pixelSide: Int) -> NSImage? {
        guard pixelSide > 0, pixelSide <= 256,
              let context = CGContext(
                data: nil, width: pixelSide, height: pixelSide, bitsPerComponent: 8,
                bytesPerRow: pixelSide * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        var proposedRect = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        guard let image = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        let scale = min(CGFloat(pixelSide) / CGFloat(image.width), CGFloat(pixelSide) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (CGFloat(pixelSide) - width) / 2, y: (CGFloat(pixelSide) - height) / 2,
            width: width, height: height
        ))
        guard let bitmap = context.makeImage() else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: pixelSide / 2, height: pixelSide / 2))
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
