# Bucky Architecture Notes

This project is a local-only macOS launcher implemented as a Swift Package macOS executable and bundled into `build/Bucky.app` by `make bundle`.

## Build And Runtime

- Entry point: `Sources/Bucky/main.swift`.
- Source layout:
  - `Sources/Bucky/App`: app delegate, global hotkey registration, launch-at-startup controller.
  - `Sources/Bucky/Config`: persisted file paths and JSON configuration models.
  - `Sources/Bucky/Indexer`: app bundle indexing.
  - `Sources/Bucky/Models`: shared launcher/tool data models.
  - `Sources/Bucky/Settings`: settings, inclusion/exclusion, and calculation history stores.
  - `Sources/Bucky/Tools/Calculator`: local arithmetic parsing/evaluation.
  - `Sources/Bucky/Tools/Dictionary`: macOS Dictionary Services lookup and fuzzy matching.
- `Sources/Bucky/UI/Shell`: macOS shell controllers for the menu bar item.
  - `Sources/Bucky/UI/SwiftUI`: macOS 26 SwiftUI Liquid Glass launcher and settings view.
  - `Sources/Bucky/UI/Shared`: UI contracts, commands, and shared utilities.
- Build command: `make bundle`.
- Bundle metadata: `packaging/Info.plist`.
- Minimum runtime target: macOS 26 (`Package.swift` and `LSMinimumSystemVersion`).
- The app runs as an accessory/menu-bar app (`LSUIElement` true).
- The status item has a fixed square footprint, a template bolt SF Symbol, and a text fallback if the symbol cannot load.
- `ApplicationMenu` provides native Edit commands routed through the AppKit responder chain; Stones do not duplicate Cut/Copy/Paste/Select All handling.

## App Indexing

- `ApplicationIndexer` scans `.app` bundles and appends top-level System Settings panes from `SystemSettingsIndexer`. It does not index arbitrary executables.
- Recursive scan roots are:
  - `/Applications`
  - `/System/Applications`
  - `~/Applications`
- `/System/Library/CoreServices` is scanned only for direct child `.app` bundles so native Apple utility apps such as Finder are available without walking the full CoreServices support tree.
- Explicit inclusions are merged after root scanning and deduped by full app path. Finder arrives from the CoreServices scan, not from a seeded inclusion default.
- Dedupe is by full app path.
- Search text for apps includes only the app title. Paths, directories, bundle identifiers, and executable names are not searchable.
- `SystemSettingsIndexer` reads the top-level System Settings sidebar from `/System/Applications/System Settings.app/Contents/Resources/Sidebar.plist`, resolves matching settings `.appex` bundles from `/System/Library/ExtensionKit/Extensions` and `/System/Applications/System Settings.app/Contents/PlugIns`, and keeps only extensions that declare `allowsXAppleSystemPreferencesURLScheme`.
- System Settings pane items launch `x-apple.systempreferences:<bundle-id>` URLs. Bucky intentionally does not parse App Intents metadata or `.searchTerms` section files for deeper settings controls.
- User-defined custom actions are stored in settings and indexed by `CustomActionIndexer` as launcher rows classified as `Action`. They run as `/bin/zsh -lc <command>` without logging the command contents.
- `ApplicationIndexSourceStream` watches app roots, System Settings resources/extensions, the Bucky config directory, and explicit inclusion parent directories with an FSEvents stream on a utility queue. Missing roots use their nearest existing ancestor; coverage is rebuilt as roots appear. Events are debounced and then trigger a fresh app-index snapshot; setup and the expensive index load remain off the main thread.
- `ApplicationRowStore` owns app row data behind stable `AppRowID` values. App filtering, selection, scroll identity, reconstruction identity, and icon preloading move row IDs or URLs instead of copying full row structs through the hot UI path.
- `ApplicationIndexSnapshotCache` memoizes the last app index to `app-index-snapshot.json` under Application Support. Startup loads this snapshot on a utility queue for fast first results, then live background indexing replaces it when fresh data arrives.
- App search memoization is generation-scoped: filter cache entries contain `AppRowID` arrays and are invalidated when `ApplicationRowStore.generation` changes, including visibility-only changes. Deferred filters and warmers publish only against their captured generation.
- `LaunchItem` precomputes normalized titles, title words, and length penalties once. `ApplicationRowStore` caches locale-aware natural title ranks so the live row-ID filter sorts integer ranks instead of repeating expensive collation on each query. Collation-equivalent titles retain the input ID order. Both array and row-ID searches use the same scoring implementation and have parity tests. Cache warming is event-driven, cancellation-aware, and bounded to a small prefix set; it never initializes Files in the background.

## Config Files

All app config uses JSON under:

```text
~/Library/Application Support/Bucky/
```

Files:

- `settings.json`: hotkey, launch-on-startup preference, animation timing preference, file-browser start directory, and custom actions.
- `inclusions.json`: explicit `.app` paths to merge into the index. Missing files are created with an empty array; malformed or unreadable files are preserved.
- `exclusions.json`: legacy paths plus typed application, URL, and custom-action identities hidden from search results. Stable custom-action IDs prevent empty paths from hiding every action.
- `calculations.json`: most recent calculator-mode calculations, newest first, capped at 100 entries.
- `dictionary-history.json`: recent looked-up terms.
- `countdowns.json`: named target datetimes. Admission stops at 100 without evicting existing records; legacy over-capacity files are not truncated.
- `file-browser.json`: bounded navigation, sorting, pins, remembered selections, and protected security-scoped bookmarks.
- `app-index-snapshot.json`: memoized launcher app/settings/action rows used as the startup snapshot. Malformed or incompatible snapshots are ignored and rebuilt by the next index pass.

Exclusions are applied after indexing and inclusions. An explicitly included app can still be hidden if its path is in exclusions.

`JSONValueStore` is the shared settings/history transaction boundary. Runtime callers use async load/mutation methods; initial/synchronous compatibility APIs remain. Failed reads keep the last valid memory state and block mutations until successful reload. Failed writes do not publish candidate state. A single FIFO `JSONFilePersistence` worker encodes and atomically replaces private `0600` files, creates only missing directories with `0700`, and never changes existing ancestor permissions. Descriptor-validated reads reject symlinks/nonregular files and bound data to 8 MiB; Countdowns also applies a 128 KiB load limit. Privacy-safe errors are surfaced without logging private paths, launch URLs, shell commands, or contents. `BUCKY_DATA_DIRECTORY` accepts an absolute isolated data directory for tests.

Files preferences have a coalescing writer, a latest-state rollback on failed saves, and an explicit flush barrier. Some displayed preferences are optimistic until completion; a visible error signals failure. Normal AppKit termination waits for approved Files operations, Files persistence, and the shared JSON queue without blocking MainActor. Force quit cannot provide a durability guarantee.

## Launcher UX

- Default hotkey is Option+Space through Carbon `RegisterEventHotKey`.
- Hotkey can be changed in Settings and is persisted in `settings.json`.
- Up and Down move selection by one row; Command+Up and Command+Down jump to the first and last visible result.
- Launcher shortcuts are handled by the visible launcher window, not global Carbon hotkeys: Command+Left and Command+Right cycle modes with wraparound, Command+/ opens shortcut help, and registered Command-number shortcuts select Stones. Both event paths use `LauncherShortcutPolicy`; native clipboard commands pass through.
- Escape clears the input first; if the input is already blank, it closes the launcher window.
- The launcher uses `LiquidGlassLauncherWindowController`, a borderless resizable `NSWindow` with an `NSHostingView` surface backed by `LiquidGlassLauncherView`, `LiquidGlassLauncherModel`, and the in-window settings model.
- SwiftUI owns the Liquid Glass visual system: `GlassEffectContainer`, `glassEffect`, glass button styles, and glass transitions for the main window, header controls, and individual result rows.
- The previous AppKit launcher mode has been removed. AppKit remains for macOS application plumbing, global hotkeys, menu bar control, and hosting SwiftUI windows.
- The bundle declares macOS 26 as its minimum OS. The runtime path also shows an unsupported OS alert if the app is somehow launched below that target instead of falling back to a legacy launcher.
- Launcher opens on the hardware primary display using `CGMainDisplayID()`, not mouse/focus display.
- `show()` reveals a retained SwiftUI Apps shell at full opacity, without a queued open animation or focus clear/requeue. The native host performs initial SwiftUI layout before hotkey registration. Heavy hidden Stones still unmount. A stateless glass backdrop is prepared with the retained hidden Apps shell, with no per-open opacity transition or delayed effect construction. Reduce Transparency uses a stable opaque fallback. Input/results never inherit backdrop opacity or geometry. The shared results scroll viewport uses a constant 1% input-surface opacity, without timers or animation. This gives native window routing and SwiftUI scrolling a painted surface over row gaps; rectangular interaction shapes handle in-app routing. The native window background and hosting layer stay clear, and the existing glass backdrop remains stateless. The hosting-view fallback converts hit-test points from superview coordinates before checking local bounds. Hotkey callbacks run directly on MainActor. The SwiftUI text binding schedules filtering directly; it does not wait for a render-driven `onChange` callback. Opening does not schedule a freshness reindex. Index freshness comes from the source stream, settings changes, startup indexing, and explicit Command+R.
- Reindexing runs on a background queue and publishes results back to the main thread.
- Source change triggers keep the app index fresh without requiring Command+R as the normal refresh path.
- Reindex publication compares the new app snapshot with the current one before clearing filter state, so unchanged source events do not invalidate warm caches.
- A small spinner at the right of the search bar indicates indexing.
- If a reindex is requested while one is active, one follow-up reindex is queued.
- During typing, if the next query would produce zero results, Bucky preserves the previous interactable filtered list. This only applies to search typing, not explicit config/index refreshes.
- App filter cache entries store filtered `AppRowID` lists. Rows dereference through `ApplicationRowStore` at render/activation time.
- App result rows/icons are cached per data/result revision. Row dictionaries, visibility, and natural-title ranks prepare off MainActor, with generation checks for later indexes and exclusion edits. Foreground searches have zero debounce and use a serial Swift actor with cooperative scan/sort cancellation. Missing deletion-prefix results warm after 250 ms input idle, never while hidden.
- Shared SwiftUI icon tasks cancel while inactive. Display rasters are 80 pixels for Apps and 144 pixels for Files. NSCache cost budgets are 8/16 MiB, with memory-pressure purging. Preload batches cap at 32 entries; Files centers on current selection. Files content/sidebar revision counters avoid whole-directory identity allocations.
- `LauncherPerformanceTrace` is opt-in via `BUCKY_PERFORMANCE_TRACE=1`; it emits fixed stage names and elapsed milliseconds only. Native integration tests verify actual text acceptance and filtering independently of focus requests or animation completion.

## Mode UX

- Calculator, Dictionary, Files, and Countdowns do not search or launch apps.
- Apps is the default mode and must not activate Files code. `LiquidGlassLauncherModel` creates `FileBrowserModel` lazily only when Files is selected or the Files UI requests it.
- Mode switches publish the new mode and restored query immediately, then defer mode-specific result snapshots behind the first interactable update. Stale deferred mode work is ignored by generation token.
- Loading result surfaces use the shared animated `SkeletonLoadingView` and `SkeletonLoadingPolicy`, with an accessible label and lifecycle-bound animation. Empty and no-results states remain ordinary text messages.
- Files mode shows the shared loading surface if the file-browser model is not already warm, then prepares the model after the first Files frame.
- Files mode lists mounted volumes alongside directory contents and supports folders-first sorting so directories can stay grouped ahead of non-folder entries.
- File-browser directory lists flow through `FileBrowserDirectoryStreaming` before reaching SwiftUI. The model publishes stable loading, empty, and loaded snapshots and ignores stale stream results when a newer directory request wins.
- Files mutations and conflict scans use a serial background worker with one admitted operation, recoverable selection/focus on failure, and a busy skeleton. Keep Both uses exclusive destinations and collision retries; replacement is restricted to explicit Replace. Cross-volume moves and multi-item mutations can still partially complete on failure.
- Directory scans coalesce to one active and one latest pending request, check cancellation during child processing, and skip inaccessible/disappearing children. Watcher refreshes debounce; Files observation and pending loads suspend while hidden, in another Stone, or under Settings/Help.
- Quick Look thumbnails cancel superseded work and use weak completion ownership. Text previews have at most two active reads, a 64 KiB cap, descriptor-validated regular files, and cancellation checks. OS calls already in progress cannot be forcibly interrupted. Drag initiation uses an immediate generic icon.
- Traversal history is capped at 128; remembered selections and ordinary bookmark retention at 256; new pin admission at 128. Legacy pins and their access bookmarks are protected even above that limit.
- Calculator mode exposes a clear-history button. Pin is global to all launcher modes. While pinned, the launcher stays above other apps, shows a bolder accent border, can be dragged by its background, refocuses on the global launcher hotkey, and stays open after result activation.
- Calculator mode evaluates arithmetic expressions with a local parser supporting `+`, `-`, `*`, `/`, `×`, `÷`, decimals, grouping commas, unary signs, and parentheses.
- Valid calculations with a binary arithmetic operator are added to `calculations.json` after a short typing debounce, and pressing Return on a live calculation commits it immediately.
- `CalculatorStone` owns result/history shaping and the debounce through `HistoryStoneProvider`; the shell uses shared rows and clear-history behavior. Arithmetic input is limited to 4,096 bytes and recursion to 64 levels; exact integer conversion avoids formatting traps.
- Dictionary mode looks up text through macOS Dictionary Services via `DCSCopyTextDefinition`, with fuzzy candidates from `NSSpellChecker` completions and guesses. Dictionary.app is not launched during lookup.
- Pressing Return on a calculation result copies its value to the pasteboard. Pressing Return on a dictionary result opens Dictionary.app at the matching word instead of copying the definition.
- The green Countdowns Stone uses the shared named-datetime creation row and confirmation overlay. Native date/time fields keep their intrinsic locale sizes. Return commits an active native editor before submission. Empty titles show a red underline and accessible hint; failed saves retain the draft and report the error.
- `LiveRemainingTimeText` updates only visible time text at a 50 ms minimum interval with animations disabled. Expired rows freeze at zero; the launcher does not rebuild an entire Countdown snapshot on each tick.
- Provider confirmations retain the originating Stone/row, consume unrelated commands, and disable background mouse and accessibility interaction. Async provider side effects complete without publishing into a different Stone after a switch.

## Settings UX

- Settings opens with Command+Comma and from the menu bar item inside the existing Bucky launcher panel.
- Command+Comma toggles the launcher panel between launcher mode and settings mode. The global launcher hotkey also returns from settings to launcher mode.
- Settings shares the same borderless transparent `BuckyPanelWindow` and hosting view architecture as the launcher, avoiding a second settings panel.
- Runtime refresh/save actions use async store transactions. Loading content is redacted in-place to reserve layout; saving disables duplicate actions. Failed saves keep drafts/selections and do not fire successful-change callbacks.
- Settings supports:
  - Recording the global hotkey.
  - Toggling launch on startup via `SMAppService.mainApp`.
  - Choosing Liquid Glass animation timing.
  - Managing included apps with Add/Remove. Add uses `NSOpenPanel` restricted to `.app` bundles.
  - Managing hidden apps with Remove.
  - Managing custom action names and shell commands that appear in app results as `Action`.

## Stone Extension Recipe

- Define a provider-owned `StoneDefinition`, conform to the generic `StoneProvider` boundary, and register through `StoneProviderRegistry`. `TextStoneProvider` remains a source-compatible name for existing conformers. The provider owns its `StoneID`, while its definition owns ordering, shortcut number, placeholder text, icon, tint, accepted surface, and update policy.
- Use `.textInput` for query-driven Stones and `.sharedResults` for non-input Stones that use the common results UI and generic active mode presentation.
- Let `LauncherMode` bridge only the shared launcher-facing metadata from the registry-backed provider definition. Registered providers on `.textInput` or `.sharedResults` publish through the shared `StoneResultSnapshot` path without a provider-specific launcher case. `.fileBrowser` is reserved for the built-in Files definition; the registry ignores providers claiming that surface or the `.files` identity.
- Model result rows and activation intents separately. `StoneResultRow` carries stable row identity, declarative `StoneActivation` values, and generic-or-provider-supplied accessory presentation; `LiquidGlassLauncherModel.perform(_:,for:)` is the side-effect boundary that turns those intents into copy, open, or history-removal behavior.
- Keep Stone-specific result shaping inside the Stone or its focused helper, similar to `DictionaryStone`, and feed shared result rows back through `StoneResultSnapshot` rather than embedding side effects in SwiftUI.
- Use `performAsync` and `performsActivationsAsynchronously` for persistence-backed actions. Use `HistoryStoneProvider` for shared history controls and `InlineCreationStoneProvider` for the focused named-datetime creation contract rather than a second modal framework.
- Add focused tests at the shared seams: catalog coverage (`StoneCatalogTests`), launcher routing (`LauncherModeRoutingTests`), row identity and activation mapping (`StoneResultsTests`), and Stone-specific behavior tests for the new domain.
- Keep domain policy local. Shared code should only learn new generic metadata or activation cases when the new Stone truly needs a new cross-cutting boundary.

## Verification And Release Boundaries

- `make test` uses an isolated temporary data directory by default. Direct `swift test` callers should set `BUCKY_DATA_DIRECTORY` to an absolute temporary directory.
- The performance test retains the checked-in array-workload baseline, additionally verifies row-ID ranking parity and reports live-path timing with OS/processor metadata. Baseline updates require an intentional performance review, not a failing-test workaround.
- `make tooling-test` runs offline release/packaging mocks. `package.sh` builds incrementally, verifies signatures/versions, and installs archive/checksum assets without overwriting existing files.
- `release.sh` delegates to `scripts/releaseTooling.py`. It requires a clean default branch matching its remote, strict SemVer, verified signed annotated tags, and successful tests/package gates before remote publication. API reads have bounded backoff; ambiguous writes are read-reconciled. Tags, draft releases, and assets are preserved on failure, never automatically deleted.
- Native focus/date-picker/preview behavior, Instruments memory profiling, Developer ID/notarization, and real GitHub publication need separate runtime/environment validation. Local default packaging remains ad-hoc signed.

## Fixture And PII Rules

- Tests and committed examples use neutral identifiers such as `/Users/test`, `/Applications/Example.app`, and `SampleCloudTarget`.
- Do not commit real company names, customer data, private domains, or other non-public identifiers in fixtures, screenshots, example JSON, or architecture notes.

## Known Product Decisions

- Apple-standard app config location is preferred over XDG because this is a native macOS GUI app.
- `/System/Library/CoreServices` is scanned shallowly so native Apple utility apps such as Finder and Screen Saver can be launched without script-level actions or the latency cost of a full support-tree walk.
- System apps such as Calculator and System Settings are covered by `/System/Applications`.
