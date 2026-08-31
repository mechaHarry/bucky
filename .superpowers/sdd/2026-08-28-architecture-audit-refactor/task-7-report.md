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

---

# Task 7 Fix Round 1 Report

## Scope

Addressed all three review findings without starting persistence extraction, view extraction, documentation, or version tasks:

- Same-key cancellation now cancels only the cancelled waiter, not every waiter for that cache key.
- Last-waiter cancellation now releases active load capacity even when the loader ignores task cancellation.
- Whitespace-only application queries now preserve the prior observable scored ordering instead of returning source order.

## Exact Interfaces After Fix

```swift
@available(macOS 26.0, *)
enum ApplicationSearchEngine {
    static func tokens(for normalizedQuery: String) -> [String]
    static func filter(_ items: [LaunchItem], normalizedQuery: String) -> [LaunchItem]
    static func filterIDs(_ ids: [ApplicationRowID], rowStore: ApplicationRowStore, normalizedQuery: String) -> [ApplicationRowID]
    static func rankedCandidates(_ candidates: [ApplicationSearchCandidate], normalizedQuery: String) -> [ApplicationSearchCandidate]
}
```

```swift
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
}
```

`IconCache.cancelLoad(for:)` was removed. Cancellation ownership is now per caller/waiter through `icon(for:)`; view-level `withTaskCancellationHandler` wrappers in app/file icon preload and row icon loading were removed.

## Cache Bounds and Concurrency Behavior After Fix

- `IconCache.applications`: count limit `256`, cost limit `134217728` bytes, max concurrent loads `4`, key is `url.path`.
- `IconCache.files`: count limit `768`, cost limit `134217728` bytes, max concurrent loads `2`, key is `url.standardizedFileURL.path`.
- Same-key requests still coalesce into one `InFlightLoad` and one loader task while retaining separate waiter IDs.
- A cancelled waiter removes only its own waiter ID and receives the configured fallback icon from `icon(for:)`.
- Remaining same-key waiters stay attached and receive the loaded icon when the coalesced load completes.
- When the last waiter cancels, the cache removes the in-flight entry, removes pending queue entries, cancels the loader task if present, releases active capacity immediately, and schedules queued work after an actor-yield cleanup turn.
- Stale completions from cancellation-ignoring loaders are guarded by a per-load UUID and cannot populate cache, complete unrelated waiters, or decrement active capacity twice.
- Detached loader tasks capture only loader/fallback closures, the key, load ID, and weak actor self.

## Search Behavior After Fix

- `normalizedQuery.isEmpty` remains the only all-results/source-order fast path.
- Whitespace-only non-empty strings tokenize to no tokens, then use the shared scoring/tie-break pipeline. This restores the previous observable behavior: all rows match, shorter titles score ahead of longer titles, and deterministic tie handling still applies.
- Indexed and in-memory paths continue to share the same tokenization, scoring, and deterministic ordering implementation.

## Files Changed in Fix Round 1

- `Sources/Bucky/Indexer/ApplicationSearchEngine.swift`
- `Sources/Bucky/UI/SwiftUI/IconCache.swift`
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`
- `Sources/Bucky/UI/SwiftUI/FileBrowserView.swift`
- `Tests/BuckyTests/ApplicationSearchEngineTests.swift`
- `Tests/BuckyTests/IconCacheTests.swift`
- `.superpowers/sdd/2026-08-28-architecture-audit-refactor/task-7-report.md`

## TDD RED Results

Before production fixes, the focused regression tests failed for the two reviewed defects that were still present:

```text
$ swift test --filter 'ApplicationSearchEngineTests|IconCacheTests'
Test Case '-[BuckyTests.ApplicationSearchEngineTests testWhitespaceOnlyQueryPreservesPreviousScoredOrdering]' failed: XCTAssertEqual failed: ("["Long Application", "App", "Medium"]") is not equal to ("["App", "Medium", "Long Application"]")
Test Case '-[BuckyTests.IconCacheTests testLastWaiterCancellationReleasesCapacityWhenLoaderIgnoresCancellation]' failed: XCTAssertTrue failed
Process exited with code 1
```

The same-key waiter cancellation regression was added alongside the RED suite and remained as explicit coverage for the key-wide cancellation removal.

## Commands and Pristine Outputs

Focused search/cache regressions:

```text
$ swift test --filter 'ApplicationSearchEngineTests|IconCacheTests'
Test Suite 'ApplicationSearchEngineTests' passed
Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'IconCacheTests' passed
Executed 9 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed
Executed 16 tests, with 0 failures (0 unexpected)
Process exited with code 0
```

Focused launcher/search/cache/performance:

```text
$ swift test --filter 'LiquidGlassLauncherFilterTests|ApplicationRowStoreTests|ApplicationSearchEngineTests|IconCacheTests|LauncherFilterPerformanceTests'
Test Suite 'Selected tests' passed
Executed 29 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 325.638 ms, baseline 361.139 ms, delta -9.83%, band comfort, samples min/median/max 324.533/325.638/327.803 ms
Process exited with code 0
```

Broader launcher-related coverage:

```text
$ swift test --filter 'Launcher|LiquidGlassLauncher|ApplicationSearchEngine|ApplicationRowStore|IconCache|FileBrowserPreviewPolicy'
Test Suite 'Selected tests' passed
Executed 144 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 335.969 ms, baseline 361.139 ms, delta -6.97%, band comfort, samples min/median/max 330.711/335.969/348.521 ms
Process exited with code 0
```

Full suite:

```text
$ swift test
Test Suite 'All tests' passed
Executed 333 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 328.987 ms, baseline 361.139 ms, delta -8.90%, band comfort, samples min/median/max 328.216/328.987/346.959 ms
Process exited with code 0
```

Diff hygiene after report append:

```text
$ git diff --check
Process exited with code 0
```

Cancellation-handler search after report append:

```text
$ rg -n "cancelLoad\(|withTaskCancellationHandler" Sources/Bucky/UI/SwiftUI Sources/Bucky/Indexer Tests/BuckyTests
Process exited with code 1
```

## Performance Comparison

- Recorded baseline: `361.139 ms`.
- Focused launcher performance run: `325.638 ms`, delta `-9.83%`, band `comfort`.
- Broader launcher-related run: `335.969 ms`, delta `-6.97%`, band `comfort`.
- Full-suite launcher performance run: `328.987 ms`, delta `-8.90%`, band `comfort`.
- No launcher-filter regression observed.

## Memory, Cancellation, and Security Self-Review

- Per-waiter cancellation removes only the current waiter's UUID from in-flight state.
- Last-waiter cancellation removes all cache-owned references for that key, cancels the task, releases active capacity, and lets stale cancellation-ignoring task completions fall through the load-ID guard.
- `completedIconsByWaiterID` is cleared for cancelled waiters and populated only for waiters still registered at completion time.
- Loader tasks use `[weak self]`, avoiding actor-retention cycles.
- Queue fan-out remains bounded by `maxConcurrentLoads`; queued keys do not create detached work until capacity exists.
- Completed icon storage remains `NSCache`-bounded by explicit count and total-cost limits.
- No network/API paths, backoff logic, or security-sensitive file operations were changed.
- No PII, company/customer details, domains, secrets, or non-public values were introduced.
- Version metadata remains unchanged intentionally because this fix round is constrained to Task 7 and explicitly excludes documentation/version tasks.

## Commit Hash

The fix-round signed commit hash is reported in the final short status response after commit creation. It cannot be embedded in this file before creating the same commit because changing this file changes the commit hash.

## Concerns

- None open for the three fix-round review findings.

---

# Task 7 Fix Round 2 Report

## Scope

Addressed the scoped re-review issue in `IconCache.icon(for:)` without starting later tasks:

- Removed the unsafe `withUnsafeCurrentTask { $0 }` handle storage/read-after-suspension pattern.
- Kept view-level key-wide cancellation handlers removed.
- Kept same-key waiter isolation, last-waiter capacity release, fallback behavior, and whitespace-only search ranking intact.

## Exact Interface After Fix Round 2

The public/internal `IconCache` surface remains the same as fix round 1:

```swift
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
}
```

`icon(for:)` now uses:

- a per-call `UUID` waiter ID;
- safe `Task.isCancelled` checks inside the async operation;
- `withTaskCancellationHandler` whose `onCancel` creates a short cleanup task that calls `cancelWaiter(id:key:)` for only that waiter ID;
- no stored `UnsafeCurrentTask` and no use of `withUnsafeCurrentTask`.

## Cache Bounds and Concurrency Behavior After Fix Round 2

- `IconCache.applications`: count limit `256`, cost limit `134217728` bytes, max concurrent loads `4`, key is `url.path`.
- `IconCache.files`: count limit `768`, cost limit `134217728` bytes, max concurrent loads `2`, key is `url.standardizedFileURL.path`.
- Same-key requests continue to coalesce through one `InFlightLoad` and one loader task with multiple waiter IDs.
- Cancellation removes only the cancelled waiter's UUID; unrelated same-key waiters remain registered.
- Last-waiter cancellation removes the in-flight entry, drops pending queue entries, cancels the loader task if present, releases active capacity immediately, and schedules queued work even if the loader ignores cancellation.
- Stale completions remain guarded by the per-load UUID and cannot cache icons, complete waiters, or release active capacity twice after cache-owned state has already been removed.
- Cleanup tasks capture the actor weakly and do not create retain cycles.

## Search Behavior Retained

- Empty normalized queries return source order.
- Whitespace-only non-empty queries continue through the shared scoring path, preserving the prior observable ordering covered by `testWhitespaceOnlyQueryPreservesPreviousScoredOrdering`.
- Indexed and in-memory application ranking remain shared through `ApplicationSearchEngine`.

## Files Changed in Fix Round 2

- `Sources/Bucky/UI/SwiftUI/IconCache.swift`
- `.superpowers/sdd/2026-08-28-architecture-audit-refactor/task-7-report.md`

## TDD / Regression Coverage

No new consumer-visible behavior was introduced in round 2; the re-review defect was an unsafe internal cancellation implementation. The existing round-1 regressions were retained and rerun against the new safe cancellation implementation:

- `testCancellingOneSameKeyWaiterKeepsOtherWaiterOnLoadedIcon`
- `testLastWaiterCancellationReleasesCapacityWhenLoaderIgnoresCancellation`
- `testWhitespaceOnlyQueryPreservesPreviousScoredOrdering`

The source-level safety check also verifies the removed unsafe API and key-wide cancellation symbols are absent from the relevant implementation/test scope.

## Commands and Pristine Outputs

Focused search/cache regressions:

```text
$ swift test --filter 'ApplicationSearchEngineTests|IconCacheTests'
Test Suite 'ApplicationSearchEngineTests' passed
Executed 7 tests, with 0 failures (0 unexpected)
Test Suite 'IconCacheTests' passed
Executed 9 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed
Executed 16 tests, with 0 failures (0 unexpected)
Process exited with code 0
```

Focused launcher/search/cache/performance:

```text
$ swift test --filter 'LiquidGlassLauncherFilterTests|ApplicationRowStoreTests|ApplicationSearchEngineTests|IconCacheTests|LauncherFilterPerformanceTests'
Test Suite 'Selected tests' passed
Executed 29 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 328.602 ms, baseline 361.139 ms, delta -9.01%, band comfort, samples min/median/max 325.543/328.602/339.847 ms
Process exited with code 0
```

Broader launcher-related coverage:

```text
$ swift test --filter 'Launcher|LiquidGlassLauncher|ApplicationSearchEngine|ApplicationRowStore|IconCache|FileBrowserPreviewPolicy'
Test Suite 'Selected tests' passed
Executed 144 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 331.690 ms, baseline 361.139 ms, delta -8.15%, band comfort, samples min/median/max 330.896/331.690/333.880 ms
Process exited with code 0
```

Full suite:

```text
$ swift test
Test Suite 'All tests' passed
Executed 333 tests, with 0 failures (0 unexpected)
Bucky performance launcher-filter checked: current median 332.311 ms, baseline 361.139 ms, delta -7.98%, band comfort, samples min/median/max 330.814/332.311/355.676 ms
Process exited with code 0
```

Diff hygiene:

```text
$ git diff --check
Process exited with code 0
```

Unsafe/key-wide cancellation source check:

```text
$ rg -n "UnsafeCurrentTask|withUnsafeCurrentTask|cancelLoad\(" Sources/Bucky/UI/SwiftUI/IconCache.swift Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift Sources/Bucky/UI/SwiftUI/FileBrowserView.swift Sources/Bucky/Indexer Tests/BuckyTests
Process exited with code 1
```

## Performance Comparison

- Recorded baseline: `361.139 ms`.
- Focused launcher performance run: `328.602 ms`, delta `-9.01%`, band `comfort`.
- Broader launcher-related run: `331.690 ms`, delta `-8.15%`, band `comfort`.
- Full-suite launcher performance run: `332.311 ms`, delta `-7.98%`, band `comfort`.
- No launcher-filter regression observed.

## Memory, Cancellation, and Security Self-Review

- No unsafe task pointer or task handle is stored beyond a closure.
- Per-waiter UUID ownership remains the only cancellation identity.
- `onCancel` performs actor cleanup by waiter ID only, preserving unrelated same-key waiters.
- Last-waiter cancellation still releases active capacity immediately and stale loader completions are ignored by load ID.
- The cancellation cleanup task captures `self` weakly to avoid retaining the cache actor after callers go away.
- Detached loader tasks still capture only loader/fallback closures, key, load ID, and weak actor self.
- No API/network/backoff paths, file security behavior, or destructive operations were changed.
- No PII, company/customer details, domains, secrets, or non-public values were introduced.
- Version metadata remains unchanged because this is constrained to Task 7 fix scope and later documentation/version tasks are explicitly out of scope.

## Commit Hash

The fix-round-2 signed commit hash is reported in the final short status response after commit creation. It cannot be embedded in this file before creating the same commit because changing this file changes the commit hash.

## Concerns

- None open for fix round 2.
