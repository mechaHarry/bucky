import AppKit
import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class IconCacheTests: XCTestCase {
    func testIconCacheReturnsCachedIconWithoutReloadingSameKey() async {
        let recorder = IconLoadRecorder()
        let cache = IconCache(
            countLimit: 2,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let url = URL(fileURLWithPath: "/tmp/Finder.app")

        let first = await cache.icon(for: url)
        let second = await cache.icon(for: url)

        XCTAssertIdentical(first, second)
        let loadCount = await recorder.loadCount(for: url.path)
        let cachedIcon = await cache.cachedIcon(for: url)
        XCTAssertEqual(loadCount, 1)
        XCTAssertIdentical(cachedIcon, first)
    }

    func testIconCacheCoalescesConcurrentLoadsForTheSameKey() async {
        let recorder = IconLoadRecorder(delayNanoseconds: 20_000_000)
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 2,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let url = URL(fileURLWithPath: "/tmp/Notes.app")

        async let first = cache.icon(for: url)
        async let second = cache.icon(for: url)
        let icons = await [first, second]

        XCTAssertIdentical(icons[0], icons[1])
        let loadCount = await recorder.loadCount(for: url.path)
        XCTAssertEqual(loadCount, 1)
    }

    func testCancellingOneSameKeyWaiterKeepsOtherWaiterOnLoadedIcon() async {
        let loadedIcon = Self.icon(named: "loaded")
        let fallbackIcon = Self.icon(named: "fallback")
        let recorder = GatedIconLoadRecorder(icon: loadedIcon)
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in fallbackIcon }
        )
        let url = URL(fileURLWithPath: "/tmp/Shared.app")

        let cancelledTask = Task { await cache.icon(for: url) }
        await recorder.waitUntilLoadStarts(for: url.path)
        let visibleTask = Task { await cache.icon(for: url) }
        await waitUntilWaiterCount(2, for: url, in: cache)

        cancelledTask.cancel()
        let cancelledIcon = await cancelledTask.value

        await recorder.releaseAll()
        let visibleIcon = await visibleTask.value

        XCTAssertIdentical(cancelledIcon, fallbackIcon)
        XCTAssertIdentical(visibleIcon, loadedIcon)
        let loadCount = await recorder.loadCount(for: url.path)
        XCTAssertEqual(loadCount, 1)
    }

    func testIconCacheLoadsMultipleKeysIndependently() async {
        let recorder = IconLoadRecorder()
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 2,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let firstURL = URL(fileURLWithPath: "/tmp/Notes.app")
        let secondURL = URL(fileURLWithPath: "/tmp/Terminal.app")

        let first = await cache.icon(for: firstURL)
        let second = await cache.icon(for: secondURL)

        XCTAssertNotIdentical(first, second)
        let firstLoadCount = await recorder.loadCount(for: firstURL.path)
        let secondLoadCount = await recorder.loadCount(for: secondURL.path)
        XCTAssertEqual(firstLoadCount, 1)
        XCTAssertEqual(secondLoadCount, 1)
    }

    func testIconCacheBoundsConcurrentLoads() async {
        let recorder = IconLoadRecorder(delayNanoseconds: 30_000_000)
        let cache = IconCache(
            countLimit: 8,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 2,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let urls = (0..<6).map { URL(fileURLWithPath: "/tmp/App\($0).app") }

        await withTaskGroup(of: NSImage.self) { group in
            for url in urls {
                group.addTask {
                    await cache.icon(for: url)
                }
            }

            for await _ in group {}
        }

        let maxActiveLoads = await recorder.maxActiveLoads()
        XCTAssertLessThanOrEqual(maxActiveLoads, 2)
    }

    func testCancellingPendingLoadRemovesItsInFlightState() async {
        let recorder = GatedIconLoadRecorder()
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let runningURL = URL(fileURLWithPath: "/tmp/Running.app")
        let cancelledURL = URL(fileURLWithPath: "/tmp/Cancelled.app")

        let runningTask = Task { await cache.icon(for: runningURL) }
        await recorder.waitUntilLoadStarts(for: runningURL.path)
        let runningLoadCount = await recorder.loadCount(for: runningURL.path)
        XCTAssertEqual(runningLoadCount, 1)

        let cancelledTask = Task { await cache.icon(for: cancelledURL) }
        await waitUntilWaiterCount(1, for: cancelledURL, in: cache)

        cancelledTask.cancel()
        _ = await cancelledTask.value
        await waitUntilWaiterCount(0, for: cancelledURL, in: cache)

        let cancelledLoadCount = await recorder.loadCount(for: cancelledURL.path)
        let inFlightLoadCount = await cache.inFlightLoadCount()
        XCTAssertEqual(cancelledLoadCount, 0)
        XCTAssertEqual(inFlightLoadCount, 1)

        await recorder.releaseAll()
        _ = await runningTask.value
        let finalInFlightLoadCount = await cache.inFlightLoadCount()
        XCTAssertEqual(finalInFlightLoadCount, 0)
    }

    func testFreshWaiterAfterLastCancellationStartsReplacementInsteadOfReceivingFallback() async {
        let loadedIcon = Self.icon(named: "loaded")
        let fallbackIcon = Self.icon(named: "fallback")
        let recorder = GatedIconLoadRecorder(icon: loadedIcon)
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { key in await recorder.load(key: key) },
            fallbackIcon: { _ in fallbackIcon }
        )
        let url = URL(fileURLWithPath: "/tmp/Replacement.app")

        let cancelledTask = Task { await cache.icon(for: url) }
        await recorder.waitUntilLoadStarts(for: url.path)
        cancelledTask.cancel()
        let cancelledIcon = await cancelledTask.value
        await waitUntilWaiterCount(0, for: url, in: cache)

        let freshTask = Task {
            await cache.icon(for: url)
        }
        await waitUntilWaiterCount(1, for: url, in: cache)
        await recorder.releaseAll()
        let freshIcon = await freshTask.value
        let loadCount = await recorder.loadCount(for: url.path)
        let cachedIcon = await cache.cachedIcon(for: url)

        XCTAssertIdentical(cancelledIcon, fallbackIcon)
        XCTAssertIdentical(freshIcon, loadedIcon)
        XCTAssertEqual(loadCount, 2)
        XCTAssertIdentical(cachedIcon, loadedIcon)
    }

    func testLastWaiterCancellationKeepsCapacityOccupiedUntilNonCooperativeLoaderCompletes() async {
        let recorder = GatedIconLoadRecorder()
        let cache = IconCache(
            countLimit: 4,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { key in await recorder.loadIgnoringCancellation(key: key) },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )
        let cancelledURL = URL(fileURLWithPath: "/tmp/Cancelled.app")
        let queuedURL = URL(fileURLWithPath: "/tmp/Queued.app")

        let cancelledTask = Task { await cache.icon(for: cancelledURL) }
        await recorder.waitUntilLoadStarts(for: cancelledURL.path)
        cancelledTask.cancel()
        _ = await cancelledTask.value

        let queuedTask = Task { await cache.icon(for: queuedURL) }
        await waitUntilWaiterCount(1, for: queuedURL, in: cache)
        let queuedLoadCountBeforeRelease = await recorder.loadCount(for: queuedURL.path)
        XCTAssertEqual(queuedLoadCountBeforeRelease, 0)

        await recorder.releaseAll()
        await recorder.waitUntilLoadStarts(for: queuedURL.path)
        _ = await queuedTask.value

        let cancelledLoadCount = await recorder.loadCount(for: cancelledURL.path)
        let queuedLoadCount = await recorder.loadCount(for: queuedURL.path)
        XCTAssertEqual(cancelledLoadCount, 1)
        XCTAssertEqual(queuedLoadCount, 1)
        let finalInFlightLoadCount = await cache.inFlightLoadCount()
        XCTAssertEqual(finalInFlightLoadCount, 0)
    }

    func testLoaderNilUsesFallbackIconAndCachesIt() async {
        let fallback = Self.icon(named: "fallback")
        let cache = IconCache(
            countLimit: 2,
            totalCostLimit: 1_000_000,
            maxConcurrentLoads: 1,
            loader: { _ -> NSImage? in nil },
            fallbackIcon: { _ in fallback }
        )
        let url = URL(fileURLWithPath: "/tmp/Missing.app")

        let icon = await cache.icon(for: url)

        XCTAssertIdentical(icon, fallback)
        let cachedIcon = await cache.cachedIcon(for: url)
        XCTAssertIdentical(cachedIcon, fallback)
    }

    func testIconCachePublishesConfiguredLimits() {
        let cache = IconCache(
            countLimit: 7,
            totalCostLimit: 12_345,
            maxConcurrentLoads: 3,
            loader: { _ -> NSImage? in nil },
            fallbackIcon: { _ in Self.icon(named: "fallback") }
        )

        XCTAssertEqual(cache.countLimit, 7)
        XCTAssertEqual(cache.totalCostLimit, 12_345)
        XCTAssertEqual(cache.maxConcurrentLoads, 3)
    }

    fileprivate static func icon(named name: String) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8))
    }

    private func waitUntilWaiterCount(
        _ expectedCount: Int,
        for url: URL,
        in cache: IconCache,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(1)
        while await cache.waiterCount(for: url) != expectedCount, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let actualCount = await cache.waiterCount(for: url)
        XCTAssertEqual(actualCount, expectedCount, file: file, line: line)
    }
}

@available(macOS 26.0, *)
private actor IconLoadRecorder {
    private let delayNanoseconds: UInt64
    private var counts: [String: Int] = [:]
    private var activeLoads = 0
    private var observedMaxActiveLoads = 0
    private var activeWaiters: [CheckedContinuation<Void, Never>] = []

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func load(key: String) async -> NSImage? {
        counts[key, default: 0] += 1
        activeLoads += 1
        observedMaxActiveLoads = max(observedMaxActiveLoads, activeLoads)
        resumeActiveWaiters()

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        activeLoads -= 1
        guard !Task.isCancelled else { return nil }
        return IconCacheTests.icon(named: key)
    }

    func loadCount(for key: String) -> Int {
        counts[key, default: 0]
    }

    func maxActiveLoads() -> Int {
        observedMaxActiveLoads
    }

    func waitUntilActiveLoadCountIsAtLeast(_ minimum: Int) async {
        guard activeLoads < minimum else { return }

        await withCheckedContinuation { continuation in
            activeWaiters.append(continuation)
        }
    }

    private func resumeActiveWaiters() {
        let waiters = activeWaiters
        activeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@available(macOS 26.0, *)
private actor GatedIconLoadRecorder {
    private let icon: NSImage?
    private var counts: [String: Int] = [:]
    private var activeLoads = 0
    private var activeWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadStartWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    init(icon: NSImage? = nil) {
        self.icon = icon
    }

    func load(key: String) async -> NSImage? {
        counts[key, default: 0] += 1
        activeLoads += 1
        resumeActiveWaiters()
        resumeLoadStartWaiters(for: key)

        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }

        activeLoads -= 1
        guard !Task.isCancelled else { return nil }
        return icon ?? IconCacheTests.icon(named: key)
    }

    func loadIgnoringCancellation(key: String) async -> NSImage? {
        counts[key, default: 0] += 1
        activeLoads += 1
        resumeActiveWaiters()
        resumeLoadStartWaiters(for: key)

        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }

        activeLoads -= 1
        return icon ?? IconCacheTests.icon(named: key)
    }

    func releaseAll() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func loadCount(for key: String) -> Int {
        counts[key, default: 0]
    }

    func waitUntilLoadStarts(for key: String) async {
        guard counts[key, default: 0] == 0 else { return }

        await withCheckedContinuation { continuation in
            loadStartWaiters[key, default: []].append(continuation)
        }
    }

    func waitUntilActiveLoadCountIsAtLeast(_ minimum: Int) async {
        guard activeLoads < minimum else { return }

        await withCheckedContinuation { continuation in
            activeWaiters.append(continuation)
        }
    }

    private func resumeActiveWaiters() {
        let waiters = activeWaiters
        activeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeLoadStartWaiters(for key: String) {
        let waiters = loadStartWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
