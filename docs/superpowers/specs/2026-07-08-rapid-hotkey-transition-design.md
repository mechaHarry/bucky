# Rapid Hotkey Transition Design

## Context

Rapid global hotkey toggles can take seconds to open the launcher. `visibilityTransitionID` guards logical completions, but it does not cancel in-flight AppKit `NSWindow` alpha animations. A rapid show/hide/show therefore leaves stale alpha animations competing for the same window. A hide received while the window is `.hiding` is currently dropped.

## Goals And Non-Goals

The goal is latest-intent-wins presentation: every hotkey intent must replace the active alpha transition, converge promptly to the requested visibility, and preserve existing focus, indexing, mode, and surface behavior. Keep the existing smooth duration of 0.20 seconds, snappy duration of 0.10 seconds, and their current curves. Keep the transition path AppKit-native and nonblocking.

Non-goals are debounce, input suppression, App Nap changes, indexing changes, focus-retry changes, hotkey-setting changes, visual redesign, or changes to mode and surface lifecycle. No user or customer data is introduced, persisted, or logged.

## Behavior

Each global hotkey produces a show or hide intent, including while another transition is running. The newest intent immediately invalidates the prior transition, cancels its native alpha animation, normalizes the window alpha to the current presentation boundary, and starts exactly one AppKit-native transition toward the newest target.

Only the winning hide completion calls `orderOut`. Only the winning show completion marks the window shown and performs the existing focus behavior. Stale completions have no effect. A sequence such as show-hide-show-hide therefore ends hidden and ordered out; the inverse sequence ends shown with the window visible. No input is debounced or discarded.

## Architecture And Data Flow

Add a small `@MainActor` presentation transition coordinator at the existing window-presentation boundary. It owns the current generation, latest visibility intent, and transition phase. The coordinator depends on an injectable native alpha animation driver that can cancel the current animation, read or normalize alpha, and animate to a target using the existing duration and timing-function policy.

The flow is:

1. The hotkey handler sends the latest show or hide intent to the coordinator.
2. The coordinator increments its generation, records the intent, cancels and replaces the active driver operation, and normalizes alpha before starting the replacement animation.
3. The driver runs one AppKit alpha animation on the main actor and returns a completion tagged with that generation and intent.
4. The coordinator accepts the completion only when both tags match the current generation and latest intent. It then performs the target-specific final action: shown-state/focus for show, or `orderOut` for hide.

The coordinator does not own indexing, query data, focus retry scheduling, mode routing, or surface materialization. Animation callbacks use weak ownership where required so a window/controller teardown cannot retain the coordinator or driver.

## Race And Error Handling

Generation and intent checks protect both transition start and completion. Cancellation is explicit replacement, not merely logical invalidation, so old AppKit animations cannot continue writing alpha after a new intent starts. Normalization prevents a replacement from inheriting an obsolete intermediate alpha. A completion arriving after cancellation, out of order, duplicated, or after teardown is ignored unless it matches the current generation and intent.

The driver must complete cancellation and replacement on the main actor. If the native animation API reports failure or cannot start, the coordinator applies the requested terminal alpha synchronously, then performs the same winning completion action. No retry loop, delay, blocking work, or payload logging is introduced.

## Tests

Use a deterministic fake driver to cover show-hide-show-hide and hide-show-hide-show sequences, including inverse ordering, and assert final alpha, `orderOut` calls, and latest visibility state. Deliver stale and out-of-order completions after replacement and assert that they cannot change alpha, ordering, focus, or state. Cover cancellation replacement, synchronous driver failure, duplicate completion, teardown, weak captures, and deallocation so the coordinator and driver do not leak.

Run the existing full Swift test suite, launcher performance test, and package/bundle validation. Live packaged verification must spam the global hotkey through rapid show/hide/show and inverse sequences and confirm that the final intent wins without a delayed opening, blank surface, stuck alpha, or premature ordering out.

## Alternatives Rejected

- Ignoring hotkeys during an animation was rejected because it drops user input and leaves the final state dependent on timing.
- Debouncing hotkeys was rejected because it adds latency and still does not provide immediate latest-intent semantics.
