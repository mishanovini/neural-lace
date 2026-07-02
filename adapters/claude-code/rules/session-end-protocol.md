# Session-End Protocol — Every Turn Ends With Exactly One DONE / PAUSING / BLOCKED Marker

**Classification:** Hybrid (pending Wave D session-honesty-gate). The discipline of classifying *why* the turn is ending (work complete vs. waiting on the user vs. genuinely stuck) is a Pattern the agent self-applies. The "the last line of the final response MUST carry exactly one valid marker, or session-end is blocked" rule is designed as a Mechanism — `continuation-enforcer.sh` (Stop hook) exists and passes its own self-test, but is **not yet wired into the live Stop chain** (`settings.json.template`); wiring is pending Wave D session-honesty-gate. Until it lands, marker discipline (including the marker format and the TodoWrite-consistency cross-check) is Pattern-only; the honesty of the chosen marker (is it really DONE?) remains Pattern regardless of wiring status.

**Originating directive (2026-05-17):** Misha was frustrated across a full day by sessions going idle between sub-tasks without making their terminal intent explicit — a session would trail off mid-plan, the operator could not tell from the last message whether it was done, waiting, or stuck, and had to babysit. The systemic fix: force every session to *declare* its terminal intent in a machine-readable form on the last line, and make that declaration non-optional via a Stop-hook gate.

## The rule in one sentence

**Every Claude Code session MUST end its turn with EXACTLY ONE of three markers, alone on the last non-empty line of its final response: `DONE: <summary>`, `PAUSING: <reason + what user input is needed>`, or `BLOCKED: <specific blocker + what unblocks it>`.** Without a valid marker the `continuation-enforcer.sh` Stop hook blocks session end and tells the agent to append one.

## The three markers

### `DONE: <one-line summary of what shipped>`

All declared work is complete and the session can wind down. "Declared work" is the plan task list, the backlog items the session committed to, and the user's standing directive — not "a stopping point I picked." Use `DONE:` only when:

- Every plan task that was not explicitly deferred by the user is checked off (or the plan's `Status:` is a terminal value), AND
- There are no incomplete `TodoWrite` items (the hook cross-checks this — see below), AND
- The summary names *what shipped*, concretely, in one line (commit SHAs, plan file, the artifact). `DONE: done` is format-invalid; `DONE: shipped continuation-enforcer.sh + rule + wiring, self-test 7/7, merged to master af11d3b` is valid.

`DONE:` is a positive completion claim, subject to the same anti-vaporware discipline as every other completion claim in the harness. A `DONE:` whose summary is contradicted by an unchecked plan task or an incomplete todo is a lie the hook catches.

**A `DONE:` while a verification gate is blocking is a lie by construction.** If `pre-stop-verifier.sh` or `product-acceptance-gate.sh` blocked this Stop — or was downgraded by the retry-guard earlier this session with no state change since — the work is incomplete by the harness's own measurement, and the honest marker is `PAUSING:` or `BLOCKED:` naming the gap. The marker is a *consequence* of verified completion, never a goal to emit so the turn looks finished. Mechanical backstop: `hooks/lib/stop-hook-retry-guard.sh` refuses to downgrade verification-class blocks while the final message claims `DONE:` (added 2026-06-09 after an autonomous loop emitted DONE past 38 consecutive pre-stop-verifier blocks).

### `PAUSING: <reason + the specific user input needed>`

The session is *intentionally* waiting on a non-delegable user decision: a Tier-3 product decision (`~/.claude/rules/planning.md`), a billing/irreversible-op click, an ambiguous business-logic call the agent must not guess. `PAUSING:` is NOT "natural breakpoint" or "good place to check in" — those are narrate-and-wait behavior and are caught by `narrate-and-wait-gate.sh`. A valid `PAUSING:` articulates BOTH:

1. Why the session cannot proceed autonomously (the specific decision that is the user's to make), AND
2. Exactly what input from the user would unblock it (a concrete question, not "let me know how you'd like to proceed").

`PAUSING: waiting for your input` is format-invalid (no articulated decision). `PAUSING: the schema migration drops the legacy column irreversibly — need your explicit go/no-go before I apply it to production` is valid.

**The Exact-Ask Rule (Misha directive 2026-06-14): "No more waiting. If you're waiting on me for something, finish your turn by telling me exactly what you need from me."** Any turn that ends in a waiting state — a `PAUSING:` marker, or a final message that surfaces a decision/question/blocker the user must resolve — MUST end with an explicit, fenced Decision-Context block (`action_item_for_user` / `decision` / `question` per `~/.claude/rules/decision-context.md`) that states, concretely: (a) **exactly what you need from the user** (the specific answer/action/value, not "let me know how you'd like to proceed"), (b) **why it's theirs and not yours** to decide, and (c) **what unblocks** — what you will do the moment they answer. A waiting turn with only a vague gesture at "your input" is a violation: the user must be able to act on your ask without a follow-up clarifying question. This is the positive obligation behind the babysitting complaint — the cost of pausing is precision about the ask. **Enforcement:** mechanically backed by `decision-context-gate.sh` (Stop hook — a decision-soliciting final message without a proper fence BLOCKS session end) composed with this rule's PAUSING-substance requirement; the agent self-applies the fence-first discipline at message-author time. The complement also holds: if there is buildable autonomous work that needs *nothing* from the user, you do NOT get to PAUSE for "steer" — drive it (per the keep-going directive below); PAUSING is only legitimate when a genuine non-delegable ask exists, and then it must be exact.

### `BLOCKED: <specific blocker + what is needed to unblock>`

The session genuinely cannot proceed without something outside its control: missing credentials, an external service down, a hard dependency on a prerequisite that does not exist yet, a destructive operation the harness forbids unilaterally. A valid `BLOCKED:` names the *specific* blocker and *what would unblock it* with enough detail that a future session can pick it up cold. `BLOCKED: stuck` is format-invalid; `BLOCKED: npm test fails because POSTGRES_URL is unset in this environment — need the test DB connection string or a sandbox with it provisioned` is valid.

`BLOCKED:` is not a softer `PAUSING:`. PAUSING is "the user must decide something"; BLOCKED is "the environment is missing something." When in doubt between the two, the distinction is: would the obstacle disappear if the user answered a question (PAUSING) or if a resource appeared (BLOCKED)?

## Why exactly one, on the last line

The marker is parsed mechanically. It must be:

- **Exactly one.** Two markers (`DONE:` and `BLOCKED:` in the same final message) is an unresolved contradiction — the hook blocks. Pick the one true terminal state.
- **On the last non-empty line.** Buried mid-message it is invisible to the operator skimming the end of the turn, which is the exact failure this rule exists to fix. The operator and the hook both read the *end* of the turn; the marker lives where they look.
- **Format-valid.** `<KEYWORD>: <substantive text>`. Keyword-only or empty-summary markers defeat the purpose (they declare a state without the information that makes the state actionable).

The marker does not replace the body of the response — write the normal summary, the normal next-steps, the normal everything. The marker is the final, machine-readable, one-line classification appended after all of that.

## Interaction with the keep-going directive

This rule and `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized" are complementary, not contradictory:

- The keep-going directive says: do NOT stop between work units when autonomous execution was authorized. If there is more declared work, the correct marker is not `DONE:` and not `PAUSING:` — there is no marker, because the turn should not be ending. Keep working.
- This rule says: WHEN the turn does end, classify why. If keep-going is active and all declared work is genuinely complete, `DONE:` with a concrete summary is correct. If keep-going is active and you are tempted to `PAUSING:` for a "checkpoint," that is the narrate-and-wait failure — there is no valid marker for "I'd like to pause for no blocking reason," so the hook (and `narrate-and-wait-gate.sh`) will block.

The marker is the positive declaration `narrate-and-wait-gate.sh` was missing: that gate catches permission-seeking *trail-off*; this gate requires an explicit *terminal-state assertion*. A session cannot satisfy this gate by trailing off — it must commit to DONE, PAUSING, or BLOCKED, each of which is independently checkable.

## What the hook checks (`continuation-enforcer.sh`)

A Stop hook, last gate in the Stop chain (after `goal-coverage-on-stop.sh`, before the non-gate `session-wrap.sh refresh`). On every session-end attempt:

1. Extract the final assistant message from the transcript JSONL. No transcript / no `jq` → no-op exit 0 (consistent with sibling Stop hooks; never block on a best-effort text scan).
2. Read the last non-empty line. Scan for exactly one `DONE:` / `PAUSING:` / `BLOCKED:` marker (leading markdown emphasis tolerated).
3. **No marker** → BLOCK: "append `DONE:` / `PAUSING:` / `BLOCKED:` per `~/.claude/rules/session-end-protocol.md` and re-end."
4. **Two or more distinct markers** → BLOCK: unresolved terminal-state contradiction; pick one.
5. **Format-invalid** (keyword present but summary empty / below the substance floor) → BLOCK naming the offending marker.
6. **`DONE:` but the last `TodoWrite` has incomplete items** → BLOCK with the incomplete list: "Marked DONE but TodoWrite has incomplete items: [...]. Complete them or change the marker to PAUSING/BLOCKED with an explanation."
7. **`PAUSING:` without an articulated specific reason + needed input** (below the substance floor) → BLOCK: "PAUSING requires a specific reason AND what user input is needed."
8. Valid marker, all cross-checks pass → exit 0 (allow).

Loop safety: the hook uses `lib/stop-hook-retry-guard.sh`. If a session cannot satisfy the gate after 3 identical-failure retries with no new commits, the block downgrades to a warn and the gap is logged to `.claude/state/unresolved-stop-hooks.log` — the same loop-break every blocking Stop hook uses.

Escape hatch: `CONTINUATION_ENFORCER_DISABLE=1` for harness-development sessions that edit the marker vocabulary itself (so the hook does not self-trigger on its own test fixtures or rule text).

## Worked examples

- **Plan fully shipped, all todos done.** Final line: `DONE: continuation-enforcer.sh + session-end-protocol.md shipped, self-test 7/7 green, wired into Stop chain, merged to master <sha>`. → allow.
- **Plan shipped but a todo still `in_progress`.** Final line: `DONE: ...`. Hook finds the incomplete todo → BLOCK. Correct response: finish the todo (then `DONE:`), or honestly downgrade to `BLOCKED:`/`PAUSING:` explaining why the todo cannot be finished now.
- **Tier-3 decision surfaced mid-build.** Final line: `PAUSING: the auth-middleware rewrite changes the session-token storage format — need your go/no-go on migrating existing sessions vs. forcing re-login before I proceed`. → allow.
- **Missing credential.** Final line: `BLOCKED: e2e suite needs E2E_PLATFORM_ADMIN_EMAIL in .env.local which is unset here — provide it or a sandbox with it set and I can finish Task 4`. → allow.
- **Trail-off (the anti-pattern).** Final line: `Let me know if you'd like me to continue with phase 2.` No marker → BLOCK (and `narrate-and-wait-gate.sh` independently blocks). Correct response: there is more declared work — keep going, do not end the turn.

## Cross-references

- `~/.claude/rules/testing.md` "Keep Going When Keep-Going Is Authorized" — the complementary rule; no marker exists for a no-reason pause.
- `~/.claude/hooks/narrate-and-wait-gate.sh` — catches permission-seeking trail-off; this gate requires the positive terminal-state assertion that gate was missing.
- `~/.claude/rules/gate-respect.md` — when this gate blocks, diagnose (read its stderr) before any bypass; the remediation is almost always "append the honest marker," not `--no-verify`.
- `~/.claude/rules/friction-reflexion.md` + `~/.claude/CLAUDE.md` Autonomy ("Drive to completion ... If you must stop, tag the final response with `WHY I STOPPED:`") — the `WHY I STOPPED:` convention is subsumed by `PAUSING:`/`BLOCKED:`, which are the structured, machine-checked forms.
- `~/.claude/hooks/lib/stop-hook-retry-guard.sh` — the loop-break library this hook sources.
- `docs/plans/session-end-protocol-enforcer.md` — the plan that introduced this rule + hook.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Three markers, when each is honest, exactly-one-on-last-line discipline | `adapters/claude-code/rules/session-end-protocol.md` |
| Hook (Mechanism, pending Wave D) | Marker present + exactly-one + format-valid + DONE/TodoWrite consistency + PAUSING substance; blocks session-end otherwise. Self-test passes; **not yet wired into the live Stop chain** — pending Wave D session-honesty-gate install | `adapters/claude-code/hooks/continuation-enforcer.sh` |
| Retry-guard (Mechanism) | Downgrades the block to a warn after 3 identical-failure retries; logs the unresolved gap | `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh` |
| User authority | The operator reads the marker on the last line and redirects when the marker is dishonest | (Pattern) |

The rule is documentation; the hook exists and self-tests green but is not yet the live mechanical floor (pending Wave D). Until wiring lands, marker discipline relies on agent self-application and the operator's interrupt authority when a turn ends without a clear terminal-intent statement.

## Scope

Applies in every project whose Claude Code installation has `continuation-enforcer.sh` wired into the Stop chain in `settings.json` — **not yet the case in the live template; wiring is pending Wave D session-honesty-gate.** The rule file is loaded contextually by the harness; no per-project opt-in. Once wired, the gate is intended to be universal — firing on every session, not only when a keep-going directive is present — because the operator needs the terminal-intent signal on *every* turn, and the retry-guard prevents any lockout when a session genuinely cannot satisfy it. Until wiring lands, this rule is documentation only.
