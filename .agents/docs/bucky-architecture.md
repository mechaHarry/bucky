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
- The status item uses the `🦾` text glyph with variable width.

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
- `ApplicationIndexSourceStream` watches app roots, System Settings resources/extensions, and the Bucky config directory with an FSEvents stream on a utility queue. Events are debounced and then trigger a fresh app-index snapshot; the expensive index load remains off the main thread.
- `ApplicationRowStore` owns app row data behind stable `AppRowID` values. App filtering, selection, scroll identity, reconstruction identity, and icon preloading move row IDs or URLs instead of copying full row structs through the hot UI path.
- `ApplicationIndexSnapshotCache` memoizes the last app index to `app-index-snapshot.json` under Application Support. Startup loads this snapshot on a utility queue for fast first results, then live background indexing replaces it when fresh data arrives.
- App search memoization is generation-scoped: filter cache entries contain `AppRowID` arrays and are invalidated when `ApplicationRowStore.generation` changes, including entries produced by background warmers.

## Config Files

All app config uses JSON under:

```text
~/Library/Application Support/Bucky/
```

Files:

- `settings.json`: hotkey, launch-on-startup preference, animation timing preference, file-browser start directory, and custom actions.
- `inclusions.json`: explicit `.app` paths to merge into the index. Missing files are created with an empty array; malformed files are rewritten as valid empty JSON.
- `exclusions.json`: paths hidden from search results. Missing or malformed files fall back to an empty in-memory set until the user changes exclusions.
- `calculations.json`: most recent calculator-mode calculations, newest first, capped at 100 entries.
- `app-index-snapshot.json`: memoized launcher app/settings/action rows used as the startup snapshot. Malformed or incompatible snapshots are ignored and rebuilt by the next index pass.

Exclusions are applied after indexing and inclusions. An explicitly included app can still be hidden if its path is in exclusions.

## Launcher UX

- Default hotkey is Option+Space through Carbon `RegisterEventHotKey`.
- Hotkey can be changed in Settings and is persisted in `settings.json`.
- Up and Down move selection by one row; Command+Up and Command+Down jump to the first and last visible result.
- Launcher shortcuts are handled by the visible launcher window, not global Carbon hotkeys: Command+Left and Command+Right cycle modes with wraparound, Command+/ opens shortcut help, and Command-number shortcuts open Calculator, Dictionary, and Files directly.
- Escape clears the input first; if the input is already blank, it closes the launcher window.
- The launcher uses `LiquidGlassLauncherWindowController`, a borderless resizable `NSWindow` with an `NSHostingView` surface backed by `LiquidGlassLauncherView`, `LiquidGlassLauncherModel`, and the in-window settings model.
- SwiftUI owns the Liquid Glass visual system: `GlassEffectContainer`, `glassEffect`, glass button styles, and glass transitions for the main window, header controls, and individual result rows.
- The previous AppKit launcher mode has been removed. AppKit remains for macOS application plumbing, global hotkeys, menu bar control, and hosting SwiftUI windows.
- The bundle declares macOS 26 as its minimum OS. The runtime path also shows an unsupported OS alert if the app is somehow launched below that target instead of falling back to a legacy launcher.
- Launcher opens on the hardware primary display using `CGMainDisplayID()`, not mouse/focus display.
- `show()` displays immediately and focuses the search field without scheduling a freshness reindex. Index freshness comes from the source stream, settings changes, startup indexing, and explicit Command+R.
- Reindexing runs on a background queue and publishes results back to the main thread.
- Source change triggers keep the app index fresh without requiring Command+R as the normal refresh path.
- Reindex publication compares the new app snapshot with the current one before clearing filter state, so unchanged source events do not invalidate warm caches.
- A small spinner at the right of the search bar indicates indexing.
- If a reindex is requested while one is active, one follow-up reindex is queued.
- During typing, if the next query would produce zero results, Bucky preserves the previous interactable filtered list. This only applies to search typing, not explicit config/index refreshes.
- App filter cache entries store filtered `AppRowID` lists. Rows dereference through `ApplicationRowStore` at render/activation time.
- App icon preloading warms the visible slice first, then waits briefly before tail-loading additional app icons.

## Mode UX

- Calculator, Dictionary, and Files modes do not search or launch apps.
- Apps is the default mode and must not activate Files code. `LiquidGlassLauncherModel` creates `FileBrowserModel` lazily only when Files is selected or the Files UI requests it.
- Mode switches publish the new mode and restored query immediately, then defer mode-specific result snapshots behind the first interactable update. Stale deferred mode work is ignored by generation token.
- Mode switches publish the new mode immediately, then defer the mode-specific snapshot work one turn so the UI can render the new shell before heavier work starts.
- Files mode shows a lightweight `Loading files` placeholder if the file-browser model is not already warm, then prepares the model after the first Files frame.
- Files mode lists mounted volumes alongside directory contents and supports folders-first sorting so directories can stay grouped ahead of non-folder entries.
- File-browser directory lists flow through `FileBrowserDirectoryStreaming` before reaching SwiftUI. The model publishes stable loading, empty, and loaded snapshots and ignores stale stream results when a newer directory request wins.
- Calculator mode exposes a clear-history button. Pin is global to all launcher modes. While pinned, the launcher stays above other apps, shows a bolder accent border, can be dragged by its background, refocuses on the global launcher hotkey, and stays open after result activation.
- Calculator mode evaluates arithmetic expressions with a local parser supporting `+`, `-`, `*`, `/`, `×`, `÷`, decimals, grouping commas, unary signs, and parentheses.
- Valid calculations with a binary arithmetic operator are added to `calculations.json` after a short typing debounce, and pressing Return on a live calculation commits it immediately.
- Dictionary mode looks up text through macOS Dictionary Services via `DCSCopyTextDefinition`, with fuzzy candidates from `NSSpellChecker` completions and guesses. Dictionary.app is not launched during lookup.
- Pressing Return on a calculation result copies its value to the pasteboard. Pressing Return on a dictionary result opens Dictionary.app at the matching word instead of copying the definition.

## Settings UX

- Settings opens with Command+Comma and from the menu bar item inside the existing Bucky launcher panel.
- Command+Comma toggles the launcher panel between launcher mode and settings mode. The global launcher hotkey also returns from settings to launcher mode.
- Settings shares the same borderless transparent `BuckyPanelWindow` and hosting view architecture as the launcher, avoiding a second settings panel.
- Settings supports:
  - Recording the global hotkey.
  - Toggling launch on startup via `SMAppService.mainApp`.
  - Choosing Liquid Glass animation timing.
  - Managing included apps with Add/Remove. Add uses `NSOpenPanel` restricted to `.app` bundles.
  - Managing hidden apps with Remove.
  - Managing custom action names and shell commands that appear in app results as `Action`.

## Stone Extension Recipe

- Define a provider-owned `StoneDefinition` and register the provider through `StoneProviderRegistry`. The provider owns its `StoneID`, while its definition owns ordering, shortcut number, placeholder text, icon, tint, accepted surface, and update policy.
- Let `LauncherMode` bridge only the shared launcher-facing metadata from the registry-backed provider definition. If the new Stone uses text input, it should ride the existing text-input surface; if it is non-textual, define the narrow surface boundary it needs.
- Model result rows and activation intents separately. `StoneResultRow` carries stable row identity plus declarative `StoneActivation` values; `LiquidGlassLauncherModel.perform(_:,for:)` is the side-effect boundary that turns those intents into copy, open, or history-removal behavior.
- Keep Stone-specific result shaping inside the Stone or its focused helper, similar to `DictionaryStone`, and feed shared result rows back through `StoneResultSnapshot` rather than embedding side effects in SwiftUI.
- Add focused tests at the shared seams: catalog coverage (`StoneCatalogTests`), launcher routing (`LauncherModeRoutingTests`), row identity and activation mapping (`StoneResultsTests`), and Stone-specific behavior tests for the new domain.
- Keep domain policy local. Shared code should only learn new generic metadata or activation cases when the new Stone truly needs a new cross-cutting boundary.

## Fixture And PII Rules

- Tests and committed examples use neutral identifiers such as `/Users/test`, `/Applications/Example.app`, and `SampleCloudTarget`.
- Do not commit real company names, customer data, private domains, or other non-public identifiers in fixtures, screenshots, example JSON, or architecture notes.

## Known Product Decisions

- Apple-standard app config location is preferred over XDG because this is a native macOS GUI app.
- `/System/Library/CoreServices` is scanned shallowly so native Apple utility apps such as Finder and Screen Saver can be launched without script-level actions or the latency cost of a full support-tree walk.
- System apps such as Calculator and System Settings are covered by `/System/Applications`.
