# Agenda Removal Design

## Goal

Remove Agenda completely from Bucky while preserving every external note file that Agenda previously opened or edited.

## Product Behavior

- Bucky exposes only Apps and Files as launcher modes.
- Apps remains Command+1 and Files remains Command+4. The remaining modes are not renumbered.
- Command+5 is unassigned and performs no action.
- Command+Left and Command+Right cycle directly between Apps and Files.
- Agenda has no stone, view, editor, Help page, tint, placeholder, command, keyboard reservation, model state, or persistence API.

## Source Removal

Delete the Agenda-owned implementation files:

- `Sources/Bucky/Agenda/AgendaModels.swift`
- `Sources/Bucky/Agenda/AgendaStore.swift`
- `Sources/Bucky/UI/SwiftUI/AgendaView.swift`
- `Tests/BuckyTests/AgendaStoreTests.swift`

Remove Agenda cases and branches from shared launcher models, views, commands, keyboard routing, mode switching, settings Help, and architecture documentation. SwiftPM discovers sources automatically, so `Package.swift` does not require an Agenda-specific edit.

## Data Cleanup

At application launch, an idempotent legacy cleanup removes only:

`~/Library/Application Support/Bucky/agenda.json`

The cleanup receives the exact store URL as an injectable input for testing. It must not decode the store, follow paths recorded inside it, enumerate referenced files, traverse directories, or remove any sibling app-support file.

External note files are user-owned data. Bucky must never delete, move, truncate, or modify them as part of Agenda removal, even when their paths appear inside the deleted reference store.

A missing legacy store is a successful no-op. Cleanup failure must not block application startup or affect unrelated data.

## Architecture

`LauncherMode` retains explicit raw values for Apps (`1`) and Files (`4`) and orders only those two modes. Agenda-specific `LauncherCommand` cases and key-routing helpers are removed rather than left dormant.

A small legacy-data cleanup unit owns removal of the exact Agenda store path. `AppDelegate` invokes it during startup. The cleanup remains independent of launcher UI and has no knowledge of Agenda note references.

## Testing

Focused tests must prove:

- `LauncherMode.ordered` is exactly Apps and Files.
- Command+1 and Command+4 still resolve; Command+2, Command+3, and Command+5 do not.
- Mode cycling wraps Apps to Files and Files to Apps.
- Agenda commands, key reservations, UI branches, Help entries, and source files are absent.
- Legacy cleanup removes the exact `agenda.json` file.
- A note file whose path appears in `agenda.json` remains byte-for-byte unchanged.
- Unrelated files beside `agenda.json` remain unchanged.
- Missing-store and removal-error paths do not prevent startup.

Run the full Swift test suite, performance guard, debug build, and package build after removal.

## Commit Strategy

Use granular signed commits:

1. Remove Agenda mode routing and keyboard commands.
2. Remove Agenda model, UI, store, and owned tests.
3. Add exact-path legacy store cleanup and safety tests.
4. Update Help and architecture documentation.

Each commit must compile or be paired with the minimum dependent deletion needed to preserve a buildable state.
