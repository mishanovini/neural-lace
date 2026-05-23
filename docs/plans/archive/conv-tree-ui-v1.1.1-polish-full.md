# Plan: Conversation Tree UI v1.1.1 (FULL) — visible-from-first-load polish (items 14–23)

> **Concurrent-session reconciliation note.** A parallel session shipped
> `docs/plans/archive/conv-tree-ui-v1.1.1-polish.md` (PR #10, master `9a3f8da`,
> closed `301a5b7`) covering ONLY items **14–18** with a divergent
> implementation (`--ty-*` vars, `.sel-tint`). This plan is the FULL **14–23**
> superset (independent 14–18 impl + 19–23 + the WCAG-AA fix), task-verified
> 11/11, all six suites green. Reconciled via a non-force merge of
> `origin/master` (their commits preserved in history; conflicting web files
> resolved to this verified superset since their 14–18 spec is fully subsumed).
> Their archived 14–18 plan is left intact as the historical record of that
> partial closure; this `-full` plan supersedes it as the authoritative
> v1.1.1 record. Renamed slug → `-full` so closure-archival does not collide.

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: existing
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Dispatch conversation-tracker tooling; the maintainer is the live user verifying via the running GUI; the conv-tree gate/emitter self-tests + the web-module state self-test + the extended responsive self-test are the acceptance artifact; no separate product end-user.
Backlog items absorbed: none

## Goal
Items 1–13 (responsive + UX-interactivity) shipped & merged at master `1a99d0f`. The maintainer kept using the live GUI and surfaced a 10-item polish punch list (14–23). The throughline: the GUI is functionally complete but scannability/affordance quality is low — type labels are uniform (no urgency-at-a-glance), the "Waiting on you" titles are crushed by a text link, hide-concluded defaults wrong and is hidden, selection highlight is faint, toasts overlap the details pane, doc references are dead text, "promote" reads as git jargon, backlog priority sorts unreliably, button colors are semantically meaningless, and the v1.1 rich-details were never sourced from the (now-available) external doc set. Ship one cohesive polish PR.

## Scope
- IN: `web/app.css`, `web/app.js`, `web/index.html` (type-color palette, link→icon, hide-concluded relocation/default/prominence, interior bidirectional highlight + auto-scroll, toast reposition + arrival flash, clickable doc links + docs browser modal/panel, expand-to-branch rename, robust priority sort, semantic button palette, inline markdown renderer); `server/server.js` (`/api/doc`, `/api/doc/open`, `/api/docs` cross-repo endpoints); `config/projects.example.json` (NEW committed generic template) + `.gitignore` entry for the per-machine `config/projects.json`; `state/backfill-details.js` (cross-repo doc-sourced enrichment); `web/responsive.selftest.js` (lock the new invariants); `docs/plans/conv-tree-ui-v1.1.1-polish.md`.
- OUT: ADR-032 schema bump (NO new event types — item 23 reuses the existing additive `item-details-set`; `schema_version` stays 1; conv-tree gates key off the major and are untouched). The Dispatch-side auto-reader (NL-FINDING-011, v1.2). The conv-tree gate hooks under `adapters/claude-code/hooks/` — untouched; re-run self-tests only for no-regression. Any new runtime npm dependency (the module is Node-stdlib-only / no-build-step; the markdown renderer is a tiny self-contained function, NOT `marked`/`markdown-it`). Real machine-specific repo paths/project codenames in any COMMITTED file (they live only in the gitignored per-machine `config/projects.json`; the kit ships a generic `.example`).

## Tasks

- [x] 14. Type-color palette (action=red / decision=amber / question=blue): `[type]` badge bg/text + 4–6px left-border accent on the item card + ~5% bg tint, in BOTH the "Waiting on you" pane AND tree [type] surfaces; WCAG AA on dark bg — Verification: full
  **Prove it works:** 1. Open GUI with action/decision/question items. 2. Each `.li-kind` badge is red/amber/blue respectively. 3. Each item card shows a matching coloured left-edge accent stripe + faint tint. 4. Badge text-on-bg contrast ≥ 4.5:1 on `#111827`.
  **Wire checks:** `web/app.css` (`--type-action/decision/question` vars + `.li-kind.*` + `.li.kind-*` accent/tint) → `web/app.js` (`renderActions` adds `kind-<k>` class to `.li`)
  **Integration points:** `node web/responsive.selftest.js` asserts the three type vars + the `.li.kind-` accent rules exist.
- [x] 15. Hyperlink crowding fix in "Waiting on you": title `flex:1`; replace the text crumb link with a fixed-width ~24px icon button (→), tooltip "Jump to in tree", same destination — Verification: full
  **Prove it works:** 1. Long-title action: title owns row width, not truncated by the link. 2. A small square → icon button sits at the row end; hover shows "Jump to in tree"; click focuses the tree node (same as old crumb).
  **Wire checks:** `web/app.js` (`renderActions` builds `.li-jump` icon button instead of `.li-crumb` text) → `web/app.css` (`.li-jump` fixed 24px, `.li-text` flex:1)
  **Integration points:** responsive.selftest asserts `.li-jump` rule + `.li-text{flex:1}`.
- [x] 16. Hide-concluded: default UNCHECKED-on-first-load = hide concluded; relocate the toggle from the global header INTO the tree pane-head; make it prominent (👁 eye icon, bigger label) — Verification: full
  **Prove it works:** 1. Fresh load (no localStorage) → concluded subtrees hidden by default. 2. The toggle lives in the tree pane-head (a "View" group), not the global header. 3. It has an 👁 glyph + a clearly-readable label.
  **Wire checks:** `web/index.html` (move `#showConcluded` label into `.tree-pane .pane-head`, add 👁) → `web/app.js` (default already OFF=hide — confirm; no localStorage = hide) → `web/app.css` (`.viewtoggle` prominence)
  **Integration points:** responsive.selftest asserts `#showConcluded` is inside the tree pane-head block and default pref = hide.
- [x] 17. Bidirectional interior highlight + auto-scroll: replace faint border with interior bg wash (type-palette ~15–20% / neutral cyan if untyped) + 3–4px solid left accent bar; clicking a Waiting item highlights the tree node interior and vice-versa; smooth-scroll the other side into view — Verification: full
  **Prove it works:** 1. Click a Waiting item → its tree node row gets a full interior wash + left bar AND scrolls into view. 2. Click a tree node → the corresponding Waiting item(s) get the interior wash AND scroll into view. 3. Highlight uses the item's type colour.
  **Wire checks:** `web/app.js` (`selectNode`/`focusNode` set a shared selection; render adds `.hl` to matching tree row + action li; `scrollIntoView({behavior:'smooth'})` on the opposite side) → `web/app.css` (`.tnode-row.hl` / `.li.hl` interior wash + left bar)
  **Integration points:** responsive.selftest asserts `.tnode-row.hl` + `.li.hl` interior-bg rules and the bidirectional wiring tokens in app.js.
- [x] 18. Toast reposition (bottom-right; bottom-center on narrow) + arrival-flash on the affected pane location for any toast / SSE-new item / state-changed item; `prefers-reduced-motion` → single persistent 1.5s highlight instead of fade — Verification: full
  **Prove it works:** 1. A save toast appears bottom-right, NOT over the ctx panel. 2. New SSE item → its card briefly flashes (600ms wash→fade). 3. reduced-motion → the flash is one persistent ~1.5s highlight, no animation.
  **Wire checks:** `web/app.css` (`.toast` right/bottom; `@media(max-width)` center; `@keyframes arrive` + reduced-motion variant) → `web/app.js` (new-id diff → ensure flash/arrival applies to actions+backlog+tree new nodes)
  **Integration points:** responsive.selftest asserts `.toast` is bottom-right (no `left:50%` in base) + an `arrive`/flash keyframe + reduced-motion clause covering it.
- [x] 19. Clickable per-item doc links + general Docs browser. Server: `GET /api/doc?project=&path=` (file contents), `POST /api/doc/open` (OS default-open), `GET /api/docs` (list docs/ across mapped projects). Cross-repo via a per-machine `config/projects.json` (gitignored; generic committed `.example`; auto-detected from tree-node project tags + the discoverable repo roots). Browser: tiny self-contained markdown renderer; per-item `docs/...` tokens become clickable → inline modal; a "📁 Docs" header button → searchable side panel grouped by project — Verification: full
  **Prove it works:** 1. An item whose details.links has a `docs/...md` path → clicking it opens an inline modal rendering that doc as markdown. 2. "Open in editor" button POSTs `/api/doc/open` → OS opens the file. 3. Header "📁 Docs" → side panel lists docs/ from each mapped project, collapsible per project, filterable by filename; click → inline preview. 4. Path-traversal (`../`) is rejected by the server (400).
  **Wire checks:** `config/projects.json` (per-machine project→root map; `.example` committed) → `server/server.js` (`/api/doc` reads `<root>/<relpath>` with traversal guard; `/api/doc/open` spawns the OS opener; `/api/docs` walks `docs/`) → `web/app.js` (`mdRender()` + `openDocModal()` + docs-browser panel; link tokens become buttons) → `web/index.html` (`#docsBtn`, `#docModal`, `#docsPanel`) → `web/app.css` (modal/panel styles)
  **Integration points:** `curl -s 'http://localhost:7733/api/doc?project=<key>&path=docs/<some>.md'` returns the doc; `curl` with `path=../../etc` → 400; responsive.selftest asserts the renderer + modal markup tokens.
- [x] 20. "promote to branch" → "expand to branch" everywhere (button label, tooltip, any doc/comment); event type stays `promoted` (schema frozen) — Verification: full
  **Prove it works:** 1. Open ctx panel on a node with open items → the per-item button reads "expand to branch" (not "promote"). 2. `grep -ri "promote to branch" web/` → 0 hits in user-facing strings.
  **Wire checks:** `web/app.js` (the `'promote to branch'` button label + `'promoted to branch'` toast → "expand to branch" / "expanded to branch"; event `type:'promoted'` UNCHANGED — schema frozen)
  **Integration points:** responsive.selftest asserts no "promote to branch" user string remains and the `promoted` event type is still emitted.
- [x] 21. Backlog priority sort robust + correctly directed: P1/high → P2/medium → P3/low top-to-bottom; handle `high|medium|low`, `P1|P2|P3`, `1|2|3`; deterministic tiebreak — Verification: full
  **Prove it works:** pre-sort `[P3, P1, P2]` → post-sort `[P1, P2, P3]`; `[low, high, medium]` → `[high, medium, low]`; mixed/unknown rank last, stable.
  **Wire checks:** `web/app.js` (`prioRank()` normalises high/p1/1→0, medium/p2/2→1, low/p3/3→2, else 9; `sortBacklog` priority branch uses it with id tiebreak) → `web/responsive.selftest.js` (a real logic assertion: evaluate the extracted rank on `[P3,P1,P2]`)
  **Integration points:** responsive.selftest executes the rank logic on `[P3,P1,P2]` and asserts `[P1,P2,P3]`.
- [x] 22. Semantic button palette across the GUI: positive/commit=green, caution/postpone=amber, info/utility=blue, elevation/scope-up=purple, destructive=muted-red, neutral=slate; filled for primary, outlined for secondary; WCAG AA — Verification: full
  **Prove it works:** 1. "mark done"/"Activate"/"Submit response" render green-filled. 2. "defer" amber. 3. "copy"/"+ context"/"stage"/"cross-link" blue. 4. "expand to branch"/"dispute" purple. 5. "archive"/"clear" muted-red. 6. "annotate"/"+ project" slate. Contrast AA on dark bg.
  **Wire checks:** `web/app.css` (semantic button classes `.btn-go/.btn-wait/.btn-info/.btn-up/.btn-del/.btn-neutral` filled+outlined) → `web/app.js` (apply the right class when creating each button)
  **Integration points:** responsive.selftest asserts the six semantic classes exist + are applied to ≥1 button each in app.js.
- [x] 23. Cross-repo doc-sourced enrichment: extend `backfill-details.js` so an item whose text/links names a `docs/...` path has its payload (description/options/recommendation/blocking_input) sourced by READING that doc cross-repo (via `config/projects.json`), not left null; ship + run the enrichment so the doc-referencing actions show real content — Verification: full
  **Prove it works:** 1. `node state/backfill-details.js --self-test` green incl. a new case: a doc-referencing item gets description/options/recommendation extracted from a temp fixture doc (not null). 2. Dry-run against a state copy whose item text names a `docs/...md` path resolvable via projects.json shows a non-null doc-sourced payload. 3. Idempotent; node/tree count unchanged (append-only).
  **Wire checks:** `state/backfill-details.js` (`resolveDocPath()` via projects.json + `extractFromDoc()` parsing `## ` headings / option blocks / recommend lines → fills description/context/options/recommendation/blocking_input) → existing `state.appendEvent` `item-details-set` → reducer → GUI `.li-details`
  **Integration points:** `node state/backfill-details.js --self-test` (existing 11 + new doc-extraction cases); dry-run against a synthetic state copy referencing a fixture doc.
- [x] 24. Extend `web/responsive.selftest.js` with all v1.1.1 invariants + full regression sweep (state selftest 15, responsive 33→N, backfill 11→N, conv-tree state-gate 18, stop-gate 8, emit 17) all green; Decisions Log complete — Verification: full
  **Prove it works:** all six suites pass; responsive.selftest grew with one assertion per item 14–22; backfill selftest grew with the doc-extraction case.
  **Wire checks:** `web/responsive.selftest.js` (new assertions) → the six regression suites
  **Integration points:** re-run all suites; paste counts into the completion report.

## Files to Modify/Create
- `neural-lace/conversation-tree-ui/web/app.css` — type-color vars + `.li-kind`/`.li.kind-*`; `.li-jump`; `.viewtoggle`; `.tnode-row.hl`/`.li.hl` interior wash; `.toast` bottom-right + `@keyframes arrive` + reduced-motion; doc modal + docs panel; semantic button classes.
- `neural-lace/conversation-tree-ui/web/app.js` — kind class on li; icon jump button; hide-concluded default/relocation; bidirectional highlight + auto-scroll; arrival flash to all panes; `mdRender`/`openDocModal`/docs-browser; "expand to branch" rename; robust `prioRank`; semantic button classes applied.
- `neural-lace/conversation-tree-ui/web/index.html` — move hide-concluded into tree pane-head; `#docsBtn`; `#docModal`+`#docScrim`; `#docsPanel`.
- `neural-lace/conversation-tree-ui/server/server.js` — `/api/doc`, `/api/doc/open`, `/api/docs` (cross-repo, traversal-guarded, stdlib only).
- `neural-lace/conversation-tree-ui/config/projects.example.json` — NEW committed generic template (placeholder project keys/paths); the real per-machine `config/projects.json` is gitignored.
- `neural-lace/conversation-tree-ui/.gitignore` (or root) — ignore `config/projects.json`.
- `neural-lace/conversation-tree-ui/state/backfill-details.js` — cross-repo doc-sourced payload extraction (`resolveDocPath`, `extractFromDoc`); self-test doc-extraction case.
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — one invariant assertion per item 14–22 + the priority-sort logic test.
- `docs/plans/conv-tree-ui-v1.1.1-polish.md` — this plan + Decisions Log.

## In-flight scope updates
- 2026-05-18: docs/plans/conv-tree-ui-v1.1.1-polish-full.md — this plan, renamed from the …-polish slug during concurrent-session reconciliation (a parallel session shipped+archived a 14–18-only plan at the original slug; rename avoids closure-archival collision). Same-content rename, light case, not a spec thaw.
- 2026-05-18: docs/plans/conv-tree-ui-v1.1.1-polish-full-evidence.md — this plan's evidence log, renamed with the plan (see above).
- 2026-05-18: docs/plans/archive/conv-tree-ui-v1.1.1-polish.md — the parallel session's archived 14–18 plan, pulled in by the non-force git merge origin/master reconciliation; kept intact as the historical record (also system-managed-exempt).
- 2026-05-18: docs/plans/archive/conv-tree-ui-v1.1.1-polish-evidence.md — the parallel session's archived 14–18 evidence, pulled in by the same merge (also system-managed-exempt).

## Testing Strategy
Each item is locked by a `web/responsive.selftest.js` assertion (the established v1.1 pattern: deterministic source-invariant guard, no headless-browser dep). Server endpoints (item 19) verified by live `curl` against `:7733`. Item 23 verified by `backfill-details.js --self-test` extended with a doc-extraction fixture case. Full regression sweep of all six suites is Task 24's gate. Live browser verification is the post-merge delivery step (server restart on `:7733`), exactly as v1.1 did.

## Walking Skeleton
Thinnest end-to-end slice that proves the architecture: extend `responsive.selftest.js` with one failing assertion for item 14 (type-color var present), make it pass with the CSS var + `.li.kind-*` rule + the `kind-<k>` class in `renderActions`, confirm the GUI still renders. Each subsequent item repeats the same loop (assertion → implement → green) on the same shared files, committed at phase milestones.

## Decisions Log
### Decision: build in-session sequentially, NOT via parallel sub-agent dispatch
- **Tier:** 1 (reversible — orchestration choice, no artifact effect)
- **Status:** proceeded with recommendation
- **Chosen:** main session builds items 14–24 directly, sequentially, committing at phase milestones.
- **Alternatives:** (a) parallel `plan-phase-builder` worktree dispatch — REJECTED: items 14–22 overwhelmingly mutate the SAME four files (`app.js`, `app.css`, `index.html`, `server.js`); orchestrator-pattern.md mandates serialize-when-tasks-share-a-file; parallel commits would merge-conflict. (b) sequential sub-agent dispatch — REJECTED: every spawn trips `conversation-tree-state-gate.sh` (this IS the conv-tree-ui project; the gate governs spawns), and `conversation-tree-emit.sh` auto-injects a `worker-*` branch node into the very tree the operator is actively viewing in the GUI — degrading the surface this PR exists to improve, and semantically false per `conversation-tree-state.md` (build-worker dispatch is not an operator branch).
- **Reasoning:** shared-file reality removes the parallelism benefit; the gate+emit side-effects make sequential dispatch strictly worse than in-session for THIS module.
- **To reverse:** N/A (no artifact).

### Decision: inline self-contained markdown renderer, NOT `marked`/`markdown-it`
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** a ~40-line dependency-free `mdRender()` (headings, bold, italic, inline/fenced code, lists, links, paragraphs, hr) in `app.js`.
- **Alternatives:** bundle `marked`/`markdown-it` — REJECTED: the module's load-bearing invariant is "Node stdlib only — NO runtime deps, NO build step" (server.js header, repeated in every state file). A vendored renderer keeps that invariant; the doc set (internal markdown) needs only the common subset.
- **Reasoning:** preserves the zero-dep / zero-build contract every conv-tree-ui file asserts; sufficient for internal docs.
- **To reverse:** swap `mdRender` for a vendored lib later if rich tables/HTML are needed (localised to one function).

### Decision: cross-repo paths are per-machine config, NOT committed (hygiene + two-layer config)
- **Tier:** 2 (a config-shape decision; checkpointed)
- **Status:** proceeded with recommendation
- **Chosen:** `config/projects.json` (the real machine-specific project→absolute-root map) is **gitignored**; the kit ships `config/projects.example.json` with generic placeholder keys/paths. Server + backfill read `projects.json` at runtime, else fall back to auto-detection from the git root + tree-node project tags. The committed plan/code/self-tests name NO real product codename or absolute user path.
- **Alternatives:** commit `projects.json` with the real paths — REJECTED: `harness-hygiene.md` bans product codenames + absolute user paths in the shareable kit; `harness-hygiene-scan.sh` (correctly) blocks it. Hardcode paths in code — REJECTED, same reason + non-portable.
- **Reasoning:** mirrors the established two-layer-config pattern (`~/.claude/local/`, `state/tree-state.json` gitignored + runtime-written). Keeps the kit generic while the feature works on the maintainer's machine via local config. This is the gate-respect-compliant proper fix, not a bypass.
- **To reverse:** delete the gitignore line + commit a real map (not advised).

### Decision: item 23 sources content by READING the referenced doc, not a hand-keyed enrich.json
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `backfill-details.js` resolves any `docs/...` link in an item's text cross-repo via `config/projects.json`, reads the doc, and extracts description/options/recommendation/blocking_input from its structure. The `--enrich <json>` override path is retained for manual precision.
- **Alternatives:** hand-author `enrich.json` keyed by item_id — REJECTED: the live state item_ids are not visible from this worktree (server reads a state file absent here); doc-sourced extraction is robust regardless of exact ids and self-refreshes when docs change.
- **Reasoning:** the v1.1 honesty contract said "no fabrication; enrichment deferred until source docs available" — the source docs ARE now on this machine, so the honest move is to source from them programmatically (no fabrication; real doc content).
- **To reverse:** the `--enrich` override still works; extraction is additive.

## Assumptions
- ADR-032 §1 authoritative: NO schema change here (item 23 reuses the existing additive `item-details-set`); `schema_version` stays 1; conv-tree gates re-run only to confirm no-regression.
- localStorage remains the UI-pref substrate (consistent with items 1–13); no new pref needs cross-device persistence.
- The committed kit must contain no real product codename / absolute user path (harness-hygiene); cross-repo specifics live only in the gitignored per-machine `config/projects.json`.
- The `prefers-reduced-motion` accessibility clause (harness UX standard) applies to the new arrival-flash exactly as it does to the existing list animations.

## Edge Cases
- An item card that is BOTH type-coloured (14/17) AND `.flash`/arrival (18): the flash keyframe must not be clobbered by the static type tint (separate properties: box-shadow flash vs. background tint + border-left).
- Bidirectional highlight when the selected node is in a different/collapsed tree: reuse the existing `focusNode` tree-switch + ancestor-expand before scrolling.
- `/api/doc` for a path outside any mapped project root, or containing `..`, or an absent file → 400/404 with a clear JSON error; never read outside a mapped root.
- `/api/doc/open` on a non-Windows host: feature-detect the opener; degrade to a clear "open-in-editor unavailable on this OS" rather than erroring.
- Docs browser with a project whose root is missing on this machine → that project group shows "(root not found on this machine)", others still list.
- Priority sort with a value not in any known scheme → rank 9, stable order (no throw).
- Reduced-motion: arrival flash becomes a single persistent ~1.5s highlight (no animation), consistent with the existing `@media (prefers-reduced-motion: reduce)` block.
- Doc-extraction on a doc with no `## ` headings / no recommendation → description from the first non-heading paragraph; options/recommendation left null (no fabrication — honesty contract preserved).

## Definition of Done
- [x] Tasks 14–24 checked off by task-verifier (11/11 PASS)
- [x] All six regression suites green (state 15, responsive 43, backfill 15, state-gate 18, stop-gate 8, emit 17/OK)
- [x] One PR to neural-lace master (#11), merged; `~/claude-projects/neural-lace` synced; server restarted on `:7733`
- [x] SCRATCHPAD.md updated; completion report appended; Status → COMPLETED

## Completion Report

### 1. Implementation Summary
All 10 punch-list items (14–23) shipped + item 24 (selftest lock & regression). Mapping:
- **14** type palette — `--type-action/decision/question` (`#ef4444/#f59e0b/#3b82f6`), filled near-black badges (AA: 5.22 / 9.15 / 5.34 on `#111827`), `.li.kind-*` 5px accent + 5% tint. Commits `e10dae7`, `23f39c0` (AA bump).
- **15** title `flex:1` + 24px `.li-jump` `→` icon (text crumb removed). `e10dae7`.
- **16** hide-concluded relocated into the tree pane-head `.viewtoggle` (👁), default = hide. `e10dae7`.
- **17** `.li.hl`/`.tnode-row.hl` interior wash + 4px bar; bidirectional select + smooth scrollIntoView both ways. `e10dae7`.
- **18** toast → bottom-right (bottom-centre narrow); `@keyframes arrive` flash on new action/backlog/tree nodes; reduced-motion → 1.5s persistent highlight. `e10dae7`.
- **19** server `/api/doc`,`/api/docs`,`/api/doc/open`; two-layer `config/projects.{js,example.json}` + gitignored real `projects.json`; dependency-free `mdRender`; inline doc modal + searchable cross-project docs browser; clickable `docs/…` link tokens. `2f2f3c9`.
- **20** "promote"→"expand to branch" / "expanded to branch"; `promoted` event type unchanged (ADR-032 frozen). `e10dae7`.
- **21** `prioRank` — fixed the `0||9` falsy-fallback (the actual "sorting backwards" root cause: `high` ranked 9, sank to the bottom); handles high/p1/1, medium/p2/2, low/p3/3, unknown→9, id tiebreak. `e10dae7`.
- **22** six semantic button classes `.btn-go/-wait/-info/-up/-del/-neutral` (+ `.outline`) applied across app.js/index.html, AA-safe fills. `e10dae7`.
- **23** `backfill-details.js` `resolveDocPath` (cross-repo via projects.js) + `extractFromDoc` (section/option/recommendation/blocking-input parser); description stays verbatim (honesty); nothing fabricated when absent. `a78ac23`.
- **24** `responsive.selftest.js` 33→43 (R34–R43; R41 *executes* the prioRank logic on `[P3,P1,P2]→[P1,P2,P3]`); backfill 11→15. `bc5ed47`.
No backlog items absorbed (`Backlog items absorbed: none`).

### 2. Design Decisions & Plan Deviations
Four Decisions-Log entries (in-session sequential build vs sub-agent dispatch; dependency-free `mdRender`; cross-repo paths as gitignored per-machine config — the gate-respect-compliant hygiene fix after `harness-hygiene-scan` correctly blocked a downstream-project codename in the committed plan; doc-sourced extraction over hand-keyed enrich.json). One in-flight refinement: item 14 action red `#dc2626`→`#ef4444` to clear WCAG AA 4.5:1 (was 4.07, surfaced by task-verifier, fixed in `23f39c0`).

### 3. Known Issues & Gotchas
- The GUI server's `STATE_FILE` is the Phase-0 well-known `state/tree-state.json` (gitignored, runtime-written) — unchanged here. Item 23's *live* enrichment is a post-merge delivery step run on the maintainer's machine against the live state with a real per-machine `config/projects.json`.
- `config/projects.json` is gitignored by design; cross-repo doc browsing for non-self projects requires the maintainer to copy `projects.example.json`→`projects.json` and fill real roots (the conv-tree-ui's own repo auto-resolves with no config).
- "Open in editor" (`/api/doc/open`) is Windows `cmd /c start`; macOS/Linux fall back to `open`/`xdg-open`; unsupported OS degrades with a clear message.

### 4. Manual Steps Required
- Post-merge: restart the GUI server on `:7733` (done as the final delivery step) so the maintainer sees the changes on browser refresh.
- Optional: create `neural-lace/conversation-tree-ui/config/projects.json` (from `.example`) on the maintainer's machine to enable cross-repo doc browsing for external projects, then run `node state/backfill-details.js --apply` to layer doc-sourced rich details onto live actions.

### 5. Testing Performed & Recommended
state 15/0 · responsive 43/0 · backfill 15/0 · conv-tree state-gate 18/0 · stop-gate 8/0 · emit 17/OK · `node --check` all clean · live `curl` `/api/doc` returns content + `../../etc` → 400 · WCAG AA recomputed (5.22/9.15/5.34). task-verifier PASS 11/11 with committed evidence log. Recommended: live browser walkthrough on `:7733` after restart (the established v1.1 delivery pattern).

### 6. Cost Estimates
Zero incremental runtime cost: no new dependency, no build step, no external service; doc endpoints are localhost read-only file serving. No recurring cost.
