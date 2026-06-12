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
      filterState = $('filterState'),
      // Phase D — item detail is now a MODAL overlay (not a list-replacing card).
      detailScrim = $('detailScrim'), detailModal = $('detailModal'),
      dmTitle = $('dmTitle'), dmBody = $('dmBody'), dmActions = $('dmActions'),
      dmClose = $('dmClose'),
      layout = $('layout'), divider = $('divider'),
      addBacklogBtn = $('addBacklogBtn'), backlogCapture = $('backlogCapture'),
      blText = $('blText'), blContext = $('blContext'),
      blPriority = $('blPriority'), blSave = $('blSave'), blCancel = $('blCancel');

  // ---- client view state ----------------------------------------------
  var S = null;                 // latest snapshot { nodes, backlog, rejections, ... }
  var loaded = false;
  var activeFilter = localStorage.getItem('workstreams.activeFilter') || 'awaiting-me';
  // Status-surface redesign (Tasks 3/5, 2026-06-11): the left pane is a project
  // COCKPIT (one count-row per project) until the operator drills into ONE
  // project, whose tree then renders bounded to that project (C4: with a
  // persistent "← all projects" return path). drillProject persists so a
  // reload restores the operator's place.
  var drillProject = localStorage.getItem('workstreams.drillProject') || null;
  var collapsedRepos = loadSet('workstreams.collapsedRepos'); // repo groups the user collapsed
  // Per-branch disclosure state in the drilled tree. Keys are
  // '<projectId>::<branch-key>'; values 'exp' | 'col'. Branches with no entry
  // use the default: OPEN for active branches, COLLAPSED for all-done ones.
  var branchState = loadObj('workstreams.branchState');
  var selItem = null;           // { nodeId, itemId } currently in the detail card
  // Phase 4 — configurable windows (localStorage override, same pattern as
  // activeFilter/drillProject above). Defaults preserve prior behavior:
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
  function loadObj(key) {
    try {
      var o = JSON.parse(localStorage.getItem(key) || '{}');
      return (o && typeof o === 'object' && !Array.isArray(o)) ? o : {};
    } catch (_) { return {}; }
  }
  function saveObj(key, obj) {
    try { localStorage.setItem(key, JSON.stringify(obj)); } catch (_) {}
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
  function projectTitle(n) {
    // The `global` root is the cross-cutting container; "global" is cryptic on
    // an operator-facing cockpit row, so it gets a readable display name.
    if (n && n.node_id === 'global') return 'Cross-project';
    return n.title || n.node_id;
  }

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
  // C3 (2026-06-11): the reducer produces committed / in-flight / blocked /
  // shipped only — `closed`/`proposed` are unreachable and dropped from the
  // v1 spine. "Done" semantics = `shipped`.
  var COMPLETE_STATES = { shipped: 1 };
  function isComplete(it) { return !!COMPLETE_STATES[itemState(it)]; }
  // Open = the legacy "waiting" predicate: unchecked & not parked
  // (deferred/contested still count as open). Base predicate only — the
  // Awaiting-me chip uses isAwaitingMe below (residual 2, 2026-06-10).
  function isWaiting(it) {
    return ((!it.checked) || it.deferred || it.contested) && !it.backlogged && itemState(it) !== 'shipped';
  }
  // Residual 2 (2026-06-10): Awaiting-me / In-flight were non-discriminating —
  // every open unchecked item satisfied BOTH (isWaiting matched everything
  // open; itemState defaults to 'in-flight' for any unchecked item without an
  // explicit state), so the two chips showed the same count (209=209) and the
  // partition carried no signal. Fix: Awaiting-me = items that are GENUINELY
  // Misha-asks (a decision / question / action_item_for_user — the rich
  // details._category written by the fence grammar wins; otherwise the item
  // kind for decisions/questions, which are user-asks by construction), still
  // open and unanswered (an inline action-responded means it is back in the
  // agent's court). In-flight = open work-in-motion items NOT awaiting him
  // (plain actions without a user-ask category). The two are disjoint by
  // construction: in-flight requires !isAwaitingMe.
  var MISHA_ASK_CATEGORIES = { decision: 1, question: 1, action_item_for_user: 1 };
  function isMishaAsk(it) {
    var cat = it.details && it.details._category;
    if (cat) return !!MISHA_ASK_CATEGORIES[cat];
    return it.kind === 'decision' || it.kind === 'question';
  }
  function isAwaitingMe(it) {
    return isWaiting(it) && isMishaAsk(it) && !it.responded;
  }
  function isInFlightItem(it) {
    return itemState(it) === 'in-flight' && !isAwaitingMe(it);
  }
  // Status-surface redesign (Tasks 3/4/5, 2026-06-11). The WAITING tier per the
  // plan's spine: "blocked (incl. blocked-on-operator = waiting on you)" — i.e.
  // every unanswered Misha-ask PLUS every blocked item. A blocked item with a
  // declared `blocked_on` dependency edge is pipeline-blocked rather than
  // operator-blocked, but it is still STALLED — it stays in the waiting tier
  // (its row shows the block reason so the operator sees why). This single
  // predicate drives the cockpit "waiting" pill, the global waiting-on-you
  // list, AND the tree's amber needs-you discipline, so the three surfaces
  // always agree (C6: amber = needs-you/blocked ONLY).
  function isWaitingOnYou(it) {
    return isAwaitingMe(it) || itemState(it) === 'blocked';
  }
  // statusCounts — the cockpit's four lifecycle buckets (C3: derived from the
  // states the reducer ACTUALLY produces — committed / in-flight / blocked /
  // shipped; `proposed`/`closed` are produced by no reducer and are dropped
  // from the v1 spine). Buckets are DISJOINT and TOTAL over the given refs:
  //   done    = shipped
  //   waiting = isWaitingOnYou (unanswered Misha-asks + blocked)
  //   next    = committed (queued; incl. deferred/backlogged via itemState)
  //   now     = in-flight (moving)
  function statusCounts(refs) {
    var c = { now: 0, next: 0, waiting: 0, done: 0, total: refs.length };
    refs.forEach(function (r) {
      var st = itemState(r.item);
      if (st === 'shipped') c.done++;
      else if (isWaitingOnYou(r.item)) c.waiting++;
      else if (st === 'committed') c.next++;
      else c.now++;                              // in-flight (the open default)
    });
    return c;
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
  // Phase D — deploy-state derivation. An item is "deployed" once it.deployed is
  // true (set by item-deployed OR item-shipped{deployed:true}). "Shipped-not-
  // deployed" = the work merged/shipped but has NOT reached production — exactly
  // the set Misha wants surfaced ("every effort that doesn't get deployed").
  function isDeployed(it) { return it.deployed === true; }
  function isShippedNotDeployed(it) {
    return itemState(it) === 'shipped' && !isDeployed(it);
  }

  // ---- state-badge glyphs ---------------------------------------------
  var STATE_ICON = {
    committed: '◷', 'in-flight': '◐', blocked: '⏳', shipped: '✓',
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

  // ====================================================================
  //  MY TASKS (operator-authored) — Task 6 of the status-surface redesign
  // ====================================================================
  // The operator's hand-authored items live as first-class WorkItems
  // (origin === 'operator') in the SAME model the AI emits into, so they also
  // appear in cockpit counts and the relevant project tree. They are created
  // on a stable dedicated project root ("My tasks") via action-added with an
  // explicit origin:'operator'; edits reuse item-text-set; reorder reuses
  // reordered; removal uses the one new item-removed event.
  var MYTASKS_NODE = 'mytasks-operator';
  var MYTASKS_TITLE = 'My tasks';
  function isOperatorItem(it) { return it && it.origin === 'operator'; }
  // Every ACTIVE operator item across all projects, in the operator's chosen
  // order (snapshot.order keyed by the My-tasks node scope), with un-ordered
  // items appended in insertion order so a freshly-added task always shows.
  // Task 7: backlogged operator items are the SEPARATE "someday" bucket — they
  // render on the Backlog surface only, and ENTER this list via promote
  // ("Tasks = active; backlog = someday"). Without this exclusion, promote
  // would be meaningless (the item would already sit in My-tasks).
  function myTaskRefs() {
    var refs = allWorkItems().filter(function (r) {
      return isOperatorItem(r.item) && !r.item.backlogged;
    });
    var order = (S && S.order && Array.isArray(S.order[MYTASKS_NODE])) ? S.order[MYTASKS_NODE] : null;
    if (!order || !order.length) return refs;
    var pos = {};
    order.forEach(function (id, i) { pos[id] = i; });
    return refs.slice().sort(function (a, b) {
      var pa = (a.itemId in pos) ? pos[a.itemId] : (order.length + 1);
      var pb = (b.itemId in pos) ? pos[b.itemId] : (order.length + 1);
      return pa - pb;
    });
  }
  // Ensure the dedicated My-tasks project root exists; if not, create it, then
  // run the continuation once it's persisted. The operator never has to
  // "create a project" — the first add lazily materializes the home node.
  function ensureMyTasksNode(then) {
    if (byId(MYTASKS_NODE)) { then(); return; }
    post({ type: 'branch-opened', node_id: MYTASKS_NODE, parent_id: null, title: MYTASKS_TITLE })
      .then(function () { then(); })
      .catch(function () { showToast('Could not create the My-tasks list — try again.', 'err'); });
  }

  // ---- filter logic ----------------------------------------------------
  function applyFilter(items, filterName) {
    switch (filterName) {
      // Task 4 (2026-06-11): the "Waiting on you" chip is the bounded global
      // item list — unanswered Misha-asks + blocked items (isWaitingOnYou),
      // the same predicate the cockpit's waiting pill counts.
      case 'awaiting-me':      return items.filter(function (r) { return isWaitingOnYou(r.item); });
      case 'in-flight':        return items.filter(function (r) { return isInFlightItem(r.item); });
      case 'blocked':          return items.filter(function (r) { return itemState(r.item) === 'blocked'; });
      case 'recently-shipped': return items.filter(function (r) { return isRecentlyShipped(r.item); });
      // Phase D — capture ALL work tracked to DEPLOYED, and surface efforts that
      // did NOT reach deployed.
      case 'shipped-not-deployed': return items.filter(function (r) { return isShippedNotDeployed(r.item); });
      case 'deployed':         return items.filter(function (r) { return isDeployed(r.item); });
      case 'orphaned':         return [];   // orphans are sessions, handled in renderFilteredItems
      // Task 7: backlogged operator items live on the Backlog surface only —
      // promote (backlog-activated) is what moves them into the active list.
      case 'my-tasks':         return items.filter(function (r) { return isOperatorItem(r.item) && !r.item.backlogged; });
      case 'all':              return items.slice();
      default:                 return items.filter(function (r) { return isWaitingOnYou(r.item); });
    }
  }
  function filterCount(filterName) {
    // Task 7: the backlog count = parked node items + legacy capture entries
    // (exactly the rows the backlog surface renders).
    if (filterName === 'backlog') return backlogItemRefs().length + legacyBacklogEntries().length;
    if (filterName === 'orphaned') return staleSessions().length;
    return applyFilter(allWorkItems(), filterName).length;
  }
  function updateChipCounts() {
    ['awaiting-me', 'in-flight', 'blocked', 'shipped-not-deployed', 'deployed',
     'recently-shipped', 'orphaned', 'my-tasks', 'backlog', 'all'].forEach(function (f) {
      var span = filterBar.querySelector('[data-count="' + f + '"]');
      if (span) span.textContent = filterCount(f);
    });
    Array.prototype.forEach.call(filterBar.querySelectorAll('.chip'), function (c) {
      c.classList.toggle('active', c.getAttribute('data-filter') === activeFilter);
      c.setAttribute('aria-selected', c.getAttribute('data-filter') === activeFilter ? 'true' : 'false');
    });
  }

  // setActiveFilter — the chip click handler (wire-check target).
  // Phase D — changing filter closes any open detail modal (the modal is now an
  // overlay, no longer a list-replacing card). The filter list always renders
  // behind the (closed) modal.
  function setActiveFilter(filterName) {
    activeFilter = filterName;
    localStorage.setItem('workstreams.activeFilter', filterName);
    closeDetailModal();                           // dismiss overlay + clear selItem
    renderFilteredItems(filterName);
    updateChipCounts();
  }

  // renderFilteredItems — re-render the single side-panel list for a filter.
  // Phase D — no longer toggles a detailCard; the list always shows, the modal
  // floats on top when an item is open.
  function renderFilteredItems(filterName) {
    filterBody.hidden = false;
    clear(filterBody);
    if (filterName === 'backlog') { renderBacklogInto(filterBody); return; }
    if (filterName === 'my-tasks') { renderMyTasksInto(filterBody); return; }
    if (filterName === 'orphaned') { renderOrphansInto(filterBody); return; }
    if (filterName === 'awaiting-me') { renderWaitingInto(filterBody); return; }
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
      'shipped-not-deployed': 'Nothing shipped-but-undeployed — every shipped effort reached production. ✓',
      'deployed': 'Nothing deployed yet.',
      'recently-shipped': 'Nothing shipped in the last ' + SHIP_RECENT_DAYS + ' days.',
      'orphaned': 'No orphaned work — every in-flight item has moved recently. ✓',
      'my-tasks': 'No personal tasks yet — add one above.',
      'all': 'No work items yet.',
    };
    return el('div', 'empty', labels[filterName] || 'Nothing here.');
  }

  // a single work-item row in the filtered list. C6: the kind chip is a
  // NEUTRAL glyph+word (icon encodes kind); status badges carry the color.
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
    meta.appendChild(el('span', 'kind-chip', kindGlyph(r.item.kind) + ' ' + r.item.kind));
    meta.appendChild(el('span', 'st-badge st-' + st, st));
    if (r.item.deferred) meta.appendChild(el('span', 'st-badge st-committed', 'deferred'));
    body.appendChild(meta);
    li.appendChild(body);
    li.addEventListener('click', function () { openDetailModal(r.nodeId, r.itemId); });
    return li;
  }

  // ====================================================================
  //  WAITING ON YOU (Task 4) — the bounded global item list
  // ====================================================================
  // The ONLY place items render globally; naturally small (unanswered
  // Misha-asks + blocked items). Each row is a context-complete SUMMARY:
  // background + recommendation inline, pulled from the item's `details`.
  // An item with empty/insufficient details is NOT painted as decision-ready
  // — it carries a visible "context incomplete" marker instead (the full
  // enrichment gate is Task 8; this list never presents a contextless choice
  // as actionable).
  function waitingSummary(it) {
    var de = it.details;
    if (!de || typeof de !== 'object') return null;
    var bg = de.background || de.about || de.the_ask || de.question
      || de.instructions || null;
    if (!bg && de.description != null) {
      var d = String(de.description).trim();
      // a description that just repeats the title (or is trivially short) is
      // not context — treat it as absent so the incomplete marker shows
      if (d && d !== String(it.text || '').trim() && d.length > 20) bg = d;
    }
    var rec = null;
    if (de.recommendation != null) {
      rec = (typeof de.recommendation === 'object')
        ? (((de.recommendation.option_key ? 'option ' + de.recommendation.option_key + ' — ' : ''))
          + (de.recommendation.reasoning || '')).trim() || null
        : String(de.recommendation);
    }
    if (!bg && !rec) return null;
    return { bg: bg, rec: rec };
  }
  function waitingRow(r) {
    var it = r.item, st = itemState(it);
    var li = el('div', 'item-row wait-row state-' + st);
    li.setAttribute('data-node', r.nodeId);
    li.setAttribute('data-item', r.itemId);
    var ki = el('span', 'ti-kind-ic wi-kind-ic', kindGlyph(it.kind));
    ki.title = it.kind || 'action';
    li.appendChild(ki);
    var body = el('div', 'item-main');
    body.appendChild(el('div', 'item-text', it.text || '(untitled)'));
    var sum = waitingSummary(it);
    if (sum) {
      var ctx = el('div', 'wait-ctx');
      if (sum.bg) ctx.appendChild(el('div', 'wait-bg', String(sum.bg)));
      if (sum.rec) ctx.appendChild(el('div', 'wait-rec', '→ ' + sum.rec));
      body.appendChild(ctx);
    } else {
      var inc = el('span', 'ctx-incomplete-badge', 'context incomplete — needs enrichment');
      inc.title = 'This item lacks the embedded context (background / options / '
        + 'recommendation) needed to act on it cold. Open it for whatever detail exists.';
      body.appendChild(inc);
    }
    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'kind-chip', kindGlyph(it.kind) + ' ' + it.kind));
    meta.appendChild(el('span', 'st-badge st-' + st,
      st === 'blocked' ? ('blocked' + (it.blocked_on ? ' on ' + it.blocked_on : '')) : 'waiting on you'));
    if (it.deferred) meta.appendChild(el('span', 'st-badge st-committed', 'deferred'));
    body.appendChild(meta);
    li.appendChild(body);
    li.addEventListener('click', function () { openDetailModal(r.nodeId, r.itemId); });
    return li;
  }
  function renderWaitingInto(container) {
    var refs = applyFilter(allWorkItems(), 'awaiting-me');
    if (!refs.length) { container.appendChild(emptyMsg('awaiting-me')); return; }
    var byProj = {};
    refs.forEach(function (r) { (byProj[r.projectId] = byProj[r.projectId] || []).push(r); });
    Object.keys(byProj).forEach(function (pid) {
      container.appendChild(el('div', 'list-group-head',
        projectTitle(byId(pid) || { title: pid })));
      byProj[pid].forEach(function (r) { container.appendChild(waitingRow(r)); });
    });
  }

  // Backlog surface render (Task 7) — same edit pattern as My-tasks
  // (in-surface "+ add", inline edit, remove, I3 revert+retry) PLUS a
  // promote-to-task affordance per row. Backlog = "someday"; promoted =
  // active/Next (leaves this view, lands in My-tasks + the activated node's
  // Next count).
  function renderBacklogInto(container) {
    // --- always-present "+ add" input (in-surface, never a native prompt) ---
    var addRow = el('div', 'mytasks-add');
    var addInput = el('input', 'mytasks-add-input');
    addInput.type = 'text';
    addInput.placeholder = 'Capture a "someday" item and press Enter…';
    addInput.setAttribute('aria-label', 'new backlog item text');
    var addBtn = el('button', 'btn-go mytasks-add-btn', '+ add');
    addBtn.setAttribute('aria-label', 'add backlog item');
    function clearFail() {
      addRow.classList.remove('save-failed');
      var rn = addRow.querySelector('.retry-note'); if (rn) rn.remove();
    }
    function submitAdd() {
      var text = (addInput.value || '').trim();
      if (!text) { showToast('Type the backlog item first.', 'err'); addInput.focus(); return; }
      addInput.disabled = true; addBtn.disabled = true;
      addBacklogItem(text, {}, function () {
        addInput.value = '';
        addInput.disabled = false; addBtn.disabled = false;
        addInput.focus();
        // render() fires from the SSE state push
      }, function () {
        // I3 on ADD: nothing persisted — keep the text, re-enable, inline retry note.
        addInput.disabled = false; addBtn.disabled = false;
        addRow.classList.add('save-failed');
        if (!addRow.querySelector('.retry-note')) {
          addRow.appendChild(el('span', 'retry-note', 'not saved — press Enter to retry'));
        }
        addInput.focus();
      });
    }
    addInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); clearFail(); submitAdd(); }
    });
    addBtn.addEventListener('click', function () { clearFail(); submitAdd(); });
    addRow.appendChild(addInput);
    addRow.appendChild(addBtn);
    container.appendChild(addRow);

    // --- parked rows (editable) + legacy capture entries (promote-only) ---
    var refs = backlogItemRefs();
    var legacy = legacyBacklogEntries();
    if (!refs.length && !legacy.length) {
      container.appendChild(el('div', 'empty', 'Backlog is empty — capture "someday" work above.'));
      return;
    }
    var listEl = el('div', 'mytasks-list');
    listEl.setAttribute('role', 'list');
    refs.forEach(function (r) { listEl.appendChild(backlogRow(r)); });
    legacy.forEach(function (b) { listEl.appendChild(legacyBacklogRow(b)); });
    container.appendChild(listEl);
  }

  // ====================================================================
  //  MY TASKS surface render (Task 6) — operator-owned, editable
  // ====================================================================
  // C5: ALL authoring is in-surface (an always-present "+ add" input + inline-
  //     editable rows) — never a native prompt() dialog.
  // I3: on a POST failure the optimistic change visibly REVERTS and an inline
  //     "not saved — retry" affordance appears ON that row (not just a toast).
  // I4: reorder via KEYBOARD (move-up / move-down controls), not drag-only.
  function renderMyTasksInto(container) {
    // --- always-present "+ add" input (in-surface, never a native prompt) ---
    var addRow = el('div', 'mytasks-add');
    var addInput = el('input', 'mytasks-add-input');
    addInput.type = 'text';
    addInput.placeholder = 'Add a task and press Enter…';
    addInput.setAttribute('aria-label', 'new task text');
    var addBtn = el('button', 'btn-go mytasks-add-btn', '+ add');
    addBtn.setAttribute('aria-label', 'add task');
    function submitAdd() {
      var text = (addInput.value || '').trim();
      if (!text) { showToast('Type the task first.', 'err'); addInput.focus(); return; }
      var itemId = uid('task');
      addInput.disabled = true; addBtn.disabled = true;
      ensureMyTasksNode(function () {
        post({ type: 'action-added', node_id: MYTASKS_NODE, item_id: itemId, text: text, origin: 'operator' },
          'Task added')
          .then(function () {
            addInput.value = '';
            addInput.disabled = false; addBtn.disabled = false;
            addInput.focus();   // ready for the next task
            // render() fires from the SSE state push; no manual re-render needed
          })
          .catch(function () {
            // I3-style failure on ADD: the input keeps its text (nothing was
            // persisted), is re-enabled, and an inline retry note shows.
            addInput.disabled = false; addBtn.disabled = false;
            addRow.classList.add('save-failed');
            if (!addRow.querySelector('.retry-note')) {
              var n = el('span', 'retry-note', 'not saved — press Enter to retry');
              addRow.appendChild(n);
            }
            addInput.focus();
          });
      });
    }
    addInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); addRow.classList.remove('save-failed'); var rn = addRow.querySelector('.retry-note'); if (rn) rn.remove(); submitAdd(); }
    });
    addBtn.addEventListener('click', function () { addRow.classList.remove('save-failed'); var rn = addRow.querySelector('.retry-note'); if (rn) rn.remove(); submitAdd(); });
    addRow.appendChild(addInput);
    addRow.appendChild(addBtn);
    container.appendChild(addRow);

    // --- the operator's task list (in chosen order; removed items filtered) ---
    var refs = myTaskRefs();
    if (!refs.length) {
      container.appendChild(el('div', 'empty', 'No personal tasks yet — add one above.'));
      return;
    }
    var listEl = el('div', 'mytasks-list');
    listEl.setAttribute('role', 'list');
    refs.forEach(function (r, ix) {
      listEl.appendChild(myTaskRow(r, ix, refs));
    });
    container.appendChild(listEl);
  }

  // One editable My-tasks row. Inline-edit on the text (contentEditable-free —
  // a real <input> swapped in on demand so screen readers and keyboard work),
  // a complete toggle, keyboard reorder (▲/▼), and remove (✕).
  function myTaskRow(r, ix, refs) {
    var st = itemState(r.item);
    var row = el('div', 'item-row mytask-row state-' + st);
    row.setAttribute('role', 'listitem');
    row.setAttribute('data-node', r.nodeId);
    row.setAttribute('data-item', r.itemId);

    var ic = el('span', 'item-ic', r.item.checked ? '✓' : stateIcon(st));
    ic.title = r.item.checked ? 'done' : st;
    row.appendChild(ic);

    // --- editable text (display span; click / Enter swaps to an input) ---
    var body = el('div', 'item-main');
    var txt = el('div', 'item-text mytask-text', r.item.text || '(untitled)');
    txt.setAttribute('tabindex', '0');
    txt.setAttribute('role', 'button');
    txt.setAttribute('aria-label', 'edit task: ' + (r.item.text || 'untitled'));
    function beginEdit() {
      if (row.querySelector('.mytask-edit')) return;   // already editing
      var inp = el('input', 'mytask-edit');
      inp.type = 'text';
      inp.value = r.item.text || '';
      inp.setAttribute('aria-label', 'edit task text');
      var prevText = r.item.text || '';
      txt.replaceWith(inp);
      inp.focus(); inp.select();
      var committed = false;
      function commit() {
        if (committed) return; committed = true;
        var next = (inp.value || '').trim();
        if (!next || next === prevText) {
          // nothing to save — restore the display span unchanged
          inp.replaceWith(txt);
          return;
        }
        // optimistic: show the new text immediately, then persist
        txt.textContent = next;
        inp.replaceWith(txt);
        post({ type: 'item-text-set', node_id: r.nodeId, item_id: r.itemId, text: next })
          .then(function () { /* SSE re-render confirms */ })
          .catch(function () {
            // I3: REVERT the visible text and show an inline retry affordance
            // ON this row (not only a toast).
            txt.textContent = prevText;
            row.classList.add('save-failed');
            if (!row.querySelector('.retry-note')) {
              var retry = el('button', 'retry-note retry-btn', '↻ not saved — retry');
              retry.setAttribute('aria-label', 'retry saving task edit');
              retry.addEventListener('click', function (e) {
                e.stopPropagation();
                row.classList.remove('save-failed'); retry.remove();
                // re-enter edit with the attempted (reverted-from) value
                beginEditWith(next);
              });
              row.appendChild(retry);
            }
          });
      }
      function cancel() {
        if (committed) return; committed = true;
        inp.replaceWith(txt);
      }
      inp.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); commit(); }
        else if (e.key === 'Escape') { e.preventDefault(); cancel(); }
      });
      inp.addEventListener('blur', commit);
    }
    function beginEditWith(seed) {
      // open the editor pre-filled with a retry value
      var inp = el('input', 'mytask-edit');
      inp.type = 'text'; inp.value = seed; inp.setAttribute('aria-label', 'edit task text');
      var prevText = r.item.text || '';
      txt.replaceWith(inp); inp.focus(); inp.select();
      var committed = false;
      function commit() {
        if (committed) return; committed = true;
        var next = (inp.value || '').trim();
        if (!next) { inp.replaceWith(txt); txt.textContent = prevText; return; }
        txt.textContent = next; inp.replaceWith(txt);
        post({ type: 'item-text-set', node_id: r.nodeId, item_id: r.itemId, text: next })
          .catch(function () {
            txt.textContent = prevText; row.classList.add('save-failed');
            if (!row.querySelector('.retry-note')) {
              var retry = el('button', 'retry-note retry-btn', '↻ not saved — retry');
              retry.addEventListener('click', function (e) { e.stopPropagation(); row.classList.remove('save-failed'); retry.remove(); beginEditWith(next); });
              row.appendChild(retry);
            }
          });
      }
      inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); commit(); } else if (e.key === 'Escape') { e.preventDefault(); committed = true; inp.replaceWith(txt); } });
      inp.addEventListener('blur', commit);
    }
    txt.addEventListener('click', beginEdit);
    txt.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); beginEdit(); } });
    body.appendChild(txt);

    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'st-badge st-' + st, st));
    meta.appendChild(el('span', 'origin-badge', 'mine'));
    body.appendChild(meta);
    row.appendChild(body);

    // --- controls: complete · reorder (▲/▼, keyboard) · remove ---
    var ctrls = el('div', 'mytask-ctrls');

    var doneBtn = el('button', 'mytask-ctrl ctrl-done', r.item.checked ? '↺' : '✓');
    doneBtn.setAttribute('aria-label', r.item.checked ? 'reopen task' : 'mark task done');
    doneBtn.title = r.item.checked ? 'reopen' : 'mark done';
    doneBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      if (r.item.checked) {
        post({ type: 'item-unchecked', node_id: r.nodeId, item_id: r.itemId }, 'Reopened');
      } else {
        post({ type: 'action-done', node_id: r.nodeId, item_id: r.itemId }, 'Done');
      }
    });
    ctrls.appendChild(doneBtn);

    var upBtn = el('button', 'mytask-ctrl ctrl-up', '▲');
    upBtn.setAttribute('aria-label', 'move task up');
    upBtn.title = 'move up';
    upBtn.disabled = ix === 0;
    upBtn.addEventListener('click', function (e) { e.stopPropagation(); reorderMyTask(refs, ix, ix - 1); });
    ctrls.appendChild(upBtn);

    var downBtn = el('button', 'mytask-ctrl ctrl-down', '▼');
    downBtn.setAttribute('aria-label', 'move task down');
    downBtn.title = 'move down';
    downBtn.disabled = ix === refs.length - 1;
    downBtn.addEventListener('click', function (e) { e.stopPropagation(); reorderMyTask(refs, ix, ix + 1); });
    ctrls.appendChild(downBtn);

    var rmBtn = el('button', 'mytask-ctrl ctrl-remove', '✕');
    rmBtn.setAttribute('aria-label', 'remove task');
    rmBtn.title = 'remove';
    rmBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      post({ type: 'item-removed', node_id: r.nodeId, item_id: r.itemId }, 'Removed')
        .catch(function () {
          // I3: removal failed — the row stays (item not actually gone) and an
          // inline retry note appears.
          row.classList.add('save-failed');
          if (!row.querySelector('.retry-note')) {
            var retry = el('button', 'retry-note retry-btn', '↻ not removed — retry');
            retry.addEventListener('click', function (ev) { ev.stopPropagation(); row.classList.remove('save-failed'); retry.remove(); rmBtn.click(); });
            row.appendChild(retry);
          }
        });
    });
    ctrls.appendChild(rmBtn);

    row.appendChild(ctrls);
    return row;
  }

  // Keyboard/button reorder — recompute the full ordered_ids list with the item
  // moved from `from` to `to`, then persist a single `reordered` event scoped to
  // the My-tasks node. On failure the SSE state is unchanged so the list snaps
  // back to the persisted order on the next render (the optimistic move is the
  // re-render driven by the SSE push, never a local mutation we'd have to undo).
  function reorderMyTask(refs, from, to) {
    if (to < 0 || to >= refs.length || from === to) return;
    var ids = refs.map(function (r) { return r.itemId; });
    var moved = ids.splice(from, 1)[0];
    ids.splice(to, 0, moved);
    post({ type: 'reordered', scope: MYTASKS_NODE, ordered_ids: ids }, 'Reordered')
      .catch(function () { showToast('Reorder not saved — try again.', 'err'); });
  }

  // ====================================================================
  //  BACKLOG surface (Task 7) — operator-owned "someday" bucket
  // ====================================================================
  // Same edit pattern as My-tasks (C5: in-surface forms only; I3: visible
  // revert + inline retry on write failure) PLUS promote-to-task.
  //
  // Data model (existing events ONLY — C1 is binding, no new event types):
  //   - A backlog row is a first-class WorkItem parked with the EXISTING
  //     `backlogged` flag (set by item-backlogged; cleared by item-unchecked).
  //     itemState() maps backlogged → 'committed', and isWaiting() excludes
  //     backlogged items, so the "someday" bucket never pollutes the waiting /
  //     in-flight surfaces. New rows live on a dedicated "Backlog" root.
  //   - Edit  = item-text-set (the existing text-repair event).
  //   - Remove = item-removed (the one C1-added event, shared with My-tasks).
  //   - PROMOTE = the EXISTING `backlog-activated` event (C1 — there is NO
  //     item-promoted). backlog-activated flips membership on the snap.backlog
  //     entry (b.activated=true → leaves the backlog view) and opens the
  //     FR-22 handoff root carrying the item's text. The promote flow then
  //     places the actual task on that activated root (action-added with
  //     origin:'operator' so it shows in My-tasks, + item-committed so it
  //     lands in the NEXT tier) and retires the parked source row
  //     (item-removed). snap.backlog mirrors are created lazily AT PROMOTE
  //     time (backlog-added with the CURRENT text) so an inline edit can
  //     never leave a stale mirror behind.
  //   - Legacy snap.backlog entries (pre-redesign captures with no node item)
  //     still render — promote-only, since the event vocabulary has no
  //     backlog-text-edit/-remove (honest limitation, fix-forward).
  var BL_NODE = 'backlog-operator';
  var BL_TITLE = 'Backlog';
  function isBacklogItem(it) { return it && it.backlogged === true && !it.checked; }
  function backlogItemRefs() {
    return allWorkItems().filter(function (r) { return isBacklogItem(r.item); });
  }
  // Legacy capture entries: un-activated snap.backlog rows with NO node item
  // (a mirror created at promote time shares its item_id with the node item,
  // so dedupe by id keeps each backlog row rendered exactly once).
  function legacyBacklogEntries() {
    var nodeIds = {};
    allWorkItems().forEach(function (r) { nodeIds[r.itemId] = 1; });
    return backlog().filter(function (b) { return !b.activated && !nodeIds[b.item_id]; });
  }
  function ensureBacklogNode(then, onFail) {
    if (byId(BL_NODE)) { then(); return; }
    post({ type: 'branch-opened', node_id: BL_NODE, parent_id: null, title: BL_TITLE })
      .then(function () { then(); })
      .catch(function () {
        showToast('Could not create the Backlog list — try again.', 'err');
        // I3: the caller's failure path must run (re-enable the add input +
        // inline retry note) — a failed node-create is a failed add.
        if (onFail) onFail();
      });
  }
  // postSeq — append a fixed sequence of events in order. Every event carries a
  // PRE-GENERATED event_id, so a retry that re-posts the SAME array is safe:
  // already-landed events are envelope-level idempotent no-ops (§2) and the
  // sequence resumes at the first event that never landed.
  function postSeq(events, okMsg) {
    events.forEach(function (ev) {
      if (!ev.event_id) ev.event_id = uid('gui');
      if (!ev.ts) ev.ts = new Date().toISOString();
    });
    var p = Promise.resolve();
    events.forEach(function (ev) {
      p = p.then(function () { return post(ev); });
    });
    return p.then(function () { if (okMsg) showToast(okMsg, 'ok'); });
  }
  // addBacklogItem — the ONE add path (used by the surface "+ add" input AND
  // the header "+ capture" form, so every captured item is equally editable).
  // opts: { priority: 'high'|'medium'|'low'|null, context: string|null }
  var PRIORITY_NUM = { high: 2, medium: 3, low: 4 };
  function addBacklogItem(text, opts, onOk, onFail) {
    opts = opts || {};
    var itemId = uid('bl');
    var events = [
      { type: 'action-added', node_id: BL_NODE, item_id: itemId, text: text, origin: 'operator' },
      { type: 'item-backlogged', node_id: BL_NODE, item_id: itemId },
    ];
    if (opts.priority && PRIORITY_NUM[opts.priority]) {
      events.push({ type: 'priority-assigned', target_id: itemId, priority: PRIORITY_NUM[opts.priority] });
    }
    if (opts.context && String(opts.context).trim()) {
      events.push({ type: 'item-details-set', node_id: BL_NODE, item_id: itemId,
                    details: { description: String(opts.context).trim() } });
    }
    ensureBacklogNode(function () {
      postSeq(events, 'Captured to backlog')
        .then(function () { if (onOk) onOk(); })
        .catch(function () { if (onFail) onFail(); });
    }, onFail);
  }
  // buildPromoteEvents — the promote-to-task sequence for a parked node item.
  // Built ONCE with stable event_ids; a retry re-posts the identical array.
  function buildPromoteEvents(r) {
    var text = r.item.text || '(untitled)';
    var mirror = null;
    backlog().forEach(function (b) { if (b.item_id === r.itemId) mirror = b; });
    var actId = (mirror && mirror.activated && mirror.activated_node)
      ? mirror.activated_node : uid('blact');
    var taskId = uid('task');
    var events = [];
    if (!mirror) {
      events.push({ type: 'backlog-added', item_id: r.itemId, tree_id: 'global',
                    priority: 'medium', text: text });
    }
    if (!(mirror && mirror.activated)) {
      events.push({ type: 'backlog-activated', item_id: r.itemId, new_node_id: actId });
      // a pre-existing mirror may carry stale text — repair the handoff
      // node's title via the existing text-repair event.
      if (mirror && mirror.text !== text) {
        events.push({ type: 'branch-retitled', node_id: actId, title: text });
      }
    }
    events.push({ type: 'action-added', node_id: actId, item_id: taskId, text: text, origin: 'operator' });
    events.push({ type: 'item-committed', node_id: actId, item_id: taskId });
    events.push({ type: 'item-removed', node_id: r.nodeId, item_id: r.itemId });
    return events;
  }
  function buildLegacyPromoteEvents(b) {
    var actId = uid('blact');
    var taskId = uid('task');
    var events = [
      { type: 'backlog-activated', item_id: b.item_id, new_node_id: actId },
      { type: 'action-added', node_id: actId, item_id: taskId, text: b.text || '(untitled)', origin: 'operator' },
      { type: 'item-committed', node_id: actId, item_id: taskId },
    ];
    if (b.context_text && String(b.context_text).trim()) {
      events.push({ type: 'item-details-set', node_id: actId, item_id: taskId,
                    details: { description: String(b.context_text).trim() } });
    }
    return events;
  }
  // promote with I3 semantics: on failure the row stays (nothing left the
  // backlog) and an inline "not promoted — retry" affordance re-posts the SAME
  // event array (idempotent resume).
  function runPromote(row, events) {
    postSeq(events, 'Promoted to task')
      .catch(function () {
        row.classList.add('save-failed');
        if (!row.querySelector('.retry-note')) {
          var retry = el('button', 'retry-note retry-btn', '↻ not promoted — retry');
          retry.setAttribute('aria-label', 'retry promoting backlog item');
          retry.addEventListener('click', function (e) {
            e.stopPropagation();
            row.classList.remove('save-failed'); retry.remove();
            runPromote(row, events);
          });
          row.appendChild(retry);
        }
      });
  }

  // attachBacklogEdit — inline text edit for a backlog row (same I3 contract
  // as myTaskRow: optimistic display, visible REVERT + inline retry on a
  // failed item-text-set).
  function attachBacklogEdit(row, txt, r) {
    function beginEditWith(seed) {
      if (row.querySelector('.mytask-edit')) return;
      var inp = el('input', 'mytask-edit');
      inp.type = 'text';
      inp.value = seed;
      inp.setAttribute('aria-label', 'edit backlog item text');
      var prevText = r.item.text || '';
      txt.replaceWith(inp);
      inp.focus(); inp.select();
      var committed = false;
      function commit() {
        if (committed) return; committed = true;
        var next = (inp.value || '').trim();
        if (!next || next === prevText) { inp.replaceWith(txt); return; }
        txt.textContent = next;
        inp.replaceWith(txt);
        post({ type: 'item-text-set', node_id: r.nodeId, item_id: r.itemId, text: next })
          .catch(function () {
            // I3: REVERT the visible text + inline retry ON the row.
            txt.textContent = prevText;
            row.classList.add('save-failed');
            if (!row.querySelector('.retry-note')) {
              var retry = el('button', 'retry-note retry-btn', '↻ not saved — retry');
              retry.setAttribute('aria-label', 'retry saving backlog edit');
              retry.addEventListener('click', function (e) {
                e.stopPropagation();
                row.classList.remove('save-failed'); retry.remove();
                beginEditWith(next);
              });
              row.appendChild(retry);
            }
          });
      }
      inp.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); commit(); }
        else if (e.key === 'Escape') { e.preventDefault(); committed = true; inp.replaceWith(txt); }
      });
      inp.addEventListener('blur', commit);
    }
    txt.addEventListener('click', function () { beginEditWith(r.item.text || ''); });
    txt.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); beginEditWith(r.item.text || ''); }
    });
  }

  // One editable backlog row: inline-editable text · priority badge ·
  // promote-to-task (▸) · remove (✕).
  function backlogRow(r) {
    var row = el('div', 'item-row mytask-row bl-row state-committed');
    row.setAttribute('role', 'listitem');
    row.setAttribute('data-node', r.nodeId);
    row.setAttribute('data-item', r.itemId);
    row.appendChild(el('span', 'item-ic', '◷'));

    var body = el('div', 'item-main');
    var txt = el('div', 'item-text mytask-text', r.item.text || '(untitled)');
    txt.setAttribute('tabindex', '0');
    txt.setAttribute('role', 'button');
    txt.setAttribute('aria-label', 'edit backlog item: ' + (r.item.text || 'untitled'));
    attachBacklogEdit(row, txt, r);
    body.appendChild(txt);
    var de = r.item.details;
    if (de && de.description) body.appendChild(el('div', 'item-ctx', String(de.description)));
    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'st-badge st-committed', 'backlog'));
    if (r.item.priority >= 1 && r.item.priority <= 4) {
      meta.appendChild(el('span', 'st-badge st-committed', 'P' + r.item.priority));
    }
    if (isOperatorItem(r.item)) meta.appendChild(el('span', 'origin-badge', 'mine'));
    body.appendChild(meta);
    row.appendChild(body);

    var ctrls = el('div', 'mytask-ctrls');
    var promoteBtn = el('button', 'mytask-ctrl ctrl-promote', '▸');
    promoteBtn.setAttribute('aria-label', 'promote to task');
    promoteBtn.title = 'promote to task (moves to the active list / Next)';
    promoteBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      runPromote(row, buildPromoteEvents(r));
    });
    ctrls.appendChild(promoteBtn);
    var rmBtn = el('button', 'mytask-ctrl ctrl-remove', '✕');
    rmBtn.setAttribute('aria-label', 'remove backlog item');
    rmBtn.title = 'remove';
    rmBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      post({ type: 'item-removed', node_id: r.nodeId, item_id: r.itemId }, 'Removed')
        .catch(function () {
          row.classList.add('save-failed');
          if (!row.querySelector('.retry-note')) {
            var retry = el('button', 'retry-note retry-btn', '↻ not removed — retry');
            retry.addEventListener('click', function (ev) {
              ev.stopPropagation();
              row.classList.remove('save-failed'); retry.remove(); rmBtn.click();
            });
            row.appendChild(retry);
          }
        });
    });
    ctrls.appendChild(rmBtn);
    row.appendChild(ctrls);
    return row;
  }

  // A legacy capture entry (snap.backlog only — promote works; edit/remove
  // need a node item the pre-redesign capture never created).
  function legacyBacklogRow(b) {
    var row = el('div', 'item-row bl-row bl-legacy state-committed');
    row.appendChild(el('span', 'item-ic', '◷'));
    var body = el('div', 'item-main');
    body.appendChild(el('div', 'item-text', b.text || '(untitled)'));
    if (b.context_text) body.appendChild(el('div', 'item-ctx', b.context_text));
    var meta = el('div', 'item-meta');
    meta.appendChild(el('span', 'st-badge st-committed', 'backlog · ' + (b.priority || '—')));
    meta.appendChild(el('span', 'st-badge st-muted', 'legacy capture'));
    body.appendChild(meta);
    row.appendChild(body);
    var ctrls = el('div', 'mytask-ctrls');
    var promoteBtn = el('button', 'mytask-ctrl ctrl-promote', '▸');
    promoteBtn.setAttribute('aria-label', 'promote to task');
    promoteBtn.title = 'promote to task (moves to the active list / Next)';
    promoteBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      runPromote(row, buildLegacyPromoteEvents(b));
    });
    ctrls.appendChild(promoteBtn);
    row.appendChild(ctrls);
    return row;
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
    if (s.opened_at) meta.appendChild(el('span', 'st-badge st-muted',
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
  // `global` is the cross-cutting backlog container; `proj-personal` and
  // `proj-pocket-technician` are 0-item ACCOUNT-name nodes — they ARE the repo
  // groups (the top tier), not projects within them. Rendering them as child
  // projects produced the redundant "Pocket Technician under Pocket Technician".
  // Excluded from the project list; their account becomes the repo header.
  var NON_PROJECT_NODES = { 'global': 1, 'proj-personal': 1, 'proj-pocket-technician': 1 };
  function projects() {
    return nodes().filter(isProject).filter(function (n) {
      if (NON_PROJECT_NODES[n.node_id]) return false;
      return showArchived.checked || n.state !== 'archived';
    });
  }

  // ---- repo grouping (top tier: GitHub repo → Project) -------------------
  // The design (workstreams-design-v2 §1) is Project → Workstream → WorkItem →
  // Sub-task; Misha added a Repo tier ABOVE projects so the tree mirrors which
  // GitHub repo each project lives in. The mapping below is DERIVED from the
  // real git remotes on this machine (mishanovini/* = Personal, Pocket-Technician/*
  // = Pocket Technician); it is overridable per-machine via a `repoMap` object on
  // the served snapshot (S.repoMap) or a project node's own `repo` field — those
  // win over this default so the data layer can correct it without a code change.
  // DERIVED from ground truth — `gh repo list` for each account + the local
  // dev/<account>/ folders (cortex-one + foresight live only in mishanovini;
  // Circuit lives only in Pocket-Technician; neural-lace lives in BOTH).
  var PROJECT_REPO_DEFAULT = {
    'proj-cortex-one': 'Personal',
    'proj-foresight': 'Personal',
    'proj-circuit': 'Pocket Technician',
  };
  // neural-lace is dual-remoted (mishanovini AND Pocket-Technician); per Misha it
  // gets its OWN "Shared" group rather than appearing under both accounts.
  var PROJECT_REPOS_MULTI = { 'proj-neural-lace': ['Shared'] };
  var REPO_ORDER = ['Pocket Technician', 'Personal', 'Shared'];
  // Returns the array of repos a project belongs to (≥1). Node-level `repo`
  // and a served `S.repoMap` override the derived default.
  function reposOf(projNode) {
    if (projNode && projNode.repo) return [].concat(projNode.repo);
    if (S && S.repoMap && S.repoMap[projNode.node_id]) return [].concat(S.repoMap[projNode.node_id]);
    if (PROJECT_REPOS_MULTI[projNode.node_id]) return PROJECT_REPOS_MULTI[projNode.node_id];
    return [PROJECT_REPO_DEFAULT[projNode.node_id] || 'Other'];
  }
  // ---- cockpit data (Task 3) -------------------------------------------
  // One entry per ROOT that owns visible work items — grouped from the SAME
  // allWorkItems() the right-pane filters read, so cockpit counts always match
  // the reduced state the filters show — PLUS item-less proper projects so an
  // empty project still shows a row rather than vanishing. Account-container
  // roots (NON_PROJECT_NODES) appear only when they actually own items (the
  // `global` cross-cutting container does; the bare account-name nodes don't).
  function cockpitRows() {
    var byProj = {};
    allWorkItems().forEach(function (r) {
      (byProj[r.projectId] = byProj[r.projectId] || []).push(r);
    });
    var ids = Object.keys(byProj);
    projects().forEach(function (p) {
      if (ids.indexOf(p.node_id) === -1) ids.push(p.node_id);
    });
    return ids
      .map(function (id) { return byId(id); })
      .filter(function (n) {
        if (!n) return false;
        if (NON_PROJECT_NODES[n.node_id] && !(byProj[n.node_id] || []).length) return false;
        return true;
      })
      .map(function (n) {
        return { projectId: n.node_id, node: n, refs: byProj[n.node_id] || [],
                 counts: statusCounts(byProj[n.node_id] || []) };
      })
      .sort(function (a, b) {
        // bottleneck-first: most-waiting projects rise to the top of their repo
        if (b.counts.waiting !== a.counts.waiting) return b.counts.waiting - a.counts.waiting;
        if (b.counts.now !== a.counts.now) return b.counts.now - a.counts.now;
        return projectTitle(a.node).localeCompare(projectTitle(b.node));
      });
  }

  // renderTree — left-pane orchestrator (wire-check entry point). Renders the
  // project COCKPIT (Task 3: one fixed-density count-row per project) by
  // default, or the DRILLED single-project tree (Task 5) once a row is
  // clicked. Density principle (load-bearing): COUNTS globally — O(projects),
  // never O(items); ITEMS render only in one bounded slice (the drilled
  // project's tree, or the right-pane waiting list).
  function renderTree() {
    clear(treeCanvas);
    var rows = cockpitRows();
    if (!rows.length) {
      treeState.hidden = false;
      treeState.textContent = loaded ? 'No projects yet.' : 'Loading…';
      return;
    }
    treeState.hidden = true;
    if (drillProject && byId(drillProject)) renderDrill(rows);
    else { drillProject = null; renderCockpit(rows); }
    var tot = statusCounts(allWorkItems());
    treeSummary.textContent = tot.waiting + ' waiting · ' + tot.now + ' now · '
      + tot.next + ' next · ' + tot.done + ' done';
    renderOrphanSection();
  }

  // setDrill — enter/leave the single-project drill (cockpit click → drilled
  // tree; C4: the "← all projects" breadcrumb calls setDrill(null)).
  function setDrill(projId) {
    drillProject = projId || null;
    if (drillProject) localStorage.setItem('workstreams.drillProject', drillProject);
    else localStorage.removeItem('workstreams.drillProject');
    renderTree();
  }

  // ---- COCKPIT (Task 3) -------------------------------------------------
  var CK_COLS = ['now', 'next', 'waiting', 'done'];
  var CK_TITLES = {
    now: 'in flight now', next: 'queued next',
    waiting: 'waiting on you / blocked', done: 'done (shipped)',
  };
  function renderCockpit(rows) {
    // column-header row — the number pills below align to the same fixed grid
    var head = el('div', 'ck-cols');
    head.setAttribute('aria-hidden', 'true');
    head.appendChild(el('span', 'ck-col-name', ''));
    CK_COLS.forEach(function (c) { head.appendChild(el('span', 'ck-col', c)); });
    treeCanvas.appendChild(head);
    // group rows by owning repo (a dual-remoted project appears under each)
    var byRepo = {};
    rows.forEach(function (row) {
      reposOf(row.node).forEach(function (rp) { (byRepo[rp] = byRepo[rp] || []).push(row); });
    });
    var repos = REPO_ORDER.filter(function (r) { return byRepo[r]; }).concat(
      Object.keys(byRepo).filter(function (r) { return REPO_ORDER.indexOf(r) === -1; }).sort());
    repos.forEach(function (repo) {
      treeCanvas.appendChild(renderRepoGroup(repo, byRepo[repo], !collapsedRepos.has(repo)));
    });
  }

  // renderRepoGroup — collapsible repo section of cockpit rows. Neutral gray
  // structure per C6; the only accent is the amber waiting chip when > 0.
  function renderRepoGroup(repo, rowList, expanded) {
    var wrap = el('div', 'repo-group' + (expanded ? ' exp' : ''));
    var head = el('button', 'repo-head');
    head.type = 'button';
    head.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    head.appendChild(el('span', 'twisty', expanded ? '▼' : '▶'));
    head.appendChild(el('span', 'repo-title', repo));
    var waitSum = 0;
    rowList.forEach(function (row) { waitSum += row.counts.waiting; });
    if (waitSum) {
      var wchip = el('span', 'rg-wait', waitSum + ' waiting');
      wchip.title = waitSum + ' item(s) in this repo are waiting on you';
      head.appendChild(wchip);
    }
    head.addEventListener('click', function () { toggleRepo(repo); });
    wrap.appendChild(head);
    if (expanded) {
      var kids = el('div', 'ck-rows');
      rowList.forEach(function (row) { kids.appendChild(cockpitRow(row)); });
      wrap.appendChild(kids);
    }
    return wrap;
  }
  function toggleRepo(repo) {
    if (collapsedRepos.has(repo)) collapsedRepos.delete(repo); else collapsedRepos.add(repo);
    saveSet('workstreams.collapsedRepos', collapsedRepos);
    renderTree();
  }

  // One fixed-density cockpit row: project name + four NUMBER pills. Never
  // renders items — a project with dozens of items shows a count, not chips.
  function cockpitRow(row) {
    var btn = el('button', 'ck-row' + (row.counts.waiting ? ' has-wait' : ''));
    btn.type = 'button';
    btn.setAttribute('data-proj', row.projectId);
    btn.setAttribute('aria-label', 'open project ' + projectTitle(row.node) + ' — '
      + CK_COLS.map(function (c) { return row.counts[c] + ' ' + c; }).join(', '));
    var name = el('span', 'ck-name', projectTitle(row.node));
    if (row.node.state === 'archived') name.appendChild(el('span', 'ck-arch', ' · archived'));
    btn.appendChild(name);
    CK_COLS.forEach(function (c) {
      var n = row.counts[c];
      var pill = el('span', 'ck-pill ck-' + c + (n ? '' : ' zero')
        + (c === 'waiting' && n ? ' accent' : ''), String(n));
      pill.title = n + ' ' + CK_TITLES[c];
      btn.appendChild(pill);
    });
    btn.addEventListener('click', function () { setDrill(row.projectId); });
    return btn;
  }

  // ---- DRILL (Task 5) -----------------------------------------------------
  // Master-detail at wide widths (C4): a compact cockpit RAIL stays on the
  // left so the operator can hop projects; at narrow widths (≤560px) the rail
  // hides and the view is a full swap with the "← all projects" breadcrumb as
  // the persistent way back — no dead-end drill.
  function renderDrill(rows) {
    var proj = byId(drillProject);
    var mine = null;
    rows.forEach(function (row) { if (row.projectId === drillProject) mine = row; });
    var refs = mine ? mine.refs : [];
    var counts = mine ? mine.counts : statusCounts([]);

    var wrap = el('div', 'drill-wrap');
    var rail = el('nav', 'ck-rail');
    rail.setAttribute('aria-label', 'all projects');
    rows.forEach(function (row) {
      var b = el('button', 'ck-rail-row' + (row.projectId === drillProject ? ' sel' : ''));
      b.type = 'button';
      b.appendChild(el('span', 'ck-rail-name', projectTitle(row.node)));
      if (row.counts.waiting) {
        var w = el('span', 'ck-rail-wait', String(row.counts.waiting));
        w.title = row.counts.waiting + ' waiting on you';
        b.appendChild(w);
      }
      b.addEventListener('click', function () { setDrill(row.projectId); });
      rail.appendChild(b);
    });
    wrap.appendChild(rail);

    var main = el('div', 'drill-main');
    // C4 — persistent return path + current-project header.
    var head = el('div', 'drill-head');
    var back = el('button', 'drill-back', '← All projects');
    back.type = 'button';
    back.setAttribute('aria-label', 'back to all projects');
    back.addEventListener('click', function () { setDrill(null); });
    head.appendChild(back);
    head.appendChild(el('span', 'drill-title', projectTitle(proj)));
    var hc = el('span', 'drill-counts');
    CK_COLS.forEach(function (c) {
      var n = counts[c];
      var pill = el('span', 'ck-pill ck-' + c + (n ? '' : ' zero')
        + (c === 'waiting' && n ? ' accent' : ''), n + ' ' + c);
      pill.title = n + ' ' + CK_TITLES[c];
      hc.appendChild(pill);
    });
    head.appendChild(hc);
    // "show done" toggle (Task 5) — backed by the header's show-completed
    // checkbox so there is ONE source of truth for done-item visibility.
    var sd = el('button', 'drill-showdone',
      (showCompleted.checked ? 'hide done' : 'show done') + ' (' + counts.done + ')');
    sd.type = 'button';
    sd.setAttribute('aria-pressed', showCompleted.checked ? 'true' : 'false');
    sd.addEventListener('click', function () {
      showCompleted.checked = !showCompleted.checked;
      render();
    });
    head.appendChild(sd);
    main.appendChild(head);

    var treeEl = el('div', 'drill-tree');
    // the drilled project IS the project tier — its branches nest inside the
    // .proj container so the Repo → Project → Workstream → WorkItem hierarchy
    // is preserved in the drill (rail = repo/projects, .proj = this project).
    var projWrap = el('div', 'proj');
    projWrap.classList.add('exp');
    renderProjectTree(projWrap, proj, refs);
    treeEl.appendChild(projWrap);
    main.appendChild(treeEl);
    wrap.appendChild(main);
    treeCanvas.appendChild(wrap);
  }

  // renderProjectTree — ONE bounded project, nested with guide lines: real
  // child branches (nodes holding items) render as branch groups; the
  // project's DIRECT items group into derived workstreams by theme.
  function renderProjectTree(treeEl, proj, refs) {
    if (!refs.length) {
      treeEl.appendChild(el('div', 'proj-empty', 'Nothing in flight'));
      return;
    }
    var direct = [], byNode = {};
    refs.forEach(function (r) {
      if (r.nodeId === proj.node_id) direct.push(r);
      else (byNode[r.nodeId] = byNode[r.nodeId] || []).push(r);
    });
    // real branch nodes first (workstream-tier nodes per collectWorkstreams
    // order, then any other item-holding descendant), then derived themes
    var seen = {};
    collectWorkstreams(proj.node_id).forEach(function (ws) {
      if (byNode[ws.node_id]) {
        treeEl.appendChild(renderWorkstream(ws, byNode[ws.node_id]));
        seen[ws.node_id] = 1;
      }
    });
    Object.keys(byNode).forEach(function (nid) {
      if (!seen[nid]) treeEl.appendChild(renderWorkstream(byId(nid) || { node_id: nid }, byNode[nid]));
    });
    renderDerivedWorkstreams(treeEl, direct);
  }

  // renderWorkstream — a REAL branch node's group (wire-check target).
  function renderWorkstream(wsNode, refs) {
    refs = refs || collectWorkItems(wsNode.node_id);
    return branchGroup(wsNode.title || wsNode.node_id, refs, 'node:' + wsNode.node_id);
  }

  // ---- derived Workstream tier (theme grouping of a project's items) -------
  // The data carries no `tier:workstream` nodes, so the Workstream tier is
  // DERIVED: each WorkItem is bucketed into a logical initiative by matching its
  // text against an ordered theme list (first match wins; the rest → "General").
  // This is the "smart, logical grouping" best-guess backfill Misha approved
  // (2026-06-03) until real workstream nodes are assigned. Order matters.
  var WS_THEMES = [
    [/cross-repo|cross repo/i, 'Cross-repo'],
    [/conv(ersation)?[\s-]?tree|workstream/i, 'Conversation Tree / Workstreams'],
    [/dispatch/i, 'Dispatch'],
    [/sync|mirror|\bfork\b|cross-machine|both masters|\bremote\b/i, 'Cross-machine sync'],
    [/doctrine|principle/i, 'Doctrine & Principles'],
    [/fm-catalog|failure[\s-]?mode|\bFM-\d/i, 'Failure-mode catalog'],
    [/propagation/i, 'Propagation engine'],
    [/retry-guard|continuation-enforcer|stop-hook|evidence-gate|scope-enforc|completion-criteria|pr-health|\bgate\b/i, 'Harness gates'],
    [/pipeline-override|never_matched|categoriz|rule rows|unattributable/i, 'Foresight Q1 — categorization'],
    [/\bbug #?\d+/i, 'Bug fixes'],
    [/install|bootstrap|fresh-machine|hook settings|auto-install/i, 'Install & bootstrap'],
    [/PR #\d+/i, 'PR follow-ups'],
  ];
  function workstreamOf(item) {
    var t = String((item && item.text) || '');
    for (var i = 0; i < WS_THEMES.length; i++) { if (WS_THEMES[i][0].test(t)) return WS_THEMES[i][1]; }
    return 'General';
  }
  // Bucket the project's direct items into derived workstreams by theme
  // (first match wins, "General" last) and render each as a branch group.
  function renderDerivedWorkstreams(parentEl, refs) {
    if (!refs.length) return;
    var byWs = {};
    refs.forEach(function (r) { var w = workstreamOf(r.item); (byWs[w] = byWs[w] || []).push(r); });
    var names = Object.keys(byWs).sort(function (a, b) {
      if (a === 'General') return 1; if (b === 'General') return -1;
      return byWs[b].length - byWs[a].length;
    });
    names.forEach(function (w) {
      parentEl.appendChild(branchGroup(w, byWs[w], 'ws:' + w));
    });
  }

  // ---- branch groups (Task 5) -------------------------------------------
  // Per-branch disclosure state. Default: OPEN for branches with open work,
  // COLLAPSED for all-done branches (done work is muted and out of the way).
  function branchKey(key) { return drillProject + '::' + key; }
  function branchExpanded(key, dflt) {
    var v = branchState[branchKey(key)];
    return v === 'exp' ? true : v === 'col' ? false : dflt;
  }
  function toggleBranch(key, expand) {
    branchState[branchKey(key)] = expand ? 'exp' : 'col';
    saveObj('workstreams.branchState', branchState);
    renderTree();
  }
  // branchGroup — one branch row + its nested items. Branch rows carry: a
  // FOCUSABLE disclosure twisty (a real <button> with aria-expanded, so the
  // keyboard can expand/collapse), an open-count badge, and an amber
  // needs-you dot when anything inside waits on the operator (C6: amber is
  // the ONLY thing that pops). Done branches are collapsed by default;
  // explicitly expanding one reveals its items even while "show done" is off.
  function branchGroup(title, refs, key) {
    var open = refs.filter(function (r) { return !isComplete(r.item); });
    var needs = refs.some(function (r) { return isWaitingOnYou(r.item); });
    var allDone = refs.length > 0 && open.length === 0;
    var expanded = branchExpanded(key, !allDone);
    var grp = el('div', 'ws' + (allDone ? ' ws-done' : ''));
    var head = el('div', 'ws-head');
    var tw = el('button', 'twisty', expanded ? '▼' : '▶');
    tw.type = 'button';
    tw.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    tw.setAttribute('aria-label', (expanded ? 'collapse ' : 'expand ') + title);
    tw.addEventListener('click', function (e) { e.stopPropagation(); toggleBranch(key, !expanded); });
    head.appendChild(tw);
    head.appendChild(el('span', 'ws-title', title));
    if (needs) {
      var dot = el('span', 'needs-dot');
      dot.title = 'something in here needs you';
      head.appendChild(dot);
    }
    head.appendChild(el('span', 'ws-open-badge' + (open.length ? '' : ' all-done'),
      open.length ? open.length + ' open' : '✓ done'));
    head.addEventListener('click', function () { toggleBranch(key, !expanded); });
    grp.appendChild(head);
    if (expanded) {
      var kids = el('div', 'tree-kids ws-kids');
      var visible = refs.filter(function (r) { return allDone || visibleInTree(r); });
      visible.forEach(function (r) { kids.appendChild(treeItemRow(r, 3)); });
      if (!visible.length) {
        kids.appendChild(el('div', 'proj-empty',
          refs.length + ' done hidden — use “show done”'));
      }
      grp.appendChild(kids);
    }
    return grp;
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
    var needs = isWaitingOnYou(r.item);
    // C6 color migration: COLOR encodes STATUS, ICON encodes KIND. Rows are
    // neutral gray; the amber dot/edge appears ONLY on needs-you/blocked; done
    // gets the muted green check. Indent is supplied by the enclosing
    // .tree-kids guide rail; data-depth is retained for the geometry regression.
    var li = el('div', 'tree-item state-' + st + (needs ? ' needs-you' : ''));
    li.setAttribute('data-depth', String(depth));
    li.setAttribute('data-node', r.nodeId);
    li.setAttribute('data-item', r.itemId);
    if (selItem && selItem.nodeId === r.nodeId && selItem.itemId === r.itemId) li.classList.add('sel');
    var ki = el('span', 'ti-kind-ic', kindGlyph(r.item.kind));
    ki.title = (r.item.kind || 'action') + ' (' + kindLabel(r.item.kind) + ')';
    li.appendChild(ki);
    li.appendChild(el('span', 'ti-text', r.item.text || '(untitled)'));
    if (st === 'shipped') {
      var dn = el('span', 'ti-done-ic', '✓');
      dn.title = 'done';
      li.appendChild(dn);
    } else if (needs) {
      var nd = el('span', 'needs-dot');
      nd.title = st === 'blocked'
        ? ('blocked' + (r.item.block_reason ? ': ' + r.item.block_reason : ''))
        : 'waiting on you';
      li.appendChild(nd);
    }
    li.addEventListener('click', function () { openDetailModal(r.nodeId, r.itemId); });
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
  // linkifyDocs (UPGRADED 2026-06-11 — operator-directed): doc references in
  // details text are now CLICKABLE and open the doc IN-APP via the Docs
  // viewer (openDocInApp → /api/doc), per Misha: "that link needs to actually
  // work directly right here and open within the Workstreams UI". Matches
  // (a) docs/… repo paths and (b) any path-ish token ending in .md — incl.
  // bare coordination-repo doc names like REDESIGN-PRD-DRAFT-2026-06-10.md.
  // Tokens embedded in URLs (preceded by '/', ':' or a word char) stay plain
  // text. DOM is built with textContent / createTextNode ONLY — details text
  // is operator-trusted but never innerHTML'd, so no HTML injection path.
  // The (see branch: …) jump still degrades to a toast (no tree-canvas nav).
  // ============================================================================
  // openDocInApp — bridge to the Docs-viewer subsystem (assigned inside the
  // docsBrowser IIFE below; null when the drawer is absent from the build, in
  // which case links degrade to an explanatory toast).
  var openDocInApp = null;
  // .md path tokens first (so docs/reviews/x.md matches whole), then bare
  // docs/… paths (covers non-.md references under docs/).
  var DOC_REF_RE = /((?:[A-Za-z0-9._-]+\/)*[A-Za-z0-9._-]+\.md\b|docs\/[A-Za-z0-9._\/-]+)/g;
  var DOC_REF_TEST = /(?:[A-Za-z0-9._-]+\/)*[A-Za-z0-9._-]+\.md\b|docs\/[A-Za-z0-9._\/-]+/;
  function linkifyDocs(container, text, projectKey) {
    var s = String(text == null ? '' : text);
    var last = 0, m;
    DOC_REF_RE.lastIndex = 0;
    while ((m = DOC_REF_RE.exec(s)) !== null) {
      // mid-URL / mid-token guard: "https://github.com/x/foo.md" must not
      // linkify its tail; a real doc ref is preceded by whitespace/punctuation.
      var prev = m.index > 0 ? s.charAt(m.index - 1) : '';
      if (prev && /[A-Za-z0-9:\/]/.test(prev)) continue;
      // trim trailing sentence punctuation the docs/… char class can swallow
      var ref = m[0].replace(/[.,;:!?]+$/, '');
      if (!ref) continue;
      if (m.index > last) container.appendChild(document.createTextNode(s.slice(last, m.index)));
      var chip = el('button', 'det-link det-link-doc', ref);
      chip.type = 'button';
      chip.title = 'Open in the in-app docs viewer';
      chip.addEventListener('click', (function (r, pk) {
        return function (e) { e.stopPropagation(); openDocSmart(r, pk); };
      })(ref, projectKey));
      container.appendChild(chip);
      last = m.index + ref.length;
      DOC_REF_RE.lastIndex = last;
    }
    if (last < s.length) container.appendChild(document.createTextNode(s.slice(last)));
  }

  // openDocSmart — resolve a doc reference to a (project, path) pair the
  // server knows, then open it IN-APP. The reference rarely names its project
  // explicitly, so candidates are probed in order against /api/doc (read-only,
  // localhost, traversal-guarded server-side): an explicit
  // `<known-project>/<path>` prefix wins; pathed refs try the item's own
  // project, then the harness repo, then the coordination repo; BARE filenames
  // try the coordination repo first (that is where bare-named docs like
  // REDESIGN-PRD-DRAFT-….md live), then the item's project (root and docs/),
  // then the harness repo. First hit opens; all-miss → error toast.
  function openDocSmart(ref, projectKey) {
    if (!openDocInApp) { showToast('Docs viewer unavailable in this build.', 'err'); return; }
    var stripped = projectKey ? String(projectKey).replace(/^proj-/, '') : null;
    var hasSlash = ref.indexOf('/') !== -1;
    var base = hasSlash ? ref.split('/').pop() : ref;
    var cands = [];
    function add(p, rel) {
      if (!p || !rel) return;
      for (var i = 0; i < cands.length; i++) { if (cands[i][0] === p && cands[i][1] === rel) return; }
      cands.push([p, rel]);
    }
    if (hasSlash) {
      var seg0 = ref.split('/')[0], rest = ref.split('/').slice(1).join('/');
      if (rest && (seg0 === 'workstreams-coordination' || seg0 === 'neural-lace' || seg0 === stripped)) {
        add(seg0, rest);
      }
      add(stripped, ref);
      add('neural-lace', ref);
      add('workstreams-coordination', ref);
      add('workstreams-coordination', base);
    } else {
      add('workstreams-coordination', ref);
      add(stripped, ref);
      add(stripped, 'docs/' + ref);
      add('neural-lace', ref);
      add('neural-lace', 'docs/' + ref);
    }
    (function tryNext(i) {
      if (i >= cands.length) { showToast('Doc not found: ' + ref, 'err'); return; }
      var p = cands[i][0], rel = cands[i][1];
      fetch('/api/doc?project=' + encodeURIComponent(p) + '&path=' + encodeURIComponent(rel))
        .then(function (r) { return r.json(); })
        .then(function (j) {
          if (j && j.ok) { openDocInApp(p, rel); }
          else { tryNext(i + 1); }
        })
        .catch(function () { tryNext(i + 1); });
    })(0);
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

  // --- decision-context fence-grammar header (Task 9-full / OQ-2) -----------
  // When the item carries the decision-context `_category` marker (stamped by
  // decision-context-gate / replay), surface the Kind + urgency chips above
  // the actionable rows. `_category` gates ONLY this category-specific extra
  // (and the context-appropriate buttons in buildActionButtons) — it must
  // NEVER gate content rows (R5 render fix, 2026-06-09).
  function dcCategoryHeader(dcCat, de) {
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
    hdr.appendChild(lbl); hdr.appendChild(hv);
    return hdr;
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

    // --- decision-context fence-grammar fields (R5 render fix, 2026-06-09) ---
    // Fence-grammar content rows render WHENEVER the field is present in
    // `details` — they do NOT require `details._category`. The R1-enriched
    // onboarding items carry background / about / the_ask / why_asking /
    // why_assigned with no `_category` stamp; the old category-gated rendering
    // silently dropped those rows (the R4 root cause). `_category` now gates
    // ONLY category-specific extras: the Kind/urgency header chips here and
    // the context-appropriate buttons in buildActionButtons.
    var dcCat = de._category;
    if (dcCat) box.appendChild(dcCategoryHeader(dcCat, de));
    // about / background — fence-grammar context fields, distinct from legacy
    // `description` / `context` rows below. Render only when present.
    add(detailRow('About', de.about, projectKey));
    add(detailRow('Background', de.background, projectKey));

    // --- contract item 1: ACTIONABLE FIELDS FIRST ----------------------------
    add(detailRow('Instructions', de.instructions, projectKey));
    // Question-class fence fields (presence-based; `question` is shared by the
    // question AND decision categories, so it renders once, when present).
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
    // Decision-class fence field (presence-based).
    add(detailRow('Why not decide alone', de.why_not_decide_alone, projectKey));
    // Action-item-for-user fence fields (presence-based).
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
    // Autonomous-action fence fields (presence-based).
    add(detailRow('Action taken', de.action_taken, projectKey));
    add(detailRow('Reasoning', de.reasoning, projectKey));
    add(detailRow('Reversibility', de.reversibility, projectKey));
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
        if (DOC_REF_TEST.test(rs)) {
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
        // item 19 preserved + upgraded: docs/… AND bare *.md links open in-app.
        if (DOC_REF_TEST.test(s)) {
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

  // ====================================================================
  //  CONTEXT CARD + GATE (Task 8, 2026-06-11)
  // ====================================================================
  // The per-kind required-field templates + the incompleteness gate ALREADY
  // exist in the sole-normative Zod module (state/decision-context-schema.js:
  // ItemDetailsContentSchema / validateItemDetails / assembleItemDetails —
  // assembleItemDetails returns null when the details are not self-contained).
  // The browser cannot require() that module (zod, CommonJS, no build step),
  // so the SERVER runs the assembler at serve time and annotates each
  // operator-ask item with `context_state: 'complete' | 'incomplete'`
  // (server/server.js annotateContextState). The client CONSUMES that
  // annotation — there is deliberately NO parallel schema or second validator
  // here (I1). The cold-read bar: could the operator decide reading ONLY this
  // card, with zero memory of the chat? complete = yes; anything else gates.
  function contextGateBlocks(it) {
    if (!isMishaAsk(it)) return false;      // the gate covers decision / question / action-for-operator
    return it.context_state !== 'complete'; // server-annotated by the sole-normative assembler
  }
  // First N sentences of a paragraph — the inline-essentials clamp
  // (progressive disclosure: 1-2 sentence background inline, the full text
  // behind the "More context" expand).
  function firstSentences(text, n) {
    var s = String(text == null ? '' : text).trim();
    if (!s) return '';
    var parts = s.match(/[^.!?]+[.!?]+(\s|$)/g);
    if (!parts || parts.length <= n) return s;
    var out = parts.slice(0, n).join('').trim();
    return out.length < s.length ? out + ' …' : out;
  }
  function optionTitle(op, ix) {
    if (typeof op === 'string') return op;
    var t = '';
    if (op.key) t += '[' + op.key + '] ';
    t += (op.name || op.label || ('option ' + (ix + 1)));
    return t;
  }
  function optionKeyOf(op, ix) {
    if (typeof op === 'string') return op;
    return op.key || op.name || op.label || ('option ' + (ix + 1));
  }
  // renderEssentialsCard — the progressive-disclosure context card for a
  // context-COMPLETE operator-ask. Essentials inline (short background, the
  // ask, ONE line per option with its meaning + tradeoff, the recommendation,
  // the reply phrasing + per-option Choose affordances); the FULL existing
  // detail renderer (renderItemDetails — about / why-not-decide-alone / links
  // / references / envelope fields) sits behind a native "More context"
  // disclosure. Re-style of the existing card, not a re-template (I1).
  function renderEssentialsCard(it, nodeId, itemId, projectKey) {
    var de = it.details || {};
    var card = el('div', 'dc-essentials');
    var bg = de.background || de.about;
    if (bg) card.appendChild(el('div', 'dc-bg', firstSentences(bg, 2)));
    var ask = de.question || de.the_ask;
    if (ask) card.appendChild(el('div', 'dc-ask', ask));
    var isDecision = it.kind === 'decision' || de._category === 'decision';
    if (Array.isArray(de.options) && de.options.length) {
      var ol = el('div', 'dc-opts');
      de.options.forEach(function (op, ix) {
        var line = el('div', 'dc-opt-line');
        var main = el('div', 'dc-opt-main');
        main.appendChild(el('span', 'dc-opt-name', optionTitle(op, ix)));
        if (typeof op === 'object') {
          var meaning = op.what_it_does || op.pros || '';
          var tradeoff = op.risk || op.cons || '';
          var bits = [];
          if (meaning) bits.push(meaning);
          if (tradeoff) bits.push('risk: ' + tradeoff);
          if (op.cost) bits.push('cost: ' + op.cost);
          if (bits.length) main.appendChild(el('span', 'dc-opt-meta', ' — ' + bits.join(' · ')));
        }
        line.appendChild(main);
        // Reply affordance: choose THIS option (replaces the retired native
        // number-entry prompt). Only on still-open decisions.
        if (isDecision && !it.checked) {
          var pick = el('button', 'dc-opt-choose', 'Choose');
          pick.type = 'button';
          pick.setAttribute('aria-label', 'choose ' + optionTitle(op, ix));
          pick.addEventListener('click', function (e) {
            e.stopPropagation();
            var k = optionKeyOf(op, ix);
            recordDecision(nodeId, itemId, it, k, 'Chose option ' + k);
          });
          line.appendChild(pick);
        }
        ol.appendChild(line);
      });
      card.appendChild(ol);
    }
    var rec = de.recommendation;
    if (rec != null) {
      var recTxt = (typeof rec === 'object')
        ? ((rec.option_key ? '[' + rec.option_key + '] ' : '') + firstSentences(rec.reasoning || '', 1))
        : firstSentences(String(rec), 1);
      if (recTxt) card.appendChild(el('div', 'dc-rec-line', '→ recommended: ' + recTxt));
    }
    if (de.reply_with) {
      var rw = el('div', 'dc-reply-line');
      rw.appendChild(el('span', 'dc-reply-k', 'Reply with '));
      var code = el('code', 'det-reply-with-box');
      code.textContent = String(de.reply_with);
      rw.appendChild(code);
      card.appendChild(rw);
    }
    // Full reasoning / links / envelope — behind the expand. Native <details>
    // disclosure: keyboard-focusable summary, no new Esc/overlay handler (I5).
    var more = document.createElement('details');
    more.className = 'dc-more';
    var sum = document.createElement('summary');
    sum.textContent = 'More context';
    more.appendChild(sum);
    more.appendChild(renderItemDetails(de, projectKey, it.text));
    card.appendChild(more);
    return card;
  }
  // renderIncompletePanel — the gated state (I2). A contextless operator-ask
  // is NEVER presented as an actionable choice: this panel replaces the card
  // AND buildActionButtons suppresses the resolving buttons entirely.
  function renderIncompletePanel(it, projectKey) {
    var panel = el('div', 'dc-incomplete-panel');
    panel.appendChild(el('div', 'dc-incomplete-h', 'context incomplete — needs enrichment'));
    var kindWord = (it.details && it.details._category)
      ? String(it.details._category).replace(/_/g, ' ') : (it.kind || 'item');
    panel.appendChild(el('div', 'dc-incomplete-b',
      'This ' + kindWord + ' lacks the embedded context (background · what each option '
      + 'means and trades off · a recommendation · how to reply) needed to decide cold. '
      + 'It is not actionable until the AI enriches it — resolution buttons are disabled.'));
    var de = it.details;
    if (de && typeof de === 'object' && Object.keys(de).length) {
      var more = document.createElement('details');
      more.className = 'dc-more';
      var sum = document.createElement('summary');
      sum.textContent = 'Show what detail exists';
      more.appendChild(sum);
      more.appendChild(renderItemDetails(de, projectKey, it.text));
      panel.appendChild(more);
    }
    return panel;
  }
  // openInlineForm — the in-surface reply form (C5: every reply / resolution
  // records via an inline form INSIDE the card — native prompt() dialogs are
  // retired). One form at a time; Cancel removes it; no new global key or
  // scrim handler is registered (I5 — the overlay stack is Task 10's; this
  // lives entirely inside the existing modal).
  function openInlineForm(container, opts) {
    var prev = container.querySelector('.dm-form');
    if (prev) prev.remove();
    var wrap = el('div', 'dm-form');
    var fieldId = uid('f');
    var lbl = el('label', 'dm-form-label', opts.label);
    lbl.setAttribute('for', fieldId);
    wrap.appendChild(lbl);
    var input = opts.multiline ? el('textarea', 'dm-form-input') : el('input', 'dm-form-input');
    if (!opts.multiline) input.type = 'text';
    input.id = fieldId;
    if (opts.placeholder) input.placeholder = opts.placeholder;
    wrap.appendChild(input);
    var row = el('div', 'dm-form-row');
    var go = el('button', 'btn-go', opts.submitLabel);
    go.type = 'button';
    go.addEventListener('click', function () {
      var v = String(input.value || '').trim();
      if (opts.required && !v) {
        showToast(opts.requiredMsg || 'Type something first.', 'err');
        input.focus();
        return;
      }
      opts.onSubmit(v);
      wrap.remove();
    });
    var cancel = el('button', 'btn-neutral outline', 'Cancel');
    cancel.type = 'button';
    cancel.addEventListener('click', function () { wrap.remove(); });
    row.appendChild(go);
    row.appendChild(cancel);
    wrap.appendChild(row);
    container.appendChild(wrap);
    if (!opts.multiline) {
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); go.click(); }
      });
    }
    input.focus();
    return wrap;
  }

  // ====================================================================
  //  ITEM DETAIL MODAL (Phase D, 2026-06-09)
  // ====================================================================
  // openDetailModal — selection handler (wire-check target). Opens a dismissible
  // MODAL OVERLAY (not a list-replacing card — the prior detailCard regression
  // Misha repeatedly flagged). The filtered list stays put behind the scrim;
  // click-scrim / Esc / ✕ closes. Renders the FULL self-contained context (the
  // Phase-C `details` payload: Background / the ask / Options / Recommendation /
  // Links via renderItemDetails) plus context-appropriate action buttons wired
  // to the answered / action-done / action-responded / item-details-set
  // lifecycle events via POST /api/event.
  function openDetailModal(nodeId, itemId) {
    var host = byId(nodeId);
    var it = host && (host.items || []).find(function (x) { return x.item_id === itemId; });
    if (!it) { closeDetailModal(); return; }
    selItem = { nodeId: nodeId, itemId: itemId };
    syncTreeSelection();                          // highlight matching tree row
    var st = itemState(it);
    var cat = (it.details && it.details._category) || null;

    dmTitle.textContent = it.text || '(untitled)';
    clear(dmBody);
    clear(dmActions);

    // --- metadata grid ---------------------------------------------------
    var meta = el('div', 'dc-meta');
    meta.appendChild(dcRow('Project', projectTitle(byId(rootProjectOf(nodeId)) || { title: nodeId })));
    var tier = (host && host.tier) ? host.tier : inferTier(nodeId);
    meta.appendChild(dcRow('Kind', it.kind + (cat && cat !== it.kind ? ' · ' + cat.replace(/_/g, ' ') : '')));
    meta.appendChild(dcRow('Tier', tier));
    // Phase D — surface the deploy disposition so the operator sees, per item,
    // whether the effort reached production.
    var stLabel = stateIcon(st) + ' ' + st;
    if (st === 'shipped') stLabel += isDeployed(it) ? ' · deployed' : ' · NOT deployed';
    meta.appendChild(dcRow('State', stLabel));
    if (it.responded) meta.appendChild(dcRow('Your response', it.responded.text));
    if (it.ship_evidence) meta.appendChild(dcRow('Ship evidence', it.ship_evidence));
    if (it.deploy_evidence) meta.appendChild(dcRow('Deploy evidence', it.deploy_evidence));
    if (it.block_reason) meta.appendChild(dcRow('Blocked', it.block_reason));
    if (host && host.opened_at) meta.appendChild(dcRow('Last activity', new Date(host.opened_at).toLocaleString()));
    dmBody.appendChild(meta);

    // --- the CONTEXT CARD (Task 8) -----------------------------------------
    // Routed through the context-completeness gate (server-annotated by the
    // sole-normative assembler — see contextGateBlocks):
    //   gated ask        → "context incomplete — needs enrichment", never a
    //                      bare choice (the partial detail stays reachable
    //                      behind a disclosure);
    //   complete ask     → progressive-disclosure essentials card (short
    //                      background · the ask · one line per option with
    //                      meaning+tradeoff · recommendation · reply
    //                      affordances) with the FULL existing renderer
    //                      behind "More context";
    //   everything else  → the existing full detail render, unchanged.
    var projKey = rootProjectOf(nodeId);
    if (contextGateBlocks(it)) {
      dmBody.appendChild(el('div', 'dc-sec-h', 'Context'));
      dmBody.appendChild(renderIncompletePanel(it, projKey));
    } else if (isMishaAsk(it) && it.context_state === 'complete') {
      dmBody.appendChild(el('div', 'dc-sec-h', 'Context'));
      dmBody.appendChild(renderEssentialsCard(it, nodeId, itemId, projKey));
    } else if (it.details && typeof it.details === 'object') {
      dmBody.appendChild(el('div', 'dc-sec-h', 'Context'));
      dmBody.appendChild(renderItemDetails(it.details, projKey, it.text));
    }

    // --- provenance ------------------------------------------------------
    var prov = collectProvenance(nodeId, itemId);
    if (prov.length) {
      dmBody.appendChild(el('div', 'dc-sec-h', 'Provenance'));
      var pl = el('div', 'dc-prov');
      prov.forEach(function (p) {
        var pr = el('div', 'dc-prov-row');
        pr.appendChild(el('span', 'dc-prov-l', p.label));
        pr.appendChild(el('span', 'dc-prov-v', p.value));
        pl.appendChild(pr);
      });
      dmBody.appendChild(pl);
    }

    // --- sub-task rollup -------------------------------------------------
    var subs = collectSubtasks(nodeId, itemId);
    if (subs.length) {
      dmBody.appendChild(el('div', 'dc-sec-h', 'Sub-tasks (' + subs.length + ')'));
      var sl = el('div', 'dc-subs');
      subs.forEach(function (s) {
        var sr = el('div', 'dc-sub-row');
        sr.appendChild(el('span', 'dc-sub-ck', s.checked ? '✓' : '⏳'));
        sr.appendChild(el('span', 'dc-sub-t', s.text));
        sl.appendChild(sr);
      });
      dmBody.appendChild(sl);
    }

    // --- context-appropriate ACTION BUTTONS ------------------------------
    buildActionButtons(dmActions, host, it, nodeId, itemId, st, cat);

    // show the overlay
    detailScrim.hidden = false;
    detailModal.hidden = false;
    if (dmClose && dmClose.focus) { try { dmClose.focus(); } catch (_) {} }
  }

  // closeDetailModal — dismiss the overlay and clear the selection. Safe to call
  // when nothing is open (idempotent).
  function closeDetailModal() {
    detailModal.hidden = true;
    detailScrim.hidden = true;
    selItem = null;
    syncTreeSelection();
  }

  // buildActionButtons — the context-appropriate affordances. The buttons differ
  // by the item's kind / decision-context category, but EVERY presentable item
  // gets a "Respond / ask a clarifying question" affordance (Misha's
  // requirement 3).
  //
  // Task 8 (2026-06-11):
  //   C5 — every reply / resolution records via an IN-SURFACE inline form
  //        (openInlineForm) — the native prompt() dialogs are retired. The
  //        explicit option choice lives as per-option "Choose" buttons on the
  //        essentials card, replacing the old number-entry dialog.
  //   I2 — when the context gate flags an operator-ask incomplete, the
  //        resolving buttons (Approve / Choose / Decline / Answer / Mark done)
  //        AND the lifecycle cluster are SUPPRESSED entirely — the only
  //        affordance is the respond channel (how the operator requests
  //        enrichment). A contextless choice can never be acted on blind.
  //
  //  decision            → Approve recommendation / Decline (per-option Choose
  //                        lives on the essentials card; each resolution emits
  //                        `answered` + records the choice via item-details-set)
  //  question            → Answer  (emits `answered` + records the answer text)
  //  action_item_for_user→ Mark done (emits `action-done`) / Decline
  //  action (generic)    → Mark done (emits `action-done`)
  //  ALWAYS              → Respond with details (emits `action-responded` — the
  //                        item stays open/awaiting but carries your note) and,
  //                        when not gated, the lifecycle controls (Block /
  //                        Commit / Mark shipped / Mark deployed) so any work
  //                        item can be tracked to DEPLOYED from the modal.
  function buildActionButtons(container, host, it, nodeId, itemId, st, cat) {
    var kind = it.kind;

    // The respond channel — built first because it is the ONE affordance the
    // gated state keeps (the enrichment-request path; action-responded keeps
    // the item open, it never resolves a choice).
    function appendRespond(label) {
      var respond = el('button', 'btn-info outline', label);
      respond.title = 'Reply with details or ask a clarifying question — keeps the item open (emits action-responded)';
      respond.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Respond with details, or ask a clarifying question',
          multiline: true, required: true,
          requiredMsg: 'Type something first.',
          submitLabel: 'Send response',
          onSubmit: function (v) {
            post({ type: 'action-responded', node_id: nodeId, item_id: itemId,
                   response_text: v }, 'Response recorded')
              .then(function () { /* stays open — re-render shows the response */ });
          },
        });
      });
      container.appendChild(respond);
    }

    // --- I2: the context-incomplete gate suppresses ALL resolving/lifecycle
    //     buttons. Only the needs-enrichment note + the respond channel render.
    if (contextGateBlocks(it)) {
      container.appendChild(el('span', 'dm-gate-note',
        'context incomplete — resolution disabled until this item is enriched'));
      appendRespond('Respond / request enrichment');
      return;
    }

    // --- the "what does the user need to DECIDE/DO" cluster (context-appropriate)
    if (kind === 'decision') {
      var rec = it.details && it.details.recommendation;
      var recKey = rec && (typeof rec === 'object' ? rec.option_key : null);
      var approve = el('button', 'btn-go', recKey ? ('Approve recommendation (' + recKey + ')') : 'Approve');
      approve.title = 'Record your decision and resolve this item (emits answered)';
      approve.addEventListener('click', function () {
        var chosen = recKey || 'approved';
        recordDecision(nodeId, itemId, it, chosen, 'Approved' + (recKey ? ' option ' + recKey : ''));
      });
      container.appendChild(approve);
      // Choosing a specific option happens on the essentials card — one
      // labeled "Choose" button per option line (renderEssentialsCard).

      var decline = el('button', 'btn-warn outline', 'Decline');
      decline.title = 'Reject this decision and resolve it (emits answered)';
      decline.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Why decline? (optional)',
          multiline: true, required: false,
          submitLabel: 'Confirm decline',
          onSubmit: function (v) {
            recordDecision(nodeId, itemId, it, 'declined', 'Declined' + (v ? ': ' + v : ''));
          },
        });
      });
      container.appendChild(decline);

    } else if (kind === 'question') {
      var answer = el('button', 'btn-go', 'Answer');
      answer.title = 'Provide your answer and resolve this question (emits answered)';
      answer.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Your answer',
          multiline: true, required: true,
          requiredMsg: 'Enter an answer first.',
          submitLabel: 'Submit answer',
          onSubmit: function (v) { recordDecision(nodeId, itemId, it, null, v); },
        });
      });
      container.appendChild(answer);

    } else {                                    // action (incl. action_item_for_user)
      var done = el('button', 'btn-go', 'Mark done');
      done.title = 'Mark this action complete (emits action-done)';
      done.addEventListener('click', function () {
        post({ type: 'action-done', node_id: nodeId, item_id: itemId }, 'Marked done')
          .then(closeDetailModal);
      });
      container.appendChild(done);
      if (cat === 'action_item_for_user') {
        var declineA = el('button', 'btn-warn outline', 'Decline');
        declineA.title = 'Decline this ask, with a reason (recorded as your response)';
        declineA.addEventListener('click', function () {
          openInlineForm(container, {
            label: 'Why decline this ask?',
            multiline: true, required: false,
            submitLabel: 'Confirm decline',
            onSubmit: function (v) {
              post({ type: 'action-responded', node_id: nodeId, item_id: itemId,
                     response_text: 'Declined: ' + (v || '(no reason given)') }, 'Declined');
            },
          });
        });
        container.appendChild(declineA);
      }
    }

    // --- ALWAYS (when not gated): respond-with-details ---------------------
    appendRespond('Respond / ask a question');

    // --- lifecycle controls: track ANY work item to DEPLOYED -------------
    var lifeSep = el('span', 'dm-act-sep', '·');
    container.appendChild(lifeSep);

    if (st !== 'blocked') {
      var block = el('button', 'btn-warn outline', 'Block');
      block.title = 'Mark this work blocked on a dependency / missing input';
      block.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Why is this blocked?',
          multiline: false, required: false,
          submitLabel: 'Mark blocked',
          onSubmit: function (v) {
            post({ type: 'item-blocked', node_id: nodeId, item_id: itemId, reason: v }, 'Marked blocked')
              .then(closeDetailModal);
          },
        });
      });
      container.appendChild(block);
    }
    if (st === 'proposed' || st === 'in-flight') {
      var commit = el('button', 'btn-neutral outline', 'Commit');
      commit.title = 'Park as committed work (not started yet)';
      commit.addEventListener('click', function () {
        post({ type: 'item-committed', node_id: nodeId, item_id: itemId }, 'Committed')
          .then(closeDetailModal);
      });
      container.appendChild(commit);
    }
    if (st !== 'shipped') {
      var ship = el('button', 'btn-neutral outline', 'Mark shipped');
      ship.title = 'Merged / shipped (not yet deployed)';
      ship.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Ship evidence (commit SHA / PR URL) — optional',
          multiline: false, required: false,
          submitLabel: 'Mark shipped',
          onSubmit: function (v) {
            var payload = { type: 'item-shipped', node_id: nodeId, item_id: itemId };
            if (v) payload.evidence = v;
            post(payload, 'Marked shipped').then(closeDetailModal);
          },
        });
      });
      container.appendChild(ship);
    }
    if (!isDeployed(it)) {
      var deploy = el('button', 'btn-go', 'Mark deployed');
      deploy.title = 'Live in production — the effort reached deployed';
      deploy.addEventListener('click', function () {
        openInlineForm(container, {
          label: 'Deploy evidence (prod URL / deploy SHA) — optional',
          multiline: false, required: false,
          submitLabel: 'Mark deployed',
          onSubmit: function (v) {
            var payload = { type: 'item-deployed', node_id: nodeId, item_id: itemId };
            if (v) payload.evidence = v;
            post(payload, 'Marked deployed').then(closeDetailModal);
          },
        });
      });
      container.appendChild(deploy);
    }
  }

  // recordDecision — resolve a decision/question by emitting `answered` AND, when
  // a chosen option / answer is supplied, an `item-details-set` that records the
  // chosen option key + the operator's note onto it.details so the choice is
  // auditable in the tree (per requirement 3: emit answered / item-details-set
  // via the state.js facade + /api/event). `answered` is the correct lifecycle
  // event for decision/question kinds (action-done is rejected on them by the
  // reducer). Closes the modal on success.
  function recordDecision(nodeId, itemId, it, chosenKey, note) {
    // Merge the resolution into the existing details payload (LWW on it.details).
    var base = (it.details && typeof it.details === 'object') ? it.details : {};
    var merged = Object.assign({}, base, {
      _resolution: {
        chosen: chosenKey || null,
        note: note || null,
        decided_at: new Date().toISOString(),
        by: 'gui',
      },
    });
    post({ type: 'answered', node_id: nodeId, item_id: itemId }, 'Recorded')
      .then(function () {
        // best-effort: record the chosen option / answer text. A failure here
        // does not un-resolve the item; the answered event already landed.
        return post({ type: 'item-details-set', node_id: nodeId, item_id: itemId, details: merged });
      })
      .then(closeDetailModal)
      .catch(function () { /* post() already toasted the error */ });
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
    // Phase D — the list ALWAYS renders (behind the modal); when an item is
    // selected the modal re-renders on top with the latest state. This is the
    // overlay model — the list is never hidden by the detail view.
    renderFilteredItems(activeFilter);
    if (selItem) openDetailModal(selItem.nodeId, selItem.itemId);
    updateChipCounts();
  }

  // ---- wiring ----------------------------------------------------------
  filterBar.addEventListener('click', function (e) {
    var chip = e.target.closest('.chip');
    if (chip) setActiveFilter(chip.getAttribute('data-filter'));
  });
  // Detail-modal dismissal: ✕ button, click-scrim, Esc. Esc here is gated on
  // the detail modal being open AND in front of the docs modal/drawer (the docs
  // subsystem has its own Esc handler that returns early when its modal is open;
  // this one fires only when the detail modal is the topmost overlay).
  if (dmClose) dmClose.addEventListener('click', closeDetailModal);
  if (detailScrim) detailScrim.addEventListener('click', closeDetailModal);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !detailModal.hidden) {
      // Doc-link layering (2026-06-11): when the in-app doc viewer is stacked
      // on top (opened from a doc link inside this modal), let ITS Esc handler
      // close it and keep the detail modal open underneath. Second Esc then
      // closes the detail modal.
      var dv = $('docModal');
      if (dv && !dv.hidden) return;
      closeDetailModal();
    }
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
    // Task 7: the header capture goes through the SAME add path as the backlog
    // surface's "+ add" input, so every captured item is equally editable /
    // removable / promotable (the old backlog-added-only path created
    // promote-only legacy entries).
    addBacklogItem(text, { priority: blPriority.value, context: blContext.value }, function () {
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

    // Expose the in-GUI viewer to the item-detail modal's doc links (2026-06-11):
    // linkifyDocs/openDocSmart open docs IN-APP through this bridge.
    openDocInApp = openDocModal;

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
  // ---- stale-tab auto-reload (Phase R2, 2026-06-09) ---------------------
  // A long-lived tab keeps DATA fresh via SSE while its CODE stays frozen at
  // tab-load time — the operator kept seeing the pre-Phase-D right-panel
  // detail for hours after the server already served the modal code (server
  // `no-cache` headers only matter on a reload that never happens). The
  // server's /api/health now carries ui_build_ms (max mtime of index.html /
  // app.js / app.css); when it advances past the stamp this tab booted with,
  // reload once so the tab always runs the code the server is serving.
  // Old servers without the field: ui_build_ms is undefined, no-op.
  var uiBuildSeen = null;
  function checkUiBuild(h) {
    if (!h || typeof h.ui_build_ms !== 'number') return;
    if (uiBuildSeen === null) { uiBuildSeen = h.ui_build_ms; return; }
    if (h.ui_build_ms > uiBuildSeen) { location.reload(); }
  }
  function pollHealth() {
    if (!freshnessEl) return;
    fetch('/api/health', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (h) {
      checkUiBuild(h);
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
