# Lesson — Trusting a Stale Proxy Denominator Over a One-Command Check Cost 28 of 34 Work Items

**Date:** 2026-07-20
**Source case:** `context-watermark.sh` (the PostToolUse early-warning hook, Wave E task
E.9a) hardcoded `CONTEXT_WINDOW_TOKENS="${CONTEXT_WATERMARK_WINDOW:-200000}"` and computed
`pct = tokens / 200000` regardless of which model was actually running the session. An
autonomous orchestrator session running `claude-opus-4-8` (a real 1,000,000-token window)
had the hook report **"~95% of 200000"** well before the pause (that reading corresponds to
~190,000 tokens — 19% of the real window). By the time the session cited its token count and
paused, it had reached 322,800 tokens — 32% of the ACTUAL window, 68% free — a point at which
the SAME wrong arithmetic would have read ~161% (322,800 ÷ 200,000), an impossible value that
underscores how broken the denominator was, not a number the session is known to have quoted
directly. Either way it read as authoritative capacity, and the session **PAUSED a multi-hour
program, abandoning 28 of 34 remaining work items** and telling the operator it had run out of
context. The operator: *"when you run out of context, that context then compacts itself so
that you can continue moving forward. That should never be a blocker."* This is a recurring
class — the identical mis-denominator was reported twice in `nl-issues.jsonl` on 2026-07-18
(one session, filing ~8 minutes apart) and again on 2026-07-20 from a different project/session
— this incident.
**Nature:** A harness-mechanism defect (wrong constant) compounded by a doctrine gap (no
rule said context pressure is never a stop condition) — not a one-off.
**Fix:** `adapters/claude-code/hooks/context-watermark.sh` now auto-detects the real window
from the transcript's `message.model` field (same jq pass that already reads `usage`), with
precedence `CONTEXT_WATERMARK_WINDOW` env override > model-detected window > conservative
200000 default — and the emitted message always names which one applied, spelling out
"ASSUMED" when the window could not be established. `doctrine/session-end-protocol.md`
gained an explicit clause: context pressure is never a valid `PAUSING`/`BLOCKED` reason.

---

## 0. TL;DR

The hook's *token count* (the numerator) was always correct — it read the platform's own
billed-usage field. The *denominator* was a constant nobody revisited when the harness
started running on 1M-context models. A session facing an unlabeled "~95%" had no way to
tell "measured against your actual window" from "measured against a number six years out of
date" — so it trusted the proxy over the one command (`echo $CONTEXT_WINDOW size, or just
check the model card`) that would have shown the real picture. **A wrong denominator that
looks like a percentage is more dangerous than an obviously-wrong number** — it doesn't
*look* wrong, so nothing prompts a second check.

## 1. The failure, precisely

- **Expected:** the hook's watermark percentage reflects the session's actual context
  capacity, and a session facing context pressure checkpoints state and continues — because
  compaction (already a live mechanism in this harness: `pre-compact-continuity.sh`,
  `docs/runbooks/pre-compaction-snapshots.md`) exists precisely to make exhaustion a
  non-event.
- **Actual:** the hook divided by a constant frozen at 200,000 tokens. On a 1M-window model
  that is wrong by 5×. The session, with no doctrine telling it context pressure is never a
  stop condition and no reason to doubt the hook's own arithmetic, treated the hook's
  unlabeled percentage as ground truth and stopped autonomous work, discarding 28 of 34
  remaining items.
- **Recurrence:** `nl-issues.jsonl` shows this EXACT defect class reported on 2026-07-18 (one
  session, filing twice ~8 minutes apart: "UI: 179.1k/1.0M = 18% when the hook claimed ~74%
  and ~85%") and again on 2026-07-20 from a different project/session — this incident. Two
  separate sessions hit the identical wrong-denominator wall and only the second one
  escalated to an actual work-loss incident bad enough to force the fix.
- **Cost:** a multi-hour autonomous program truncated at ~18% real completion loss (28/34
  items), plus operator time spent explaining, again, that compaction handles overflow.

## 2. Classification

**Proxy-trust failure** — the same error class as trusting a code path that *could* explain
a bug instead of the logs that show what *did* happen (see
[`2026-07-14-root-cause-must-be-evidenced-before-fix.md`](2026-07-14-root-cause-must-be-evidenced-before-fix.md)).
Here the proxy was a hook's own arithmetic output, dressed as a measurement rather than
flagged as resting on an unverified assumption. **The meta-lesson generalizes beyond this
hook: any advisory signal computed from a constant that the real world can silently outgrow
(a context window, a rate limit, a plan tier, a quota) must either revalidate that constant
against ground truth or LABEL itself as unverified — never present a derived number with the
confidence of a direct measurement.**

## 3. Why the soundness asymmetry makes this severe

An advisory hook (`kind: writer`, `blocking: no` in the manifest) is, by design, not supposed
to be able to cause harm — it can only inject text, never block a tool call. This incident
shows that framing is incomplete: **a non-blocking hook can still cause a session to block
*itself*** if its message reads as authoritative and the session has no counter-doctrine.
The false-negative (hook silent when it should have warned) is the historically-assumed
failure mode for an advisory hook; this incident is the false-POSITIVE case — the hook fired
confidently and WRONGLY, and that was worse than firing not at all, because it actively
directed the session to stop.

## 4. The fix (deployed this change)

1. **Auto-detect the window from the model**, parsed in the same jq pass that already reads
   `usage` from the transcript's last assistant event (`_measure_context_tokens`). A new
   `_model_window` lookup table (verified live against
   `platform.claude.com/docs/en/about-claude/models/overview` on 2026-07-20, not
   trusted-from-memory) maps model IDs to their real window, delimiter-anchored (exact ID or
   ID + literal dash, e.g. for a dated snapshot) rather than a bare prefix glob — so a future
   numeric sibling of a listed model isn't silently swallowed into the wrong bucket (see §5);
   anything not in the table falls through to the conservative default and is labeled so.
2. **Precedence:** `CONTEXT_WATERMARK_WINDOW` env override (the escape hatch, kept) >
   model-detected window > conservative 200000 default.
3. **The message can no longer be read as unlabeled authoritative capacity.** It now always
   names the window ("~32% of 1000000"), states whether that window was detected from the
   model, came from an override, or was ASSUMED (and if assumed, says explicitly that the
   percentage may be an overestimate) — and carries the never-a-stop-reason clause on every
   fire: *"Context pressure is NEVER a reason to stop or pause autonomous work — compaction
   handles overflow automatically; checkpoint state and keep going."*
4. **Doctrine amendment:** `doctrine/session-end-protocol.md`'s `PAUSING`/`BLOCKED` guidance
   now explicitly excludes context pressure as a valid reason for either marker — closing the
   gap that let a wrong hook output be treated as a legitimate blocker in the first place.
   This is deliberately a BELT-AND-SUSPENDERS fix: even a CORRECTLY measured high watermark
   must not become a stop condition, so fixing only the denominator would have been
   insufficient.

## 5. Honest residual risk

- **The model→window table will go stale.** New models ship; the table must be
  re-verified, not assumed-forward. The header comment in `context-watermark.sh` documents
  the verification date and source so a future maintainer knows to re-check rather than
  trust the existing entries indefinitely.
- **Legacy `claude-3-*` models were not re-verified** for this change — they fall through to
  the conservative 200000 default, which happens to be correct for that family, but this was
  not independently re-confirmed against current docs (deprioritized: those models are not
  observed running anywhere on this machine's transcripts as of 2026-07-20).
- **The doctrine amendment relies on a session reading `session-end-protocol.md`.** It is
  JIT-loaded per `doctrine-jit.sh`'s existing triggers, not injected unconditionally — a
  session that never touches a surface triggering that doctrine file could still, in theory,
  misread a correctly-labeled watermark message as a reason to pause. The hook's own message
  text (item 3 above) is therefore the PRIMARY defense (it fires unconditionally wherever the
  hook fires); the doctrine amendment is the secondary, broader-context backstop.
- **Prefix-collision in the model table (caught by `harness-reviewer` before landing, not
  found independently).** The first draft of `_model_window` used a bare trailing `*` glob
  per entry (e.g. `claude-opus-4-1*`), which would have silently swallowed a future numeric
  sibling — `claude-opus-4-10` or `claude-opus-4-18` both start with `claude-opus-4-1` — into
  that entry's bucket, mislabeling it "detected" (confident-and-wrong) if the sibling actually
  ships with a different window. Fixed to delimiter-anchored matching (exact ID, or ID +
  literal dash for dated snapshots) before landing, with a self-test case (T19) proving the
  collision no longer occurs. Residual: the anchoring is still a finite, hand-maintained list —
  it protects against confident-and-wrong on an UNLISTED sibling, but a genuinely wrong window
  value entered for a LISTED model would still be trusted as "detected." There is no
  independent oracle re-verifying the table's values beyond the one-time doc fetch cited in
  the header comment.

## 6. Companion work

- Filed via `nl-issue.sh` — three entries in `nl-issues.jsonl`: 2026-07-18 (×2, untriaged
  until this fix), 2026-07-20 (the incident that forced the fix). All three triaged `task`
  against this change once merged.
- Sibling of
  [`2026-07-14-root-cause-must-be-evidenced-before-fix.md`](2026-07-14-root-cause-must-be-evidenced-before-fix.md)
  — both are "the harness trusted an inference/proxy where it should have required
  ground-truth or an explicit unverified-label."
