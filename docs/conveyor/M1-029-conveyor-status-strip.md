# M1-029 — Conveyor status strip

## Outcome

Add a compact, read-only status strip above the Kanban board that answers two separate questions without opening a menu:

1. Is the Conveyor running, paused, ready, idle, or unavailable?
2. Does the selected project need attention before work can continue?

The strip is independent from board filters, sidebar visibility, and the feature Inspector.

## Current problem

The sidebar currently reduces controller state to `Paused`, `Running`, or `Idle`. That projection cannot explain important combinations such as:

- paused with no Ready work;
- paused while queue reconciliation is the next action;
- running with “pause after current” requested;
- idle because no feature is dependency-ready;
- controller state that is unavailable or requires a human decision.

The Filter menu controls only what the board displays. The Inspector controls only selected-feature details. Neither is an appropriate home for project execution status.

## Source of truth

Use the Development Conveyor’s read-only:

```text
scripts/conveyor status --project <project-id>
```

Factory Desktop must decode a narrow, typed projection from that command. It must not infer lifecycle truth from card counts alone.

Required controller fields:

- `project_id`
- `operator_paused`
- `next_action`
- `unpaused_proposed_next_action`
- `current_state`
- `derived_state`
- `cycle_phase`
- `cycle_stop_reason`
- `human_resolution_required`
- `human_gate`
- `queue_status.configured_milestone`
- `queue_status.ready_features`
- `queue_status.reconciliation_classification`
- `current_repository_state.clean`
- `current_repository_state.writer_lease`
- `lock_status`
- `selected_feature`

Unknown enum values and absent optional fields must decode without failing the entire board refresh.

## Presentation model

Keep execution and attention orthogonal. Do not flatten them into one status enum.

### Execution state

| State | Label | Supporting text |
|---|---|---|
| Active transaction or cycle | `Running` | Active feature and phase when available |
| Active transaction with `operator_paused == true` | `Running` | `Pausing after current` |
| No active transaction and `operator_paused == true` | `Paused` | Explain what would happen if unpaused |
| No active transaction with Ready work | `Ready` | Next eligible feature when available |
| No active transaction and no Ready work | `Idle` | `No Ready work in <milestone>` |
| Command or decode failure | `Unavailable` | Short failure reason and Refresh affordance |

Running takes precedence over paused so “pause after current” is not misreported as already stopped.

### Attention state

Show at most one primary attention message, using this order:

1. human resolution required;
2. queue reconciliation required;
3. conflicting or ambiguous lock;
4. repository has local changes;
5. none.

Lower-priority conditions remain available in accessibility help or a disclosure, but the strip must not become a diagnostics dashboard.

## UI placement and behavior

- Place the strip directly below the board feature-count/milestone summary and above the priority drop targets.
- Show a compact status symbol, primary label, and one supporting sentence.
- Show an attention badge only when attention is required.
- Keep Filter as its own toolbar menu.
- Keep Inspector open/close as its own toolbar button and `⌘⌥I` command.
- Selecting or double-clicking cards must not alter project execution status.
- Refresh on initial load, project switch, explicit Refresh, app activation, and after a successful Conveyor mutation.
- Status refresh is read-only and must not unpause, reconcile, acquire a writer lock, start a feature, or mutate a queue.

At narrow widths the strip may wrap onto two lines. It must not increase the window’s minimum width or introduce a second horizontal scrollbar.

## Current-state fixture

The following controller combination must render as a composite state rather than a misleading single label:

```text
operator_paused: true
next_action: project_paused
current_state: queue_reconciliation
unpaused_proposed_next_action: queue_reconciliation
queue_status.ready_features: []
queue_status.configured_milestone: M0
current_repository_state.clean: false
```

Expected visible result:

```text
Paused · No Ready work in M0
Queue reconciliation required
```

It must not display `Running`. Repository local changes may appear as secondary help because queue reconciliation has higher attention priority.

## Acceptance criteria

1. A pure presentation mapper covers Running, Running/pausing, Paused, Ready, Idle/no-ready-work, human gate, reconciliation, dirty repository, lock ambiguity, unavailable, and unknown future values.
2. The process client invokes only the validated read-only `status --project <id>` argument array with `shell=false`.
3. The current-state fixture renders `Paused`, `No Ready work in M0`, and `Queue reconciliation required`.
4. A running project with pause requested renders `Running` and `Pausing after current`.
5. Filter and Inspector controls remain separate and retain their existing behavior and shortcuts.
6. The strip has a useful combined accessibility label and does not rely on color alone.
7. At approximately 900, 1200, and full-display widths, every sidebar/Inspector combination remains resizable; the strip wraps without growing the window.
8. Refresh or decode failure preserves the last valid board projection, marks status `Unavailable`, and offers a non-mutating retry.
9. Focused tests prove that status refresh never calls pause, resume, ready, backlog, priority, run, or reconciliation mutations.
10. `swift build`, `swift test --filter ConveyorBoardTests`, and `git diff --check` pass.

## Non-goals

- Starting, pausing, resuming, or reconciling the Conveyor automatically.
- Replacing the project sidebar summary.
- Moving filters into the status strip.
- Moving project status into the feature Inspector.
- Exposing raw controller JSON or every diagnostic field.
- Adding notifications, history charts, or cross-project portfolio monitoring.

## Likely change surface

- `Sources/FactoryDesktopCore/ConveyorProcessClient.swift`
- `Sources/FactoryDesktopCore/ConveyorModels.swift`
- `Sources/FactoryDesktopCore/ConveyorBoardStore.swift`
- `Sources/FactoryDesktop/ConveyorBoardView.swift`
- `Tests/FactoryDesktopCoreTests/ConveyorBoardTests.swift`

If the controller’s existing status JSON cannot provide a stable narrow projection, add a backward-compatible read-only projection there first; do not duplicate controller lifecycle rules in Swift.
