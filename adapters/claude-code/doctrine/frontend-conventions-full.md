# Frontend Conventions — full detail

> Companion to the compact: `doctrine/frontend-conventions.md`. Carries the full statement of conventions whose compact form is capped at 3000 bytes; the compact is the operative summary.

## Prerequisite unblocking — never a dead end

When a user attempts an action whose prerequisite is unmet, the app never merely blocks. Every blocked state carries its own path to resolution:

- **Self-contained prerequisites** (a missing record, a missing field, a one-step setup): open an **inline modal that satisfies the prerequisite right there**, then let the user continue the original action.
- **Page-level configuration** (settings surfaces, multi-step setup): present a **direct deep link to the page where the prerequisite can be satisfied** — a real navigable link, not a named-but-unlinked destination.
- In both cases the surface states what is missing and why it is needed: **"You need X to do Y."**

**Anti-patterns (all are defects):**

- A disabled control with no explanation of why it is disabled.
- A toast-only rejection — the message disappears and the user is left where they started with no path forward.
- Error text that names a destination ("configure this in Settings") without linking it.
- A silent no-op — the control accepts the interaction and nothing observable happens.

**Enforcement:**

- Review checklist: **no new precondition ships without its unblocking affordance.**
- The feature's acceptance scenarios MUST cover the blocked-state UX — what a user with the unmet prerequisite sees, and where it leads them.

(Operator directive 2026-07-06; first codified downstream as that project's ADR 084.)
