# Task 12 Report — Final-review cancellation and Stone-extension fixes

## Scope completed

- Bound Dictionary lookup execution to one detached synchronous lookup at a time. A newer request waits for a non-cooperative lookup to complete, stale and cancelled requests do not publish, and no additional detached lookup is created while work is still active.
- Corrected `IconCache` capacity accounting. Cancellation of the final waiter now cancels the loader cooperatively but retains the in-flight entry and active slot until the loader completion path executes.
- Added `TextStoneProvider` and `StoneProviderRegistry` type erasure. Dictionary now supplies metadata, snapshots, updates, activation intent, and Dictionary-specific activation effects through the registry. The launcher routes registered text-Stone queries, deferred updates, snapshots, stored queries, and primary activation generically. Files remains on its specialized browser path; existing Apps and default Calculator behavior are unchanged.
- Replaced the closed Stone identity and launcher-mode enums with extensible value representations while preserving built-in constants, equality, raw values, command shortcuts, and ordering. The provider registry overlays built-in definitions and appends genuinely new provider-owned definitions in injection order; the launcher, mode switcher, help surface, cycling, and command-number routing now use that registry-derived mode list.

## TDD evidence

The following behavior tests were written and run before their production implementations:

1. `IconCacheTests.testLastWaiterCancellationKeepsCapacityOccupiedUntilNonCooperativeLoaderCompletes`
   - RED: the queued loader began while the cancelled loader was still blocked.
   - GREEN: the queued loader waits until the first loader completes.
2. `DictionaryStoneTests.testNewerAsyncQueryWaitsForNonCooperativeLookupBeforeStarting`
   - RED: both synchronous lookup closures began concurrently.
   - GREEN: only the old lookup starts until it completes; the newer request then starts and wins publication.
3. `StoneCatalogTests.testRegisteredTextStoneProviderSuppliesSnapshotsAndActivations`
   - RED: the provider contract and registry did not exist.
   - GREEN: a type-erased provider supplies initial snapshot, async update, and activation intent.
4. `StoneResultsTests.testRegisteredTextStoneProviderDrivesTextModeSnapshot`
   - RED: the launcher could not receive registered providers.
   - GREEN: an injected calculator-definition provider drives the text-mode snapshot without a new model mode branch.
5. `StoneResultsTests.testAdditionalTextStoneProviderParticipatesInLauncherBehavior`
   - RED: a new Stone identity could not be represented and the launcher exposed no registry-backed mode list.
   - GREEN: an additional neutral text provider contributes its own identity, definition, metadata, shortcut, ordering, update policy, loading/result snapshots, stored query, cancellation, and activation without central enum or behavior branches.
6. `StoneCatalogTests.testLauncherModeEqualityUsesStoneIdentity`
   - RED: launcher-mode equality changed when definition metadata or shortcut values changed.
   - GREEN: launcher-mode equality and hashing use Stone identity while mode presentation continues to use the provider-owned definition.

## Safety and ownership review

- Dictionary state is `@MainActor`; only the synchronous lookup closure leaves that actor. `ActiveLookup` owns the single detached task and is cleared only after that task completes. The detached task captures the lookup closure, not the Stone or launcher model, avoiding a retain cycle.
- Request gates exist at both Dictionary and launcher routing boundaries. They reject stale generations and prevent cancelled work from publishing after completion.
- IconCache retains the active `InFlightLoad` with an empty waiter set after cancellation, so `activeLoadCount` remains truthful. Completion, rather than cancellation, removes the entry and releases capacity. No result is cached or retained for a request with no waiters.
- Provider registry and providers are main-actor isolated. Launcher deferred tasks capture the model weakly; providers have no back-reference to the model. Files routing remains separate and continues to use its specialized browser, navigation, and accessibility behavior.
- The registry retains only its injected providers and finite definition list for the launcher lifetime. Existing per-provider tasks remain keyed by Stone identity, cancelled on mode/query transitions and model deinitialization, and guarded against stale publication. The fix adds no detached or unbounded work.
- New identities and definitions are injected in process only; no external loading, network, persistence, shell, or deserialization boundary was added. Duplicate provider identities and shortcut numbers fail during registry construction.
- No API backoff, shell-command behavior, release-facing public API, or version witness changed; a semantic-version bump is not required for this internal behavior correction.

## Verification

- Focused Stone/mode suites: `swift test --filter 'StoneCatalogTests|StoneResultsTests|LauncherModeRoutingTests|ModeSwitcherLayoutPolicyTests|LauncherModeTintPolicyTests|ToolResultsSnapshotPolicyTests|DictionaryStoneTests'` — 96 tests passed.
- Full suite: `swift test` — 346 tests passed.
- Bundle: `make bundle` — passed and produced the locally signed app bundle.
- Whitespace: `git diff --check` — passed.

## Concern

The compiler continues to report two existing non-Sendable capture warnings for `ApplicationIndexSnapshotCache` in the launcher's background indexing/cache-loading paths. Task 12 does not modify that path; the new Dictionary, IconCache, and provider-registry changes introduce no new warnings.
