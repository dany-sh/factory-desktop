# Current-state repository audit

Audit date: 2026-07-16. Evidence came from the live checkout, source inspection, Git history, package manifest, and `swift test`. “Verified” below means behavior is present in inspected code and covered by a passing relevant test or direct package validation; it does not mean production security certification.

## Executive finding

The repository is a coherent but different product: **Factory Desktop**, a local-first coding-project/task/worktree and AI-runner orchestrator. The requested litigation workspace is not partially hidden in the codebase; its domain models and pipelines are absent. Reusing current legal-sounding names such as `Artifact` or `WorkerEvidence` would create dangerous semantic confusion. The sustainable path is to preserve only infrastructure patterns behind new boundaries and introduce a distinct legal domain after ADR-0001 is resolved.

## Structure and responsibilities

| Area | Observed responsibility | Classification |
|---|---|---|
| `FactoryDesktop` executable | SwiftUI scenes, project/task/Kanban/worker UI, settings, inspectors, Markdown windows | Implemented and verified for current product |
| `FactoryDesktopCore` | Models, `AppStore`, SQLite repository/migrations, Git/worktree lifecycle, command runner, Ollama/Codex adapters | Implemented and verified for current product |
| `CSQLite` | System-library bridge | Implemented and verified |
| `FactoryDesktopCoreTests` | 181 tests in one 4,624-line XCTest file | Implemented and verified; organization is insufficient for a second domain |
| `Resources/Editor` | Bundled TinyMCE editor inside `WKWebView` | Implemented and verified by build; UI behavior insufficiently tested |
| Documentation | Root README describes coding orchestrator v0.1 | Implemented but stale relative to recent runner/worker functionality |
| `docs/`, ADRs, `AGENTS.md` | Absent before this audit | Missing |

SwiftPM defines one macOS 14 executable product, one core target, one test target, and a MarkdownUI dependency. There is no Xcode project, app sandbox entitlement file, persistence model package, or legal-domain module.

## Persistence and configuration

- `FactoryPaths` creates a compiled per-user `~/.factory` root containing `factory.db`, migration snapshots, runs, worktrees, and prompts. This is acceptable for the existing tool but violates the new configurable-workspace requirement if reused unchanged.
- SQLite is opened directly through `CSQLite`. `SQLiteDatabase.transaction` uses `BEGIN IMMEDIATE`, `COMMIT`, and best-effort `ROLLBACK`.
- `MigrationRunner` contains 11 append-only numbered SQL migrations, SHA-256 checksums, one pre-migration database copy, and a single migration transaction.
- `FactoryRepository` is a large concrete repository with CRUD for projects, tasks, runs, artifacts, task events, runner sessions/executions, notifications, worker events/context/evidence/queues/approvals.
- `Project` owns a path, default branch, command configuration, metadata, and timestamps. Registration uses `NSOpenPanel`, but paths are stored as strings; no security-scoped bookmarks or profile import/export exist.
- `AppStore` constructs concrete dependencies, migrates on launch, marks running executions detached, reloads all state, and publishes roughly fifty properties. It is a `@MainActor` 5,130-line composition root plus workflow coordinator.

Classification: database migration backup and transactional persistence are **implemented and verified** for current tables; case-scoped persistence, workspace profiles, portability, corruption recovery, and legal audit history are **missing**. The concrete repository and global store are **requires architectural decision** before legal-domain growth.

## File-system safety, monitoring, recovery, and undo

Implemented mechanisms:

- `CommandRunner` passes executable/argument arrays to `Process` through `/usr/bin/env`, blocks named destructive fragments, and allowlists a set of Git/build/test/open/Codex shapes.
- Git worktree operations check default-branch state, dirty state, missing paths, unmerged commits, and require manual approval for selected mutations. Cancellable worker processes are tracked by an actor and running jobs become detached after restart.
- Markdown saving uses modification date plus size as an optimistic version, refuses missing/read-only/externally changed files, writes atomically, and has discard/reload UI.
- Migration backup copies the database before pending migrations.

Limits:

- No general case-root boundary, canonical path containment, symlink traversal check, hard-link policy, stable file identity, content hash catalog, file-operation journal, multi-file atomic plan, compensating rollback, crash recovery, or undo manager exists.
- No file watcher/FSEvents/DispatchSource catalog monitoring exists. Refreshes are explicit Git/status operations; Markdown metadata refresh is document-local, not a watcher.
- Current lifecycle cleanup is Git-specific and must not be treated as legal-file safety.
- `CommandRunner` is not a generic security boundary: manual approval can admit non-allowlisted commands; path safety checks only establish absolute syntax/existence, not authorized-root containment.

Classification: current Git safeguards are **implemented and verified** for their narrow domain; legal source preservation and organization transactions are **missing**.

## Document behavior

- Markdown has a separate window, MarkdownUI display, editable mode, save/discard conflict flow, and a TinyMCE task editor implemented with `WKWebView`.
- The main window uses `NavigationSplitView`; detail contains an `HSplitView` and optional right inspector. When the inspector is absent, center content expands, which is a reusable interaction pattern.
- There is no Quick Look, PDFKit, image/media/Office/spreadsheet preview, page state, multi-preview stack, side-by-side document comparison, citations, or stale-preview service.

Classification: Markdown editing is **implemented and verified**; the web editor is **prototype or experimental** for a native legal document workspace; requested document preview is **missing**.

## Current models and legal-domain status

Current durable records include `Project`, `FactoryTask`, `RunRecord`, `Artifact`, `TaskEvent`, Codex/runner links, `RunnerWorkspace`, `RunnerSession`, `RunnerExecution`, `AgentTurn`, `WorkerReport`, `TaskProposal`, `RunnerNotification`, `LifecycleSnapshot`, worker events/context/prompt snapshots/worker “evidence,” queues, and approvals.

None is the requested legal `Case`, `CaseFile`, `EvidenceItem`, `Exhibit`, `Binder`, `Witness`, `TimelineEvent`, `CalendarEvent`, `Deadline`, or legal `Task`. In particular, `WorkerEvidence` is execution evidence about an AI coding worker and must not be migrated or renamed into evidentiary material.

Classification: all requested legal models are **missing**.

## UI patterns

Reusable patterns are native WindowGroups, menu commands and shortcuts, split navigation, collapsible/resizable right inspector, forms and sheets, alerts/confirmation dialogs, drag/drop Kanban, empty-state views, AppKit directory picker, and separate Markdown windows. Limitations are feature-specific view concentration (`TaskDetailView`, inspectors), global selection in `AppStore`, no navigation history/restoration model, no accessibility test suite, and a bundled web editor that conflicts with the “native first” target if used for the primary workspace.

Classification: native shell patterns are **implemented but insufficiently tested**; legal information architecture is **missing**.

## Integrations and external boundaries

Implemented: Git CLI, Codex CLI, local Ollama HTTP, Terminal/VS Code/open commands, in-app source update/relaunch, MarkdownUI, SQLite. Process cancellation and adapter protocols exist for runners. No EventKit, Contacts, Quick Look, PDFKit, Vision/OCR, Spotlight/Core Spotlight, mail, cloud storage, or legal rules provider exists.

All current coding integrations are out of scope for the legal core. Any retained runner/AI adapter must sit behind a new consent-and-provenance boundary.

## Test guarantees

`swift test` built the executable and executed 181 XCTest cases with zero failures on arm64e macOS 14. Covered behavior includes Markdown conflict handling, model round trips, migrations, repository CRUD, task lifecycle and audit events, command blocking, Git/worktree gates and repair, local commands, runner orchestration, cancellation/detachment, AI proposal review, and worker timeline/context persistence.

Not covered: legal models/workflows, UI automation, VoiceOver, sandbox bookmarks, general file boundaries, symlinks/hard links, file transaction crash recovery, import/export, PDF/binder generation, pagination, calendar/deadlines, search index, file watchers, large-case scale, corruption/restore, confidentiality, or AI grounding for legal facts.

## Undocumented, documented-only, obsolete, and placement findings

- Recent runner/worker chat, append-only worker events, context snapshots, message queues, approvals, lifecycle snapshots, and self-update behavior are substantially more capable than the root README documents: **implemented but undocumented**.
- README terminology still describes older task statuses and a “v0.1” flow: **potentially obsolete documentation**.
- Backlog migration preserves the old `backlog_ideas` table while new tasks carry idea metadata: **potentially obsolete**, but removal requires a migration decision.
- Parallel Codex-specific links and generic runner links overlap: **requires architectural decision**; do not copy both into the legal product.
- Several very large files (`AppStore`, `FactoryRepository`, `TaskDetailView`, the single test file) concentrate unrelated responsibilities: **implemented but incorrectly placed for future expansion**.
- The current product README claims no autonomous editing, while worker execution can run workspace-write Codex tasks with review-first gates: **documentation insufficient**, not proof of unsafe behavior.

## Constraints future work must respect

1. Do not mutate or reinterpret existing coding tables as legal tables.
2. Do not put legal case state under a fixed `~/.factory` root.
3. Keep migration numbering/ownership isolated per store or explicitly branch the schema lineage.
4. Preserve review-first and cancellable-work patterns, but replace command-fragment safety with capability-specific typed operations.
5. Keep UI state on the main actor; move cataloging, hashing, watching, indexing, PDF work, transactions, and exports to isolated cancellable services/actors.
6. Avoid a second domain inside the current monolithic `AppStore` and repository.
7. Existing dirty user changes in `SidebarView.swift` and `AppStore.swift` were not altered by this documentation task.

## AGENTS.md evaluation

No repository `AGENTS.md` existed. Therefore no instructions covered product vision, legal file safety, feature IDs, testing, workspace configuration, generated files, or AI boundaries. This documentation index now gives future tasks those rules. A root `AGENTS.md` should be created only after ADR-0001 fixes the product/target layout, so instructions can name real module boundaries instead of speculative paths.
