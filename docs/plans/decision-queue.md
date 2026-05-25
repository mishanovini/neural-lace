# Plan: Decision Queue substrate (throughput-bottleneck-reducer)

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
shape: build-harness-infrastructure
tier: 2
rung: 1
architecture: substrate-plus-tooling
frozen: false
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal substrate; self-tests are the acceptance artifact; user-facing surface (Conv Tree Decisions panel) lands in a separate session that owns the conv-tree-ui codebase
Backlog items absorbed: none

## Goal

Build a persistent Decision Queue infrastructure so Dispatch can hand Misha a prioritized, structured queue of decisions instead of dumping unsorted asks in chat. Each item carries enough context (recommendation, counterargument, deferral cost, downstream impact, mode flag, dependencies, source link) that Misha can resolve it without re-loading context. Dispatch (and the daily harness evaluator) can highlight items to draw attention to the most-blocking ones.

Misha is the throughput bottleneck; this substrate exists to reduce the per-decision cost on his side and surface the *right* decisions first.

## User-facing Outcome

After this plan ships:
- Misha can read the current decision queue (CLI + the Conv Tree Decisions panel that lands separately) and see, for each item: the question, Dispatch's recommendation with rationale, the counterargument, what waits if he defers, downstream impact, source links.
- Dispatch (any agent session) can add a decision item, list pending items, close one with Misha's answer, and highlight an item with a human-readable reason — via the shell wrapper script.
- The daily harness evaluator's recommendations land in the queue automatically (no longer require Misha to scrape them from the daily packet).
- Highlighted items render with visual emphasis in the Conv Tree (the panel itself ships in the follow-on session).

## Scope

- IN: JSON schema for queue items; shell storage script with add/list/get/close/update/highlight/unhighlight + self-test; live state at `~/.claude/state/decision-queue/`; Dispatch calling-convention doc; harness-evaluator.sh extension that writes recommendations into the queue; Conv Tree Decisions panel spec doc (handoff to follow-on session).
- OUT: the Conv Tree Decisions panel implementation itself (lives in `conversation-tree-ui/`, which is on a different branch and has an in-flight UX redesign in another session). Out: auto-emit-to-conv-tree wiring of decision-queue operations (deferred — requires extension to `conversation-tree-emit.sh`'s tool-surface matrix; documented as follow-up).

## Files to Modify/Create

- `docs/plans/decision-queue.md` — this plan file.
- `docs/decisions/036-decision-queue-substrate.md` — ADR locking the substrate decisions (per-machine vs in-repo, file format, schema field set, priority-score formula v1, Mechanism vs Pattern split).
- `docs/DECISIONS.md` — index row for the new ADR.
- `adapters/claude-code/schemas/decision-queue.schema.json` — JSON Schema 2020-12 for queue items. Single source of truth for the item shape.
- `adapters/claude-code/scripts/decision-queue.sh` — storage layer: add | list | get | close | update | highlight | unhighlight | --self-test. Writes to `~/.claude/state/decision-queue/queue.json` (computed view) + `queue.audit.jsonl` (append-only audit log).
- `docs/dispatch-decision-queue-tools.md` — Dispatch-facing calling convention: how to invoke each subcommand from Bash, expected JSON shapes, exit codes, when to use each mode (QUICK / PICK / DEEP), when to highlight.
- `docs/conv-tree-decisions-panel-spec.md` — self-contained spec for the Conv Tree Decisions panel (Task B handoff): server API endpoints to add, frontend panel layout, per-mode reply UI, highlight rendering, source-doc link handling. The next session running on a worktree with `conversation-tree-ui/` can implement directly from this spec.
- `adapters/claude-code/scripts/harness-eval-decision-queue-bridge.sh` — self-contained bridge from harness-evaluator recommendations into the Decision Queue. Ships on this branch; activation via one-line addition to `harness-evaluator.sh` deferred until the `feat/drift-backlog-and-harness-evaluator` branch (which is where `harness-evaluator.sh` lives) lands on master.
- `docs/harness-architecture.md` — inventory rows for the new schema + two scripts.
- `docs/DECISIONS.md` — index row for ADR-036.

## In-flight scope updates

(populated if scope expands mid-build)

## Tasks

- [ ] 1. ADR-036 + plan + index row landed — Verification: mechanical
  - **Prove it works:** `[ -f docs/decisions/036-decision-queue-substrate.md ] && grep -q "036" docs/DECISIONS.md && [ -f docs/plans/decision-queue.md ]`
  - **Wire checks:** `docs/decisions/036-decision-queue-substrate.md` → `docs/DECISIONS.md` (index row references the ADR number) → `docs/plans/decision-queue.md` (this plan, Decisions Log entry will cite the ADR)
  - **Integration points:** n/a — standalone documentation task with no cross-component coupling.

- [ ] 2. `decision-queue.schema.json` lands and self-validates — Verification: mechanical
  - **Prove it works:** `jq empty adapters/claude-code/schemas/decision-queue.schema.json && jq -e '.["$schema"] and .required and .properties.id and .properties.highlighted' adapters/claude-code/schemas/decision-queue.schema.json`
  - **Wire checks:** `adapters/claude-code/schemas/decision-queue.schema.json` → declares `"$schema": "https://json-schema.org/draft/2020-12/schema"` → required fields per spec
  - **Integration points:** consumed by `decision-queue.sh` for validation on `add` / `update`; consumed by `conv-tree-decisions-panel-spec.md` as the contract for the UI panel.

- [ ] 3. `decision-queue.sh` storage script lands with full subcommand surface and --self-test PASS — Verification: mechanical
  - **Prove it works:** `bash adapters/claude-code/scripts/decision-queue.sh --self-test` exits 0 with all scenarios PASS
  - **Wire checks:** `adapters/claude-code/scripts/decision-queue.sh` (`add`, `list`, `get`, `close`, `update`, `highlight`, `unhighlight`, `--self-test` subcommands) → `~/.claude/state/decision-queue/queue.json` (write) → `~/.claude/state/decision-queue/queue.audit.jsonl` (append) → `adapters/claude-code/schemas/decision-queue.schema.json` (validates each item on add/update via `jq`)
  - **Integration points:** invoked by Dispatch agents, harness-evaluator.sh, and (via API) the Conv Tree server.

- [ ] 4. `dispatch-decision-queue-tools.md` doc lands — Verification: mechanical
  - **Prove it works:** `[ -f docs/dispatch-decision-queue-tools.md ] && grep -q "decision-queue.sh add" docs/dispatch-decision-queue-tools.md && grep -q "highlight" docs/dispatch-decision-queue-tools.md && grep -q "QUICK\|PICK\|DEEP" docs/dispatch-decision-queue-tools.md`
  - **Wire checks:** `docs/dispatch-decision-queue-tools.md` → `adapters/claude-code/scripts/decision-queue.sh` (every documented invocation matches a real subcommand)
  - **Integration points:** Dispatch (cloud-side orchestrator) reads this doc to know the calling convention; humans read it to debug.

- [ ] 5. `conv-tree-decisions-panel-spec.md` handoff doc lands — Verification: mechanical
  - **Prove it works:** `[ -f docs/conv-tree-decisions-panel-spec.md ] && grep -q "Decisions panel" docs/conv-tree-decisions-panel-spec.md && grep -q "highlight" docs/conv-tree-decisions-panel-spec.md && grep -q "QUICK\|PICK\|DEEP" docs/conv-tree-decisions-panel-spec.md && grep -q "/api/" docs/conv-tree-decisions-panel-spec.md`
  - **Wire checks:** `docs/conv-tree-decisions-panel-spec.md` → references `adapters/claude-code/schemas/decision-queue.schema.json` (the item contract) → references `adapters/claude-code/scripts/decision-queue.sh` (the storage layer the server proxies to)
  - **Integration points:** consumed by the next session that owns the `conversation-tree-ui/` worktree.

- [ ] 6. `harness-evaluator.sh` writes recommendations into the queue — Verification: mechanical
  - **Prove it works:** `grep -q "decision-queue.sh add" adapters/claude-code/scripts/harness-evaluator.sh && bash adapters/claude-code/scripts/harness-evaluator.sh --self-test` exits 0 (the existing self-test continues to pass after the extension)
  - **Wire checks:** `adapters/claude-code/scripts/harness-evaluator.sh` (extension block) → `adapters/claude-code/scripts/decision-queue.sh add` (writes each recommendation as a decision item) → `adapters/claude-code/scripts/decision-queue.sh highlight` (called for any recommendation flagged high-severity)
  - **Integration points:** the daily packet is unchanged (still written to `docs/reviews/`); the queue surface is additive.

- [ ] 7. Branch pushed and PR opened against master — Verification: mechanical
  - **Prove it works:** PR URL exists and the PR is open against master (not merged); `gh pr view --json url,state,baseRefName | jq -e '.state == "OPEN" and .baseRefName == "master"'`
  - **Wire checks:** `feat/decision-queue` branch → origin (pushed) → PR (open)
  - **Integration points:** Misha reviews and decides whether to merge; per hard rules no merge from this session.

## Decisions Log

(populated during build per Tier 2+ decisions, with cross-reference to `docs/decisions/036-decision-queue-substrate.md`)

## Evidence Log

(populated by task-verifier — for this plan, each task's mechanical PASS is the evidence)

## Walking Skeleton

The vertical slice that proves the substrate end-to-end before the UI panel lands:

1. `decision-queue.sh add` creates an item from CLI flags → file at `~/.claude/state/decision-queue/queue.json` contains the item, validates against the schema, gets a UUID + timestamps.
2. `decision-queue.sh list --state open --format json` returns the item.
3. `decision-queue.sh highlight <id> --reason "blocks 8 other items" --level strong` updates the item's `highlighted`/`highlight_reason`/`highlight_level` + appends to `highlight_history`.
4. `decision-queue.sh close <id> --answer "go with option A" --by user` flips `state` to `answered`, sets `closed_at`, records `answer` + `answer_by`.
5. All five operations are exercised by `--self-test` and each passes against a synthetic `XDG_STATE_HOME` so the self-test does not touch the user's real queue.

This walking skeleton IS what the Conv Tree Decisions panel renders from. The panel is rendering; the substrate is what makes the data exist.

## Definition of Done

- [ ] All 7 tasks checked off via task-verifier or close-plan.sh
- [ ] `decision-queue.sh --self-test` PASSes locally
- [ ] `harness-evaluator.sh --self-test` PASSes locally (existing tests still green after extension)
- [ ] Branch pushed + PR opened against master (no merge)
- [ ] SCRATCHPAD.md updated to reflect the new substrate
- [ ] Completion report appended to this plan file
- [ ] Status: COMPLETED (triggers auto-archival)
