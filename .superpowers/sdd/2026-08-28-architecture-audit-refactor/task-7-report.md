# Task 7 Report: Application Search Engine and Icon Cache Consolidation

## Summary

Implemented Task 7 only. Application ranking/tokenization/scoring now lives in `ApplicationSearchEngine`, with `LiquidGlassLauncherModel.filter(_:normalizedQuery:)` and `filterIDs(_:rowStore:normalizedQuery:)` preserved as compatibility/performance wrappers. App and file icon loading now share `IconCache`, configured separately for applications and files.

No persistence extraction, view extraction, README changes, architecture documentation changes, or version bump were performed.

## Exact Interfaces

```swift
struct ApplicationSearchCandidate: Hashable {
    let sourceIndex: Int
    let title: String
    let searchText: String

    init(sourceIndex: Int, title: String, searchText: String)
    init(sourceIndex: Int, item: LaunchItem)
}

enum ApplicationSearchEngine {
    static func tokens(for normalizedQuery: String) -> [String]
    static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem]
    static func filterIDs(
        _ ids: [AppRowID],
        rowStore: ApplicationRowStore,
        normalizedQuery: String
    ) -> [AppRowID]
    static func rankedCandidates(
        _ candidates: [ApplicationSearchCandidate],
        normalizedQuery: String
    ) -> [ApplicationSearchCandidate]
}

@available(macOS 26.0, *)
actor IconCache {
    typealias Loader = @Sendable (String) async -> NSImage?
    typealias FallbackIcon = @Sendable (String) -> NSImage
    typealias CacheKey = @Sendable (URL) -> String

    static let applications: IconCache
    static let files: IconCache

    nonisolated let countLimit: Int
    nonisolated let totalCostLimit: Int
    nonisolated let maxConcurrentLoads: Int

    init(
        countLimit: Int,
        totalCostLimit: Int,
        maxConcurrentLoads: Int,
        cacheKey: @escaping CacheKey = { $0.path },
        loader: @escaping Loader,
        fallbackIcon: @escaping FallbackIcon
    )

    func cachedIcon(for url: URL) -> NSImage?
    nonisolated func icon(for url: URL) async -> NSImage
    func inFlightLoadCount() -> Int
    func cancelLoad(for url: URL)
}
```

## Search Behavior

- Empty normalized queries return all inputs in original source order for both in-memory items and indexed row IDs.
- Non-empty queries split on whitespace through `ApplicationSearchEngine.tokens(for:)`.
- Ranking order remains: exact title match, title prefix, title word prefix, title substring, then search-text-only match.
- Score ties are ordered by `localizedStandardCompare` on title.
- Equal-title ties are now explicitly deterministic by original source index.
- Indexed and in-memory paths use the same tokenization and scoring implementation and tests cover equivalent rankings for equivalent inputs.
- `LiquidGlassLauncherModel.filter` remains the performance-facing wrapper used by the existing benchmark.

## Icon Cache Bounds and Concurrency Behavior

- `IconCache.applications`: count limit `256`, cost limit `134217728` bytes, max concurrent loads `4`, key is `url.path`.
- `IconCache.files`: count limit `768`, cost limit `134217728` bytes, max concurrent loads `2`, key is `url.standardizedFileURL.path`.
- Same-key requests coalesce through one in-flight load entry with multiple waiter IDs.
- Different keys are queued and scheduled only while `activeLoadCount < maxConcurrentLoads`.
- `NSCache` owns completed `NSImage` values and enforces count/cost eviction; in-flight dictionaries retain only currently requested keys and waiter IDs.
- `cancelLoad(for:)` removes queued loads, cancels running tasks when explicitly cancelled, drops pending queue entries, and releases waiter IDs with fallback images.
- App/file preload policies and fallback symbols remain in their original views; the shared cache only supplies fallback `NSImage` values when a loader returns `nil` or a load is explicitly cancelled.

## Files Changed

- Added `Sources/Bucky/Indexer/ApplicationSearchEngine.swift`.
- Added `Sources/Bucky/UI/SwiftUI/IconCache.swift`.
- Modified `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`.
- Modified `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`.
- Modified `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`.
- Added `Tests/BuckyTests/ApplicationSearchEngineTests.swift`.
- Added `Tests/BuckyTests/IconCacheTests.swift`.
- Added `.superpowers/sdd/2026-08-28-architecture-audit-refactor/task-7-report.md`.

## Commands and Pristine Outputs

RED:

```text
$ swift test --filter 'ApplicationSearchEngineTests|IconCacheTests'
error: cannot find 'ApplicationSearchEngine' in scope
error: cannot find 'IconCache' in scope
Process exited with code 1
```

Focused search/cache/wrapper/performance:

```text
$ swift test --filter 'LiquidGlassLauncherFilterTests|ApplicationRowStoreTests|ApplicationSearchEngineTests|IconCacheTests|LauncherFilterPerformanceTests'
Test Suite 'Selected tests' passed
Executed 26 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 333.116 ms, baseline 361.139 ms, delta -7.76%, band comfort, samples min/median/max 330.632/333.116/337.941 ms
Process exited with code 0
```

Broader launcher-related tests:

```text
$ swift test --filter 'Launcher|LiquidGlassLauncher|ApplicationSearchEngine|ApplicationRowStore|IconCache|FileBrowserPreviewPolicy'
Test Suite 'Selected tests' passed
Executed 141 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 333.896 ms, baseline 361.139 ms, delta -7.54%, band comfort, samples min/median/max 327.363/333.896/341.967 ms
Process exited with code 0
```

Full suite:

```text
$ swift test
Test Suite 'All tests' passed
Executed 330 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 332.277 ms, baseline 361.139 ms, delta -7.99%, band comfort, samples min/median/max 331.433/332.277/334.775 ms
Process exited with code 0
```

Whitespace/diff hygiene:

```text
$ git diff --check
Process exited with code 0
```

## Performance Comparison

- Initial refactor benchmark failed: current median `421.390 ms`, baseline `361.139 ms`, delta `+16.68%`, band `regression`.
- After specializing the `ApplicationSearchEngine.filter` and `filterIDs` entry points while keeping shared tokenization/scoring, final full-suite benchmark passed: current median `332.277 ms`, baseline `361.139 ms`, delta `-7.99%`, band `comfort`.

## Memory, Cancellation, and Security Self-Review

- Removed duplicated cache actors that captured `self` strongly from detached loader tasks.
- Shared cache detached loader captures only loader/fallback closures and weak actor self for completion publication.
- In-flight state is bounded by requested keys and cleared on completion or explicit cancellation.
- Pending load fan-out is bounded by `maxConcurrentLoads`; queued keys do not create detached loader tasks until a slot opens.
- Completed icons are stored in `NSCache` with explicit count and total-cost limits instead of unbounded dictionaries.
- Cancellation cleanup is explicit from app/file preload and row icon loading via `withTaskCancellationHandler` calling `IconCache.cancelLoad(for:)`.
- No API/network behavior was changed; existing graceful backoff/security behavior was not touched.
- No PII, customer/company data, domains, or non-public values were introduced.
- Version metadata remains present at `3.1.0`; it was intentionally not bumped because Task 7 explicitly says not to begin documentation/version tasks.

## Commit Hash

The final signed commit hash is reported in the short status response after commit creation. It cannot be embedded in this file before creating the same commit because changing this file changes the commit hash.

## Concerns

- Existing Swift build emits pre-existing Sendable warnings for `ApplicationIndexSnapshotCache` captured from dispatch queues; this task did not touch that ownership path.
- `IconCache.cancelLoad(for:)` cancels by cache key, so two callers for the same key share cancellation. This matches same-key coalescing and current app/file view usage, but a future multi-owner API may want per-waiter cancellation tokens.
