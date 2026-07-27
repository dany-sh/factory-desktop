# Canonical conceptual data model

This is conceptual, not a schema migration. IDs are opaque UUIDs unless a future ADR selects another stable form. Human labels, paths, case numbers, exhibit numbers, page labels, and hashes are attributes—not identity.

## Critical distinction

```mermaid
flowchart LR
    PF[Physical file bytes\nat an authorized URL] --> CF[CaseFile catalog identity]
    CF --> FV[FileVersion\nobserved bytes/version]
    FV --> ES[EvidenceSource\nprovenance role]
    ES --> EI[EvidenceItem\nevidentiary concept]
    EI --> EX[Exhibit\npermanent identity]
    EX --> ER[ExhibitRevision\nlocked composition/number assignment]
    ER --> EP[ExhibitPage\nsource page + transforms]
    EP --> BR[BinderRevision\npage plan and manifest]
    BR --> BV[BinderVolume\ngenerated derivative PDF]
```

A physical file exists outside the database. `CaseFile` catalogs it. `FileVersion` pins observed content. `EvidenceItem` explains evidentiary meaning and can use several sources. `Exhibit` is a permanent trial-preparation identity. `ExhibitRevision` pins title/number/composition. `ExhibitPage` describes generated pages. `BinderRevision` assembles locked exhibit revisions. Generated PDFs are derivatives and never evidence merely because they exist.

## Models

Each row states purpose; identity; important fields/relationships; lifecycle/mutability/versioning; physical-file/strategy/export/audit policy.

| Model | Definition and policy |
|---|---|
| `WorkspaceProfile` | Configures named workspace and roots/capabilities. UUID; name, bookmark/root references, derivative/backup policies, recents. Mutable/versioned; no case source itself; no strategy; profile export redacts bookmarks/secrets; audit create/change/switch. |
| `Case` | Root aggregate for a matter. UUID; metadata/status/root authorization/settings and relations to all case records. Mutable with audited fields; archived/closed states; may reference physical case root; may contain confidentiality but strategy lives in typed records; summary export profile-controlled. |
| `Party` | Case-specific role of a person/organization. UUID; case/entity/role/side/effective dates/aliases. Mutable/history; no file; may be sensitive; neutral export generally yes; audit. |
| `Person` | Reusable natural-person identity within case/workspace policy. UUID; names/aliases/contact fields. Mutable with merge history; no file; may be sensitive; export selected; audit. |
| `Organization` | Firm/court/company/agency identity. UUID; names/aliases/contact. Same lifecycle/export/audit rules as Person. |
| `Counsel` | Representation relationship, not a duplicate person. UUID; person, firm, party, role, effective dates, restrictions. Mutable/history; no file; sensitive; neutral/contact exports differ; audit. |
| `CaseFile` | Stable catalog record independent of path. UUID; case, current location, resource/volume identity, type, health, logical metadata, favorite/archive. Mutable location/health; never deleted merely because missing; directly references physical file; not strategy; selected exports; audit material catalog/relink changes. |
| `FileVersion` | Immutable observation of bytes. UUID; CaseFile, size/timestamps/hash/resource identity/MIME/availability/observedAt. Append-only/superseded; references physical version; no strategy; manifest export as configured; audit creation/integrity incident. |
| `DocumentMetadata` | App-owned descriptive metadata for CaseFile. UUID or one-to-one versioned record; source party, received/created/filed/served dates with provenance, status, confidentiality, notes. Mutable/history; no separate physical file; may contain internal notes; export field-controlled; audit. |
| `EvidenceItem` | Evidentiary concept. UUID; neutral/internal descriptions, status/category/issues/foundation/objections/review/priority. Mutable with history; relates many EvidenceSources, witnesses/events/assertions/exhibits; no direct file required; strategy yes; neutral export profile; audit. |
| `EvidenceSource` | Provenanced use of a file/version in evidence. UUID; EvidenceItem, FileVersion, role, page/Bates range, source/custodian/acquisition/authentication/hash/lineage. Mutable annotations but pins FileVersion; physical reference yes; may contain custody strategy; export selected; audit. |
| `Exhibit` | Permanent exhibit identity. UUID; case and lifecycle root. Mutable status through controlled transitions; no physical file by itself; strategy via revisions/notes; export yes; audit all transitions. |
| `ExhibitRevision` | Immutable/finalizable snapshot of number assignment, neutral/internal title, composition, inclusion and status details. UUID + revision number; belongs to Exhibit; draft mutable, finalized immutable/successor revisions; no single physical file; strategy yes; court profile excludes; audit. |
| `ExhibitPage` | Ordered generated-page instruction. UUID; revision, ordinal, source FileVersion/page, crop/rotation/redaction/blank/cover/separator transform, label. Immutable when revision final; references physical source version and derivative output; strategy no; manifest export yes; audit as revision plan. |
| `Binder` | Stable binder identity/configuration root. UUID; case/name/profile/current draft. Controlled lifecycle; no physical file; may contain internal profile; selected export; audit. |
| `BinderRevision` | Immutable snapshot of exhibit revisions, order, pagination/template/validation/manifest/finalization. UUID + revision; draft mutable then locked; relates volumes; no source file, generated derivative refs; strategy depending profile; manifest export; audit. |
| `BinderVolume` | Volume page plan and generated output metadata. UUID; BinderRevision, ordinal/title/page range/output derivative/hash/status. Regenerated only within draft; locked output preserved; derivative physical file yes; strategy according profile; export yes; audit. |
| `Witness` | Case role for Person. UUID; role/affiliation/call status/availability/subpoena/time/order/contact restrictions/prep fields. Mutable/history; no physical file; substantial strategy; neutral vs internal exports; audit. |
| `WitnessExhibitLink` | Typed relation (introduce/authenticate/foundation/impeachment/admission) between stable IDs. UUID; witness, exhibit, optional revision, status/date/source. Mutable/history; no file; strategy possible; export selected; audit. |
| `TimelineEvent` | Factual chronology entry. UUID; flexible temporal value, neutral fact, strategy interpretation, category/participants/location/status/accounts/citations/sequence. Mutable with versions; no direct file but source links; strategy yes; neutral timeline export; audit. |
| `CalendarEvent` | Court/preparation scheduled event. UUID; type, start/end/timezone/recurrence/status/source/responsible/relations/external IDs. Mutable with reschedule history; no file but citations; limited strategy; ICS/report export; audit. |
| `Deadline` | Candidate and/or confirmed due date with preserved calculation lineage. UUID; trigger, suggested date, confirmed date, state, override, calculation, rule reference. Append calculation revisions; confirmed never overwritten; no file; may be sensitive; report export; immutable decisions audit. |
| `DeadlineRuleReference` | Identifies reviewed rule/source, jurisdiction, edition/effective dates, formula metadata and citation. UUID/version; immutable once used; may reference source document/version; no strategy; calculation report export; audit publication/supersession. |
| `Task` | Legal preparation action. UUID; parent, dates, recurrence, priority/status/assignee/dependencies/relations/checklist/completion. Mutable/history; attachments link CaseFiles; notes may be internal; report selected; audit. Distinct from current `FactoryTask`. |
| `Note` | Typed narrative not suitable as issue/assertion/task. UUID; type/body/visibility/links/author/timestamps. Mutable with versions/tombstone; no direct physical file; often strategy; export explicit; audit. |
| `LegalIssue` | Structured claim/defense/element/theme/research issue. UUID; kind/title/description/status/parent/relations. Mutable/history; no file; strategy likely; export explicit; audit. |
| `FactualAssertion` | Atomic proposition with epistemic state. UUID; text/status/supporting/contradicting sources/witnesses/events/issues/review date/internal flag. Versioned/superseded; no direct file; strategy possible; export selected; audit. |
| `Communication` | Preserved communication/thread member. UUID; type/direction/participants/sent/received/status/thread/attachment FileVersions/source. Mutable metadata, source immutable; physical source/attachments yes; sensitive; export selected; audit. |
| `Tag` | Named/color/icon logical classification. UUID; workspace/case scope/name. Mutable; links many records; no file/strategy; export optional; audit definition/merges. |
| `CustomField` | Definition and typed values. Stable key UUID; label/type/options/scope/version/values. Definition versioned; no file; sensitivity configurable; export mapped; audit. |
| `AuditEvent` | Append-only consequential history. UUID/sequence; case/actor/time/type/object/transaction/before-after refs/reason/sensitivity. Immutable; may reference files but contains minimized payload; never strategy text unless essential; internal audit export; no edit/delete except governed retention class. |
| `FileOperationTransaction` | Durable operation plan/journal. UUID; plan digest/status/steps/preconditions/inverses/approver/recovery. Append state transitions; references physical paths/versions; no strategy; diagnostic/internal export; immutable audit link. |
| `ExportRecord` | What was disclosed/generated. UUID; profile/version/selection/input versions/output hashes/manifest/warnings/recipient-purpose optional/status. Immutable after publish; output physical derivatives; may reveal strategy selection; internal export log; audit. |
| `AISuggestion` | Non-authoritative probabilistic proposal. UUID; feature kind/input citations/provider/model/policy/output/confidence/status/user edits/decision/disclosure. Immutable proposal with decision history; no direct file; may contain strategy; excluded from neutral exports; audit request/accept/reject/failure. |

## Shared value types and relationship rules

Use typed `TemporalValue` (precise, approximate, range, unknown), `ProvenancedValue<T>` (origin, citation, epistemic state, confirmer, supersession), `SourceCitation` (stable record/file version/page/region), `Confidentiality`, `ExportVisibility`, `RecordVersion`, and typed relationship records. Do not encode these as free-form JSON when database constraints/querying matter.

Deletion is normally tombstoning/archive/supersession. Hard deletion is limited to disposable caches, abandoned uncommitted staging, or policy-governed diagnostics. Foreign keys use stable IDs; human numbers/titles/paths are projections.
