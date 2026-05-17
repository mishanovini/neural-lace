'use strict';
// Conversation Tree UI — Walking Skeleton client (Phase 0).
// Reads the file-mediated state contract via the server's SSE stream and
// renders one node per branch-opened. NO framework, NO build step.
// The client only READS; it never spawns/steers a Claude Code session.

(function () {
  var treeEl = document.getElementById('tree');
  var emptyEl = document.getElementById('empty');
  var statusEl = document.getElementById('status');

  function render(snapshot) {
    var nodes = (snapshot && Array.isArray(snapshot.nodes)) ? snapshot.nodes : [];
    // Clear previous render (skeleton: full re-render; diffing is Phase C).
    treeEl.querySelectorAll('.node').forEach(function (n) { n.remove(); });

    if (nodes.length === 0) {
      emptyEl.style.display = '';
      return;
    }
    emptyEl.style.display = 'none';

    nodes.forEach(function (node) {
      var el = document.createElement('article');
      el.className = 'node' + (node.parent_id ? ' child' : '');
      el.setAttribute('data-node-id', node.id);

      var title = document.createElement('div');
      title.className = 'title';
      title.textContent = node.title;

      var meta = document.createElement('div');
      meta.className = 'meta';
      meta.textContent = (node.parent_id ? 'child of ' + node.parent_id + ' · ' : 'root · ') +
        (node.opened_at || '');

      el.appendChild(title);
      el.appendChild(meta);
      treeEl.appendChild(el);
    });
  }

  function connect() {
    var es = new EventSource('/api/events');
    es.addEventListener('state', function (e) {
      try { render(JSON.parse(e.data)); } catch (err) { /* ignore malformed frame */ }
      statusEl.textContent = 'live';
      statusEl.classList.add('live');
    });
    es.onerror = function () {
      statusEl.textContent = 'reconnecting…';
      statusEl.classList.remove('live');
      // EventSource auto-reconnects; no manual retry needed.
    };
  }

  connect();
})();
