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
 * "My items" (A10): this task's dispatch note says the operator-authored
 * "My items" section's ACTUAL relocation into this view is task 8's job
 * (task 8's own bullet claims ownership of "the standalone pane REMOVED —
 * its items move into the Inbox 'My items' section"), so it is not built
 * here — the standalone My-To-Do pane (todo.js, in the Requests tab sidebar)
 * is untouched. See docs/backlog.md for the tracked follow-up.
 */
(function () {
  var body = document.getElementById('inboxBody');
  if (!body) return; // pane not present on this page — no-op

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
    body.innerHTML = '';
    var box = el('div', 'pane-loading', 'deriving your inbox…');
    box.setAttribute('aria-busy', 'true');
    body.appendChild(box);
  }
  function renderErrorState(message) {
    body.innerHTML = '';
    var box = el('div', 'pane-error');
    box.setAttribute('role', 'alert');
    box.appendChild(el('div', 'pane-error-title', 'Could not read what is waiting on you'));
    box.appendChild(el('div', 'pane-error-cmd', String(message || 'unknown error — the server may be restarting')));
    box.appendChild(btn('btn-go small', 'Retry', function () { load(); }));
    body.appendChild(box);
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
    body.innerHTML = '';

    // Win state (C4, delta R1): scoped to the answerable section — a
    // non-empty quarantine section (rendered right below) never defeats
    // it. Rendered ONLY on a successful derivation (the error state above
    // already handles failure, so reaching here means ok:true).
    if (answerable.length === 0) {
      var win = el('div', 'pane-empty inbox-win', 'Nothing waiting on you — all sessions running free. As of ' + formatAge(lastDerivedAt) + '.');
      body.appendChild(win);
    } else {
      var answerHead = el('div', 'ib-section-head', 'Awaiting your answer (' + answerable.length + ')');
      body.appendChild(answerHead);
      answerable.forEach(function (it) { body.appendChild(renderRow(it, false)); });
    }

    if (quarantined.length > 0) {
      var qHead = el('div', 'ib-section-head ib-quarantine-head',
        quarantined.length + ' arrived without context — defects filed against the producing sessions');
      body.appendChild(qHead);
      quarantined.forEach(function (it) { body.appendChild(renderRow(it, true)); });
    }

    restoreUiState(st);
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
  // Inbox (N) count entirely (see file header).
  // ============================================================
  load();
  setInterval(function () { load(); }, REFRESH_INTERVAL_MS);
})();
