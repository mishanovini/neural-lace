# Plan: Conv-Tree GUI — fix stacked toast notifications
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
tier: 1
rung: 1
architecture: client-side-js
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Local GUI polish for the operator's tracker app; no external product user. Self-tests + Misha's morning PR review against the live GUI are the acceptance artifact.

## Goal

The conv-tree GUI's `pushNote()` notifications system creates a new `.note` element for every event (branch-concluded / deferred-due / action-ready) and persists each one until manually dismissed. Misha's screenshots showed 8-10 stacked "Branch X concluded — parent Y notified" toasts accumulating in the right-side note-stack. Fix: add auto-dismiss for non-hot notes, cap visible count, and collapse similar notifications by parent.

## Scope

- IN: refactor of `pushNote()` in `neural-lace/conversation-tree-ui/web/app.js`; CSS-free (no `app.css` touch); new structural-shape assertions in `web/responsive.selftest.js`.
- OUT: changes to the `snackbar()` / `toast` system (separate single-toast element, not the stacking issue); changes to the underlying event firing logic (`detectConcludeNotifications` / `checkDefers` — they still fire once per node, the change is purely client-side rendering); deferred-due notifications (kept `hot: true` — they represent action items the user must act on, so they correctly persist).

## Tasks

- [x] 1. Refactor `pushNote(key, msg, hot)` in `web/app.js` to accept an options object as the third argument: `{ hot, groupKey, groupRender, durationMs }`. Backward-compat: a boolean third-arg still works (treated as `{hot: bool}`). Implement: auto-dismiss timer (5s default for non-hot; never for hot); visible-cap helper (max 3 non-hot in the DOM; hot always persists); group-by-key collapse (existing data-group element gets count+1 and groupRender refreshes the body). Update the `detectConcludeNotifications` call site to pass `groupKey: 'concl-parent-<parent_id>'` with a groupRender that produces "N branches under 'X' concluded — most recent: 'Y'". The `act-*` and `defer-*` call sites stay as-is (boolean third arg → backward-compat path). — Verification: mechanical

- [x] 2. Add 7 structural-shape regression tests (R71-R77) to `web/responsive.selftest.js` locking the four pushNote invariants (constants present, signature accepts options, auto-dismiss for non-hot only, cap walks .note children, group-by-key collapses via data-group/data-count, concluded notifications use the parent-keyed group, note body lives in a `.note-body` child). Run the full suite; confirm 77/77 PASS. — Verification: mechanical

## Files to Modify/Create

- `neural-lace/conversation-tree-ui/web/app.js` — pushNote refactor (+ helper functions `_scheduleAutoDismiss`, `_enforceCap`); detectConcludeNotifications call-site adapted to pass groupKey+groupRender.
- `neural-lace/conversation-tree-ui/web/responsive.selftest.js` — R71-R77 toast-fix invariants appended.
- `docs/plans/conv-tree-toast-stacking-2026-05-23.md` — this plan file (self-claiming for the scope-enforcement-gate).

## Assumptions

- `pushNote` is only called from inside `app.js` (the IIFE) and is not part of the public API surface; refactoring its signature is safe because no external module depends on it.
- The existing CSS for `.note-stack` (`position: fixed; flex-direction: column; gap: 0.4rem; max-width: 22rem`) renders the stack acceptably for cap=3 visible notes. No CSS changes needed.
- The "hot" classification on call sites maps correctly to user-action-required: `defer-*` (deferred items due) = hot=true → persists; `act-*` (action ready to start in Dispatch) and `concl-*` (branch concluded) = hot=false → auto-dismiss after 5s.
- Misha will refresh the browser tab to load the modified `app.js`; the running node server (port 7733) serves the file directly with no caching/build step.

## Edge Cases

- **Auto-dismiss fires after manual dismiss:** `closeToast` clears the timeout via `clearTimeout(nd._t)` before removing the node. Defensive check `if (nd.parentNode)` in the timer callback prevents double-remove crashes.
- **Group-render closure capturing wrong title:** each `pushNote` invocation captures `branchTitle` in its own groupRender closure scope; subsequent calls use THIS invocation's groupRender (pulled from the new options object), so the "most recent: Y" correctly reflects the latest branch.
- **Cap eviction of a manually-dismissed note:** the `_enforceCap` helper walks live DOM children; manually-dismissed notes are already removed, so the cap walk only sees still-visible notes.
- **Hot note count vs cap:** if a user has 4 hot deferred-due notes pending action, the cap doesn't evict them — hot notes are excluded from the cap and always persist.
- **Reload-page resets:** `dismissed` Set is in-memory; on reload, previously-dismissed notes re-fire if `seenConcluded` / `firedDefers` Sets haven't recorded them yet. The per-event Sets at the call sites (`seenConcluded` for concluded, `firedDefers` for defers in localStorage) prevent re-firing per node. Out of scope to change.

## Testing Strategy

Mechanical:
- `node --check neural-lace/conversation-tree-ui/web/app.js` exits 0.
- `node neural-lace/conversation-tree-ui/web/responsive.selftest.js` reports 77/77 PASS (was 70/70; +7 new).
- `node neural-lace/conversation-tree-ui/state/selftest.js` reports 17/17 PASS (regression check — should be unchanged).
- `curl -s http://127.0.0.1:7733/app.js | grep -c NOTE_AUTO_DISMISS_MS` ≥ 1 (server serves modified file).

Runtime (manual, Misha PR review):
- Open `http://127.0.0.1:7733/`; refresh to load new `app.js`.
- Open browser dev console; paste `for (var i = 0; i < 8; i++) pushNote('test-' + i, 'Test toast ' + i + ' — should auto-dismiss in 5s', false);` to inject 8 non-hot notes.
- Expect: only 3 visible at a time (older ones drop off the top of the stack); all dismiss after ~5s; manual ✕ button works to dismiss earlier.
- Paste `for (var i = 0; i < 5; i++) pushNote('group-' + i, 'Branch "B' + i + '" concluded — parent "X" notified.', { hot: false, groupKey: 'concl-parent-X', groupRender: function (count, latest) { return count + ' branches under "X" concluded — most recent: "B' + (count-1) + '"'; } });` to test grouping.
- Expect: single note shows "5 branches under 'X' concluded — most recent: 'B4'".

## Walking Skeleton

The skeleton is the pushNote refactor itself: each layer (auto-dismiss timer, visible-cap, group-by-key) is independently functional and additive. The simplest end-to-end slice (non-hot note → auto-dismiss after 5s) works without the other two layers; group-by-key composes on top without disturbing auto-dismiss; cap-3 composes on top without disturbing grouping.

## Decisions Log

### Decision: Hot notes persist; cap is non-hot only.
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `_enforceCap` counts only non-hot `.note` children; hot notes are excluded from eviction.
- **Alternatives:** include hot notes in the cap (rejected — would silently drop deferred-due reminders the user must act on); split into two separate stacks (rejected — adds CSS complexity for marginal UX win).
- **Reasoning:** the user requirement was "Don't lose information." Hot notes represent things the user must act on; auto-evicting them would lose information. Non-hot notes (branch-concluded, action-ready) are informational and safely time out.
- **Checkpoint:** N/A (single commit)
- **To reverse:** revert the `nonHot.push(notes[i])` filter in `_enforceCap` to include all notes; restore single-flat-list behavior.

### Decision: Manual dismiss of a grouped note suppresses future activations of the same groupKey.
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** on `✕` click, add BOTH the specific note key AND the groupKey to the `dismissed` Set. `pushNote` checks `dismissed.has(groupKey)` at entry.
- **Alternatives:** only suppress the specific key (rejected — user clicking ✕ on a collapsed "5 branches under X concluded" note is saying "stop telling me about this group of conclusions"; new branch concluding under X would re-fire as a fresh note, contradicting that intent); never suppress the group (same problem).
- **Reasoning:** matches the conservative interpretation of manual dismissal: "I've seen these, stop." A reload clears in-memory `dismissed`, which is the natural reset.
- **Checkpoint:** N/A
- **To reverse:** drop the `if (groupKey) dismissed.add(groupKey)` line in the ✕ click handler; per-branch notes re-fire after dismissal.

## Definition of Done

- [x] `pushNote` refactor lands with options-object + boolean backward-compat signature
- [x] `_scheduleAutoDismiss` and `_enforceCap` helpers present
- [x] `detectConcludeNotifications` call site passes `groupKey: 'concl-parent-<parent_id>'`
- [x] R71-R77 toast-fix invariants added to `web/responsive.selftest.js`
- [x] `node --check` clean on the modified app.js
- [x] `node web/responsive.selftest.js` reports 77/77 PASS
- [x] `node state/selftest.js` reports 17/17 PASS (regression unchanged)
- [x] Modified app.js confirmed served by the running localhost server (curl)
- [x] Plan committed with the work
- [x] Plan flipped to `Status: COMPLETED` in a follow-up commit (auto-archive)
- [x] Branch pushed; PR opened against master
