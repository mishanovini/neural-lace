# Workstreams rebuild — residual defects + stale claims (2026-06-09)

Persisted per bug-persistence at the close of the R1–R8 rebuild (acceptance 4/4 PASS, plan 6/6
task-verified). These are the known-open residuals carried forward, each with a route.

| # | Finding | Evidence | Route |
|---|---|---|---|
| 1 | 10 U+FFFD mojibake chars frozen in item TEXT (`cls-coord-*`, `cls-s4` etc.) — corruption is upstream-of-canonical (em-dash mangle at the 07:23 migration ingest); details fields carry clean text since R6, but item text is unrepairable | R5/R8 builder reports; `tree-state.json.audit.log` carries EF BF BD at ingest | discovery `2026-06-09-no-event-sourced-text-repair-path.md` (pending) — add additive `item-text-set` event |
| 2 | "Awaiting me" and "In flight" filters are non-discriminating (209 = 209: every open unchecked item satisfies both) — not false, but the partition carries no signal yet | R8 advocate defects-beyond-scenarios | UI follow-up: distinguish Misha-ask items (`_category` present) from wim work items in the Awaiting-me predicate |
| 3 | Migration 162's header comment claims "all Circuit data is test data (2026-06-04 audit)" — **STALE: One Season Heating and Air Conditioning is a real customer as of Misha 2026-06-09.** Live impact quantified: One Season exposure = 4 `time_windows` rows normalized (no deletions); PT-internal orgs hold the 32 contacts + 16 appointments with legacy values | prod query 2026-06-09 (service-role, per-org counts); Misha statement | Fix the header claim when m162 is applied; m162 apply awaiting Misha go |
| 4 | Code/DB atomicity violation lived 5 days (Bundle B code merged 2026-06-04; m162 unapplied) because the approval ask drowned in chat — the exact failure class the Workstreams tracker now prevents | git log + migration state | Structural fix shipped (tracker + enriched m162 item); apply closes the drift |
| 5 | `preview_screenshot` times out against the Workstreams UI page (renderer-capture issue; page healthy, console clean) — pixel evidence replaced by DOM dumps in acceptance artifacts | R8 method note | Tooling follow-up, low priority |

## Status update 2026-06-10
- Residual #3 RESOLVED: m162 APPLIED to prod + verified (contacts {diagnostic:30,maintenance:10,installation:3}; enum rejects legacy; One Season = 4 time_windows rows normalized, nothing deleted). Three latent migration bugs fixed en route (old-enum DEFAULT on the array column; forbidden param rename; manual _backup_162_* snapshots pinning the old type — recast to text, data preserved). Fix on circuit master 9f2b8afe; stale "test data" header corrected.
- Residual #4 RESOLVED: the code/DB atomicity drift is closed by the apply.
- NEW (2026-06-10): One Season is a REAL customer — circuit merges now carry real-user risk; continuous program proceeds full-auto ONLY on Misha's explicitly-directed items, with post-merge deploy verification and pre-deploy acceptance on customer-messaging-grade work (items 2/14). Customer-tier flip to review-before-deploy offered to Misha as the standing alternative.
