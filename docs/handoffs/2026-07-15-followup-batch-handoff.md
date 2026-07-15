# Follow-up handoff — model-enforcement + harness-governance batch (2026-07-15)

**Copy this whole file into a fresh session to execute the follow-up work.** It is
self-contained: every item has the context, the current on-disk/SHA state, the decisions
already made (do NOT re-litigate them), and enough detail to act without the originating
conversation. Repo: `neural-lace` (run from its main checkout on this machine).

## Where things stand (what's already DONE — don't redo)

- **Model-assignment enforcement (Directive 2) shipped + live.** `model-pin-gate.sh` (PreToolUse
  Task|Agent) blocks silent model-inherit; `check_model_pins` doctor check; all 24 agents pinned;
  policy `config/model-policy.json`. Reviewed (REJECT→fixed→re-review PASS). On personal origin
  master through `e0918b2`; live-synced. Plan archived: `docs/plans/archive/model-enforcement-2026-07-14.md`.
- **Decision 063 (block-not-inject) verified + written on disk** (see item 5).

## THE BATCH — one plan, one shared primitive (operator chose "batch")

Items 1–3 are the same class ("a Pattern that should be a Mechanism") and share ONE primitive:
**a review/evidence record keyed to a change, that gates the next step (build or deploy).**
Design that record + gate ONCE; the three are its consumers. This needs its own
`architecture-reviewer` design pass (it's high-blast-radius) before building.

### 1. Review-before-deploy Mechanism (the core gap)
- **Problem (PROVEN):** there is NO deterministic gate requiring a harness change (hook/gate/
  agent/rule) to be reviewed before it is committed, merged, or deployed. §10's "harness-review
  before a blocking gate lands" is a **Pattern, not a Mechanism.** It failed twice in the
  originating workstream: (a) a prior session live-synced a buggy `model-pin-gate` to `~/.claude`
  with zero review; (b) this session committed + `install.sh`-deployed a fix before its re-review
  returned. Nothing stopped either.
- **Deploy paths that check nothing about review:** `adapters/claude-code/install.sh` (manual) and
  `session-start-auto-install.sh` (auto-sync from origin/master).
- **Proposed shape:** a review-record artifact (like close-plan's `.evidence.json`) keyed to the
  change/commit, verdict PASS from `harness-reviewer`; a gate on the DEPLOY step (install /
  auto-install) that blocks harness changes lacking a PASS record. Decide the trigger scope
  (all `adapters/claude-code/**`? only gate/hook/rule files?) and the record's identity key.
- **Caution:** blast radius = every harness deploy. A false-positive blocks the estate. Design
  review + its own harness-review before landing (per §10).

### 2. Directive 1 — evidence-before-fix commit gate (the "5th lesson")
- **Lesson:** `docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`. Reviewed this
  session: it is NOT redundant with `diagnosis.md` (that doc is framed for prod *crashes* and is a
  Pattern; nothing gates a fix shipping on an inferred cause).
- **Fix:** require an evidenced `## Root cause (evidenced)` block, PROVEN/INFERRED-tagged, before a
  `fix(...)` commit; a reviewer/gate rejects a fix whose cause is inferred-not-observed. Broaden
  `diagnosis.md` beyond crashes to data/behavior bugs.
- **Home:** separate plan `docs/plans/evidence-before-fix-gate-2026-07-14.md` (referenced but not
  yet authored). Same review-record substrate as item 1.

### 3. pt/master `artifact-evidence-bar` reconcile
- pt/master carries a doctrine (`artifact-evidence-bar`) that generalizes constitution §10
  ("no evidence, no gate") to ALL artifacts — gates, AGENTS (golden case), DESIGNS (architecture
  review before build), reviews (falsifiability). Same primitive as items 1–2. Integrate it when
  reconciling pt (item 7) and fold into the batch design.

## MODEL-ENFORCEMENT RESIDUALS

### 4. Evidence-bar evasion-by-omission (deterministic §10 hole)
- `check_new_gate_evidence_bar` (`harness-doctor.sh` ~L2059) only inspects manifest entries whose
  `added_after >= "2026-07"`; it `continue`s past any entry LACKING `added_after`. So a new
  `blocking:true` gate evades the whole §10 evidence bar by simply omitting `added_after` — exactly
  how `model-pin` evaded it before it was fixed.
- **Fix (structural, not a backfill of values):** (a) backfill `added_after` on the **31 legacy
  `blocking:true` entries** that lack it; (b) THEN add a doctor assertion that every `blocking:true`
  entry HAS `added_after` (+ the three evidence fields). Order matters — the assertion REDs the 31
  until they're backfilled. Sweep: `node -e 'const m=require("./adapters/claude-code/manifest.json");console.log(m.entries.filter(e=>e.blocking===true&&!(e.added_after||"").trim()).map(e=>e.id))'`

### 5. Commit the on-disk decision 063 + doctrine note
- **On disk, UNCOMMITTED** (scope gate blocked them after the model-enforcement plan closed):
  `docs/decisions/063-model-pin-gate-blocks-not-injects.md` (untracked) and
  `adapters/claude-code/doctrine/model-selection.md` (modified — adds the "why block not inject"
  note). Commit them under the batch plan's scope. Content is final; just needs a home.

### 6. Built-in-strictness — OPERATOR DECISION (still open)
- The gate blocks no-model spawns of Claude Code built-ins (`Explore`/`Plan`/`general-purpose`/
  `claude`) — they have no `.md` to pin, and per **decision 063** the gate CANNOT auto-assign a
  model (the platform excludes Task/Agent from `updatedInput`), so block-until-explicit is the only
  enforcement. **Live default = STRICT.** Operator may relax (exempt named built-ins, accepting they
  inherit the caller's model). Await the operator's `strict` / `exempt <list>` / `relax`.

## ESTATE HYGIENE

### 7. pt/master reconcile
- Local master is **behind pt/master by 14, ahead by 8**. pt's 14 commits include: `architecture-reviewer`
  v1+v2, `artifact-evidence-bar` doctrine (item 3), `reap-what-you-spawn`, cockpit-v2 plans.
- **MUST, as part of the merge:** pin `adapters/claude-code/agents/architecture-reviewer.md`
  `model: fable` (category: design) AND add it to `config/model-policy.json` — else `check_model_pins`
  REDs and the gate blocks its no-model spawns.
- **Blocker:** `git fetch github-pt` (remote `pt`, SSH host alias `github-pt`) currently fails on
  access rights — the WORK github account's SSH key needs sorting first. `origin` (the personal
  account's fetch remote) is fine. Push BOTH remotes after reconcile.

### 8. nl-issue triage
- ~56 untriaged. Six filed this session, all relevant to the batch: TaskStop loses stage-1 (uncommitted)
  work; evidence-bar evasion-by-omission (item 4); SendMessage-resume ignores model override (fable→opus
  fallback only holds on FRESH dispatch, not resume); `write-evidence.sh` writes evidence to CWD not the
  plan dir; scope-enforcement-gate should exempt `docs/decisions/*` (like `docs/discoveries/*`); platform
  gap = no subagent-model-injection (decision 063). Triage via `nl-issue.sh --list --untriaged`.

## CARRY-FORWARD (awareness, not tasks)

- **Fable monthly spend limit is EXHAUSTED.** Reviewers/designers (pinned fable) run on the opus
  fallback until it resets or the operator raises it (`/usage-credits`). NOTE: SendMessage-RESUME of a
  fable-pinned agent reverts to fable and re-hits the cap — always FRESH-dispatch reviewers with
  `model: opus` while capped.
- **Separate track (NOT this batch):** status-page → Workstreams-UI adoption —
  `docs/design-notes/status-page-for-ws-ui-adoption.md`, backlog `WS-UI-STATUS-PAGE-ADOPTION-01`.
  Different session/topic; listed only so it isn't lost.
