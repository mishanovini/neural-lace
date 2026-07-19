'use strict';
/* requests.js — the Requests ledger view (cockpit-roadmap-redesign Task 5,
 * "Requests ledger view"). Renders GET /api/requests
 * (server/requests-routes.js — the pinned payload contract lives in that
 * file's header). Registers itself into the navigation shell
 * (window.WorkstreamsShell, defined by app.js) as the 'requests' view
 * adapter, REPLACING app.js's interim placeholder (last registerView() call
 * for a given name wins — app.js's own header comment on registerView
 * documents this).
 *
 * A NEW, independent file (mirrors task 3's roadmap.js precedent): this view
 * does NOT touch asks.js — the pre-existing ask-tree (sessions, peers,
 * lifecycle done/dismiss/merge affordances) is untouched, its own tests
 * (the T13 and PV series in cockpit.selftest.js) stay green unmodified, and it remains
 * reachable below this view inside the Requests tab (a documented, scoped
 * decision — see this task's build report; consolidating/removing it is
 * out of this task's scope, follow-up filed for task 8's UI-polish pass).
 * This module mounts its own wrapper as the FIRST child of
 * #tabRequestsPanel at runtime (no static markup needed beyond the one
 * <script> tag that loads this file — see the shell fragment).
 *
 * Laws carried here (plan task 5, binding):
 *  - Timeline anatomy (I6): collapsed = title + one-line CURRENT state
 *    ("became → <plan>" or "open, amended <age>"); expanded = OLDEST-FIRST
 *    chronology, origin pinned first, every event dated, "became →" as the
 *    terminal event on promotion; amendment rows carry the task-2 detach
 *    affordance (undo-window-adjacent pattern — see below for the honest
 *    limitation this build ships with).
 *  - "became →" links use #roadmap/<id> addressing (shell rules apply:
 *    landed state, return, miss behavior) — close-on-promote is this view's
 *    exit verb.
 *  - Findability (C8): a filter box (substring over title + distilled
 *    intent + verbatim origin); closed requests default-collapsed under age
 *    groups ("this week / this month / older") that search reaches inside.
 *  - Recency (I1): every row carries "last amended <age>" (or an honest
 *    "registered <age>, never amended" fallback).
 *  - Four UI states (C4): loading / error+Retry / FILTERED-empty (names the
 *    filter + hidden count + one-click clear) / TRUE-empty (explains
 *    auto-capture, no setup ask).
 *  - A11y (C9): nested <details>/<summary> disclosure; title editing = the
 *    todo.js/roadmap.js edit-button + Escape + focus-return pattern; every
 *    status signal is text + color; interactive chips are real <button>s;
 *    aria-live feedback on every write.
 *  - Refresh model (C7, task-3 law extended to this view): 30s poll,
 *    STATE-PRESERVING re-render (open-details set, scroll, focus,
 *    uncommitted title edit survive a tick); failed refresh labels the pane
 *    "derived <age> — STALE", never silent staleness.
 *
 * HONEST LIMITATION (documented, not routed around): the amendment "detach"
 * affordance calls POST /api/requests/amend/detach, which delegates to a
 * NEW ask-registry.sh verb (detach-amendment) this task PINS but does not
 * implement — task 2 (in flight) owns ask-registry.sh. Until that verb
 * ships, a click returns a NAMED error surfaced in the row's aria-live
 * feedback, never a silent success (this task's dispatch mandate). No
 * amendment_candidate records exist in production today either (task 2's
 * capture/classification lane is also in flight) — the timeline anatomy
 * and detach affordance are wired and selftest-proven against forward-
 * compatible fixture data (server/requests-routes.selftest.js S7/S9), ready
 * the moment task 2 lands, per A2's stated honest limit ("amendment
 * detection is best-effort, not a guarantee").
 */
(function () {
  var panel = document.getElementById('tabRequestsPanel');
  if (!panel) return; // view container absent on this page — no-op

  function $(id) { return document.getElementById(id); }
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
  var AGE_GROUP_ORDER = ['this week', 'this month', 'older'];

  // ============================================================
  // mount — build the ledger's own DOM subtree, inserted as the FIRST child
  // of #tabRequestsPanel (before the existing ask-tree/sidebar layout).
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

  var section = el('section', 'pane requests-ledger-section', '');
  section.id = 'requestsLedgerSection';
  section.setAttribute('aria-label', 'requests ledger');

  var toolbar = el('div', 'requests-ledger-toolbar');
  var filterInput = document.createElement('input');
  filterInput.type = 'text';
  filterInput.id = 'requestsFilter';
  filterInput.placeholder = 'filter requests (title, intent, or verbatim origin)…';
  filterInput.setAttribute('aria-label', 'filter requests (matches title, distilled intent, and verbatim origin)');
  toolbar.appendChild(filterInput);
  var ageLabel = el('span', 'pane-age', '—');
  ageLabel.setAttribute('data-age-for', 'requests');
  toolbar.appendChild(ageLabel);
  section.appendChild(toolbar);

  var body = el('div', 'pane-body requests-ledger-body');
  body.id = 'requestsLedgerBody';
  section.appendChild(body);

  panel.insertBefore(section, panel.firstChild);

  // ============================================================
  // state
  // ============================================================
  var openSet = {};        // request id -> details-open bool
  var groupOpenSet = {};   // age-group name -> details-open bool
  var lastPayload = null;
  var lastFetchFailed = false;
  var lastDerivedAt = null;
  var landingId = null;
  var whenLoadedQueue = [];

  function setAgeLabel() {
    ageLabel.textContent = 'derived ' + formatAge(lastDerivedAt) + (lastFetchFailed ? ' — STALE (last refresh failed)' : '');
    ageLabel.classList.toggle('stale', lastFetchFailed);
  }

  // ============================================================
  // filtering (C8 — findability: title + distilled intent + verbatim origin)
  // ============================================================
  function filterText() { return (filterInput.value || '').trim().toLowerCase(); }
  function itemMatches(item, q) {
    if (!q) return true;
    if ((item.title || '').toLowerCase().indexOf(q) !== -1) return true;
    if ((item.distilled_intent || '').toLowerCase().indexOf(q) !== -1) return true;
    if ((item.verbatim_ref || '').toLowerCase().indexOf(q) !== -1) return true;
    return false;
  }

  // ============================================================
  // age grouping for CLOSED requests ("this week / this month / older" —
  // C8, adopted from the proposal; search reaches inside via forced-open).
  // ============================================================
  function ageGroupOf(item) {
    var ts = item.closed_at || item.created_ts;
    if (!ts) return 'older';
    var ms = Date.now() - Date.parse(ts);
    if (isNaN(ms) || ms < 0) return 'this week';
    var days = ms / 86400000;
    if (days <= 7) return 'this week';
    if (days <= 30) return 'this month';
    return 'older';
  }

  // ============================================================
  // per-item current-state one-liner (collapsed anatomy — I6)
  // ============================================================
  function currentStateText(item) {
    if (item.closed_reason === 'promoted') return 'became → ' + (item.became && item.became.plan_slug || 'a plan');
    if (item.closed_reason === 'done') return 'done';
    if (item.closed_reason === 'dismissed') return 'dismissed';
    if (item.closed_reason === 'merged') return 'merged into ' + (item.merged_into || 'another request');
    if (item.last_amended_ts) return 'open, amended ' + formatAge(item.last_amended_ts);
    return 'open, registered ' + formatAge(item.created_ts);
  }

  function recencyText(item) {
    return item.last_amended_ts ? 'last amended ' + formatAge(item.last_amended_ts)
      : 'no amendments yet · registered ' + formatAge(item.created_ts);
  }

  // ============================================================
  // small helpers reused across rows (duplicated locally per this codebase's
  // established small-helper convention — asks.js/roadmap.js each carry
  // their own copy rather than sharing a module system)
  // ============================================================
  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () {});
    }
  }
  function makeCopyBtn(text, label) {
    var b = btn('ghost small rl-copy-btn', label || 'copy', function (e) {
      e.stopPropagation();
      copyToClipboard(text);
      var orig = b.textContent;
      b.textContent = 'copied';
      setTimeout(function () { b.textContent = orig; }, 1200);
    });
    b.title = 'copy "' + text + '" to clipboard';
    return b;
  }

  // ============================================================
  // title editor — the todo.js/roadmap.js pattern: explicit Edit button,
  // Escape cancels, focus returns (C9/A3 — ALWAYS operator-editable).
  // ============================================================
  function openTitleEditor(row, item, editBtn, say) {
    if (row.querySelector('.rl-title-input')) return;
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'rl-title-input';
    input.value = item.title;
    input.setAttribute('aria-label', 'edit title for "' + item.title + '"');
    var saveBtn = btn('btn-go small', 'Save', null);
    var cancelBtn = btn('ghost small', 'Cancel', null);
    editBtn.hidden = true;
    row.appendChild(input);
    row.appendChild(saveBtn);
    row.appendChild(cancelBtn);
    input.focus();
    input.select();
    function close() {
      input.remove(); saveBtn.remove(); cancelBtn.remove();
      editBtn.hidden = false;
      editBtn.focus();
    }
    cancelBtn.addEventListener('click', close);
    input.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
    saveBtn.addEventListener('click', function () {
      var t = input.value.trim();
      if (!t) { say('Title cannot be empty.', true); return; }
      saveBtn.disabled = true;
      fetch('/api/requests/title', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ask_id: item.id, title: t }),
      }).then(function (r) { return r.json(); }).then(function (j) {
        if (j && j.ok) { say('Title saved.', false); close(); load(); }
        else { saveBtn.disabled = false; say((j && j.error) || 'Could not save the title.', true); }
      }).catch(function (e) { saveBtn.disabled = false; say('Could not save the title: ' + e, true); });
    });
  }

  // ============================================================
  // amendment detach — I6 correction affordance. See the file header's
  // HONEST LIMITATION note: the underlying verb doesn't exist yet, so a
  // click today returns a named error, never a silent success.
  // ============================================================
  function detachAmendment(askId, eventTs, say, onDone) {
    fetch('/api/requests/amend/detach', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ask_id: askId, event_ts: eventTs }),
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.ok) { say('Detached.', false); if (onDone) onDone(); load(); }
      else { say((j && j.error) || 'Could not detach this amendment.', true); }
    }).catch(function (e) { say('Could not detach this amendment: ' + e, true); });
  }

  // ============================================================
  // timeline rendering (I6 — oldest-first, origin pinned first, "became →"
  // as the terminal event)
  // ============================================================
  function timelineNode(item) {
    var wrap = el('div', 'rl-timeline');
    var list = document.createElement('ol');
    list.className = 'rl-timeline-list';
    (item.timeline || []).forEach(function (ev) {
      var li = document.createElement('li');
      li.className = 'rl-timeline-event rl-event-' + ev.type;
      var textSpan = el('span', 'rl-event-text', ev.text);
      li.appendChild(textSpan);
      var ageSpan = el('span', 'rl-event-age', formatAge(ev.ts));
      li.appendChild(ageSpan);
      if (ev.type === 'promoted' && shell) {
        li.appendChild(btn('ghost small rl-became-link', 'open on the Roadmap', function () {
          shell.navigate('#roadmap/' + item.id);
        }));
      }
      if (ev.detachable) {
        var feedback = el('span', 'rl-event-feedback', '');
        feedback.setAttribute('aria-live', 'polite');
        var detachBtn = btn('ghost small rl-detach-btn', 'Detach (not an amendment)', function () {
          detachBtn.disabled = true;
          detachAmendment(item.id, ev.ts, function (text, isErr) {
            feedback.textContent = text;
            feedback.className = 'rl-event-feedback' + (isErr ? ' rl-feedback-err' : ' rl-feedback-ok');
            if (isErr) detachBtn.disabled = false;
          });
        });
        detachBtn.title = 'marks this candidate as not-an-amendment (feeds the classifier) — undo-window pattern (I6)';
        li.appendChild(detachBtn);
        li.appendChild(feedback);
      }
      list.appendChild(li);
    });
    wrap.appendChild(list);
    return wrap;
  }

  // ============================================================
  // per-row drilldown (expanded anatomy)
  // ============================================================
  function drilldown(item) {
    var box = el('div', 'rl-drill');

    var feedback = el('div', 'rl-edit-feedback');
    feedback.setAttribute('aria-live', 'polite');
    feedback.hidden = true;
    function say(text, isErr) {
      feedback.hidden = false;
      feedback.textContent = text;
      feedback.className = 'rl-edit-feedback' + (isErr ? ' rl-feedback-err' : ' rl-feedback-ok');
    }

    // title edit (ALWAYS editable — A3)
    var titleRow = el('div', 'rl-title-edit');
    var editBtn = btn('ghost small rl-edit-btn', 'Edit title', null);
    editBtn.setAttribute('aria-label', 'edit the title of "' + item.title + '"');
    editBtn.addEventListener('click', function () { openTitleEditor(titleRow, item, editBtn, say); });
    titleRow.appendChild(editBtn);
    box.appendChild(titleRow);

    // verbatim origin — "one click away" (I6): already carried eagerly in
    // the landing payload, so this is a plain disclosure, no extra fetch.
    var vDetails = document.createElement('details');
    vDetails.className = 'rl-verbatim-details';
    var vSummary = document.createElement('summary');
    vSummary.className = 'rl-verbatim-summary';
    vSummary.textContent = 'Verbatim origin';
    vDetails.appendChild(vSummary);
    var vBody = el('div', 'rl-verbatim-body');
    if (item.verbatim_ref) {
      vBody.appendChild(el('span', 'rl-verbatim-ref', item.verbatim_ref));
      vBody.appendChild(makeCopyBtn(item.verbatim_ref));
    } else {
      vBody.appendChild(el('span', 'pane-empty', 'no verbatim reference captured for this request'));
    }
    vDetails.appendChild(vBody);
    box.appendChild(vDetails);

    // recency (I1)
    box.appendChild(el('div', 'rl-recency', recencyText(item)));

    // evolution timeline (I6)
    var timelineHead = el('div', 'rl-subhead', 'Evolution timeline');
    box.appendChild(timelineHead);
    box.appendChild(timelineNode(item));

    box.appendChild(feedback);
    return box;
  }

  // ============================================================
  // row rendering (collapsed anatomy — I6)
  // ============================================================
  function renderRow(item) {
    var det = document.createElement('details');
    det.className = 'rl-row rl-state-' + item.state + (item.closed_reason ? ' rl-reason-' + item.closed_reason : '');
    det.dataset.requestId = item.id;
    det.tabIndex = -1; // landing target: programmatically focusable (C2)
    if (openSet[item.id]) det.open = true;
    det.addEventListener('toggle', function () {
      if (det.open) openSet[item.id] = true; else delete openSet[item.id];
    });

    var sum = document.createElement('summary');
    sum.className = 'rl-row-summary';
    sum.appendChild(el('span', 'rl-title', item.title));
    var stateChip = el('span', 'chip rl-state-chip rl-state-chip-' + (item.closed_reason || 'open'), currentStateText(item));
    sum.appendChild(stateChip);
    sum.appendChild(el('span', 'rl-recency-inline', recencyText(item)));
    det.appendChild(sum);

    det.appendChild(drilldown(item));
    return det;
  }

  // ============================================================
  // four UI states + the state-preserving master render (C4 + C7)
  // ============================================================
  function renderLoadingState() {
    body.innerHTML = '';
    var box = el('div', 'pane-loading', 'loading requests…');
    box.setAttribute('aria-busy', 'true');
    body.appendChild(box);
  }
  function renderErrorState(message) {
    body.innerHTML = '';
    var box = el('div', 'pane-error');
    box.setAttribute('role', 'alert');
    box.appendChild(el('div', 'pane-error-title', 'Could not load requests'));
    box.appendChild(el('div', 'pane-error-cmd', String(message || 'unknown error — the server may be restarting')));
    box.appendChild(btn('btn-go small', 'Retry', function () { load(); }));
    body.appendChild(box);
  }

  function clearAllFilters() {
    filterInput.value = '';
    renderAll();
  }

  function captureUiState() {
    var st = { scrollY: window.scrollY, focusRequestId: null, edit: null };
    var ae = document.activeElement;
    if (ae && body.contains(ae)) {
      var rowEl = ae.closest && ae.closest('[data-request-id]');
      if (rowEl) st.focusRequestId = rowEl.dataset.requestId;
      if (ae.classList && ae.classList.contains('rl-title-input') && rowEl) {
        st.edit = { requestId: rowEl.dataset.requestId, value: ae.value };
      }
    }
    return st;
  }
  function restoreUiState(st) {
    if (!st) return;
    window.scrollTo(0, st.scrollY);
    if (st.edit && st.edit.requestId) {
      var det = body.querySelector('[data-request-id="' + cssEsc(st.edit.requestId) + '"]');
      var item = findItemData(st.edit.requestId);
      if (det && item) {
        det.open = true;
        var titleRow = det.querySelector('.rl-title-edit');
        var editBtn = titleRow && titleRow.querySelector('.rl-edit-btn');
        if (titleRow && editBtn) {
          openTitleEditor(titleRow, item, editBtn, function () {});
          var input = titleRow.querySelector('.rl-title-input');
          if (input) input.value = st.edit.value;
          return;
        }
      }
    }
    if (st.focusRequestId) {
      var again = body.querySelector('[data-request-id="' + cssEsc(st.focusRequestId) + '"]');
      if (again) again.focus();
    }
    if (landingId) {
      var landed = body.querySelector('[data-request-id="' + cssEsc(landingId) + '"]');
      if (landed) landed.classList.add('landing-highlight');
    }
  }
  function cssEsc(s) { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\\]]/g, '\\$&'); }
  function findItemData(id) {
    var items = (lastPayload && lastPayload.items) || [];
    for (var i = 0; i < items.length; i++) { if (items[i].id === id) return items[i]; }
    return null;
  }

  function renderAll() {
    if (!lastPayload) return;
    var st = captureUiState();
    var q = filterText();
    var allItems = lastPayload.items || [];
    var open = [], closed = [];
    allItems.forEach(function (it) {
      if (it.state === 'closed') closed.push(it); else open.push(it);
    });
    var openVisible = open.filter(function (it) { return itemMatches(it, q); });
    var closedVisible = closed.filter(function (it) { return itemMatches(it, q); });

    body.innerHTML = '';

    if (allItems.length === 0) {
      body.appendChild(el('div', 'pane-empty', 'Requests appear here automatically as you talk to sessions — nothing to set up.'));
      restoreUiState(st);
      return;
    }
    if (openVisible.length === 0 && closedVisible.length === 0) {
      var line = el('div', 'pane-empty', 'no requests match "' + q + '" ');
      line.appendChild(btn('ghost small', 'clear filter', clearAllFilters));
      body.appendChild(line);
      restoreUiState(st);
      return;
    }

    if (openVisible.length > 0) {
      var openHead = el('div', 'rl-section-head', 'Open (' + openVisible.length + ')');
      body.appendChild(openHead);
      openVisible.sort(function (a, b) {
        return String(b.last_amended_ts || b.created_ts).localeCompare(String(a.last_amended_ts || a.created_ts));
      });
      openVisible.forEach(function (it) { body.appendChild(renderRow(it)); });
    } else if (q) {
      body.appendChild(el('div', 'pane-empty rl-open-empty', 'no OPEN requests match "' + q + '" (matches exist below in closed)'));
    }

    if (closedVisible.length > 0) {
      var closedHead = el('div', 'rl-section-head', 'Closed (' + closedVisible.length + ')');
      body.appendChild(closedHead);
      var byGroup = {};
      AGE_GROUP_ORDER.forEach(function (g) { byGroup[g] = []; });
      closedVisible.forEach(function (it) { byGroup[ageGroupOf(it)].push(it); });
      AGE_GROUP_ORDER.forEach(function (groupName) {
        var groupItems = byGroup[groupName];
        if (!groupItems.length) return; // never an expanded empty shell
        var det = document.createElement('details');
        det.className = 'rl-age-group';
        det.dataset.ageGroup = groupName;
        var hasMatch = !!q; // any presence in this filtered bucket already means a match
        det.open = groupOpenSet[groupName] || hasMatch;
        det.addEventListener('toggle', function () {
          if (det.open) groupOpenSet[groupName] = true; else delete groupOpenSet[groupName];
        });
        var sum = document.createElement('summary');
        sum.className = 'rl-age-group-summary';
        sum.textContent = groupName + ' (' + groupItems.length + ')';
        det.appendChild(sum);
        groupItems.sort(function (a, b) { return String(b.closed_at || b.created_ts).localeCompare(String(a.closed_at || a.created_ts)); });
        groupItems.forEach(function (it) { det.appendChild(renderRow(it)); });
        body.appendChild(det);
      });
    }

    restoreUiState(st);
  }

  // ============================================================
  // data loading — 30s poll, STALE on failure, never a DOM wipe (C7)
  // ============================================================
  function load() {
    var firstLoad = !lastPayload;
    if (firstLoad) renderLoadingState();
    return fetch('/api/requests')
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
        renderAll();
        var q = whenLoadedQueue.splice(0);
        q.forEach(function (cb) { try { cb(); } catch (_) {} });
      })
      .catch(function (err) {
        lastFetchFailed = true;
        setAgeLabel();
        if (!lastPayload) renderErrorState(String(err));
      });
  }
  function whenLoaded(cb) { if (lastPayload) cb(); else whenLoadedQueue.push(cb); }

  filterInput.addEventListener('input', function () { renderAll(); });

  // ============================================================
  // landing + path expansion (C2 — #request/<id> addressing)
  // ============================================================
  function findRowEl(id) { return body.querySelector('[data-request-id="' + cssEsc(id) + '"]'); }

  function expandTo(id) {
    var item = findItemData(id);
    if (!item) return null;
    openSet[id] = true;
    if (item.state === 'closed') groupOpenSet[ageGroupOf(item)] = true;
    renderAll();
    return findRowEl(id);
  }

  // ============================================================
  // shell registration — the 'requests' view adapter (C2). REPLACES app.js's
  // interim placeholder (last registerView('requests', ...) call wins).
  // ============================================================
  if (shell && shell.registerView) {
    shell.registerView('requests', {
      landOn: function (id, done) {
        whenLoaded(function () {
          var target = expandTo(id);
          landingId = target ? id : null;
          done(target || null);
        });
      },
      missInfo: function (id, cb) {
        whenLoaded(function () {
          cb('This request is no longer in the ledger — it may have been merged, cleared, or never existed.');
        });
      },
      snapshotState: function () {
        return { openSet: Object.assign({}, openSet), groupOpenSet: Object.assign({}, groupOpenSet), scrollY: window.scrollY };
      },
      restoreState: function (s) {
        if (!s) return;
        openSet = Object.assign({}, s.openSet);
        groupOpenSet = Object.assign({}, s.groupOpenSet);
        renderAll();
        window.scrollTo(0, s.scrollY);
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
  load();
  setInterval(function () { load(); }, REFRESH_INTERVAL_MS);
})();
