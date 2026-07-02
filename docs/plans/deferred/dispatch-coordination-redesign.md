# Plan: Dispatch ↔ Code Session Coordination Redesign (Pattern 5 of 5)
Status: DEFERRED
Execution Mode: orchestrator
Mode: design
frozen: false
tier: 3
rung: 3
architecture: harness-infrastructure
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal coordination mechanisms (SessionStart/Notification/Stop hooks + a reconciler); the "user" is a hook firing at an event boundary and the maintainer running --self-test. No product UI surface to advocate for; self-tests are the acceptance artifact.
owner: Misha
target-completion-date: (set when build phase is greenlit)
Backlog items absorbed: none

<!-- This is the DESIGN deliverable for Pattern 5. DESIGN-ONLY: no code changes, no
     commits this session. Implementation is a SEPARATE phase requiring Misha's explicit
     greenlight AND a systems-designer PASS on this plan (Mode: design gate). The plan
     touches only adapters/claude-code/ + docs/, so the build-harness-infrastructure
     work-shape applies (Mode: code at build time, systems-designer relaxed) — BUT this
     plan is authored Mode: design because it integrates a new third-party service
     (ntfy.sh) and crosses session boundaries (>3 state transitions), which are explicit
     Mode: design triggers. The brief also mandates Mode: design. Honor both. -->

## Disposition (2026-07-02)
Deferred per DEC-2026-07-02-002 (same cluster as orchestrator-prime). Its problem space (wake delivery, operator visibility) is partially re-solved by the overhaul's digest + ledger; re-evaluate what remains post-F.4.

## Goal

Make the Dispatch (event-driven, sleeps) ↔ child Code session (goes idle awaiting a
directive) relay reliable, and make the conversation-tree GUI actually populate, by
landing the **mechanical, curative** fixes that are achievable harness-side, while
**naming honestly** the one gap that is not (parent-wake on child turn-end — Anthropic-side).

Five root causes (full evidence in `docs/discoveries/2026-05-25-dispatch-coordination-debug.md`):
1. No reliable parent-wake on child turn-end (Anthropic-blocked; bounded palliative + filed issue).
2. conv-tree emit hook never fires (NOT a matcher typo — structural blind spot + path divergence; reconciler + canonical-path fix).
3. No auto-detect of dispatch-mode (manual flip today; SessionStart detector keyed on env vars that actually exist).
4. No idempotency on Dispatch task-spawn (double-spawn; Dispatch-side prevention recommended upstream + harness-side detector).
5. No phone/external notification path (opt-in ntfy.sh out-of-band push).

**User-facing Outcome.** After this ships: (a) a fresh or forgetful session resolves
dispatch-mode correctly without a manual flip; (b) the conversation-tree GUI shows every
local-Dispatch branch and what's waiting on Misha, regardless of how the branch was
created; (c) when a child needs Misha and Dispatch is asleep, his phone buzzes; (d) a
double-spawn is detected and surfaced; (e) the parent-wake gap is filed upstream with a
concrete ask and bounded locally so the relay never hangs *forever*. The maintainer's
user-facing outcome for each mechanism is its `--self-test` passing + the documented
runtime behavior firing under its trigger.

## Scope

- IN:
  - `~/.claude/hooks/dispatch-mode-detect.sh` (new SessionStart detector) — RC3 / ADR-041.
  - `~/.claude/hooks/ntfy-notify.sh` (new opt-in notifier) wired into Notification/Stop — RC5 / ADR-042.
  - `~/.claude/hooks/conv-tree-reconcile.sh` (new SessionStart + optional periodic reconciler) — RC2/RC4 / ADR-039.
  - Canonical cwd-independent conv-tree state-path resolution shared by emit hook, read hook, GUI launcher — RC2 / ADR-039.
  - `adapters/claude-code/examples/ntfy.config.example.json` and dispatch-mode example refresh.
  - `settings.json.template` wiring for the three new hooks (SessionStart ordering; Notification/Stop chains).
  - Docs: ADR-039/041/042 (authored this session), the discovery (authored this session), the upstream issue draft (authored this session), `docs/harness-architecture.md` row updates (build phase), SETUP/install notes for ntfy opt-in.
  - A bounded parent-side poll pattern (documented `ScheduleWakeup`/scheduled-task cadence) as the *named palliative* for RC1.
- OUT:
  - Any Dispatch-internal code change (closed-source; we recommend, we don't implement). RC4 *prevention* and RC1 *cure* live here.
  - Any change to the GUI's passive-observer contract (ADR-031 r7) — the GUI does not gain tool-calling/orchestration.
  - Re-opening the ADR-034 Dispatch-only matcher scope (Task/Agent stay out).
  - Cloud-orchestrator visibility (Decision 011 gap — a purely-cloud session never running locally stays invisible; accepted, unchanged).
  - Closing the inter-session messaging gap harness-side (impossible without Anthropic — named, filed, not faked).
  - Implementation. This session is design-only.

## Tasks

<!-- All tasks are Verification: mechanical (harness-infra: file exists + --self-test PASS +
     mirror byte-identical) UNLESS noted. Build phase only — none executed this session. -->

### Task group A — Dispatch-mode auto-detect (RC3 / ADR-041)
- [ ] A1. Author `dispatch-mode-detect.sh` implementing the ADR-041 priority ladder (env override → manual-lock → host+agent heuristic → default false), atomic temp-then-rename publish, `detected_by`/`detected_at` provenance fields, writer-class never-block + log. — Verification: mechanical
  - **Prove it works:** 1. Run `dispatch-mode-detect.sh --self-test`. 2. Confirm scenarios: `CLAUDE_CODE_DISPATCH=1`→true; `=0`→false; manual-lock file untouched; `ENTRYPOINT=claude-desktop`+`AI_AGENT=*_agent`→true; bare env→false; malformed prior file→no-clobber+exit 0.
  - **Wire checks:** `adapters/claude-code/hooks/dispatch-mode-detect.sh` → writes `~/.claude/local/dispatch-mode.json` → read by `~/.claude/CLAUDE.md` Autonomy consumers. (≥2 arrows; build phase verifies file existence + grep of the published field.)
  - **Integration points:** resolve the `local-edit-gate.sh` interaction (allowlist the detector's writer path or route via the tolerated temp-then-rename). `bash ~/.claude/hooks/local-edit-gate.sh --self-test` after.
- [ ] A2. Resolve `local-edit-gate.sh` ↔ detector interaction (allowlist or sanctioned-writer path); extend that gate's self-test with a `dispatch-mode-detect.sh` writer scenario. — Verification: mechanical
- [ ] A3. Wire `dispatch-mode-detect.sh` FIRST in the `settings.json.template` SessionStart chain (before discovery-surfacer / spawned-task-result-surfacer); sync live mirror; `diff -q`. — Verification: mechanical
- [ ] A4. Refresh `dispatch-mode.example.json` to document `manual` lock + the new provenance fields. — Verification: mechanical

### Task group B — conv-tree reconciliation + canonical path (RC2 / ADR-039)
- [ ] B1. Author `conv-tree-reconcile.sh` (SessionStart): call `mcp__ccd_session_mgmt__list_sessions`, emit idempotent `branch-opened` for unseen sessions + `concluded` for archived, through the frozen ADR-032 facade. No schema change. — Verification: mechanical
  - **Prove it works:** 1. `conv-tree-reconcile.sh --self-test` against a synthetic session list. 2. Re-run; confirm idempotency (no duplicate nodes — `event_id` dedupe). 3. Confirm a now-archived session emits `concluded`.
  - **Wire checks:** `adapters/claude-code/hooks/conv-tree-reconcile.sh` → frozen facade `state.js appendEvent` → canonical state file → GUI read. (≥2 arrows.)
  - **Integration points:** must use the SAME canonical state path as B2; `bash ~/.claude/hooks/conversation-tree-emit.sh --self-test` still green after.
- [ ] B2. Pin a cwd-independent canonical conv-tree state path: launcher publishes the git-common-dir-resolved path to `~/.claude/local/conv-tree-state-path` (or `CONV_TREE_STATE_PATH`); emit hook, read hook, reconciler, and GUI launcher each read that pointer. Kills the `neural-lace/neural-lace` doubling + checkout split. — Verification: full
  **Prove it works:**
  1. Start GUI from the dev checkout; note the published path.
  2. Run an emit from a session cwd'd in `claude-projects`.
  3. Confirm the event lands in the GUI-watched file (read log no longer reports "state file absent").
  **Wire checks:**
  - `conv-tree-launcher` writes `~/.claude/local/conv-tree-state-path` → `adapters/claude-code/hooks/conversation-tree-emit.sh` reads that pointer
  - `~/.claude/local/conv-tree-state-path` → `adapters/claude-code/hooks/conv-tree-reconcile.sh` + the GUI launcher read the same canonical file
  **Integration points:**
  - GUI server reads same path; verify via `conv-tree-read.log` showing a present (not absent) state file post-fix.
- [ ] B3. Record in ADR-039 / architecture doc that the interception matcher is CONFIRMED CORRECT (not the bug) so no future session re-chases `mcp__dispatch__*`. — Verification: mechanical (doc grep)
- [ ] B4. RC4 duplicate-spawn detector: extend the reconciler to flag two sessions with same brief-hash within N minutes; surface to operator via `docs/discoveries/` or `docs/findings.md`. Detection only — name prevention as Dispatch-side. — Verification: mechanical

### Task group C — ntfy out-of-band push (RC5 / ADR-042)
- [ ] C1. Author `ntfy-notify.sh`: read `~/.claude/local/ntfy.config.json`; POST bounded (`curl --max-time 5`, backgrounded) to `<base_url>/<topic>` with no-content payload (event class + opaque session id + short summary only); absent/disabled config → silent no-op exit 0; each path logs + exit 0. — Verification: mechanical
  - **Prove it works:** 1. `ntfy-notify.sh --self-test` (config-absent no-op; enabled→constructs correct POST; disabled→no-op; payload carries NO prompt/file/path content). 2. With a real test topic, fire a `Notification` event and confirm a phone push arrives.
  - **Wire checks:** `adapters/claude-code/hooks/ntfy-notify.sh` → reads `~/.claude/local/ntfy.config.json` → `curl POST <base_url>/<topic>`. (≥2 arrows.)
  - **Integration points:** wired into `Notification` (default on) + `Stop` (opt-in) chains; harness-hygiene scan must pass (no topic/secret in repo).
- [ ] C2. Wire `ntfy-notify.sh` into `settings.json.template` Notification (default) + Stop (opt-in) chains; sync mirror; `diff -q`. — Verification: mechanical
- [ ] C3. Ship `ntfy.config.example.json` (placeholder topic) + SETUP/installation notes (topic = capability, self-host option, no-content guarantee). — Verification: mechanical

### Task group D — RC1 palliative + upstream (Anthropic-blocked, named)
- [ ] D1. Document the bounded parent-side poll pattern (`ScheduleWakeup` / scheduled-task cadence) as a NAMED PALLIATIVE in `automation-modes.md` / `spawn-task-report-back.md` cross-ref: prevents infinite hang, does not cure prompt-resume latency. Explicitly labeled palliative. — Verification: mechanical (doc)
- [ ] D2. Finalize + file `docs/proposals/anthropics-claude-code-parent-wake-issue.md` against `anthropics/claude-code` (Misha files; dedupe against #40070 first). — Verification: mechanical

### Task group E — close-out
- [ ] E1. Update `docs/harness-architecture.md` (3 new hooks), enforcement map in `vaporware-prevention.md` if applicable, `docs/DECISIONS.md` rows (039/041/042 — added this session). — Verification: mechanical
- [ ] E2. systems-designer PASS on this plan (the Mode: design gate) BEFORE any of A–C builds. — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/dispatch-mode-detect.sh` — NEW (A1).
- `adapters/claude-code/hooks/conv-tree-reconcile.sh` — NEW (B1).
- `adapters/claude-code/hooks/ntfy-notify.sh` — NEW (C1).
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — MODIFY (B2: read canonical path pointer).
- `adapters/claude-code/hooks/conversation-tree-read.sh` — MODIFY (B2: read canonical path pointer).
- `adapters/claude-code/hooks/local-edit-gate.sh` — MODIFY (A2: detector writer interaction + self-test).
- `adapters/claude-code/settings.json.template` — MODIFY (A3, C2: wire 3 hooks).
- `adapters/claude-code/examples/ntfy.config.example.json` — NEW (C3).
- `adapters/claude-code/examples/dispatch-mode.example.json` — MODIFY (A4).
- the conv-tree GUI launcher script — MODIFY (B2: publish canonical state path).
- `docs/decisions/041-dispatch-mode-autodetect-signal.md` — CREATED this session.
- `docs/decisions/042-ntfy-out-of-band-notification.md` — CREATED this session.
- `docs/decisions/039-conv-tree-reconciliation-over-interception.md` — CREATED this session.
- `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` — CREATED this session.
- `docs/proposals/anthropics-claude-code-parent-wake-issue.md` — CREATED this session.
- `docs/DECISIONS.md` — MODIFY (rows 037–039, this session).
- `docs/harness-architecture.md` — MODIFY (build phase, E1).
- `SCRATCHPAD.md` — MODIFY (this session).

## In-flight scope updates
<!-- Build-phase additions go here with date + one-line reason. -->

## Assumptions

- The conv-tree state library facade (`state.js appendEvent` / ADR-032 frozen A2) remains the only sanctioned writer; the reconciler emits through it, no raw JSON. (Re-verify the facade signature at build time per `claims.md`.)
- `mcp__ccd_session_mgmt__list_sessions` is available in the orchestrator/local-Dispatch session the reconciler runs in (PROVEN available in *this* session's toolset). A session lacking it degrades to interception-only (the reconciler no-ops gracefully).
- `CLAUDE_CODE_ENTRYPOINT`, `AI_AGENT`, and the SDK-marker env vars observed this session are stable across Claude Code 2.1.x desktop sessions (HYPOTHESIZED — refutation: env-diff of known standalone vs known Dispatch-child session; see ADR-041).
- ntfy.sh (or a self-hosted instance) is reachable from the operator's machine when enabled; absence degrades to silent no-op, never a block.
- Hooks run under Git-Bash on Windows with `jq` available (the SCRATCHPAD notes ~10 doctrine hooks fall back to no-jq degraded mode without a Claude Code restart — the build phase must confirm the 3 new hooks tolerate no-jq or require the restart).

## Edge Cases

- **Dispatch-mode false-positive** (human-at-desktop flagged dispatch): only downgrades MC-widget → plain-text (safe). ADR-041 Consequences.
- **Manual lock present:** detector must NOT clobber an explicit human choice (ADR-041 rule 2).
- **Reconciler runs with no `list_sessions` tool:** graceful no-op (interception fast-path still active).
- **Reconciler re-run / double-fire:** idempotent on `event_id` — converges, never duplicates.
- **Canonical path pointer absent** (GUI never launched): hooks fall back to current cwd-relative behavior + log a warning (no regression vs today).
- **ntfy down / no network:** 5s-bounded curl, swallow, log, exit 0 — never blocks.
- **ntfy payload accidentally carrying content:** explicit no-content construction + a self-test scenario asserting the payload contains no prompt/file/path substrings (harness-hygiene).
- **Double-spawn where both went through the hook:** `event_id` dedupe means the tree shows one node; the RC4 detector still flags the two underlying sessions from `list_sessions`.
- **No-jq degraded mode:** the three new hooks must either tolerate it or require the documented Claude Code restart (build-phase decision).

## Acceptance Scenarios
n/a — `acceptance-exempt: true` (harness-internal; self-tests are the acceptance artifact). Each hook ships a `--self-test` exercising its branches; the maintainer-observable outcome is `--self-test: OK` + the documented runtime behavior under its trigger.

## Testing Strategy

Per-hook `--self-test` (the harness's native rubric) covering every branch enumerated in the
Tasks "Prove it works" blocks. B2 (canonical path) is `Verification: full`: the proof is the
`conv-tree-read.log` flipping from "state file absent" to a present file after an emit from a
divergent cwd. C1's push leg requires one real end-to-end POST to a test topic (functionality,
not mock — per `testing.md`, you cannot mock the thing you claim to verify). systems-designer
PASS on this plan gates the whole build (E2).

## Walking Skeleton

B1 + B2 together are the walking skeleton: the thinnest end-to-end slice that
exercises every layer of the conv-tree spine — a session emits an event (emit
hook) → through the frozen ADR-032 facade into the single canonical state file
(B2's pinned, git-common-dir-resolved path) → the GUI reads that same file and
surfaces the branch to the operator (`conv-tree-read.log` reports a present,
not "absent", state file). Pinning the canonical path (B2) first removes the
`neural-lace/neural-lace` doubling that otherwise makes every later RC
unobservable; B1's reconciler is the first producer that proves the slice
end-to-end. Groups A (dispatch-mode auto-detect) and C (ntfy push) are
independent flesh layered onto the same emit → state → read spine and ship
only after the skeleton is green.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in §§1–10 is cited at a Task + a Files entry; 3 new hooks + 3 modified files + launcher all have task + file entries. 0 stranded.
S2 (Existing-Code-Claim Verification): swept — claims about emit-hook matcher, log contents, env vars, `list_sessions` availability, read-log path divergence were all re-verified against live files/env THIS session (not memory); evidence in the discovery. `state.js appendFacade` signature flagged for build-time re-verification (Assumptions).
S3 (Cross-Section Consistency): swept — "matcher is correct" stated consistently in discovery, ADR-039, Task B3; "RC1 Anthropic-blocked / not faked" consistent across Goal, Scope OUT, Task D, ADR-042; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept — params: `curl --max-time 5` (C1, ADR-042 consistent), reconciler "N minutes" duplicate window (B4 — left as a build-time tunable, flagged not fixed), poll cadence (D1 — references `ScheduleWakeup` cache-window guidance, not a fixed number). No conflicting literals.
S5 (Scope-vs-Analysis Check): swept — every "Add/Modify" verb checked against Scope OUT; Dispatch-internal changes (RC1 cure, RC4 prevention) correctly placed OUT (recommend-not-implement); GUI contract change correctly OUT; matcher re-scope correctly OUT. 0 contradictions.

## Decisions Log
- **Decision: matcher is correct — fix is reconciliation, not a namespace change.** Tier 2. Surfaced to user: 2026-05-25 (this design session, plain-text). Chosen: keep matcher, add `list_sessions` reconciler + canonical path. Alternatives: widen to `mcp__dispatch__*` (refuted — namespace doesn't exist). Record: ADR-039.
- **Decision: auto-detect on env vars that exist, not `PROVIDER_MANAGED_BY_HOST`.** Tier 2. Surfaced to user: 2026-05-25. Chosen: ENTRYPOINT + agent-SDK corroboration, conservative over-flag. Alternative: the originally-proposed two-part signal (refuted — second var absent). Record: ADR-041.
- **Decision: RC1 not faked.** Tier 2. Surfaced to user: 2026-05-25. Chosen: file upstream issue + named parent-side-poll palliative + out-of-band ntfy. Alternative: claim report-back convention "closes" it (rejected — false promise). Record: ADR-042 + the issue draft.

## Ordered implementation roadmap

Dependency-ordered; A and C are independent of B and can parallelize; D is doc/file-only.

1. **E2 — systems-designer PASS on this plan** (the Mode: design gate; nothing builds until this passes).
2. **A1–A4 — dispatch-mode auto-detect** (highest value-per-effort; self-contained; unblocks correct MC-widget behavior immediately). Resolve the local-edit-gate interaction (A2) as part of A.
3. **B2 — canonical conv-tree state path** FIRST within group B (the path divergence is actively producing no-ops today; fixing it is prerequisite for B1 to be observable).
4. **B1, B3, B4 — reconciler + matcher-confirmation doc + duplicate detector** (depend on B2's canonical path).
5. **C1–C3 — ntfy out-of-band push** (independent; can run parallel to A/B).
6. **D1 — document the parent-side-poll palliative**; **D2 — Misha files the upstream issue**.
7. **E1 — architecture doc + DECISIONS + enforcement-map close-out.**

## Definition of Done
- [ ] systems-designer PASS on this plan (E2) — the Mode: design gate.
- [ ] A/B/C hooks authored, each `--self-test: OK`, wired in settings, mirror byte-identical.
- [ ] B2 proven: `conv-tree-read.log` shows a present (not absent) state file after a cross-cwd emit.
- [ ] C1 proven: one real end-to-end ntfy push received on a test topic.
- [ ] D2: upstream issue filed (or explicitly deferred by Misha).
- [ ] harness-architecture.md + DECISIONS.md + SCRATCHPAD updated.
- [ ] Completion report appended.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
Within one SessionStart of a Dispatch-orchestrated session: dispatch-mode is correctly
resolved with zero manual flips (provenance auditable in `dispatch-mode.json.detected_by`).
Within one reconciler run: every local-Dispatch sibling session appears as a tree node in
the GUI-watched state file (verifiable: `conv-tree-read.log` stops reporting "state file
absent"). Within 5s of a child `Notification` event with ntfy enabled: a push reaches
Misha's phone. The relay never hangs *silently forever* — if the parent can't be woken
(RC1, Anthropic-blocked), the human is woken instead (ntfy) and/or a bounded poll advances
state. The one thing NOT promised: prompt parent-resume on child turn-end (filed upstream,
named as unsolved).

### 2. End-to-end trace with a concrete example
Misha, on his phone, taps "new task" in the Dispatch app to spawn a Foresight child. The
Dispatch backend creates session `zealous-lalande`. **No local hook fires** (the spawn
originated in the app UI, not an orchestrator tool call — RC2(a)). Later, an orchestrator
or any local-Dispatch session starts; `conv-tree-reconcile.sh` runs at SessionStart, calls
`list_sessions`, sees `zealous-lalande` (and its duplicate `laughing-poitras`, same brief
within ~1 min), and emits `branch-opened` for the unseen ones through the facade into the
**canonical** state file (B2) the GUI watches → the GUI now shows both branches, and the
RC4 detector flags the pair as a suspected duplicate (B4). `zealous-lalande` runs, hits a
point needing Misha's input, fires a `Notification` → `ntfy-notify.sh` POSTs "Session
zealous-lalande needs your input" to Misha's ntfy topic → his phone buzzes even though the
Dispatch parent is asleep (RC1 unsolved but routed-around). Misha opens the session,
answers. Meanwhile the dispatch-mode of every session was auto-resolved at its SessionStart
(A1), so none of them rendered a dead MC-widget.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| `dispatch-mode-detect.sh` | `~/.claude/CLAUDE.md` Autonomy consumers | Atomically-published `dispatch-mode.json` with `running_under_dispatch:bool`, `detected_by`, `detected_at`; never partially written (temp-then-rename). |
| conv-tree GUI launcher | emit/read/reconcile hooks | `~/.claude/local/conv-tree-state-path` (or `CONV_TREE_STATE_PATH`) = absolute canonical state-file path, git-common-dir-resolved, written once at GUI start. |
| `conv-tree-reconcile.sh` | conv-tree state file (via facade) | Idempotent `branch-opened`/`concluded` events keyed on session-derived `event_id`; emits through `state.js appendEvent` only; no schema bump. |
| `list_sessions` tool | reconciler | JSON array of sibling sessions (id, title/brief, status, timestamps); reconciler treats it as authoritative ground truth. |
| `ntfy-notify.sh` | ntfy.sh `<topic>` | HTTP POST, ≤5s, Title/Tags/Priority headers + one-line no-content body; opaque session id only; best-effort, never blocks. |

### 4. Environment & execution context
Git-Bash on Windows 11; Claude Code 2.1.146, `claude-desktop` entrypoint. Hooks fire on
SessionStart / Notification / Stop. `jq` availability is conditional (SCRATCHPAD: ~10 hooks
fall back to no-jq degraded mode pending a Claude Code restart — the 3 new hooks must
tolerate no-jq or document the restart requirement). Local layer `~/.claude/local/` holds
`dispatch-mode.json`, `ntfy.config.json`, `conv-tree-state-path` — all gitignored,
per-machine. `~/.claude/` is a copy (Windows install, not symlink) — every change mirrors
from `adapters/claude-code/` and is `diff -q`-verified.

### 5. Authentication & authorization map
- ntfy public service: the **topic name is the only capability** — unguessable topic =
  access control; lives in the gitignored local layer; never in the repo (harness-hygiene).
  Self-hosted instance = `base_url` swap, optional bearer/basic auth added in local config.
- `list_sessions` / `spawn_task`: authorized by the session's own MCP tool grant; the
  reconciler inherits whatever the running session has — no separate credential.
- No new secrets enter the repo. Pre-push scanner + harness-hygiene Layer-1/2 must pass.

### 6. Observability plan (built before the feature)
Each hook logs to its own `~/.claude/logs/<hook>.log` (matching `conversation-tree-emit.log`
convention): detector logs `detected_by` + resolved value; reconciler logs sessions seen /
events emitted / duplicates flagged; ntfy logs POST status + HTTP code (never the payload
body beyond the event class). The canonical-path fix is observable via the existing
`conv-tree-read.log` flipping from "state file absent" to present. Every `--self-test`
prints per-scenario PASS/FAIL.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery |
|---|---|---|---|
| detect | env vars change in a future CC build | mode mis-resolved | refutation-criterion env-diff (ADR-041) → update ladder; manual lock always overrides |
| detect | local-edit-gate blocks the writer | SessionStart noise / no publish | A2 allowlist; until then writer uses tolerated temp-rename |
| reconcile | `list_sessions` absent | reconciler no-op | graceful; interception fast-path still active; logged |
| reconcile | facade signature drift | emit fails | re-verify facade at build (Assumptions); facade owns idempotency |
| path | pointer absent (GUI never launched) | cwd-relative fallback | log warning; no regression vs today |
| ntfy | service down / no net | no push | 5s timeout, swallow, log, exit 0; human unaffected beyond missing one push |
| ntfy | payload leaks content | privacy/hygiene breach | no-content construction + self-test assertion; harness-hygiene scan |
| RC1 | parent never wakes | relay stalls | bounded poll (palliative) advances; ntfy wakes human; upstream issue is the cure |

### 8. Idempotency & restart semantics
Detector: pure function of env + prior file; re-running republishes the same value (atomic).
Reconciler: idempotent on `event_id` — re-run converges, never duplicates; a torn prior
snapshot is handled by ADR-032 §7a/§8 attestation (unchanged). ntfy: at-most-once
best-effort; a missed push is acceptable (human opens session anyway); a double-fire sends
two harmless pushes. Canonical-path pointer: rewritten idempotently by the launcher each
start. No step holds state that corrupts on partial completion.

### 9. Load / capacity model
Detector + reconciler run once per SessionStart (negligible; reconciler's cost = one
`list_sessions` call, bounded by the operator's session count — tens, not thousands). ntfy:
one bounded 5s POST per `Notification` event (Notification events are rare — only when Claude
needs the human). Parent-side poll (palliative): cadence is the cost lever — per
`ScheduleWakeup` guidance, stay under the 5-min prompt-cache window only when actively
waiting on fast-changing external state; otherwise 1200s+ to avoid burning cache. No
unbounded loops. Bottleneck: none at realistic session counts.

### 10. Decision records & runbook
Decisions: ADR-041 (auto-detect signal), ADR-042 (ntfy contract), ADR-039 (reconciliation
over interception). Runbook:
- *Symptom: GUI empty.* Check `conv-tree-read.log` for "state file absent" → canonical-path
  pointer missing/diverged (B2) → confirm `~/.claude/local/conv-tree-state-path` matches the
  GUI's launch cwd-resolved path; relaunch GUI to republish.
- *Symptom: MC-widget hangs under Dispatch.* Check `dispatch-mode.json.detected_by` → if
  `default-false` on a Dispatch session, the heuristic missed → set `CLAUDE_CODE_DISPATCH=1`
  or add a manual lock; file an env-diff per ADR-041 refutation criterion.
- *Symptom: no phone push.* Check `ntfy-notify.log` for HTTP code; verify `ntfy.config.json`
  enabled + topic + reachable `base_url`; confirm phone subscribed to the topic.
- *Symptom: relay hung.* Expected for RC1 until upstream fix — confirm the bounded poll is
  scheduled and/or the ntfy push fired; the cure is the filed issue, not a local fix.
