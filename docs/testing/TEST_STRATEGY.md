# Testing and quality strategy

Testing ships with each feature. Feature status becomes “Implemented and verified” only when its acceptance criteria and applicable matrix below pass. Legal fixtures are synthetic or properly licensed and never use a live client case.

## Layers

| Layer | Required coverage |
|---|---|
| Domain/unit | Identity, state transitions, temporal precision, provenance/epistemic state, confidentiality/export visibility, ordering/numbering, page planning, recurrence/deadline formulas, deterministic validation |
| Persistence | CRUD/constraints, many-to-many links, Unit of Work/audit atomicity, concurrency/locking/read-only, corruption, backup, fresh and every supported migration |
| File boundary | Canonical roots, traversal, Unicode/case, symlink loop/escape, hard links, missing/changed/open/read-only/huge files, mount disconnect, stable identity/relink |
| Transactions/recovery | Plan digest, collision, no-overwrite, cross-volume, permissions/disk, rollback/undo conflicts, cancellation and process kill after every journal/side-effect/DB/audit point |
| Import/export | Mapping errors, duplicates, idempotent retries, staging, partial output, manifests/hashes, confidentiality/source-path profiles, package restore |
| Documents/binder | PDF/image/text/media/unsupported/corrupt/encrypted fixtures, pagination/labels/ranges/blank/separator, duplicate/missing pages, normalization, visual goldens, print geometry, revisions |
| Calendar/search/watcher | DST/time zone/all-day/recurrence, suggestion/confirmation/recalc, source citations, index staleness/reindex, watcher ordering/coalescing/overflow/full convergence |
| UI/accessibility | First run, missing/read-only/recovery, all main sections, preview collapse/width/stack/compare, restoration, keyboard/focus, VoiceOver, contrast/text/reduced motion, errors/cancel |
| Performance | Reference envelopes and targets in PERF-001/002, memory/temp/disk, main-thread stalls, cancellation/resume, workspace switch stress |
| Security/privacy | Bookmark revocation, quarantine/malformed docs, external open, log/crash content scans, case lock, export/AI disclosure consent |
| AI | Offline/timeout/refusal/malformed/hallucinated/uncited/stale-input outputs, acceptance/edit/rejection audit, direct-mutation prohibition, local/external disclosure |

## Fixtures

- Small and reference-scale case generators with deterministic IDs/clocks.
- Filesystems on case-sensitive and insensitive volumes where CI/lab supports; symlinks/hard links/sparse/Unicode/case-only names.
- PDF corpus: mixed page size/orientation, scanned/image/text, encrypted, malformed, truncated, forms, annotations, redaction-lookalikes, duplicate/blank/missing pages, very large file/page counts.
- Versioned SQLite/package/export/binder manifest goldens for every supported format.
- Reviewed synthetic deadline rule fixtures only; no jurisdiction content without governance.
- Fake preview/provider/calendar/watcher/clock/executor/storage adapters supporting delays, drift and fault injection.

## Phase gates

- Phase 0: architecture dependency checks; domain invariant skeleton; DB migration/backup/lock/corruption; root/symlink/hard-link; audit atomicity; job recovery harness; reference benchmarks.
- Phase 1: setup/profile/switch/case/metadata/dashboard; no-personal-path scan; confidentiality; workspace-race UI tests.
- Phase 2: catalog/watcher/version/hash/preview/search; stale/cancel/race/large-file and keyboard/VoiceOver tests.
- Phase 3: evidence provenance/lineage/export separation/completeness tests.
- Phase 4: exhibit identity/revisions/order/renumber locks/dependencies/missing pages.
- Phase 5: binder golden/render/reconcile/cancel/kill/finalize/reopen/export disclosure.
- Phase 6: witness strategy separation; timeline precision/citations/disputes.
- Phase 7: calendar/DST/recurrence; suggested-confirmed deadline invariants; task dependencies/templates.
- Phase 8: index/report/package/archive/restore/interoperability and public-ready full matrix.
- Phase 9: complete file-transaction fault matrix and operational recovery UI before any mutation ships.
- Phase 10: AI grounding/consent/offline/failure/direct-write tests before each capability is separately enabled.

## Commands and CI

Current SwiftPM baseline is `swift build` and `swift test`. As legal targets arrive, CI adds target-filtered unit suites, integration/golden tests, UI/accessibility jobs and scheduled large/performance/security jobs. Tests that require UI framework rendering or external volumes are explicitly tagged and run on controlled macOS hosts; they are not silently skipped in release evidence.

## Traceability

Test names or metadata include feature IDs. Each roadmap task lists its required layer/fixtures. P0/P1 acceptance criteria must map to at least one automated test unless a documented manual macOS/VoiceOver/print gate is unavoidable; manual gates record OS/hardware/input/output evidence.
