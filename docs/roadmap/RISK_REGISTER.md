# Risk register

Severity/likelihood use Critical/High/Medium/Low. Detection is required before prevention can be considered complete.

| Risk | Sev / likelihood | Detection | Prevention | Recovery | Must address |
|---|---|---|---|---|---|
| Destructive file operation | Critical / Medium | Hash/path/journal reconciliation and kill tests | Authorized roots, typed plan, no-overwrite, approval digest | Compensating rollback/NeedsUser and backup | Ph0 design, Ph9 execution |
| Broken source references | Critical / Medium | Missing/move/version health scans | Stable CaseFile/FileVersion IDs, typed links | Confirmed relink or tombstone; never guess | Ph2 |
| Incorrect exhibit renumbering | High / Medium | Complete mapping/dependency diff | UUID identity, locks/reservations, atomic plan | Restore as new order revision/change report | Ph4 |
| Binder pagination/range error | Critical / Medium | Independent PDF reconciliation/goldens | Pure page plan + locked inputs | Reject publish; regenerate successor | Ph5 |
| Missing/duplicate pages | Critical / Medium | Source/page/manifest/visual validation | Exact ranges and page provenance | Block finalization; revise exhibit/binder | Ph4–5 |
| Stale preview | High / Medium | Version token mismatch | Cancellation/generation IDs/versioned tabs | Mark stale; reload/compare | Ph2 |
| Stale search index | High / High | File/index version comparison | Version-keyed index and watcher reconciliation | Exclude/label stale; reindex | Ph2/8 |
| Deadline calculation error | Critical / Medium | Golden formula/time-zone tests and review display | Reviewed rule refs, pure engine, work shown | Preserve confirmed date; supersede candidate/corrective audit | Ph7 |
| Suggested/confirmed confusion | Critical / Medium | Type/UI/export assertions | Separate fields/states/commands/styles | Corrective confirmation event; warnings | Ph1 model, Ph7 UI |
| AI hallucination | Critical / High if enabled | Citation/schema/grounding tests and user review | Suggestion-only boundary; typed authority gates | Reject/supersede; provider disable; audit | Ph10 before enable |
| Confidential data leakage | Critical / Medium | Disclosure preview tests/log scans | Restrictive profiles, field classification, scoped consent | Revoke provider/access; incident/export record | Ph0–1 and every export |
| Database/file divergence | Critical / Medium | Journal/catalog/DB reconciliation | Unit of Work + durable recovery record | Recovery Center completes/compensates/relinks | Ph0/9 |
| External file modifications | High / High | Watcher/full scan/version/hash | Version pinning, stale states, read-only guidance | New FileVersion, compare/relink/revise | Ph2 |
| Workspace switching race | Critical / Medium | Stress with generation IDs | Case-scoped actors, cancellation/drain | Reject stale publication; reopen affected case read-only/audit incident | Ph1 |
| File watcher race/overflow | High / High | Event-sequence/overflow fixtures | Events as hints, batching, periodic/full reconcile | Full rescan converges | Ph2 |
| Large-case performance | High / High | Reference benchmarks/telemetry without content | Paging, indexes, incremental async jobs | Cancel/resume/degraded mode/soft limit warning | Ph0 then every phase |
| Unsupported/malformed format | High / High | Type/parser/quarantine fixtures | Safe renderer choice, isolation, no execution | Clear unsupported state, safe external open | Ph2 |
| PDF rendering differences | High / Medium | Cross-version visual/page/hash reconciliation | Record renderer version; normalized derivatives; tolerances | Block finalization or regenerate with preserved prior revision | Ph5 |
| Partial export | Critical / Medium | Manifest/hash/staging state | Stage then atomic publish | Delete/recover staging; previous export intact | Ph5/8 |
| Migration failure | Critical / Medium | Golden old schemas/checksums/integrity | Preflight backup, transactional migration, independent schema owner | Restore backup/read-only recovery | Ph0 and every schema change |
| Restore failure | Critical / Low | Isolated restore verification | Package hash/schema/path preview | Leave current case untouched; clean staging | Ph8 |
| Over-coupled domain models | High / High | Dependency checks/file-size/review | Domain modules/protocol boundaries/ADRs | Extract in bounded migration before feature growth | Ph0 |
| UI complexity/duplicated editors | Medium / High | IA review/usability/accessibility tests | One owning section, shared inspector/preview, progressive disclosure | Simplify route/read model, retain IDs/data | Every UI phase |
| Scope expansion | High / High | Feature-ID/task/exit-criteria review | One-focused-task queue, explicit deferrals | Stop/re-scope/document new feature ID | Every phase |

No Critical risk may be accepted implicitly. A phase can exit with a Critical residual risk only through an explicit ADR documenting owner, evidence, mitigation and release boundary impact.
