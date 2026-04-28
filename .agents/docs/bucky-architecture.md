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
  - `Sources/Bucky/UI/Shell`: macOS shell controllers for the menu bar item and SwiftUI settings window hosting.
  - `Sources/Bucky/UI/SwiftUI`: macOS 26 SwiftUI Liquid Glass launcher and settings view.
  - `Sources/Bucky/UI/Shared`: UI contracts, commands, and shared utilities.
- Build command: `make bundle`.
- Bundle metadata: `packaging/Info.plist`.
- Minimum runtime target: macOS 26 (`Package.swift` and `LSMinimumSystemVersion`).
- The app runs as an accessory/menu-bar app (`LSUIElement` true).
- The status item uses the `🦾` text glyph with variable width.

## App Indexing

- `ApplicationIndexer` scans `.app` bundles only. It does not index arbitrary executables.
- Recursive scan roots are:
  - `/Applications`
  - `/System/Applications`
  - `~/Applications`
- `/System/Library/CoreServices` is intentionally not a scan root.
- Explicit inclusions are merged after root scanning. This is how Finder is included without scanning all CoreServices.
- Default inclusion path: `/System/Library/CoreServices/Finder.app`.
- Dedupe is by full app path.
- Search text includes only the app title. Paths, directories, bundle identifiers, and executable names are not searchable.

## Config Files

All app config uses JSON under:

```text
~/Library/Application Support/Bucky/
```

Files:

- `settings.json`: hotkey, launch-on-startup preference, and animation timing preference.
- `inclusions.json`: explicit `.app` paths to merge into the index. Missing or malformed file defaults to Finder.
- `exclusions.json`: paths hidden from search results.
- `calculations.json`: most recent tools-mode calculations, newest first, capped at 100 entries.

Exclusions are applied after indexing and inclusions. An explicitly included app can still be hidden if its path is in exclusions.

## Launcher UX

- Default hotkey is Option+Space through Carbon `RegisterEventHotKey`.
- Hotkey can be changed in Settings and is persisted in `settings.json`.
- Up and Down move selection by one row; Command+Up and Command+Down jump to the first and last visible result.
- Command+/ is handled by the visible launcher window, not a global Carbon hotkey. It switches between app mode and tools mode.
- Escape clears the input first; if the input is already blank, it closes the launcher window.
- The launcher uses `LiquidGlassLauncherWindowController`, a borderless resizable `NSWindow` with an `NSHostingView` surface backed by `LiquidGlassLauncherView` and `LiquidGlassLauncherModel`.
- SwiftUI owns the Liquid Glass visual system: `GlassEffectContainer`, `glassEffect`, glass button styles, and glass transitions for the main window, header controls, and individual result rows.
- The previous AppKit launcher mode has been removed. AppKit remains for macOS application plumbing, global hotkeys, menu bar control, and hosting SwiftUI windows.
- The bundle declares macOS 26 as its minimum OS. The runtime path also shows an unsupported OS alert if the app is somehow launched below that target instead of falling back to a legacy launcher.
- Launcher opens on the hardware primary display using `CGMainDisplayID()`, not mouse/focus display.
- `show()` displays immediately, focuses the search field, then schedules background reindexing on the next main-loop pass.
- Reindexing runs on a background queue and publishes results back to the main thread.
- A small spinner at the right of the search bar indicates indexing.
- If a reindex is requested while one is active, one follow-up reindex is queued.
- During typing, if the next query would produce zero results, Bucky preserves the previous interactable filtered list. This only applies to search typing, not explicit config/index refreshes.

## Tools UX

- Tools mode does not search or launch apps.
- Tools mode exposes a clear-history button. Pin is global to app and tools modes. While pinned, the launcher stays above other apps, can be dragged by its background, refocuses on the global launcher hotkey, and stays open after result activation.
- Arithmetic input is detected before dictionary lookup. Purely arithmetic text, including a standalone number like `1`, stays in math mode and never triggers dictionary mode.
- Arithmetic expressions are evaluated with a local parser supporting `+`, `-`, `*`, `/`, `×`, `÷`, decimals, grouping commas, unary signs, and parentheses.
- Valid calculations with a binary arithmetic operator are added to `calculations.json` after a short typing debounce, and pressing Return on a live calculation commits it immediately.
- Non-arithmetic text is looked up through macOS Dictionary Services via `DCSCopyTextDefinition`, with fuzzy candidates from `NSSpellChecker` completions and guesses. Dictionary.app is not launched during lookup.
- Pressing Return on a calculation result copies its value to the pasteboard. Pressing Return on a dictionary result opens Dictionary.app at the matching word instead of copying the definition.

## Settings UX

- Settings opens with Command+Comma and from the menu bar item.
- Settings window level is `.floating`, so it stays above the launcher.
- Settings supports:
  - Recording the global hotkey.
  - Toggling launch on startup via `SMAppService.mainApp`.
  - Choosing Liquid Glass animation timing.
  - Managing included apps with Add/Remove. Add uses `NSOpenPanel` restricted to `.app` bundles.
  - Managing hidden apps with Remove.

## Known Product Decisions

- Apple-standard app config location is preferred over XDG because this is a native macOS GUI app.
- `/System/Library/CoreServices` should not be scanned wholesale.
- Finder is included by default through explicit inclusion instead.
- System apps such as Calculator and System Settings are covered by `/System/Applications`.
