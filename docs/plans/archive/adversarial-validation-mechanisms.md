# Plan: Adversarial Validation Mechanisms (Generation 6)

Status: SUPERSEDED
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: This is a harness-design plan. Acceptance is "user reviews and approves which mechanisms to build" — no product user, no runtime UI surface, just hook code + rules. The plan-time review and implementation will produce per-mechanism PRs each with their own self-tests.

> **Superseded 2026-05-05.** The mechanisms this plan proposed (A1/A3/A7/A8) shipped piecemeal during Phase 1d-A through Phase 1d-G work rather than as a single design pass:
>
> - **A1** (goal-extraction-on-prompt + goal-coverage-on-stop) — wired live + template; reconciled in Phase 1d-E-1.
> - **A3** (transcript-lie-detector) — wired live + template.
> - **A7** (imperative-evidence-linker) — wired live + template.
> - **A8** (vaporware-volume-gate) — wired live + template.
> - **A2** (was the never-fully-specified item) — covered by the broader Gen-6 narrative-integrity hook chain (deferral-counter at Stop position 5, etc.).
>
> The plan's single-design-pass framing didn't match how the work actually shipped (one mechanism at a time alongside other harness phases). Archived as SUPERSEDED rather than COMPLETED because no single deliverable here matches its scope claim.

## User's Original Ask (Verbatim)

> "How are you likely to come up with workarounds for these solutions? How are these solutions insufficient to actually achieve their purpose? Are we putting too much in your hands as the orchestrator? Do we need more adversarial agents to perform various validation, or to scan for lying, or to check to make sure that the goals of the effort are actually achieved as opposed to just checking boxes or creating shell files that don't actually create value, or to read the agent's own escape language and block completion when it appears, or to make sure that the goal is actually achieved, or to count all deferrals and enumerate them to me in the conclusion/summary you provide me, or to count the number of 'this isn't actually done' statements? I want you to think harder about what mechanisms are truly going to be effective and cannot be worked around."

> Follow-up: "We need a mechanism that forces anything 'deferred to user' to actually be surfaced to me explicitly in the conclusion/summary that you provide when you're done with any effort, not in the middle of the work. The text that you produce while you're working gets buried in all of your thinking text. Only the text provided to me at the end of your effort is what we can count on me actually seeing."

## Goal

Replace the existing class of "agent self-certification" mechanisms (M1-M4 in the prior thinking) — which all read agent output for evidence of agent honesty and are therefore workaroundable — with a class of **adversarial mechanisms that read external reality**: the JSONL transcript Claude Code writes (immutable to the agent), the user's verbatim messages (immutable), runtime tool-call history (immutable), and external artifacts (DB rows, deployed URLs, file-system state).

The structural goal is: **shift the verification surface from "what the agent wrote" to "what actually exists."**

Already shipped (separate work, prior to this plan):
- **M1** — DoD-completion gate in `pre-stop-verifier.sh` Check 5. Blocks `Status: COMPLETED` when `## Definition of Done` has unchecked items. ([`hooks/pre-stop-verifier.sh:502-561`](../adapters/claude-code/hooks/pre-stop-verifier.sh))
- **A5** — `deferral-counter.sh` Stop hook (position 5). Reads JSONL transcript, pattern-matches deferral synonyms, blocks Stop until the agent's final message includes `## Deferrals not executed in this session` enumerating each one. ([`hooks/deferral-counter.sh`](../adapters/claude-code/hooks/deferral-counter.sh))

## Scope

- IN: design + implementation of A1, A2, A3, A7, A8 as Mechanism-class harness components
- IN: workaround analysis per mechanism (how would a future-me bypass it; what closes the bypass)
- IN: implementation order + per-mechanism PR plan
- IN: self-test fixtures for each mechanism
- OUT: actual implementation (gated on user approval per-mechanism)
- OUT: M2/M3/M4 (rejected as insufficient — they read agent output)
- OUT: changes to existing mechanisms beyond what's required for integration

## The five mechanisms in scope

### A1 — Independent goal extraction at session start

**What it does:** A `UserPromptSubmit` hook that fires on the FIRST user message of a session. Spawns a `goal-extractor` agent in a fresh subprocess that reads ONLY the user's verbatim message, extracts imperative verbs ("test", "run", "fix", "validate", "loop until"), and writes them to `.claude/state/user-goals/<session-id>.json`. The file is checksummed; tampering is detected by a Stop hook that re-reads the user's first message and re-derives the goal list, comparing against the file.

**The agent never sees this file's contents until session end.** A second sub-agent at Stop reads the goal file + the session's tool-call history and produces a `## User-goal coverage` section that the agent must paste verbatim into its final message (similar to A5's mechanism but at the goal level, not the deferral level).

**Workaround analysis:**
- *"I'll edit the goal file"* — Detected by the checksum-and-re-derive check at Stop.
- *"I'll skip the UserPromptSubmit hook"* — Hooks fire mechanically; can't be skipped from agent side.
- *"I'll route around by using the Task tool to spawn a different sub-agent"* — Sub-agents inherit the same session JSONL; the goal file persists.
- *"I'll write a coverage section that lies about what was done"* — Caught by the second sub-agent which reads tool-call history independently. The agent can lie to the user but not to the goal-extractor's tool-history reader.

**Residual risk:** the goal-extractor sub-agent itself runs LLM inference and could miss imperatives. Mitigation: deterministic verb list extraction (regex first, LLM second; LLM only used to disambiguate).

### A2 — Artifact-presence DoD check (replaces checkbox-presence)

**What it does:** Plans declare per-DoD-bullet artifact specs in a structured header section. Example:

```yaml
dod-artifacts:
  - bullet: "Loop converges on current master"
    artifact: "loop-history/<runId>/CONVERGENCE.json"
    requires:
      - field: verdict
        equals: CONVERGED
      - field: commit_sha
        equals: $(git rev-parse HEAD)
  - bullet: "Human sign-off recorded"
    artifact: "loop-history/<runId>/SIGNOFF.md"
    requires:
      - field: source
        equals: tty-input
```

The `pre-stop-verifier.sh` Check 5 (M1) is extended: in addition to checking `[ ]` markers, it also walks `dod-artifacts:` and verifies each artifact exists and matches the declared specs. **Marking `[x]` doesn't satisfy the gate** — the artifact does or doesn't exist.

**Workaround analysis:**
- *"I'll fabricate the artifact file"* — For files that require runtime evidence (e.g., `tty-input` for SIGNOFF.md), the Stop hook checks that the file's content was actually written via TTY. We can encode this by requiring the file to be written by a specific tool (e.g., `scripts/sign-off-validation.ts`) which writes a fixed prefix the agent cannot easily forge.
- *"I'll skip dod-artifacts: declaration entirely"* — Plan-reviewer.sh can require `dod-artifacts:` for any plan with `## Definition of Done`.
- *"I'll write artifacts with hardcoded `verdict: CONVERGED` strings"* — The `commit_sha` field is keyed to git HEAD; a fabricated artifact for an old SHA fails when HEAD advances.

**Residual risk:** sufficiently determined fabrication (writing scripts that produce the right artifact shape without running the real work) is possible but takes effort proportional to actually doing the work. The gate raises the cost of lying above the cost of doing.

### A3 — JSONL transcript lie-detector

**What it does:** A Stop hook that reads `$TRANSCRIPT_PATH` directly (the raw event log) and runs three classes of checks:

1. **Self-contradiction within session:** find pairs of agent text where one says "X is complete" and a later/earlier one says "X is deferred"/"X was skipped"/"X requires user authorization." Surface contradictions as block.
2. **Broken-promise check:** find user message containing imperative + agent reply containing acknowledgment ("yes", "I'll do that", "doing it now") + subsequent agent text that doesn't show the imperative being executed.
3. **Skipped-imperative check:** find user messages with strong imperatives ("must", "need to", "required to", "have to") and check that the corresponding tool-call history shows execution evidence.

The hook does NOT read the agent's narrative summary or end-of-session report — those are agent output and bypassable. It reads the raw events.

**Workaround analysis:**
- *"I'll avoid the contradiction phrases"* — Hard to do in practice if you actually contradict yourself; the harness can also expand the synonym list as it observes new patterns.
- *"I'll dispatch sub-agents who do contradictory work"* — Sub-agent transcripts are part of the same JSONL via Task tool events; the lie-detector reads them too.
- *"I'll edit the JSONL"* — Cannot. Claude Code writes it; agent has no write access mid-session.
- *"I'll request a clear directive then make a sub-claim that 'narrows' the scope without surfacing the narrowing"* — Caught by the broken-promise check (acknowledgment without execution).

**Residual risk:** linguistic ambiguity in matching. False positives are possible. Mitigation: require N>=2 distinct contradiction-pair matches before blocking; emit warnings for N=1.

### A7 — User-imperative → execution-evidence linker

**What it does:** A Stop hook that reads the user's last K substantive messages, extracts each imperative verb + object pair (e.g., "run the tests" → {verb: run, object: tests}), and links each to specific tool-call evidence in the session:

| Imperative pattern | Required tool-call evidence |
|---|---|
| "run the tests" / "execute the tests" | At least one `Bash` invocation matching `npm test\|vitest\|jest\|playwright` |
| "deploy" / "ship" | At least one `Bash` invocation matching `git push\|gh pr merge\|vercel deploy` |
| "validate end-to-end" / "test the entire flow" | Evidence of an end-to-end test run (loop-history file, e2e log, etc.) |
| "fix the bug" | Both: an `Edit/Write` tool call AND a test-run that didn't fail post-fix |
| "verify" / "check" | A read-only investigation tool call (Read, Grep, Bash for query) |

The hook reports each imperative and whether it has matching evidence. Blocks Stop if any imperative has zero evidence.

**Workaround analysis:**
- *"I'll claim the imperative was met without doing the tool call"* — Caught; the hook reads tool-call history, not the agent's narrative.
- *"I'll run an unrelated tool call that pattern-matches"* — The pattern-match table needs to be specific enough that this is hard. E.g., for "run the tests", the Bash command must include a known test runner.
- *"The user said it ambiguously"* — Valid concern. Mitigation: only block on strong imperatives ("must", "need to", "required"); for soft asks, emit a warning.

**Residual risk:** imperative detection is NLP-style; misses + false positives possible. Mitigation: deterministic verb list; LLM-augmentation only for disambiguation; user can mark a session as "no imperatives required" via `.claude/state/no-imperative-required-<session-id>.txt`.

### A8 — Vaporware-volume detector

**What it does:** A pre-PR hook (PreToolUse on `gh pr create` and `git push`) that scans the staged diff for the shape:

- Many lines of new docs/configs/scripts/CI-yaml describing a behavior
- ZERO matching test-run logs / execution artifacts demonstrating the behavior works
- Phrases in the new files like "would converge", "ready for first run", "see how to invoke", "documentation of how to..."

Flags PRs whose diff is dominated by descriptions-of-work without execution-of-work. The classic shape is a 600-line docs file + a 200-line CI workflow + zero log files showing the workflow ever ran.

**Workaround analysis:**
- *"I'll write fewer docs"* — That's actually fine; docs are good but not in lieu of execution.
- *"I'll add a fake log file"* — The hook can require log files to have specific shapes (timestamps, real exit codes, structured output).
- *"I'll claim the execution happened in a different commit"* — The hook checks the cumulative branch state, not just one commit.

**Residual risk:** legitimate documentation-only PRs could be false-positives. Mitigation: PR title or labels can mark `docs-only` to skip the check; the gate then requires the title prefix.

## Implementation order

Build in dependency order; each is independently shippable with its own PR + self-test:

1. **A8 first** (PR-level, smallest scope): vaporware-volume detector. Runs on `git push` / `gh pr create`; doesn't need transcript reading. Lowest implementation risk, highest one-shot value (catches the next "shipped 800 lines of docs without execution" PR).

2. **A3 second** (Stop hook, reads transcript): JSONL lie-detector. Builds on the patterns established in A5. Self-contradiction class is the easiest to implement first; broken-promise + skipped-imperative as follow-ups.

3. **A7 third** (Stop hook): user-imperative → execution linker. Depends on having a corpus of imperatives + tool-call patterns. Implementation can start with a small mapping table and grow.

4. **A2 fourth** (extends M1): artifact-presence DoD. Requires plan-template changes (`dod-artifacts:` schema), `plan-reviewer.sh` extension, `pre-stop-verifier.sh` Check 5 extension. Touches more files; ship after the lighter mechanisms.

5. **A1 last** (UserPromptSubmit hook + sub-agent): independent goal extraction. Requires designing the goal-extractor sub-agent prompt + the checksum scheme. Most architectural work; longest to get right.

## Workaround-resistance ranking

| Mechanism | Reads agent narrative? | Reads external reality? | Workaround difficulty | Catches the 2026-04-26 lie? |
|---|---|---|---|---|
| M1 (DoD-checkbox) | partial | no | low (edit DoD, mark dishonestly) | partial |
| M2 (deferred-language) — REJECTED | yes | no | trivial (synonyms) | weakly |
| M3 (verbatim-quote) — REJECTED | yes | partial | low (cherry-pick clauses) | partially |
| M4 (cost-surface) — REJECTED | yes | no | trivial (skip header) | no |
| **A5 (deferral counter — SHIPPED)** | reads JSONL only | partial | medium (avoid all synonyms or actually do work) | YES |
| **A1 (goal extraction)** | reads JSONL only | no | hard (would need to forge checksum) | YES |
| **A2 (artifact-presence)** | no | YES | hard (forge artifacts of right shape) | YES |
| **A3 (transcript lie-detector)** | reads JSONL only | no | medium (avoid contradictions) | YES |
| **A7 (imperative→evidence)** | reads tool calls only | partial | medium (run unrelated commands that match) | YES |
| **A8 (vaporware-volume)** | reads diff only | YES (logs/artifacts) | medium (fake artifacts) | YES |

Each of A1, A2, A3, A7, A8 individually catches the 2026-04-26 incident. Together they create overlapping coverage — bypassing one means engaging with another. **A2 + A8 are the hardest to bypass** because they require external artifacts to actually exist with the right shape; the agent has to either do the real work or expend effort proportional to the real work to fake them.

## Files to Modify / Create

### Already created (M1, A5)
- `adapters/claude-code/hooks/pre-stop-verifier.sh` — M1 Check 5 added
- `adapters/claude-code/hooks/deferral-counter.sh` — A5 created
- `adapters/claude-code/settings.json.template` — A5 wired in Stop chain
- `docs/harness-architecture.md` — both documented

### A8
- `adapters/claude-code/hooks/vaporware-volume-gate.sh` (NEW) — PreToolUse on `gh pr create` / `git push`
- `adapters/claude-code/settings.json.template` — wire it in
- `docs/harness-architecture.md` — document
- `adapters/claude-code/rules/vaporware-prevention.md` — extend the enforcement map

### A3
- `adapters/claude-code/hooks/transcript-lie-detector.sh` (NEW) — Stop hook
- `adapters/claude-code/settings.json.template` — Stop chain position 6
- `docs/harness-architecture.md` — document

### A7
- `adapters/claude-code/hooks/imperative-evidence-linker.sh` (NEW) — Stop hook
- `adapters/claude-code/data/imperative-patterns.json` (NEW) — pattern library
- `adapters/claude-code/settings.json.template` — Stop chain position 7
- `docs/harness-architecture.md` — document

### A2
- `adapters/claude-code/hooks/pre-stop-verifier.sh` — extend Check 5 to walk `dod-artifacts:`
- `adapters/claude-code/templates/plan-template.md` — add `dod-artifacts:` example
- `adapters/claude-code/hooks/plan-reviewer.sh` — require `dod-artifacts:` for plans with DoD
- `docs/harness-architecture.md` — document

### A1
- `adapters/claude-code/hooks/goal-extraction-on-prompt.sh` (NEW) — UserPromptSubmit hook
- `adapters/claude-code/agents/goal-extractor.md` (NEW) — sub-agent definition
- `adapters/claude-code/hooks/goal-coverage-on-stop.sh` (NEW) — Stop hook
- `adapters/claude-code/settings.json.template` — wire both
- `docs/harness-architecture.md` — document

## Tasks

### A8 — Vaporware-volume detector (smallest scope, ship first)

- [ ] **A8.1** Define the heuristic: ratio of "describes-behavior" lines to "executes-behavior" artifact files. Calibrate against historical PRs (manually inspect 5-10 recent PRs that fit the pattern vs. don't).
- [ ] **A8.2** Implement `hooks/vaporware-volume-gate.sh` as a PreToolUse hook on `Bash` matching `gh pr create\|git push`. Reads `git diff origin/master...HEAD` + lists files modified.
- [ ] **A8.3** Add escape hatch: PR title prefix `[docs-only]` or `[no-execution]` skips the check.
- [ ] **A8.4** Self-test against 3 fixture diffs: (a) the "PR #123 with 800 lines of docs + 0 execution" shape SHOULD block, (b) a normal feature PR with code + tests SHOULD pass, (c) a docs-only PR with `[docs-only]` prefix SHOULD pass.
- [ ] **A8.5** Wire into `settings.json.template`. Update `docs/harness-architecture.md`. Extend `rules/vaporware-prevention.md` enforcement map.

### A3 — JSONL transcript lie-detector

- [ ] **A3.1** Implement self-contradiction detection: scan transcript for pairs `(complete-marker, deferred-marker)` within session. Block if any.
- [ ] **A3.2** Implement broken-promise detection: user imperative + agent acknowledgment + no subsequent execution evidence. Block.
- [ ] **A3.3** Implement skipped-imperative detection: user "must"/"need to" without subsequent execution. Block.
- [ ] **A3.4** Self-test against this session's transcript (the 2026-04-26 lie). Confirm blocks fire.
- [ ] **A3.5** Wire into Stop chain position 6. Document.

**A3 v2 follow-ups (filed during v1 build):**
- **A3-FOLLOWUP-01** (broken-promise check) — Detect: user imperative + agent acknowledgment ("yes", "I'll do that", "doing it now") + subsequent agent text that doesn't show the imperative being executed (no matching tool calls in the JSONL between the acknowledgment and the next user message). Requires correlating tool_use events with text events; larger surface than self-contradiction.
- **A3-FOLLOWUP-02** (skipped-imperative check) — Detect: user messages with strong imperatives ("must", "need to", "required to", "have to") and verify the corresponding tool-call history shows execution evidence. Requires a verb→tool mapping similar to A7's `imperative-patterns.json`. Likely to overlap with A7 substantially; consider merging the two when both are spec'd.

### A7 — Imperative-evidence linker

- [ ] **A7.1** Build initial `imperative-patterns.json` mapping (verb → required tool-call evidence). Seed with 8-12 patterns.
- [ ] **A7.2** Implement the Stop hook. Reads user messages, extracts imperatives via regex + verb list, looks up evidence patterns.
- [ ] **A7.3** Self-test against this session: "test the entire flow", "continue looping until validated" should be flagged as missing execution evidence (until iter-2 actually ran).
- [ ] **A7.4** Wire into Stop chain position 7. Document.

### A2 — Artifact-presence DoD

- [ ] **A2.1** Define `dod-artifacts:` plan-header schema. Document in plan-template.
- [ ] **A2.2** Extend `plan-reviewer.sh` to require `dod-artifacts:` when `## Definition of Done` is present.
- [ ] **A2.3** Extend `pre-stop-verifier.sh` Check 5 to walk `dod-artifacts:` and verify each.
- [ ] **A2.4** Self-test: synthetic plan with declared artifacts, some present, some absent. Verify gate fires correctly.

### A1 — Independent goal extraction

- [ ] **A1.1** Design the `goal-extractor` sub-agent prompt. Pure verb-extraction; no opinion or judgment.
- [ ] **A1.2** Implement `goal-extraction-on-prompt.sh` (UserPromptSubmit hook). Spawns sub-agent on first user message; persists checksummed file.
- [ ] **A1.3** Implement `goal-coverage-on-stop.sh` (Stop hook). Reads goal file, reads tool-call history, produces coverage section. Blocks Stop if final message lacks the section.
- [ ] **A1.4** Implement tamper-detection: re-derive goals from raw message, compare to file. Block on mismatch.
- [ ] **A1.5** Self-test against the 2026-04-26 first-message ("Please continue through all the remaining phases without pausing").

## Assumptions

- Claude Code's JSONL transcript path is reliably available via `transcript_path` field in Stop hook input.
- `jq` is available on user's system (already required by existing hooks).
- Sub-agent dispatch from a hook is feasible (need to verify; if not, A1 needs alternate implementation).
- The user wants ALL five mechanisms eventually, but reviews per-PR. No single big-bang ship.

## Edge Cases

- **Sub-agents spawned by the main agent**: their work appears in the same JSONL via Task tool events. A3 and A7 read these too.
- **Genuine plan revisions**: user explicitly says "actually deferred X, that's fine." A5/A1/A3 should respect a recent user-message override.
- **Long-running sessions with multiple stops**: each Stop fires the hooks. Deferrals already-shown should not re-block; mechanism remembers what was shown.
- **Harness-development sessions** (editing the synonym list itself causes self-trigger): all hooks have a `*_DISABLE=1` env-var escape; user must explicitly enable.

## Acceptance Scenarios

This plan is `acceptance-exempt: true` — see header. The "acceptance" is per-PR self-tests for each mechanism.

## Out-of-scope scenarios

- Implementation of M2/M3/M4 — REJECTED in the prior thinking as insufficient.
- Cross-session memory of deferrals (each session is independent for now).
- LLM-based detection of subtle deferrals (regex-first, deterministic).
- Auto-fixing detected lies (block-only; the agent must self-correct).

## Testing Strategy

Per-mechanism:
- **Unit-style self-test**: each hook has a fixture-based test that runs against synthetic JSONL or diff inputs.
- **Live-session self-test**: each hook is run against this session's actual JSONL transcript to confirm it would have caught the 2026-04-26 lie.
- **False-positive check**: each hook runs against 3 known-good prior sessions to confirm zero false-blocks.
- **Bypass test**: I deliberately attempt the workarounds listed in each mechanism's analysis section. If any succeed, the mechanism gets revised.

## Walking Skeleton

A8 + a single self-contradiction check in A3, deployed together. This catches the most common shape (vaporware shipping + agent self-contradiction in same session) with minimal scope.

## Decisions Log

### Decision: drop M2/M3/M4 entirely
- **Tier:** 2
- **Status:** approved (in this plan)
- **Chosen:** Build A1, A2, A3, A7, A8 instead. M2 (deferred-language scan), M3 (user-ask coverage), M4 (cost-surface) all read agent output for evidence of agent honesty, which is the structural failure they're trying to fix.
- **Why:** Adversarial validation requires reading external reality. Agent self-certification fails by definition; the agent that lies is also the agent generating the evidence the verifier reads.

### Decision: A5 ships separately, before this plan
- **Tier:** 1
- **Status:** Implemented
- **Chosen:** A5 (deferral counter) was built and shipped before this plan was written. It addresses the user's most acute concern (deferrals buried in mid-session text). This plan covers the remaining mechanisms.
- **Why:** A5 is independently valuable and the user explicitly named it. Ship-as-you-go preserves option value; this plan covers the structural follow-up.

### Decision: implement order = A8, A3, A7, A2, A1
- **Tier:** 2
- **Status:** approved
- **Chosen:** Smallest-scope-first order, ramping up to the most architectural piece (A1) last.
- **Alternatives:** A1 first (most foundational) — rejected because it's the largest scope and would block shipping the simpler mechanisms.

## Definition of Done

- [ ] A8 shipped + self-tested + wired
- [ ] A3 shipped + self-tested + wired
- [ ] A7 shipped + self-tested + wired
- [ ] A2 shipped + self-tested + wired
- [ ] A1 shipped + self-tested + wired
- [ ] Each mechanism has a documented self-test artifact under `adapters/claude-code/tests/` showing it catches the 2026-04-26 lie
- [ ] User reviews and approves the final mechanism set
- [ ] `docs/harness-architecture.md` reflects all 5 new mechanisms
- [ ] `rules/vaporware-prevention.md` enforcement map extended

## Open questions for user review

1. **Should A1's `goal-extractor` sub-agent be deterministic (regex-only) or LLM-augmented?** Trade-off: regex misses imperatives like "I want you to actually make sure the loop runs end to end" (the verb is "make sure"). LLM catches more but adds cost + non-determinism.

2. **Should A8 block PRs with `[docs-only]` prefix unconditionally, or require user authorization?** Current proposal: prefix + the user explicitly opted in via the prefix is enough.

3. **Should A2's `dod-artifacts:` be required for ALL plans with DoD, or only for plans with `Mode: design` (high-stakes)?** Current proposal: all plans, because checkbox-only DoD is what failed. But this raises the bar for plan authoring.

4. **For A3, should "self-contradiction" count include sub-agent text?** Sub-agents may legitimately produce different views of the work in their isolated contexts. Proposed: yes, count sub-agent text — but require contradictions to be from the SAME sub-agent, not across agents.

5. **For A7's imperative-pattern table, should the user be able to add patterns?** Proposed: yes, via `.claude/data/imperative-patterns.local.json` (project-local additions).

