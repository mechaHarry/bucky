# Scroll rebound performance audit

Status: unresolved. No production scrolling behavior changed during this audit.

The reported symptom is smooth trackpad scrolling followed by a visibly slower rubber-band rebound after releasing an overscroll at the list edge. The gap-input fix and the stateless glass backdrop remain in place.

## Controlled comparison

An isolated native application used synthetic app rows and the production launcher controller alongside a plain SwiftUI `ScrollView` / `LazyVStack`. The plain list had no glass, selection animation, scroll-position binding, result reconstruction, or background indexing. Both windows were tested on the same display, whose reported maximum refresh rate was 100 Hz.

The fixture sent precise, phased scroll-wheel events directly to each list's native scroll view: begin, repeated changes, and end. It passively recorded clip-view bounds changes and verified that each list overscrolled and returned to its initial offset. These are synthetic in-process events, not physical trackpad input. Bounds notifications measure offset updates, not the screen's presentation frame rate.

- During the gesture, offset changes were approximately 10 ms apart.
- Both the plain list and Bucky began their rebound with approximately 10 ms updates, then shifted to approximately 20 ms updates. Some updates near the end were 40–60 ms apart.
- Requesting a 100 Hz window display link produced callbacks at the requested cadence but did not improve the rebound's offset-update cadence in either list.
- The sequence also occurred without Instruments attached. Profiling added occasional longer intervals; those should not be attributed to the product.

The plain comparison shows that Bucky's glass, row decorations, and model work are not required to reproduce this offset-update pattern. It does not establish the exact physical-trackpad presentation rate, nor prove that Bucky adds no rendering cost. Tiny movements near the end can also produce fewer bounds notifications because offsets are rounded.

A controlled Animation Hitches recording was verified to cover all four cases. Application update records were matched to frame lifetime records by swap ID, excluding unrelated process updates. The process owned multiple fixture windows, and the exported records did not provide a clean per-list presentation-rate measurement. Frame pipeline durations and whole-display compositor swaps are not substitutes for that measurement; the audit does not claim an exact 30 or 60 FPS rebound.

## Implementation review and decision

The shared results list delegates elastic scrolling to the framework. There is no Bucky rebound timer, release animation, or 30/60 Hz limit. Its explicit animations respond to result reconstruction and keyboard selection, rather than trackpad release.

Keep the ineffective continuous display link out of production: it adds callbacks and energy use without improving the measured behavior. SwiftUI's public bounce policy controls when bouncing is enabled; it does not expose a rebound frame-rate setting. A change to remove elastic bounce would be a separate user-visible behavior decision and needs validation at both list edges.

## Physical verification

On a display with a fixed high refresh rate, compare Bucky with a plain SwiftUI list using the same physical gesture. Repeat top and bottom overscroll, small and large releases, and scrolling over row gaps. Record actual application presentation during the rebound, distinguishing application updates from whole-display compositor swaps. Do not label bounds notifications or display-link callbacks as presentation FPS.
