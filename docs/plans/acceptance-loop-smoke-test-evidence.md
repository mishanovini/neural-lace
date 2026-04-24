# Evidence Log — Acceptance Loop Smoke Test (walking skeleton)

This evidence file accompanies `docs/plans/archive/acceptance-loop-smoke-test.md` (Status: DEFERRED — auto-archived by `plan-lifecycle.sh` on status transition). The skeleton plan's full task (live browser-MCP runtime advocate execution) is deferred to Phase G of the parent plan (`docs/plans/end-user-advocate-acceptance-loop.md`). The architectural-only walking-skeleton run during Phase A dispatch is documented below for traceability.

## Architectural-only validation run (2026-04-24)

**Context:** dispatched as part of Phase A (A.1-A.5) of the parent plan. Browser MCP (Chrome MCP / Playwright MCP / Claude_Preview) was not available in the dispatched session's tool surface — Chrome MCP returned "extension not connected" on two retries; Claude_Preview is launch.json-driven and not applicable to externally-started static servers. Per parent-plan Edge Case "Browser MCP unavailable" and the dispatch instructions, scenario `smoke-1` was exercised via `curl` as an honest substitute for the live-browser path.

### smoke-1 — outcome

**Verdict:** PASS (architectural-only — partial fidelity; live-browser path deferred to Phase G).

**Server:** `npx http-server -p 3000` against neural-lace repo root.

**Assertion exercised:**
- `curl -sS -D headers.tmp -o body.tmp http://localhost:3000/README.md` returned HTTP 200.
- `Content-Type: text/markdown; charset=UTF-8`. Content-Length: 14118 bytes.
- `grep -q 'Neural Lace' body.tmp` → match (literal string present in served body).

**Artifact:** `.claude/state/acceptance/acceptance-loop-smoke-test/sess-skeleton-2026-04-24T09-10-30Z.json` (gitignored). Contains:
- `verdict: PASS` for `smoke-1`
- `assertion_fidelity: partial — literal-text assertion exercised via HTTP body inspection; browser-rendered verification deferred to Phase G self-test (no browser MCP connected)`
- `runtime_environment.browser_mcp: NONE_CONNECTED, fallback: curl`

**Sibling artifact files** (gitignored): `smoke-1-network.log` (full curl output + headers + PASS line), `smoke-1-console.log` (n/a), `smoke-1-screenshot-omitted.txt` (placeholder noting browser unavailability).

### Hook recognition validation

`adapters/claude-code/hooks/pre-stop-verifier.sh` Check 0 ("acceptance-loop awareness") was empirically exercised:
- With `Status: ACTIVE` on the smoke-test plan: emitted `[acceptance-gate] plan acceptance-loop-smoke-test is acceptance-exempt; reason: This is the walking-skeleton self-test plan...` — exemption path verified.
- With `Status: DEFERRED` on the smoke-test plan: hook bypassed the plan entirely (per existing DEFERRED handling) and selected another ACTIVE plan; emitted `[acceptance-gate] plan <slug>: no acceptance directory at .claude/state/acceptance/<slug>` — non-exempt path verified.

Both code paths fire as designed at this skeleton stage. Production blocking behavior is Phase D (`product-acceptance-gate.sh`).

### Why this plan is DEFERRED, not COMPLETED

The smoke-test plan's full job is to demonstrate the LIVE browser-automation path (Chrome MCP driving a real browser, capturing real screenshots, asserting via DOM-rendered text). That path was not exercised in the Phase A dispatch because browser MCP was unavailable. Marking this plan COMPLETED would overstate what shipped. DEFERRED with a clear reason captures the truth: the architectural plumbing is validated, the live-fidelity exercise is queued for Phase G.
