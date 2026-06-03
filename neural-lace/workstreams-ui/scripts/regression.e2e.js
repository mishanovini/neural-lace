#!/usr/bin/env node
// Workstreams GUI — browser regression suite (puppeteer).
//
// Locks the 8 bugs fixed 2026-06-02 (docs/reviews/2026-06-02-workstreams-gui-
// 8-bug-regression.md) so they cannot silently recur. Unlike the DOM-free
// node selftests (state/selftest.js, web/responsive.selftest.js), these run a
// REAL headless browser against the live server — the only way to catch CSS
// footguns (the `[hidden]` override that squeezed the detail card) and
// DOM-wiring bugs (selection sync, dropped drawer) that unit tests miss.
//
// Usage:
//   1. Start the GUI server:  node server/server.js   (default port 7733)
//   2. npm i -D puppeteer      (full, downloads Chromium)   OR
//      npm i -D puppeteer-core  (tiny — drives system Chrome via CHROME_PATH)
//   3. WS_URL=http://127.0.0.1:7733/ node scripts/regression.e2e.js
//
// Exit 0 = all pass, 1 = a regression, 2 = harness error.
'use strict';
const fs = require('fs');
const URL = process.env.WS_URL || 'http://127.0.0.1:7733/';

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

(async () => {
  const browser = await puppeteer.launch(launchOpts);
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });
  const errs = [];
  page.on('pageerror', e => errs.push(String(e.stack || e)));
  await page.goto(URL, { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 1400));

  // bug #1 — repo-grouped tree renders; projects nest under a repo header.
  const t = await page.evaluate(() => {
    const repoHead = document.querySelector('#treeCanvas .repo-group > .repo-head');
    const firstProj = document.querySelector('#treeCanvas .proj-head');
    let nested = false;
    if (repoHead && firstProj) nested = firstProj.getBoundingClientRect().x > repoHead.getBoundingClientRect().x + 8;
    return { repos: document.querySelectorAll('#treeCanvas .repo-group').length,
             projs: document.querySelectorAll('#treeCanvas .proj').length,
             items: document.querySelectorAll('#treeCanvas .tree-item').length, nested };
  });
  ok(1, t.repos >= 1 && t.projs >= 1 && t.items >= 1 && t.nested,
     `repos=${t.repos} projs=${t.projs} items=${t.items} projNestedUnderRepo=${t.nested}`);

  // bug #9 (flat-list regression, 2026-06-02 / repo+workstream tiers 2026-06-03)
  // The design hierarchy is Repo → Project → Workstream → WorkItem (kinds are
  // per-item BADGES, never the nesting axis). Assert the four tiers sit at
  // strictly-greater, perceptibly-stepped x AND that a real Workstream tier
  // (.ws) exists AND that the discarded kind-grouping (.tree-group) is GONE.
  // This catches both the original flat-list and the wrong kind-grouping fix.
  const tier = await page.evaluate(() => {
    const x = (el) => el ? Math.round(el.getBoundingClientRect().x) : null;
    const minX = els => { const xs = Array.from(new Set(els.map(x).filter(v => v != null))); return xs.length ? Math.min(...xs) : null; };
    const repoGroup = document.querySelector('#treeCanvas .repo-group.exp') || document.querySelector('#treeCanvas .repo-group');
    if (!repoGroup) return { err: 'no repo group' };
    const proj = repoGroup.querySelector('.proj.exp') || document.querySelector('#treeCanvas .proj.exp');
    if (!proj) return { err: 'no expanded project' };
    const repoX = x(repoGroup.querySelector(':scope > .repo-head'));
    const projX = x(proj.querySelector(':scope > .proj-head'));
    const wsX = minX(Array.from(proj.querySelectorAll('.ws > .ws-head')));
    const itemX = minX(Array.from(proj.querySelectorAll('.tree-item')));
    return {
      repoCount: document.querySelectorAll('#treeCanvas .repo-group').length,
      wsCount: proj.querySelectorAll('.ws').length,
      itemCount: proj.querySelectorAll('.tree-item').length,
      treeGroupCount: document.querySelectorAll('#treeCanvas .tree-group').length, // must be 0 (kind-grouping retired)
      repoX, projX, wsX, itemX,
      stepProj: (projX != null && repoX != null) ? projX - repoX : null,
      stepWs: (wsX != null && projX != null) ? wsX - projX : null,
      stepItem: (itemX != null && wsX != null) ? itemX - wsX : null,
    };
  });
  const tierPass = tier.repoCount >= 1 && tier.wsCount >= 1 && tier.itemCount >= 1
    && tier.treeGroupCount === 0
    && tier.stepProj >= 12 && tier.stepWs >= 12 && tier.stepItem >= 12;
  ok(9, tierPass, `repos=${tier.repoCount} ws=${tier.wsCount} items=${tier.itemCount} ` +
    `kindGroups=${tier.treeGroupCount}(want0) x: repo=${tier.repoX}->proj=${tier.projX}(+${tier.stepProj})` +
    `->ws=${tier.wsX}(+${tier.stepWs})->item=${tier.itemX}(+${tier.stepItem})`);

  // bug #4 — tree rows carry COLORED kind badges (not just a faint glyph).
  const b4 = await page.evaluate(() => {
    const badges = Array.from(document.querySelectorAll('#treeCanvas .tree-item .ti-badge'));
    const colored = badges.filter(b => { const c = getComputedStyle(b).backgroundColor; return c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent'; });
    return { count: badges.length, colored: colored.length };
  });
  ok(4, b4.count >= 1 && b4.colored === b4.count, `badges=${b4.count} colored=${b4.colored}`);

  // bug #3 — stale-session surface excludes internal subagent nodes + honest label.
  const b3 = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('#orphanBody .orphan-row')).map(e => e.textContent);
    return { count: rows.length, head: (document.querySelector('.orphan-head') || {}).textContent || '',
             hasSubagent: rows.some(r => /subagent [0-9a-f]{8,}/i.test(r)) };
  });
  ok(3, !b3.hasSubagent && !/orphan/i.test(b3.head), `count=${b3.count} hasSubagent=${b3.hasSubagent} head="${b3.head.trim()}"`);

  // bug #7 — show-completed toggle exists and re-renders without error (reveal
  // is data-dependent; assert wired + non-destructive: never HIDES open items).
  const b7toggle = await page.evaluate(() => !!document.querySelector('#showCompleted'));
  if (b7toggle) {
    const before = await page.evaluate(() => document.querySelectorAll('#treeCanvas .tree-item').length);
    const eb = errs.length;
    await page.click('#showCompleted'); await new Promise(r => setTimeout(r, 350));
    const after = await page.evaluate(() => document.querySelectorAll('#treeCanvas .tree-item').length);
    await page.click('#showCompleted'); await new Promise(r => setTimeout(r, 250));
    ok(7, after >= before && errs.length === eb, `toggle=true treeItems ${before}->${after}`);
  } else ok(7, false, 'no #showCompleted toggle');

  // bug #2 + #5 — click a tree item: detail card FILLS the pane (not a bottom
  // strip) AND the clicked tree row gets the .sel highlight.
  await page.evaluate(() => { const ti = document.querySelector('#treeCanvas .tree-item'); if (ti) ti.click(); });
  await new Promise(r => setTimeout(r, 450));
  const click = await page.evaluate(() => {
    const r = document.querySelector('#detailCard').getBoundingClientRect();
    return { cardH: Math.round(r.height), filterVisible: document.querySelector('#filterBody').offsetParent !== null,
             sel: document.querySelectorAll('#treeCanvas .tree-item.sel').length };
  });
  ok(2, click.cardH >= 250 && !click.filterVisible, `cardH=${click.cardH} filterStillVisible=${click.filterVisible}`);
  ok(5, click.sel === 1, `selTreeRows=${click.sel}`);

  // bug #6 — docs folder browser button opens a populated drawer (#docsPanel is
  // position:fixed so offsetParent is null — use hidden + in-viewport geometry).
  const b6btn = await page.evaluate(() => !!document.querySelector('#docsBtn'));
  let b6 = { open: false, rows: 0 };
  if (b6btn) {
    await page.click('#docsBtn'); await new Promise(r => setTimeout(r, 700));
    b6 = await page.evaluate(() => {
      const p = document.querySelector('#docsPanel'); const b = p.getBoundingClientRect();
      const inView = b.width > 10 && b.x < window.innerWidth && b.x + b.width > 0;
      return { open: !p.hidden && inView, rows: document.querySelectorAll('#docsBody .dp-proj, #docsBody .dp-dir, #docsBody .dp-file').length };
    });
  }
  ok(6, b6btn && b6.open, `btn=${b6btn} open=${b6.open} contentRows=${b6.rows}`);

  // bug #8 — /api/health reachable (heartbeat freshness is operational state).
  const health = await page.evaluate(async () => { try { const r = await fetch('/api/health'); return await r.json(); } catch (e) { return { ok: false }; } });
  ok(8, health && health.ok === true, `health.ok=${health && health.ok} heartbeat_stale=${health && health.heartbeat_stale}`);

  ok(0, errs.length === 0, `pageErrors=${errs.length}${errs.length ? ' :: ' + errs[0].slice(0, 160) : ''}`);

  const pass = results.filter(r => r.pass).length;
  console.log(`\n=== Workstreams GUI regression ${pass}/${results.length} PASS ===`);
  results.sort((a, b) => a.n - b.n).forEach(r => console.log(`${r.pass ? 'PASS' : 'FAIL'}  bug#${r.n}  ${r.d}`));
  await browser.close();
  process.exit(results.every(r => r.pass) ? 0 : 1);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
