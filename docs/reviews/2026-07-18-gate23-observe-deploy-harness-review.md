# Harness Review — GATE 2/3 OBSERVE-mode deployment (2026-07-18)

Reviewer: harness-reviewer (opus). Orchestrating session: cockpit-redesign build session
(this doc + the review records were written by the orchestrator from the reviewer's returned
verdict, per the write-review-record.sh contract).

Context: the GATE 2/3 probe-log flip analysis (same day) PROVED both gates were never
deployed — every auto-install since 2026-07-17 skipped them ("no PASS harness-change-review
record covers blob_sha ..."), so their probe logs were empty and the manifest flip criteria
were unevaluable. nl-issue filed (review-claimed-but-never-registered = deploy theater class).
This review closes the gap path (a): review the current blobs, register the records, let
auto-install deploy.

## Verdicts (all for OBSERVE-mode deployment; enforce-flip is a separate later decision)

| File | Blob | Verdict |
|---|---|---|
| `adapters/claude-code/hooks/agent-design-gate.sh` | `725c5a7037dff9ea18df11309c97c34c6fcbde27` | PASS (Minor findings only) |
| `adapters/claude-code/hooks/agent-commit-gate.sh` | `4757bc79b4182976aebe392ef502ca7d4cff2066` | PASS (Minor findings only) |
| `adapters/claude-code/settings.json.template` | `f21cc78ac8aac53d7ef7274c986098f793c7c8e9` | PASS (delta vs covered `de765570` = GATE 2 + GATE 3 wiring + one documented rider; nothing smuggled) |

Zero-tolerance criterion (any observe-mode path returning a blocking exit or wedging a
session ⇒ REJECT): NOT triggered for either hook — PROVEN by exit-path trace.

## Load-bearing evidence (reviewer, verbatim highlights)

- **Observe-mode blocking-exit trace:** agent-design-gate — both would-block points end in
  `[ "${AGENT_DESIGN_GATE_ENFORCE:-0}" = "1" ] && return 2 || return 0`; in observe the test
  is false so `return 0` executes; all other paths are literal `return 0`. agent-commit-gate —
  only `exit 2` is inside `if [ "$ENFORCE" != "1" ]`-guarded enforce branch; every
  skip/fail-open path is `exit 0`; fail-open is total (`cat 2>/dev/null || true`, jq guarded,
  no pwd fallback). Double safety both: PreToolUse/SubagentStop block only on exit 2.
- **SubagentStop contract uncertainty degrades to no-op:** all fields absent → `CWD=""` →
  `skip-non-pool` probe line + exit 0. No error, no block.
- **Self-tests:** agent-design-gate 8/8 PASS exit 0; agent-commit-gate 10/10 PASS exit 0
  (incl. observe-default-allows-and-records + negative/FP cases).
- **Template delta (`de765570` → `f21cc78`), exactly 3 hunks:** (1) GATE 2 PreToolUse wiring
  `Edit|Write|MultiEdit → agent-design-gate.sh`; (2) RIDER: plan-lifecycle.sh PostToolUse
  matcher widened `Edit|Write` → `Edit|Write|MultiEdit` — documented (cockpit-v2 Task 5,
  2026-07-17), never-blocks-always-exit-0, selftest scenario 21 locks it — accepted;
  (3) GATE 3 SubagentStop wiring `→ agent-commit-gate.sh`. Nothing else changed.
- **Remedy-chain (ADR 059 D5):** no active remedy chain in observe (N/A). Forward-looking
  enforce-mode trace: commit-gate blocks at most once per stop (stop_hook_active + 10-min
  marker) — cannot deadlock by construction; stash-escape names the always-succeeds exit
  (NL-FINDING-019 applied).
- **Constitution §10 triad:** golden scenario / FP expectation / retirement condition present
  in both manifest entries (manifest.json:19-68); `blocking:false` honestly mirrors observe.

## Minor advisories (non-blocking; nl-issue filed for the sweep/generalization)

1. **unbounded-append-state-log** (PROVEN): agent-design-gate probe jsonl has no rotation,
   unlike its sibling's ~200KB tail-keep. Sweep found rotation inconsistent across hooks
   (cross-repo-nl-touch-warn.sh, doc-gate.sh also unrotated). House rule needed: every
   append-only state probe rotates or documents bounded growth.
2. **message-arithmetic** (PROVEN, instance-only): design-gate block message says "all seven
   properties" alongside GOLDEN CASE; code enforces GOLDEN CASE + 6 vocab checks. Reword at
   enforce-flip time.
3. **fail-toward-block-on-missing-tooling** (HYPOTHESIZED): jq-less environment would make
   every new-agent Write would-block ("jq unavailable") — enforce-mode FP surface only.
   Fold into the enforce-flip review: confirm jq guaranteed or fail-open.

## Disposition

Records registered via `write-review-record.sh capture` (kind: harness-change-review,
verdict PASS, all three files in one record); next session-start-auto-install sync deploys
both hooks + the template wiring live in OBSERVE mode; probes then start accumulating toward
the manifest flip criteria (agent-commit-gate: cwd-identifies-own-worktree + stop_hook_active
observed + zero false would-blocks; agent-design-gate: N real fires, zero FPs).
