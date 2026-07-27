# ADR-0001: Isolate the legal product domain

- Status: Proposed; blocking Phase 0 implementation
- Date: 2026-07-16
- Feature IDs: APP-001, CASE-001, TEST-001

## Context

The existing package is a coherent coding-project/worktree/AI-runner product. The requested application is a litigation case workspace. Names such as Project, Task, Artifact and WorkerEvidence are semantically incompatible with legal Case, legal Task, generated export, and EvidenceItem.

## Decision

Default to a new legal executable/domain/persistence boundary in this package during transition. Do not rename or migrate current coding records into legal records. Retain current source behavior until a separate approved task decides whether to keep, split, or retire Factory Desktop.

## Consequences

Reusable infrastructure is extracted only behind protocols with tests. Legal schemas have independent ownership/versioning. There is temporary package/product complexity, but no ambiguous data migration or giant mixed AppStore. A product naming/bundle-ID/distribution choice remains open.

## Alternatives rejected

- Relabel current models: dangerously false semantics and migration lineage.
- Add all legal features to existing AppStore/repository: preserves build simplicity but compounds coupling and fixed-path assumptions.
- Immediate destructive rewrite: violates staged safety and this task's boundaries.
