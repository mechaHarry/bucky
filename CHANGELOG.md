# Changelog

All notable changes to Bucky are documented here.

## [3.2.8] - 2026-10-01

### Fixed

- Preserve saved configuration and Countdown records on failed reads or writes; reject new Countdowns at capacity instead of evicting existing records.
- Keep Files operations off the UI thread, prevent Keep Both destination races from replacing files, and suspend inactive directory work.
- Cancel obsolete directory and preview jobs, bound preview concurrency and retained navigation state, and skip unreadable children without losing readable siblings.
- Bound calculator input and recursion, and avoid integer formatting overflow.
- Use typed exclusions for custom actions and watch explicitly included apps and missing source roots.
- Bind confirmation actions to their originating Stone and block background interaction until dismissed.
- Restrict persisted files to private permissions and avoid logging private paths, commands, or URLs in diagnostics.
- Preserve tags and release assets on failure, verify signed tags and packages before publication, and retry API reads with bounded backoff.

### Changed

- Route Calculator history and async Stone actions through shared provider contracts and consolidate launcher shortcut decoding.
- Precompute app search metadata, generation-scope deferred filters, and replace recurring cache warming with bounded event-driven work.
- Update Countdown time text independently of stable rows, without fades or hidden/expired clock work.
- Save settings and history asynchronously, surface failures, and drain Files operations and queued persistence on normal quit.
- Package incrementally without cleaning shared build output, and isolate test data from normal app configuration.

## [3.2.7] - 2026-10-01

### Fixed

- Added native Cut, Copy, Paste, and Select All commands for focused input boxes throughout the app.

## [3.2.6] - 2026-09-03

### Fixed

- Focus the Countdown title field after the inline creation row finishes mounting during keyboard mode switches.

## [3.2.5] - 2026-09-03

### Fixed

- Reused the Files-style Liquid Glass confirmation overlay for Countdown deletion instead of opening a separate AppKit modal.
- Focus the Countdown title field when the stone opens and handle Return from any creation-row field.
- Refuse empty Countdown titles with a subtle red underline on the title field.

## [3.2.4] - 2026-09-02

### Changed

- Replaced the Countdown add/edit modal with an always-visible inline creation row containing native glass date and time fields.
- Press Return in the name field or the plus button to create a countdown immediately below the creation row.

## [3.2.3] - 2026-09-02

### Fixed

- Focus the Countdown name field immediately when the editor opens.
- Pass all keyboard input through to active Countdown modals so shifted text, Tab navigation, and date-picker arrow keys are handled by the modal.

## [3.2.2] - 2026-09-02

### Fixed

- Keep Countdown modal interactions visible while focus is temporarily lost, then restore launcher focus after the modal closes.
- Give Countdown editor controls stable spacing and enough room for date selection.
- Remove live result transition animation from Countdown updates so displayed time changes frame by frame.

## [3.2.1] - 2026-09-02

### Fixed

- Made the menubar icon size and visibility explicit so it remains visible across macOS menu bar layouts.

## [3.2.0] - 2026-09-01

### Added

- Added the green Countdowns Stone with named target datetimes, live remaining-time display, and add/edit/delete management.
- Added atomic JSON persistence for countdowns and generic Stone provider actions plus live refresh metadata.

## [3.1.6] - 2026-09-01

### Added

- Reusable Stone provider contracts, catalog metadata, shared result snapshots, row actions, and activation handling for future Stones.
- Shared animated skeleton loading states across launcher results, file browsing, and native previews.

### Improved

- Dictionary lookups and application icon loading now have bounded, cancellable, stale-result-safe execution paths.
- File preview loading now shows consistent loading feedback before native content is ready.
- Release tooling no longer fetches and rewrites existing historical tags during release preparation.

### Cleaned up

- Removed unused ranking seams, obsolete UI transition policy code, tautological tests, and non-neutral test fixture data from repository history.
- Updated architecture documentation with the extension recipe for adding a new Stone without duplicating launcher behavior or UI conventions.
