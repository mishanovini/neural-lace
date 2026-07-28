# Operator requests ledger — cockpit redesign rounds 10–11 + estate program kickoff (2026-07-27/28)

Operator-requested record (2026-07-28: "document all the requests that I made to you today
surrounding this and what you've done about them so far — I want to come back to this in the
future"). Verbatim sources: docs/reviews/2026-07-17-cockpit-ux-design-input.md (Rounds 10–11
carry the full quotes); this file is the request→disposition index, not a re-quote.

## Requests and dispositions

| # | Request (round/source) | What was done | State | Verify at |
|---|---|---|---|---|
| 1 | Phase label shouldn't sit above the title like a child item — one line per phase (R10) | "Phase N of M" merged into the title row | SHIPPED `3474075` | :7733 tree rows |
| 2 | Make expandability obvious (R10) | Disclosure chevrons on every expandable row, rotate on open | SHIPPED `3474075` | any tree row |
| 3 | What are these phases part of? Master sequence unclear (R10) | Interim: per-project aggregate progress header; superseded by #6 | SHIPPED `3474075` → superseded | group headers |
| 4 | Reorder button did something unexplained; should I even be allowed? (R10) | Feedback now names what moved, where, in whose build order; edge cases named. Allowed = yes: it's the round-2 "intended build order" control, now sibling-list-scoped (R11) | SHIPPED `3474075` + `18e8f65` | move ↑/↓ toast |
| 5 | "Phases" is misleading invented terminology — kill it (R11) | Sibling-plan "phase" labeling retired surface-wide (rows read "#N of M"); "Phase" remains ONLY where a plan file's own `###` heading says it | SHIPPED `18e8f65` | tree rows vs batch rows |
| 6 | Represent the REAL hierarchy: master plans → plans → batches → tasks; multiple masters, each its own node; don't make things up (R11) | Verified real practice against plan files; made mechanical: `parent-plan:` header field, batch derivation (verbatim `###` headings or contiguous letter-runs, never title text), master nodes w/ dual progress counts, reference-lifecycle safety (dangling/cycle/aging), active-path default expansion, four-bucket headers in the round-1 words | SHIPPED `391ec8c` + `18e8f65` | :7733 + docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md |
| 7 | "Do we need to bring in the UX designer?" (R11) | Yes — ux-designer plan-time review ran; verdict FAIL on my draft IA with 6 binding constraints (caught 2 fabrication traps + specified the whole tree anatomy); its spec gated the build | DONE | docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md |
| 8 | "Confirm this is how you actually design/plan/build" (R11, A2P table) | Confirmed with file evidence: lettered batches + child-plan spawning are real practice; "master plan" was prose-only until #6 made it a field | ANSWERED | Round 11 record |
| 9 | Progress out of phase order "seems completely random" (R10/R11) | Two causes: (a) intended-build-order ≠ execution order (honest data, reorder is the fix); (b) REAL BUG FOUND — lettered task ids (`A1`/`B2`/`C2-3`) were silently dropped by the parser, hiding most tasks of 16+ plans; grammar fixed + pinned; harness lifecycle hook has the same hole (nl-issue filed) | SHIPPED `391ec8c` | foresight went 7→16 visible plans |
| 10 | Document today's requests for future reference (2026-07-28) | This file | SHIPPED (this commit) | here |
| 11 | Pull latest; implement the Accountable Estate Program plan (2026-07-28) | Pulled (plan @ b6faaa7, T1–T14); T1 slice (estate inventory + daily brief) dispatched under the program's WIP-1 rule | IN FLIGHT | docs/plans/accountable-estate-program-2026-07.md |

## Prior-session requests still standing (context for the comeback read)

- **Your walkthrough verdict on :7733** — the one blocker for closing cockpit-roadmap-redesign
  (T9's human component; NY-1784807155-8b40).
- **PURGE** (43 worktrees + 82 verified-merged branches — the biggest machine-load lever;
  NY-1784489893-c961) · **Defender exclusions** (admin) · **4 scheduled-task installers**.
- **Decision offered, unanswered:** bring cross-repo master linking into scope so the one real
  master/child family on this machine (Circuit A2P → marketing campaign-resubmission) groups
  visibly? (Same-project-only was the UX review's decide-and-go default.)
- **Decision offered, unanswered:** a real initiative/program grouping level above plans
  (plans declaring membership in a named initiative) — data-model addition, buildable on ask.

## Where the full trails live
- Verbatim + per-round fix tables: docs/reviews/2026-07-17-cockpit-ux-design-input.md (Rounds 1–11)
- The binding hierarchy spec: docs/reviews/2026-07-28-roadmap-hierarchy-ux-review.md
- Plan + in-flight log: docs/plans/cockpit-roadmap-redesign.md
- Estate program: docs/plans/accountable-estate-program-2026-07.md (+ its four design/review docs)
