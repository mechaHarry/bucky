# Architecture Audit, Test Cleanup, and Stone Framework

## Goal

Make Bucky easier and safer to evolve by removing low-value tests and PII, centralizing duplicated behavior, introducing a catalog-driven Stone framework, migrating one async Stone through that framework, and documenting the resulting extension path. Rewrite local Git history after the working-tree changes are verified so identified test PII is removed from historical test blobs.

## Constraints and invariants

- Preserve current user-visible behavior unless a task explicitly changes a documented defect.
- Keep Files as a specialized Stone where filesystem semantics require it, while sharing catalog, result, activation, and presentation contracts.
- Keep UI and data work independent: views show skeleton/loading states while asynchronous work is in flight.
- Keep APIs bounded and cancellation-safe: no unbounded task creation, caches have limits, and async work must not retain view models after cancellation.
- Preserve graceful retry/backoff behavior in existing API clients.
- Do not commit company, customer, developer, host, domain, or other non-public identifiers.
- Use semantic versioning; bump the app patch version from 3.1.0 to 3.1.1 for the refactor release.
- Make each implementation slice independently testable and revertible.
- Do not force-push or modify remote history. The history rewrite is local and must have a verified recovery bundle.

## Verification baseline

Before implementation, record the existing baseline from the isolated worktree:

- swift test
- make bundle
- git diff --check
- git status --short

The current baseline is 347 passing tests and a passing bundle build. Re-run the same checks after each relevant slice and at the end.

## Task 1: Remove meaningless source-text tests

Files:

- Delete Tests/BuckyTests/InclusionExclusionStoresTests.swift.
- Modify Tests/BuckyTests/FadeMarqueeTextPolicyTests.swift.
- Modify Tests/BuckyTests/SettingsViewLayoutTests.swift.
- Modify Tests/BuckyTests/LauncherModeRoutingTests.swift.
- Modify Tests/BuckyTests/LauncherResultListPolicyTests.swift.
- Modify Tests/BuckyTests/LauncherModeTintPolicyTests.swift.
- Modify Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift.
- Modify Tests/BuckyTests/FileBrowserMotionPolicyTests.swift.
- Modify Tests/BuckyTests/FileBrowserPreviewPolicyTests.swift.
- Modify Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift.
- Modify Tests/BuckyTests/LiquidGlassLauncherFilterTests.swift.

Changes:

- Remove assertions that read production source files, search for implementation strings, or enforce private source layout.
- Keep tests that exercise observable behavior, policy values, model output, accessibility metadata, state transitions, or public contracts.
- If a removed source-text assertion identified a real contract, replace it with a behavior-level test in the owning test file.
- Do not compensate for deleted tests with broad snapshots or duplicate unit coverage.

Verification:

- Run the focused test files/filters.
- Search the remaining test target for source-file reads and source-text assertions.
- Confirm no meaningful behavior coverage disappeared by comparing the retained test intent with the existing model/policy implementation.

## Task 2: Neutralize current test fixtures and identifiers

Files:

- Add Tests/BuckyTests/TestFixtures.swift.
- Modify all affected files under Tests/BuckyTests.
- Modify Sources/Bucky/Indexer/ApplicationIndexSourceStream.swift.
- Modify Sources/Bucky/Indexer/FileBrowserDirectoryStream.swift.
- Modify Sources/Bucky/Indexer/FileBrowserDirectoryWatcher.swift.

Changes:

- Add a small neutral fixture namespace with stable values such as /Users/test, SampleCloudTarget, and Sample Cloud Target.
- Replace developer home paths and company/cloud-provider names in tests with neutral fixtures.
- Replace developer-specific queue labels in production diagnostics with stable local.bucky labels.
- Prefer fixture constants over repeating literal paths and names.
- Keep test semantics unchanged; only identity and fixture data should change.

Verification:

- Run the full test suite.
- Search tracked tests for harriche, mechaHarry, Cisco, OneDrive, and equivalent case variants.
- Search source diagnostics for the old developer-specific queue labels.
- Review the diff for accidental changes to non-test behavior.

## Task 3: Add the catalog-driven Stone foundation

Files:

- Add Sources/Bucky/Models/StoneModels.swift.
- Modify Sources/Bucky/Models/CoreModels.swift.
- Add Tests/BuckyTests/StoneCatalogTests.swift.

Interfaces:

    enum StoneID: Int, CaseIterable, Identifiable, Hashable
    enum StoneSurface: Hashable
    enum StoneUpdatePolicy: Equatable, Hashable
    struct StoneTint: Equatable, Hashable
    struct StonePresentation: Equatable, Hashable
    struct StoneDefinition: Identifiable, Equatable, Hashable
    enum StoneCatalog

The catalog must expose:

- Stable StoneID values for Applications, Calculator, Dictionary, and Files.
- A single ordered list of definitions.
- Shortcut number, title, placeholder, system image, surface, text-input capability, update policy, and tint metadata.
- A lookup function that cannot silently return an unrelated Stone for an invalid ID.

Changes:

- Make LauncherMode bridge to StoneID and StoneDefinition for compatibility.
- Keep the ordered catalog as the one source of truth for Stone metadata.
- Make catalog construction deterministic and immutable.

Tests:

- Every StoneID has exactly one definition.
- IDs and shortcut numbers are unique and stable.
- All required presentation fields are non-empty and valid.
- Files is the only existing Stone that does not accept text input.
- Every existing LauncherMode maps to a catalog entry.

Verification:

- Run StoneCatalogTests and the existing mode/model tests.
- Confirm no UI behavior changes before switching consumers to the catalog.

## Task 4: Drive existing UI metadata from the Stone catalog

Files:

- Modify Sources/Bucky/UI/ModeSwitcherView.swift.
- Modify Sources/Bucky/UI/LauncherModeTintPolicy.swift.
- Modify Sources/Bucky/UI/ToolResultsSnapshotPolicy.swift.
- Modify Sources/Bucky/UI/SettingsView.swift.
- Modify affected UI and policy tests.

Changes:

- Replace repeated mode switches for labels, placeholders, icons, tints, surfaces, and shortcut help with StoneCatalog lookups.
- Keep truly behavior-specific policy in its owning type, such as Dictionary-only marquee behavior.
- Ensure settings and mode switching enumerate the ordered catalog instead of maintaining parallel arrays.
- Preserve loading skeleton behavior and existing keyboard/accessibility behavior.

Verification:

- Run mode switcher, tint, result-list, settings, and accessibility tests.
- Add a catalog-driven test proving a new catalog entry would be visible to the shared metadata consumers without adding another switch.
- Confirm UI/data concurrency still shows a loading state while data is pending.

## Task 5: Introduce shared Stone result and activation contracts

Files:

- Add Sources/Bucky/Models/StoneResults.swift.
- Modify Sources/Bucky/Models/CoreModels.swift.
- Modify the launcher result model/view files that currently duplicate row and activation logic.
- Add Tests/BuckyTests/StoneResultsTests.swift.

Interfaces:

    enum StoneResultSnapshot: Equatable
    struct StoneResultRow: Identifiable, Equatable, Hashable
    enum StoneActivation: Equatable

The shared contract must represent loading, empty, message, and loaded states. Rows must have stable IDs, display fields, optional copy text, and a small semantic kind. Activations must express copy, open URL, remove history, or no action without embedding view-specific side effects.

Changes:

- Move common result-row construction and activation intent out of views.
- Keep side effects in the model/controller boundary that owns them.
- Make stale async results unable to overwrite a newer query.
- Keep Files-specific preview/navigation behavior specialized behind the shared boundary.

Verification:

- Test every snapshot state and stable row identifier.
- Test each activation intent and the no-op path.
- Test stale result suppression and cancellation behavior where the shared model consumes async results.

## Task 6: Migrate Dictionary as the first async Stone

Files:

- Add Sources/Bucky/Tools/Dictionary/DictionaryStone.swift.
- Modify Sources/Bucky/Tools/Dictionary/DictionaryHistoryStore.swift if needed.
- Modify the current Dictionary model/view integration.
- Add Tests/BuckyTests/DictionaryStoneTests.swift.

Interface:

    @MainActor
    final class DictionaryStone {
        typealias Lookup = @Sendable (String) -> [DictionaryResult]
        init(historyStore: DictionaryHistoryStore, lookup: @escaping Lookup)
        func snapshot(for query: String) -> StoneResultSnapshot
        func lookupResults(for query: String) async -> StoneResultSnapshot
        func activation(for row: StoneResultRow) -> StoneActivation
    }

Changes:

- Move Dictionary history row creation, lookup result mapping, and activation mapping into DictionaryStone.
- Use the shared loading/empty/loaded result contract.
- Preserve existing debounce/update policy and history persistence semantics.
- Inject lookup behavior for deterministic tests; do not require network or live system state.
- Ensure cancellation and stale-query suppression are explicit.

Tests:

- Blank query with and without history.
- Lookup success, no match, injected failure/empty response, and duplicate handling.
- Stable history row IDs.
- Result activation and history-removal activation.
- A newer query wins when an older async lookup completes later.

Verification:

- Run DictionaryStoneTests and all existing Dictionary tests.
- Run the app/model tests that exercise mode switching and result activation.

## Task 7: Consolidate application ranking and bounded icon loading

Files:

- Add Sources/Bucky/Indexer/ApplicationSearchEngine.swift.
- Add Sources/Bucky/UI/SwiftUI/IconCache.swift.
- Modify Sources/Bucky/Models/LiquidGlassLauncherModel.swift.
- Modify Sources/Bucky/UI/SwiftUI/ApplicationIconView.swift.
- Modify Sources/Bucky/UI/SwiftUI/FileIconView.swift.
- Add Tests/BuckyTests/ApplicationSearchEngineTests.swift.
- Add Tests/BuckyTests/IconCacheTests.swift.

Interfaces:

    struct ApplicationSearchCandidate: Hashable
    enum ApplicationSearchEngine
    @available(macOS 26.0, *)
    actor IconCache

The search engine must provide shared tokenization and scoring for indexed IDs and in-memory launch items. Preserve the existing ranking order and performance-facing wrapper. IconCache must have a count limit, cost limit, bounded concurrent loads, same-key request coalescing, cancellation cleanup, and no unbounded retention of NSImage values.

Changes:

- Remove duplicate filter/tokenization/scoring logic from the launcher model.
- Keep LiquidGlassLauncherModel.filter as a compatibility/performance wrapper if existing tests or call sites depend on it.
- Replace duplicated application/file icon cache implementations with the shared cache configured separately for each domain.
- Preserve app/file preload behavior and fallback icons.

Tests:

- Search tokenization, exact/prefix/substring ranking, empty query, and deterministic ties.
- Indexed and in-memory paths produce equivalent ranking where inputs are equivalent.
- Icon cache hit, same-key coalescing, multiple keys, bounded concurrency, cancellation, and fallback behavior.

Verification:

- Run focused search and icon tests.
- Run the launcher performance test and compare against the recorded baseline.
- Check for retain cycles in task/cache/view-model ownership and confirm cancelled tasks do not keep stale loaders alive.

## Task 8: Centralize JSON persistence and split only cohesive views

Files:

- Add Sources/Bucky/Config/JSONFilePersistence.swift.
- Modify Sources/Bucky/Config/InclusionStore.swift.
- Modify Sources/Bucky/Config/ExclusionStore.swift.
- Modify Sources/Bucky/Config/DictionaryHistoryStore.swift.
- Add Sources/Bucky/UI/SwiftUI/FileBrowserPreviewView.swift.
- Add Sources/Bucky/UI/SwiftUI/SettingsSubviews.swift.
- Keep or refine existing ApplicationIconView.swift and FileIconView.swift extraction from Task 7.
- Modify parent views/models only where extraction makes ownership clearer.
- Add Tests/BuckyTests/JSONFilePersistenceTests.swift.

Interface:

    enum JSONFilePersistence {
        static func read<Value: Decodable>(
            _ type: Value.Type,
            from fileURL: URL,
            decoder: JSONDecoder
        ) throws -> Value

        static func write<Value: Encodable>(
            _ value: Value,
            to fileURL: URL,
            fileManager: FileManager,
            encoder: JSONEncoder
        ) throws
    }

Changes:

- Centralize data-directory creation, JSON encoder/decoder setup, atomic writes, and error propagation.
- Preserve each store's missing-file and malformed-file defaults.
- Preserve inclusion-specific write behavior and set semantics.
- Extract only cohesive UI units with explicit inputs/actions; do not split state merely to reduce file line count.

Verification:

- Test missing, malformed, valid, and write/read-round-trip cases.
- Run all store, settings, file browser, and preview tests.
- Review ownership for retained closures, timers, notification observers, and tasks to prevent leaks.

## Task 9: Update documentation and version

Files:

- Modify README.md.
- Modify .agents/docs/bucky-architecture.md.
- Modify Bucky/Info.plist.

Changes:

- Document the current behavior of inclusions/exclusions, including missing or malformed file defaults.
- Document the direct Finder/CoreServices application scan and current async loading behavior.
- Add the Stone extension recipe: add catalog metadata, implement a Stone boundary, map results/activations, add focused behavior tests, and wire only domain-specific policy.
- Record that test fixtures and committed examples must use neutral identifiers.
- Bump CFBundleShortVersionString from 3.1.0 to 3.1.1 without changing unrelated build metadata.

Verification:

- Check README claims against implementation and tests.
- Run git diff --check and inspect the version diff.

## Task 10: Final verification before history rewrite

Run:

- swift test
- make bundle
- git diff --check
- git status --short
- searches for PII and source-text tests
- the launcher performance test

Review:

- Confirm API retry/backoff behavior was not weakened.
- Confirm no new unbounded caches, task fan-out, observer leaks, timer leaks, or retain cycles were introduced.
- Confirm all changed tests are behavior-level and meaningful.
- Confirm the Stone framework is exercised by a real migrated Stone, not only catalog tests.

## Task 11: Rewrite local history to remove identified test PII

Scope:

- Rewrite blobs reachable from local branches, remote-tracking refs, and tags.
- Change only identified PII in test files.
- Do not rewrite commit messages, CODEOWNERS, source files outside the approved diagnostic-label changes, or remote servers.

Recovery:

- Before rewriting, create /private/tmp/bucky-pre-history-rewrite.bundle with git bundle create --all.
- Record the bundle checksum and current ref list.

Rewrite:

- Use a temporary blob-rewrite script and a history rewrite operation that changes only files under Tests/.
- Apply replacements longest-first: harriche to test, OneDrive-Cisco to SampleCloudTarget, OneDrive - Cisco to Sample Cloud Target, Cisco to Sample, and mechaHarry to bucky.
- Preserve tag names and local ref names.
- Do not use force-push.

Verification:

- Verify the recovery bundle.
- Search every rewritten ref for the old identifiers.
- Inspect rewritten test blobs and representative diffs.
- Run git fsck --full --no-reflogs.
- Re-run swift test and make bundle at the rewritten branch tip.
- Confirm the new HEAD remains signed and the repository is clean except for intended local worktree metadata.

## Commit sequence

Use small signed conventional commits in this order:

1. test: remove source-layout assertions
2. test: neutralize fixture identifiers
3. feat: add Stone catalog contracts
4. refactor: drive metadata from Stone catalog
5. feat: add shared Stone result contracts
6. feat: migrate Dictionary Stone boundary
7. refactor: share search and icon infrastructure
8. refactor: centralize persistence and split cohesive views
9. docs: document Stone extension path
10. chore: bump patch version
11. chore: rewrite local test history

Each commit must pass the narrowest relevant tests. The final implementation commit sequence should be easy to bisect and revert.

## Completion criteria

- Full tests pass with no source-text-only tests retained.
- Test fixtures and rewritten history contain no identified PII.
- Applications, Calculator, Dictionary, and Files are represented by one catalog.
- Dictionary is migrated through a shared async Stone/result boundary.
- Shared ranking, icon caching, and persistence code are consolidated with bounded resource use.
- UI is split only along cohesive ownership boundaries.
- README and architecture documentation describe what works and how to add a Stone.
- Version is 3.1.1.
- Bundle and full test verification pass after the history rewrite.
