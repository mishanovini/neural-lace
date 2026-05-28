# Plan: D8 + D9 + D10 — Principles Wiring + Sync + Gate Tightening
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: build-harness-infrastructure
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanisms; self-tests + live invocation are the acceptance artifacts; no product user runtime to advocate for
Backlog items absorbed: none

## Goal

Three Misha-directed deliverables, all touching the principles substrate:

- **D8** — explicitly wire `~/.claude/rules/principles.md` into `CLAUDE.md` via top-of-file section + @-reference + Detailed Protocols entry. Currently principles.md exists and is auto-loaded but CLAUDE.md doesn't reference it; the explicit wiring closes the documentation drift.
- **D9** — install-time sync from principles.md → personal-memory directories. Add a phase to `install.sh` that reads `~/.claude/local/personal-memory-paths.txt` and copies principles.md content into `principles_canonical.md` at each listed path with an auto-generated header marker. Keeps the personal-memory mirror in sync with the canonical source.
- **D10** — flip `principles-compliance-gate.sh` from warn-only to mixed-mode. R4 (false-binary), R5 (done-without-SHA), R7 (promise-without-mechanism) BLOCK Stop. R3 (multi-option question) stays warn-only BUT in block-mode emits an in-band alert marker to `~/.claude/state/external-monitor-alerts/` which the SessionStart `external-monitor-alert-surfacer.sh` hook surfaces at next interactive session. Mode flipped via `~/.claude/local/principles-gate-mode = block`.

## Scope

- IN: CLAUDE.md edits, install.sh sync phase, gate R3 alert path, mode-file write.
- OUT: writing self-test for the in-band notification path itself (smoke-tested manually; the existing 10-scenario detection self-test covers detection unchanged); changing R3 detection logic (the heuristic stays).

## Tasks

- [x] 1. Add `## Operating Principles` section + Detailed Protocols entry to `adapters/claude-code/CLAUDE.md`; sync to live mirror — Verification: mechanical
- [x] 2. Create `adapters/claude-code/examples/personal-memory-paths.example.txt` with format docs + example shapes — Verification: mechanical
- [x] 3. Add personal-memory sync phase to `install.sh`; seed config from example on first install — Verification: mechanical
- [x] 4. Live first sync: copy principles.md into the agent-mode memory dir as `principles_canonical.md` (240-line file written) — Verification: mechanical
- [x] 5. Populate `~/.claude/local/personal-memory-paths.txt` with the active personal-memory path — Verification: mechanical
- [x] 6. Modify `principles-compliance-gate.sh` to emit R3-only external-monitor-alert marker when R3 fires in block-mode — Verification: mechanical
- [x] 7. Smoke-test R3 alert emission end-to-end with a transcript fixture — Verification: mechanical
- [x] 8. Flip mode: write `block` to `~/.claude/local/principles-gate-mode` — Verification: mechanical
- [x] 9. Sync gate to live mirror byte-identical — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/CLAUDE.md` — add `## Operating Principles` section + Detailed Protocols entry pointing at principles.md
- `adapters/claude-code/install.sh` — new personal-memory sync phase
- `adapters/claude-code/examples/personal-memory-paths.example.txt` — NEW; format example
- `adapters/claude-code/hooks/principles-compliance-gate.sh` — R3 in-band alert emission in block-mode
- `docs/plans/d8-d9-d10-principles-wiring-2026-05-28.md` — THIS plan file

## In-flight scope updates

(none)

## Walking Skeleton

CLAUDE.md edit + install.sh phase + gate alert path each independently slice through the harness. CLAUDE.md ships explicit principles reference; install.sh sync becomes idempotent (runs on every install, no manual step beyond config); gate produces alert markers that compose with the already-wired external-monitor-alert-surfacer. Self-tests on the gate detection remain 10/10 PASS.

## Acceptance Scenarios

acceptance-exempt: true. Each artifact's `--self-test` PASS + the live smoke-test of the R3 alert emission are the harness-internal acceptance artifacts. No product user runtime applicable.

## Testing Strategy

- `principles-compliance-gate.sh --self-test` → 10/10 PASS (confirmed)
- Live smoke-test of R3 in-band alert: transcript fixture with R3-triggering content + PRINCIPLES_GATE_MODE=block → alert JSON file written (confirmed)
- install.sh syntax check via `bash -n` → PASS (confirmed)
- Isolated sync-phase test: synthetic config + synthetic target dir → principles_canonical.md generated with correct header (confirmed)
- Live first sync: 240-line file written to the agent-mode memory dir (confirmed)

## Decisions Log

### Decision: R3 stays warn-only but with in-band notification via external-monitor-alert
- **Tier:** 1
- **Status:** Misha-directed
- **Chosen:** Keep R3 warn-only (cannot mechanically judge "is one option clearly principled?") but emit an in-band notification marker when R3 fires in block-mode. The marker surfaces at next SessionStart via the already-wired external-monitor-alert-surfacer.sh.
- **Alternatives:**
  - Block on R3 → REJECTED: high false-positive rate (warn log shows 9 legitimate R3 firings across recent sessions where decision-surfacing was correct)
  - Stay warn-only with no surface change → REJECTED: per Misha + in-band-friction principle, log-only ceremony doesn't change behavior
- **Reasoning:** the alert marker provides delayed-but-real in-band feedback at next session start without blocking the current session. Composes with the alert surfacing chain shipped earlier today.

### Decision: install.sh writes principles_canonical.md, NOT overwriting feedback_dispatch_operating_rules.md
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** New separate file at the target dir, leaving any existing personal-memory file unchanged.
- **Alternatives:** overwrite the personal-memory file with principles.md content
- **Reasoning:** the personal memory file (`feedback_dispatch_operating_rules.md`) has user-specific framing ("anti-patterns I do that this catches") that principles.md doesn't carry. Separating the auto-synced canonical from the user-edited personal file preserves both characters and avoids destructive overwrite.

## Definition of Done

- [x] All tasks checked off
- [x] All self-tests PASS
- [x] Live mirror synced byte-identical
- [x] Personal memory first-sync done (240-line file present)
- [x] Mode flipped to "block" + verified
- [x] PR opened + merged
