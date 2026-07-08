# Bucky

The no-frills/robust approach to macOS Launchers.

## Build

```sh
make bundle
```

The app bundle is created at `build/Bucky.app`.

## Run

```sh
open build/Bucky.app
```

## Distribution

For a local distributable archive, run the package script. It starts from a clean rebuild, packages only the `.app` bundle, and writes a zip plus SHA-256 checksum under `dist/`.

```sh
./package.sh
```

The generated archive uses this naming pattern:

```text
dist/Bucky-<semantic-version>-macos-<architecture>.zip
```

To test the archive from Terminal:

```sh
ZIP_PATH="$(ls -t dist/Bucky-*.zip | head -n 1)"
mkdir -p /tmp/bucky-distribution-test
ditto -x -k "$ZIP_PATH" /tmp/bucky-distribution-test
open /tmp/bucky-distribution-test/Bucky.app
```

To install it manually from Terminal after unzipping:

```sh
ZIP_PATH="$(ls -t dist/Bucky-*.zip | head -n 1)"
ditto -x -k "$ZIP_PATH" /tmp
mv /tmp/Bucky.app /Applications/Bucky.app
open /Applications/Bucky.app
```

This zip is a local unsigned build artifact. For broad distribution outside your own machine, sign and notarize the app before sharing it.

## Behavior

Use Option+Space to open or hide the floating launcher by default. Type to filter parsed app names, use the up and down arrows to move through the list, use Command+Up and Command+Down to jump to the top or bottom, and press Return to launch the selected app.

Use `Cmd+1` for Apps and `Cmd+4` for Files while the launcher is open; `Cmd+2`, `Cmd+3`, and `Cmd+5` are unassigned. Command+Left and Command+Right cycle between Apps and Files. In Apps search, `=` as the first non-filler (non-whitespace) character starts the calculator route, and `?` in that position starts the dictionary route. Calculator expressions such as `1` or `2 + 3` are evaluated inline without opening Calculator, while dictionary lookups use fuzzy spelling and completion matches. Press Return on a calculation result to copy it, or on a dictionary result to open Dictionary at the matching word. The calculator route includes a clear-history button; pin is available in either mode, can be toggled with Command+P while Bucky is focused, and keeps the window above other apps until unpinned.

Bucky now uses the SwiftUI-native Liquid Glass launcher with a glass window surface, per-row glass effects, glass buttons, and animated state transitions. macOS 26 is required; the previous AppKit launcher has been removed.

Indexing starts when the launcher controller initializes and refreshes when configured sources or relevant settings change. While the launcher is open, Command+R explicitly reindexes and refreshes the currently displayed results using the current search text. Command+Comma opens Settings.

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
