# Stop-hook orthogonality matrix (NL-self-review)

**Date:** 2026-05-04
**Triggered by:** HARNESS-GAP-10 sub-gap A (Phase 1d-E-2 Task 1)
**Author:** orchestrator audit

## Purpose

The harness has five Stop hooks that all detect narrative-integrity failures
between the agent's behavior and the agent's user-facing summary. They were
shipped as separate Generation 6 mechanisms (A1, A3, A5, A7) plus an earlier
Gen 5 / behavioral hook (narrate-and-wait). HARNESS-GAP-10 sub-gap A asked:
are all five sufficiently orthogonal that retaining them does not duplicate
work or produce overlapping false positives?

This audit walks each ordered pair and names ONE specific scenario where
hook A blocks but hook B does NOT. Each cell is a real example, not a
restated mission statement. Per-pair recommendations follow the matrix.

## Hook summaries (one-line each)

- **narrate-and-wait** (`narrate-and-wait-gate.sh`) — when keep-going was
  given by the user, blocks if the FINAL assistant message trails off with
  a permission-seeking phrase ("want me to continue?", "let me know if...").
- **transcript-lie-detector** (A3) — blocks if the session JSONL contains
  BOTH completion phrases ("Plan COMPLETED") AND deferral phrases ("deferred
  to user", "PHASE6-FOLLOWUP") about the same scope, unless the final
  message has a `## Resolved contradictions in this session` section.
- **goal-coverage** (A1) — extracts user-goal verbs from the FIRST user
  message (SHA-256 checksummed against transcript), checks tool-call
  evidence for each, blocks if any goal lacks evidence and the final message
  has no `## User-goal coverage` section.
- **imperative-evidence** (A7) — scans ALL user messages for strong
  imperatives ("must run the tests", "please deploy"), maps each to a
  tool-call evidence regex, blocks unmatched imperatives unless the final
  message has a `## User-imperative coverage` section.
- **deferral-counter** (A5) — counts deferral phrases ("deferred", "TBD",
  "follow-up", "next session", "user must decide", ~50 synonyms) anywhere
  in transcript; blocks unless final message has a `## Deferrals not
  executed in this session` section enumerating them.

## Pairwise orthogonality matrix

For each ordered pair `(A catches, B does NOT)`, one specific example.
Each scenario is a session where hook-A blocks the session-end and hook-B
allows it. The diagonal is `—` (a hook does not catch its own absence).

| A catches \ B doesn't | narrate-and-wait | transcript-lie-detector | goal-coverage | imperative-evidence | deferral-counter |
|---|---|---|---|---|---|
| **narrate-and-wait** | — | (1) Agent finishes a refactor cleanly with no contradictions or deferrals, then ends with "Want me to push the branch?" — pure permission-seeking after keep-going; A3 sees no completion-vs-deferral pair. | (2) User's first message says "explore the codebase" (no goal verb extracted by A1's whitelist), agent explores then asks "want me to write up findings?"; A1 has no goals to check. | (3) User's first message has no strong imperative ("hi, can you help me think through this?"), keep-going given later, agent ends with "let me know how to proceed"; A7 has no imperatives to evidence. | (4) Agent did everything cleanly, no deferral synonyms anywhere; ends with "ready to continue when you give the go-ahead"; A5 has zero deferrals to enumerate. |
| **transcript-lie-detector** | (5) Agent writes "Plan COMPLETED" mid-session and "deferred to next session" three turns later, but the FINAL message is a clean status report with no permission-seeking phrase; narrate-and-wait sees no trail-off. | — | (6) The contradiction is about a task that wasn't a first-message user goal — e.g., agent claimed a sub-component "shipped" but mid-session admits "actually deferred"; A1 only checks first-message goals. | (7) Agent self-contradicts about an internal milestone (no user imperative said "ship the auth module"); A7 has no imperative tied to that scope. | (8) The contradiction phrasing pairs "complete"+"not yet verified" — "not yet verified" is not in A5's deferral list (specific to "verified" not present in the synonym set), so A5 doesn't flag it as a deferral, but A3 sees the completion-vs-non-completion contradiction. |
| **goal-coverage** | (9) User said "test the new endpoint" in first message; agent never ran any test, ends with a clean status report saying tests were "considered but skipped" (no permission-seeking phrase, no deferral synonym match); narrate-and-wait sees a definitive close. | (10) Agent silently skipped the goal — never wrote "complete" OR "deferred" about it; transcript has no contradiction to detect. | — | (11) The first-message goal verb ("verify") is in A1's whitelist but the user phrased it weakly ("could you maybe verify..."); A7's strong-imperative scanner requires "must/need to/please/required to" trigger words, which the user didn't use. | (12) Goal was never executed, but the agent's narrative used phrases like "let's focus on X" instead of any A5 deferral synonym; A5 has zero matches even though the goal was effectively deferred. |
| **imperative-evidence** | (13) User's mid-session message said "please run the full test suite"; agent never ran tests; final message is a clean factual report, no narrate-and-wait phrase. | (14) Agent simply skipped the imperative without ever claiming completion of it AND without ever admitting deferral — no contradiction pair exists in transcript. | (15) User's mid-session imperative ("please deploy") was given AFTER the first user message; A1 only extracts goals from the FIRST message and would not see it. | — | (16) Agent skipped the imperative silently, no deferral synonyms anywhere in transcript; A5 is silent. |
| **deferral-counter** | (17) Agent leaves "PHASE6-FOLLOWUP-01 — execute after user authorization" in commit messages and SCRATCHPAD; final message is a complete success summary with no permission-seeking phrasing; narrate-and-wait sees a clean close. | (18) Agent writes "this is deferred to next session" multiple times but NEVER pairs it with any completion phrase ("done", "shipped", "COMPLETED") — A3 needs both halves of the contradiction to fire. | (19) Deferred work is unrelated to the first user goal — e.g., user said "fix the lint errors", agent fixes them AND defers some unrelated polish work it noticed; A1 checks goal coverage and finds the lint goal honored. | (20) Deferred work was never explicitly demanded by the user via strong imperative — agent self-imposed deferral on internal scope ("for now I'll skip the perf optimization"); A7 has no user-imperative entry for it. | — |

## Per-pair recommendation

All ten unordered pairs reviewed. KEEP SEPARATE = orthogonal trigger AND
orthogonal action; CLARIFY BOUNDARY = some overlap on edge cases but
distinct primary class; CONSOLIDATE = substantial overlap.

| Pair | Verdict | Reasoning |
|---|---|---|
| narrate-and-wait × transcript-lie-detector | **KEEP SEPARATE** | narrate-and-wait fires on the agent's TONE in the final message (permission-seeking trail-off after keep-going). transcript-lie-detector fires on logical INCONSISTENCY across the entire transcript (completion vs deferral about same scope). Different surfaces, different triggers, different remedies. |
| narrate-and-wait × goal-coverage | **KEEP SEPARATE** | narrate-and-wait is keep-going-conditional and tone-detected. goal-coverage is unconditional (any session with extracted first-message goals) and evidence-detected. A goal can go uncovered in a session where the agent never mentioned the goal again — narrate-and-wait would not see anything to flag. |
| narrate-and-wait × imperative-evidence | **KEEP SEPARATE** | narrate-and-wait checks final-message TONE only; imperative-evidence checks tool-call evidence for any user imperative anywhere in session. An agent ending "all done!" cleanly while never having executed the user's "please run the tests" is exactly the gap A7 closes. |
| narrate-and-wait × deferral-counter | **KEEP SEPARATE** | Tone vs. content. The agent can have ZERO deferral-synonym occurrences in transcript while still ending with "let me know if you'd like me to continue". Conversely, the agent can write "deferred to next session" multiple times with a clean factual close that has no permission-seeking phrasing. |
| transcript-lie-detector × goal-coverage | **KEEP SEPARATE** | A3 needs BOTH halves of the contradiction (completion AND deferral phrases) about the same scope. A1 needs only goal-extraction-mismatch from the first message. They miss different things: A3 misses silent skips; A1 misses contradictions about non-first-message work. |
| transcript-lie-detector × imperative-evidence | **KEEP SEPARATE** | A3 detects logical inconsistency in agent self-narration. A7 detects evidence-vs-imperative gap regardless of agent narration. A user imperative that's silently skipped — agent never says "done" OR "deferred" about it — is invisible to A3 but caught by A7. |
| transcript-lie-detector × deferral-counter | **CLARIFY BOUNDARY** | Substantial overlap on the deferral-pattern side: A3's deferral list overlaps with A5's, since both look for "deferred", "follow-up", etc. The orthogonality is asymmetric: A5 fires on bare deferral (no completion claim needed); A3 fires only when paired with a completion claim. **Recommendation: keep both, but document the asymmetry in each hook's WHY THIS EXISTS section** so a maintainer doesn't think A3 supersedes A5 (it doesn't — A5 catches deferrals that have no contradicting completion claim). |
| goal-coverage × imperative-evidence | **CLARIFY BOUNDARY** | Both check tool-call evidence against user-stated needs, but differ on input scope: A1 reads ONLY the first user message; A7 reads ALL user messages. A1 also uses a 16-verb whitelist; A7 uses a JSON pattern library with verb+object pairs. **Recommendation: keep both. The first user message is the highest-signal moment (A1's value), but most sessions have additional imperatives mid-session (A7's value).** Consolidating would force a choice between checksum-anchored single-message extraction (A1) and broad cross-session imperative scanning (A7) — both valuable. |
| goal-coverage × deferral-counter | **KEEP SEPARATE** | A1 checks tool-call evidence (did execution happen?); A5 checks transcript narrative (did agent leak deferral phrases?). Goal can be silently skipped (A1 fires, A5 silent). Conversely, agent can defer non-goal work using deferral phrases (A5 fires, A1 silent). |
| imperative-evidence × deferral-counter | **KEEP SEPARATE** | A7 checks tool-call evidence against user imperatives. A5 checks deferral-phrase counts in transcript. Agent can skip an imperative silently (A7 fires, A5 silent). Agent can defer self-imposed scope using deferral phrases without any user imperative being touched (A5 fires, A7 silent). |

## Conclusion

**All five Stop hooks are sufficiently orthogonal to retain.** Each catches a
distinct failure class with a distinct trigger signal:

- **Tone vs. content separation:** narrate-and-wait alone gates the final
  message's tone; the other four gate transcript content (logical
  consistency, goal/imperative coverage, deferral surfacing).
- **Trigger-source separation:** narrate-and-wait is keep-going-conditional;
  transcript-lie-detector requires a contradiction pair; goal-coverage
  anchors on first-message extraction with checksum integrity; imperative-
  evidence scans all user messages with strong-imperative trigger words;
  deferral-counter scans entire transcript for ~50 synonyms.
- **Action-surface separation:** each hook demands its OWN final-message
  section heading (`## Resolved contradictions...`, `## User-goal coverage`,
  `## User-imperative coverage`, `## Deferrals not executed in this session`).
  This is by design — an agent confronted with multiple gaps must enumerate
  each separately, which preserves the audit trail for the user.

**Two pairs flagged as CLARIFY BOUNDARY** (transcript-lie-detector ×
deferral-counter; goal-coverage × imperative-evidence). Both pairs have
genuinely orthogonal primary classes but overlap on edge cases. The
recommendation is documentation, not consolidation: each hook's header
comment should briefly note which sibling hook handles the adjacent class
so a future maintainer doesn't conclude one supersedes the other.

**No CONSOLIDATE recommendations.** No pair has substantial enough overlap
to warrant merging. Each hook is the cheapest correct mechanism for its
own failure class.

**Confidence in the assessment:** medium-high. The matrix examples are
plausible session shapes derived from each hook's documented trigger
conditions and from the originating incidents named in their WHY THIS
EXISTS sections. A future audit (post-Gen-6 maturity, ~3-6 months of
observation) should re-confirm by looking at actual sessions: count how
often each hook blocked alone vs. blocked-with-siblings, and whether any
pair fired together >80% of the time (which would signal practical
consolidation despite theoretical orthogonality).

## Followups (filed to backlog if not already)

- **Per-hook header note about adjacent sibling.** Add a one-line note to
  each Stop-hook header comment naming the adjacent hook(s) for the
  CLARIFY BOUNDARY pairs above. (Documentation-only; no behavior change.)
- **Post-maturity firing-frequency audit.** After 3-6 months of Gen 6
  observation, re-run this audit using actual session logs to confirm
  the theoretical orthogonality holds in practice.
