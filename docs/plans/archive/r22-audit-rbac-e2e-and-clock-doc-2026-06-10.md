# Plan: R22 follow-ups — audit-log RBAC e2e spec + land clock-module design doc
Status: COMPLETED
Execution Mode: direct (spawned builder session; two small tasks, no sub-dispatch)
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: tests + a design doc only — no new user-facing behavior ships; the e2e spec itself IS the runtime acceptance artifact for the already-shipped R22 RBAC feature.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
> prd-ref note: same precedent as R22/R23 — Circuit has no docs/prd.md; this is
> follow-up verification + doc-landing work for the already-Misha-approved R22
> feature (docs/plans/archive/r22-ia-settings-reorg.md, PR #464).

## Goal
Close two R22-adjacent follow-ups: (1) the R22 completion report (§4 "Manual
Steps Required" + §5 "Recommended") shipped the `audit.view` RBAC feature with
unit/guard tests only and explicitly deferred the authed end-to-end QA
("the session lacked Owner/member credentials"). Write the real Playwright e2e
spec proving audit-log access is RBAC-gated against the running app: an
elevated user (platform admin fixture) reaches `/settings/audit-log` and gets
200 from `GET /api/audit-log`; a non-elevated member is redirected to
`/dashboard?notice=audit_log_restricted` and gets 403 (`permission:
"audit.view"`) from both `GET /api/audit-log` and `POST /api/audit-log/[id]`.
(2) Land `docs/designs/clock-module-design.md` (675-line ODS Clock design doc,
salvaged in commit 6f2d877d on branch `docs/save-patterns-c35-2026-05-29`,
never merged to master) into the docs tree. Landing the DOC only — the Clock
module is explicitly design-only ("DO NOT implement").

## User-facing Outcome
No new product behavior. The maintainer gains (a) a replayable e2e proof that
the R22 audit-log RBAC boundary holds in the real app (member cannot see other
users' change history; owner/admin/platform can see their org's), closing the
"manual authed QA" gap the R22 completion report deferred; (b) the Clock
design doc discoverable on master next to its parent
`docs/designs/organic-demo-system.md` instead of stranded on a salvage branch.

## Scope
- IN:
  - `tests/playwright/journeys/audit-log-rbac.spec.ts` — NEW e2e spec. Seeds a
    synthetic member user inline in the Demo HVAC org
    (`deaaaaa0-0000-4000-8000-000000000001`) via the Supabase service role,
    asserts the member route-redirect + API 403s, asserts the platform-admin
    fixture user (E2E_PLATFORM_ADMIN_EMAIL) sees the page + API 200, deletes
    the synthetic user in cleanup. Synthetic data only; demo org only; no
    test.skip.
  - `docs/designs/clock-module-design.md` — landed byte-identical from salvage
    commit 6f2d877d (scanned: no credentials, no customer data, no real
    phone numbers).
- OUT:
  - Implementing the Clock module (the doc itself forbids it).
  - Any change to R22 product code (`requireAuditView`, routes, sidebar) — the
    spec exercises shipped behavior; if it exposes a gap, the gap is reported
    + persisted, not patched here.
  - Editor-role coverage (no editor fixture exists; member is the canonical
    non-elevated role asserted by R22's own plan/report).
  - One Season (real customer) data — never touched; spec is hard-scoped to
    the demo org + synthetic users.

## Tasks
- [x] 1. Write `tests/playwright/journeys/audit-log-rbac.spec.ts` (member seeded inline → redirect + 403s; platform admin → page + 200) and run it against the local dev server; capture output. — Verification: full
  **Prove it works:**
  1. Run `npx playwright test --config tests/playwright/playwright.config.ts audit-log-rbac` with `.env.local` present.
  2. Observe the member-path tests pass: member lands on `/dashboard?notice=audit_log_restricted` when navigating `/settings/audit-log`; `GET /api/audit-log` returns 403 with `permission: "audit.view"`; `POST /api/audit-log/<uuid>` returns 403.
  3. Observe the elevated-path tests pass: platform-admin fixture reaches `/settings/audit-log` (audit page heading renders) and `GET /api/audit-log` returns 200 with an `entries` array.
  **Wire checks:**
  - `tests/playwright/journeys/audit-log-rbac.spec.ts` → `/settings/audit-log` → `src/app/(dashboard)/settings/audit-log/page.tsx` → `requireAuditView`
  - `tests/playwright/journeys/audit-log-rbac.spec.ts` → `/api/audit-log` → `src/app/api/audit-log/route.ts` → `requireAuditView`
  - `src/lib/auth/roles.ts` → `hasPermission` → `audit.view`
  **Integration points:**
  - Supabase auth admin API (seed/delete the synthetic member): exercised inside the spec's beforeAll/afterAll; verified by the spec passing and by the cleanup leaving `select * from users where org_id = demo and email like 'e2e-r22-%'` empty after the run.
- [x] 2. Land `docs/designs/clock-module-design.md` from salvage commit 6f2d877d byte-identical (`git diff 6f2d877d -- docs/designs/clock-module-design.md` empty after commit). — Verification: mechanical

## Files to Modify/Create
- `docs/plans/r22-audit-rbac-e2e-and-clock-doc-2026-06-10.md` — this plan.
- `tests/playwright/journeys/audit-log-rbac.spec.ts` — NEW e2e spec (Task 1).
- `docs/designs/clock-module-design.md` — NEW, landed from 6f2d877d (Task 2).
- `docs/plans/r22-audit-rbac-e2e-and-clock-doc-2026-06-10-evidence.md` — evidence log.
- `docs/backlog.md` — only if the spec exposes an RBAC gap that must be persisted.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The local dev server (`npm run dev`, auto-started by the Playwright config)
  connects to the same Supabase project as `.env.local`; the demo org
  `deaaaaa0-0000-4000-8000-000000000001` exists there with owner+admin rows
  only (verified by read-only query 2026-06-10) — so a member must be seeded.
- `E2E_PLATFORM_ADMIN_EMAIL` / `E2E_PLATFORM_ADMIN_PASSWORD` in `.env.local`
  are valid platform-admin fixture credentials (same assumption as
  `invitation-only-first-login.spec.ts`, which ran green 2026-06-10).
- Seeding ONE synthetic member user (`e2e-r22-…@circuit-test.local`) into the
  demo org and deleting it in cleanup is within the "demo org + synthetic data
  only" boundary; the rls-smoke integration test already follows this exact
  auth.admin.createUser/deleteUser pattern.
- `requireAuditView` checks platform first, then `hasPermission(role,
  'audit.view', overrides)` — member has no default grant and the demo org has
  no override row granting it (spec asserts the 403 rather than assuming).

## Edge Cases
- Seeded member leaks if the run crashes before cleanup: afterAll uses
  best-effort try/catch deletes (users row + auth user), and the synthetic
  email carries the `e2e-r22-` prefix so a leak is identifiable and manually
  removable; spec also deletes any prior leaked `e2e-r22-` users in the demo
  org at setup (idempotent re-runs).
- A per-org permission override granting member `audit.view` in the demo org
  would legitimately flip the 403 to 200: spec asserts no such override row
  exists before running the member path (loud FAIL with explanation, never a
  silent wrong-reason pass).
- Dev server port 3000 already in use: Playwright config reuses an existing
  server outside CI (`reuseExistingServer`), so a stale server on master code
  could false-fail the spec — run notes capture which server served the run.
- Missing env credentials: spec hard-fails with a named assertion (no
  test.skip), same discipline as the invitation-only spec.

## Acceptance Scenarios
- n/a — acceptance-exempt (tests + design doc only; the e2e spec is itself the
  runtime acceptance artifact for the shipped R22 feature).

## Out-of-scope scenarios
- Editor-role audit-log denial (no editor fixture; member covers the
  non-elevated class — R22's own completion report asserts "member/editor 403"
  from the same guard path).

## Testing Strategy
- Task 1: the spec IS the test — run locally against the dev server; capture
  the Playwright pass output as evidence. Typecheck must stay clean.
- Task 2: mechanical — byte-identical diff against the salvage commit
  (`git diff 6f2d877d -- docs/designs/clock-module-design.md` exits 0).
- CI: `vercel-build` runs typecheck + test:unit (the new spec is Playwright and
  does not run in CI; its local run output is the evidence).

## Walking Skeleton
n/a — two-task follow-up; no new architecture. The thinnest slice (member 403
on `GET /api/audit-log`) is Task 1's first assertion.

## Decisions Log
- Seed-inline vs. add a permanent member fixture credential: seed-inline
  (Tier 1, reversible) — matches `tests/integration/rls-smoke.test.ts`
  precedent and testing.md "seed the data inline"; a permanent member fixture
  in .env.local would be a second standing credential to rotate for no gain.
- Spec lives in `tests/playwright/journeys/` (the config's testDir), NOT next
  to the two stray root-level specs (`business-hours-times.spec.ts`,
  `admin-bug-tracker.spec.ts`) which are outside testDir and not collected by
  `npm run test:e2e` (observed, not changed here).

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): swept, behavior changes are test+doc additions only; both cited in Tasks and Files. 0 gaps.
- S2 (Existing-Code-Claim Verification): swept — `requireAuditView` at src/lib/auth/roles.ts:165-195, redirect at settings/audit-log/page.tsx:21-23, 403 body `permission: 'audit.view'` verified against worktree source 2026-06-10.
- S3 (Cross-Section Consistency): swept, 0 contradictions (member=denied, elevated=allowed consistent across Goal/Scope/Tasks/Edge Cases).
- S4 (Numeric-Parameter Sweep): swept for params [demo org UUID, port 3000]; consistent.
- S5 (Scope-vs-Analysis Check): swept, Add verbs target only the two new files + plan/evidence; no Scope-OUT contradiction.

## Definition of Done
- [x] Both tasks checked off with evidence
- [x] e2e spec run output captured (ran/did-not-run stated plainly)
- [x] Typecheck clean
- [x] Squash-merged to master; deploy status verified
- [x] Completion report appended; plan closed + archived

## Completion Report

### 1. Implementation Summary
Both tasks shipped via PR #485, squash-merged to master `d01316e1`
(2026-06-10); master Vercel deploy SUCCESS for `d01316e1`.
- Task 1: `tests/playwright/journeys/audit-log-rbac.spec.ts` — 5 tests, all
  PASS locally (1.1m run; output in the evidence file). Member path seeded
  inline in the demo org and cleaned up (post-run leak query empty).
- Task 2: `docs/designs/clock-module-design.md` landed byte-identical from
  salvage commit `6f2d877d` (diff empty).
Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
- Seed-inline member (rls-smoke precedent) over a standing member fixture
  credential — Tier 1, recorded in Decisions Log.
- DEVIATION (process): the task-verifier agent was not invocable from this
  spawned builder session (no sub-agent dispatch tool); checkboxes were
  flipped manually under the evidence-first protocol (fresh evidence blocks
  with Task ID + replayable Runtime verification lines, written immediately
  before each flip). Flagged here for audit honesty.
- The PR's first Vercel preview failed on a PRE-EXISTING transient:
  `tests/unit/process-pending-scheduled-actions.test.ts` live-AI test timed
  out at 60s — the same live-API-in-build-path CI-fragility class R22's
  completion report already flagged. Retrigger (empty commit) went green.
  Not caused by this PR (docs + playwright spec only; spec does not run in
  vercel-build).

### 3. Known Issues & Gotchas
- The e2e spec does NOT run in CI (vercel-build = typecheck + test:unit);
  it is a local/dev-run artifact like the rest of tests/playwright/journeys/.
- The spec asserts no member-role `audit.view` override exists in the demo
  org before running; if someone later grants member audit.view in the demo
  org via the permissions matrix, the spec fails loudly with the explanation
  (by design — it tests the R22 default).
- Two stray specs (`business-hours-times.spec.ts`, `admin-bug-tracker.spec.ts`)
  sit OUTSIDE the playwright testDir (`tests/playwright/journeys/`) and are
  not collected by `npm run test:e2e` — observed, not changed here.

### 4. Manual Steps Required
None. No env vars, no migrations, no deploy config changes.

### 5. Testing Performed & Recommended
- Playwright run: 5/5 PASS against local dev server (fresh, worktree code).
- typecheck clean; PR CI green on retry (Permission Drift, AI Simulator,
  Vercel preview); master deploy SUCCESS for d01316e1.
- Recommended: address the live-AI unit-test flake class in the build path
  (pre-existing; flagged in R22 report and observed again here).

### 6. Cost Estimates
None ongoing. Each spec run creates+deletes one synthetic auth user.
