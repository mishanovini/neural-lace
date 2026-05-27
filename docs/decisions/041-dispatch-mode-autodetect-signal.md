# ADR 041 — Dispatch-mode auto-detection signal

**Date:** 2026-05-25
**Status:** Proposed (design-only; implementation gated on Misha's greenlight — Pattern 5 of the plan-lifecycle redesign initiative)
**Stakeholders:** Misha (decision authority); every Claude Code session that must decide whether to render `AskUserQuestion`/MC-widget vs plain-text prose (per `~/.claude/CLAUDE.md` Autonomy section detection priority).

## Context

`~/.claude/CLAUDE.md` (Autonomy section) and four harness rules (`discovery-protocol.md`,
`planning.md` "Plan-Time Decisions With Interface Impact", `interactive-process-fidelity.md`,
`acceptance-scenarios.md`) all branch on whether the session is "running under Dispatch."
Under Dispatch (remote/phone-relayed orchestration) the MC-widget does not relay answers
back, so the session must use plain-text prose; standalone it may use the widget.

Today that decision reads `~/.claude/local/dispatch-mode.json`, which **requires a manual
flip**. The file on this machine currently holds `"running_under_dispatch": true`,
manually set, still carrying the example `_comment`. A session that forgets the flip (or a
fresh machine where the file is absent) defaults to "standalone" and can hang a
Dispatch-relayed session by rendering an MC-widget that never returns an answer.

The original design (referenced in the brief and in prior session notes) proposed a
SessionStart hook keying on `CLAUDE_CODE_ENTRYPOINT=claude-desktop` **plus**
`CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1`.

**Empirical refutation (PROVEN, this session, Claude Code 2.1.146):**
`CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` is **absent** from the environment
(`env | grep PROVIDER_MANAGED` → nothing). The second half of the proposed signal does
not exist on this build. The detector must be designed against env vars that actually
exist. Present and usable: `CLAUDE_CODE_ENTRYPOINT=claude-desktop`,
`AI_AGENT=claude-code_2-1-146_agent`, `CLAUDE_AGENT_SDK_VERSION`,
`CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH=1`, `CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH=1`,
`CLAUDECODE=1`.

## Decision

Add a SessionStart hook `~/.claude/hooks/dispatch-mode-detect.sh` that runs **first** in
the SessionStart chain (before `discovery-surfacer.sh`, `spawned-task-result-surfacer.sh`,
and any surfacing that should respect the resolved mode), and atomically publishes
`~/.claude/local/dispatch-mode.json` via temp-then-rename. Resolution is a strict
priority ladder; the first rule that matches wins:

1. **Explicit env override.** `CLAUDE_CODE_DISPATCH=1` → `running_under_dispatch: true`;
   `CLAUDE_CODE_DISPATCH=0` → `false`. (Honors the documented top-priority signal.)
2. **Manual lock honored.** If the existing file carries `"manual": true`, the hook does
   **not** clobber the user's deliberate choice — it leaves the file untouched and exits.
   (The `/grant-local-edit`-style respect for an explicit human decision; auto-detect is a
   convenience, not an override of intent.)
3. **Host + agent corroboration (the heuristic).** `CLAUDE_CODE_ENTRYPOINT=claude-desktop`
   AND at least one agent-SDK marker (`AI_AGENT` matches `*_agent`, OR
   `CLAUDE_AGENT_SDK_VERSION` set, OR `CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH=1`) →
   `running_under_dispatch: true`. Rationale: a desktop-hosted *SDK/agent-driven* session
   is the population that contains every Dispatch-orchestrated session; a human typing
   directly in the desktop chat is the false-positive set (see Consequences).
4. **Otherwise** → `running_under_dispatch: false`.

The published file gains a `"detected_by"` field (`"env-override" | "manual-lock" |
"host-agent-heuristic" | "default-false"`) and a `"detected_at"` ISO timestamp so the
provenance of each session's mode is auditable. The hook NEVER blocks (writer-class, like
`conversation-tree-emit.sh`); any failure logs to `~/.claude/logs/dispatch-mode-detect.log`
and exits 0, leaving any prior file in place.

Local-edit note: `~/.claude/local/**` writes are normally gated by `local-edit-gate.sh`.
This hook is the **sanctioned auto-writer** of exactly one field-set in exactly one file;
the build phase must add `dispatch-mode.json` to the gate's allowlist for the
`dispatch-mode-detect.sh` writer path (or the hook writes via the same temp-then-rename
the gate already tolerates for harness-managed files). Resolving that interaction cleanly
is a build-phase task, flagged here.

## Alternatives considered

- **A — Keep the two-part `ENTRYPOINT + PROVIDER_MANAGED_BY_HOST` signal as specified.**
  Rejected: `PROVIDER_MANAGED_BY_HOST` does not exist on Claude Code 2.1.146 (PROVEN).
  Building it would produce a detector that never fires rule 3, silently defaulting every
  session to `false` — worse than today's manual flip.
- **B — Manual flip only (status quo).** Rejected: it is the reported pain; a fresh
  machine or a forgotten flip hangs Dispatch-relayed sessions on MC-widgets.
- **C — Tighten the heuristic to distinguish "Dispatch-orchestrated" from "human-at-desktop"
  using only env.** Rejected for v1: we have no PROVEN env var that separates the two on
  this build (the refutation criterion below is exactly the experiment that would unlock C).
  Conservative over-flagging (rule 3) is the safe interim — its only cost is plain-text
  prose where a widget would have worked.
- **D — Infer from the presence of `mcp__ccd_session_mgmt__*` tools in the toolset.**
  Rejected: a hook cannot introspect the session's tool surface from SessionStart stdin;
  tool availability is not exposed to hooks.

## Consequences

- **Enables:** zero-touch correct mode on fresh machines and forgotten-flip sessions; the
  Dispatch-relay-hangs-on-MC-widget failure is closed for the common case.
- **Costs / accepted false-positive:** rule 3 conservatively flags **all** desktop-hosted
  agent-SDK sessions as Dispatch-mode, including a human-at-desktop interactive session.
  The *only* effect of a false-positive is that such a session uses plain-text prose
  instead of the MC-widget for option-surfacing — the documented **safe fallback** (plain
  text never breaks; MC under Dispatch does break). Tradeoff accepted: a minor UX
  downgrade on some standalone sessions vs a hang on mis-detected Dispatch sessions.
- **Refutation criterion (the experiment that would let us tighten rule 3, per
  `~/.claude/rules/claims.md`):** capture `env` from (i) a *known* plain human-at-desktop
  interactive session and (ii) a *known* Dispatch-spawned child session, and diff. If a
  stable env var distinguishes them, rule 3 is replaced by that var and the false-positive
  set collapses. Until that diff exists, the heuristic stays conservative. This session
  could only observe one session's env, so the heuristic's discriminating power is
  HYPOTHESIZED, not PROVEN.
- **Interaction with `local-edit-gate.sh`** must be resolved at build time (allowlist the
  detector's writer path) — flagged, not yet designed in detail.

## Cross-references

- Discovery: `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` (RC3, PROVEN absence of `PROVIDER_MANAGED_BY_HOST`).
- Plan: `docs/plans/dispatch-coordination-redesign.md` (Task group A).
- `~/.claude/CLAUDE.md` Autonomy section — the detection-priority ladder this hook populates.
- Sibling ADRs this session: 042 (ntfy out-of-band), 039 (conv-tree reconciliation).
- `~/.claude/rules/local-edit-authorization.md` — the gate whose allowlist the detector touches.
