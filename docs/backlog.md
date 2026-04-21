# Neural Lace — Harness Backlog

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

## P0 — Mechanical enforcement of bug-persistence rule

**Rule (recently added to `testing.md`):** every bug identified in a session must be persisted to `docs/backlog.md` or `docs/reviews/YYYY-MM-DD-<slug>.md` before the session ends.

**Problem:** the rule is self-applied. On 2026-04-20 the maintainer violated it repeatedly within a single session (~25 bugs surfaced across PRs #60-#65, most documented only in PR bodies + chat; the consolidated list had to be reconstructed retroactively). Adding MORE rule text is not a fix — the existing `planning.md` rule already said the same thing.

**Proposed fix — `hooks/bug-persistence-gate.sh` (Stop hook):**

1. Scan the session transcript for trigger phrases that indicate a bug was identified. Non-exhaustive list:
   - "we should also…"
   - "for next session"
   - "turns out X doesn't work"
   - "let me flag this"
   - "as a follow-up"
   - "ideally we'd…"
   - "this is missing"
   - "I'll document this later"
   - "known issue"
   - "TODO:" (in conversation, not code)
2. For each match, check `git diff` since session start for any modification to `docs/backlog.md` or creation of `docs/reviews/YYYY-MM-DD-*.md`.
3. If trigger phrases exist AND no persistence happened, block session end. Print the matched phrases with ~3 lines of surrounding context and prompt the agent to persist them.
4. Allow bypass via explicit attestation file: if the agent writes `state/bugs-attested-YYYY-MM-DD-HHMM.txt` with a line per trigger-phrase-match justifying why it's not a real bug (e.g., quoted example, rhetorical hypothetical), the hook accepts that and lets the session end.
5. The attestation file lives under `.claude/state/` (gitignored) so it doesn't pollute the repo.

**Scope:** ~4 hours. Hook script, sample transcript parsing, integration with `pre-stop-verifier.sh` (if it exists; otherwise new Stop hook), tests via a dummy session transcript.

**Success criteria:** a session that surfaces a bug in conversation and doesn't edit backlog.md or docs/reviews/* must be blocked from ending.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure
