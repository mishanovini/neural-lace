'use strict';
/* asks.js — ask-rooted-workstreams-p1, Task 1 WALKING SKELETON.
 *
 * This is deliberately the THINNEST possible client: fetch /api/asks,
 * render one card per ask with its chronological narrative lines. Task 13
 * REPLACES this file wholesale with the full ask-tree landing (project
 * grouping, plan progress bars + drill-down, lifecycle affordances, drift
 * badges, a11y contract citation to app.js's WCAG 2.2 AA header) — see the
 * plan's Task 13 spec. Until then this module is intentionally additive and
 * self-contained: it does not touch app.js's six-pane cockpit, and app.js
 * does not yet know this file exists (app.js becomes shell/router only at
 * Task 13).
 *
 * Anti-noise law (hard constraint 1): this renderer must never surface a
 * gate/hook identifier. It only ever prints the `summary`/narrative text
 * the server already prepared from progress-log events — plain sentences
 * like "task 3 verified done", never an oracle/gate name.
 */
(function () {
  var container = document.getElementById('asksSkeletonBody');
  if (!container) return; // section not present on this page — no-op

  function renderLoading() {
    container.innerHTML = '<div class="pane-loading" aria-busy="true">loading asks…</div>';
  }

  function renderError(message) {
    container.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'pane-error';
    box.setAttribute('role', 'alert');
    var h = document.createElement('div');
    h.className = 'pane-error-title';
    h.textContent = 'Could not load asks';
    box.appendChild(h);
    var msg = document.createElement('div');
    msg.className = 'pane-error-cmd';
    msg.textContent = String(message || 'unknown error');
    box.appendChild(msg);
    var retry = document.createElement('button');
    retry.className = 'btn-go small';
    retry.textContent = 'Retry';
    retry.addEventListener('click', load);
    box.appendChild(retry);
    container.appendChild(box);
  }

  function renderEmpty() {
    container.innerHTML = '';
    var p = document.createElement('div');
    p.className = 'pane-empty';
    p.textContent = 'No asks registered yet. New sessions register their opening ask automatically.';
    container.appendChild(p);
  }

  function renderAsks(asks) {
    container.innerHTML = '';
    if (!asks || asks.length === 0) { renderEmpty(); return; }
    asks.forEach(function (ask) {
      var card = document.createElement('div');
      card.className = 'ask-card';

      var h3 = document.createElement('h3');
      h3.textContent = ask.summary || ask.ask_id;
      card.appendChild(h3);

      var meta = document.createElement('div');
      meta.className = 'ask-card-meta';
      meta.textContent = (ask.project ? ask.project + ' · ' : '') + ask.ask_id;
      card.appendChild(meta);

      var narrative = Array.isArray(ask.narrative) ? ask.narrative : [];
      if (narrative.length === 0) {
        var none = document.createElement('div');
        none.className = 'ask-narrative-empty';
        none.textContent = 'no progress events yet';
        card.appendChild(none);
      } else {
        var ul = document.createElement('ul');
        ul.className = 'ask-narrative';
        narrative.forEach(function (line) {
          var li = document.createElement('li');
          li.textContent = line;
          ul.appendChild(li);
        });
        card.appendChild(ul);
      }

      container.appendChild(card);
    });
  }

  function load() {
    renderLoading();
    fetch('/api/asks')
      .then(function (r) { return r.json(); })
      .then(function (resp) {
        if (!resp || resp.ok === false) {
          renderError(resp && resp.error ? resp.error : 'server returned ok:false');
          return;
        }
        renderAsks(resp.asks || []);
      })
      .catch(function (err) {
        renderError(String(err));
      });
  }

  load();
})();
