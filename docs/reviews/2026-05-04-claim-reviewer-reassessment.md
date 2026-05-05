# claim-reviewer post-Gen6 reassessment (NL-self-review)

**Date:** 2026-05-04
**Triggered by:** Phase 1d-E-2 Task 3 (audit gap from sub-gap C of the build-doctrine audit)
**Source files audited:**
- `~/.claude/agents/claim-reviewer.md` (the agent under reassessment)
- `~/.claude/hooks/transcript-lie-detector.sh` (Gen 6, position 6 in Stop chain)
- `~/.claude/hooks/goal-coverage-on-stop.sh` (Gen 6, position 8)
- `~/.claude/hooks/imperative-evidence-linker.sh` (Gen 6, position 7)
- `~/.claude/hooks/deferral-counter.sh` (Gen 6, position 5)
- `~/.claude/hooks/vaporware-volume-gate.sh` (Gen 6, PreToolUse on `gh pr create`)

## Background

`claim-reviewer` was introduced in Gen 4 as the residual mitigation for **verbal vaporware** — claims made in conversation responses (not in plan files, evidence blocks, or PRs) that assert features exist or work without backing citations. The problem was structural: Claude Code has no PostMessage hook, so no mechanism could fire after the agent drafts a chat response. The agent's own discipline (invoke `claim-reviewer` before sending) was the only line of defense, and a builder determined to ship a confident answer could simply skip the invocation. This was acknowledged at the time as the single unclosed gap in Gen 4 enforcement.

Gen 6 (shipped 2026-04-26 / 2026-04-27) introduced four narrative-integrity Stop hooks plus one PR-time PreToolUse hook. These hooks fire *mechanically* against the session transcript, the user-prompt history, and the staged PR body — they do not depend on the agent invoking them. The question this audit answers: **how much of `claim-reviewer`'s residual coverage have the Gen 6 hooks superseded?**

## Methodology

For each FAIL category in `claim-reviewer.md` (categories A through G, 19 numbered failure conditions), I asked:

1. **What phenotype does this category catch?** (Restated in plain language.)
2. **Does any Gen 6 hook now fire mechanically against the same phenotype?** (Cross-referenced against the five hook names.)
3. **If yes, does the hook catch it as well as `claim-reviewer` would, or only partially?**
4. **Recommendation per category:** deprecate (Gen 6 fully covers), keep (still residual coverage), or mechanize (Gen 6 partially covers but a sharper hook would close it).

## Per-claim-class table

| Cat. | claim-reviewer phenotype | Gen 6 coverage | Verdict |
|---|---|---|---|
| A.1 | "We have X" / "X works" without `file:line` | None of the five hooks parse the assistant's last chat message for citation density. The closest is `vaporware-volume-gate.sh` but it only fires on `gh pr create`, not on chat replies. | **keep** |
| A.2 | Present-tense behavior claims ("the system sends...") without citation | Same gap — no Stop hook reads the final assistant message for tense + citation. `transcript-lie-detector.sh` reads the transcript for self-contradiction across messages, not for missing citations within one message. | **keep** |
| A.3 | "Currently / today / already" claims without citation | Same gap. | **keep** |
| B.4 | Citation file does not exist | No Gen 6 hook validates citation paths. `claim-reviewer` does this via `Read`/`Grep`. | **keep** |
| B.5 | Citation line number doesn't contain claimed code | Same — no hook does this verification. | **keep** |
| B.6 | Citation points to different feature than claimed | Same — semantic mismatch detection requires LLM-level reasoning, not regex. | **keep** |
| C.7 | Hedging language ("should work" / "probably") | `imperative-evidence-linker.sh` looks for user imperatives without matching evidence — orthogonal. No hook scans for hedge words in chat replies. | **keep** |
| C.8 | "Based on what I built earlier" without fresh grep | Adjacent to `transcript-lie-detector.sh` (catches self-contradiction across the transcript), but transcript-lie-detector compares completion-claim vs. deferral-claim within the same session — it doesn't verify "what I built earlier still exists." | **keep** |
| D.9 | Future-tense ("we'll add") mixed with "we have" | Adjacent to `transcript-lie-detector.sh` if the future-tense and present-tense claims contradict each other across messages. Single-message conflation isn't caught. | **keep (partial overlap)** |
| D.10 | "I planned to build" as evidence feature exists | Adjacent to `goal-coverage-on-stop.sh` — that hook catches user goals not honored, but doesn't catch the inverse (agent claims a thing was built that was only planned). | **keep** |
| E.11 | Claim feature "is used" without tracing caller | No Gen 6 hook traces caller chains. `claim-reviewer`'s grep-the-codebase verification is irreplaceable here. | **keep** |
| E.12 | Claim DB column "stores" data without writer evidence | Same — no Gen 6 hook reads the codebase to verify writers exist. | **keep** |
| F.13 | Vague qualifiers ("typically", "in the general case") | No Gen 6 hook scans chat replies for qualifier words. | **keep** |
| F.14 | Answers a different question than was asked | `goal-coverage-on-stop.sh` extracts verbs from the *first* user message and checks evidence — orthogonal. Per-question relevance check doesn't exist. | **keep** |
| G.15 | "I fixed X" without citing change AND verification | `transcript-lie-detector.sh` catches this when the fix-claim contradicts a deferral-claim later in the same session. **Partial overlap.** Doesn't catch the case where the fix-claim is unique in the transcript but unsupported. | **keep (partial overlap)** |
| G.16 | "Error no longer appears" without before-state observation | Adjacent to `transcript-lie-detector.sh` but only catches contradictions, not missing baseline. `vaporware-volume-gate.sh` catches the high-doc-volume PR variant of this but not chat-reply variant. | **keep** |
| G.17 | "Tests pass" as sole evidence of fix | None of the five hooks require the specific failing-then-passing test to be named. | **keep** |
| G.18 | "Deployment succeeded so fix is live" | None catch the absence of a runtime check against production. | **keep** |
| G.19 | "I addressed the root cause" without causal trace | None of the five hooks force a causal-trace structure. | **keep** |

**Coverage summary:** 0 of 19 categories are *fully* superseded by Gen 6 hooks. 3 of 19 (D.9, G.15, G.16) have partial overlap with `transcript-lie-detector.sh` — when the unsupported claim contradicts another claim in the same transcript, the lie-detector catches it. 16 of 19 have no Gen 6 coverage.

## Why Gen 6 doesn't supersede claim-reviewer

The Gen 6 narrative-integrity hooks all operate against **transcript-wide signals or PR-time signals**:

- `transcript-lie-detector.sh` — cross-message self-contradiction in the session
- `goal-coverage-on-stop.sh` — first-message goals vs. tool-call evidence in the session
- `imperative-evidence-linker.sh` — user imperatives vs. tool-call evidence
- `deferral-counter.sh` — deferrals in transcript vs. surfacing in final message
- `vaporware-volume-gate.sh` — PR diff stat (doc lines vs. code lines) at `gh pr create` time

None of them perform **intra-message citation verification** against the live codebase. `claim-reviewer`'s job is to read a *single draft response*, extract every "we have X" / "X works" / "X is fixed" sentence, grep the cited file, read the cited line, and confirm the claim. That is irreducibly an LLM-with-codebase-tools task, not a regex-on-transcript task.

The Gen 6 hooks are stronger than `claim-reviewer` along the axes they cover — they fire mechanically and cannot be skipped. But the axes they cover are different from `claim-reviewer`'s axis. Claims made in chat that don't contradict other transcript content, that aren't first-message goals, that don't lack tool-call evidence (because the tool calls happened in *prior* sessions), that aren't user-imperatives, that aren't deferrals, and that aren't shipped in PR bodies — those still live or die on `claim-reviewer`'s discipline.

## Recommendation

**KEEP `claim-reviewer` as-is.** It remains the only line of defense for in-chat verbal vaporware where claims don't contradict other transcript content. Deprecating or removing it would re-open the Gen 4 residual gap with no replacement.

**Document the partial overlaps** (D.9 / G.15 / G.16) in `claim-reviewer.md` itself so a future builder reading the agent file knows that some FAIL conditions may also surface from the Stop-hook chain — `claim-reviewer` is no longer the *only* path that catches them, but it is still the most reliable one for in-the-moment chat replies.

**Do not mechanize the residual.** The reason Gen 4 left this as a self-invoked agent rather than a hook was: PostMessage hooks don't exist in Claude Code. That constraint is unchanged in 2026-05. Until Anthropic ships a PostMessage event, no hook can fire after a chat reply is drafted. The next-best mitigation — a UserPromptSubmit hook that detects when the *user* asks a "does X work?" question and reminds the agent to invoke `claim-reviewer` — was considered for Gen 5 and rejected as too noisy (most product Q&A questions don't need full claim-review; the agent's own judgment of when to invoke is correct most of the time).

**Reassessment trigger:** if Anthropic ships a PostMessage hook event, revisit this audit immediately. That single architectural change would make most of the 16 keep-classed conditions mechanizable, and the agent could be deprecated in favor of a hook that fires on every assistant chat reply.

## What didn't get audited (out of scope)

- **The agent's class-aware feedback format.** Section "Output Format Requirements — class-aware feedback" in `claim-reviewer.md` is an internal output-discipline rule for the agent's own FAIL responses. It's orthogonal to the Gen 6 supersession question.
- **Whether the agent gets invoked enough in practice.** This audit assumes the agent is invoked when product Q&A occurs. Empirical invocation frequency is a separate question (telemetry-class; deferred per Phase 1d-E-2 sub-gap D scope).
- **Whether the 19 FAIL categories are themselves the right enumeration.** Audit took the agent's current categories as given.
