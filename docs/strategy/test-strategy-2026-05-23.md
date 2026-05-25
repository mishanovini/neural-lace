# Test Strategy — Neural Lace Harness (2026-05-23)

**Status:** Draft for review
**Author:** orchestrator session, branch `strategy/test-design-2026-05-23`
**Scope:** the harness itself (`adapters/claude-code/`, `evals/`, `tests/`, hooks, agents, rules), not downstream consumer projects.
**Companion doc:** `docs/claude-code-quality-strategy.md` (existing 571-line "why" narrative). This doc is the **how** — operational test strategy.

---

## 1. Executive summary

The harness has **substantially more test infrastructure than is visible from a clean checkout**, and a reviewer who looks for "tests pass on green" gets a misleading answer:

- **44 of 58 hooks** (76%) ship a `--self-test` flag handler with real fixtures, real assertions, and real exit codes.
- **5 hook fixture directories** under `adapters/claude-code/tests/` (dod-artifact-gate, goal-extraction, imperative-evidence-linker, transcript-lie-detector, vaporware-volume-gate) — these are integration-shaped tests already.
- **2 cross-hook scenario runners** at `tests/acceptance-loop-self-test.sh` and `tests/agent-teams-self-test.sh`.
- **5 golden security evals** under `evals/golden/` covering force-push, credential-push, env-edit, public-repo, safe-read.
- **10 testing-related agents** (`task-verifier`, `functionality-verifier`, `comprehension-reviewer`, `plan-evidence-reviewer`, `end-user-advocate`, `domain-expert-tester`, `code-reviewer`, `claim-reviewer`, `test-writer`, `security-reviewer`).

**None of it runs in CI.** `.github/workflows/` contains exactly one workflow: `pr-template-check.yml`, which validates the capture-codify section of PR bodies. The reviewer's "no test suite visible" critique is correct as a CI observation and wrong as an infrastructure observation. **The infrastructure exists; the wiring is missing.**

The single highest-leverage action is wiring the existing self-tests + golden evals to CI as a status check. Sized in hours, not days. Everything else (cross-hook scenario tests, adapter contract validation, reviewer-calibration) is real work — but until the existing self-tests run on green, claims about test quality elsewhere are theater.

### Four-tier model proposed

| Tier | What it covers | Agent / owner | Pass-rate floor |
|---|---|---|---|
| **Unit** | Single hook in isolation via `--self-test` | The hook itself (no agent); aggregated by `harness-test-runner` script | **100%** |
| **Integration** | Multi-component, no live LLM (hook + state file + fixture) | `tests/<hook-name>/` fixtures + new `harness-test-runner` script | **99%** |
| **Scenario** | End-to-end multi-session / cross-hook workflows | Existing `acceptance-loop-self-test.sh` + `agent-teams-self-test.sh`, expanded; `task-verifier` agent calls these on plan close | **95%** |
| **Eval** | LLM behavior on representative prompts (golden security tests + future agent-quality evals) | `evals/golden/` + planned `evals/agent-behavior/` | **90%** (with named exemptions) |

### Three biggest gaps surfaced

1. **Zero CI execution.** 44 hook self-tests exist; 0 run automatically. A regression that breaks a self-test ships to master silently until a session happens to invoke that hook.
2. **No cross-hook integration coverage beyond two walking-skeleton runners.** Most hooks are tested only in isolation; cross-hook interdependencies (e.g., `tool-call-budget` ack flag interacting with `pre-stop-verifier`) are exercised only when a real session happens to trigger the pattern.
3. **Self-invoked reviewer agents (claim-reviewer, code-reviewer, test-writer, security-reviewer) have no mechanical invocation trail.** A builder optimizing for speed skips all four; nothing surfaces that they were skipped. HARNESS-GAP-11 already acknowledges the reviewer-accountability dimension of this.

### Three most-effective-per-effort actions

1. **Wire all `--self-test` + `evals/golden/` to a new `.github/workflows/harness-tests.yml`.** Add a README badge. Block merge on red. ~3 hours. Closes Gap #1.
2. **Author a `harness-test-runner` orchestration script** at `adapters/claude-code/scripts/run-all-tests.sh` that invokes every `--self-test`, every `tests/*/` fixture exercise, every `evals/golden/*.sh`, and the two existing scenario runners — emitting a single PASS/FAIL summary + per-tier counts. ~4 hours. Powers Action 1's CI workflow and gives local devs a one-command "is the harness green?" check.
3. **Add a reviewer-PASS attribution log** (per HARNESS-GAP-11) as a write-only no-op log NOW, even before the calibration audit consumes it. The data substrate only becomes useful after weeks of accumulation; landing it cheaply now starts the clock. ~2 hours.

**Total Phase 1: ~9 hours, eliminates the reviewer's correct critique and establishes a foundation for everything else.**

### Decisions needed from Misha

1. **Pass-rate thresholds per tier** — defaults proposed above (100/99/95/90). Tightening or loosening?
2. **Scenario tests as a sustained investment?** They have the highest value-per-test and the highest maintenance cost. My recommendation: yes, but cap at ~12 scenarios initially (one per architectural seam) and grow from observed failure modes, not anticipation.
3. **New `harness-test-runner` agent vs. improve `task-verifier`?** My recommendation: **both**. Build the orchestration script first (Phase 1); add a thin `harness-test-runner` agent in Phase 4 that knows when to invoke the script and how to interpret partial-pass results. `task-verifier` stays the per-task verdict authority — it shouldn't be overloaded with full-suite orchestration.

---

## 2. What exists today (honest audit)

### 2.1 Hooks and their self-tests

- 58 `.sh` files under `adapters/claude-code/hooks/`.
- 44 carry a `--self-test` handler (76% coverage).
- The 14 without are mostly thin shims (account-switchers, settings divergence detectors that read live filesystem state, etc.) — most could reasonably skip self-tests.

**Representative depth (spot-checked):**

- `plan-reviewer.sh` — 8+ named scenarios (a–h) covering required-section validation, pre-submission audit gates, fully-populated / missing-assumptions / placeholder-only variants. Creates temp fixtures, invokes the hook, compares exit codes. **Genuinely comprehensive.**
- `bug-persistence-gate.sh` — 5 scenarios covering all four persistence targets (backlog / review / discovery / findings) + "none" (expects block). Synthesizes git repos, fabricates transcripts with trigger phrases. **Genuinely integration-shaped, despite living in the hook file.**
- `tool-call-budget.sh` — E1–E4 covering solo passthrough, solo-block at counter=30, resume after ack, reject ack without fresh review. **Tests interactions with state files, which is the right shape.**

**Critical observation:** what the harness calls "self-tests" are in practice **a mix of unit and integration tests**. They span the single-function-in-isolation case AND the hook-+-fixture-+-state-file case. The four-tier model below preserves the distinction so future test design is intentional about which tier it's adding to.

### 2.2 Hook-specific fixture directories

`adapters/claude-code/tests/` contains:

- 2 cross-hook scenario runners: `acceptance-loop-self-test.sh`, `agent-teams-self-test.sh`
- 5 fixture directories: `dod-artifact-gate/`, `goal-extraction/`, `imperative-evidence-linker/`, `transcript-lie-detector/`, `vaporware-volume-gate/` — each containing `fixture-*.jsonl` / `.md` / `.txt` files plus, in some cases, a `present-fixtures-runs` script

This is the integration-tier substrate. It's only used by 5 hooks today; the pattern is unevenly applied.

### 2.3 evals/

```
evals/
├── README.md
└── golden/
    ├── credential-push-blocked.sh
    ├── env-edit-blocked.sh
    ├── force-push-blocked.sh
    ├── public-repo-blocked.sh
    └── safe-read-allowed.sh
```

Bash scripts using regex pattern matching + exit codes. **Last commit `731add1` — "ci(harness): in-flight fix — golden test bugs + known-failing allowlists" — recent maintenance, not rotting.** README documents the manual run idiom; no CI integration.

The "structural/" subdirectory mentioned in the README is **planned but not implemented** — a gap the README itself surfaces.

### 2.4 Testing-related agents (honest assessment)

| Agent | Mechanical enforcement | Verdict |
|---|---|---|
| **task-verifier** | YES — required by `plan-edit-validator.sh` for checkbox flip + invoked by `pre-stop-verifier.sh` at session end | **Real work.** Functionality-over-components axis is concrete; default-FAIL discipline is stated. Acknowledged residual risk: prose-evidence fabrication. |
| **functionality-verifier** | YES — auto-invoked by task-verifier on every `Verification: full` runtime task. Browser MCP required, fallback chain documented. | **Real work.** "Be the user" framing + JSON artifact (screenshots + network + console) = non-fakeable evidence. |
| **comprehension-reviewer** | YES — auto-invoked by task-verifier at `rung ≥ 2`. Three-stage cascade (schema → substance → diff-correspondence). | **Real work.** Newest agent (2026-05-12); short empirical track record, but design is tight. |
| **plan-evidence-reviewer** | PARTIAL — invoked by `pre-stop-verifier.sh`. Output is a durable file read by `tool-call-budget.sh --ack`. **Bypassable by direct file write** (acknowledged in `vaporware-prevention.md` row 58). | **Real work with named gap.** |
| **end-user-advocate** | YES (runtime mode) — `product-acceptance-gate.sh` Stop hook blocks session end without PASS artifact. Plan-time mode is advisory. | **Real work.** Adversarial-probes section in runtime mode is the standout. |
| **domain-expert-tester** | PARTIAL — P0 findings block plan close; invocation is conditional (per `testing.md` substantial-UI mandate). | **Real work, conditionally invoked.** |
| **code-reviewer** | NO — self-invoked. | **Mixed.** Well-designed prompt; relies on builder discipline. No evidence of systematic invocation. |
| **test-writer** | NO — self-invoked. Zero hook references. | **Unclear.** Prompt is good; invocation history unknown. |
| **claim-reviewer** | NO — self-invoked. Explicitly named in `vaporware-prevention.md` as "the single unclosed gap from Generation 4." | **Theater unless invoked, which is by builder discipline.** |
| **security-reviewer** | NO — self-invoked. | **Theater unless invoked.** Highest-cost-of-skipping in the residual-risk set. |

**Implication for tier ownership (Section 4):** the four "real-work mechanical" agents (task-verifier, functionality-verifier, comprehension-reviewer, plan-evidence-reviewer) already carry the verification spine inside the per-task verdict loop. None of them owns CI-level harness-self-testing. That's the gap a `harness-test-runner` agent would fill.

### 2.5 CI workflows

`.github/workflows/`:

- `pr-template-check.yml` — sole workflow. Validates PR body has capture-codify section. Not a test runner.

**No package.json test target in the repo root.** No jest, vitest, mocha, pytest, bats. The harness is bash-first; the test runner needs to be bash-first too.

### 2.6 Adapter contract validation

`adapters/claude-code/schemas/` contains 7 JSON schemas (accounts, agent-teams, automation-mode, evidence, personal, projects, propagation-rules).

**No test validates `settings.json.template` parses as JSON or conforms to a schema.** No test verifies that documented hook behavior matches actual implementation. The schemas exist as runtime references, not as gated contracts.

### 2.7 Multi-session / scenario coverage

- `tests/acceptance-loop-self-test.sh` — 6-stage structural check wired into `/harness-review` Check 10 (per `vaporware-prevention.md` row 28). Verifies plumbing of the end-user-advocate loop.
- `tests/agent-teams-self-test.sh` — Layers A + I1..I6, six integration scenarios for Agent Teams.

**Both are walking skeletons.** Neither is a general framework. There is no test that simulates "Dispatch spawns Code session → PreToolUse fires → state file written → next session reads state" — exactly the architectural seam most likely to silently regress.

---

## 3. Reference frame: the harness's own testing doctrine

Citing `~/.claude/rules/testing.md` (loaded into every session at the harness boot path) so the strategy below explicitly builds on the rule, not around it:

- **FUNCTIONALITY OVER COMPONENTS — most important rule in the harness.** Three test layers (unit / integration / functionality); only functionality is required for user-facing task completion.
- **No mocked LLMs / external APIs / databases / time for functionality tests of AI features.**
- **"All tests pass" ≠ "the feature works."**
- **No skipped tests** — `no-test-skip-gate.sh` blocks commits adding `test.skip()` without an issue reference.
- **Bug persistence within the same session** — observed bugs go to `docs/backlog.md`, `docs/reviews/`, or `docs/findings.md` immediately.
- **Keep going when authorized** — `narrate-and-wait-gate.sh` enforces.

**Implication:** the strategy below extends the doctrine, it does not redefine it. The four-tier model maps cleanly: unit + integration are the testing.md "unit" and "integration" layers; scenario is testing.md's "functionality" layer applied to the harness itself (where the harness's "user" is the maintainer); eval is the LLM-behavior layer that testing.md does not explicitly name but which the existing `evals/golden/` directory implements.

---

## 4. Four-tier model — definitions, ownership, criteria

### 4.1 Unit tier

**Scope:** a single hook tested in isolation via its `--self-test` flag, with no external state dependencies beyond what the test itself sets up in `mktemp` directories.

**Examples that fit:** regex-only validators (`force-push-prohibition`, `no-test-skip-gate`, `definition-on-first-use-gate`). The check is pure: input → output, no side effects beyond stderr.

**Examples that DON'T fit:** anything that reads `$HOME/.claude/state/` (those are integration). Anything that requires a running git repo with specific state (those are integration). Anything that calls another hook (those are scenario).

**Owner:** the hook itself. Each hook's `--self-test` IS the unit-test suite for that hook. No agent owns this.

**Aggregation:** `run-all-tests.sh` (Phase 1) shells out to every `*.sh --self-test` and aggregates exit codes.

**Pass-rate floor:** **100%.** Unit tests are deterministic; any FAIL is a real regression. No flake budget. Quarantine path: if a unit test becomes flaky, the underlying hook has a non-deterministic dependency the test should mock or replace.

**Coverage target:** every hook of non-trivial complexity (>50 lines or any state interaction) carries a `--self-test`. Current 76% coverage is acceptable; the 14 without should each be audited once for "is this genuinely too trivial for a test, or did we skip?" — output an explicit `# self-test: n/a — pure shim` comment to lock the decision.

### 4.2 Integration tier

**Scope:** a hook + its fixture directory + state interactions, exercised through the same `--self-test` entry point but using `tests/<hook-name>/` for fixture data.

**Examples that fit today:** the 5 hooks with `tests/<hook>/` directories. The pattern: complex hooks (transcript-lie-detector reads a synthetic transcript JSONL; goal-extraction reads a fixture first-message + fixture extracted-goals + a synthetic stop transcript) need real input shape to test against.

**Examples that should fit:** any hook that reads a non-trivial input structure (transcripts, plan files, evidence blocks, JSON state files). Promote 8-10 more hooks to this pattern over time, prioritized by complexity.

**Owner:** the hook itself, with fixtures co-located in `tests/<hook-name>/`. No agent owns this either — the test stays close to the code.

**Aggregation:** same `run-all-tests.sh`. The script discovers `tests/<hook-name>/present-fixtures-runs` scripts and invokes them.

**Pass-rate floor:** **99%.** Integration tests touch filesystem; rare transient I/O failures are acceptable. A single FAIL on retry-PASS is logged but doesn't block.

**No mocking of the system under test.** This is `testing.md`'s rule; it applies here. A test for `transcript-lie-detector.sh` exercises the actual hook against a fixture JSONL — not a mock of the hook.

### 4.3 Scenario tier

**Scope:** multi-hook, multi-session, end-to-end workflows that exercise architectural seams. "Dispatch spawns Code session → PreToolUse fires → state file written → next session's SessionStart reads it." "Plan transitions Status: ACTIVE → COMPLETED → plan-lifecycle.sh archives → next session's archive-aware lookup resolves."

**Examples today:** the 2 walking-skeleton runners (`acceptance-loop-self-test.sh`, `agent-teams-self-test.sh`).

**Examples that SHOULD exist (Phase 2 priorities):**

| # | Scenario | Why it matters |
|---|---|---|
| S1 | Spawn-task report-back loop end-to-end | Conv-tree-state gates depend on it; HARNESS-GAP-08 mechanism |
| S2 | Plan creation → frozen → spec-freeze blocks edit → thaw → edit allowed | C2 mechanism end-to-end |
| S3 | Multi-worktree acceptance artifact aggregation | Agent Teams + Gen 5 critical path |
| S4 | DAG-waiver gate at Tier 3+ first dispatch | Per-session marker behavior |
| S5 | Local-edit authorization grant → consume → expire | ADR-029 mechanism |
| S6 | Findings ledger schema-gate blocks malformed entry; bug-persistence-gate accepts well-formed | C9 + bug-persistence integration |
| S7 | Discovery surfaces at session start; bug-persistence accepts discovery file as durable target | Build Doctrine Phase 1d substrate |
| S8 | Continuation enforcer blocks Stop without marker; retry-guard downgrades after 3 retries | `continuation-enforcer.sh` + `stop-hook-retry-guard.sh` |
| S9 | Wire-check gate parses Wire checks block; static trace PASS allows; broken arrow blocks | Per-task integration verification |
| S10 | Scope-enforcement-gate blocks commit; in-flight scope update path resolves | C10 mechanism |
| S11 | PRD-validity-gate blocks plan creation without valid prd-ref | C1 mechanism |
| S12 | Comprehension-reviewer blocks rung-2 checkbox flip without articulation block | C15 mechanism |

12 scenarios cover the architectural seams that matter most. Two exist today; ten are gaps.

**Owner:** a new **`harness-test-runner`** agent (proposed in Phase 4) that orchestrates scenario invocation, parses output, and reports per-scenario PASS/FAIL/SKIP. The agent is thin (~150-line prompt); the heavy lifting is in the bash scripts. The agent's value: it knows how to interpret partial-pass results, distinguish flake from regression, and route findings into `docs/findings.md` per the C9 schema.

**Pass-rate floor:** **95%.** Scenario tests touch many components; transient failures are realistic. Two consecutive FAILs with the same signature = real regression. One transient FAIL with PASS on retry = logged but not blocking. Quarantine after 3 transient FAILs in 7 days.

**Flake policy:**
- Auto-quarantine after 3 transient FAILs in 7 days (test moved to `tests/quarantine/` with a dated note + open issue)
- Quarantined tests run but don't block CI
- Quarantine review: any quarantined test for >14 days surfaces in `/harness-review` Check N (TBD) — must be fixed, deleted with rationale, or explicitly accepted as known-flake with refutation criterion

### 4.4 Eval tier

**Scope:** behavioral correctness of agents and rules against representative inputs. Today: 5 golden security tests (regex-pattern enforcement of blocked-vs-allowed Bash commands).

**Future expansion (Phase 5 or later, not Phase 1):**

- `evals/agent-behavior/` — LLM-as-judge or fixed-rubric evals for `task-verifier`, `claim-reviewer`, `code-reviewer` on representative diff inputs. Tests like: "given this diff with a known vaporware pattern, does code-reviewer surface it?" Run periodically (not per-commit; cost), report drift, feed into HARNESS-GAP-11's reviewer-calibration tracker.
- `evals/rule-conformance/` — given a rule and a synthetic transcript, does the agent (or hook) behave per the rule's documented contract?

**Owner:** the existing eval files own themselves (each `evals/golden/*.sh` is self-contained). LLM-behavior evals (when added) need a runner that handles cost/quota — possibly a scheduled job, not per-commit.

**Pass-rate floor:** **90%** with named exemptions. LLM behavior is non-deterministic; a 100% pass-rate target on agent-behavior evals is unrealistic. Drift past 90% = audit. Drift past 80% = the agent's prompt needs revision.

**Critical:** eval tier is NOT a substitute for unit / integration / scenario tiers. It supplements them by catching behavior the deterministic tiers can't reach (agent judgment quality).

---

## 5. Fail-on-red criteria

### 5.1 Per-tier hard failure semantics

| Tier | CI status check | Block merge? | Annotation only? |
|---|---|---|---|
| Unit | `harness-unit-tests` | YES on red | No |
| Integration | `harness-integration-tests` | YES on red | No |
| Scenario | `harness-scenario-tests` | YES on red unless test is in `quarantine/` | Quarantined tests annotate |
| Eval (golden security) | `harness-security-evals` | YES on red — these are security-critical | No |
| Eval (LLM-behavior, future) | `harness-agent-evals` | NO — annotate only | Yes |

**Rationale for blocking three of five.** The "block-on-red" floor must hold for tests that have deterministic correctness and security implications. LLM-behavior evals are noisy; blocking on them would erode trust in the CI signal.

### 5.2 Flaky-test policy

**Identification.** A test that fails ONCE in a CI run but PASSes on automatic retry is logged as `transient`. A test that fails on retry too is logged as `regression`. The runner script tracks both per-test in `.claude/state/test-flake-log.jsonl`.

**Quarantine.** After 3 `transient` events for the same test in 7 calendar days, the test auto-moves to `tests/quarantine/` (or `evals/quarantine/`) with a dated note. CI continues to run quarantined tests but does not gate merge on them.

**Resolution.** Any quarantined test sitting for >14 days surfaces in `/harness-review`:
- Fix the underlying non-determinism, OR
- Delete the test with a rationale (e.g., "test was wrong; the behavior it asserted is itself uncertain"), OR
- Mark as known-flake with a refutation criterion (per `claims.md`: "would be refuted by N consecutive passes after fix X")

**Audit-logged escape hatch.** A maintainer can `unquarantine` a test by writing a fresh marker to `.claude/state/test-unquarantine-<test-name>-<timestamp>.txt` with substantive justification (≥40 chars). The marker has a 1-hour TTL, mirroring `bug-persistence-gate.sh`'s waiver pattern. Audit-logged.

### 5.3 Side-effect tests

The integration + scenario tiers exercise filesystem writes to `mktemp` directories, synthetic git repos under `mktemp`, and (for some hooks) sleep-and-poll on state files. Conventions:

- **All side effects MUST be scoped to `$(mktemp -d)` or `${TMPDIR}/<test-name>-XXXXX`.** The runner verifies this via a wrapper that asserts no writes to `$HOME` outside `~/.claude/state/test-sandbox/`.
- **Trap-based cleanup is mandatory.** Every test script ends with `trap 'rm -rf "$TMPDIR_FOR_TEST"' EXIT`.
- **No tests touch the live `$HOME/.claude/` state directories.** The runner sets `CLAUDE_STATE_HOME=<sandbox>` before invoking and hooks honor it.
- **Network-dependent tests are SKIPPED in CI** (with explicit `# skip-in-ci: no-network` comment) — they run only in local dev or in scheduled jobs with explicit network gating.

---

## 6. Where the harness fails its own test today (honest)

Per `testing.md` "FUNCTIONALITY OVER COMPONENTS": every test verifies functionality, not components.

**The harness has 44 component (unit) tests, 5 integration tests, 2 scenario walking-skeletons, and 5 golden security evals.** It has zero CI execution of any of them.

This is the inverse of the testing.md aspiration. The rule says functionality tests are the load-bearing layer; the harness's actual coverage is component-heavy, scenario-thin, and unrun.

Explicit gaps the strategy must close:

| Gap | Severity | Closed by |
|---|---|---|
| Zero CI execution | **Severe** | Phase 1 |
| 10 of 12 needed scenario tests missing | **Error** | Phase 2 |
| Self-invoked reviewer agents have no invocation trail | **Error** (named in HARNESS-GAP-11) | Phase 3 (reviewer-PASS log) + Phase 5 (calibration) |
| Adapter contract validation absent (7 schemas, 0 tests) | **Warn** | Phase 4 |
| `evals/structural/` planned in README but never built | **Warn** | Phase 2 (as part of scenario expansion) |
| Hook self-test convention is uneven (76% coverage; the 14 without are unaudited) | **Warn** | Phase 1 (one-pass audit) |
| Flake quarantine has no implementation | **Info** | Phase 5 |
| Reviewer-PASS attribution log (HARNESS-GAP-11) doesn't exist | **Info** | Phase 3 |

Severity per the `findings-ledger.md` schema: `info < warn < error < severe`.

---

## 7. Phased implementation plan

Sequenced for value-per-effort. Each phase is independently shippable; later phases depend on earlier substrate but don't block on each other once their predecessor is in.

### Phase 1 — Wire what exists to CI (~1 day, including audit pass)

1. Write `adapters/claude-code/scripts/run-all-tests.sh` that:
   - Discovers `adapters/claude-code/hooks/*.sh` with `--self-test` and invokes each
   - Discovers `adapters/claude-code/tests/*/present-fixtures-runs` and invokes each
   - Invokes `adapters/claude-code/tests/acceptance-loop-self-test.sh` and `tests/agent-teams-self-test.sh`
   - Invokes every `evals/golden/*.sh`
   - Emits per-tier counts + final PASS/FAIL + writes a JSONL log for later flake analysis
2. Write `.github/workflows/harness-tests.yml` that invokes `run-all-tests.sh` on push to master + on PR. Splits into 4 jobs (unit / integration / scenario / golden-evals) for clean status-check granularity.
3. Add green-badge to `README.md`.
4. One-pass audit of the 14 hooks without `--self-test`: classify each as `# self-test: n/a — pure shim` (locked decision) or "needs test, opening issue #NNN" (added to backlog).
5. Configure branch protection on master: all 4 jobs required.

**Acceptance:** PR opened with intentionally broken self-test gets blocked by CI. Existing master is green at the moment of wiring (any pre-existing red is fixed first, or the test is quarantined with rationale).

### Phase 2 — Author 10 missing scenario tests (~3 days)

1. Per the table in §4.3, author S1–S10 scenario tests under `tests/scenarios/<slug>/`.
2. Each scenario gets a fixture directory + a runner script + a brief README documenting what architectural seam it exercises.
3. Wire into `run-all-tests.sh` scenario discovery.
4. Pass-rate floor 95%; quarantine path active.

**Acceptance:** A regression introduced in any of the 10 architectural seams (e.g., spec-freeze stops blocking, or scope-enforcement-gate's merge-context allowlist breaks) is caught by CI within the scenario job.

### Phase 3 — Reviewer-PASS attribution log (HARNESS-GAP-11 foundation, ~2 hours)

1. Add a tiny library at `adapters/claude-code/hooks/lib/reviewer-pass-log.sh` exposing one function: `log_reviewer_pass <reviewer-name> <task-id> <plan-path> <summary>`.
2. Extend the 4 reviewer agents (task-verifier, code-reviewer, claim-reviewer, plan-evidence-reviewer) with a final-step instruction: "before returning PASS, source the library and call `log_reviewer_pass`."
3. Log file at `.claude/state/reviewer-passes/<reviewer>-<ISO-ts>.json` per-pass; gitignored.
4. **No consumer yet.** This is the substrate that HARNESS-GAP-11's full mechanism needs. Land it cheap now; the calibration audit comes later.

**Acceptance:** Every reviewer PASS in normal usage produces a log entry. Grep `find .claude/state/reviewer-passes/` confirms accumulation. No behavior change for the reviewer itself.

### Phase 4 — Adapter contract validation + `harness-test-runner` agent (~2 days)

1. Add `adapters/claude-code/hooks/schema-validity-gate.sh` (PreToolUse Edit/Write on `*.json` under `adapters/claude-code/`): validates against the appropriate schema using `ajv` or `jq` checks.
2. Add `.github/workflows/schema-validation.yml` invoking the same library on PR.
3. Build `adapters/claude-code/agents/harness-test-runner.md` — a thin agent that:
   - Invokes `run-all-tests.sh`
   - Parses the per-tier output
   - Distinguishes regression from quarantined-flake
   - Routes findings into `docs/findings.md` per the C9 schema
   - Returns a structured PASS/FAIL verdict with per-tier breakdown
4. The agent is invoked manually via `/harness-test` slash command AND on plan close by `task-verifier` for harness-development plans.

**Acceptance:** Editing `settings.json.template` with a typo that breaks JSON is blocked at the gate. `/harness-test` produces a clean per-tier summary. A harness-development plan that breaks a test cannot reach `Status: COMPLETED` without surfacing the regression.

### Phase 5 — Flaky-test quarantine + reviewer-calibration audit (~1 day)

1. Extend `run-all-tests.sh` to read `.claude/state/test-flake-log.jsonl` and apply the 3-fails-in-7-days quarantine rule automatically (writes to `tests/quarantine/`).
2. Add `/harness-review` Check N: scan `tests/quarantine/` and `evals/quarantine/` for entries older than 14 days; surface for review.
3. Add `/harness-review` Check N+1: scan `.claude/state/reviewer-passes/` against runtime failures and surface "this reviewer's PASS preceded N failures in 7 days" patterns. (Depends on Phase 3 having accumulated data — gated on ~30+ days of log accumulation.)
4. Wire both into the weekly `/harness-review` cadence.

**Acceptance:** A flaky test that fails 3 times in a week auto-quarantines without manual action. The weekly harness-review surfaces "task-verifier PASSed 3 tasks that runtime-failed later" if such a pattern emerges. Wires HARNESS-GAP-11 from acknowledgment into measurement.

### Total effort estimate

- Phase 1: ~1 day (highest leverage; do this first)
- Phase 2: ~3 days
- Phase 3: ~2 hours (cheap substrate-laying; do alongside Phase 1)
- Phase 4: ~2 days
- Phase 5: ~1 day (depends on Phase 3 data accumulation)

**Total: ~7 days of work spread over weeks (Phase 5 needs calendar time for log accumulation).**

---

## 8. Agent strategy: improve existing OR add new?

Misha's question: *"Do we already have an agent that's supposed to be good at this? Can we improve that agent?"*

**Honest answer: we have agents that are good at per-task verification (task-verifier, functionality-verifier, comprehension-reviewer) and zero agents that own harness-self-testing as their primary role.** The per-task agents are doing real work and shouldn't be overloaded with full-suite orchestration responsibility — their value comes from focused, blocking, per-checkbox semantics.

**Recommended split:**

### task-verifier — extend, don't change role

Add one section to its prompt: when invoked on a harness-development plan (plan declares `Mode: code` + work-shape `build-harness-infrastructure`), include a check "did `run-all-tests.sh` pass at the relevant tiers since the last commit on this branch?" If not, return INCOMPLETE with the specific failing tier named.

This is a 30-line prompt addition. It does NOT make task-verifier the harness-test orchestrator; it makes task-verifier aware that harness work has a CI-style gate it should respect.

### harness-test-runner — new agent, thin orchestrator

Owns: invoking `run-all-tests.sh`, interpreting output, routing findings.

Does NOT own: the actual test logic (lives in bash). Does NOT own: per-task verdicts (task-verifier's role). Does NOT own: scenario authoring (the scenario fixture directories own their own logic).

The agent is ~150 lines. It's invoked:
- Manually via `/harness-test` slash command
- By `task-verifier` on harness-development plan close
- By scheduled `/harness-review` (weekly cadence)

Without this agent, `run-all-tests.sh` is just a script that someone has to manually run. With it, the script gains an interpretation layer + integration with `docs/findings.md` + a known invocation surface that the rest of the harness can rely on.

### reviewer-PASS attribution (no agent — pure mechanism)

A `lib/reviewer-pass-log.sh` shell library that the 4 reviewer agents source in their prompts. No new agent needed; the existing reviewers gain a final-step "log your PASS" instruction.

Why not an agent: agents are for judgment; logging is mechanical. Adding an agent in this seam would dilute the existing reviewers' focus.

---

## 9. Decisions needed from Misha

1. **Pass-rate thresholds.** Proposed: 100 / 99 / 95 / 90 (unit / integration / scenario / eval). Tighter (100/100/99/95) means less tolerance for non-determinism — fine if we're willing to fix every flake immediately. Looser (99/98/90/85) means more annotations and less merge friction but erodes signal trust. **Recommendation: proposed defaults.**

2. **Scenario investment cap.** Phase 2 proposes 10 new scenarios (S1–S10 in §4.3). Each scenario has ongoing maintenance cost as the architectural seam evolves. **Recommendation: ship all 10 in Phase 2; cap further additions at +2 per quarter until we see whether the maintenance burden is sustainable.**

3. **harness-test-runner agent in Phase 4 vs Phase 1.** Phase 1 ships `run-all-tests.sh` as a script. Phase 4 adds the agent layer. The agent could be folded into Phase 1 for a slightly heavier first phase. **Recommendation: keep agent in Phase 4. The script alone is enough to wire CI; the agent's interpretation value is what justifies its own work.**

4. **Reviewer-PASS log scope.** Phase 3 proposes logging for 4 reviewer agents. Could extend to all 10 testing-related agents (adding security-reviewer, end-user-advocate, etc.). **Recommendation: start with the 4 that have clear PASS verdicts; expand if Phase 5's calibration audit finds the signal valuable.**

5. **CI cost.** A full `run-all-tests.sh` run is mostly bash; per-run cost is trivial. But Phase 4 schema validation + Phase 5 LLM-behavior evals (when added) hit real GitHub Actions minutes. **Decision needed only if we add the LLM-behavior tier — defer.**

---

## 10. Refutation criteria

Per `~/.claude/rules/claims.md`: any plan built on a hypothesis names what would refute it.

**Hypothesis behind this strategy:** wiring existing self-tests + golden evals to CI is the cheapest, highest-value action because (a) the tests exist and are maintained, (b) the only reason they don't catch regressions today is the missing CI hook, (c) most regressions in the harness are caught by hook self-tests when those hooks are exercised in a real session — which is non-deterministic and slow.

**Would be refuted by:**

- After Phase 1 ships, observing that ZERO regressions are caught by CI in 30+ days of normal harness development. (Means the self-tests don't actually catch real regressions, and the value is symbolic, not substantive.) Mitigation: pause Phase 2 expansion; audit which self-tests are catching what.
- After Phase 2 ships, observing that scenario tests fail constantly on legitimate changes, blocking work. (Means the scenarios are over-coupled to implementation detail and need to be redesigned.) Mitigation: rewrite or delete the false-positive scenarios; tighten the scenario authoring rubric.
- After Phase 3 ships, observing that reviewer-PASS attribution log accumulates noise but no actionable signal even after 60+ days. (Means HARNESS-GAP-11's premise — that reviewer drift is observable from passing-then-failing patterns — is wrong.) Mitigation: revisit HARNESS-GAP-11; consider whether reviewer accountability needs a different mechanism entirely (e.g., spot-audit by humans, not pattern-mining).

**Plan is conservative-by-design** in the sense that Phase 1 + Phase 3 are cheap enough that if the broader plan is wrong, the cost of running them is small. The expensive phases (2, 4, 5) gate on Phase 1 producing observable value.

---

## 11. Cross-references

- `~/.claude/rules/testing.md` — the harness's primary testing doctrine; this doc extends it.
- `docs/claude-code-quality-strategy.md` — the existing 571-line "why" narrative; this doc is the operational "how."
- `~/.claude/rules/risk-tiered-verification.md` — per-task `Verification: <level>` field. The four-tier model here is the harness-self-testing analogue.
- `~/.claude/rules/mechanical-evidence.md` — structured `.evidence.json` substrate; the test-flake-log JSONL format follows the same shape principle.
- `~/.claude/rules/vaporware-prevention.md` — the enforcement map this strategy reads against.
- `~/.claude/rules/orchestrator-pattern.md` — agent dispatch shape; `harness-test-runner` invocation follows it.
- `~/.claude/rules/claims.md` — hypothesis-vs-proof labeling; the refutation criteria in §10 honor this.
- `docs/backlog.md` HARNESS-GAP-11 — reviewer accountability is one-way; Phase 3 + Phase 5 of this strategy close it.
- `docs/decisions/035-diagnostic-first-protocol.md` — most recent ADR; if this strategy ships, the next ADR (036) records the four-tier model decision.
- `docs/failure-modes.md` — FM catalog; new failure modes surfaced by Phase 1 CI runs feed back into this catalog per the standard "After Every Failure" loop.

---

## 12. Open questions (not blocking)

- **Is `evals/structural/`** (planned in evals README, never built) the same surface as the proposed scenario tier? Probably yes — recommend consolidating both under `tests/scenarios/` once Phase 2 ships, retiring the structural/ name.
- **Should hook unit tests live in the hook file (current convention) or be extracted to `tests/unit/<hook-name>.sh`?** Current convention is fine for ≤200 lines of self-test; complex hooks may benefit from extraction. Defer until a complex hook's self-test becomes unmaintainable.
- **LLM-behavior evals** (future): GPT-style agents-as-judges vs. fixed-rubric? Defer — Phase 5 + later.
- **Cross-repo test propagation:** when downstream projects adopt the harness, do they inherit the test infrastructure? Per Decision 011 Approach A, project-`.claude/` inheritance covers rules + hooks but not necessarily `evals/` or `tests/`. Worth a decision when the first downstream project asks.
