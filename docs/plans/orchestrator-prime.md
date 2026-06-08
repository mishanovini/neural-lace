# Plan: orchestrator-prime — the always-on harness-native orchestrator
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
frozen: false
tier: 3
rung: 3
architecture: harness-infrastructure
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal always-on orchestrator runtime (a SKILL + scaffold + self-scheduling loop); the "user" is the maintainer running it and a hook/loop firing at an event boundary. No product UI to advocate for; self-tests + the report-only first-cycle output are the acceptance artifact.
owner: Misha
Backlog items absorbed: none

## Goal

Build **orchestrator-prime**: a self-driving, harness-native Claude Code session that keeps
Misha's in-flight work moving without him poking each session — by waking itself on a timer
(`/loop`/ScheduleWakeup), polling its inbox + conversation tree + sibling-session status,
spawning/tracking work, surfacing completions and blockers via a file-mediated outbox, and
emitting conversation-tree events for everything. It IS the harness (full agent/hook/rule
access), replacing the *orchestration* role of the sandbox-blind Dispatch session; Dispatch
becomes a thin file-mediated relay.

**User-facing Outcome.** Misha sends a message through Dispatch; orchestrator-prime picks it
up on its next self-wake, acts, and surfaces a response — without Misha manually advancing each
child session. Rate-limited/idle sessions are detected and surfaced (with a respawn offer);
completions are surfaced once; the conversation-tree GUI shows the live picture regardless of
the relay seam's health.

## Scope
- IN:
  - `adapters/claude-code/skills/orchestrator-prime.md` (+ `~/.claude/` mirror) — the brain. **DONE this session.**
  - `~/.claude/orchestrator-prime/{inbox,outbox}/` + `state.json` runtime scaffold. **DONE this session.**
  - `docs/decisions/068-orchestrator-prime-loop-architecture.md` — the ADR. **DONE this session.**
  - `~/.claude/rules/dispatch-relay-protocol.md` — instructs Dispatch sessions to write the inbox + read the outbox + surface via SendUserMessage. (BUILD — Task 3.)
  - `feedback-dispatch-relay-only.md` memory + MEMORY.md index row — future Dispatch sessions relay, don't orchestrate. (BUILD — Task 4.)
  - Inbox/outbox seam smoke test + harness-map-dependency check before launch. (BUILD — Task 5.)
  - systems-designer PASS on this plan (the Mode:design gate). (BUILD — Task 6.)
- OUT:
  - Any Dispatch-internal code change (closed-source). The relay is a *convention* future Dispatch sessions follow, not code we ship into Dispatch.
  - Message-based session revival (PROVEN impossible — no send primitive; we detect+surface+respawn-with-ack instead).
  - Overriding the per-repo customer-tier auto-merge policy (review-before-deploy repos are surfaced, not auto-merged).
  - Launching the always-on auto-merging loop onto live customer repos before Task 5 passes AND the harness map exists AND Misha acks (the irreversible-blast-radius guard).
  - Re-opening ADR-034 matcher scope or the ADR-031 passive-observer GUI contract.

## Tasks
- [x] 1. Author the orchestrator-prime SKILL (brain) written to the verified tool surface; mirror byte-identical. — Verification: mechanical
- [x] 2. Create runtime scaffold (`inbox/`, `outbox/`, `state.json`) + ADR-068. — Verification: mechanical
- [ ] 3. Write `~/.claude/rules/dispatch-relay-protocol.md` (Dispatch writes inbox / reads outbox / SendUserMessage; makes NO orchestration decisions) + mirror. — Verification: mechanical
- [ ] 4. Write `feedback-dispatch-relay-only.md` memory + MEMORY.md index row. — Verification: mechanical
- [ ] 5. Smoke-test the inbox/outbox seam (does a Dispatch session actually write the inbox / surface the outbox?) AND confirm the harness map exists, BEFORE launch. — Verification: full
  - **Prove it works:** 1. Drop a synthetic `inbox/test.json`; confirm a Dispatch session surfaces an `outbox/*.json` to Misha. 2. `ls ~/.claude/orchestrator-harness-map.md`. 3. Launch orchestrator-prime; confirm its report-only first cycle writes a correct "I'm online + inherited state" outbox.
  - **Wire checks:** `~/.claude/skills/orchestrator-prime.md` → reads `~/.claude/orchestrator-prime/inbox/` → writes `~/.claude/orchestrator-prime/outbox/`. (≥2 arrows.)
  - **Integration points:** `mcp__ccd_session_mgmt__list_sessions` available in the launch session; conversation-tree facade reachable.
- [ ] 6. systems-designer PASS on this Mode:design plan BEFORE the always-on loop is launched with full autonomy. — Verification: mechanical
- [ ] 7. Launch in FULL AUTONOMY from cycle 1 via the durable `orchestrator-prime-keepalive` scheduled task (DONE — created); report-only gating DROPPED per Misha 2026-06-02. — Verification: full
- [ ] 8. Dispatch-callback: per-cycle, when the outbox has new entries, `spawn_task` a chip surfacing them to Misha (the real verified surface; `mcp__dispatch__start_task` does not exist). — Verification: mechanical (DONE in SKILL)
- [ ] 9. Full harness awareness on startup (read all agents/hooks/rules/skills/memory/ADRs, build an in-memory index, re-index on change). — Verification: mechanical (DONE in SKILL)
- [ ] 10. Conv-tree ownership: rely on auto-emit (confirmed live) + orchestrator-prime forward emission of schema-valid in-scope events; 40-node manual backfill stays rejected (schema-invalid + ADR-034). — Verification: mechanical (DONE; disposition recorded)

## Files to Modify/Create
- `adapters/claude-code/skills/orchestrator-prime.md` — NEW (DONE). The brain. (+ `~/.claude/` mirror, untracked.)
- `~/.claude/orchestrator-prime/{inbox,outbox}/`, `state.json` — NEW runtime scaffold (DONE, untracked per-machine).
- `docs/decisions/050-orchestrator-prime-loop-architecture.md` — NEW (DONE). The ADR (brief called it "068"; correct sequential number is 047).
- `docs/plans/orchestrator-prime.md` — NEW. This plan file.
- `adapters/claude-code/rules/dispatch-relay-protocol.md` — NEW (DONE). (+ `~/.claude/` mirror, untracked.)
- `adapters/claude-code/rules/INDEX.md` — MODIFY (DONE). Rules-index row for the new relay rule (CI-enforced).
- `docs/DECISIONS.md` — MODIFY (DONE). Index row for ADR 050.
- `docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md` — MODIFY. Decision + implementation log filled (originally committed 67b0007).
- `~/.claude/projects/.../memory/{feedback-dispatch-relay-only.md,MEMORY.md}` — NEW/MODIFY (DONE, untracked per-machine memory).

## In-flight scope updates
- 2026-06-08: docs/backlog.md — orchestrator-prime loop logs open-work entries to the backlog
<!-- date + one-line reason -->
- 2026-06-02: Misha direction update — report-only gating DROPPED (full autonomy cycle 1); auto-merge policy READ FROM HARNESS applied to all repos with green-prod-deploy hard exclusion; Dispatch-callback added via `spawn_task` chip; full-harness-awareness startup; durable `orchestrator-prime-keepalive` scheduled task created (reboot resilience); manifest references status-snapshot; SKILL rewritten to v2.
- 2026-06-02: `docs/discoveries/2026-06-02-conv-tree-backfill-premise-mismatch.md` dispositioned (A: rely on auto-emit + orchestrator-prime forward emission; 40-node manual backfill rejected as schema-invalid + ADR-034). orchestrator-prime owns conv-tree forward emission, so this discovery is in this plan's scope.

## Assumptions
- `ScheduleWakeup`/`CronCreate --durable` reliably re-wakes the loop (PROVEN available this session; durability across session death verified at Task 5).
- A Dispatch session can write `~/.claude/orchestrator-prime/inbox/` and read the outbox (HYPOTHESIZED — Dispatch is closed-source; refutation: Task 5 smoke test shows no inbox write / no outbox surface → the relay seam is dead and we fall back to conv-tree GUI + ntfy for visibility).
- `mcp__ccd_session_mgmt__list_sessions` is available in the launch session (PROVEN available in this build session).
- The conversation-tree facade (`appendEvent`, ADR-032) is the only sanctioned writer (re-verify signature at build per claims.md).

## Edge Cases
- Inbox absent / Dispatch never writes it → "no new messages" (not an error); visibility falls back to the conv-tree GUI.
- Rate-limited child detected → CANNOT message it; surface + respawn-with-ack only (dedup guard prevents RC4 double-spawn).
- Green PR on a customer-facing repo (review-before-deploy) → surface, never auto-merge.
- Loop dies mid-cycle → `CronCreate --durable` re-wakes a fresh session that hydrates from state.json + tree.
- Harness map absent at launch → proceed, note the gap, do not block (degrade, don't fail).
- First cycle → report-only; no merges/respawns until Misha's inbox ack.

## Acceptance Scenarios
n/a — `acceptance-exempt: true`. Acceptance artifact = the SKILL's report-only first-cycle "I'm online + inherited state" outbox message + the Task 5 seam smoke test.

## Testing Strategy
Task 5's seam smoke test is the load-bearing functional check (real inbox-write → real outbox-surface, not mocked, per testing.md). The SKILL itself is verified by its report-only first cycle producing a correct classified-session inventory. systems-designer PASS (Task 6) gates the full-autonomy launch.

## Walking Skeleton
The thinnest end-to-end slice: a synthetic `inbox/test.json` → orchestrator-prime's first
(report-only) cycle reads it → classifies sessions via `list_sessions` → writes
`outbox/<id>.json` + emits a `branch-opened` tree event → the conv-tree GUI shows it AND (if the
seam is live) Dispatch surfaces the outbox to Misha. This exercises every layer (inbox → loop →
list_sessions → outbox + tree facade → operator surface) without any merge/respawn/revive risk.

## Verified / Refuted / Unverified mechanism table (load-bearing)
| Manifest behavior | Status | Basis |
|---|---|---|
| `/loop` self-wake (always-on) | VERIFIED | ScheduleWakeup/CronCreate available; 60–3600s cadence |
| Poll `list_sessions` for status | VERIFIED | tool available |
| Spawn new work | VERIFIED | spawn_task / start_code_task |
| Emit tree events | VERIFIED | ADR-032 facade |
| Auto-merge via `gh` (full-auto repos only) | VERIFIED | gh CLI; gated by automation-mode |
| **Revive rate-limited child by messaging it** | **REFUTED** | no send/resume primitive (RC1 + tool search) → DETECT+SURFACE+respawn-with-ack instead |
| **Read child's latest message verbatim** | **REFUTED** | no read_transcript → only `search_session_transcripts` snippets |
| Dispatch writes inbox / reads outbox | UNVERIFIED | Dispatch closed-source → Task 5 smoke test; fallback = conv-tree GUI + ntfy |

## Decisions Log
- **Decision: /loop + file-mediated inbox/outbox replaces the refuted transcript-read relay.** Tier 3. Surfaced to user: 2026-06-02 (Misha proposed /loop directly). Chosen: self-waking loop polling a file inbox — sidesteps the RC1 parent-wake gap. Alternative: transcript-read relay (refuted — passive read can't make a session process a message). Record: ADR-068.
- **Decision: revival = detect+surface+respawn-with-ack, not message-revive.** Tier 2. Surfaced: 2026-06-02. Chosen: the only path the verified tool surface supports. Alternative: send resume messages (refuted — no primitive). Record: ADR-068 + the discovery.
- **Decision: first cycle report-only; customer-repo merges surfaced not auto-merged.** Tier 3 (irreversible blast radius). Surfaced: 2026-06-02. Chosen: human eyes on first report + respect git.md customer-tier policy. Record: this plan.

## Systems Engineering Analysis
1. **Outcome:** within one self-wake cycle of a Dispatch inbox write, orchestrator-prime processes it and writes an outbox response; within one cycle of a child completing, it's surfaced once; the conv-tree GUI shows the live picture regardless of seam health. NOT promised: prompt cross-session message delivery (RC1, Anthropic-blocked).
2. **End-to-end trace:** Misha taps a message in Dispatch → Dispatch writes `inbox/t42.json` → orchestrator-prime's ScheduleWakeup fires (~600s) → reads `inbox/t42.json` → `list_sessions` shows `local_e688f010` flipped running→done → emits `concluded` + writes `outbox/t42.json` "escalation triage done; here's the summary" + marks surfaced → Dispatch reads outbox → SendUserMessage to Misha → ScheduleWakeup next cycle.
3. **Interface contracts:** inbox/outbox = JSON files keyed by turn_id (Dispatch↔orchestrator-prime); `list_sessions` = authoritative session ground truth; conv-tree facade `appendEvent` = idempotent on event_id; `gh pr list --json` = PR ground truth; automation-mode.json = per-repo merge authority.
4. **Environment:** Git-Bash/Windows, Claude Code 2.1.x, claude-desktop entrypoint. Loop persists via CronCreate --durable (survives session death). `~/.claude/orchestrator-prime/` is per-machine runtime state (gitignored).
5. **Auth map:** orchestrator-prime inherits the launch session's MCP + gh + Supabase grants (account auto-switch by cwd). No new secrets. Merges respect per-repo automation-mode + branch protection.
6. **Observability:** every action → a conv-tree event (the durable audit) + an outbox message (the operator surface) + state.json (the cycle log). A dead seam is observable as "outbox written but never surfaced."
7. **Failure modes:** seam dead → fall back to GUI+ntfy (Task 5 detects); loop dies → durable cron re-wakes; rate-limited child → detect+surface (can't message); double-spawn risk → dedup guard; customer-repo bad-merge → prevented by review-before-deploy surfacing.
8. **Idempotency:** state.json `surfaced` set prevents double-surface; tree events idempotent on event_id; inbox files `.done`-marked after processing; respawn gated by dedup guard.
9. **Load/capacity:** one `list_sessions` + one `gh pr list`×7 + file I/O per cycle (negligible). Cadence ≥300s to preserve prompt cache. Bottleneck: none at realistic session counts.
10. **Decision records & runbook:** ADR-068. Runbook — *seam silent:* check outbox written + whether a Dispatch session ran; fall back to GUI. *Loop stopped:* check durable cron + relaunch from state.json. *Duplicate spawn:* dedup-guard window too short → widen. *No merges:* repo in review-before-deploy → expected (surfaced not merged).

## Definition of Done
- [ ] dispatch-relay-protocol.md + memory entry written (Tasks 3–4).
- [ ] Seam smoke test passes OR seam declared dead + GUI/ntfy fallback documented (Task 5).
- [ ] systems-designer PASS (Task 6).
- [ ] Report-only first cycle produces a correct inherited-state outbox; Misha acks full autonomy (Task 7).
- [ ] harness-architecture.md + DECISIONS.md + SCRATCHPAD updated; completion report appended.
