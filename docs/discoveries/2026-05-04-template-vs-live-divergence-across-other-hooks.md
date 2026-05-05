---
title: Pre-existing template-vs-live divergence across hooks not in Phase 1d-C-2 scope
date: 2026-05-04
type: process
status: decided
auto_applied: true
originating_context: Phase 1d-C-2 Task 9 builder noted divergence while wiring prd-validity-gate + spec-freeze-gate; carried forward through Phase 1d-C-3
decision_needed: n/a — split-decision applied 2026-05-04 (B now; A deferred to Phase 1d-E)
predicted_downstream:
  - adapters/claude-code/settings.json.template
  - ~/.claude/settings.json
  - the SessionStart settings-divergence detector (if any)
  - docs/backlog.md (Phase 1d-E reconciliation entry)
---

## What was discovered

The 2026-05-03 discovery `2026-05-03-settings-template-vs-live-divergence.md` documented that two settings files (`adapters/claude-code/settings.json.template` and the live `~/.claude/settings.json`) can drift, and the convention going forward is to edit BOTH in the same commit.

Phase 1d-C-2 + 1d-C-3 honored that convention for the new gates we wired (prd-validity-gate, spec-freeze-gate, findings-ledger-schema-gate). All three are byte-identical between the two files (modulo `~/` expansion).

But while wiring those gates, the Phase 1d-C-2 Task 9 builder noted that a number of OTHER hooks have pre-existing divergence:
- `outcome-evidence-gate.sh`
- `systems-design-gate.sh`
- `no-test-skip-gate.sh`
- `automation-mode-gate.sh`
- `public-repo-blocker` variants

These are present in one settings file but not the other (or wired with subtly different matchers/commands). The divergence pre-dates 1d-C-2; not introduced by anything this session shipped.

## Why it matters

A hook only fires if it's wired in the LIVE settings file (`~/.claude/settings.json`). If a hook lives in the template but not in live, every session running on this machine misses that hook. The reverse — live but not template — means a fresh install (`install.sh`) won't get the hook.

Practical effect: the harness's claimed enforcement may not match its actual enforcement on this machine. We've been operating with this gap; we don't know which gates are actually firing vs which are just "present in template."

This is bigger than housekeeping — it's a quiet undermining of the harness's mechanism layer. A reviewer who reads `vaporware-prevention.md`'s enforcement-map and trusts the rows is trusting a claim that may not hold for unrelated hooks.

## Options

A. **Run a dedicated reconciliation pass.** Diff the two files, list every divergence, decide per hook whether the template or the live is canonical, sync. Probably 1-2 hours of focused work + needs maintainer judgment per hook (some divergences may be intentional — e.g., a per-machine local-only hook).

B. **Build a SessionStart divergence-detector.** A hook that runs on every session start, diffs template vs live, surfaces unexpected divergences as warnings. Reuses existing pattern from the harness-source-of-truth checker. Lower cost than A; surfaces the gap continuously rather than fixing it once.

C. **Both.** B as the durable substrate (catches future drift); A as the one-shot cleanup of accumulated drift.

D. **Accept the divergence.** Document it in a known-issues section; accept that some hooks fire, some don't; rely on the maintainer to spot-check periodically.

## Recommendation

C. The reconciliation pass (A) is needed because the gap is large and accumulated; once-and-done is the right shape. The divergence-detector (B) is needed because the convention "edit both files in the same commit" failed pre-Phase-1d-D and will fail again without mechanical enforcement.

**Reasoning principle:** drift in the Mechanism layer should be observable, not assumed-not-present. A divergence-detector makes the actual state visible at every session start; a one-shot reconciliation closes the existing gap. Together they prevent the harness from quietly drifting from its claimed enforcement.

## Decision

**Split decision (2026-05-04):** ship B now, defer A to Phase 1d-E.

The discovery file's original recommendation was C (both A and B). The user accepted B but pushed back on the framing of A as "user judgment per hook." Their reasoning: the orchestrator (Claude) is better positioned than the user to research drift origins via git blame + commit log archaeology, and to propose canonical state with rationale per hook, rather than asking the user to decide cold.

**B — SessionStart divergence-detector — auto-applied now (2026-05-04).** Reversible: one revert removes the hook. Reasoning principle: drift in the Mechanism layer should be observable, not assumed-not-present. The detector's first runs become the worklist for A.

**A — One-shot reconciliation pass — deferred to Phase 1d-E with a methodology change.** When A is taken up:

1. The orchestrator (not the user) runs the research pass per divergent hook:
   - `git log --all --follow adapters/claude-code/hooks/<hook>.sh` to find when each hook entered the repo
   - `git blame adapters/claude-code/settings.json.template` on the relevant lines to find when the template wired the hook
   - Diff the live `~/.claude/settings.json` line against template — note shape of divergence (matcher-different, command-different, present-here-not-there)
   - Re-read the originating commit's message + plan + decision record (if any) to recover author intent
   - Cross-reference with `docs/harness-architecture.md` to see which form is documented as canonical
2. Output: a per-hook proposal — "live is canonical because X" or "template is canonical because Y" or "this divergence is intentional, document it as such" — each with cited evidence (commit SHAs, doc references).
3. User reviews proposals and either accepts them en masse or course-corrects the ones that look wrong.

The user's role is **review the proposals**, not "decide cold which side is right." This is the educational-format principle — give the decision-maker enough substantive context to evaluate, not raw choices.

## Implementation log

- 2026-05-04 — B (SessionStart divergence-detector) ships in this session. Backlog entry for A added under Phase 1d-E with the research-pass methodology specified above.
- (A's implementation log will be populated during Phase 1d-E.)
