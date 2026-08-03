# THE GATED PIPELINE — master design (2026-08-03)

**Status:** DRAFT — awaiting architecture-reviewer + harness-reviewer verdicts (this design does
not proceed to a plan without both; D-15 applied to itself).
**Author:** Fable (main session 4a470c8c, model claude-fable-5, authored inline — D-13 satisfied
by construction; the `design-author` agent this design creates will own future design docs).
**Supersedes:**
- `docs/plans/harness-execution-redesign-2026-08.md` Stages 2–4 sequencing (Tasks 4–6) — absorbed
  and re-sequenced here per the architecture review's F2 (drain before Stage 2). The plan itself
  is closed out honestly by REQ-A6, not silently abandoned.
- Check 17's single-link semantics (`plan-reviewer.sh:3304-3393`) — upgraded to the review-chain
  contract (REQ-B7). The old semantics ("a review record exists") are the P-30 defect.
- The *derived review record* practice — banned. A review artifact that no reviewer agent produced
  never again satisfies any gate (REQ-B7's `Reviewer:` + `Verdict:` parse requirement).
- The 2026-07-04 observability review's "Law 1 refreshes-on-a-timer" reading as applied to hot
  paths — swept per REQ-B4 (the derive/push distinction: deriving from the oracle stays law;
  timer-pull refresh on hot paths is superseded by push-materialize, OD-registered).
**Inputs (all read in full):** `docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md` ·
`docs/handoffs/2026-08-03-MASTER-HANDOFF-process-integrity.md` ·
`docs/reviews/2026-08-03-stage0-stage1-harness-review.md` (REFORMULATE) ·
`docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md`
(SOUND-WITH-AMENDMENTS) · `docs/designs/end-to-end-process.md` ·
`docs/reviews/2026-08-03-exhaustive-inventory-handoff-review.md` (this session's input review) ·
a 12-surface grounding sweep at HEAD `6e28a82c` (citations throughout are from that sweep and are
current-state, not remembered-state).

---

## 0. What this design is, in three sentences

The estate's proven failure mode is not bad designs — it is **ungoverned transitions**: designs
authored by nobody in particular, plans that silently drop design requirements, builders dispatched
before any review runs, and deploys gated on "a review happened" rather than "the required reviews
happened" (P-29/P-30/P-31/P-39/P-40, all PROVEN). This design makes the four-stage pipeline
**design → plan → build → deploy** mechanically chained: every stage's output artifact carries
proof its predecessor's review ran and passed, every transition has a named world-class reviewer,
and an attempted skip is **blocked, not discouraged** (D-15's acceptance bar). It also fixes the
three open Criticals (F1, F2, F6) and the inventory gap (F9) *first*, because a pipeline built on a
wedged daemon, a corrupted arbiter cache, and a friction sensor nobody can read would be theater.

## 1. Problem statement (evidence-anchored)

Five defect classes, all PROVEN in the inventory and re-verified against HEAD by the grounding
sweep on 2026-08-03:

1. **No mechanical barrier between stages.** The only PreToolUse hooks on `Task|Agent` dispatch
   are `teammate-spawn-validator.sh`, `model-pin-gate.sh`, and `workstreams-emit.sh` (telemetry) —
   none checks that any review ran (`settings.json.template:332-358`). `plan-reviewer.sh` fires
   only at `git commit` via `pre-commit-gate.sh:242-265`; `Status: ACTIVE` is written by a plain
   Write (`start-plan.sh:444`). A session can therefore dispatch builders against an unreviewed —
   even uncommitted — plan. This session's predecessor did exactly that (P-39).
2. **Review-linked ≠ review-performed.** Check 17 verifies a `docs/reviews/*architecture-review*.md`
   file exists with a SOUND-ish verdict token (`plan-reviewer.sh:3339-3392`); a self-assembled
   *derived* record satisfied it (P-30).
3. **Design authoring is ungoverned.** No design-author agent exists (grounded: 25 agents, none
   with an authoring remit); design docs were written by un-pinned workflow agents while
   `model-policy.json:10-15` pins design *reviewing* to `["fable","opus"]` (P-31, D-13 violated
   structurally).
4. **Directives have no identity, carriage, or supersession.** `docs/operator-directives.md` does
   not exist (grounded); binding directives live in chat + `nl-issues.jsonl` lines 153/154/158 +
   brief addenda + 4 more stores (P-32/P-33). The plan template has no `Directives:` field
   (grounded: zero matches in templates + doctrine). Appending made the push directive invisible
   while looking documented (P-32).
5. **Open Criticals sit in the activation path.** F1 (daemon wedges after one tick; `daemon.pid`
   written at `nl-maintenance.sh:517`, never read; no `sf_release` anywhere in the repo), F2
   (two writers, incompatible schemas, one cache file: doctor writes 5 fields at
   `harness-doctor.sh:7477-7489`, digest writes 3 fields at `session-start-digest.sh:521-538`;
   sf-skip `exit 0` with no verdict at `harness-doctor.sh:7363-7367`), F6 (writer
   `~/.claude/state/workaround-sensor.jsonl` schema `bypass_kind`… vs consumer
   `~/.claude/state/gate-friction/ledger.jsonl` schema `.event` at `nl-maintenance.sh:393` — now
   LIVE: 4 real `gc_escape_used` call sites exist), F9 (zero Stage-1 manifest entries; grounded:
   no match for `nl-maintenance|doctor-verdict-cache|both-substrates` in 157 entries).

**P-42 discharge — the register's justification, re-derived without the Law-1 premise.** The
architecture review's headline argument (pull-cockpit was "compliant with contrary Law 1") is
refuted by the operator and by the file itself: `derive-cache.js:7-11` mandates deriving from the
`nl` oracle rather than trusting a maintained event log; "refreshes on a timer" (line 11) is that
module's implementation choice, orthogonal to push-vs-pull. The register is nonetheless justified,
on independent PROVEN grounds: (a) P-32 — a binding directive lived in "Addendum item 1" and never
reached plan task text, so appending made it invisible; (b) P-33 — seven stores of directive truth
with no ids, no supersession, no single citation target; (c) nl-issues:158 (2026-08-02e) — "a
directive that is not in the dispatch prompt does not exist," violated twice in one hour by two
different actors; (d) P-38 — mechanism-built-never-armed recurs because no store tracks
directive→mechanism state. Supersession stays mandatory (the register must be able to retire prior
laws like the timer-refresh reading, or it becomes the eighth store); what changes is the *framing*:
supersession is required because appended/updated doctrine otherwise persists as live citations in
code comments — not because Law 1 contradicted push.

## 2. Binding constraints (from the inventory; this design must not violate them)

- **Hard stops:** no `NL-Maintenance` registration until F1+F2 fixed AND re-reviewed (master
  handoff §0) · no WSL (D-08) · no new hardware (D-09) · drain + doctor-red triage BEFORE Stage 2
  (arch F2) · never force-push, never rewrite pushed history (§9).
- **D-15 (the spine, all four clauses):** reviewer between every transition; each reviewer
  world-class at ONE job; skipping mechanically IMPOSSIBLE; deploy gated on the COMPLETE review
  set. Acceptance bar: *an attempted skip is demonstrated blocked.*
- **D-07 anti-bloat:** every addition names what it displaces (§7 scorecard).
- **D-03 gate philosophy:** every new/extended gate emits {WHAT/WHY/FIX/ESCAPE} via
  `gate-contract-lib.sh` (shipped, Stage 0b) + `--check` mode; **§10 evidence bar:** every new
  gate names its golden scenario, expected FP rate, and retirement/demotion condition (inline in
  §5 per gate).
- **D-12:** every inventory item gets an explicit disposition (§9 maps all of S-14…S-33).
- **Observe-first:** new gates ship WARN where the golden case permits, with a **machine-readable
  flip condition** (the F7 lesson: prose flips are banned; flip dates/conditions live in data the
  check reads).

## 3. Decisions (each with rationale + reversal cost; §3-format asks only where genuinely operator's)

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-1 | **Reviewer fleet: extend two, add two — `design-author` (authoring role) and `plan-fidelity-reviewer` (design→plan)** | D-15.1 makes a reviewer at *every* transition binding; grounding proves design→plan has NO owner (plan-reviewer is a shell script checking shape; the master handoff's "extend the reviewer that already runs" cannot judge substance). S-19a's own rule: create only where none does. Authoring: no owner exists (P-31). The other transitions stay with existing agents (§5). | Delete two .md agent files; one revert |
| DEC-2 | **Build tier stays Sonnet; safety-critical protection comes from mechanical review-before-merge, not tier promotion** (Q-02) | P-43's own evidence: Fable-pinned harness-reviewer DID catch the daemon bug; the failure was merging before the review ran. The pipeline makes that sequencing mechanical; paying Fable on every build buys insurance the review already provides. | model-policy.json one-line category change |
| DEC-3 | **Directive-store consolidation: 7 → 4 with named roles** (Q-04): `docs/operator-directives.md` = standing BINDING directives (sole citation target); `nl-issues.jsonl` = intake only (triaged entries get `register_ref` or close); `docs/decisions/` = immutable rationale records (ADRs); `NEEDS-YOU.md` = open asks only. Backlog/reviews/chat are never directive stores. | P-33's defect is *no canonical store*, not *too many files with different jobs*. Chat→intake→register is a pipeline, not duplication. | Register is one file; revert restores status quo |
| DEC-4 | **Daemon: fix F1 fully (sf_release + watchdog pid-kill + un-masked self-test), prepare registration, but registration awaits operator ratification** (Q-05) | The operator rejected resident daemons by name (R3.1); registering one autonomously — even fixed — repeats the F3 process defect the review named. The ask is non-blocking: every other work stream proceeds; the estate has run maintenance-off for days (a truce, not an emergency). | If REJECTED: installer flips to pure `--tick` mode (5-min floor), one flag |
| DEC-5 | **Review-set per change class** (Q-09, decided): harness surface (`adapters/claude-code/**`, `~/.claude/**` templates) → architecture (if Check-17 keywords fire) + harness + evidence; product code → architecture (if keywords) + security (if auth/input surface) + functionality + domain reviewer per surface; docs-only → plan-fidelity only. Encoded as data in the deploy gate (REQ-B9), not prose. | Q-09's proposal was already right; leaving it as an open ask feeds P-35 (ask-rot). | Table is config; edit anytime |
| DEC-6 | **Invariant 8 text amended to the shipped first-approximation fingerprint + TTL bound; full per-check declared-inputs machinery is REJECTED** (arch Q2-1) | The review's arithmetic: ~40 hand-maintained input graphs guarding a staleness window the 30-min TTL already bounds. | Reinstate the invariant text; build later if evidence demands |
| DEC-7 | **Cold-doctor closure target re-scoped: cached `--quick` < 2 s stands as the contract; the cold target is set only after per-check profiling** (arch F2b) | 9m12s on a CLEAN sandbox PROVES cold cost is O(repo); "< 2 s cold post-drain" is disproven and keeping it makes the closure gate theater. | Restore old target if profiling refutes O(repo) |
| DEC-8 | **Stage 3 descoped to: death-certificate fields on nl-maintenance's existing handle-wait + cleanup-as-sensor fields on the existing janitor log (D-05 minimal). Sequence numbers, universal write-ahead intent, bracket-age invariant, weekly aggregation: REJECTED until a second measured loss class exists** (arch F6/Q2-3) | One proven loss class ≠ four mechanisms; sequence numbers violate the estate's own no-capture-without-consumer law. D-05 is an operator directive — the minimal fields honor it without the reporting machinery. | Each cut mechanism is independently addable later |
| DEC-9 | **Orphan reaper (Q-07): arm only AFTER maintenance activation (post-DEC-4 ratification), with allowlist + two-strike + the 24 h observe data cited in the arming commit** | The reaper lives in health-tick, which is Disabled until nl-maintenance activates; arming before activation is a no-op ritual. Observe data shows zero dangerous targets — arming is defensible then. | Unset one env marker |
| DEC-10 | **Estate git reconcile: merge `origin/master` (2 duplicate-content commits) into local via a merge commit, then push both mirrors** | Local 7 ahead / origin 2 ahead with same-subject rebased duplicates; §9 bans history rewrite; the 2d669a74 precedent is exactly this shape. | Merge commit is permanent but content-neutral |

## 4. Architecture — the artifact chain

The pipeline's connective tissue is a **review-chain block**: a machine-parsable header section
each stage's artifact carries, naming its predecessor + the reviews that authorized it.

```
## Review Chain
design-ref: docs/designs/<slug>.md@<git-blob-or-commit-sha>
design-reviews:
  - reviewer: architecture-reviewer  verdict: SOUND-WITH-AMENDMENTS  record: docs/reviews/<f>.md
  - reviewer: harness-reviewer       verdict: PASS                   record: docs/reviews/<f>.md
plan-reviews:
  - reviewer: plan-fidelity-reviewer verdict: PASS                   record: docs/reviews/<f>.md
```

Parsing rules (shared lib `hooks/lib/review-chain-lib.sh`, REQ-B6): a review line is valid iff the
`record:` file exists, its `## Verdict:` heading parses to the stated verdict, AND the record's own
`Reviewer:` line names the same agent — a record that says no agent ran it (the *derived* class)
fails parse **by construction**. SHA-anchoring (`@<sha>`) makes a chain entry cover specific bytes
(the end-to-end-process 6→7 rule, extended up-pipeline). Verdict vocabulary: architecture-reviewer
{SOUND, SOUND-WITH-AMENDMENTS, NEEDS-RESHAPING} (existing); harness/plan-fidelity {PASS,
REFORMULATE, REJECT} (existing harness-reviewer vocabulary; PASS-equivalents only satisfy chains).

**The three gates that consume chains** (all use `gate-contract-lib.sh` messages + `--check`):

- **G1 (design→plan)** — extends the existing PreToolUse-Write precedent on `docs/plans/`
  (`prd-validity-gate.sh` already fires there): a plan whose header declares `design-ref:` (new
  template field, REQ-B5) must carry a Review Chain whose design-reviews parse valid; a plan
  matching Check-17's keyword set OR touching `adapters/claude-code/**` REQUIRES `design-ref:`.
  plan-reviewer.sh gains the commit-time twin (Checks 20–22, REQ-B7). *Golden:* P-39's plan (built
  from an accreting design with a derived record). *Expected FP:* small docs-only plans matching
  keywords — the existing Check-17 phrase-anchored set measured 27% corpus fire-rate is reused
  unchanged, so no new FP class; escape = `design-ref: n/a — <30+ char justification>` (ledgered
  via `gc_escape_used`, weekly-visible). *Flip:* ships BLOCKING at Write-time for the `design-ref:
  n/a` justification length only, WARN for chain-parse failures for 7 days (calendar date in the
  gate's config JSON, the F7 lesson), then BLOCK.
- **G2 (plan→build)** — NEW thin PreToolUse gate on `Task|Agent` (rides the exact event
  model-pin-gate proves is inspectable): if the dispatch prompt's `NL-ATTRIBUTION:` line says
  `role=builder` and names `plan=<slug>`, the gate requires `docs/plans/<slug>.md` to be committed
  (HEAD or index) with a Review Chain whose plan-reviews AND (if design-ref present) design-reviews
  parse valid. Block message includes the exact missing link + the dispatch command to run the
  missing reviewer. **This is the D-15 acceptance-bar demo site** (REQ-B8's demo: a scripted
  builder dispatch against a chain-less plan must exit blocked). *Golden:* P-39/P-40 verbatim.
  *Expected FP:* ad-hoc non-plan builder dispatches — mitigated: prompts with no NL-ATTRIBUTION or
  role≠builder pass with a WARN (attribution stays WARN-only per orchestrator-pattern; G2 blocks
  only self-declared plan builders). Workflow-internal `agent()` spawns remain the documented
  honest residual (`model-policy.json:47-50` precedent) — named, not overclaimed. *Retirement:*
  demote to WARN if ledgered FPs exceed 3/week in the calibration fortnight (data-file condition).
- **G3 (build→deploy)** — extends `review-record-push-gate.sh` (already "the AUTHORITATIVE carrier
  of review-before-deploy" at the true funnel, `git-hooks/pre-push:79-92`): instead of "a review
  record exists," the gate computes the change class from the pushed paths (DEC-5 table as config
  JSON) and verifies EVERY required review for that class parses valid (agent + verdict + record).
  *Golden:* the three merged-without-review stages (P-40). *Expected FP:* mixed-class pushes —
  class union applies; emergency escape = existing operator-authorized artifact shape
  (deterministic-process Rule 2), ledgered. `git push --no-verify` residual stays NAMED-AND-ACCEPTED
  (server-side enforcement remains S-34, operator-only). *Flip:* WARN 7 days (config date), then
  BLOCK.

**Directives register + carriage (three channels from one file):**
`docs/operator-directives.md` — entries `OD-NNN`, format: `id | status (BINDING/SUPERSEDED) |
surfaces (globs) | supersedes | the complete instruction (≤5 lines: rule + golden case +
anti-pattern + sanctioned alternative)`. Seeded from nl-issues 153/154/158 verbatim + the D-01…D-23
curated set; each seeded nl-issue gets `register_ref`. Channels: (1) **plan** — per-task
`Directives:` field (template + Check 21); (2) **dispatch** — `scripts/dispatch-directives.sh
<plan> <task>` computes tag-matched entries (glob match on the task's Files-to-Modify — a lib
computation, not judgment) and prints the block the orchestrator pastes into the prompt;
orchestrator-pattern doctrine gains the step; G2 WARNs when a builder dispatch for a
tagged-surface task lacks the matched `OD-` citations; (3) **session JIT** — `doctrine-jit.sh`
gains a **separate second walk** for the register (its own marker namespace, so it cannot compete
with the doctrine walk's first-match-wins — the grounded starvation risk), injecting matched
entries once per session. Registering a superseding entry obliges the same-commit citation sweep
of the superseded law (REQ-B4's Law-1 sweep is instance #1).

## 5. Transition ownership (D-15.1/.2 resolved per-transition)

| Transition | Reviewer (ONE job) | Status |
|---|---|---|
| (authoring) | **`design-author`** — writes design docs from a template mandating per-decision rationale, explicit non-goals, `supersedes:`, machine-parsable REQ table, Directives-honored section; pinned `["fable","opus"]` | NEW (REQ-B2) |
| design → plan | **`plan-fidelity-reviewer`** — ONE job: is the plan a faithful, complete, buildable projection of the reviewed design? Verifies every MUST REQ-ID is claimed by a task whose text actually implements it (substance, not string-match), no task contradicts the design, directives carried. Floor beneath it: mechanical Checks 20–22 | NEW (REQ-B3) |
| design soundness | **`architecture-reviewer`** (existing; remit +2 lines: directive compliance vs register + supersession declaration present) + **`harness-reviewer`** for harness surface (existing, constitution-required) | EXTEND |
| plan → build | **G2 gate** consumes the chain; **`comprehension-reviewer`** keeps pre-build articulation (existing, R2+) | EXTEND/GATE |
| build (per task) | `task-verifier` (+ `functionality-verifier` on full-verification tasks) — existing, unchanged | KEEP |
| build → deploy | **G3 gate** verifies the DEC-5 review set, produced by existing reviewers (code/harness/security/functionality per class) | EXTEND/GATE |

## 6. Requirements (the fidelity contract — the plan is mechanically checked against this table)

**Phase A — stop the bleeding (all MUST, sequenced first):**
| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-A0 | MUST | Estate reconcile per DEC-10: merge `origin/master` into local master, push both mirrors, verify `git rev-list --left-right --count` = 0/0 on both. Stash-protect `docs/backlog.md` churn. |
| REQ-A1 | MUST | F1 fixed: `single-flight-lib.sh` gains `sf_release` (clears the recursion var + lock for the named key) with header stating the run-to-exit assumption; `run_daemon` releases per pass; `run_watchdog` reads `daemon.pid`, kills a live stale daemon before relaunch; S11 self-test re-run WITHOUT `SF_DISABLE=1` asserting ≥2 real ticks (the mask at `nl-maintenance.sh:790-791` deleted). Verify: self-test passes; a 3-iteration daemon run under the real guard produces 3 heartbeats. |
| REQ-A2 | MUST | F2+F5+F8 fixed as one contract: sf-skip serves the cached verdict when one exists else exits distinct code 3 with parseable `[doctor] SKIPPED (<reason>)` (never bare exit 0); `refresh_doctor_cache` writes the FULL 5-field schema or refuses to overwrite (never re-stamps `ts` on a cache hit, never strips `fingerprint`), and invokes doctor with `DOCTOR_VERDICT_CACHE_DISABLE=1 SF_DISABLE=1`; fingerprint gains live-hooks newest-mtime + `git diff --quiet` dirty bit; a two-writer self-test runs BOTH writers against one file and asserts schema invariants. Verify: new self-test scenario passes; grep proves no 3-field writer remains. |
| REQ-A3 | MUST | F6 fixed: ONE ledger file + ONE schema — `NL_MAINT_FRICTION_LEDGER` defaults to `workaround-sensor.jsonl`; the pane's jq maps `bypass_kind` rows to `workarounds`; a block-event writer decision is recorded (blocks come from gate `--check`/block sites via `gc_block` counters or are explicitly deferred with the metric renamed); end-to-end test: `gc_escape_used` → dashboard row. |
| REQ-A4 | MUST | F9 fixed: manifest.json entries for nl-maintenance, doctor-verdict-cache, both-substrates-alive (+ F4's zero-substrate WARN: schedule-manifest declares managed_by=nl-maintenance ∧ all legacy Disabled ∧ no fresh activation marker/heartbeat → WARN, RED after 14 days — dates in data). `manifest-check.sh --gen-index` regenerated. |
| REQ-A5 | MUST | F7 mechanized: cadence-WARN + budget-WARN flip conditions moved into `schedule-manifest.json` data (`warn_since`/`red_after` dates; managed_by=nl-maintenance entries annotated satisfied-by-construction once the activation marker exists); F11 (HALT canonical path split: locks scoped, HALT always at one canonical dir); F10 (one side-by-side CPU counter validation vs Task Manager, documented) — the F12 census fix folds into REQ-C3's scorecard. |
| REQ-A6 | MUST | Predecessor plan closed honestly: task-verifier runs on its T1/T2/T3 evidence, checkboxes flipped where PASS, then `harness-execution-redesign-2026-08.md` → `Status: SUPERSEDED` (pointer here); its T4–T6 scope carried by Phase C/D below. |
| REQ-A7 | SHOULD | Registration prepared (installer verified by self-test, rollback tested) + the DEC-4 ratification ask surfaced via needs-you.sh; registration executes on operator YES (or flips to pure-tick on NO). |

**Phase B — the gated pipeline:**
| REQ | Level | Requirement |
|---|---|---|
| REQ-B1 | MUST | `docs/operator-directives.md` register: format per §4; seeded (nl-issues 153/154/158 verbatim-derived + curated D-01…D-23); each seeded intake entry gets `register_ref`; supersession semantics (an entry may supersede an entry or a named in-repo law, obliging the same-commit citation sweep). |
| REQ-B2 | MUST | `design-author` agent (pinned fable/opus in frontmatter + model-policy category design) + `templates/design-template.md` (per-decision rationale w/ reversal cost, explicit non-goals, `supersedes:`, machine-parsable `## Requirements` REQ table, `## Directives honored` section, Review Chain stub). |
| REQ-B3 | MUST | `plan-fidelity-reviewer` agent (pinned fable/opus, category review): protocol = read design REQ table + plan; verify MUST coverage substantively; six-field class-aware findings; verdicts PASS/REFORMULATE/REJECT; anti-rubber-stamp step (must name the weakest mapping even on PASS); GOLDEN CASE: the push-directive drop (P-32) replayed as a fixture design+plan pair in its self-test/eval. |
| REQ-B4 | MUST | Supersession sweep #1: `derive-cache.js:7-11` header amended (derive-from-oracle retained; timer-refresh line annotated superseded by OD-push-materialize) in the same commit that registers the entry. |
| REQ-B5 | MUST | Plan template: `design-ref:` header field + per-task `Implements: REQ-…` + per-task `Directives: OD-…` + Review Chain section. Same-commit: template + doctrine text. |
| REQ-B6 | MUST | `hooks/lib/review-chain-lib.sh` — the one parser (used by G1/G2/G3 + plan-reviewer Checks 20–22); self-test includes the derived-record fixture failing parse. |
| REQ-B7 | MUST | plan-reviewer.sh Checks 20–22: (20) design-ref present when required + design-reviews chain parses; (21) per-task Directives/Implements fields present, every design MUST REQ-ID claimed ≥1 task; (22) chain records name agent+verdict (Check 17 marked superseded in its comment, kept for keyword-triggering only). |
| REQ-B8 | MUST | G2 gate per §4 (thin, gate-contract messages, `--check`, workaround-sensor escape) + **the acceptance-bar demonstration**: a self-test scenario dispatch-shaped exactly like P-39's is blocked, recorded in the evidence file. |
| REQ-B9 | MUST | G3: review-record-push-gate.sh consumes the DEC-5 class table (config JSON) + review-chain-lib; WARN 7 days by config date, then BLOCK. |
| REQ-B10 | MUST | No-addendum lint riding the existing hygiene-scan gate: `docs/designs/**` + `docs/plans/**` reject `^#+.*(Addendum|Round [0-9]|Update:)` headings (golden: the considerations brief); escape = none needed (integration-with-changelog is always available). Then the existing brief's addenda are integrated into its body (the D-04 cleanup). |
| REQ-B11 | MUST | Directives carriage channels 2+3: `dispatch-directives.sh` + orchestrator-pattern step + doctrine-jit second walk (own marker namespace). |
| REQ-B12 | SHOULD | Register gate posture v1: G1/G2 WARN when a tagged-surface plan/dispatch lacks matched OD citations (golden: 2026-08-02e; retirement: zero carriage violations across 10 consecutive plans → demote to review checklist). |

**Phase C — sequencing debts + anti-bloat floor (the arch review's co-critical):**
| REQ | Level | Requirement |
|---|---|---|
| REQ-C1 | MUST | Doctor 71-red triage: classify every RED (fix / retire-check / waiver-with-reason), executed via the already-triaged dispositions where they exist (`docs/reviews/2026-08-02-estate-entropy-triage.md`); target: doctor readable (single-digit REDs) BEFORE any Stage-2 work. |
| REQ-C2 | MUST | Estate drain executions with dispositions (D-12): 10 verified-safe worktrees pruned; 135 nl-issues triaged via the mechanized supersession sweep (S-30: grep each against `git log --grep` since filing — the demonstrated highest-leverage sweep), remainder dispositioned; stale ACTIVE plans (23 grounded) dispositioned via close-plan/SUPERSEDED/DEFERRED each with a one-line reason. |
| REQ-C3 | MUST | Honest scorecard surfaced: net-artifact delta + hooks-per-Bash + SessionStart spawns + machine-census scheduled tasks (F12: count = census, not subset) rendered in the existing dashboard snapshot (no new reporting machinery — DEC-8). |
| REQ-C4 | MUST | Invariant-8 text amendment (DEC-6) + cold-target re-scope (DEC-7) recorded in the plan/brief body (not an addendum). |
| REQ-C5 | SHOULD | DEC-8's kept minimal Stage-3 subset: death-certificate fields on the existing handle-wait + cleanup-as-sensor fields on the existing janitor log, each naming its consumer at birth. |

**Explicit NON-GOALS of this cycle:** Stage-2 thin stubs (next cycle, AFTER C1 makes the arbiter
readable — it remains the anti-bloat load-bearing stage and its admission includes sourced-mode
self-tests per arch F11); WSL anything; new hardware; sequence numbers / write-ahead intent /
bracket-age / weekly aggregation (DEC-8); full invariant-8 machinery (DEC-6); JIT pre-warnings
(defer until post-Stage-2 friction data); model-routing enforcement S-26 and cloud-offload S-27
(unblocked by, not part of, this cycle); Workflow-internal spawn gating (honest residual, S-33
stays open in the register as a documented limitation).

## 7. Anti-bloat ledger (D-07: what each addition displaces)

| Addition | Displaces (named) |
|---|---|
| review-chain-lib + Checks 20–22 | Check 17's single-link semantics; the derived-record practice; ad-hoc "did a review happen" prose checks |
| G2 gate | The unenforced orchestrator-pattern prose step "verify review before dispatch" (memory-rung → mechanism-rung conversion) |
| G3 class table | review-record-push-gate's single-record semantics |
| Directives register | BINDING entries scattered in nl-issues (get `register_ref` + close as intake), brief round-override archaeology, NEEDS-YOU duplication of standing directives |
| design-author + template | The blank-slate/workflow-agent authoring path (P-31) — banned for design docs |
| plan-fidelity-reviewer | Nothing existing (net-new capability); its mechanical floor displaces manual design-vs-plan eyeballing |
| no-addendum lint | The append practice itself (P-32/D-04) |
| Net score | Tracked live via REQ-C3; this cycle's own additions: +2 agents, +1 lib, +1 gate, +1 register, +1 template vs. −1 practice-ban enforced, −Check-17 semantics, −5 legacy tasks deleted at +30-day gate (C2), −10 worktrees, −visible-red pile (C1). The DOWN trend on hooks-per-Bash still rides Stage 2 (next cycle), honestly stated. |

## 8. Failure modes (pre-mortem, designed against)

1. **The pipeline blocks the pipeline's own build** (bootstrap): Phase A/B tasks are built under
   the OLD rules (this design + its two reviews satisfy G1/G2's intent manually; the plan carries
   the Review Chain block from birth so G2 enforces from the moment it exists). The demo (REQ-B8)
   uses a fixture plan, not a live one.
2. **G2 FPs strand ad-hoc work**: only self-declared `role=builder plan=<slug>` dispatches can
   block; everything else warns. Calibration fortnight with ledgered-FP demotion condition.
3. **The register rots like NEEDS-YOU**: the register holds only BINDING standing directives
   (target < 30 entries); intake stays in nl-issues; the C2 supersession sweep is the rot-control
   mechanism and is itself mechanized (S-30). |
4. **Two new agents drift toward generalists**: each carries a GOLDEN CASE fixture in its
   definition (evidence-bar property) and a one-job sentence the harness-reviewer is instructed to
   enforce on any future edit.
5. **WARN-flips forgotten again (F7 recurrence)**: every WARN ships with `red_after` as a DATE in
   config consumed by the check itself — no prose flips anywhere in this design.
6. **Chain forgery** (a builder writes a fake Review Chain): records must exist in `docs/reviews/`
   with parseable Reviewer+Verdict AND SHA-anchoring; forging those requires fabricating a full
   review record in a pushed commit — caught by G3's record-parse + the existing
   plan-evidence-reviewer session-end audit (which re-derives claims). Residual: a determined
   fabricator defeats local gates; server-side protection remains S-34 (operator-only, register
   entry). Named, not overclaimed.

## 9. Inventory disposition map (D-12: nothing dropped silently)

S-14→REQ-B1 · S-15→REQ-B5/B7 · S-16→REQ-B7 (folded into chain) · S-17→REQ-B2 · S-18→REQ-B10 ·
S-19/19a/19b/19c→§4+§5 (G1/G2/G3 + two agents) · S-20→NON-GOAL (next cycle, after C1) ·
S-21→REQ-C5 (attribution-without-autokill default) · S-22→REQ-A5 adjunct (hook self-timeout: folded
into single-flight-lib work if trivial, else next cycle — plan decides with LOE) · S-23→DEC-8 ·
S-24 keep-moving watchdog→NON-GOAL this cycle (queued; depends on activation) · S-25→NON-GOAL
(queued) · S-26/S-27→NON-GOAL (queued) · S-28 DAG scheduling→NON-GOAL this cycle (queued; G2 is its
prerequisite) · S-29→REQ-A5 (doctor lint on gate messages rides the F7 data work) · S-30→REQ-C2 ·
S-31→partially DONE (verdict cache) + REQ-A2 completes correctness; speed-in-CI queued · S-32→queued
(nl-issue exists) · S-33→register entry as documented residual · S-34/S-35→register entries flagged
OPERATOR-ONLY with SLA surfacing · Q-01→DEC-1 · Q-02→DEC-2 · Q-03→§1 P-42 discharge · Q-04→DEC-3 ·
Q-05→DEC-4 · Q-06→REQ-C2 · Q-07→DEC-9 · Q-08→§5 · Q-09→DEC-5.

## 10. Verification strategy (how the plan proves this design shipped)

Every REQ line carries its verification inline; the plan must map REQ→task 1:1 (Check 21 enforces
once built; plan-fidelity-reviewer enforces substantively at plan review). The demonstration that
closes the cycle is D-15's own acceptance bar, executed live: **(1)** a scripted builder dispatch
against a fixture plan with no Review Chain → G2 blocks (transcript in evidence file); **(2)** a
push containing a harness-surface commit with an incomplete review set → G3 refuses (WARN during
calibration, with the WARN text quoted); **(3)** doctor GREEN-or-triaged (single-digit REDs) before
any Stage-2 successor plan goes ACTIVE. Component evidence (self-tests) never closes user-facing
REQs (constitution §4).
