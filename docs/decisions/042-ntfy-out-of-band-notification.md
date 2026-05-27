# ADR 042 — ntfy.sh out-of-band notification contract

**Date:** 2026-05-25
**Status:** Proposed (design-only; implementation gated on Misha's greenlight — Pattern 5 of the plan-lifecycle redesign initiative)
**Stakeholders:** Misha (decision authority; sole recipient of the push); future build-session orchestrators.

## Context

RC1 and RC5 (see `docs/discoveries/2026-05-25-dispatch-coordination-debug.md`) together
produce the worst-case relay failure: Dispatch is asleep, a child Code session goes idle
needing the operator's input, and there is **no path to tell the human**. The harness has
no inter-session wake (RC1 is Anthropic-blocked — see ADR's cross-reference to the filed
issue), so even a correct in-band channel cannot reach a sleeping parent. The realistic,
mechanical, curative move for the *human-awareness* leg — independent of whether the
parent ever wakes — is an out-of-band push to the operator's phone.

[ntfy.sh](https://ntfy.sh) is a pub/sub push service: an HTTP `POST` to
`https://ntfy.sh/<topic>` delivers a push notification to every device subscribed to
`<topic>`. No account, no SDK, no credential required for the public service (the topic
name is the only "secret" — an unguessable topic is the access control). A self-hosted
ntfy instance is a drop-in URL swap.

This is a **third-party integration the harness has not used before**, which is one of the
triggers that makes the parent plan `Mode: design` (per `~/.claude/rules/design-mode-planning.md`).

## Decision

Add an opt-in, config-driven notifier `~/.claude/hooks/ntfy-notify.sh`, wired into the
`Notification` and `Stop` hook chains. It POSTs a small JSON/text payload to a
user-configured ntfy topic when a child session needs the operator. Default behavior with
no config is a **silent no-op** (absent config → exit 0, nothing sent).

**Config — `~/.claude/local/ntfy.config.json` (gitignored; per-machine; never committed).**
Per `~/.claude/rules/harness-hygiene.md` and `secret-hygiene.md`, the topic (the only
access-controlling value) lives in the local layer, never in the repo. Shape:

```json
{
  "version": 1,
  "enabled": true,
  "base_url": "https://ntfy.sh",
  "topic": "<unguessable-per-user-topic>",
  "events": { "notification": true, "stop": false, "subagent_stop": false },
  "min_priority": "default",
  "include_session_id": true
}
```

An `ntfy.config.example.json` ships in `adapters/claude-code/examples/` with a placeholder
topic (`<your-unguessable-ntfy-topic>`) per the functional-placeholder rule. The live file
is created by the operator (or seeded by the install script as an example, never with a
real topic).

**Which hook events POST (the contract):**

| Hook event | Fires when | POST by default? | Payload intent |
|---|---|---|---|
| `Notification` | Claude needs user input / permission (the canonical "I'm blocked on the human" signal) | **yes** (`events.notification: true`) | "Session `<id>` needs your input: `<notification text>`" + tag `needs-input` |
| `Stop` | A session ends its turn (could be idle-waiting or done) | **no** (opt-in via `events.stop`) | "Session `<id>` stopped: `<last marker: DONE/PAUSING/BLOCKED>`" — only useful with the session-end markers from `session-end-protocol.md` |
| `SubagentStop` | A sub-agent finished | **no** (opt-in) | low-value for the relay problem; off by default to avoid noise |

The `Notification` event is the load-bearing one: it is exactly "the child needs the
human," routed to the phone regardless of whether Dispatch is awake.

**Payload shape (ntfy HTTP headers + body):**
- `POST <base_url>/<topic>`
- Header `Title: Neural Lace — <event>`
- Header `Tags: <needs-input|stopped|...>`
- Header `Priority: <min_priority>`
- Body: a one-line human summary; `<session_id>` appended when `include_session_id: true`.
- The payload **never includes** prompt content, file contents, credentials, or
  repo-identifying paths (harness-hygiene). Only the event class, a short summary, and the
  opaque session id.

**Failure isolation (writer-class, never blocks):** the hook runs the POST with a short
timeout (e.g. `curl --max-time 5`), in the background where possible, swallows all output,
logs success/failure to `~/.claude/logs/ntfy-notify.log`, and **always exits 0**. A down
ntfy service, no network, or a malformed config never blocks a tool call or a Stop — same
discipline as `conversation-tree-emit.sh`.

## Alternatives considered

- **A — Email / SMS via a transactional provider (SendGrid, Twilio).** Rejected for v1:
  requires an API credential in the local layer (more secret-hygiene surface), an account,
  and per-message cost. ntfy's topic-as-capability needs no credential and no account.
- **B — Push via the Claude mobile app / Anthropic-native notification.** Rejected:
  no documented hook→app push API exists; this is part of what RC1's upstream issue asks
  for. ntfy is the available-today path.
- **C — Always-on (no config, hardcoded topic).** Rejected: a hardcoded topic is a shared
  secret in the repo (harness-hygiene violation) and spams every installer. Opt-in with a
  per-user topic is the only hygienic shape.
- **D — POST full context (prompt, blocker detail) to the push.** Rejected: the payload
  transits a third-party service and lands on a lock screen; per harness-hygiene it must
  carry only event class + opaque id + short summary. Misha opens the session to see detail.

## Consequences

- **Enables (curative for the human-awareness leg):** when a child needs input and
  Dispatch is asleep, Misha's phone buzzes. The relay no longer hangs *silently* — the
  human is the wake mechanism. This does NOT close RC1 (no parent-wake) and does not claim
  to; it routes *around* it for the human. Named honestly: curative for "human is unaware,"
  not for "parent session is asleep."
- **Costs:** one more opt-in local config file; a 5s-bounded network call on
  `Notification` events; reliance on a third-party (or self-hosted) push service. Topic
  secrecy is the only access control — documented in the install notes.
- **Privacy:** payloads transit ntfy.sh (public instance) unless self-hosted. The
  no-content rule keeps the exposure to "a session needs input" + an opaque id. Operators
  wanting zero third-party exposure point `base_url` at a self-hosted ntfy.
- **Interaction with `local-edit-gate.sh`:** the operator creates `ntfy.config.json` via
  the normal `/grant-local-edit` flow; the hook only *reads* it, so no auto-writer
  allowlist is needed (unlike ADR-041).

## Cross-references

- Discovery: `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` (RC1, RC5).
- Plan: `docs/plans/dispatch-coordination-redesign.md` (Task group C).
- Upstream issue: `docs/proposals/anthropics-claude-code-parent-wake-issue.md` (the curative RC1 fix this ADR routes around).
- `~/.claude/rules/harness-hygiene.md`, `~/.claude/rules/secret-hygiene.md` — topic-in-local-layer, no-content-in-payload.
- `~/.claude/rules/session-end-protocol.md` — the DONE/PAUSING/BLOCKED markers the `Stop` payload would carry.
- Sibling ADRs this session: 041 (auto-detect), 039 (conv-tree reconciliation).
