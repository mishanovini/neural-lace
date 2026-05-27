# ADR 039 — Conversation-tree visibility: reconciliation over interception (matcher reconciled)

**Date:** 2026-05-25
**Status:** Proposed (design-only; implementation gated on Misha's greenlight — Pattern 5 of the plan-lifecycle redesign initiative)
**Stakeholders:** Misha (decision authority); the conversation-tree GUI (passive observer, ADR-031 r7); future build-session orchestrators.

## Context

The brief reported "the `conversation-tree-emit` hook never fires despite being correctly
registered," hypothesizing a matcher/namespace mismatch (`mcp__dispatch__*`). Diagnostic-first
investigation (`docs/discoveries/2026-05-25-dispatch-coordination-debug.md`, RC2) produced:

1. **Matcher reconciliation (PROVEN).** The matcher
   `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task` names the **correct**
   namespace. `mcp__ccd_session__spawn_task` is a live tool in an orchestrator session's own
   toolset; `mcp__dispatch__*` does not exist. The brief's premise is **refuted.** No
   matcher change is warranted on namespace grounds. (ADR-031 r8 / ADR-034 already fixed the
   enumerated set deliberately; this ADR confirms it is *correct as written*, not a bug.)
2. **The hook has genuinely never fired on a real spawn (PROVEN).** `conversation-tree-emit.log`
   contains only `--self-test` fixtures; zero real `--on-spawn` events, ever.
3. **Two real causes, neither a matcher typo (PROVEN):**
   - **(a) Structural blind spot.** PreToolUse fires only when a *hook-loading local* Claude
     session *calls* the tool. Branches created from the Dispatch app UI (human action) or a
     cloud orchestrator (inherits only project `.claude/`, not `~/.claude/` — Decision 011)
     produce no interceptable tool call. This is the ADR-031 r7 "passive observer / cloud
     blind spot," accepted in the abstract, now reproduced concretely.
   - **(b) Sink/source path divergence.** `conv-tree-read.log` shows the GUI reading a state
     file at `…/neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json` while
     sessions flip between the `claude-projects` and `dev/Pocket Technician` checkouts. The
     emit/read hooks resolve the path relative to cwd, so writer and reader can resolve
     **different files** — even a firing emit can land where the GUI never looks.

Interception (PreToolUse on the spawn tool) is therefore the wrong *primary* mechanism for
tree visibility: it can only ever see the subset of branches an orchestrator opens via a
local tool call, which the evidence says is empty in practice.

## Decision

Adopt **reconciliation over interception** as the primary visibility mechanism, and fix the
path divergence. Three parts:

1. **Keep the interception matcher exactly as-is.** It is correct (ADR-034) and remains a
   *fast-path* emitter for the case where a local orchestrator *does* call `spawn_task` /
   `start_code_task` — that path stays valuable and idempotent (ADR-032 `event_id`). No
   change. This ADR explicitly records "matcher confirmed correct, not the bug" so a future
   session does not re-chase the `mcp__dispatch__*` ghost.

2. **Add a `list_sessions` reconciler** (`~/.claude/hooks/conv-tree-reconcile.sh`, SessionStart
   + optionally periodic). It calls the **real, available** `mcp__ccd_session_mgmt__list_sessions`
   tool to enumerate the operator's *actual* sibling Dispatch sessions (the authoritative
   source of "what branches exist"), and emits a `branch-opened` event (idempotent on the
   session-derived `event_id`) for every session not already in the tree, plus `concluded`
   for sessions now archived. This makes tree visibility **independent of whether any spawn
   tool call was intercepted** — it reconciles the tree against ground truth on a cadence,
   which is exactly what survives the structural blind spot.
   - Mechanism caveat (honest): `list_sessions` is itself an MCP tool, so the reconciler
     must run *inside a session that has that tool* (a local orchestrator / Dispatch session).
     A purely cloud orchestrator that never touches the local machine still can't be seen —
     that residual is the same Decision-011 cloud gap ADR-031 already accepts. The reconciler
     closes the *local-Dispatch* blind spot (the dominant real workflow), not the cloud one.

3. **Pin a cwd-independent canonical state path.** The emit hook, the read hook, and the GUI
   launcher must all resolve the same file regardless of which checkout the session runs from.
   Decision: resolve the conversation-tree state path from the **git common dir** of the
   *tree's owning repo* (one tree per repo, per ADR-032 path resolution), published once to
   `~/.claude/local/conv-tree-state-path` (or an env `CONV_TREE_STATE_PATH`, which the hooks
   and launcher already honor) by the launcher at GUI start. All writers/readers read that
   pointer instead of recomputing `<cwd>/neural-lace/conversation-tree-ui/state/…`. This kills
   the `neural-lace/neural-lace` doubling and the claude-projects-vs-dev-checkout split.

4. **Free RC4 duplicate-spawn detection.** The reconciler already enumerates sessions with
   metadata; extend it to flag two sessions with the **same brief-hash created within N
   minutes** as a suspected duplicate (the laughing-poitras / zealous-lalande incident) and
   surface it to the operator via the discovery/finding substrate. This is **detection, not
   prevention** — prevention requires a Dispatch-side idempotency key, which is closed-source
   to us and is the subject of the upstream recommendation. Named honestly.

## Alternatives considered

- **A — Widen the matcher to `mcp__dispatch__*` (the brief's fix).** Rejected: PROVEN that
  namespace does not exist; the matcher already names the correct one. This would add dead
  alternatives and re-introduce the very `Task`/`Agent` over-capture ADR-034 just removed.
- **B — Rely on interception alone, harder.** Rejected: interception is structurally blind to
  GUI-originated and cloud-originated branches; no amount of matcher work fixes "there is no
  tool call to intercept."
- **C — Make the GUI poll `list_sessions` directly (no harness hook).** Rejected: the GUI is a
  passive file-mediated observer per ADR-031 r7; it must not gain orchestration/tool-calling
  capability. The reconciler keeps the write on the harness (orchestrator) side, preserving
  the passive-observer contract.
- **D — Leave path resolution cwd-relative, document the gotcha.** Rejected: the divergence is
  actively producing "state file absent" no-ops *today*; a documented gotcha is palliative,
  the canonical-path pin is curative.

## Consequences

- **Enables (curative for local-Dispatch visibility):** the tree populates from ground truth
  (`list_sessions`) regardless of how a branch was created, and writer/reader/GUI agree on one
  file. The FR-24 "open branches always surface-able" property becomes achievable for the
  dominant local-Dispatch workflow.
- **Residual (named):** a purely-cloud orchestrator that never runs locally remains invisible —
  the Decision-011 cloud gap ADR-031 already accepts; unchanged. RC4 prevention remains
  Dispatch-side (we detect, Anthropic/Dispatch must prevent).
- **Cost:** one new SessionStart (+optional periodic) hook that makes an MCP tool call;
  reconciliation cadence is a tunable (SessionStart is the floor; a periodic
  `ScheduleWakeup`/scheduled-task cadence is optional and traded against the prompt-cache
  window per `ScheduleWakeup` guidance).
- **No schema change.** Reconciler emits the existing ADR-032 `branch-opened`/`concluded`
  event classes through the frozen facade; idempotency on `event_id` means re-running the
  reconciler is safe (it converges, it doesn't duplicate).
- **ADR-034 unchanged.** The Dispatch-only enumerated matcher set stands; this ADR adds a
  parallel reconciliation path, it does not re-open the Task/Agent scoping.

## Cross-references

- Discovery: `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` (RC2, RC4).
- ADR-031 (passive observer + cloud blind spot), ADR-032 (state schema + `event_id` idempotency + path resolution), ADR-034 (Dispatch-only matcher — confirmed correct here).
- Decision 011 (cloud sessions inherit only project `.claude/`) — bounds what the reconciler can see.
- Plan: `docs/plans/dispatch-coordination-redesign.md` (Task group B + RC4 detector).
- Sibling ADRs this session: 041 (auto-detect), 042 (ntfy out-of-band).
