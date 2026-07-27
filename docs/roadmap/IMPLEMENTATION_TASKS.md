# Sequential implementation tasks

Each item is sized for one focused Codex task. The first ten are the required exact start order. A task may be split smaller but may not be merged with a later item unless the roadmap and feature inventory are updated first.

## First 10 — exact order

1. **R0-01 — Decide legal product target and disposition of Factory Desktop** (`APP-001`, `CASE-001`, ADR-0001). Approve target/bundle/module naming and current-product retain/split/retire policy. Docs/package-plan only; no feature implementation.
2. **R0-02 — Scaffold isolated legal targets and dependency checks** (`TEST-001`, `PERF-003`). Add empty domain/infrastructure/app/test targets with dependency-direction tests; no legal UI behavior or current schema changes.
3. **R0-03 — Define legal identities, provenance, temporal and confidentiality value types** (`CASE-001`, `AUDIT-002`, `TIME-001`, `SEC-006`). Pure domain types/state invariants and unit tests only.
4. **R0-04 — Establish workspace-profile and case-persistence ownership** (`APP-003`, `SEC-007`, `BACKUP-006`). Define separate workspace/case stores, schema version/migration/locking/backup policy and temp-DB tests; do not touch current DB.
5. **R0-05 — Implement authorized-root capability and canonical boundary service** (`SEC-001`, `SEC-002`, `ORG-007`). Bookmarks/config abstraction, canonical containment, symlink/hard-link read policy and synthetic filesystem tests.
6. **R0-06 — Implement case audit ledger and atomic Unit of Work** (`AUDIT-001`–`005`). Append-only events, sensitivity/retention classes, domain-write atomicity and tombstone tests.
7. **R0-07 — Implement durable background-job and recovery-state foundation** (`APP-013`, `BACKUP-004`, `ACCESS-004`, `PERF-003`). Job IDs/checkpoints/cancel/restart/recovery protocols with kill/fault harness; no binder/file mutation yet.
8. **R0-08 — Add large-case fixtures and baseline performance/security gates** (`PERF-001`, `TEST-003`, `TEST-006`). Synthetic generators, benchmark budgets, confidential-log scanner and CI categories.
9. **R1-01 — Build first-run workspace setup, validation, and read-only recovery shell** (`APP-001/002/006/007/013`). Native setup/recovery UI using Phase 0 services; keyboard/VoiceOver tests.
10. **R1-02 — Implement blank legal case create/open/close and recents** (`CASE-001`, `APP-008/015`, `BACKUP-002`). Case schema v1, atomic creation, manual backup and recent references; no file catalog yet.

## Remaining Phase 1

11. **R1-03 — Workspace profile import/export and isolated switching** (`APP-004/005`, `PERF-004`).
12. **R1-04 — Core case metadata with versioned provenance** (`META-001`).
13. **R1-05 — People, parties, counsel, organizations and contact restrictions** (`META-002/003`).
14. **R1-06 — Typed case notes and confidentiality enforcement** (`META-006`, `SEC-006`).
15. **R1-07 — Existing-folder adoption plan and atomic case import** (`APP-014`, `IMPORT-001`).
16. **R1-08 — Actionable case dashboard, activity and warning aggregation** (`CASE-002/004/005`, `APP-011/012`).

## Phase 2

17. **R2-01 — CaseFile/FileVersion schema and read-only scanner** (`FILE-001/002`).
18. **R2-02 — Hashing, exact duplicates, missing/move/replacement reconciliation** (`FILE-004/008`).
19. **R2-03 — File watcher actor with overflow/full-rescan convergence** (`FILE-003`).
20. **R2-04 — Document metadata, tags, logical folders and bulk metadata** (`FILE-005/006/012`, `ORG-001`).
21. **R2-05 — Typed cross-domain file relationship foundation and version grouping** (`FILE-007/009`).
22. **R2-06 — Quarantine and unsupported/risky file classification** (`FILE-010`, `SEC-004`).
23. **R2-07 — Native preview boundary and fluid collapsible right panel** (`DOC-001/002/010`).
24. **R2-08 — PDFKit preview, page tools, source citations and positions** (`DOC-005/008/009`).
25. **R2-09 — Other native previews, tabs/stack and side-by-side comparison** (`DOC-003/004/006/007`, `FILE-011`).
26. **R2-10 — Exact structured and versioned PDF full-text search** (`SEARCH-001/002`).

## Phase 3

27. **R3-01 — EvidenceItem/EvidenceSource schema and file relationships** (`EVID-001/003`).
28. **R3-02 — Evidence neutral/strategy metadata, statuses and export exclusion** (`EVID-002/005`).
29. **R3-03 — Original/working/derivative lineage and integrity metadata** (`EVID-006/007`).
30. **R3-04 — Evidence issues, witnesses/events/assertion relationship APIs** (`EVID-004/008`).
31. **R3-05 — Evidence completeness validator and review workspace** (`EVID-010`).
32. **R3-06 — Evidence comparison and neutral index export** (`EVID-009`, `EXPORT-002`).

## Phase 4

33. **R4-01 — Exhibit identity, revision and lifecycle state machine** (`EXH-001/004/007`).
34. **R4-02 — Exhibit numbering schemes, locks, reservations and conflicts** (`EXH-002`).
35. **R4-03 — Exhibit titles, inclusion, foundation/admission links** (`EXH-003/008/009`).
36. **R4-04 — Composite exhibit page plan and source transforms** (`EXH-005`).
37. **R4-05 — Exhibit page quality validator** (`EXH-006`).
38. **R4-06 — Exhibit ordering/grouping/filtering workspace** (`EXH-010`).
39. **R4-07 — Atomic renumber impact plan, order locks, restore and change report** (`EXH-011/012`).

## Phase 5

40. **R5-01 — Binder/revision/volume schema and draft planning UI** (`BIND-001`).
41. **R5-02 — Pure binder page-plan and pagination/label engine** (`BIND-003`).
42. **R5-03 — Binder templates, covers, TOC, separators and markings** (`BIND-002`).
43. **R5-04 — Source-safe PDF/image normalization derivative stage** (`BIND-004`).
44. **R5-05 — Binder structural and quality validation/reconciliation** (`BIND-006`).
45. **R5-06 — Durable staged PDF assembly and incremental regeneration** (`BIND-005/007`).
46. **R5-07 — Binder manifest, exact ranges, hashes and exhibit index** (`BIND-008/011`).
47. **R5-08 — Binder finalization, reopen and revision preservation** (`BIND-009/010`).
48. **R5-09 — Court/internal/exchange export profiles and disclosure preview** (`EXPORT-001/005`).

## Phase 6

49. **R6-01 — Witness identity, roles, availability and restrictions** (`WIT-001/002`).
50. **R6-02 — Witness preparation, prior statements and typed notes** (`WIT-003/004/006`).
51. **R6-03 — Witness-exhibit links, order and neutral/contact exports** (`WIT-005/007/008`).
52. **R6-04 — Flexible sourced factual timeline model** (`TIME-001`–`004`).
53. **R6-05 — Disputed accounts, views and deterministic findings** (`TIME-005`–`007`).
54. **R6-06 — Typed notes, legal issues and investigation items** (`KNOW-001/002/005`).
55. **R6-07 — Factual assertions, support/contradiction and review workspace** (`KNOW-003/004/006`).

## Phase 7

56. **R7-01 — Calendar event/recurrence/source model and views** (`CAL-001`–`003`).
57. **R7-02 — Deadline suggestion and reviewed rule-reference model** (`CAL-005`).
58. **R7-03 — Deadline confirmation/rejection/manual override/recalculation** (`CAL-006/007`).
59. **R7-04 — Calendar reminders, rescheduling, conflicts and completion** (`CAL-004/009`).
60. **R7-05 — Legal task/subtask/checklist/dependency model** (`TASK-001`–`003`).
61. **R7-06 — Recurring tasks, saved views and preparation templates** (`TASK-004/005`).
62. **R7-07 — ICS and deadline/task report exports** (`CAL-008`, `TASK-006`, `EXPORT-003`).

## Phase 8

63. **R8-01 — Faceted/fuzzy/saved search and stale-index operations** (`SEARCH-003/004`).
64. **R8-02 — OCR derivative/index pipeline** (`SEARCH-005`).
65. **R8-03 — Manual communications, threads, relationships and preservation export** (`COMM-001`–`004`).
66. **R8-04 — Structured CSV/spreadsheet/list/calendar/contact imports** (`IMPORT-003/004`).
67. **R8-05 — Human and machine-readable case reports/schemas** (`EXPORT-002–004/007`).
68. **R8-06 — Binder manifest/package import interoperability** (`IMPORT-005`).
69. **R8-07 — Case package backup, restore preview and migration** (`IMPORT-006`, `EXPORT-006`, `BACKUP-003/006`).
70. **R8-08 — Archive/reopen and first-public-ready quality gate** (`BACKUP-005`, `CASE-007`, `META-007/008`).

## Phase 9

71. **R9-01 — File operation proposal model and full dry-run validator** (`ORG-002/006/008`).
72. **R9-02 — Durable transaction journal and single rename/move execution** (`ORG-003/009`).
73. **R9-03 — Cross-volume and bulk operations with compensating rollback** (`ORG-003/009`).
74. **R9-04 — Operation history and safe inverse undo** (`ORG-010`).
75. **R9-05 — Deterministic naming templates/normalization/suggestions** (`ORG-004/005`).
76. **R9-06 — Recovery Center UI and complete file fault-matrix release gate** (`BACKUP-004`, `TEST-003`).

## Phase 10

77. **R10-01 — AI provider, disclosure, consent and AISuggestion foundation** (`AI-001`, `SEC-008`).
78. **R10-02 — Source-grounded classification/title/name suggestions** (`AI-002/003`).
79. **R10-03 — Timeline/date/evidence/assertion suggestions** (`AI-004/005`, `TIME-008`).
80. **R10-04 — Relationship/duplicate/inconsistency/comparison/binder suggestions** (`AI-006`–`009`, `SEARCH-006`).
81. **R10-05 — Source-grounded briefing and natural-language search** (`AI-010`).

## Task completion template

Each task handoff records: feature IDs and copied acceptance criteria; current status before/after; files/modules affected; schema/migration/backup impact; original-file effect; threat/failure/recovery analysis; tests/fixtures/commands/results; docs/ADR changes; explicit deferrals. A task does not begin the next queue item automatically.
