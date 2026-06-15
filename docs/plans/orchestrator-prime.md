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
  - `docs/decisions/050-orchestrator-prime-loop-architecture.md` — the ADR. **DONE this session.**
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
- [x] 2. Create runtime scaffold (`inbox/`, `outbox/`, `state.json`) + ADR 050. — Verification: mechanical
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
- `docs/decisions/050-orchestrator-prime-loop-architecture.md` — NEW (DONE). The ADR (originating brief called it "068"; the correct sequential number landed as 050, matching the file + ADR header + DECISIONS.md index row).
- `docs/plans/orchestrator-prime.md` — NEW. This plan file.
- `adapters/claude-code/rules/dispatch-relay-protocol.md` — NEW (DONE). (+ `~/.claude/` mirror, untracked.)
- `adapters/claude-code/rules/INDEX.md` — MODIFY (DONE). Rules-index row for the new relay rule (CI-enforced).
- `docs/DECISIONS.md` — MODIFY (DONE). Index row for ADR 050.
- `docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md` — MODIFY. Decision + implementation log filled (originally committed 67b0007).
- `~/.claude/projects/.../memory/{feedback-dispatch-relay-only.md,MEMORY.md}` — NEW/MODIFY (DONE, untracked per-machine memory).

## In-flight scope updates
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
- **Decision: 2026-06-15 finish-push assessment — build artifacts confirmed complete; remaining tasks (5/6/7 + keepalive) are runtime/agent-dispatch/fresh-session-gated and cannot complete in a builder session. Plan stays ACTIVE.** Tier 1. A dispatched builder session (worktree off clean master a68ad4c) was asked to drive this plan to completion. Honest assessment of on-disk state:
  - **PROVEN built + committed on master:** Task 1 (SKILL, `adapters/claude-code/skills/orchestrator-prime.md`, committed 8c2ac95), Task 2 (ADR 050 + runtime scaffold `~/.claude/orchestrator-prime/{inbox,outbox,state.json}`), Task 3 (relay rule `dispatch-relay-protocol.md` + INDEX.md row, committed), Task 4 (`feedback-dispatch-relay-only.md` memory + MEMORY.md index row, present). Tasks 8/9/10 are DONE-in-SKILL with dispositions recorded. The two `[ ]` checkboxes on Tasks 3 & 4 are stale-unflipped, NOT unbuilt — their artifacts all exist and are committed; only `task-verifier` may flip them (verifier mandate) and a builder session has no Agent-tool surface to invoke it.
  - **Mirror-sync false alarm (diagnosis-first):** the live `~/.claude/` mirrors of the SKILL and relay rule appeared to differ from canonical, but `cmp`/`git show HEAD` proved the difference is purely `core.autocrlf=true` working-tree CRLF vs git-stored LF — the live mirror is byte-identical to git-stored canonical for BOTH files. No mirror sync was needed or performed. (Aside: most OTHER canonical skills git-store CRLF while these two store LF — a pre-existing harness-wide EOL inconsistency, out of scope here.)
  - **Genuinely remaining + why NOT completable this session:** Task 5 (seam smoke test, `Verification: full`) needs a real Dispatch session writing the inbox AND a running orchestrator-prime reading the outbox — a live cross-session/runtime test, impossible from a single builder session. Task 6 (systems-designer PASS) requires the `Agent`/`Task` sub-agent-dispatch tool, which is NOT in a builder session's tool surface. Task 7 (launch verification, `Verification: full`) requires actually launching orchestrator-prime and observing its first cycle — runtime, and currently blocked by the keepalive cold-start gap (RWR-25, below). **Precise remaining steps:** (5) from a live Dispatch session, drop `inbox/test.json`, confirm an `outbox/*.json` surfaces to Misha; `ls ~/.claude/orchestrator-harness-map.md`; (6) invoke `systems-designer` on this Mode:design plan from a session that has the Agent tool, address findings to PASS; (7) launch orchestrator-prime, confirm its first-cycle "online + inherited state" outbox is correct + Misha acks.
  - **RWR-25 keepalive cold-start status (the always-on guarantee is currently false):** the keepalive scheduled task's cold-start path `Skill(skill="orchestrator-prime")` returns "Unknown skill" because flat-`~/.claude/skills/<name>.md` skills are NOT in the Skill-tool registry — only `<name>/SKILL.md` directory-form skills register (PROVEN by the keepalive's failed runs; documented in untracked discoveries `2026-06-02-flat-md-skills-not-skill-tool-invocable.md` + `2026-06-11-orchestrator-prime-keepalive-cannot-invoke-skill-in-scheduled-context.md`). The fix recommendation is **D-then-A**: confirm the format-is-the-cause HYPOTHESIS (convert one skill → fresh session → observe Skill-invocability) BEFORE migrating all skills. **The conversion (build half) was DEFERRED this session, with reason** (see next entry).
- **Decision: 2026-06-15 — DEFER the RWR-25 flat-`.md`→`<name>/SKILL.md` skill-directory conversion; do NOT do it as part of this finish-push.** Tier 2. The brief permitted the conversion build but said to assess risk/breadth and defer with reason if risky/broad. Reasons to defer, in order: (1) **Unconfirmed premise** — that the flat-vs-directory format is the cause is HYPOTHESIZED, not PROVEN (`claims.md`); the discovery's own recommendation is D-then-A: run the cheap, fresh-session-gated refutation test FIRST so the class-fix isn't built on a wrong premise. The refutation test CANNOT run mid-session (the Skill registry loads at session start). (2) **Broader than a mechanical conversion** — `install.sh` does NOT manage skills at all (its sync loop covers `rules agents hooks scripts pipeline-prompts pipeline-templates commands` — `skills` is absent), so the discovery's option-A ("update install.sh to emit/register the directory form") is net-new install logic + a `~/.claude/` manual-copy step + updating every rule that references `/skill` invocations — a real multi-task harness-maintenance plan, not a one-session conversion. (3) **No RWR-25 plan + out of orchestrator-prime's declared scope** — RWR-25 is captured only in untracked discoveries with no plan; folding an 11-skill (canonical) migration into orchestrator-prime-finish would be scope-drift. (4) **Breakage risk** — the handful of working directory-form skills (`<name>/SKILL.md` form) live only in the live mirror, installed from a different (project-tier / marketplace) path, NOT from canonical `adapters/`; converting canonical flat skills + hand-copying could collide with their registration. **Remaining step (fresh-session-gated):** open an RWR-25 harness-maintenance plan; Step 1 = the refutation test (convert `orchestrator-prime` only → fresh session → `Skill(orchestrator-prime)` resolves?); if confirmed, Step 2 = migrate all flat skills + add install.sh skill-sync + update `/skill`-referencing rules; Step 3 = give the keepalive a Skill-independent cold-start primitive OR the surface-not-respawn reframe (discovery option C/D). Until then, the keepalive's autonomous restart is broken and orchestrator-prime only comes up when Misha launches it interactively.
- **Decision: long-lived ACTIVE by design — do not triage this plan as stale (2026-06-10 stale-plan triage).** Tier 1. This plan IS the running orchestrator-prime program, not a finite build: the always-on loop (durable `orchestrator-prime-keepalive` scheduled task) is the deliverable in operation. Its closure criterion is PROGRAM COMPLETION — including the One Season reminder and the completion report per the portfolio tracker — not "all build tasks checked." The stale-plan surfacer (and future staleness/commitment-breach gates per plan-lifecycle-redesign R5) should expect a long-lived `Status: ACTIVE` here; flag it for closure only when the program itself is being retired. Remaining build-phase items (Tasks 5–7: seam smoke test, systems-designer PASS, launch verification) are tracked above and still owed.
- **Decision: /loop + file-mediated inbox/outbox replaces the refuted transcript-read relay.** Tier 3. Surfaced to user: 2026-06-02 (Misha proposed /loop directly). Chosen: self-waking loop polling a file inbox — sidesteps the RC1 parent-wake gap. Alternative: transcript-read relay (refuted — passive read can't make a session process a message). Record: ADR 050.
- **Decision: revival = detect+surface+respawn-with-ack, not message-revive.** Tier 2. Surfaced: 2026-06-02. Chosen: the only path the verified tool surface supports. Alternative: send resume messages (refuted — no primitive). Record: ADR 050 + the discovery.
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
10. **Decision records & runbook:** ADR 050. Runbook — *seam silent:* check outbox written + whether a Dispatch session ran; fall back to GUI. *Loop stopped:* check durable cron + relaunch from state.json. *Duplicate spawn:* dedup-guard window too short → widen. *No merges:* repo in review-before-deploy → expected (surfaced not merged).

## Definition of Done
- [ ] dispatch-relay-protocol.md + memory entry written (Tasks 3–4).
- [ ] Seam smoke test passes OR seam declared dead + GUI/ntfy fallback documented (Task 5).
- [ ] systems-designer PASS (Task 6).
- [ ] Report-only first cycle produces a correct inherited-state outbox; Misha acks full autonomy (Task 7).
- [ ] harness-architecture.md + DECISIONS.md + SCRATCHPAD updated; completion report appended.
