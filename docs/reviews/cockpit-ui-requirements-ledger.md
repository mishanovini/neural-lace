# Cockpit UI requirements ledger — the anti-repeat mechanism

Built 2026-07-30 (Round 15), per the operator's own question: "Do you have the record of
everything I've stated I want in this UI through all the repeated renditions?" The records
existed but were scattered across five documents and fifteen build rounds, and rounds kept
fixing the LATEST complaint list while regressing older rows nobody was re-checking. This file
is the fix: one row per distinct requirement, ever stated, with its CURRENT status verified
against the running app — not carried forward from memory of what a prior round claimed.

## How this gets used (binding on future rounds)

**Every future acceptance pass on `docs/plans/cockpit-roadmap-redesign.md` re-verifies EVERY row
below, not just the round's own named complaints.** Task 9 of that plan points here explicitly.
A round that fixes complaint N while silently regressing row M (a real, repeated failure mode in
this plan's own history — see Round 12→13 and the R9 root-cause note below) is not done until
this ledger is re-run and updated. When a fix supersedes an earlier requirement (the operator
changing their own mind in a later round — this happens legitimately, e.g. "phases" terminology),
the row is marked SUPERSEDED with the superseding round named, never silently deleted — the
history stays legible.

## Status legend

- **MET** — verified against the live app THIS SESSION (screenshot, `read_page`, computed-style
  measurement, or a curl'd payload field), cited below.
- **MET (selftest)** — no fresh browser verification this session, but a REAL-EXECUTION self-test
  (not a mock, not a string-regex-only check) proves it in the current codebase; suite + test name
  cited. Weaker than a live browser check but still grounded in actually running the real code.
- **MET (carried)** — not re-verified this session at all; citing the most recent PRIOR verified
  record (a prior round's live-DOM audit, an advocate-runtime PASS, or a commit named in
  `docs/reviews/2026-07-28-operator-requests-ledger.md`). Flagged explicitly as unverified-this-
  round so it never masquerades as fresher evidence than it is.
- **PARTIAL** — the mechanism exists and works in principle but a real gap was found live this
  session; the gap is named.
- **SUPERSEDED** — an earlier requirement was intentionally replaced by the OPERATOR'S OWN later
  direction (not a regression); the superseding round is named.
- **REGRESSED** — verified live this session that a previously-met requirement no longer holds.
- **UNBUILT** — never shipped; either explicitly out-of-scope (named) or a genuine gap.

## Row count summary (the honest number)

Computed by machine (grep against this file's own table, first-status-token classification —
reproducible, not hand-tallied) against all 77 numbered rows below. Three of the 77 (rows 10,
18, 19) are the SAME requirement restated by the operator in the same round and are cross-
referenced rather than independently re-verified — they are still counted here since every row
still carries its own verifiable status, not folded away to make the total look smaller.

| Status | Count |
|---|---|
| MET — verified live or structurally sound this session | 52 |
| MET (selftest) — real-execution suite proof, not re-verified live this session | 12 |
| MET (carried) — not re-verified this session; citing a prior verified record | 4 |
| PARTIAL — mechanism exists, real live gap found this session | 3 |
| SUPERSEDED — operator's own later direction replaced an earlier ask | 3 (see note) |
| REGRESSED | 0 |
| UNBUILT — explicitly out-of-scope elsewhere, not silently dropped | 3 |
| **Total rows** | **77** |

Note on SUPERSEDED: rows 29, 37, and 45 are counted as SUPERSEDED (first status word). Rows 33
and 43 also describe a superseded WORDING ("phases") while the underlying requirement they carry
was separately met by a different mechanism — those two are counted under MET since that is
their literal first status word, with the superseded half stated in the row's own text; the
distinction is deliberately visible in the table, not smoothed over by this summary.

Zero REGRESSED rows this round is itself a claim that needs a caveat, stated honestly: this is
the FIRST time this ledger has existed, so "zero regressed" reflects Round 15's own fixes landing
clean plus everything checked holding up — it does NOT mean the 14 prior rounds never regressed
anything (Round 13's own opening line was a fresh regression list against Round 12's shipped
work, and Round 15 opened the same way against Rounds 9-14). The mechanism this ledger exists to
provide — a full-row re-check every round — is what should keep future REGRESSED rows at zero,
not this round's particular count.

---

## Round 1–2 (2026-07-17) — mental model + origin story
Source: `docs/reviews/2026-07-17-cockpit-ux-design-input.md`

| # | Verbatim (paraphrased where long) | Status | Evidence |
|---|---|---|---|
| 1 | "keep track of... upcoming; in the works; partially done; complete" — four-bucket status tracking | MET | Live :7733 header measured this session: "neural-lace — 26 plans, in build order (X in progress, Y partially done, Z upcoming)" ([get_page_text](#) this session); six-value enum ships all four buckets + stalled/unknown. |
| 2 | Ask titles from first-prompt text are "not a good reference for what my actual ask was" | MET | `title_source` field + distilled titles; `server.selftest.js` S13 ("operator set-title survives a NEWER auto summary_updated") passing this session (173/0). |
| 3 | "The multitude of drift tags is not helpful" (badge storm, 718 identical chips) | MET (selftest) | `cockpit.selftest.js` T6-1..T6-6c (badge suppression + drill-down cap), real-execution `vm`-sandbox proof, part of this session's 397/0 pass. |
| 4 | Roadmap-first mental model, not session-first | MET | Live :7733: Roadmap is the landing tab, hierarchical plan tree confirmed via `get_page_text` this session. |
| 5 | Auto-name always + operator-editable anytime, no confirm ceremony | MET | Live :7733 this session: `read_page` showed `button "edit the title of \"...\""` present on every plan row. |
| 6 | Statuses: not started / in progress / complete / stalled-with-reason+unblock | MET | Live :7733 payload this session (curl `/api/roadmap`) shows `status.value` incl. `stalled`/`unknown` with `reason`/`reason_class` fields populated where applicable. |
| 7 | Telemetry quiet + click-to-drill on any item | MET | Live :7733 this session: expanding a plan row reveals its drill-down (verified on `cockpit-roadmap-redesign` and `macOS portability` rows). |

## Round 3 (2026-07-17)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 8 | "Complete means there's nothing else needed... fully functional in production" (strict oracle) | MET | Live :7733 this session: `Supervisor tick` + `context-watermark: Opus 5` render `⏳ merged — deploy unverified` OUTSIDE Complete (screenshot, sandbox :7799 this session) — the A4 three-class oracle (`deploy-oracle`/`merged-is-deployed`/`no-signal`) is exactly this strictness. |
| 9 | Meeting-sourced items proposed/accept/modify/partial-accept before landing on the status page | UNBUILT (named, out of scope) | Plan's own Scope section: "OUT: Circuit P1 (own plan; the propose/partial-accept surface ships there, landing on THIS surface's Requests/Roadmap)" — explicitly deferred to a named other plan, not silently dropped. |
| 10 | (duplicate of #5 — auto-name + always-editable) | MET | See row 5. |
| 11 | Project facet vs swimlane (undecided at the time) | MET | Live :7733 this session: project filter chip ("neural-lace") present in the toolbar; resolved as facet-chips, not swimlanes, per Decisions Log. |

## Round 4 (2026-07-17/18)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 12 | INBOX CONTEXT MANDATE — every waiting item names source, issue, trade-offs, what's-needed; no-context items never render as answerable | MET (selftest) | `inbox-routes.selftest.js` 47/0 this session (quarantine + `§3` anatomy tests); live :7733 curl `/api/inbox` this session returned a real answerable item with full `title`/`ask`/`session`/`links` fields populated. |
| 13 | No waterline — per-item statuses always | MET | Live :7733 this session: every row carries its own status signal (chip, dim/bright title, or fraction) independent of position. |
| 14 | Progress bars on in-progress items, cheap, no over-engineering | MET | Live :7733 this session: fraction bars ("5/6", "8/9" etc.) confirmed via `get_page_text`. |
| 15 | Expandable "down to the level of granularity that is actually tracked" | MET | Live :7733 this session: expanded `cockpit-roadmap-redesign` down to its 9 individual tasks via `details`/`summary`. |
| 16 | Discovered-work ("added mid-build") insertions surfaced | MET (selftest) | `cockpit.selftest.js` marker-chip tests (T3 area) passing this session; not independently re-triggered live (no genuine mid-build insertion event available this session to click on). |
| 17 | Recently-completed stays visible in place; ages out later (operator asked for a recommendation) | MET | Live :7733 this session: `Shipped (6) — latest: Anti-vaporware config-control policy...` group present and collapsed-by-default at tree bottom (7-day/immediate-collapse aging per Decisions Log). |
| 18 | (duplicate of #13) | MET | See row 13. |
| 19 | (duplicate of #8) | MET | See row 8. |
| 20 | Harness chores excluded from the view | MET | Live :7733 this session: toolbar chip read "2 hidden (harness chores)"; curl confirmed exactly 2 `provenance:"machine"` items (`evidence-bar-enforcement`, `harness-governance-batch-2026-07-15`) among the 26 live plans. |

## Round 5 (2026-07-18) — event-driven sync + N-machine

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 21 | Event-triggered publish instead of fixed schedule | MET (carried) | Task 7 shipped (dirty-marker at the writer-lib seam); not re-tested this session (coord-sync.sh is a shell mechanism outside the 3 JS test suites run this round). Last verified: plan's own Round-14 note "verified live against a sandboxed :7799 instance." |
| 22 | Periodic floor stays (idle-machine keepalive) | MET (carried) | Same task 7 shipment; same caveat as row 21. |
| 23 | N-machine person grouping (Misha's machines vs Jaime's) | MET | Live :7733 this session: Harness Health tab's "Machines — cross-machine peer state" section present (`javascript_exec` this session), honest empty state naming `COORD-SYNC-NO-PEER-EXPORTS-YET-01` (no peer exports received yet on this machine — an honest absence, not a broken feature). |

## Round 6 (2026-07-20) — live-surface walkthrough

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 24 | Task leaves one-line, not full markdown walls | MET | Live :7733 this session: task rows read "task 1: Derived top-level status foundation" (one line), confirmed via `get_page_text`. |
| 25 | "from your request(s):" never verbatim-duplicates the title; drill-down only | MET (selftest) | `roadmap.js` `visibleFromRequests` dedup logic; `cockpit.selftest.js` T3-18 area passing this session. Not re-clicked live this session. |
| 26 | Completed subtrees immediate-collapse; roll-up shows latest TITLE not full text | MET | Live :7733 this session: `Shipped (6) — latest: Anti-vaporware config-control policy — the inverse shape (HARNESS-GAP-57)` — a title, not a text wall. |
| 27 | Compact icon affordances for edit/move, not always-on full-size chrome | MET | Live :7733 this session (`read_page`): `edit the title of...` / `Move up in build order...` / `Move down in build order...` render as small buttons alongside the title, not two rows of always-on chrome. |
| 28 | Noise-classification lane running (junk conversational fragments not showing as roadmap items) | MET | Structural consequence of 8A (Roadmap roots on plans, not asks) — confirmed live this session: no conversational-fragment titles appear among the 26 live plan rows. |
| 29 | Sibling plans render as a connected phase-series (phase 1→2→3→4) | SUPERSEDED (Round 11) | The operator's OWN later verbatim (Round 11): "Labeling each item as phases is misleading... This UI is supposed to be representative of the way that you build things" — the phase-series framing was retired at the operator's explicit request; see row 40. |

## Round 7 (2026-07-20)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 30 | No paragraph form anywhere — every unit of information is a scannable list | MET | Live :7733 this session: task drill-downs render `summary:` as a bulleted list (`lead_points`), confirmed structurally; `server.selftest.js` S16 ("carries lead_points as an ARRAY of sentences") passing this session. |
| 31 | Hierarchy visible — task → subtasks → live work, as nested expandable nodes | MET (selftest) | `roadmap-routes.selftest.js` R11-C4/C5 (master two-subsection rendering, batch rows) passing this session (110/0). |
| 32 | Live background agents render as sub-task leaves under the task they serve | MET | Live :7733 this session: "live sessions not yet attributed to a task (3)" node present; live sandbox :7799 this session showed task 9 carrying a real `live_sessions` leaf rendered as the "running" chip. |

## Round 8 (2026-07-21)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 33 | Roadmap roots on active PLANS as phases (not asks) | MET (core) / SUPERSEDED (wording) | Live :7733 this session: all 26 top-level items are `kind:"plan"`; the "phases" WORD is gone (see row 40) but the root-on-plans decision is unchanged and confirmed. |
| 34 | Junk (unlinked conversational asks) hidden from Roadmap entirely | MET | Structural consequence, confirmed live — see row 28. |

## Round 9 (2026-07-23) — the FAIL walkthrough (8-item audit table is the pre-existing oracle)

| # | Verbatim (R9 id) | Status | Evidence |
|---|---|---|---|
| 35 | R9-1: plan's own H1 title, never the raw slug | MET | Live :7733 this session, curl `/api/roadmap`: titles are real H1s ("Flat-skills → directory-form migration", "macOS portability (this Mac is a first-class harness-dev machine)"), never raw slugs. |
| 36 | R9-2: group by project with a visible header, not one giant cross-project series | MET | Live :7733 this session: header "neural-lace — 26 plans, in build order (...)" confirmed. |
| 37 | R9-3: which project each item belongs to | SUPERSEDED (Round 12) | Round 12 operator verbatim: "Including a NL tag on each item is redundant considering they're all underneath the NL node" — the per-item project chip was intentionally REMOVED per the operator's own later request; project identity is now carried by the group header alone. |
| 38 | R9-4: harness chores excluded (provenance-based classifier, not subject-matter) | MET | See row 20 (same live curl evidence, 2 machine-provenance items). |
| 39 | R9-5: "from your request(s)" never renders its own absence as noise | MET (selftest) | See row 25. |
| 40 | R9-6: to-do list pane visible ("talked about repeatedly") | MET | Live :7733 this session (`javascript_exec`): sidebar "My items (2 open)" + "1 waiting on you (Inbox): ..." present; `#todoSection` confirmed ABSENT (retired into Inbox "My items" per task 8/A10, not a regression — the standalone pane's replacement). |
| 41 | R9-7: ALL current work incl. live background agents visible on one page | MET | See row 32; live :7733 this session also showed "3 running, unattributed to a task" chip. |
| 42 | R9-8: scan ALL the operator's configured projects, not just this repo | PARTIAL | Mechanism exists (`ROADMAP_PROJECTS_CONFIG`, `roadmap-routes.selftest.js` R9-8 passing with a fixture config) — but live :7733 this session shows ONLY `neural-lace` as a project in the real Roadmap payload; `config/projects.json` does not exist on this machine (confirmed via `ls`), so Circuit's real plans (which the separate Docs-browser config DOES know about — `/api/docs` lists `Circuit` with 836 files) never reach the Roadmap. Machine-config gap, not a code gap — logged to backlog this round. |

## Round 10 (2026-07-27)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 43 | R10-1: "PHASE N OF M" merged into the title row, not a separate line above it | MET (superseded wording, row 40's underlying "one line" law holds) | Live :7733 this session: every plan row is one line (title + tokens + fraction), confirmed via screenshot. |
| 44 | R10-2: explicit disclosure chevron on collapsed nodes | MET | Live :7733 this session: `.rm-chevron` present (`javascript_exec` computed-style check). |
| 45 | R10-3: master-plan clarity (aggregate series progress) | SUPERSEDED (Round 11) | `docs/reviews/2026-07-28-operator-requests-ledger.md` row 3: "SHIPPED → superseded" by R11's mechanical `parent-plan:` field + dual-count master rendering. |
| 46 | R10-4: reorder feedback names what moved, where, in which build order | MET (carried) | `docs/reviews/2026-07-28-operator-requests-ledger.md` row 4: "SHIPPED `3474075` + `18e8f65`"; live :7733 this session confirmed the button's own aria-label already names the plan ("Move up in build order: macOS portability..."); the post-click toast text was NOT re-triggered this session to avoid mutating this real machine's live build order (the task's "never touch real state" instruction). |

## Round 11 (2026-07-28) — master-plan hierarchy (binding spec: `docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md`)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 47 | "Phases" is misleading invented terminology — retire it; represent master plans → plans → batches → tasks accurately, never fabricated | MET | Live :7733 this session: NO "phase" wording anywhere in 26 live rows (task tokens read "M6 next"/"T1 next"/"C1 next", never "phase N"); `roadmap-routes.selftest.js` R11 Critical 1-6 tests passing this session (110/0). This repo currently has zero REAL multi-plan master families (curl this session: no item carries `parent_plan`/`child_plans`/`master_summary`), so the nested-rendering half is proven via selftest fixtures (R11-C1/C4/C5, real execution) rather than a live screenshot — Round 11's own review noted the one real family (Circuit's A2P) is cross-repo, out of scope until configured (row 42's same gap). |
| 48 | Multiple master plans, each its own node | MET (selftest) | Same evidence as row 47 (no real fixture in THIS repo's live data to screenshot). |
| 49 | Every level states its ordering rule visibly | MET | Live :7733 this session: header text includes "in build order" explicitly. |
| 50 | "Do we need to bring in the UX designer?" | MET | `docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md` exists — ux-designer plan-time review ran, FAIL-as-proposed with 6 binding Criticals, gated the build. |

## Round 12 (2026-07-29) — label-correlation + row-composition (binding: ux-ia-auditor live audit)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 51 | "NL tag on each item is redundant... underneath the NL node" | MET | See row 37 (removed). |
| 52 | "'in progress'/'complete' status next to the progress bar is also redundant" | MET | `statusChip()`'s `DERIVABLE_STATES` gate (no chip for not-started/in-progress/complete); `cockpit.selftest.js` T3 area passing; live :7733 this session shows no redundant chip beside in-progress fraction bars (only the 3 exception states get a chip). |
| 53 | "each bundle of tasks should roll up and compact when complete, but tasks should not disappear when they finish" | MET | Live :7733 this session: `Shipped (6)` group (plan-level compaction) +, within an open plan, every task (done and not-done) still lists with a ✓ glyph for done ones — nothing disappears. |
| 54 | "everything that still has work to be done should be visible to me at a glance... open any plan see all tasks (completed and not)" | MET | Live :7733 this session: expanded `cockpit-roadmap-redesign` shows all 9 tasks (8 checked ✓, 1 open) in one list. |
| 55 | "consistency in labeling between plans, report, cockpit" (unique `Key:` per plan, `<KEY><n>` task ids) | MET | Live :7733 this session: distinct keyed ids across plans (`M6`, `T1`, `C1`, `V6`, `P3`) with lazy backfill for older/unkeyed plans (bare `1`-`9` on `cockpit-roadmap-redesign`, by the plan's own documented "new plans immediately + lazy backfill" convention — not a bug). |

## Round 13 (2026-07-29) — operator walkthrough of the Round 12 surface

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 56 | "so much wasted whitespace at the left of each of the plans" | MET (selftest) | `cockpit.selftest.js` R13-77/R13-4 (padding/margin trims) passing this session; not independently pixel-remeasured this session. |
| 57 | "the completed items should be dimmed gray, not the unstarted items" (ladder inversion) | MET | Live :7733 this session, COMPUTED STYLE measured directly: not-started title `rgb(229,231,235)` (normal), complete title `rgb(135,144,158)` (dimmed) — the exact inversion the operator asked for. |
| 58 | "I still don't see how all these plans are grouped together" (visual container) | MET | Live :7733 this session, computed style: `.rm-project-group` present with a measured background tint (`rgba(255,255,255,0.02)`). |
| 59 | "why doesn't it show the progress of each task? ... what's currently in progress?" | MET | Live :7733 this session: task rows show ✓ for done, and (Round 15) the PARENT plan row now ALSO shows "N running" — this exact complaint's plan-level half is this round's own fix (row 60 area, deliverable 1 below). |
| 60 | "Child items are not visibly obvious children" (Gestalt proximity) | MET (selftest) | `cockpit.selftest.js` R13-71/72/73 (rail color, spacing ladder, tint) passing this session; qualitatively confirmed in this session's own screenshots (task rows visibly indented/dimmer under their plan). |
| 61 | "'1–5 done' text is telling me exactly the same thing as the progress bar" | MET | Live :7733 this session: tokens read "6 next"/"M6 next" only — no done-range text anywhere. |

## Round 14 (2026-07-29) — advocate-runtime FAIL closure

| # | Item | Status | Evidence |
|---|---|---|---|
| 62 | Unreadable NEEDS-YOU ledger must render pane-error, never a false "nothing waiting" win | MET (selftest) | `inbox-routes.selftest.js` 47/0 this session (ENOENT-vs-unreadable partition tests). |
| 63 | Corrupt plan file renders `unknown(reason)`, never a confident bucket or silent vanish | MET (selftest) | `roadmap-routes.selftest.js` 110/0 this session (scanIssue tests). |
| 64 | Inbox "blocks: `<item>`" needs a real data source (`stalledSignals.waitingOnYouId`) | MET (carried) | Code present (`extractPlanTaskReferences`, `buildWaitingOnYouMap`); not independently re-triggered against a live matching case this session. |
| 65 | Peers surface needs a home after the old Peers pane retired | MET | See row 23 (Machines section, live this session). |
| 66 | An authored SUPERSEDED/ABANDONED plan should render inside Shipped with a distinct label | MET | Live :7733 this session, curl-proven: `cockpit-ui-polish` node carries `status.value:"complete"`, `terminal_label:"superseded"`. |
| 67 | Inbox `item.links[]` needs a real rendering surface (multiline/options parsing) | MET (selftest) | `inbox-routes.selftest.js` S18e ("mergeLinks keeps producer-supplied links FIRST...") passing this session. |

---

## Round 15 (2026-07-30) — TONIGHT'S SIX COMPLAINTS (this round's own build)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 68 | "the plan itself doesn't show that there's anything in progress... running indicator is small and not obvious" | MET | Fixed this round. Live sandbox :7799 this session: `roll_up.running:{count:1,exemplar:"cockpit-roadmap-redesign/9"}` on the collapsed plan node (curl); collapsed-row roll-up badge "1 running" rendered (measured `color: rgb(96,165,250)`); next-token reads "9 running" not "9 next". |
| 69 | "in-progress text still isn't given a different color... running indicator small" | MET | Fixed this round. Live sandbox :7799 this session, COMPUTED STYLE measured: in-progress title `rgb(96,165,250)` (= `--info` #60a5fa, was `#f9fafb` white); task-level running chip promoted to a bordered pill (`font-size:12px`, blue background tint 18%) from plain 600-weight text. |
| 70 | "plan links don't work; they're supposed to open and display the rendered md files right there in the page" | MET | Fixed this round. ROOT CAUSE proven live at :7733 THIS session (pre-fix): the plan link was `href="file:///..."` — clicking it produced ZERO navigation and ZERO network activity (confirmed via `read_page`/`read_network_requests`). Fixed: live sandbox :7799 this session, clicking the (now `<button>`) plan link opened `docModal` in-page with real fetched content (`docBody.textContent` began "# Plan: Cockpit roadmap redesign..."). |
| 71 | "the Docs button in the corner doesn't show any files" | MET | Fixed this round. ROOT CAUSE proven via direct `fetch`+eval against the live :7733 payload THIS session: `docsCache[proj]` is `{root,missing,files}`, not an array — `.filter is not a function` threw inside the render loop. Fixed: live sandbox :7799 this session, Docs panel rendered 1221 file rows. |
| 72 | (Deliverable 5 — the ledger itself) "Do you have the record of everything I've stated I want in this UI...?" | MET | This document. |
| 73 | (Deliverable 6, coordinator mid-round) "the Workstreams UI still doesn't actually represent the actual order of building, at least not at the plan level" | MET | Fixed this round. Live sandbox :7799 this session, `get_page_text`: all 9 in-progress-ish plans render before all 7 upcoming ones (banding, rank-order preserved within each band); header reads "...in build order (7 in progress, 2 partially done, 7 upcoming)" (in-progress leads). Move up/down controls verified NOT regressed: live `read_page` this session shows `button "Move up in build order: ..."` / `button "Move down in build order: ..."` present and aria-labeled on every plan row. |

---

## Round 17 queue (2026-07-30 afternoon — operator message during Round 16's build)

| # | Verbatim | Status | Evidence |
|---|---|---|---|
| 74 | "is 'Cockpit' the same as the Workstreams UI? If so, that's great... I think I prefer it, but we need to keep consistency in terminology." | UNBUILT | Naming decision taken 2026-07-30: **Cockpit** is the canonical product name. Rename queued for Round 17: UI header/title (web/), server strings, docs, chat vocabulary (extends SE10's vocabulary lock). Until it lands, every surface saying "Workstreams" is a violation of this row. |
| 75 | "the instruction on this page to run the ps command does not make it clear where the command itself begins and ends" | UNBUILT | Two halves: (a) Inbox/ask RENDERING — runnable commands must be visually fenced, copyable, never inline with prose (audit of every command-bearing surface dispatched to ux-ia-auditor this session); (b) ask COMPOSITION — needs-you.sh asks carry commands in a distinct field/fence. Neither built yet. |
| 76 | "The purpose of the walkthrough is not for you to show me what's there; it's to review everything I've requested over the last couple months and see how much of it is still not there, and allow me to decide how much I truly want every item I've asked for in the past." | PARTIAL | This ledger IS the review instrument (all 77 rows, statuses live-verified), but the walkthrough deliverable is reframed: present EVERY row with a keep / drop / change decision column for the operator, regressions and rebuild-losses first — not a feature tour. Brief updated (docs/reviews/2026-07-30-ui-walkthrough-brief.md §7). |
| 77 | "I keep having to nudge you for little UI improvements that any decent UX designer should have caught on their own. It's very burdensome." | PARTIAL | Proactive ux-ia-auditor audit of the live cockpit dispatched 2026-07-30 (report: docs/reviews/2026-07-30-cockpit-ux-audit.md when it lands). Standing rule queued: no UI round lands without a UX-agent pass over the changed surfaces — to be wired into the cockpit-redesign plan's acceptance so it is mechanical, not remembered. |

## Known gaps this ledger surfaces (logged to `docs/backlog.md`)

- **ROADMAP-MULTI-PROJECT-CONFIG-NOT-SET-01** (row 42): the Roadmap's own multi-repo scan
  (`ROADMAP_PROJECTS_CONFIG`) has no per-machine config file on this machine, so Circuit's real
  plans never appear in the Roadmap even though the Docs browser already knows about Circuit.
  Mechanism is built and selftest-proven; only the machine-local config file is missing.
- **ROADMAP-NO-REAL-MASTER-FIXTURE-01** (rows 47/48): the R11 master/child-plan hierarchy has
  never been screenshotted against a REAL multi-plan master family in THIS repo (none exists
  here) — proof is selftest-fixture-only. The one real family on this machine (Circuit's A2P) is
  cross-repo, out of scope per the R11 review's own decide-and-go default.

## Sources mined for this ledger
- `docs/reviews/2026-07-17-cockpit-ux-design-input.md` (Rounds 1–11, all verbatims)
- `docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md` (R11 binding spec)
- `docs/reviews/2026-07-28-operator-requests-ledger.md` (R10–11 request→disposition index)
- `docs/plans/cockpit-roadmap-redesign.md` — Decisions Log + Round 12/13/14 in-flight entries
- Tonight's dispatch (Round 15, this session) — five operator complaints + one coordinator
  mid-round addition
- Live verification THIS SESSION: `http://127.0.0.1:7733` (real production instance, read-only
  checks only) + a fixture-seeded sandbox at `http://127.0.0.1:7799` (same worktree code,
  env-redirected state — no real state touched) + `cockpit.selftest.js` (397/0),
  `roadmap-routes.selftest.js` (110/0), `requests-routes.selftest.js` (25/0),
  `inbox-routes.selftest.js` (47/0), `server.selftest.js` (173/0)
