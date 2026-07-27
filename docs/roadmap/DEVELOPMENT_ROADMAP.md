# Development roadmap

This roadmap is sequential. A later phase may prototype behind a disabled flag only if all prior architectural prerequisites it consumes have exited. Tests are part of every phase.

## Inventory totals

| Domain | Count | Domain | Count |
|---|---:|---|---:|
| ACCESS | 5 | AI | 10 |
| APP | 15 | AUDIT | 5 |
| BACKUP | 6 | BIND | 11 |
| CAL | 9 | CASE | 7 |
| COMM | 4 | DOC | 10 |
| EVID | 10 | EXH | 12 |
| EXPORT | 7 | FILE | 12 |
| IMPORT | 6 | KNOW | 6 |
| META | 8 | ORG | 10 |
| PERF | 5 | SEARCH | 6 |
| SEC | 8 | TASK | 6 |
| TEST | 6 | TIME | 8 |
| WIT | 8 | **Total** | **200** |

| Priority | Count | Meaning |
|---|---:|---|
| P0 | 59 | Structural or data safety |
| P1 | 76 | First genuinely usable case workflow |
| P2 | 43 | Complete trial preparation |
| P3 | 11 | Advanced productivity |
| P4 | 11 | Optional future |

Counts use the first/primary priority in each feature row and were mechanically verified against the inventory.

## Release boundaries

- **Minimum safe product:** all P0 foundations needed to configure/open a case read-only: ADR-0001; APP-001/003/006/007/013; CASE-001; FILE-001/002/010; ORG-007; AUDIT-001–005; SEC-001–007; BACKUP-001/002/004/006; PERF-001/003/004; TEST-001–003/006. It does not ship physical mutation or claim usefulness without Phase 1/2.
- **MVP:** minimum safe product plus Phase 1 and the P1 slice of Phase 2/3/6/7/8: case metadata/dashboard/parties, read-only catalog, native preview, exact/full-text search, evidence/provenance, manual sourced timeline/calendar/tasks, basic reports/exports.
- **Minimum useful product:** MVP plus exhibits/order/renumbering, witnesses and a validated draft single-volume binder with revision history.
- **First public-ready version:** through Phase 8 plus hardened archive/restore, multi-volume binder, accessibility/performance/security release matrix. Physical reorganization remains optional and may ship later.
- **Architecture-mature-only:** Phase 9 physical bulk organization and Phase 10 AI/semantic/two-way integrations. AI cannot be used to compensate for missing deterministic features.

## Phase 0 — Repository and architecture stabilization

- **Goal/value:** establish a legal product boundary and a minimum safe substrate without changing the current coding product.
- **IDs:** APP-001/003/006/007/013; CASE-001; ORG-007; AUDIT-001–005; SEC-001–005/007; BACKUP-001/002/004/006; PERF-001/003/004; TEST-001–003/006; ACCESS-004.
- **Dependencies/prerequisites:** accept ADR-0001; enforce module direction; separate workspace/case storage; synthetic fixtures.
- **Migrations:** none to current DB; define independent legal workspace/case schema and format version policy.
- **Tests:** dependency checks, domain IDs/provenance, migration/backup/lock/corruption, root/symlink/hard-link, audit atomicity, recovery kill harness, performance baseline.
- **Risks:** mixed products, fixed paths, premature schema, overlarge global store.
- **Exit:** legal targets compile/test independently; current 181 tests still pass; no current table/source behavior changed; root authorization, read-only failure, audit and job recovery contracts proven.
- **Deferred:** case UX beyond setup shell; catalog content; all mutation/binder/AI.
- **Task sequence:** R0-01 through R0-08 in `IMPLEMENTATION_TASKS.md`.

## Phase 1 — Case foundation

- **Goal/value:** configure profiles and create/open a usable case with identity, metadata, people, dashboard and recents.
- **IDs:** APP-002/004/005/008/011/012/014/015; CASE-001/002/004/005; META-001–003/006; IMPORT-001; SEC-006; ACCESS-001–003/005; PERF-002/004; TEST-001/002/006.
- **Dependencies:** Phase 0 case session/persistence/audit/security.
- **Migrations:** legal schema v1 for cases, people/parties/counsel/notes/provenance/audit; workspace profile schema v1.
- **Tests:** first-run/cancel/import/create/switch/read-only; metadata/versioning/confidentiality; recents; dashboard provenance; workspace-switch race; keyboard/VoiceOver.
- **Risks:** onboarding writes sources, personal paths, confidential dashboard leakage.
- **Exit:** blank/template/existing-folder case opens; profile switch is isolated; dashboard identifies next safe actions; backups/restoration of schema v1 pass.
- **Deferred:** detailed catalog/preview, advanced metadata/issues, calendar sync.
- **Task sequence:** R1-01 through R1-08.

## Phase 2 — File catalog and document workspace

- **Goal/value:** understand and preview the case tree without changing it.
- **IDs:** FILE-001–012; ORG-001; DOC-001–010; SEARCH-001/002; IMPORT-002; SEC-002–005; PERF-002/003; ACCESS-001–005; TEST-003/004/005/006.
- **Dependencies:** authorized case root, stable IDs/provenance, background jobs.
- **Migrations:** CaseFile/FileVersion/DocumentMetadata/tag/logical-organization/relationship tables; disposable index schema separate.
- **Tests:** scans/watch races/overflow, identity/hash/move/replacement, missing/quarantine, bulk metadata, renderer stale/cancel/crash, PDF pages/search, preview panel collapse/no-gap, scale.
- **Risks:** watcher races, stale previews/index, malformed docs, hard-link/symlink escape.
- **Exit:** 50k-file fixture is browsable; catalog load writes nothing under source root; native preview and source citations work; exact/full-text results are version-correct.
- **Deferred:** physical rename/move, OCR/semantic, evidence semantics.
- **Task sequence:** R2-01 through R2-10.

## Phase 3 — Evidence management

- **Goal/value:** turn cataloged files into sourced, reviewable evidence records while preserving originals/derivatives.
- **IDs:** EVID-001–010; FILE-007/009; META-004; TEST-001/002/006.
- **Dependencies:** Phase 2 file identity/preview/relationships.
- **Migrations:** evidence/source/link/status/provenance tables.
- **Tests:** many-to-many files/evidence, provenance, original/derivative roles, strategy export exclusion, missing versions, completeness and comparisons.
- **Risks:** conflating files/evidence/derivatives, confidential strategy leakage.
- **Exit:** evidence workflow 3 passes end-to-end; every source pins exact FileVersion; neutral evidence index contains no strategy.
- **Deferred:** exhibits/binder, AI summaries.
- **Task sequence:** R3-01 through R3-06.

## Phase 4 — Exhibits and ordering

- **Goal/value:** create versioned exhibits, inspect pages/quality, order and safely renumber them.
- **IDs:** EXH-001–012; AUDIT-004; TEST-001/002/004.
- **Dependencies:** evidence provenance and document page model.
- **Migrations:** exhibit identity/revision/page/number/order/link/inclusion tables.
- **Tests:** UUID permanence, state/locks, page ranges, replacement, duplicate/missing pages, drag/order restore, renumber conflicts/dependency mapping/atomicity.
- **Risks:** number as identity, stale references, missing pages, strategy export.
- **Exit:** workflows 4/5/7 pass; locked orders/number assignments cannot mutate silently; old/new report reconstructs every change.
- **Deferred:** binder PDF assembly, admission automation.
- **Task sequence:** R4-01 through R4-07.

## Phase 5 — Binder generation

- **Goal/value:** generate validated, traceable single/multi-volume draft/final binders without touching sources.
- **IDs:** BIND-001–011; EXPORT-001/002/005; BACKUP-004; PERF-005; TEST-004/006.
- **Dependencies:** locked exhibit revisions/order; derivative store; durable jobs.
- **Migrations:** binder/revision/volume/job/validation/export record tables; manifest v1.
- **Tests:** page-plan goldens, normalization, labels/ranges/TOC, duplicate/missing/redaction warnings, large/cancel/kill/low-disk, atomic publish, finalize/reopen/reproduce.
- **Risks:** pagination/render mismatch, partial finals, source modification, confidential export.
- **Exit:** workflows 6/12/15 pass; independent reconciliation matches all manifests; source hashes unchanged; prior final remains on every failure.
- **Deferred:** court-specific filing automation, AI review.
- **Task sequence:** R5-01 through R5-09.

## Phase 6 — Witnesses, factual timeline, and knowledge

- **Goal/value:** prepare testimony and a sourced factual narrative distinct from court dates.
- **IDs:** WIT-001–008; TIME-001–007; KNOW-001–006; META-004/005; CASE-006; TEST-001/002/006.
- **Dependencies:** evidence/exhibit relationships, provenance, preview.
- **Migrations:** witness/link/order, temporal/account/citation, issue/assertion/note tables.
- **Tests:** strategy-neutral separation, restrictions, stable exhibit links after renumber, flexible dates, competing accounts, assertion support/contradiction/supersession.
- **Risks:** unsourced facts, strategy leakage, timeline/calendar confusion.
- **Exit:** workflows 8/9 pass; every confirmed timeline fact is sourced/user-confirmed; neutral witness/timeline exports exclude strategy.
- **Deferred:** extraction suggestions, credibility scoring (non-goal).
- **Task sequence:** R6-01 through R6-07.

## Phase 7 — Calendar, deadlines, and tasks

- **Goal/value:** manage dates/preparation with a legally honest suggestion-confirmation workflow.
- **IDs:** CAL-001–009; TASK-001–006; CASE-002/005; EXPORT-003; TEST-005/006.
- **Dependencies:** ADR-0003, provenance, deterministic clock/calendar abstraction.
- **Migrations:** calendar/recurrence/deadline/rule-ref/calculation/decision/task/dependency/template/reminder tables.
- **Tests:** time zones/DST/recurrence, source links, candidate/confirm/reject/reschedule/recalc, no confirmed overwrite, cycles/templates/idempotence, ICS export.
- **Risks:** deadline error, status confusion, external calendar conflict.
- **Exit:** workflow 10 passes; suggested and confirmed are type/UI/export distinct; no jurisdiction formula ships without reviewed governance.
- **Deferred:** two-way EventKit, AI trigger extraction.
- **Task sequence:** R7-01 through R7-07.

## Phase 8 — Search, communications, reporting, archive, public readiness

- **Goal/value:** retrieve/report/exchange/archive a complete case reliably.
- **IDs:** CASE-007; META-007/008; COMM-001–004; SEARCH-003–005; IMPORT-003–006; EXPORT-002–007; BACKUP-003/005; FILE-008/009; EVID-009; TIME-006/007; TEST-004–006.
- **Dependencies:** all deterministic domain owners and export profiles.
- **Migrations:** communications/custom fields/saved search/OCR extraction/archive package metadata; export/package schemas v1.
- **Tests:** mapping/idempotence, index/OCR staleness, reports/JSON/CSV/ICS, disclosure profiles, package hashes, isolated restore, archived read-only, full accessibility/performance/security matrix.
- **Risks:** partial/confidential exports, restore/migration failure, index scale.
- **Exit:** archive/restore workflow passes; first public-ready matrix passes; machine/human outputs reconcile.
- **Deferred:** semantic search, external mail/calendar required sync.
- **Task sequence:** R8-01 through R8-08.

## Phase 9 — Safe organization automation

- **Goal/value:** optionally perform explainable physical organization with industrial-strength recovery.
- **IDs:** ORG-002–010; AI-002 only later behind Phase 10; AUDIT-004; BACKUP-004; TEST-003; PERF-005.
- **Dependencies:** mature stable identity/catalog/audit/recovery and full file fault harness.
- **Migrations:** FileOperationTransaction/step/journal/history v1.
- **Tests:** full safety matrix in `FILE_SAFETY_MODEL.md`, including cross-volume/kill/rollback/undo/external drift.
- **Risks:** catastrophic data loss or out-of-root mutation.
- **Exit:** workflow 11/14 pass at every injected failure; source bytes never change; operations remain optional/off by default until release review.
- **Deferred:** unattended mutation, destructive dedupe, auto-organization.
- **Task sequence:** R9-01 through R9-06.

## Phase 10 — Optional AI assistance

- **Goal/value:** add source-grounded suggestions while keeping every manual workflow intact.
- **IDs:** AI-001–010; TIME-008; SEARCH-006; SEC-008; TEST-006.
- **Dependencies:** mature provenance, consent, suggestions, deterministic alternatives.
- **Migrations:** AISuggestion/disclosure/decision records; embeddings/index formats remain disposable.
- **Tests:** grounding/citation, stale inputs, hallucination, provider/consent/offline failure, accept/edit/reject audit, no direct writes.
- **Risks:** confidentiality, hallucinated law/facts/dates, AI dependency.
- **Exit:** each AI capability separately gated and removable; disabling network/provider leaves public-ready core passing.
- **Deferred:** autonomous agents, uncited case chat, AI legal conclusions/deadline confirmation.
- **Task sequence:** R10-01 through R10-05.

## Global exit rule

A phase exits only when every included P0/P1 acceptance criterion is mapped to passing automated/manual evidence, migrations/backups are proven, source-file effect is verified, authoritative docs are updated, and the next phase can consume stable protocols rather than implementation internals.
