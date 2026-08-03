# THE GATED PIPELINE — master design (2026-08-03, r3)

**Status:** r3 — delta findings integrated; awaiting the reviewers' scoped confirmations of the
amended §4 / REQ-B6 / REQ-B14 / REQ-B10 / REQ-A2 text (both delta verdicts stated no further full
pass is needed).
**Author:** Fable (main session 4a470c8c, model claude-fable-5, authored inline — D-13 satisfied
by construction; the `design-author` agent this design creates will own future design docs).
**Changelog:** r1 (4fb1b234) → r2 (a4cd03f5): integrated `docs/reviews/2026-08-03-gated-pipeline-design-harness-review.md`
(REFORMULATE: C-1, C-2, M-1…M-11, Mi-1…Mi-6) and
`docs/reviews/2026-08-03-gated-pipeline-design-architecture-review.md` (SOUND-WITH-AMENDMENTS:
H1, H2, M1…M4, L1…L5) — every finding integrated in the body per the no-addendum rule this design
itself establishes. r2 → r3: integrated the delta re-reviews — harness delta REFORMULATE (rule-3
pre-ledger exemption + B14 bootstrap ordering [Critical]; B10 archive-scope exclusion; A2
cache-disable flag restored; grandfather wording = slug list) and architecture delta
SOUND-WITH-AMENDMENTS (D1 record-attested three-way anchor match; D2 artifact-ref'd
completion-side ledger rows; D3 inflight-blob visibility hash). Review-id namespaces are disambiguated throughout: `HR-F*` = the Stage-0/1
harness review's findings; `INV-F*` = the inventory Part-6 items; `C-*/M-*/Mi-*` = the r1 harness
review; `H*/M*(arch)/L*` = the r1 architecture review.
**Supersedes:**
- `docs/plans/harness-execution-redesign-2026-08.md` Stages 2–4 sequencing (Tasks 4–6) — absorbed
  and re-sequenced here. The plan itself is closed out honestly by REQ-A6, not silently abandoned.
- Check 17's single-link semantics (`plan-reviewer.sh:3304-3393`) — upgraded to the review-chain
  contract (REQ-B7). The old semantics ("a review record exists") are the P-30 defect.
- The *derived review record* practice — a record no reviewer agent produced never again satisfies
  any gate: chain validity requires reviewer-name parse AND a matching dispatch-ledger row (§4).
- The 2026-07-04 observability review's "refreshes-on-a-timer" reading as applied to hot paths —
  swept per REQ-B4 (derive-from-oracle stays law; timer-pull refresh on hot paths is superseded by
  push-materialize, OD-registered).
**Inputs (all read in full):** `docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md` ·
`docs/handoffs/2026-08-03-MASTER-HANDOFF-process-integrity.md` ·
`docs/reviews/2026-08-03-stage0-stage1-harness-review.md` (REFORMULATE, HR-F1…HR-F12) ·
`docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md`
(SOUND-WITH-AMENDMENTS) · `docs/designs/end-to-end-process.md` ·
`docs/reviews/2026-08-03-exhaustive-inventory-handoff-review.md` · a 12-surface grounding sweep at
HEAD `6e28a82c` · both r1 design reviews (above).

---

## 0. What this design is, in three sentences

The estate's proven failure mode is not bad designs — it is **ungoverned transitions**: designs
authored by nobody in particular, plans that silently drop design requirements, builders dispatched
before any review runs, and deploys gated on "a review happened" rather than "the required reviews
happened" (P-29/P-30/P-31/P-39/P-40, all PROVEN). This design makes the four-stage pipeline
**design → plan → build → deploy** mechanically chained: every stage's output artifact carries
proof its predecessor's review ran and passed — **grounded in hook-observed facts (dispatch ledger,
blob anchors), not self-declared prose** — and an attempted skip is blocked, not discouraged
(D-15's acceptance bar). It also fixes the open Criticals (F1, F2, F6) and the inventory gap (F9)
*first*, because a pipeline built on a wedged daemon, a corrupted arbiter cache, and a friction
sensor nobody can read would be theater.

## 1. Problem statement (evidence-anchored)

Five defect classes, all PROVEN in the inventory and re-verified against HEAD by the grounding
sweep on 2026-08-03:

1. **No mechanical barrier between stages.** The only PreToolUse hooks on `Task|Agent` dispatch
   are `teammate-spawn-validator.sh`, `model-pin-gate.sh`, and `workstreams-emit.sh` (telemetry) —
   none checks that any review ran (`settings.json.template:332-358`). `plan-reviewer.sh` fires
   only at `git commit` via `pre-commit-gate.sh:242-265`; `Status: ACTIVE` is written with no gate
   on the write path — plan creation runs through *Bash* (`start-plan.sh` templates the header;
   note per arch-L3: the ACTIVE-templating is the production path's behavior, and the script's
   Bash nature means no PreToolUse file-tool matcher ever sees it — which is why commit-time and
   dispatch-time are the real floors, not Write-time). A session can therefore dispatch builders
   against an unreviewed — even uncommitted — plan. This session's predecessor did exactly that
   (P-39).
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
5. **Open Criticals sit in the activation path.** HR-F1 (daemon wedges after one tick;
   `daemon.pid` written at `nl-maintenance.sh:517`, never read; no `sf_release` anywhere in the
   repo), HR-F2 (two writers, incompatible schemas, one cache file: doctor writes 5 fields at
   `harness-doctor.sh:7477-7489`, digest writes 3 fields at `session-start-digest.sh:521-538`;
   sf-skip `exit 0` with no verdict at `harness-doctor.sh:7363-7367`), HR-F6 (writer
   `~/.claude/state/workaround-sensor.jsonl` schema `bypass_kind`… vs consumer
   `~/.claude/state/gate-friction/ledger.jsonl` schema `.event` at `nl-maintenance.sh:393` — now
   LIVE: 4 real `gc_escape_used` call sites exist), HR-F9 (zero Stage-1 manifest entries;
   grounded: no match for `nl-maintenance|doctor-verdict-cache|both-substrates` in 157 entries).

**P-42 discharge — the register's justification, re-derived without the Law-1 premise.** The prior
architecture review's headline argument (pull-cockpit was "compliant with contrary Law 1") is
refuted by the operator and by the file itself: `derive-cache.js:7-11` mandates deriving from the
`nl` oracle rather than trusting a maintained event log; "refreshes on a timer" (line 11) is that
module's implementation choice, orthogonal to push-vs-pull. The register is nonetheless justified,
on independent PROVEN grounds: (a) P-32 — a binding directive lived in "Addendum item 1" and never
reached plan task text, so appending made it invisible; (b) P-33 — seven stores of directive truth
with no ids, no supersession, no single citation target; (c) nl-issues:158 (2026-08-02e) — "a
directive that is not in the dispatch prompt does not exist," violated twice in one hour by two
different actors; (d) P-38 — mechanism-built-never-armed recurs because no store tracks
directive→mechanism state. Supersession stays mandatory because appended/updated doctrine
otherwise persists as live citations in code comments — not because Law 1 contradicted push.
**Per arch-L2, the predecessor review's remaining adopted findings (arch-F2 71-red/9m12s, arch-F6
class-count, arch-F2b cold-cost, invariant-8 descope) were re-audited for the same conflation:
each is measurement-anchored and Law-1-independent; their adoption here is explicit and safe.**

## 2. Binding constraints (from the inventory; this design must not violate them)

- **Hard stops:** no `NL-Maintenance` registration until HR-F1+HR-F2 fixed AND re-reviewed (master
  handoff §0) · no WSL (D-08) · no new hardware (D-09) · drain + doctor-red triage BEFORE Stage 2
  (arch F2 of the predecessor review — honored structurally by REQ-A8's placement) · never
  force-push, never rewrite pushed history (§9).
- **D-15 (the spine, all four clauses):** reviewer between every transition; each reviewer
  world-class at ONE job; skipping mechanically IMPOSSIBLE; deploy gated on the COMPLETE review
  set. Acceptance bar: *an attempted skip is demonstrated blocked — including the adversarial
  variants (no attribution; never-dispatched reviewer).*
- **D-07 anti-bloat:** every addition names what it displaces (§7 scorecard, every new file
  counted).
- **D-03 gate philosophy:** every new/extended gate emits {WHAT/WHY/FIX/ESCAPE} via
  `gate-contract-lib.sh` (shipped, Stage 0b) + `--check` mode; **§10 evidence bar:** every new
  gate — and every ROW of a per-class enforcement table (M-6) — names its golden scenario,
  measured/modeled FP rate, and flip/demotion condition as machine-readable data.
- **D-12:** every inventory item AND every finding of every input review (full id-space, M-1's
  generalization) gets an explicit disposition (§9).
- **Observe-first:** new gates ship WARN where the golden case permits, with flip dates in data
  the check reads (the HR-F7 lesson; no prose flips anywhere in this design).

## 3. Decisions (each with rationale + reversal cost)

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-1 | **Reviewer fleet: extend two, add two — `design-author` and `plan-fidelity-reviewer`** | D-15.1 makes a reviewer at *every* transition binding; design→plan has NO owner (a shell script cannot judge substance); S-19a: create only where none does. Upheld by the arch review's dedicated scrutiny (its §(a)). **Flagged for the operator's §8 decisions-review list: this decides open questions Q-01/Q-08** — defensible under §3, trivially reversible, but theirs to override. | Delete two .md agent files; one revert |
| DEC-2 | **Build tier stays Sonnet; safety-critical protection = mechanical review-before-merge** (Q-02) | P-43: the Fable review DID catch the daemon bug; the failure was sequencing, now mechanical. | model-policy one-line change |
| DEC-3 | **Directive-store consolidation: 7 → 4 named roles** (Q-04): register = standing BINDING directives (sole citation target); nl-issues = intake (triage → `register_ref` or close); decisions/ = immutable ADRs — **with the forward guard (arch-L1): an ADR asserting a binding standing rule must carry `register_ref` or an explicit "no standing rule" line, WARN-linted (REQ-B1)**; NEEDS-YOU = open asks only. | P-33's defect is no-canonical-store; the guard prevents the store-count from silently regrowing. | Register is one file; lint is one check |
| DEC-4 | **Daemon: fix HR-F1 fully, prepare registration, registration awaits operator ratification** (Q-05) | Registering a by-name-rejected shape autonomously repeats the F3 process defect. Non-blocking for all other streams. | REJECTED → pure `--tick` mode, one flag |
| DEC-5 | **Review-set per change class** (Q-09), as config data, with per-class evidence bars (M-6) and an explicit EXEMPT class (arch-M2): `docs/reviews/**`, `docs/handoffs/**`, `NEEDS-YOU.md`, `docs/backlog.md` churn — *the pipeline never gates its own provenance artifacts*. Harness class ships toward BLOCK (golden: P-40); product + other-docs classes ship WARN with per-class measured baselines (would-have-blocked over the calibration week's real push history) and per-class data-file flip conditions. | Q-09 decided; per-row §10 bar honored; circular self-gating avoided. | Table is config; edit anytime |
| DEC-6 | **Invariant 8 amended to shipped form + TTL bound; full machinery REJECTED** | Predecessor review Q2-1 arithmetic. | Reinstate text later |
| DEC-7 | **Cold-doctor target re-scoped: cached < 2 s stands; cold target set after profiling** | 9m12s clean-sandbox measurement. | Restore if profiling refutes |
| DEC-8 | **Stage 3 descoped to death-certificate fields + cleanup-as-sensor fields (D-05 minimal); sequence numbers / write-ahead / bracket-age / weekly aggregation REJECTED until a second measured loss class** | One proven class ≠ four mechanisms. | Independently addable |
| DEC-9 | **Orphan reaper armed only after maintenance activation, with allowlist + two-strike + cited observe data** (Q-07) | Arming pre-activation is a no-op ritual. | Unset one marker |
| DEC-10 | **Estate reconcile: merge `origin/master` duplicates via merge commit, push both mirrors** | §9 bans rewrite; 2d669a74 precedent. | Content-neutral |

## 4. Architecture — the artifact chain

The pipeline's connective tissue is a **review-chain block**: a machine-parsable section each
stage's artifact carries, naming its predecessor + the reviews that authorized it.

```
## Review Chain
authored-by: design-author (model: fable)          # or the session, pre-agent; parsed when design-ref required (M-10)
design-ref: docs/designs/<slug>.md@<git-blob-sha>
design-reviews:
  - reviewer: architecture-reviewer  verdict: SOUND-WITH-AMENDMENTS  record: docs/reviews/<f>.md
  - reviewer: harness-reviewer       verdict: PASS                   record: docs/reviews/<f>.md
plan-reviews:
  - reviewer: plan-fidelity-reviewer verdict: PASS  record: docs/reviews/<f>.md  plan-blob: <sha>
```

**Validity rules** (ONE parser: `hooks/lib/review-chain-lib.sh`, REQ-B6 — the sole validity
oracle for G1, G2, G3, and Checks 20–22). A chain entry is valid iff ALL of:
1. The `record:` file exists, its `## Verdict:` heading parses to the stated verdict, and the
   record's own `Reviewer:` line names the same agent (an honestly-derived record fails by
   construction).
2. **Anchor-vs-bytes, three-way (H2/M-5 + delta-D1):** validity requires a THREE-WAY match:
   the chain entry's anchored SHA == the blob the review record itself attests (every review
   record carries a `**Reviewed:** <path> @ <blob>` header line — the record template field) ==
   the referenced artifact's blob at HEAD (`git hash-object`). Because the attested blob lives in
   the REVIEWER's record, an author cannot re-anchor by editing one hex string in the chain:
   re-anchoring requires a fresh record, which rule 3 ties to a fresh reviewer dispatch. Mismatch
   ⇒ WARN during the calibration window (config date), then BLOCK. Plan-side: `plan-blob:`
   anchors the plan's bytes computed over the file MINUS its `## Review Chain` section and
   `## In-flight scope updates` (canonicalization in the lib, so appending chain entries never
   self-invalidates; **the record's attested blob for a plan is likewise the CANONICALIZED
   blob — a raw-file attestation could never three-way-match, since appending the chain entry
   changes the raw blob; the lib computes both sides of the comparison the same way**).
   **Inflight visibility (delta-D3):** the chain also carries an
   `inflight-blob:` hash of the excluded In-flight section; G2 emits a LEDGERED WARN (never a
   block) when it changes, and the next fidelity re-anchor covers the accumulated updates — the
   one structurally-excluded section stays visible, closing the P-32 side door. G2 re-verifies
   at every dispatch. **The staleness contract in one sentence: no gate ever treats an anchored
   chain as covering bytes the anchor does not hash to.**
3. **Dispatch-ledger cross-check (H1 + delta-D2 + harness-delta Critical):** a matching
   reviewer-completion row exists in `~/.claude/state/dispatch-ledger.jsonl` — written by the
   existing `workstreams-emit.sh` **`--on-builder-complete` PostToolUse path** (the agent
   actually RAN; a blocked or failed dispatch mints no row), schema
   `{subagent_type, model, ts, session_id, artifact_ref}` where `artifact_ref` is extracted from
   the dispatch prompt by workstreams-emit's existing parse (the `docs/…` path or plan slug the
   reviewer was pointed at; empty when underivable). Rule 3 requires: agent-type match AND
   `artifact_ref` matching the record's reviewed subject (when the row carries one — an empty
   ref satisfies type-match only and is the named degraded form) AND `ts` within the window
   [first commit touching the reviewed artifact, the record's commit time]. **Pre-ledger
   exemption (harness-delta Critical; keying per arch r3 note):** records whose FIRST-COMMIT
   time (`git log --follow --format=%ct | tail -1` of the record file — never a self-declared
   header date, which would reopen the backdating seam) predates the ledger-landing date
   (recorded in the lib's config, same pattern as G2's gate-landing date) are EXEMPT from rule 3
   — rules 1–2 still apply in full; this covers every record produced before REQ-B14 exists,
   including this design's own review records. Honest residual: the ledger proves *an agent of
   that type completed against that artifact ref*, not what it read; transcript-anchored proof
   remains out of scope (named, not overclaimed).

**The three gates that consume chains** (all use `gate-contract-lib.sh` messages + `--check`;
all carry manifest.json entries in the same commit — Mi-2/HR-F9 generalization):

- **G1 (design→plan)** — a thin new gate file on PreToolUse matcher `Edit|Write|MultiEdit` for
  `docs/plans/**` (M-4: widened from Write-only) **as advisory early warning**, with the
  **enforcement floor at commit-time** (plan-reviewer Checks 20–22, REQ-B7) — stated per-path:
  Bash-script writes (start-plan.sh) bypass any file-tool matcher, so start-plan.sh itself invokes
  the gate's `--check` at scaffold time. Requirement: a plan matching Check-17's keyword set OR
  touching `adapters/claude-code/**` REQUIRES `design-ref:` with valid design-reviews; escape =
  `design-ref: n/a — <30+ char justification>` (ledgered via `gc_escape_used`). *Golden:* P-39's
  plan. *FP model:* keyword class = the measured 27.0% corpus rate reused unchanged; **surface
  class = NEW and unmeasured — its fire rate over the plan corpus is measured during calibration
  and recorded in the gate's evidence entry BEFORE the flip (arch-M4)**. *Flip:* WARN 7 days
  (config date) → BLOCK at commit-time floor. *Demotion (Mi-6):* ledgered-FP > 5/week during
  calibration → stay WARN, recalibrate trigger. *Recalibration threshold (Mi-3):* `n/a`-escape
  rate > 30% of new plans in any fortnight → trigger-set review, auto-filed.
- **G2 (plan→build)** — NEW thin PreToolUse gate on `Task|Agent`. **Trigger (H1): keyed on
  `tool_input.subagent_type`** — any build-category agent type per `model-policy.json`
  (`plan-phase-builder`, `test-writer`) is a builder dispatch regardless of prose; the
  `NL-ATTRIBUTION:` line *refines* (names the plan slug), never gates. Logic: for
  `plan-phase-builder`, a plan slug must be derivable from attribution or prompt (underivable ⇒
  BLOCK — that agent exists only for plan work); for `test-writer`, underivable slug ⇒ WARN +
  ledger row (ad-hoc use is legitimate). With a slug: the plan must be committed (HEAD or index,
  resolved against the session cwd's git toplevel; no-repo ⇒ WARN pass, Mi-5) with plan-reviews
  AND (if design-ref present/required) design-reviews valid per the three rules above.
  **Grandfather (C-2):** plans on the install-generated grandfather slug list (generated once at
  gate install, enumerating extant plan slugs — the slug list IS the mechanism; blobs carry no
  dates) pass with
  a LEDGERED WARN naming the retrofit path (fidelity review + chain block); REQ-C2's stale-plan
  dispositioning covers that population; **new plans BLOCK from day one** — preserving the
  acceptance bar on the golden shape, which is a new plan. *Named residuals:* Workflow-internal
  `agent()` spawns (policy precedent `model-policy.json:47-50`); role-mislabeled non-build
  `subagent_type` dispatches doing build work — mitigated by the M-7 heuristic: any dispatch
  prompt referencing a `docs/plans/` path without attribution writes a workaround-sensor row, so
  evasion is measured from day one; the known quoted-header parse quirk is fixed in a parse
  shared with workstreams-emit. *Retirement/demotion:* ledgered FPs > 3/week in the calibration
  fortnight → demote to WARN (data-file condition). **This is the D-15 acceptance-bar demo site**
  (REQ-B8, three variants).
- **G3 (build→deploy)** — extends `review-record-push-gate.sh` (already the authoritative funnel,
  `git-hooks/pre-push:79-92`): computes change class from pushed paths per the DEC-5 config table
  and verifies EVERY required review for that class per the validity rules, **reading records AS
  OF the local SHA being pushed (same-push honoring — the lib's existing precedent, stated per
  M-6)**. Class postures per DEC-5: harness → flip to BLOCK by config date (golden: P-40);
  provenance-docs → EXEMPT; product/other classes → WARN with per-class measured baselines and
  per-class flip conditions. `git push --no-verify` residual stays NAMED-AND-ACCEPTED (server-side
  = S-34, operator-only, register entry).

**Directives register + carriage (three channels from one canonical file):** canonical form is
**`config/operator-directives.json`** (M-3: JSON canonical, one grammar), with a generated
human-readable `docs/operator-directives.md` view (the manifest→INDEX generation precedent);
**ONE parser lib `hooks/lib/directives-register-lib.sh`** serves all three consumers (Check 21,
`dispatch-directives.sh`, the JIT walk) with a shared fixture round-trip test. Entry fields:
`id (OD-NNN)`, `status (BINDING|SUPERSEDED)`, `surfaces (globs)`, `supersedes (OD-ids or named
in-repo laws)`, `instruction` (≤5 lines: rule + golden case + anti-pattern + sanctioned
alternative). Seeded from nl-issues 153/154/158 verbatim + curated D-01…D-23; each seeded intake
entry gets `register_ref`. Registering a superseding entry obliges the same-commit citation sweep
of the superseded law (REQ-B4 is instance #1). Channels: (1) **plan** — per-task `Directives:`
field (template + Check 21); (2) **dispatch** — `scripts/dispatch-directives.sh <plan> <task>`
computes tag-matched entries (glob match on Files-to-Modify; lib computation, not judgment) for
the orchestrator to paste; G2 WARNs when a builder dispatch for a tagged-surface task lacks the
matched `OD-` citations; (3) **session JIT** — `doctrine-jit.sh` gains a register walk that
**computes alongside the doctrine walk and merges into ONE `hookSpecificOutput` emission (C-1:
single JSON object containing both bodies; per-walk markers written independently; the
always-exit-0 writer contract preserved; self-test includes the both-match-same-event scenario
asserting one valid JSON object)**.

## 5. Transition ownership (D-15.1/.2 resolved per-transition)

| Transition | Reviewer (ONE job) | Status |
|---|---|---|
| (authoring) | **`design-author`** — writes design docs from the template (per-decision rationale, non-goals, `supersedes:`, machine-parsable REQ table, Directives-honored, Review Chain stub with authored-by). Frontmatter `model: fable` (single value = chain[0]; the fallback chain lives in model-policy.json — Mi-4) | NEW (REQ-B2) |
| design → plan | **`plan-fidelity-reviewer`** — ONE job: is the plan a faithful, complete, buildable projection of the reviewed design? MUST-REQ coverage verified substantively; no task contradicts the design; directives carried. Frontmatter `model: fable`. Floor: mechanical Checks 20–22 | NEW (REQ-B3) |
| design soundness | **`architecture-reviewer`** (remit +2 lines: directive compliance vs register + supersession declared) + **`harness-reviewer`** for harness surface | EXTEND |
| plan → build | **G2 gate** consumes the chain; **`comprehension-reviewer`** keeps pre-build articulation | EXTEND/GATE |
| build (per task) | `task-verifier` (+ `functionality-verifier` on full-verification tasks) | KEEP |
| build → deploy | **G3 gate** verifies the DEC-5 review set produced by existing reviewers | EXTEND/GATE |

## 6. Requirements (the fidelity contract — the plan is mechanically checked against this table)

**Phase A — stop the bleeding (all MUST, sequenced first; A8 runs A-parallel):**
| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-A0 | MUST | Estate reconcile per DEC-10: merge `origin/master`, push both mirrors, verify 0/0 divergence both. Stash-protect `docs/backlog.md`. |
| REQ-A1 | MUST | HR-F1 fixed: `sf_release` added to the lib (header states run-to-exit assumption); `run_daemon` releases per pass; `run_watchdog` reads `daemon.pid` and, **only after verifying the target's command line contains `nl-maintenance` + `--daemon` (M-8: MSYS2 `/proc/<pid>/cmdline`, fallback `ps -p`; identity mismatch ⇒ log-and-skip, never kill)**, kills the stale daemon before relaunch; S11 re-run WITHOUT `SF_DISABLE=1` asserting ≥2 real ticks (mask at `nl-maintenance.sh:790-791` deleted). Verify: self-test; 3-iteration daemon run under the real guard → 3 heartbeats. |
| REQ-A2 | MUST | HR-F2+F5+F8 fixed as one contract, **single-writer (M-2 preferred form): the doctor is the cache's ONLY writer** — sf-skip serves the cached verdict when one exists else exits distinct code 3 with parseable `[doctor] SKIPPED (<reason>)` (never bare exit 0); `refresh_doctor_cache` becomes invoke-and-read-only (runs `--quick` with `SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1` — **the disable flag restored per the harness delta: the refresher's job is a proactive recompute, so a within-TTL cache-HIT no-op would silently change its warm-keeping semantics**; the doctor's own write path at `:7477-7489` produces the record; the digest never writes the cache file) — no ts re-stamping, no fingerprint stripping, by construction; fingerprint gains live-hooks newest-mtime + `git diff --quiet` dirty bit; self-test asserts the single-writer property (digest path leaves the cache byte-identical except via the doctor's own write). Verify: scenario passes; grep proves no digest-side cache write remains. |
| REQ-A3 | MUST | HR-F6 fixed: ONE ledger file + ONE schema — `NL_MAINT_FRICTION_LEDGER` defaults to `workaround-sensor.jsonl`; pane jq maps `bypass_kind` → `workarounds`; block-event writer decision recorded (gc_block counters or explicit deferral with metric renamed); end-to-end test: `gc_escape_used` → dashboard row. |
| REQ-A4 | MUST | HR-F9 fixed: manifest entries for nl-maintenance, doctor-verdict-cache, both-substrates (+ HR-F4 zero-substrate WARN → RED after 14 days, dates in data). `--gen-index` regenerated. |
| REQ-A5 | MUST | Mechanized flips + small fixes: HR-F7 (cadence/budget WARN flip dates in `schedule-manifest.json`; managed_by entries satisfied-by-construction post-activation); **HR-F3 (M-1 restoration): `_sf_is_stale` gains owner-pid liveness (kill -0) with TTL fallback, AND doctor-quick TTL raised to ≥2× measured cold cycle (1200s), each TTL justified in a comment against a measured cycle**; **HR-F10 (M-1): the `never-suppressed` scenario labels renamed `…-BY-SSF`**; HR-F11 (HALT canonical path split); INV-F10/arch-F10 (one side-by-side CPU counter validation vs Task Manager, documented). |
| REQ-A6 | MUST | Predecessor plan closed honestly: task-verifier on T1/T2/T3 evidence, flip where PASS, then `Status: SUPERSEDED` (pointer here); T4–T6 scope carried by Phase C + non-goals. |
| REQ-A7 | SHOULD | Registration prepared (installer + rollback self-tested) + DEC-4 ratification ask surfaced via needs-you.sh; executes on operator YES (NO ⇒ pure-tick flag). |
| REQ-A8 | MUST | **(arch-M1, moved from Phase C) Doctor 71-red triage, A-parallel:** classify every RED (fix / retire / waiver-with-reason) using the existing dispositions (`docs/reviews/2026-08-02-estate-entropy-triage.md`); target single-digit REDs. Until complete, all Phase-A/B done-bars use targeted self-tests, never global doctor state (stated rule, arch-M1's alternative branch, so A-work is not serialized behind triage). |

**Phase B — the gated pipeline (bootstrap order: B1…B7 → **B14 → B13** → B8/B9 — the ledger
lands BEFORE the bootstrap self-review so that review is itself ledgered; harness-delta
Critical):**
| REQ | Level | Requirement |
|---|---|---|
| REQ-B1 | MUST | Register per §4: `config/operator-directives.json` canonical + generated md view + `directives-register-lib.sh` (ONE parser, round-trip fixture test) + seeding + supersession semantics + **the ADR forward guard (arch-L1): WARN-lint on decisions/ files asserting standing rules without `register_ref`**. Manifest entry same-commit. |
| REQ-B2 | MUST | `design-author` agent (frontmatter `model: fable`; model-policy category design) + `templates/design-template.md` (rationale-per-decision, non-goals, supersedes, REQ table, Directives-honored, Review Chain stub w/ authored-by). |
| REQ-B3 | MUST | `plan-fidelity-reviewer` agent (frontmatter `model: fable`; category review): protocol per §5; six-field class-aware findings; PASS/REFORMULATE/REJECT; anti-rubber-stamp (names the weakest mapping even on PASS); GOLDEN CASE fixture: the P-32 push-directive drop replayed as a design+plan pair in its eval. |
| REQ-B4 | MUST | Supersession sweep #1: `derive-cache.js:7-11` header amended in the same commit that registers OD-push-materialize. |
| REQ-B5 | MUST | Plan template: `design-ref:` header + per-task `Implements: REQ-…` + `Directives: OD-…` + Review Chain section. |
| REQ-B6 | MUST | `review-chain-lib.sh` — the three validity rules of §4 including the THREE-WAY anchor match (chain == record-attested blob == HEAD), plan-blob canonicalization + `inflight-blob:` WARN hash, and the dispatch-ledger cross-check with pre-ledger exemption + artifact-ref match; self-test fixtures: honest derived record (fails), never-dispatched reviewer (fails rule 3), author-re-anchored chain without a fresh record (fails rule 2 three-way), wrong-artifact-ref row (fails rule 3), pre-ledger-dated record (passes rules 1–2, exempt from 3), stale anchor (fails post-calibration), inflight change (ledgered WARN, passes), valid chain (passes). Manifest entry same-commit. |
| REQ-B7 | MUST | plan-reviewer Checks 20–22: (20) design-ref required-when-triggered + design-reviews valid **including anchor comparison at HEAD (M-5)**; (21) per-task Directives/Implements present, every design MUST-REQ claimed ≥1 task; (22) chain records name agent+verdict+ledger-row. Check 17 comment marked superseded (kept for keyword-triggering). |
| REQ-B8 | MUST | G2 per §4 (subagent_type-keyed, grandfathered, gate-contract messages, `--check`, escape ledgered) + **the acceptance-bar demonstration, THREE variants (H1): (i) the P-39 shape — plan-phase-builder dispatch, chain-less NEW plan → BLOCKED; (ii) same dispatch with NO attribution line → still BLOCKED (subagent_type keying); (iii) a chain entry naming a never-dispatched reviewer → fails validity.** Recorded in the evidence file with transcripts. Manifest entry same-commit. |
| REQ-B9 | MUST | G3 extension per §4/DEC-5: class table config + per-class postures/baselines/flips + provenance-docs exemption + same-push honoring. Manifest entry same-commit. |
| REQ-B10 | MUST | No-addendum lint riding hygiene-scan, **pattern narrowed per M-9: `Addendum`/`Update:` headings rejected in `docs/designs/**` + `docs/plans/**` — with `docs/plans/archive/**` EXCLUDED from scope entirely (harness delta: archives are closed records; the archived D.5-addendum hit stays a coherent negative fixture); `Round [0-9]` rejected in `docs/designs/**` ONLY (review-round records in plans are established practice — the measured 5 legitimate hits become negative self-test fixtures verbatim); case-insensitive, stated; escape = standard fresh-waiver (ledgered)**. Golden: the considerations brief. Then the brief's addenda integrated into its body. |
| REQ-B11 | MUST | Carriage channels 2+3: `dispatch-directives.sh` + orchestrator-pattern step + **doctrine-jit merged single-emission walk (C-1)** with the both-match self-test scenario. |
| REQ-B12 | SHOULD | Register-carriage WARN posture v1 (G1/G2 WARN on tagged-surface plan/dispatch lacking matched OD citations; golden: 2026-08-02e; retirement: zero carriage violations across 10 consecutive plans). |
| REQ-B13 | MUST | **Bootstrap sequencing (M-11): after B3 lands, `plan-fidelity-reviewer` reviews THIS cycle's plan; its record is committed and the plan's chain entry added; ONLY THEN does REQ-B8/G2 land.** The pipeline's own birth is never its first unplanned block. |
| REQ-B14 | MUST | **Dispatch ledger (H1 + delta-D2): workstreams-emit's `--on-builder-complete` PostToolUse path appends `{subagent_type, model, ts, session_id, artifact_ref}` rows to `~/.claude/state/dispatch-ledger.jsonl`** — completion-side so a blocked/failed dispatch mints no row; `artifact_ref` from the existing prompt parse (extend, don't add; always-exit-0 preserved); ledger-landing date recorded in the lib config (the rule-3 pre-ledger exemption boundary). **Lands BEFORE B13 in the bootstrap order.** Consumed by review-chain-lib rule 3. Manifest entry same-commit. |

**Phase C — remaining debts + anti-bloat floor:**
| REQ | Level | Requirement |
|---|---|---|
| REQ-C2 | MUST | Estate drain with dispositions (D-12): 10 verified-safe worktrees pruned; 135 nl-issues via the mechanized supersession sweep (S-30) + remainder dispositioned; 23 stale ACTIVE plans dispositioned (close/SUPERSEDE/DEFER, one-line reason each — doubles as G2's grandfather-population retirement, C-2); **the 1,254 unacked alerts (arch-L4): the one downstream route fix clearing 36% executed or explicitly re-owned, remainder dispositioned**. |
| REQ-C3 | MUST | Honest scorecard surfaced in the existing dashboard snapshot: net-artifact delta + hooks-per-Bash + SessionStart spawns + machine-census scheduled tasks (HR-F12). |
| REQ-C4 | MUST | DEC-6 invariant-8 amendment + DEC-7 cold-target re-scope recorded in the brief's body. |
| REQ-C5 | SHOULD | DEC-8 minimal subset: death-certificate fields on the existing handle-wait + cleanup-as-sensor fields on the existing janitor log, each naming its consumer at birth. |
| REQ-C6 | MUST | **Stage-2 admission trigger (arch-M3): REQ-A8's completion mechanically opens Stage-2 admission — a doctor WARN "stage-2 admission open since <date>" (data-file date) that persists until a Stage-2 plan goes ACTIVE.** Converts "next cycle" from intention to obligation. |

**Explicit NON-GOALS of this cycle:** Stage-2 thin stubs themselves (admission-triggered next
cycle; sourced-mode self-tests are its admission per predecessor arch-F11); WSL; new hardware;
sequence numbers / write-ahead / bracket-age / weekly aggregation (DEC-8); full invariant-8
machinery (DEC-6); JIT pre-warnings; S-26/S-27/S-24/S-25/S-28 (queued, unblocked-by-not-part-of);
Workflow-internal spawn gating (documented residual, register entry); transcript-anchored review
proof (dispatch-ledger rows are the v1 trust root — named residual).

## 7. Anti-bloat ledger (D-07: what each addition displaces; every new file counted — Mi-1)

| Addition (file) | Displaces (named) |
|---|---|
| `hooks/lib/review-chain-lib.sh` + Checks 20–22 | Check 17 single-link semantics; derived-record practice; ad-hoc review-happened prose |
| G1 gate file (`hooks/design-ref-gate.sh`, thin) | Nothing directly (new coverage); its commit-time floor rides the existing plan-reviewer |
| G2 gate file (`hooks/dispatch-chain-gate.sh`, thin) | The unenforced orchestrator-pattern prose step (memory-rung → mechanism-rung) |
| G3 = extension in `review-record-push-gate.sh` + class config | Its own single-record semantics |
| `config/operator-directives.json` + generated md + `hooks/lib/directives-register-lib.sh` + `scripts/dispatch-directives.sh` | Scattered BINDING nl-issues entries (→ `register_ref` + close), brief round-override archaeology, NEEDS-YOU duplication of standing directives |
| `agents/design-author.md` + `templates/design-template.md` | The blank-slate/workflow-agent authoring path — **displaced by convention + the review requirement (an unreviewed design cannot feed a chained plan); authoring-path enforcement itself is a NAMED RESIDUAL, verified only via the chain's authored-by parse when design-ref is required (M-10 honest form)** |
| `agents/plan-fidelity-reviewer.md` | Net-new capability; its mechanical floor displaces manual design-vs-plan eyeballing |
| No-addendum lint (in hygiene-scan) | The append practice (P-32/D-04) |
| Dispatch-ledger rows (in workstreams-emit) | Nothing (new observability; zero new spawn cost) |
| Net | +2 agents, +2 thin gates, +2 libs, +1 config+generator, +1 script, +1 template vs. −1 enforced-at-review practice, −Check-17 semantics, −5 legacy tasks (deleted at +30-day gate), −10 worktrees, −71-red pile (A8), −23 stale plans (C2). Hooks-per-Bash unchanged this cycle (Stage 2's job, now admission-triggered — REQ-C6); the cycle is honestly net-additive on files and net-subtractive on standing entropy. |

## 8. Failure modes (pre-mortem, designed against)

1. **Bootstrap** — REQ-B13's explicit ordering; the demo uses fixtures; the master plan is
   fidelity-reviewed before G2 exists (mechanical parse-satisfaction, not "manual intent").
2. **G2 FPs strand work** — subagent_type keying scopes blocking to build-category types;
   grandfather covers the legacy population (C-2); demotion condition is data.
3. **Register rots** — BINDING-only, target < 30 entries; intake stays nl-issues; ADR guard
   (arch-L1) stops silent regrowth; supersession sweep is the rot control.
4. **Agent drift toward generalists** — GOLDEN CASE fixtures in each definition; harness-reviewer
   instructed (in the agent files' own headers) to enforce the one-job sentence on any edit.
5. **WARN-flips forgotten** — every flip/demotion/measurement condition in this design is a
   config-data date or threshold (HR-F7 rule, no exceptions).
6. **Chain forgery / self-attestation** — the H1 trust root: hook-observed dispatch rows + blob
   anchors + record parse. Residuals named: ledger proves type-ran not bytes-read; `--no-verify`;
   Workflow-internal spawns; server-side (S-34) remains the operator-only backstop.
7. **Anchor churn** — the reviewer-only re-anchor path plus canonicalization (chain edits never
   self-invalidate); calibration WARN window before anchor BLOCK.
8. **Gate-cost creep** — §11's recalibration metrics; provenance-docs exemption kills the
   circular class (arch-M2).

## 9. Inventory + review disposition map (D-12; full id-space per M-1's generalization)

Inventory: S-14→B1 · S-15→B5/B7 · S-16→B7 · S-17→B2 · S-18→B10 · S-19/a/b/c→§4+§5 ·
S-20→REQ-C6-triggered next cycle · S-21→C5 · S-22→A5-adjunct (hook self-timeout folded into lib
work if trivial, else queued with LOE) · S-23→DEC-8 · S-24/S-25/S-26/S-27/S-28→queued non-goals ·
S-29→A5 · S-30→C2 · S-31→A2 completes correctness, speed-in-CI queued · S-32→queued · S-33→register
residual entry · S-34/S-35→register OPERATOR-ONLY entries · Q-01→DEC-1 (flagged) · Q-02→DEC-2 ·
Q-03→§1 · Q-04→DEC-3 · Q-05→DEC-4 · Q-06→C2 · Q-07→DEC-9 · Q-08→§5 · Q-09→DEC-5.
Stage-0/1 harness review (HR-F1…F12): F1→A1 · F2→A2 · **F3→A5** · F4→A4 · F5→A2 · F6→A3 · F7→A5 ·
F8→A2 · F9→A4 · **F10→A5 (rename)** · F11→A5 · F12→C3.
r1 harness review: C-1→B11 · C-2→B8+C2 · M-1→A5+§9 · M-2→A2 · M-3→B1 · M-4→G1 spec · M-5→B6/B7 ·
M-6→B9/DEC-5 · M-7→G2 residual+ledger heuristic · M-8→A1 · M-9→B10 · M-10→§7 · M-11→B13 ·
Mi-1→§7 · Mi-2→per-REQ manifest lines · Mi-3/Mi-6→G1 spec · Mi-4→§5/B2/B3 · Mi-5→G2 spec.
r1 architecture review: H1→§4 rule 3+B8+B14 · H2→§4 rule 2+B6/B7 · M1→A8 · M2→DEC-5 exemption ·
M3→C6 · M4→G1 spec · L1→B1 · L2→§1 · L3→§1 · L4→C2 · L5→§11.

## 10. Verification strategy

Every REQ carries verification inline; the plan maps REQ→task 1:1 (Check 21 mechanical floor;
plan-fidelity-reviewer substantive). Cycle-closing demonstration = D-15's acceptance bar with the
three adversarial variants (REQ-B8), plus: a push with an incomplete harness-class review set
refused (WARN text quoted during calibration), and the A8 target (single-digit doctor REDs) met
before any Stage-2 plan goes ACTIVE. Component evidence never closes user-facing REQs (§4).

## 11. The price, named (arch-L5)

Each pipeline traversal of a qualifying change costs 2–4 premium-tier reviews (~10–15 min latency
each, dispatched parallel where independent) plus the chain bookkeeping (~minutes). At the recent
volume of ~2–4 qualifying plans/week, that is roughly 6–12 premium reviews/week — order tens of
dollars and tens of minutes, paid forever, on every qualifying change. This is accepted against
the measured cost of the alternative (P-39's class: a 17-hour 100%-CPU incident, three
merged-unreviewed stages, and operator trust). Recalibration triggers (all ledgered data): G1
`n/a`-rate > 30%/fortnight; G2 FPs > 3/week; G3 per-class would-have-blocked baselines before any
flip. If review latency becomes the bottleneck the fleet question (Q-01's parallelism branch)
reopens — that is the named condition, not a vibe.
