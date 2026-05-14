# Bucky Refinements Design

## Context

This design covers four launcher refinements on branch `refinement_2026_05_13`:

- Calculator live-result scrolling and trailing equals handling.
- Native file drag respecting Bucky multi-selection.
- Persisted Dictionary history for enter-opened words.
- Mode-switcher stone and active pill animation.

Bucky is a local-only macOS 26 Swift Package app. The launcher UI is SwiftUI Liquid Glass hosted by AppKit. Existing boundaries are:

- `LiquidGlassLauncherModel` owns mode routing, tool results, and selection scroll requests.
- `ModeSwitcherView` owns mode stones, active pills, and search text fields.
- `FileBrowserModel` owns file selection across directories.
- `NativeFileDragSourceView` bridges file rows into AppKit native dragging.
- Calculator history already persists through `CalculationHistoryStore`.

The changes stay within those boundaries. UI remains native SwiftUI/AppKit, and persisted data stays as JSON under Bucky's app support directory.

## Approved Approach

Use targeted fixes in existing models and policies:

- Normalize calculator input and explicitly scroll live result rows.
- Pass file drag payload selection through the existing file browser selection model.
- Add a dedicated dictionary history store.
- Preserve native text-editing shortcuts through key-routing policy.
- Change mode-switcher glass transition policy so stones and pills morph between stable slots.

This avoids a broader tool-history abstraction and avoids UI-only patches that would be harder to test.

## Calculator And Text Input

Calculator accepts trailing `=` as a completion marker. `ArithmeticEvaluator` will normalize one or more trailing equals signs after trimming whitespace before validation, evaluation, and history storage. Examples:

- `2+2=` evaluates as `2+2`.
- `2+2 =` evaluates as `2+2`.
- `2+2==` evaluates as `2+2`.

`=` inside the expression body remains invalid. For example, `2=+2` should not evaluate.

When calculator typing produces a valid live calculation, `LiquidGlassLauncherModel` will set `selectedIndex` to `0` and publish a selection scroll request. This keeps the live calculation row visible while typing, even if the user previously moved selection into calculation history.

Native copy, cut, paste, select-all, and related text editing shortcuts must reach input fields in text-entry contexts:

- Applications search.
- Calculator search.
- Dictionary search.
- File rename text field.

Bucky launcher shortcuts still win where they are explicitly defined, including `Cmd+1` through `Cmd+4`, `Cmd+R`, `Cmd+,`, `Cmd+P`, command brackets, and command arrow navigation.

## Files Drag

Native file drag will respect Bucky multi-selection.

Drag payload selection:

- If the row under the mouse is already in `selectedURLs`, drag all selected URLs.
- If the row under the mouse is not selected, drag only that row.
- Selected URLs from other directories remain included when the dragged row is part of the multi-selection.

`FileBrowserView` will pass a URL provider into `NativeFileDragSourceView` instead of a single fixed URL. The AppKit bridge will create one `NSDraggingItem` per URL using native file URL pasteboard writers. The pointer row keeps the visible drag image; additional selected files can use lightweight native dragging items.

The drag source operation remains copy for dragging out of Bucky. Existing in-app copy/move behavior is unchanged.

## Dictionary History

Dictionary gets a dedicated persisted history store under app support, separate from calculator history.

Data model:

```swift
struct DictionaryHistoryEntry: Codable, Hashable {
    let term: String
    let date: Date
}

struct DictionaryHistoryFile: Codable {
    var words: [DictionaryHistoryEntry]
}
```

Behavior:

- Only enter-opened dictionary words are stored.
- Opening a dictionary result adds the term to history.
- Opening a history row reopens Dictionary for that term and moves it to the top.
- History dedupes by normalized term.
- History is capped at 100 entries.
- Blank Dictionary mode shows history rows when history exists.
- Blank Dictionary mode remains quiet when history is empty.
- Each history row has a clear button to remove that row.

The row clear action removes only that word and refreshes the blank dictionary result list.

## Mode Switcher Animation

The mode switcher uses the sliding active pill model. Each mode has a compact
stone slot in the ordered row. When a mode becomes active, the active pill
expands from that mode's compact stone slot; when it deactivates, the pill
shrinks back to the same slot. The active pill therefore travels across the row
with the selected mode instead of expanding into one fixed header location.

Inactive stones remain visually fixed in their compact mode slots. The active
mode does not also render a separate inactive stone; its glass identity morphs
from that compact slot into the active pill and back. Switching modes should
therefore read as one malleable glass object per mode, not as separate stones
being pushed aside by an expanding pill.

Implementation notes:

- Every mode participates in matched glass geometry.
- The moving glass identity belongs to the stone/pill surface.
- The active pill's leading edge matches the selected mode's inactive stone
  frame, so expansion and shrinkage start and end at the same slot.
- Inactive stone slots are independent of the active mode; do not move trailing
  stones to make room for the active pill.
- Text input foregrounds stay outside the moving glass identity so native focus, typing, and legibility remain stable.
- The current pattern of foreground content above a separate glass surface remains in place.

The goal is a spatially legible sliding pill, not a rail where every active mode
expands into the same fixed pill location.

## Error Handling And Security

All changes are local-only and avoid network access.

File drag uses native file URL pasteboard writers and does not synthesize string paths for dragging. Dictionary and calculator history write JSON atomically under app support, matching existing persistence behavior. Malformed history files should fail gracefully by logging and falling back to empty history.

No new long-lived timers, retained AppKit delegates, or background tasks are required. The existing calculation debounce timer remains cancellable.

## Testing

Add or update focused tests:

- Calculator evaluates trailing `=` and rejects embedded `=`.
- Calculator history storage uses the normalized expression.
- Valid live calculator typing resets selection to the live row and publishes a scroll request.
- Key-routing policy passes native text editing shortcuts through for text input modes and file rename mode while preserving launcher commands.
- File drag selection policy returns all selected URLs when dragging a selected row and only the row URL when dragging an unselected row.
- File drag selection preserves selected URLs from other directories.
- Dictionary history persists, dedupes, caps entries, removes single rows, and shows on blank input.
- Opening dictionary results and history rows records/moves history entries.
- Mode switcher transition policy uses matched geometry for every mode while keeping text field foreground outside the glass identity.

Run `swift test` after implementation.
