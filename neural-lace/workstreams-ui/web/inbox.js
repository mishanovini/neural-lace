'use strict';
/* inbox.js — the Inbox view (cockpit-roadmap-redesign Task 4, "Inbox view +
 * context contract enforcement"). Renders GET /api/inbox
 * (server/inbox-routes.js — the payload contract lives in that file's
 * header). Registers itself into the navigation shell (window.WorkstreamsShell,
 * defined by app.js) as the 'inbox' view adapter — the interim renderer
 * app.js used to carry here (count badge + a minimal answerable list) has
 * been REMOVED entirely (not just overridden): this module is now the SOLE
 * writer of #inboxTabCount/#inboxBody, so "the two counts can never
 * disagree" (A10) holds by construction — there is only ever one.
 *
 * Unlike requests.js/roadmap.js, this view does NOT insert its own wrapper
 * subtree: task 3 already shipped static markup for this tab
 * (#inboxSection/#inboxBody/[data-age-for="inbox"]/#inboxMissBanner in
 * index.html) that nothing else writes to anymore, so this module binds to
 * it directly — same pattern roadmap.js uses for its own static toolbar.
 *
 * Laws carried here (plan task 4, binding):
 *  - CONTEXT CONTRACT (I4/A8): a context-less item cannot render as
 *    answerable. The server pre-splits `answerable`/`quarantined`; this
 *    view never re-derives that split — same "no second heuristic" rule
 *    the server's own header states re: needs-you.sh's lint_warnings.
 *  - Item anatomy (I5): collapsed row = type glyph+label, one imperative
 *    ask sentence, source chip, age, "blocks: <item>" when present (never
 *    fabricated — see server header's HONEST LIMIT, so this never renders
 *    today). Expanded = the constitution §3 anatomy: Decision/Action
 *    needed -> Context -> Trade-offs table (decisions only) -> My pick ->
 *    Reply-with (the ANSWER lifecycle verb, C3a: pointer + copyable stub,
 *    v1 — inline answering is the PENDING follow-on, not built here).
 *  - Lifecycle (C3): ANSWER = the channel line + copyable stub (below);
 *    RESOLVE = operator dismiss, POST /api/inbox/dismiss (a labeled
 *    override); STALE-LINK = a followed #inbox/<id> link to an item no
 *    longer open renders "resolved earlier — ...", never blank (the same
 *    honest fallback text app.js's own removed interim adapter used,
 *    carried forward since this build does not compute an exact
 *    resolved-at timestamp for a since-vanished item).
 *  - Quarantine (I4/A8): rendered BELOW answerable items, under "N arrived
 *    without context"; framed as a SYSTEM failure (never the operator's
 *    fault), shows what the system DOES know, whether the auto-defect has
 *    ACTUALLY been filed yet (never claimed before the auditor cycle runs
 *    it), and an "open source session" escape hatch (a copyable
 *    `claude --resume <id>` command when a session is known — HONEST
 *    LIMIT: the Harness Health drill-in branch delta R3 also names is not
 *    wired in this build; see docs/backlog.md).
 *  - Win state (C4, delta R1): renders ONLY when zero ANSWERABLE items
 *    exist AND derivation succeeded — scoped to the answerable section, so
 *    a non-empty quarantine section never defeats it. A failed/unreadable
 *    ledger renders pane-error + Retry, NEVER the win state.
 *  - Refresh model (C7): 30s poll, STATE-PRESERVING re-render (open-details
 *    set for both sections, scroll, focus, and any uncommitted reply-stub
 *    edit survive a tick); failed refresh labels the pane "derived <age> —
 *    STALE", never silent staleness.
 *  - A11y (C9): nested <details>/<summary> disclosure; every status/type
 *    signal is text + color; interactive chips are real <button>s;
 *    aria-live feedback on every write (dismiss/copy).
 *
 * "My items" (A10, built here — task 8 item 5): operator-authored to-do
 * items from docs/operator-todo.md — GET/POST /api/todo, server/server.js's
 * existing Task-14 endpoints, UNCHANGED — render as a THIRD, distinct
 * section below quarantine: "My items". EXCLUDED from the Inbox (N)
 * answerable count by construction: setTabCount() below is only ever
 * called from renderAll() with THIS view's own /api/inbox `answerable`
 * length; the /api/todo fetch feeding "My items" is a wholly separate data
 * source setTabCount never reads — the two counts cannot disagree because
 * only one of them is ever a count at all.
 *
 * Preserves every interaction the retired standalone pane (attic/todo.js)
 * had: operator add/edit/toggle (POST actions add/edit/toggle) and the
 * pointer item's operator-override escape hatch (POST action
 * pointer_override) — reusing the exact same generic .todo-* CSS classes
 * (not scoped to the retired #todoSection) so the operator loses no
 * capability. Rendered in its OWN persistent subtree (myItemsWrap, a
 * sibling of inboxSectionsWrap below) and loaded ONCE at boot + after
 * every write — same as the original todo.js, deliberately NOT on the
 * Inbox's 30s poll — so an in-progress edit is never destroyed by a timer
 * tick that has nothing to do with it. Respects the noise_flag marker
 * convention (server respec 2026-07-19: flag, never withhold).
 *
 * The standalone pane's markup/script tag are removed from index.html and
 * todo.js itself is salvaged (git mv, never deleted) to attic/todo.js —
 * see index.html's sidebar comment + docs/plans/cockpit-roadmap-redesign.md
 * task 8.
 */
(function () {
  var body = document.getElementById('inboxBody');
  if (!body) return; // pane not present on this page — no-op

  // Two independent persistent subtrees inside #inboxBody (A10 + file
  // header above): `inboxSectionsWrap` holds the Inbox's own
  // poll-refreshed answerable/quarantine/win-state rendering — renderAll()
  // below now wipes+rebuilds THIS wrapper (not #inboxBody directly) every
  // 30s tick, so "My items" is never blown away by a poll it has nothing
  // to do with. `myItemsWrap` holds "My items", loaded once at boot + after
  // every write (todo.js's own precedent) rather than on a timer.
  var inboxSectionsWrap = document.createElement('div');
  inboxSectionsWrap.className = 'ib-sections-wrap';
  body.appendChild(inboxSectionsWrap);
  var myItemsWrap = document.createElement('div');
  myItemsWrap.className = 'ib-my-items-wrap';
  body.appendChild(myItemsWrap);

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
  var ageLabel = document.querySelector('[data-age-for="inbox"]');
  var tabCount = $('inboxTabCount');

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
  function cssEsc(s) { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/["\\\]]/g, '\\$&'); }
  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () {});
    }
  }

  // ============================================================
  // state
  // ============================================================
  var openSet = {};       // answerable item id -> details-open bool
  var openSetQ = {};      // quarantined item id -> details-open bool
  var replyEdits = {};    // item id -> in-progress (uncommitted) reply-stub text
  var lastPayload = null;
  var lastFetchFailed = false;
  var lastDerivedAt = null;
  var landingId = null;
  var whenLoadedQueue = [];

  function setAgeLabel() {
    if (!ageLabel) return;
    ageLabel.textContent = 'derived ' + formatAge(lastDerivedAt) + (lastFetchFailed ? ' — STALE (last refresh failed)' : '');
    ageLabel.classList.toggle('stale', lastFetchFailed);
  }
  function setTabCount(n) {
    if (!tabCount) return;
    tabCount.textContent = (n === null || n === undefined) ? '(—)' : '(' + n + ')';
  }

  // ============================================================
  // TYPE glyph + label (I5 — text + color, never color-only)
  // ============================================================
  function typeGlyph(kind) { return kind === 'question' ? '❓' : '🗳'; }
  function typeLabel(kind) { return kind === 'question' ? 'question' : 'decision'; }

  // ============================================================
  // reply-stub editor (the ANSWER lifecycle verb, C3a — pointer + copyable
  // stub, v1). An editable single-line input so the operator can fill in
  // their actual answer before copying; edits survive a poll tick (C7).
  // ============================================================
  function replyBlock(item, say) {
    var wrap = el('div', 'ib-reply');
    wrap.appendChild(el('div', 'ib-reply-channel', 'How to answer: ' + item.reply_channel));
    if (item.reply_with) {
      wrap.appendChild(el('div', 'ib-reply-with', 'Reply with: ' + item.reply_with));
    }
    var stubRow = el('div', 'ib-reply-stub-row');
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'ib-reply-stub-input';
    input.value = (Object.prototype.hasOwnProperty.call(replyEdits, item.id)) ? replyEdits[item.id] : item.reply_stub;
    input.setAttribute('aria-label', 'copyable reply stub for "' + item.title + '"');
    input.addEventListener('input', function () { replyEdits[item.id] = input.value; });
    stubRow.appendChild(input);
    var copyBtn = btn('btn-go small ib-copy-btn', 'Copy', function () {
      copyToClipboard(input.value);
      var orig = copyBtn.textContent;
      copyBtn.textContent = 'copied';
      say('Reply stub copied — paste it into the named channel to answer.', false);
      setTimeout(function () { copyBtn.textContent = orig; }, 1200);
    });
    stubRow.appendChild(copyBtn);
    wrap.appendChild(stubRow);
    return wrap;
  }

  // ============================================================
  // trade-offs table (decisions only — §3 anatomy step 3)
  // ============================================================
  function optionsTable(options) {
    if (!options || !options.length) return null;
    var table = document.createElement('table');
    table.className = 'ib-options-table';
    var thead = document.createElement('thead');
    var hr = document.createElement('tr');
    hr.appendChild(el('th', '', 'Option'));
    hr.appendChild(el('th', '', 'What happens'));
    thead.appendChild(hr);
    table.appendChild(thead);
    var tbody = document.createElement('tbody');
    options.forEach(function (o) {
      var tr = document.createElement('tr');
      tr.appendChild(el('td', '', o.option));
      tr.appendChild(el('td', '', o.outcome));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    return table;
  }

  // ============================================================
  // dismiss (RESOLVE lifecycle verb, C3b — a labeled override)
  // ============================================================
  function dismiss(id, say, onDone) {
    fetch('/api/inbox/dismiss', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: id }),
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.ok) { say('Dismissed.', false); if (onDone) onDone(); load(); }
      else { say((j && j.error) || 'Could not dismiss this item.', true); }
    }).catch(function (e) { say('Could not dismiss this item: ' + e, true); });
  }

  // ============================================================
  // expanded anatomy — the constitution §3 compact format (I5), shared by
  // both answerable and quarantined rows; quarantine adds its own extra
  // block (quarantineExtra) below.
  // ============================================================
  function expandedAnatomy(item, isQuarantined) {
    var box = el('div', 'ib-drill');

    var feedback = el('div', 'ib-edit-feedback');
    feedback.setAttribute('aria-live', 'polite');
    feedback.hidden = true;
    function say(text, isErr) {
      feedback.hidden = false;
      feedback.textContent = text;
      feedback.className = 'ib-edit-feedback' + (isErr ? ' ib-feedback-err' : ' ib-feedback-ok');
    }

    // 1. Decision/Action needed — one sentence, visually primary.
    var head = el('div', 'ib-anatomy-head', (item.kind === 'question' ? 'Question: ' : 'Decision needed: ') + item.title);
    box.appendChild(head);

    // 2. Context (<=5 lines, decisions only — questions carry no structure).
    if (item.context && item.context.length) {
      var ctxBox = el('div', 'ib-context');
      item.context.slice(0, 5).forEach(function (line) { ctxBox.appendChild(el('div', 'ib-context-line', line)); });
      box.appendChild(ctxBox);
    }

    // 3. Trade-offs table (decisions only).
    var table = optionsTable(item.options);
    if (table) box.appendChild(table);

    // 4. My pick.
    if (item.my_pick) box.appendChild(el('div', 'ib-my-pick', 'My pick: ' + item.my_pick));

    // 5. Reply-with (the ANSWER lifecycle verb).
    if (!isQuarantined) box.appendChild(replyBlock(item, say));

    // Quarantine-only extra anatomy (I4/A8).
    if (isQuarantined) box.appendChild(quarantineExtra(item, say));

    // dismiss (RESOLVE — every item, answerable or quarantined).
    var actionsRow = el('div', 'ib-actions');
    actionsRow.appendChild(btn('ghost small ib-dismiss-btn', 'Dismiss', function () {
      dismiss(item.id, say);
    }));
    box.appendChild(actionsRow);

    // BELOW THE FOLD: raw verbatim + session lineage.
    var raw = document.createElement('details');
    raw.className = 'ib-raw-details';
    var rawSum = document.createElement('summary');
    rawSum.textContent = 'Raw verbatim + session lineage';
    raw.appendChild(rawSum);
    var rawBody = el('div', 'ib-raw-body');
    rawBody.appendChild(el('pre', 'ib-raw-text', item.raw_text || ''));
    rawBody.appendChild(el('div', 'ib-raw-meta',
      'session: ' + (item.session || '(none recorded)') + (item.tier ? (' · tier ' + item.tier) : '')));
    raw.appendChild(rawBody);
    box.appendChild(raw);

    box.appendChild(feedback);
    return box;
  }

  // ============================================================
  // quarantine-only extra anatomy (I4/A8) — framed as a SYSTEM failure.
  // ============================================================
  function quarantineExtra(item, say) {
    var box = el('div', 'ib-quarantine-extra');
    box.appendChild(el('div', 'ib-quarantine-framing',
      'The system could not classify this as answerable — it arrived without enough context.'));

    var reasons = el('ul', 'ib-lint-reasons');
    (item.lint_reasons || []).forEach(function (r) { reasons.appendChild(el('li', '', r)); });
    box.appendChild(reasons);

    box.appendChild(el('div', 'ib-defect-line',
      item.defect_filed
        ? 'A defect has been filed against the producing session.'
        : 'A defect will be filed at the next background audit cycle.'));

    // "open source session" escape hatch — HONEST LIMIT: the Harness
    // Health drill-in branch (delta R3) is not wired in this build; the
    // copyable resume command is always the live, never-dead affordance.
    var oss = item.open_source_session || {};
    if (oss.has_session) {
      var ossRow = el('div', 'ib-open-session-row');
      var ossInput = document.createElement('input');
      ossInput.type = 'text';
      ossInput.className = 'ib-resume-cmd-input';
      ossInput.readOnly = true;
      ossInput.value = oss.resume_cmd;
      ossInput.setAttribute('aria-label', 'copyable command to open the source session');
      ossRow.appendChild(ossInput);
      ossRow.appendChild(btn('ghost small', 'Copy resume command', function () {
        copyToClipboard(oss.resume_cmd);
        say('Resume command copied.', false);
      }));
      box.appendChild(ossRow);
    } else {
      box.appendChild(el('div', 'ib-open-session-row', 'no session recorded for this item — nothing to resume'));
    }
    return box;
  }

  // ============================================================
  // row rendering (collapsed anatomy — I5)
  // ============================================================
  function renderRow(item, isQuarantined) {
    var det = document.createElement('details');
    det.className = 'ib-row' + (isQuarantined ? ' ib-row-quarantined' : ' ib-row-answerable');
    det.dataset.inboxId = item.id;
    det.tabIndex = -1; // landing target: programmatically focusable (C2)
    var set = isQuarantined ? openSetQ : openSet;
    if (set[item.id]) det.open = true;
    det.addEventListener('toggle', function () {
      if (det.open) set[item.id] = true; else delete set[item.id];
    });

    var sum = document.createElement('summary');
    sum.className = 'ib-row-summary';
    sum.appendChild(el('span', 'ib-type-glyph', typeGlyph(item.kind)));
    sum.appendChild(el('span', 'chip ib-type-chip', typeLabel(item.kind)));
    sum.appendChild(el('span', 'ib-ask-text', item.ask));
    var sourceChip = el('span', 'chip ib-source-chip', item.session ? ('session ' + item.session) : 'no session recorded');
    sum.appendChild(sourceChip);
    sum.appendChild(el('span', 'ib-age', formatAge(item.created_at)));
    // "blocks: <item>" — only ever rendered when the server actually names
    // a roadmap id (see server header's HONEST LIMIT: always null today).
    if (item.blocks_roadmap_id) {
      sum.appendChild(btn('ghost small ib-blocks-chip', 'blocks: ' + item.blocks_roadmap_id, function (e) {
        e.preventDefault(); e.stopPropagation();
        if (shell) shell.navigate('#roadmap/' + item.blocks_roadmap_id);
      }));
    }
    det.appendChild(sum);
    det.appendChild(expandedAnatomy(item, isQuarantined));
    return det;
  }

  // ============================================================
  // four UI states + the state-preserving master render (C4 + C7)
  // ============================================================
  function renderLoadingState() {
    inboxSectionsWrap.innerHTML = '';
    var box = el('div', 'pane-loading', 'deriving your inbox…');
    box.setAttribute('aria-busy', 'true');
    inboxSectionsWrap.appendChild(box);
  }
  function renderErrorState(message) {
    inboxSectionsWrap.innerHTML = '';
    var box = el('div', 'pane-error');
    box.setAttribute('role', 'alert');
    box.appendChild(el('div', 'pane-error-title', 'Could not read what is waiting on you'));
    box.appendChild(el('div', 'pane-error-cmd', String(message || 'unknown error — the server may be restarting')));
    box.appendChild(btn('btn-go small', 'Retry', function () { load(); }));
    inboxSectionsWrap.appendChild(box);
  }

  function captureUiState() {
    var st = { scrollY: window.scrollY, focusId: null };
    var ae = document.activeElement;
    if (ae && body.contains(ae)) {
      var rowEl = ae.closest && ae.closest('[data-inbox-id]');
      if (rowEl) st.focusId = rowEl.dataset.inboxId;
    }
    return st;
  }
  function restoreUiState(st) {
    if (!st) return;
    window.scrollTo(0, st.scrollY);
    if (st.focusId) {
      var again = body.querySelector('[data-inbox-id="' + cssEsc(st.focusId) + '"]');
      if (again) again.focus();
    }
    if (landingId) {
      var landed = body.querySelector('[data-inbox-id="' + cssEsc(landingId) + '"]');
      if (landed) landed.classList.add('landing-highlight');
    }
  }

  function findRowEl(id) { return body.querySelector('[data-inbox-id="' + cssEsc(id) + '"]'); }
  function findItemData(id) {
    if (!lastPayload) return null;
    var all = (lastPayload.answerable || []).concat(lastPayload.quarantined || []);
    for (var i = 0; i < all.length; i++) { if (all[i].id === id) return all[i]; }
    return null;
  }

  function renderAll() {
    if (!lastPayload) return;
    var st = captureUiState();
    var answerable = lastPayload.answerable || [];
    var quarantined = lastPayload.quarantined || [];

    setTabCount(answerable.length);
    inboxSectionsWrap.innerHTML = '';

    // Win state (C4, delta R1): scoped to the answerable section — a
    // non-empty quarantine section (rendered right below) or a non-empty
    // "My items" section (rendered in its own independent wrap, further
    // below in the DOM) never defeats it. Rendered ONLY on a successful
    // derivation (the error state above already handles failure, so
    // reaching here means ok:true).
    if (answerable.length === 0) {
      var win = el('div', 'pane-empty inbox-win', 'Nothing waiting on you — all sessions running free. As of ' + formatAge(lastDerivedAt) + '.');
      inboxSectionsWrap.appendChild(win);
    } else {
      var answerHead = el('div', 'ib-section-head', 'Awaiting your answer (' + answerable.length + ')');
      inboxSectionsWrap.appendChild(answerHead);
      answerable.forEach(function (it) { inboxSectionsWrap.appendChild(renderRow(it, false)); });
    }

    if (quarantined.length > 0) {
      var qHead = el('div', 'ib-section-head ib-quarantine-head',
        quarantined.length + ' arrived without context — defects filed against the producing sessions');
      inboxSectionsWrap.appendChild(qHead);
      quarantined.forEach(function (it) { inboxSectionsWrap.appendChild(renderRow(it, true)); });
    }

    restoreUiState(st);
  }

  // ============================================================
  // "My items" (A10 — see file header). Operator-authored to-do items from
  // docs/operator-todo.md, via the UNCHANGED GET/POST /api/todo endpoints.
  // Loaded ONCE at boot + after every write (todo.js's own precedent — no
  // 30s poll here, so an in-progress edit is never destroyed by a tick
  // that has nothing to do with it). EXCLUDED from the Inbox (N) count:
  // setTabCount() above is only ever invoked from renderAll() with the
  // /api/inbox `answerable` length — this fetch cycle is a wholly separate
  // data source setTabCount never reads.
  // ============================================================
  function postTodo(bodyObj) {
    return fetch('/api/todo', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(bodyObj),
    }).then(function (r) { return r.json(); }).catch(function (err) { return { ok: false, error: String(err) }; });
  }

  var myItemsFeedbackEl = null;
  var myItemsFeedbackTimer = null;
  function showMyItemsFeedback(text, isError) {
    if (!myItemsFeedbackEl) return;
    if (myItemsFeedbackTimer) clearTimeout(myItemsFeedbackTimer);
    myItemsFeedbackEl.hidden = false;
    myItemsFeedbackEl.textContent = text;
    myItemsFeedbackEl.className = 'todo-global-feedback' + (isError ? ' todo-feedback-error' : ' todo-feedback-ok');
    myItemsFeedbackTimer = setTimeout(function () { myItemsFeedbackEl.hidden = true; }, isError ? 8000 : 3000);
  }

  // duplicated absolute-href helper (this codebase's own convention — see
  // asks.js/attic/todo.js precedent; no shared client-side module system).
  function myItemsFileUrl(p) {
    if (typeof p !== 'string' || p === '') return null;
    if (/^https?:\/\//i.test(p)) return p;
    var norm = p.replace(/\\/g, '/');
    if (/^[A-Za-z]:\//.test(norm)) return 'file:///' + norm;
    if (/^\/\//.test(norm)) return null; // UNC — copy-only is the honest fallback
    if (/^\//.test(norm)) return 'file://' + norm;
    return null;
  }

  // operator item row — editable + checkable (ports attic/todo.js's
  // renderOperatorItem exactly: same POST verbs, same noise_flag marker
  // convention — respec 2026-07-19, availability outranks lint, the server
  // flags rather than withholds).
  function renderMyItemOperatorRow(item) {
    var row = el('div', 'todo-item todo-item-operator');

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.className = 'todo-checkbox';
    cb.checked = !!item.checked;
    cb.setAttribute('aria-label', (item.checked ? 'mark not done: ' : 'mark done: ') + item.text);
    cb.addEventListener('change', function () {
      var wasChecked = cb.checked;
      cb.disabled = true;
      postTodo({ action: 'toggle', index: item.index }).then(function (r) {
        if (r && r.ok) { showMyItemsFeedback('Saved.', false); loadMyItems(); }
        else {
          cb.checked = !wasChecked; // mistake recovery: revert the optimistic flip
          cb.disabled = false;
          showMyItemsFeedback('Could not update: ' + ((r && r.error) || 'unknown error'), true);
        }
      });
    });
    row.appendChild(cb);

    var textSpan = el('span', 'todo-item-text' + (item.checked ? ' todo-item-checked' : ''), item.text);
    if (item.noise_flag) {
      var noiseMark = el('span', 'todo-noise-flag', ' ⚑ quotes internal identifiers');
      noiseMark.title = 'This item quotes harness-internal command/script names. Rendered in full — flagged for awareness only.';
      textSpan.appendChild(noiseMark);
    }
    row.appendChild(textSpan);

    var editBtn = btn('ghost small todo-edit-btn', 'Edit', function () { startMyItemEdit(row, item, textSpan, editBtn); });
    editBtn.setAttribute('aria-label', 'edit "' + item.text + '"');
    row.appendChild(editBtn);

    return row;
  }

  function startMyItemEdit(row, item, textSpan, editBtn) {
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'todo-edit-input';
    input.value = item.text;
    input.setAttribute('aria-label', 'edit to-do text');
    var saveBtn = btn('btn-go small', 'Save', null);
    var cancelBtn = btn('ghost small', 'Cancel', null);

    textSpan.hidden = true;
    editBtn.hidden = true;
    row.appendChild(input);
    row.appendChild(saveBtn);
    row.appendChild(cancelBtn);
    input.focus();
    input.select();

    function cancel() {
      input.remove(); saveBtn.remove(); cancelBtn.remove();
      textSpan.hidden = false; editBtn.hidden = false;
    }
    cancelBtn.addEventListener('click', cancel);
    input.addEventListener('keydown', function (e) { if (e.key === 'Escape') cancel(); });
    saveBtn.addEventListener('click', function () {
      var text = input.value.trim();
      if (!text) { showMyItemsFeedback('To-do text cannot be empty.', true); return; }
      saveBtn.disabled = true;
      postTodo({ action: 'edit', index: item.index, text: text }).then(function (r) {
        if (r && r.ok) { showMyItemsFeedback('Saved.', false); loadMyItems(); }
        else { saveBtn.disabled = false; showMyItemsFeedback('Could not save: ' + ((r && r.error) || 'unknown error'), true); }
      });
    });
  }

  // pointer item row — DERIVED, never a checkbox lookalike (ports
  // attic/todo.js's renderPointerItem: lock glyph, aria-disabled,
  // navigation-first affordance, "Mark handled" operator-override escape
  // hatch for when the auditor's derivation can't see a resolution).
  function renderMyItemPointerRow(item) {
    var row = el('div', 'todo-item todo-item-pointer' + (item.checked ? ' todo-item-resolved' : ''));

    var glyph = el('span', 'todo-pointer-glyph');
    glyph.setAttribute('role', 'button');
    glyph.setAttribute('aria-disabled', 'true');
    glyph.setAttribute('tabindex', '-1');
    glyph.title = 'resolves when you answer the underlying item — click to go there';
    glyph.setAttribute('aria-label', item.checked ? 'automatically resolved, read-only' : 'automatic, read-only — not directly editable');
    glyph.textContent = item.checked ? '🔒✓' : '🔒'; // lock (+ check when resolved) — text+color, never color-only
    row.appendChild(glyph);

    var pbody = el('div', 'todo-pointer-body');
    var titleRow = el('div', 'todo-pointer-title');
    var link = document.createElement('a');
    link.className = 'todo-pointer-link';
    link.title = 'resolves when you answer the underlying item — click to go there';
    link.textContent = item.title || ('(untitled ' + (item.section || 'item') + ')');
    var href = myItemsFileUrl(item.raw_link);
    if (href) {
      link.href = href;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
    } else {
      link.href = '#';
      link.setAttribute('aria-disabled', 'true');
      link.addEventListener('click', function (e) { e.preventDefault(); });
    }
    titleRow.appendChild(link);
    pbody.appendChild(titleRow);

    if (item.body) {
      pbody.appendChild(el('div', 'todo-pointer-preview', item.body.length > 200 ? item.body.slice(0, 200) + '…' : item.body));
    }

    var tierLabel = (item.tier && item.tier !== 'untiered') ? ('tier ' + item.tier) : 'no tier';
    var stateLabel = item.checked ? (item.operator_override ? 'marked handled by you' : 'resolved') : 'waiting on you';
    pbody.appendChild(el('div', 'todo-pointer-meta', (item.section || 'item') + ' · ' + tierLabel + ' · ' + stateLabel));

    row.appendChild(pbody);

    if (!item.checked) {
      var overrideBtn = btn('ghost small todo-override-btn', 'Mark handled', function () {
        overrideBtn.disabled = true;
        postTodo({ action: 'pointer_override', needs_you_id: item.needs_you_id }).then(function (r) {
          if (r && r.ok) { showMyItemsFeedback('Marked handled.', false); loadMyItems(); }
          else { overrideBtn.disabled = false; showMyItemsFeedback('Could not mark handled: ' + ((r && r.error) || 'unknown error'), true); }
        });
      });
      overrideBtn.title = 'use this if you already resolved it and the pointer did not auto-check';
      row.appendChild(overrideBtn);
    }

    return row;
  }

  // add form — always visible (todo.js precedent: adding is not restricted
  // to the empty state).
  function renderMyItemsAddForm() {
    var form = document.createElement('form');
    form.className = 'todo-add-form';
    form.setAttribute('aria-label', 'add a to-do item');
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'todo-add-input';
    input.placeholder = 'add a to-do item…';
    input.setAttribute('aria-label', 'new to-do item text');
    var addBtn = document.createElement('button');
    addBtn.type = 'submit';
    addBtn.className = 'btn-go small';
    addBtn.textContent = 'Add';
    form.appendChild(input);
    form.appendChild(addBtn);
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var text = input.value.trim();
      if (!text) return;
      addBtn.disabled = true;
      postTodo({ action: 'add', text: text }).then(function (r) {
        addBtn.disabled = false;
        if (r && r.ok) { input.value = ''; showMyItemsFeedback('Added.', false); loadMyItems(); }
        else { showMyItemsFeedback('Could not add: ' + ((r && r.error) || 'unknown error'), true); }
      });
    });
    return form;
  }

  function renderMyItemsLoading() {
    myItemsWrap.innerHTML = '';
    myItemsWrap.appendChild(el('div', 'ib-section-head', 'My items'));
    var box = el('div', 'todo-status');
    var loading = el('div', 'pane-loading', 'loading your to-do items…');
    loading.setAttribute('aria-busy', 'true');
    box.appendChild(loading);
    myItemsWrap.appendChild(box);
  }
  function renderMyItemsError(message) {
    myItemsWrap.innerHTML = '';
    myItemsWrap.appendChild(el('div', 'ib-section-head', 'My items'));
    var box = el('div', 'todo-status pane-error');
    box.setAttribute('role', 'alert');
    box.appendChild(el('div', 'pane-error-title', 'Could not load your to-do list'));
    box.appendChild(el('div', 'pane-error-cmd', String(message || 'unknown error — the server may be restarting')));
    box.appendChild(btn('btn-go small', 'Retry', function () { loadMyItems(); }));
    myItemsWrap.appendChild(box);
  }
  function renderMyItemsBody(payload) {
    myItemsWrap.innerHTML = '';

    var operatorItems = payload.operator_items || [];
    var pointerItems = (payload.pointer_items || []).slice().sort(function (a, b) {
      // outstanding pointers first, resolved ones sink — mirrors the
      // ask-tree's own "active first, completed collapsed" ordering.
      return (a.checked === b.checked) ? 0 : (a.checked ? 1 : -1);
    });
    var openCount = operatorItems.filter(function (i) { return !i.checked; }).length +
      pointerItems.filter(function (i) { return !i.checked; }).length;

    myItemsWrap.appendChild(el('div', 'ib-section-head', 'My items (' + openCount + ' open)'));

    myItemsFeedbackEl = el('div', 'todo-global-feedback');
    myItemsFeedbackEl.setAttribute('aria-live', 'polite');
    myItemsFeedbackEl.hidden = true;
    myItemsWrap.appendChild(myItemsFeedbackEl);

    myItemsWrap.appendChild(renderMyItemsAddForm());

    var list = el('div', 'todo-list');
    if (operatorItems.length === 0 && pointerItems.length === 0) {
      list.appendChild(el('div', 'pane-empty todo-empty', 'No to-do items yet — add one above. Items also appear automatically when a session parks a decision on you.'));
    } else {
      operatorItems.forEach(function (it) { list.appendChild(renderMyItemOperatorRow(it)); });
      pointerItems.forEach(function (it) { list.appendChild(renderMyItemPointerRow(it)); });
    }
    myItemsWrap.appendChild(list);
  }

  function loadMyItems() {
    renderMyItemsLoading();
    return fetch('/api/todo')
      .then(function (r) { return r.json(); })
      .then(function (resp) {
        if (!resp || resp.ok === false) {
          renderMyItemsError(resp && resp.error ? resp.error : 'server returned ok:false');
          return;
        }
        renderMyItemsBody(resp);
      })
      .catch(function (err) { renderMyItemsError(String(err)); });
  }

  // ============================================================
  // data loading — 30s poll, STALE on failure, never a DOM wipe (C7)
  // ============================================================
  function load() {
    var firstLoad = !lastPayload;
    if (firstLoad) renderLoadingState();
    return fetch('/api/inbox')
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

  // ============================================================
  // landing + path expansion (C2 — #inbox/<id> addressing)
  // ============================================================
  function expandTo(id) {
    var item = findItemData(id);
    if (!item) return null;
    var isQuarantined = !!(lastPayload.quarantined || []).some(function (q) { return q.id === id; });
    (isQuarantined ? openSetQ : openSet)[id] = true;
    renderAll();
    return findRowEl(id);
  }

  // ============================================================
  // shell registration — the 'inbox' view adapter (C2). This is now the
  // ONLY registerView('inbox', ...) call in the app (app.js's interim one
  // was removed, not merely overridden — see file header).
  // ============================================================
  if (shell && shell.registerView) {
    shell.registerView('inbox', {
      landOn: function (id, done) {
        whenLoaded(function () {
          var target = expandTo(id);
          landingId = target ? id : null;
          done(target || null);
        });
      },
      missInfo: function (id, cb) {
        whenLoaded(function () {
          cb('resolved earlier — no longer waiting on you (answered or cleared in the ledger).');
        });
      },
      snapshotState: function () {
        return { openSet: Object.assign({}, openSet), openSetQ: Object.assign({}, openSetQ), scrollY: window.scrollY };
      },
      restoreState: function (s) {
        if (!s) return;
        openSet = Object.assign({}, s.openSet);
        openSetQ = Object.assign({}, s.openSetQ);
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
  // boot: initial load + the 30s tick (C7) — this view now owns the
  // Inbox (N) count entirely (see file header). "My items" loads once here
  // (+ after every write, from within its own handlers above) — never on
  // the 30s tick, per its own section header.
  // ============================================================
  load();
  loadMyItems();
  setInterval(function () { load(); }, REFRESH_INTERVAL_MS);
})();
