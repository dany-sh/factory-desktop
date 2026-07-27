# Authoritative product and architecture documentation

This directory is the source of truth for evolving this repository into a local-first native macOS workspace for litigation and other document-intensive legal matters. The current executable is a coding-orchestration prototype; it is not evidence that a legal feature is implemented.

## Authority and ownership

| Concern | Authoritative document |
|---|---|
| Vision, principles, product boundaries, release definitions | [Product vision](product/PRODUCT_VISION.md) |
| Feature IDs, priority, status, acceptance criteria, dependencies | [Feature inventory](product/FEATURE_INVENTORY.md) |
| Complete user/system flows and recovery | [User workflows](product/USER_WORKFLOWS.md) |
| Navigation, selection, inspectors, preview behavior | [Information architecture](product/INFORMATION_ARCHITECTURE.md) |
| Verified repository behavior and gaps | [Current-state audit](architecture/CURRENT_STATE_AUDIT.md) |
| Target module boundaries and dependency rules | [Architecture baseline](architecture/ARCHITECTURE_BASELINE.md) |
| Conceptual entities and relationships | [Data model](architecture/DATA_MODEL.md) |
| Original-file, transaction, rollback, and recovery rules | [File safety model](architecture/FILE_SAFETY_MODEL.md) |
| Binder inputs, stages, validation, revisions | [Binder pipeline](architecture/BINDER_PIPELINE.md) |
| Suggested versus confirmed date semantics | [Deadline model](architecture/DEADLINE_MODEL.md) |
| Optional AI/provider boundary | [AI boundary](architecture/AI_BOUNDARY.md) |
| Phase gates and release sequence | [Development roadmap](roadmap/DEVELOPMENT_ROADMAP.md) |
| One-focused-task implementation queue | [Implementation tasks](roadmap/IMPLEMENTATION_TASKS.md) |
| Product and engineering risks | [Risk register](roadmap/RISK_REGISTER.md) |
| Required test layers and fixtures | [Test strategy](testing/TEST_STRATEGY.md) |
| Chosen and pending architectural decisions | [Decision records](decisions/) |

Documents link to these owners instead of repeating their content. If two documents conflict, use the owner above and open a documentation correction before implementation.

## How future Codex tasks use this set

Every implementation task must:

1. name one or more feature IDs from `FEATURE_INVENTORY.md`;
2. quote that feature's acceptance criteria and explicit non-goals;
3. name the roadmap task and phase;
4. identify affected architecture boundaries and decision records;
5. add the tests required by `TEST_STRATEGY.md` in the same task;
6. update feature status and any changed decision, without changing unrelated feature scope;
7. state whether original files can be touched; if yes, follow `FILE_SAFETY_MODEL.md` and include preview, approval, transaction, rollback, recovery, and audit tests.

Feature IDs are permanent. A retired feature keeps its ID and becomes `Potentially obsolete`; IDs are never reassigned. New features receive the next number in their domain.

## Current baseline warning

The source tree currently implements Factory Desktop, a local coding-project/task/worktree orchestrator. Legal-case capabilities in the inventory are proposals unless their status explicitly says otherwise. Reusable mechanisms must be extracted behind legal-domain protocols; current `Project`, `FactoryTask`, runner, Git, and artifact models must not be relabeled as legal entities.

## Documentation maintenance rule

Product behavior changes require updates in this order: feature inventory, applicable decision/data/safety document, roadmap task status, then user-facing documentation. Generated exports and local case paths never belong in the repository.
