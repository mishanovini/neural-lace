# 053 — Customer-Facing Review Gate (mechanical UX + customer-advocate enforcement)

> Renumbered from 046 at the 2026-06-10 landing: the 2026-06-02 build was salvaged unmerged to `feat/customer-facing-review-gate-2026-06-01` while master independently took 046 (workstreams-lifecycle-emit); 051 is reserved by cross-machine-coordination and 052 is taken, so 053 is the next free number (ADR-number-collision class, `principles.md` Decision Principle 7).

- **Date:** 2026-06-02 (landed on master 2026-06-10)
- **Status:** Active
- **Stakeholders:** Misha (operator/owner); the Dispatch orchestrator; the UX-family agents (`ux-designer`, `UX End-User Tester`, `Domain Expert Tester`, `Audience Content Reviewer`); the customer-advocate agent (`end-user-advocate`).
- **Mechanism:** `adapters/claude-code/hooks/customer-facing-review-gate.sh` (Stop hook) + `adapters/claude-code/rules/customer-facing-review.md` (stub rule) + Stop-chain wiring in `settings.json.template`.

## Context — the failure this gate exists to stop (read it; do not rationalize it away)

On **2026-06-02** the Dispatch orchestrator spawned FOUR customer-facing sessions in a single day —

1. **Nav IA** (contractor dashboard navigation information architecture),
2. **Smart Import v2** (contractor-facing import flow),
3. **doc-reviewer** (downstream-product support-doc review),
4. **support-backfill** (backfilling `docs/support/*.mdx` contractor docs),

— with **ZERO** UX-agent involvement and **ZERO** customer-advocate-agent (`end-user-advocate`) involvement across all four.

The harness was *supposed* to require that review. The requirement existed — as prose:

- `rules/planning.md` → "Mandatory: ux-designer review for new UI surfaces" and "Mandatory: end-user-advocate review for every plan."
- `rules/testing.md` → "UX Validation After Substantial Builds (Mandatory)."

But it existed **only as a social convention**. No hook fired. A task-loaded orchestrator, optimizing for getting work dispatched, silently routed around the convention four consecutive times and nothing in the harness noticed. Misha did.

**The cost of this failure class is exactly the cost the harness was built to prevent:** UI a contractor cannot use, support docs written in the wrong voice for the audience, dead-end navigation, and features that compile + pass tests while confusing the target persona. "Tests pass" / "typecheck clean" / "the code exists" never catch this — only an adversarial user-perspective pass (UX agent) plus an adversarial product-observer pass (customer-advocate) catch it. Those two passes are precisely what was skipped.

This is the same structural lesson the rest of Gen 4–6 encodes: **a requirement that lives only in prose is a requirement that gets skipped under load.** The fix is to move it from SOCIAL to MECHANICAL.

## Decision

Ship a **Stop-hook gate** (`customer-facing-review-gate.sh`) that:

1. Scans the agent-uneditable `$TRANSCRIPT_PATH` for spawn surfaces (`mcp__ccd_session__spawn_task`, `mcp__ccd_session_mgmt__start_code_task`, and `Agent` dispatches to builder subagent_types).
2. Classifies each spawn's prompt/title/tldr/description/cwd blob as **customer-facing** (STRONG contractor signals override a platform/backend EXCLUSION; WEAK signals fire only absent exclusion).
3. If ≥1 customer-facing spawn was made, requires the session transcript to ALSO contain an `Agent` dispatch to a **UX-family** subagent_type AND one to the **CX-family** (`end-user-advocate`).
4. If either is missing, **blocks session wrap** (block-mode default, exit 2 + `{"decision":"block"}` routed through the 3-retry `lib/stop-hook-retry-guard.sh`), naming WHICH family is missing.

Escape hatches (both audit-logged, reason mandatory): a `[skip-ux-review: <reason>]` footer in the final message, or `UX_REVIEW_GATE_DISABLE=1`. Mode resolves `UX_REVIEW_GATE_MODE` env > `~/.claude/local/ux-review-gate-mode` > `block`.

The gate is wired in `settings.json.template`'s Stop chain **after** `pr-health-snapshot-gate.sh`, **before** the non-gate `session-wrap.sh refresh`. It mirrors `pr-health-snapshot-gate.sh` structurally (block-mode default, retry-guard, mode resolution, `--self-test`) — deliberate consistency with the existing completion-criteria gate family.

## Alternatives considered

- **(A) Stop-hook gate on the orchestrator [CHOSEN].** Same architectural shape as `decision-context-gate.sh` / `pr-health-snapshot-gate.sh` / `principles-compliance-gate.sh` — scans the transcript at Stop, blocks wrap on a missing completion criterion. *Why chosen:* consistency with the existing completion-criteria gate pattern (the harness already enforces a dozen completion criteria this way); reads the agent-uneditable transcript so it can't be gamed; non-invasive (does not intercept the spawn itself, so it never blocks legitimate spawns mid-flight).
- **(B) Pre-spawn hook on `start_code_task` that auto-prepends "invoke UX agent, then customer-advocate, then incorporate findings."** *Why rejected:* more invasive (rewrites the orchestrator's spawn payload), couples the gate to the spawn-tool surface, and enforces *process ordering* rather than *outcome presence* — a session could be auto-prepended the steps and still skip them. Option A enforces the outcome (both reviews present in the session) which is what actually matters. Kept as a documented fallback if A proves insufficient.
- **(C) Leave it as a prose convention and add a memory rule.** *Why rejected:* this IS the status quo that failed four times on 2026-06-02. Memory/prose is precisely the substrate that drifts under load. Rejected by the originating incident itself.

## Refutation criterion (per `claims.md`)

**Claim (HYPOTHESIZED):** a Stop-hook gate that requires both review families on customer-facing spawns will prevent the 2026-06-02 recurrence. **Refuted by:** a future session that spawns customer-facing work, never invokes UX/CX agents, and still wraps cleanly with the gate live in `~/.claude/settings.json` (and no `[skip-ux-review:]` / disable used). If that happens, the classifier missed the customer-facing signal OR the satisfier detection misread the agent dispatches — both are fixable in the hook. The `--self-test` (8 named scenarios) plus the live downstream-product acceptance test (a product-repo cwd + "support page"/"navigation" spawn blocks) are the pre-ship evidence the mechanism fires.

## Consequences

**Enables:** the orchestrator CAN'T silently skip UX/customer-advocate review on customer-facing work, even when task-loaded and forgetful. The requirement is now mechanical at the session-wrap boundary.

**Costs / accepted limitations:**
- **Spawn-keyed, not edit-keyed.** The gate detects *spawned* customer-facing work (the 2026-06-02 failure mode). A session doing customer-facing work *directly* (no spawn) is not caught — the prose mandates + operator interrupt authority cover that path. Extending to direct edits is a candidate follow-up.
- **Classifier false-positive/negative risk.** Keyword + path classification is heuristic. STRONG/WEAK/EXCLUSION tiers + the `[skip-ux-review:]` escape bound the blast radius; the audit log surfaces skip frequency for calibration.
- **Block-mode default fires on every Stop universally** (intrinsic to the Stop-hook surface) — defensive no-ops (no transcript, no customer-facing spawn, no `jq`) keep it inert in the common case, and the retry-guard prevents any lockout.
- **Live-wiring is the operator's `install.sh` step** (HARNESS-GAP-14 template-vs-live split) — the script is mirrored to `~/.claude/hooks/` and wired in the template; live `~/.claude/settings.json` is updated on install.

## Coordination with completion-criteria-gate (the 9th criterion)

The companion `completion-criteria-gate` (in-flight 2026-06-01, sibling worktree `completion-criteria-gate-2026-06-01`) carries an 8-criterion session-completion checklist; UX review was not one of them. This ADR adds a **9th criterion**: *"UX agent + customer-advocate agent review attached"* for customer-facing work, `N/A` for backend-only.

Because `completion-criteria-gate.sh` lives **uncommitted in a sibling worktree**, editing it on this branch would race/conflict and violate worktree isolation. Per the explicit coordination instruction, the 9th-criterion spec is handed off via a JSON written to `.claude/state/spawned-task-results/` for the completion-criteria session to reconcile into its own gate. This gate (`customer-facing-review-gate.sh`) is the *mechanical* enforcement of that criterion regardless of whether the checklist gate also lists it — the two are complementary (one blocks at wrap on the specific UX/CX-missing condition; the other tracks it as one item in a broader completion checklist).

**Landing note (2026-06-10):** the completion-criteria gate shipped (ADR 049) with its original EIGHT criteria — the handed-off 9th criterion was never reconciled into it. This gate stands as the sole mechanical enforcement of UX/CX review at session wrap; folding the criterion into the completion-criteria checklist is an open follow-up tracked in `docs/backlog.md`.
