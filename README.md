# Bucky

Bucky is a small local macOS launcher.

## Build

```sh
make bundle
```

The app bundle is created at `build/Bucky.app`.

## Run

```sh
open build/Bucky.app
```

Use Option+Space to open or hide the floating launcher by default. Type to filter parsed app names, use the up and down arrows to move through the list, use Command+Up and Command+Down to jump to the top or bottom, and press Return to launch the selected app.

Use Command+/ while the launcher is open to switch between app search and tools mode. In tools mode, arithmetic text such as `1` or `2 + 3` is evaluated inline without opening Calculator, and dictionary lookups use fuzzy spelling and completion matches. Press Return on a calculation result to copy it, or on a dictionary result to open Dictionary at the matching word. Tools mode includes a clear-history button; pin is available from either mode, can be toggled with Command+P while Bucky is focused, and keeps the window above other apps until unpinned.

Bucky now uses the SwiftUI-native Liquid Glass launcher with a glass window surface, per-row glass effects, glass buttons, and animated state transitions. macOS 26 is required; the previous AppKit launcher has been removed.

The launcher reindexes app locations in the background every time it opens. While the launcher is open, Command+R also reindexes and refreshes the currently displayed results using the current search text. Command+Comma opens Settings.

The menu bar item provides Open, Reindex, Settings, and Quit actions. Bucky scans `.app` bundles under `/Applications`, `/System/Applications`, and `~/Applications`.

Explicitly included apps are also indexed. The default inclusion is:

```text
/System/Library/CoreServices/Finder.app
```

## Settings

Settings are stored as JSON at:

```text
~/Library/Application Support/Bucky/settings.json
```

Settings currently include the global hotkey, launch-on-startup preference, and animation timing preference.

Calculation history is stored as JSON at:

```text
~/Library/Application Support/Bucky/calculations.json
```

## Inclusions

Included app paths are stored as JSON at:

```text
~/Library/Application Support/Bucky/inclusions.json
```

The file format is:

```json
{
  "includedPaths": [
    "/System/Library/CoreServices/Finder.app"
  ]
}
```

Use Settings to add apps through the macOS file picker or remove included apps from the list.

## Exclusions

Each result has a hide button. Exclusions are stored as JSON at:

```text
~/Library/Application Support/Bucky/exclusions.json
```

The file format is:

```json
{
  "excludedPaths": [
    "/Applications/Example.app"
  ]
}
```

Edit that file manually and press Command+R in Bucky to reload it, or remove hidden apps from Settings.
