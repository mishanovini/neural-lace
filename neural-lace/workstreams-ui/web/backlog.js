'use strict';
/* backlog.js — ask-rooted-workstreams-p1, Task 15 "Backlog pane".
 *
 * Renders the sidebar's Backlog pane: a compact top-N-per-tier view of
 * `docs/backlog.md` (GET /api/backlog) with a one-click toggle to the full
 * list, an ADD form (both Claude and the operator write the SAME row shape
 * the O.9 triage loop's golden oracle already parses — server.js's
 * buildBacklogPayload()/parseBacklogRows() port that oracle's R1-R4 rules
 * verbatim), and disposition buttons — SCHEDULE / DEMOTE / FOLD / WONTFIX —
 * writing the EXACT disposition vocabulary that loop understands, row-
 * scoped, to the REAL file (never a parallel store).
 *
 * Disposition UX (review round 1, constraint 9): SCHEDULE/DEMOTE/FOLD are
 * non-destructive from the operator's perspective (the file gains a marker,
 * nothing is deleted) and get success feedback + a brief Undo (mirrors
 * asks.js's own UNDO_WINDOW_MS lifecycle-row pattern below); WONTFIX is
 * permanent-reading and gets an inline CONFIRM step instead of an Undo
 * affordance — four adjacent one-click durable writes need misclick
 * protection, and WONTFIX is the one this module never offers to reverse
 * (the server itself does not special-case it — the client is what enforces
 * "CONFIRM instead of undo" here).
 *
 * Anti-noise law (hard constraint 1) — deliberately NOT applied to row
 * text: docs/backlog.md IS the harness's own engineering backlog, so a
 * hook/gate/script identifier in a row's title or preview is legitimate
 * subject matter, not mechanism-attribution noise (see server.js's matching
 * header comment for the full rationale). This module renders row
 * title/preview verbatim as server-prepared text.
 *
 * Absolute-links law (hard constraint 2): the ONE href this module ever
 * sets is the "open backlog.md" affordance, built from the server's
 * `file_path` (an absolute filesystem path) — duplicated absolute-href
 * helpers below, matching todo.js/asks.js's own per-file duplication
 * convention (no shared client-side module system in this app).
 */
(function () {
  var root = document.getElementById('backlogBody');
  if (!root) return; // pane not present on this page — no-op

  function $(id) { return document.getElementById(id); }

  // ============================================================
  // absolute-href helpers (duplicated from todo.js/asks.js by convention)
  // ============================================================
  function toFileUrl(p) {
    var norm = String(p).replace(/\\/g, '/');
    if (/^[A-Za-z]:\//.test(norm)) return 'file:///' + norm;
    if (/^\/\//.test(norm)) return null; // UNC — copy-only is the honest fallback
    if (/^\//.test(norm)) return 'file://' + norm;
    return null;
  }
  function absoluteLinkHref(value) {
    if (typeof value !== 'string' || value === '') return null;
    if (/^https?:\/\//i.test(value)) return value;
    return toFileUrl(value);
  }

  var TIER_LABELS = { high: 'High priority', medium: 'Medium priority', low: 'Low priority', unlabeled: 'Unlabeled' };
  var TIER_ORDER = ['high', 'medium', 'low', 'unlabeled'];
  var UNDO_WINDOW_MS = 8000;
  var showingFull = false;

  // ============================================================
  // top-level render states (loading / error / empty / ideal — constraint 8)
  // ============================================================
  function renderLoading() {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'backlog-status';
    box.innerHTML = '<div class="pane-loading" aria-busy="true">loading the backlog…</div>';
    root.appendChild(box);
    setCount(null);
  }

  function renderError(message) {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'backlog-status pane-error';
    box.setAttribute('role', 'alert');
    var h = document.createElement('div');
    h.className = 'pane-error-title';
    h.textContent = 'Could not load the backlog';
    box.appendChild(h);
    var msg = document.createElement('div');
    msg.className = 'pane-error-cmd';
    msg.textContent = String(message || 'unknown error — the server may be restarting');
    box.appendChild(msg);
    var retry = document.createElement('button');
    retry.type = 'button';
    retry.className = 'btn-go small';
    retry.textContent = 'Retry';
    retry.addEventListener('click', load);
    box.appendChild(retry);
    root.appendChild(box);
    setCount(null);
  }

  function setCount(n) {
    var el = $('backlogCount');
    if (!el) return;
    el.textContent = (n === null || n === undefined) ? '—' : String(n) + ' open';
  }

  // ============================================================
  // writes
  // ============================================================
  function postBacklog(body) {
    return fetch('/api/backlog', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then(function (r) { return r.json(); }).catch(function (err) { return { ok: false, error: String(err) }; });
  }

  var globalFeedbackEl = null;
  var globalFeedbackTimer = null;
  function showGlobalFeedback(text, isError) {
    if (!globalFeedbackEl) return;
    if (globalFeedbackTimer) clearTimeout(globalFeedbackTimer);
    globalFeedbackEl.hidden = false;
    globalFeedbackEl.textContent = text;
    globalFeedbackEl.className = 'backlog-global-feedback' + (isError ? ' backlog-feedback-error' : ' backlog-feedback-ok');
    globalFeedbackTimer = setTimeout(function () { globalFeedbackEl.hidden = true; }, isError ? 8000 : 3000);
  }

  // ============================================================
  // row rendering — open rows get disposition actions; inflight/terminal
  // rows render as a greyed, badge-carrying line (constraint 9: "moves under
  // its disposition word").
  // ============================================================
  function ageText(row) {
    if (row.age_days === null || row.age_days === undefined) return 'no date';
    if (row.age_days <= 0) return 'added today';
    return row.age_days + 'd ago';
  }

  function renderDispositionedRow(row) {
    var wrap = document.createElement('div');
    wrap.className = 'backlog-row backlog-row-done';
    var head = document.createElement('div');
    head.className = 'backlog-row-head';
    var title = document.createElement('span');
    title.className = 'backlog-row-title';
    title.textContent = row.title;
    head.appendChild(title);
    var badge = document.createElement('span');
    badge.className = 'chip backlog-badge backlog-badge-' + row.status;
    badge.textContent = row.disposition_word || (row.status === 'terminal' ? 'CLOSED' : 'IN FLIGHT');
    head.appendChild(badge);
    wrap.appendChild(head);
    var meta = document.createElement('div');
    meta.className = 'backlog-row-meta';
    meta.textContent = row.id + ' · ' + ageText(row);
    wrap.appendChild(meta);
    return wrap;
  }

  // renderOpenRow(row, onMoved) — onMoved() runs once a disposition's undo
  // window elapses without an undo click (the caller reloads so the row
  // takes its permanent place, mirroring asks.js's renderLifecycleRow).
  //
  // cockpit-roadmap-redesign Task 8 (absorbed UI-polish item 2): the row is
  // now a native <details class="backlog-row"> — COLLAPSED BY DEFAULT (no
  // `open` attribute), one-line <summary> (id + title + tier + age),
  // click/keyboard-expandable. Disposition buttons + the preview text move
  // into the expanded body only. Native <details>/<summary> is this
  // codebase's own established keyboard-a11y disclosure pattern (same one
  // roadmap.js's tree nodes and asks.js's plan/verbatim drill-downs already
  // use) — no separate manual aria-expanded bookkeeping needed, the browser
  // provides real keyboard operability (Enter/Space) for free.
  function renderOpenRow(row, onMoved) {
    var wrap = document.createElement('details');
    wrap.className = 'backlog-row';

    var summary = document.createElement('summary');
    summary.className = 'backlog-row-summary';
    var summaryTitle = document.createElement('span');
    summaryTitle.className = 'backlog-row-summary-title';
    summaryTitle.textContent = row.title;
    // LIVE-BROWSER-CAUGHT (this task's build): a long title in the sidebar's
    // ~260px width, combined with `flex:1; min-width:0`, does NOT overflow
    // gracefully — it shrinks to a sliver and WORD-WRAPS across dozens of
    // lines (860px+ tall observed), defeating "one-line collapsed" entirely.
    // CSS now truncates with text-overflow:ellipsis (single line, always);
    // the native `title` attribute gives a hover tooltip, and the FULL,
    // untruncated title is repeated inside the expanded detail body below
    // (title="..." is mouse-only — expand is the real, keyboard/AT-
    // reachable way to read it in full).
    summaryTitle.title = row.title;
    summary.appendChild(summaryTitle);
    var summaryMeta = document.createElement('span');
    summaryMeta.className = 'backlog-row-summary-meta';
    summaryMeta.textContent = row.id + ' · ' + (row.priority === 'unlabeled' ? 'no priority label' : row.priority) + ' · ' + ageText(row);
    summary.appendChild(summaryMeta);
    if (row.is_overdue) {
      var overdue = document.createElement('span');
      overdue.className = 'chip backlog-overdue';
      overdue.textContent = 'overdue';
      summary.appendChild(overdue);
    }
    wrap.appendChild(summary);

    var detail = document.createElement('div');
    detail.className = 'backlog-row-detail';

    // the FULL, untruncated title (the collapsed summary above ellipsizes
    // it to keep the row genuinely one-line — see the comment on
    // summaryTitle above). The row is built detached from the document
    // here (no layout yet, so scrollWidth/clientWidth aren't meaningful) —
    // a length heuristic is this codebase's own established convention for
    // this exact judgment call (same threshold class as the 160/200-char
    // preview clamps elsewhere in this file/asks.js). Only rendered past
    // the threshold so a short title isn't shown twice for no reason.
    if (row.title.length > 40) {
      var fullTitle = document.createElement('div');
      fullTitle.className = 'backlog-row-title';
      fullTitle.textContent = row.title;
      detail.appendChild(fullTitle);
    }

    if (row.preview) {
      var preview = document.createElement('div');
      preview.className = 'backlog-row-preview';
      preview.textContent = row.preview.length > 160 ? row.preview.slice(0, 160) + '…' : row.preview;
      detail.appendChild(preview);
    }

    var actions = document.createElement('div');
    actions.className = 'backlog-row-actions';
    var confirmArea = document.createElement('div');
    confirmArea.className = 'backlog-row-confirm';
    confirmArea.hidden = true;
    var feedback = document.createElement('div');
    feedback.className = 'backlog-row-feedback';
    feedback.setAttribute('aria-live', 'polite');
    feedback.hidden = true;

    function setBusy(b) {
      Array.prototype.forEach.call(actions.querySelectorAll('button'), function (btn) { btn.disabled = b; });
    }

    function showRowFeedback(text, undoPayload) {
      actions.hidden = true;
      confirmArea.hidden = true;
      feedback.hidden = false;
      feedback.innerHTML = '';
      var t = document.createElement('span');
      t.className = 'backlog-row-feedback-text';
      t.textContent = text;
      feedback.appendChild(t);
      var timer = null;
      if (undoPayload) {
        var undoBtn = document.createElement('button');
        undoBtn.type = 'button';
        undoBtn.className = 'ghost small backlog-undo-btn';
        undoBtn.textContent = 'Undo';
        undoBtn.addEventListener('click', function () {
          if (timer) clearTimeout(timer);
          undoBtn.disabled = true;
          postBacklog({ action: 'undo', id: row.id, appended_suffix: undoPayload.appended_suffix }).then(function (r) {
            if (r && r.ok) { load(); } else {
              t.textContent = 'Undo failed: ' + ((r && r.error) || 'unknown error') + '. Reload to check status.';
              undoBtn.disabled = false;
            }
          });
        });
        feedback.appendChild(undoBtn);
        timer = setTimeout(function () { if (onMoved) onMoved(); }, UNDO_WINDOW_MS);
      } else {
        timer = setTimeout(function () { if (onMoved) onMoved(); }, 2500);
      }
    }

    function dispose(disposition, extra) {
      setBusy(true);
      var body = Object.assign({ action: 'dispose', id: row.id, disposition: disposition }, extra || {});
      postBacklog(body).then(function (r) {
        setBusy(false);
        if (r && r.ok) {
          var label = disposition.toUpperCase() + (r.word && r.word !== disposition.toUpperCase() ? ' (' + r.word + ')' : '');
          showRowFeedback(label + '.', disposition === 'wontfix' ? null : { appended_suffix: r.appended_suffix });
        } else {
          showRowFeedback('Could not ' + disposition + ': ' + ((r && r.error) || 'unknown error'), null);
          actions.hidden = false;
        }
      });
    }

    function makeActionBtn(label, cls, handler) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = cls || 'ghost small';
      b.textContent = label;
      b.addEventListener('click', handler);
      return b;
    }

    actions.appendChild(makeActionBtn('Schedule', 'ghost small', function () { dispose('schedule'); }));
    actions.appendChild(makeActionBtn('Demote', 'ghost small', function () { dispose('demote'); }));
    actions.appendChild(makeActionBtn('Fold…', 'ghost small', function () {
      actions.hidden = true;
      confirmArea.hidden = false;
      confirmArea.innerHTML = '';
      var input = document.createElement('input');
      input.type = 'text';
      input.className = 'backlog-fold-input';
      input.placeholder = 'plan slug (optional)';
      input.setAttribute('aria-label', 'plan slug to fold ' + row.id + ' into');
      var confirmBtn = makeActionBtn('Confirm fold', 'btn-go small', function () {
        confirmArea.innerHTML = '';
        dispose('fold', { target: input.value.trim() });
      });
      var cancelBtn = makeActionBtn('Cancel', 'ghost small', function () { confirmArea.hidden = true; actions.hidden = false; });
      confirmArea.appendChild(input);
      confirmArea.appendChild(confirmBtn);
      confirmArea.appendChild(cancelBtn);
      input.focus();
    }));
    actions.appendChild(makeActionBtn('Wontfix…', 'ghost small backlog-wontfix-btn', function () {
      actions.hidden = true;
      confirmArea.hidden = false;
      confirmArea.innerHTML = '';
      var warn = document.createElement('span');
      warn.className = 'backlog-confirm-text';
      warn.textContent = 'Mark WONTFIX? This is permanent (no undo).';
      var yesBtn = makeActionBtn('Yes, WONTFIX', 'btn-go small', function () {
        confirmArea.innerHTML = '';
        dispose('wontfix');
      });
      var cancelBtn = makeActionBtn('Cancel', 'ghost small', function () { confirmArea.hidden = true; actions.hidden = false; });
      confirmArea.appendChild(warn);
      confirmArea.appendChild(yesBtn);
      confirmArea.appendChild(cancelBtn);
    }));

    detail.appendChild(actions);
    detail.appendChild(confirmArea);
    detail.appendChild(feedback);
    wrap.appendChild(detail);
    return wrap;
  }

  // ============================================================
  // add form — always visible (constraint 8: empty state carries the add
  // affordance; adding is not restricted to the empty state).
  // ============================================================
  function renderAddForm() {
    var form = document.createElement('form');
    form.className = 'backlog-add-form';
    form.setAttribute('aria-label', 'add a backlog row');

    var title = document.createElement('input');
    title.type = 'text';
    title.className = 'backlog-add-title';
    title.placeholder = 'add a backlog item…';
    title.setAttribute('aria-label', 'new backlog item title');

    var priority = document.createElement('select');
    priority.className = 'backlog-add-priority';
    priority.setAttribute('aria-label', 'priority');
    [['medium', 'medium'], ['high', 'high'], ['low', 'low']].forEach(function (opt) {
      var o = document.createElement('option');
      o.value = opt[0]; o.textContent = opt[1];
      priority.appendChild(o);
    });

    var desc = document.createElement('input');
    desc.type = 'text';
    desc.className = 'backlog-add-desc';
    desc.placeholder = 'detail (optional)…';
    desc.setAttribute('aria-label', 'new backlog item detail');

    var addBtn = document.createElement('button');
    addBtn.type = 'submit';
    addBtn.className = 'btn-go small';
    addBtn.textContent = 'Add';

    form.appendChild(title);
    form.appendChild(priority);
    form.appendChild(desc);
    form.appendChild(addBtn);

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var t = title.value.trim();
      if (!t) return;
      addBtn.disabled = true;
      postBacklog({ action: 'add', title: t, priority: priority.value, description: desc.value.trim() }).then(function (r) {
        addBtn.disabled = false;
        if (r && r.ok) {
          title.value = ''; desc.value = '';
          showGlobalFeedback('Added ' + r.id + '.', false);
          load();
        } else {
          showGlobalFeedback('Could not add: ' + ((r && r.error) || 'unknown error'), true);
        }
      });
    });
    return form;
  }

  // ============================================================
  // top-level render
  // ============================================================
  function renderTierGroup(tier, tierData) {
    var group = document.createElement('div');
    group.className = 'backlog-tier-group';
    var h = document.createElement('div');
    h.className = 'backlog-tier-title';
    h.textContent = TIER_LABELS[tier] + ' (' + tierData.total + ')';
    group.appendChild(h);
    if (tierData.rows.length === 0) {
      var none = document.createElement('div');
      none.className = 'backlog-tier-empty';
      none.textContent = 'none';
      group.appendChild(none);
      return group;
    }
    tierData.rows.forEach(function (row) {
      group.appendChild(renderOpenRow(row, load));
    });
    if (tierData.total > tierData.rows.length) {
      var more = document.createElement('div');
      more.className = 'backlog-tier-more';
      more.textContent = (tierData.total - tierData.rows.length) + ' more in this tier — see full list';
      group.appendChild(more);
    }
    return group;
  }

  function renderFullList(payload) {
    var wrap = document.createElement('div');
    wrap.className = 'backlog-full-list';

    var openSection = document.createElement('div');
    var openHead = document.createElement('div');
    openHead.className = 'backlog-tier-title';
    openHead.textContent = 'Open (' + payload.counts.open_total + ')';
    openSection.appendChild(openHead);
    var openRows = payload.full.filter(function (r) { return r.status === 'open'; });
    if (openRows.length === 0) {
      var none = document.createElement('div');
      none.className = 'backlog-tier-empty';
      none.textContent = 'none';
      openSection.appendChild(none);
    } else {
      openRows.forEach(function (row) { openSection.appendChild(renderOpenRow(row, load)); });
    }
    wrap.appendChild(openSection);

    var dispRows = payload.full.filter(function (r) { return r.status !== 'open'; });
    if (dispRows.length > 0) {
      var dispSection = document.createElement('div');
      var dispHead = document.createElement('div');
      dispHead.className = 'backlog-tier-title';
      dispHead.textContent = 'Dispositioned (' + dispRows.length + ')';
      dispSection.appendChild(dispHead);
      dispRows.forEach(function (row) { dispSection.appendChild(renderDispositionedRow(row)); });
      wrap.appendChild(dispSection);
    }
    return wrap;
  }

  var lastPayload = null;

  function renderIdeal(payload) {
    lastPayload = payload;
    root.innerHTML = '';

    globalFeedbackEl = document.createElement('div');
    globalFeedbackEl.className = 'backlog-global-feedback';
    globalFeedbackEl.setAttribute('aria-live', 'polite');
    globalFeedbackEl.hidden = true;
    root.appendChild(globalFeedbackEl);

    root.appendChild(renderAddForm());

    var header = document.createElement('div');
    header.className = 'backlog-header-row';
    var summary = document.createElement('span');
    summary.className = 'backlog-counts-summary';
    summary.textContent = payload.counts.open_total + ' open · ' + payload.counts.inflight_total +
      ' in flight · ' + payload.counts.terminal_total + ' closed';
    header.appendChild(summary);

    var fileHref = absoluteLinkHref(payload.file_path);
    if (fileHref) {
      var openLink = document.createElement('a');
      openLink.className = 'backlog-open-file-link';
      openLink.href = fileHref;
      openLink.target = '_blank';
      openLink.rel = 'noopener noreferrer';
      openLink.textContent = 'open backlog.md';
      header.appendChild(openLink);
    }

    var toggleBtn = document.createElement('button');
    toggleBtn.type = 'button';
    toggleBtn.className = 'ghost small backlog-toggle-btn';
    toggleBtn.textContent = showingFull ? 'Show compact view' : 'Show full list';
    toggleBtn.addEventListener('click', function () { showingFull = !showingFull; renderIdeal(lastPayload); });
    header.appendChild(toggleBtn);

    root.appendChild(header);

    setCount(payload.counts.open_total);

    var total = payload.counts.open_total + payload.counts.inflight_total + payload.counts.terminal_total;
    if (total === 0) {
      var empty = document.createElement('div');
      empty.className = 'pane-empty backlog-empty';
      empty.textContent = 'No backlog rows yet — add one above.';
      root.appendChild(empty);
      return;
    }

    if (showingFull) {
      root.appendChild(renderFullList(payload));
    } else {
      TIER_ORDER.forEach(function (tier) {
        root.appendChild(renderTierGroup(tier, payload.compact[tier]));
      });
    }
  }

  function load() {
    renderLoading();
    fetch('/api/backlog')
      .then(function (r) { return r.json(); })
      .then(function (resp) {
        if (!resp || resp.ok === false) {
          renderError(resp && resp.error ? resp.error : 'server returned ok:false');
          return;
        }
        renderIdeal(resp);
      })
      .catch(function (err) { renderError(String(err)); });
  }

  load();
})();
