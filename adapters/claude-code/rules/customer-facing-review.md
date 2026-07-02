# Customer-Facing Review Gate (Stub — enforcement is in the hook)

**Rule:** a session that SPAWNS customer-facing build work must also involve BOTH the **UX agent** AND the **customer-advocate agent** (`end-user-advocate`) before it is allowed to wrap. HARD REQUIREMENT (block-mode default) — the gate blocks session wrap when a customer-facing spawn was made but one or both review agents were never invoked in the session.

**Classification:** Mechanism. This file is intentionally short. The classifier signals, the agent-family lists, the skip-flag grammar, the mode resolution, and the self-test all live in `hooks/customer-facing-review-gate.sh`. If a constraint described here isn't backed by the hook, it's theater.

## Why this rule exists

On **2026-06-02** the Dispatch orchestrator spawned FOUR customer-facing sessions — Nav IA, Smart Import v2, doc-reviewer, support-backfill — with ZERO UX-agent and ZERO customer-advocate-agent involvement. The harness was *supposed* to require that review on customer-facing work (the discipline lived in `planning.md` "Mandatory: ux-designer review" + "Mandatory: end-user-advocate review" and in `testing.md` "UX Validation After Substantial Builds"), but the requirement was **social, not mechanical**: a task-loaded orchestrator silently routed around it four times in one day. Nothing fired.

The cost of routing around UX/CX review on customer-facing work is exactly what the harness exists to prevent: UI a contractor can't use, support docs in the wrong voice, dead-end navigation, features that compile but confuse the target persona. "Tests pass" never catches this; only an adversarial user-perspective pass does. This gate moves the requirement from SOCIAL to MECHANICAL — the orchestrator CAN'T silently skip review even when it forgets. See ADR 053 (`docs/decisions/053-customer-facing-review-gate.md` — authored as ADR 046 in the 2026-06-02 salvage; renumbered at the 2026-06-10 landing because master's 046 was taken by workstreams-lifecycle-emit).

## What "customer-facing" means (the classifier)

The gate scans the agent-uneditable `$TRANSCRIPT_PATH` for spawn surfaces (`mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` / `Agent` dispatches to builder subagent_types) and classifies each spawn's prompt/title/tldr/description/cwd blob:

- **STRONG** (contractor-facing; override the platform/backend exclusion): `contractor`, `user-facing`, `support page`, `navigation`, `nav ia`, `src/app/(dashboard)`, `(dashboard)`, `/dashboard`, `src/components/`, `docs/support`.
- **WEAK** (customer-facing only if no exclusion signal is present): `\bpage\b`, `\bUI\b`, `/admin`.
- **EXCLUSION** (platform/backend; suppress WEAK, never STRONG): `(platform)`, `src/app/(platform)`, `platform-admin`, `src/lib/`, `src/trigger/`, `migrations/`, `tests-only`.

A spawn is customer-facing iff STRONG matches, OR (WEAK matches AND no EXCLUSION). Pure backend/infra/platform spawns never fire the gate.

## Agent families (the satisfiers)

- **UX family** (any one satisfies the UX requirement): `ux-designer` | `UX End-User Tester` | `Domain Expert Tester` | `Audience Content Reviewer`.
- **CX family** (the customer-advocate requirement): `end-user-advocate`.

Both families must appear as `Agent` dispatches (subagent_type match, case-insensitive) somewhere in the session transcript.

## Enforcement map (hook-backed)

| Constraint | Hook that enforces it | File |
|---|---|---|
| Customer-facing spawn + missing UX or CX agent → session wrap blocked | `customer-facing-review-gate.sh` Stop hook (block-mode default) | `~/.claude/hooks/customer-facing-review-gate.sh` |
| Block message names WHICH family is missing (UX and/or CX) | same hook | same |
| Backend-only / platform-only spawns pass without UX/CX | same hook (classifier) | same |
| Both review families present → allow silently | same hook | same |
| 3-retry downgrade-to-warn loop-break | shared `lib/stop-hook-retry-guard.sh` | `~/.claude/hooks/lib/stop-hook-retry-guard.sh` |

## Escape hatches (both audit-logged; reason mandatory)

- `[skip-ux-review: <reason>]` footer in any assistant message — the reason is mandatory (an empty reason is rejected) and is appended to the audit log.
- `UX_REVIEW_GATE_DISABLE=1` env var — for harness-dev sessions editing the gate itself (which would otherwise self-trigger).
- Audit log: `${UX_REVIEW_AUDIT_LOG:-$HOME/.claude/state/ux-review-gate-overrides.log}`.

## Mode

Resolution order: `UX_REVIEW_GATE_MODE` env > `~/.claude/local/ux-review-gate-mode` file > `block`. Per the hard-requirement directive the default is `block` (like `pr-health-snapshot-gate.sh`, unlike the warn-default gates).

## Known limitation (honest)

The gate keys on **spawned** customer-facing work (the 2026-06-02 failure mode). A session that does customer-facing work *directly* (Edit/Write in its own context, no spawn) is not detected by this gate — the existing `planning.md` / `testing.md` review mandates (Pattern) cover that path, and the operator retains interrupt authority. Extending the gate to direct customer-facing edits is a candidate follow-up.

## Live-wiring note (HARNESS-GAP-14 class)

The canonical wiring is in `adapters/claude-code/settings.json.template` (Stop chain, after `pr-health-snapshot-gate.sh`, before the non-gate `session-wrap.sh refresh`). Live `~/.claude/settings.json` is per-machine and updated by the operator's `install.sh` run — the same template-vs-live split `pr-health-snapshot-gate.sh` and `doc-gate.sh` have. Until install runs, the gate's script is present in `~/.claude/hooks/` but is not yet invoked from the live Stop chain — wired in template; live wiring pending Wave B.6 install; slated for Wave D relocation per ADR 058.

## Coordination with completion-criteria-gate

The companion `completion-criteria-gate` shipped 2026-06-01 (ADR 049) with its original EIGHT criteria — the proposed 9th criterion (`UX agent + customer-advocate agent review attached`, N/A for backend-only) was handed off via `.claude/state/spawned-task-results/` during the 2026-06-02 parallel build (see ADR 053) but was NOT incorporated into the shipped gate. As of the 2026-06-10 landing, THIS gate is the sole mechanical enforcement of UX/CX review at session wrap; folding the criterion into the completion-criteria checklist remains an open follow-up (tracked in `docs/backlog.md`).

## Cross-references

- `~/.claude/hooks/customer-facing-review-gate.sh` — the gate; classifier + self-test (8 named scenarios + disable bonus) live in the hook header.
- `~/.claude/rules/pr-health-snapshot.md` — sibling block-mode Stop gate this one mirrors structurally.
- `~/.claude/rules/planning.md` "Mandatory: ux-designer review" + "Mandatory: end-user-advocate review" — the Pattern-level mandates this gate makes mechanical.
- `~/.claude/rules/testing.md` "UX Validation After Substantial Builds" — the substantial-UI-build review mandate.
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- `docs/decisions/053-customer-facing-review-gate.md` — the ADR (failure-mode cost made explicit; renumbered from 046 at landing).

## Scope

Applies in any session whose Claude Code installation has `customer-facing-review-gate.sh` wired in `settings.json`. The gate fires on every Stop; defensive no-ops (no transcript, no `jq`, no customer-facing spawn, disable env) keep it inert where it can't apply. Agent-family lists are easy to extend as the agent registry grows.
