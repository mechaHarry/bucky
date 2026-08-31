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

Use `Cmd+1` for Apps, `Cmd+2` for Calculator, `Cmd+3` for Dictionary, and `Cmd+4` for Files while the launcher is open. Use Command+Left and Command+Right to cycle launcher modes, and Command+/ to open shortcut help. Calculator and Dictionary remain separate modes: arithmetic text such as `1` or `2 + 3` is evaluated inline in Calculator without opening Calculator, while Dictionary lookups use fuzzy spelling and completion matches. Press Return on a calculation result to copy it, or on a dictionary result to open Dictionary at the matching word. Calculator mode includes a clear-history button; pin is available from any mode, can be toggled with Command+P while Bucky is focused, and keeps the window above other apps until unpinned.

Files mode shows mounted volumes alongside folders and files, and supports folders-first sorting when you want directories grouped ahead of other entries.

Bucky now uses the SwiftUI-native Liquid Glass launcher with a glass window surface, per-row glass effects, glass buttons, and animated state transitions. macOS 26 is required; the previous AppKit launcher has been removed.

App indexing starts during launcher controller initialization and stays fresh through the source stream, settings changes, and explicit refresh paths. Opening the launcher only presents and focuses the existing window state; while the launcher is open, Command+R reindexes and refreshes the currently displayed results using the current search text. Command+Comma opens Settings.

The menu bar item provides Open, Reindex, Settings, and Quit actions. Bucky scans `.app` bundles recursively under `/Applications`, `/System/Applications`, and `~/Applications`, and scans only direct child `.app` bundles under `/System/Library/CoreServices` so native utilities such as Finder stay launchable without walking nested support trees.

App indexing and mode handoff stay asynchronous. Apps can briefly show `Loading apps` while a background index is still populating the first result set. Switching into Files first shows a lightweight `Loading files` placeholder until the file browser model is activated, then the file browser publishes its own loading or loaded directory state.

## Stone Boundaries

Shared launcher mode metadata lives in `StoneCatalog`, shared rows flow through `StoneResultRow` and `StoneResultSnapshot`, and shared side effects flow through `StoneActivation` plus `LiquidGlassLauncherModel.perform(_:,for:)`. That keeps mode definitions, result rendering, and activation behavior aligned across Apps, Calculator, Dictionary, and Files.

To add a new Stone:

- Define a provider-owned `StoneDefinition` and register the provider through `StoneProviderRegistry`; the provider owns its `StoneID`, metadata, query behavior, and activation mapping.
- Use the registry-backed launcher mode and shortcut collections so the new Stone appears in ordering, keyboard navigation, placeholders, icons, surfaces, tints, and update policy without editing a central enum or switch.
- Keep Stone-specific query/result behavior in a focused Stone helper or boundary, then map its output into shared `StoneResultRow` and `StoneResultSnapshot` values.
- Reuse shared activation intents where possible and extend `StoneActivation` only if the new Stone needs a genuinely new cross-cutting side effect.
- Add focused coverage in `Tests/BuckyTests/StoneCatalogTests.swift`, `Tests/BuckyTests/LauncherModeRoutingTests.swift`, `Tests/BuckyTests/StoneResultsTests.swift`, plus Stone-specific behavior tests for the new domain.
- Keep domain-specific rules inside the new Stone instead of widening shared launcher policy.

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

If `inclusions.json` is missing, Bucky creates it with an empty `includedPaths` array. If the file is malformed, Bucky rewrites it as valid empty JSON and continues with no explicit inclusions. Finder is no longer injected through this file; it is discovered by the direct `/System/Library/CoreServices` scan.

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

If `exclusions.json` is missing or malformed, Bucky falls back to an empty exclusion set. The file is only written when exclusions are changed.

## Fixture And PII Rules

Committed fixtures, screenshots, and JSON examples must stay neutral. Use placeholders such as `/Users/test`, `/Applications/Example.app`, and sample names already used in tests. Do not commit company names, customer names, private domains, or other non-public identifiers in docs, fixtures, or example config.
