'use strict';
/* todo.js — ask-rooted-workstreams-p1, Task 14 "My To-Do pane".
 *
 * Renders the sidebar's My To-Do pane: ONE list built from TWO sources in
 * `docs/operator-todo.md` (server GET /api/todo), never a parallel store:
 *   - OPERATOR items ("## Operator items" section) — freely add/edit/check
 *     from this UI; every write round-trips through POST /api/todo and
 *     re-fetches (file is truth, UI is a view — Prove-it-works step 4).
 *   - POINTER items (the AUTO-marker section) — mechanically appended by
 *     `needs-you.sh`'s Task 4 splice, NEVER operator-editable here. Their
 *     checked state is DERIVED by Task 12's background auditor (auto-check
 *     on ledger resolution); this module renders that state, it never
 *     computes it. Review round 1: pointer items are visually DISTINCT from
 *     editable ones — a lock glyph, aria-disabled, an explicit tooltip
 *     ("resolves when you answer the underlying item — click to go there"),
 *     and navigation (to the raw NEEDS-YOU.md ledger, which carries the
 *     item's full §3 block) is the item's PRIMARY affordance (P1 = navigate;
 *     P2 — answering in place — is explicitly out of scope, sketch §7).
 *     PLUS the constraint-7 operator-override escape hatch ("Mark handled")
 *     for when the auditor's derivation can't see a resolution.
 *
 * Anti-noise law (hard constraint 1): every string here is either a
 * hardcoded reviewed literal below, or operator-authored to-do text
 * (free-form) / a needs-you.sh-authored decision title/body (already
 * cold-reader-linted at write time) — the server's GET /api/todo additionally
 * scans all three with payload-schema.js's containsDenylistedIdentifier
 * before they ever reach the wire, mirroring asks.js's own precedent.
 *
 * Absolute-links law (hard constraint 2): the ONE href this module ever
 * sets is the pointer item's "click to go there" link, built from the
 * server's `raw_link` (absolute path to NEEDS-YOU.md) — duplicated
 * absolute-href/file-url helpers below, matching asks.js's own duplication
 * (no shared client-side module system in this app).
 */
(function () {
  var root = document.getElementById('todoBody');
  if (!root) return; // pane not present on this page — no-op

  function $(id) { return document.getElementById(id); }

  // ============================================================
  // absolute-href helpers (duplicated from asks.js by this codebase's own
  // convention — see this file's header)
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

  // ============================================================
  // top-level render states (loading / error / empty / ideal — constraint 8)
  // ============================================================
  function renderLoading() {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'todo-status';
    box.innerHTML = '<div class="pane-loading" aria-busy="true">loading your to-do items…</div>';
    root.appendChild(box);
    setCount(null);
  }

  function renderError(message) {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'todo-status pane-error';
    box.setAttribute('role', 'alert');
    var h = document.createElement('div');
    h.className = 'pane-error-title';
    h.textContent = 'Could not load your to-do list';
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
    var el = $('todoCount');
    if (!el) return;
    el.textContent = (n === null || n === undefined) ? '—' : String(n) + ' open';
  }

  // ============================================================
  // writes (constraint 9: success feedback + mistake recovery on every one)
  // ============================================================
  function postTodo(body) {
    return fetch('/api/todo', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then(function (r) { return r.json(); }).catch(function (err) { return { ok: false, error: String(err) }; });
  }

  var globalFeedbackEl = null;
  var globalFeedbackTimer = null;
  function showFeedback(text, isError) {
    if (!globalFeedbackEl) return;
    if (globalFeedbackTimer) clearTimeout(globalFeedbackTimer);
    globalFeedbackEl.hidden = false;
    globalFeedbackEl.textContent = text;
    globalFeedbackEl.className = 'todo-global-feedback' + (isError ? ' todo-feedback-error' : ' todo-feedback-ok');
    globalFeedbackTimer = setTimeout(function () { globalFeedbackEl.hidden = true; }, isError ? 8000 : 3000);
  }

  // ============================================================
  // operator item row — editable + checkable (real <input>/<button>
  // elements throughout, ≥24px targets via CSS, aria-live feedback)
  // ============================================================
  function renderOperatorItem(item) {
    var row = document.createElement('div');
    row.className = 'todo-item todo-item-operator';

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.className = 'todo-checkbox';
    cb.checked = !!item.checked;
    cb.setAttribute('aria-label', (item.checked ? 'mark not done: ' : 'mark done: ') + item.text);
    cb.addEventListener('change', function () {
      var wasChecked = cb.checked;
      cb.disabled = true;
      postTodo({ action: 'toggle', index: item.index }).then(function (r) {
        if (r && r.ok) { showFeedback('Saved.', false); load(); }
        else {
          cb.checked = !wasChecked; // mistake recovery: revert the optimistic flip
          cb.disabled = false;
          showFeedback('Could not update: ' + ((r && r.error) || 'unknown error'), true);
        }
      });
    });
    row.appendChild(cb);

    var textSpan = document.createElement('span');
    textSpan.className = 'todo-item-text' + (item.checked ? ' todo-item-checked' : '');
    textSpan.textContent = item.text;
    row.appendChild(textSpan);

    var editBtn = document.createElement('button');
    editBtn.type = 'button';
    editBtn.className = 'ghost small todo-edit-btn';
    editBtn.textContent = 'Edit';
    editBtn.setAttribute('aria-label', 'edit "' + item.text + '"');
    editBtn.addEventListener('click', function () { startEdit(row, item, textSpan, editBtn); });
    row.appendChild(editBtn);

    return row;
  }

  function startEdit(row, item, textSpan, editBtn) {
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'todo-edit-input';
    input.value = item.text;
    input.setAttribute('aria-label', 'edit to-do text');
    var saveBtn = document.createElement('button');
    saveBtn.type = 'button';
    saveBtn.className = 'btn-go small';
    saveBtn.textContent = 'Save';
    var cancelBtn = document.createElement('button');
    cancelBtn.type = 'button';
    cancelBtn.className = 'ghost small';
    cancelBtn.textContent = 'Cancel';

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
      if (!text) { showFeedback('To-do text cannot be empty.', true); return; }
      saveBtn.disabled = true;
      postTodo({ action: 'edit', index: item.index, text: text }).then(function (r) {
        if (r && r.ok) { showFeedback('Saved.', false); load(); }
        else { saveBtn.disabled = false; showFeedback('Could not save: ' + ((r && r.error) || 'unknown error'), true); }
      });
    });
  }

  // ============================================================
  // pointer item row — DERIVED, never a checkbox lookalike (review round 1).
  // ============================================================
  function renderPointerItem(item) {
    var row = document.createElement('div');
    row.className = 'todo-item todo-item-pointer' + (item.checked ? ' todo-item-resolved' : '');

    var glyph = document.createElement('span');
    glyph.className = 'todo-pointer-glyph';
    glyph.setAttribute('role', 'button');
    glyph.setAttribute('aria-disabled', 'true');
    glyph.setAttribute('tabindex', '-1');
    glyph.title = 'resolves when you answer the underlying item — click to go there';
    glyph.setAttribute('aria-label', item.checked ? 'automatically resolved, read-only' : 'automatic, read-only — not directly editable');
    glyph.textContent = item.checked ? '🔒✓' : '🔒'; // lock (+ check when resolved) — text+color, never color-only
    row.appendChild(glyph);

    var body = document.createElement('div');
    body.className = 'todo-pointer-body';

    var titleRow = document.createElement('div');
    titleRow.className = 'todo-pointer-title';
    var href = absoluteLinkHref(item.raw_link);
    var link = document.createElement('a');
    link.className = 'todo-pointer-link';
    link.title = 'resolves when you answer the underlying item — click to go there';
    link.textContent = item.title || ('(untitled ' + (item.section || 'item') + ')');
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
    body.appendChild(titleRow);

    if (item.body) {
      var preview = document.createElement('div');
      preview.className = 'todo-pointer-preview';
      preview.textContent = item.body.length > 200 ? item.body.slice(0, 200) + '…' : item.body;
      body.appendChild(preview);
    }

    var meta = document.createElement('div');
    meta.className = 'todo-pointer-meta';
    var tierLabel = (item.tier && item.tier !== 'untiered') ? ('tier ' + item.tier) : 'no tier';
    var stateLabel = item.checked ? (item.operator_override ? 'marked handled by you' : 'resolved') : 'waiting on you';
    meta.textContent = (item.section || 'item') + ' · ' + tierLabel + ' · ' + stateLabel;
    body.appendChild(meta);

    row.appendChild(body);

    if (!item.checked) {
      var overrideBtn = document.createElement('button');
      overrideBtn.type = 'button';
      overrideBtn.className = 'ghost small todo-override-btn';
      overrideBtn.textContent = 'Mark handled';
      overrideBtn.title = 'use this if you already resolved it and the pointer did not auto-check';
      overrideBtn.addEventListener('click', function () {
        overrideBtn.disabled = true;
        postTodo({ action: 'pointer_override', needs_you_id: item.needs_you_id }).then(function (r) {
          if (r && r.ok) { showFeedback('Marked handled.', false); load(); }
          else { overrideBtn.disabled = false; showFeedback('Could not mark handled: ' + ((r && r.error) || 'unknown error'), true); }
        });
      });
      row.appendChild(overrideBtn);
    }

    return row;
  }

  // ============================================================
  // add form — always visible (constraint 8: empty state carries the add
  // affordance, but adding is not restricted to the empty state)
  // ============================================================
  function renderAddForm() {
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
        if (r && r.ok) { input.value = ''; showFeedback('Added.', false); load(); }
        else { showFeedback('Could not add: ' + ((r && r.error) || 'unknown error'), true); }
      });
    });
    return form;
  }

  // ============================================================
  // top-level render
  // ============================================================
  function renderIdeal(payload) {
    root.innerHTML = '';

    globalFeedbackEl = document.createElement('div');
    globalFeedbackEl.className = 'todo-global-feedback';
    globalFeedbackEl.setAttribute('aria-live', 'polite');
    globalFeedbackEl.hidden = true;
    root.appendChild(globalFeedbackEl);

    root.appendChild(renderAddForm());

    var operatorItems = payload.operator_items || [];
    var pointerItems = (payload.pointer_items || []).slice().sort(function (a, b) {
      // outstanding pointers first, resolved ones sink — mirrors the
      // ask-tree's own "active first, completed collapsed" ordering.
      return (a.checked === b.checked) ? 0 : (a.checked ? 1 : -1);
    });

    var openCount = operatorItems.filter(function (i) { return !i.checked; }).length +
      pointerItems.filter(function (i) { return !i.checked; }).length;
    setCount(openCount);

    var list = document.createElement('div');
    list.className = 'todo-list';
    if (operatorItems.length === 0 && pointerItems.length === 0) {
      var empty = document.createElement('div');
      empty.className = 'pane-empty todo-empty';
      empty.textContent = 'No to-do items yet — add one above. Items also appear automatically when a session parks a decision on you.';
      list.appendChild(empty);
    } else {
      operatorItems.forEach(function (it) { list.appendChild(renderOperatorItem(it)); });
      pointerItems.forEach(function (it) { list.appendChild(renderPointerItem(it)); });
    }
    root.appendChild(list);
  }

  function load() {
    renderLoading();
    fetch('/api/todo')
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
