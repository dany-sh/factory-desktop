# Product vision

## Mission

Build a native macOS case workspace that takes a litigation or other document-intensive legal matter from initial organization through hearing, trial, or final resolution. It replaces fragmented Finder, spreadsheet, calendar, PDF, word-processing, paper-note, and script workflows while keeping originals authoritative, local, and recoverable.

The product must let a user understand case state, find and relate every source, prepare evidence and witnesses, build versioned exhibits and binders, manage factual and court dates, and export reliable deliverables. Automation may assist but may not become the authority.

## Product principles

1. **Local-first.** Core case work remains available offline. Network, cloud, calendar, and AI connections are optional adapters.
2. **Source preservation.** A source is immutable to the application. Edits, OCR, redactions, normalization, annotations, exhibit pages, and binders are derivatives with their own identity.
3. **Safe operations.** Consequential file changes have a complete plan, validation, explicit approval, durable transaction journal, recovery, rollback where feasible, operation history, and bounded scope.
4. **User authority.** Suggestions do not mutate authoritative records. Acceptance is an explicit, auditable user action.
5. **Legal reliability.** Values carry provenance and epistemic state: source, user-entered, inferred, suggested, confirmed, disputed, or superseded. Suggestions never masquerade as confirmed law or fact.
6. **Traceability.** Dates, assertions, descriptions, pages, and generated output resolve to stable records and source citations even after a filename changes.
7. **Progressive complexity.** Manual local workflows precede OCR, semantic search, calendar sync, rules, and AI.
8. **Native macOS.** SwiftUI owns scenes and standard presentation; focused AppKit bridges provide windowing, Finder, Quick Look, PDFKit, media, responder-chain, and security-scoped access where needed.
9. **Configurable workspaces.** Users explicitly select workspace and case roots. No compiled username, case name, personal directory, or permanent single-workspace assumption is allowed.
10. **Architecture before accumulation.** Every feature has an owner, identity, lifecycle, boundary, acceptance criteria, tests, and recovery story.

## Product boundaries

The application catalogs and relates physical files; it does not require physical reorganization. Logical folders, tags, ordering, evidence/exhibit relationships, and case metadata live in application persistence. On-disk renames and moves are optional, separately approved transactions.

The application is not a legal research authority, deadline authority, document-management cloud, e-filing portal, word processor, redaction guarantee, or substitute for professional judgment. Jurisdiction-specific rules require a reviewed rule framework and identifiable source before inclusion.

## Release boundaries

| Boundary | Meaning | Required capability groups |
|---|---|---|
| Minimum safe product (MSP) | Can open/configure a case without risking sources | P0 workspace profiles, source identity, read-only catalog, permission/boundary checks, audit foundation, backups, recovery mode, migration policy |
| Minimum viable product (MVP) | Safely organizes and understands one case | MSP plus P1 case metadata/dashboard, parties, files, native preview, basic evidence, manual tasks/calendar/timeline, exact search, basic exports |
| Minimum useful product (MUP) | Supports a real pre-hearing evidence workflow | MVP plus exhibit lifecycle/order, witness links, sourced timeline, draft single-volume binder with validation and revision history |
| First public-ready version | Reliable multi-case trial-preparation workspace | MUP plus multi-volume binder, archive/restore, accessibility, performance gates, file-operation recovery, comprehensive reports, confidentiality profiles |

AI, semantic search, auto-classification, legal-rule calculations, two-way calendar synchronization, near-duplicate ML, and aggressive physical organization are excluded until deterministic foundations and audit/recovery are mature.

## Default assumptions and open product choices

- Default: one `WorkspaceProfile` can contain many cases; each case has one explicitly authorized source root and one app-managed derivative root.
- Default: case databases are case-scoped for portability and confidentiality, while workspace-level storage holds profiles, recents, and non-sensitive UI state.
- Default: exhibit identity is a UUID; exhibit numbers are versioned assignments, never identity.
- Default: binders are immutable revisions. Reopening creates a new revision.
- Default: system calendar integration begins as export-only; import/sync arrives later.
- Open: whether the current Factory Desktop executable is retired, retained as a separate product, or moved to a separate package. See ADR-0001.
- Open: application sandbox distribution strategy and bookmark storage details.
- Open: the reviewed legal-rule content/provider governance process.

## Success measures

- No original is modified by cataloging, preview, evidence creation, exhibit creation, binder generation, search, OCR, or AI.
- Every generated page and exported value resolves to a source/revision/citation.
- Interrupted mutations and binder jobs reopen into an explicit recovery state.
- A user can determine the next safe action from the dashboard without decoding raw counts.
- Core case operation remains usable offline and without AI.
