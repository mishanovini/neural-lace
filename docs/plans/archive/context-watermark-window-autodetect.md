# Plan: context-watermark.sh window auto-detection + never-a-stop-reason doctrine
Status: COMPLETED
Execution Mode: single-session
Mode: code
tier: 1
rung: 0
architecture: single-hook change (context-watermark.sh) + one doctrine-file clause + one lesson-file record; no new components
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal advisory-hook fix; the hook's `--self-test` (11→20 scenarios) is the acceptance artifact, no product user surface
Backlog items absorbed: none

## Goal
`context-watermark.sh` (PostToolUse early-warning hook, Wave E task E.9a) hardcoded
`CONTEXT_WINDOW_TOKENS="${CONTEXT_WATERMARK_WINDOW:-200000}"` and computed
`pct = tokens / 200000` regardless of which model produced the transcript. On a
1,000,000-token-window model (`claude-opus-4-8`) this overstates usage by 5x. Proven
incident, 2026-07-20: an autonomous orchestrator session at 322,800/1,000,000 tokens
(32% used, 68% free) had the hook's wrong-denominator arithmetic read as if near
exhaustion, and the session PAUSED a multi-hour program, abandoning 28 of 34 remaining
work items. Recurring — the identical defect was reported in `nl-issues.jsonl` on
2026-07-18 (one session, twice ~8 minutes apart) before this incident forced the fix.
Fix: auto-detect the real window from the transcript's `message.model` field (same jq
pass that already reads `usage`), with `CONTEXT_WATERMARK_WINDOW` env override kept as
the escape hatch; rewrite the emitted message so a wrong/assumed denominator can never
again be read as unlabeled authoritative capacity; and close the independent doctrine
gap that let a wrong (or even a correctly measured) high watermark be treated as a
legitimate reason to pause autonomous work.

## Scope
- IN: `adapters/claude-code/hooks/context-watermark.sh` — `_model_window` lookup table,
  `_resolve_window` precedence function, `_measure_context_tokens` extended to also
  parse `message.model` in the same jq pass, `_compute_watermark` rewritten to resolve
  the window per-call and emit the new message wording, self-test extended 11→20
  scenarios (T12-T19).
- IN: `adapters/claude-code/doctrine/session-end-protocol.md` — explicit clause that
  context pressure is never valid grounds for `PAUSING`/`BLOCKED`.
- IN: `docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md` — new
  incident writeup (durable record per constitution §5).
- IN: `docs/plans/context-watermark-window-autodetect.md` — this plan (self-claiming).
- OUT: `constitution.md` — deliberately not touched (capped, gated file; the doctrine
  fix belongs in the JIT-loaded `session-end-protocol.md` instead).
- OUT: `nl-issues.jsonl` triage (`--triage <n> task <ref>` for entries 122/123/142) —
  tracked as a follow-up in this plan's Completion Report, not blocking the fix itself
  (the ledger triage tool is independently slow/unreliable on this machine right now;
  see Known Issues).
- OUT: any product/runtime code; any other hook.

## Tasks
- [ ] 1. Auto-detect the context window from the transcript's `message.model` (same jq
  pass as `usage`); add `_model_window` (delimiter-anchored lookup table, verified live
  against platform.claude.com/docs on 2026-07-20) and `_resolve_window`
  (override > detected > assumed precedence). — Verification: mechanical
- [ ] 2. Rewrite the emitted watermark message so it always names the window, states
  detected/override/ASSUMED explicitly, and carries the never-a-stop-reason/compaction
  clause on every fire. — Verification: mechanical
- [ ] 3. Extend `--self-test` from 11 to 20 scenarios (T12-T19) covering model-absent,
  large-context detection (incl. the exact real-incident numbers), 200k-model detection,
  env-override precedence, unrecognized-model fallback, a direct `_model_window` table
  spot-check, and the prefix-collision anchoring guard. — Verification: mechanical
- [ ] 4. Add the `session-end-protocol.md` doctrine clause (context pressure ≠ valid
  PAUSING/BLOCKED reason) and the incident lesson file. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/context-watermark.sh` — window auto-detection, message
  rewrite, self-test extension (11→20).
- `adapters/claude-code/doctrine/session-end-protocol.md` — never-a-stop-reason clause.
- `docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md` — incident
  writeup (new file).
- `docs/plans/context-watermark-window-autodetect.md` — this plan (self-claiming).

## Testing Strategy
- `bash adapters/claude-code/hooks/context-watermark.sh --self-test` → 20/20 pass (no
  regression on scenarios T1-T11; new T12-T19 cover window resolution end to end,
  including a direct reconstruction of the real incident's token count against the real
  window, which now correctly stays silent instead of false-alarming).
- `harness-reviewer` (Opus) adversarial review of the diff — PASS with 3 non-blocking
  advisories, all addressed before landing (see Decisions Log).

## Decisions Log

### Decision: model→window lookup as an explicit table, not a computed heuristic
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `_model_window` is a hand-maintained, delimiter-anchored `case` table,
  verified live against `platform.claude.com/docs/en/about-claude/models/overview` on
  2026-07-20 rather than inferred from the model name's shape.
- **Alternatives:** Parse a numeric heuristic from the model string (e.g. "5.x family =
  1M") — rejected because the real mapping is NOT purely generational (Opus 4.6/4.7/4.8
  and Sonnet 4.6 are all 1M while Sonnet/Opus 4.5 and Opus 4.1 are 200k), so a heuristic
  would have been confidently wrong for exactly the models most likely to appear.
- **Reasoning:** An explicit, dated, source-cited table makes staleness visible (the
  header comment names the verification date) rather than silently drifting.
- **To reverse:** delete the table; the code falls through to the conservative default
  for every model (safe, just loses auto-detection).

### Decision: delimiter-anchored matching, not a bare prefix glob (harness-reviewer finding)
- **Tier:** 1
- **Status:** proceeded with recommendation (post-review fix, applied before landing)
- **Chosen:** each table entry matches "the bare ID" OR "the bare ID + literal dash"
  (`claude-opus-4-1|claude-opus-4-1-*`), not a bare `claude-opus-4-1*` glob.
- **Alternatives:** Keep the bare-glob form — rejected because it would silently swallow
  a future numeric sibling (`claude-opus-4-10`, `claude-opus-4-18`) into the wrong
  bucket, mislabeling it "detected" (confident-and-wrong) instead of falling through to
  "assumed" (honest-and-uncertain) — precisely the failure class this fix exists to
  close. `harness-reviewer` (Opus) flagged this as the one must-fix finding.
- **Reasoning:** Confident-and-wrong is strictly worse than honest-and-uncertain for an
  advisory signal a session may trust at face value.
- **To reverse:** revert to bare-glob patterns (not recommended — reintroduces the risk).

### Decision: doctrine amendment lands in `session-end-protocol.md`, not `constitution.md`
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** the never-a-stop-reason clause is added to the JIT-loaded
  `doctrine/session-end-protocol.md`.
- **Alternatives:** Add it to the always-loaded `~/.claude/rules/constitution.md` §8
  (Autonomy) — rejected: that file is explicitly capped and gated ("a new rule may enter
  this file only by replacing something... becomes the live payload at Wave C.5 cutover,
  after operator approval" per its own header), which is a bigger, differently-owned
  decision than this fix's scope.
- **Reasoning:** `session-end-protocol.md` already governs the exact marker
  (`PAUSING`/`BLOCKED`) this incident misused, and is loaded whenever that surface is
  touched — the right-sized, right-owned home for this specific clause.
- **To reverse:** delete the added paragraph; no cross-file coupling to unwind.

## Definition of Done
- [ ] All tasks shipped
- [ ] 20/20 self-test pass, no regression on T1-T11
- [ ] `harness-reviewer` PASS (advisories addressed)
- [ ] Doctrine + lesson file land in the same commit
- [ ] Completion report appended; Status → COMPLETED

## Completion Report

_Generated by close-plan.sh on 2026-07-21T07:29:39Z._

### 1. Implementation Summary

Plan: `docs/plans/context-watermark-window-autodetect.md` (slug: `context-watermark-window-autodetect`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/doctrine/session-end-protocol.md`
- `adapters/claude-code/hooks/context-watermark.sh`
- `docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md`
- `docs/plans/context-watermark-window-autodetect.md`

Commits referencing these files:

```
6aa156a NL Overhaul Wave E batch 1: E.1 digest, E.2 sandbox isolation, E.7 resumer, E.8 nl-issue, E.9 pre-compaction (#79)
97bd86e fix(context-watermark): auto-detect context window from model, not a hardcoded 200000
b632fc3 NL Overhaul Wave C: context diet — constitution-only rules/, doctrine compacts + JIT injection, manifest, cutover (#69)
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
