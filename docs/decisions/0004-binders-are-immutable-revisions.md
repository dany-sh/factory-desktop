# ADR-0004: Binders and exhibits use immutable finalized revisions

- Status: Accepted as architecture baseline
- Date: 2026-07-16
- Feature IDs: EXH-007, BIND-001, BIND-009, BIND-010

## Decision

Exhibit and binder stable identities own revision histories. A finalized revision is immutable; replacing a source, changing pages, renumbering, reopening, or regenerating changed inputs creates a successor revision. Outputs and manifests bind exact revisions and input versions.

## Consequences

Prior binders remain reproducible/traceable, stale dependents are visible, and “latest” never silently rewrites court-facing output. Storage/retention grows and needs explicit policy, but generated material remains reliable.
