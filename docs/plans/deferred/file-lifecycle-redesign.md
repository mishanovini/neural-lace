# Plan: File-Lifecycle Redesign — Curative Mechanics for Session-Generated Artifacts
Status: DEFERRED
<!-- DEFERRED 2026-06-04 by stale-ACTIVE-plan cleanup. Design phase shipped (plan PR #15, ADR 037 + ADR 038 + root-cause discovery on HEAD). R-task roadmap mostly unbuilt (R3 pending-items-marker-convention.md and R5 docs-publish-on-stop.sh / published-docs-surfacer.sh absent; R1 session-wrap markers + R4 extract hook landed piecemeal). No commits in 9 days. RE-ENGAGE TRIGGER: when file-lifecycle implementation resumes — reconcile the piecemeal R1/R4 landings, flip back to ACTIVE, restore from archive. Reversible. -->
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; every file touched is under adapters/claude-code/ or neural-lace/conversation-tree-ui/. The "user" is the maintainer and each shipped mechanism's `--self-test` PASS is its acceptance artifact. No product UI surface exists.
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-07-01

<!-- This is a DESIGN-ONLY artifact. No implementation, no commits this session.
     R1–R5 below are gated on Misha's authorization + the open Decisions-for-Misha.
     `owner:`/`target-completion-date:` model the ADR-036-proposed schema (dogfood). -->

## Goal

Give session-generated files a codified, mechanically-enforced lifecycle so that
the four failures diagnosed in `docs/discoveries/2026-05-25-file-lifecycle-root-cause-chain.md`
become structurally impossible:

- **RC1** the `session-wrap.sh` `1666666 min` stale sentinel → Stop-hook loop (435× today);
- **RC2** durable deliverables written in worktrees stranded when the branch isn't merged;
- **RC3** Conv-Tree-populating scripts untracked (no history, wipeable);
- **RC4** pending items surfaced in chat never reaching the Conv Tree automatically.

The design is **curative not palliative** (produce the artifact / propagate the
file / mechanize the manual step — never silence a check or auto-defer) and
**mechanical not advisory** (a hook or a tracked tool, not a documented hope).

This is **Pattern 3 of 5** in the plan-lifecycle-redesign initiative. The parallel
session owns plan *closure* (ADR 036); this plan owns file *lifecycle*. Shared
surface: `session-wrap.sh`. Integration handled at landing time.

## Scope

- **IN:**
  - RC1: `session-wrap.sh cmd_refresh` create-on-missing-from-template + self-test.
  - RC2: `docs-publish-on-stop.sh` Stop hook + staging ledger + `published-docs-surfacer.sh` SessionStart surfacer + self-tests + settings wiring.
  - RC3: track `backfill-from-sessions.js` (after personal-path sanitization); retire `add-pending-items.js` instance; README breadcrumb note.
  - RC4: `pending-items-marker-convention.md` rule + `conversation-tree-extract-pending.sh` Stop hook + self-test + settings wiring.
  - The two ADRs (037, 038) and this discovery as the policy substrate.
- **OUT:**
  - Plan-closure machinery (owner/target-date enforcement, auto-closure, acceptance-scenario substance) — that is the parallel ADR-036 session. This plan does NOT touch `plan-reviewer.sh`, `plan-auto-closure.sh`, `product-acceptance-gate.sh`, or `close-plan.sh`.
  - The Signal-3 4h-window false-attribution issue (`2026-05-17` discovery) — a distinct `session-wrap` root cause (which commits count), not touched here.
  - Conv-Tree GUI/server/state-library changes (ADR-031/032 frozen A2 facade — called, never modified).
  - The `~/claude-projects/` hardcoded fallback (nervous-lehmann Gap 1) and the dispatch-mode auto-detect (Gap 4) — separate backlog items, not in this plan.
  - A transparent write-time path-redirect for RC2 — rejected as mechanically infeasible (ADR 037 Alternatives A).

## Tasks

- [ ] R1. `session-wrap.sh cmd_refresh` create-on-missing-from-template (RC1). — Verification: mechanical
  **Prove it works:** 1. In a temp git repo with NO `SCRATCHPAD.md`, run `session-wrap.sh refresh`. 2. Observe exit 0 AND a freshly-created `SCRATCHPAD.md` with the 30-line template stub. 3. Run `verify` → PASS (no `1666666 min` sentinel).
  **Wire checks:** `adapters/claude-code/scripts/session-wrap.sh` → `cmd_refresh` create branch (new) → `cmd_verify` Signal-1 reads the created file. (mechanical-tier: chain verified by the embedded `--self-test` S10/S11.)
  **Integration points:** n/a — single-script change; existing S1–S9 self-tests must still pass (regression).
- [ ] R2. Track `backfill-from-sessions.js`; sanitize personal-path comment; retire `add-pending-items.js`; add empty-tree README breadcrumb (RC3). — Verification: mechanical
  **Prove it works:** 1. `git ls-files neural-lace/conversation-tree-ui/scripts/backfill-from-sessions.js` returns the path. 2. `harness-hygiene-scan.sh --full-tree` returns no personal-path finding for it. 3. `add-pending-items.js` is absent from the tree (retired) or explicitly documented as superseded.
  **Wire checks:** n/a — file-tracking + doc change, no runtime code chain.
  **Integration points:** n/a.
- [ ] R3. `rules/pending-items-marker-convention.md` — the marker contract (ADR 038 D1). — Verification: mechanical
  **Prove it works:** 1. Rule file exists with the three marker headers + list-shape grammar + section-termination rules. 2. `definition-on-first-use-gate.sh` passes (no undefined acronyms). 3. The grammar is concrete enough that R4's parser self-tests reference it.
  **Wire checks:** n/a — doc-only; defines the contract R4 consumes.
  **Integration points:** n/a — must land before R4 (R4 depends on the written contract).
- [ ] R4. `conversation-tree-extract-pending.sh` Stop hook + ~14-scenario self-test + settings wiring (RC4, ADR 038 D2–D4). — Verification: full
  **Prove it works:**
  1. Pipe a transcript whose final assistant message has `**Questions for Misha**` + 2 bulleted items to the hook with `CONV_TREE_STATE_PATH` set to a temp sink.
  2. Read the sink via the state library; observe 2 `question-raised` items under the session's branch.
  3. Re-fire → still exactly 2 (idempotent).
  **Wire checks:**
  - `adapters/claude-code/hooks/conversation-tree-extract-pending.sh` parses `$TRANSCRIPT_PATH` final assistant message → `adapters/claude-code/hooks/conversation-tree-emit.sh` `--emit-item`
  - `adapters/claude-code/hooks/conversation-tree-emit.sh` `--emit-item` → `neural-lace/conversation-tree-ui/state/state.js` `appendEvent`
  **Integration points:**
  - `conversation-tree-emit.sh --emit-item`/`--emit-branch` (verify via the hook's own `--self-test`); `$TRANSCRIPT_PATH` JSONL shape (verify against a real session transcript by `head`).
- [ ] R5. `docs-publish-on-stop.sh` Stop hook + staging ledger + `published-docs-surfacer.sh` SessionStart surfacer + self-tests + settings wiring (RC2, ADR 037 D3). — Verification: full
  **Prove it works:**
  1. In a worktree off a temp main repo, write `docs/reviews/2026-05-25-test.md`.
  2. Run `docs-publish-on-stop.sh`.
  3. Observe the file copied into the MAIN checkout's `docs/reviews/` (copy-if-absent) AND a `~/.claude/state/published-docs/<sha>.json` ledger entry.
  4. Pre-place a different-content same-path file in main → observe NO overwrite + a surfacer entry instead.
  **Wire checks:**
  - `adapters/claude-code/hooks/docs-publish-on-stop.sh` resolves main via `git rev-parse --git-common-dir` → copy-if-absent into main `docs/reviews/` → ledger write `~/.claude/state/published-docs/`
  - `adapters/claude-code/hooks/published-docs-surfacer.sh` reads `~/.claude/state/published-docs/` ledger → emits SessionStart surfacer block
  **Integration points:**
  - the main-checkout resolution (verify with a real worktree via `git worktree add` in the self-test); composes with `git-discipline.md` Rule 2 (no conflict — copy-if-absent yields to merged copies).

## Files to Modify/Create

- `adapters/claude-code/scripts/session-wrap.sh` — R1: `cmd_refresh` create-on-missing branch + S10/S11 self-test scenarios. (Live mirror `~/.claude/scripts/session-wrap.sh` synced per harness-maintenance.md.)
- `neural-lace/conversation-tree-ui/scripts/backfill-from-sessions.js` — R3: sanitize header personal-path comment; then `git add` (track).
- `neural-lace/conversation-tree-ui/scripts/add-pending-items.js` — R3: retire (delete after R4 ships, or document as superseded; never tracked as-is).
- `neural-lace/conversation-tree-ui/scripts/README.md` — R3: one-line empty-tree breadcrumb (nervous-lehmann Gap 2, folded in cheaply).
- `adapters/claude-code/rules/pending-items-marker-convention.md` — R3/R4: NEW marker contract.
- `adapters/claude-code/hooks/conversation-tree-extract-pending.sh` — R4: NEW Stop hook.
- `adapters/claude-code/hooks/docs-publish-on-stop.sh` — R5: NEW Stop hook.
- `adapters/claude-code/hooks/published-docs-surfacer.sh` — R5: NEW SessionStart surfacer.
- `adapters/claude-code/settings.json.template` — R4+R5: wire the two new Stop hooks + the surfacer; sync to live `~/.claude/settings.json`.
- `docs/harness-architecture.md` — R4/R5: add rows for the 3 new hooks (docs-freshness-gate requires it).
- `docs/decisions/037-*.md`, `docs/decisions/038-*.md`, `docs/DECISIONS.md` — index rows (this session).

## In-flight scope updates
<!-- Add `- <date>: <path> — <reason>` lines here if a file enters scope during build. -->

## Assumptions

- `conversation-tree-emit.sh` `--emit-item`/`--emit-branch`/`--emit-details`/`--resolve-item` modes behave as their ST22–ST31 self-tests assert (verified present in the adapter copy this session).
- Claude Code PreToolUse hooks cannot mutate `tool_input` (basis for rejecting RC2 Approach A) — verified against the hook-output contract (allow/deny/context only).
- `$TRANSCRIPT_PATH` is set in Stop-hook context and points at the agent-uneditable session JSONL (same assumption the Gen-6 narrative-integrity hooks rely on).
- The main checkout is resolvable from a worktree via `git rev-parse --git-common-dir` → dirname (same pattern `_main_repo_root` and git-discipline Rule 2 use; ADR 028 confirms it for `session-wrap`).
- `SCRATCHPAD.md` lives in the parent checkout by convention (ADR 028); the create-on-missing target is therefore the parent root, and worktree sessions never strand ephemeral state.
- The marker convention's three labels match the shape orchestrators already emit (`**Questions/Action items/Decisions for Misha**`), so R3's contract codifies existing habit rather than imposing a new one.

## Edge Cases

- **RC1 race:** two sessions both find SCRATCHPAD missing → both create. Mitigation: atomic temp-then-rename, create-only-when-absent; identical static stub makes last-writer-wins harmless.
- **RC1 non-NL git repo:** a session in an unrelated git repo gets a SCRATCHPAD stub created. Acceptable (doctrine says every project maintains one; harmless 30-line file). Noted as the cost in ADR 037 D2.
- **RC2 same-path collision in main:** main already has `docs/reviews/X.md` with different content → copy-if-absent does NOT overwrite; the ledger + surfacer flag it for manual harvest.
- **RC2 main unresolvable:** session not in a worktree, or common-dir resolution fails → publish degrades to ledger-only; surfacer carries it forward. Never blocks Stop (writer hook).
- **RC2 the deliverable is also committed + merged later:** copy-if-absent yields to the merged copy (same path, real content via merge); no double-tracking.
- **RC4 marker in a code block / quoted context:** parser requires the header anchored on its own line + a following list; mid-prose / fenced mentions are not extracted (FP1/FP4 self-tests).
- **RC4 marker present, no items:** zero items extracted, no spurious node (FP2).
- **RC4 items already extracted a prior turn:** deterministic `item_id` + final-message-per-Stop scan → no double (FP3, idempotency).
- **RC4 no anchor branch yet:** hook lazily creates the per-session conversation-root via `--emit-branch` (D3).
- **RC4 no `$TRANSCRIPT_PATH` / no `jq` / no node:** silent no-op exit 0 (writer-hook failure isolation, mirrors `conversation-tree-emit.sh`).

## Testing Strategy

Each mechanism ships with a `--self-test` block (harness verification idiom). Per
risk-tiered-verification: R1–R3 are `Verification: mechanical` (structural,
self-test-attested); R4–R5 are `Verification: full` (runtime behavior against temp
sinks + synthetic worktrees, exercised by the self-tests, which ARE the runtime
exercise for harness mechanisms whose user is the maintainer).

### R1 — `session-wrap.sh` regression + new scenarios
- S10 (NEW): missing SCRATCHPAD + `refresh` → file created from template, exit 0, `verify` PASS (no sentinel).
- S11 (NEW): missing SCRATCHPAD + `refresh` twice → second run does NOT clobber the first (idempotent create).
- S1–S9 (existing) must still PASS (no regression to the fresh/stale/worktree/non-git paths).

### R4 — `conversation-tree-extract-pending.sh` self-test (the FP/FN matrix the brief asks for)

**False-positive guards (must extract NOTHING / not over-extract):**
- FP1 — `**Questions for Misha**` inside a fenced code block → 0 items.
- FP2 — header present, no list under it ("…: none this session") → 0 items, no spurious node.
- FP3 — same items in two consecutive turns' final messages → exactly-once (deterministic `item_id` + per-message scan; whitespace/case normalized before hashing).
- FP4 — the phrase appears mid-sentence in prose (not an anchored header) → 0 items.
- FP5 — a numbered list under an UNRELATED header (`## Files changed`) following the pending section → extractor stops at the section boundary, does not bleed.

**False-negative guards (must NOT miss a real marker):**
- FN1 — header variants: `**Questions for Misha**`, `**Questions for Misha:**`, `## Questions for Misha` → all matched.
- FN2 — list shapes `-`, `*`, `1.`, `1)` → all parsed.
- FN3 — only a subset of markers present (Questions only, no Decisions) → each independent.
- FN4 — case variance (`decisions for misha`) → matched (case-insensitive).
- FN5 — a wrapped multi-line item → captured whole.

**Structural guards:**
- ST-anchor — no prior branch → conversation-root lazily created via `--emit-branch`, items attached under it.
- ST-idem — 3 re-fires of the same final message → exactly the same item count.
- ST-iso — broken state-lib path / missing jq → exit 0, logged, never blocks Stop.

### R5 — `docs-publish-on-stop.sh` self-test
- PUB1 — worktree writes `docs/reviews/X.md` → copied into main copy-if-absent + ledger entry.
- PUB2 — main already has same-path different-content file → NOT overwritten; surfacer entry created.
- PUB3 — main unresolvable → ledger-only, exit 0.
- PUB4 — non-durable path (e.g. `src/foo.ts`) written in worktree → NOT published (scope is durable-doc classes only).
- PUB5 — `published-docs-surfacer.sh`: unacked ledger entry surfaces; acked entry does not.

## Walking Skeleton

R1 alone is the walking skeleton: a single end-to-end vertical slice (missing-file
→ refresh creates → verify passes → loop impossible) through the smallest mechanism,
shippable in one short session, immediately ending the active 435× bleed. Every
later R builds on the same "classify the file, back it with a mechanism" spine.

## Implementation Roadmap (ordered; small sessions)

| R | Scope | Tier | Depends on | Blast radius | Why this order |
|---|---|---|---|---|---|
| **R1** | `session-wrap.sh` create-on-missing | mechanical | — | tiny (one function) | Stops the active 435× loop. Cheapest. Ship first. |
| **R2** | track tool / retire instance / README | mechanical | — | tiny (tracking + sanitize) | Quick hygiene win; de-risks the manual-script dependency before RC4 replaces it. |
| **R3** | marker-convention rule (ADR 038 D1) | mechanical | — | doc-only | Defines the parser contract R4 needs. Must precede R4. |
| **R4** | extraction Stop hook + self-test + wiring | full | R3, `--emit-item` (shipped) | medium (new Stop hook, writer-class) | Delivers the high-value auto-population; retires `add-pending-items.js`. |
| **R5** | publish-on-stop + ledger + surfacer | full | — | **highest** (writes into operator's main working tree) | Riskiest; ship LAST; gated on Misha's B1-vs-B4 ack (Decision D-2 below). |

Each R is a self-contained session that ends with its mechanism's `--self-test`
green + the live mirror synced (`harness-maintenance.md`). R1–R3 can proceed on
authorization; R4 after R3; R5 after the open decision resolves.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — each RC's behavior change is cited at its Task entry's Wire checks + the matching Files-to-Modify row; 4 RCs, all 4 surfaced at both entry points.
S2 (Existing-Code-Claim Verification): swept — session-wrap.sh line 259 guard + line 128-136 sentinel verified by Read this session; emit-hook `--emit-item` modes verified present (ST22–ST31) by Read; git-tracking status verified by `git ls-files`/`git status`. All claims re-read against the actual files.
S3 (Cross-Section Consistency): swept — "copy-if-absent" / "writer-not-gate" / "curative-not-palliative" used consistently across plan + both ADRs + discovery; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept — `1666666` (=99999999/60), `30`-min Signal-1 threshold, `200`-char rich-detail threshold (referenced, not changed), `~14` self-test scenarios for R4. All values consistent across plan + ADRs + discovery.
S5 (Scope-vs-Analysis Check): swept — every "Add/Build" verb checked against Scope OUT; plan-closure machinery, Signal-3 attribution, GUI/state-lib, `~/claude-projects` fallback, dispatch-mode-detect, and write-time redirect are all explicitly OUT and none is prescribed IN. 0 contradictions.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
Within one session of R1 landing, a session that starts with no SCRATCHPAD ends
cleanly (exit 0, file created, zero loop iterations) instead of looping. Within one
session of R4 landing, an orchestrator that writes `**Questions for Misha**` + N
items sees N `question-raised` items appear in the Conv Tree "Waiting on you" pane
with NO manual script run. Within one session of R5 landing, a durable doc written
in a worktree is readable in the operator's main checkout `docs/reviews/` (or
surfaced for harvest) even when the worktree branch is never merged.

### 2. End-to-end trace with a concrete example
RC1: At T=0 a session starts in `~/dev/<consumer-org>/neural-lace` (no
SCRATCHPAD.md). Stop fires. `session-wrap.sh refresh` runs: `find_repo_root` →
parent root; `cmd_refresh` sees `! -f SCRATCHPAD.md` → writes the 30-line stub to a
temp file → `mv` into place (atomic) → appends the `<!-- session-wrap.sh: handoff
verified … -->` marker. `cmd_verify` Signal 1: `mtime_seconds_ago(SCRATCHPAD.md)` =
3s ≤ 1800 → PASS. Exit 0. The Stop hook does not re-prompt. Loop count: 0 (was 435).

RC4: At T=0 the orchestrator's final assistant message contains
`**Action items for Misha**\n- Set up ntfy.sh for phone notifications`. Stop fires.
`conversation-tree-extract-pending.sh` reads `$TRANSCRIPT_PATH`, isolates the final
assistant message, parses the `action` section → 1 item. Anchor: ledger has no
branch this session → emit `--emit-branch node_id=sess-<hash> title="<first task>"`.
Then pipe `{kind:action, node_id:sess-<hash>, item_id:sha1(sid|action|"set up
ntfy.sh…"), text:"Set up ntfy.sh…"}` to `conversation-tree-emit.sh --emit-item`. The
frozen facade appends `action-added`. The GUI (watching the main-checkout
tree-state.json) renders it in "Waiting on you". Exit 0.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| `cmd_refresh` (R1) | `cmd_verify` Signal 1 | After refresh, `SCRATCHPAD.md` exists at parent root with mtime < 30 min. |
| `conversation-tree-extract-pending.sh` (R4) | `conversation-tree-emit.sh --emit-item` | Emits one JSON `{kind∈{question,action,decision}, node_id, item_id, text}` per parsed item on stdin; reuses the frozen facade, never writes state directly. |
| marker-convention rule (R3) | the R4 parser | The three anchored headers + 4 list shapes + section-termination rules are the COMPLETE set the parser recognizes; items outside the shape are not extracted. |
| `docs-publish-on-stop.sh` (R5) | main checkout working tree + ledger | Copy-if-absent only; durable-doc path classes only; always write a `~/.claude/state/published-docs/<sha>.json` ledger entry; never overwrite; never block Stop. |
| `published-docs-surfacer.sh` (R5) | next SessionStart context | Emits a system-reminder block per unacked, un-auto-placed ledger entry; silent when none. |

### 4. Environment & execution context
Windows 11 + Git Bash; hooks run as `bash` subprocesses from the session cwd
(possibly a worktree). `jq`/`node` availability is not guaranteed (degraded-mode
fallback required, mirroring `conversation-tree-emit.sh`). `$TRANSCRIPT_PATH`,
`$CLAUDE_SESSION_ID`, `$CLAUDE_TOOL_INPUT` provided by Claude Code. State sinks:
the main-checkout `tree-state.json` (GUI) + the §5 gate path + `~/.claude/state/`
(ledgers). Live mirror `~/.claude/` is a COPY of `adapters/claude-code/` (no
symlinks on Windows) — every change synced both ways per harness-maintenance.md.

### 5. Authentication & authorization map
No external auth boundary. All three new hooks are writer-class (never gate, never
block) per gate-respect.md. Local-edit-gate governs `~/.claude/local/**` — not
touched. The publish hook writes into the operator's own main checkout (local
filesystem, no remote, no token). No credential surface.

### 6. Observability plan (built before the feature)
- R1: `cmd_refresh` logs `[session-wrap] created SCRATCHPAD.md from template (was missing)` when it creates.
- R4: `conversation-tree-extract-pending.sh` logs to `~/.claude/logs/conversation-tree-emit.log` (shared with the emit hook): `extracted N item(s) [Q:a A:b D:c] for session=<sid> anchor=<node>`.
- R5: `docs-publish-on-stop.sh` logs each file: `published <path> → main (copy-if-absent: placed|skipped-exists|main-unresolvable)`; ledger entry is itself the durable audit record.
- All three: failure-isolation log line on any caught error, then exit 0.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery |
|---|---|---|---|
| R1 create | parent root unresolvable | no SCRATCHPAD created | falls back to `verify` skip (non-git exit 0); no loop (the loop required an EXISTING-but-stale read — a never-resolvable repo already exits 0). |
| R1 create | disk write fails | stub absent | logged; `verify` Signal 1 still sentinel — but this is a genuine disk fault, not the missing-file false-positive; surfaces honestly. |
| R4 parse | malformed transcript JSONL | 0 items | silent no-op exit 0. |
| R4 emit | `--emit-item` rejects (facade invariant) | item not added | per-item logged, others proceed, exit 0. |
| R4 anchor | `--emit-branch` fails | items orphaned | logged; item still attempted at project/global root fallback. |
| R5 copy | same-path collision in main | not overwritten | ledger + surfacer flag for manual harvest. |
| R5 copy | main checkout on a conflicting branch | new untracked file appears | benign (untracked); operator sees it where they look. |

### 8. Idempotency & restart semantics
- R1: create-only-when-absent → re-run is a no-op (existing file freshened, not recreated).
- R4: deterministic `item_id` + final-message-per-Stop → re-fire emits the same ids, facade dedupes → exactly-once.
- R5: copy-if-absent + content-hash ledger key → re-publishing the same file is a no-op; a re-fired Stop does not duplicate.
- All Stop hooks: safe to fire multiple times per session (Claude Code may re-fire); each is idempotent by construction.

### 9. Load / capacity model
Negligible. R1: one `stat` + one small write per Stop. R4: one `jq` parse of the
final assistant message (bounded by message size) + N `--emit-item` subprocess
calls (N = pending items, typically <25). R5: one `git rev-parse` + a handful of
file copies (durable docs touched this session, typically <5). Bottleneck: the
per-item node subprocess in R4 (same cost profile as the existing emit hook, which
ships fine). No saturation risk at single-operator scale.

### 10. Decision records & runbook
ADRs 037 (policy + RC1/RC2/RC3) and 038 (RC4 marker + extraction) capture the
non-trivial choices with alternatives. Runbook:
- **Symptom: session loops on "1666666 min stale".** Pre-R1: `touch SCRATCHPAD.md`
  in the parent checkout to break the loop manually. Post-R1: cannot occur.
- **Symptom: a worktree deliverable is missing from main.** Pre-R5: read it by
  absolute worktree path; merge the branch. Post-R5: check `~/.claude/state/
  published-docs/` + the SessionStart surfacer.
- **Symptom: pending items not appearing in the Conv Tree.** Pre-R4: run the
  (retired) manual script. Post-R4: confirm the markers match the convention
  (R3 rule); check `conversation-tree-emit.log` for the extraction line.

## Decisions Log
[Populated during implementation per the Mid-Build Decision Protocol.]

### Decision: RC2 solved at session-end (publish), not write-time (redirect)
- **Tier:** 2
- **Status:** proceeded with recommendation (design)
- **Chosen:** publish-on-stop copy-if-absent (ADR 037 D3).
- **Alternatives:** transparent PreToolUse path-redirect (infeasible — hooks can't mutate tool_input); symlink (breaks worktree isolation).
- **Reasoning:** the only mechanically-possible curative; write-time redirect is not buildable.
- **To reverse:** delete `docs-publish-on-stop.sh` + unwire; no data loss (copy-if-absent never destroyed anything).

## Definition of Done
- [ ] R1–R5 tasks task-verified (each mechanism's `--self-test` green).
- [ ] Live mirror `~/.claude/` synced + `diff -q` clean for every touched file.
- [ ] `docs/harness-architecture.md` rows added for the 3 new hooks.
- [ ] `add-pending-items.js` retired; `backfill-from-sessions.js` tracked + hygiene-clean.
- [ ] SCRATCHPAD updated; this plan flipped to COMPLETED (auto-archives).

## Open Decisions for Misha (gate implementation)

- **D-1 (RC2 blast radius):** B1 (auto copy-if-absent into the main working tree — automatic, deliverable appears directly) vs B4 (staging-ledger + surfacer only — near-zero blast radius, requires a harvest action). Recommendation: the **hybrid** in ADR 037 D3 (auto-copy when safe, ledger backstop always). Confirm you're OK with worktree sessions writing new untracked files into your main checkout's `docs/`.
- **D-2 (RC4 anchor):** create the per-session conversation-root **lazily** (only when items are extracted — recommended, minimal) vs **proactively at SessionStart** for every Dispatch session (a small extension of ADR-034's Dispatch-only scope). Recommendation: lazy. Proactive only if you want every Dispatch session visible in the tree even with no pending items.
- **D-3 (R5 inclusion):** ship R5 at all, or defer it and rely on git-discipline Rule 2 (merge + main-pull) for worktree docs? Recommendation: ship R5 — the nervous-lehmann review proves Rule 2 is not reliably followed.
