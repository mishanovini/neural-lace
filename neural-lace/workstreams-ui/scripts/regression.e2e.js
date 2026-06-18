#!/usr/bin/env node
// Workstreams GUI — browser regression suite (puppeteer).
//
// Status-surface redesign (Tasks 3/4/5, 2026-06-11): the suite now locks the
// COCKPIT → DRILL → WAITING design (docs/plans/workstreams-ui-status-surface-
// redesign-2026-06-11.md). The prior 8-bug locks that still apply carry over
// (modal overlay + selection sync, orphan-subagent exclusion, docs drawer,
// /api/health); the assertions that encoded the RETIRED global repo-tree and
// the color=KIND badges (old bugs #1/#9/#4) are superseded by cockpit/drill/
// amber-discipline assertions per the plan's In-flight scope updates (C6).
//
// Unlike the DOM-free node selftests (state/selftest.js, web/responsive.
// selftest.js), these run a REAL headless browser against the live server —
// the only way to catch CSS footguns and DOM-wiring bugs unit tests miss.
//
// Usage:
//   1. Start the GUI server:  node server/server.js   (default port 7733)
//   2. npm i -D puppeteer      (full, downloads Chromium)   OR
//      npm i -D puppeteer-core  (tiny — drives system Chrome via CHROME_PATH)
//   3. WS_URL=http://127.0.0.1:7733/ node scripts/regression.e2e.js
//      Optional: SHOT_DIR=<dir> saves JPEG screenshots of each surface.
//
// Exit 0 = all pass, 1 = a regression, 2 = harness error.
'use strict';
const fs = require('fs');
const path = require('path');
const URL = process.env.WS_URL || 'http://127.0.0.1:7733/';
const SHOT_DIR = process.env.SHOT_DIR || '';

// Prefer full puppeteer (bundled Chromium); fall back to puppeteer-core driving
// the system Chrome. The fallback keeps the suite runnable without the ~150MB
// Chromium download — it just needs a Chrome binary (CHROME_PATH or a default).
let puppeteer, launchOpts = { headless: 'new', args: ['--no-sandbox', '--disable-gpu'] };
try {
  puppeteer = require('puppeteer');
} catch (_) {
  try {
    puppeteer = require('puppeteer-core');
    const candidates = [process.env.CHROME_PATH,
      'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
      '/usr/bin/google-chrome', '/usr/bin/chromium-browser',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].filter(Boolean);
    const exe = candidates.find(p => { try { return fs.existsSync(p); } catch (_) { return false; } });
    if (!exe) { console.error('puppeteer-core found but no Chrome binary — set CHROME_PATH.'); process.exit(2); }
    launchOpts.executablePath = exe;
  } catch (__) {
    console.error('Install a driver: `npm i -D puppeteer` or `npm i -D puppeteer-core` (dev-only).');
    process.exit(2);
  }
}

const results = [];
const ok = (n, c, d) => results.push({ n, pass: !!c, d });
async function shot(page, name) {
  if (!SHOT_DIR) return;
  try {
    fs.mkdirSync(SHOT_DIR, { recursive: true });
    await page.screenshot({ path: path.join(SHOT_DIR, name + '.jpg'), type: 'jpeg', quality: 60 });
  } catch (e) { console.error('screenshot failed:', name, String(e).slice(0, 120)); }
}

// The oracle: re-derive the per-project lifecycle counts from /api/state with
// the SAME bucket definitions the plan locks (C3: states the reducer actually
// produces; waiting = unanswered Misha-asks + blocked). Cross-checked against
// the rendered cockpit so "counts match the reduced state" is a real assertion,
// not a self-reference.
const ORACLE_SRC = `(() => {
  const itemState = it => it.state ? it.state : it.checked ? 'shipped'
    : it.contested ? 'blocked' : (it.deferred || it.backlogged) ? 'committed' : 'in-flight';
  const ASK = { decision: 1, question: 1, action_item_for_user: 1 };
  const isAsk = it => { const c = it.details && it.details._category;
    return c ? !!ASK[c] : (it.kind === 'decision' || it.kind === 'question'); };
  const isOpen = it => ((!it.checked) || it.deferred || it.contested)
    && !it.backlogged && itemState(it) !== 'shipped';
  const isAwait = it => isOpen(it) && isAsk(it) && !it.responded;
  const needsYou = it => isAwait(it) || itemState(it) === 'blocked';
  return fetch('/api/state').then(r => r.json()).then(snap => {
    const byId = {}; (snap.nodes || []).forEach(n => byId[n.node_id] = n);
    const rootOf = id => { let n = byId[id], g = 0;
      while (n && n.parent_id != null && g++ < 50) n = byId[n.parent_id];
      return n ? n.node_id : id; };
    const perProj = {}; let waitTotal = 0; const needIds = {};
    (snap.nodes || []).forEach(n => {
      if (/^(sess|sub)-/.test(n.node_id)) return;
      if (n.state === 'archived') return;            // showArchived off in tests
      (n.items || []).forEach(it => {
        const p = rootOf(n.node_id);
        const c = perProj[p] = perProj[p] || { now: 0, next: 0, waiting: 0, done: 0, total: 0 };
        c.total++;
        const st = itemState(it);
        if (st === 'shipped') c.done++;
        else if (needsYou(it)) { c.waiting++; waitTotal++; needIds[it.item_id] = 1; }
        else if (st === 'committed') c.next++;
        else c.now++;
      });
    });
    return { perProj, waitTotal, needIds };
  });
})()`;

(async () => {
  const browser = await puppeteer.launch(launchOpts);
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  const errs = [];
  page.on('pageerror', e => errs.push(String(e.stack || e)));
  // Tasks 7/8 (2026-06-11, C5): NO native dialog (prompt/alert/confirm) may
  // fire anywhere in the suite — every reply / resolution is an in-surface
  // form. Counted across the whole run; asserted in T20.
  let nativeDialogs = 0;
  page.on('dialog', d => { nativeDialogs++; d.dismiss().catch(() => {}); });
  // fresh client state — the cockpit (not a persisted drill) must show first
  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 30000 });
  await page.evaluate(() => localStorage.clear());
  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 1400));
  const oracle = await page.evaluate(ORACLE_SRC);

  // T1 — cockpit renders: one count-row per project, 4 NUMBER pills each,
  // and NO item rows anywhere in the cockpit (counts not chips — Task 3).
  const t1 = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#treeCanvas .ck-row'));
    const pillRows = rows.map(r => Array.from(r.querySelectorAll('.ck-pill')));
    return {
      rows: rows.length,
      allHave4Pills: pillRows.every(p => p.length === 4),
      allNumeric: pillRows.every(p => p.every(x => /^\d+$/.test(x.textContent.trim()))),
      treeItems: document.querySelectorAll('#treeCanvas .tree-item').length,
      repoHeads: document.querySelectorAll('#treeCanvas .repo-head').length,
      colHead: !!document.querySelector('#treeCanvas .ck-cols'),
    };
  });
  ok(1, t1.rows >= 1 && t1.allHave4Pills && t1.allNumeric && t1.treeItems === 0
    && t1.repoHeads >= 1 && t1.colHead,
    `ckRows=${t1.rows} 4pills=${t1.allHave4Pills} numeric=${t1.allNumeric} ` +
    `treeItemsInCockpit=${t1.treeItems}(want0) repoHeads=${t1.repoHeads}`);

  // T2 — cockpit counts MATCH the reduced state (per-project cross-check
  // against the /api/state oracle above).
  const t2 = await page.evaluate(() => {
    const out = {};
    document.querySelectorAll('#treeCanvas .ck-row').forEach(r => {
      out[r.getAttribute('data-proj')] =
        Array.from(r.querySelectorAll('.ck-pill')).map(p => Number(p.textContent.trim()));
    });
    return out; // [now, next, waiting, done] per project
  });
  let mismatches = [];
  Object.keys(oracle.perProj).forEach(pid => {
    const want = oracle.perProj[pid], got = t2[pid];
    if (!got) { mismatches.push(pid + ':no-row'); return; }
    if (got[0] !== want.now || got[1] !== want.next || got[2] !== want.waiting || got[3] !== want.done) {
      mismatches.push(`${pid}: got ${got.join('/')} want ${want.now}/${want.next}/${want.waiting}/${want.done}`);
    }
  });
  ok(2, mismatches.length === 0,
    mismatches.length ? mismatches.slice(0, 3).join(' ; ') : `all ${Object.keys(oracle.perProj).length} project rows match the reduced state`);

  // T3 — fixed density: row heights constant even for the project with the
  // most items (a lopsided project shows a NUMBER, not overflowing chips).
  const t3 = await page.evaluate(() => {
    const hs = Array.from(document.querySelectorAll('#treeCanvas .ck-row'))
      .map(r => Math.round(r.getBoundingClientRect().height));
    return { min: Math.min(...hs), max: Math.max(...hs) };
  });
  ok(3, t3.max - t3.min <= 2 && t3.max <= 60, `rowHeights ${t3.min}..${t3.max}px (constant, bounded)`);
  await shot(page, 'cockpit-1280');

  // T4 — drill: click the busiest project's row (most waiting, then most
  // items — so the amber assertion below exercises real needs-you rows) →
  // bounded tree with C4 breadcrumb + project header; tiers nest.
  const busiest = Object.keys(oracle.perProj)
    .sort((a, b) => (oracle.perProj[b].waiting - oracle.perProj[a].waiting)
      || (oracle.perProj[b].total - oracle.perProj[a].total))[0];
  await page.click(`#treeCanvas .ck-row[data-proj="${busiest}"]`);
  await new Promise(r => setTimeout(r, 400));
  const t4 = await page.evaluate(() => {
    const x = el => el ? Math.round(el.getBoundingClientRect().x) : null;
    const tree = document.querySelector('#treeCanvas .drill-tree');
    const wsHead = tree && tree.querySelector('.ws > .ws-head');
    const item = tree && tree.querySelector('.tree-item');
    return {
      drill: !!tree, back: !!document.querySelector('.drill-back'),
      title: (document.querySelector('.drill-title') || {}).textContent || '',
      rail: !!document.querySelector('.ck-rail'),
      wsCount: tree ? tree.querySelectorAll('.ws').length : 0,
      items: tree ? tree.querySelectorAll('.tree-item').length : 0,
      guideRails: tree ? tree.querySelectorAll('.tree-kids').length : 0,
      stepItem: (item && wsHead) ? x(item) - x(wsHead) : null,
    };
  });
  ok(4, t4.drill && t4.back && t4.title.length > 0 && t4.rail && t4.wsCount >= 1
    && t4.items >= 1 && t4.guideRails >= 1 && t4.stepItem >= 12,
    `drill=${t4.drill} back=${t4.back} title="${t4.title}" rail=${t4.rail} ` +
    `ws=${t4.wsCount} items=${t4.items} rails=${t4.guideRails} itemIndent=+${t4.stepItem}px`);

  // T5 — amber discipline (C6 prove-it): the set of amber-marked rows in the
  // drilled tree === the oracle's needs-you set. Amber on any non-needs-you
  // row = FAIL; a needs-you row without amber = FAIL.
  const t5 = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#treeCanvas .drill-tree .tree-item'));
    return rows.map(r => ({
      item: r.getAttribute('data-item'),
      amber: r.classList.contains('needs-you') || !!r.querySelector('.needs-dot'),
    }));
  });
  const amberWrong = t5.filter(r => r.amber !== !!oracle.needIds[r.item]);
  const amberCount = t5.filter(r => r.amber).length;
  ok(5, t5.length >= 1 && amberWrong.length === 0,
    `visibleRows=${t5.length} amberRows=${amberCount} mismatches=${amberWrong.length}` +
    (amberWrong.length ? ' :: ' + amberWrong.slice(0, 3).map(r => r.item).join(',') : ''));

  // T6 — C6 kind-color retirement: NO colored kind classes anywhere; kind is
  // expressed by neutral glyph icons.
  const t6 = await page.evaluate(() => ({
    kindColored: document.querySelectorAll(
      '.k-action, .k-decision, .k-question, .ti-badge, .li-kind.action, .li-kind.decision, .li-kind.question').length,
    kindIcons: document.querySelectorAll('#treeCanvas .ti-kind-ic').length,
  }));
  ok(6, t6.kindColored === 0 && t6.kindIcons >= 1,
    `kindColorClasses=${t6.kindColored}(want0) kindGlyphIcons=${t6.kindIcons}`);

  // T8a (measured BEFORE the T7 keyboard toggle mutates disclosure state) —
  // all-done branches are collapsed by default.
  const t8a = await page.evaluate(() => {
    const doneGroups = Array.from(document.querySelectorAll('#treeCanvas .drill-tree .ws.ws-done'));
    return {
      doneGroups: doneGroups.length,
      expandedDone: doneGroups.filter(g => g.querySelector('.tree-item')).length,
      itemsBefore: document.querySelectorAll('#treeCanvas .drill-tree .tree-item').length,
      toggle: !!document.querySelector('.drill-showdone'),
    };
  });

  // T7 — keyboard expand/collapse: focus the first twisty, press Enter,
  // aria-expanded flips (Task 5 prove-it step 4). Restore by clicking the
  // (re-rendered) twisty so the toggle leaves no residue in later checks.
  const before7 = await page.evaluate(() => {
    const tw = document.querySelector('#treeCanvas .drill-tree .ws .twisty');
    if (!tw) return null;
    tw.focus();
    return tw.getAttribute('aria-expanded');
  });
  await page.keyboard.press('Enter');
  await new Promise(r => setTimeout(r, 350));
  const after7 = await page.evaluate(() => {
    const tw = document.querySelector('#treeCanvas .drill-tree .ws .twisty');
    return tw ? tw.getAttribute('aria-expanded') : null;
  });
  await page.evaluate(() => {
    const tw = document.querySelector('#treeCanvas .drill-tree .ws .twisty');
    if (tw) tw.click();                            // restore prior state
  });
  await new Promise(r => setTimeout(r, 300));
  ok(7, before7 !== null && after7 !== null && before7 !== after7,
    `aria-expanded ${before7} -> ${after7} via keyboard Enter`);

  // T8 — done handling: default collapse (from t8a, measured in the current
  // drill) AND, non-vacuously, in the project with the MOST done items (via
  // the master-detail rail): done branches collapsed by default, "show done"
  // reveals completed items.
  const maxDone = Object.keys(oracle.perProj)
    .sort((a, b) => oracle.perProj[b].done - oracle.perProj[a].done)[0];
  await page.evaluate(() => { const b = document.querySelector('.drill-back'); if (b) b.click(); });
  await new Promise(r => setTimeout(r, 350));
  await page.click(`#treeCanvas .ck-row[data-proj="${maxDone}"]`);
  await new Promise(r => setTimeout(r, 400));
  const t8b = await page.evaluate(() => {
    const doneGroups = Array.from(document.querySelectorAll('#treeCanvas .drill-tree .ws.ws-done'));
    return {
      doneGroups: doneGroups.length,
      expandedDone: doneGroups.filter(g => g.querySelector('.tree-item')).length,
      itemsBefore: document.querySelectorAll('#treeCanvas .drill-tree .tree-item').length,
      toggle: !!document.querySelector('.drill-showdone'),
    };
  });
  let t8pass = t8a.toggle && t8a.expandedDone === 0 && t8b.toggle && t8b.expandedDone === 0;
  let t8d = `drill1: doneBranches=${t8a.doneGroups} expandedByDefault=${t8a.expandedDone}(want0) · ` +
    `maxDone(${maxDone}): doneBranches=${t8b.doneGroups} expandedByDefault=${t8b.expandedDone}(want0)`;
  if (t8b.toggle) {
    await page.click('.drill-showdone');
    await new Promise(r => setTimeout(r, 350));
    const itemsAfter = await page.evaluate(() =>
      document.querySelectorAll('#treeCanvas .drill-tree .tree-item').length);
    t8pass = t8pass && itemsAfter >= t8b.itemsBefore
      && (t8b.doneGroups === 0 || itemsAfter > t8b.itemsBefore);
    t8d += ` items ${t8b.itemsBefore}->${itemsAfter} after show-done`;
    await page.click('.drill-showdone');
    await new Promise(r => setTimeout(r, 250));
  }
  ok(8, t8pass, t8d);
  // return to the busiest drill for the modal lock below
  await page.evaluate(() => { const b = document.querySelector('.drill-back'); if (b) b.click(); });
  await new Promise(r => setTimeout(r, 300));
  await page.click(`#treeCanvas .ck-row[data-proj="${busiest}"]`);
  await new Promise(r => setTimeout(r, 400));
  await shot(page, 'drill-1280');

  // T11 (kept lock, old bugs #2/#5) — clicking a tree item opens the MODAL
  // OVERLAY (scrim + modal in front; list stays behind) and syncs .sel.
  await page.evaluate(() => { const ti = document.querySelector('#treeCanvas .drill-tree .tree-item'); if (ti) ti.click(); });
  await new Promise(r => setTimeout(r, 450));
  const t11 = await page.evaluate(() => {
    const m = document.querySelector('#detailModal');
    const scrim = document.querySelector('#detailScrim');
    const mr = m.getBoundingClientRect();
    return {
      modalVisible: !m.hidden, scrimVisible: !scrim.hidden, modalH: Math.round(mr.height),
      filterStillVisible: document.querySelector('#filterBody').offsetParent !== null,
      sel: document.querySelectorAll('#treeCanvas .tree-item.sel').length,
    };
  });
  ok(11, t11.modalVisible && t11.scrimVisible && t11.filterStillVisible && t11.modalH >= 200 && t11.sel === 1,
    `modal=${t11.modalVisible} scrim=${t11.scrimVisible} listBehind=${t11.filterStillVisible} modalH=${t11.modalH} sel=${t11.sel}`);
  await page.keyboard.press('Escape');
  await new Promise(r => setTimeout(r, 300));
  const dismissed = await page.evaluate(() =>
    document.querySelector('#detailModal').hidden && document.querySelector('#detailScrim').hidden);
  ok(12, dismissed, `modal+scrim hidden after Esc=${dismissed}`);

  // T9 — C4 return path: "← All projects" restores the cockpit (no dead-end).
  await page.click('.drill-back');
  await new Promise(r => setTimeout(r, 350));
  const t9 = await page.evaluate(() => ({
    ckRows: document.querySelectorAll('#treeCanvas .ck-row').length,
    drill: !!document.querySelector('#treeCanvas .drill-tree'),
  }));
  ok(9, t9.ckRows >= 1 && !t9.drill, `breadcrumb back: ckRows=${t9.ckRows} drillGone=${!t9.drill}`);

  // T10 — waiting-on-you list (Task 4): bounded (row count === oracle waiting
  // total) and context-complete — every row carries inline background/
  // recommendation OR a visible "context incomplete" marker; never a bare
  // contextless title painted as actionable.
  await page.click('.chip[data-filter="awaiting-me"]');
  await new Promise(r => setTimeout(r, 350));
  const t10 = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#filterBody .wait-row'));
    return {
      rows: rows.length,
      contextComplete: rows.filter(r => r.querySelector('.wait-ctx')).length,
      flaggedIncomplete: rows.filter(r => r.querySelector('.ctx-incomplete-badge')).length,
      bare: rows.filter(r => !r.querySelector('.wait-ctx') && !r.querySelector('.ctx-incomplete-badge')).length,
    };
  });
  ok(10, t10.rows === oracle.waitTotal && t10.bare === 0 && t10.rows >= 1,
    `waitRows=${t10.rows} (oracle=${oracle.waitTotal}) ctx=${t10.contextComplete} ` +
    `incomplete=${t10.flaggedIncomplete} bare=${t10.bare}(want0)`);
  await shot(page, 'waiting-1280');

  // T13 (kept lock, old bug #3) — stale-session surface excludes internal
  // subagent nodes + honest label.
  const t13 = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#orphanBody .orphan-row')).map(e => e.textContent);
    return { count: rows.length, head: (document.querySelector('.orphan-head') || {}).textContent || '',
             hasSubagent: rows.some(r => /subagent [0-9a-f]{8,}/i.test(r)) };
  });
  ok(13, !t13.hasSubagent && !/orphan/i.test(t13.head), `count=${t13.count} hasSubagent=${t13.hasSubagent} head="${t13.head.trim()}"`);

  // T14 (kept lock, old bug #6) — docs drawer opens populated.
  const b6btn = await page.evaluate(() => !!document.querySelector('#docsBtn'));
  let b6 = { open: false, rows: 0 };
  if (b6btn) {
    await page.click('#docsBtn'); await new Promise(r => setTimeout(r, 700));
    b6 = await page.evaluate(() => {
      const p = document.querySelector('#docsPanel'); const b = p.getBoundingClientRect();
      const inView = b.width > 10 && b.x < window.innerWidth && b.x + b.width > 0;
      return { open: !p.hidden && inView, rows: document.querySelectorAll('#docsBody .dp-proj, #docsBody .dp-dir, #docsBody .dp-file').length };
    });
    await page.keyboard.press('Escape'); await new Promise(r => setTimeout(r, 250));
  }
  ok(14, b6btn && b6.open, `btn=${b6btn} open=${b6.open} contentRows=${b6.rows}`);

  // T15 (kept lock, old bug #8) — /api/health reachable.
  const health = await page.evaluate(async () => { try { const r = await fetch('/api/health'); return await r.json(); } catch (e) { return { ok: false }; } });
  ok(15, health && health.ok === true, `health.ok=${health && health.ok}`);

  // T16 — responsive: 768 (cockpit usable) and 390 (drill = full swap, rail
  // hidden, breadcrumb still present — C4's ≤390px behavior).
  await page.setViewport({ width: 768, height: 1024 });
  await new Promise(r => setTimeout(r, 350));
  const t16a = await page.evaluate(() => ({
    ckRows: document.querySelectorAll('#treeCanvas .ck-row').length,
    overflow: document.documentElement.scrollWidth > window.innerWidth + 2,
  }));
  await shot(page, 'cockpit-768');
  await page.setViewport({ width: 390, height: 844 });
  await new Promise(r => setTimeout(r, 350));
  await page.evaluate(() => { const r = document.querySelector('#treeCanvas .ck-row'); if (r) r.click(); });
  await new Promise(r => setTimeout(r, 400));
  const t16b = await page.evaluate(() => {
    const rail = document.querySelector('.ck-rail');
    return {
      drill: !!document.querySelector('#treeCanvas .drill-tree'),
      railHidden: !rail || getComputedStyle(rail).display === 'none',
      back: !!document.querySelector('.drill-back'),
    };
  });
  await shot(page, 'drill-390');
  await page.evaluate(() => { const b = document.querySelector('.drill-back'); if (b) b.click(); });
  await new Promise(r => setTimeout(r, 350));
  await shot(page, 'cockpit-390');
  ok(16, t16a.ckRows >= 1 && !t16a.overflow && t16b.drill && t16b.railHidden && t16b.back,
    `768: rows=${t16a.ckRows} noOverflow=${!t16a.overflow} · 390: drill=${t16b.drill} ` +
    `railHidden=${t16b.railHidden} back=${t16b.back}`);

  // ====================================================================
  // Tasks 7/8 (2026-06-11) — backlog round-trip + context card + gate.
  // These tests WRITE events, so the suite must run against a COPY of the
  // live state (CONV_TREE_STATE_PATH), never the operator's real file.
  // ====================================================================
  await page.setViewport({ width: 1280, height: 800 });
  await new Promise(r => setTimeout(r, 350));
  const stamp = Date.now().toString(36);

  // T17 — backlog surface round-trip (Task 7 prove-it): add → it appears in
  // backlog and NOT in My-tasks; promote → it leaves backlog, the task lands
  // committed (Next) on the activated root, and NOW shows in My-tasks.
  const blText = 'e2e backlog roundtrip ' + stamp;
  await page.click('.chip[data-filter="backlog"]');
  await new Promise(r => setTimeout(r, 400));
  const t17a = await page.evaluate(() => ({
    addInput: !!document.querySelector('#filterBody .mytasks-add-input'),
    rows: document.querySelectorAll('#filterBody .bl-row').length,
  }));
  await page.type('#filterBody .mytasks-add-input', blText);
  await page.keyboard.press('Enter');
  await new Promise(r => setTimeout(r, 1200));
  const t17b = await page.evaluate(txt => {
    const rows = Array.from(document.querySelectorAll('#filterBody .bl-row'));
    const row = rows.find(r => (r.querySelector('.item-text') || {}).textContent === txt);
    return { present: !!row, rows: rows.length,
             promote: row ? !!row.querySelector('.ctrl-promote') : false };
  }, blText);
  await shot(page, 'backlog-add-1280');
  // the someday bucket must NOT leak into the active list before promote
  await page.click('.chip[data-filter="my-tasks"]');
  await new Promise(r => setTimeout(r, 400));
  const t17c = await page.evaluate(txt =>
    Array.from(document.querySelectorAll('#filterBody .mytask-row .item-text, #filterBody .mytask-row .mytask-text'))
      .some(e => e.textContent === txt), blText);
  // promote
  await page.click('.chip[data-filter="backlog"]');
  await new Promise(r => setTimeout(r, 400));
  await page.evaluate(txt => {
    const row = Array.from(document.querySelectorAll('#filterBody .bl-row'))
      .find(r => (r.querySelector('.item-text') || {}).textContent === txt);
    if (row) row.querySelector('.ctrl-promote').click();
  }, blText);
  await new Promise(r => setTimeout(r, 1600));
  const t17d = await page.evaluate(txt => {
    const inBacklog = Array.from(document.querySelectorAll('#filterBody .bl-row'))
      .some(r => (r.querySelector('.item-text') || {}).textContent === txt);
    return fetch('/api/state').then(r => r.json()).then(snap => {
      let task = null, parked = false, actNode = null;
      (snap.nodes || []).forEach(n => (n.items || []).forEach(it => {
        if (it.text !== txt) return;
        if (n.node_id === 'backlog-operator') { parked = true; return; }
        task = it; actNode = n;
      }));
      return { inBacklog, parkedStill: parked, taskFound: !!task,
               taskState: task ? task.state : null,
               taskOrigin: task ? task.origin : null,
               actOrigin: actNode ? actNode.origin : null };
    });
  }, blText);
  await page.click('.chip[data-filter="my-tasks"]');
  await new Promise(r => setTimeout(r, 400));
  const t17e = await page.evaluate(txt =>
    Array.from(document.querySelectorAll('#filterBody .mytask-row'))
      .some(r => (r.querySelector('.item-text, .mytask-text') || {}).textContent === txt), blText);
  await shot(page, 'mytasks-1280');
  await shot(page, 'backlog-promoted-1280');
  ok(17, t17a.addInput && t17b.present && t17b.promote && !t17c
    && !t17d.inBacklog && !t17d.parkedStill && t17d.taskFound
    && t17d.taskState === 'committed' && t17d.taskOrigin === 'operator'
    && t17d.actOrigin === 'backlog-activated' && t17e,
    `add=${t17b.present} inMyTasksBeforePromote=${t17c}(want false) ` +
    `leftBacklog=${!t17d.inBacklog} task=${t17d.taskFound}/${t17d.taskState}/${t17d.taskOrigin} ` +
    `activatedRoot=${t17d.actOrigin} inMyTasksAfter=${t17e}`);

  // T18 — context-COMPLETE decision card (Task 8 prove-it step 1): background,
  // each option's meaning+tradeoff, recommendation, reply affordances inline;
  // full detail behind "More context"; reply records via the IN-SURFACE form.
  const ctxNode = 'e2e-ctx-' + stamp, decId = 'e2e-dec-' + stamp;
  const decText = 'e2e context-complete decision ' + stamp;
  const posted = await page.evaluate(async (nodeId, itemId, txt) => {
    async function postEv(ev) {
      ev.actor = 'gui'; ev.ts = new Date().toISOString();
      ev.event_id = 'gui-e2e-' + Math.random().toString(36).slice(2);
      const r = await fetch('/api/event', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(ev) });
      return (await r.json());
    }
    const a = await postEv({ type: 'branch-opened', node_id: nodeId, parent_id: null, title: 'E2E context demo' });
    const b = await postEv({ type: 'decision-raised', node_id: nodeId, item_id: itemId, text: txt });
    const c = await postEv({ type: 'item-details-set', node_id: nodeId, item_id: itemId, details: {
      _category: 'decision',
      background: 'We are choosing the storage backend for the e2e demo. The current file store hits contention at 10 writers and the launch needs a call this week.',
      question: 'Adopt sqlite, or keep the file store with a write queue?',
      options: [
        { key: 'sqlite', name: 'Adopt sqlite', what_it_does: 'moves state into a single WAL-mode db', risk: 'migration effort', reversibility_cost: 'cheap', cost: '2 days' },
        { key: 'queue', name: 'Keep files + queue', what_it_does: 'serializes writers behind a queue', risk: 'queue becomes a bottleneck', reversibility_cost: 'free', cost: '1 day' },
      ],
      recommendation: { option_key: 'sqlite', reasoning: 'Contention is structural; queueing only defers it.' },
      reply_with: 'sqlite OR queue',
    }});
    return { a: a.ok, b: b.ok, c: c.ok };
  }, ctxNode, decId, decText);
  await new Promise(r => setTimeout(r, 1000));
  await page.click('.chip[data-filter="awaiting-me"]');
  await new Promise(r => setTimeout(r, 500));
  await page.evaluate(id => {
    const row = document.querySelector(`#filterBody .wait-row[data-item="${id}"]`);
    if (row) row.click();
  }, decId);
  await new Promise(r => setTimeout(r, 500));
  const t18 = await page.evaluate(() => {
    const card = document.querySelector('#dmBody .dc-essentials');
    const opts = Array.from(document.querySelectorAll('#dmBody .dc-opt-line'));
    const acts = document.querySelector('#detailModal .dm-actions') || document.querySelector('#dmActions');
    const actTexts = acts ? Array.from(acts.querySelectorAll('button')).map(b => b.textContent) : [];
    return {
      card: !!card,
      bg: !!(card && card.querySelector('.dc-bg') && card.querySelector('.dc-bg').textContent.length > 20),
      optLines: opts.length,
      meaningOnEveryOpt: opts.every(o => /—/.test(o.textContent) && /risk:/.test(o.textContent)),
      chooseBtns: document.querySelectorAll('#dmBody .dc-opt-choose').length,
      rec: !!document.querySelector('#dmBody .dc-rec-line'),
      reply: !!document.querySelector('#dmBody .dc-reply-line'),
      more: !!document.querySelector('#dmBody .dc-more'),
      gateNote: !!document.querySelector('.dm-gate-note'),
      approve: actTexts.some(t => /Approve/.test(t)),
    };
  });
  await shot(page, 'context-complete-1280');
  // reply via the in-surface form (never a native prompt)
  await page.evaluate(() => {
    const acts = document.querySelector('#detailModal .dm-actions') || document.querySelector('#dmActions');
    const b = Array.from(acts.querySelectorAll('button')).find(x => /Respond/.test(x.textContent));
    if (b) b.click();
  });
  await new Promise(r => setTimeout(r, 300));
  const t18form = await page.evaluate(() => !!document.querySelector('.dm-form textarea.dm-form-input'));
  await page.type('.dm-form .dm-form-input', 'e2e in-surface reply');
  await page.evaluate(() => {
    const f = document.querySelector('.dm-form');
    const go = Array.from(f.querySelectorAll('button')).find(x => /Send/.test(x.textContent));
    if (go) go.click();
  });
  await new Promise(r => setTimeout(r, 900));
  const t18resp = await page.evaluate(async (nodeId, itemId) => {
    const snap = await (await fetch('/api/state')).json();
    const n = (snap.nodes || []).find(x => x.node_id === nodeId);
    const it = n && (n.items || []).find(x => x.item_id === itemId);
    return !!(it && it.responded && /in-surface reply/.test(it.responded.text));
  }, ctxNode, decId);
  await page.keyboard.press('Escape');
  await new Promise(r => setTimeout(r, 300));
  ok(18, posted.a && posted.b && posted.c && t18.card && t18.bg && t18.optLines === 2
    && t18.meaningOnEveryOpt && t18.chooseBtns === 2 && t18.rec && t18.reply
    && t18.more && !t18.gateNote && t18.approve && t18form && t18resp,
    `card=${t18.card} bg=${t18.bg} opts=${t18.optLines} meaning=${t18.meaningOnEveryOpt} ` +
    `choose=${t18.chooseBtns} rec=${t18.rec} reply=${t18.reply} more=${t18.more} ` +
    `approve=${t18.approve} inSurfaceForm=${t18form} respondedRecorded=${t18resp}`);

  // T19 — context-INCOMPLETE gate (Task 8 prove-it step 2 + I2): a detail-less
  // decision renders the "context incomplete — needs enrichment" panel, and
  // EVERY resolving/lifecycle button is suppressed — the only affordance is
  // the respond/enrichment channel.
  const incId = 'e2e-inc-' + stamp;
  await page.evaluate(async (nodeId, itemId, stampArg) => {
    async function postEv(ev) {
      ev.actor = 'gui'; ev.ts = new Date().toISOString();
      ev.event_id = 'gui-e2e-' + Math.random().toString(36).slice(2);
      await fetch('/api/event', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(ev) });
    }
    await postEv({ type: 'decision-raised', node_id: nodeId, item_id: itemId,
                   text: 'e2e contextless decision ' + stampArg });
  }, ctxNode, incId, stamp);
  await new Promise(r => setTimeout(r, 900));
  await page.click('.chip[data-filter="awaiting-me"]');
  await new Promise(r => setTimeout(r, 400));
  await page.evaluate(id => {
    const row = document.querySelector(`#filterBody .wait-row[data-item="${id}"]`);
    if (row) row.click();
  }, incId);
  await new Promise(r => setTimeout(r, 500));
  const t19 = await page.evaluate(() => {
    const acts = document.querySelector('#detailModal .dm-actions') || document.querySelector('#dmActions');
    const btns = acts ? Array.from(acts.querySelectorAll('button')) : [];
    const txts = btns.map(b => b.textContent);
    return {
      panel: !!document.querySelector('#dmBody .dc-incomplete-panel'),
      panelText: (document.querySelector('#dmBody .dc-incomplete-h') || {}).textContent || '',
      essentials: !!document.querySelector('#dmBody .dc-essentials'),
      gateNote: !!document.querySelector('.dm-gate-note'),
      btnCount: btns.length,
      btnTexts: txts.join(' | '),
      resolving: txts.filter(t => /Approve|Decline|Answer|Mark done|Choose|Block|Commit|shipped|deployed/i.test(t)).length,
    };
  });
  await shot(page, 'context-incomplete-1280');
  await page.keyboard.press('Escape');
  await new Promise(r => setTimeout(r, 250));
  ok(19, t19.panel && /context incomplete/i.test(t19.panelText) && !t19.essentials
    && t19.gateNote && t19.resolving === 0 && t19.btnCount === 1,
    `panel=${t19.panel} "${t19.panelText}" gateNote=${t19.gateNote} ` +
    `buttons=${t19.btnCount}(want1: respond-only) resolving=${t19.resolving}(want0)`);

  // T20 — C5: the served client source carries ZERO native-prompt call sites,
  // and no native dialog fired anywhere in this suite.
  const appSrc = await page.evaluate(async () => await (await fetch('/app.js')).text());
  const promptHits = (appSrc.match(/window\.prompt/g) || []).length;
  ok(20, promptHits === 0 && nativeDialogs === 0,
    `window.prompt-in-source=${promptHits}(want0) nativeDialogsFired=${nativeDialogs}(want0)`);

  // ====================================================================
  // Task 10 (2026-06-12) — a11y/polish locks: overlay stack (I5), amber
  // chip discipline (C6), waiting-row ↔ card context_state parity.
  // ====================================================================

  // T21 — I5 overlay stack: opening the docs drawer moves focus INSIDE the
  // layer; Esc closes the TOPMOST layer and RESTORES focus to the opener;
  // no scrim lingers after the stack empties.
  await page.evaluate(() => { const b = document.querySelector('#docsBtn'); b.focus(); b.click(); });
  await new Promise(r => setTimeout(r, 600));
  const t21a = await page.evaluate(() => ({
    drawerOpen: !document.querySelector('#docsPanel').hidden,
    scrimShown: !document.querySelector('#docScrim').hidden,
    focusInside: document.querySelector('#docsPanel').contains(document.activeElement),
  }));
  await page.keyboard.press('Escape');
  await new Promise(r => setTimeout(r, 300));
  const t21b = await page.evaluate(() => ({
    drawerClosed: document.querySelector('#docsPanel').hidden,
    scrimHidden: document.querySelector('#docScrim').hidden,
    focusRestored: document.activeElement === document.querySelector('#docsBtn'),
  }));
  ok(21, t21a.drawerOpen && t21a.scrimShown && t21a.focusInside
    && t21b.drawerClosed && t21b.scrimHidden && t21b.focusRestored,
    `open: drawer=${t21a.drawerOpen} scrim=${t21a.scrimShown} focusInside=${t21a.focusInside} · ` +
    `Esc: closed=${t21b.drawerClosed} scrimHidden=${t21b.scrimHidden} focusRestored=${t21b.focusRestored}`);

  // T22 — C6 chip discipline: the amber count accent appears ONLY on the
  // needs-you-semantic chips (Waiting on you / Blocked) and only when > 0;
  // the retired chip-warn on shipped-not-deployed / stale-sessions is gone.
  // Plus the rename sweep: no "Conversation Tree" copy in the app chrome or
  // the served source's group label (item DATA may still say it — that is
  // operator data, not product copy).
  const t22 = await page.evaluate(() => {
    const warn = Array.from(document.querySelectorAll('#filterBar .chip-count.chip-warn'))
      .map(s => s.getAttribute('data-count'));
    const counts = {};
    document.querySelectorAll('#filterBar .chip-count').forEach(s => {
      counts[s.getAttribute('data-count')] = Number(s.textContent.trim());
    });
    const chrome = (document.querySelector('header').textContent || '')
      + (document.querySelector('#filterBar').textContent || '')
      + Array.from(document.querySelectorAll('.pane-title, .pane-head')).map(e => e.textContent).join(' ');
    return { warn, counts, chromeRenamed: !/conversation[\s-]?tree/i.test(chrome) };
  });
  const AMBER_OK = ['awaiting-me', 'blocked'];
  const badWarn = t22.warn.filter(f => AMBER_OK.indexOf(f) === -1 || !(t22.counts[f] > 0));
  const missingWarn = AMBER_OK.filter(f => t22.counts[f] > 0 && t22.warn.indexOf(f) === -1);
  const labelRenamed = !/Conversation Tree \/ Workstreams/.test(appSrc);
  ok(22, badWarn.length === 0 && missingWarn.length === 0 && t22.chromeRenamed && labelRenamed,
    `amberChips=[${t22.warn.join(',')}] badAmber=${badWarn.length}(want0) ` +
    `missingAmber=${missingWarn.length}(want0) chromeRenamed=${t22.chromeRenamed} wsLabelRenamed=${labelRenamed}`);

  // T23 — Task 10 row/card parity: every ASK row in the waiting list keys its
  // "context incomplete" marker to the SERVER-derived context_state — exactly
  // the predicate the detail-card gate uses, so row and card cannot disagree.
  await page.click('.chip[data-filter="awaiting-me"]');
  await new Promise(r => setTimeout(r, 400));
  const t23 = await page.evaluate(async () => {
    const snap = await (await fetch('/api/state')).json();
    const cs = {};
    (snap.nodes || []).forEach(n => (n.items || []).forEach(it => {
      if (it.context_state) cs[it.item_id] = it.context_state;
    }));
    const rows = Array.from(document.querySelectorAll('#filterBody .wait-row'));
    const mism = [];
    let asks = 0;
    rows.forEach(r => {
      const id = r.getAttribute('data-item');
      if (!(id in cs)) return;                    // non-ask rows carry no context_state
      asks++;
      const badge = !!r.querySelector('.ctx-incomplete-badge');
      const want = cs[id] !== 'complete';
      if (badge !== want) mism.push(id + ':' + cs[id] + '/badge=' + badge);
    });
    return { rows: rows.length, asks, mism };
  });
  ok(23, t23.mism.length === 0,
    `waitRows=${t23.rows} askRows=${t23.asks} parityMismatches=${t23.mism.length}` +
    (t23.mism.length ? ' :: ' + t23.mism.slice(0, 3).join(' ; ') : ''));

  ok(0, errs.length === 0, `pageErrors=${errs.length}${errs.length ? ' :: ' + errs[0].slice(0, 160) : ''}`);

  const pass = results.filter(r => r.pass).length;
  console.log(`\n=== Workstreams GUI regression ${pass}/${results.length} PASS ===`);
  results.sort((a, b) => a.n - b.n).forEach(r => console.log(`${r.pass ? 'PASS' : 'FAIL'}  T${r.n}  ${r.d}`));
  await browser.close();
  process.exit(results.every(r => r.pass) ? 0 : 1);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
