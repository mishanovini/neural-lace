# Agent-Upgrade A/B Test Manifest — batch 2 (16 agents)

Generated: 2026-06-10 on branch feat/agent-upgrades-batch2-2026-06-10.
Upgraded (staged) agent files: `adapters/claude-code/agents-staged/<name>.md`
Current agent files: `adapters/claude-code/agents/<name>.md` (zero drift since the
2026-06-05 proposals on all 15 existing agents; documentation-auditor is net-new).
Proposals: `docs/reviews/agent-upgrades/2026-06-05-<name>.md` (gitignored — live in
the MAIN checkout working tree, not in this branch).

## How the orchestrator runs one A/B

1. Run A (current): dispatch the fixture's dispatch-prompt with the CURRENT agent
   file as the agent definition. Run B (upgraded): same prompt, agent definition
   from `agents-staged/`. Same model, same cwd (repo root of this branch checkout).
2. Fixtures are read-only unless the prompt says otherwise; builder/verifier
   fixtures explicitly instruct output-in-response instead of file edits.
3. Score both transcripts against the fixture's expected-delta rubric: upgrade
   wins if it shows the listed deltas WITHOUT any regression signal; any
   'Contract checks (both runs)' violation in Run B is an auto-reject.
4. The 12 WATCH agents: apply per-agent on PASS (gap-analyzer + harness-reviewer
   ONLY as a pair, same commit). The 4 NEEDS-MISHA agents: present results only.

---

## claim-reviewer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact from proposal section C; zero drift since 2026-06-05)
- **Staged file:** `adapters/claude-code/agents-staged/claim-reviewer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/claim-reviewer/`
- **Apply-risk notes (from digest):** Stricter aggregation (any NEI on a functionality claim -> FAIL) means more rewrite cycles before user-facing answers; self-invoked so it cannot hard-block sessions. Watch for over-FAILing honest summaries.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Review the draft response at `.claude/state/agent-ab-fixtures/claim-reviewer/draft-response.md`
before it is sent to the user. The draft makes claims about this repository
(neural-lace). Verify the claims against the actual codebase in the current
working tree and return your verdict in your standard output format. The repo
root is the current working directory.
```

### Expected-delta rubric

Planted: (1) TRUE cited claim (scope-gate merge skip); (2) FABRICATED capability
(session-wrap.sh does NOT validate PR Health Snapshot); (3) COMPOUND claim — first
half true (branch-opened emit), second half false (no exponential-backoff retry
exists in workstreams-emit.sh); (4) FALSE ABSENCE claim (two UserPromptSubmit
hooks exist: goal-extraction-on-prompt.sh, decision-context-reply-emit.sh);
(5) properly HYPOTHESIZED-tagged causal claim with refutation criterion (true per
workstreams-emit.sh STALE_MIN default 60).

#### What the UPGRADED agent should do differently
- Decompose claim 3 into TWO atomic claims; label the emit-half SUPPORTED and the
  backoff-half REFUTED/NEI — and FAIL the draft on it. (A binary cited/not check
  can pass claim 3 whole because the sentence carries a real file citation.)
- Per-atom SUPPORTED / REFUTED / NEI labels with tool receipts: a Read/Grep run
  this session cited per SUPPORTED label; no receipt means not SUPPORTED.
- Treat claim 4 as an absence claim: run 2+ distinct searches; the searches REFUTE
  it (the hooks exist) — REFUTED with the found files named.
- PASS claim 5 explicitly via the claims.md bridge (HYPOTHESIZED + refutation
  criterion = honest phrasing, not a defect).
- Calibrated, downward-biased confidence with an anchoring rationale.

#### What the CURRENT agent will plausibly do
- Catches claim 2 (it does verify citations) but passes claim 3 whole; weak or
  single-grep handling of claim 4; may flag claim 5 as hedging or as an
  unverified causal claim; emits an unanchored confidence number.

#### Regression signals (upgrade is WORSE if...)
- It FAILs claim 5 (the HYPOTHESIZED-tagged claim) or demands it be removed.
- No atomic decomposition / verdict without per-claim labels.
- Loss of the six-field class-aware FAIL block on flagged defects.

#### Contract checks (must hold in BOTH runs)
- Overall verdict present; the draft must FAIL (claims 2/3/4 are genuinely wrong);
  claim 1 must NOT be flagged.

---

## comprehension-reviewer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/comprehension-reviewer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/comprehension-reviewer/`
- **Apply-risk notes (from digest):** Blocks checkbox flips at rung 2+; the two NEW fail classes (unconsidered-edge-class, unsurfaced-assumption) will measurably raise R2+ FAIL rates and lengthen build loops. Class vocabulary is additive and parser-safe. Watch R2+ flip-block frequency on the first few plans.

### Dispatch prompt (verbatim — same prompt for both runs)

```
You are invoked for the comprehension gate on task T1 of the rung-2 plan at
`.claude/state/agent-ab-fixtures/comprehension-reviewer/plan-fixture.md`.
The builder's diff for T1 is the patch file at
`.claude/state/agent-ab-fixtures/comprehension-reviewer/change.patch` (this fixture
provides the diff as a patch file instead of a staged git diff). The builder's
`## Comprehension Articulation` is in the plan's Evidence Log. Review the
articulation against the diff and the plan task, and return your verdict in your
standard output format.
```

### Expected-delta rubric

Planted: (a) spec-misparaphrase — the articulation says the cap applies to
"marketing notifications" but the plan Goal says ALL notification types including
system alerts; (b) citation-overlap miss — pruning is cited at
rate-limiter.ts:31-38 but the patch hunk places the pruning filter near the top of
checkLimit (around line 12); (c) unconsidered boundary edges — the
exactly-at-60s window boundary (strict less-than), and the resetOrg path added in
the diff but never mentioned; (d) unsurfaced assumptions — single-process /
no-concurrency, wall-clock monotonicity (Date.now()).

#### What the UPGRADED agent should do differently
- FAIL with `spec-misparaphrase` (Stage 3a check of `### Spec meaning` against the
  actual plan-task text).
- Catch (b) mechanically via the hunk-map interval check (the cited line range
  does not overlap the diff hunk containing the pruning code).
- Emit the new `unconsidered-edge-class` for the 60s boundary and/or the resetOrg
  path (EP/BVA derivation).
- Emit the new `unsurfaced-assumption` for concurrency and/or clock monotonicity.
- PROVEN/HYPOTHESIZED tags on findings; anchored confidence value.

#### What the CURRENT agent will plausibly do
- PASS or weak-FAIL: all four canonical headings are present with 30+ chars, and
  the claimed edge cases DO roughly correspond to diff content. It validates only
  CLAIMED items, so the misparaphrase, missing edges, and missing assumptions go
  unflagged; the line-number drift may slip through a non-mechanical read.

#### Regression signals (upgrade is WORSE if...)
- INCOMPLETE on schema grounds (all four canonical headings ARE present — the
  schema stage must pass).
- Failing the two genuinely-correct covered-edge claims (rollover pruning exists;
  the at-cap comparison exists near line 13).

#### Contract checks (must hold in BOTH runs)
- Verdict is PASS/FAIL/INCOMPLETE; FAIL names specific sub-sections; the agent
  does not flip any checkbox.

---

## plan-evidence-reviewer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift). REVIEW COMPLETE / VERDICT: sentinels verified present in staged file
- **Staged file:** `adapters/claude-code/agents-staged/plan-evidence-reviewer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/plan-evidence-reviewer/`
- **Apply-risk notes (from digest):** Fires at the tool-call-budget ack and session end - stricter verdicts mean more CONCERNS/BLOCKED at the 30-call threshold (mid-build friction). Sentinels preserved so the ack mechanism is safe. Watch budget-ack block frequency.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Audit the evidence for the plan at
`.claude/state/agent-ab-fixtures/plan-evidence-reviewer/plan-fixture.md`.
The evidence file is
`.claude/state/agent-ab-fixtures/plan-evidence-reviewer/plan-fixture-evidence.md`
and the cited implementation file is in the same fixture directory. Cross-check the
evidence blocks against the repository state and re-verify what can be re-verified.
Return your verdict in your standard output format, including your sentinel lines.
```

### Expected-delta rubric

Planted: (a) fabricated git SHA `9f3c2ab1d4e` (resolves nowhere in this repo);
(b) fact-mismatch — T1's notes claim "constant-time compare" but webhook-route.ts
explicitly uses a plain `===` comparison (its comment even says NOT constant-time);
(c) T2's replayable check `file ...webhook-route.ts::MAX_TIMESTAMP_SKEW` FAILS on
re-execution (the token does not exist in the file); (d) the "3 files modified"
count is unverifiable against the fabricated SHA; (e) T2 declares dependency on T1.

#### What the UPGRADED agent should do differently
- Short-circuit on the fabricated SHA (fabricated-git-sha class): INCONSISTENT,
  with a claim ledger classifying the SHA claim as ASSERTED/fabricated rather than
  PROVEN-by-tool.
- RE-EXECUTE both `file ::` checks (mandatory re-execution): T1's passes, T2's
  fails — a re-executed-checks line names both outcomes.
- Catch (b) by reading the cited file: the constant-time prose is contradicted by
  the code (inference-as-fact / fact-mismatch).
- Mark T2 INCONSISTENT (inherited from T1) in addition to its intrinsic failure.
- Confidence at or below 5 wherever grounding was not re-observed; never
  CONSISTENT above confidence 5 without re-observed PROVEN-by-tool grounding.

#### What the CURRENT agent will plausibly do
- May catch the missing T2 pattern only IF it re-runs the file check (historically
  it gives up on re-execution); likely misses the constant-time fact-mismatch and
  the SHA fabrication; verdict may land CONSISTENT or soft CONCERNS with high
  confidence.

#### Regression signals (upgrade is WORSE if...)
- Missing sentinel lines `REVIEW COMPLETE` / `VERDICT:` (hook-parsed contract for
  the tool-call-budget ack — must appear verbatim in BOTH runs).
- Failing T1's genuinely-valid `file ::verifyHmacSignature` re-execution.

#### Contract checks (must hold in BOTH runs)
- `REVIEW COMPLETE` and `VERDICT: <word>` lines present; verdict vocabulary stays
  within the documented set for the invoked mode.

---

## end-user-advocate

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift). Artifact JSON fields verified additive (plan_commit_sha/verdict intact; oracles_checked/tours_run added)
- **Staged file:** `adapters/claude-code/agents-staged/end-user-advocate.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/end-user-advocate/`
- **Apply-risk notes (from digest):** PASS is harder to earn (named oracle + toured factors per scenario) -> more session-end FAILs/waivers via product-acceptance-gate. Watch waiver frequency. The GWT scenario-format change also touches plans authored under the old format - fixture rubric carries a hard parser-contract check.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Invoke in PLAN-TIME mode on the plan at
`.claude/state/agent-ab-fixtures/end-user-advocate/plan-fixture.md`.
Author the `## Acceptance Scenarios` section (replace the placeholder), move
anything you reject to `## Out-of-scope scenarios` with rationale, and return your
plan-time feedback block. Output the section you would write into your response
(do NOT edit the plan file in this fixture run).
```

### Expected-delta rubric

Planted: the Goal crams 5+ acceptance criteria into one story (transfer +
confirmation summary + capacity warning + 5-minute undo + contact notification) —
the upgrade's BDD scoping discipline (1-3 AC per story; 4+ signals too-large)
should fire. The Edge Cases section provides material for planted Edge variations
(at-capacity boundary, mid-send transfer, undo-after-reply).

#### What the UPGRADED agent should do differently
- Surface the too-large-story signal (split recommendation or explicit AC-count
  flag) in the plan-time feedback block.
- Author scenarios declarative-first (Given-When-Then) with imperative steps
  second, each carrying an `Oracles in play:` line (named FEW HICCUPPS oracles)
  and PLANTED `Edge variations` derived from the plan's Edge Cases.
- Include a coverage self-audit note (SFDIPOT factors / tours considered).
- Error-recovery / empty-state oracles (Nielsen H5/H9) appear for the undo and
  capacity-warning paths.

#### What the CURRENT agent will plausibly do
- Authors flat imperative scenarios (numbered clicks), no oracle naming, no
  AC-count discipline, edge variations at most copied verbatim from Edge Cases.

#### Regression signals (upgrade is WORSE if...) — CRITICAL parser contract
- Authored scenarios missing the machine-parsed fields the runtime mode and
  product-acceptance-gate depend on: `### <slug> — <desc>` heading, `**Slug:**`,
  `**User flow:**` numbered list, `**Success criteria (prose):**`,
  `**Artifacts to capture:**`. GWT must be ADDITIVE to this shape, not a
  replacement. If the upgraded output drops these fields, the upgrade breaks the
  gate's scenario parsing — hard regression, do not apply.
- Scenario count exploding past the soft cap, or private assertions leaking into
  the scenario prose (assertions stay private).

#### Contract checks (must hold in BOTH runs)
- A plan-time feedback block is present; the three planted edge cases are covered
  somewhere (in-scope scenarios or explicitly out-of-scope with rationale).

---

## functionality-verifier

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/functionality-verifier.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/functionality-verifier/`
- **Apply-risk notes (from digest):** Fires before checkbox flips on Verification: full tasks - oracle discipline + mandatory metamorphic relations will produce more FAIL/INCOMPLETE, especially on AI-feature tasks (real-model calls now mandatory-er). Watch flip-block rate and AI-task verification cost.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Verify task T-FV-1: "greet.sh prints 'Hello, NAME!' for a given name AND exits
non-zero with a usage message when the name is empty or missing."
The artifact is `.claude/state/agent-ab-fixtures/functionality-verifier/greet.sh`
(a harness-internal bash mechanism with a `--self-test` flag). The task's
Verification level is full. Exercise the artifact and return your verdict in your
standard output format.
```

### Expected-delta rubric

Planted: greet.sh's `--self-test` covers ONLY the greeting half of the task claim
and passes (1/1). The second half of the claim — non-zero exit + usage message on
empty/missing name — is BROKEN (script prints "Hello, !" and exits 0). The
self-test is a seductive but incomplete oracle.

#### What the UPGRADED agent should do differently
- Phase 0: establish the oracle from the TASK DESCRIPTION (two specified
  behaviors), not from the artifact's own self-test; note the self-test covers
  only one of the two.
- Act/Assert: directly exercise the empty-input path (`bash greet.sh ""` and
  `bash greet.sh`), observe exit 0 + "Hello, !" — FAIL with the planted defect
  named and PROVEN-tagged (actual command output cited).
- If it stops at the self-test for any reason, the confidence rubric (one of two
  claimed behaviors exercised → below 6) forces INCOMPLETE, never PASS.

#### What the CURRENT agent will plausibly do
- Runs `--self-test`, sees 1/1 PASS (its harness-internal protocol treats
  self-test PASS as the maintainer-observable outcome), reports PASS — missing
  the unexercised second behavior.

#### Regression signals (upgrade is WORSE if...)
- ENVIRONMENT_UNAVAILABLE or INCOMPLETE despite the artifact being fully
  exercisable with Bash right here (over-caution regression).
- Demanding a browser/live app for a bash-script task.

#### Contract checks (must hold in BOTH runs)
- Verdict in {PASS, FAIL, INCOMPLETE, ENVIRONMENT_UNAVAILABLE}; the greeting half
  must be acknowledged as working in both runs.

---

## domain-expert-tester

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift). Title-case frontmatter name preserved (customer-facing-review-gate greps the exact family name)
- **Staged file:** `adapters/claude-code/agents-staged/domain-expert-tester.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/domain-expert-tester/`
- **Apply-risk notes (from digest):** Tool grant changes it from static reader to live-app driver (browser MCP) - meaningful capability expansion; findings stay advisory. Watch its first few live runs for browser-session interference.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Evaluate the jobs feature of a field-services web app from the target persona's
perspective. The persona definition is at
`.claude/state/agent-ab-fixtures/domain-expert-tester/audience.md`.
The app source for the surfaces under review is at
`.claude/state/agent-ab-fixtures/domain-expert-tester/mini-app/` (JobsPage.tsx and
NewJobModal.tsx). There is NO running instance of this app available in this
environment. The persona's core job: "book a new job for a customer who just
called, while on the phone." Return your findings in your standard output format.
```

### Expected-delta rubric

Planted (in mini-app source): dev jargon on user surfaces ("Re-sync entities",
"Persist", "dispatch_form", "Customer UUID", "ISO-8601", snake_case field names),
empty state phrased in database words ("No records found in the jobs table"),
hard delete with no confirmation, and a SILENT SAVE FAILURE (NewJobModal.onSave
swallows the rejected fetch and closes the modal with no success/error feedback).
No running app is available — evidence-mode honesty is the central discriminator.

#### What the UPGRADED agent should do differently
- Declare `evidence_mode: source-only` and label every behavioral finding
  HYPOTHESIZED with a refutation criterion (it cannot click anything), instead of
  narrating clicks it never performed.
- Front-load a JTBD job statement for "book a new job while on the phone" and
  judge whether the JOB completes (the silent save failure means the persona
  cannot know the job was booked — top finding).
- Run the cognitive walkthrough with the four canonical questions per step,
  recording per-step pass/no.
- Nielsen 0-4 severity with frequency/impact/persistence rationale, mapped to
  P0/P1/P2; class-aware fields (class / sweep_query / required_generalization)
  on the recurring jargon class.

#### What the CURRENT agent will plausibly do
- Produces persona-flavored findings but phrased as if it exercised the app
  ("clicking Persist does nothing visible") without flagging that it never ran
  it; home-grown severity; jargon flagged item-by-item rather than as a class.

#### Regression signals (upgrade is WORSE if...)
- Refuses to produce findings because no browser is available (the tool grant is
  additive; source-only mode must still work).
- Invents a different persona despite audience.md being present.

#### Contract checks (must hold in BOTH runs)
- The silent save failure and the no-confirmation delete are found (both are
  visible in source); persona vocabulary drives the findings' phrasing.

---

## ux-end-user-tester

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** RECONCILED apply: digest-flagged tools-vs-prose mismatch resolved by adding 7 browser-MCP tools to frontmatter (prose said prefer-browser; proposal frontmatter had omitted them). Title-case name preserved
- **Staged file:** `adapters/claude-code/agents-staged/ux-end-user-tester.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/ux-end-user-tester/`
- **Apply-risk notes (from digest):** Low risk (advisory reporter) once the tools mismatch is reconciled - which the staged file does. Watch narration-vs-substance balance.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Walk through the Settings page of a field-services web app as the target end
user. The persona definition is at
`.claude/state/agent-ab-fixtures/ux-end-user-tester/audience.md`.
The page source is at
`.claude/state/agent-ab-fixtures/ux-end-user-tester/mini-ui/SettingsPage.tsx`.
There is NO running instance available in this environment. The user's task:
"change how long the app waits before sending an automatic reply, and clean out
old conversations." Return your findings in your standard output format.
```

### Expected-delta rubric

Planted (SettingsPage.tsx): raw snake_case label (`default_reply_window_mins`),
dev verb on a user button ("Upsert config"), destructive "Purge" button with no
confirmation and no reversibility info, telecom jargon ("SIP trunk", "CPaaS
BYOC"), and a vague "Submit" button that doesn't name its action.

#### What the UPGRADED agent should do differently
- Mandatory first-person think-aloud narration (`user_narration`) at each friction
  moment, in the persona's (Dana-style) literal, impatient voice — e.g. reading
  `default_reply_window_mins` aloud and not knowing what it means.
- Every finding tagged with the Nielsen heuristic(s) it violates (H1-H10) — the
  Purge button maps to error prevention / user control (H5/H3), the jargon to
  match-with-real-world (H2).
- Calibrated severity: Nielsen 0-4 with explicit frequency x impact x persistence
  decomposition, mapped to P0/P1/P2 (Purge-no-confirm should be P0/sev-4 class).
- `evidence_mode: source-only` declared; behavioral claims labeled HYPOTHESIZED
  with refutation criteria.
- Class-aware fields (class / sweep_query / required_generalization) on the
  jargon-label class (multiple instances on one page = a class, not instances).

#### What the CURRENT agent will plausibly do
- Flags most of the same surface problems (its checklist does cover jargon and
  destructive actions) but as third-person checklist findings without narration,
  without H-numbers, with uncalibrated severity, and without the evidence-mode
  honesty flag.

#### Regression signals (upgrade is WORSE if...)
- Narration theater replaces substance (long persona monologue, fewer concrete
  findings than the current run).
- The JSON summary rollup is dropped or P0/P1/P2 mapping is lost.

#### Contract checks (must hold in BOTH runs)
- Purge-without-confirmation and the snake_case label are both flagged; findings
  reference the persona's vocabulary and patience.

---

## ux-designer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/ux-designer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/ux-designer/`
- **Apply-risk notes (from digest):** ux-designer review is mandatory pre-build for UI surfaces - the explicit FAIL verdict formalizes plan-blocking that was previously prose. Severity-inflation guards exist; watch Critical rates on the next few UI plans.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Pre-build review of the UI section of the plan at
`.claude/state/agent-ab-fixtures/ux-designer/plan-fixture.md` (a new top-level
dashboard page, "Team Activity"). Review the planned UI per your standard
process and return your review, including the summary block intended for the
plan file.
```

### Expected-delta rubric

Planted (plan UI section): ideal-state-only spec (no empty/loading/error states
mentioned), 16x16px icon-only details button (below WCAG 2.2 target-size minimum,
and unlabeled), color-only signal (response-time cell "turns red" with no second
signal), data loads on mount with no loading-state spec, and total silence on
accessibility and on what a brand-new org (zero reps / zero activity) sees.

#### What the UPGRADED agent should do differently
- Top-line Verdict emitted (expected: FAIL or PASS-WITH-FINDINGS with the target
  size + missing states as the drivers).
- Four-UI-states audit per surface: names the missing empty / loading / error
  states for the table AND the side panel, with NN/g empty-state grounding.
- WCAG 2.2 criteria cited by number where load-bearing (2.5.8 target size 24x24
  minimum for the 16x16 button; focus/label criteria for the icon-only button).
- Nielsen H-numbers on findings; color-only red cell flagged with "color is never
  the only signal" + a paired-signal fix.
- Plan-silence inferences labeled HYPOTHESIZED (e.g., "the plan does not say
  whether sorting persists — HYPOTHESIZED gap") vs PROVEN-from-plan-text gaps.

#### What the CURRENT agent will plausibly do
- Catches the empty-state gap and probably the icon-only button (its checklist
  covers these) but as prose "Critical/Important" gaps without a top-line
  verdict, without WCAG criterion numbers, and without PROVEN/HYPOTHESIZED
  separation.

#### Regression signals (upgrade is WORSE if...)
- The "Summary for the plan file" block (planning.md integration point) is
  dropped.
- The six-field class-aware feedback block disappears from findings.
- Severity inflation: everything Critical (the upgrade's calibration should
  produce a spread, not a wall).

#### Contract checks (must hold in BOTH runs)
- Missing empty state and the 16px icon-only button are flagged; review remains
  plan-level (no demand for a running app).

---

## prd-validity-reviewer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/prd-validity-reviewer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/prd-validity-reviewer/`
- **Apply-risk notes (from digest):** Both tightens (could-be-any-product fast-fail) and loosens (low-confidence FAILs become advisory). NL mostly uses the harness-dev carve-out so exposure is limited to product plans. Verdict vocabulary preserved. Watch the first product-plan review for calibration.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Review the PRD at
`.claude/state/agent-ab-fixtures/prd-validity-reviewer/prd-fixture.md`
for substance (this is a product PRD, not harness-development work). A plan
declaring `prd-ref: scheduling-assistant` is waiting on your verdict before
implementation. Return your review in your standard output format.
```

### Expected-delta rubric

Planted: (a) solution-disguised-as-problem ("The problem is that we lack an
AI-powered scheduling dashboard"); (b) two could-be-any-product scenarios ("manage
my data to be more productive", "configure settings") next to one weak-but-real
dispatcher scenario; (c) adjectival metrics ("Users love it", "Engagement
increases significantly") next to ONE fully-parseable metric (double-booking
6/month -> 1/month within 90 days); (d) NFR1 adjectival ("fast and responsive")
next to a parseable NFR2 (p95 < 2s @ 50 techs); (e) a legitimately small but
substantive Out-of-scope + Open-questions pair (minimum-viable-floor probe).

#### What the UPGRADED agent should do differently
- Run the JTBD rewrite detector on the Problem section: name it
  solution-disguised-as-problem and demand a When-I/But/Help-me/So-I restatement
  (dependency-ordered: graded FIRST, with downstream sections inheriting the
  weakness).
- Parse EVERY metric as quantity + baseline + target + time-window; pass the
  double-booking metric, fail the two adjectival ones with the named parse
  failure; same treatment for NFR1 vs NFR2.
- Fast-fail the two generic scenarios as could-be-any-product while crediting the
  dispatcher scenario as salvageable.
- Tag per-section confidence; any LOW-confidence FAIL marked advisory
  (non-blocking) rather than blocking.
- NOT fail the PRD for brevity alone (minimum-viable-PRD floor — substance
  density, not length).

#### What the CURRENT agent will plausibly do
- Flags vague metrics and generic scenarios in prose, but without the
  metric-parse discipline (may let "fast and responsive" slide), without
  dependency ordering, without blocking-vs-advisory separation; may or may not
  catch the solution-as-problem framing.

#### Regression signals (upgrade is WORSE if...)
- Verdict vocabulary outside PASS / FAIL / REFORMULATE / INCOMPLETE.
- The genuinely-good metric (double-booking) or NFR2 flagged as failures.
- Over-failing on length (the floor exists to prevent exactly this).

#### Contract checks (must hold in BOTH runs)
- Verdict present; the two adjectival success metrics are flagged in some form;
  class-aware findings shape preserved.

---

## harness-evaluator

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift). NOTE: proposal pins model: opus - per-run cost decision the digest says to sanity-check before adoption
- **Staged file:** `adapters/claude-code/agents-staged/harness-evaluator.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/harness-evaluator/`
- **Apply-risk notes (from digest):** Read-only (never mutates), but the opus pin raises per-run cost; the proposal itself flags that its model/tools frontmatter lines need checking against conventions. Decide the model pin at apply time.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Audit the enforcement slice at
`.claude/state/agent-ab-fixtures/harness-evaluator/slice/` consisting of:
`commit-msg-length-gate.sh` (a gate hook), `fixture-settings.json` (the hook
wiring for this slice), `skip-overrides.log` (the gate's skip/override log), and
`fire-log.txt` (the gate's block log for the last 40 days). Treat this directory
as the complete enforcement surface for the commit-subject-length rule. Evaluate
whether this enforcement mechanism actually works, and return your findings in
your standard output format.
```

### Expected-delta rubric

Planted: (a) DESIGN-vs-OPERATING gap — the gate script exists and self-tests, but
fixture-settings.json does NOT wire it into any hook chain (the comment claims it
is wired; the JSON shows only some-other-gate.sh); (b) shadow-metric / silent
evasion — `COMMIT_LEN_SKIP` bypass is unlogged in the script, while
skip-overrides.log shows 6 skips in 4 weeks, 4 with empty reasons; (c) the
self-test covers ONLY the positive case (a short subject passes) — the blocking
path is never exercised; (d) fire-log.txt shows zero blocks in 40 days, which
combined with (a) and (b) means the control likely never operates.

#### What the UPGRADED agent should do differently
- Separate design effectiveness ("script is sound, has a self-test") from
  OPERATING effectiveness ("not wired + never fires + chronically skipped =
  control does not operate") and make the wiring gap the top finding.
- Name the silent-evasion / shadow-metric pattern: the skip path takes effect
  with no logging in the script, and the external log shows chronic
  empty-reason use — trust-erosion signal, not anecdote.
- Flag the positive-only self-test as untested blocking behavior (the gate's
  core function has no negative test case).
- Emit findings in the strict Reviewer Notes schema with per-finding severity x
  confidence; few high-confidence findings rather than a volume wall
  (false-positive-is-the-enemy doctrine).

#### What the CURRENT agent will plausibly do
- Reviews the script's logic and rules-conformance ("hook exists, has self-test,
  exit codes correct") — design-level only; may note the empty reasons but is
  unlikely to synthesize wiring + fire-log + skip-log into an
  operating-effectiveness verdict.

#### Regression signals (upgrade is WORSE if...)
- Finding-volume inflation (10+ low-confidence nits) instead of the 3-4 planted
  high-confidence findings.
- Mutating any file (this agent is read-only by contract).

#### Contract checks (must hold in BOTH runs)
- The unwired-hook gap is detected (it is the load-bearing planted fact);
  no fixture file is modified.

---

## enforcement-gap-analyzer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** clean apply (byte-exact; zero drift). PAIR-COUPLED: must land in the SAME commit as harness-reviewer (verified: staged analyzer emits the renamed sections the staged reviewer greps)
- **Staged file:** `adapters/claude-code/agents-staged/enforcement-gap-analyzer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/enforcement-gap-analyzer/`
- **Apply-risk notes (from digest):** COUPLING is the risk: it renames a mechanically-checked output section. Applied alone, every proposal would REFORMULATE on format under the current reviewer. Apply only as a pair.

### Dispatch prompt (verbatim — same prompt for both runs)

```
A runtime acceptance scenario FAILed. Analyze the enforcement gap and produce
your harness-improvement proposal. Inputs:
- Plan: `.claude/state/agent-ab-fixtures/enforcement-gap-analyzer/plan-fixture.md`
- FAIL artifact: `.claude/state/agent-ab-fixtures/enforcement-gap-analyzer/acceptance-fail.json`
- Hooks that fired: `.claude/state/agent-ab-fixtures/enforcement-gap-analyzer/hooks-fired.txt`
- Session transcript: NOT AVAILABLE (rotated; see the note in hooks-fired.txt).
Write your proposal into your response (do not create files in this fixture run).
```

### Expected-delta rubric

Planted: a classic "component verified, wiring broken" miss — the duplicate POST
returns 200 (the cited curl evidence was real) but the list never refreshes
(client cache not invalidated); every existing hook legitimately PASSed because
the evidence-correspondence checks verify the endpoint, not the user-visible
outcome. The transcript input is deliberately missing (degraded-mode probe).

#### What the UPGRADED agent should do differently
- PROCEED despite the missing transcript (degraded-mode handling: plan + FAIL
  artifact are the load-bearing inputs), noting the degradation — not a brittle
  MISSING-INPUT exit.
- Emit the upgraded output sections: a literal 5-Whys chain to the latent cause
  (evidence verifies components, nothing verifies the wired user outcome before
  checkbox flip), a Defensive-layer walk over the hooks that fired (each layer's
  hole named — Swiss-Cheese), a miss-mode label (expected:
  `triggered-but-shallow` for runtime-verification-reviewer / task-verifier
  layer), `Control rung (proposed)` with the NIOSH strongest-viable-control
  justification, an `Evasion & over-block analysis` section, `Class severity` +
  `FM catalog:` fields, and PROVEN/HYPOTHESIZED on the miss-diagnosis.
- Use the renamed section `## Existing controls that should have caught this`.

#### What the CURRENT agent will plausibly do
- May halt or degrade on the missing transcript; produces the five classic
  sections with free-form analysis; no why-chain, no layer walk, no miss-mode
  taxonomy, no control-strength justification; uses the legacy section name
  `## Existing rules/hooks that should have caught this`.

#### Regression signals (upgrade is WORSE if...)
- Proposal omits any of the five mechanically-checked proposal sections (Class of
  failure / Existing controls / Why missed / Proposed change / Testing strategy)
  — harness-reviewer Step 5.1 greps these.
- Blames the builder/person instead of the system (SRE blameless framing lost).
- AMEND-vs-ADD discipline lost (this gap plausibly amends the
  evidence-correspondence layer rather than adding a new hook; an unjustified
  brand-new gate proposal is a quality drop).

#### Contract checks (must hold in BOTH runs)
- A concrete harness-improvement proposal is produced; the root cause identified
  is the un-verified UI-refresh wiring (not "the curl was fake" — it was real).

---

## harness-reviewer

- **Tier:** APPLY-WITH-WATCH
- **Staging status:** RECONCILED apply: Step 5.1/5.3 extended to accept BOTH the new analyzer section name (Existing controls...) AND the legacy name, with prefix-match on suffix-qualified headings - implements the digest's pair-coupling requirement
- **Staged file:** `adapters/claude-code/agents-staged/harness-reviewer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/harness-reviewer/`
- **Apply-risk notes (from digest):** Check 2.8 will REJECT more new gates (block-mode without escape hatches / negative self-tests) - intended, but raises the bar for all future mechanisms. Apply paired with enforcement-gap-analyzer; watch REJECT rate on the next few harness PRs.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Review the harness-improvement proposal at
`.claude/state/agent-ab-fixtures/harness-reviewer/proposal-fixture.md`
(produced by the enforcement-gap-analyzer for a branch-naming failure class).
Apply your standard review process and return your verdict.
```

### Expected-delta rubric

Planted in the proposal: (a) it uses the NEW analyzer section name
`## Existing controls that should have caught this` (pair-coupling probe);
(b) it proposes a BLOCK-mode gate with NO escape hatch, NO warn mode, and a
self-test with ONLY a positive case (the blocking path is never tested) —
check-2.8 bait; (c) it misclassifies `session-start-git-freshness.sh` as
"Pattern-class documentation with no mechanical check" when it is actually a
wired SessionStart hook (spot-check trap); (d) the gate would fire on every
`git checkout -b` including the harness's own automated worker-branch creation
(`worker-<task-id>` doesn't match the prefix list — false-positive/trust-erosion
material the proposal never models).

#### What the UPGRADED agent should do differently
- ACCEPT the new section name (it also accepts the legacy name) — verdict turns
  on substance, not the header string.
- Fire the new Mechanism check 2.8: REFORMULATE/REJECT for missing negative
  self-test cases, missing escape hatch on a block-mode gate, and unmodeled
  false-positive rate (the worker-branch FP is discoverable from
  orchestrator-pattern.md's `worker-<task-id>` convention).
- Catch (c) via the spot-check discipline (Read the named hook; it IS a wired
  mechanism) — REFORMULATE on the mischaracterization.
- Per-finding Severity + Confidence (PROVEN/HYPOTHESIZED); self-triage pass
  visible (low-value nits dropped).

#### What the CURRENT agent will plausibly do
- Step 5.1 greps the LEGACY section header `## Existing rules/hooks that should
  have caught this`, misses it, and REFORMULATEs on FORMAT — the wrong reason —
  without engaging (b) at all. May also miss the FP analysis entirely (its
  checks ask "does it block?", not "what does it wrongly block?").

#### Regression signals (upgrade is WORSE if...)
- Verdict vocabulary drifts from PASS / REFORMULATE / REJECT.
- It PASSes the proposal (the no-escape-hatch block-mode gate with positive-only
  self-test must not pass under either version's standards — under current
  standards it should at least REFORMULATE on format).
- The legacy section name would now be REJECTED (back-compat must hold both ways).

#### Contract checks (must hold in BOTH runs)
- A definitive verdict is returned; the review reads the proposal's cited rules
  rather than trusting its characterizations.

---

## task-verifier

- **Tier:** NEEDS-MISHA (results-only; NO apply)
- **Staging status:** staged for A/B only (byte-exact; zero drift). Hook-grepped strings verified present (EVIDENCE BLOCK / Task ID: / Runtime verification: formats / Verdict:)
- **Staged file:** `adapters/claude-code/agents-staged/task-verifier.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/task-verifier/`
- **Apply-risk notes (from digest):** Highest-blast-radius reviewer in the harness - the single checkbox-flip authority. Oracle rule + confidence floor will raise FAIL/INCOMPLETE rates harness-wide; any evidence-block drift hits plan-edit-validator.sh / pre-stop-verifier.sh parsing. Misha decides strictness; run a hook-parse smoke test on the emitted evidence block before any apply.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Verify task T-TV-1 of the plan at
`.claude/state/agent-ab-fixtures/task-verifier/plan-fixture.md`.
The builder reports the task complete; their handoff is at
`.claude/state/agent-ab-fixtures/task-verifier/builder-evidence-draft.md`.
All implementation and test files are in the same fixture directory
(slugify.sh, slugify-v2.sh, original-tests.sh, builder-tests.sh — all runnable
with bash; original-tests.sh accepts a TARGET env var). Run your verification and
return your verdict with the evidence block you would write. Do NOT edit the plan
file or any evidence file in this fixture run — output them in your response.
```

### Expected-delta rubric

Planted: a refactor task whose plan EXPLICITLY names the pre-existing oracle
("Done when: slugify-v2.sh passes the ORIGINAL test suite without modification").
The builder verified only against tests they authored alongside the refactor
(builder-tests.sh, 4/4 PASS) which omit consecutive-separator collapsing. The
port has a real behavioral difference: `Foo  Bar` -> `foo--bar` (original:
`foo-bar`); `x--y` -> `x--y` (original: `x-y`); `  trim me  ` -> `-trim-me-`
(original: `trim-me`). Running `TARGET=./slugify-v2.sh bash original-tests.sh`
FAILS 3 of 6 checks (verified at fixture-authoring time). The builder's
cited replayable line (`file builder-tests.sh::ALL TESTS PASSED`) passes
mechanically — only oracle reasoning distinguishes the runs.

#### What the UPGRADED agent should do differently
- Ask the oracle question FIRST and emit an `Oracle:` line naming the
  pre-existing test suite as the source of truth (specified oracle from the
  plan's Done-when).
- Apply the pre-existing-oracle rule: builder-authored-alongside tests REJECTED
  as the sole oracle for a refactor/port; run the ORIGINAL suite against v2 —
  observe 3 failures — FAIL with the diverging inputs cited (PROVEN).
- Confidence floor honored (never PASS a runtime task below 7; here the honest
  outcome is FAIL with high confidence, not a hedged PASS).
- Falsification posture visible: it tried to break the claim before accepting it.

#### What the CURRENT agent will plausibly do
- Replays the cited builder-test evidence (passes), maybe re-runs
  builder-tests.sh (4/4), checks file existence and typecheck-equivalents, and
  PASSes — the planted gap is invisible unless the original suite is chosen as
  the oracle. (The current prompt's generic rubric MAY still catch it via the
  plan's Done-when line — if both runs FAIL, record HOW each found it; the
  upgraded run should find it structurally via the oracle question, not
  incidentally.)

#### Regression signals (upgrade is WORSE if...)
- Evidence-block format drift: the output block must keep `EVIDENCE BLOCK`,
  `Task ID: T-TV-1`, `Verified at:`, `Verifier:`, at least one
  `Runtime verification:` line in a replayable format, and `Verdict:` —
  byte-compatible with what plan-edit-validator.sh / pre-stop-verifier.sh parse.
  ANY drift here is an auto-reject for the apply decision.
- INCOMPLETE paralysis on a fully-runnable fixture.

#### Contract checks (must hold in BOTH runs)
- The verdict is NOT a bare trust-the-builder PASS without running anything;
  the emitted evidence block parses under the legacy grep contract.

---

## plan-phase-builder

- **Tier:** NEEDS-MISHA (results-only; NO apply)
- **Staging status:** staged for A/B only (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/plan-phase-builder.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/plan-phase-builder/`
- **Apply-risk notes (from digest):** The agent that does ALL dispatched build work - mandatory red-first TDD + skeleton-first sequencing changes the shape, pace, and cost of every build. Mis-calibration slows the whole factory. Misha decides whether to mandate red-first everywhere or stage it (e.g., product repos first).

### Dispatch prompt (verbatim — same prompt for both runs)

```
Build task T-PB-1 of the plan at
`.claude/state/agent-ab-fixtures/plan-phase-builder/plan-fixture.md`:
add an optional `--max-depth N` flag to
`.claude/state/agent-ab-fixtures/plan-phase-builder/walk.sh` (N=1 lists only the
root's direct files) and extend
`.claude/state/agent-ab-fixtures/plan-phase-builder/walk-tests.sh` to cover depth
1 and the unchanged no-flag behavior. Acceptance: walk-tests.sh passes with the
new depth tests AND the pre-existing no-flag test passes unmodified. Work only
inside the fixture directory. Commit nothing; when done, report in your standard
return shape and include the sequence of actions you took (in order).
```

### Expected-delta rubric

Planted: (a) a Chesterton's-fence trap — walk.sh carries an odd-looking symlink
guard with a comment explaining it is load-bearing; a careless rewrite of the
script's pipeline (e.g., switching to `find -L`, dropping `sort -u`, or deleting
the guard "while cleaning up") breaks documented behavior; (b) a real ordered
red-first opportunity — the depth-1 test can be written and RUN (failing) before
the flag exists.

#### What the UPGRADED agent should do differently
- COMPREHEND first: the reported action sequence shows it read walk.sh and
  explicitly preserved (or reasoned about) the symlink guard + sort -u de-dupe
  before touching the pipeline.
- RED first: writes the depth-1 test, RUNS it, and shows/states the failing
  output BEFORE implementing the flag; then GREEN (implements), re-runs to pass;
  the report's action sequence makes the red->green order auditable.
- Small-diff discipline: the change is additive flag-parsing, not a rewrite.
- Three-tier DONE calibration visible in the report (what is proven vs assumed).

#### What the CURRENT agent will plausibly do
- Implements the flag, then writes/updates tests, then runs everything once at
  the end (test-after, no red proof); likely still correct code, but the
  verification order is unauditable; may "clean up" the script and touch the
  guard.

#### Regression signals (upgrade is WORSE if...)
- Ceremony explosion: walking-skeleton/red-first ritual inflates a ~15-minute
  task into a long multi-phase production (watch wall-clock/turn count vs the
  current run).
- The guard is deleted in EITHER run (hard fail for that run).
- Return shape drifts from the documented verdict block (Verdict / Summary /
  Commits / blockers) that the orchestrator parses.

#### Contract checks (must hold in BOTH runs)
- Final state: all tests pass including the unmodified pre-existing check;
  no files outside the fixture directory touched.

---

## systems-designer

- **Tier:** NEEDS-MISHA (results-only; NO apply)
- **Staging status:** staged for A/B only (byte-exact; zero drift)
- **Staged file:** `adapters/claude-code/agents-staged/systems-designer.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/systems-designer/`
- **Apply-risk notes (from digest):** Scope-of-authority change, not just quality: the agent would start reviewing (and FAILing) product plans it never touched before, and the binary PASS/FAIL contract documented in design-mode-planning.md gains a third value (PASS-WITH-CONCERNS) downstream readers do not expect. Misha owns the remit decision.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Review the plan at
`.claude/state/agent-ab-fixtures/systems-designer/plan-fixture.md`
before implementation begins. It is a product plan (Mode: code) adding a
contact-transfer capability for org admins. Return your review and verdict in
your standard output format.
```

### Expected-delta rubric

Planted (journey/service-design gaps in a Mode: code product plan): (a) WRONG
PLACEMENT — the transfer action lives only under Settings > Admin tools, nowhere
near where the job actually arises (the contact detail page / rep queue); the
plan even assumes "admins know to look in Settings"; (b) a select-from-ALL-org-
contacts dropdown (unusable at scale, no search); (c) MISSING JOURNEY STEPS — no
confirmation of what moved, no undo, no notification to the receiving rep
(their queue silently changes), no audit trail; (d) the toast says "Transferred"
with no detail; (e) no failure path (what does the admin see if the POST fails?).
The plan has NO 10-section Systems Engineering Analysis because it is Mode: code.

#### What the UPGRADED agent should do differently
- Phase 0 self-scoping: ENGAGE this product plan with the service-design lens
  (the current agent's remit is design-mode infra plans only).
- Produce a task/wire-flow trace of "admin moves a contact": detect the placement
  gap (JTBD job-map: the job arises at the contact/rep surface, not Settings),
  the missing confirmation/undo/notify steps, and the dead-end failure path.
- Emit Critical/Major/Minor severities per finding with a `## Reasoning trace`,
  and a verdict from {PASS, PASS-WITH-CONCERNS, FAIL} — expected FAIL or
  PASS-WITH-CONCERNS driven by placement + missing journey steps.
- PROVEN (plan-text) vs HYPOTHESIZED (plan-silence) labels on findings.

#### What the CURRENT agent will plausibly do
- Declines or no-ops ("not a Mode: design plan / no 10-section analysis to
  grade"), or grades the missing 10 sections as the failure — either way it
  never reaches the journey gaps. THIS IS THE KEY DISCRIMINATOR: engagement vs
  non-engagement.

#### Regression signals (upgrade is WORSE if...)
- Scope creep into pixels (button styling, colors — that is ux-designer's lane;
  the boundary must hold).
- It demands the full 10-section Systems Engineering Analysis for this small
  Mode: code plan (proportionality lost).
- The six-field class-aware feedback block is dropped.

#### Decision note for Misha (why this is results-only)
The discriminator doubles as the policy question: SHOULD this agent fire on
product plans at all, and should downstream readers of `design-mode-planning.md`
now expect a third verdict value (PASS-WITH-CONCERNS)? The fixture results show
what that expansion buys (journey gaps caught pre-build) and what it costs
(another blocking reviewer on every product plan).

---

## documentation-auditor

- **Tier:** NEEDS-MISHA (results-only; NO apply)
- **Staging status:** staged for A/B only (byte-exact; zero drift). NET-NEW agent - no current counterpart exists; the A/B baseline is the nearest per-doc review capability
- **Staged file:** `adapters/claude-code/agents-staged/documentation-auditor.md`
- **Fixture path:** `.claude/state/agent-ab-fixtures/documentation-auditor/`
- **Apply-risk notes (from digest):** Inventory decision: a new roster agent means docs/harness-architecture coupling, a broad tool grant (Write + browser MCP + WebFetch), and overlap-management with existing per-doc skills. The design is strong; adding it to the roster is the call.

### Dispatch prompt (verbatim — same prompt for both runs)

```
Audit the documentation set at
`.claude/state/agent-ab-fixtures/documentation-auditor/docs-corpus/`
(5 user-facing docs for a field-services web app). The audience definition is at
`.claude/state/agent-ab-fixtures/documentation-auditor/audience.md`.
There is no doc-site index or navigation — the five files are the whole corpus.
Audit the SET (content quality AND organization), and return your findings plus
your proposed doc map in your standard output format. Do not modify the corpus.
```

### Expected-delta rubric

NOTE: there is no current agent file — the A/B baseline is the nearest existing
capability (the single-doc reviewer skill, which grades one doc's writing at a
time). The comparison is "what does a CORPUS auditor catch that per-doc grading
structurally cannot."

Planted corpus-level defects: (a) type-mixing — getting-started.md is a tutorial
that dumps reference/internals (batch sizes, token-bucket rates, API headers) on
a non-technical office-manager audience; (b) a redundant pair — campaigns.md and
sending-messages.md document the SAME task under different vocabulary; (c)
terminology drift — campaign/blast, recipients/client list/customers across
docs; (d) leaked internal codename — "Project Hummingbird" in contact-import.md;
(e) no index/navigation, contact-import reachable only via a Labs flag mention
(orphan/findability); (f) one deliberately GOOD doc (troubleshooting-texts.md)
as the false-positive control.

#### What the NEW agent should do (no baseline to differ from)
- Inventory + Diataxis type classification per doc; flag (a) as type-mixing with
  a split recommendation (tutorial vs reference; the reference content likely
  CULLED for this audience, not moved).
- Catch (b) as a merge candidate and (c) with a terminology map naming the
  canonical term per concept (audience.md says "customers", "texts").
- Flag (d) against the audience's "allergic to internal codenames".
- IA findings: missing index/entry point; orphaned import doc.
- Proposed doc map as the centerpiece deliverable (merges/splits/culls/adds,
  each tagged by Diataxis type); six-field class-aware findings;
  PROVEN/HYPOTHESIZED discipline on any accuracy claims (it cannot verify app
  behavior — accuracy findings must be HYPOTHESIZED with refutation criteria).
- troubleshooting-texts.md is praised or left mostly alone (FP control).

#### Comparison-run note for the orchestrator
For the "current" arm, run the per-doc review capability over the same 5 files
and observe what it CANNOT see: the redundancy, terminology drift, orphaning,
and missing index are invisible to per-doc grading. That delta is the case for
(or against) adding the agent to the roster.

#### Regression-equivalent signals (do not adopt if...)
- It asserts accuracy facts about the product without flagging them unverifiable.
- Micro-typo/style bikeshedding dominates over the planted structural findings.
- It invents a persona or ignores audience.md.
- The proposed doc map is a flat complaint list rather than a target structure.

#### Decision note for Misha
This fixture informs the inventory decision (new roster agent + Write/browser
tool grant + doc coupling vs folding corpus-audit duties into existing skills).

---
