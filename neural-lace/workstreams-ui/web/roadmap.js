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
  // one badge PER class present, never a masked class (delta R4).
  var ROLLUP_ORDER = ['waiting-on-you', 'crashed', 'blocked-on', 'limit-parked', 'unknown'];
  var ROLLUP_BADGE_LABEL = {
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
  var pendingEdit = null; // {itemId, value, selStart, selEnd} — uncommitted title edit
  var whenLoadedQueue = [];

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
    return false;
  }

  // applyFilters(items) -> {visible, hiddenChores, filtered}
  function applyFilters(items) {
    var q = filterText();
    var hiddenChores = 0;
    var visible = [];
    (items || []).forEach(function (it) {
      if (!showChores && it.provenance === 'machine') { hiddenChores++; return; }
      if (selectedProjects.length && selectedProjects.indexOf(it.project || '') === -1) return;
      if (!itemMatchesText(it, q)) return;
      visible.push(it);
    });
    return {
      visible: visible,
      hiddenChores: hiddenChores,
      filtered: !!(q || selectedProjects.length),
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
  function isPhaseSeries(children) {
    return !!(children && children.length && children[0] && children[0].kind === 'plan');
  }
  function phaseLabel(index, total) {
    return 'Phase ' + (index + 1) + ' of ' + total;
  }
  // PHASE-SERIES-END

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
    // A self-contained label map (deliberately NOT the outer STATUS_LABEL
    // var) so this function stays a PURE, standalone-executable unit — the
    // same real-execution test technique cockpit.selftest.js already uses
    // for isPhaseSeries/visibleFromRequests (extracted + run in a vm
    // sandbox with no outer-scope access).
    var LABELS = {
      'not-started': 'not started', 'in-progress': 'in progress',
      'merged-unverified': 'merged — deploy unverified', 'complete': 'complete',
      'stalled': 'stalled', 'unknown': 'status unknown',
    };
    var counts = {};
    (items || []).forEach(function (it) {
      var v = (it.status && it.status.value) || 'unknown';
      counts[v] = (counts[v] || 0) + 1;
    });
    var order = ['complete', 'in-progress', 'not-started', 'stalled', 'merged-unverified', 'unknown'];
    var parts = order.filter(function (v) { return counts[v]; }).map(function (v) {
      return counts[v] + ' ' + (LABELS[v] || v);
    });
    var label = project || '(no project)';
    var count = (items || []).length;
    // "plans, in build order" not "phases" (operator 2026-07-24: "is there a
    // plan this is tied to?" — each phase IS one plan file; the header says
    // so instead of implying membership in some unnamed program).
    return label + ' — ' + count + (count === 1 ? ' plan' : ' plans') + ', in build order' +
      (parts.length ? ' (' + parts.join(', ') + ')' : '');
  }
  // PROJECT-GROUPING-END

  // ============================================================
  // status chip + roll-up badges + markers (shared by tree AND kanban)
  // ============================================================
  function statusChip(item) {
    var st = item.status || {};
    var value = st.value || 'unknown';
    var label = st.label || STATUS_LABEL[value] || value;
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
      chip = el('span', 'chip rm-status rm-status-' + value, text);
    }
    return chip;
  }

  function progressNode(item) {
    // zero tracked children -> NO bar (no fake granularity); otherwise the
    // bar ALWAYS carries the "n/m" text (never bar-only).
    if (!item.progress || !item.progress.total) return null;
    var p = item.progress;
    var wrap = el('span', 'rm-progress');
    var barOuter = el('span', 'rm-progress-bar');
    barOuter.setAttribute('role', 'img');
    barOuter.setAttribute('aria-label', p.done + ' of ' + p.total + ' tasks done');
    var fill = el('span', 'rm-progress-fill');
    fill.style.width = Math.round(100 * p.done / p.total) + '%';
    barOuter.appendChild(fill);
    wrap.appendChild(barOuter);
    wrap.appendChild(el('span', 'rm-progress-text', p.done + '/' + p.total));
    return wrap;
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

  // ============================================================
  // drill-down body (C6 + C5 reasons + title edit + rank reorder)
  // ============================================================
  function drilldown(item, topLevelIndex, topLevelCount) {
    var box = el('div', 'rm-drill');

    // R9 follow-up (operator 2026-07-24: "is there a plan this is tied to?
    // why don't I see a link?"): every phase IS a plan file — link it,
    // absolute path (operator directive: links are always absolute).
    if (item.kind === 'plan' && item.plan_path) {
      var planRow = el('div', 'rm-plan-link-row');
      planRow.appendChild(el('span', 'rm-drill-label', 'plan: '));
      var a = document.createElement('a');
      a.className = 'rm-plan-link';
      a.textContent = item.plan_path.replace(/^.*[\\/](docs[\\/])/, '$1').replace(/\\/g, '/');
      a.title = item.plan_path;
      a.href = 'file:///' + String(item.plan_path).replace(/\\/g, '/').replace(/^\/+/, '');
      planRow.appendChild(a);
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

      // Compact item chrome (round-6 gap 4): ONE row of small ICON buttons
      // (never two permanent rows), hidden until hover OR focus-within
      // (CSS-only — keyboard reachable, WCAG 2.2 2.5.7 stands: never
      // hover-only). The todo.js edit pattern (explicit Edit button, never
      // click-on-text-only, Escape cancels, focus returns — C9/A3) and the
      // keyboard-operable move up/down (A7 + delta R2) are UNCHANGED
      // behaviorally — only the chrome's visual weight + grouping changed.
      var titleRow = el('div', 'rm-title-edit');
      var chromeRow = el('div', 'rm-item-chrome');
      var editBtn = btn('ghost small rm-edit-btn rm-icon-btn', '✎', null);
      editBtn.setAttribute('aria-label', 'edit the title of "' + item.title + '"');
      editBtn.dataset.focusKey = 'edit:' + item.id;
      editBtn.addEventListener('click', function () { openTitleEditor(titleRow, item, editBtn, say, null); });
      chromeRow.appendChild(editBtn);

      // build-order reorder — keyboard-operable REAL buttons, never
      // drag-only (A7 + WCAG 2.2 2.5.7, delta R2).
      var upBtn = btn('ghost small rm-rank-btn rm-icon-btn', '↑', function () { moveRank(item.id, 'up', say); });
      upBtn.setAttribute('aria-label', 'Move up in build order: ' + item.title);
      upBtn.dataset.focusKey = 'rank-up:' + item.id;
      upBtn.disabled = topLevelIndex === 0;
      var downBtn = btn('ghost small rm-rank-btn rm-icon-btn', '↓', function () { moveRank(item.id, 'down', say); });
      downBtn.setAttribute('aria-label', 'Move down in build order: ' + item.title);
      downBtn.dataset.focusKey = 'rank-down:' + item.id;
      downBtn.disabled = topLevelIndex === topLevelCount - 1;
      chromeRow.appendChild(upBtn);
      chromeRow.appendChild(downBtn);
      box.appendChild(titleRow);
      box.appendChild(chromeRow);

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

  function openTitleEditor(titleRow, item, editBtn, say, restore) {
    if (titleRow.querySelector('.rm-title-input')) return; // already open
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'rm-title-input';
    input.value = restore ? restore.value : item.title;
    input.setAttribute('aria-label', 'edit title');
    input.dataset.editFor = item.id;
    var saveBtn = btn('btn-go small', 'Save', null);
    var cancelBtn = btn('ghost small', 'Cancel', null);
    editBtn.hidden = true;
    // gap 4: keep the (otherwise hover/focus-only) chrome row visible for
    // the WHOLE edit, so a stray mouseout mid-edit never hides the open
    // input/Save/Cancel controls.
    titleRow.classList.add('rm-editing');
    titleRow.appendChild(input);
    titleRow.appendChild(saveBtn);
    titleRow.appendChild(cancelBtn);
    input.focus();
    if (restore && restore.selStart !== undefined) {
      try { input.setSelectionRange(restore.selStart, restore.selEnd); } catch (_) {}
    } else { input.select(); }
    function close() {
      input.remove(); saveBtn.remove(); cancelBtn.remove();
      editBtn.hidden = false;
      titleRow.classList.remove('rm-editing');
      editBtn.focus(); // focus-return (todo.js pattern)
      if (pendingEdit && pendingEdit.itemId === item.id) pendingEdit = null;
    }
    cancelBtn.addEventListener('click', close);
    input.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
    saveBtn.addEventListener('click', function () {
      var t = input.value.trim();
      if (!t) { say('Title cannot be empty.', true); return; }
      saveBtn.disabled = true;
      fetch('/api/roadmap/title', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: item.id, title: t }),
      }).then(function (r) { return r.json(); }).then(function (j) {
        if (j && j.ok) { say('Title saved.', false); close(); load(); }
        else { saveBtn.disabled = false; say((j && j.error) || 'Could not save the title.', true); }
      }).catch(function (e) { saveBtn.disabled = false; say('Could not save the title: ' + e, true); });
    });
  }

  function moveRank(itemId, direction, say) {
    fetch('/api/roadmap/rank', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: itemId, direction: direction }),
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.ok) { say(j.unchanged ? 'Already at the edge of the list.' : 'Order updated.', false); load(); }
      else { say('Could not reorder: ' + ((j && j.error) || 'unknown error'), true); }
    }).catch(function (e) { say('Could not reorder: ' + e, true); });
  }

  // ============================================================
  // tree rendering
  // ============================================================
  function renderNode(item, topLevelIndex, topLevelCount) {
    var det = document.createElement('details');
    det.className = 'rm-node rm-kind-' + item.kind;
    det.dataset.itemId = item.id;
    det.tabIndex = -1; // landing target: programmatically focusable (C2)
    if (openSet[item.id]) det.open = true;
    det.addEventListener('toggle', function () {
      if (det.open) openSet[item.id] = true; else delete openSet[item.id];
    });

    var sum = document.createElement('summary');
    sum.className = 'rm-row';
    var titleSpan = el('span', 'rm-title', item.title);
    // R9-1: the slug becomes a tooltip/secondary once the H1 title takes
    // the primary spot (item.id IS the slug for a plan-kind node — see
    // roadmap-routes.js's `id: pf.slug`, no separate field needed).
    if (item.kind === 'plan') titleSpan.title = item.id;
    sum.appendChild(titleSpan);
    // R9-3: a subtle per-phase PROJECT chip (text, never color-only) so
    // every phase row names which project it belongs to, not just the
    // filter-chip toolbar.
    if (item.kind === 'plan' && item.project) {
      sum.appendChild(el('span', 'chip rm-project-tag', item.project));
    }
    sum.appendChild(statusChip(item));
    var prog = progressNode(item);
    if (prog) sum.appendChild(prog);
    sum.appendChild(markerChips(item));
    // a fully-collapsed complete subtree keeps its recency in the headline
    if ((item.status && item.status.value === 'complete' && item.completed_at) ||
        (item.status && item.status.value === 'merged-unverified' && item.completed_at)) {
      sum.appendChild(el('span', 'rm-completed-when',
        (item.status.value === 'complete' ? 'completed ' : 'merged ') + formatAge(item.completed_at)));
    }
    sum.appendChild(rollupBadges(item)); // hidden while open via CSS — never masked while collapsed (C1)
    det.appendChild(sum);

    det.appendChild(drilldown(item, topLevelIndex, topLevelCount));

    var kids = item.children || [];
    // round-6 gap 3: a FULLY-COMPLETE node's children collapse into the
    // roll-up IMMEDIATELY, regardless of the per-child 7-day window — see
    // the COLLAPSE-LAW block above. item.status is only ever 'complete'
    // once every child has shipped, so this is never a false bypass.
    var parentFullyComplete = !!(item.status && item.status.value === 'complete');
    if (kids.length) det.appendChild(renderChildList(kids, item.id, parentFullyComplete));
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
    var totalCount = children.length;
    if (phaseSeries) wrap.classList.add('rm-phase-series');
    live.forEach(function (c) {
      var node = renderNode(c, -1, -1);
      if (phaseSeries) {
        var step = el('div', 'rm-phase-step');
        step.appendChild(el('div', 'rm-phase-label', phaseLabel(children.indexOf(c), totalCount)));
        step.appendChild(node);
        wrap.appendChild(step);
      } else {
        wrap.appendChild(node);
      }
    });
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

  function renderTree(visibleItems) {
    var tree = el('div', 'rm-tree');
    var live = [], aged = [];
    visibleItems.forEach(function (it) {
      var isComplete = it.status && it.status.value === 'complete';
      if (isComplete && agedOut(it.completed_at)) aged.push(it); else live.push(it);
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
    var groups = phaseSeries ? groupItemsByProject(live) : [{ project: '', items: live }];
    groups.forEach(function (g) {
      var container = tree;
      if (phaseSeries) {
        var groupEl = el('section', 'rm-project-group');
        groupEl.setAttribute('aria-label', 'project ' + (g.project || '(no project)'));
        groupEl.appendChild(el('div', 'rm-project-group-head', projectGroupHeaderText(g.project, g.items)));
        tree.appendChild(groupEl);
        container = groupEl;
      }
      g.items.forEach(function (it, gi) {
        var node = renderNode(it, live.indexOf(it), live.length);
        if (phaseSeries) {
          var step = el('div', 'rm-phase-step');
          step.appendChild(el('div', 'rm-phase-label', phaseLabel(gi, g.items.length)));
          step.appendChild(node);
          container.appendChild(step);
        } else {
          container.appendChild(node);
        }
      });
    });
    if (aged.length) {
      aged.sort(function (a, b) { return String(b.completed_at).localeCompare(String(a.completed_at)); });
      var roll = document.createElement('details');
      roll.className = 'rm-completed-rollup';
      roll.dataset.rollupFor = '(top)';
      if (openSet['rollup:(top)']) roll.open = true;
      roll.addEventListener('toggle', function () {
        if (roll.open) openSet['rollup:(top)'] = true; else delete openSet['rollup:(top)'];
      });
      var rsum = document.createElement('summary');
      rsum.className = 'rm-completed-rollup-summary';
      rsum.textContent = aged.length + ' completed ▸ — latest: ' + (aged[0].title || aged[0].id);
      roll.appendChild(rsum);
      var rbody = el('div', 'rm-children');
      aged.forEach(function (c) { rbody.appendChild(renderNode(c, -1, -1)); });
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
    KANBAN_COLUMNS.forEach(function (col) {
      var cards = visibleItems.filter(function (it) { return (it.status && it.status.value) === col; });
      if (KANBAN_EXCEPTIONAL[col] && cards.length === 0) return; // R5: exceptional columns only when non-empty
      var colEl = el('section', 'rm-kanban-col rm-kanban-col-' + col);
      colEl.setAttribute('aria-label', KANBAN_COLUMN_LABEL[col]);
      colEl.appendChild(el('div', 'rm-kanban-col-head', KANBAN_COLUMN_LABEL[col] + ' (' + cards.length + ')'));
      cards.forEach(function (it) {
        var card = el('div', 'rm-card');
        card.dataset.itemId = it.id;
        card.tabIndex = -1;
        var cardTitle = el('div', 'rm-card-title', it.title);
        cardTitle.title = it.id; // R9-1: slug as tooltip here too
        card.appendChild(cardTitle);
        var chipRow = el('div', 'rm-card-chips');
        if (it.project) chipRow.appendChild(el('span', 'chip rm-project-tag', it.project)); // R9-3
        chipRow.appendChild(statusChip(it)); // same chips as the tree (I3)
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
  // preserves expansion + scroll + focus + uncommitted edits. openSet is
  // maintained live by the toggle listeners; here we capture the rest.
  // CAPTURE-UI-STATE-BEGIN
  function captureUiState() {
    var st = { scrollY: window.scrollY, bodyScrollTop: body.scrollTop, focusKey: null, edit: null };
    var ae = document.activeElement;
    if (ae && body.contains(ae)) {
      if (ae.dataset && ae.dataset.focusKey) st.focusKey = ae.dataset.focusKey;
      else if (ae.dataset && ae.dataset.itemId) st.focusKey = 'item:' + ae.dataset.itemId;
    }
    // T3-fix1 (comprehension gate FAIL conf 6): capture any OPEN title editor's
    // uncommitted value by PRESENCE, not focus — an open-but-unfocused editor
    // (focus on Save/Cancel, or moved outside the pane entirely) is otherwise
    // silently destroyed by the 30s tick's renderAll() DOM wipe.
    var openInput = document.querySelector('.rm-title-input');
    if (openInput) {
      st.edit = {
        itemId: openInput.dataset.editFor,
        value: openInput.value,
        selStart: openInput.selectionStart, selEnd: openInput.selectionEnd,
      };
    }
    return st;
  }
  // CAPTURE-UI-STATE-END

  function restoreUiState(st) {
    if (!st) return;
    window.scrollTo(0, st.scrollY);
    body.scrollTop = st.bodyScrollTop;
    if (st.edit && st.edit.itemId) {
      pendingEdit = st.edit;
      var det = findItemEl(st.edit.itemId);
      if (det) {
        det.open = true;
        var row = det.querySelector('.rm-title-edit');
        var editBtn = row && row.querySelector('.rm-edit-btn');
        var itemData = findItemData(st.edit.itemId);
        if (row && editBtn && itemData) {
          openTitleEditor(row, itemData, editBtn, function () {}, st.edit);
          return;
        }
      }
    }
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
    body.innerHTML = '';
    var ub = lastPayload.unbound_sessions;
    if (ub && ub.live_sessions && ub.live_sessions.length) {
      body.appendChild(renderUnboundSessions(ub));
    }
    if (f.visible.length === 0) {
      body.appendChild(renderEmptyStates(f));
    } else {
      body.appendChild(viewMode === 'kanban' ? renderKanban(f.visible) : renderTree(f.visible));
      if (f.hiddenChores > 0 && !showChores) {
        var note = el('div', 'rm-chore-note', f.hiddenChores + ' items hidden (harness chores) ');
        note.appendChild(btn('ghost small', 'show', function () {
          showChores = true; lsSet(LS_SHOW_CHORES, '1'); syncToolbar(); renderAll();
        }));
        body.appendChild(note);
      }
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
  function findItemData(id, list) {
    var items = list || (lastPayload && lastPayload.items) || [];
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === id) return items[i];
      var hit = findItemData(id, items[i].children || []);
      if (hit) return hit;
    }
    return null;
  }
  function pathTo(id, list, trail) {
    var items = list || (lastPayload && lastPayload.items) || [];
    for (var i = 0; i < items.length; i++) {
      var t = (trail || []).concat([items[i].id]);
      if (items[i].id === id) return t;
      var hit = pathTo(id, items[i].children || [], t);
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
        return;
      }
      var answerable = (inbox && inbox.ok !== false && inbox.answerable) || [];
      var ops = j.operator_items || [];
      var ptrs = (j.pointer_items || []).filter(function (p) { return !p.checked; });
      if (countEl) countEl.textContent = '(' + (answerable.length + ops.filter(function (o) { return !o.checked; }).length + ptrs.length) + ' open)';
      bodyEl.innerHTML = '';
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
      if (!answerable.length && !ops.length && !ptrs.length) {
        bodyEl.appendChild(el('div', 'rm-side-empty', 'nothing on your list'));
        return;
      }
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
