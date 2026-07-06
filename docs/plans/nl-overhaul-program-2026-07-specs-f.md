# Wave F — mechanical specs (strong-model refinement, authored 2026-07-03 by the program-origin Fable session)
Status: REFERENCE (spec appendix, not an independent plan — task F.0 deliverable)
prd-ref: n/a — harness-development
rung: 1
architecture: coding-harness
frozen: true

Context at authoring: Waves A–D live (doctor --full LITERAL GREEN 8/8 @ b8a1597; evidence
addendum 03a7827). Wave E batch 1 merged (#79), batch 2 running, batch 3 + §E.W ahead.
This file makes Wave F lesser-model-buildable per ADR 058 D9. It folds in ADR 059,
findings NL-FINDING-019–028, and the 2026-07-03 two-session coordination lessons.
PRECONDITION for every F task: Wave E fully merged + §E.W cutover verified (doctor
--full green post-install). Do not start F on a half-cut-over harness.

## §F.0.1 Serialization rules (binding; same pattern as §E.0.1)

ORCHESTRATOR-ONLY surfaces: `settings.json.template`, `manifest.json`,
`harness-doctor.sh`, `install.sh`, `rules/constitution.md`. F builders that need a
doctor check ship a `doctor-predicate.md` fragment (exact command + RED condition +
fixture) under `adapters/claude-code/tests/fixtures/wave-f/<task>/`; ONE designated
integrator (F.1 builder) implements all fragments in the doctor in a single pass.
Builder protocol: verbatim §E.0.1 (worktree check NL-FINDING-014; worker-F.<n> branch;
fix≠commit calls 016; CRLF grep-verify; self-test after message edits; self-tests pin
canonical root via nl-paths, never cwd — SELFTEST-ORACLE-PIN-01; suites that exercise
retry-guard blocks MUST export RETRY_GUARD_STATE_DIR into their tempdir —
NL-FINDING-028). Before ANY commit: `git fetch origin` + check max finding/task IDs
(4 collisions on 2026-07-03); diverged remotes reconcile by MERGE, never rebase+force.

## §F.0.2 Dispatch map

| Batch | Task | Model | Branch | Notes |
|-------|------|-------|--------|-------|
| 1 | F.1 | sonnet | worker-F.1 | budgets + staleness escalation; owns doctor edits this wave |
| 1 | F.5 | sonnet | worker-F.5 | governance hardening; harness-reviewer file + manifest AUDIT (fragments only) |
| 1 | F.6 | sonnet | worker-F.6 | sync clone per specs-e §SYNC-CLONE-C |
| 1 | F.2 | sonnet | worker-F.2 | docs/READMEs; PURE docs — no hook edits |
| 2 | F.3 | strongest available (operator-facing) | main session | serial; batch decision proposal |
| 2 | F.4 | strongest available | main session | serial; runs §F.4-PROTOCOL below verbatim |

F.1+F.5 both touch gate-governance seams: F.5's manifest changes ship as fragments;
F.1's integrator pass merges them with its own doctor edits. F.2 waits for F.1/F.5
merge if its generated docs read the manifest (they do) — dispatch batch 1 together
but MERGE F.2 last within the batch.

## §F.1 Budgets + staleness escalation — exact spec

- Doctor checks (all in `--quick`; each with a red-fixture self-test):
  1. Stop ≤6, SessionStart ≤8 chain entries (template AND live) — already partially
     present; consolidate under one `budget-chains` check id.
  2. Blocking gates ≤12: count manifest entries `blocking:true`.
  3. Always-loaded ≤30KB: byte-sum of `~/.claude/rules/*` + CLAUDE.md.
  4. ACTIVE plans ≤3 machine-wide: `grep -l "^Status: ACTIVE" docs/plans/*.md | wc -l`
     across every repo listed in `~/.claude/local/nl-repo-path` + registered project
     roots (document the exact root list the check walks; fail-open if a root is
     unreadable, count what is readable).
  5. Worktree count ≤6 and none older than 7 days without a commit; local branches
     with no upstream and no commit in 7 days flagged.
- Staleness ESCALATION lives in the digest (E.1), not the doctor: a nightly-ish
  SessionStart pass drafts one-line disposition proposals (defer plan / delete or
  push branch / remove worktree — one-word operator approval each). Idempotent:
  a proposal keyed `<artifact>-<yyyymmdd>` is emitted once. The doctor only REDs on
  budget breach; the digest carries the remediation proposals (pin (d): the message
  names the exact one-word reply).
- New-gate evidence bar → constitution §10 already carries it; F.1 adds the DOCTOR
  side: any manifest entry with `added_after: 2026-07` must name `golden_scenario`,
  `fp_expectation`, `retirement_condition`, and (per ADR 059 D4) `waiver_path` or
  `honesty_rationale` — schema-validated, RED otherwise.
- Done-when: red-fixtures for each budget violation pass in the self-test; live run
  green on this machine.

## §F.5 Gate-governance hardening (ADR 059 D4/D5/D7) — exact spec

- Waiver parity audit: for every manifest `blocking:true` entry, verify the hook
  greps for a `<gate>-waiver-*` (or documented equivalent) OR the manifest entry
  carries `honesty_rationale` (session-honesty class: resolvable by the session, no
  valve offered — ADR 059 D4 scoping). Ship as manifest fragments + an audit table in
  the PR body. Do NOT hand-edit manifest.json (F.1 integrates).
- harness-reviewer remedy-chain section: add to the agent file a mandatory table —
  "remedy prescribed → gates that remedy triggers", with NL-FINDING-016 (fix+commit
  compound → commit-gate) and NL-FINDING-019 (scope-line append → plan-ownership
  block) as worked golden examples. Also fold NL-FINDING-024's lesson: any PreToolUse
  writer-then-gate pair on the same matcher is a RACE (hooks run concurrently) — the
  reviewer must flag ordering-dependent designs.
- Auto-demotion: `scripts/gate-demotion.sh` reading the E.3 threshold-crossing file;
  on crossing: set `blocking:false` + `honest_status: "auto-demoted <date> pending
  harness-reviewer re-review (E.3 threshold)"` via a jq transform, ledger-emit, and
  digest line. Self-test: fixture ledger crossing → manifest copy flips + note.
  Runs from the E.5 weekly KPI pass (not a new hook — zero new chain entries).
- Candidate gate (downstream-product incident 2026-07-03, golden scenario on file): PreToolUse
  WARN (not block) on Edit/Write targeting the NL repo from a session whose project
  root ≠ NL repo, pointing at nl-issue.sh. Ship ONLY if it passes the §10 evidence
  bar (FP expectation: legitimate cross-repo harness sessions — orchestrators in
  worktrees — must not warn; test that fixture) — otherwise record as rejected with
  reason in the Decisions Log.
- Done-when: per plan line 146 (grep-provable waiver-parity; reviewer file section;
  demotion self-test green).

## §F.2 Docs + README regeneration — exact spec

- `docs/harness-architecture.md`: REGENERATED from manifest.json by a new
  `scripts/gen-architecture-doc.sh` (inventory tables: hooks by event, blocking vs
  warn, budgets, doctrine index) — never hand-maintained again; doctor predicate:
  regen script output byte-equals the committed doc (drift = RED).
- README sweep (each gets a `<!-- last-verified: YYYY-MM-DD (doctor-checked) -->`
  anchor the doctor greps for, ≤90 days old): root README.md,
  adapters/claude-code/README*, doctrine/INDEX.md (generated — verify generator not
  hand-edits), attic/README (must say WHY attic exists + one-release retention rule),
  evals/README, workstreams-ui README(s), scripts/README if present. Content bar:
  each README's claims must be mechanism-true (constitution §10) — the F.2 builder
  runs each named command before writing it.
- Heartbeat doc residue: if E.W shipped NL-FINDING-022's registration, flip the two
  doctrine files' NOT-WIRED wording back to live wording citing the schtasks name;
  if E.W deleted the mode instead, remove Layer C from both docs. Either way the
  claim must match `schtasks` reality (doctor predicate exists from E.10).
- failure-modes.md + findings: add the program's fixed classes as failure-mode
  entries (016 compound-commit, 019 two-gate trap, 024 writer-gate race, 027
  resolved-block poisoning, 028 selftest state-leak) with their mechanical guards.
- Done-when: plan line 148 (inventory-count script assertion) + doctor README-anchor
  predicate green.

### §F.2b Docs-as-process (operator directive 2026-07-04: proactive, not tail-gated)

Docs must be produced INSIDE the build loop; tail gates become backstops only.
Three mechanisms (F.2 builder ships all three; harness-reviewer reviews as
Pattern+Mechanism hybrid):
1. Plan template gains a required `Docs impact:` field PER TASK (the doc/README/
   runbook delta the task causes, or the literal word `none` with a reason).
   `plan-edit-validator` warns when absent; `task-verifier` treats a non-`none`
   Docs-impact as part of the task's Done-when — docs land in the SAME commit as
   the code, verified at checkbox time, not at session end. (Generation beats
   maintenance where possible: prefer extending a generator over hand-editing.)
2. Every NEW operator-facing capability ships a RUNBOOK stub (what it is, the one
   command, where its output lands) + a "what's new" line: `nl-issue.sh`-style
   append to `~/.claude/state/harness-changelog.jsonl`, which the E.1 digest
   surfaces once per session ("harness changes since your last session") — closes
   the silent-auto-install gap where capabilities arrive unannounced (e.g. nl-issue
   landed 2026-07-03 and the operator would not have known without being told).
3. Existing freshness/anchor gates (doctor README anchors, docs-freshness) stay as
   the BACKSTOP layer; a backstop firing is a signal the in-process layer failed —
   ledger it as such (E.3-style rate visibility).
- Done-when: template field present + validator warn fixture; verifier honors
  Docs-impact (fixture: task with non-none impact and no doc delta → verifier
  refuses flip); changelog append + digest line proven in sandbox; runbook stub
  exists for every Wave-E/F operator-facing capability (enumerate: nl-issue,
  session-resumer, digest, NEEDS-YOU, pre-compaction snapshots, KPI report).

## §F.3 Estate dispositions (serial, operator-facing) — protocol

Present ONE batched compact-format decision block (constitution §3, ≤20 lines) for:
the 6 pre-program ACTIVE plans (recommendations were prepared 2026-07-02 —
DEC-2026-07-02-002 executed part; verify current statuses first, some already
terminal), the DRAFT plan, 3 pending discoveries, the two B.11 admin-frozen plans
(permanent disposition), and any Wave-E/F additions. Options per artifact:
COMPLETE-verify / DEFER-to-dated-backlog / ABANDON-with-rationale. Every disposition
lands as a status flip + Decisions Log row + backlog reconciliation IN ONE COMMIT
per artifact class. Done-when: plan line 150.

## §F.4-PROTOCOL Pre-registered retro (run verbatim ~2026-07-24, or 3 weeks post-D-cutover)

Output: `docs/reviews/nl-overhaul-completion-2026-07.md`. Compare against
`docs/reviews/nl-overhaul-baseline-2026-07.md` sections 1–6 with THESE queries
(pre-registered 2026-07-03 to bind the later evaluator; adjust paths only if E/F
renamed them, and say so):

1. Retry-guard downgrades: count `unresolved-stop-hooks.log` entries dated in the 21
   post-cutover days vs the baseline's 21-day window. TARGET: −50% (ADR 058
   refutation clause b).
2. Waiver density: count `*-waiver-*.txt` created per week (state dirs, all repos) +
   ledger `waiver` events per gate. TARGET: −50% aggregate; any single gate ≥3/week
   = E.3 alarm must have fired (verify it did — if it didn't, E.3 is broken: file).
3. Signal consumption: external-monitor alerts unacked (baseline: 32/32 unacked) —
   TARGET: 0 unacked >7d; digest ack path exercised.
4. Rules-dir bytes: `du -b ~/.claude/rules` ≤30KB (baseline 883,882 → 9,786 at
   authoring). Doctor budget check green.
5. Stop-chain entries: ≤6 template+live (post-E.W may be 4 — record actual).
6. Blocking gates: ≤12 manifest `blocking:true`.
PLUS: synthetic-runner scenario scores vs Wave-B baseline run (clause a — scores
must improve); doctor --full green run dated within the retro week.
VERDICT RULES (pre-registered): if clause (a) fails OR clause (b) fails → the ADR 058
hypothesis is REFUTED for that clause → the mandated action is PROGRAM PAUSE +
re-design proposal to operator; do NOT add gates, do NOT rationalize partial numbers.
Ambiguous/mixed → present the table to the operator with a recommendation, no
self-graded pass. Also record: findings 019–028 status sweep (each terminal or
owned), attic retirement date honored, completion report appended to the plan.
MANDATORY in the completion report (operator commitment 2026-07-04): the
ACTIVATION PROPOSAL for `docs/plans/nl-observability-program-2026-08.md` (DRAFT,
frozen) — one-word operator greenlight flips it ACTIVE and starts O.0. Omitting
this proposal fails F.4's Done-when.

## §F.6 Sync-daemon durable fix

Build exactly specs-e §SYNC-CLONE-C (do not re-derive). Done-when: plan line 154
(grep + live sync with an open interactive session + zero interactive-checkout
touches in the refusal log).
