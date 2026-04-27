# Bucky Architecture Notes

This project is a local-only macOS launcher implemented as a Swift Package/AppKit executable and bundled into `build/Bucky.app` by `make bundle`.

## Build And Runtime

- Main source: `Sources/Bucky/main.swift`.
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
- Search text includes app title, bundle identifier, bundle executable name, and path.

## Config Files

All app config uses JSON under:

```text
~/Library/Application Support/Bucky/
```

Files:

- `settings.json`: hotkey and launch-on-startup preference.
- `inclusions.json`: explicit `.app` paths to merge into the index. Missing or malformed file defaults to Finder.
- `exclusions.json`: paths hidden from search results.

Exclusions are applied after indexing and inclusions. An explicitly included app can still be hidden if its path is in exclusions.

## Launcher UX

- Default hotkey is Option+Space through Carbon `RegisterEventHotKey`.
- Hotkey can be changed in Settings and is persisted in `settings.json`.
- The launcher panel is an always-on-top borderless `NSPanel`.
- Panel opens on the hardware primary display using `CGMainDisplayID()`, not mouse/focus display.
- `show()` displays immediately, focuses the search field, then schedules background reindexing on the next main-loop pass.
- Reindexing runs on a background queue and publishes results back to the main thread.
- A small spinner at the right of the search bar indicates indexing.
- If a reindex is requested while one is active, one follow-up reindex is queued.
- During typing, if the next query would produce zero results, Bucky preserves the previous interactable filtered list. This only applies to search typing, not explicit config/index refreshes.

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
