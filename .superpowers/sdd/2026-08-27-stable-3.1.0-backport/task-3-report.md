# Task 3 Report

Date: 2026-08-27
Worktree: isolated release worktree for `agent/release-3.0.3-stable-backport`
Base before Task 3: `38266fa`

## Scope Completed

Implemented Task 3 from the stable 3.1.0 backport brief in the isolated release worktree:

- Backported launcher focus restoration and bounded focus-claim retry behavior without foreground app activation.
- Backported key-capable nonactivating launcher panel behavior.
- Backported hotkey open fade behavior, configurable animation timing, cold-open scheduling, and interrupted show/hide transition replacement.
- Added `LauncherWindowAlphaAnimationDriver` and `LauncherWindowVisibilityTransitionCoordinator` to centralize alpha animation cancellation, timing, generation guards, and terminal show/hide completion.
- Backported compact native status-menu presentation with a template `bolt.fill` icon and compact text fallback.
- Preserved Task 2 command/help routing and the `resetPanelVisibilityAfterHide()` seam.
- Avoided importing Notes/Agenda behavior and did not add Apps-prefixed calculator/dictionary routing.

## Cherry-Picks Applied

Applied the brief's no-commit source commits:

```bash
git cherry-pick -n d0eae3f
git cherry-pick -n 2676d57
git cherry-pick -n e8441a3
git cherry-pick -n a9d3636
git cherry-pick -n efc664c
git cherry-pick -n fee48fb
git cherry-pick -n fcb1df0
git cherry-pick -n 5650e9d
```

## Manual Reconciliation

- `2676d57` conflicted in `Tests/BuckyTests/LauncherModeRoutingTests.swift`. Resolution kept Task 2's help/settings reset test and added the hotkey fade test.
- `5650e9d` conflicted in `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`. Resolution kept the coordinator refactor while calling `model.resetPanelVisibilityAfterHide()` from `completeHidePresentation()` instead of the incoming `model.hideSettings()`, preserving Task 2's Help reset behavior.
- Updated the Task 2 preservation test to assert the new `completeHidePresentation()` path rather than the removed `finishHide(transitionID:)` helper.
- Reverted the staged `.agents/docs/bucky-architecture.md` status-menu documentation line because it was outside this task brief.

## Files Changed

- `Sources/Bucky/UI/Shared/BuckyPanelWindow.swift`
- `Sources/Bucky/UI/Shell/StatusMenuController.swift`
- `Sources/Bucky/UI/SwiftUI/LauncherWindowAlphaAnimationDriver.swift`
- `Sources/Bucky/UI/SwiftUI/LauncherWindowFramePolicy.swift`
- `Sources/Bucky/UI/SwiftUI/LauncherWindowVisibilityTransitionCoordinator.swift`
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift`
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`
- `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift`
- `Tests/BuckyTests/LauncherModeRoutingTests.swift`
- `Tests/BuckyTests/LauncherWindowOpenAnimationSchedulerTests.swift`
- `Tests/BuckyTests/LauncherWindowVisibilityTransitionTests.swift`
- `Tests/BuckyTests/ModeSwitcherLayoutPolicyTests.swift`
- `Tests/BuckyTests/SettingsViewLayoutTests.swift`
- `Tests/BuckyTests/StatusMenuControllerTests.swift`

## Verification

Focused tests run in the release worktree:

```bash
swift test --filter LauncherWindow
swift test --filter LauncherModeRoutingTests
swift test --filter StatusMenuControllerTests
```

Results:

- `LauncherWindow`: passed, 27 tests, 0 failures.
- `LauncherModeRoutingTests`: passed, 56 tests, 0 failures.
- `StatusMenuControllerTests`: passed, 2 tests, 0 failures.

Diff and async-safety checks:

```bash
rg -n "Task\\(|DispatchQueue|Timer|async|weak self|generation|transition" Sources/Bucky/UI/SwiftUI Sources/Bucky/Files
git diff --check
git diff --cached -G 'Agenda|Notes|note|agenda' -- Sources/Bucky Tests/BuckyTests
```

Observed notes:

- `git diff --check` returned clean.
- No staged Agenda/Notes additions were found in source or tests.
- New transition callbacks are generation-guarded through `LauncherWindowVisibilityTransitionCoordinator.complete(...)`.
- New AppKit alpha callbacks use weak owner/window captures.
- New focus retries are bounded by `LauncherWindowFocusClaimPolicy.retryDelays` and invalidated by `focusClaimID`.
- Existing model async work retains its prior cancellation/generation patterns.

## Security / Stability Review

- No new network behavior was added.
- No new destructive filesystem operation was added.
- No user, company, customer, domain, or private path data was added to source or tests.
- The status-menu change is local AppKit UI presentation only and preserves existing menu actions.
- `packaging/Info.plist` remains `3.0.2`; the SDD ledger assigns the `3.1.0` semantic-version bump to Task 4, so Task 3 did not modify release metadata.

## Commit

Planned signed commit message:

```bash
git commit -S -m "fix: stabilize launcher transitions"
```

Commit note:

- The initial signed commit attempt was blocked because the configured local `ggshield` pre-commit hook could not find the `ggshield` executable.
- Per the global plan constraint, the final signed commit used `--no-verify` to bypass only that unavailable local hook.

## Fix Round 1

Reviewer issue: P1 transition race when returning from Help or Settings while a hide animation is in flight.

Root cause:

- `hide()` requested a hide generation and started the alpha animation.
- `showLauncherFromPanel()` cleared the Help/Settings panel and focused the window, but did not request a replacement show generation.
- The old hide animation completion could therefore still match the coordinator state and run `completeHidePresentation()`, ordering the launcher out after the panel return.

Fix:

- Updated `showLauncherFromPanel()` to use `LauncherWindowShowTransitionPolicy`, request `.show` through `visibilityTransitionCoordinator`, and either start `animateWindowOpen(generation:)` or complete the show generation for synchronous materialized returns.
- Preserved `model.resetPanelVisibilityAfterHide()` in `completeHidePresentation()`.
- Kept stable Help/mode behavior unchanged and did not add any Apps/Agenda/Notes routing.

Regression coverage:

- Added a coordinator test proving a show request during hiding cancels the hide and ignores the stale hide completion.
- Added a source-contract test proving panel returns request a replacement show generation and complete or animate it.

Fix-round verification:

```bash
swift test --filter LauncherModeRoutingTests/testReturningFromPanelDuringHideReplacesTransitionGeneration
swift test --filter LauncherWindowVisibilityTransitionTests/testShowRequestDuringHidingCancelsHideAndIgnoresStaleHideCompletion
swift test --filter LauncherWindow
swift test --filter LauncherModeRoutingTests
git diff --check
```

Results:

- The new source-contract test failed before the fix because `showLauncherFromPanel()` did not request `.show`.
- Both focused regressions passed after the fix.
- Full focused transition/routing tests passed with 28/28 `LauncherWindow` tests and 57/57 `LauncherModeRoutingTests`.
- `git diff --check` returned clean.

Fix-round commit:

```bash
git commit -S --no-verify -m "fix: replace panel return transitions"
```

Commit note:

- The signed fix-round commit used `--no-verify` for the same unavailable local `ggshield` pre-commit hook recorded above.
