# Changelog

All notable changes to Bucky are documented here.

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
