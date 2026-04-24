# Plan: Acceptance Loop Smoke Test (walking skeleton)

Status: DEFERRED
Deferral reason: 2026-04-24 — walking-skeleton plumbing validated end-to-end via curl substitute (no browser MCP connected during A.5 dispatch); the live browser-automation path (Chrome MCP / Playwright MCP) is deferred to Phase G self-test when a properly-equipped session exercises the production end-user-advocate against a non-bootstrap plan. The artifact at `.claude/state/acceptance/acceptance-loop-smoke-test/sess-skeleton-2026-04-24T09-10-30Z.json` documents the run; the hook recognized this plan as acceptance-exempt and emitted the expected log line.
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: This is the walking-skeleton self-test plan for the end-user-advocate acceptance loop itself; it bootstraps the loop and therefore cannot be acceptance-gated by a mechanism that does not yet exist in production form. Phase G's full self-test will exercise the production path against a non-bootstrap plan.

## Goal

Validate end-to-end that the end-user advocate plan-time → runtime → artifact → Stop-hook control flow can flow ONE simple acceptance scenario through every architectural layer of the Generation 5 acceptance loop. The user-observable outcome: a maintainer running this plan can witness (a) the agent reading this file in plan-time mode and confirming the scenario, (b) the agent driving a real browser to navigate the URL and observe the expected text, (c) a JSON PASS artifact landing in `.claude/state/acceptance/acceptance-loop-smoke-test/`, and (d) `pre-stop-verifier.sh` reading that artifact and allowing the session to terminate cleanly.

The walking-skeleton target is the neural-lace repo root served by a local static HTTP server on port 3000 (Python `http.server` or Node `http-server` — whichever is available on the machine). Zero project-app dependency, zero auth, zero database. The smoke test exercises the loop's plumbing, not any product feature.

## Scope

- IN: a single scenario (`smoke-1`) that navigates a browser to `http://localhost:3000/README.md` and verifies the page contains the literal string `Neural Lace`.
- IN: a hand-crafted PASS artifact under `.claude/state/acceptance/acceptance-loop-smoke-test/` demonstrating the JSON schema (Section 3 of the parent plan).
- IN: validation that the new pre-stop-verifier hook code path detects the artifact and allows session end on a stub `acceptance-exempt: true` plan.
- OUT: scenario coverage of any actual project feature (intentionally trivial so the test tells us about the LOOP, not the PRODUCT).
- OUT: production agent prompts, full hook logic, artifact retention automation, gap-analyzer chaining — those land in Phases C/D/E of the parent plan.

## Tasks

- [ ] 1. Server-up verification — confirm a static HTTP server is serving the neural-lace root on port 3000 and `/README.md` returns the text "Neural Lace" (HTTP 200, body contains the string).

## Files to Modify/Create

- `docs/plans/acceptance-loop-smoke-test.md` — this stub plan (created by Phase A.1).
- `docs/plans/acceptance-loop-smoke-test-evidence.md` — task-verifier evidence (deferred until Phase G self-test exercises the production path; this skeleton plan stays acceptance-exempt and so doesn't need the evidence file for hook satisfaction, but we can still produce it for completeness during the walking-skeleton run).
- `.claude/state/acceptance/acceptance-loop-smoke-test/<session-id>-<timestamp>.json` — runtime artifact (gitignored; demonstrated by Phase A.3).

## Assumptions

- A static HTTP server (Python `http.server` or Node `http-server` via `npx`) is installable / runnable on the maintainer's machine. The neural-lace repo root contains a `README.md` whose first heading is `# Neural Lace`.
- Browser MCP (`mcp__Claude_in_Chrome__*`) is available in the dispatched sub-agent's tool surface, OR the session can fall back to `mcp__Claude_Preview__*` (Playwright MCP) for the same navigation/text-check capability.
- The `acceptance-exempt: true` plan-header field will be honored by the production `product-acceptance-gate.sh` (Phase D) — for the walking skeleton, the exemption justifies why this skeleton plan does not itself need an artifact under `pre-stop-verifier.sh`'s gate.

## Acceptance Scenarios

### smoke-1 — Maintainer can observe expected text on a served page

**Slug:** `smoke-1`

**User flow:**
1. Maintainer ensures a static HTTP server is running and serving the neural-lace repo root on `http://localhost:3000`.
2. Maintainer (or the runtime advocate agent) opens a browser and navigates to `http://localhost:3000/README.md`.
3. The browser renders the README content.

**Success criteria (prose):** the rendered page contains the literal text `Neural Lace` (case-sensitive). HTTP status is 200. Console has no errors that would prevent rendering. Network tab shows the README response was 200 OK.

**Artifacts to capture:** screenshot of the rendered page, network log showing the GET to `/README.md`, console log (expected to be empty / informational).

## Out-of-scope scenarios

- Any test of clickable navigation, form submission, JS-heavy SPA behavior, or auth flows. The walking skeleton intentionally stays at "open URL → see text" so failures isolate to the loop, not the product.
- Cross-browser testing. One browser context is enough to validate the loop.

## Edge Cases

- **Server not running.** Runtime advocate should `curl -s http://localhost:3000/README.md` first; if it fails, the artifact records `verdict: FAIL` with `failure_reason: "static server not reachable on port 3000"`. Maintainer starts the server and re-runs.
- **Browser MCP unavailable.** Runtime advocate falls back to Playwright MCP. If both unavailable, scenario is marked `verdict: SKIP` with `failure_reason: "no browser automation available; architectural validation only"`. Walking-skeleton run documents the limitation honestly; Phase G self-test will exercise the live path on a properly equipped session.
- **README first line changes.** If a future commit renames the project, this scenario's expected-text assertion breaks. Acceptable: the scenario must be updated alongside that rename, exactly the discipline the loop is meant to enforce.

## Testing Strategy

- This plan IS itself the test of the acceptance loop's walking skeleton. Evidence in `docs/plans/acceptance-loop-smoke-test-evidence.md` records the runtime advocate's PASS / FAIL outcome on `smoke-1`.
- Hook unit-test: `pre-stop-verifier.sh` should treat `acceptance-exempt: true` plans as no-artifact-required (verified by inspection of the new code path in Phase A.4).
- Artifact schema test: the hand-crafted JSON in `.claude/state/acceptance/acceptance-loop-smoke-test/` validates parseably (verified by `jq .` returning success in the evidence file).

## Walking Skeleton

This plan IS the walking skeleton for the parent plan. Its scope is intentionally one scenario through one HTTP GET so any failure isolates to the loop's plumbing, not to a product feature.

## Decisions Log

*Populated during implementation if any decisions arise.*

## Definition of Done

- [ ] `smoke-1` scenario authored in this plan file (`## Acceptance Scenarios` section) — done by file creation.
- [ ] Runtime advocate executes `smoke-1` (or architectural-only validation if browser MCP unavailable) and writes artifact under `.claude/state/acceptance/acceptance-loop-smoke-test/`.
- [ ] `pre-stop-verifier.sh` updated to recognize `acceptance-exempt: true` and an artifact-presence path for non-exempt plans.
- [ ] Evidence file `docs/plans/acceptance-loop-smoke-test-evidence.md` documents the run outcome.
