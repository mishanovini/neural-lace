# Plan: Evidence-bar enforcement — turn the world-class standard from Pattern into Mechanism

Status: COMPLETED
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## Goal

The operator's directive (2026-07-14/16): the world-class standard must be ENFORCED, not documented —
"nothing gets built before being designed, planned, and reviewed," and the builder anti-pattern
(ending with uncommitted work) needs deterministic enforcement. Constitution §10 names undelivered
enforcement as theater. This plan lands the three gates + the merge-scan production fix.

## User-facing Outcome

The maintainer (the harness's user) gets: (1) a plan that qualifies for design review cannot go
ACTIVE without an architecture-reviewer verdict; (2) a new/modified agent file cannot land without
the seven properties + a GOLDEN CASE; (3) a worktree subagent cannot cleanly end its run with
uncommitted work; (4) the cockpit's merged-commit backfill completes once and stays cheap forever.

## Scope

IN: the three gates (plan-reviewer.sh Check 17; agent-design-gate.sh; agent-commit-gate.sh), their
self-tests, wiring (settings.json.template), manifest/schema/INDEX registration, the evidence-bar
doctrine text they enforce, and merge-scan-lib.sh's incremental cursor.
OUT: the orphaned-worktree-guard reformulation (separate, REFORMULATE-held); cockpit-v2 (own plan).

## Tasks

- [x] 1. [serial] GATE 1 (plan-reviewer.sh Check 17, architecture-review-before-build): verify the
  aa1-aa7 self-test scenarios pass (suite runs detached — ~85s/scenario), then land — Verification:
  mechanical
- [x] 2. [serial] GATE 2 (agent-design-gate.sh, agent golden-case): already 7/7 self-tested + wired +
  §10 manifest fields; land with GATE 1 — Verification: mechanical
- [x] 3. [serial] GATE 3 (agent-commit-gate.sh, SubagentStop builder-commit): built this session,
  self-test 7/7 (S5 caught + removed a pwd-fallback false-positive path), wired, §10 manifest entry,
  events enum extended (first SubagentStop hook). Land; confirm the probe log at first live fire —
  Verification: mechanical
- [x] 4. [serial] merge-scan incremental cursor (production fix): per-repo last-scanned-SHA cursor
  advanced per-batch so a tree-killed run still makes durable progress and the backfill converges;
  warm-cursor run <5s; full ms_self_test green (builder in flight) — Verification: full
- [x] 5. [serial] harness-reviewer pass over GATE 3 + the enum/schema change (GATE 1/2 were built by a
  builder against the standard; GATE 3 is orchestrator-authored and needs the independent adversarial
  pass our own doctrine requires), fold in findings — Verification: mechanical
- [x] 6. [serial] Flip the artifact-evidence-bar doctrine/manifest honest_status to Mechanism ONLY
  once gates 1-3 are landed and green — the claim must never lead the truth — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-reviewer.sh` (Check 17 + aa self-tests)
- `adapters/claude-code/hooks/agent-design-gate.sh` (new)
- `adapters/claude-code/hooks/agent-commit-gate.sh` (new)
- `adapters/claude-code/hooks/lib/merge-scan-lib.sh` (+ cursor; builder in flight)
- `adapters/claude-code/settings.json.template` (wiring)
- `adapters/claude-code/manifest.json`, `adapters/claude-code/schemas/manifest.schema.json`,
  `adapters/claude-code/scripts/manifest-check.sh`, `adapters/claude-code/doctrine/INDEX.md`
- `adapters/claude-code/doctrine/artifact-evidence-bar.md` (+ `-full`), status flip at the end

## In-flight scope updates

(none yet)

## Assumptions

- SubagentStop fires on a subagent's clean stop and exit 2 blocks with stderr fed back (platform
  docs); the gate's probe line confirms the field contract at first live fire — if cwd is absent in
  real events the gate is inert and MUST be rehosted (named in its retirement condition).
- The ~85s/scenario plan-reviewer self-test cost is environmental (process spawn cost on this
  machine), not a defect introduced here; the detached run is the workaround.
- The scope gate correctly demanded this plan; the work it covers was already built under operator
  directive and is being landed, not designed here (design review for these gates = the standard
  itself + task 5's harness-reviewer pass).

## Edge Cases

- GATE 3: session running IN a pool worktree + garbage event input → must NOT guess cwd (S5, fixed).
- GATE 3: blocked agent whose commit is itself gate-blocked → stash path always succeeds; one block
  per stop via stop_hook_active.
- GATE 3: crashes/SIGKILL/reboot fire no hook — honestly out of coverage (detection layer owns it).
- Cursor: history rewritten/cursor not an ancestor → full-scan fallback, self-heal.
- Cursor: killed mid-scan → per-batch advancement means durable progress (the load-bearing case).
- Enum widening: SubagentStop added to schema + both validator lanes; manifest-check must be GREEN.

## Acceptance Scenarios

1. A new agent .md missing a GOLDEN CASE → agent-design-gate blocks the write; adding the section
   unblocks (gate self-test S4/S5 already prove this pair).
2. A plan with a qualifying data-architecture phrase going ACTIVE without a linked architecture
   review → plan-reviewer Check 17 blocks; linking a SOUND review unblocks (aa2/aa3).
3. A worktree subagent ends dirty → blocked once with rescue commands; commits; ends clean (S1/S2).
4. Auditor cycle on a warm cursor scans only new commits in <5s (builder's timing evidence).

## Out-of-scope scenarios

- Enforcing commit discipline on crashed/killed agents (no hook fires) — detection layer, separate.
- Retro-validating the ~20 grandfathered agents against the golden-case bar (grandfathered by
  agent-design-gate design; new/modified files only).

## Closure Contract

Closes when: all three gates landed on master + manifest-check GREEN + each gate's self-test green in
CI (Hooks self-test job) + merge-scan cursor fix landed with its timing evidence + honest_status
flipped (task 6). Completion report cites each gate's golden scenario + FP analysis.

## Testing Strategy

Per-gate embedded `--self-test` (sandboxed fixtures, hooksPath neutered per NL-FINDING-029) is the
oracle; CI's Hooks-self-test job re-runs them in a clean env. The merge-scan fix reuses ms_self_test's
sandboxed fixture-repo pattern with a kill-resilience scenario. No new test infrastructure.

## Walking Skeleton

Already walked: GATE 3 end-to-end (event → parse → scope check → dirt check → block/pass) proven by
its 7/7 self-test in this session.

## Decisions Log

- (2026-07-17) **Observe-first rollout for BOTH new gates** (harness-review REFORMULATE, 4 majors):
  agent-commit-gate and agent-design-gate land with `blocking:false` — they compute and LOG their
  would-block verdicts (upgraded probe: raw cwd + session_id + rotation) but exit 0, flipping to
  enforce only against named criteria (GATE 3: probe proves cwd == the stopping agent's OWN
  agent-<id> worktree AND stop_hook_active observed on a block→retry pair; GATE 2: N real fires,
  0 false positives). Rationale: (a) the review PROVED the data-loss tail — if SubagentStop's cwd
  is the PARENT's worktree, a blocked subagent following the stash advice would stash the
  orchestrator's live WIP; (b) blocking-before-FP-calibration is the cry-wolf failure that
  REFORMULATE'd orphaned-worktree-guard; (c) it resolves the D5 blocking budget (14/13 RED from
  agate-2) to 13/13 GREEN without weakening GATE 1 (hosted inside plan-reviewer, already counted).
  Also per review: SESSION_EVENTS in blocking-budget-check.js gains SubagentStop (partial-enum-
  widening fix), fp_expectation corrected (reviewers are silent because each gets its OWN clean
  worktree, not because the gate knows roles), block message softened for read-only agents, and a
  defense-in-depth loop bound independent of stop_hook_active added for the enforce path.

- (2026-07-16) GATE 3 hosts on SubagentStop (not PostToolUse:Agent) — PostToolUse fires at async
  LAUNCH, not completion; SubagentStop is the only per-agent stop event. Risk (field contract) is
  bounded by the probe + a named rehost condition. Reversible: one hook entry.
- (2026-07-16) No pwd fallback in GATE 3 (S5): fail-open means don't guess; a wrong guess false-blocks
  innocent subagents (the cry-wolf failure that REFORMULATE'd orphaned-worktree-guard).
- (2026-07-16) Scenario cost of plan-reviewer's suite (~85s each) accepted for now; detached run is
  the mitigation. Filing a perf follow-up is task-5 material if harness-reviewer flags it.

## Pre-Submission Audit

- Checked: no sensitive data in gate code (paths via $HOME; fixture emails example.com).
- Checked: settings.json.template stays valid JSON; manifest-check GREEN after enum widening.
- Checked: doctrine compacts under the 3000B cap (no compact edited beyond the status line in task 6).
- Checked: every gate carries golden_scenario + fp_expectation + retirement_condition (§10).

## Definition of Done

A maintainer can: watch agent-design-gate block a golden-case-less agent file; watch Check 17 block a
qualifying ACTIVE plan without a review; watch agent-commit-gate block a dirty subagent stop; and see
the auditor's merge backfill converge and stay <5s — each demonstrated by self-test output or live
fire, all on master, manifest GREEN, honest_status truthful.

## Completion report (2026-07-17)

**All 6 tasks verified by task-verifier (commit 30c9df8, conf 8-9 per task) and landed on master.**
Master @ 7a41ad6 lineage; Evals CI GREEN; blocking-gate budget 13/13 GREEN; manifest-check GREEN.

**What the maintainer can now do (the §4 demonstration):**
- A qualifying plan CANNOT go ACTIVE without an architecture-review verdict — plan-reviewer Check 17,
  BLOCKING, verified by aa1-aa7 (aa2/aa4/aa5 prove the block; aa3/aa7 prove SOUND/S-W-A pass; aa6
  proves DRAFT exemption). FP-rate measured: 27% trigger rate on the 237-plan corpus, phrase-anchored.
- A new agent file missing the GOLDEN CASE + seven properties is caught — agent-design-gate, 8/8,
  OBSERVE-FIRST (would-block logged to probe; flip after N real fires / 0 FPs).
- A worktree subagent ending with uncommitted work is caught — agent-commit-gate (first SubagentStop
  hook), 10/10, OBSERVE-FIRST (flip criteria: probe proves own-worktree cwd + stop_hook_active on a
  block→retry pair + zero false would-blocks).
- The auditor's merge backfill converges once and stays cheap — incremental cursor, 36/36 incl.
  kill-resilience, warm scan 2.5s measured.

**Decisions made decide-and-go (per §8, batched here):** observe-first rollout for both new gates
(closing the harness-review's 4 majors; full rationale in the Decisions Log above); SubagentStop
added to SESSION_EVENTS so future blocking SubagentStop gates count against the D5 budget;
GATE 2 stayed PreToolUse-hosted (rehost-to-precommit rejected as needless surgery once observe-first
resolved the budget).

**Known residuals (tracked, not blockers):** the two observe-first gates need their probe logs
reviewed and flipped to enforce when criteria are met (queued); crashes/kills remain the detection
layer's job (orphaned-worktree-guard reformulation, separate); Acceptance Scenario 4's "<5s" was the
builder's measurement, not re-timed by the verifier (mechanism makes it structurally cheap).

**Process deviation, closed:** Task 4's comprehension articulation existed in the builder's report
but was never filed; placed in evidence-bar-enforcement-evidence.md during integration, with the
verifier's independent FM-023 falsification (test-to-spec correspondence) recorded as the grading.
