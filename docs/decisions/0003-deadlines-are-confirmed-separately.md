# ADR-0003: Deadline suggestions and confirmed deadlines are separate

- Status: Accepted as architecture baseline
- Date: 2026-07-16
- Feature IDs: CAL-005, CAL-006, CAL-007, AUDIT-002

## Decision

A deadline calculation produces a versioned suggestion with trigger, formula, source and work shown. A confirmed deadline is an explicit user decision preserving the suggestion. Recalculation creates another candidate and cannot overwrite a confirmed date.

## Consequences

Dashboard, reminders, reports and exports must use typed state and visually separate confirmed/tentative/suggested. Rules require reviewed sources and effective-date governance. AI may extract candidates but cannot authorize a rule or confirmation.
