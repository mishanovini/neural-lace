'use strict';
/* Workstreams cockpit client — NL Observability Program Wave O, task O.4
 * (specs-o §O.4). REPLACES the event-sourced tree/write-affordance client.
 * Every pane is a poll of a /api/pane/* endpoint whose payload is the SAME
 * derive-cache entry the server refreshes from the real `nl <sub> --json`
 * oracle (contract C5) — the acceptance bar every runtime scenario checks
 * is "what a pane displays equals what the oracle returns". This file
 * NEVER computes its own counts/states from raw data; it only renders what
 * the server already derived (CANONICAL-COUNTERS-01 applies to the UI too:
 * ux-review amendment 5).
 *
 * READ-ONLY v1 (orchestrator disposition): no write affordances anywhere.
 * The link-resolver (ux-review amendment 6) is the ONE component every pane
 * uses for links — no pane grows its own.
 * A11y baseline (ux-review amendment 12, WCAG 2.2 AA): chips are text+color
 * (never color-only), real buttons/anchors, visible focus, aria-live
 * regions on every pane body, drawer is role=dialog with focus management +
 * Esc-close, targets >=24px, text contrast >=4.5:1 (see app.css).
 */
(function () {
  var $ = function (id) { return document.getElementById(id); };

  // ---- element handles ---------------------------------------------------
  var reconcilerBadge = $('reconcilerBadge'), reconcilerDisclosureBody = $('reconcilerDisclosureBody'),
      refreshBtn = $('refreshBtn'), refreshFeedback = $('refreshFeedback'),
      interruptStrip = $('interruptStrip'),
      needsMeBody = $('needsMeBody'), statusBody = $('statusBody'),
      healthBody = $('healthBody'), costsBody = $('costsBody'),
      shippedBody = $('shippedBody'), backlogBody = $('backlogBody'),
      lastLookAnchor = $('lastLookAnchor'), markSeenBtn = $('markSeenBtn'),
      whyScrim = $('whyScrim'), whyDrawer = $('whyDrawer'),
      whyTitle = $('whyTitle'), whyBody = $('whyBody'), whyClose = $('whyClose'),
      docsBtn = $('docsBtn'), docScrim = $('docScrim'), docsPanel = $('docsPanel'),
      docsFilter = $('docsFilter'), docsBody = $('docsBody'), docsClose = $('docsClose'),
      docModal = $('docModal'), docTitle = $('docTitle'), docBody = $('docBody'),
      docOpenEditor = $('docOpenEditor'), docClose = $('docClose');

  // ============================================================
  // Link resolver (ux-review amendment 6) — the ONE component Q2/Q3/Q6 use.
  // http(s) -> <a target=_blank>; local/repo path -> the docs viewer
  // (/api/doc) + open-in-editor; unresolvable -> plain text + copy
  // affordance; a 40-hex or 7-hex-prefix token renders with a copy button
  // (SHAs get copy-to-clipboard per the amendment).
  // ============================================================
  var SHA_RE = /^[0-9a-f]{7,40}$/i;
  var DOC_PROJECT_HINT = 'neural-lace'; // this repo's own project key in config/projects.js

  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function () {});
    }
  }

  function makeCopyBtn(text, label) {
    var b = document.createElement('button');
    b.className = 'ghost small copy-btn';
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

  // resolveLink(raw) -> DOM node. raw may be a URL, a repo-relative path, or
  // a bare SHA. Never throws; unresolvable input still renders as visible
  // text + a copy affordance rather than disappearing.
  function resolveLink(raw) {
    var wrap = document.createElement('span');
    wrap.className = 'link-resolved';
    if (typeof raw !== 'string' || raw.length === 0) {
      wrap.textContent = '(empty)';
      return wrap;
    }
    if (/^https?:\/\//i.test(raw)) {
      var a = document.createElement('a');
      a.href = raw; a.target = '_blank'; a.rel = 'noopener noreferrer';
      a.textContent = raw;
      wrap.appendChild(a);
      return wrap;
    }
    if (SHA_RE.test(raw)) {
      var shaSpan = document.createElement('span');
      shaSpan.className = 'sha';
      shaSpan.textContent = raw.slice(0, 9);
      wrap.appendChild(shaSpan);
      wrap.appendChild(makeCopyBtn(raw));
      return wrap;
    }
    // Local/repo path -> docs viewer + open-in-editor, IF it looks like a
    // path this checkout can resolve (contains a slash or a known doc
    // extension). Otherwise: plain text + copy (unresolvable case).
    if (/[\\/]/.test(raw) || /\.(md|txt|json|sh|js)$/i.test(raw)) {
      var btn = document.createElement('button');
      btn.className = 'ghost small link-path-btn';
      btn.textContent = raw;
      btn.title = 'open in docs viewer';
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        openDoc(DOC_PROJECT_HINT, raw);
      });
      wrap.appendChild(btn);
      wrap.appendChild(makeCopyBtn(raw, 'copy path'));
      return wrap;
    }
    wrap.textContent = raw;
    wrap.appendChild(makeCopyBtn(raw));
    return wrap;
  }

  // ============================================================
  // Age / freshness rendering (ux-review amendments 1 + 4). Every
  // trust-bearing datum names its own age; stale accent when
  // age > 2x refresh interval OR the last refresh failed.
  // ============================================================
  var REFRESH_INTERVAL_MS = 30000; // matches derive-cache.js's default; re-read from /api/health once available
  function formatAge(iso) {
    if (!iso) return 'never';
    var ms = Date.now() - Date.parse(iso);
    if (isNaN(ms)) return 'unknown';
    if (ms < 0) ms = 0;
    var s = Math.round(ms / 1000);
    if (s < 60) return s + 's ago';
    var m = Math.round(s / 60);
    if (m < 60) return m + 'm ago';
    var h = Math.round(m / 60);
    return h + 'h ago';
  }
  function setAge(paneKey, iso, failed) {
    var el = document.querySelector('[data-age-for="' + paneKey + '"]');
    if (!el) return;
    el.textContent = 'derived ' + formatAge(iso) + (failed ? ' — STALE (last refresh failed)' : '');
    var ageMs = iso ? Date.now() - Date.parse(iso) : Infinity;
    el.classList.toggle('stale', failed || ageMs > 2 * REFRESH_INTERVAL_MS);
  }

  // ============================================================
  // Error / empty / loading states (ux-review amendment 1 — GLOBAL
  // INVARIANT: rc!=0 renders a named ERROR state with plain language,
  // stderr tail, the failing command line, and a Retry wired to the
  // refresh endpoint. NEVER the empty state on failure.)
  // ============================================================
  function renderError(container, paneResp) {
    container.innerHTML = '';
    var box = document.createElement('div');
    box.className = 'pane-error';
    box.setAttribute('role', 'alert');
    var h = document.createElement('div');
    h.className = 'pane-error-title';
    h.textContent = 'Derivation failed (rc=' + paneResp.rc + ')';
    box.appendChild(h);
    var cmd = document.createElement('div');
    cmd.className = 'pane-error-cmd';
    cmd.textContent = '$ ' + paneResp.command;
    box.appendChild(cmd);
    if (paneResp.stderr_tail) {
      var pre = document.createElement('pre');
      pre.className = 'pane-error-stderr';
      pre.textContent = paneResp.stderr_tail;
      box.appendChild(pre);
    }
    var retry = document.createElement('button');
    retry.className = 'btn-go small';
    retry.textContent = 'Retry';
    retry.addEventListener('click', forceRefresh);
    box.appendChild(retry);
    container.appendChild(box);
  }

  function renderLoading(container) {
    container.innerHTML = '<div class="pane-loading" aria-busy="true">loading…</div>';
  }

  // isLoading(resp) — rc === null means the server's cache has never
  // completed a refresh for this subcommand yet (cold start: the cache
  // entry is seeded {data:null, rc:null, ...} and the first background
  // refresh — kicked off asynchronously so it never blocks server.listen()
  // — may still be in flight). This is DISTINCT from rc !== 0 (a refresh
  // was attempted and failed): a still-loading pane must render the
  // loading state, never the error state, or a slow first `nl backlog` on
  // a large estate would flash a false "derivation failed" the instant the
  // page loads.
  function isLoading(resp) {
    return resp.rc === null || resp.rc === undefined;
  }

  // ============================================================
  // Pane fetch/poll loop
  // ============================================================
  var lastPaneData = {}; // pane key -> last successfully-rendered payload (for interrupt strip / cross-pane reads)

  function fetchPane(pane, extraQuery) {
    return fetch('/api/pane/' + pane + (extraQuery || ''))
      .then(function (r) { return r.json(); })
      .catch(function (err) {
        return { schema: 1, pane: pane, data: null, rc: 1, stderr_tail: String(err), derived_at: null, command: 'nl ' + pane + ' --json' };
      });
  }

  function fetchReconciler() {
    return fetch('/api/reconciler').then(function (r) { return r.json(); }).catch(function () { return null; });
  }

  // ---- Q1 status pane ----
  function renderStatus(resp) {
    setAge('status', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(statusBody); return; }
    if (resp.rc !== 0 && !(resp.data && resp.data.sessions)) { renderError(statusBody, resp); return; }
    var sessions = (resp.data && resp.data.sessions) || [];
    lastPaneData.status = sessions;
    statusBody.innerHTML = '';
    if (sessions.length === 0) {
      // Q1 empty-state self-certifies against the heartbeat-pipeline health
      // (ux-review amendment 1). We don't have a separate pipeline-health
      // signal wired client-side yet (O.6's doctor predicate owns that);
      // render the honest oracle-named empty state without fabricating a
      // verdict we don't have.
      statusBody.innerHTML = '<div class="pane-empty">No live sessions (oracle: heartbeats dir, 0 files).</div>';
      return;
    }
    // Priority sort for attention-semantics (ux-review amendment 9):
    // waiting-on-me > crashed > stalled > throttled > blocked > working >
    // unobserved-cloud > unknown (mirrors od_sessions' own tie-break order,
    // C4 contract).
    var order = { 'waiting-on-me': 0, crashed: 1, stalled: 2, throttled: 3, blocked: 4, working: 5, 'unobserved-cloud': 6, unknown: 7 };
    var sorted = sessions.slice().sort(function (a, b) {
      return (order[a.state] != null ? order[a.state] : 9) - (order[b.state] != null ? order[b.state] : 9);
    });
    var list = document.createElement('ul');
    list.className = 'session-list';
    sorted.forEach(function (s) {
      var li = document.createElement('li');
      li.className = 'session-row session-state-' + s.state;
      var chip = document.createElement('span');
      chip.className = 'chip state-chip state-' + s.state;
      chip.textContent = s.state; // text + color, never color-only (a11y baseline)
      chip.title = chipTooltip(s.state);
      li.appendChild(chip);
      var meta = document.createElement('span');
      meta.className = 'session-meta';
      meta.textContent = s.session_id + '  branch=' + s.branch + (s.detail ? ' (' + s.detail + ')' : '');
      li.appendChild(meta);
      var whyBtn = document.createElement('button');
      whyBtn.className = 'ghost small why-btn';
      whyBtn.textContent = 'Why?';
      whyBtn.title = 'open the causal chain for this session (nl why)';
      whyBtn.addEventListener('click', function () { openWhyDrawer(s.session_id); });
      li.appendChild(whyBtn);
      list.appendChild(li);
    });
    statusBody.appendChild(list);
  }

  // Chip tooltips carry the mechanical derivation rule (ux-review amendment
  // 7 — "chips carry tooltips stating their mechanical derivation rule").
  function chipTooltip(state) {
    switch (state) {
      case 'waiting-on-me': return 'an OPEN needs-you ledger entry names this session (trumps all other states)';
      case 'crashed': return 'heartbeat stale AND recorded pid not alive';
      case 'stalled': return 'heartbeat stale AND recorded pid still alive';
      case 'throttled': return 'a throttle-detected ledger event is newer than this session\'s last activity';
      case 'blocked': return 'the newest ledger block event is newer than this session\'s last transcript activity';
      case 'working': return 'fresh heartbeat, none of the above conditions hold';
      case 'unobserved-cloud': return 'UNKNOWN — session seen only via ledger lifecycle/spawn events, no local heartbeat or transcript';
      default: return 'no local heartbeat or transcript; state cannot be derived (rendered as unknown, not fabricated)';
    }
  }

  // ---- Q2 needs-me pane ----
  function renderNeedsMe(resp) {
    setAge('needs-me', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(needsMeBody); return; }
    if (resp.rc !== 0 && !(resp.data && resp.data.items)) { renderError(needsMeBody, resp); return; }
    var items = (resp.data && resp.data.items) || [];
    lastPaneData.needsMe = items;
    needsMeBody.innerHTML = '';
    if (items.length === 0) {
      needsMeBody.innerHTML = '<div class="pane-empty">Nothing needs you right now (oracle: od_needs_me, 0 open items).</div>';
      return;
    }
    items.forEach(function (it) {
      var card = document.createElement('div');
      card.className = 'needs-me-card';
      var head = document.createElement('div');
      head.className = 'nm-head';
      var sec = document.createElement('span');
      sec.className = 'chip section-chip section-' + it.section;
      sec.textContent = it.section;
      head.appendChild(sec);
      var sessSpan = document.createElement('span');
      sessSpan.className = 'nm-session';
      if (it.session && lastPaneData.status && !lastPaneData.status.some(function (s) { return s.session_id === it.session; })) {
        sessSpan.textContent = 'session gone: ' + it.session; // ux-review amendment 5
        sessSpan.classList.add('session-gone');
      } else {
        sessSpan.textContent = 'session: ' + (it.session || 'unknown');
      }
      head.appendChild(sessSpan);
      card.appendChild(head);
      var text = document.createElement('div');
      text.className = 'nm-text';
      text.textContent = it.text;
      card.appendChild(text);
      if (it.links && it.links.length) {
        var linksRow = document.createElement('div');
        linksRow.className = 'nm-links';
        it.links.forEach(function (l) { linksRow.appendChild(resolveLink(l)); });
        card.appendChild(linksRow);
      }
      needsMeBody.appendChild(card);
    });
  }

  // ---- Q3 shipped pane ----
  function renderShipped(resp) {
    setAge('shipped', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(shippedBody); return; }
    if (resp.rc !== 0 && !resp.data) { renderError(shippedBody, resp); return; }
    var d = resp.data || {};
    var shas = d.shas || [], decisions = d.decisions || [], failures = d.failures || 0;
    lastPaneData.shipped = d;
    shippedBody.innerHTML = '';
    if (shas.length === 0 && decisions.length === 0 && failures === 0) {
      var since = lastLookAnchor.dataset.since || d.since || 'your last look';
      shippedBody.innerHTML = '<div class="pane-empty">Nothing shipped since your last look, ' + formatAge(since) + '.</div>';
      return;
    }
    var ul = document.createElement('ul');
    ul.className = 'shipped-list';
    shas.forEach(function (s) {
      var li = document.createElement('li');
      li.appendChild(resolveLink(s.sha));
      var subj = document.createElement('span');
      subj.className = 'shipped-subject';
      subj.textContent = ' ' + s.subject;
      li.appendChild(subj);
      ul.appendChild(li);
    });
    decisions.forEach(function (docName) {
      var li = document.createElement('li');
      li.className = 'shipped-decision';
      li.appendChild(resolveLink('docs/decisions/' + docName));
      ul.appendChild(li);
    });
    shippedBody.appendChild(ul);
    if (failures > 0) {
      var f = document.createElement('div');
      f.className = 'shipped-failures';
      f.textContent = failures + ' failure event(s) [block|downgrade] in window (oracle: od_shipped_since)';
      shippedBody.appendChild(f);
    }
  }

  // ---- Q4 health pane ----
  // O.4-fix1 item 1 (Q4 strip FAIL): the oracle (od_harness_health --json,
  // shelled directly by derive-cache.js's runHealth — see that file's
  // header for why `nl status` itself can't supply this) returns 15 gates
  // with 7d block/waiver/downgrade counts; this pane used to render only
  // the doctor verdict+age and NOTHING from .gates. Renders one expandable
  // row per gate (interaction-table amendment 8: "gate name click -> its
  // 7d numbers") via <details>/<summary> (natively keyboard-operable — no
  // custom JS focus handling needed), with waiver-dominant gates visibly
  // flagged (text label, not color-only — a11y baseline) using the ONE
  // --interrupt accent already reserved for interrupt-worthy classes.
  function renderHealth(resp) {
    setAge('health', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(healthBody); return; }
    if (resp.rc !== 0 && !(resp.data && resp.data.doctor)) { renderError(healthBody, resp); return; }
    var doctor = (resp.data && resp.data.doctor) || {};
    var gates = (resp.data && Array.isArray(resp.data.gates)) ? resp.data.gates : [];
    healthBody.innerHTML = '';
    var verdictRow = document.createElement('div');
    verdictRow.className = 'health-verdict';
    var isGreen = /GREEN/i.test(doctor.verdict || '');
    var isRed = /RED/i.test(doctor.verdict || '');
    var chip = document.createElement('span');
    chip.className = 'chip doctor-chip ' + (isRed ? 'doctor-red' : isGreen ? 'doctor-green' : 'doctor-unknown');
    chip.textContent = doctor.verdict || 'unavailable';
    verdictRow.appendChild(chip);
    var age = document.createElement('span');
    age.className = 'health-cache-age';
    age.textContent = ' as of ' + (doctor.ts ? formatAge(doctor.ts) : 'unknown');
    verdictRow.appendChild(age);
    healthBody.appendChild(verdictRow);

    if (gates.length === 0) return;
    var gateCount = document.createElement('div');
    gateCount.className = 'health-gate-count';
    gateCount.textContent = gates.length + ' gate(s) with block/waiver/downgrade activity in trailing 7d (oracle: od_harness_health)';
    healthBody.appendChild(gateCount);

    var list = document.createElement('div');
    list.className = 'health-gate-list';
    gates.forEach(function (g) {
      var det = document.createElement('details');
      det.className = 'health-gate-row' + (g.dominant === 'waiver' ? ' waiver-dominant' : '');
      var sum = document.createElement('summary');
      sum.className = 'health-gate-summary';
      var nameSpan = document.createElement('span');
      nameSpan.className = 'health-gate-name';
      nameSpan.textContent = g.gate;
      sum.appendChild(nameSpan);
      if (g.dominant === 'waiver') {
        var flag = document.createElement('span');
        flag.className = 'chip health-gate-flag';
        flag.textContent = 'waiver-dominant';
        sum.appendChild(flag);
      }
      det.appendChild(sum);
      var nums = document.createElement('div');
      nums.className = 'health-gate-numbers';
      nums.textContent = 'block=' + (g.block_7d || 0) + ' waiver=' + (g.waiver_7d || 0) +
        ' downgrade=' + (g.downgrade_7d || 0) + ' (dominant=' + (g.dominant || 'block') + ')';
      det.appendChild(nums);
      list.appendChild(det);
    });
    healthBody.appendChild(list);
  }

  // ---- Q5 costs pane ----
  // O.4-fix1 item 2 (Q5 strip FAIL): the oracle (od_costs --json) returns a
  // per-session breakdown (.sessions[], each with totals + transcript_status)
  // but this pane rendered ONLY the aggregate totals/throttle/truncation —
  // zero session rows against the oracle's 10-session set. Renders one
  // compact row per session (session id + totals + an honest
  // transcript_status label so the stale/partial per-session edge has a
  // surface to render on, per the FAIL's own note).
  function renderCosts(resp) {
    setAge('costs', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(costsBody); return; }
    if (resp.rc !== 0 && !(resp.data && resp.data.total)) { renderError(costsBody, resp); return; }
    var d = resp.data || {};
    var t = d.total || {};
    var sessions = Array.isArray(d.sessions) ? d.sessions : [];
    costsBody.innerHTML = '';
    var row = document.createElement('div');
    row.className = 'costs-row';
    row.textContent = 'in=' + (t.input_tokens || 0) + ' out=' + (t.output_tokens || 0) +
      ' cache_read=' + (t.cache_read_input_tokens || 0);
    costsBody.appendChild(row);
    var throttleRow = document.createElement('div');
    throttleRow.className = 'costs-row';
    throttleRow.textContent = (d.throttle_events || 0) + ' throttle event(s), ~' + (d.est_minutes_lost || 0) + ' min lost (oracle: od_costs)';
    costsBody.appendChild(throttleRow);
    if (d.truncated_to_recent) {
      var note = document.createElement('div');
      note.className = 'costs-note';
      note.textContent = '(truncated to the most-recently-modified transcripts)';
      costsBody.appendChild(note);
    }
    if (sessions.length > 0) {
      var table = document.createElement('table');
      table.className = 'costs-session-table';
      sessions.forEach(function (s) {
        var tr = document.createElement('tr');
        tr.className = 'costs-session-row';
        var sidTd = document.createElement('td');
        sidTd.className = 'costs-session-id';
        sidTd.textContent = s.session_id;
        tr.appendChild(sidTd);
        var totalsTd = document.createElement('td');
        totalsTd.className = 'costs-session-totals';
        totalsTd.textContent = 'in=' + (s.input_tokens || 0) + ' out=' + (s.output_tokens || 0) +
          ' cache_read=' + (s.cache_read_input_tokens || 0);
        tr.appendChild(totalsTd);
        var statusTd = document.createElement('td');
        var st = s.transcript_status || 'unknown';
        statusTd.className = 'chip costs-session-status costs-status-' + st;
        statusTd.textContent = st; // text + color, never color-only (a11y baseline)
        tr.appendChild(statusTd);
        table.appendChild(tr);
      });
      costsBody.appendChild(table);
    }
  }

  // ---- backlog health strip ----
  function renderBacklog(resp) {
    setAge('backlog', resp.derived_at, resp.rc !== 0 && !isLoading(resp));
    if (isLoading(resp)) { renderLoading(backlogBody); return; }
    if (resp.rc !== 0 && !(resp.data && 'open_total' in (resp.data || {}))) { renderError(backlogBody, resp); return; }
    var d = resp.data || {};
    backlogBody.innerHTML = '';
    var row = document.createElement('div');
    row.className = 'backlog-row';
    row.textContent = (d.open_total || 0) + ' open row(s), ' + (d.terminal_total || 0) + ' terminal (oracle: od_backlog_health)';
    backlogBody.appendChild(row);
    if (d.priority) {
      var p = document.createElement('div');
      p.className = 'backlog-row';
      p.textContent = 'priority: high=' + d.priority.high + ' medium=' + d.priority.medium + ' low=' + d.priority.low;
      backlogBody.appendChild(p);
    }
  }

  // ============================================================
  // Interrupt-priority strip (specs-o §O.4.3b — BINDING). Re-sorted VIEW
  // over the SAME status/needs-me data already rendered in the panes below
  // — never a separate source. On cold load, WAITING-ON-ME rows sort above
  // everything and open NEEDS-YOU entries render above Q3/Q4/Q5 in reading
  // order, both inside the initial viewport, ONE accent color reserved for
  // this class. Demotion is DERIVED, not sticky: a resolved item / a
  // heartbeat back to normal simply stops appearing here on the next
  // render (this function is called fresh every poll).
  // ============================================================
  function renderInterruptStrip() {
    var waitingSessions = (lastPaneData.status || []).filter(function (s) { return s.state === 'waiting-on-me'; });
    var openNeedsMe = lastPaneData.needsMe || [];
    interruptStrip.innerHTML = '';
    if (waitingSessions.length === 0 && openNeedsMe.length === 0) {
      interruptStrip.classList.add('quiet');
      interruptStrip.textContent = '';
      return;
    }
    interruptStrip.classList.remove('quiet');
    var n = waitingSessions.length + openNeedsMe.length;
    var label = document.createElement('span');
    label.className = 'interrupt-label';
    label.textContent = n + ' item(s) need you now:';
    interruptStrip.appendChild(label);
    waitingSessions.forEach(function (s) {
      var chip = document.createElement('span');
      chip.className = 'chip interrupt-chip';
      chip.textContent = 'session ' + s.session_id + ' (waiting-on-me)';
      interruptStrip.appendChild(chip);
    });
    openNeedsMe.forEach(function (it) {
      var chip = document.createElement('span');
      chip.className = 'chip interrupt-chip';
      chip.textContent = '[' + it.section + '] ' + (it.text || '').split('\n')[0].slice(0, 60);
      interruptStrip.appendChild(chip);
    });
  }

  // ============================================================
  // Reconciler badge (specs-o §O.4.3). Quiet state:
  // "reconciler: 0 drift (checked <ts>)". Firing: "drift: N claims" +
  // per-mismatch list. Clears on reconvergence (never latched — this is
  // recomputed fresh every poll from the server's check()).
  // ============================================================
  // renderBadgeDisclosure(mismatches) — O.4-fix1 item 4. Renders the
  // per-mismatch detail into the KEYBOARD-REACHABLE <details> body
  // (#reconcilerDisclosureBody) instead of the hover-only title=
  // tooltip the badge also still carries (kept for mouse users / as a
  // redundant cue, never the ONLY path to the same information — WCAG
  // 2.2 AA "content on hover" expectations). null/empty -> the body is
  // cleared so a stale mismatch list never lingers under an unrelated
  // badge state (e.g. after reconvergence or during an oracle-unavailable
  // state).
  function renderBadgeDisclosure(mismatches) {
    reconcilerDisclosureBody.innerHTML = '';
    if (!mismatches || mismatches.length === 0) return;
    var ul = document.createElement('ul');
    ul.className = 'reconciler-mismatch-list';
    mismatches.forEach(function (m) {
      var li = document.createElement('li');
      li.textContent = m.note;
      ul.appendChild(li);
    });
    reconcilerDisclosureBody.appendChild(ul);
  }

  function renderReconciler(result) {
    if (!result) {
      reconcilerBadge.textContent = 'reconciler: unavailable';
      reconcilerBadge.className = 'reconciler-badge reconciler-unknown';
      renderBadgeDisclosure(null);
      return;
    }
    // Degradation honesty (O.4-fix1 item 5): when the derived-truth oracle
    // itself is down (server.js's status cache entry has no usable
    // session data), the comparator has nothing trustworthy to diff
    // against — render an honest "oracle unavailable" (unknown/muted)
    // state, NEVER a drift count computed against an empty/dead
    // comparator (the real S8 bug: "drift: 9" during a simulated CLI
    // outage, which read as 9 REAL drifted sessions rather than "unknown
    // right now").
    if (result.oracle_unavailable) {
      reconcilerBadge.textContent = 'reconciler: oracle unavailable';
      reconcilerBadge.className = 'reconciler-badge reconciler-unknown';
      reconcilerBadge.title = 'derived-truth oracle (nl status) is currently unavailable — drift cannot be computed';
      renderBadgeDisclosure(null);
      return;
    }
    if (result.drift_count === 0) {
      reconcilerBadge.textContent = 'reconciler: 0 drift (checked ' + formatAge(result.checked_at) + ')';
      reconcilerBadge.className = 'reconciler-badge reconciler-quiet';
      reconcilerBadge.title = '';
      renderBadgeDisclosure(null);
    } else {
      reconcilerBadge.textContent = 'drift: ' + result.drift_count + ' claim(s)';
      reconcilerBadge.className = 'reconciler-badge reconciler-firing';
      reconcilerBadge.title = result.mismatches.map(function (m) { return m.note; }).join('\n') +
        '\n(Enter/click to see full details below)';
      renderBadgeDisclosure(result.mismatches);
    }
  }

  // ============================================================
  // Q6 why-drawer
  // ============================================================
  var whyLastFocused = null;
  function openWhyDrawer(sessionId) {
    whyLastFocused = document.activeElement;
    whyTitle.textContent = 'why: ' + sessionId;
    whyBody.innerHTML = '<div class="pane-loading" aria-busy="true">loading…</div>';
    whyScrim.hidden = false;
    whyDrawer.hidden = false;
    whyDrawer.focus();
    fetchPane('why', '?session=' + encodeURIComponent(sessionId) + '&last_block=1').then(function (resp) {
      whyBody.innerHTML = '';
      if (resp.rc !== 0 || !resp.data) {
        renderError(whyBody, resp);
        return;
      }
      var chain = resp.data.chain || [];
      if (chain.length === 0) {
        whyBody.innerHTML = '<div class="pane-empty">No ledger events for ' + sessionId +
          ' (oracle: signal ledger). Likely: cloud/unobserved session, or started before turn-tracing.<br>' +
          '<code>nl why ' + sessionId + ' --last-block</code></div>';
        return;
      }
      var table = document.createElement('table');
      table.className = 'why-chain';
      chain.forEach(function (row) {
        var tr = document.createElement('tr');
        ['ts', 'gate', 'event', 'detail'].forEach(function (f) {
          var td = document.createElement('td');
          td.textContent = row[f] || '';
          tr.appendChild(td);
        });
        table.appendChild(tr);
      });
      whyBody.appendChild(table);
      if (resp.data.transcript_status === 'absent') {
        var note = document.createElement('div');
        note.className = 'why-transcript-note';
        note.textContent = '(no transcript found for this session — ledger-only chain)';
        whyBody.appendChild(note);
      }
      // O.4-fix1 item 3 (Q6 verdict line FAIL): render the mandated
      // one-line verdict (what blocked, which state it read, what
      // happened next) whenever the payload carries one. server.js's
      // derive-cache.js runWhy() attaches `data.verdict` either straight
      // from od_why --json (once the lib fix lands — see that file's
      // header for the LIB DEPENDENCY this doesn't fix here) or, today,
      // via a text-mode fallback shell-out — so this render path is
      // agnostic to WHICH source produced the field and needs no future
      // change when the lib catches up.
      if (resp.data.verdict) {
        var verdictRow = document.createElement('div');
        verdictRow.className = 'why-verdict';
        verdictRow.textContent = resp.data.verdict;
        whyBody.appendChild(verdictRow);
      }
    });
  }
  function closeWhyDrawer() {
    whyScrim.hidden = true;
    whyDrawer.hidden = true;
    if (whyLastFocused && whyLastFocused.focus) whyLastFocused.focus();
  }
  whyClose.addEventListener('click', closeWhyDrawer);
  whyScrim.addEventListener('click', closeWhyDrawer);

  // Focus trap (O.4-fix1 item 4 — "trap sensibly", standard modal-dialog
  // convention / WCAG 2.4.11): while the why-drawer is open, Tab from the
  // LAST focusable descendant wraps to the FIRST, and Shift+Tab from the
  // FIRST wraps to the LAST, so keyboard focus can never escape into the
  // page behind the modal scrim. Queries focusable descendants fresh on
  // every keydown (the drawer body's content is re-rendered per session).
  function focusableIn(container) {
    return Array.prototype.slice.call(
      container.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')
    ).filter(function (el) { return !el.disabled && el.offsetParent !== null; });
  }
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      if (!whyDrawer.hidden) closeWhyDrawer();
      else if (!docModal.hidden) closeDocModal();
      else if (!docsPanel.hidden) closeDocsPanel();
      return;
    }
    if (e.key === 'Tab' && !whyDrawer.hidden) {
      var focusables = focusableIn(whyDrawer);
      if (focusables.length === 0) return;
      var first = focusables[0], last = focusables[focusables.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault(); last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault(); first.focus();
      }
    }
  });

  // ============================================================
  // Q3 Mark-seen control (ux-review amendment 3 — implicit-state-reset).
  // Advances the last-look anchor ONLY on this explicit click, with
  // feedback. First-use window is 24h (server default before any
  // Mark-seen has ever happened this session).
  // ============================================================
  var LAST_LOOK_KEY = 'workstreams.lastLookSince';
  function getStoredLastLook() {
    try { return localStorage.getItem(LAST_LOOK_KEY) || ''; } catch (_) { return ''; }
  }
  function setStoredLastLook(iso) {
    try { localStorage.setItem(LAST_LOOK_KEY, iso); } catch (_) {}
  }
  markSeenBtn.addEventListener('click', function () {
    var now = new Date().toISOString();
    setStoredLastLook(now);
    lastLookAnchor.dataset.since = now;
    lastLookAnchor.textContent = 'last look: just now';
    markSeenBtn.textContent = 'Seen ✓';
    setTimeout(function () { markSeenBtn.textContent = 'Mark seen'; }, 1200);
    fetchPane('shipped', '?since=' + encodeURIComponent(now)).then(renderShipped);
  });

  // ============================================================
  // Docs browser (kept — link-resolver backend)
  // ============================================================
  var docsLoaded = false, docsCache = {};
  function loadDocs() {
    return fetch('/api/docs').then(function (r) { return r.json(); }).then(function (j) {
      docsCache = (j && j.projects) || {};
      docsLoaded = true;
      renderDocsList('');
    });
  }
  function renderDocsList(filterText) {
    docsBody.innerHTML = '';
    Object.keys(docsCache).forEach(function (proj) {
      var files = docsCache[proj] || [];
      files.filter(function (f) { return !filterText || f.toLowerCase().indexOf(filterText.toLowerCase()) !== -1; })
        .forEach(function (f) {
          var row = document.createElement('button');
          row.className = 'doc-row ghost';
          row.textContent = proj + ' / ' + f;
          row.addEventListener('click', function () { openDoc(proj, f); });
          docsBody.appendChild(row);
        });
    });
  }
  docsFilter.addEventListener('input', function () { renderDocsList(docsFilter.value); });
  docsBtn.addEventListener('click', function () {
    docScrim.hidden = false;
    docsPanel.hidden = false;
    if (!docsLoaded) loadDocs();
  });
  function closeDocsPanel() { docScrim.hidden = true; docsPanel.hidden = true; }
  docsClose.addEventListener('click', closeDocsPanel);
  docScrim.addEventListener('click', function (e) { if (e.target === docScrim) { closeDocsPanel(); closeDocModal(); } });

  function openDoc(project, docPath) {
    docTitle.textContent = project + ' / ' + docPath;
    docBody.textContent = 'loading…';
    docModal.hidden = false;
    fetch('/api/doc?project=' + encodeURIComponent(project) + '&path=' + encodeURIComponent(docPath))
      .then(function (r) { return r.json(); })
      .then(function (j) {
        docBody.textContent = j && j.ok ? j.content : ('error: ' + (j && j.error));
      })
      .catch(function (err) { docBody.textContent = 'error: ' + err; });
    docOpenEditor.onclick = function () {
      fetch('/api/doc/open', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ project: project, path: docPath }),
      }).catch(function () {});
    };
  }
  function closeDocModal() { docModal.hidden = true; }
  docClose.addEventListener('click', closeDocModal);

  // ============================================================
  // Refresh control (ux-review amendment 4 — visible Refresh with
  // in-flight/succeeded/failed feedback)
  // ============================================================
  function forceRefresh() {
    refreshFeedback.textContent = 'refreshing…';
    refreshBtn.disabled = true;
    fetch('/api/refresh', { method: 'POST' }).then(function (r) { return r.json(); })
      .then(function (j) {
        var anyFail = j && j.results && Object.keys(j.results).some(function (k) { return j.results[k].rc !== 0; });
        refreshFeedback.textContent = anyFail ? 'refresh: one or more panes failed' : 'refresh: succeeded';
        refreshBtn.disabled = false;
        pollAll();
        setTimeout(function () { refreshFeedback.textContent = ''; }, 2500);
      })
      .catch(function (err) {
        refreshFeedback.textContent = 'refresh failed: ' + err;
        refreshBtn.disabled = false;
      });
  }
  refreshBtn.addEventListener('click', forceRefresh);

  // ============================================================
  // Poll loop — one pass fetches all six panes + the reconciler, renders
  // them, then re-derives the interrupt strip from the freshly-rendered
  // Q1/Q2 data. Cadence matches the server's own refresh cycle (30s
  // default); an SSE "refresh" event (pushed the instant the server's own
  // cache tick completes) triggers an out-of-band poll so the UI never
  // waits a FULL extra cycle behind the server.
  // ============================================================
  function pollAll() {
    renderLoadingIfEmpty();
    Promise.all([
      fetchPane('status').then(renderStatus),
      fetchPane('needs-me').then(renderNeedsMe),
      fetchPane('shipped', lastLookAnchor.dataset.since ? '?since=' + encodeURIComponent(lastLookAnchor.dataset.since) : '').then(renderShipped),
      fetchPane('health').then(renderHealth),
      fetchPane('costs').then(renderCosts),
      fetchPane('backlog').then(renderBacklog),
      fetchReconciler().then(renderReconciler),
    ]).then(renderInterruptStrip);
  }
  function renderLoadingIfEmpty() {
    [statusBody, needsMeBody, shippedBody, healthBody, costsBody, backlogBody].forEach(function (el) {
      if (!el.hasChildNodes()) renderLoading(el);
    });
  }

  // ---- init ----
  var storedSince = getStoredLastLook();
  if (storedSince) {
    lastLookAnchor.dataset.since = storedSince;
  } else {
    lastLookAnchor.dataset.since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  }
  lastLookAnchor.textContent = 'last look: ' + formatAge(lastLookAnchor.dataset.since);

  pollAll();
  setInterval(pollAll, REFRESH_INTERVAL_MS + 2000); // small offset so this poll lands just after the server's own tick

  var es = new EventSource('/api/events');
  es.addEventListener('refresh', function () { pollAll(); });
  es.onerror = function () { /* SSE reconnects automatically; polling loop is the fallback truth source regardless */ };

  // ui_build auto-reload (kept from the old server): poll /api/health,
  // reload if the served web assets changed under us.
  var bootUiBuild = null;
  function pollHealth() {
    fetch('/api/health').then(function (r) { return r.json(); }).then(function (j) {
      if (!j) return;
      if (bootUiBuild === null) { bootUiBuild = j.ui_build_ms; return; }
      if (j.ui_build_ms && j.ui_build_ms !== bootUiBuild) { location.reload(); }
    }).catch(function () {});
  }
  pollHealth();
  setInterval(pollHealth, 20000);
})();
