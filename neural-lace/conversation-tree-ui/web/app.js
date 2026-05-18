'use strict';
/* Conversation Tree UI — Phase C/D client (ADR-031 Option 2 passive tracker).
 * Reads the file-mediated state contract via SSE; writes GUI mutations as
 * single appended events through POST /api/event (symmetric FR-11). The GUI
 * NEVER spawns/feeds/steers a Claude Code session — there is no continue/
 * resume/compose/send affordance anywhere (Option-2 invariant). No framework,
 * no build step. */
(function () {
  // ---- element handles -------------------------------------------------
  var $ = function (id) { return document.getElementById(id); };
  var treeSelect = $('treeSelect'), addProjBtn = $('addProjBtn'),
      showArchived = $('showArchived'), lastRead = $('lastRead'),
      statusEl = $('status'), corruptBanner = $('corruptBanner'),
      noteStack = $('noteStack'), toast = $('toast'),
      treeCanvas = $('treeCanvas'), treeScroll = $('treeScroll'),
      treeState = $('treeState'), treeCrumb = $('treeCrumb'),
      actionsBody = $('actionsBody'), actionsState = $('actionsState'),
      actionsSort = $('actionsSort'),
      backlogBody = $('backlogBody'), backlogState = $('backlogState'),
      backlogSort = $('backlogSort'), addBacklogBtn = $('addBacklogBtn'),
      backlogCapture = $('backlogCapture'), blText = $('blText'),
      blPriority = $('blPriority'), blContext = $('blContext'),
      blSave = $('blSave'), blCancel = $('blCancel'),
      ctxPanel = $('ctxPanel'), ctxScrim = $('ctxScrim'), zoomIn = $('zoomIn'),
      zoomOut = $('zoomOut'), fitSel = $('fitSel'),
      showConcluded = $('showConcluded'), tabBar = $('tabBar');

  // ---- client view state ----------------------------------------------
  var S = null;                 // latest snapshot
  var loaded = false;           // first frame received yet?
  var activeTree = localStorage.getItem('ctree-active') || 'global';
  var sel = null;               // selected node_id
  var collapsed = new Set();    // node_ids the user collapsed (default expanded)
  var zoom = 1;
  var firedDefers = new Set(JSON.parse(localStorage.getItem('ctree-fired') || '[]'));
  var dismissed = new Set();    // dismissed persistent notes (node_id keys)
  var seenConcluded = new Set(); // nodes already known concluded (notify once)
  var primed = false;           // suppress conclude-notifications on first frame
  var ctxExpanded = false;      // FR-6 layered: summary -> full
  // v1.1 item 3: hide-concluded. localStorage UI-pref convention (same as
  // zoom/collapsed/activeTree/projects/drafts). Default OFF = hide concluded
  // (Misha's preferred default). '1' = show concluded.
  var showConcludedPref = localStorage.getItem('ctree-show-concluded') === '1';

  // ---- tiny DOM helpers ------------------------------------------------
  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  // v1.1-ux items 7/12/13: snackbar. opts.undo = fn → renders an "Undo"
  // button + uses the 10s timer (item 12). A ✕ is ALWAYS present (item 13):
  // pressing it closes immediately AND cancels the pending Undo (the action
  // stays in its post-action state — undo only fires on the Undo click).
  function closeToast() {
    clearTimeout(toast._t);
    toast._pendingUndo = null;
    toast.hidden = true;
    clear(toast);
  }
  function snackbar(msg, opts) {
    opts = opts || {};
    clearTimeout(toast._t);
    clear(toast);
    toast.className = 'toast ' + (opts.kind || '');
    toast.hidden = false;
    toast.appendChild(el('span', 'sb-msg', msg));
    toast._pendingUndo = (typeof opts.undo === 'function') ? opts.undo : null;
    if (toast._pendingUndo) {
      var u = el('button', 'sb-undo', 'Undo');
      u.addEventListener('click', function () {
        var fn = toast._pendingUndo; closeToast(); if (fn) fn();
      });
      toast.appendChild(u);
    }
    var x = el('button', 'sb-x', '✕');
    x.title = 'dismiss (cancels Undo)';
    x.addEventListener('click', closeToast);     // item 13: ✕ cancels the pending undo
    toast.appendChild(x);
    // item 12: undo-bearing snackbar lingers 10s; plain feedback stays 2.6s
    var dur = opts.duration || (toast._pendingUndo ? 10000 : 2600);
    toast._t = setTimeout(closeToast, dur);
  }
  // Back-compat: every existing showToast(msg,kind) caller = plain snackbar.
  function showToast(msg, kind) { snackbar(msg, { kind: kind }); }

  // v1.1-ux item 7: respect reduced-motion (harness UX/accessibility std).
  function reducedMotion() {
    try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; }
    catch (_) { return false; }
  }
  // item 7: slide+fade the row OUT (~200ms) before the mutation posts, so a
  // state change is felt, not just "vanished". Then run `then`.
  function animateLeave(li, then) {
    if (!li || reducedMotion()) { then(); return; }
    li.classList.add('leaving');
    setTimeout(then, 210);
  }
  // item 7: optimistic post + undo snackbar. `undoFn` posts the inverse
  // event. post() is silenced (3rd arg) so only the undo snackbar shows.
  function actWithUndo(li, postEv, okMsg, undoFn, afterOk) {
    animateLeave(li, function () {
      post(postEv, okMsg, true).then(function (ok) {
        if (!ok) return;                       // post() surfaced the error
        if (afterOk) afterOk();
        snackbar(okMsg + ' — Undo?', { kind: 'ok', undo: undoFn });
      });
    });
  }
  // items 7+8: which action/backlog item ids are NEW since the last render
  // (drives the entrance flash + the per-pane "+N new" badge). Primed on the
  // first frame so nothing flashes/badges on initial load.
  var seenActionIds = null, seenBacklogIds = null;
  var newActionIds = {}, newBacklogIds = {};
  var newActionsCount = 0, newBacklogCount = 0;
  function diffNewIds(curIds, prevSet, kind) {
    var fresh = {};
    if (prevSet == null) {            // first frame — prime, badge nothing
      var prime = {}; curIds.forEach(function (id) { prime[id] = 1; });
      if (kind === 'a') seenActionIds = prime; else seenBacklogIds = prime;
      return { fresh: {}, count: 0 };
    }
    var cnt = 0;
    curIds.forEach(function (id) { if (!prevSet[id]) { fresh[id] = 1; cnt++; } });
    var next = {}; curIds.forEach(function (id) { next[id] = 1; });
    if (kind === 'a') seenActionIds = next; else seenBacklogIds = next;
    return { fresh: fresh, count: cnt };
  }

  // item 9: rich-details disclosure (collapsed by default; per-item toggle).
  var expandedItems = new Set();
  function detailRow(label, val) {
    if (val == null || val === '') return null;
    var d = el('div', 'det-row');
    d.appendChild(el('span', 'det-k', label));
    d.appendChild(el('span', 'det-v', String(val)));
    return d;
  }
  function renderItemDetails(de) {
    var box = el('div', 'li-details');
    var add = function (node) { if (node) box.appendChild(node); };
    add(detailRow('What', de.description));
    add(detailRow('Why / context', de.context));
    if (Array.isArray(de.options) && de.options.length) {
      var ow = el('div', 'det-row');
      ow.appendChild(el('span', 'det-k', 'Options'));
      var ol = el('div', 'det-v');
      de.options.forEach(function (op) {
        if (typeof op === 'string') { ol.appendChild(el('div', 'det-opt', op)); return; }
        var o = el('div', 'det-opt');
        o.appendChild(el('div', 'det-opt-l', op.label || ''));
        if (op.pros) o.appendChild(el('div', 'muted', '+ ' + op.pros));
        if (op.cons) o.appendChild(el('div', 'muted', '− ' + op.cons));
        ol.appendChild(o);
      });
      ow.appendChild(ol); box.appendChild(ow);
    }
    add(detailRow('Instructions', de.instructions));
    add(detailRow('Recommendation', de.recommendation));
    add(detailRow('Blocking input needed', de.blocking_input));
    if (Array.isArray(de.links) && de.links.length) {
      var lw = el('div', 'det-row');
      lw.appendChild(el('span', 'det-k', 'Links'));
      var lv = el('div', 'det-v');
      de.links.forEach(function (lk) {
        var c = el('span', 'det-link', String(lk));
        c.title = 'repo path / reference';
        lv.appendChild(c); lv.appendChild(document.createTextNode(' '));
      });
      lw.appendChild(lv); box.appendChild(lw);
    }
    return box;
  }
  // item 10: a decision/question (or an action whose details flag it as
  // needing input) can be answered inline without context-switching.
  function respondable(it) {
    return it.kind === 'decision' || it.kind === 'question'
      || (it.details && it.details.blocking_input);
  }
  function copyResponseForDispatch(it, text) {
    var blob = '[action ' + it.item_id + '] ' + it.text + '\nResponse: ' + text + '\n' +
      '(captured in the Conversation Tree GUI — paste to close the loop in Dispatch)';
    try {
      navigator.clipboard.writeText(blob).then(
        function () { showToast('response copied — paste into Dispatch', 'ok'); },
        function () { fallbackCopy(blob); });
    } catch (_) { fallbackCopy(blob); }
  }
  // item 8: per-pane "+N new" badge. Set from the SSE-driven diff; cleared
  // when the user looks at that pane (focus / scroll / click within it).
  function updateNewBadges() {
    var ab = $('actionsNewBadge'), bb = $('backlogNewBadge');
    if (ab) { ab.textContent = newActionsCount ? '+' + newActionsCount + ' new' : ''; ab.hidden = !newActionsCount; }
    if (bb) { bb.textContent = newBacklogCount ? '+' + newBacklogCount + ' new' : ''; bb.hidden = !newBacklogCount; }
  }
  function clearNewBadge(which) {
    if (which === 'a' && newActionsCount) { newActionsCount = 0; updateNewBadges(); }
    if (which === 'b' && newBacklogCount) { newBacklogCount = 0; updateNewBadges(); }
  }

  // ---- write path (BF-5 mutation-feedback contract) --------------------
  // Optimistic intent + explicit saved/error. The crown-jewel tree is never
  // shown as saved when the append failed: on failure we re-sync from SSE
  // (server is the source of truth) and surface an explicit revert toast.
  function post(ev, okMsg, silent) {
    return fetch('/api/event', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(ev),
    }).then(function (r) { return r.json().then(function (j) { return { r: r, j: j }; }); })
      .then(function (o) {
        if (o.r.ok && o.j.ok) {
          // Authoritative immediate update: the server returns the real
          // post-append snapshot. Apply it now (BF-5 immediate confirmation +
          // removes the race where a follow-up check reads pre-append state);
          // the SSE frame re-confirms shortly. Never shows an unpersisted
          // change as saved — this IS the persisted snapshot.
          if (o.j.snapshot) {
            S = o.j.snapshot; loaded = true;
            detectConcludeNotifications(); checkDefers(); render();
          }
          if (!silent) showToast(okMsg || 'saved', 'ok');
          return o.j;
        }
        var why = o.j && (o.j.error || (o.j.schema_too_new && 'schema too new'));
        showToast('Couldn’t save that change — tree state unchanged; ' + (why || 'append rejected'), 'err');
        return null; // SSE will re-broadcast last-good; nothing to revert
      })
      .catch(function () {
        showToast('Couldn’t save that change — tree state unchanged; server unreachable', 'err');
        return null;
      });
  }
  function uid(p) { return (p || 'g') + '-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e5).toString(36); }

  // ---- snapshot helpers ------------------------------------------------
  function nodes() { return (S && Array.isArray(S.nodes)) ? S.nodes : []; }
  function backlog() { return (S && Array.isArray(S.backlog)) ? S.backlog : []; }
  function byId(id) { return nodes().find(function (n) { return n.node_id === id; }) || null; }
  function order(scope) { return (S && S.order && S.order[scope]) ? S.order[scope] : null; }
  function treeOf(n) { return n.tree_id || 'global'; }
  function nodeTrees() {
    var t = {};
    nodes().forEach(function (n) { t[treeOf(n)] = 1; });
    backlog().forEach(function (b) { t[b.tree_id || 'global'] = 1; });
    t['global'] = 1;
    (JSON.parse(localStorage.getItem('ctree-projects') || '[]')).forEach(function (p) { t[p] = 1; });
    return Object.keys(t).sort();
  }
  function chain(nodeId) {        // node -> root, array of nodes (self first)
    var out = [], cur = byId(nodeId), guard = 0;
    while (cur && guard++ < 500) { out.push(cur); cur = cur.parent_id ? byId(cur.parent_id) : null; }
    return out;
  }
  function crumb(nodeId) {
    return chain(nodeId).reverse().map(function (n) { return n.title || n.node_id; }).join(' › ');
  }
  function isWaiting(it) { return (!it.checked) || it.deferred || it.contested; }

  // ---- per-pane data-state rendering (C1b/c/d/e + BF-2) ----------------
  // Four never-conflated states: loading | first-run-empty | steady-state-empty
  // | populated (+ a global corruption banner that never blanks a pane).
  function paneState(stateEl, bodyEl, mode, opts) {
    opts = opts || {};
    if (mode === 'populated') { stateEl.hidden = true; bodyEl.style.display = ''; return; }
    bodyEl.style.display = 'none'; stateEl.hidden = false;
    // Clear only pure list bodies (actions/backlog). The tree pane's body is
    // the scroll container that also holds #treeCanvas/#treeState — never wipe
    // it here; renderTree owns treeCanvas's contents.
    if (bodyEl.classList.contains('list-body')) clear(bodyEl);
    stateEl.className = 'pane-state' + (mode === 'loading' ? ' skel' : '');
    clear(stateEl);
    if (mode === 'loading') {
      stateEl.appendChild(el('div', null, 'Loading conversation tree…'));
      stateEl.appendChild(el('div', 'bar')); stateEl.appendChild(el('div', 'bar')); stateEl.appendChild(el('div', 'bar'));
    } else if (mode === 'first-run') {
      stateEl.appendChild(el('div', null, opts.first || 'Nothing here yet.'));
      var h = el('div', 'hint', opts.hint || ''); stateEl.appendChild(h);
    } else if (mode === 'steady-empty') {
      stateEl.appendChild(el('div', null, opts.steady || 'All caught up.'));
      if (opts.affordance) stateEl.appendChild(opts.affordance);
    }
  }

  // ---- corruption banner (UX-I4 / C1d) ---------------------------------
  function renderCorrupt() {
    if (S && S.schema_too_new) {
      corruptBanner.hidden = false;
      corruptBanner.textContent = '⚠ ' + (S.message || 'schema too new') +
        ' — the saved tree was written by a newer version; showing nothing rather than mis-parsing. Upgrade the GUI/gate.';
      return true;
    }
    if (S && S.__corrupt) {
      corruptBanner.hidden = false;
      corruptBanner.textContent = '⚠ State file unreadable — could not load from any saved version. ' +
        'See the append-only audit log; the tree was NOT blanked, no events were lost.';
      return true;
    }
    corruptBanner.hidden = true;
    return false;
  }

  // ---- TREE PANE (C2) --------------------------------------------------
  // v1.1 item 3: node_ids whose ENTIRE subtree is concluded (concluded leaf,
  // or a branch all of whose descendants are concluded). When hide is on,
  // these drop out — but a concluded ancestor with any non-concluded
  // descendant stays so the open work underneath remains reachable.
  function concludedHiddenSet() {
    if (showConcludedPref) return null;            // showing all -> hide nothing
    var same = nodes().filter(function (n) { return treeOf(n) === activeTree; });
    var kids = {};
    same.forEach(function (n) { if (n.parent_id) (kids[n.parent_id] = kids[n.parent_id] || []).push(n); });
    var memo = {}, hide = {};
    function allConcluded(n) {
      if (n.node_id in memo) return memo[n.node_id];
      memo[n.node_id] = false;                      // cycle guard
      if (n.state !== 'concluded') return (memo[n.node_id] = false);
      var ch = kids[n.node_id] || [];
      var res = ch.every(allConcluded);
      memo[n.node_id] = res;
      if (res) hide[n.node_id] = 1;
      return res;
    }
    same.forEach(allConcluded);
    return hide;
  }
  function visibleNodes() {
    var hidden = concludedHiddenSet();
    return nodes().filter(function (n) {
      if (treeOf(n) !== activeTree) return false;
      if (n.state === 'archived' && !showArchived.checked) return false;
      if (hidden && hidden[n.node_id]) return false;   // item 3: drop fully-concluded subtrees
      return true;
    });
  }
  // True when the active tree HAS branches but the concluded filter hid all
  // of them (drives a tailored steady-empty, never a blank canvas).
  function allHiddenByConcluded() {
    if (showConcludedPref) return false;
    var same = nodes().filter(function (n) {
      return treeOf(n) === activeTree && !(n.state === 'archived' && !showArchived.checked);
    });
    return same.length > 0 && visibleNodes().length === 0;
  }
  function forest(vis) {
    var ids = {}; vis.forEach(function (n) { ids[n.node_id] = n; });
    var roots = [], kids = {};
    vis.forEach(function (n) {
      var p = n.parent_id;
      if (p && ids[p]) { (kids[p] = kids[p] || []).push(n); }
      else { roots.push(n); }
    });
    return { roots: roots, kids: kids };
  }
  function nodeBadges(n) {
    var frag = document.createDocumentFragment();
    var draftLive = localStorage.getItem('ctree-draft-' + n.node_id);
    if (n.draft || (draftLive && draftLive.trim())) frag.appendChild(el('span', 'badge draft', '▸ unfinished note'));
    if (n.items && n.items.some(function (i) { return i.contested; })) frag.appendChild(el('span', 'badge contested', '⚠ contested'));
    if (n.items && n.items.some(function (i) { return i.deferred; })) frag.appendChild(el('span', 'badge deferred', 'deferred'));
    // BF-1 persistent on-node handoff badge — set on the passive-handoff
    // action, persists until Dispatch acts on it (items added / concluded /
    // archived). The fixed-set copy is intentional ("ready to start in
    // Dispatch" — positive affordance, never only the negative).
    if (n.origin === 'backlog-activated' && n.state === 'open' &&
        (!n.items || n.items.length === 0)) {
      frag.appendChild(el('span', 'badge handoff', '▸ ready to start in Dispatch'));
    }
    if (n.bound_sessions && n.bound_sessions.length) frag.appendChild(el('span', 'badge sess', '⚠ ' + n.bound_sessions.length + ' session(s) — may be partial'));
    var openCt = (n.items || []).filter(function (i) { return isWaiting(i); }).length;
    if (openCt) frag.appendChild(el('span', 'badge count', openCt + ' open'));
    return frag;
  }
  function renderTreeNode(n, kids, container) {
    var wrap = el('div', 'tnode');
    var kidList = kids[n.node_id] || [];
    var hasKids = kidList.length > 0;
    var isCollapsed = collapsed.has(n.node_id) || n.state === 'concluded';
    if (isCollapsed) wrap.classList.add('collapsed');

    var row = el('div', 'tnode-row');
    if (n.node_id === sel) row.classList.add('sel');
    if (n.state === 'concluded') row.classList.add('concluded');
    if (n.state === 'archived') row.classList.add('archived');
    row.setAttribute('data-node', n.node_id);
    row.setAttribute('draggable', 'true'); // C5 mouse drag re-parent

    var tw = el('span', 'twist', hasKids ? (isCollapsed ? '▸' : '▾') : '·');
    tw.addEventListener('click', function (e) {
      e.stopPropagation();
      if (!hasKids) return;
      if (collapsed.has(n.node_id)) collapsed.delete(n.node_id); else collapsed.add(n.node_id);
      render();
    });
    row.appendChild(tw);

    if (n.state === 'concluded') {
      var stub = el('span', 'tnode-title concluded stub', n.title + '  — concluded');
      row.appendChild(stub);
      var reopen = el('button', 'ghost', '↩ re-open');
      reopen.title = 'auto-concluded — re-open (no data loss)';
      reopen.addEventListener('click', function (e) { e.stopPropagation(); post({ type: 're-opened', node_id: n.node_id }, 're-opened'); });
      row.appendChild(reopen);
    } else {
      var t = el('span', 'tnode-title', n.title || n.node_id);
      row.appendChild(t);
    }
    row.appendChild(nodeBadges(n));

    row.addEventListener('click', function () { selectNode(n.node_id); });
    // C5: drag-drop re-parent (mouse-only, NFR-6 v1).
    row.addEventListener('dragstart', function (e) { e.dataTransfer.setData('text/node', n.node_id); });
    row.addEventListener('dragover', function (e) { e.preventDefault(); row.classList.add('dragover'); });
    row.addEventListener('dragleave', function () { row.classList.remove('dragover'); });
    row.addEventListener('drop', function (e) {
      e.preventDefault(); row.classList.remove('dragover');
      var dragged = e.dataTransfer.getData('text/node');
      if (dragged && dragged !== n.node_id) {
        post({ type: 're-parented', node_id: dragged, new_parent_id: n.node_id }, 're-parented');
      }
    });

    wrap.appendChild(row);
    if (hasKids) {
      var kc = el('div', 'tkids');
      kidList.forEach(function (k) { renderTreeNode(k, kids, kc); });
      wrap.appendChild(kc);
    }
    container.appendChild(wrap);
  }
  function renderTree() {
    var vis = visibleNodes();
    if (!loaded) { paneState(treeState, treeScroll, 'loading'); return; }
    if (nodes().length === 0) {
      paneState(treeState, treeScroll, 'first-run', {
        first: 'No conversation tree yet.',
        hint: 'When Dispatch opens a branch (or you activate a backlog item), the tree appears here.',
      });
      return;
    }
    if (vis.length === 0) {
      if (allHiddenByConcluded()) {
        var aff = el('button', 'ghost', 'Show concluded');
        aff.addEventListener('click', function () { showConcluded.checked = true; applyShowConcluded(); });
        paneState(treeState, treeScroll, 'steady-empty', {
          steady: 'All branches in "' + activeTree + '" are concluded — hidden by your "show concluded" preference.',
          affordance: aff,
        });
        return;
      }
      paneState(treeState, treeScroll, 'steady-empty', {
        steady: activeTree === 'global'
          ? 'This tree has no branches yet.'
          : 'Project "' + activeTree + '" has no branches yet — activate a backlog item or switch trees.',
      });
      return;
    }
    paneState(treeState, treeScroll, 'populated');
    clear(treeCanvas);
    // item 5: fluid zoom — scale visually AND widen/narrow the layout box so
    // rows reflow to fill the freed width (no dead horizontal space).
    treeCanvas.style.transform = 'scale(' + zoom + ')';
    treeCanvas.style.width = (100 / zoom) + '%';
    var f = forest(vis);
    var orderedRoots = applyOrder(f.roots, order('tree:' + activeTree), 'node_id');
    orderedRoots.forEach(function (r) { renderTreeNode(r, f.kids, treeCanvas); });
    treeCrumb.textContent = sel ? crumb(sel) : 'no selection';
  }

  // ---- ACTIONS PANE (C3) ----------------------------------------------
  function actionEntries() {
    var out = [];
    visibleNodes().forEach(function (n) {
      if (n.state === 'archived') return;
      (n.items || []).forEach(function (it) {
        if (isWaiting(it)) out.push({ n: n, it: it });
      });
    });
    return out;
  }
  function sortActions(arr) {
    var mode = actionsSort.value;
    if (mode === 'manual') {
      var ord = order('actions:' + activeTree);
      return applyOrderObj(arr, ord, function (x) { return x.it.item_id; });
    }
    var c = arr.slice();
    c.sort(function (a, b) {
      if (mode === 'deferred') return (a.it.deferred ? 1 : 0) - (b.it.deferred ? 1 : 0);
      if (mode === 'node') return crumb(a.n.node_id).localeCompare(crumb(b.n.node_id));
      return a.it.kind.localeCompare(b.it.kind); // 'kind' default
    });
    return c;
  }
  function renderActions() {
    if (!loaded) { paneState(actionsState, actionsBody, 'loading'); return; }
    var entries = sortActions(actionEntries());
    if (entries.length === 0) {
      paneState(actionsState, actionsBody, 'steady-empty', {
        steady: 'Nothing waiting on you right now — items appear here when Dispatch raises a decision/question or an action needs you.',
      });
      return;
    }
    paneState(actionsState, actionsBody, 'populated');
    clear(actionsBody);
    // items 7+8: detect newly-arrived action items (flash + "+N new" badge)
    var dN = diffNewIds(entries.map(function (e) { return e.it.item_id; }), seenActionIds, 'a');
    newActionIds = dN.fresh;
    if (dN.count) { newActionsCount += dN.count; updateNewBadges(); }
    entries.forEach(function (en, ix) {
      var n = en.n, it = en.it;
      var li = el('div', 'li' + (it.contested ? ' contested' : '')
        + (it.responded ? ' responded' : '')
        + (newActionIds[it.item_id] ? ' flash' : ''));
      li.setAttribute('draggable', actionsSort.value === 'manual' ? 'true' : 'false');
      var top = el('div', 'li-top');
      top.appendChild(el('span', 'li-kind ' + it.kind, it.kind));
      top.appendChild(el('span', 'li-text', it.text));
      if (it.deferred) {
        var d = el('span', 'badge deferred', 'deferred' + (it.scheduled_for ? ' · ' + fmtTime(it.scheduled_for) : ''));
        top.appendChild(d);
      }
      var cr = el('span', 'li-crumb', crumb(n.node_id));
      cr.title = 'reveal in tree';
      cr.addEventListener('click', function () { focusNode(n.node_id); });
      top.appendChild(cr);
      li.appendChild(top);

      // item 9: rich-details disclosure (collapsed by default)
      if (it.details && typeof it.details === 'object') {
        var expanded = expandedItems.has(it.item_id);
        var disc = el('button', 'ghost det-toggle', (expanded ? '▾' : '▸') + ' details');
        disc.addEventListener('click', function () {
          if (expandedItems.has(it.item_id)) expandedItems.delete(it.item_id);
          else expandedItems.add(it.item_id);
          renderActions();
        });
        li.appendChild(disc);
        if (expanded) li.appendChild(renderItemDetails(it.details));
      }
      // item 10: responded — awaiting confirmation (visible, de-emphasised)
      if (it.responded) {
        var rn = el('div', 'responded-note');
        rn.appendChild(el('span', 'badge', 'responded — awaiting confirmation'));
        rn.appendChild(el('div', 'muted', it.responded.text));
        var cp = el('button', 'ghost', '⧉ Copy to Dispatch →');
        cp.addEventListener('click', function () { copyResponseForDispatch(it, it.responded.text); });
        rn.appendChild(cp);
        li.appendChild(rn);
      }

      if (it.contested) {
        var label = it.contested.direction === 'dispatch-done-you-disputed'
          ? '⚠ Dispatch marked done · you disputed'
          : '⚠ You marked done · Dispatch disputed';
        var cn = el('div', 'contest-note');
        cn.appendChild(el('div', null, label));
        cn.appendChild(el('div', 'muted', it.contested.note || ''));
        var rb = el('div', 'li-actions');
        var accept = el('button', 'ghost', 'Accept their position');
        accept.addEventListener('click', function () {
          post({ type: 'contest-resolved', node_id: n.node_id, item_id: it.item_id, resolution: 'accept-theirs' }, 'resolved')
            .then(function (ok) { if (ok) maybeAutoConclude(n.node_id); });
        });
        var keep = el('button', 'ghost', 'Keep mine, re-open');
        keep.addEventListener('click', function () {
          post({ type: 'contest-resolved', node_id: n.node_id, item_id: it.item_id, resolution: 'keep-mine-reopen' }, 'resolved');
        });
        rb.appendChild(accept); rb.appendChild(keep);
        cn.appendChild(rb);
        li.appendChild(cn);
      } else {
        var acts = el('div', 'li-actions');
        var done = el('button', 'ghost', it.kind === 'action' ? 'mark done' : 'mark answered');
        done.addEventListener('click', function () {
          var type = it.kind === 'action' ? 'action-done' : 'answered';
          var label = it.kind === 'action' ? 'Marked done' : 'Marked answered';
          actWithUndo(li,
            { type: type, node_id: n.node_id, item_id: it.item_id }, label,
            function () {   // item 7 undo: re-surface the item (+ re-open node if it auto-concluded)
              post({ type: 'item-unchecked', node_id: n.node_id, item_id: it.item_id }, 'undone', true)
                .then(function (ok) {
                  if (!ok) return;
                  var nd = byId(n.node_id);
                  if (nd && nd.state === 'concluded') post({ type: 're-opened', node_id: n.node_id }, 're-opened', true);
                });
            },
            function () { maybeAutoConclude(n.node_id); });
        });
        acts.appendChild(done);
        // D2: dispute a state-checked item (low-emphasis safety net).
        if (it.checked) {
          var dis = el('button', 'ghost', 'dispute');
          dis.title = 'safety net — not a distrust mechanism';
          dis.addEventListener('click', function () {
            var note = prompt('Why do you dispute this being done? (a note; can become a thread in Dispatch)');
            if (note == null) return;
            post({ type: 'contested', node_id: n.node_id, item_id: it.item_id, direction: 'dispatch-done-you-disputed', note: note }, 'flagged contested');
          });
          acts.appendChild(dis);
        }
        // D3: defer / clear-defer.
        if (it.deferred) {
          var clr = el('button', 'ghost', 'clear defer');
          clr.addEventListener('click', function () { post({ type: 'defer-cleared', node_id: n.node_id, item_id: it.item_id }, 'defer cleared'); });
          acts.appendChild(clr);
        } else {
          var dfr = el('button', 'ghost', 'defer');
          dfr.addEventListener('click', function () {
            var when = prompt('Defer until (ISO time, or blank for no schedule):', new Date(Date.now() + 36e5).toISOString());
            if (when == null) return;
            actWithUndo(li,
              { type: 'deferred', node_id: n.node_id, item_id: it.item_id, scheduled_for: when.trim() || null }, 'Deferred',
              function () { post({ type: 'defer-cleared', node_id: n.node_id, item_id: it.item_id }, 'defer cleared', true); });
          });
          acts.appendChild(dfr);
        }
        // item 10: inline Respond on decisions/questions/needs-input (only
        // when not yet responded — the responded note above takes over then)
        if (respondable(it) && !it.responded) {
          var rsp = el('button', 'ghost', 'Respond');
          rsp.addEventListener('click', function () {
            if (li.querySelector('.respond-box')) return;   // one open at a time
            var rb2 = el('div', 'respond-box');
            var ta = el('textarea', 'draft-area');
            ta.placeholder = 'Your response — captured here; Copy to Dispatch closes the loop (v1.1).';
            var row = el('div', 'row');
            var submit = el('button', 'primary', 'Submit response');
            submit.addEventListener('click', function () {
              var txt = ta.value.trim();
              if (!txt) { ta.focus(); return; }
              post({ type: 'action-responded', node_id: n.node_id, item_id: it.item_id, response_text: txt }, 'response captured')
                .then(function (ok) { if (ok) copyResponseForDispatch(it, txt); });
            });
            var cancel = el('button', 'ghost', 'cancel');
            cancel.addEventListener('click', function () { rb2.remove(); });
            row.appendChild(submit); row.appendChild(cancel);
            rb2.appendChild(ta); rb2.appendChild(row);
            li.appendChild(rb2);
            ta.focus();
          });
          acts.appendChild(rsp);
        }
        li.appendChild(acts);
      }
      // manual drag-reorder (FR-29)
      if (actionsSort.value === 'manual') wireReorder(li, it.item_id, 'actions:' + activeTree, function () { return actionEntries().map(function (e) { return e.it.item_id; }); });
      actionsBody.appendChild(li);
    });
  }

  // ---- BACKLOG PANE (C4) ----------------------------------------------
  function backlogEntries() {
    return backlog().filter(function (b) { return (b.tree_id || 'global') === activeTree; });
  }
  var PRIO_RANK = { high: 0, medium: 1, low: 2 };
  function sortBacklog(arr) {
    var mode = backlogSort.value;
    if (mode === 'manual') return applyOrderObj(arr, order('backlog:' + activeTree), function (b) { return b.item_id; });
    var c = arr.slice();
    if (mode === 'priority') c.sort(function (a, b) { return (PRIO_RANK[a.priority] || 9) - (PRIO_RANK[b.priority] || 9); });
    else c.sort(function (a, b) { return String(a.item_id).localeCompare(String(b.item_id)); }); // date (ULID-ish id is time-sortable)
    return c;
  }
  function renderBacklog() {
    if (!loaded) { paneState(backlogState, backlogBody, 'loading'); return; }
    var entries = sortBacklog(backlogEntries());
    if (entries.length === 0) {
      var aff = el('button', 'primary', '+ capture one');
      aff.addEventListener('click', openCapture);
      paneState(backlogState, backlogBody, 'steady-empty', {
        steady: 'No backlog items in "' + activeTree + '" — capture one with [+].',
        affordance: aff,
      });
      return;
    }
    paneState(backlogState, backlogBody, 'populated');
    clear(backlogBody);
    var dB = diffNewIds(entries.map(function (x) { return x.item_id; }), seenBacklogIds, 'b');
    newBacklogIds = dB.fresh;
    if (dB.count) { newBacklogCount += dB.count; updateNewBadges(); }
    entries.forEach(function (b) {
      var li = el('div', 'li' + (newBacklogIds[b.item_id] ? ' flash' : ''));
      li.setAttribute('draggable', backlogSort.value === 'manual' ? 'true' : 'false');
      var top = el('div', 'li-top');
      top.appendChild(el('span', 'prio ' + b.priority, b.priority));
      top.appendChild(el('span', 'li-text', b.text));
      if (b.activated) top.appendChild(el('span', 'badge', 'activated ✓'));
      li.appendChild(top);
      if (b.context_refs && b.context_refs.length) {
        li.appendChild(el('div', 'muted', 'context: ' + b.context_refs.join(' | ')));
      }
      var acts = el('div', 'li-actions');
      if (!b.activated) {
        var act = el('button', 'primary', 'Activate → new tree root');
        act.addEventListener('click', function () { activateBacklog(b); });
        acts.appendChild(act);
        var addc = el('button', 'ghost', '+ context');
        addc.addEventListener('click', function () {
          var note = prompt('Attach a context note / file ref / prior-decision:');
          if (note == null || !note.trim()) return;
          post({ type: 'context-attached', target: b.item_id, context_ref: note.trim() }, 'context attached');
        });
        acts.appendChild(addc);
      } else {
        var copy = el('button', 'ghost', '⧉ copy context for Dispatch');
        copy.addEventListener('click', function () { copyHandoff(b.text, b.context_refs, b.activated_node); });
        acts.appendChild(copy);
      }
      li.appendChild(acts);
      if (backlogSort.value === 'manual') wireReorder(li, b.item_id, 'backlog:' + activeTree, function () { return backlogEntries().map(function (x) { return x.item_id; }); });
      backlogBody.appendChild(li);
    });
  }
  function openCapture() {
    backlogCapture.hidden = false; blText.value = ''; blContext.value = '';
    blText.focus();
  }
  addBacklogBtn.addEventListener('click', openCapture);
  blCancel.addEventListener('click', function () { backlogCapture.hidden = true; });
  blSave.addEventListener('click', function () {
    var txt = blText.value.trim();
    if (!txt) { blText.focus(); return; }
    var itemId = uid('bl');
    post({ type: 'backlog-added', item_id: itemId, tree_id: activeTree, priority: blPriority.value, text: txt }, 'backlog item added')
      .then(function (ok) {
        if (!ok) return;
        var ctx = blContext.value.trim();
        if (ctx) post({ type: 'context-attached', target: itemId, context_ref: ctx }, 'context attached');
        backlogCapture.hidden = true;
      });
  });
  function activateBacklog(b) {
    var newId = uid('n');
    post({ type: 'backlog-activated', item_id: b.item_id, new_node_id: newId }, 'activated — new tree root created')
      .then(function (ok) {
        if (!ok) return;
        // BF-1 / DEC-C positive handoff affordance.
        copyHandoff(b.text, b.context_refs, newId);
        pushNote('act-' + b.item_id,
          '▸ ready to start in Dispatch — "' + b.text + '" is now a tracked tree root. ' +
          'This tracker doesn’t run Claude — open Dispatch and continue there; this node now tracks it. ' +
          '(Context copied to clipboard.)', false);
        // item 7 undo (partial, documented): reverses the user-visible effect
        // by archiving the just-created node (no un-activate event exists).
        snackbar('Activated — Undo?', { kind: 'ok', undo: function () {
          post({ type: 'archived', node_id: newId }, 'undone — node archived', true);
        } });
      });
  }
  function copyHandoff(text, ctx, nodeId) {
    var blob = 'Continue this work in Dispatch:\n\n' + text + '\n\n' +
      (ctx && ctx.length ? 'Context:\n- ' + ctx.join('\n- ') + '\n\n' : '') +
      'Tracker node: ' + (nodeId || '(new)') + '\n';
    try {
      navigator.clipboard.writeText(blob).then(
        function () { showToast('context copied — paste into Dispatch', 'ok'); },
        function () { fallbackCopy(blob); });
    } catch (_) { fallbackCopy(blob); }
  }
  function fallbackCopy(blob) {
    var ta = el('textarea'); ta.value = blob; ta.style.position = 'fixed'; ta.style.left = '-9999px';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); showToast('context copied — paste into Dispatch', 'ok'); }
    catch (e) { showToast('copy failed — select the context block manually', 'err'); }
    document.body.removeChild(ta);
  }

  // ---- ordering helpers (FR-29 reordered) ------------------------------
  function applyOrder(arr, ord, key) {
    if (!ord) return arr;
    var pos = {}; ord.forEach(function (id, i) { pos[id] = i; });
    return arr.slice().sort(function (a, b) {
      var pa = pos[a[key]], pb = pos[b[key]];
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1; if (pb == null) return -1;
      return pa - pb;
    });
  }
  function applyOrderObj(arr, ord, keyFn) {
    if (!ord) return arr;
    var pos = {}; ord.forEach(function (id, i) { pos[id] = i; });
    return arr.slice().sort(function (a, b) {
      var pa = pos[keyFn(a)], pb = pos[keyFn(b)];
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1; if (pb == null) return -1;
      return pa - pb;
    });
  }
  var dragId = null;
  function wireReorder(li, id, scope, idsFn) {
    li.addEventListener('dragstart', function () { dragId = id; });
    li.addEventListener('dragover', function (e) { e.preventDefault(); li.classList.add('dragover'); });
    li.addEventListener('dragleave', function () { li.classList.remove('dragover'); });
    li.addEventListener('drop', function (e) {
      e.preventDefault(); li.classList.remove('dragover');
      if (!dragId || dragId === id) return;
      var ids = idsFn();
      ids = ids.filter(function (x) { return x !== dragId; });
      var at = ids.indexOf(id);
      ids.splice(at < 0 ? ids.length : at, 0, dragId);
      post({ type: 'reordered', scope: scope, ordered_ids: ids }, 'reordered');
      dragId = null;
    });
  }

  // ---- node selection + FR-6 context surface (C2) ----------------------
  function selectNode(id) { sel = id; ctxExpanded = false; render(); openCtx(id); }
  function focusNode(id) {                          // BF-4 cross-surface nav
    var n = byId(id); if (!n) return;
    if (treeOf(n) !== activeTree) {
      activeTree = treeOf(n); localStorage.setItem('ctree-active', activeTree); syncTreeSelect();
      showToast('Switched to "' + activeTree + '" tree to show this', 'ok');
    }
    chain(id).forEach(function (a) { collapsed.delete(a.node_id); }); // expand ancestors
    sel = id; render(); openCtx(id);
    setTimeout(function () {
      var r = treeCanvas.querySelector('[data-node="' + cssEsc(id) + '"]');
      if (r) r.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }, 30);
  }
  function cssEsc(s) { return String(s).replace(/"/g, '\\"'); }
  // v1.1 item 2: single dismiss path. Hides panel + backdrop scrim and
  // clears selection so a later render()/SSE frame does not re-open it.
  function closeCtx() {
    ctxPanel.hidden = true;
    ctxScrim.hidden = true;
    sel = null;
    render();
  }
  function openCtx(id) {
    var n = byId(id);
    if (!n) { closeCtx(); return; }
    ctxPanel.hidden = false;
    ctxScrim.hidden = false;          // CSS hides the scrim at >=1440 (docked)
    clear(ctxPanel);
    var head = el('div', 'ctx-head');
    head.appendChild(el('span', 'pane-title', n.title || n.node_id));
    var x = el('button', 'ghost x', '✕');
    x.title = 'close (Esc / click outside also close)';
    x.addEventListener('click', closeCtx);
    head.appendChild(x);
    ctxPanel.appendChild(head);
    var body = el('div', 'ctx-body');

    // parent chain to root
    var s1 = el('div', 'ctx-sec'); s1.appendChild(el('h4', null, 'Parent chain → root'));
    var cc = el('div', 'ctx-chain');
    chain(id).reverse().forEach(function (a, i, arr) {
      var seg = el('span', 'seg', a.title || a.node_id);
      seg.addEventListener('click', function () { focusNode(a.node_id); });
      cc.appendChild(seg);
      if (i < arr.length - 1) cc.appendChild(document.createTextNode('  ›  '));
    });
    s1.appendChild(cc); body.appendChild(s1);

    // diverging sub-branches
    var subs = nodes().filter(function (x) { return x.parent_id === id; });
    var s2 = el('div', 'ctx-sec'); s2.appendChild(el('h4', null, 'Diverging sub-branches (' + subs.length + ')'));
    if (subs.length === 0) s2.appendChild(el('div', 'muted', 'none'));
    subs.forEach(function (x) {
      var d = el('div', 'ctx-item ' + 'seg'); d.textContent = x.title || x.node_id;
      d.style.cursor = 'pointer'; d.addEventListener('click', function () { focusNode(x.node_id); });
      s2.appendChild(d);
    });
    body.appendChild(s2);

    // open items (summary -> full, OQ-3 layered)
    var open = (n.items || []).filter(function (it) { return isWaiting(it); });
    var s3 = el('div', 'ctx-sec'); s3.appendChild(el('h4', null, 'Open items (' + open.length + ')'));
    var showN = ctxExpanded ? open.length : Math.min(3, open.length);
    open.slice(0, showN).forEach(function (it) {
      var d = el('div', 'ctx-item', '[' + it.kind + '] ' + it.text +
        (it.deferred ? '  (deferred)' : '') + (it.contested ? '  (contested)' : ''));
      var pr = el('button', 'ghost', 'promote to branch');
      pr.style.marginLeft = '0.4rem';
      pr.addEventListener('click', function () {
        post({ type: 'promoted', node_id: n.node_id, item_id: it.item_id, new_node_id: uid('n') }, 'promoted to branch');
      });
      d.appendChild(pr);
      s3.appendChild(d);
    });
    if (open.length > showN || (ctxExpanded && open.length > 3)) {
      var more = el('div', 'ctx-more', ctxExpanded ? 'show less' : 'show all ' + open.length + ' — fuller context');
      more.addEventListener('click', function () { ctxExpanded = !ctxExpanded; openCtx(id); });
      s3.appendChild(more);
    }
    body.appendChild(s3);

    // cross-links (FR-3) + add cross-link
    var s4 = el('div', 'ctx-sec'); s4.appendChild(el('h4', null, 'Cross-links'));
    (n.cross_links || []).forEach(function (cl) {
      var chip = el('span', 'xlink-chip', (cl.tag || 'link') + ' → ' + (byId(cl.to) ? byId(cl.to).title : cl.to));
      chip.addEventListener('click', function () { if (byId(cl.to)) focusNode(cl.to); });
      s4.appendChild(chip); s4.appendChild(document.createTextNode(' '));
    });
    var addL = el('button', 'ghost', '+ cross-link');
    addL.addEventListener('click', function () {
      var to = prompt('Link to which node_id? (cross-tree allowed)');
      if (!to) return;
      var tag = prompt('Link tag / relationship:', 'related');
      post({ type: 'cross-linked', from_node: n.node_id, to_node: to.trim(), tag: (tag || 'related').trim() }, 'cross-linked');
    });
    s4.appendChild(document.createElement('br')); s4.appendChild(addL);
    body.appendChild(s4);

    // D4 per-branch draft (a STAGED note to paste into Dispatch — BF-1; no
    // send/compose affordance). Live-persist to localStorage (best-effort,
    // NFR-1); "stage" persists to state; "mark used" clears.
    var s5 = el('div', 'ctx-sec'); s5.appendChild(el('h4', null, 'Staged note (paste into Dispatch — not a message channel)'));
    var ta = el('textarea', 'draft-area');
    ta.value = (localStorage.getItem('ctree-draft-' + id) != null)
      ? localStorage.getItem('ctree-draft-' + id) : (n.draft || '');
    ta.addEventListener('input', function () { localStorage.setItem('ctree-draft-' + id, ta.value); });
    s5.appendChild(ta);
    var dr = el('div', 'row');
    var stage = el('button', 'ghost', 'stage (persist)');
    stage.addEventListener('click', function () { post({ type: 'draft-saved', node_id: id, draft_text: ta.value }, 'note staged'); });
    var copyD = el('button', 'ghost', '⧉ copy');
    copyD.addEventListener('click', function () { copyHandoff(n.title, [ta.value], id); });
    var used = el('button', 'ghost', 'mark used / clear');
    used.addEventListener('click', function () {
      localStorage.removeItem('ctree-draft-' + id);
      post({ type: 'draft-cleared', node_id: id }, 'note cleared');
    });
    dr.appendChild(stage); dr.appendChild(copyD); dr.appendChild(used);
    s5.appendChild(dr);
    body.appendChild(s5);

    // node-level controls: archive / annotate. NO continue/resume anywhere.
    var s6 = el('div', 'ctx-sec'); s6.appendChild(el('h4', null, 'Node'));
    var r6 = el('div', 'row');
    if (n.state === 'archived') {
      var rest = el('button', 'ghost', 'restore from archive');
      rest.addEventListener('click', function () { post({ type: 're-opened', node_id: id }, 'restored'); });
      r6.appendChild(rest);
    } else {
      var arch = el('button', 'ghost', 'archive');
      arch.title = 'archival never closes a Claude Code session (FR-28)';
      arch.addEventListener('click', function () {
        post({ type: 'archived', node_id: id }, 'Archived', true).then(function (ok) {
          if (!ok) return;
          snackbar('Archived — Undo?', { kind: 'ok', undo: function () {
            post({ type: 're-opened', node_id: id }, 'undone — restored', true);
          } });
        });
        closeCtx();
      });
      r6.appendChild(arch);
    }
    var note = el('button', 'ghost', 'annotate');
    note.addEventListener('click', function () {
      var t = prompt('Annotation (lifecycle trail / FR-12):'); if (!t) return;
      post({ type: 'annotated', node_id: id, text: t }, 'annotated');
    });
    r6.appendChild(note);
    s6.appendChild(r6);
    s6.appendChild(el('div', 'handoff-explain',
      'This tracker doesn’t run Claude — open Dispatch and continue there; this node now tracks it.'));
    body.appendChild(s6);

    ctxPanel.appendChild(body);
  }

  // ---- D1 auto-conclude (only when the full checklist is checked) ------
  function maybeAutoConclude(nodeId) {
    var n = byId(nodeId); if (!n || !n.items || n.items.length === 0) return;
    var allChecked = n.items.every(function (it) { return it.checked && !it.contested; });
    if (allChecked && n.state === 'open') {
      post({ type: 'concluded', node_id: nodeId }, 'branch concluded');
    }
  }

  // ---- persistent in-GUI notifications (BF-6 / DEC-B) ------------------
  function pushNote(key, msg, hot) {
    if (dismissed.has(key)) return;
    var existing = noteStack.querySelector('[data-k="' + cssEsc(key) + '"]');
    if (existing) return;
    var nd = el('div', 'note' + (hot ? ' hot' : ''));
    nd.setAttribute('data-k', key);
    var x = el('button', 'ghost dismiss', '✕');
    x.addEventListener('click', function () { dismissed.add(key); nd.remove(); });
    nd.appendChild(x);
    nd.appendChild(document.createTextNode(msg));
    noteStack.appendChild(nd);
  }
  function detectConcludeNotifications() {
    nodes().forEach(function (n) {
      if (n.state === 'concluded' && !seenConcluded.has(n.node_id)) {
        seenConcluded.add(n.node_id);
        if (primed && n.parent_id) {
          var p = byId(n.parent_id);
          pushNote('concl-' + n.node_id,
            'Branch "' + (n.title || n.node_id) + '" concluded — parent "' +
            (p ? p.title : n.parent_id) + '" notified.', false);
        }
      }
    });
    primed = true;
  }
  function fmtTime(t) { try { return new Date(t).toLocaleString(); } catch (_) { return String(t); } }
  // D3: at the scheduled time, highlight + notify exactly ONCE; do nothing
  // else (no auto-clear, no auto-move, no auto-act).
  function checkDefers() {
    var now = Date.now();
    nodes().forEach(function (n) {
      (n.items || []).forEach(function (it) {
        if (it.deferred && it.scheduled_for) {
          var due = Date.parse(it.scheduled_for);
          var key = n.node_id + ':' + it.item_id + ':' + it.scheduled_for;
          if (!isNaN(due) && due <= now && !firedDefers.has(key)) {
            firedDefers.add(key);
            localStorage.setItem('ctree-fired', JSON.stringify([].slice.call(firedDefers)));
            pushNote('defer-' + key,
              'Deferred item due: "' + it.text + '" (' + crumb(n.node_id) + '). ' +
              'It stays on your list, tagged — nothing was moved or cleared.', true);
          }
        }
      });
    });
  }

  // ---- project (tree) selector (D5) ------------------------------------
  function syncTreeSelect() {
    var trees = nodeTrees();
    clear(treeSelect);
    trees.forEach(function (t) {
      var o = el('option', null, t === 'global' ? 'global (cross-cutting)' : t);
      o.value = t; if (t === activeTree) o.selected = true;
      treeSelect.appendChild(o);
    });
    if (trees.indexOf(activeTree) === -1) { activeTree = 'global'; }
  }
  treeSelect.addEventListener('change', function () {
    activeTree = treeSelect.value; localStorage.setItem('ctree-active', activeTree);
    closeCtx();
  });
  addProjBtn.addEventListener('click', function () {
    var name = prompt('New project tree name (user-directed; no auto-discovery):');
    if (!name || !name.trim()) return;
    name = name.trim();
    var ps = JSON.parse(localStorage.getItem('ctree-projects') || '[]');
    if (ps.indexOf(name) === -1) ps.push(name);
    localStorage.setItem('ctree-projects', JSON.stringify(ps));
    activeTree = name; localStorage.setItem('ctree-active', name);
    syncTreeSelect(); render();
  });
  showArchived.addEventListener('change', render);
  actionsSort.addEventListener('change', renderActions);
  backlogSort.addEventListener('change', renderBacklog);

  // ---- item 3: hide-concluded toggle (localStorage UI-pref) ------------
  function applyShowConcluded() {
    showConcludedPref = !!showConcluded.checked;
    localStorage.setItem('ctree-show-concluded', showConcludedPref ? '1' : '0');
    render();
  }
  showConcluded.checked = showConcludedPref;       // default OFF = hide
  showConcluded.addEventListener('change', applyShowConcluded);

  // ---- item 2: ctx overlay dismiss — click-outside + Esc ---------------
  ctxScrim.addEventListener('click', closeCtx);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !ctxPanel.hidden) closeCtx();
  });

  // ---- item 1: single-pane tab bar (layout C only) ---------------------
  // CSS shows #tabBar only when w<1024 AND h<1024; JS just flips
  // body[data-tab]. Default tab = tree (matches the CSS :not([data-tab])).
  if (!document.body.dataset.tab) document.body.dataset.tab = 'tree';
  tabBar.addEventListener('click', function (e) {
    var b = e.target.closest('button[data-tab]');
    if (!b) return;
    document.body.dataset.tab = b.dataset.tab;
    [].forEach.call(tabBar.querySelectorAll('button'), function (x) {
      x.classList.toggle('active', x === b);
    });
    if (b.dataset.tab === 'actions') clearNewBadge('a');   // item 8: looked at it
    if (b.dataset.tab === 'backlog') clearNewBadge('b');
  });
  // item 8: looking at a pane (scroll or click within it) clears its badge.
  actionsBody.addEventListener('scroll', function () { clearNewBadge('a'); });
  actionsBody.addEventListener('click', function () { clearNewBadge('a'); });
  backlogBody.addEventListener('scroll', function () { clearNewBadge('b'); });
  backlogBody.addEventListener('click', function () { clearNewBadge('b'); });

  // ---- pan/zoom (C2) ---------------------------------------------------
  zoomIn.addEventListener('click', function () { zoom = Math.min(2, zoom + 0.1); renderTree(); });
  zoomOut.addEventListener('click', function () { zoom = Math.max(0.4, zoom - 0.1); renderTree(); });
  // item 4: true fit-to-viewport. Measure the tree's NATURAL (zoom==1)
  // bounding box, derive the scale that fits it inside the visible tree-pane
  // area with a small padding margin, apply scale + scroll to origin. Works
  // with no node selected (the old impl no-op'd without a selection).
  fitSel.addEventListener('click', function () {
    if (!loaded || visibleNodes().length === 0) return;
    var pT = treeCanvas.style.transform, pW = treeCanvas.style.width;
    treeCanvas.style.transform = 'scale(1)';
    treeCanvas.style.width = '100%';
    // read layout metrics at natural scale (transform does not affect them)
    var cw = treeCanvas.scrollWidth, ch = treeCanvas.scrollHeight;
    var vw = treeScroll.clientWidth, vh = treeScroll.clientHeight;
    if (!cw || !ch || !vw || !vh) { treeCanvas.style.transform = pT; treeCanvas.style.width = pW; return; }
    var z = Math.min(vw / cw, vh / ch) * 0.96;          // 4% padding
    z = Math.max(0.15, Math.min(2, z));                 // fit may zoom further out than +/-
    zoom = z;
    renderTree();                                       // applies scale + width:(100/zoom)%
    treeScroll.scrollLeft = 0; treeScroll.scrollTop = 0;
    showToast('fit to view (' + Math.round(z * 100) + '%)', 'ok');
  });
  (function () { // drag-to-pan on empty tree space
    var down = false, sx, sy, sl, st;
    treeScroll.addEventListener('mousedown', function (e) {
      if (e.target.closest('.tnode-row')) return;
      down = true; sx = e.clientX; sy = e.clientY; sl = treeScroll.scrollLeft; st = treeScroll.scrollTop;
    });
    window.addEventListener('mousemove', function (e) {
      if (!down) return;
      treeScroll.scrollLeft = sl - (e.clientX - sx);
      treeScroll.scrollTop = st - (e.clientY - sy);
    });
    window.addEventListener('mouseup', function () { down = false; });
  })();

  // ---- top-level render ------------------------------------------------
  function render() {
    var corrupt = renderCorrupt();
    syncTreeSelect();
    if (corrupt && (!S || (!S.nodes || S.nodes.length === 0))) {
      // corruption with no last-good content: panes show first-run, banner
      // carries the truth — never a blank screen (UX-I4).
    }
    renderTree();
    renderActions();
    renderBacklog();
    if (sel && !ctxPanel.hidden) openCtx(sel);
  }

  // ---- SSE connection (read half of the file contract) -----------------
  function connect() {
    var es = new EventSource('/api/events');
    es.addEventListener('state', function (e) {
      try { S = JSON.parse(e.data); } catch (err) { return; }
      loaded = true;
      lastRead.textContent = 'last read ' + new Date().toLocaleTimeString();
      statusEl.textContent = 'live'; statusEl.classList.add('live');
      detectConcludeNotifications();
      checkDefers();
      render();
    });
    es.onerror = function () {
      statusEl.textContent = 'reconnecting…'; statusEl.classList.remove('live');
    };
  }
  setInterval(checkDefers, 30000); // D3 scheduled-time poll
  connect();
})();
