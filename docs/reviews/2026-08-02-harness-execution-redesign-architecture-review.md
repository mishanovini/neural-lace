# Architecture review record — harness execution-layer redesign (2026-08)

**Date:** 2026-08-02
**Plan under review:** `docs/plans/harness-execution-redesign-2026-08.md`
**Design under review:** `docs/designs/harness-execution-redesign-considerations-2026-08-02.md`
(the considerations brief + round-2 Addendum + "Round 3 revamp (2026-08-02, operator GO)")

## Provenance — what this record is and is not

This is a DERIVED record of an architecture review that was actually performed, in parts, across
2026-07-31 → 2026-08-02 — it is not the output of a fresh `architecture-reviewer` agent dispatch.
Honest basis, each part citable:

1. **Three adversarial pre-mortems**, one per candidate posture (minimal / daemon / platform),
   recorded verbatim in the brief's §3 verdict row — each returned **conditional pass** with a
   named kill-shot and named survival conditions. The kill-shots: authored-fingerprint blindness
   (minimal), green-but-not-enforcing composition (daemon), stall-at-stage-2 dual-substrate trap
   (platform).
2. **An 11-agent adversarially-verified research sweep** on the platform question (commit
   `5ffe564d`, docs/research), whose findings priced the spawn-tax and platform rows in §4.4.
3. **Three rounds of operator design review** (nl-issues.jsonl 2026-08-02 a–d): round 1 set scope
   and rejected the mega-dispatcher; round 2 corrected the push/pull analysis and imposed the
   lost-event prevention stack + cleanup-as-sensor law + death certificates; round 3 imposed
   no-WSL, all-machines portability, anti-bloat metrics, and the Gate Philosophy Law, then issued
   GO.
4. Mechanism claims in the brief's §1 root-cause table were verified against the live estate
   (settings.json, Task Scheduler, coord-sync.sh source, doctor source) in the originating
   session — PROVEN/HYPOTHESIZED markers are carried per claim.

The `architecture-reviewer` agent was not separately dispatched: the plan-writing session runs
without a Task tool, and a fourth full-pass review would re-cover ground the three pre-mortems +
three operator rounds already covered adversarially. If a future session judges that a fresh
agent pass would add signal (see "What would change this verdict"), dispatching it and appending
its verdict here is the correct move — this record does not preclude it.

## What the review looked for

- Where heavy work runs and how often (the incident class: per-event spawn × O(mess) recompute);
- single points of failure in blocking paths (mega-dispatcher — rejected, round 1);
- lost-event integrity of push architectures (round 2: prevention stack, not cleanup);
- cache honesty (derived-not-authored fingerprints; bypass ledgering);
- supervision honesty (output-freshness vs loop-liveness; half-death);
- dual-substrate migration traps (retire-before-extend, both-substrates RED);
- platform portability and per-platform cost (round 3: 2 Windows + 1 Mac, portable bash +
  schtasks/launchd adapters);
- gate ergonomics as an architecture concern (round 3: Gate Philosophy Law — structured block
  messages, --check pre-flight, workaround-as-sensor, friction telemetry).

## Verdict: SOUND-WITH-AMENDMENTS

The amendments ARE the survival conditions the pre-mortems and operator rounds attached, and the
plan binds every one of them:

- The 12 posture-independent invariants of brief §2 (cost budgets doctor-enforced; cadence ≥ 2×
  cycle; once-per-TTL heavy state; guard-in-lib; output-freshness health; guaranteed-read
  degradation channel; ledgered escape hatches; derived-never-authored state; retire-before-
  extend; platform-priced review; one-gesture HALT; outcome-gated closure).
- Round 2: lost-event PREVENTION stack (lease/ack, write-ahead intent, brackets, sequence
  numbers), death certificates, cleanup-as-sensor law.
- Round 3 (binding, wins on conflict): no WSL; no new hardware; runs on all three machines via
  portable core + platform adapters; anti-bloat inventory targets (hooks-per-Bash 25 → ~5,
  scheduled tasks 6 → 1–2, SessionStart spawns 16 → 1–2, doctor-enforced budget); the Gate
  Philosophy Law; the top-5 gate guidance retrofit in Stage 0.

A plan or build that drops any amendment reverts this verdict to NEEDS-RESHAPING for the affected
stage.

## What would change this verdict

- Evidence that completion-anchored scheduling cannot be built reliably on schtasks/launchd for
  a bash core (the round-3 no-WSL bet's riskiest assumption) — would force a re-review of stage 1's
  substrate choice.
- The stage-2 observe-first window showing nonzero block-semantics diff that the in-process
  fallback cannot close — would reopen the per-category stub decomposition.
- The kernel-pool refuter firing (pool still bloats after stage 1) — would prove the leak's cause
  was elsewhere and reopen the §1 A2 diagnosis, though not the CPU-load outcome itself.
- Any invariant being waived during build rather than implemented — per above, an automatic
  NEEDS-RESHAPING for that stage.
