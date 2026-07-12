'use strict';
/* asks.js — ask-rooted-workstreams-p1, Task 13 "UI landing — ask tree".
 *
 * REPLACES the Task 1 walking-skeleton stub wholesale with the full
 * ask-tree landing: project sections (collapsible) -> ask cards (summary +
 * one-click verbatim reference, progress narrative excerpt, aggregate plan
 * progress bar + an explicit drill-down control, waiting count, drift
 * badges), a collapsed "completed" group (review round 1/2 exit-mechanism
 * law), and lifecycle affordances (done/dismiss/merge) with success
 * feedback + undo (constraint 9). Drill-down is lazy: `/api/asks` (this
 * file's ONLY eager fetch) carries just enough to render the shallow card;
 * `/api/ask/<id>` (Task 11) is fetched on first expand of either the
 * verbatim reveal or the plan drill-down, and memoized per ask so both
 * reveals share one request.
 *
 * Anti-noise law (hard constraint 1): every string this module ever assigns
 * to a DOM text node is either (a) a hardcoded, reviewed, plain-English
 * literal below, or (b) server-prepared operator prose (`summary`,
 * `narrative_excerpt`, a §3 waiting-item `title`/`body`) that the payload
 * schema (Task 11) already scans for gate/hook identifiers before it ever
 * reaches the wire. This module never fabricates copy that mentions a
 * script, hook, or oracle name.
 *
 * Absolute-links law (hard constraint 2): the ONE place this module ever
 * sets a real `<a href>` is `absoluteLinkNode()`, which only accepts
 * http(s)/file:// /drive-letter/UNC/POSIX-absolute strings (mirrors
 * `server/payload-schema.js`'s `isAbsoluteHref`) — anything else renders as
 * plain text + a copy button, never a relative href. Plan-doc links are the
 * ONE documented exception (ux-review amendment 6): they resolve through
 * the EXISTING `/api/doc` + `/api/doc/open` handlers via the shared
 * `docModal` DOM (app.js already wires its close affordances — Esc,
 * docClose, docScrim — this module reuses those elements/handlers rather
 * than growing its own modal).
 */
(function () {
  var root = document.getElementById('askTreeBody');
  if (!root) return; // section not present on this page — no-op

  // ============================================================
  // small utilities
  // ============================================================
  function $(id) { return document.getElementById(id); }

  function formatAge(iso) {
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
    var d = Math.round(h / 24);
    return d + 'd ago';
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () {});
    }
  }

  function makeCopyBtn(text, label) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'ghost small ask-copy-btn';
    b.textContent = label || 'copy';
    b.title = 'copy "' + text + '" to clipboard';
    b.addEventListener('click', function (e) {
      e.stopPropagation();
      copyToClipboard(text);
      var orig = b.textContent;
      b.textContent = 'copied';
      setTimeout(function () { b.textContent = orig; }, 1200);
    });
    return b;
  }

  // isAbsoluteHref — mirrors server/payload-schema.js's isAbsoluteHref
  // exactly (same five accepted shapes) so this module never sets a
  // relative `<a href>` regardless of what a future field carries.
  function isAbsoluteHref(v) {
    if (typeof v !== 'string' || v === '') return false;
    if (/^https?:\/\//i.test(v)) return true;
    if (/^file:\/\//i.test(v)) return true;
    if (/^[A-Za-z]:[\\/]/.test(v)) return true;
    if (/^\\\\/.test(v)) return true;
    if (/^\//.test(v)) return true;
    return false;
  }

  function toFileUrl(p) {
    var norm = String(p).replace(/\\/g, '/');
    if (/^[A-Za-z]:\//.test(norm)) return 'file:///' + norm;
    if (/^\/\//.test(norm)) return null; // UNC — not worth the encoding risk; copy-only is the honest fallback
    if (/^\//.test(norm)) return 'file://' + norm;
    return null;
  }

  // absoluteLinkNode(value) — the ONE function in this module that ever
  // assigns a real `<a href>`. Any non-empty string reaches here (evidence
  // links, raw NEEDS-YOU.md links, needs-you.sh §3 `links[]` entries); only
  // an absolute shape becomes a clickable anchor (http(s) as-is, a local
  // absolute path best-effort converted to `file://`) — everything else is
  // plain text + a copy affordance, never a relative href (constraint 2).
  function absoluteLinkNode(value) {
    var wrap = document.createElement('span');
    wrap.className = 'ask-link-resolved';
    if (typeof value !== 'string' || value === '') {
      wrap.textContent = '(none)';
      return wrap;
    }
    if (/^https?:\/\//i.test(value)) {
      var a = document.createElement('a');
      a.href = value; a.target = '_blank'; a.rel = 'noopener noreferrer';
      a.textContent = value;
      wrap.appendChild(a);
      return wrap;
    }
    if (isAbsoluteHref(value)) {
      var fileUrl = toFileUrl(value);
      if (fileUrl) {
        var fa = document.createElement('a');
        fa.href = fileUrl; fa.target = '_blank'; fa.rel = 'noopener noreferrer';
        fa.textContent = value;
        wrap.appendChild(fa);
      } else {
        wrap.appendChild(document.createTextNode(value));
      }
      wrap.appendChild(makeCopyBtn(value, 'copy path'));
      return wrap;
    }
    // Not absolute — never rendered as a clickable href (constraint 2).
    // Plain text + copy so the reference is never silently dropped.
    wrap.appendChild(document.createTextNode(value));
    wrap.appendChild(makeCopyBtn(value));
    return wrap;
  }

  // openPlanDocModal(project, path) — reuses the EXISTING docModal DOM
  // app.js already renders/wires (docClose click, docScrim click, Escape
  // key all already close it regardless of who opened it) rather than
  // growing a second link-handling surface (ux-review amendment 6: "no
  // pane grows its own link handling"). Best-effort no-op if the shared
  // modal elements are absent from this page for any reason.
  function openPlanDocModal(project, docPath) {
    var docModal = $('docModal'), docTitle = $('docTitle'), docBody = $('docBody'), docOpenEditor = $('docOpenEditor');
    if (!docModal || !docTitle || !docBody) return;
    docTitle.textContent = project + ' / ' + docPath;
    docBody.textContent = 'loading…';
    docModal.hidden = false;
    fetch('/api/doc?project=' + encodeURIComponent(project) + '&path=' + encodeURIComponent(docPath))
      .then(function (r) { return r.json(); })
      .then(function (j) { docBody.textContent = j && j.ok ? j.content : ('error: ' + (j && j.error)); })
      .catch(function (err) { docBody.textContent = 'error: ' + err; });
    if (docOpenEditor) {
      docOpenEditor.onclick = function () {
        fetch('/api/doc/open', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ project: project, path: docPath }),
        }).catch(function () {});
      };
    }
  }

  // ============================================================
  // top-level render states (loading / error / empty / ideal —
  // constraint 8)
  // ============================================================
  function renderLoading() {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'ask-tree-status';
    box.innerHTML = '<div class="pane-loading" aria-busy="true">loading asks…</div>';
    root.appendChild(box);
  }

  function renderError(message) {
    root.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'ask-tree-status pane-error';
    box.setAttribute('role', 'alert');
    var h = document.createElement('div');
    h.className = 'pane-error-title';
    h.textContent = 'Could not load asks';
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
  }

  function renderFullyEmpty() {
    var box = document.createElement('div');
    box.className = 'ask-tree-status';
    box.innerHTML = '<div class="pane-empty">No asks registered yet. New sessions register their opening ask automatically — nothing to set up.</div>';
    return box;
  }

  // ============================================================
  // drift badges (Task 12 populates; always [] until it lands — the
  // affordance is built now so no later migration is needed).
  // ============================================================
  function renderDriftBadges(badges) {
    var wrap = document.createElement('span');
    wrap.className = 'ask-badges-row';
    (badges || []).forEach(function (b) {
      var label = (b && (b.label || b.type || b.note)) || 'drift';
      var det = document.createElement('details');
      det.className = 'ask-badge-details';
      var sum = document.createElement('summary');
      sum.className = 'chip ask-badge';
      sum.textContent = String(label); // text + color (a11y baseline) — never color-only
      det.appendChild(sum);
      var body = document.createElement('div');
      body.className = 'ask-badge-detail-body';
      // Task 12 hasn't defined the divergence-detail shape yet — render
      // whatever fields the badge object carries rather than guessing one.
      var lines = [];
      Object.keys(b || {}).forEach(function (k) {
        if (k === 'label' || k === 'type') return;
        lines.push(k + ': ' + String(b[k]));
      });
      body.textContent = lines.length ? lines.join(' · ') : 'divergence detail not yet available';
      det.appendChild(body);
      wrap.appendChild(det);
    });
    return wrap;
  }

  // ============================================================
  // detail fetch — memoized per ask id so the verbatim reveal and the
  // plan drill-down share one request (Behavioral Contracts: no oracle
  // shelling on the landing path; this is off that path entirely, fired
  // only on explicit operator expand).
  // ============================================================
  var detailCache = {}; // ask_id -> Promise<detailPayload|{__error:msg}>
  function getAskDetail(askId, forceReload) {
    if (!forceReload && detailCache[askId]) return detailCache[askId];
    var p = fetch('/api/ask/' + encodeURIComponent(askId))
      .then(function (r) { return r.json().then(function (j) { return { status: r.status, json: j }; }); })
      .then(function (r) {
        if (!r.json || r.json.ok === false) {
          return { __error: (r.json && r.json.error) || ('request failed (HTTP ' + r.status + ')') };
        }
        return r.json;
      })
      .catch(function (err) { return { __error: String(err) }; });
    detailCache[askId] = p;
    return p;
  }

  // ============================================================
  // sessions + spawn lineage (constraint: never a lost session — flat
  // grouping where no provenance edge exists).
  // ============================================================
  var HB_STATE_LABEL = { live: 'live', stale: 'stale', throttled: 'throttled', crashed: 'crashed', missing: 'no heartbeat' };
  function renderSessionRow(s, depth) {
    var li = document.createElement('li');
    li.className = 'ask-session-row';
    li.style.marginLeft = (depth * 16) + 'px';
    var chip = document.createElement('span');
    var st = s.state || 'missing';
    chip.className = 'chip ask-session-chip hb-' + st;
    chip.textContent = HB_STATE_LABEL[st] || st; // text + color, never color-only
    li.appendChild(chip);
    if (s.role) {
      var roleSpan = document.createElement('span');
      roleSpan.className = 'ask-session-role';
      roleSpan.textContent = s.role;
      li.appendChild(roleSpan);
    }
    var idSpan = document.createElement('span');
    idSpan.className = 'ask-session-id';
    idSpan.textContent = s.session_id;
    li.appendChild(idSpan);
    var copyBtn = document.createElement('button');
    copyBtn.type = 'button';
    copyBtn.className = 'ghost small ask-copy-btn';
    copyBtn.textContent = 'Copy session id';
    copyBtn.addEventListener('click', function () { copyToClipboard(s.session_id); var o = copyBtn.textContent; copyBtn.textContent = 'copied'; setTimeout(function () { copyBtn.textContent = o; }, 1200); });
    li.appendChild(copyBtn);
    var caption = document.createElement('span');
    caption.className = 'ask-session-copy-caption';
    caption.textContent = 'copy session id — resume with `claude --resume ' + s.session_id + '`';
    li.appendChild(caption);
    return li;
  }
  function renderSessionsList(sessions) {
    var list = document.createElement('ul');
    list.className = 'ask-session-list';
    if (!sessions || sessions.length === 0) {
      var none = document.createElement('div');
      none.className = 'pane-empty';
      none.textContent = 'no sessions recorded for this ask yet';
      return none;
    }
    // Lineage: a session with resumed_from pointing at another session in
    // this SAME set renders indented beneath its parent (spawn-lineage
    // edge); everything else — including a resumed_from that points
    // nowhere resolvable — renders flat, so no session is ever silently
    // dropped for lacking provenance.
    var byId = {};
    sessions.forEach(function (s) { byId[s.session_id] = s; });
    var childrenOf = {};
    var isChild = {};
    sessions.forEach(function (s) {
      if (s.resumed_from && byId[s.resumed_from] && s.resumed_from !== s.session_id) {
        childrenOf[s.resumed_from] = childrenOf[s.resumed_from] || [];
        childrenOf[s.resumed_from].push(s);
        isChild[s.session_id] = true;
      }
    });
    function appendWithChildren(s, depth, seen) {
      if (seen[s.session_id]) return; // cycle guard — never infinite-loop on bad data
      seen[s.session_id] = true;
      list.appendChild(renderSessionRow(s, depth));
      (childrenOf[s.session_id] || []).forEach(function (c) { appendWithChildren(c, depth + 1, seen); });
    }
    var seen = {};
    sessions.forEach(function (s) { if (!isChild[s.session_id]) appendWithChildren(s, 0, seen); });
    // Any session caught in a cycle/orphan gap never reached above still
    // renders flat rather than vanishing.
    sessions.forEach(function (s) { if (!seen[s.session_id]) list.appendChild(renderSessionRow(s, 0)); });
    return list;
  }

  // ============================================================
  // waiting items — real §3 block, or the NEVER-TERMINAL defect form
  // (constraint 9: always carries the violation notice + an absolute link
  // to the raw NEEDS-YOU.md entry + the source session id).
  // ============================================================
  function renderWaitingItem(item) {
    var box = document.createElement('div');
    if (item.defect) {
      box.className = 'ask-waiting-item ask-defect-form';
      box.setAttribute('role', 'note');
      var msg = document.createElement('div');
      msg.className = 'ask-defect-message';
      msg.textContent = item.message || 'context missing — session violated §3';
      box.appendChild(msg);
      var recovery = document.createElement('div');
      recovery.className = 'ask-defect-recovery';
      var label = document.createElement('span');
      label.textContent = 'Raw ledger entry: ';
      recovery.appendChild(label);
      recovery.appendChild(absoluteLinkNode(item.raw_link));
      box.appendChild(recovery);
      if (item.session_id) {
        var sessRow = document.createElement('div');
        sessRow.className = 'ask-defect-session';
        sessRow.appendChild(renderSessionRow({ session_id: item.session_id, role: 'source', state: 'missing' }, 0));
        box.appendChild(sessRow);
      }
      return box;
    }
    box.className = 'ask-waiting-item';
    var title = document.createElement('div');
    title.className = 'ask-waiting-title';
    title.textContent = item.title || '(untitled decision)';
    box.appendChild(title);
    var body = document.createElement('div');
    body.className = 'ask-waiting-body';
    body.textContent = item.body || '';
    box.appendChild(body);
    if (item.links && item.links.length) {
      var linksRow = document.createElement('div');
      linksRow.className = 'ask-waiting-links';
      item.links.forEach(function (l) { linksRow.appendChild(absoluteLinkNode(l)); });
      box.appendChild(linksRow);
    }
    if (item.session_id) {
      var sr = document.createElement('div');
      sr.className = 'ask-waiting-session';
      sr.appendChild(renderSessionRow({ session_id: item.session_id, role: 'source', state: 'missing' }, 0));
      box.appendChild(sr);
    }
    return box;
  }

  // ============================================================
  // per-plan drill-down block (MULTI-PLAN CARDS, review round 2: one
  // live-doc link per plan; per-task rows grouped by plan).
  // ============================================================
  var TASK_STATUS_LABEL = { done: 'done', in_flight: 'in flight', not_started: 'not started' };
  function taskStatusOf(t) { return t.done ? 'done' : (t.in_flight ? 'in_flight' : 'not_started'); }
  function renderPlanBlock(row) {
    var block = document.createElement('div');
    block.className = 'ask-plan-block';
    var head = document.createElement('div');
    head.className = 'ask-plan-head';
    var name = document.createElement('span');
    name.className = 'ask-plan-slug';
    name.textContent = row.plan_slug;
    head.appendChild(name);
    if (row.plan_doc && row.plan_doc.project && row.plan_doc.path) {
      var linkBtn = document.createElement('button');
      linkBtn.type = 'button';
      linkBtn.className = 'ghost small ask-plan-doc-link';
      linkBtn.textContent = 'View live plan doc';
      linkBtn.title = 'open ' + row.plan_doc.project + '/' + row.plan_doc.path + ' in the docs viewer';
      linkBtn.addEventListener('click', function () { openPlanDocModal(row.plan_doc.project, row.plan_doc.path); });
      head.appendChild(linkBtn);
    } else {
      var noDoc = document.createElement('span');
      noDoc.className = 'ask-plan-nodoc';
      noDoc.textContent = '(plan file not found)';
      head.appendChild(noDoc);
    }
    block.appendChild(head);
    if (!row.tasks || row.tasks.length === 0) {
      var empty = document.createElement('div');
      empty.className = 'pane-empty ask-plan-empty';
      empty.textContent = 'no tasks found for this plan';
      block.appendChild(empty);
      return block;
    }
    var list = document.createElement('ul');
    list.className = 'ask-task-list';
    row.tasks.forEach(function (t) {
      var li = document.createElement('li');
      li.className = 'ask-task-row';
      var status = taskStatusOf(t);
      var chip = document.createElement('span');
      chip.className = 'chip ask-task-status task-status-' + status;
      chip.textContent = TASK_STATUS_LABEL[status]; // text + color, never color-only
      li.appendChild(chip);
      var idSpan = document.createElement('span');
      idSpan.className = 'ask-task-id';
      idSpan.textContent = 'task ' + t.id;
      li.appendChild(idSpan);
      if (t.done && t.evidence_link) {
        var ev = document.createElement('span');
        ev.className = 'ask-task-evidence';
        ev.appendChild(document.createTextNode('evidence: '));
        ev.appendChild(absoluteLinkNode(t.evidence_link));
        li.appendChild(ev);
      }
      list.appendChild(li);
    });
    block.appendChild(list);
    return block;
  }

  function renderArtifact(a) {
    var row = document.createElement('div');
    row.className = 'ask-artifact-row';
    var sha = document.createElement('span');
    sha.className = 'ask-artifact-sha';
    sha.textContent = (a.sha || '').slice(0, 9);
    row.appendChild(sha);
    if (a.sha) row.appendChild(makeCopyBtn(a.sha));
    if (a.ts) {
      var ts = document.createElement('span');
      ts.className = 'ask-artifact-ts';
      ts.textContent = formatAge(a.ts);
      row.appendChild(ts);
    }
    if (a.evidence_link) row.appendChild(absoluteLinkNode(a.evidence_link));
    return row;
  }

  // ============================================================
  // drill-down body — populated on first expand from the memoized detail
  // fetch. Renders: per-plan blocks grouped by plan_slug (MULTI-PLAN
  // CARDS), waiting items (§3 block or defect form), sessions + lineage,
  // artifacts.
  // ============================================================
  function renderDrilldownBody(container, askId) {
    container.innerHTML = '<div class="pane-loading" aria-busy="true">loading plan detail…</div>';
    getAskDetail(askId).then(function (detail) {
      container.innerHTML = '';
      if (detail.__error) {
        var errBox = document.createElement('div');
        errBox.className = 'pane-error';
        errBox.setAttribute('role', 'alert');
        var t = document.createElement('div');
        t.className = 'pane-error-title';
        t.textContent = 'Could not load this ask’s detail';
        errBox.appendChild(t);
        var m = document.createElement('div');
        m.className = 'pane-error-cmd';
        m.textContent = detail.__error;
        errBox.appendChild(m);
        var retry = document.createElement('button');
        retry.type = 'button';
        retry.className = 'btn-go small';
        retry.textContent = 'Retry';
        retry.addEventListener('click', function () { getAskDetail(askId, true); renderDrilldownBody(container, askId); });
        errBox.appendChild(retry);
        container.appendChild(errBox);
        return;
      }
      var planRows = detail.plan_rows || [];
      var plansSection = document.createElement('div');
      plansSection.className = 'ask-plans-section';
      if (planRows.length === 0) {
        var noPlan = document.createElement('div');
        noPlan.className = 'pane-empty';
        noPlan.textContent = 'no plan linked yet';
        plansSection.appendChild(noPlan);
      } else {
        planRows.forEach(function (row) { plansSection.appendChild(renderPlanBlock(row)); });
      }
      container.appendChild(plansSection);

      var waitingSection = document.createElement('div');
      waitingSection.className = 'ask-waiting-section';
      waitingSection.id = 'ask-waiting-' + askId;
      waitingSection.tabIndex = -1;
      var waitingHead = document.createElement('div');
      waitingHead.className = 'ask-subhead';
      waitingHead.textContent = 'Waiting on you';
      waitingSection.appendChild(waitingHead);
      var waitingItems = detail.waiting_items || [];
      if (waitingItems.length === 0) {
        var noWaiting = document.createElement('div');
        noWaiting.className = 'pane-empty';
        noWaiting.textContent = 'nothing waiting on you for this ask';
        waitingSection.appendChild(noWaiting);
      } else {
        waitingItems.forEach(function (item) { waitingSection.appendChild(renderWaitingItem(item)); });
      }
      container.appendChild(waitingSection);

      var sessionsSection = document.createElement('div');
      sessionsSection.className = 'ask-sessions-section';
      var sessionsHead = document.createElement('div');
      sessionsHead.className = 'ask-subhead';
      sessionsHead.textContent = 'Sessions';
      sessionsSection.appendChild(sessionsHead);
      sessionsSection.appendChild(renderSessionsList(detail.sessions || []));
      container.appendChild(sessionsSection);

      var artifacts = detail.artifacts || [];
      if (artifacts.length) {
        var artSection = document.createElement('div');
        artSection.className = 'ask-artifacts-section';
        var artHead = document.createElement('div');
        artHead.className = 'ask-subhead';
        artHead.textContent = 'Artifacts';
        artSection.appendChild(artHead);
        artifacts.forEach(function (a) { artSection.appendChild(renderArtifact(a)); });
        container.appendChild(artSection);
      }
    });
  }

  function renderVerbatimBody(container, askId) {
    container.innerHTML = '<div class="pane-loading" aria-busy="true">loading…</div>';
    getAskDetail(askId).then(function (detail) {
      container.innerHTML = '';
      if (detail.__error) {
        var errBox = document.createElement('div');
        errBox.className = 'pane-error';
        errBox.setAttribute('role', 'alert');
        errBox.textContent = 'Could not load the verbatim reference: ' + detail.__error;
        container.appendChild(errBox);
        return;
      }
      if (!detail.verbatim_ref) {
        var none = document.createElement('div');
        none.className = 'pane-empty';
        none.textContent = 'no verbatim reference captured for this ask';
        container.appendChild(none);
        return;
      }
      var row = document.createElement('div');
      row.className = 'ask-verbatim-ref';
      var label = document.createElement('div');
      label.className = 'ask-verbatim-label';
      // Honest limitation (follow-up filed, not routed around): the
      // registry currently captures a REFERENCE (transcript path + prompt
      // offset), not the resolved prompt text itself — no read surface
      // exists yet to turn that pointer into displayed text, and building
      // one is server/* work outside this task's file ownership (Tasks
      // 11/12 own server/). This renders the real reference, absolute and
      // copyable, rather than a fabricated "original text" the current
      // architecture cannot actually produce.
      label.textContent = 'Capture reference (transcript path + prompt offset):';
      row.appendChild(label);
      row.appendChild(absoluteLinkNode(detail.verbatim_ref));
      container.appendChild(row);
    });
  }

  // ============================================================
  // lifecycle actions — done/dismiss/merge (operator-override exit path,
  // constraint 7) with success feedback + brief undo (constraint 9).
  // ============================================================
  function postLifecycle(askId, action, into) {
    var body = { action: action };
    if (into) body.into = into;
    return fetch('/api/ask/' + encodeURIComponent(askId) + '/lifecycle', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).then(function (r) { return r.json(); }).catch(function (err) { return { ok: false, error: String(err) }; });
  }

  var UNDO_WINDOW_MS = 8000;

  // renderLifecycleRow(ask, isCompleted, onMoved) — onMoved() is called
  // once the undo window has elapsed without an undo click, signalling the
  // caller to reload the whole landing (the card has now truly left the
  // active list / re-entered it — Task 12's auditor derivation may also
  // race this, so the next full load() is the source of truth either way).
  function renderLifecycleRow(ask, isCompleted, onMoved) {
    var row = document.createElement('div');
    row.className = 'ask-lifecycle-row';
    var feedback = document.createElement('div');
    feedback.className = 'ask-feedback-row';
    feedback.setAttribute('aria-live', 'polite');
    feedback.hidden = true;

    var actionsWrap = document.createElement('div');
    actionsWrap.className = 'ask-lifecycle-actions';

    function showFeedback(text, undoAction) {
      actionsWrap.hidden = true;
      feedback.hidden = false;
      feedback.innerHTML = '';
      var t = document.createElement('span');
      t.className = 'ask-feedback-text';
      t.textContent = text;
      feedback.appendChild(t);
      var timer = null;
      if (undoAction) {
        var undoBtn = document.createElement('button');
        undoBtn.type = 'button';
        undoBtn.className = 'ghost small ask-undo-btn';
        undoBtn.textContent = 'Undo';
        undoBtn.addEventListener('click', function () {
          if (timer) clearTimeout(timer);
          postLifecycle(ask.ask_id, 'reopen').then(function (r) {
            if (r && r.ok) {
              feedback.hidden = true;
              actionsWrap.hidden = false;
            } else {
              t.textContent = 'Undo failed: ' + ((r && r.error) || 'unknown error') + '. Reload to check status.';
            }
          });
        });
        feedback.appendChild(undoBtn);
      }
      timer = setTimeout(function () { if (onMoved) onMoved(); }, UNDO_WINDOW_MS);
    }

    function makeActionBtn(label, cls, handler) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = cls || 'ghost small';
      b.textContent = label;
      b.addEventListener('click', handler);
      return b;
    }

    if (isCompleted) {
      actionsWrap.appendChild(makeActionBtn('Reopen', 'ghost small', function () {
        postLifecycle(ask.ask_id, 'reopen').then(function (r) {
          if (r && r.ok) { showFeedback('Reopened.', null); if (onMoved) setTimeout(onMoved, 1200); }
          else showFeedback('Reopen failed: ' + ((r && r.error) || 'unknown error'), null);
        });
      }));
    } else {
      actionsWrap.appendChild(makeActionBtn('Done', 'btn-go small', function () {
        postLifecycle(ask.ask_id, 'done').then(function (r) {
          if (r && r.ok) showFeedback('Marked done.', true);
          else showFeedback('Could not mark done: ' + ((r && r.error) || 'unknown error'), null);
        });
      }));
      actionsWrap.appendChild(makeActionBtn('Dismiss', 'ghost small', function () {
        postLifecycle(ask.ask_id, 'dismiss').then(function (r) {
          if (r && r.ok) showFeedback('Dismissed.', true);
          else showFeedback('Could not dismiss: ' + ((r && r.error) || 'unknown error'), null);
        });
      }));
      var mergeBtn = makeActionBtn('Merge into…', 'ghost small', function () {
        mergeBtn.hidden = true;
        chooser.hidden = false;
      });
      actionsWrap.appendChild(mergeBtn);

      var chooser = document.createElement('div');
      chooser.className = 'ask-merge-chooser';
      chooser.hidden = true;
      var candidates = (getAllActiveAsks() || []).filter(function (a) { return a.ask_id !== ask.ask_id; });
      if (candidates.length === 0) {
        var noneMsg = document.createElement('span');
        noneMsg.className = 'ask-merge-none';
        noneMsg.textContent = 'no other active asks to merge into';
        chooser.appendChild(noneMsg);
      } else {
        candidates.forEach(function (c) {
          var opt = document.createElement('button');
          opt.type = 'button';
          opt.className = 'ghost small ask-merge-option';
          opt.textContent = c.summary || c.ask_id;
          opt.addEventListener('click', function () {
            postLifecycle(ask.ask_id, 'merge', c.ask_id).then(function (r) {
              if (r && r.ok) showFeedback('Merged into "' + (c.summary || c.ask_id) + '".', true);
              else showFeedback('Merge failed: ' + ((r && r.error) || 'unknown error'), null);
            });
          });
          chooser.appendChild(opt);
        });
      }
      var cancelChoose = document.createElement('button');
      cancelChoose.type = 'button';
      cancelChoose.className = 'ghost small';
      cancelChoose.textContent = 'Cancel';
      cancelChoose.addEventListener('click', function () { chooser.hidden = true; mergeBtn.hidden = false; });
      chooser.appendChild(cancelChoose);
      actionsWrap.appendChild(chooser);
    }

    row.appendChild(actionsWrap);
    row.appendChild(feedback);
    return row;
  }

  // ============================================================
  // ask card (shallow-first with lazy drill-down)
  // ============================================================
  function renderProgressArea(ask) {
    var wrap = document.createElement('div');
    var pp = ask.plan_progress || { done: 0, in_flight: 0, not_started: 0, total: 0 };
    if (!pp.total) {
      wrap.className = 'ask-noplan-note';
      wrap.textContent = 'no plan linked yet';
      return wrap;
    }
    wrap.className = 'ask-progress-row';
    var bar = document.createElement('div');
    bar.className = 'ask-progress-bar';
    bar.setAttribute('role', 'img');
    bar.setAttribute('aria-label', pp.done + ' of ' + pp.total + ' tasks done, ' + pp.in_flight + ' in flight');
    var segDone = document.createElement('div');
    segDone.className = 'ask-progress-seg seg-done';
    segDone.style.width = (100 * pp.done / pp.total) + '%';
    var segFlight = document.createElement('div');
    segFlight.className = 'ask-progress-seg seg-inflight';
    segFlight.style.width = (100 * pp.in_flight / pp.total) + '%';
    var segNot = document.createElement('div');
    segNot.className = 'ask-progress-seg seg-notstarted';
    segNot.style.width = (100 * pp.not_started / pp.total) + '%';
    bar.appendChild(segDone); bar.appendChild(segFlight); bar.appendChild(segNot);
    wrap.appendChild(bar);
    var text = document.createElement('span');
    text.className = 'ask-progress-text';
    text.textContent = pp.done + ' done · ' + pp.in_flight + ' in flight · ' + pp.not_started + ' not started';
    wrap.appendChild(text);

    // DRILL-DOWN SIGNIFIER (review round 1): an explicit control beside
    // the bar — the bar itself is never the sole click target. Native
    // <details>/<summary> gives a real chevron + keyboard/AT support for
    // free (same convention this app already uses for the reconciler
    // badge and per-gate health rows).
    var details = document.createElement('details');
    details.className = 'ask-drilldown-details';
    var summary = document.createElement('summary');
    summary.className = 'ask-drilldown-summary';
    summary.textContent = pp.total + (pp.total === 1 ? ' task' : ' tasks');
    details.appendChild(summary);
    var body = document.createElement('div');
    body.className = 'ask-drilldown-body';
    details.appendChild(body);
    var fetched = false;
    details.addEventListener('toggle', function () {
      if (details.open && !fetched) { fetched = true; renderDrilldownBody(body, ask.ask_id); }
    });
    wrap.appendChild(details);
    wrap._drilldownDetails = details; // exposed so the waiting-count button can open + scroll to it
    return wrap;
  }

  function renderAskCard(ask, isCompleted, onMoved) {
    var card = document.createElement('div');
    card.className = 'ask-card' + (isCompleted ? ' ask-card-completed' : '');

    var head = document.createElement('div');
    head.className = 'ask-card-head';
    var h3 = document.createElement('h3');
    h3.className = 'ask-card-title';
    h3.textContent = ask.summary || ask.ask_id;
    head.appendChild(h3);

    var meta = document.createElement('div');
    meta.className = 'ask-card-meta';
    meta.textContent = (ask.project ? ask.project + ' · ' : '') + 'last activity ' + formatAge(ask.activity_ts);
    head.appendChild(meta);
    card.appendChild(head);

    // verbatim — one click away (compact reveal, separate from the
    // heavier plan drill-down below).
    var verbatimDetails = document.createElement('details');
    verbatimDetails.className = 'ask-verbatim-details';
    var vSummary = document.createElement('summary');
    vSummary.className = 'ask-verbatim-summary';
    vSummary.textContent = 'Verbatim';
    verbatimDetails.appendChild(vSummary);
    var vBody = document.createElement('div');
    vBody.className = 'ask-verbatim-body';
    verbatimDetails.appendChild(vBody);
    var vFetched = false;
    verbatimDetails.addEventListener('toggle', function () {
      if (verbatimDetails.open && !vFetched) { vFetched = true; renderVerbatimBody(vBody, ask.ask_id); }
    });
    card.appendChild(verbatimDetails);

    var narrative = document.createElement('div');
    narrative.className = 'ask-narrative-excerpt';
    narrative.textContent = ask.narrative_excerpt || 'no progress events yet';
    card.appendChild(narrative);

    var progressArea = renderProgressArea(ask);
    card.appendChild(progressArea);

    var statusRow = document.createElement('div');
    statusRow.className = 'ask-status-row';
    if (ask.waiting_count > 0) {
      var waitBtn = document.createElement('button');
      waitBtn.type = 'button';
      waitBtn.className = 'chip ask-waiting-btn';
      waitBtn.textContent = ask.waiting_count + (ask.waiting_count === 1 ? ' item waiting on you' : ' items waiting on you');
      waitBtn.title = 'view in this ask’s plan detail below';
      waitBtn.addEventListener('click', function () {
        var det = progressArea._drilldownDetails;
        if (!det) return;
        det.open = true;
        setTimeout(function () {
          var target = document.getElementById('ask-waiting-' + ask.ask_id);
          if (target) { target.scrollIntoView({ block: 'nearest' }); target.focus(); }
        }, 60);
      });
      statusRow.appendChild(waitBtn);
    }
    statusRow.appendChild(renderDriftBadges(ask.drift_badges));
    card.appendChild(statusRow);

    card.appendChild(renderLifecycleRow(ask, isCompleted, onMoved));

    return card;
  }

  // ============================================================
  // project groups + completed group
  // ============================================================
  var allActiveAsksFlat = [];
  function getAllActiveAsks() { return allActiveAsksFlat; }

  function renderProjectGroup(group) {
    var details = document.createElement('details');
    details.className = 'ask-project-group';
    details.open = true; // expanded by default — cold-start scanning is the primary flow
    var summary = document.createElement('summary');
    summary.className = 'ask-project-summary';
    summary.textContent = group.project + ' (' + group.asks.length + ')';
    details.appendChild(summary);
    var body = document.createElement('div');
    body.className = 'ask-project-body';
    group.asks.forEach(function (ask) {
      body.appendChild(renderAskCard(ask, false, load));
    });
    details.appendChild(body);
    return details;
  }

  function renderCompletedGroup(completed) {
    if (!completed || completed.count === 0) return null; // hidden entirely — never an expanded empty shell (review round 2)
    var details = document.createElement('details');
    details.className = 'ask-completed-group';
    // collapsed by default (review round 1 exit-mechanism law)
    var summary = document.createElement('summary');
    summary.className = 'ask-completed-summary';
    summary.textContent = 'Completed (' + completed.count + ' · newest ' + formatAge(completed.newest_completed_ts) + ')';
    details.appendChild(summary);
    var body = document.createElement('div');
    body.className = 'ask-completed-body';
    (completed.asks || []).forEach(function (ask) {
      body.appendChild(renderAskCard(ask, true, load));
    });
    details.appendChild(body);
    return details;
  }

  // ============================================================
  // top-level render
  // ============================================================
  function renderLanding(payload) {
    root.innerHTML = '';
    var groups = payload.groups || [];
    var completed = payload.completed || { count: 0, asks: [] };
    allActiveAsksFlat = groups.reduce(function (acc, g) { return acc.concat(g.asks); }, []);

    var totalActive = allActiveAsksFlat.length;
    if (totalActive === 0 && completed.count === 0) {
      root.appendChild(renderFullyEmpty());
      return;
    }
    if (totalActive === 0) {
      var note = document.createElement('div');
      note.className = 'pane-empty';
      note.textContent = 'No active asks — see Completed below.';
      root.appendChild(note);
    } else {
      groups.forEach(function (g) { root.appendChild(renderProjectGroup(g)); });
    }
    var completedNode = renderCompletedGroup(completed);
    if (completedNode) root.appendChild(completedNode);
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
        renderLanding(resp);
      })
      .catch(function (err) { renderError(String(err)); });
  }

  load();
})();
