# ADR-0002: Stable identity and immutable original boundary

- Status: Accepted as architecture baseline
- Date: 2026-07-16
- Feature IDs: FILE-002, EVID-007, EXH-001, BIND-001, ORG-003

## Decision

Opaque IDs identify catalog, evidence, exhibit and binder records. Path, filename, case number, exhibit number and page label are versioned attributes. Original bytes are read-only to ordinary services. Derivatives have explicit lineage. Only an approved journaled file transaction may change an original's path, and it must preserve/verify bytes.

## Consequences

Renumbering and renaming do not break relationships. Replacement creates FileVersion/ExhibitRevision lineage rather than overwriting. Binder PDFs cannot become evidence implicitly. Physical organization is more deliberate but recoverable and auditable.
