# File Browser Design

Date: 2026-05-04
Branch: `file-browser`
Target version: `3.0.0`

## Summary

Bucky will add a first-class Files mode to the launcher. The current left-side main-view rail will be replaced by a top Liquid Glass mode row where the active mode expands into a pill and inactive modes are circular icon orbs. Modes are ordered Apps, Calculator, Dictionary, Files and are addressable with `Cmd+1`, `Cmd+2`, `Cmd+3`, and `Cmd+4`.

Files mode is a keyboard-driven, native macOS file browser. It starts at the last persisted directory when available, otherwise home. It supports pinned directories, hidden files shown by default, sorting, multi-depth selection, staged copy/move, Move to Trash, Finder-style conflict handling, native file icons, and held-Space Quick Look-style previews.

## Goals

- Keep the launcher horizontally roomy by replacing the left main-view sidebar with top-layer mode orbs.
- Add Files as a native-feeling, Liquid Glass browser built around keyboard navigation.
- Keep file state and file operations isolated from existing app search, calculator, and dictionary behavior.
- Persist pins, last directory, sort mode, and recent traversal path.
- Make copy, move, rename, and trash flows explicit, confirmable, and recoverable.
- Provide strict model tests for navigation, selection, persistence, and operation state.

## Non-Goals

- No drag-and-drop file transfer out of Bucky in the initial version.
- No permanent delete operation.
- No shell-based file operations.
- No general-purpose text input in Files browse mode beyond shortcuts and first-character navigation.

## Architecture

The implementation should use a native subsystem instead of folding file behavior into the existing launcher model.

- `LauncherMode`: defines ordered modes: Apps, Calculator, Dictionary, Files.
- `ModeSwitcherView`: renders the top Liquid Glass mode row. Active mode expands into the pill; inactive modes are circular icon orbs.
- `FileBrowserModel`: owns current directory, directory stack, selected rows, multi-depth selections, sorting, pins, hidden-file visibility, preview/action state, copy/move pending state, and traversal memory.
- `FileSystemClient`: reads directories, resolves metadata, sorts entries, and exposes parent/child relationships.
- `FileBrowserStore`: persists pins, last active directory, sort mode, and remembered traversal chain under Bucky app support.
- `FileBrowserView`: renders pinned directories, gliding directory columns, rows, marquee labels, action overlay, rename overlay, transfer confirmation, conflict popup, and Quick Look peek.
- `MacFileServices`: wraps AppKit/Foundation integrations: `NSWorkspace` icons, Open, Reveal in Finder, pasteboard path copy, Trash, and preview support.

The model and file clients should be testable without SwiftUI. SwiftUI should render state and forward key commands rather than own file rules.

## Mode Switcher

The main mode UI sits on one top layer:

- Apps active: expanded search pill, then Calculator, Dictionary, and Files icon orbs.
- Calculator active: Apps orb, expanded calculator pill, Dictionary orb, Files orb.
- Dictionary active: Apps orb, Calculator orb, expanded dictionary pill, Files orb.
- Files active: Apps orb, Calculator orb, Dictionary orb, expanded path/sort pill.

Files active pill is not an input. It displays the full path for the current directory or focused file. Clicking the path copies it. The sort control lives inside the pill and offers Name, Date Created, Date Modified, and Size. Long paths marquee back and forth only when overflowing, with fade masks at overflowing edges.

## Files Layout

Files mode uses a multi-pane layout:

- A left pinned-directory rail inside the Files body.
- Two or three gliding directory columns showing the active path context.
- Rows with file or directory name on the left and native macOS icon on the right.
- Long row names use the same overflow-only fade marquee behavior as the path pill.
- Hidden files and directories are shown by default.
- Smart placeholders appear while directory data loads or when a directory cannot be read.

The action/preview pane is an overlay. It never reserves horizontal layout width.

## Keyboard State Flow

Files mode has explicit focus states.

### Browse

Default state.

- Up/Down: select different rows in the current directory.
- Left: move to parent directory.
- Right: enter selected directory.
- Right on a file: wobble the current pane.
- Left at root/no parent: wobble the current pane.
- Alphanumeric keys: cycle through current-directory entries with matching first character.
- Tap Space: toggle selection for the current row.
- Shift+Space: range-select from the prior anchor to the current row.
- Hold Space: show Quick Look-style preview while held.
- Release Space: dismiss the preview and return to browse focus.
- Return: open the focused action overlay.

### Preview Actions

Action overlay is focused.

- Up/Down: select an action.
- Return: perform or start the selected action.
- Escape: close overlay and return to browse.

Actions adapt to the current selection. Single selection supports Open, Rename, Reveal in Finder, Copy Path, Copy, Move, and Move to Trash. Multiple selection supports Batch Rename, Copy Paths, Copy, Move, and Move to Trash. Multi-selection can span multiple directories, and the overlay groups selected items by parent path with clear counts.

### Renaming

Rename and Batch Rename use a separate focused overlay.

- Return: confirm.
- Escape: cancel and return to the action overlay.

### Transfer Pending

Copy and Move first stage a payload. The action overlay slides mostly out of view, is clipped by the main panel, and is dimmed or blurred to indicate it is out of focus. Browse focus returns and the destination pane gets an oscillating glow.

- Return: ask for confirmation to copy or move staged items into the current directory.
- Escape: cancel the transfer and restore the action overlay focus.

Name conflicts use a Finder-style popup with Keep Both, Replace, and Cancel.

### Confirming

Confirmation overlays are used for copy/move, conflicts, and Move to Trash. Move to Trash requires a double-confirm popup.

## Path Memory

Files remembers two related states:

- Last active directory, persisted across launches.
- Recent traversal chain, kept so rapid Left/Right navigation feels reversible.

Holding Left repeatedly should climb parents quickly toward root while preserving the recently traversed child chain. Holding Right immediately afterward should follow that remembered chain back down when possible. If a remembered child no longer exists, the chain stops gracefully at the deepest valid directory.

## File Operations

All file operations go through `MacFileServices` or `FileSystemClient`; views do not operate on paths directly.

- Open: `NSWorkspace.open`.
- Reveal in Finder: `NSWorkspace.activateFileViewerSelecting`.
- Copy Path/Copy Paths: write full paths to the pasteboard.
- Copy: stage payload, confirm destination, then copy through Foundation file APIs.
- Move: stage payload, confirm destination, then move through Foundation file APIs.
- Move to Trash: use `FileManager.trashItem`, never permanent deletion.
- Rename/Batch Rename: validate target names and apply through Foundation file APIs.

Operations should avoid shell execution. They should operate on resolved URLs, report recoverable errors, prune stale selections after directory refresh, and avoid following symlink cycles while building path context.

## Quick Look-Style Preview

Held Space opens a transient preview for the focused row. Releasing Space dismisses it.

Supported files should preview through native macOS capabilities where feasible. Unsupported files show a fallback surface with native icon, kind, size, dates, and full path. Preview resources should be released when the held-Space preview closes so large files do not remain retained.

Return remains reserved for action flow. Quick Look peek does not change selection, scroll position, or current row.

## Persistence

`FileBrowserStore` persists a compact JSON file in Bucky app support:

- Pinned directory URLs.
- Last active directory.
- Sort mode.
- Remembered traversal chain.

Files opens at the persisted last active directory when valid. If that directory is gone or unreadable, it falls back to home and surfaces a non-blocking placeholder/error state.

## Errors And Security

Directory reads, metadata fetches, and file operations should fail gracefully. Permission failures, missing files, and stale selections should render focused, recoverable UI states instead of crashing or silently doing nothing.

The app should not execute file contents. Opening files delegates to `NSWorkspace` after an explicit user action. Move to Trash is the only destructive operation and is double-confirmed. Copy and move require destination confirmation. Conflict behavior is explicit and user-selected.

Preview and icon loading should avoid retaining large resources longer than needed. Directory enumeration should be cancellable or stale-result guarded so quick navigation does not render outdated data over newer state.

## Testing

Strict tests are required for this feature.

Model tests:

- Sort by name, date created, date modified, and size.
- Hidden files shown by default.
- Up/Down selection behavior.
- First-character cycling.
- Left/Right parent and child navigation.
- Wobble state when Right is pressed on a file or Left has no parent.
- Tap Space selection.
- Shift+Space range selection.
- Multi-depth selection grouping.
- Preview action availability for single vs multiple selections.
- Transfer pending state, cancel, and destination confirmation.
- Conflict decisions: Keep Both, Replace, Cancel.
- Move to Trash double-confirm state.
- Last directory persistence.
- Pin persistence.
- Traversal chain restoration after climbing toward root.
- Stale selection pruning after directory refresh.

UI/key handling tests:

- `Cmd+1...4` routes to Apps, Calculator, Dictionary, Files.
- Browse state owns non-shortcut alphanumeric input.
- Return moves from browse to action overlay.
- Escape returns from preview/action/rename/transfer states as specified.
- Held Space opens preview and release dismisses it without toggling selection.

Integration or service tests:

- File operation clients use injected temporary directories.
- Trash behavior is abstracted for tests so permanent deletion is never needed.
- Persistence reads invalid/missing JSON gracefully and falls back to defaults.

## Release Work

Implementation should update app semantic version metadata to `3.0.0` on the `file-browser` branch after the feature plan is approved.
