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

Use Option+Space to open or hide the floating launcher by default. Type to filter parsed apps, use the up and down arrows to move through the list, and press Return to launch the selected app.

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

Settings currently include the global hotkey and launch-on-startup preference.

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
