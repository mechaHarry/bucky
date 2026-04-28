# Bucky Architecture Notes

This project is a local-only macOS launcher implemented as a Swift Package/AppKit executable and bundled into `build/Bucky.app` by `make bundle`.

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
  - `Sources/Bucky/UI/AppKit`: legacy-compatible AppKit launcher, settings, menu, and table views.
  - `Sources/Bucky/UI/SwiftUI`: macOS 26 SwiftUI Liquid Glass launcher.
  - `Sources/Bucky/UI/Shared`: UI contracts, commands, utilities, and resize grip.
- Build command: `make bundle`.
- Bundle metadata: `packaging/Info.plist`.
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

- `settings.json`: hotkey and launch-on-startup preference.
- `inclusions.json`: explicit `.app` paths to merge into the index. Missing or malformed file defaults to Finder.
- `exclusions.json`: paths hidden from search results.
- `calculations.json`: most recent tools-mode calculations, newest first, capped at 100 entries.

Exclusions are applied after indexing and inclusions. An explicitly included app can still be hidden if its path is in exclusions.

## Launcher UX

- Default hotkey is Option+Space through Carbon `RegisterEventHotKey`.
- Hotkey can be changed in Settings and is persisted in `settings.json`.
- Up and Down move selection by one row; Command+Up and Command+Down jump to the first and last visible result.
- Shift+/ is handled by a local key monitor scoped to the visible launcher window, not a global Carbon hotkey. It switches between app mode and tools mode only when the input is blank.
- Escape clears the input first; if the input is already blank, it closes the launcher window.
- The legacy AppKit launcher is an always-on-top borderless `NSPanel`; the macOS 26 Liquid Glass launcher uses a borderless resizable `NSWindow` hosting a full SwiftUI glass surface.
- A custom bottom-right resize grip resizes the borderless launcher directly, with a 520x340 minimum size on the SwiftUI Liquid Glass path.
- `AppDelegate` chooses the launcher implementation through `LauncherControlling`.
- On macOS 26+, the default launcher is `LiquidGlassLauncherWindowController`, an `NSHostingView` surface backed by `LiquidGlassLauncherView` and `LiquidGlassLauncherModel`. It uses SwiftUI `GlassEffectContainer`, `glassEffect`, glass button styles, and glass transitions for the main window, header controls, and individual result rows.
- Set `BUCKY_FORCE_APPKIT_UI=1` to force the AppKit launcher on macOS 26.
- The AppKit launcher still has a macOS 26 Liquid Glass path using `NSGlassEffectView` and glass button chrome. Earlier macOS versions use `NSVisualEffectView.material = .hudWindow` and textured rounded buttons.
- Launcher opens on the hardware primary display using `CGMainDisplayID()`, not mouse/focus display.
- `show()` displays immediately, focuses the search field, then schedules background reindexing on the next main-loop pass.
- Reindexing runs on a background queue and publishes results back to the main thread.
- A small spinner at the right of the search bar indicates indexing.
- If a reindex is requested while one is active, one follow-up reindex is queued.
- During typing, if the next query would produce zero results, Bucky preserves the previous interactable filtered list. This only applies to search typing, not explicit config/index refreshes.

## Tools UX

- Tools mode does not search or launch apps.
- Tools mode exposes a clear-history button for calculation history.
- Tools mode exposes a pin button. While pinned, the launcher stays above other apps, can be dragged by its background, ignores the global launcher hotkey, stays open after result activation, and cannot switch back to app mode until unpinned.
- Arithmetic input is detected before dictionary lookup. Purely arithmetic text, including a standalone number like `1`, stays in math mode and never triggers dictionary mode.
- Arithmetic expressions are evaluated with a local parser supporting `+`, `-`, `*`, `/`, `×`, `÷`, decimals, grouping commas, unary signs, and parentheses.
- Valid calculations with a binary arithmetic operator are added to `calculations.json` after a short typing debounce, and pressing Return on a live calculation commits it immediately.
- Non-arithmetic text is looked up through macOS Dictionary Services via `DCSCopyTextDefinition`, with fuzzy candidates from `NSSpellChecker` completions and guesses. Dictionary.app is not launched during lookup.
- Pressing Return on a calculation result copies its value to the pasteboard. Pressing Return on a dictionary result opens Dictionary.app at the matching word instead of copying the definition.

## Settings UX

- Settings opens with Command+Comma and from the menu bar item.
- Settings window level is `.modalPanel`, so it stays above the launcher.
- Settings supports:
  - Recording the global hotkey.
  - Toggling launch on startup via `SMAppService.mainApp`.
  - Managing included apps with Add/Remove. Add uses `NSOpenPanel` restricted to `.app` bundles.
  - Managing hidden apps with Remove.

## Known Product Decisions

- Apple-standard app config location is preferred over XDG because this is a native macOS GUI app.
- `/System/Library/CoreServices` should not be scanned wholesale.
- Finder is included by default through explicit inclusion instead.
- System apps such as Calculator and System Settings are covered by `/System/Applications`.
