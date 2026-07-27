# M1-030 — Sidebar status consistency

## Outcome

Make Conveyor lifecycle wording consistent between the status strip, the project
rows in the sidebar, and the sidebar's Current Project summary.

The sidebar must reuse the typed status presentation introduced by M1-029. It
must not infer execution state from queue-card counts or create a second
lifecycle mapper.

## Problem

The status strip now projects the controller's typed per-project status, while
the sidebar still derives labels from queue state:

- a project with no active feature can be labeled `Idle` even when the
  controller reports `feature_ready`;
- blocked queue-card counts can be mistaken for the project's execution state;
- a pause request can be presented as `Paused` before the controller reaches a
  paused state.

This produces conflicting status labels in the same window. In the current
local fixture, Case Manager is correctly shown as `Ready` in the status strip
with `P0-003` as the next eligible feature, but the Current Project sidebar
summary says `Idle`.

## Source of truth

`ConveyorStatusPresentation`, produced by `ConveyorStatusPresenter`, is the
single source of truth for lifecycle wording:

- `Running`
- `Ready`
- `Waiting`
- `Paused`
- `Complete`
- `Unavailable`

Queue-card counts remain the source of truth only for compact work-count
information such as Ready and Blocked counts. They must not determine the
project lifecycle label.

## Scope

### Project rows

Each visible project row uses its latest typed status presentation for the
secondary lifecycle label.

- A status that has not loaded yet may display `Loading`.
- A status refresh failure displays `Unavailable`; it must not fall back to a
  queue-derived lifecycle label.
- The row remains compact: project title plus one secondary line.
- Ready and Blocked counts may remain available as separate compact metadata,
  but they do not replace or modify the lifecycle label.

### Current Project summary

The Current Project section uses the same presentation as the selected
project's status strip.

- `feature_ready` displays `Ready`, even when there is no active feature.
- `feature_cycle_running` displays `Running`.
- A pause request does not display `Paused` until the controller reports a
  paused state.
- Unknown or unavailable controller values degrade safely to `Unavailable`.

### Status refresh

The store maintains the latest typed status for every registered project shown
in the sidebar.

- Initial load performs read-only status refreshes for the registered projects.
- Explicit refresh and app activation refresh the visible project statuses.
- Project selection ensures the selected project's status is refreshed.
- Refresh uses only the existing read-only Conveyor status command.
- A failed refresh preserves the last valid presentation where available and
  marks the status unavailable, matching the M1-029 failure model.
- Refreshes must not invoke pause, resume, start, reconciliation, integration,
  or any other mutating Conveyor command.

## Acceptance criteria

1. Project-row lifecycle labels and the Current Project lifecycle label are
   produced from `ConveyorStatusPresentation`.
2. The status strip, selected project row, and Current Project section agree on
   the selected project's lifecycle label.
3. A `feature_ready` project with no active feature displays `Ready`, not
   `Idle`.
4. A genuinely paused project displays `Paused`.
5. A running project with a pause request remains `Running` until the
   controller reports a paused state.
6. Unknown, not-yet-loaded, and failed status results have explicit safe
   presentations and never fall back to queue-derived execution state.
7. Ready and Blocked queue counts remain accurate and independent from the
   lifecycle presentation.
8. Loading all sidebar statuses is read-only and cannot mutate a registered
   application repository or Conveyor controller state.
9. The sidebar remains a compact native macOS list; this feature does not add
   attention details, diagnostics, controls, or raw status data to project
   rows.
10. The M1-029 status strip, Filter section, Inspector, and board-card behavior
    remain unchanged.
11. Focused presenter/store/view tests cover Ready, Paused, running with a pause
    request, unavailable status, and multiple project rows.
12. `swift build`, `swift test --filter ConveyorBoardTests`, and
    `git diff --check` pass.

## Expected change surface

- `Sources/FactoryDesktop/ConveyorBoardView.swift`
- `Sources/FactoryDesktopCore/ConveyorBoardStore.swift`
- `Tests/FactoryDesktopTests/ConveyorBoardTests.swift`

Changes outside this surface require a scope review before implementation.

## Non-goals

- Adding sidebar attention badges or full next-action detail
- Changing the status-strip layout or wording
- Adding pause, resume, start, or reconciliation controls
- Displaying raw JSON or subprocess output
- Portfolio-wide monitoring, history, notifications, or background polling
- Changing feature-card classification or queue filtering
- Pushing, releasing, deploying, or merging into a remote default branch

## Validation

Run:

```sh
swift build
swift test --filter ConveyorBoardTests
git diff --check
```

Perform a live macOS check with at least one Ready project and one Paused
project. Confirm that each sidebar label agrees with its status strip and that
the Current Project summary agrees with the selected row.
