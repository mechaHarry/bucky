# Faster Window Animation Timing Design

## Context

Launcher window presentation currently uses the shared `LauncherWindowPresentationAnimationPolicy` for both open and close alpha fades. The configured smooth timing is 0.24 seconds and the snappy timing is 0.12 seconds. Cold opens also use a deferred scheduler with transition and visibility guards so content is materialized before the fade begins. The goal is to reduce perceived hotkey latency without changing launcher behavior or presentation architecture.

## Chosen Approach

Change only the shared policy durations:

- `.smooth`: 0.24 seconds to 0.20 seconds.
- `.snappy`: 0.12 seconds to 0.10 seconds.

Preserve the existing timing functions: smooth uses `easeInEaseOut`, and snappy uses `easeOut`. Keep the distinction between the two settings. No new setting, animation abstraction, or UI surface is needed.

## Alternatives Rejected

- Changing the timing functions was rejected because it would alter the character of the existing smooth and snappy modes, not only their speed.
- Adding a separate cold-open duration was rejected because it would duplicate policy and risk divergence between open and close presentation.
- Changing SwiftUI content transitions or the window lifecycle was rejected because the latency goal does not require changing hide/show ownership, focus behavior, or surface materialization.
- Removing the smooth/snappy distinction was rejected because users already control that preference and the modes have intentionally different motion profiles.

## Behavior And Architecture

Both launcher window open and close presentation animations continue to obtain their duration and timing function from `LauncherWindowPresentationAnimationPolicy`. The new durations reduce the current values by approximately 17% for smooth and 16.7% for snappy while retaining the same curves.

The implementation must preserve the cold-open deferred scheduler, transition IDs, visibility-state checks, completion guards, and non-animated SwiftUI materialization. It must also preserve focus retries, indexing and background work, mode routing, surface lifecycle, and the existing hide/show architecture. The change must not introduce blocking work, new persistent data, network access, credentials, or logging of user content.

## Testing

Strict policy tests must assert 0.20 seconds for smooth and 0.10 seconds for snappy, along with the existing timing-function expectations. Focused launcher routing tests must continue to verify that open and close use the shared policy and that cold-open scheduler and race guards remain present. Run the full Swift test suite and the existing launcher performance guard.

Packaged live verification must exercise the first cold hotkey open and confirm that the window reaches its expected visible alpha after the deferred fade, without a blank, stuck, or prematurely removed surface. The verification must also cover a subsequent close and reopen path so both directions use the policy. No UI or settings tests should be added for behavior that is explicitly out of scope.

## Out Of Scope

- New UI, settings, animation preferences, or user-facing controls.
- Changes to timing functions, spring/bounce behavior, or non-window SwiftUI animations.
- Changes to cold-open scheduling, race guards, focus retries, indexing, mode routing, or surface lifecycle.
- Changes to window sizing, positioning, opacity semantics, accessibility behavior, or persistence.
- Reworking performance infrastructure beyond running the existing guard.
