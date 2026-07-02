# Customer-Facing Review Gate — compact
> Enforcement: customer-facing-review-gate.sh (Stop, block-mode default — RELOCATING per D.4). Full: none (compact only)
> Applies: a session that spawned customer-facing build work — Dispatch orchestrator sessions specifically.

- A session that SPAWNS customer-facing build work must also involve BOTH a UX-family agent AND the customer-advocate agent before it wraps, or session wrap BLOCKs.
- **UX family** (any one satisfies): `ux-designer` | `UX End-User Tester` | `Domain Expert Tester` | `Audience Content Reviewer`.
- **CX family** (the customer-advocate requirement): `end-user-advocate`.
- Customer-facing classification: STRONG signals (`contractor`, `user-facing`, `support page`, `navigation`, `src/app/(dashboard)`, `src/components/`, `docs/support`) override an exclusion; WEAK signals (`\bpage\b`, `\bUI\b`, `/admin`) fire only absent an exclusion; EXCLUSION signals (`(platform)`, `src/lib/`, `src/trigger/`, `migrations/`) suppress WEAK and are never overridden by WEAK.
- Escape hatch: a `[skip-ux-review: <reason>]` footer in the final message (reason mandatory, audit-logged) or `UX_REVIEW_GATE_DISABLE=1` for harness-dev sessions editing the gate.
- Known limitation: keys on SPAWNED work only — direct customer-facing edits in the session's own context aren't caught by this gate; the Pattern-level review mandates in doctrine/planning.md and doctrine/testing.md still apply there.
- **D.4 relocates this gate**: moves from a Stop-hook block to a spawn-time PreToolUse warn + ledger — catching the miss earlier (at spawn) rather than only at session wrap.
