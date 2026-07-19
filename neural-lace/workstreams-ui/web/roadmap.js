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

  // ============================================================
  // drill-down body (C6 + C5 reasons + title edit + rank reorder)
  // ============================================================
  function drilldown(item, topLevelIndex, topLevelCount) {
    var box = el('div', 'rm-drill');

    // from your request(s) — C6, the round-1 verbatim direction. Both
    // directions law: the Requests view renders "became →" back (task 5).
    var fr = item.from_requests || [];
    var frRow = el('div', 'rm-from-requests');
    frRow.appendChild(el('span', 'rm-drill-label', 'from your request(s): '));
    if (fr.length === 0) {
      frRow.appendChild(el('span', 'rm-drill-none', '(no captured request — registered directly)'));
    } else {
      fr.forEach(function (r) {
        frRow.appendChild(btn('ghost small rm-request-link', r.title || r.id, function () {
          // T3-fix2: encode the id segment (encode/decode symmetry with
          // app.js routeFromHash's decodeURIComponent) — a raw '%' in an id
          // otherwise throws URIError in the hashchange handler.
          if (shell) shell.navigate('#request/' + encodeURIComponent(r.id));
        }));
      });
    }
    box.appendChild(frRow);

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

    if (item.kind === 'intent') {
      // feedback line for every write below (aria-live — C9)
      var feedback = el('div', 'rm-edit-feedback');
      feedback.setAttribute('aria-live', 'polite');
      feedback.hidden = true;
      function say(text, isErr) {
        feedback.hidden = false;
        feedback.textContent = text;
        feedback.className = 'rm-edit-feedback' + (isErr ? ' rm-feedback-err' : ' rm-feedback-ok');
      }

      // title edit — the todo.js pattern: explicit Edit button (never
      // click-on-text-only), Escape cancels, focus returns (C9/A3).
      var titleRow = el('div', 'rm-title-edit');
      var editBtn = btn('ghost small rm-edit-btn', 'Edit title', null);
      editBtn.setAttribute('aria-label', 'edit the title of "' + item.title + '"');
      editBtn.dataset.focusKey = 'edit:' + item.id;
      editBtn.addEventListener('click', function () { openTitleEditor(titleRow, item, editBtn, say, null); });
      titleRow.appendChild(editBtn);
      box.appendChild(titleRow);

      // build-order reorder — keyboard-operable REAL buttons, never
      // drag-only (A7 + WCAG 2.2 2.5.7, delta R2).
      var rankRow = el('div', 'rm-rank-row');
      var upBtn = btn('ghost small rm-rank-btn', '↑ Move up', function () { moveRank(item.id, 'up', say); });
      upBtn.setAttribute('aria-label', 'Move up in build order: ' + item.title);
      upBtn.dataset.focusKey = 'rank-up:' + item.id;
      upBtn.disabled = topLevelIndex === 0;
      var downBtn = btn('ghost small rm-rank-btn', '↓ Move down', function () { moveRank(item.id, 'down', say); });
      downBtn.setAttribute('aria-label', 'Move down in build order: ' + item.title);
      downBtn.dataset.focusKey = 'rank-down:' + item.id;
      downBtn.disabled = topLevelIndex === topLevelCount - 1;
      rankRow.appendChild(upBtn);
      rankRow.appendChild(downBtn);
      box.appendChild(rankRow);

      // merged-unverified: the LABELED per-item operator override to
      // complete (A4's binding rule) — delegates to the existing lifecycle
      // endpoint; manual done is always an override, labeled.
      if (st.value === 'merged-unverified') {
        var overrideBtn = btn('ghost small rm-override-btn', 'Mark complete anyway (override)', function () {
          overrideBtn.disabled = true;
          fetch('/api/ask/' + encodeURIComponent(item.id) + '/lifecycle', {
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
        body: JSON.stringify({ ask_id: item.id, title: t }),
      }).then(function (r) { return r.json(); }).then(function (j) {
        if (j && j.ok) { say('Title saved.', false); close(); load(); }
        else { saveBtn.disabled = false; say((j && j.error) || 'Could not save the title.', true); }
      }).catch(function (e) { saveBtn.disabled = false; say('Could not save the title: ' + e, true); });
    });
  }

  function moveRank(askId, direction, say) {
    fetch('/api/roadmap/rank', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask_id: askId, direction: direction }),
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
    sum.appendChild(titleSpan);
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
    if (kids.length) det.appendChild(renderChildList(kids, item.id));
    return det;
  }

  // renderChildList — applies COMPLETED AGING per parent (round 4 + I2):
  // complete children inside the window stay in place (collapsed, headline
  // keeps "completed <when>"); complete children PAST the window fold into
  // ONE per-parent roll-up row: "N completed ▸ — latest: <title>".
  function renderChildList(children, parentId) {
    var wrap = el('div', 'rm-children');
    var live = [], aged = [];
    children.forEach(function (c) {
      var isComplete = c.status && (c.status.value === 'complete');
      if (isComplete && agedOut(c.completed_at)) aged.push(c); else live.push(c);
    });
    live.forEach(function (c) { wrap.appendChild(renderNode(c, -1, -1)); });
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
    live.forEach(function (it, i) { tree.appendChild(renderNode(it, i, live.length)); });
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
        card.appendChild(el('div', 'rm-card-title', it.title));
        var chipRow = el('div', 'rm-card-chips');
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
  // boot: initial load + the 30s tick (C7)
  // ============================================================
  syncToolbar();
  load();
  setInterval(function () {
    load();
    setAgeLabel(); // age text keeps counting even between successful loads
  }, REFRESH_INTERVAL_MS);
})();
