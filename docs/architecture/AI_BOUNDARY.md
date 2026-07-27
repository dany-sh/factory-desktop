# Optional AI boundary

AI is an adapter that creates suggestions. The local application, deterministic services, source records, user confirmations, and audit ledger remain authoritative.

## Contract

An AI request contains feature ID/purpose, case/workspace scope, exact input record/file versions and permitted excerpts, redaction/minimization policy, provider/model/configuration, whether data leaves the Mac, requested structured output schema, citation requirements, and cancellation/retention policy. External requests require a disclosure preview and scoped consent.

The provider returns an untrusted structured response. The boundary validates schema, citation resolvability, scope, input versions, and prohibited authority changes, then stores an `AISuggestion`. Domain repositories cannot be injected into provider adapters. Accept/edit/reject is a separate user command that creates normal domain history and references the suggestion.

## Feature policy

| Capability | Inputs | Required review/grounding | Offline/failure behavior |
|---|---|---|---|
| Name/folder/class/title | Confirmed metadata and selected file text | Reason/input fields; accepted physical change still uses file transaction preview | Deterministic templates/manual editing remain |
| Summary/facts/assertions | Exact source versions/pages | Every material claim cites source; user chooses epistemic state | Manual summary/structured records remain |
| Timeline/date candidates | Exact source pages/text | Candidate only; page citation; user edits/confirms | Manual timeline/date entry remains |
| Deadline candidate extraction | Source document citation only | Cannot invent rule or confirm date; deterministic engine separate | Manual trigger/rule selection remains |
| Relationship/witness suggestions | Existing stable IDs and citations | Per-item/batch diff approval | Manual linking remains |
| Duplicate/inconsistency/missing | Exact compared records/index versions | Explain comparison; no delete/merge | Exact-hash/deterministic checks remain |
| Comparison/thread summary | Pinned versions/messages | Source citations; stale on input change | Native compare/manual review remains |
| Binder review | Binder manifest/render/validation | Cannot waive blocking validation | Deterministic validation remains |
| Briefing/NL search | Explicit authorized query scope/index | Resolvable citations; may answer not found | Exact/faceted search and dashboard remain |

## Hallucination and authority controls

- No AI output directly edits Case, File, Evidence, Exhibit, Binder, Witness, Timeline, Calendar, Deadline, Task, Assertion, or export records.
- Unresolvable citations make the suggestion invalid. Citation presence is necessary but not proof; review UI shows source beside output.
- Dates, rules, legal conclusions, admission status and factual confirmation have typed authority gates that AI credentials cannot satisfy.
- Accepted text keeps provider/model/policy/input hashes, source citations, user edits and decision history.
- Rejection/failure is non-destructive and auditable. Repeated rejected suggestions may be suppressed locally by policy.
- Provider outage, timeout, refusal, malformed response, input drift, or consent denial returns to the manual workflow.
- Logs exclude source content; provider retention/training terms are presented rather than assumed.

## Local versus external

Local models still produce untrusted suggestions but require no network disclosure. External providers require explicit current consent and a documented data-retention boundary. Provider choice is case/workspace configuration, never compiled. Natural-language UX may not obscure which provider receives what.
