# Application Code Paths — Change Domain Data Through the App, Not the Database Directly

**Classification:** Pattern (self-applied discipline). No hook can tell whether a data change went through the application's own code path or through a raw query / a script that shortcut it — the running system only sees the resulting rows. This rule binds the agent through self-application; the operator's interrupt authority is the backstop.

**Originating incident (2026-07-03):** a one-time backfill needed to move a set of domain entities into a terminal lifecycle state. Instead of running the change through the application's real entry point (the endpoint/route that performs that transition for live traffic), the agent wrote a script that imported a single internal state-transition **helper** and called it directly. The state moved — the helper did fire the state-machine engine, and its immediate seeded side effect ran — but the **route-level** work the real flow performs was silently skipped: the actor-attributed audit-log entry and the cross-field/cross-table consistency writes. The entities ended up in a shape the application itself would never produce, with no human-facing "who changed this and why" trail. It *looked* right on the surface (a display predicate masked the split) while raw-column readers, downstream jobs, and audits disagreed. The operator's directive: **build a habit of following application code for changes like this instead of just changing things in the database.**

## The rule in one sentence

**When you need to change domain/business data in a running system — a one-off correction, a backfill, a bulk state change, a "fix the bad rows" cleanup — do it THROUGH the application's own code path (its endpoint, service command, or task that runs the full flow), NOT through raw SQL and NOT through a script that imports one internal function; the application path enforces the invariants, audit trails, side effects, compliance rules, and cross-field consistency that a direct write silently skips.**

## Why direct writes are the trap

Domain data is owned by application logic. The endpoint that performs an action (opt a contact out, cancel an order, close a ticket, advance a workflow) is almost never a single write — it is a *flow*: validate → mutate the primary field → write the consistency fields → record provenance / audit → fire side effects (notifications, cancellations, downstream sync) → return. Every one of those steps is an invariant the system depends on.

A raw `UPDATE`, or a script that calls one internal helper, gets **only the piece you touched**. Everything the surrounding flow does — and everything a *future* maintainer adds to that flow — is skipped, invisibly. The failure is worst precisely because it usually "works": the primary field changes, the happy-path display looks correct, and the gaps (missing audit row, un-fired side effect, split consistency fields, skipped compliance write) surface later, somewhere else, as "bad data" no one can explain.

Calling an internal helper directly is **not** a safe middle ground. The helper is one node inside the flow; the route is the flow. Invoking the node bypasses the wrapper — which is exactly where the invariants live.

## The discipline

Before any change to domain data:

1. **Ask: is there an application entry point that already does this?** An API route, a server action, a command/service function invoked by the real UI, a scheduled task. If yes → **use it** (call the endpoint, enqueue the task, drive the real UI action). Do not reimplement its inner steps.
2. **If no such path exists and the change is worth doing → build the path**, then run the change through it. A proper admin/system endpoint or task that executes the full flow is reusable, testable, and correct — and it makes the *next* bulk change safe too. Building it is the work, not a detour from it.
3. **A backfill/migration script is acceptable ONLY when it invokes the real application flow** — it hits the endpoint, or runs the same command the app runs — never when it shortcuts to a raw write or a bare internal-helper call.
4. **After the change, verify the entity matches what the application flow would produce** — the audit row, the side effects, every consistency field — not just the one field you targeted. (Composes with the harness "trust nothing — verify the artifact" discipline.)

## The legitimate direct-database cases (the exceptions)

Direct database access is correct — and required — for:

- **Schema migrations (DDL):** creating/altering tables, columns, constraints, indexes, enums, RLS policies. That is the migration system's job and belongs in the migration files, not behind an application endpoint. (See the migrations rule for how.)
- **Read-only queries / diagnostics:** inspecting state, counting, auditing, investigating. Reading never bypasses an invariant.
- **Genuinely app-external data:** analytics scratch tables, import staging the app does not own, throwaway experiment data.
- **True break-glass with no application path and an irreversibly-urgent need** — and even then, replicate every step the real flow performs, document it, and file building the proper path as follow-up.

The boundary: **if the data represents domain state the application owns and mutates through its own logic, the change goes through that logic.** Schema is the store's shape (direct); domain rows are the app's state (through the app).

## Cross-references

- `~/.claude/rules/security.md` — no destructive/irreversible operations without approval; direct production data writes are adjacent risk.
- `~/.claude/rules/database-migrations.md` — the legitimate direct-DDL path (schema, not domain state).
- `~/.claude/rules/diagnosis.md` — "Trust nothing — verify the artifact"; verify the *whole* resulting shape, not the one field.
- `~/.claude/rules/claims.md` — a change that "looks right" on the display is not proven correct; check the invariants the flow maintains.
- `~/.claude/rules/planning.md` "FUNCTIONALITY OVER COMPONENTS" — the same spirit: the endpoint's *behavior* (the full flow) is the unit that matters, not the single write it wraps.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Change domain data through application code paths; build the path if missing; direct-DB only for schema/read-only/app-external | `adapters/claude-code/rules/application-code-paths.md` |
| User authority | The operator catches a direct-write shortcut the discipline missed (the originating incident) | (Pattern) |

The rule is Pattern-class. There is deliberately no hook: the running system cannot distinguish "changed via the app" from "changed via a script," so mechanical detection is not available. The discipline relies on the agent self-applying it and the operator's interrupt authority.

## Scope

Applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/application-code-paths.md`. Loaded contextually by the harness; no opt-in required. Binds every agent in every session mode — a backfill, a data correction, or a bulk state change is a domain-data mutation in all of them, and the temptation to "just update the rows / call the helper directly this once" is exactly where invariants get skipped.
