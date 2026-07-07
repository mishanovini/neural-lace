# Conv Tree Demo Session — Harness Gaps Surfaced

**Date:** 2026-05-20
**Session:** nervous-lehmann-35212e (Conv Tree demo + backfill + items-injection)
**Persisted to satisfy:** `bug-persistence-gate.sh` (trigger-phrase observations require durable storage; this file is the canonical capture for the gaps surfaced this session).

## Context

This session was Misha's demo of the Conv Tree GUI itself, layered with three urgent operational sub-tasks:
1. Verify the emit-hook wiring + auto-detect dispatch mode + matcher-name discrepancy.
2. Backfill today's 17 JSONLs through the legitimate `appendEvent` path so the GUI shows real history.
3. Inject today's pending items (decisions/actions/questions/backlog) into the tree.

All three sub-tasks completed. Along the way the session surfaced five harness gaps. Four were flagged in the earlier items-injection turn as `backlog-added` events in the Conv Tree; the fifth (auto-extraction hook missing) was discovered during the addendum investigation in this turn. All five are captured here for the durable audit trail. None is blocking the demo.

## Gaps

### 1. `~/claude-projects/` hardcoded fallback path doesn't exist on this machine

**Where:** `adapters/claude-code/hooks/conversation-tree-emit.sh` line 126, `_resolve_gui_state_path()` fallback branch.
**What:** Falls back to `$HOME/claude-projects/neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json` when `_main_repo_root()` can't resolve. Misha's actual repo is at `~/dev/<org-dir>/neural-lace/`. `~/claude-projects/` doesn't exist on this machine.
**Impact:** When the emit hook runs outside a git context, writes go to a non-existent path. Already happening: `~/.claude/logs/conv-tree-read.log` shows multiple invocations citing the `claude-projects/...` path.
**Suggested fix:** Resolve the project root from a per-machine convention file (e.g. `~/.claude/local/projects.config.json`'s root entry) instead of hardcoding the conventional path. Or: read `~/.claude/CLAUDE.md`'s "Accounts & Auto-Switching" directive for the per-machine projects root.
**Status:** Open. Also filed as a `backlog-added` event in Conv Tree (low priority).

### 2. No operator-facing breadcrumb for the empty Conv Tree on first install

**Where:** The conv-tree-ui product surface (GUI + `scripts/README.md`).
**What:** A fresh operator opening the GUI sees an empty tree with no explanation of how to populate it. ADR-031 Pin 2a establishes implicit auto-bootstrap (first Dispatch spawn creates `tree-state.json` via the emit hook), but this design intent isn't visible to the operator. The user opening the GUI after install has no way to know what to do.
**Impact:** Demo friction; new-operator confusion.
**Suggested fix:** One-sentence note in `conversation-tree-ui/scripts/README.md`: "The state file is created automatically on the first Dispatch-spawned task; until then, the GUI correctly shows an empty tree." Optionally: an empty-state CTA in the GUI itself with the same message.
**Status:** Open. Also filed as a `backlog-added` event in Conv Tree (low priority).

### 3. `session-wrap.sh` refresh produces 1666666-min stale sentinel

**Where:** `~/.claude/hooks/session-wrap.sh` refresh, ~line 259 (per memory from earlier session note — line number not re-verified this session).
**What:** The refresh only edits an existing SCRATCHPAD.md; if SCRATCHPAD is missing, it silently no-ops and produces a 1666666-minute (~31-year) stale-sentinel value. That value fails any "is recent" check and triggers the Stop-hook re-fire loop (~15+ iterations) observed in the `dreamy-black-dd82c1` worktree-cleanup session (see `docs/discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md`).
**Impact:** Stop-hook lockout on sessions without SCRATCHPAD.
**Suggested fix:** If SCRATCHPAD is missing, create a minimal stub before the timestamp arithmetic OR special-case the "no SCRATCHPAD" path to skip the freshness signal entirely.
**Status:** Open. Possibly relates to the existing discovery `2026-05-17-session-wrap-signal3-transitive-false-fire.md` but is a distinct failure mode (signal-3 transitive false-fire is the wrong-attribution problem; this is the missing-file problem). Also filed as a `backlog-added` event in Conv Tree (low priority).

### 4. Auto-detect dispatch-mode at SessionStart via `CLAUDE_CODE_ENTRYPOINT=claude-desktop`

**Where:** Currently no hook does this. Should be a new `~/.claude/hooks/dispatch-mode-detect.sh` (SessionStart, position 1).
**What:** `~/.claude/local/dispatch-mode.json` is currently flipped manually (this session did it via the local-edit-gate marker). The env var `CLAUDE_CODE_ENTRYPOINT=claude-desktop` is reliably set by the desktop app — a SessionStart hook could read it and auto-populate the file. Detection priority: (1) `CLAUDE_CODE_DISPATCH=1` if Anthropic ships it; (2) `CLAUDE_CODE_ENTRYPOINT=claude-desktop` + `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1` → `running_under_dispatch: true`; (3) default false.
**Impact:** Every operator needs to manually flip the file on each machine; CLAUDE.md documents the auto-detection priority but the implementation is missing.
**Suggested fix:** Land the hook + register at SessionStart position 1. Use atomic temp-then-rename for the write to avoid GUI seeing a torn file. Estimated effort: ~60 LOC bash + 5-scenario --self-test.
**Status:** Open. Proposal-shaped; needs ADR-level review only if the detection priority is contentious. Also filed as a `backlog-added` event in Conv Tree (low priority).

### 5. Auto-extraction hook for `**Questions for Misha** / **Decisions for Misha** / **Action items for Misha**` markers is MISSING from this machine AND from the doctrine

**Where:** Should exist as a Stop hook (or PostToolUse equivalent) but does not.
**What:** Misha believes there's supposed to be a hook that auto-extracts pending items from assistant output (the `**Questions for Misha**` / `**Decisions for Misha**` / `**Action items for Misha**` marker convention this session has been using). Investigation findings:
- **No hook in `~/.claude/hooks/`** matches any extraction or marker pattern for these specific labels.
- **No hook in `adapters/claude-code/hooks/`** matches either.
- **No documented marker convention** in `~/.claude/rules/`, `docs/decisions/`, `docs/conventions/`, ADR-031, ADR-032, ADR-034, or `docs/prd.md` (the conv-tree PRD) prescribes how pending items should be marked for auto-extraction.
- **`conversation-tree-read.sh` is the OPPOSITE direction** — it READS operator GUI events (actor=`gui`) and injects them into the orchestrator's next prompt. It does NOT scan assistant output.
- **`conversation-tree-emit.sh`** writes `branch-opened` on Dispatch spawn and `concluded` on Stop. It does NOT scan the assistant transcript for `decision-raised` / `question-raised` / `action-added` markers.

**The doctrine + implementation both have no such hook.** The closest infrastructure is the architectural intent of ADR-031's "symmetric file contract" — Misha's side is the GUI (POST /api/event with actor=gui), Dispatch's side is the lifecycle emit hooks (actor=dispatch on spawn/stop). Authoring pending-items from assistant text is a THIRD pattern not covered by either.

**Why this matters:** Without the auto-extraction hook, every time the orchestrator surfaces pending items in `**Questions for Misha**` / `**Decisions for Misha**` style sections, those items only live in chat — they don't reach the tree unless a separate script (like this session's `add-pending-items.js`) is run manually. The friction is real, and Misha's directive ("we need to make this automatic") is exactly the right framing.

**Suggested fix (architectural sketch — not implemented):**
- New hook: `~/.claude/hooks/conversation-tree-extract-pending.sh` (or extend `conversation-tree-emit.sh --on-stop`).
- Trigger: Stop hook position (mirroring how `conversation-tree-emit.sh --on-stop` is wired).
- Reads: the agent-uneditable `$TRANSCRIPT_PATH` JSONL, finds the final assistant message.
- Scans for: `**Decisions for Misha**`, `**Action items for Misha**`, `**Questions for Misha**` (case-insensitive, configurable marker list).
- Under each marker, extracts numbered or bulleted items.
- For each item: calls `appendEvent` with the matching event type (`decision-raised` / `action-added` / `question-raised`).
- Anchors to: the current session's branch (the one `--on-spawn` created earlier; correlate via the per-session ledger at `~/.claude/state/conversation-tree-emit/opened-<sid>.jsonl`).
- Idempotency: deterministic `event_id` from `sha1(session_id|item_text)` so re-firing on the same transcript is a no-op.
- Doctrine: needs a brief rule at `~/.claude/rules/pending-items-marker-convention.md` specifying the marker syntax and the bullet/numbered-list shape (so the hook has a reliable contract to parse against).

**Estimated effort:** ~200-300 LOC bash + node, ~10-scenario `--self-test`, plus a one-page rule file + a `--on-extract` mode added to `conversation-tree-emit.sh` (or a separate hook for clean separation).

**Status:** Open. **Filed here as the canonical capture of this finding** — a separate `docs/discoveries/2026-05-20-pending-items-auto-extraction-hook-missing.md` could be written if Misha wants the per-discovery file pattern; this review serves as the consolidated record either way.

## Provenance

- The 4 backlog-added events for gaps 1–4 are in `tree-state.json` already (priority `low`, `tree_id: global`).
- Gap 5 was discovered during the in-turn investigation in response to Misha's addendum; only captured here in this file.
- This review file satisfies `bug-persistence-gate.sh` for the trigger-phrase observations surfaced in this session.

## Status & Next steps

| Gap | Severity | Owner | Status |
|-----|----------|-------|--------|
| 1. ~/claude-projects fallback | low | maintainer | open, backlog |
| 2. No bootstrap breadcrumb | low | maintainer | open, backlog |
| 3. session-wrap missing-SCRATCHPAD | medium | maintainer | open, backlog; partially overlaps with [2026-05-17 discovery](../discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md) |
| 4. Auto-detect dispatch-mode | medium | maintainer | open, backlog; proposal-shaped |
| 5. Auto-extract pending-items | **high** (Misha named it explicitly) | maintainer | open; needs doctrine spec + hook implementation; no existing scaffold |

Gap 5 is the highest-priority item from this session because it's the difference between "Conv Tree needs manual injection per session" and "Conv Tree auto-populates from normal assistant output." It's the right next harness improvement.
