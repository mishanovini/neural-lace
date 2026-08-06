# Plan: Requests tab shows nothing — amendment-candidate classification is dead in production
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 2
rung: 3
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: mishanovini
target-completion-date: 2026-07-30
prd-ref: n/a — urgent operator-facing defect fix, direct chat mandate 2026-07-30
ask-id: ask-auto-69752570c1d63e96

## Goal
Operator report (verbatim, 2026-07-30): "The Requests tab still isn't showing much of
anything. I've made tons of requests that aren't showing up at all." PROVEN root cause
(this plan's own diagnosis, verified against the live `~/.claude/state/ask-registry.jsonl`
and this machine's real session transcripts):

1. `pl_ask_id_for_session` (hooks/lib/progress-log-lib.sh, consumed by
   hooks/workstreams-read.sh) derives `ask_id` 1:1 from `session_id` for a session's
   WHOLE LIFETIME, including across resumes. A long-running session therefore files
   every substantively different later request as a pending `amendment_candidate` of
   its FIRST ask, forever — 114 real candidates on this machine, ALL but a handful
   attributed to the session's opening prompt ("Please connect to gh and download the
   latest copy of Neural Lace").
2. The async LLM classifier meant to sort these (`ask-registry.sh`'s
   `_ar_classify_candidate_text`, `env -u CLAUDECODE claude --model haiku -p ...`) is
   PROVEN dead in production: invoked from a hook running inside an already-live
   Claude Code session, it does not fail fast — it HANGS until the 20s
   `nl_run_bounded` bound kills it (reproduced directly: `timeout 25 env -u
   CLAUDECODE claude --model haiku -p "..." </dev/null` -> rc=124). Zero of the 114
   real candidates captured 2026-07-28..30 ever got a `candidate_classified` verdict.
   The lane's own self-tests never caught this because they inject a FAKE
   `_AR_CLASSIFY_CMD` instead of ever shelling out to the real `claude` binary.
3. EVEN classified candidates would still be invisible: `workstreams-ui/server/
   requests-routes.js`'s registry fold never read `candidate_classified` records at
   all — it only ever consulted the permanently-`pending` birth record's own
   `classification` field, and rendered a content-free generic placeholder
   ("possible amendment captured (not yet classified)") for every amendment event
   regardless.

## User-facing Outcome
The operator opens the Requests tab and sees their own actual recent requests, with
REAL text, as distinct rows — not a stale 2-3-item list from days/weeks ago while
dozens of real requests sit invisible. Demonstrated end-to-end against a REPAIRED
COPY of the live registry: `before=3` visible top-level requests (`record_type:
"created"`), `after=35` after running the backfill script for real, verified both via
the raw `/api/requests` JSON payload and visually in a sandboxed cockpit instance
(`CTREE_PORT=7799`, never the orchestrator's `:7733`).

## Scope
- IN: a deterministic (no model call, no hang risk) amendment/noise/new-topic
  classifier that resolves an operator prompt's REAL text from its own Claude Code
  session transcript and either classifies it against its parent ask or PROMOTES it
  into its own new top-level ask when it is substantively unrelated.
- IN: fixing `requests-routes.js` to actually read `candidate_classified` records and
  render resolved real text instead of a generic placeholder.
- IN: a one-shot, idempotent, `--dry-run`-default backfill script that runs the new
  classifier retroactively against the 114 existing stuck-pending candidates.
- OUT: fixing the underlying LLM-classifier hang itself (a Claude Code CLI nested-
  session-guard behavior, not something fixable from this repo) — the LLM lane is left
  wired as a secondary attempt for the day that's fixed elsewhere, but is no longer
  load-bearing.
- OUT: the pre-existing, independently-reproduced-on-HEAD `_ar_strip_markdown`/
  `cmd_amend`/`cmd_set_deadline`/`sla`-classification self-test failures (5 of them,
  proven present before this plan's changes via a HEAD-vs-modified self-test diff) —
  filed via `nl-issue.sh`, not fixed here (unrelated defect class).
- OUT: the `/api/requests/amend/detach` endpoint's pre-existing verb-name mismatch
  (client posts `event_ts` to a `detach-amendment` verb that does not exist;
  ask-registry.sh's real verb is `detach-candidate --candidate-id`) — a separate,
  already-documented "HONEST LIMITATION" in requests.js predating this plan; noted in
  `docs/backlog.md`, not fixed here (the Detach button was already non-functional;
  this plan does not make it worse, and fixing it does not block the visibility fix).

## Tasks
- [x] 1. Diagnose the root cause (session-to-ask 1:1 derivation + dead LLM classifier
  + unread candidate_classified records), build the deterministic resolver +
  classifier + promotion mechanism, fix the UI read path, build the backfill script,
  and demonstrate before/after against a real registry copy.
  **Verification: full**
  **Prove it works:**
    1. `cp ~/.claude/state/ask-registry.jsonl <tmp>/state/` (a real copy of the live,
       damaged registry).
    2. `ASK_REGISTRY_STATE_DIR=<tmp>/state bash adapters/claude-code/scripts/
       backfill-classify-amendment-candidates.sh --dry-run` reports the projected
       classify/promote decisions with zero changes on disk.
    3. `ASK_REGISTRY_STATE_DIR=<tmp>/state bash adapters/claude-code/scripts/
       backfill-classify-amendment-candidates.sh --apply` — before=3, after=35
       visible top-level (`record_type:"created"`) requests.
    4. `CTREE_PORT=7799 ASK_REGISTRY_STATE_DIR=<tmp>/state node
       neural-lace/workstreams-ui/server/server.js` — `curl
       127.0.0.1:7799/api/requests` returns 35+ open+closed items with real operator
       text as their titles (e.g. "Why did the green line items change to purple?",
       "I want Claude to clean up the organization of the dev/claude folders on all
       my computers.", "Who the hell gave you a standing instruction not to dispatch
       agents unless I request it?") — verified both via the raw JSON and visually
       in the Browser pane's rendered Requests tab.
  **Wire checks:**
    `hooks/workstreams-read.sh` (`_ask_capture_candidate`) → `scripts/ask-registry.sh`
    (`cmd_capture_candidate` → `_ar_async_deterministic_classify_candidate`) →
    `neural-lace/workstreams-ui/server/verbatim-resolver.js` (`classify` CLI command)
    → `scripts/ask-registry.sh` (`_ar_append_record` / `cmd_register`) →
    `~/.claude/state/ask-registry.jsonl` → `neural-lace/workstreams-ui/server/
    requests-routes.js` (`foldRegistryForRequests`, `resolveCandidateText`) →
    `neural-lace/workstreams-ui/web/requests.js` (`timelineEventNode`).
  **Integration points:**
    - `ask-registry.sh capture-candidate` → deterministic classifier: verified live
      via `manual-test.sh` (real subprocess, real background job, real registry
      writes) — an "amendment"-overlap candidate and a substantively-unrelated
      candidate resolved and classified/promoted correctly within ~1s.
    - `verbatim-resolver.js classify` ↔ `ask-registry.sh`: verified via
      `ask-registry.sh --self-test` Scenarios R5-R8 (real fixture transcript, no
      fake `_AR_CLASSIFY_CMD` seam) and `backfill-classify-amendment-candidates.sh
      --self-test` Scenarios 1-5.
    - `requests-routes.js` ↔ `verbatim-resolver.js`: verified via
      `requests-routes.selftest.js` Scenarios T1-T5 (real fixture transcript file on
      disk, real resolution, real `candidate_promoted` timeline event + a real
      separate top-level spun-off item).
    - Live curl against a real sandboxed server instance (`curl
      127.0.0.1:7799/api/requests`) against the REPAIRED copy of the real, live,
      damaged production registry — see Prove-it-works step 4.

## Files to Modify/Create
- `neural-lace/workstreams-ui/server/verbatim-resolver.js` — new: resolves a
  `verbatim_ref` pointer to real operator text from its Claude Code session
  transcript (timestamp-nearest matching, ordinal fallback/tiebreak), plus the
  deterministic amendment/noise/new-topic classifier. Dual-purpose: `require()`-able
  module AND a `resolve`/`classify` CLI (create)
- `neural-lace/workstreams-ui/server/verbatim-resolver.selftest.js` — new:
  24-assertion self-test (create)
- `neural-lace/workstreams-ui/server/requests-routes.js` — reads
  `candidate_classified` records (previously silently ignored), resolves + renders
  real candidate text, adds the `candidate_promoted` timeline event type (modify)
- `neural-lace/workstreams-ui/server/requests-routes.selftest.js` — 6 new
  assertions (T1-T5) proving the read-path fix against a real fixture transcript
  (modify)
- `neural-lace/workstreams-ui/web/requests.js` — renders a "open the new request"
  link for `candidate_promoted` timeline events (modify)
- `adapters/claude-code/scripts/ask-registry.sh` — `_AR_VALID_CLASSIFICATIONS` gains
  `promoted`; new `_ar_resolver_cli_path` / `_ar_async_deterministic_classify_candidate`
  (wired unconditionally into `cmd_capture_candidate`, no `ASK_SUMMARIZER` gate); new
  read-only `heuristic-summarize` verb (`cmd_heuristic_summarize`); 6 new self-test
  scenarios (R5-R8, J2) (modify)
- `adapters/claude-code/scripts/backfill-classify-amendment-candidates.sh` — new:
  one-shot, idempotent, `--dry-run`-default backfill for the 114 already-stuck
  candidates, plus `--apply`/`--limit`/`--self-test` (create)

## Assumptions
- The registry's own append-only, never-store-raw-text design (ask-registry.sh's
  documented invariant) is correct and should be preserved — resolution happens
  transiently, on read, from the transcript, never persisted back into the registry.
- Real Claude Code session transcripts (`~/.claude/projects/<proj>/<session>.jsonl`)
  are stable enough in shape (`type`, `isSidechain`, `message.role`, `message.content`)
  to resolve against; validated directly against 114 real production records (0-1s
  timestamp deltas) before relying on it.
- A candidate whose resolved text is a harness-injected synthetic marker
  (`<task-notification>`, `<system-reminder>`, compact-continuation summaries) is
  never a genuine operator request and should classify `noise` unconditionally —
  PROVEN necessary: 78 of 116 real live candidates resolved to exactly this shape.
- Lexical (Jaccard-style, stopword-filtered) overlap between a candidate's resolved
  text and its parent ask's resolved/stored text is an adequate, honest, conservative
  proxy for "is this a new topic" — imperfect (a short contextual follow-up with zero
  shared vocabulary gets promoted rather than filed as an amendment), but the
  operator's stated problem is invisibility, and surfacing a borderline case as its
  own small request is strictly better than the prior 100%-invisible baseline.

## Edge Cases
- Unresolvable `verbatim_ref` (missing transcript, timestamp out of the 10s
  tolerance, ordinal out of range) → classifier leaves the candidate pending, no
  fabrication (ask-registry.sh Scenario R8; backfill self-test Scenario 2's
  `cand-bc-unresolvable`).
- A same-wall-clock-second burst of several real prompts (this repo's capture
  timestamps have 1-second resolution) → nearest-timestamp ties are broken by the
  ref's own ordinal, not first-found-in-array (verbatim-resolver.selftest.js's
  dedicated tie-break scenario; discovered via a real manual-test timing collision).
- A growing, multi-megabyte transcript file read repeatedly by a polled UI endpoint
  → mtime+size-keyed in-process cache in `verbatim-resolver.js`, re-read only when
  the file actually changed.
- A promoted candidate's new ask must still carry a resolvable `verbatim_ref` so its
  OWN drilldown/title work identically to any other ask — the same ref is passed
  through to `register`, never re-derived.
- Legacy/fixture `amendment_candidate` records lacking `candidate_id` (predates this
  plan) → `requests-routes.js`'s fold falls back to a ts-keyed key rather than
  colliding all such records into one entry.

## Testing Strategy
- `neural-lace/workstreams-ui/server/verbatim-resolver.selftest.js`: 29/29 (resolution,
  cache invalidation, tie-break, classification, synthetic-content guard, CLI).
- `neural-lace/workstreams-ui/server/requests-routes.selftest.js`: 36/36 (30
  pre-existing baseline unchanged + 6 new T1-T5 assertions).
- `neural-lace/workstreams-ui/server/server.selftest.js`: 176/176 (baseline,
  unchanged).
- `neural-lace/workstreams-ui/web/cockpit.selftest.js`: 496/496 (baseline,
  unchanged).
- `neural-lace/workstreams-ui/server/roadmap-routes.selftest.js`: 113/113 (baseline,
  unchanged).
- `neural-lace/workstreams-ui/server/inbox-routes.selftest.js`: 47/47 (baseline,
  unchanged).
- `adapters/claude-code/scripts/ask-registry.sh --self-test`: 105 passed / 5 failed —
  the 5 failures PROVEN pre-existing (reproduced identically against `git show
  HEAD:...ask-registry.sh` before any change in this plan) and unrelated
  (`_ar_strip_markdown`, `cmd_amend`, `cmd_set_deadline`, `sla` classification x2);
  filed via `nl-issue.sh`, not fixed here. Run on BOTH `/bin/bash` (3.2.57) and
  `/opt/homebrew/bin/bash` (5.3.15), sequentially — identical 103/5 on both.
- `adapters/claude-code/scripts/backfill-classify-amendment-candidates.sh
  --self-test`: 12/12 on both bash binaries.
- Live acceptance: backfill `--dry-run` then `--apply` against a real COPY of the
  live, damaged `~/.claude/state/ask-registry.jsonl` (before=3, after=35 visible
  top-level requests), a real sandboxed `server.js` instance on `CTREE_PORT=7799`
  (never the orchestrator's `:7733`), `curl 127.0.0.1:7799/api/requests` returning
  real operator text, and a Browser-pane visual check of the rendered Requests tab.

## Acceptance Scenarios
1. Operator opens the Requests tab on a machine whose registry has accumulated
   pending amendment candidates from a long-running session.
   1.1. The tab shows an "Open (N)" section where N reflects the operator's actual
        distinct recent requests, not a stale 2-3-item list.
   1.2. Each row's title is the operator's own real words (or a close paraphrase),
        never a generic "amendment captured" placeholder and never empty.
   1.3. A request that is a short conversational aside (an ack, a background-task
        notification) does not appear as a noisy, content-free top-level row.

## Decisions Log
- D1 (2026-07-30, Tier 2 — reversible via a later record_type, not re-litigated
  here): the LLM classify lane is left WIRED but no longer load-bearing, rather than
  removed. Rationale: removing it is a larger, separately-reviewable call (it is
  extensively self-tested/documented infrastructure); leaving it as a secondary
  attempt costs nothing (deterministic path runs first and virtually always
  decides) and preserves the option if the CLI's nested-session-guard bug is ever
  fixed elsewhere. Reversible: delete the `ASK_SUMMARIZER` branch in
  `cmd_capture_candidate` in one commit if a future review disagrees.
- D2 (2026-07-30, Tier 2): resolution happens ON READ (transiently, never
  persisted) rather than backfilling raw text into the registry itself.
  Rationale: preserves ask-registry.sh's own long-standing, explicitly documented
  design invariant ("transcript ref + minted candidate_id, NEVER the raw text — the
  registry stays small"); Chesterton's Fence — that decision predates this plan and
  was not this plan's call to reverse.
- D3 (2026-07-30, Tier 2): synthetic harness-injected content (task-notifications,
  system reminders) is force-classified `noise`, never run through the normal
  overlap decision. Rationale: PROVEN necessary against real data (78 of 116 live
  candidates were exactly this shape); without the guard they would each get
  "promoted" into their own garbled top-level request, trading one defect
  (invisibility) for another (noise flood).

## Definition of Done
- [x] All tasks checked off
- [x] All tests pass (see Testing Strategy)
- [x] Linting/formatting clean (no linter configured for these directories beyond
  the self-tests themselves)
- [x] SCRATCHPAD.md updated with final state
- [x] Completion report appended to this plan file

## Completion report
Diagnosed, built, self-tested (see Testing Strategy), reviewed (three harness-reviewer
passes, all PASS after fixing the first pass's 3 Major findings — see review records
below), and demonstrated live against a real copy of the operator's own damaged
registry (before=3, after=35 visible top-level requests, final calibration after the
promotion-threshold fix). Commits (worktree `agent-a465831e5b8168bdc`):
- `84d0684` — this governing plan.
- `fdd433a` — the fix itself (verbatim-resolver.js, ask-registry.sh, backfill script,
  requests-routes.js/requests.js, manifest.json addendum, 3 review records).

Review records: `docs/reviews/records/2026-07-30-harness-change-review-05284b04.json`
(ask-registry.sh + backfill, opus CONDITIONAL-PASS → fixed → haiku PASS),
`docs/reviews/records/2026-07-30-harness-change-review-28112fca.json`
(requests-routes.js + requests.js, haiku PASS),
`docs/reviews/records/2026-07-30-harness-change-review-61174097.json`
(verbatim-resolver.js, haiku PASS).
