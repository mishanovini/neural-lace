'use strict';
/* roadmap.js — the Roadmap tree view + kanban toggle
 * (cockpit-roadmap-redesign Task 3, "Roadmap tree view + the navigation
 * shell"). Renders GET /api/roadmap (server/roadmap-routes.js — the pinned
 * payload contract lives in that file's header; statuses/roll-ups are
 * task 1's derive-lib at merge, this module only RENDERS what the server
 * derived — CANONICAL-COUNTERS-01 applies to this view too).
 *
 * Registers itself into the navigation shell (app.js's
 * window.WorkstreamsShell) as the 'roadmap' view adapter: hash landings
 * (#roadmap/<id>) expand + scroll + highlight + focus through this module's
 * locateAndExpand; Back restores expansion + scroll via
 * snapshotState/restoreState (C2).
 *
 * ROUND 8 RE-ROOTING (2026-07-21, binding — docs/reviews/2026-07-17-cockpit-
 * ux-design-input.md "Round 8"): the top-level items are now PLAN FILES
 * (docs/plans/*.md), rendered as a connected phase-series in build order,
 * each expanding to its own tasks as leaves. Asks/requests are NOT roots
 * here any more — they only ever supply OPTIONAL provenance
 * (from_requests, C6) on a plan that happens to have one linked; an
 * unlinked junk ask has no plan and so never appears here (lives only in
 * the Requests tab). `item.kind` is 'plan' | 'task' (no more 'intent').
 *
 * Laws carried here (plan task 3, binding):
 *  - Six-value status chips with TEXT labels on every item; bars always
 *    carry the "n/m" text; zero-tracked-children items omit the bar (C5).
 *  - ROLL-UP badges: ONE badge PER attention class present, precedence
 *    orders display only (C1 + delta R4); badge click expands the path.
 *  - "from your request(s)" on every drill-down, via #request/<id> (C6).
 *  - Recency ages on every chip; <24h transitions get a text "new" marker
 *    (I1). Completed aging: in place for completed_age_days, collapsed
 *    subtree headline "completed <when>", then the per-parent
 *    "N completed ▸ — latest: <title>" roll-up; the "added mid-build"
 *    marker ages on the SAME knob (round 4 + I2 — one tunable).
 *  - Kanban toggle (I3): cards = TOP-LEVEL items; merged-unverified and
 *    unknown are EXCEPTIONAL columns, rendered only when non-empty (R5);
 *    toggle + project-chip selections persist (localStorage).
 *  - Harness-chore exclusion by PROVENANCE, never subject matter (A9),
 *    with a counted "hidden" note + one-click reveal.
 *  - Four UI states (C4): loading "deriving roadmap…" / pane-error + Retry
 *    (NEVER the empty state on failure) / FILTERED-empty (names the filter,
 *    hidden count, one-click clear) / TRUE-empty (items arrive
 *    automatically — no setup ask).
 *  - 30s STATE-PRESERVING refresh (C7): open-details set, scroll, focus,
 *    uncommitted title edits, and the landing highlight survive a poll
 *    tick; a failed refresh labels the pane "derived <age> — STALE",
 *    never silent staleness and never a DOM wipe.
 *  - A11y (C9): nested <details>/<summary> tree; title editing = the
 *    todo.js edit-button + Escape + focus-return pattern; every signal is
 *    text + color; interactive chips are real <button>s; the kanban toggle
 *    and project chips are aria-pressed buttons; reorder = keyboard-
 *    operable Move up / Move down real buttons (WCAG 2.2 2.5.7 — R2).
 */
(function () {
  var body = document.getElementById('roadmapBody');
  if (!body) return; // view container absent on this page — no-op

  function $(id) { return document.getElementById(id); }
  var filterInput = $('roadmapFilter');
  var projectChipsWrap = $('roadmapProjectChips');
  var choreToggle = $('roadmapChoreToggle');
  var kanbanToggle = $('roadmapKanbanToggle');

  var shell = window.WorkstreamsShell || null;
  var formatAge = (shell && shell.formatAge) || function (iso) {
    if (!iso) return 'unknown';
    var ms = Date.now() - Date.parse(iso);
    if (isNaN(ms)) return 'unknown';
    if (ms < 0) ms = 0;
    var s = Math.round(ms / 1000);
    if (s < 60) return s + 's ago';
    var m = Math.round(s / 60);
    if (m < 60) return m + 'm ago';
    var h = Math.round(m / 60);
    if (h < 24) return h + 'h ago';
    return Math.round(h / 24) + 'd ago';
  };

  var REFRESH_INTERVAL_MS = 30000; // the existing cockpit tick (C7)

  // ---- six-value enum: display labels (text + color, never color-only).
  // The chip prefers the server-prepared status.label (named-absence
  // pattern: "status unknown — plan parse failed" / "merged — deploy
  // unverified"); this map is the fallback for a label-less payload.
  var STATUS_LABEL = {
    'not-started': 'not started',
    'in-progress': 'in progress',
    'merged-unverified': 'merged — deploy unverified',
    'complete': 'complete',
    'stalled': 'stalled',
    'unknown': 'status unknown',
  };

  // Roll-up precedence (C1 + adjudication (b)): governs display ORDER only —
  // one badge PER class present, never a masked class (delta R4). Round 15
  // (operator, repeated): "running" joins the SAME machinery the
  // stalled/unknown attention badges already use (C1's roll-up law applied
  // to the running state, not just attention states) — leads the order
  // since "someone is actively working on this right now" is the loudest,
  // most wanted-visible fact, ahead of the genuine problem states.
  var ROLLUP_ORDER = ['running', 'waiting-on-you', 'crashed', 'blocked-on', 'limit-parked', 'unknown'];
  var ROLLUP_BADGE_LABEL = {
    'running': 'running',
    'waiting-on-you': 'stalled — waiting on you',
    'crashed': 'stalled — crashed',
    'blocked-on': 'stalled — blocked on a predecessor',
    'limit-parked': 'stalled — limit-parked',
    'unknown': 'status unknown',
  };

  // Kanban columns (I3 + adjudication (d)): four core columns + the two
  // EXCEPTIONAL ones (merged-unverified, unknown) rendered only when
  // non-empty (delta R5) — never inside Complete.
  var KANBAN_COLUMNS = ['not-started', 'in-progress', 'stalled', 'merged-unverified', 'unknown', 'complete'];
  var KANBAN_EXCEPTIONAL = { 'merged-unverified': true, 'unknown': true };
  var KANBAN_COLUMN_LABEL = {
    'not-started': 'Not started',
    'in-progress': 'In progress',
    'stalled': 'Stalled',
    'merged-unverified': 'Merged — deploy unverified',
    'unknown': 'Status unknown',
    'complete': 'Complete',
  };

  // ---- persisted view preferences (I3 law: the alternate view names its
  // unit-of-card AND its state persistence — localStorage, per machine).
  var LS_VIEW_MODE = 'roadmap.viewMode';
  var LS_PROJECT_CHIPS = 'roadmap.projectChips';
  var LS_SHOW_CHORES = 'roadmap.showChores';
  function lsGet(k, dflt) { try { var v = localStorage.getItem(k); return v === null ? dflt : v; } catch (_) { return dflt; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (_) {} }

  var viewMode = lsGet(LS_VIEW_MODE, 'tree') === 'kanban' ? 'kanban' : 'tree';
  var showChores = lsGet(LS_SHOW_CHORES, '0') === '1';
  var selectedProjects = (function () {
    try { var a = JSON.parse(lsGet(LS_PROJECT_CHIPS, '[]')); return Array.isArray(a) ? a : []; }
    catch (_) { return []; }
  })();

  // ---- view state (C7 + C2): the open-details set + scroll + focus store,
  // used by BOTH the poll-tick preserving re-render and Back restoration.
  var openSet = {};       // item id -> true (details open)
  var lastPayload = null; // last successful /api/roadmap payload
  var lastFetchFailed = false;
  var lastDerivedAt = null;
  var landingId = null;   // the currently-highlighted landed item (survives re-render)
  var whenLoadedQueue = [];
  var currentMatchNotes = {}; // item id -> matched descendant (Round 12 item 8), refreshed each renderAll()

  // ============================================================
  // small builders
  // ============================================================
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }
  function btn(cls, text, onClick) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.textContent = text;
    if (onClick) b.addEventListener('click', onClick);
    return b;
  }

  function setAgeLabel() {
    var ageEl = document.querySelector('[data-age-for="roadmap"]');
    if (!ageEl) return;
    ageEl.textContent = 'derived ' + formatAge(lastDerivedAt) +
      (lastFetchFailed ? ' — STALE (last refresh failed)' : '');
    ageEl.classList.toggle('stale', lastFetchFailed);
  }

  // agedOut(ts) — the ONE completed-aging tunable (I2: the insertion marker
  // and completed roll-up share this knob; the server sends the number).
  function agedOut(ts) {
    if (!ts || !lastPayload) return false;
    var days = lastPayload.completed_age_days || 7;
    var ms = Date.now() - Date.parse(ts);
    return !isNaN(ms) && ms > days * 86400000;
  }
  function isNew(ts) { // I1: transitions <24h old get a subtle non-color-only marker
    if (!ts) return false;
    var ms = Date.now() - Date.parse(ts);
    return !isNaN(ms) && ms >= 0 && ms < 86400000;
  }

  // ============================================================
  // filtering (A9 provenance + project facets + the R6 substring box)
  // ============================================================
  function filterText() { return (filterInput && filterInput.value || '').trim().toLowerCase(); }

  function itemMatchesText(item, q) {
    if (!q) return true;
    if ((item.title || '').toLowerCase().indexOf(q) !== -1) return true;
    if ((item.id || '').toLowerCase().indexOf(q) !== -1) return true;
    var fr = item.from_requests || [];
    for (var i = 0; i < fr.length; i++) {
      if ((fr[i].title || '').toLowerCase().indexOf(q) !== -1) return true;
    }
    var kids = item.children || [];
    for (var j = 0; j < kids.length; j++) { if (itemMatchesText(kids[j], q)) return true; }
    // R11 (I4: filter matches render with their full ancestor chain) — a
    // master's resolved child plans must be searchable too.
    var childPlans = item.child_plans || [];
    for (var k = 0; k < childPlans.length; k++) { if (itemMatchesText(childPlans[k], q)) return true; }
    return false;
  }

  // applyFilters(items) -> {visible, hiddenChores, filtered, matchNoteById}
  function applyFilters(items) {
    var q = filterText();
    var hiddenChores = 0;
    var visible = [];
    var matchNoteById = {}; // Round 12 item 8: which descendant matched a task-id/title query
    (items || []).forEach(function (it) {
      if (!showChores && it.provenance === 'machine') { hiddenChores++; return; }
      if (selectedProjects.length && selectedProjects.indexOf(it.project || '') === -1) return;
      if (!itemMatchesText(it, q)) return;
      visible.push(it);
      if (q) {
        var ownMatch = (String(it.title || '')).toLowerCase().indexOf(q) !== -1 ||
          (String(it.id || '')).toLowerCase().indexOf(q) !== -1;
        if (!ownMatch) {
          var m = findMatchingDescendant(it, q);
          if (m) matchNoteById[it.id] = m;
        }
      }
    });
    return {
      visible: visible,
      hiddenChores: hiddenChores,
      filtered: !!(q || selectedProjects.length),
      matchNoteById: matchNoteById,
    };
  }

  // ============================================================
  // round-6/7 pure helpers (no DOM) — deliberately DOM-free so
  // cockpit.selftest.js can extract + execute them in a Node `vm` sandbox
  // for REAL behavioral proof, the same technique already used for
  // captureUiState (T3-27b) and ITEM_HASH_RE (T3-4b).
  // ============================================================
  // PROVENANCE-DEDUP-BEGIN
  // Round-6 gap 2: "from your request(s)" is inherited UNCHANGED by every
  // descendant (C6), so an intent's own drill-down always duplicated its
  // OWN title verbatim, and a plan/task nested under it repeated the exact
  // same text a second/third time once several levels were open at once
  // ("triple verbatim ... for one item family"). visibleFromRequests
  // filters out any entry whose (normalized) title equals THIS item's own
  // title; when that empties an otherwise non-empty list, the row must be
  // SUPPRESSED ENTIRELY (allSuppressed), never fall back to "(no captured
  // request)" — a request genuinely exists, it is just textually identical
  // to the title already on screen.
  function normalizeForCompare(s) {
    return String(s == null ? '' : s).trim().toLowerCase().replace(/\s+/g, ' ');
  }
  function visibleFromRequests(item) {
    var ownTitle = normalizeForCompare(item && item.title);
    var all = (item && item.from_requests) || [];
    var visible = all.filter(function (r) { return normalizeForCompare(r && r.title) !== ownTitle; });
    return { entries: visible, allSuppressed: all.length > 0 && visible.length === 0 };
  }
  // PROVENANCE-DEDUP-END

  // COLLAPSE-LAW-BEGIN
  // Round-6 gap 3: a FULLY-COMPLETE node (all children complete, by
  // construction of the status derivation — a parent's own status can only
  // be 'complete' once every child has shipped) collapses EVERY child into
  // the aged/roll-up bucket IMMEDIATELY — never enumerating N already-done
  // children individually just because each one is still inside the 7-day
  // "stay visible in place" window (round 4's rule, which governs a
  // STILL-ACTIVE parent's completed siblings, not a parent whose own work
  // is entirely finished). partitionChildren is the one function both the
  // per-parent child list (renderChildList) and the top-level list
  // (renderTree) call, so the law reads identically at every level.
  function partitionChildren(children, parentFullyComplete, agedOutFn) {
    var live = [], aged = [];
    (children || []).forEach(function (c) {
      var isComplete = c.status && c.status.value === 'complete';
      if (isComplete && (parentFullyComplete || agedOutFn(c.completed_at))) aged.push(c);
      else live.push(c);
    });
    return { live: live, aged: aged };
  }
  // COLLAPSE-LAW-END

  // PHASE-SERIES-BEGIN
  // Round 6 gap 6: sibling PLAN nodes under an intent are the operator's
  // "series of phases" ("phase one through four... each phase has its own
  // plan") — rendered as connected, numbered steps in build order, never a
  // plain flat list indistinguishable from an intent's other child kinds.
  //
  // R11 I5 (terminology sweep — "phases" labeling retired, docs/reviews/
  // 2026-07-28-roadmap-hierarchy-ux-review.md) rendered this as a "#k of n"
  // chip ("▸ #3 of 9 · <title>"). ROUND 12 (ux-ia-auditor live audit, item
  // 3) RETIRED the chip entirely: live-measured PROOF it is a render-
  // position artifact, not an identity — filtering to "T3" renumbered
  // Accountable Estate from "#12 OF 16" to "#2 OF 3" on the same screen.
  // isPhaseSeries/buildOrderLabel remain as pure, tested utilities (the
  // connected-sequence CONNECTOR LINE they still drive via rm-phase-series/
  // rm-phase-step is unaffected — only the unstable NUMBER TEXT is gone);
  // renderNode/renderTree/renderChildList no longer call buildOrderLabel.
  function isPhaseSeries(children) {
    return !!(children && children.length && children[0] && children[0].kind === 'plan');
  }
  function buildOrderLabel(index, total) {
    return '#' + (index + 1) + ' of ' + total;
  }
  // PHASE-SERIES-END

  // TASK-SPAN-BEGIN
  // Round 12 item 2 (the operator's #1 complaint, ux-ia-auditor live
  // audit): the task ids that make up a plan's own progress fraction
  // ALREADY reach the browser (server: roadmap-routes.js's deriveTaskNode
  // emits `id: slug + '/' + t.id`) but were discarded at render — the
  // fraction ("5/6") never said WHICH tasks. deriveTaskSpanLabel reads
  // item.children (already on the wire, no server change needed) and
  // derives a POSITIONAL span label.
  //
  // ROUND 13 fix 6 (operator, live walkthrough of the Round 12 surface:
  // "The '1–5 done' text is telling me exactly the same thing as the
  // progress bar sitting right next to it"): the done-half is DROPPED
  // entirely — the fraction + bar (fractionCellForRow, column 4) already
  // carry "how much done"; this column now names ONLY the one fact the bar
  // cannot carry — WHICH task is next. When every task is done there is no
  // "next" to name; the literal is "all done", never a done-range/count
  // (the old "1–8 done" wording this function used to emit for that case is
  // gone). In practice this branch is only ever reached by a plan whose
  // OWN status is already 'complete' (item.status is 'complete' only once
  // every child has shipped), and Round 12 item 6 already routes such
  // plans to the top-level Shipped group — so "all done" is, as a
  // structural consequence rather than a special case, only ever seen
  // there. The contiguity/doneCount bookkeeping the old implementation
  // needed to safely render a done-RANGE is gone with the range itself;
  // firstOpenChildId below just finds the first non-complete child,
  // full stop — still never fooled by a later complete task after an open
  // one (T13-old-R12-11's non-contiguous case), just no longer needing to
  // say so out loud.
  //
  //  - Never say "running" — this function never reads live_sessions and
  //    never emits any word but "next"/"all done", regardless of the first
  //    open task's own status value or live sessions. ROUND 13 fix 4 adds
  //    an HONEST "running" claim, but that lives in taskSpanCell (the DOM
  //    layer, below) which checks item.live_sessions directly on the ROW
  //    being rendered — a live task genuinely carrying a session renders
  //    "running" instead of "next"/checking this function at all; a task
  //    that merely SITS NEXT with no live session gets "next", never
  //    upgraded to a claim this pure function cannot verify.
  function shortTaskId(id) {
    var s = String(id == null ? '' : id);
    var i = s.lastIndexOf('/');
    return i === -1 ? s : s.slice(i + 1);
  }
  // firstOpenChildId(children) -> id | null. Shared by deriveTaskSpanLabel
  // (the parent's OWN "<id> next" token) and, at the call sites in
  // renderChildList/renderTaskBatches below, per-CHILD "is this the row the
  // parent just called 'next'?" — same function, same answer, by
  // construction (Round 13 fix 4: the child flagged "next" is always
  // IDENTICAL to the id named in the parent's own task-span text).
  function firstOpenChildId(children) {
    var kids = children || [];
    for (var i = 0; i < kids.length; i++) {
      var isDone = !!(kids[i] && kids[i].status && kids[i].status.value === 'complete');
      if (!isDone) return kids[i].id;
    }
    return null;
  }
  // deriveTaskSpanLabel(item) — Round 15 (operator, repeated): "if I expand
  // a plan I can see the tasks that are in progress, but the plan itself
  // doesn't show there's anything in progress." When item.roll_up.running
  // is populated (server's absorbOneChildRollUp: a REAL descendant
  // live_sessions entry, the SAME signal taskSpanCell already renders as
  // "running" on the leaf task row — never merely "in-progress status",
  // which also fires on stale done>0-but-idle plans), the token becomes
  // "<id> running" instead of "<id> next" — same id slot, one word swapped,
  // never a fabricated claim this function cannot verify (the server
  // already verified it via the roll-up law, C1 applied to running).
  function deriveTaskSpanLabel(item) {
    var kids = (item && item.children) || [];
    if (!kids.length) return '';
    var openId = firstOpenChildId(kids);
    var runningEntry = item && item.roll_up && item.roll_up.running;
    var isRunning = !!(runningEntry && runningEntry.count);
    if (openId === null) return isRunning ? 'running' : 'all done';
    return shortTaskId(openId) + (isRunning ? ' running' : ' next');
  }
  // TASK-SPAN-END

  // FILTER-MATCH-BEGIN
  // Round 12 item 8: filtering by a task id (e.g. "T3") already returns the
  // OWNING plan rows (itemMatchesText recurses into children/child_plans),
  // but gave no hint WHICH descendant matched — the operator had to open
  // every returned plan and hand-scan its full task list. findMatchingDescendant
  // walks children/child_plans (never the item's OWN title/id — the caller
  // only needs this when the item's own fields did NOT match) and returns
  // the first id/title hit, or null. Pure (no DOM) — vm-sandbox tested like
  // visibleFromRequests/isPhaseSeries above.
  function findMatchingDescendant(item, q) {
    if (!q) return null;
    var lists = [(item && item.children) || [], (item && item.child_plans) || []];
    for (var li = 0; li < lists.length; li++) {
      var arr = lists[li];
      for (var i = 0; i < arr.length; i++) {
        var c = arr[i];
        if ((String(c.id || '')).toLowerCase().indexOf(q) !== -1 ||
            (String(c.title || '')).toLowerCase().indexOf(q) !== -1) return c;
        var nested = findMatchingDescendant(c, q);
        if (nested) return nested;
      }
    }
    return null;
  }
  // FILTER-MATCH-END

  // PROJECT-GROUPING-BEGIN
  // Round 9 gap 2 (R9-2, operator audit): 8A re-rooted the tree on plans,
  // and renderTree's own top-level "phase series" treatment (isPhaseSeries/
  // phaseLabel, previously reused verbatim from renderChildList — see
  // R8-3/R8-6) then numbered EVERY unrelated plan as one giant
  // cross-project series ("PHASE 1 OF 16"), which "implies membership in
  // nothing" (the operator's own words). FIX: group the top-level list by
  // PROJECT (a visible header naming the project + counts, R9-2/R9-3),
  // number phases WITHIN each group. groupItemsByProject/
  // projectGroupHeaderText are pure (no DOM) — extracted for the same
  // real-execution test technique as isPhaseSeries/visibleFromRequests
  // above (cockpit.selftest.js runs these in a vm sandbox).
  //
  // Groups preserve FIRST-APPEARANCE order over the incoming array, which
  // is already build-order-sorted server-side (rank, then added_ts) — so a
  // project's own items stay in their real build order within its group;
  // "keep reorder buttons working" (R9-2) holds because moveRank/the
  // up/down button disabled-state below are computed against the items'
  // TRUE GLOBAL position (not the group-local index) — reordering still
  // operates on the one real build-order list the server keeps.
  function groupItemsByProject(items) {
    var order = [];
    var byProject = {};
    (items || []).forEach(function (it) {
      var key = it.project || '';
      if (!byProject[key]) { byProject[key] = []; order.push(key); }
      byProject[key].push(it);
    });
    return order.map(function (key) { return { project: key, items: byProject[key] }; });
  }
  function projectGroupHeaderText(project, items) {
    // R11 anatomy L0 (ux review): the FOUR-BUCKET count strip in the
    // operator's own round-1 words — upcoming / in progress / partially
    // done / complete. Mapping: not-started→upcoming; in-progress AND
    // stalled→in progress (lifecycle position; the stall itself surfaces
    // via badges, never hidden); merged-unverified→partially done (the R3
    // complete oracle: not complete until nothing is left for production);
    // unknown appended separately when nonzero (honest partition
    // exception, never silently bucketed). Pure, standalone-executable
    // (vm-sandbox test technique — no outer-scope access).
    var counts = {};
    (items || []).forEach(function (it) {
      var v = (it.status && it.status.value) || 'unknown';
      counts[v] = (counts[v] || 0) + 1;
    });
    // Round 15 (coordinator, operator verbatim: "the Workstreams UI still
    // doesn't actually represent the actual order of building"): "in
    // progress" leads the strip (immediately after "in build order") —
    // matching the new render order (bandPlanItems, below) that now puts
    // in-progress-ish plans before upcoming ones — instead of leading with
    // "upcoming", which read as backwards next to a phrase claiming build
    // order.
    var buckets = [
      ['in progress', (counts['in-progress'] || 0) + (counts['stalled'] || 0)],
      ['partially done', (counts['merged-unverified'] || 0)],
      ['upcoming', (counts['not-started'] || 0)],
      ['complete', (counts['complete'] || 0)],
    ];
    var parts = buckets.filter(function (b) { return b[1]; }).map(function (b) {
      return b[1] + ' ' + b[0];
    });
    if (counts['unknown']) parts.push(counts['unknown'] + ' status unknown');
    var label = project || '(no project)';
    var count = (items || []).length;
    // "plans, in build order" not "phases" (operator 2026-07-24: "is there a
    // plan this is tied to?" — each phase IS one plan file; the header says
    // so instead of implying membership in some unnamed program).
    return label + ' — ' + count + (count === 1 ? ' plan' : ' plans') + ', in build order' +
      (parts.length ? ' (' + parts.join(', ') + ')' : '');
  }
  // PROJECT-GROUPING-END

  // PLAN-BANDING-BEGIN
  // bandPlanItems(items) — Round 15 (coordinator, operator verbatim: "the
  // Workstreams UI still doesn't actually represent the actual order of
  // building, at least not at the plan level"). roadmap_rank's DEFAULT is
  // registry-insertion order (R11 adjudication (a), deliberately NOT
  // recency — recency churn would reorder the list under the operator
  // daily, so that reasoning still stands and is UNCHANGED here); but
  // insertion order alone lets a not-started plan sit ABOVE one that is
  // actively in-progress, which reads as "wrong order" even though rank
  // itself never lied. THREE STABLE BANDS fix it: any plan that is NOT
  // not-started (in-progress/stalled/merged-unverified/unknown — "any
  // running or partially-done plan") renders before every not-started
  // ("upcoming") plan; each band keeps its OWN existing rank order
  // internally (a plain filter, never a re-sort) so membership is purely
  // STATE-DERIVED and changes ONLY when a plan's own status changes, never
  // a recency-driven reshuffle. Shipped (complete) is already its own
  // separate band, unchanged (Round 12 item 6) — this only reorders what
  // was previously the single flat "live" list. Pure, standalone-
  // executable (same vm-sandbox test technique as groupItemsByProject/
  // projectGroupHeaderText above — no outer-scope access).
  function bandPlanItems(items) {
    var arr = items || [];
    var inProgress = arr.filter(function (it) { return it.status && it.status.value !== 'not-started'; });
    var upcoming = arr.filter(function (it) { return !it.status || it.status.value === 'not-started'; });
    return inProgress.concat(upcoming);
  }
  // PLAN-BANDING-END

  // ============================================================
  // status chip + roll-up badges + markers (shared by tree AND kanban)
  // ============================================================
  // Round 12 item 4 (operator: the status chip is redundant with the
  // fraction/progress bar for the states the fraction CAN derive). The
  // fraction derives not-started (0/N), complete (N/N), and in-progress
  // (anything in between) by construction — it CANNOT derive stalled,
  // merged-unverified, or unknown, which is exactly why those three stay
  // loud. DERIVABLE_STATES gates statusChip() below; EXCEPTION_GLYPH
  // supplies the small column-6 glyph for the other three.
  var DERIVABLE_STATES = { 'not-started': true, 'in-progress': true, 'complete': true };
  var EXCEPTION_GLYPH = { stalled: '⚠', 'merged-unverified': '⏳', unknown: '?' };
  var TITLE_STATE_CLASS = {
    'not-started': 'rm-title-not-started',
    'in-progress': 'rm-title-in-progress',
    'complete': 'rm-title-complete',
    'stalled': 'rm-title-stalled',
    'merged-unverified': 'rm-title-merged-unverified',
    'unknown': 'rm-title-unknown',
  };
  function titleStateClass(item) {
    var v = (item.status && item.status.value) || '';
    return TITLE_STATE_CLASS[v] || '';
  }

  function statusChip(item) {
    var st = item.status || {};
    var value = st.value || 'unknown';
    // Round 12 item 4: no chip at all for the three DERIVABLE states — the
    // fraction + task-span text already say it; a same-info chip here was
    // the operator's named redundancy ("showing the 'in progress'/
    // 'complete' status next to the progress bar is also redundant").
    // ROADMAP-SUPERSEDED-RENDERS-PENDING-01: a `complete` item carrying a
    // `terminal_label` (superseded/abandoned) is the ONE exception — an
    // authored terminal status must render its own distinct chip inside
    // Shipped, never fold silently into the same no-chip "ordinary
    // complete" bucket (server: roadmap-routes.js derivePlanRootNode).
    if (DERIVABLE_STATES[value] && !st.terminal_label) return null;
    var label = st.terminal_label || st.label || STATUS_LABEL[value] || value;
    var ageTs = value === 'complete' ? (item.completed_at || st.since) : st.since;
    var text = label + (ageTs ? ', ' + formatAge(ageTs) : '');
    var chip;
    if (value === 'stalled' || value === 'unknown') {
      // reason one click away (C5): the chip is a REAL button opening the
      // item's drill-down where the full reason + what-unblocks renders.
      chip = btn('chip rm-status rm-status-' + value, text, function () {
        var det = findItemEl(item.id);
        if (det && det.tagName === 'DETAILS') det.open = true;
        var reasonRow = det && det.querySelector('.rm-status-reason');
        if (reasonRow) { reasonRow.scrollIntoView({ block: 'nearest' }); }
      });
      chip.title = st.reason || 'open for the derived reason';
    } else {
      var chipClass = 'chip rm-status rm-status-' + (st.terminal_label ? 'terminal-' + st.terminal_label : value);
      chip = el('span', chipClass, text);
    }
    return chip;
  }

  function progressNode(item) {
    // zero tracked children -> NO bar (no fake granularity); otherwise the
    // bar ALWAYS carries the "n/m" text (never bar-only).
    if (!item.progress || !item.progress.total) return null;
    var p = item.progress;
    var statusVal = (item.status && item.status.value) || 'not-started';
    var wrap = el('span', 'rm-progress');
    var barOuter = el('span', 'rm-progress-bar');
    barOuter.setAttribute('role', 'img');
    barOuter.setAttribute('aria-label', p.done + ' of ' + p.total + ' tasks done');
    // Round 12 item 5: the fill is STATUS-COLORED (rm-fill-<value>), not one
    // static green for every fraction — retires --ok from the roadmap.
    var fill = el('span', 'rm-progress-fill rm-fill-' + statusVal);
    fill.style.width = Math.round(100 * p.done / p.total) + '%';
    barOuter.appendChild(fill);
    wrap.appendChild(barOuter);
    wrap.appendChild(el('span', 'rm-progress-text', p.done + '/' + p.total));
    return wrap;
  }

  // R11 Critical 5: a master's TWO SEPARATE labeled fractions ("plans 2/7",
  // "own tasks 3/5") — NEVER blended into one number. The `[master]` tag is
  // driven ONLY by `master_summary` being present, i.e. ONLY from RESOLVED
  // children (server-side applyMasterHierarchy) — never merely from a
  // declared `parent_plan` string on some OTHER plan.
  function masterSummaryNode(item) {
    var ms = item.master_summary;
    if (!ms) return null;
    var frag = document.createDocumentFragment();
    frag.appendChild(el('span', 'chip rm-master-tag', 'master — ' + ms.plans.total + (ms.plans.total === 1 ? ' plan' : ' plans')));
    frag.appendChild(el('span', 'chip rm-master-fraction', 'plans ' + ms.plans.done + '/' + ms.plans.total));
    frag.appendChild(el('span', 'chip rm-master-fraction', 'own tasks ' + ms.own_tasks.done + '/' + ms.own_tasks.total));
    return frag;
  }

  // R11 Critical 4(2)/(4): the reference-lifecycle badges. Both are REAL
  // buttons (text, never color-only) so the reason is one click away —
  // consistent with the stalled/unknown status chip's own affordance.
  function referenceLifecycleBadges(item) {
    var frag = document.createDocumentFragment();
    if (item.dangling_parent) {
      var b = btn('chip rm-dangling-badge', "parent '" + item.parent_plan + "' not found", function () {
        var det = findItemEl(item.id);
        if (det && det.tagName === 'DETAILS') det.open = true;
      });
      b.title = 'this plan declares parent-plan: ' + item.parent_plan + ', but no such plan resolves in this project';
      frag.appendChild(b);
    }
    if (item.cycle_flag) {
      var cb = btn('chip rm-cycle-badge', 'cycle detected with \'' + item.cycle_with + '\'', function () {
        if (item.cycle_with) expandPathTo(item.cycle_with);
      });
      cb.title = 'a parent-plan cycle was found and broken here — both plans are flagged';
      frag.appendChild(cb);
    }
    return frag;
  }

  function rollupBadges(item) {
    var wrap = el('span', 'rm-rollups');
    var ru = item.roll_up || {};
    ROLLUP_ORDER.forEach(function (cls) { // precedence = display order, never selection (R4)
      var entry = ru[cls];
      if (!entry || !entry.count) return;
      var label = entry.count + ' ' + (ROLLUP_BADGE_LABEL[cls] || cls);
      var badge = btn('chip rm-rollup-badge rm-rollup-' + cls, label, function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (entry.exemplar) expandPathTo(entry.exemplar);
      });
      badge.title = 'expand to the affected item';
      wrap.appendChild(badge);
    });
    return wrap;
  }

  function markerChips(item) {
    var frag = document.createDocumentFragment();
    // "added mid-build" is a TRANSIENT annotation chip: it declares itself
    // by aging out on the SAME completed_age_days knob (I2 — one tunable).
    if (item.added_mid_build && !agedOut(item.added_ts)) {
      frag.appendChild(el('span', 'chip rm-marker rm-marker-midbuild', 'added mid-build'));
    }
    if (isNew(item.status && item.status.since)) {
      frag.appendChild(el('span', 'rm-new-marker', 'new')); // text marker, never color-only (I1)
    }
    return frag;
  }

  // ============================================================
  // Round 12 (ux-ia-auditor live audit) — the row's GRID CELLS. Each
  // function ALWAYS returns a real element (possibly empty) so every row
  // appends exactly one child per column, in the same order, every time —
  // the fix for the flex-wrap misalignment (item 1): a conditionally-
  // skipped child used to shift every LATER column into the wrong slot.
  //
  // ROUND 13 fix 1 (operator walkthrough, live-measured): the dedicated
  // 56px marker column (new/added-mid-build chips) was EMPTY on 105/112
  // real rows (93.75%) — a fixed-width dead zone between the chevron and
  // the title on nearly every row, live-measured pushing the title text
  // ~66px (56px column + its own 10px grid gap) further right than
  // necessary. markerCell/its column are RETIRED; markerChips(item) now
  // renders INSIDE titleCell (column now 2, was 3) — the same place
  // referenceLifecycleBadges already lived, appended right after the
  // title text. The grid goes from 7 columns to 6; every row still
  // appends exactly one cell per remaining column, always (the R12-6
  // discipline this fix does not relax).
  // ============================================================
  function titleCell(item) { // column 2 (1fr)
    var cell = el('span', 'rm-cell rm-cell-title');
    // Round 13 fix 4 (per-task done-state, operator: "why doesn't it show
    // the progress of each task?"): a leaf task that's actually complete
    // gets a leading check glyph. Text (not color-only, WCAG 1.4.1) and
    // NOT aria-hidden — a task-kind row carries no other done/not-done
    // text signal of its own (the exception chip is suppressed for the
    // three derivable states, same as everywhere else in this file), so
    // this glyph is the one place a screen-reader user hears "done" on an
    // individual task row.
    if (item.kind === 'task' && item.status && item.status.value === 'complete') {
      cell.appendChild(el('span', 'rm-task-check', '✓'));
    }
    var titleSpan = el('span', 'rm-title ' + titleStateClass(item), item.title);
    // Round 12 item 1: ellipsis truncates the title (CSS); the FULL text
    // lives in title= — R9-1's slug-as-tooltip is folded in after it so
    // hovering still surfaces the plan slug, not just the title repeated.
    titleSpan.title = item.title + (item.kind === 'plan' ? ' — ' + item.id : '');
    cell.appendChild(titleSpan);
    cell.appendChild(markerChips(item)); // Round 13 fix 1: folded in from the retired marker column
    cell.appendChild(referenceLifecycleBadges(item)); // rare (dangling-parent/cycle); wraps inside this cell
    return cell;
  }

  // taskSpanCell(item, isNextTask) — column 3 (190px). Round 13 fix 4: for a
  // TASK-kind row (a leaf has no children of its own, so
  // deriveTaskSpanLabel(item.children) is always '') this column is
  // otherwise dead space — repurposed to carry the one per-task claim the
  // rest of the row cannot: "running" when the task genuinely carries a
  // live session (checked directly on THIS item — never fabricated,
  // never borrowed from a sibling), else "next" when the caller
  // (renderChildList/renderTaskBatches) determined this is the first
  // not-done task in its parent's list — the SAME id the parent's own
  // task-span text just named "next" (both call firstOpenChildId). A task
  // that is neither running nor next renders nothing here — no fake
  // granularity on every row.
  function taskSpanCell(item, isNextTask) {
    var cell = el('span', 'rm-cell rm-cell-taskspan');
    if (item.kind === 'task') {
      if (item.live_sessions && item.live_sessions.length) {
        // Round 15 (operator: "the running indicator is small and not
        // obvious"): the `chip` base class gives it the same loud
        // bordered-pill treatment every other status signal in this view
        // uses, instead of plain inline text.
        cell.appendChild(el('span', 'chip rm-task-running', 'running'));
      } else if (isNextTask) {
        cell.appendChild(el('span', 'rm-task-next', 'next'));
      }
      return cell;
    }
    // Round 15: the "<id> running" token (deriveTaskSpanLabel) earns the
    // SAME loud --info blue + weight 600 the leaf task's own "running" chip
    // and the bright in-progress title use — text + colour together (WCAG
    // 1.4.1: the word "running" is the non-colour carrier, the blue is the
    // reinforcement, never the only signal). "next"/"all done" stay the
    // existing neutral (positional claim only).
    var label = deriveTaskSpanLabel(item);
    if (label) {
      var isRunningLabel = label === 'running' || / running$/.test(label);
      cell.appendChild(el('span', isRunningLabel ? 'rm-taskspan-running' : '', label));
    }
    return cell;
  }

  function fractionCellForRow(item) { // column 4 (76px)
    var cell = el('span', 'rm-cell rm-cell-fraction');
    var prog = progressNode(item);
    if (prog) cell.appendChild(prog);
    return cell;
  }

  function exceptionGlyphCell(item) { // column 5 (46px)
    var v = item.status && item.status.value;
    var g = EXCEPTION_GLYPH[v];
    var cell = el('span', 'rm-cell rm-cell-exglyph' + (g ? ' rm-exglyph-' + v : ''), g || '');
    if (g) cell.setAttribute('aria-hidden', 'true'); // decorative — the adjacent label chip (column 6) carries the real text (WCAG 1.4.1)
    return cell;
  }

  function exceptionLabelCell(item) { // column 6 (132px): the loud exception chip + descendant roll-up badges
    var cell = el('span', 'rm-cell rm-cell-exception');
    var chip = statusChip(item); // null for the three derivable states — an empty column 6 means "healthy"
    if (chip) cell.appendChild(chip);
    cell.appendChild(rollupBadges(item)); // descendant attention (C1) — independent of this item's OWN state
    return cell;
  }

  // taskStructureBlock(item) — round-6 gap 1 + round-7 7A/7B/7B-i: renders
  // the task's own lead sentences, its "- **Label:**" sub-bullets (visible
  // hierarchy — 7B), and any currently-attached live agent sessions
  // (7B-i), ALL as bulleted lists (7A: never a paragraph). Absent/empty
  // server fields render nothing — never a fabricated empty section.
  var AGENT_STATUS_GLYPH = { running: '●', stalled: '◐', unknown: '○' };
  function taskStructureBlock(item) {
    var frag = document.createDocumentFragment();

    var leadPoints = item.lead_points || [];
    if (leadPoints.length) {
      var leadWrap = el('div', 'rm-lead');
      leadWrap.appendChild(el('span', 'rm-drill-label', 'summary:'));
      var leadList = el('ul', 'rm-lead-points');
      leadPoints.forEach(function (p) { leadList.appendChild(el('li', '', p)); });
      leadWrap.appendChild(leadList);
      frag.appendChild(leadWrap);
    }

    var subtasks = item.subtasks || [];
    if (subtasks.length) {
      var subWrap = el('div', 'rm-subtasks-wrap');
      subWrap.appendChild(el('span', 'rm-drill-label', 'subtasks (' + subtasks.length + '):'));
      var subList = el('ul', 'rm-subtasks');
      subtasks.forEach(function (s) {
        var li = document.createElement('li');
        li.appendChild(el('span', 'rm-subtask-title', s.title));
        var bodyPoints = s.body_points || [];
        if (bodyPoints.length) {
          var bodyList = el('ul', 'rm-subtask-body');
          bodyPoints.forEach(function (p) { bodyList.appendChild(el('li', '', p)); });
          li.appendChild(bodyList);
        }
        subList.appendChild(li);
      });
      subWrap.appendChild(subList);
      frag.appendChild(subWrap);
    }

    var liveSessions = item.live_sessions || [];
    if (liveSessions.length) {
      var agentWrap = el('div', 'rm-agents-wrap');
      agentWrap.appendChild(el('span', 'rm-drill-label', 'currently running (' + liveSessions.length + '):'));
      var agentList = el('ul', 'rm-agents');
      liveSessions.forEach(function (a) {
        var li = document.createElement('li');
        li.className = 'rm-agent rm-agent-' + (a.status && a.status.value || 'unknown');
        var glyph = el('span', 'rm-agent-glyph', AGENT_STATUS_GLYPH[a.status && a.status.value] || '○');
        glyph.setAttribute('aria-hidden', 'true');
        li.appendChild(glyph);
        var label = (a.status && a.status.label) || 'status unknown';
        var text = a.title + ' — ' + label;
        if (a.status && a.status.since) text += ', ' + formatAge(a.status.since);
        li.appendChild(el('span', 'rm-agent-text', text));
        agentList.appendChild(li);
      });
      agentWrap.appendChild(agentList);
      frag.appendChild(agentWrap);
    }

    return frag;
  }

  // R9-7 (operator audit row 7): running work is NEVER invisible. Sessions
  // with a live heartbeat but no task binding render as ONE top-of-tree
  // collapsible node (server: deriveUnboundSessionsNode -> payload
  // `unbound_sessions`; null when nothing is live — honest absence, no
  // fake node). Same rm-agents markup/classes as the task-level leaves.
  function renderUnboundSessions(node) {
    var det = document.createElement('details');
    det.className = 'rm-unbound-sessions';
    det.dataset.itemId = node.id;
    if (openSet['unbound:(top)']) det.open = true;
    det.addEventListener('toggle', function () {
      if (det.open) openSet['unbound:(top)'] = true; else delete openSet['unbound:(top)'];
    });
    var sum = document.createElement('summary');
    sum.className = 'rm-unbound-summary';
    sum.appendChild(el('span', 'rm-title', node.title));
    sum.appendChild(el('span', 'chip rm-status rm-status-in-progress', (node.status && node.status.label) || 'running'));
    det.appendChild(sum);
    var list = el('ul', 'rm-agents');
    (node.live_sessions || []).forEach(function (a) {
      var li = document.createElement('li');
      li.className = 'rm-agent rm-agent-' + (a.status && a.status.value || 'unknown');
      var glyph = el('span', 'rm-agent-glyph', AGENT_STATUS_GLYPH[a.status && a.status.value] || '○');
      glyph.setAttribute('aria-hidden', 'true');
      li.appendChild(glyph);
      var label = (a.status && a.status.label) || 'status unknown';
      var text = a.title + ' — ' + label;
      if (a.status && a.status.since) text += ', ' + formatAge(a.status.since);
      li.appendChild(el('span', 'rm-agent-text', text));
      list.appendChild(li);
    });
    det.appendChild(list);
    return det;
  }

  // openPlanDocModal(project, docPath) — reuses the EXISTING docModal DOM
  // app.js already wires (Esc, docClose, docScrim all close it regardless
  // of who opened it), the SAME small-duplicated-reader pattern asks.js's
  // own openPlanDocModal already established (ux-review amendment 6: "no
  // pane grows its own link handling"). Best-effort no-op if the shared
  // modal elements are absent from this page for any reason.
  function openPlanDocModal(project, docPath) {
    var docModal = $('docModal'), docTitle = $('docTitle'), docBody = $('docBody'), docOpenEditor = $('docOpenEditor');
    if (!docModal || !docTitle || !docBody) return;
    docTitle.textContent = project + ' / ' + docPath;
    docBody.textContent = 'loading…';
    docModal.hidden = false;
    fetch('/api/doc?project=' + encodeURIComponent(project) + '&path=' + encodeURIComponent(docPath))
      .then(function (r) { return r.json(); })
      .then(function (j) {
        // Round 16 deliverable 2: same shared markdown renderer app.js's
        // Docs panel uses for this SAME #docBody element (see
        // web/md-render.js's header for the escaping-first security
        // contract) — no second implementation. Missing global (script
        // failed to load) degrades to plain text, never a throw.
        if (j && j.ok) {
          if (window.MdRender && typeof window.MdRender.renderMarkdown === 'function') {
            docBody.innerHTML = window.MdRender.renderMarkdown(j.content);
          } else {
            docBody.textContent = j.content;
          }
        } else {
          docBody.textContent = 'error: ' + (j && j.error);
        }
      })
      .catch(function (err) { docBody.textContent = 'error: ' + err; });
    if (docOpenEditor) {
      docOpenEditor.onclick = function () {
        fetch('/api/doc/open', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ project: project, path: docPath }),
        }).catch(function () {});
      };
    }
  }
  function makeCopyBtn(text, label) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'ghost small copy-btn';
    b.textContent = label || 'copy';
    b.title = 'copy "' + text + '" to clipboard';
    b.addEventListener('click', function (e) {
      e.stopPropagation();
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).catch(function () {});
      var orig = b.textContent;
      b.textContent = 'copied';
      setTimeout(function () { b.textContent = orig; }, 1200);
    });
    return b;
  }

  // ============================================================
  // drill-down body (C6 + C5 reasons + merged-unverified override).
  // ROUND 16: title edit + rank reorder used to live here — both retired
  // (deliverables 3/4/5); reorder now wires onto the SUMMARY row itself,
  // see wirePlanRowReorder/renderNode, not this drill-down body.
  // ============================================================
  function drilldown(item) {
    var box = el('div', 'rm-drill');

    // R9 follow-up (operator 2026-07-24: "is there a plan this is tied to?
    // why don't I see a link?"): every phase IS a plan file — link it.
    // ROUND 15 (operator, verified live): the OLD `file:///` href was a
    // DEAD link from this http-served page (confirmed live at :7733 — no
    // navigation, no network activity on click). Plan links now open the
    // SAME in-page docs viewer the Docs button already renders markdown
    // through (/api/doc {project,path}, reusing docModal) — never a
    // second renderer (ux-review amendment 6). `plan_doc` is null only
    // when the plan lives outside every configured/discovered project
    // root; that (rare, should not occur for this repo's own plans) case
    // falls back to plain text + copy, never a fabricated/dead link.
    if (item.kind === 'plan' && item.plan_path) {
      var planRow = el('div', 'rm-plan-link-row');
      planRow.appendChild(el('span', 'rm-drill-label', 'plan: '));
      var displayPath = item.plan_path.replace(/^.*[\\/](docs[\\/])/, '$1').replace(/\\/g, '/');
      if (item.plan_doc && item.plan_doc.project && item.plan_doc.path) {
        var planLinkBtn = btn('rm-plan-link rm-plan-link-btn', displayPath, function () {
          openPlanDocModal(item.plan_doc.project, item.plan_doc.path);
        });
        planLinkBtn.title = item.plan_path + ' — open the rendered file in-page';
        planRow.appendChild(planLinkBtn);
      } else {
        var planTextSpan = el('span', 'rm-plan-link', displayPath);
        planTextSpan.title = item.plan_path;
        planRow.appendChild(planTextSpan);
        planRow.appendChild(makeCopyBtn(item.plan_path, 'copy path'));
      }
      box.appendChild(planRow);
    }

    // from your request(s) — C6, the round-1 verbatim direction: drill-down
    // ONLY (never inline-by-default), and suppressed entirely when it would
    // just echo this item's own title back (round-6 gap 2). ROUND-9 R9-5:
    // the row now renders ONLY when a genuine (non-duplicate) linked
    // request actually exists — the pre-fix "(no captured request —
    // registered directly)" fallback rendered on nearly every phase once
    // 8A re-rooted the tree on plans (most plans have no linked ask at
    // all), which is exactly the provenance noise C6's dedup law targeted;
    // `!frInfo.allSuppressed` alone was insufficient because it stays FALSE
    // (i.e. "not suppressed") when from_requests was empty from the start,
    // which is the common case post-8A — entries.length > 0 is the real
    // gate. Both directions law: the Requests view renders "became →" back
    // (task 5).
    var frInfo = visibleFromRequests(item);
    if (!frInfo.allSuppressed && frInfo.entries.length > 0) {
      var frRow = el('div', 'rm-from-requests');
      frRow.appendChild(el('span', 'rm-drill-label', 'from your request(s): '));
      frInfo.entries.forEach(function (r) {
        frRow.appendChild(btn('ghost small rm-request-link', r.title || r.id, function () {
          // T3-fix2: encode the id segment (encode/decode symmetry with
          // app.js routeFromHash's decodeURIComponent) — a raw '%' in an id
          // otherwise throws URIError in the hashchange handler.
          if (shell) shell.navigate('#request/' + encodeURIComponent(r.id));
        }));
      });
      box.appendChild(frRow);
    }

    // task-leaf structure (round-6 gap 1 continuation + round-7 7A/7B/7B-i):
    // a scannable LIST, never the raw folded plan-markdown paragraph. Only
    // task-kind items carry these fields (server-populated); absent/empty
    // arrays render nothing, never a placeholder paragraph.
    box.appendChild(taskStructureBlock(item));

    // stalled/unknown: the derived reason + what-unblocks, one click away.
    var st = item.status || {};
    if (st.value === 'stalled' || st.value === 'unknown') {
      var reasonRow = el('div', 'rm-status-reason');
      reasonRow.appendChild(el('span', 'rm-drill-label',
        st.value === 'stalled' ? 'stalled: ' : 'status unknown: '));
      reasonRow.appendChild(el('span', '', st.reason || 'reason unavailable'));
      if (st.unblock && st.unblock.hash) {
        reasonRow.appendChild(btn('ghost small rm-unblock-link', st.unblock.label || 'what unblocks this', function () {
          if (shell) shell.navigate(st.unblock.hash);
        }));
      }
      box.appendChild(reasonRow);
    }

    if (item.kind === 'plan') {
      // feedback line for every write below (aria-live — C9)
      var feedback = el('div', 'rm-edit-feedback');
      feedback.setAttribute('aria-live', 'polite');
      feedback.hidden = true;
      function say(text, isErr) {
        feedback.hidden = false;
        feedback.textContent = text;
        feedback.className = 'rm-edit-feedback' + (isErr ? ' rm-feedback-err' : ' rm-feedback-ok');
      }

      // ROUND 16 deliverables 3/4 (operator, live walkthrough, verbatim):
      // "I don't like the buttons appearing below the plan doc links;
      // they force the GUI underneath to jump around awkwardly, and
      // they're also unnecessary. I don't see any need to edit the name
      // of the plan titles." The edit-button + Move up/down chrome row
      // that used to render here (round-6 gap 4, then Round 13 fix 5's
      // height:0 hover-reveal hack) is REMOVED outright, not merely
      // hidden — plan titles come from the H1, no edit affordance
      // anywhere in this view. Reordering is now drag-and-drop on the
      // row's own grip handle (wirePlanRowReorder, called from renderNode
      // once the row's DOM exists) — same moveRank()/`/api/roadmap/rank`
      // delegation as the retired buttons; a NON-VISUAL Cmd/Ctrl+ArrowUp/Down keyboard
      // path on the focused row satisfies WCAG 2.2 2.5.7 (drag must not
      // be the ONLY operable path) without resurrecting a visible control.

      // merged-unverified: the LABELED per-item operator override to
      // complete (A4's binding rule) — delegates to the existing lifecycle
      // endpoint; manual done is always an override, labeled.
      if (st.value === 'merged-unverified') {
        // The lifecycle endpoint is ask-id-keyed (server.js, unrelated to
        // this plan-rooted tree) — resolve the plan's first linked ask
        // (from_requests[0], the SAME target title/rank edits delegate
        // through) when one exists; a plan with no linked ask has no
        // ask-lifecycle record to override, so the fetch degrades to an
        // honest server-side "not found" error rather than a silent no-op.
        var overrideTargetId = (item.from_requests && item.from_requests[0] && item.from_requests[0].id) || item.id;
        var overrideBtn = btn('ghost small rm-override-btn', 'Mark complete anyway (override)', function () {
          overrideBtn.disabled = true;
          fetch('/api/ask/' + encodeURIComponent(overrideTargetId) + '/lifecycle', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'done' }),
          }).then(function (r) { return r.json(); }).then(function (j) {
            if (j && j.ok) { say('Marked complete (override recorded).', false); load(); }
            else { overrideBtn.disabled = false; say('Could not mark complete: ' + ((j && j.error) || 'unknown error'), true); }
          }).catch(function (e) { overrideBtn.disabled = false; say('Could not mark complete: ' + e, true); });
        });
        overrideBtn.title = 'no deploy signal exists for this project — this records a manual, labeled override';
        box.appendChild(overrideBtn);
      }

      box.appendChild(feedback);
    }
    return box;
  }

  // openTitleEditor / the plan-title edit affordance is RETIRED (Round 16
  // deliverable 4, operator verbatim: "I don't see any need to edit the
  // name of the plan titles"). Plan titles come from the H1 — no edit
  // input, no Save/Cancel, anywhere in this view. NOTE: `POST
  // /api/roadmap/title` still exists server-side (roadmap-routes.js) —
  // deliberately left in place, out of THIS scope: the operator's ask was
  // "no edit affordance on plan TITLES" in the Roadmap view specifically
  // ("ask/request title editing elsewhere is NOT in scope"), and
  // requests-routes.js's own title-write path shares the same underlying
  // delegation (see that file's own comment referencing this endpoint) —
  // removing the route would risk that shared surface for a UI-only ask.

  // ============================================================
  // ROUND 16 deliverable 5 — drag-and-drop build-order reordering
  // (replaces the retired Move up / Move down buttons). Persists via the
  // SAME /api/roadmap/rank one-step-at-a-time delegation moveRank() below
  // always used; a drag of N visual positions issues N sequential calls.
  // WCAG 2.2 2.5.7 (drag must never be the ONLY operable path): every
  // plan row's <summary> also carries a Cmd/Ctrl+ArrowUp/Down keydown
  // handler that calls moveRank() directly — a real, documented (row
  // title/aria-keyshortcuts), non-visual alternative, not a second visible
  // control (which is exactly what the operator asked to have removed).
  // ============================================================
  var dragState = null; // { itemId } — the plan currently being dragged

  // planRowContainer(rowEl) -> the nearest wrapper that groups a plan row
  // with its TRUE reorder siblings, mirroring the server's own
  // computeSiblingIds scoping (roadmap-routes.js): top-level plans share
  // one project group (or the bare tree, ungrouped fallback); a master's
  // resolved child plans share their own .rm-master-plans subsection's
  // .rm-children wrapper (rendered with rm-phase-series exactly like the
  // top level — renderChildList applies the identical wrapping either way).
  function planRowContainer(rowEl) {
    return rowEl.closest('.rm-project-group, .rm-children.rm-phase-series, .rm-tree');
  }
  function siblingPlanRows(container) {
    if (!container) return [];
    return Array.prototype.slice.call(
      container.querySelectorAll(':scope > .rm-phase-step > .rm-node.rm-kind-plan, :scope > .rm-node.rm-kind-plan')
    );
  }
  function clearDropIndicators() {
    var marked = document.querySelectorAll('.rm-drop-before, .rm-drop-after');
    for (var i = 0; i < marked.length; i++) marked[i].classList.remove('rm-drop-before', 'rm-drop-after');
  }
  // reorderFeedback(det) -> a say(text, isErr) callback writing into THIS
  // row's own .rm-edit-feedback element (the same one the merged-
  // unverified override button already renders into) — one feedback
  // surface per plan row, never a second implementation.
  function reorderFeedback(det) {
    return function (text, isErr) {
      if (!det) return;
      var fb = det.querySelector(':scope > .rm-drill > .rm-edit-feedback');
      if (!fb) return;
      fb.hidden = false;
      fb.textContent = text;
      fb.className = 'rm-edit-feedback' + (isErr ? ' rm-feedback-err' : ' rm-feedback-ok');
    };
  }
  // sequentialMove(item, direction, remaining, say) — issues `remaining`
  // single-step /api/roadmap/rank calls (the exact endpoint the retired
  // buttons called), silently for every step but the last; the LAST step
  // delegates to moveRank() itself so the user sees the SAME human message
  // ("Moved ... now #N of M in ...'s build order") a single button click
  // always produced — one message implementation, not a duplicate.
  function sequentialMove(item, direction, remaining, say) {
    if (remaining <= 1) { moveRank(item, direction, say); return; }
    fetch('/api/roadmap/rank', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: item.id, direction: direction }),
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (!j || !j.ok) { if (say) say('Could not reorder: ' + ((j && j.error) || 'unknown error'), true); load(); return; }
      if (j.unchanged) {
        if (say) say('Could not move further — already at the ' + (direction === 'up' ? 'top' : 'bottom') + '.', false);
        load();
        return;
      }
      sequentialMove(item, direction, remaining - 1, say);
    }).catch(function (e) { if (say) say('Could not reorder: ' + e, true); load(); });
  }
  // REORDER-STEPS-BEGIN
  // computeReorderSteps(ids, draggedId, targetId, before) -> {direction,
  // count} | null — PURE (no DOM), so the selftest can real-execute it
  // directly in a `vm` sandbox rather than trusting a source-regex. `ids`
  // is the CURRENT sibling order (same list /api/roadmap/rank's
  // computeSiblingIds would compute server-side); the result is the
  // direction + step count of single-position /api/roadmap/rank moves
  // needed to land `draggedId` immediately before/after `targetId`.
  function computeReorderSteps(ids, draggedId, targetId, before) {
    var fromIdx = ids.indexOf(draggedId);
    var targetIdx = ids.indexOf(targetId);
    if (fromIdx === -1 || targetIdx === -1 || fromIdx === targetIdx) return null;
    var destIdx = before ? targetIdx : targetIdx + 1;
    if (fromIdx < destIdx) destIdx -= 1; // removing the dragged row shifts everything after it left by one
    var steps = destIdx - fromIdx;
    if (steps === 0) return null;
    return { direction: steps > 0 ? 'down' : 'up', count: Math.abs(steps) };
  }
  // REORDER-STEPS-END
  function performDrop(draggedId, targetId, before, say) {
    var targetEl = document.querySelector('[data-item-id="' + cssEscape(targetId) + '"]');
    var container = targetEl && planRowContainer(targetEl);
    var rows = siblingPlanRows(container);
    var ids = rows.map(function (r) { return r.dataset.itemId; });
    var move = computeReorderSteps(ids, draggedId, targetId, before);
    if (!move) return;
    var draggedItem = findItemData(draggedId) || { id: draggedId };
    // OPTIMISTIC MOVE (operator, 2026-07-30: "it actually takes several
    // seconds for the GUI to actually update after dropping the item").
    // ROOT CAUSE: a drop of N positions fires N SEQUENTIAL round-trips
    // (sequentialMove recurses one /api/roadmap/rank POST per position,
    // each awaiting the last) and only then re-renders — so the row sat
    // visibly un-moved for seconds and the drag read as broken.
    // The DOM now moves IMMEDIATELY, before any network call; the
    // persistence still runs (and still reconciles/repairs via load() on
    // failure), so a successful drop looks instant and a failed one is
    // corrected rather than silently wrong.
    var draggedEl = document.querySelector('[data-item-id="' + cssEscape(draggedId) + '"]');
    var draggedRow = draggedEl && planRowContainer(draggedEl);
    var targetRow = targetEl && planRowContainer(targetEl);
    if (draggedRow && targetRow && draggedRow.parentNode && draggedRow !== targetRow) {
      if (before) targetRow.parentNode.insertBefore(draggedRow, targetRow);
      else targetRow.parentNode.insertBefore(draggedRow, targetRow.nextSibling);
    }
    sequentialMove(draggedItem, move.direction, move.count, say);
  }
  // wirePlanRowReorder(det, sum, item) — called from renderNode for every
  // kind:"plan" row. Adds a small grip handle (draggable) into the title
  // cell and dragover/drop/keydown listeners onto the row itself.
  function wirePlanRowReorder(det, sum, item) {
    var titleCellEl = sum.querySelector('.rm-cell-title');
    if (titleCellEl) {
      var handle = el('span', 'rm-drag-handle', '⠿');
      handle.setAttribute('aria-hidden', 'true');
      handle.draggable = true;
      handle.title = 'drag to reorder';
      titleCellEl.insertBefore(handle, titleCellEl.firstChild);
    }
    // REVERTED (operator, 2026-07-30): the whole-row drag surface was my
    // own inference, not an ask — "I didn't ask you to make the whole row
    // the drag surface. Please undo that." The grip is the ONLY drag
    // handle, as Round 16 shipped it. The real defect the operator then
    // identified was latency, not hit-area: the drop fired N sequential
    // /api/roadmap/rank round-trips followed by a full roadmap re-render,
    // so the row visibly snapped back and only reordered seconds later.
    // That is fixed in performDrop (optimistic DOM move), not here.
    if (titleCellEl) {
      var gripEl = titleCellEl.querySelector('.rm-drag-handle');
      if (gripEl) {
        gripEl.addEventListener('dragstart', function (e) {
          dragState = { itemId: item.id };
          det.classList.add('rm-dragging');
          if (e.dataTransfer) {
            e.dataTransfer.effectAllowed = 'move';
            try { e.dataTransfer.setData('text/plain', item.id); } catch (_) {}
          }
        });
        gripEl.addEventListener('dragend', function () {
          det.classList.remove('rm-dragging');
          clearDropIndicators();
          dragState = null;
        });
      }
    }

    sum.addEventListener('dragover', function (e) {
      if (!dragState || dragState.itemId === item.id) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
      var r = sum.getBoundingClientRect();
      var before = (e.clientY - r.top) < r.height / 2;
      clearDropIndicators();
      sum.classList.add(before ? 'rm-drop-before' : 'rm-drop-after');
    });
    sum.addEventListener('dragleave', function () {
      sum.classList.remove('rm-drop-before', 'rm-drop-after');
    });
    sum.addEventListener('drop', function (e) {
      e.preventDefault();
      var before = sum.classList.contains('rm-drop-before');
      clearDropIndicators();
      var dragged = dragState;
      dragState = null;
      if (!dragged || dragged.itemId === item.id) return;
      performDrop(dragged.itemId, item.id, before, reorderFeedback(det));
    });

    // WCAG 2.2 2.5.7 — a non-drag path MUST exist. Cmd/Ctrl+ArrowUp/Down
    // on the focused row (a real <summary>, already natively focusable)
    // fires the SAME moveRank() the retired buttons called. Documented on
    // the row itself (title + aria-keyshortcuts), never a silent shortcut.
    sum.setAttribute('aria-keyshortcuts', 'Control+ArrowUp Control+ArrowDown Meta+ArrowUp Meta+ArrowDown');
    var existingTitle = sum.getAttribute('title');
    sum.setAttribute('title', (existingTitle ? existingTitle + ' — ' : '') + 'Cmd/Ctrl+↑/↓ to move in the build order');
    sum.addEventListener('keydown', function (e) {
      if (!(e.metaKey || e.ctrlKey)) return;
      if (e.key === 'ArrowUp') { e.preventDefault(); moveRank(item, 'up', reorderFeedback(det)); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); moveRank(item, 'down', reorderFeedback(det)); }
    });
  }

  function moveRank(item, direction, say) {
    var itemId = typeof item === 'string' ? item : item.id;
    fetch('/api/roadmap/rank', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: itemId, direction: direction }),
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.ok) {
        // R10-4 (operator: "it says it changed the ordering, but I don't
        // know what that actually means"): name WHAT moved, WHERE it now
        // sits, and WHICH group's build order — never a bare "updated".
        if (j.unchanged) {
          say('No change — this item is already at the ' + (direction === 'up' ? 'top' : 'bottom') + ' of its build order.', false);
        } else if (typeof item === 'object' && lastPayload) {
          var siblings = (lastPayload.items || []).filter(function (x) { return x.project === item.project; });
          var oldIdx = siblings.findIndex(function (x) { return x.id === itemId; });
          var newIdx = oldIdx + (direction === 'up' ? -1 : 1);
          var shortT = (item.title || itemId).slice(0, 50);
          // I5 (terminology sweep — "phases" retired): "#N of M", never
          // "phase N of M".
          say('Moved "' + shortT + '" ' + direction + ' — now #' + (newIdx + 1) + ' of ' +
            siblings.length + ' in ' + (item.project || 'this project') + "'s build order.", false);
        } else {
          say('Build order updated.', false);
        }
        load();
      }
      else { say('Could not reorder: ' + ((j && j.error) || 'unknown error'), true); }
    }).catch(function (e) { say('Could not reorder: ' + e, true); });
  }

  // ============================================================
  // tree rendering
  // ============================================================

  // R11 Critical 6 — the ACTIVE-PATH default-expansion policy. A container
  // defaults OPEN only when its SUBTREE (never merely itself) holds an
  // active thing — in-progress, a live session, or waiting-on-operator —
  // so the chain down to the active row is visible while every idle
  // sibling stays one line. The operator's explicit choices always win:
  // toggle stores true AND false (an explicit close survives re-renders;
  // the old delete-on-close made the default re-open it every tick).
  function nodeIsActive(n) {
    if (!n) return false;
    if (n.live_sessions && n.live_sessions.length) return true;
    if (!n.status) return false;
    if (n.status.value === 'in-progress') return true;
    return n.status.value === 'stalled' && n.status.reason_class === 'waiting-on-you';
  }
  function subtreeHasActive(n) {
    var lists = [n.children, n.child_plans];
    for (var li = 0; li < lists.length; li++) {
      var arr = lists[li] || [];
      for (var i = 0; i < arr.length; i++) {
        if (nodeIsActive(arr[i]) || subtreeHasActive(arr[i])) return true;
      }
    }
    return false;
  }
  function defaultOpen(item) {
    var expl = openSet[item.id];
    if (expl === true) return true;
    if (expl === false) return false;
    return subtreeHasActive(item);
  }

  function renderNode(item, topLevelIndex, topLevelCount, isNextTask) {
    var det = document.createElement('details');
    det.className = 'rm-node rm-kind-' + item.kind;
    det.dataset.itemId = item.id;
    det.tabIndex = -1; // landing target: programmatically focusable (C2)
    // Round 12 item 8: a filter match living on a DESCENDANT forces this
    // ancestor open so the match note (appended below) is reachable —
    // folded into the SAME initial-open decision defaultOpen() makes so the
    // toggle listener's deviation-tracking baseline stays correct.
    var filterMatch = currentMatchNotes[item.id];
    if (defaultOpen(item) || filterMatch) det.open = true;
    // Record only DEVIATIONS from the rendered state: the programmatic
    // default-open above also fires 'toggle', and persisting the default as
    // an explicit choice would freeze the active-path recomputation.
    var renderedOpen = det.open;
    det.addEventListener('toggle', function () {
      if (det.open === renderedOpen) return;
      renderedOpen = det.open;
      openSet[item.id] = det.open;
    });

    // Round 12 (ux-ia-auditor live audit, item 1): a CSS GRID row — fixed
    // columns, one cell appended per column, ALWAYS, even when empty (see
    // the cell builders above). Replaces the flex-wrap layout that let
    // conditionally-absent content shift every later column (measured live:
    // a 292px/346px swing in where the status chip/fraction started).
    // ROUND 13 fix 1: the dedicated marker column is RETIRED (live-measured
    // 93.75% empty — see the cell-builders comment above); markerChips now
    // renders inside titleCell, so the grid is 6 columns, not 7.
    var sum = document.createElement('summary');
    sum.className = 'rm-row';
    sum.appendChild(el('span', 'rm-chevron', '▸'));       // column 1 (16px)
    sum.appendChild(titleCell(item));                       // column 2 (1fr)
    // R11 Critical 5: a master shows its TWO labeled fractions instead of
    // the plain progress bar (never a blended single number) — spans
    // columns 3+4 (rm-cell-mastersummary, app.css); every other node keeps
    // the task-span text (column 3, item 2) + the fraction (column 4).
    if (item.master_summary) {
      var msCell = el('span', 'rm-cell rm-cell-mastersummary');
      msCell.appendChild(masterSummaryNode(item));
      sum.appendChild(msCell);
    } else {
      sum.appendChild(taskSpanCell(item, isNextTask));      // column 3 (190px)
      sum.appendChild(fractionCellForRow(item));            // column 4 (76px)
    }
    sum.appendChild(exceptionGlyphCell(item));              // column 5 (46px)
    sum.appendChild(exceptionLabelCell(item));              // column 6 (132px)
    det.appendChild(sum);

    // Round 16 deliverable 5: drag-and-drop + Cmd/Ctrl+ArrowUp/Down
    // build-order reorder — plan rows only (matches the retired buttons'
    // own kind==='plan' gate).
    if (item.kind === 'plan') wirePlanRowReorder(det, sum, item);

    // Round 12 item 8: the note is a SIBLING of summary, not inside
    // .rm-drill — it must stay visible even while the row is collapsed
    // (rm-filter-match-note is not gated by [open], unlike .rm-drill).
    if (filterMatch) {
      var matchText = 'matches: ' + (filterMatch.kind === 'task'
        ? 'task ' + shortTaskId(filterMatch.id)
        : (filterMatch.kind || 'item')) + ' — ' + (filterMatch.title || filterMatch.id);
      det.appendChild(el('div', 'rm-filter-match-note', matchText));
    }

    det.appendChild(drilldown(item));

    var kids = item.children || [];
    var childPlans = item.child_plans || [];
    // round-6 gap 3: a FULLY-COMPLETE node's children collapse into the
    // roll-up IMMEDIATELY, regardless of the per-child 7-day window — see
    // the COLLAPSE-LAW block above. item.status is only ever 'complete'
    // once every child has shipped, so this is never a false bypass.
    var parentFullyComplete = !!(item.status && item.status.value === 'complete');
    if (childPlans.length) {
      // R11 Critical 3/I1 (anatomy L2): a master's two child kinds render as
      // TWO LABELED subsections — "Plans — build order" first, then "Direct
      // tasks — task id" (I6: reuses the SAME details/summary renderNode
      // path as everything else — no bespoke markup).
      det.appendChild(renderLabeledSubsection('Plans — build order', 'rm-master-plans',
        renderChildList(childPlans, item.id, parentFullyComplete)));
      if (kids.length) {
        det.appendChild(renderLabeledSubsection('Direct tasks — task id', 'rm-master-owntasks',
          renderChildList(kids, item.id, parentFullyComplete)));
      }
    } else if (kids.length) {
      det.appendChild(renderChildList(kids, item.id, parentFullyComplete));
    }
    return det;
  }

  // renderLabeledSubsection(label, cls, contentEl) — a plain (non-collapsible)
  // labeled wrapper: the LABEL itself is not a toggle (the anatomy calls for
  // it as a caption naming the group, not another expand/collapse level);
  // the details/summary discipline lives one level down, on each row inside.
  function renderLabeledSubsection(label, cls, contentEl) {
    var wrap = el('div', 'rm-subsection ' + cls);
    wrap.appendChild(el('div', 'rm-subsection-label', label));
    wrap.appendChild(contentEl);
    return wrap;
  }

  // renderTaskBatches(liveChildren, nextId) — R11 anatomy L3: groups a
  // plan's task children into CONTIGUOUS runs sharing the same
  // (server-derived) `.batch` label, file order preserved (never
  // re-sorted); a task with `batch: ''` renders directly, un-wrapped,
  // exactly as before batching existed. nextId (Round 13 fix 4) threads
  // through so the "next" task keeps its affordance even when it happens
  // to fall inside a batch run.
  function renderTaskBatches(liveChildren, nextId) {
    var frag = document.createDocumentFragment();
    var i = 0;
    while (i < liveChildren.length) {
      var c = liveChildren[i];
      var label = c.batch || '';
      if (!label) { frag.appendChild(renderNode(c, -1, -1, c.id === nextId)); i++; continue; }
      var runEnd = i;
      while (runEnd < liveChildren.length && (liveChildren[runEnd].batch || '') === label) runEnd++;
      frag.appendChild(renderBatchRow(label, liveChildren.slice(i, runEnd), nextId));
      i = runEnd;
    }
    return frag;
  }

  // renderBatchRow — I6: reuses the details/summary disclosure pattern (a11y
  // by construction); VERBATIM label + a "done/total" fraction chip.
  // Defaults OPEN (a batch carries no attention state of its own — the
  // roll-up law already surfaces attention on the tasks inside); an explicit
  // operator close is remembered for this session (own key namespace, does
  // not collide with the item-id-keyed openSet entries elsewhere).
  function renderBatchRow(label, tasks, nextId) {
    var key = 'batch:' + (tasks[0] && tasks[0].id || label);
    var det = document.createElement('details');
    det.className = 'rm-batch';
    det.open = openSet.hasOwnProperty(key) ? openSet[key] : true;
    det.addEventListener('toggle', function () {
      if (det.open) delete openSet[key]; else openSet[key] = false;
    });
    var sum = document.createElement('summary');
    sum.className = 'rm-batch-summary';
    sum.appendChild(el('span', 'rm-chevron', '▸'));
    sum.appendChild(el('span', 'rm-batch-label', label));
    var done = tasks.filter(function (t) { return t.status && t.status.value === 'complete'; }).length;
    sum.appendChild(el('span', 'chip rm-batch-fraction', done + '/' + tasks.length));
    det.appendChild(sum);
    var body = el('div', 'rm-children');
    tasks.forEach(function (t) { body.appendChild(renderNode(t, -1, -1, t.id === nextId)); });
    det.appendChild(body);
    return det;
  }

  // renderChildList — applies COMPLETED AGING per parent (round 4 + I2):
  // complete children inside the window stay in place (collapsed, headline
  // keeps "completed <when>"); complete children PAST the window fold into
  // ONE per-parent roll-up row: "N completed ▸ — latest: <title>". A
  // FULLY-COMPLETE parent (parentFullyComplete) bypasses the window
  // entirely — round-6 gap 3. Sibling PLAN nodes render as a connected,
  // numbered series (round-6 gap 6 — the operator's "phase one through
  // four" mental model).
  function renderChildList(children, parentId, parentFullyComplete) {
    var wrap = el('div', 'rm-children');
    var part = partitionChildren(children, !!parentFullyComplete, agedOut);
    var live = part.live, aged = part.aged;
    var phaseSeries = isPhaseSeries(children);
    if (phaseSeries) wrap.classList.add('rm-phase-series');
    // Round 13 fix 4: the "next" affordance applies to TASK children only
    // (a phase-series list is child PLANS, which get their own "n next"
    // via the parent's task-span text one level up, not this per-child
    // marker) — computed from the SAME firstOpenChildId the parent's own
    // taskSpanCell(item) already calls via deriveTaskSpanLabel(item.children),
    // over the full unpartitioned list so the flagged child is always the
    // identical id the parent's own text names "next".
    var nextId = phaseSeries ? null : firstOpenChildId(children);
    // R11 Critical 1/2 (anatomy L3): task children carrying a `.batch` label
    // render as grouped batch rows — "batch rows only when the file carries
    // them" (a plan with no batch structure renders its tasks directly,
    // unchanged). Batches never apply to child-PLAN nesting (phaseSeries).
    var hasBatches = !phaseSeries && live.some(function (c) { return c.batch; });
    if (hasBatches) {
      wrap.appendChild(renderTaskBatches(live, nextId));
    } else {
      live.forEach(function (c) {
        // Round 12 item 3: buildOrderLabel is no longer rendered (retired
        // "#N OF 16" ordinal — proven unstable); the connector line
        // (rm-phase-step, below) still marks the sibling sequence visually.
        var node = renderNode(c, -1, -1, c.id === nextId);
        if (phaseSeries) {
          var step = el('div', 'rm-phase-step');
          step.appendChild(node);
          wrap.appendChild(step);
        } else {
          wrap.appendChild(node);
        }
      });
    }
    if (aged.length) {
      aged.sort(function (a, b) { return String(b.completed_at).localeCompare(String(a.completed_at)); });
      var roll = document.createElement('details');
      roll.className = 'rm-completed-rollup';
      roll.dataset.rollupFor = parentId;
      if (openSet['rollup:' + parentId]) roll.open = true;
      roll.addEventListener('toggle', function () {
        if (roll.open) openSet['rollup:' + parentId] = true; else delete openSet['rollup:' + parentId];
      });
      var rsum = document.createElement('summary');
      rsum.className = 'rm-completed-rollup-summary';
      // count + one exemplar for scent (severity-1 fold from the UX review)
      rsum.textContent = aged.length + ' completed ▸ — latest: ' + (aged[0].title || aged[0].id);
      roll.appendChild(rsum);
      var rbody = el('div', 'rm-children');
      aged.forEach(function (c) { rbody.appendChild(renderNode(c, -1, -1)); });
      roll.appendChild(rbody);
      wrap.appendChild(roll);
    }
    return wrap;
  }

  // TOP-GROUP-BEGIN
  // R17 Round 17 deliverable 4 (operator 2026-07-30, decision A —
  // multi-project grouping). ABOVE the existing per-project grouping
  // (groupItemsByProject/projectGroupHeaderText, unchanged below), plans
  // now render under up to three canonical top-level DISPLAY groups, in
  // this fixed order: "Neural Lace" (this repo, always present), "Pocket
  // Technician" (Circuit's plans, when configured), "Personal" (always
  // rendered too, even with zero plans — an honest "no projects
  // configured" line rather than the group silently vanishing). Any
  // OTHER group name the server's data actually produces (e.g. the
  // '(ungrouped)' catch-all a flat-string, no-`group` config entry lands
  // in) is appended after the canonical three, in first-appearance order.
  // The mapping itself (which project belongs to which group) is
  // server-computed (`item.project_group`, from config/projects.json) —
  // this is purely a client-side DISPLAY partition over data the server
  // already grouped, never a client-side guess at project membership.
  var CANONICAL_TOP_GROUPS = ['Neural Lace', 'Pocket Technician', 'Personal'];
  function groupItemsByTopGroup(items) {
    var byGroup = {};
    var order = [];
    CANONICAL_TOP_GROUPS.forEach(function (g) { byGroup[g] = []; order.push(g); }); // always present, even empty
    (items || []).forEach(function (it) {
      var g = it.project_group || '(ungrouped)';
      if (!byGroup[g]) { byGroup[g] = []; order.push(g); }
      byGroup[g].push(it);
    });
    return order.map(function (g) { return { group: g, items: byGroup[g] }; });
  }
  // topGroupHasInProgress(items) — "in progress" here means the same
  // "not not-started and not complete" band bandPlanItems already uses
  // for its first band (in-progress/stalled/merged-unverified/unknown);
  // drives the group's collapsed-by-default state (renderTopGroup below).
  function topGroupHasInProgress(items) {
    return (items || []).some(function (it) {
      return it.status && it.status.value !== 'not-started' && it.status.value !== 'complete';
    });
  }
  function topGroupHeaderText(groupName, items) {
    var count = (items || []).length;
    if (!count) return groupName + ' — no projects configured';
    return groupName + ' — ' + count + (count === 1 ? ' plan' : ' plans');
  }
  function renderTopGroup(groupName, items) {
    var det = document.createElement('details');
    det.className = 'rm-top-group';
    det.dataset.topGroup = groupName;
    var openKey = 'topgroup:' + groupName;
    var defaultOpen = topGroupHasInProgress(items);
    det.open = Object.prototype.hasOwnProperty.call(openSet, openKey) ? !!openSet[openKey] : defaultOpen;
    det.addEventListener('toggle', function () { openSet[openKey] = det.open; });
    var sum = document.createElement('summary');
    sum.className = 'rm-top-group-head';
    sum.textContent = topGroupHeaderText(groupName, items);
    det.appendChild(sum);
    var bodyEl = el('div', 'rm-top-group-body');
    if (!items.length) {
      bodyEl.appendChild(el('div', 'rm-empty-note', 'no projects configured'));
    } else {
      bodyEl.appendChild(renderProjectGroups(items));
    }
    det.appendChild(bodyEl);
    return det;
  }
  function renderTree(visibleItems) {
    var outer = el('div', 'rm-tree');
    groupItemsByTopGroup(visibleItems).forEach(function (tg) {
      outer.appendChild(renderTopGroup(tg.group, tg.items));
    });
    return outer;
  }
  // TOP-GROUP-END

  // renderProjectGroups(visibleItems) — the PRE-R17 renderTree body,
  // unchanged: per-project grouping (R9-2), in-progress/upcoming banding
  // (Round 15), and the Shipped roll-up — now scoped to ONE top-level
  // group's items at a time (renderTree above calls this once per group,
  // so "Keep in-progress→upcoming→shipped banding WITHIN each group"
  // holds by construction: nothing below this line changed, only WHO
  // calls it and with WHAT SUBSET of items).
  function renderProjectGroups(visibleItems) {
    var tree = el('div', 'rm-tree');
    var live = [], shipped = [];
    // Round 12 item 6 (operator: "each bundle of tasks should roll up and
    // compact when all children tasks are complete... When an entire plan
    // completes, it rolls up into the completed section"): a fully-complete
    // PLAN leaves the main list on STATUS ALONE, never gated on the 7-day
    // aging clock — that clock is fed by completed_at, which falls back to
    // the plan FILE's mtime when no task_done event exists
    // (roadmap-routes.js:1001), and this machine's continuous
    // session-start-auto-install sync keeps touching that mtime, resetting
    // the 7-day countdown indefinitely (ROADMAP-COMPLETED-AGING-MTIME-
    // RESET-01 — server-side, out of this task's scope; this fix makes
    // "Shipped" independent of that clock entirely). Opening a shipped
    // plan still renders ALL its own tasks via the SAME renderNode/
    // renderChildList path (unchanged) — only the top-level list membership
    // changed, never what's visible once you open one.
    visibleItems.forEach(function (it) {
      var isComplete = it.status && it.status.value === 'complete';
      if (isComplete) shipped.push(it); else live.push(it);
    });
    // Round 8 (8A): the tree roots on PLANS — the top level is the
    // operator's "series of phases". Round 9 (R9-2): grouped by PROJECT —
    // a flat cross-project series ("PHASE 1 OF 16") implies membership in
    // nothing (operator audit row 2). Phases number WITHIN their group;
    // reorder buttons keep operating on the true GLOBAL build-order
    // position (renderNode receives the item's index in `live`, never the
    // group-local one).
    var phaseSeries = isPhaseSeries(live);
    if (phaseSeries) tree.classList.add('rm-phase-series');
    // Round 12 item 6: the per-project header still reports the project's
    // TRUE overall progress (incl. shipped plans) — "how far through" the
    // operator asked for — even though shipped rows themselves now live in
    // the separate Shipped group below, not in this list.
    var projectTotals = {};
    groupItemsByProject(visibleItems).forEach(function (g) { projectTotals[g.project] = g.items; });
    var groups = phaseSeries ? groupItemsByProject(live) : [{ project: '', items: live }];
    groups.forEach(function (g) {
      var container = tree;
      if (phaseSeries) {
        var allForProject = projectTotals[g.project] || g.items;
        var groupEl = el('section', 'rm-project-group');
        groupEl.setAttribute('aria-label', 'project ' + (g.project || '(no project)'));
        var head = el('div', 'rm-project-group-head');
        // Round 12 item 3: R10-3's aggregate bar + "N/M complete" text is
        // RETIRED — it restated the header's OWN "... complete" bucket
        // count a third time on the same screen (live-verified:
        // "neural-lace — 16 plans... (2 complete)" immediately followed by
        // a separate "2/16 complete" line). projectGroupHeaderText already
        // carries the complete count; nothing else said it a second way.
        head.appendChild(el('span', 'rm-group-head-text', projectGroupHeaderText(g.project, allForProject)));
        groupEl.appendChild(head);
        tree.appendChild(groupEl);
        container = groupEl;
      }
      // Round 15: in-progress-ish plans render before upcoming ones WITHIN
      // this project's own list (bandPlanItems) — rank order is preserved
      // inside each band; `live.indexOf(it)`/`live.length` below still
      // reference the ORIGINAL flat list, so reorder buttons keep operating
      // on the true global build-order position exactly as before (R9-2d).
      bandPlanItems(g.items).forEach(function (it) {
        // Round 12 item 3: no ordinal label passed (buildOrderLabel is
        // retired from rendering — see the PHASE-SERIES-BEGIN note); the
        // rm-phase-step wrapper stays for the series connector line only.
        var node = renderNode(it, live.indexOf(it), live.length);
        if (phaseSeries) {
          var step = el('div', 'rm-phase-step');
          step.appendChild(node);
          container.appendChild(step);
        } else {
          container.appendChild(node);
        }
      });
    });
    if (shipped.length) {
      shipped.sort(function (a, b) { return String(b.completed_at).localeCompare(String(a.completed_at)); });
      var roll = document.createElement('details');
      roll.className = 'rm-completed-rollup rm-shipped-group';
      roll.dataset.rollupFor = '(top)';
      if (openSet['rollup:(top)']) roll.open = true;
      roll.addEventListener('toggle', function () {
        if (roll.open) openSet['rollup:(top)'] = true; else delete openSet['rollup:(top)'];
      });
      var rsum = document.createElement('summary');
      rsum.className = 'rm-completed-rollup-summary';
      // Round 12 item 6: "Shipped (n)" — the operator's own heading, not a
      // restatement of the header counts (which now describe the WHOLE
      // project, shipped included) or the nested per-parent "N completed"
      // wording (task 3's unchanged, still-aging-gated mechanism).
      rsum.textContent = 'Shipped (' + shipped.length + ') — latest: ' + (shipped[0].title || shipped[0].id);
      roll.appendChild(rsum);
      var rbody = el('div', 'rm-children');
      shipped.forEach(function (c) { rbody.appendChild(renderNode(c, -1, -1)); });
      roll.appendChild(rbody);
      tree.appendChild(roll);
    }
    return tree;
  }

  // ============================================================
  // kanban rendering (I3): unit-of-card = TOP-LEVEL roadmap items.
  // ============================================================
  function renderKanban(visibleItems) {
    var board = el('div', 'rm-kanban');
    // R11 I4: cards are PLANS — a master is never a card (its status is
    // derived; mixing kinds breaks column semantics). Its child plans ARE
    // cards, each carrying a master chip so the grouping stays readable.
    var cardEntries = [];
    visibleItems.forEach(function (it) {
      if (it.master_summary) {
        (it.child_plans || []).forEach(function (cp) {
          cardEntries.push({ item: cp, masterTitle: it.title });
        });
      } else {
        cardEntries.push({ item: it, masterTitle: null });
      }
    });
    KANBAN_COLUMNS.forEach(function (col) {
      var cards = cardEntries.filter(function (e) { return (e.item.status && e.item.status.value) === col; });
      if (KANBAN_EXCEPTIONAL[col] && cards.length === 0) return; // R5: exceptional columns only when non-empty
      var colEl = el('section', 'rm-kanban-col rm-kanban-col-' + col);
      colEl.setAttribute('aria-label', KANBAN_COLUMN_LABEL[col]);
      colEl.appendChild(el('div', 'rm-kanban-col-head', KANBAN_COLUMN_LABEL[col] + ' (' + cards.length + ')'));
      cards.forEach(function (entry) {
        var it = entry.item;
        var card = el('div', 'rm-card');
        card.dataset.itemId = it.id;
        card.tabIndex = -1;
        var cardTitle = el('div', 'rm-card-title', it.title);
        cardTitle.title = it.id; // R9-1: slug as tooltip here too
        card.appendChild(cardTitle);
        var chipRow = el('div', 'rm-card-chips');
        if (entry.masterTitle) chipRow.appendChild(el('span', 'chip rm-master-tag', entry.masterTitle)); // I4
        if (it.project) chipRow.appendChild(el('span', 'chip rm-project-tag', it.project)); // R9-3
        // Round 12 item 4 fix: statusChip(it) returns null for the three
        // DERIVABLE states now (not-started/in-progress/complete) — the
        // column header itself already names the status ("In progress
        // (4)"), so this was ALSO redundant there, same as the tree row;
        // appendChild(null) threw and silently aborted the whole board
        // render before this guard (regression caught live, fixed same
        // commit). Exception-state cards (stalled/merged-unverified/
        // unknown) still show the loud chip — same chips as the tree (I3).
        var kanbanChip = statusChip(it);
        if (kanbanChip) chipRow.appendChild(kanbanChip);
        var prog = progressNode(it);
        if (prog) chipRow.appendChild(prog);
        chipRow.appendChild(rollupBadges(it));
        chipRow.appendChild(markerChips(it));
        card.appendChild(chipRow);
        card.appendChild(btn('ghost small rm-card-open', 'Open in tree', function () {
          setViewMode('tree');
          expandPathTo(it.id);
        }));
        board.appendChild(colEl);
        colEl.appendChild(card);
      });
      if (cards.length === 0) colEl.appendChild(el('div', 'pane-empty rm-kanban-empty', 'nothing here'));
      board.appendChild(colEl);
    });
    return board;
  }

  // ============================================================
  // toolbar controls
  // ============================================================
  function setViewMode(mode) {
    viewMode = mode === 'kanban' ? 'kanban' : 'tree';
    lsSet(LS_VIEW_MODE, viewMode);
    syncToolbar();
    renderAll();
  }
  if (kanbanToggle) {
    kanbanToggle.addEventListener('click', function () {
      setViewMode(viewMode === 'kanban' ? 'tree' : 'kanban');
    });
  }
  if (choreToggle) {
    choreToggle.addEventListener('click', function () {
      showChores = !showChores;
      lsSet(LS_SHOW_CHORES, showChores ? '1' : '0');
      syncToolbar();
      renderAll();
    });
  }
  if (filterInput) filterInput.addEventListener('input', function () { renderAll(); });

  function syncToolbar() {
    if (kanbanToggle) kanbanToggle.setAttribute('aria-pressed', String(viewMode === 'kanban'));
    if (choreToggle) {
      choreToggle.setAttribute('aria-pressed', String(showChores));
      var hidden = lastPayload ? (lastPayload.items || []).filter(function (i) { return i.provenance === 'machine'; }).length : 0;
      choreToggle.textContent = showChores
        ? 'showing harness chores — hide'
        : (hidden + ' hidden (harness chores)');
      choreToggle.title = 'harness chores are machine-filed items (by provenance, not topic) — click to ' + (showChores ? 'hide' : 'show');
    }
  }

  function renderProjectChips() {
    if (!projectChipsWrap || !lastPayload) return;
    var focusKey = document.activeElement && document.activeElement.dataset && document.activeElement.dataset.focusKey;
    projectChipsWrap.innerHTML = '';
    var projects = {};
    (lastPayload.items || []).forEach(function (i) { if (i.project) projects[i.project] = true; });
    Object.keys(projects).sort().forEach(function (p) {
      var pressed = selectedProjects.indexOf(p) !== -1;
      var chip = btn('chip rm-project-chip', p, function () {
        var i = selectedProjects.indexOf(p);
        if (i === -1) selectedProjects.push(p); else selectedProjects.splice(i, 1);
        lsSet(LS_PROJECT_CHIPS, JSON.stringify(selectedProjects));
        renderProjectChips();
        renderAll();
      });
      chip.setAttribute('aria-pressed', String(pressed));
      chip.dataset.focusKey = 'proj:' + p;
      projectChipsWrap.appendChild(chip);
    });
    if (focusKey) {
      var again = projectChipsWrap.querySelector('[data-focus-key="' + focusKey.replace(/"/g, '\\"') + '"]');
      if (again) again.focus();
    }
  }

  function clearAllFilters() {
    if (filterInput) filterInput.value = '';
    selectedProjects = [];
    lsSet(LS_PROJECT_CHIPS, '[]');
    renderProjectChips();
    renderAll();
  }

  // ============================================================
  // four UI states + the state-preserving master render (C4 + C7)
  // ============================================================
  function renderLoadingState() {
    body.innerHTML = '';
    var box = el('div', 'pane-loading', 'deriving roadmap…');
    box.setAttribute('aria-busy', 'true');
    body.appendChild(box);
  }

  function renderErrorState(message) {
    // NEVER the empty state on failure (the app.js:185 law).
    body.innerHTML = '';
    var box = el('div', 'pane-error');
    box.setAttribute('role', 'alert');
    box.appendChild(el('div', 'pane-error-title', 'Could not derive the roadmap'));
    box.appendChild(el('div', 'pane-error-cmd', String(message || 'unknown error — the server may be restarting')));
    box.appendChild(btn('btn-go small', 'Retry', function () { load(); }));
    body.appendChild(box);
  }

  function renderEmptyStates(f) {
    // TRUE-empty vs FILTERED-empty are DIFFERENT states (C4).
    var box = el('div', 'rm-empty');
    var totalItems = (lastPayload.items || []).length;
    if (totalItems === 0) {
      box.appendChild(el('div', 'pane-empty',
        'Nothing on the roadmap yet. Items arrive automatically as sessions capture your requests — nothing to set up.'));
      return box;
    }
    var desc = [];
    if (filterText()) desc.push('"' + filterText() + '"');
    if (selectedProjects.length) desc.push('project ' + selectedProjects.join(', '));
    if (f.filtered) {
      var line = el('div', 'pane-empty', 'no items match ' + (desc.join(' + ') || 'the current filter') + ' ');
      line.appendChild(btn('ghost small', 'clear filters', clearAllFilters));
      box.appendChild(line);
    }
    if (f.hiddenChores > 0) {
      var choreLine = el('div', 'pane-empty rm-chore-note', f.hiddenChores + ' items hidden (harness chores) ');
      choreLine.appendChild(btn('ghost small', 'show', function () {
        showChores = true; lsSet(LS_SHOW_CHORES, '1'); syncToolbar(); renderAll();
      }));
      box.appendChild(choreLine);
    }
    if (!f.filtered && f.hiddenChores === 0) {
      box.appendChild(el('div', 'pane-empty', 'no items to show'));
    }
    return box;
  }

  // captureUiState/restoreUiState — the C7 law: any auto-refreshing surface
  // preserves expansion + scroll + focus. openSet is maintained live by the
  // toggle listeners; here we capture the rest. ROUND 16: the uncommitted-
  // title-edit capture that used to live here (T3-fix1, comprehension gate
  // FAIL conf 6) is retired ALONG WITH the edit feature itself (deliverable
  // 4) — there is no more `.rm-title-input` for it to ever find, so this is
  // a genuine removal, not a stale no-op left behind.
  // CAPTURE-UI-STATE-BEGIN
  function captureUiState() {
    var st = { scrollY: window.scrollY, bodyScrollTop: body.scrollTop, focusKey: null };
    var ae = document.activeElement;
    if (ae && body.contains(ae)) {
      if (ae.dataset && ae.dataset.focusKey) st.focusKey = ae.dataset.focusKey;
      else if (ae.dataset && ae.dataset.itemId) st.focusKey = 'item:' + ae.dataset.itemId;
    }
    return st;
  }
  // CAPTURE-UI-STATE-END

  function restoreUiState(st) {
    if (!st) return;
    window.scrollTo(0, st.scrollY);
    body.scrollTop = st.bodyScrollTop;
    if (st.focusKey) {
      var sel = st.focusKey.indexOf('item:') === 0
        ? '[data-item-id="' + cssEscape(st.focusKey.slice(5)) + '"]'
        : '[data-focus-key="' + cssEscape(st.focusKey) + '"]';
      var elAgain = body.querySelector(sel);
      if (elAgain) elAgain.focus();
    }
    if (landingId) {
      var landed = findItemEl(landingId);
      if (landed) landed.classList.add('landing-highlight');
    }
  }

  function cssEscape(s) {
    return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\\]]/g, '\\$&');
  }

  function renderAll() {
    if (!lastPayload) return;
    var st = captureUiState();
    var f = applyFilters(lastPayload.items || []);
    currentMatchNotes = f.matchNoteById || {}; // Round 12 item 8
    body.innerHTML = '';
    var ub = lastPayload.unbound_sessions;
    if (ub && ub.live_sessions && ub.live_sessions.length) {
      body.appendChild(renderUnboundSessions(ub));
    }
    if (f.visible.length === 0) {
      body.appendChild(renderEmptyStates(f));
    } else {
      body.appendChild(viewMode === 'kanban' ? renderKanban(f.visible) : renderTree(f.visible));
      // Round 12 item 3: the footer "N items hidden (harness chores) show"
      // note RETIRED here — it duplicated the toolbar's OWN chore toggle
      // (roadmapChoreToggle, syncToolbar()), ~700px above this footer on a
      // populated list, and its copy carried a grammar defect ("1 items
      // hidden") the toolbar's own text never had. The toolbar control is
      // ALWAYS visible (static DOM, outside #roadmapBody) so nothing is
      // lost by removing this duplicate. The FILTERED/TRUE-empty state's
      // OWN hidden-chores line (renderEmptyStates) is UNCHANGED — that one
      // explains an otherwise-confusing "0 items" moment, a different
      // purpose than restating an already-visible toolbar control.
    }
    // Ghost-bounding aggregate (2026-07-21): ask-linked plans whose file
    // could not be found AND whose newest link is older than the aging
    // window are excluded from the tree entirely (never 150+ dead roots)
    // but named here as ONE honest count — never a silent drop (C5).
    var staleOmitted = lastPayload.stale_links_omitted || 0;
    if (staleOmitted > 0) {
      body.appendChild(el('div', 'rm-chore-note rm-stale-links-note',
        staleOmitted + ' linked plan' + (staleOmitted === 1 ? '' : 's') + ' not found (too old to show individually — still tracked in Requests)'));
    }
    restoreUiState(st);
  }

  // ============================================================
  // data loading — 30s poll, STALE on failure, never a DOM wipe (C7)
  // ============================================================
  function load() {
    var firstLoad = !lastPayload;
    if (firstLoad) renderLoadingState();
    return fetch('/api/roadmap')
      .then(function (r) { return r.json(); })
      .then(function (j) {
        if (!j || j.ok === false) {
          lastFetchFailed = true;
          setAgeLabel();
          if (!lastPayload) renderErrorState(j && j.error);
          return;
        }
        lastPayload = j;
        lastFetchFailed = false;
        lastDerivedAt = j.generated_at;
        setAgeLabel();
        syncToolbar();
        renderProjectChips();
        renderAll();
        var q = whenLoadedQueue.splice(0);
        q.forEach(function (cb) { try { cb(); } catch (_) {} });
      })
      .catch(function (err) {
        lastFetchFailed = true;
        setAgeLabel();
        if (!lastPayload) renderErrorState(String(err)); // keep last-good DOM otherwise — STALE label carries the truth
      });
  }

  function whenLoaded(cb) {
    if (lastPayload) cb(); else whenLoadedQueue.push(cb);
  }

  // ============================================================
  // item lookup + path expansion (landing + roll-up badge clicks)
  // ============================================================
  function findItemEl(id) {
    return body.querySelector('[data-item-id="' + cssEscape(id) + '"]');
  }
  // R11: both traversals now ALSO recurse into `child_plans` (a master's
  // resolved children — Critical 3/4), not just `children` (own tasks) —
  // a nested child plan must stay hash-addressable/expandable exactly like
  // any other item.
  function findItemData(id, list) {
    var items = list || (lastPayload && lastPayload.items) || [];
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === id) return items[i];
      var hit = findItemData(id, items[i].children || []) || findItemData(id, items[i].child_plans || []);
      if (hit) return hit;
    }
    return null;
  }
  function pathTo(id, list, trail) {
    var items = list || (lastPayload && lastPayload.items) || [];
    for (var i = 0; i < items.length; i++) {
      var t = (trail || []).concat([items[i].id]);
      if (items[i].id === id) return t;
      var hit = pathTo(id, items[i].children || [], t) || pathTo(id, items[i].child_plans || [], t);
      if (hit) return hit;
    }
    return null;
  }

  // expandPathTo(id) — opens every ancestor (and the aged-completed roll-up
  // group when the target lives inside one), then focuses + highlights.
  function expandPathTo(id) {
    var trail = pathTo(id);
    if (!trail) return null;
    if (viewMode === 'kanban' && trail.length > 1) {
      // nested targets only exist in the tree — switch honestly (persisted:
      // the operator SEES the mode change and can toggle back).
      setViewMode('tree');
    }
    trail.forEach(function (tid) { openSet[tid] = true; });
    // aged-completed roll-up groups on the trail must open too
    openSet['rollup:(top)'] = openSet['rollup:(top)'] || false;
    renderAll();
    var target = findItemEl(id);
    if (!target) {
      // target may sit inside a closed aged-completed group — open them all
      body.querySelectorAll('.rm-completed-rollup').forEach(function (d) { d.open = true; });
      target = findItemEl(id);
    }
    if (target) {
      if (shell && shell.applyLanding) shell.applyLanding(target, { returnAffordance: false });
      else { target.scrollIntoView({ block: 'center' }); target.focus(); }
    }
    return target;
  }

  // ============================================================
  // shell registration — the 'roadmap' view adapter (C2). Tasks 4-5
  // register their own views through this same API.
  // ============================================================
  if (shell && shell.registerView) {
    shell.registerView('roadmap', {
      // landOn(id, done) — done(el|null); the shell applies the landed
      // state (scroll + highlight + focus + return affordance) on el.
      landOn: function (id, done) {
        whenLoaded(function () {
          var target = expandPathTo(id);
          landingId = target ? id : null;
          done(target || null);
        });
      },
      // missInfo(id, cb) — the C3 stale-link rule: never blank/404.
      missInfo: function (id, cb) {
        whenLoaded(function () {
          var data = findItemData(id);
          if (data && data.completed_at) {
            cb('resolved ' + formatAge(data.completed_at) + ' — completed');
          } else {
            cb('This item is no longer on the roadmap — it may have completed and aged out, or been merged into another item.');
          }
        });
      },
      snapshotState: function () {
        return { openSet: Object.assign({}, openSet), scrollY: window.scrollY, bodyScrollTop: body.scrollTop };
      },
      restoreState: function (s) {
        if (!s) return;
        openSet = Object.assign({}, s.openSet);
        renderAll();
        window.scrollTo(0, s.scrollY);
        body.scrollTop = s.bodyScrollTop;
      },
      onShow: function () { if (!lastPayload) load(); },
      clearLanding: function () {
        landingId = null;
        var prev = body.querySelector('.landing-highlight');
        if (prev) prev.classList.remove('landing-highlight');
      },
    });
  }

  // ============================================================
  // R9-6 sidebar (operator audit row 6): compact My-items + Backlog panes
  // on the landing. Same GET/POST /api/todo and GET /api/backlog contracts
  // as inbox.js "My items" and backlog.js — one writer (the server), two
  // compact mirrors; full editing stays on the Inbox/Requests surfaces.
  // Collapsed state persists (localStorage, kanban-toggle discipline);
  // My-items reloads once at boot + after every write (inbox.js precedent:
  // never on the 30s tick, so an in-flight click is never destroyed);
  // Backlog is read-only here and MAY refresh on the tick safely.
  // ============================================================
  var LS_SIDE_MYITEMS = 'rm.side.myitems.open';
  var LS_SIDE_BACKLOG = 'rm.side.backlog.open';
  var SIDE_LIST_CAP = 8; // compact pane: cap rows, name the remainder

  function sidePaneBoot(paneId, lsKey) {
    var pane = document.getElementById(paneId);
    if (!pane) return null;
    var saved = lsGet(lsKey);
    if (saved === '0') pane.open = false;
    pane.addEventListener('toggle', function () { lsSet(lsKey, pane.open ? '1' : '0'); });
    return pane;
  }

  function loadSideMyItems() {
    var bodyEl = document.getElementById('rmMyItemsBody');
    var countEl = document.getElementById('rmMyItemsCount');
    if (!bodyEl) return;
    // R9 follow-up (operator 2026-07-24: "why don't I see anything on my
    // to-do list? you just told me something was waiting on me"): the
    // operator's mental model of "my list" is EVERYTHING waiting on them —
    // which lives in the Inbox's answerable set, not only the todo file
    // (whose auto-pointer splice also lands pre-checked — needs-you.sh bug,
    // nl-issue filed). Both sources render here; the Inbox stays canonical.
    Promise.all([
      fetch('/api/todo').then(function (r) { return r.json(); }).catch(function () { return null; }),
      fetch('/api/inbox').then(function (r) { return r.json(); }).catch(function () { return null; }),
    ]).then(function (both) {
      var j = both[0];
      var inbox = both[1];
      if (!j || j.ok === false) {
        bodyEl.innerHTML = '';
        bodyEl.appendChild(el('div', 'rm-side-error', 'could not load — retry on next tick'));
        if (countEl) countEl.textContent = '(!)';
        return;
      }
      // Round 12 item 9 (inbox count honesty): pre-fix, an /api/inbox
      // failure was silently treated as answerable=[] — an UNREADABLE
      // ledger and a GENUINELY EMPTY one rendered the identical confident
      // "nothing on your list" line. An unreadable ledger is UNKNOWN, never
      // a silent zero — this is the landing surface (the Roadmap tab), so
      // the error must surface HERE, not only inside the Inbox tab itself.
      var inboxFailed = !inbox || inbox.ok === false;
      var answerable = inboxFailed ? [] : (inbox.answerable || []);
      var ops = j.operator_items || [];
      var ptrs = (j.pointer_items || []).filter(function (p) { return !p.checked; });
      var openOpsCount = ops.filter(function (o) { return !o.checked; }).length;
      if (countEl) {
        countEl.textContent = inboxFailed
          ? '(!)'
          : '(' + (answerable.length + openOpsCount + ptrs.length) + ' open)';
      }
      bodyEl.innerHTML = '';
      if (inboxFailed) {
        bodyEl.appendChild(el('div', 'rm-side-error', 'Inbox: could not load — retry on next tick'));
      }
      if (answerable.length) {
        var wlist = el('ul', 'rm-side-list');
        answerable.slice(0, SIDE_LIST_CAP).forEach(function (item) {
          var li = el('li', 'rm-side-item rm-side-waiting');
          var t = item.title || item.ask || item.id;
          var goBtn = btn('ghost small rm-side-go', t.length > 90 ? t.slice(0, 90) + '…' : t, function () {
            if (shell) shell.navigate('#inbox/' + encodeURIComponent(item.id));
          });
          goBtn.title = item.ask || t;
          li.appendChild(el('span', 'rm-side-glyph', item.kind === 'decision' ? '◆' : '▸'));
          li.appendChild(goBtn);
          wlist.appendChild(li);
        });
        bodyEl.appendChild(el('div', 'rm-side-tiers', answerable.length + ' waiting on you (Inbox):'));
        bodyEl.appendChild(wlist);
      }
      // The confident "nothing on your list" win-line renders ONLY when
      // every source actually reported zero — never when the Inbox source
      // is unknown (inboxFailed).
      if (!inboxFailed && !answerable.length && !ops.length && !ptrs.length) {
        bodyEl.appendChild(el('div', 'rm-side-empty', 'nothing on your list'));
        return;
      }
      if (inboxFailed && !ops.length && !ptrs.length) return; // the error note above already said so
      if (!ops.length && !ptrs.length) return;
      var list = el('ul', 'rm-side-list');
      ops.forEach(function (item) {
        var li = el('li', 'rm-side-item');
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.checked = !!item.checked;
        cb.setAttribute('aria-label', (item.checked ? 'mark not done: ' : 'mark done: ') + item.text);
        cb.addEventListener('change', function () {
          cb.disabled = true;
          fetch('/api/todo', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'toggle', index: item.index }),
          }).then(function (r) { return r.json(); }).then(function (r) {
            if (r && r.ok) { loadSideMyItems(); }
            else { cb.checked = !cb.checked; cb.disabled = false; }
          }).catch(function () { cb.checked = !cb.checked; cb.disabled = false; });
        });
        li.appendChild(cb);
        li.appendChild(el('span', 'rm-side-text' + (item.checked ? ' rm-side-done' : ''), item.text));
        list.appendChild(li);
      });
      ptrs.slice(0, SIDE_LIST_CAP).forEach(function (p) {
        var li = el('li', 'rm-side-item rm-side-pointer');
        var t = p.title || p.needs_you_id;
        li.appendChild(el('span', 'rm-side-glyph', '?'));
        var span = el('span', 'rm-side-text', t.length > 90 ? t.slice(0, 90) + '…' : t);
        span.title = t;
        li.appendChild(span);
        list.appendChild(li);
      });
      if (ptrs.length > SIDE_LIST_CAP) {
        list.appendChild(el('li', 'rm-side-item rm-side-more', '+' + (ptrs.length - SIDE_LIST_CAP) + ' more in the Inbox'));
      }
      bodyEl.appendChild(list);
    }).catch(function () {
      bodyEl.innerHTML = '';
      bodyEl.appendChild(el('div', 'rm-side-error', 'could not load — retry on next tick'));
      if (countEl) countEl.textContent = '(!)'; // Round 12 item 9
    });
  }

  function loadSideBacklog() {
    var bodyEl = document.getElementById('rmBacklogBody');
    var countEl = document.getElementById('rmBacklogCount');
    if (!bodyEl) return;
    fetch('/api/backlog').then(function (r) { return r.json(); }).then(function (j) {
      if (!j || j.ok === false) {
        bodyEl.innerHTML = '';
        bodyEl.appendChild(el('div', 'rm-side-error', 'could not load — retry on next tick'));
        if (countEl) countEl.textContent = '(!)'; // Round 12 item 9
        return;
      }
      var counts = j.counts || {};
      if (countEl) countEl.textContent = '(' + (counts.open_total || 0) + ' open)';
      bodyEl.innerHTML = '';
      var byTier = counts.by_tier || {};
      var tierLine = ['high', 'medium', 'low'].filter(function (t) { return byTier[t]; })
        .map(function (t) { return byTier[t] + ' ' + t; }).join(' · ');
      if (tierLine) bodyEl.appendChild(el('div', 'rm-side-tiers', tierLine));
      var compact = j.compact || {};
      var list = el('ul', 'rm-side-list');
      var shown = 0;
      ['high', 'medium'].forEach(function (tier) {
        var rows = (compact[tier] && compact[tier].rows) || [];
        rows.forEach(function (row) {
          if (shown >= SIDE_LIST_CAP) return;
          shown++;
          var li = el('li', 'rm-side-item');
          li.appendChild(el('span', 'chip rm-side-tier rm-side-tier-' + tier, tier));
          var t = row.title || row.id || String(row);
          var span = el('span', 'rm-side-text', t.length > 90 ? t.slice(0, 90) + '…' : t);
          span.title = t;
          li.appendChild(span);
          list.appendChild(li);
        });
      });
      if (list.children.length) bodyEl.appendChild(list);
      else bodyEl.appendChild(el('div', 'rm-side-empty', 'no high/medium rows — see the full list'));
    }).catch(function () {
      bodyEl.innerHTML = '';
      bodyEl.appendChild(el('div', 'rm-side-error', 'could not load — retry on next tick'));
      if (countEl) countEl.textContent = '(!)'; // Round 12 item 9
    });
  }

  function bootSidebar() {
    if (!document.getElementById('rmSidebar')) return;
    sidePaneBoot('rmMyItemsPane', LS_SIDE_MYITEMS);
    sidePaneBoot('rmBacklogPane', LS_SIDE_BACKLOG);
    var openInbox = document.getElementById('rmMyItemsOpenInbox');
    if (openInbox && shell) openInbox.addEventListener('click', function () { shell.navigate('#inbox'); });
    var openReq = document.getElementById('rmBacklogOpenRequests');
    if (openReq && shell) openReq.addEventListener('click', function () { shell.navigate('#requests'); });
    loadSideMyItems();
    loadSideBacklog();
    setInterval(loadSideBacklog, REFRESH_INTERVAL_MS); // backlog is read-only here — tick-safe
  }

  // ============================================================
  // boot: initial load + the 30s tick (C7)
  // ============================================================
  syncToolbar();
  load();
  bootSidebar();
  setInterval(function () {
    load();
    setAgeLabel(); // age text keeps counting even between successful loads
  }, REFRESH_INTERVAL_MS);
})();
