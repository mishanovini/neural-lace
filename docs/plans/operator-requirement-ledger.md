# Plan: Operator-requirement ledger — make the operator's words a checkable artifact
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal; no user-facing UI surface. The functional demonstration is the artifact's own `--self-test`, per the functionality-verifier harness-internal rule.
tier: 2
rung: 3
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-08-05
prd-ref: n/a — harness-development

## Goal

Every verifier in this harness checks delivered work against a PLAN. `task-verifier`
re-derives each claim against `docs/plans/`; `harness-reviewer` attacks the design in
`docs/designs/`; `plan-evidence-reviewer` re-observes the evidence block. Between them
they caught roughly 15 real defects in the 2026-07-28/29 session. But every one of those
artifacts is the agent's *interpretation* of what the operator asked for. The operator's
requirement lives in chat, is filtered through that interpretation into a plan, and the
verifiers then faithfully verify the interpretation — including whatever it silently lost.

Two failures in that session, both verbatim, both from the same mechanism:

1. Operator: *"Fable is supposed to always fail back to Opus."* The agent built a gate
   that BLOCKED a Fable dispatch and told the caller to use Opus — satisfying "use Opus"
   while destroying "automatically". Reviewers checked it against the design doc and
   passed that aspect; nobody checked it against the sentence.
2. Operator: *"I don't want the agents to pin Opus. Opus is a fallback, not the primary
   option."* The previous fix had permanently repinned 21 agents to Opus — satisfying
   "use Opus as fallback" while destroying "Fable is primary".

The diagnosed mechanism: the agent treats a requirement as a GOAL TO DISCHARGE rather
than a SPECIFICATION WITH INVARIANTS. Once something discharges the verb, it stops
checking against the rest of the sentence, then writes a confident rationale for why that
was the right call. One sentence, two invariants, one preserved.

This plan makes the operator's verbatim requirement a first-class, durable, checkable
artifact, decomposes it into separately checkable invariants, and adds the checking step
that returns a per-invariant verdict.

## Scope

**IN** — three new record types on the EXISTING `ask-registry.sh` store
(`requirement_recorded`, `invariant_declared`, `invariant_verdict`) plus the six fields
they need; five new verbs (`record-requirement`, `declare-invariant`, `invariant-verdict`,
`invariants`, `invariant-check`); 16 self-test scenarios; a compact doctrine file; a
`task-verifier` protocol step (1.6) that runs the check and routes on its exit code; a
manifest entry carrying the full evidence bar; this plan.

**OUT** — explicit exclusions. (a) No new store — the harness has an explicit ≤3-store
consolidation goal (`docs/reviews/2026-07-27-accountable-estate-architecture-review.md`
F5/F6), and adding one would need justification this work does not have. (b) No new
blocking gate — 36 blocking entries already exist against ADR 058 D5's ≤12 target, so a
37th is indefensible without adoption evidence. (c) No automatic extraction of
requirements from the prompt stream: that is precisely the retired
`goal-extraction-on-prompt.sh` / `goal-coverage-on-stop.sh` narrative-gate class
(ADR 058 D5 — *"artifact checks block; narrative checks observe"*), and rebuilding it
would repeat a lesson this harness already learned and paid for. (d) No verdict-staleness
model — see Edge Cases. (e) No changes to any existing verb's behavior or record shape.

## Tasks

- [ ] T1 — Extend the `_ar_append_record` writer seam with six trailing optional fields
      (`requirement_id`, `verbatim`, `invariant_id`, `invariant_text`, `invariant_verdict`,
      `evidence_ref`), taking the record from 21 to 27 always-present fields, and document
      the ledger's reader contract in the SCHEMA header.
      `Verification: mechanical` · `Docs impact: none — the contract lives in the script's own SCHEMA header, which this task writes.`
- [ ] T2 — Add the three write verbs and the two read verbs, with the exit-code contract
      (0 pass / 1 fail / 3 nothing-registered / 4 cannot-evaluate).
      `Verification: full` · `Docs impact: adapters/claude-code/doctrine/operator-requirement-ledger.md`
- [ ] T3 — Add the self-test scenarios, decomposed by the property each one pins:
      `Verification: full` · `Docs impact: none — self-test output is the artifact.`
  - [ ] T3a — Verbatim preservation: RL1 (byte-exact through JSON escaping, quotes and
        backslashes) and RL2 (a 606-char requirement stored whole, never summarised).
  - [ ] T3b — Decomposition: RL3 (sequential, separately addressable invariant ids).
  - [ ] T3c — The checking contract: RL4 (absence is not a pass), RL5 (the golden case —
        a violated sibling is not discharged by its satisfied twin), RL6 (all-hold passes),
        RL7 (last-verdict-wins, including a same-second `ts` collision).
  - [ ] T3d — Refusals: RL9 (`holds` without a citation) and RL10 (verdict vocabulary).
  - [ ] T3e — Degrade honesty: RL12 (exit 3, nothing registered) and RL13 (exit 4, cannot
        evaluate), neither of which may read as a pass.
  - [ ] T3f — Non-interference and plumbing: RL8 (the cockpit title fold is untouched),
        RL11 (the `--plan-slug` back-link resolves), RL15 (the router propagates the exit
        code), RL14 and RL16 (TSV column integrity through the real bash `read` consumer).
  - [ ] T3g — Mutation-test each of the above: one semantically-valid reversion per
        scenario, each required to turn its named scenario RED.
- [ ] T4 — Add `task-verifier` Step 1.6 plus the `Operator invariants:` evidence-block line.
      `Verification: contract` · `Docs impact: adapters/claude-code/agents/task-verifier.md`
- [ ] T5 — Land the manifest entry (golden_scenario / fp_expectation / retirement_condition
      / honesty_rationale) and regenerate `doctrine/INDEX.md`.
      `Verification: mechanical` · `Docs impact: adapters/claude-code/doctrine/INDEX.md`

**Prove it works:** 1. `bash adapters/claude-code/scripts/ask-registry.sh record-requirement
--ask-id <ask> --verbatim 'I do not want the agents to pin Opus. Opus is a fallback, not
the primary option.'` 2. `declare-invariant` twice against the returned requirement id —
once for "Fable remains the declared primary", once for "Opus is used only while Fable is
unavailable". 3. `invariant-verdict` the second one `holds` with a citation. 4.
`invariant-check --requirement-id <r>` exits **1**, reporting `1/2 invariants hold` —
the satisfied invariant does not discharge its violated sibling. This is the 2026-07-29
failure replayed against the mechanism that would have caught it.

**Wire checks:** operator sentence → `adapters/claude-code/scripts/ask-registry.sh`
(`cmd_record_requirement`) → `_ar_append_record` → `ask-registry.jsonl`
(`requirement_recorded`) → `_ar_invariant_rows` → `cmd_invariant_check` →
`adapters/claude-code/agents/task-verifier.md` (`Step 1.6`) → `Operator invariants:`

**Integration points:** the existing `link-plan` back-link (`cmd_link_plan`) is what makes
`invariant-check --plan-slug <slug>` resolvable from a plan path, which is the only handle
`task-verifier` has. Verify: `ask-registry.sh invariant-check --plan-slug <slug>`;
`ask-registry.sh invariants --ask-id <id>`; `bash adapters/claude-code/scripts/manifest-check.sh`.

## Files to Modify/Create

Paths are backticked because the scope gate's bullet parser, on encountering any
backtick in a line, extracts ONLY backticked tokens — a plain path alongside a
backticked prose word yields zero entries.

- `adapters/claude-code/scripts/ask-registry.sh` — six fields on the writer seam; three
  record types; five verbs; RL1 to RL16 self-test; SCHEMA + usage docs.
- `adapters/claude-code/agents/task-verifier.md` — new Step 1.6, plus the operator-invariant
  line in the Step 7 evidence block.
- `adapters/claude-code/doctrine/operator-requirement-ledger.md` — new compact doctrine
  (under the 3000-byte cap).
- `adapters/claude-code/manifest.json` — new operator-requirement-ledger entry.
- `adapters/claude-code/doctrine/INDEX.md` — regenerated by manifest-check.sh --gen-index.
- `docs/plans/operator-requirement-ledger.md` — this plan.
- `docs/plans/operator-requirement-ledger-evidence.md` — builder runtime evidence.

## Assumptions

1. **`ask-registry.sh` is the right substrate, not a new store.** It already holds the
   operator's ask, already has a plan back-link, and the consolidation goal argues against
   a fourth store. Refuted if the registry's append-only single-writer model turns out not
   to hold under the workstreams-ui server's concurrent writes.
2. **Invariant extraction is judgment work, not parsing.** No regex can tell that "Opus is
   a fallback, not the primary option" carries two invariants. The decomposition is
   therefore agent-invoked by design, and the mechanism's job is to make the result
   durable and checkable rather than to produce it.
3. **`jq` is present for the read path.** Both read verbs degrade to exit 4, never to a
   pass, when it is absent. The write path deliberately does not depend on jq, so a
   requirement can always be recorded even where it cannot be read back.
4. **Opt-in is correct for a Pattern.** Because an unenrolled ask returns exit 3 rather
   than a failure, the ledger is silent until used. This trades adoption risk for
   zero false-fire risk — the right trade for an artifact with no measured FP rate.

## Edge Cases

- **A sentence with only one invariant.** Permitted, but the doctrine names it a smell and
  tells the reader to look again for the sibling — the golden case is precisely a missed
  sibling.
- **A blank evidence cell shifting every later TSV column.** TAB is an IFS-whitespace
  character, so bash `read -r a b c` collapses a run of tabs into one delimiter. Every
  emitted cell is therefore guaranteed non-blank (`-` when empty). Covered by RL14 (the
  no-verdict branch) and RL16 (the blank-cell guard), both asserted positionally through
  the real `read` consumer — an `awk -F'\t'` assertion cannot see this defect at all,
  because awk honours empty fields.
- **Two verdicts inside the same one-second `ts`.** A re-verification routinely lands in
  the same second as the verdict it supersedes, so `ts` alone is not a total order. The
  fold sorts by `[ts, append-index]`. RL7 fails loudly if no same-second collision was
  actually produced, rather than passing while never exercising the tiebreak.
- **A requirement containing quotes, backslashes, tabs or newlines.** Round-trips through
  `_ar_json_escape`; RL1 asserts byte-exact equality on a string carrying both quote and
  backslash.
- **A `holds` verdict with no citation.** Refused outright — an unevidenced pass is the
  defect this ledger exists to catch, so it is never persisted.
- **A requirement longer than 140 characters.** Stored whole. `_ar_truncate140`
  sentence-splits and ellipsises, which is the exact lossy step the ledger prevents; the
  ledger uses a plain 4000-char byte cap instead. RL2 asserts a 606-char requirement
  survives intact.
- **Verdict staleness (NOT handled).** A `holds` recorded against one commit is not
  invalidated by later commits. Mitigated only by the convention of citing a SHA in
  `--evidence`. Named in the manifest's `fp_expectation` as the residual false-pass risk.
- **The ask's cockpit title.** The title folds as last-non-empty `summary`, so a ledger
  record carrying a non-empty summary would silently rewrite it. All three record types
  abstain from `summary` and `title_source`; RL8 asserts the folded title is unchanged
  after 3 requirements, 3 invariants and 12 verdicts.

## Testing Strategy

`--self-test` scenarios RL1–RL16, sandboxed under `ASK_REGISTRY_STATE_DIR` /
`ASK_REGISTRY_MIRROR_PATH` / `PROGRESS_LOG_STATE_DIR` with `HARNESS_SELFTEST=1`.

**Every fixture is produced by the real verbs.** No hand-written JSONL is ever fed to the
reader, so the reader is never tested against a shape its producer does not actually emit.

**Every scenario is mutation-tested.** A separate harness copies the script, applies one
semantically-valid reversion of the code under test, and requires the named scenario to go
RED. Two guards keep the harness honest: the mutant must differ from the source (proving
the mutation applied at all), and it must still pass `bash -n` (proving the scenario went
red because behavior changed, not because the file became syntactically invalid — an early
draft of the harness produced exactly that false signal, since perl interpolates `$vars`
in the replacement half). Total failure counts are reported against the measured baseline
so a blanket breakage cannot be mistaken for a discriminating result.

Two real defects were caught this way and are now regression-covered: the tab-collapse
column shift (RL14/RL16), and an RL14 assertion that was a bare substring grep — green
against the broken code, because a shifted column still contains the text, just in the
wrong slot. Both fixes made the assertions positional.

Run on BOTH `/opt/homebrew/bin/bash` (5.3) and `/bin/bash` (3.2.57). Portability rules
observed: no associative arrays, no `mapfile`, no `sed -i` without a suffix, no `date -d`,
no GNU-only `timeout`.

## Walking Skeleton

T1+T2 are the skeleton and were built first: one operator sentence recorded, one invariant
declared against it, one verdict returned, one `invariant-check` exit code observed — the
thinnest slice touching every layer of this artifact (writer seam → store → fold → reader
→ exit code → consuming agent). It was exercised end-to-end before any scenario was
written, and it immediately surfaced the tab-collapse column defect that no amount of
later unit-level work would have found. Flesh (the refusals, the selectors, the degrade
codes) was added onto the proven structure afterward.

## Definition of Done

A verifier can take an operator sentence, store it unparaphrased, decompose it into two
invariants, and get a per-invariant verdict in which a satisfied invariant does NOT
discharge its violated sibling — demonstrated by replaying the 2026-07-29 failure through
`invariant-check` and observing exit 1 with `1/2 invariants hold`. Supporting conditions:
the self-test is green on both bash interpreters with no new failures against the measured
baseline; every scenario is proven discriminating by mutation; `manifest-check.sh`
introduces no new RED; and the manifest entry states the artifact's true rung rather than
claiming enforcement that was not wired.

## Closure Contract

- **Commands that run:** `/opt/homebrew/bin/bash adapters/claude-code/scripts/ask-registry.sh --self-test`;
  `/bin/bash adapters/claude-code/scripts/ask-registry.sh --self-test`;
  `bash adapters/claude-code/scripts/manifest-check.sh`.
- **Expected outputs:** `71 passed, 5 failed` on BOTH interpreters, where the 5 are the
  pre-existing BSD-`date` failures in the unrelated `set-deadline` verb (measured identical
  on unmodified HEAD at `50 passed, 5 failed`); `manifest-check` reporting the same 2
  pre-existing REDs (`estate-janitor`, `estate-brief`) and no new ones.
- **On-disk artifact location:** `docs/plans/operator-requirement-ledger-evidence.md`.
- **Done when:** the five task checkboxes are flipped by `task-verifier` against that
  evidence file, and `Status:` flips to COMPLETED.

## Behavioral Contracts

### Idempotency
The store is append-only; no verb mutates or deletes a prior record. Re-running
`invariant-verdict` with the same values appends a duplicate that folds to the identical
result, so repeated invocation is safe. `invariant-check` is a pure read.
`declare-invariant` is NOT idempotent by design — calling it twice declares two
invariants, because the caller alone knows whether a second statement is a duplicate.

### Performance budget
MEASURED, not estimated: a full 16-scenario ledger run
  (~30 CLI invocations plus repeated folds over the registry) completes within the
  existing suite, which runs end-to-end in a few seconds on both interpreters. The read
path is a single `jq -s` slurp per call, so cost is linear in registry size; no budget is
claimed for a registry beyond the current scale, and none has been measured.

### Retry semantics
Every write verb exits 0 unconditionally and never blocks its caller, matching the
existing registry contract; a malformed or rejected write is reported on stderr and simply
not persisted, so a caller never needs to retry. Read verbs distinguish
failure-to-evaluate (4) from a genuine negative (1) so a retry can be targeted at the
right condition.

### Failure modes
No `jq` → exit 4. No registry file → exit 4. Nothing registered for the selector → exit 3.
Invariants registered but unmet → exit 1. All hold → exit 0. Codes 3 and 4 are deliberately
NOT passes: the whole class of failure being addressed here is a check that reports green
because it did not actually run.

## Decisions Log

- **D1 — Extend `ask-registry.sh` rather than create a requirement store.** The ≤3-store
  consolidation goal (F5/F6) puts the burden of proof on adding one, and the registry
  already carries both the operator's ask and the plan back-link the check needs.
- **D2 — Store the verbatim text, departing from the registry's `capture-candidate`
  no-raw-text posture.** That posture exists for bulk, unclassified, high-volume prompt
  capture. A requirement quote is small, deliberately selected, and useless as a pointer:
  a `verbatim_ref` into a transcript cannot be checked against once transcripts rotate,
  which would defeat the entire property.
- **D3 — Pattern, not a blocking gate.** 36 blocking entries exist against a ≤12 target,
  and the retired goal-coverage pair is direct evidence that a Stop-time narrative check
  of this shape is the wrong rung. The manifest entry states the rung honestly and the
  retirement condition names the adoption evidence that would justify promotion.
- **D4 — `holds` requires `--evidence`.** An unevidenced pass is the failure being
  prevented, so the mechanism refuses to record one rather than trusting the caller.
