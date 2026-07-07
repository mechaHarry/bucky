# Apps Dictionary Prefix Design

## Summary

Migrate Dictionary from a standalone launcher stone into the Apps stone. A query whose first non-whitespace character is `?` activates Dictionary behavior inside Apps, matching the existing `=` calculator trigger. Calculator, Dictionary, and normal application search will share one Apps result-list and row interaction foundation while retaining their specialized data sources and behavior.

The migration must not alter the architecture or performance characteristics of application indexing, filtering, caching, scoring, or icon preloading.

## User Experience

- Ordinary text continues to filter applications.
- `= expression` activates calculator results and history.
- `? word` performs a live Dictionary lookup.
- A bare `?` displays persisted Dictionary history.
- Leading whitespace before either prefix is allowed.
- Dictionary keeps its magenta tint, formatted definition preview, per-definition Wikimedia image sections, Return-to-open behavior, history persistence and removal, and hold-Space preview with arrow traversal.
- Calculator keeps its calculator tint, immediate evaluation, copy behavior, history, and result glow.
- Dictionary no longer appears as a stone. Command+3 becomes inert; Files and Agenda remain Command+4 and Command+5.
- Dictionary shortcuts and explanations move into the Apps Help page.

## Query Routing

Introduce a single Apps query classifier with three mutually exclusive routes:

1. `applications(query)` for ordinary input.
2. `calculator(expression)` when `=` is the first non-whitespace character.
3. `dictionary(term)` when `?` is the first non-whitespace character.

The classifier returns an empty expression or term for a bare prefix so the corresponding history can be shown. Prefixes are only special in the first non-whitespace position. A `?` or `=` elsewhere remains part of an ordinary application query.

Changing routes cancels stale Dictionary lookup or preview work and clears route-specific transient feedback. It does not invalidate or rebuild the application filter cache.

## Data Boundaries

The three routes keep specialized data producers:

- Applications continue to publish stable application row IDs backed by `ApplicationRowStore`, `ApplicationFilterCache`, and existing index snapshots.
- Calculator continues to produce calculation and calculation-history values from `ArithmeticEvaluator` and `CalculationHistoryStore`.
- Dictionary continues to produce definition and history values from `DictionaryLookup` and `DictionaryHistoryStore`.

The migration does not convert application rows into `ToolItem` values. Data convergence stops at the presentation boundary so normal Apps filtering and activation stay on their existing fast path.

## Shared Apps Presentation

Create one shared Apps result-list and row shell used by all three routes. The shell owns:

- Stable row sizing and spacing.
- Selection glass, hover state, and focus treatment.
- Scroll-to-selection behavior.
- Leading icon geometry.
- Primary and secondary text geometry.
- Trailing action placement.
- Loading, empty, selected, and disabled states.
- Pointer activation, Return activation, and arrow navigation.

Small route adapters provide stable identity, icon, text content, tint, actions, and activation callbacks. The shared shell remains generic and does not erase the specialized stores or route behavior.

All calculator and Dictionary rows adopt the exact Apps row dimensions, spacing, selection glass, hover behavior, and action placement. Their content, tint, and commands remain specialized:

- Application rows launch or hide applications.
- Calculator rows display expression/result content and copy results.
- Dictionary rows display term/definition content, open terms, remove history, and participate in hold-Space preview.

The active Apps pill follows the route tint without changing launcher mode.

## Dictionary Lookup and Loading

Dictionary lookup keeps the existing short debounce, detached lookup execution, cancellation, and generation-token stale-result rejection. Lookup work must not block typing, application indexing, or SwiftUI updates.

When a new Dictionary term is pending, the shared Apps list shows native skeleton rows. Results from the previous term are not presented as results for the new term. A completed lookup replaces the skeleton with definitions or a native empty state.

Leaving the Dictionary route cancels pending lookup and preview work. Returning to ordinary Apps text immediately restores cached application results. Calculator remains synchronous and updates without the Dictionary debounce.

## Preview and Images

Hold-Space routing applies when the Apps query route is Dictionary. Preview behavior remains otherwise unchanged:

- Releasing Space closes the preview with its existing animation.
- Arrow navigation while Space is held refreshes the preview for the newly selected history or definition row.
- Definition variants retain formatted sections and their associated image carousels.
- Wikimedia requests retain their existing skeleton UI, cancellation, cache, timeout, and privacy behavior.

No query, definition, history item, local path, or remote response content is added to logs. No credentials or API keys are introduced.

## Mode and Help Cleanup

Remove the Dictionary launcher mode, stone, Command+3 label, standalone stored query, mode-switch branches, and separate Help page. Preserve Dictionary's palette as an Apps feature tint rather than a `LauncherMode` tint case.

The Apps Help page documents:

- `= expression` for calculator.
- `? word` for Dictionary.
- Bare-prefix history behavior.
- Return activation.
- Hold Space for Dictionary preview.
- Dictionary history removal.

Historical implementation plans remain historical. The active architecture note under `.agents/docs` must be updated to describe both prefix tools accurately.

## Failure Behavior

- A Dictionary lookup that returns no definition produces a stable empty state and leaves input focused.
- Cancelled or stale lookup results never replace the current route's rows.
- Malformed persisted history continues to fail gracefully through the existing store fallback.
- Wikimedia image failure leaves definition text usable and replaces loading skeletons with the existing nonblocking fallback.
- Switching routes never closes Bucky or discards normal Apps cache state.

## Testing

Strict automated coverage must include:

- Query classification for ordinary text, leading whitespace, bare prefixes, and prefixes outside the first non-whitespace position.
- Bare `?` Dictionary history and `? word` live lookup.
- Dictionary debounce, cancellation, generation checks, loading skeleton state, empty state, and stale-result rejection.
- Switching among ordinary Apps, calculator, and Dictionary without application-cache invalidation.
- Shared row dimensions, spacing, hover, selection glass, action placement, scrolling, pointer activation, Return, and arrow navigation.
- Calculator evaluation, history, copy, and result glow through the shared Apps surface.
- Dictionary history persistence/removal, Return-to-open, hold-Space preview, arrow-updated preview, close animation, and feature tint.
- Removal of the Dictionary stone, Command+3 routing, standalone query state, and separate Help page.
- Existing launcher filter performance coverage to prove normal Apps filtering remains within its regression band.
- Full Swift test suite, debug build, release bundle, and a live keyboard interaction pass.

## Out of Scope

- Changing the application indexing, filtering, scoring, cache, or icon-preload architecture.
- Replacing Dictionary Services, `NSSpellChecker`, or Wikimedia Commons.
- Adding more Apps prefixes or a public plugin system.
- Redesigning the definition preview beyond adapting its route and shared row entry point.

## Success Criteria

The migration is complete when Calculator and Dictionary operate through one Apps list and row interaction foundation; normal Apps performance and behavior remain unchanged; each tool retains its unique tint, content, actions, history, and preview behavior; Dictionary has no standalone launcher surface; and all strict tests and live verification pass.
