# Bucky Architecture Audit and Refactor Design

## Goal

Reduce accidental complexity in Bucky while preserving current launcher, files, settings, indexing, persistence, and animation behavior; make the test suite smaller and more contract-focused; remove identified personal and company-specific fixture data from current files and Git history.

## Baseline

- Repository: Swift Package macOS executable, minimum macOS 26.
- Current version: 3.1.0.
- Baseline verification: `swift test` passes 347 tests with 0 failures.
- Performance baseline: launcher filtering remains inside the existing comfort band.
- Largest production files are `FileBrowserView.swift`, `LiquidGlassLauncherModel.swift`, `SettingsView.swift`, `LiquidGlassLauncherWindowController.swift`, and `FileBrowserModel.swift`.
- The largest test files are `FileBrowserModelTests.swift`, `LauncherModeRoutingTests.swift`, and `SettingsViewLayoutTests.swift`.

## Principles

1. Preserve observable behavior unless a documented inconsistency is corrected.
2. Prefer a small shared helper over a framework-like abstraction.
3. Test public or internal behavior and policy outputs, not source-code spelling.
4. Keep UI work and background data work independent; loading states remain explicit.
5. Make asynchronous work cancellable, generation-scoped, and weakly owned where appropriate.
6. Do not log custom command contents or other user data.
7. Make destructive file and Git operations recoverable and verify their exact scope.

## Workstreams

### 1. Test suite hygiene and fixture privacy

Remove tests whose only purpose is to search source files for a string that should or should not exist, beginning with the Finder-default assertion in `InclusionExclusionStoresTests.swift`. Retain behavior coverage for routing, filtering, persistence, and policy calculations. Where a source assertion protects a meaningful runtime contract, expose or reuse a small policy seam and test its result; otherwise delete the assertion rather than preserve a brittle textual proxy.

Consolidate repeated test setup into neutral helpers. Replace personal or company-specific fixture values with generic values such as `/Users/test`, `SampleCloudTarget`, and `Sample Cloud Target`. Queue-label tests must not assert a developer-specific reverse-DNS identifier.

### 2. Shared runtime infrastructure

- Extract one application-filtering implementation that supports both full `LaunchItem` results and stable `AppRowID` results without duplicating token matching and scoring.
- Extract the common asynchronous `NSImage` cache behavior used by application and file rows. The shared cache must retain bounded cache size, in-flight request coalescing, bounded concurrent native icon loads, cancellation-safe cleanup, and the existing per-domain limits.
- Extract only the repeated JSON file encode/decode and atomic-write mechanics needed by settings, history, inclusion/exclusion, file-browser state, and snapshot persistence. Preserve each store’s current default and malformed-file behavior, including the intentional difference for inclusion files.

### 3. File decomposition

Split only cohesive, private responsibilities from oversized files after the shared helpers are stable:

- launcher filtering and cache policy types from `LiquidGlassLauncherModel.swift`;
- application/file icon views, preload policies, and cache wiring from their parent views;
- settings subviews and help catalog from `SettingsView.swift`;
- file-browser preview support from `FileBrowserView.swift` where the extracted boundaries do not require behavior changes.

Do not split `FileBrowserModel` or `LiquidGlassLauncherWindowController` solely to reduce line count. Their state transitions must first have clear interfaces and contract tests.

### 4. Security, memory, and lifecycle review

Review custom shell-command launch, native file operations, security-scoped bookmark access, directory watchers, FSEvents teardown, notification observers, timers, and asynchronous tasks. Add focused tests for any lifecycle behavior that is currently unprotected. Preserve the existing security posture of not exposing command contents in logs and ensure cancellation cannot leave continuations, timers, or observers retained indefinitely.

### 5. Documentation and versioning

Correct `README.md` and `.agents/docs/bucky-architecture.md` so they describe the current empty inclusion default and shallow CoreServices discovery of Finder. Bump `CFBundleShortVersionString` from 3.1.0 to 3.1.1 for the compatible internal refactor and documentation correction.

### 6. History rewrite

After code changes are committed and verified, create a recovery bundle outside the repository. Rewrite all local branch, remote-tracking, and tag histories so test files no longer contain these identified values:

- `harriche`;
- `Cisco` and both OneDrive fixture spellings;
- `mechaHarry` when it appears in test fixtures or test assertions.

Use neutral replacements that preserve test meaning. Do not rewrite unrelated public ownership metadata such as `CODEOWNERS` unless separately requested. Verify every reachable commit and every rewritten test blob, then report that remote branches will require coordinated force-updates if the cleaned history is to be published.

## Verification

Each workstream is verified independently with focused tests, followed by:

```sh
swift test
make bundle
git diff --check
```

The launcher-filter performance test must remain within its configured comfort band. Final history verification must demonstrate that the forbidden strings are absent from all reachable commit contents under the chosen ref scope and that the recovery bundle exists before refs are changed.

## Non-goals

- No new product features.
- No change to the launcher’s user-facing mode behavior, hotkeys, or persistence formats.
- No wholesale rewrite of SwiftUI views or file-browser state management.
- No force-push to any remote without a separate explicit request.
