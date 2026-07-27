# Native macOS information architecture

## Window and layout model

One case window uses a native sidebar, central content, optional inspector/preview, toolbar, menus, sheets, and panels. The sidebar sections are Dashboard, Files, Evidence, Exhibits, Binder, Witnesses, Timeline, Calendar, Tasks, Notes & Issues, Search, and Activity. Workspace/case selection sits above sections; settings are separate.

The right side has one fluid container with metadata/relationships and document preview modes. It is collapsible and resizable. **When closed, it is removed from the split layout and the central workspace expands to fill the complete available width; no fixed empty preview column or center max-width reserves space.** Width is restored per window/section within safe bounds. Side-by-side comparison may use the central canvas or a dedicated window so the inspector is not overloaded.

Selection uses stable IDs and is section-owned. Preview follows selection only when enabled; pinned preview tabs do not change when list selection changes. Navigation routes link to the owning section rather than recreating duplicate editors elsewhere.

## Sections

| Section | Main list/canvas and purpose | Inspector/preview | Commands and drag/drop | Empty/error behavior |
|---|---|---|---|---|
| Dashboard | Action cards: next event/deadline, tasks, readiness, warnings, activity, missing info | Selecting a card shows source/why/action; document warning can preview source | Resolve, confirm, open, create task; no object reordering | Setup checklist; stale/degraded cards identify owner and retry |
| Files | Outline/table of physical tree plus logical views, metadata columns and bulk selection | File metadata/relationships beside native preview | Import, rescan, reveal, open, tag, propose organize; drag changes logical group by default, physical move requires transaction sheet | Explain authorized root/import; missing/permission/watcher state with reconnect/rescan |
| Evidence | Filterable evidence list with review/category/priority/completeness | Evidence inspector plus selected source preview and provenance | Create/link/compare/review/exclude; drop files creates a reviewed evidence-link proposal | Teach file vs evidence; broken source/completeness warnings |
| Exhibits | Proposed/final/status list and dedicated ordering canvas | Exhibit revision/source pages/validation/witness links; page preview | Create, revise, status, lock, drag order/groups; renumber always previews mapping | Explain evidence prerequisite; conflicts/missing pages are actionable |
| Binder | Revision/volume outline and page-plan canvas | Validation/manifest/page preview | New revision, assign volumes, validate, generate, finalize; drag only in draft | Start from selected exhibits; interrupted job routes recovery |
| Witnesses | Witness list/order and preparation overview | Neutral details plus gated internal prep; linked exhibit/source preview | Add/link/reorder/generate list/contact sheet | Explain person vs witness; contact restriction warnings |
| Timeline | Table/chronology/visual views of factual events | Event sources/accounts/strategy plus source preview | Add/confirm/dispute/link/filter/export; drag may adjust visual grouping, never date silently | Explain factual vs court calendar; unsourced/conflicting state |
| Calendar | Month/agenda/upcoming and deadline review queue | Event source, calculation, related tasks/docs | Add/reschedule/confirm/reject deadline/export ICS | No-date onboarding; sync/permission failures leave local calendar usable |
| Tasks | List/board/checklist saved views | Task metadata, dependencies and linked source preview | Add/subtask/complete/reorder checklist/apply template | Preparation template choices; dependency/error details |
| Notes & Issues | Segmented typed notes, legal issues, assertions, investigation | Source/support/contradiction/visibility; preview cited material | Add/link/supersede/convert question to task | Explains why notes/issues/assertions are distinct |
| Search | Query, scope/facets, grouped results | Result context and preview at match/page | Save search, open owning section, compare; no destructive drag | Index status/staleness/reindex action; exact search usable without semantic AI |
| Activity | Human-readable consequential event timeline with filters | Before/after/source/transaction/recovery details | Filter/export audit; navigate to target/tombstone | No activity yet; diagnostics unavailable does not hide audit |

## Global interaction rules

- Space toggles Quick Look/preview; Command-Option-I toggles inspector; Command-K focuses global search/commands if adopted; standard Back/Forward and Save semantics apply.
- Context menus mirror menu/toolbar commands and never become the sole route.
- Drag/drop defaults to logical relationships/order. A drop that would copy/move/rename physical files opens an explicit plan sheet.
- Internal strategy is visually distinct and never shown in a neutral preview/export context without an explicit profile switch.
- Long jobs live in a jobs/recovery surface and may continue while users navigate; selection changes cannot redirect results.
- Multiwindow: case windows may be independently read-only/writable per locking policy; document comparison windows are non-authoritative.
- Window restoration excludes confirmations, unsent external disclosure, and in-progress mutation approvals.

## Native framework ownership

SwiftUI owns scenes, navigation, lists/tables, toolbars, inspectors, settings, sheets, and most forms. PDFKit owns PDF rendering/search/page/zoom. Quick Look owns broad read-only fallback. AppKit bridges own NSWindow panels, NSOpen/SavePanel, Finder/NSWorkspace, responder-chain/menus, and security-scoped URLs. AVKit/AVFoundation owns media. ImageIO/TextKit/native text views handle image/plain/rich text where practical. `WKWebView` is not the primary case workspace; it is allowed only for a narrowly justified renderer/editor with an ADR and accessibility/security tests.
