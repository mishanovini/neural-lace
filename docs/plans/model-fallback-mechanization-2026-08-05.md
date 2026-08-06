# Plan: mechanize the Fable-to-Opus model fallback (resolver + auto-observe)
Status: ACTIVE
Execution Mode: single-session
Mode: code
Backlog items absorbed: MODEL-LIMIT-INFERENCE-BAN-2026-08-05 (partial — the ban itself
stands; this plan closes the "exhaustion is only ever marked manually" residual it
documents).
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism work (a hook, two scripts, a
settings-template wiring entry) with no user-facing UI surface; each touched file's own
`--self-test` suite is the acceptance oracle, per work-shapes/build-harness-infrastructure.md's
harness-internal carve-out — same shape as `hygiene-gate-escape-fix-2026-08-04.md`.
tier: 2
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
design-ref: n/a — small, single-session fix dispatched directly by the operator; no
design-doc cycle was run (direct-dispatch harness-safety-fix shape, same as
`hygiene-gate-escape-fix-2026-08-04.md`).

## Intended Functionality

**Outcome (operator's terms, repeated many times, 2026-08-05):** "the review agents are
supposed to default to Fable and fall back to Opus ... implement it mechanically" — a
Fable-pinned reviewer/verifier agent must automatically end up on Opus when Fable is
exhausted, WITHOUT the orchestrator having to notice the failure, diagnose it, and
hand-pick the next tier (2026-08-05 incident: this cost four turns of a falsely-reported
blocker and multiple dead agents).

**Observation:** `config/model-policy.json` already declared the `["fable","opus"]`
chain and `model-availability.sh` already had exhaustion marking + a PreToolUse
reroute-block (manifest.json id `model-availability`, added 2026-07-29), but its own
`honest_status` field named the residual: "the tier's unavailability must still be
OBSERVED and marked by whoever sees the spend-limit error ... this is not
self-detecting." This plan closes that residual plus two adjacent gaps: no pure-query
resolver a caller could use to print "use THIS model now," and dispatch-directives.sh
not printing a resolved model at all.

**Deterministic pass/fail:** all three touched suites exit 0 with zero failures
(verbatim totals in `## Testing Strategy`), including the specific pinned scenarios
named there (chain[0] fresh / within-TTL fallback / stale-TTL retry / unknown-or-empty
chain loud failure / auto-observe marks only on a verbatim error match).

**Explicitly NOT included:** Does not turn an already-in-flight dying dispatch into a
live one — a PostToolUse hook only runs after the call already failed, so the FIRST
dispatch against a freshly-exhausted tier still dies; every dispatch AFTER that one
(same session or later) is what gets rerouted. Does not add a machine-readable
budget/quota API (none exists to add — confirmed in docs/backlog.md
MODEL-LIMIT-INFERENCE-BAN-2026-08-05); exhaustion is still only ever known from a real
observed failure string, never a proactive check. Does not change `config/
manifest.json` (proposed entry reported back instead, per the dispatching instruction).
Does not touch the Workflow-inline `agent()` / `spawn_task` / cron/remote dispatch
surfaces — same pre-existing, named residual as `model-pin-gate.sh`'s PreToolUse path.

**Human dependencies:**
- None required at runtime — INTENDED (the whole point is that the orchestrator no
  longer has to notice a spend-limit failure, diagnose it, and hand-pick a fallback
  model; `--observe` records the failure automatically and `resolve` reads it back
  automatically on the next dispatch).
- A harness-reviewer PASS before this reaches master — INTENDED per
  `doctrine/review-independence.md` (a builder session must not review its own harness
  change); left for the dispatching orchestrator per `review-before-deploy.md`'s
  push-time gate, not run inside this isolated worktree.

## Goal
Close the "exhaustion is only ever marked manually" residual the `model-availability`
gate's own manifest entry names, so a Fable-pinned review/design agent that hits the
monthly spend limit results in the NEXT dispatch automatically running on Opus — no
orchestrator turn spent noticing, diagnosing, or hand-picking the fallback model.

## Scope
In scope: a pure-query multi-hop chain resolver in `model-availability.sh`; a
PostToolUse `--observe` entrypoint on `model-pin-gate.sh` that marks exhaustion ONLY
from a verbatim observed failure string; `dispatch-directives.sh` printing the resolved
model at dispatch time; the silent-inherit block message naming a resolved fallback for
known-but-unpinned agents; wiring the new hook in `settings.json.template`.
Out of scope (see "Explicitly NOT included" above and Decisions Log): editing
`config/manifest.json` directly; a machine-readable quota/budget API; the
Workflow-inline/`spawn_task`/cron dispatch surfaces a hook cannot see; retrying an
already-in-flight failed dispatch.

## Files to Modify/Create
- `adapters/claude-code/scripts/model-availability.sh` — new `resolve --agent
  <name>|--category <name>` pure-query chain walker (reuses the existing
  jq-over-model-policy.json + `cmd_is_exhausted`/`cmd_reason` idiom).
- `adapters/claude-code/hooks/model-pin-gate.sh` — new `--observe` PostToolUse
  entrypoint (auto-marks exhaustion from a REAL observed dispatch failure string, never
  an inference); silent-inherit block message now names the resolved chain[0] model for
  a known-but-unpinned agent type.
- `adapters/claude-code/scripts/dispatch-directives.sh` — prints a resolved `model:
  <tier>  # <reason>` line (role→category mapped) right after the NL-ATTRIBUTION header.
- `adapters/claude-code/settings.json.template` — wires `model-pin-gate.sh --observe` at
  PostToolUse, matcher `Task|Agent`.
- `docs/plans/model-fallback-mechanization-2026-08-05.md` — this plan (self-listing,
  same convention as the reference plan).

## Assumptions
- The operator's own repeated directive (embedded in this session's dispatch) is
  authoritative on scope: build the resolver, the auto-observation, and the
  dispatch-time print, mechanically — no assumption was needed on whether to build it.
- The other `Status: ACTIVE` plans in this repo are unrelated to this fix; this plan
  exists specifically so `scope-enforcement-gate.sh` has a correctly-scoped home for the
  commit, same convention as `hygiene-gate-escape-fix-2026-08-04.md`.
- TTL for an auto-observed exhaustion mark: the existing `cmd_mark_exhausted` default
  (4 hours) is reused unchanged, rather than a longer TTL derived from the real weekly
  reset cadence. Rationale (already documented in the existing code, reaffirmed here):
  a TTL is a guess standing in for an unobservable condition (no machine-readable limits
  source exists — confirmed in the MODEL-LIMIT-INFERENCE-BAN backlog entry), so it must
  err short. A too-long TTL keeps agents off their primary long after a weekly quota may
  have reset; a too-short one just means the next real failure re-marks it — cheap,
  self-correcting, and never a silent permanent reroute.
- `dispatch-directives.sh`'s role vocabulary (builder/verifier/reviewer/advocate) maps
  to model-policy.json's category vocabulary (build/review/design/cheap) as
  builder→build, {verifier,reviewer,advocate}→review — the only mapping consistent with
  how those roles are actually dispatched today (verifier/reviewer/advocate all
  currently dispatch review-category agents).
- `config/manifest.json` intentionally NOT edited per the dispatching instruction; the
  proposed entry update (add `PostToolUse` to `events`, revise `honest_status` — the
  "not self-detecting" claim is now false for the one error string this observes) was
  reported back to the dispatching session instead of applied here.

## Edge Cases
- Every tier in a chain marked exhausted simultaneously: `resolve` fails loudly
  (non-zero rc, distinct stderr message from the unknown-chain case) rather than
  silently picking the last-tried tier — pinned by model-availability.sh Scenario 14.
- An agent name unknown to `config/model-policy.json` (typo, or a genuinely new agent
  never triaged into the policy): `resolve --agent` falls through to category lookup,
  and if that also fails, refuses to guess (loud failure) — pinned by Scenario 13; the
  gate's block message correspondingly falls back to its pre-existing generic text
  instead of naming a specific model.
- A dispatch failure whose response text does NOT contain the verbatim spend-limit
  string (a different error, a normal completion, a non-Task/Agent tool): `--observe`
  records nothing — a miss is cheap (caught by the next real hit or the reroute block),
  a false mark is not (docs/backlog.md MODEL-LIMIT-INFERENCE-BAN-2026-08-05) — pinned by
  three distinct model-pin-gate.sh scenarios.
- Windows `jq -r` CRLF: `resolve`'s chain array, read via `jq -r '.[]'` line-by-line,
  carried a trailing `\r` on this machine, silently breaking every tier-string
  comparison downstream (`cmd_is_exhausted "$t"` never matched). Found by the RED half
  of red-green on Scenario 10 during this plan's own build, not assumed away; fixed by
  stripping `\r` on read, same discipline as the pre-existing CRLF-safe frontmatter
  helpers in this same file family.

## Testing Strategy
Each touched file's own `--self-test` suite is the oracle (harness-internal work). Every
new assertion was mutation-tested by hand: temporarily breaking the mechanism it checks,
confirming the matching scenario goes RED, then restoring and re-confirming GREEN.
Verbatim totals (all green, post-restore):
- `model-availability.sh --self-test`: 20 passed, 0 failed. New Scenarios 9-15 pin:
  chain[0] fresh → chain[0] chosen (9); chain[0] observed-exhausted within TTL →
  chain[1] chosen with a reason naming chain[0] (10); an observation older than TTL →
  chain[0] retried (11); unknown category (12) / unknown agent (13) / every tier
  exhausted (14) → loud failure, never a silent default; `resolve --agent` uses the
  agent's OWN declared chain, not a guess (15). Mutation-tested by neutering the
  exhaustion-skip `if` — Scenarios 10 and 14 correctly went RED.
- `model-pin-gate.sh --self-test`: 26 passed, 0 failed. New scenarios: a known-but-
  unpinned agent's block message names its resolved chain[0] model (mutation-tested —
  the first version of this assertion used a substring needle that was ALSO a substring
  of the generic fallback text and stayed falsely GREEN with the resolver call gutted;
  fixed to assert the unique "(resolved from ...)" clause, then re-confirmed the
  mutation now goes RED); an unknown/typo'd agent type still gets the generic text; five
  `--observe` scenarios (frontmatter-pinned tier marked on a spend-limit match,
  explicit-model tier marked, the realistic apostrophe-bearing production string
  matches, a normal completion marks nothing, an unrelated error marks nothing, a
  non-Task/Agent tool marks nothing) — mutation-tested by nulling the exhaustion pattern
  (the three "marks" scenarios correctly went RED).
- `dispatch-directives.sh --self-test`: 13 passed, 0 failed. New Scenarios S9-S11:
  role=builder resolves category "build" → `model: sonnet` (9); role=reviewer resolves
  category "review" → `model: fable` (10); fable marked exhausted in the sandbox →
  falls back to `model: opus` with a reason naming fable (11). Mutation-tested by
  breaking the role→category mapping (S9 correctly went RED, S10/S11 correctly
  unaffected — precise isolation) and by dropping the reason text (S11 correctly went
  RED).
- Settings template validated with `jq empty adapters/claude-code/settings.json.template`
  (valid JSON) after adding the new PostToolUse entry.

## Tasks
- [ ] 1. Build the chain-walking resolver, the auto-observe exhaustion recorder, the
      dispatch-directives.sh model print, and the gate block-message improvement, with
      mutation-tested self-test coverage in all three touched suites — Verification: full

**Prove it works:** `bash adapters/claude-code/scripts/model-availability.sh
--self-test`, `bash adapters/claude-code/hooks/model-pin-gate.sh --self-test`, and
`bash adapters/claude-code/scripts/dispatch-directives.sh --self-test` each exit 0 with
the verbatim totals in `## Testing Strategy` above.

**Wire checks:** `dispatch-directives.sh` → (shells out to) `model-availability.sh
resolve` → (reads) `config/model-policy.json` `categories`/`agents` chains + (reads)
`cmd_is_exhausted`'s state dir. `model-pin-gate.sh --observe` (wired PostToolUse
`Task|Agent` in `settings.json.template`) → (shells out to) `model-availability.sh
mark-exhausted` → (read back by) `model-pin-gate.sh` PreToolUse reroute block and by
`model-availability.sh resolve`.

**Integration points:** `settings.json.template`'s new PostToolUse `Task|Agent` entry —
verified structurally via `jq empty settings.json.template` (valid JSON) and by
`model-pin-gate.sh --self-test`'s `--observe` scenarios (the same code path the live
wiring invokes); no running Claude Code session was available inside this isolated
worktree to observe a real Task/Agent dispatch trigger the hook end-to-end, so this is
DONE (verified structurally, runtime not exercised) per the builder protocol's
evidence-tier discipline — the orchestrator or a follow-up session should confirm the
hook fires on a real dispatch after this lands.

## Decisions Log
- 2026-08-05: `config/manifest.json` deliberately left unedited per the dispatching
  instruction. Proposed entry update (add `PostToolUse` to the `model-availability` gate
  id's `events`; revise `honest_status` to state exhaustion is now auto-observed from a
  real dispatch failure string, not merely reroute-blocked after a human notices) was
  reported to the dispatching session rather than applied here — the orchestrator or a
  harness-reviewer pass should apply it.
- 2026-08-05: `--observe` was added as a NEW ENTRYPOINT on the EXISTING
  `model-pin-gate.sh` file rather than a separate hook file, specifically so it could
  reuse `_resolve_agent_def`/`_mpg_frontmatter_model` without a second parser (the
  operator directive's "implement it mechanically" reading applied to code reuse, not
  just behavior).
