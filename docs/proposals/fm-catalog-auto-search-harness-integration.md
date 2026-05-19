# Proposal — FM-catalog auto-search at session spawn (harness integration)

> **Status:** Proposal only. This document specifies the design; it does NOT ship the hook. Implementation is a separate execution (own plan, own PR). Ratified context: Decision 033, `docs/conventions/failure-mode-catalogs.md`, FM-028.

## The problem this closes

The investigation-first reflex (`~/.claude/rules/diagnosis.md` "Check the Failure-Mode Catalog Before Forming a Hypothesis") relies on the agent *remembering* to grep `docs/failure-modes.md`. Doctrine-that-relies-on-memory drifts under context pressure — exactly the case (a long, frustrating investigation) where the catalog matters most and where the agent is least likely to stop and grep. FM-028 catalogs this very class. The highest-leverage closure is to make the lookup **reflexive and mechanical**: surface candidate FM matches automatically at session start so the agent sees them without having to remember to look.

## Design

A new SessionStart hook, `fm-catalog-surfacer.sh`, modeled almost exactly on the existing `discovery-surfacer.sh` (the proven precedent: a SessionStart hook that scans a `docs/` artifact and injects a system-reminder block, silent when nothing matches or the artifact is absent, always exit 0).

### Which hook fires, when

- **Event:** `SessionStart` (matcher `startup`), same event class as `discovery-surfacer.sh`.
- **Wiring:** added to the SessionStart hook chain in `adapters/claude-code/settings.json.template` (canonical) and synced to `~/.claude/settings.json` (live mirror), positioned after `discovery-surfacer.sh`.
- **Activation gate:** runs only when BOTH (a) `docs/failure-modes.md` exists in the working directory, and (b) the session has an investigation-shaped trigger (see "Input source" — if no signal text is available, the hook is silent rather than dumping the whole catalog).

### Input source (what keywords it searches for)

The hook needs the session's intent text to extract keywords. Priority order, first that resolves:

1. **The verbatim first user message**, already checksummed and persisted by the existing `goal-extraction-on-prompt.sh` (UserPromptSubmit) → `~/.claude/state/` artifact. SessionStart precedes the first user message, so this is consumed on the *next* hook tick or via a SessionStart→UserPromptSubmit deferral (see "Open question 1").
2. **The session title / spawn prompt**, when the session was spawned via `mcp__ccd_session__spawn_task` / `Task` (the title/prompt is in the spawn `tool_input`, surfaced through the same mechanism `spawned-task-result-surfacer.sh` uses).
3. **Fallback:** if no intent text is available at SessionStart, the hook is silent. It does NOT dump the whole catalog (noise, defeats the signal). Resolution of the timing question is Open Question 1.

### What it does

1. Confirm `docs/failure-modes.md` exists; else exit 0 silent (projects without a catalog see no churn — same graceful-degrade contract as `discovery-surfacer.sh`).
2. Extract candidate keywords from the intent text: lowercase, drop stopwords, keep nouns/verbs/error-string-like tokens and any `[A-Z]{2,6}` acronyms or quoted strings.
3. For each `## FM-NNN` entry, grep the entry's `Symptom` and `Discriminator` field text for keyword overlap. Score by distinct-keyword-match count.
4. If one or more entries score above a threshold (default: ≥ 2 distinct keyword matches — tunable, `(hypothesis, pending pilot evidence)`), emit ONE system-reminder block:

   ```
   [fm-catalog] This session's intent overlaps known failure classes. Before forming a
   hypothesis, check these — they may already name what you are about to investigate:
     • FM-024 — <title>   (matched: <keywords>)
         Discriminator: <one-line>
         Recovery: <one-line>
     • FM-027 — <title>   (matched: <keywords>)
         ...
   Full entries: docs/failure-modes.md. This is a hint, not a verdict — confirm via the
   Discriminator before assuming the match.
   ```

5. If zero entries match, exit 0 silent (no "no matches" noise).
6. Never blocks. SessionStart hooks are advisory by nature; this one only injects context. Exit 0 always (mirrors `discovery-surfacer.sh`).

### Why injection-at-spawn beats reflex-only

Reflex-only (the `diagnosis.md` rule alone) is Pattern: it works when the agent remembers. Injection-at-spawn is the Mechanism layer: the candidate FMs are *in the agent's context before it forms its first hypothesis*, with the Discriminator right there to confirm/reject the match. The agent does not have to choose to look — the look already happened. This is the standard harness Mechanism+Pattern split (the reflex rule is the Pattern; this hook is the Mechanism).

## False-positive control

- **Threshold (≥ 2 distinct keyword matches):** a single common word ("error", "fails") does not trigger; two specific tokens overlapping a Symptom is the floor. Tunable; tag the chosen value `(hypothesis, pending pilot evidence)` per the harness's AP16 cadence discipline.
- **Hint framing, not verdict:** the injected block explicitly says "confirm via the Discriminator before assuming the match" — the Discriminator field exists precisely so a surfaced candidate can be quickly accepted or rejected, preventing the hook from anchoring the agent on a wrong FM.
- **Cap the surfaced set:** at most the top 3 by score; if more than 3 match, surface the top 3 and a count ("+N more — grep the catalog").
- **Opt-out:** an `FM_CATALOG_SURFACER_DISABLE=1` env var (mirrors the established disable-env-var pattern used by other advisory hooks) for sessions where the catalog is being edited itself (avoid self-trigger on the catalog's own test fixtures).

## Open questions (resolve at implementation time)

1. **SessionStart-vs-first-message timing.** SessionStart fires before the first user message, so the verbatim-first-message source (priority 1) is not yet available at that tick. Options: (a) defer the surfacer to the first UserPromptSubmit instead of SessionStart; (b) keep it at SessionStart but consume the spawn-prompt/title source only; (c) two-stage — SessionStart primes, UserPromptSubmit (first only) does the keyword match. Recommendation to evaluate first: **(c)**, because spawned investigation sessions carry intent in the spawn prompt (available at SessionStart) while interactive sessions carry it in the first message (available at first UserPromptSubmit) — (c) covers both.
2. **Keyword extraction quality.** Naive stopword-drop may under/over-match. A small fixed extraction (acronyms, quoted strings, capitalized tool/error tokens, the 5 highest-TF non-stopwords) is the proposed v1; tune against pilot evidence rather than over-engineering up front.
3. **Cross-project scope.** The hook reads the *project's* `docs/failure-modes.md` (working-directory-relative), so it works uniformly across projects with zero per-project config — consistent with the convention. No harness-repo-specific path.

## Implementation checklist (for the future execution — not this PR)

- [ ] `adapters/claude-code/hooks/fm-catalog-surfacer.sh` + `--self-test` (scenarios: no-catalog-silent, no-match-silent, single-match-below-threshold-silent, two-match-surfaces, >3-match-caps-at-3, disable-env-silent).
- [ ] Wire into `adapters/claude-code/settings.json.template` SessionStart chain after `discovery-surfacer.sh`; sync `~/.claude/settings.json`.
- [ ] Resolve Open Question 1 with a decision record if the chosen timing model is non-obvious (Tier 2).
- [ ] Enforcement-map row in `adapters/claude-code/rules/vaporware-prevention.md`.
- [ ] Update `docs/harness-architecture.md` SessionStart-hooks table.
- [ ] FM-028's `Detection` field updated from "proposed" to the shipped hook.

## Cross-references

- `docs/conventions/failure-mode-catalogs.md` — the convention this hook mechanizes.
- `docs/decisions/033-failure-mode-catalog-cross-project-convention.md` — names this proposal as the next, separate execution.
- `docs/failure-modes.md` FM-028 — the class this hook closes mechanically.
- `~/.claude/hooks/discovery-surfacer.sh` — the proven SessionStart-surfacer precedent this design mirrors.
- `~/.claude/rules/diagnosis.md` — the investigation-first reflex (the Pattern layer this hook's Mechanism layer reinforces).
