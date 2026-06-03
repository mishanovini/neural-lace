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
  var showArchived = $('showArchived'), showCompleted = $('showCompleted'),
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
  // Phase 4 — configurable windows (localStorage override, same pattern as
  // activeFilter/focusProject above). Defaults preserve prior behavior:
  //   localStorage 'workstreams.orphanHours'     (default 24) — stale-session threshold
  //   localStorage 'workstreams.shipRecentDays'  (default 7)  — "Recently shipped" window
  var ORPHAN_HOURS = Number(localStorage.getItem('workstreams.orphanHours')) || 24;
  var SHIP_RECENT_DAYS = Number(localStorage.getItem('workstreams.shipRecentDays')) || 7;

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
  // Internal sub-agent sessions (auto-titled "subagent <hash>", node_id sub-*)
  // are AI-internal mechanics — peer reviewers, verifiers, parallel builders.
  // Per ADR-034 they are NOT branches of the user↔AI conversation and must NOT
  // be surfaced to the operator as orphans needing reconciliation (bug #3).
  function isInternalSubagent(n) {
    return n && /^subagent\s+[0-9a-f]{6,}/i.test(String(n.title || ''));
  }
  function staleSessions() {
    return nodes().filter(function (n) {
      if (!isSession(n)) return false;
      if (isInternalSubagent(n)) return false;    // bug #3: drop AI-internal subagent noise
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
    syncTreeSelection();                          // bug #5: clear tree highlight
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
      var workstreams = collectWorkstreams(p.node_id);
      // Real Workstream-tier nodes (Phase-3 backfill) render first as their own
      // tier — Project → Workstream → WorkItem → Sub-task.
      workstreams.forEach(function (ws) { body.appendChild(renderWorkstream(ws)); });
      // Direct project items (today's data has no Workstream tier — every item
      // hangs off the project root). Rendering them as a flat list of d1 rows is
      // the FLAT-LIST bug (2026-06-02): all items land at one indent, reading as
      // an undifferentiated dump. Instead derive a real intermediate tier from
      // `kind` (Decisions / Questions / Actions) and nest items inside guide-rail
      // containers, so the degraded (workstream-less) view still reads as a
      // hierarchy: Project → Kind group → WorkItem.
      var directs = collectWorkItems(p.node_id).filter(visibleInTree);
      if (directs.length) renderKindGroups(body, directs);
      if (!directs.length && !workstreams.length) {
        body.appendChild(el('div', 'proj-empty', 'Nothing in flight'));
      }
      wrap.appendChild(body);
    }
    return wrap;
  }

  // ---- intermediate tier: group flat project items by kind ----------------
  // Kind is the only structural grouping today's data carries, so it is the
  // honest source for the middle tier until real Workstream nodes exist. Each
  // group renders a header (depth 1) followed by a .tree-kids guide-rail
  // container holding the items (depth 2) — the nesting container is what makes
  // the items sit at a measurably distinct, clearly-indented x (regression:
  // tier-nesting). Known kinds keep a stable order; unknown kinds sort last.
  var KIND_ORDER = ['decision', 'question', 'action'];
  var KIND_HEAD = { decision: 'Decisions', question: 'Questions', action: 'Actions' };
  function renderKindGroups(parentEl, refs) {
    var byKind = {};
    refs.forEach(function (r) {
      var k = r.item.kind || 'action';
      (byKind[k] = byKind[k] || []).push(r);
    });
    var kinds = KIND_ORDER.filter(function (k) { return byKind[k]; }).concat(
      Object.keys(byKind).filter(function (k) { return KIND_ORDER.indexOf(k) === -1; }).sort());
    kinds.forEach(function (k) {
      var grp = byKind[k];
      var gh = el('div', 'tree-group k-' + k);
      gh.appendChild(el('span', 'tg-badge k-' + k, kindLabel(k)));
      gh.appendChild(el('span', 'tg-title', KIND_HEAD[k] || k));
      gh.appendChild(el('span', 'tg-count', String(grp.length)));
      parentEl.appendChild(gh);
      var kids = el('div', 'tree-kids');
      grp.forEach(function (r) { kids.appendChild(treeItemRow(r, 2)); });
      parentEl.appendChild(kids);
    });
  }

  // renderWorkstream — per-workstream rollup + its work items (wire-check target).
  // Items + sub-tasks nest inside .tree-kids guide-rail containers (compounding
  // indent per depth) so Workstream → WorkItem → Sub-task each sit at a distinct x.
  function renderWorkstream(wsNode) {
    var wrap = el('div', 'ws');
    var head = el('div', 'ws-head');
    head.appendChild(el('span', 'ws-title', wsNode.title || wsNode.node_id));
    var allShipped = collectWorkItems(wsNode.node_id).every(function (r) { return isComplete(r.item); });
    head.appendChild(el('span', 'ws-state st-' + (allShipped ? 'shipped' : 'active'),
      allShipped ? 'shipped' : 'active'));
    wrap.appendChild(head);
    var kids = el('div', 'tree-kids');
    collectWorkItems(wsNode.node_id).filter(visibleInTree).forEach(function (r) {
      kids.appendChild(treeItemRow(r, 2));
    });
    // sub-tasks (children of the workstream that are not sessions) nest one
    // level deeper, under their own sub-header + nested guide-rail container.
    childrenOf(wsNode.node_id).filter(function (c) { return !isSession(c); }).forEach(function (sub) {
      var subItems = collectWorkItems(sub.node_id).filter(visibleInTree);
      if (!subItems.length) return;
      var subHead = el('div', 'tree-group tree-subhead');
      subHead.appendChild(el('span', 'tg-title', sub.title || sub.node_id));
      kids.appendChild(subHead);
      var subKids = el('div', 'tree-kids');
      subItems.forEach(function (r) { subKids.appendChild(treeItemRow(r, 3)); });
      kids.appendChild(subKids);
    });
    wrap.appendChild(kids);
    return wrap;
  }

  // non-complete-by-default: hide shipped/closed in the tree unless "show
  // archived" is on (the tree's complete-work escape hatch for this phase).
  function visibleInTree(r) {
    // Completed (shipped/closed) items hide in the tree unless EITHER the
    // "show completed" toggle (bug #7) OR "show archived" is on.
    return showArchived.checked || (showCompleted && showCompleted.checked) || !isComplete(r.item);
  }

  // Short uppercase kind label for the colored tree badge (bug #4). Falls back
  // to the raw kind for any future kind value.
  var KIND_LABEL = { decision: 'DEC', question: 'ASK', action: 'ACT' };
  function kindLabel(k) { return KIND_LABEL[k] || String(k || '').slice(0, 3).toUpperCase() || '•'; }

  function treeItemRow(r, depth) {
    var st = itemState(r.item);
    // Indent is supplied by the enclosing .tree-kids guide-rail container (not a
    // per-depth margin class), so a workstream-less project still nests cleanly.
    // data-depth is retained for the geometry regression + any depth styling.
    var li = el('div', 'tree-item state-' + st);
    li.setAttribute('data-depth', String(depth));
    li.setAttribute('data-node', r.nodeId);
    li.setAttribute('data-item', r.itemId);
    if (selItem && selItem.nodeId === r.nodeId && selItem.itemId === r.itemId) li.classList.add('sel');
    li.appendChild(el('span', 'ti-ic', stateIcon(st)));
    // colored kind badge (decision / question / action) — parity with the
    // right-pane .k-* chips so the type is scannable in the tree (bug #4).
    var badge = el('span', 'ti-badge k-' + (r.item.kind || 'action'), kindLabel(r.item.kind));
    badge.title = r.item.kind || '';
    li.appendChild(badge);
    li.appendChild(el('span', 'ti-text', r.item.text || '(untitled)'));
    li.addEventListener('click', function () { renderDetailCard(r.nodeId, r.itemId); });
    return li;
  }

  // syncTreeSelection — toggle the .sel highlight on existing tree rows to match
  // selItem WITHOUT a full re-render (bug #5: clicking an item — from the tree
  // OR the right-pane list — now highlights the matching tree row).
  function syncTreeSelection() {
    Array.prototype.forEach.call(treeCanvas.querySelectorAll('.tree-item'), function (li) {
      var on = selItem
        && li.getAttribute('data-node') === selItem.nodeId
        && li.getAttribute('data-item') === selItem.itemId;
      li.classList.toggle('sel', !!on);
    });
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

  // ============================================================================
  // PORTED 2026-06-02 from the pre-rename conv-tree-ui renderer (ee16f41:
  // neural-lace/conversation-tree-ui/web/app.js). Personal evolved the old
  // renderer with decision-context fence-grammar rendering; PT rewrote app.js
  // four-tier from scratch and did not carry it. This block restores the
  // decision-context detail rendering inside the four-tier detail card.
  // linkifyDocs is a self-contained LITE version (renders docs/… as styled
  // chips; the four-tier renderer has no docs-modal subsystem, so they are
  // informational rather than click-to-open — content preserved, no missing
  // dependency). The (see branch: …) jump degrades to a toast (the four-tier
  // renderer has no focusNode tree-canvas navigation).
  // ============================================================================
  function linkifyDocs(container, text, projectKey) {
    var s = String(text == null ? '' : text);
    var re = /docs\/[A-Za-z0-9._\/-]+/g, last = 0, m;
    while ((m = re.exec(s)) !== null) {
      if (m.index > last) container.appendChild(document.createTextNode(s.slice(last, m.index)));
      var chip = el('span', 'det-link det-link-doc', m[0]);
      chip.title = 'repo path' + (projectKey ? ' (project: ' + projectKey + ')' : '');
      container.appendChild(chip);
      last = m.index + m[0].length;
    }
    if (last < s.length) container.appendChild(document.createTextNode(s.slice(last)));
  }
  function detailRow(label, val, projectKey) {
    if (val == null || val === '') return null;
    var d = el('div', 'det-row');
    d.appendChild(el('span', 'det-k', label));
    var v = el('div', 'det-v');
    linkifyDocs(v, String(val), projectKey);   // item 19: docs/… → clickable
    d.appendChild(v);
    return d;
  }

  function renderItemDetails(de, projectKey, itemText) {
    var box = el('div', 'li-details');
    if (!de || typeof de !== 'object') return box;
    var add = function (node) { if (node) box.appendChild(node); };

    // --- contract item 2: redundancy detection -------------------------------
    var descRedundant = (
      itemText != null && de.description != null
      && String(de.description).trim() === String(itemText).trim()
    );

    // --- contract item 5: incomplete-metadata signal -------------------------
    var hasActionable = !!(
      de.instructions || de.recommendation || de.blocking_input
      || (Array.isArray(de.options) && de.options.length)
    );
    var descIsSubstantive = (
      de.description != null && !descRedundant
      && String(de.description).trim().length > 20
    );
    var incomplete = !hasActionable && !descIsSubstantive;

    // --- contract item 4: graceful fallback ----------------------------------
    if (incomplete) {
      var fb = el('div', 'det-fallback');
      var fbLine = el('div', 'muted',
        'No detailed instructions recorded — see linked branch / Dispatch doc for context.');
      fb.appendChild(fbLine);
      var fbBadge = el('span', 'det-incomplete-badge', 'incomplete metadata');
      fbBadge.title = 'This item lacks actionable instructions/options/recommendation. '
        + 'Re-run backfill-details.js with --enrich or paste fuller detail when raising the item.';
      fb.appendChild(fbBadge);
      box.appendChild(fb);
    }

    // --- decision-context fence-grammar header (Task 9-full / OQ-2) -----------
    // When the item carries the decision-context `_category` marker (stamped
    // by decision-context-gate / replay), surface the urgency chip + category
    // hint above the legacy actionable rows so the operator immediately sees
    // what's being asked of them. Legacy items (no `_category`) skip this.
    var dcCat = de._category;
    if (dcCat) {
      var hdr = el('div', 'det-row det-dc-header');
      var lbl = el('span', 'det-k', 'Kind');
      var hv = el('div', 'det-v');
      var kindChip = el('span', 'det-chip det-chip-cat det-chip-cat-' + String(dcCat),
        String(dcCat).replace(/_/g, ' '));
      hv.appendChild(kindChip);
      if (de.urgency) {
        var ug = el('span', 'det-chip det-chip-urgency det-chip-urgency-' + String(de.urgency),
          'urgency: ' + String(de.urgency));
        hv.appendChild(document.createTextNode(' '));
        hv.appendChild(ug);
      }
      hdr.appendChild(lbl); hdr.appendChild(hv); box.appendChild(hdr);
      // about / background — fence-grammar context fields, distinct from legacy
      // `description` / `context` rows below. Render only when present.
      add(detailRow('About', de.about, projectKey));
      add(detailRow('Background', de.background, projectKey));
    }

    // --- contract item 1: ACTIONABLE FIELDS FIRST ----------------------------
    add(detailRow('Instructions', de.instructions, projectKey));
    // Question-category fence fields (asked-of-the-user payload).
    if (dcCat === 'question') {
      add(detailRow('Question', de.question, projectKey));
      add(detailRow('Why asking', de.why_asking, projectKey));
      add(detailRow('What I’ve tried', de.what_ive_tried, projectKey));
      if (de.answer_shape) {
        var asRow = el('div', 'det-row');
        asRow.appendChild(el('span', 'det-k', 'Answer shape'));
        var asV = el('div', 'det-v');
        asV.appendChild(el('span', 'det-chip det-chip-answer-shape', String(de.answer_shape)));
        asRow.appendChild(asV); box.appendChild(asRow);
      }
    }
    // Decision-category fence fields (question + why_not_decide_alone above options).
    if (dcCat === 'decision') {
      add(detailRow('Question', de.question, projectKey));
      add(detailRow('Why not decide alone', de.why_not_decide_alone, projectKey));
    }
    // Action-item-for-user fence fields.
    if (dcCat === 'action_item_for_user') {
      add(detailRow('The ask', de.the_ask, projectKey));
      add(detailRow('Why assigned', de.why_assigned, projectKey));
      add(detailRow('What I’m doing meanwhile', de.what_im_doing_meanwhile, projectKey));
      if (de.state) {
        var stRow = el('div', 'det-row');
        stRow.appendChild(el('span', 'det-k', 'State'));
        var stV = el('div', 'det-v');
        stV.appendChild(el('span', 'det-chip det-chip-state det-chip-state-' + String(de.state),
          String(de.state)));
        stRow.appendChild(stV); box.appendChild(stRow);
      }
    }
    // Autonomous-action fence fields (fait-accompli notification).
    if (dcCat === 'autonomous_action') {
      add(detailRow('Action taken', de.action_taken, projectKey));
      add(detailRow('Reasoning', de.reasoning, projectKey));
      add(detailRow('Reversibility', de.reversibility, projectKey));
    }
    if (Array.isArray(de.options) && de.options.length) {
      var ow = el('div', 'det-row');
      ow.appendChild(el('span', 'det-k', 'Options'));
      var ol = el('div', 'det-v');
      de.options.forEach(function (op) {
        if (typeof op === 'string') { ol.appendChild(el('div', 'det-opt', op)); return; }
        var o = el('div', 'det-opt');
        // Legacy `label` OR new-schema `name` (+ optional `key` prefix).
        var optTitle = '';
        if (op.key) optTitle += '[' + op.key + '] ';
        optTitle += (op.name || op.label || '');
        o.appendChild(el('div', 'det-opt-l', optTitle));
        // Legacy pros/cons preserved.
        if (op.pros) o.appendChild(el('div', 'muted', '+ ' + op.pros));
        if (op.cons) o.appendChild(el('div', 'muted', '− ' + op.cons));
        // New-schema decision-option fields (rendered when present).
        if (op.what_it_does) o.appendChild(el('div', 'det-opt-field',
          'what it does: ' + op.what_it_does));
        if (op.risk) o.appendChild(el('div', 'det-opt-field', 'risk: ' + op.risk));
        if (op.reversibility_cost) {
          var rcWrap = el('div', 'det-opt-field');
          rcWrap.appendChild(document.createTextNode('reversibility: '));
          rcWrap.appendChild(el('span',
            'det-chip det-chip-revcost det-chip-revcost-' + String(op.reversibility_cost),
            String(op.reversibility_cost)));
          o.appendChild(rcWrap);
        }
        if (op.cost) o.appendChild(el('div', 'det-opt-field', 'cost: ' + op.cost));
        ol.appendChild(o);
      });
      ow.appendChild(ol); box.appendChild(ow);
    }
    // Recommendation: legacy is a plain string; fence-schema is an object with
    // option_key + reasoning. Render whichever shape arrives.
    if (de.recommendation != null) {
      if (typeof de.recommendation === 'string') {
        add(detailRow('Recommendation', de.recommendation, projectKey));
      } else if (typeof de.recommendation === 'object') {
        var rWrap = el('div', 'det-row');
        rWrap.appendChild(el('span', 'det-k', 'Recommendation'));
        var rV = el('div', 'det-v');
        if (de.recommendation.option_key) {
          var rk = el('div', 'det-rec-key', 'option: ' + de.recommendation.option_key);
          rV.appendChild(rk);
        }
        if (de.recommendation.reasoning) {
          var rr = el('div', 'det-rec-reasoning');
          rr.textContent = de.recommendation.reasoning;
          rV.appendChild(rr);
        }
        rWrap.appendChild(rV); box.appendChild(rWrap);
      }
    }
    // reply_with: how to phrase the chosen response (decision category).
    if (de.reply_with) {
      var rwRow = el('div', 'det-row det-reply-with');
      rwRow.appendChild(el('span', 'det-k', 'Reply with'));
      var rwV = el('div', 'det-v');
      var rwBox = el('code', 'det-reply-with-box');
      rwBox.textContent = String(de.reply_with);
      rwV.appendChild(rwBox);
      rwRow.appendChild(rwV); box.appendChild(rwRow);
    }
    add(detailRow('Blocking input needed', de.blocking_input, projectKey));
    // Envelope fields shared across categories (after the actionable payload).
    add(detailRow('Default if no response', de.default_if_no_response, projectKey));
    add(detailRow('Expires at', de.expires_at, projectKey));
    add(detailRow('Warn at', de.warn_at, projectKey));
    // references: autonomous_action carries a required ≥1 entry list; other
    // categories may carry it as supplementary cross-links.
    if (Array.isArray(de.references) && de.references.length) {
      var refRow = el('div', 'det-row');
      refRow.appendChild(el('span', 'det-k', 'References'));
      var refV = el('div', 'det-v');
      de.references.forEach(function (r) {
        var rs = String(r);
        if (/docs\/[A-Za-z0-9._\/-]+/.test(rs)) {
          linkifyDocs(refV, rs, projectKey);
        } else {
          var rc = el('span', 'det-link', rs);
          refV.appendChild(rc);
        }
        refV.appendChild(document.createTextNode(' '));
      });
      refRow.appendChild(refV); box.appendChild(refRow);
    }

    // --- supporting detail (only when distinct from the item header) ---------
    if (!descRedundant) add(detailRow('Description', de.description, projectKey));
    add(detailRow('Context', de.context, projectKey));

    // --- contract item 3: links (last, but with branch-link parsing) ---------
    if (Array.isArray(de.links) && de.links.length) {
      var lw = el('div', 'det-row');
      lw.appendChild(el('span', 'det-k', 'Links'));
      var lv = el('div', 'det-v');
      de.links.forEach(function (lk) {
        var s = String(lk);
        // item 19 preserved: a docs/… link becomes a clickable .doc-link.
        if (/docs\/[A-Za-z0-9._\/-]+/.test(s)) {
          linkifyDocs(lv, s, projectKey);
        } else {
          // v1.1.4 item 40 NEW: parse `(see branch: TITLE)` → clickable jump.
          // Match the title against nodes() (substring match — the backfill
          // emits the full title verbatim, but be lenient about wrapping
          // parens / trailing punctuation).
          var bm = s.match(/see\s+branch:\s*(.+?)\s*\)?\s*$/i);
          if (bm) {
            var wanted = bm[1].trim();
            var match = nodes().find(function (n) {
              return n && n.title && String(n.title).trim() === wanted;
            });
            if (match) {
              var jb = el('button', 'det-link det-link-branch',
                '→ branch: ' + (match.title || match.node_id));
              jb.title = 'Referenced branch (jump unavailable in four-tier view)';
              jb.setAttribute('data-jump-node', match.node_id);
              jb.addEventListener('click', function () { showToast('Referenced branch: ' + (match.title || match.node_id), 'ok'); });
              lv.appendChild(jb);
              lv.appendChild(document.createTextNode(' '));
              return;
            }
          }
          // Fallback: plain chip (preserved from prior behavior).
          var c = el('span', 'det-link', s);
          c.title = 'repo path / reference';
          lv.appendChild(c);
        }
        lv.appendChild(document.createTextNode(' '));
      });
      lw.appendChild(lv); box.appendChild(lw);
    }
    return box;
  }

  // renderDetailCard — selection handler (wire-check target). Replaces the
  // filtered list with the card; deselect (✕ / Esc) restores the list.
  function renderDetailCard(nodeId, itemId) {
    var host = byId(nodeId);
    var it = host && (host.items || []).find(function (x) { return x.item_id === itemId; });
    if (!it) { setActiveFilter(activeFilter); return; }
    selItem = { nodeId: nodeId, itemId: itemId };
    syncTreeSelection();                          // bug #5: highlight matching tree row
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

    // decision-context fence detail — ported 2026-06-02 from the pre-rename
    // conv-tree-ui renderer (renderItemDetails). Shows the fence-grammar
    // payload (question / decision options / action-item / autonomous-action
    // action_taken+reasoning+reversibility, recommendation, references, …).
    if (it.details && typeof it.details === 'object') {
      detailCard.appendChild(el('div', 'dc-sec-h', 'Detail'));
      detailCard.appendChild(renderItemDetails(it.details, rootProjectOf(nodeId), it.text));
    }

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
  if (showCompleted) showCompleted.addEventListener('change', function () { render(); });

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

  // ====================================================================
  //  DOCS BROWSER (restored 2026-06-02 — bug #6). Cross-project folder tree
  //  reading /api/docs (flat per-project file list → nested project→folder→file
  //  tree) + an in-GUI markdown viewer (/api/doc) + open-in-OS-editor
  //  (/api/doc/open). Ported from the pre-rename renderer (ee16f41); the
  //  four-tier rewrite dropped the frontend while the endpoints + CSS survived.
  // ====================================================================
  (function docsBrowser() {
    var docsBtn = $('docsBtn'), docsPanel = $('docsPanel'), docsClose = $('docsClose'),
        docsFilter = $('docsFilter'), docsBody = $('docsBody'), docScrim = $('docScrim'),
        docModal = $('docModal'), docTitle = $('docTitle'), docBody = $('docBody'),
        docClose = $('docClose'), docOpenEditor = $('docOpenEditor');
    if (!docsBtn || !docsPanel) return;            // drawer not in this build

    var docsCache = null, curDoc = null;
    var DOCS_EXP_KEY = 'workstreams.docsExpanded';
    var docsExpanded = (function () {
      try { var r = JSON.parse(localStorage.getItem(DOCS_EXP_KEY) || '[]'); return Array.isArray(r) ? r : []; }
      catch (_) { return []; }
    })();
    function isExp(k) { return docsExpanded.indexOf(k) !== -1; }
    function toggleExp(k) {
      var i = docsExpanded.indexOf(k);
      if (i === -1) docsExpanded.push(k); else docsExpanded.splice(i, 1);
      try { localStorage.setItem(DOCS_EXP_KEY, JSON.stringify(docsExpanded)); } catch (_) {}
    }

    function openDocsPanel() {
      docsPanel.hidden = false; docScrim.hidden = false;
      if (docsCache) { renderDocsPanel(); return; }
      docsBody.innerHTML = '<p class="muted">Loading docs…</p>';
      fetch('/api/docs').then(function (r) { return r.json(); }).then(function (j) {
        docsCache = (j && j.projects) || {}; renderDocsPanel();
      }).catch(function () { docsBody.innerHTML = '<p class="muted">Server unreachable.</p>'; });
    }
    function closeDocsPanel() { docsPanel.hidden = true; if (docModal.hidden) docScrim.hidden = true; }

    function buildDocTree(files) {
      var root = { dirs: {}, files: [] };
      files.forEach(function (full) {
        var parts = String(full).split('/'), fname = parts.pop(), node = root;
        parts.forEach(function (seg) {
          if (!node.dirs[seg]) node.dirs[seg] = { dirs: {}, files: [] };
          node = node.dirs[seg];
        });
        node.files.push({ name: fname, full: full });
      });
      return root;
    }
    function countDocs(node) {
      var n = node.files.length;
      Object.keys(node.dirs).forEach(function (d) { n += countDocs(node.dirs[d]); });
      return n;
    }
    function renderDocNode(parent, node, projKey, pathPrefix, depth, expandAll) {
      Object.keys(node.dirs).sort().forEach(function (dname) {
        var child = node.dirs[dname];
        var folderPath = pathPrefix ? pathPrefix + '/' + dname : dname;
        var fkey = projKey + '' + folderPath;
        var open = expandAll || isExp(fkey);
        var row = el('div', 'dp-dir');
        row.style.paddingLeft = (0.6 + depth * 0.9) + 'rem';
        row.appendChild(el('span', 'twist', open ? '▾' : '▸'));
        row.appendChild(el('span', 'dp-name', dname));
        row.appendChild(el('span', 'dp-count', String(countDocs(child))));
        row.addEventListener('click', function () { toggleExp(fkey); renderDocsPanel(); });
        parent.appendChild(row);
        if (open) renderDocNode(parent, child, projKey, folderPath, depth + 1, expandAll);
      });
      node.files.forEach(function (file) {
        var fe = el('div', 'dp-file');
        fe.style.paddingLeft = (1.3 + depth * 0.9) + 'rem';
        fe.appendChild(el('span', 'dp-fileicon', '📄'));
        fe.appendChild(el('span', 'dp-name', file.name));
        fe.title = file.full;
        fe.addEventListener('click', function () { openDocModal(projKey, file.full); });
        parent.appendChild(fe);
      });
    }
    function renderDocsPanel() {
      var f = (docsFilter.value || '').trim().toLowerCase(), filterActive = f.length > 0;
      clear(docsBody);
      Object.keys(docsCache).sort().forEach(function (key) {
        var info = docsCache[key];
        var files = (info.files || []).filter(function (p) {
          return !filterActive || p.toLowerCase().indexOf(f) !== -1;
        });
        if (filterActive && files.length === 0) return;
        var projOpen = info.missing ? false : (filterActive ? true : isExp(key));
        var head = el('div', 'dp-proj');
        head.appendChild(el('span', 'twist', info.missing ? '⚠' : (projOpen ? '▾' : '▸')));
        head.appendChild(el('span', 'dp-name', key));
        head.appendChild(el('span', 'dp-count', info.missing ? 'root not found' : String(files.length)));
        if (!info.missing) head.addEventListener('click', function () { toggleExp(key); renderDocsPanel(); });
        docsBody.appendChild(head);
        if (info.missing) { docsBody.appendChild(el('div', 'dp-missing', info.root)); return; }
        if (!projOpen) return;
        if (files.length === 0) { docsBody.appendChild(el('div', 'dp-missing', '(no docs)')); return; }
        renderDocNode(docsBody, buildDocTree(files), key, '', 1, filterActive);
      });
      if (!docsBody.firstChild) docsBody.appendChild(el('p', 'muted', 'No docs match.'));
    }

    // --- in-GUI markdown viewer -------------------------------------------
    function inlineMd(s) {
      return esc(s)
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>')
        .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    }
    function mdRender(src) {
      var lines = String(src == null ? '' : src).split(/\r?\n/);
      var html = '', i = 0, inList = false, listTag = '';
      function closeList() { if (inList) { html += '</' + listTag + '>'; inList = false; listTag = ''; } }
      while (i < lines.length) {
        var ln = lines[i];
        if (/^```/.test(ln)) {
          closeList(); i++; var code = '';
          while (i < lines.length && !/^```/.test(lines[i])) { code += lines[i] + '\n'; i++; }
          i++; html += '<pre><code>' + esc(code) + '</code></pre>'; continue;
        }
        var h = ln.match(/^(#{1,6})\s+(.*)$/);
        if (h) { closeList(); html += '<h' + h[1].length + '>' + inlineMd(h[2]) + '</h' + h[1].length + '>'; i++; continue; }
        if (/^\s*([-*])\s+/.test(ln)) {
          if (!inList || listTag !== 'ul') { closeList(); html += '<ul>'; inList = true; listTag = 'ul'; }
          html += '<li>' + inlineMd(ln.replace(/^\s*[-*]\s+/, '')) + '</li>'; i++; continue;
        }
        if (/^\s*\d+\.\s+/.test(ln)) {
          if (!inList || listTag !== 'ol') { closeList(); html += '<ol>'; inList = true; listTag = 'ol'; }
          html += '<li>' + inlineMd(ln.replace(/^\s*\d+\.\s+/, '')) + '</li>'; i++; continue;
        }
        if (/^\s*(---+|\*\*\*+)\s*$/.test(ln)) { closeList(); html += '<hr>'; i++; continue; }
        if (/^\s*$/.test(ln)) { closeList(); i++; continue; }
        closeList(); html += '<p>' + inlineMd(ln) + '</p>'; i++;
      }
      closeList(); return html;
    }
    function openDocModal(project, relPath) {
      curDoc = { project: project, path: relPath };
      docTitle.textContent = project + ' › ' + relPath;
      docBody.innerHTML = '<p class="muted">Loading…</p>';
      docModal.hidden = false; docScrim.hidden = false;
      fetch('/api/doc?project=' + encodeURIComponent(project) + '&path=' + encodeURIComponent(relPath))
        .then(function (r) { return r.json(); })
        .then(function (j) {
          if (j && j.ok) docBody.innerHTML = mdRender(j.content);
          else docBody.innerHTML = '<p class="muted">Could not load this doc: ' + esc((j && j.error) || 'unknown') + '</p>';
        })
        .catch(function () { docBody.innerHTML = '<p class="muted">Server unreachable.</p>'; });
    }
    function closeDocModal() { docModal.hidden = true; curDoc = null; if (docsPanel.hidden) docScrim.hidden = true; }

    docsBtn.addEventListener('click', openDocsPanel);
    docsClose.addEventListener('click', closeDocsPanel);
    docsFilter.addEventListener('input', function () { if (docsCache) renderDocsPanel(); });
    if (docClose) docClose.addEventListener('click', closeDocModal);
    if (docOpenEditor) docOpenEditor.addEventListener('click', function () {
      if (!curDoc) return;
      fetch('/api/doc/open', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(curDoc) })
        .then(function (r) { return r.json(); })
        .then(function (j) { showToast(j && j.ok ? 'opened in editor' : ('open failed: ' + ((j && j.error) || '')), j && j.ok ? 'ok' : 'err'); })
        .catch(function () { showToast('open failed — server unreachable', 'err'); });
    });
    docScrim.addEventListener('click', function () { closeDocModal(); closeDocsPanel(); });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (!docModal.hidden) { closeDocModal(); return; }
      if (!docsPanel.hidden) closeDocsPanel();
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
