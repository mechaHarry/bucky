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

Use `Cmd+1` for Calculator, `Cmd+2` for Dictionary, and `Cmd+3` for Files while the launcher is open. Use Command+Left and Command+Right to cycle launcher modes, and Command+/ to open shortcut help. Calculator and Dictionary remain separate modes: arithmetic text such as `1` or `2 + 3` is evaluated inline in Calculator without opening Calculator, while Dictionary lookups use fuzzy spelling and completion matches. Press Return on a calculation result to copy it, or on a dictionary result to open Dictionary at the matching word. Calculator mode includes a clear-history button; pin is available from any mode, can be toggled with Command+P while Bucky is focused, and keeps the window above other apps until unpinned.

Files mode shows mounted volumes alongside folders and files, and supports folders-first sorting when you want directories grouped ahead of other entries.

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
