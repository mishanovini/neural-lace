# TDD-Gate Per-Project Exemption: `routesTestedVia: e2e`

**Mechanism:** `adapters/claude-code/hooks/pre-commit-tdd-gate.sh` (live mirror `~/.claude/hooks/pre-commit-tdd-gate.sh`)
**Added:** 2026-05-27

## The problem this solves

The TDD gate's Layer 1 requires every API route file (`src/app/api/.../route.ts`)
to have a co-located integration test under `tests/api/`. Layer 3 bans mocks in
the `tests/api/` tier — those tests must hit real infrastructure.

For a route protected by an auth layer that cannot run in the integration
harness (the motivating case: **NextAuth**), this is an architecturally
unsatisfiable combination at pre-commit time:

- Exercising the route from `tests/api/` requires standing in for the auth
  session → mocking auth.
- Layer 3 bans mocks in `tests/api/`.
- So the route cannot satisfy the `tests/api/` requirement at all.

Such routes are correctly tested via **end-to-end** tests (Playwright / journey
tests) that drive a real browser through the real auth flow. E2E tests do not
`import` the route file — they navigate to its URL — so they never satisfy the
Layer 1/2 co-location/reference check regardless of how thorough they are.

This is not project-specific: any downstream using NextAuth (or any
non-mockable auth) + E2E-for-routes hits the same wall.

## The exemption

A project opts in by declaring, in its `package.json`:

```json
{
  "harness": {
    "routesTestedVia": "e2e"
  }
}
```

When `harness.routesTestedVia` is `"e2e"`, the TDD gate exempts API route files
(`src/app/api/.../route.ts`) from the Layer 1 `tests/api/` co-location
requirement (and, transitively, the Layer 2 referring-test requirement — route
files are scored exclusively by the Layer 1 path).

`package.json` is already the gate's per-project config surface: `pre-commit-gate.sh`
reads npm scripts via `jq` the same way. No new config file is introduced.

### Forward-extensible values

| Value | Behavior |
|---|---|
| (field absent) | **Default.** Route files require `tests/api/` co-location — current behavior, unchanged. |
| `"co-located-unit"` | Same as default (explicit declaration of the current behavior). |
| `"e2e"` | Route files exempt from the `tests/api/` requirement. |
| `"contract"` *(future)* | Reserved; treated as default until implemented. |

Only the exact value `"e2e"` triggers the exemption. Any other value (or a
missing field) leaves the gate's behavior completely unchanged.

## What is NOT relaxed

The exemption is narrowly scoped to **the `tests/api/` co-location requirement
for route files**. Everything else still applies in full, even under
`routesTestedVia: "e2e"`:

- **Layer 1 for non-route runtime files** — new pages still need a Playwright
  spec; new Trigger tasks still need a trigger/journey test; new migrations
  still need a verification block or migration test.
- **Layer 2 for `src/lib`, `src/components`, etc.** — modified non-route runtime
  files still require a referring test.
- **Layer 3 — the mock ban** in `tests/api/`, `tests/integration/`,
  `tests/journey/`, `tests/playwright/`. (Self-test scenario D confirms the mock
  ban still fires under `routesTestedVia: e2e`.)
- **Layer 4 — the trivial-assertion ban.**
- **Layer 5 — the silent-skip ban.**

The exemption removes exactly one architecturally-impossible requirement; it
does not weaken the global anti-vaporware signal.

## Auditability

Every exemption that fires is logged in two places, so the relaxation is never
silent:

1. **stderr** (visible in the commit output):
   `[tdd-gate] EXEMPTION routes-tested-via-e2e: '<file>' skips the tests/api co-location requirement (...)`
2. **`.claude/state/tdd-gate-exemptions.log`** (append-only, survives the session):
   `<ISO-8601-UTC>  exemption=routes-tested-via-e2e  value=e2e  file=<path>  source=package.json:harness.routesTestedVia`

If a project's E2E coverage later proves insufficient, the log answers exactly
which route modifications were waved through the `tests/api/` requirement and when.

## plan-reviewer

`plan-reviewer.sh` has **no** corresponding `tests/api/` co-location check
(the `route.ts` references in its body are self-test fixtures, not a gate), so
no plan-reviewer change is needed for this exemption.

## Self-test

```bash
bash ~/.claude/hooks/pre-commit-tdd-gate.sh --self-test
```

Five scenarios:
- **A** — `routesTestedVia: e2e` + new `route.ts`, no `tests/api/` → **exempt** (PASS), and the exemption is logged.
- **B** — no `harness` field + new `route.ts`, no `tests/api/` → **still blocked** (default unchanged).
- **C** — `routesTestedVia: co-located-unit` + new `route.ts` → **not exempt** (only `"e2e"` exempts).
- **D** — `routesTestedVia: e2e` + a `tests/api/` file using a mock → **still blocked** by Layer 3 (other layers intact).
