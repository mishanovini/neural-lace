'use strict';
/* Workstreams UI — v2 work-first reframe (2026-05-30). Formerly the
 * Conversation Tree UI client. ADR-031 Option-2 passive tracker: reads the
 * file-mediated state contract via SSE (/api/events → "state"), writes GUI
 * mutations as single appended events through POST /api/event (symmetric
 * FR-11). The GUI NEVER spawns / feeds / steers a Claude Code session — there
 * is no continue / resume / compose / send affordance (Option-2 invariant).
 * No framework, no build step (Node-stdlib server; vanilla DOM here).
 *
 * Reframe (vs the Conversation-Tree renderer it replaces):
 *   - LEFT pane renders a four-tier hierarchy: Project → Workstream → WorkItem
 *     → Sub-task. Sessions (sess-* / sub-* nodes) are NEVER rendered as their
 *     own row; they surface only as provenance inside the detail card.
 *   - RIGHT pane is a filter-driven single list (Awaiting me / In flight /
 *     Blocked / Recently shipped / Orphaned / Backlog / All), replacing the
 *     stacked Waiting/Backlog/Decisions/Questions accordion. Default filter =
 *     "Awaiting me"; default-visible states are the non-complete ones
 *     ({proposed, committed, in-flight, blocked}); {shipped, closed} hide until
 *     "All" / "Recently shipped" is chosen (Misha's 2026-05-30 Q2 answer).
 *   - Selecting an item replaces the filtered list with a detail card
 *     (kind / tier / state / provenance / sub-task rollup / action buttons).
 *   - An adjustable divider resizes the two panes; the split persists to
 *     localStorage.
 *
 * Today's data has no explicit Workstream tier (items hang directly off
 * project roots); the four-tier functions degrade gracefully to Project →
 * WorkItem and light up the Workstream tier automatically once Phase-3
 * backfill assigns it. */
(function () {
  // ---- element handles -------------------------------------------------
  var $ = function (id) { return document.getElementById(id); };
  var showArchived = $('showArchived'),
      freshnessEl = $('freshness'), statusEl = $('status'),
      corruptBanner = $('corruptBanner'), toast = $('toast'),
      treeCanvas = $('treeCanvas'), treeScroll = $('treeScroll'),
      treeState = $('treeState'), treeSummary = $('treeSummary'),
      orphanSection = $('orphanSection'), orphanBody = $('orphanBody'),
      orphanCount = $('orphanCount'),
      filterBar = $('filterBar'), filterBody = $('filterBody'),
      filterState = $('filterState'), detailCard = $('detailCard'),
      layout = $('layout'), divider = $('divider'),
      addBacklogBtn = $('addBacklogBtn'), backlogCapture = $('backlogCapture'),
      blText = $('blText'), blContext = $('blContext'),
      blPriority = $('blPriority'), blSave = $('blSave'), blCancel = $('blCancel');

  // ---- client view state ----------------------------------------------
  var S = null;                 // latest snapshot { nodes, backlog, rejections, ... }
  var loaded = false;
  var activeFilter = localStorage.getItem('workstreams.activeFilter') || 'awaiting-me';
  var focusProject = localStorage.getItem('workstreams.focusProject') || null;
  var collapsed = loadSet('workstreams.collapsed');   // project ids the user collapsed
  var selItem = null;           // { nodeId, itemId } currently in the detail card
  var ORPHAN_HOURS = 24;        // in-flight with no movement for >24h = orphan
  var SHIP_RECENT_DAYS = 7;

  function loadSet(key) {
    try { return new Set(JSON.parse(localStorage.getItem(key) || '[]')); }
    catch (_) { return new Set(); }
  }
  function saveSet(key, set) {
    try { localStorage.setItem(key, JSON.stringify(Array.from(set))); } catch (_) {}
  }

  // ---- tiny DOM helpers ------------------------------------------------
  function el(tag, cls, txt) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (txt != null) n.textContent = txt;
    return n;
  }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  var toastTimer = null;
  function showToast(msg, kind) {
    toast.textContent = msg;
    toast.className = 'toast' + (kind ? ' ' + kind : '');
    toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { toast.hidden = true; }, 2600);
  }
  function uid(p) {
    return (p || 'g') + '-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e5).toString(36);
  }

  // ---- event write path (symmetric FR-11) ------------------------------
  // POST one appended event to /api/event with one retry (exp backoff), then
  // surface an error toast and leave the GUI in pre-action state (no silent
  // loss — plan Behavioral Contracts → Retry semantics).
  function post(ev, okMsg) {
    if (!ev.event_id) ev.event_id = uid('gui');
    if (!ev.ts) ev.ts = new Date().toISOString();
    if (!ev.actor) ev.actor = 'gui';
    function attempt(delay) {
      return fetch('/api/event', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(ev),
      }).then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      }).then(function (j) {
        if (j && j.ok === false) throw new Error(j.error || 'rejected');
        if (okMsg) showToast(okMsg, 'ok');
        return j;
      }).catch(function (err) {
        if (delay < 2000) {
          return new Promise(function (res) { setTimeout(res, delay); })
            .then(function () { return attempt(Math.min(delay * 2, 2000)); });
        }
        showToast('Save failed — ' + err.message + '. Try again.', 'err');
        throw err;
      });
    }
    return attempt(200);
  }

  // ---- data accessors --------------------------------------------------
  function nodes() { return (S && Array.isArray(S.nodes)) ? S.nodes : []; }
  function backlog() { return (S && Array.isArray(S.backlog)) ? S.backlog : []; }
  function byId(id) { return nodes().find(function (n) { return n.node_id === id; }) || null; }
  function childrenOf(id) { return nodes().filter(function (n) { return n.parent_id === id; }); }

  // A project = a root node (parent_id == null). The proj-* roots are the real
  // projects; the today-* roots are archived daily rollups.
  function isProject(n) { return n && n.parent_id == null; }
  // Sessions / sub-branches surface only as provenance, never as a tree row.
  function isSession(n) { return n && /^(sess|sub)-/.test(n.node_id); }
  function projectTitle(n) { return n.title || n.node_id; }

  // WorkItems are the decision/question/action entries on a node (collectWorkItems).
  // The wire-check chain renderTree → collectWorkstreams → renderWorkstream →
  // collectWorkItems is preserved even though today's data has no Workstream
  // nodes (collectWorkstreams returns []), so items render directly under the
  // project via collectWorkItems(projectId).
  function collectWorkItems(scopeNodeId) {
    var n = byId(scopeNodeId);
    if (!n || !Array.isArray(n.items)) return [];
    return n.items.map(function (it) {
      return { nodeId: n.node_id, itemId: it.item_id, item: it, projectId: rootProjectOf(n.node_id) };
    });
  }
  // Workstream-tier nodes under a project = non-session child branches. Today
  // every child is a session, so this returns []; Phase-3 backfill adds real
  // workstream nodes (tier === 'workstream') which this picks up automatically.
  function collectWorkstreams(projectNodeId) {
    return childrenOf(projectNodeId).filter(function (c) {
      return !isSession(c) && (c.tier === 'workstream' || hasNonSessionDescendantItems(c));
    });
  }
  function hasNonSessionDescendantItems(n) {
    return Array.isArray(n.items) && n.items.length > 0;
  }
  function rootProjectOf(nodeId) {
    var n = byId(nodeId), guard = 0;
    while (n && n.parent_id != null && guard++ < 50) n = byId(n.parent_id);
    return n ? n.node_id : nodeId;
  }

  // ---- WorkItem state derivation --------------------------------------
  // Explicit it.state (from the new item-committed/shipped/blocked events)
  // wins; otherwise infer from the legacy checked/contested/deferred flags so
  // the existing 62 items render correctly without migration (plan Edge Cases).
  function itemState(it) {
    if (it.state) return it.state;
    if (it.checked) return 'shipped';
    if (it.contested) return 'blocked';
    if (it.deferred || it.backlogged) return 'committed';
    return 'in-flight';
  }
  var COMPLETE_STATES = { shipped: 1, closed: 1 };
  function isComplete(it) { return !!COMPLETE_STATES[itemState(it)]; }
  // Awaiting me = the legacy "waiting on you" predicate: unchecked & not parked
  // (deferred/contested still count as waiting). This is the default filter.
  function isWaiting(it) {
    return ((!it.checked) || it.deferred || it.contested) && !it.backlogged && itemState(it) !== 'shipped';
  }
  function nodeOpenedMs(nodeId) {
    var n = byId(nodeId);
    var t = n && (n.opened_at || null);
    var ms = t ? Date.parse(t) : NaN;
    return isNaN(ms) ? null : ms;
  }
  // Orphans (Phase 2) are STALE SESSIONS, matching the v2 design §3/§4 sketch
  // ("session 743934a8 — no declared item", "session a5d… — declared but
  // stalled") — NOT work items. A session node that opened but was never
  // concluded/archived, and last opened > ORPHAN_HOURS ago, is an un-reconciled
  // orphan: exactly what the Phase-4 hard-block gate will require dispositioning.
  // Item-level "no-progress-for-24h" needs the event log the GUI does not have
  // (Phase-3 reconciler adds it); until then the safe default for work items is
  // NON-orphaned (plan Integration points), so the orphan surface keys off the
  // session signal which IS computable from the snapshot.
  function staleSessions() {
    return nodes().filter(function (n) {
      if (!isSession(n)) return false;
      if (n.state === 'concluded' || n.state === 'archived') return false;
      var ms = nodeOpenedMs(n.node_id);
      if (ms == null) return true;                // unknown age but still open ⇒ orphan candidate
      return (Date.now() - ms) > ORPHAN_HOURS * 3600 * 1000;
    });
  }
  function isRecentlyShipped(it) {
    if (itemState(it) !== 'shipped') return false;
    if (!it.shipped_ts) return false;             // legacy checked items have no ship ts
    var ms = Date.parse(it.shipped_ts);
    if (isNaN(ms)) return false;
    return (Date.now() - ms) < SHIP_RECENT_DAYS * 86400 * 1000;
  }

  // ---- state-badge glyphs ---------------------------------------------
  var STATE_ICON = {
    proposed: '·', committed: '◷', 'in-flight': '◐', blocked: '⏳', shipped: '✓', closed: '✓',
  };
  function stateIcon(st) { return STATE_ICON[st] || '◐'; }
  function kindGlyph(k) { return k === 'decision' ? '◆' : k === 'question' ? '?' : '!'; }

  // ====================================================================
  //  ALL WORKITEMS (flattened, across every project) — the filter source
  // ====================================================================
  function allWorkItems() {
    var out = [];
    nodes().forEach(function (n) {
      if (isSession(n)) return;                   // sessions are provenance, not items
      if (n.state === 'archived' && !showArchived.checked) return;
      (n.items || []).forEach(function (it) {
        out.push({ nodeId: n.node_id, itemId: it.item_id, item: it, projectId: rootProjectOf(n.node_id) });
      });
    });
    return out;
  }

  // ---- filter logic ----------------------------------------------------
  function applyFilter(items, filterName) {
    switch (filterName) {
      case 'awaiting-me':      return items.filter(function (r) { return isWaiting(r.item); });
      case 'in-flight':        return items.filter(function (r) { return itemState(r.item) === 'in-flight'; });
      case 'blocked':          return items.filter(function (r) { return itemState(r.item) === 'blocked'; });
      case 'recently-shipped': return items.filter(function (r) { return isRecentlyShipped(r.item); });
      case 'orphaned':         return [];   // orphans are sessions, handled in renderFilteredItems
      case 'all':              return items.slice();
      default:                 return items.filter(function (r) { return isWaiting(r.item); });
    }
  }
  function filterCount(filterName) {
    if (filterName === 'backlog') return backlog().filter(function (b) { return !b.activated; }).length;
    if (filterName === 'orphaned') return staleSessions().length;
    return applyFilter(allWorkItems(), filterName).length;
  }
  function updateChipCounts() {
    ['awaiting-me', 'in-flight', 'blocked', 'recently-shipped', 'orphaned', 'backlog', 'all'].forEach(function (f) {
      var span = filterBar.querySelector('[data-count="' + f + '"]');
      if (span) span.textContent = filterCount(f);
    });
    Array.prototype.forEach.call(filterBar.querySelectorAll('.chip'), function (c) {
      c.classList.toggle('active', c.getAttribute('data-filter') === activeFilter);
      c.setAttribute('aria-selected', c.getAttribute('data-filter') === activeFilter ? 'true' : 'false');
    });
  }

  // setActiveFilter — the chip click handler (wire-check target).
  function setActiveFilter(filterName) {
    activeFilter = filterName;
    localStorage.setItem('workstreams.activeFilter', filterName);
    selItem = null;                               // leaving an item-detail context
    detailCard.hidden = true;
    renderFilteredItems(filterName);
    updateChipCounts();
  }

  // renderFilteredItems — re-render the single side-panel list for a filter.
  function renderFilteredItems(filterName) {
    detailCard.hidden = true;
    filterBody.hidden = false;
    clear(filterBody);
    if (filterName === 'backlog') { renderBacklogInto(filterBody); return; }
    if (filterName === 'orphaned') { renderOrphansInto(filterBody); return; }
    var refs = applyFilter(allWorkItems(), filterName);
    if (!refs.length) {
      filterBody.appendChild(emptyMsg(filterName));
      return;
    }
    // group by project for readability
    var byProj = {};
    refs.forEach(function (r) { (byProj[r.projectId] = byProj[r.projectId] || []).push(r); });
    Object.keys(byProj).forEach(function (pid) {
      var head = el('div', 'list-group-head', projectTitle(byId(pid) || { title: pid }));
      filterBody.appendChild(head);
      byProj[pid].forEach(function (r) { filterBody.appendChild(itemRow(r)); });
    });
  }
  function emptyMsg(filterName) {
    var labels = {
      'awaiting-me': 'Nothing is waiting on you. ✓',
      'in-flight': 'Nothing in flight right now.',
      'blocked': 'Nothing blocked.',
      'recently-shipped': 'Nothing shipped in the last ' + SHIP_RECENT_DAYS + ' days.',
      'orphaned': 'No orphaned work — every in-flight item has moved recently. ✓',
      'all': 'No work items yet.',
    };
    return el('div', 'empty', labels[filterName] || 'Nothing here.');
  }

  // a single work-item row in the filtered list
  function itemRow(r) {
    var st = itemState(r.item);
    var li = el('div', 'item-row state-' + st);
    li.setAttribute('data-node', r.nodeId);
    li.setAttribute('data-item', r.itemId);
    var ic = el('span', 'item-ic', stateIcon(st));
    ic.title = st;
    li.appendChild(ic);
    var body = el('div', 'item-main');
    var txt = el('div', 'item-text', r.item.text || '(untitled)');
    body.appendChild(txt);
    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'k-' + r.item.kind, r.item.kind));
    meta.appendChild(el('span', 'st-badge st-' + st, st));
    if (r.item.deferred) meta.appendChild(el('span', 'st-badge st-committed', 'deferred'));
    body.appendChild(meta);
    li.appendChild(body);
    li.addEventListener('click', function () { renderDetailCard(r.nodeId, r.itemId); });
    return li;
  }

  function renderBacklogInto(container) {
    var bl = backlog().filter(function (b) { return !b.activated; });
    if (!bl.length) { container.appendChild(el('div', 'empty', 'Backlog is empty.')); return; }
    bl.forEach(function (b) {
      var row = el('div', 'item-row state-committed');
      row.appendChild(el('span', 'item-ic', '◷'));
      var body = el('div', 'item-main');
      body.appendChild(el('div', 'item-text', b.text || '(untitled)'));
      if (b.context_text) body.appendChild(el('div', 'item-ctx', b.context_text));
      var meta = el('div', 'item-meta');
      meta.appendChild(el('span', 'st-badge st-committed', 'backlog · ' + (b.priority || '—')));
      body.appendChild(meta);
      row.appendChild(body);
      container.appendChild(row);
    });
  }

  function sessionRow(s) {
    var row = el('div', 'item-row state-blocked');
    row.appendChild(el('span', 'item-ic', '⚠️'));
    var body = el('div', 'item-main');
    body.appendChild(el('div', 'item-text', s.title || s.node_id));
    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'st-badge st-blocked', 'open session'));
    meta.appendChild(el('span', 'st-badge st-committed',
      'in ' + projectTitle(byId(rootProjectOf(s.node_id)) || { title: '—' })));
    if (s.opened_at) meta.appendChild(el('span', 'st-badge st-proposed',
      'opened ' + new Date(s.opened_at).toLocaleDateString()));
    body.appendChild(meta);
    row.appendChild(body);
    return row;
  }
  function renderOrphansInto(container) {
    var ss = staleSessions();
    if (!ss.length) { container.appendChild(el('div', 'empty',
      'No orphaned sessions — every session has concluded. ✓')); return; }
    container.appendChild(el('div', 'list-group-head',
      'Open sessions never concluded (' + ss.length + ')'));
    ss.forEach(function (s) { container.appendChild(sessionRow(s)); });
  }

  // ====================================================================
  //  TREE PANE — four-tier hierarchy
  // ====================================================================
  function projects() {
    return nodes().filter(isProject).filter(function (n) {
      return showArchived.checked || n.state !== 'archived';
    });
  }
  // Per-project rollup: counts of awaiting / in-flight across the project's
  // (non-session) descendant items, for the header badge.
  function projectRollup(projId) {
    var refs = projectItems(projId);
    var awaiting = refs.filter(function (r) { return isWaiting(r.item); }).length;
    var inflight = refs.filter(function (r) { return itemState(r.item) === 'in-flight'; }).length;
    var blocked = refs.filter(function (r) { return itemState(r.item) === 'blocked'; }).length;
    return { awaiting: awaiting, inflight: inflight, blocked: blocked, total: refs.length };
  }
  // Every non-session descendant item of a project (items on the project node
  // plus items on any workstream/sub nodes under it).
  function projectItems(projId) {
    var out = collectWorkItems(projId);
    collectWorkstreams(projId).forEach(function (ws) {
      out = out.concat(collectWorkItems(ws.node_id));
      childrenOf(ws.node_id).filter(function (c) { return !isSession(c); }).forEach(function (sub) {
        out = out.concat(collectWorkItems(sub.node_id));
      });
    });
    return out;
  }

  // renderTree — project-level renderer (wire-check entry point).
  function renderTree() {
    clear(treeCanvas);
    var projs = projects();
    if (!projs.length) {
      treeState.hidden = false;
      treeState.textContent = loaded ? 'No projects yet.' : 'Loading…';
      return;
    }
    treeState.hidden = true;
    // pick the focus project (most-recently-clicked, else the one with the most
    // awaiting items) if none is recorded
    if (!focusProject || !byId(focusProject)) {
      var best = null, bestN = -1;
      projs.forEach(function (p) {
        var r = projectRollup(p.node_id);
        if (r.awaiting > bestN) { bestN = r.awaiting; best = p.node_id; }
      });
      focusProject = best || projs[0].node_id;
    }
    var totAwait = 0, totFlight = 0;
    projs.forEach(function (p) {
      var roll = projectRollup(p.node_id);
      totAwait += roll.awaiting; totFlight += roll.inflight;
      var expanded = (p.node_id === focusProject) && !collapsed.has(p.node_id);
      treeCanvas.appendChild(renderProject(p, roll, expanded));
    });
    treeSummary.textContent = totAwait + ' awaiting · ' + totFlight + ' in flight';
    renderOrphanSection();
  }

  function renderProject(p, roll, expanded) {
    var wrap = el('div', 'proj' + (expanded ? ' exp' : ''));
    var head = el('div', 'proj-head');
    head.appendChild(el('span', 'twisty', expanded ? '▼' : '▶'));
    head.appendChild(el('span', 'proj-title', projectTitle(p)));
    var badge = el('span', 'proj-badge');
    if (roll.awaiting) badge.appendChild(el('span', 'b-await', roll.awaiting + ' awaiting'));
    if (roll.inflight) badge.appendChild(el('span', 'b-flight', roll.inflight + ' in-flight'));
    if (roll.blocked) badge.appendChild(el('span', 'b-block', roll.blocked + ' blocked'));
    if (!roll.total) badge.appendChild(el('span', 'b-none', 'nothing in flight'));
    head.appendChild(badge);
    head.addEventListener('click', function () { toggleProject(p.node_id); });
    wrap.appendChild(head);
    if (expanded) {
      var body = el('div', 'proj-body');
      // direct work items under the project (non-complete by default)
      var directs = collectWorkItems(p.node_id).filter(visibleInTree);
      directs.forEach(function (r) { body.appendChild(treeItemRow(r, 1)); });
      // workstream-tier nodes (lights up after Phase-3 backfill)
      collectWorkstreams(p.node_id).forEach(function (ws) {
        body.appendChild(renderWorkstream(ws));
      });
      if (!directs.length && !collectWorkstreams(p.node_id).length) {
        body.appendChild(el('div', 'proj-empty', 'Nothing in flight'));
      }
      wrap.appendChild(body);
    }
    return wrap;
  }

  // renderWorkstream — per-workstream rollup + its work items (wire-check target).
  function renderWorkstream(wsNode) {
    var wrap = el('div', 'ws');
    var head = el('div', 'ws-head');
    head.appendChild(el('span', 'ws-title', wsNode.title || wsNode.node_id));
    var allShipped = collectWorkItems(wsNode.node_id).every(function (r) { return isComplete(r.item); });
    head.appendChild(el('span', 'ws-state st-' + (allShipped ? 'shipped' : 'active'),
      allShipped ? 'shipped' : 'active'));
    wrap.appendChild(head);
    var body = el('div', 'ws-body');
    collectWorkItems(wsNode.node_id).filter(visibleInTree).forEach(function (r) {
      body.appendChild(treeItemRow(r, 2));
    });
    // sub-tasks (children of the workstream that are not sessions)
    childrenOf(wsNode.node_id).filter(function (c) { return !isSession(c); }).forEach(function (sub) {
      collectWorkItems(sub.node_id).filter(visibleInTree).forEach(function (r) {
        body.appendChild(treeItemRow(r, 3));
      });
    });
    wrap.appendChild(body);
    return wrap;
  }

  // non-complete-by-default: hide shipped/closed in the tree unless "show
  // archived" is on (the tree's complete-work escape hatch for this phase).
  function visibleInTree(r) {
    return showArchived.checked || !isComplete(r.item);
  }

  function treeItemRow(r, depth) {
    var st = itemState(r.item);
    var li = el('div', 'tree-item d' + depth + ' state-' + st);
    if (selItem && selItem.nodeId === r.nodeId && selItem.itemId === r.itemId) li.classList.add('sel');
    li.appendChild(el('span', 'ti-ic', stateIcon(st)));
    li.appendChild(el('span', 'ti-kind', kindGlyph(r.item.kind)));
    li.appendChild(el('span', 'ti-text', r.item.text || '(untitled)'));
    li.addEventListener('click', function () { renderDetailCard(r.nodeId, r.itemId); });
    return li;
  }

  function toggleProject(projId) {
    if (focusProject === projId && !collapsed.has(projId)) {
      collapsed.add(projId);                      // collapse the focused project
    } else {
      collapsed.delete(projId);
      focusProject = projId;                      // focus + expand
      localStorage.setItem('workstreams.focusProject', projId);
    }
    saveSet('workstreams.collapsed', collapsed);
    renderTree();
  }

  function renderOrphanSection() {
    var ss = staleSessions();
    if (!ss.length) { orphanSection.hidden = true; return; }
    orphanSection.hidden = false;
    orphanCount.textContent = ss.length;
    clear(orphanBody);
    ss.slice(0, 20).forEach(function (s) {
      var row = el('div', 'orphan-row');
      row.appendChild(el('span', 'orphan-ic', '⚠️'));
      row.appendChild(el('span', 'orphan-text',
        projectTitle(byId(rootProjectOf(s.node_id)) || { title: '—' }) + ' — ' + (s.title || s.node_id)));
      orphanBody.appendChild(row);
    });
    if (ss.length > 20) orphanBody.appendChild(el('div', 'proj-empty', '+ ' + (ss.length - 20) + ' more'));
  }

  // ====================================================================
  //  DETAIL CARD
  // ====================================================================
  // collectProvenance — session events that touched this item. The GUI has the
  // snapshot only (no event log), so provenance is best-effort: the containing
  // node, its bound sessions, and any sibling session nodes under the same
  // project that declare serves_item_id === this item (the Phase-1
  // session→work-item link).
  function collectProvenance(nodeId, itemId) {
    var prov = [];
    var host = byId(nodeId);
    if (host) {
      prov.push({ label: 'on node', value: host.title || host.node_id });
      (host.bound_sessions || []).forEach(function (sid) {
        prov.push({ label: 'bound session', value: sid });
      });
    }
    var projId = rootProjectOf(nodeId);
    childrenOf(projId).filter(isSession).forEach(function (s) {
      if (s.serves_item_id === itemId) {
        prov.push({ label: 'serving session', value: s.title || s.node_id });
      }
    });
    return prov;
  }
  // collectSubtasks — children whose parent_id === the item's node, i.e.
  // sub-task branches. Items aren't nodes, so this walks snapshot.nodes for
  // non-session children of the containing node (returns [] for today's data).
  function collectSubtasks(nodeId, itemId) {
    var subs = [];
    childrenOf(nodeId).filter(function (c) { return !isSession(c); }).forEach(function (c) {
      (c.items || []).forEach(function (it) {
        subs.push({ text: it.text, checked: !!it.checked, state: itemState(it) });
      });
    });
    return subs;
  }

  // renderDetailCard — selection handler (wire-check target). Replaces the
  // filtered list with the card; deselect (✕ / Esc) restores the list.
  function renderDetailCard(nodeId, itemId) {
    var host = byId(nodeId);
    var it = host && (host.items || []).find(function (x) { return x.item_id === itemId; });
    if (!it) { setActiveFilter(activeFilter); return; }
    selItem = { nodeId: nodeId, itemId: itemId };
    var st = itemState(it);
    filterBody.hidden = true;
    detailCard.hidden = false;
    clear(detailCard);

    var head = el('div', 'dc-head');
    head.appendChild(el('span', 'dc-title', it.text || '(untitled)'));
    var close = el('button', 'ghost dc-close', '✕');
    close.title = 'back to list (Esc)';
    close.addEventListener('click', function () { setActiveFilter(activeFilter); });
    head.appendChild(close);
    detailCard.appendChild(head);

    var meta = el('div', 'dc-meta');
    meta.appendChild(dcRow('Project', projectTitle(byId(rootProjectOf(nodeId)) || { title: nodeId })));
    var tier = (host && host.tier) ? host.tier : inferTier(nodeId);
    meta.appendChild(dcRow('Kind', it.kind));
    meta.appendChild(dcRow('Tier', tier));
    meta.appendChild(dcRow('State', stateIcon(st) + ' ' + st));
    if (it.ship_evidence) meta.appendChild(dcRow('Evidence', it.ship_evidence));
    if (it.block_reason) meta.appendChild(dcRow('Blocked', it.block_reason));
    if (host && host.opened_at) meta.appendChild(dcRow('Last activity', new Date(host.opened_at).toLocaleString()));
    detailCard.appendChild(meta);

    // provenance
    var prov = collectProvenance(nodeId, itemId);
    if (prov.length) {
      detailCard.appendChild(el('div', 'dc-sec-h', 'Provenance'));
      var pl = el('div', 'dc-prov');
      prov.forEach(function (p) {
        var pr = el('div', 'dc-prov-row');
        pr.appendChild(el('span', 'dc-prov-l', p.label));
        pr.appendChild(el('span', 'dc-prov-v', p.value));
        pl.appendChild(pr);
      });
      detailCard.appendChild(pl);
    }

    // sub-task rollup
    var subs = collectSubtasks(nodeId, itemId);
    if (subs.length) {
      detailCard.appendChild(el('div', 'dc-sec-h', 'Sub-tasks (' + subs.length + ')'));
      var sl = el('div', 'dc-subs');
      subs.forEach(function (s) {
        var sr = el('div', 'dc-sub-row');
        sr.appendChild(el('span', 'dc-sub-ck', s.checked ? '✓' : '⏳'));
        sr.appendChild(el('span', 'dc-sub-t', s.text));
        sl.appendChild(sr);
      });
      detailCard.appendChild(sl);
    }

    // actions — Mark shipped / Block / Decompose / Reassign. Mark shipped &
    // Block are wired to the Phase-1 events; Decompose/Reassign are Phase-3/4
    // surfaces (disabled placeholders) so the affordance is visible now.
    var acts = el('div', 'dc-acts');
    var ship = el('button', 'btn-go', 'Mark shipped');
    ship.addEventListener('click', function () {
      post({ type: 'item-shipped', node_id: nodeId, item_id: itemId }, 'Marked shipped')
        .then(function () { selItem = null; });
    });
    acts.appendChild(ship);
    var block = el('button', 'btn-warn outline', 'Block');
    block.addEventListener('click', function () {
      var reason = window.prompt('Why is this blocked?', '');
      if (reason == null) return;
      post({ type: 'item-blocked', node_id: nodeId, item_id: itemId, reason: reason }, 'Marked blocked');
    });
    acts.appendChild(block);
    var commit = el('button', 'btn-info outline', 'Commit');
    commit.title = 'park as committed work (not started yet)';
    commit.addEventListener('click', function () {
      post({ type: 'item-committed', node_id: nodeId, item_id: itemId }, 'Committed');
    });
    acts.appendChild(commit);
    var decompose = el('button', 'btn-neutral outline', 'Decompose');
    decompose.disabled = true; decompose.title = 'Phase 3+ — break into sub-tasks';
    acts.appendChild(decompose);
    var reassign = el('button', 'btn-neutral outline', 'Reassign');
    reassign.disabled = true; reassign.title = 'Phase 3+ — re-parent to another workstream';
    acts.appendChild(reassign);
    detailCard.appendChild(acts);
  }
  function dcRow(label, val) {
    var r = el('div', 'dc-row');
    r.appendChild(el('span', 'dc-l', label));
    r.appendChild(el('span', 'dc-v', val == null ? '—' : String(val)));
    return r;
  }
  function inferTier(nodeId) {
    var n = byId(nodeId);
    if (!n) return 'work-item';
    if (n.parent_id == null) return 'project';
    var depth = 0, cur = n, guard = 0;
    while (cur && cur.parent_id != null && guard++ < 50) { depth++; cur = byId(cur.parent_id); }
    return depth === 1 ? 'workstream' : depth === 2 ? 'work-item' : 'sub-task';
  }

  // ====================================================================
  //  RENDER ORCHESTRATION
  // ====================================================================
  function renderCorrupt() {
    var corrupt = S && S.valid === false;
    if (corrupt) {
      corruptBanner.hidden = false;
      corruptBanner.textContent = '⚠ State file appears torn — showing last-good content. '
        + 'The reducer is replaying the event log to recover.';
    } else {
      corruptBanner.hidden = true;
    }
    return corrupt;
  }
  function render() {
    renderCorrupt();
    renderTree();
    if (selItem) {
      renderDetailCard(selItem.nodeId, selItem.itemId);
    } else if (activeFilter === 'backlog') {
      renderFilteredItems('backlog');
    } else {
      renderFilteredItems(activeFilter);
    }
    updateChipCounts();
  }

  // ---- wiring ----------------------------------------------------------
  filterBar.addEventListener('click', function (e) {
    var chip = e.target.closest('.chip');
    if (chip) setActiveFilter(chip.getAttribute('data-filter'));
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && selItem) { setActiveFilter(activeFilter); }
  });
  showArchived.addEventListener('change', function () { render(); });

  // backlog capture
  addBacklogBtn.addEventListener('click', function () {
    backlogCapture.hidden = !backlogCapture.hidden;
    if (!backlogCapture.hidden) blText.focus();
  });
  blCancel.addEventListener('click', function () { backlogCapture.hidden = true; });
  blSave.addEventListener('click', function () {
    var text = (blText.value || '').trim();
    if (!text) { showToast('Enter the work item text first.', 'err'); return; }
    post({
      type: 'backlog-added', item_id: uid('bl'), tree_id: 'global',
      priority: blPriority.value, text: text, context_text: (blContext.value || '').trim(),
    }, 'Captured to backlog').then(function () {
      blText.value = ''; blContext.value = ''; backlogCapture.hidden = true;
      setActiveFilter('backlog');
    });
  });

  // ---- adjustable divider (persists workstreams.paneSplit) -------------
  (function dividerSetup() {
    var saved = parseFloat(localStorage.getItem('workstreams.paneSplit'));
    if (!isNaN(saved) && saved > 15 && saved < 85) setSplit(saved);
    var dragging = false;
    function setSplit(pct) {
      layout.style.setProperty('--tree-w', pct + '%');
    }
    function pctFromEvent(clientX) {
      var rect = layout.getBoundingClientRect();
      return Math.max(18, Math.min(80, ((clientX - rect.left) / rect.width) * 100));
    }
    divider.addEventListener('mousedown', function () { dragging = true; document.body.style.userSelect = 'none'; });
    window.addEventListener('mousemove', function (e) {
      if (!dragging) return;
      var pct = pctFromEvent(e.clientX);
      setSplit(pct);
    });
    window.addEventListener('mouseup', function () {
      if (!dragging) return;
      dragging = false; document.body.style.userSelect = '';
      var cur = layout.style.getPropertyValue('--tree-w');
      if (cur) localStorage.setItem('workstreams.paneSplit', parseFloat(cur));
    });
    divider.addEventListener('keydown', function (e) {
      var cur = parseFloat(layout.style.getPropertyValue('--tree-w')) || 42;
      if (e.key === 'ArrowLeft') { cur = Math.max(18, cur - 2); }
      else if (e.key === 'ArrowRight') { cur = Math.min(80, cur + 2); }
      else return;
      setSplit(cur); localStorage.setItem('workstreams.paneSplit', cur); e.preventDefault();
    });
  })();

  // ---- SSE connection (read half of the file contract) -----------------
  function connect() {
    var es = new EventSource('/api/events');
    es.addEventListener('state', function (e) {
      try { S = JSON.parse(e.data); } catch (err) { return; }
      loaded = true;
      statusEl.textContent = 'live'; statusEl.classList.add('live');
      render();
    });
    es.onerror = function () {
      statusEl.textContent = 'reconnecting…'; statusEl.classList.remove('live');
    };
  }

  // ---- freshness badge -------------------------------------------------
  function fmtAge(sec) {
    if (sec == null) return '—';
    if (sec < 60) return sec + 's';
    if (sec < 3600) return Math.round(sec / 60) + 'm';
    if (sec < 86400) return Math.round(sec / 3600) + 'h';
    return Math.round(sec / 86400) + 'd';
  }
  function pollHealth() {
    if (!freshnessEl) return;
    fetch('/api/health', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (h) {
      if (!h || !h.ok) { freshnessEl.textContent = 'health?'; freshnessEl.className = 'freshness stale'; return; }
      freshnessEl.textContent = 'state ' + fmtAge(h.state_age_seconds) + ' • hb ' + fmtAge(h.heartbeat_age_seconds);
      freshnessEl.className = 'freshness' + (h.heartbeat_stale ? ' stale' : '');
    }).catch(function () {
      freshnessEl.textContent = 'health err'; freshnessEl.className = 'freshness stale';
    });
  }
  setInterval(pollHealth, 30000);
  pollHealth();

  // initial chip-active paint, then connect
  updateChipCounts();
  connect();
})();
