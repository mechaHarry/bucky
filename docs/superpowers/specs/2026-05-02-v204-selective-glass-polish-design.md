# v2.0.4 Selective Glass Polish Design

## Goal

Reintroduce a small set of visual improvements from the post-v2.0.0 work without disturbing the restored list/filter performance baseline. The changes should improve alignment, button affordance, and depth contrast while keeping the implementation native SwiftUI/Liquid Glass and narrowly scoped to launcher view presentation.

## Scope

This change covers three launcher UI updates:

1. Align the results list top inset against the results panel, so applications and tools mode use the same top gap.
2. Convert row secondary actions to glass buttons for hide, calculation copy, calculation-history copy, and dictionary launch.
3. Add thin adaptive rim highlights around launcher surfaces to improve depth/layer contrast.

The change does not modify filtering, query preservation, indexing, icon caching, hotkeys, settings, package/release scripts, or the performance baseline metric.

## Design

### Results Panel Alignment

The results area will become an explicit panel surface. Its content inset will live at the panel/list boundary rather than inside a mode-specific row list. Both application rows and tool rows will use the same scroll container and top content margin. Empty-state text remains centered in the panel.

The intended visible result is that switching between app mode and tools mode no longer changes the top gap between the header and the first row.

### Focus/Hover-Only Action Buttons

Row secondary actions will be modeled as independent glass buttons, not plain icons:

- application rows: hide from results
- calculation rows: copy result
- calculation history rows: copy result
- dictionary rows: launch/open dictionary entry

The buttons are visible and hit-testable only when the row is selected or hovered. This preserves a clean scan path while keeping actions discoverable during pointer or keyboard focus. Pressing the row body still activates the primary row action. Pressing the secondary action performs only that secondary action.

This design deliberately avoids the delayed activation animation from the heavier v2.0.2 interaction state work. The visual button treatment comes back, but the timing path stays simple.

### Thin Rim Highlights

Rim highlights will use semantic adaptive colors:

- separator color for neutral rims,
- selected content background color for selected row rims,
- control accent color only for active or selected affordance emphasis.

Rims should be thin and local:

- launcher window outer surface,
- search/header surface,
- results panel surface,
- row panel surface,
- selected row overlay,
- row action glass buttons.

The implementation should prefer `strokeBorder` overlays over extra opaque fills. It should not introduce custom dark scrims, large shadows, or non-semantic fixed colors.

## Architecture

Most work belongs in `Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift`.

If action visibility needs test coverage, introduce a small pure helper in the test target or a tiny file-local value type that can be unit-tested without rendering SwiftUI. Avoid restoring the full v2.0.2 `LauncherRowInteractionState` abstraction unless implementation pressure proves it necessary.

## Performance Guard

The existing `make perf` gate must run after implementation. The expected outcome is `comfort`; a `watch` result requires reviewing whether the UI change affected model/filter work unexpectedly, and a `regression` result blocks completion.

The UI changes are not expected to affect `LiquidGlassLauncherModel.filter(_:normalizedQuery:)`, so any performance-gate movement should come from measurement noise rather than intentional model work.

## Testing

Required verification:

```bash
swift test
make perf
```

Add or update tests only where behavior is represented by pure logic. Visual appearance itself is verified by code review and local app launch rather than brittle snapshot tests.

## Operator Notes

The work starts from branch `v2.0.4`, created from signed-merged `master` after the performance baseline landed.

The baseline update workflow is not part of this change. If `make perf` reports a regression, fix the UI/model issue rather than recapturing the baseline.
