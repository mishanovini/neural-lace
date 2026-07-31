---
title: product-acceptance-gate waiver path unreachable for exempt+UI plans
date: 2026-06-10
type: process
status: superseded
auto_applied: false
originating_context: "Operational session (launch Workstreams UI server + desktop shortcut). product-acceptance-gate.sh blocked session end on 4 orthogonal prior-session ACTIVE plans; a per-session waiver could not clear them."
decision_needed: "Fix product-acceptance-gate.sh so an exempt-but-UI-refused plan can still be cleared by a fresh per-session waiver (re-order the checks), OR triage the 4 stale ACTIVE plans (close/defer/de-exempt), OR accept the recurring retry-guard downgrade as the de-facto escape?"
predicted_downstream:
  - adapters/claude-code/hooks/product-acceptance-gate.sh
  - docs/plans/conv-tree-project-root-topology.md
  - docs/plans/cross-machine-workstreams-coordination-2026-06-04.md
  - docs/plans/file-lifecycle-redesign.md
---

# product-acceptance-gate waiver path is structurally unreachable for exempt+UI plans

## What was discovered

`product-acceptance-gate.sh` (Stop hook, position 4) evaluates each ACTIVE plan in this
order (`adapters/claude-code/hooks/product-acceptance-gate.sh:828-865`):

1. **Exemption check** (`:828`). For a plan with `acceptance-exempt: true` + substantive
   reason, `check_exemption` returns `EXEMPT_OK`.
2. Inside the `EXEMPT_OK` branch, the **2026-06-09 user-facing-surface refusal** (`:835`)
   runs: if `plan_declares_ui_surface` matches `src/app/|src/components/|page.tsx|*-ui/|/web/`
   in the plan's declared files, it appends a BLOCKER and **`continue`s at `:837`**.
3. The **per-session waiver check** is at `:851` — i.e. *after* the `continue`.

So for an `acceptance-exempt: true` plan that also declares a `*-ui/` (or `/web/`, `src/app/`)
path, the gate blocks at step 2 and never reaches the waiver check at step 3. **A fresh,
correctly-named, non-empty per-session waiver cannot clear such a plan** — the waiver path is
only reachable for `NOT_EXEMPT` plans (`:848` falls through to `:851`).

Confirmed live (2026-06-10, by replaying the gate's exact section-scoped awk+grep against all
8 ACTIVE plans): **3** plans are refused — `conv-tree-project-root-topology`,
`cross-machine-workstreams-coordination-2026-06-04`, `file-lifecycle-redesign`.
(An earlier whole-file grep overcounted `plan-lifecycle-redesign`; its `-ui/` mention is body
prose outside the scanned sections, so it passes as exempt.) Correctly-formed waivers under
`.claude/state/acceptance-waiver-<slug>-<ts>.txt` (verified matching the gate's
`acceptance-waiver-${slug}-*.txt` glob and `-newermt '1 hour ago'` freshness) were written and
the gate still blocked — because it never consults them for these plans.

## Why it matters

The 2026-06-09 refusal exists for a good reason: a genuine **product** UI plan (`src/app/`,
`src/components/`) must not switch off the one adversarial gate that opens the running product.
But the refusal cannot distinguish a product UI from the **harness-internal** Workstreams /
conversation-tree operator-tracker (`workstreams-ui/`, `conversation-tree-ui/`) — whose
legitimate acceptance bar is `--self-test` PASS + manual GUI verification (exactly what each
plan's `acceptance-exempt-reason` states). The net effect: these harness-internal plans become
**un-waivable**, so **every** subsequent session — including operationally-orthogonal ones that
never touch those plans — gets blocked at Stop until the plans are closed or the gate is fixed.
The only present-day escape is the `stop-hook-retry-guard.sh` downgrade-to-warn after 3
identical retries, which is a fallback, not an intended path.

## Options

A. **Re-order the gate checks** so the per-session waiver check (`:851`) runs *before* the
   exempt+UI refusal (`:835`), OR add a waiver short-circuit inside the `EXEMPT_OK` branch.
   Restores the documented per-occurrence escape for orthogonal sessions while keeping the
   refusal's intent (it still blocks an un-waived product-UI plan).
B. ~~**Narrow the `plan_declares_ui_surface` pattern** to exclude harness-internal UI paths
   (`workstreams-ui/`, `conversation-tree-ui/`).~~ **RETRACTED 2026-06-10:** the 2026-06-09
   refusal's ORIGINATING INCIDENT was precisely a Workstreams-UI plan declaring itself
   "harness-internal tooling" exempt and shipping a broken modal as "verified"
   (per `acceptance-scenarios.md` + the gate's own comment at `:260-261`). The `*-ui/`
   pattern deliberately targets these plans — the operator IS the user of the harness GUIs,
   so "no product user" does not apply. Excluding harness UI paths would un-fix that incident.
B'. **Session-attribution (the deeper class fix):** scope the gate's BLOCK to plans whose
   declared files intersect the session's own changes (commits + working tree); surface
   untouched stale plans as warnings instead (SessionStart's stale-plan surfacer already
   nags them). Same failure class as the 2026-05-17 session-wrap Signal-3 discovery
   (transitive false-fire on cross-session artifacts). Tradeoff to decide honestly: the
   all-plans block is a deliberate ratchet that makes stale plans somebody's problem;
   attribution softens that pressure. Contract change → requires an ADR.
C. **Triage the 4 stale ACTIVE plans** (close → COMPLETED / defer / remove the exemption +
   author `## Acceptance Scenarios`). Resolves today's instance but not the class; the next
   exempt+UI plan re-hits it.
D. **Accept the retry-guard downgrade** as the de-facto escape. Cheapest, but trains sessions
   to ride the downgrade — exactly the anti-pattern `testing.md` warns against.

## Recommendation

**A + C, with B' authored as an ADR for the operator's decision.** (Supersedes the original
A+B recommendation — B is retracted above.) A fixes the mechanical bug: the per-session waiver
is the designed escape valve (1h TTL, substantive justification, audit-visible, weekly-reviewed)
and no block class should be structurally un-waivable; hoist the `check_waiver` block above
`check_exemption` in the per-plan loop + add a self-test scenario (exempt+UI plan + fresh
waiver → ALLOW). C is the honest remediation the gate's own message prescribes for the 2
genuinely-GUI plans — and it is now actually executable, since the Workstreams server runs at
127.0.0.1:7733 (launched 2026-06-10); `file-lifecycle-redesign`'s refusal is more arguable
(its declared `-ui/` files are scripts under the UI directory, not GUI surface) but the plan
is 14d stale and warrants close-or-defer triage regardless. B' (session-attribution) is the
deeper class fix; it changes the gate's contract, so it ships as an ADR surfaced for decision,
not auto-applied. D alone is not acceptable.

This is a **Mechanism (hook) change** and a 4-plan triage — out of scope for an operational
"launch the server" session and not something to do unilaterally per
`~/.claude/rules/friction-reflexion.md` / `~/.claude/rules/gate-respect.md` ("when a gate is
structurally wrong, fix the gate as a normal harness-dev plan, not a per-occurrence bypass").
Surfaced here for a dedicated session.

## Decision

(pending — awaiting operator direction)

2026-07-02: superseded by ADR 058 D5 — the session-scoped work-integrity-gate (task D.2) removes the orthogonal-plan class entirely.

## Implementation log

(empty — nothing implemented this session)
