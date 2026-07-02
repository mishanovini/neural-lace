'use strict';
/* Selftest for work-in-motion-sweep.js (Workstreams Phase R7).
 *
 * Runs against a TEMP state file via the CONV_TREE_STATE_PATH env override
 * (absolute precedence per state/resolve-state-path.js) — NEVER touches the
 * canonical tree-state.json. Also pins WORKSTREAMS_STATE_CONFIG to a
 * nonexistent file so the home-dir config can never leak in.
 *
 * Scenarios:
 *   T1  fixture ground truth (plans/branch/PR) produces the expected nodes,
 *       titles, and ONE unchecked+stateless item per node (the exact shape
 *       web/app.js itemState() derives 'in-flight' from)
 *   T2  IDEMPOTENCY: an immediate second sweep emits ZERO new events
 *   T3  gone effort -> item-shipped (shipped-not-deployed shape) + annotated +
 *       concluded; node leaves the open set
 *   T4  second sweep after the gone-handling emits ZERO new events
 *   T5  reactivation: effort back in ground truth -> re-opened +
 *       item-unchecked + item-committed
 *   T6  failed category collection (prsOk=false) suppresses gone-detection
 *       for that category (a fetch failure never concludes live work)
 *   T7  existing project root is REUSED (no duplicate root creation)
 *   T8  collectPlans: ACTIVE picked up, non-ACTIVE skipped, archive/ ignored
 *   T9  collectBranches against a real temp git repo: unmerged-unique branch
 *       found with the right uniqueCount; merged branch excluded
 *
 * Exit 0 = all pass; exit 1 otherwise.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'wim-sweep-'));
const TMP_STATE = path.join(tmpRoot, 'tree-state.json');
process.env.CONV_TREE_STATE_PATH = TMP_STATE;
process.env.WORKSTREAMS_STATE_CONFIG = path.join(tmpRoot, 'no-such-config.txt');

// Require AFTER the env override so state.js resolves STATE_FILE to the temp.
const sweepMod = require('./work-in-motion-sweep.js');
const state = require('../state/state.js');

let pass = 0, fail = 0;
function ok(name, cond, detail) {
  if (cond) { console.log('PASS: ' + name); pass++; }
  else { console.log('FAIL: ' + name + (detail ? ' — ' + detail : '')); fail++; }
}
function readSnap() {
  const st = state.readState({ statePath: TMP_STATE });
  return st.snapshot;
}
function nodeById(snap, id) { return (snap.nodes || []).find(n => n.node_id === id) || null; }

// Mirrors web/app.js itemState() (app.js:175-181) so the assertions verify the
// EXACT derivation the UI filters consume.
function uiItemState(it) {
  if (it.state) return it.state;
  if (it.checked) return 'shipped';
  if (it.contested) return 'blocked';
  if (it.deferred || it.backlogged) return 'committed';
  return 'in-flight';
}
function uiIsShippedNotDeployed(it) { return uiItemState(it) === 'shipped' && it.deployed !== true; }

// ---------------------------------------------------------------------------
// Fixture ground truth (one repo, all three categories)
// ---------------------------------------------------------------------------
function fixtureGT() {
  return [{
    repoKey: 'testrepo',
    rootNodeId: 'proj-testrepo',
    rootTitle: 'Test Repo',
    plansOk: true, plans: [
      { slug: 'alpha-plan', title: 'Alpha Plan' },
      { slug: 'beta-plan', title: 'Beta Plan' },
    ],
    branchesOk: true, branches: [{ name: 'feat/gamma', uniqueCount: 3 }],
    prsOk: true, prs: [{ number: 42, title: 'Add gamma support' }],
  }];
}

// ---- T1: first run ingests everything -------------------------------------
const r1 = sweep(fixtureGT(), true);
function sweep(gt, apply) { return sweepMod.sweep(gt, { apply: apply, statePath: TMP_STATE }); }

const brId = sweepMod.branchNodeId('testrepo', 'feat/gamma');
{
  // root(1) + 4 efforts x (branch-opened + action-added) = 9 events
  ok('T1 first run plans 9 events', r1.planned.length === 9, 'got ' + r1.planned.length);
  ok('T1 first run appends 9 events', r1.appended === 9, 'got ' + r1.appended);
  const snap = readSnap();
  const root = nodeById(snap, 'proj-testrepo');
  ok('T1 project root created', !!root && root.parent_id === null);
  const planN = nodeById(snap, 'wim-plan-alpha-plan');
  ok('T1 plan node exists with title', !!planN && planN.title === 'PLAN: Alpha Plan [ACTIVE]',
    planN && planN.title);
  ok('T1 plan node parented under root', !!planN && planN.parent_id === 'proj-testrepo');
  const brN = nodeById(snap, brId);
  ok('T1 branch node exists with title', !!brN && brN.title === 'BRANCH: feat/gamma (+3 unshipped)',
    brN && brN.title);
  const prN = nodeById(snap, 'wim-pr-testrepo-42');
  ok('T1 PR node exists with title', !!prN && prN.title === 'PR #42: Add gamma support',
    prN && prN.title);
  const allWim = [planN, nodeById(snap, 'wim-plan-beta-plan'), brN, prN];
  ok('T1 each effort node carries exactly ONE item',
    allWim.every(n => n && Array.isArray(n.items) && n.items.length === 1));
  ok('T1 items are unchecked + stateless => UI derives in-flight',
    allWim.every(n => uiItemState(n.items[0]) === 'in-flight'));
  ok('T1 no reducer rejections', !(snap.rejections || []).length,
    JSON.stringify(snap.rejections || []));
}

// ---- T2: idempotency -------------------------------------------------------
{
  const r2 = sweep(fixtureGT(), true);
  ok('T2 second run plans ZERO events', r2.planned.length === 0, 'got ' + r2.planned.length);
  ok('T2 second run appends ZERO events', r2.appended === 0, 'got ' + r2.appended);
  ok('T2 second run skipped the 4 existing efforts', r2.skippedExisting === 4, 'got ' + r2.skippedExisting);
}

// ---- T3: gone effort -------------------------------------------------------
{
  const gt = fixtureGT();
  gt[0].branches = []; // feat/gamma merged + deleted
  const r3 = sweep(gt, true);
  // item-shipped + annotated + concluded for the branch node
  ok('T3 gone effort plans 3 events', r3.planned.length === 3, 'got ' + r3.planned.length);
  const types = r3.planned.map(e => e.type).sort().join(',');
  ok('T3 gone events are shipped+annotated+concluded',
    types === 'annotated,concluded,item-shipped', types);
  const snap = readSnap();
  const brN = nodeById(snap, brId);
  ok('T3 branch node concluded', !!brN && brN.state === 'concluded', brN && brN.state);
  const it = brN.items[0];
  ok('T3 item is shipped-not-deployed (the UI filter shape)', uiIsShippedNotDeployed(it),
    JSON.stringify({ state: it.state, checked: it.checked, deployed: it.deployed }));
  ok('T3 item carries shipped_ts (recently-shipped window)', typeof it.shipped_ts === 'string');
  ok('T3 node carries the gone note', Array.isArray(brN.annotations) && brN.annotations.length === 1
    && /gone from ground truth/.test(brN.annotations[0].text));
  ok('T3 no reducer rejections (conclude passed FR-7)', !(snap.rejections || []).length,
    JSON.stringify(snap.rejections || []));
}

// ---- T4: idempotency after gone-handling -----------------------------------
{
  const gt = fixtureGT();
  gt[0].branches = [];
  const r4 = sweep(gt, true);
  ok('T4 re-run after gone-handling plans ZERO events', r4.planned.length === 0, 'got ' + r4.planned.length);
}

// ---- T5: reactivation -------------------------------------------------------
{
  const r5 = sweep(fixtureGT(), true); // feat/gamma is back
  const types = r5.planned.map(e => e.type).sort().join(',');
  ok('T5 reactivation plans re-opened+item-unchecked+item-committed',
    types === 'item-committed,item-unchecked,re-opened', types);
  const snap = readSnap();
  const brN = nodeById(snap, brId);
  ok('T5 branch node open again', !!brN && brN.state === 'open', brN && brN.state);
  ok('T5 item back in the non-complete set', brN.items[0].checked === false);
  ok('T5 item state explicitly committed', brN.items[0].state === 'committed', brN.items[0].state);
}

// ---- T6: failed category suppresses gone-detection --------------------------
{
  const gt = fixtureGT();
  gt[0].prsOk = false; gt[0].prs = []; gt[0].prsSkipReason = 'simulated auth failure';
  const r6 = sweep(gt, true);
  ok('T6 PR fetch failure emits nothing for the (live) PR node', r6.planned.length === 0,
    'got ' + r6.planned.length + ' ' + JSON.stringify(r6.planned.map(e => e.type)));
  const snap = readSnap();
  const prN = nodeById(snap, 'wim-pr-testrepo-42');
  ok('T6 PR node still open (NOT concluded on fetch failure)', !!prN && prN.state === 'open',
    prN && prN.state);
}

// ---- T7: existing root reused ------------------------------------------------
{
  const gt = [{
    repoKey: 'testrepo', rootNodeId: 'proj-DIFFERENT-id', rootTitle: 'Test Repo',
    plansOk: true, plans: [{ slug: 'zeta-plan', title: 'Zeta' }],
    branchesOk: true, branches: [], prsOk: true, prs: [],
  }];
  const r7 = sweep(gt, true);
  const rootOpens = r7.planned.filter(e => e.type === 'branch-opened' && e.parent_id === null);
  ok('T7 no duplicate project root created (title-matched existing proj-testrepo)',
    rootOpens.length === 0, JSON.stringify(rootOpens));
  const snap = readSnap();
  const zeta = nodeById(snap, 'wim-plan-zeta-plan');
  ok('T7 new effort parented under the DISCOVERED root', !!zeta && zeta.parent_id === 'proj-testrepo',
    zeta && zeta.parent_id);
}

// ---- T8: collectPlans fixture ------------------------------------------------
{
  const repoDir = path.join(tmpRoot, 'fake-repo');
  const plansDir = path.join(repoDir, 'docs', 'plans');
  fs.mkdirSync(path.join(plansDir, 'archive'), { recursive: true });
  fs.writeFileSync(path.join(plansDir, 'active-one.md'),
    '# Plan: Active One\nStatus: ACTIVE\n\n## Goal\nx\n');
  fs.writeFileSync(path.join(plansDir, 'done-one.md'),
    '# Plan: Done One\nStatus: COMPLETED\n');
  fs.writeFileSync(path.join(plansDir, 'archive', 'old-active.md'),
    '# Plan: Old\nStatus: ACTIVE\n'); // must be ignored (subdir)
  const res = sweepMod.collectPlans(repoDir);
  ok('T8 collectPlans ok', res.ok === true);
  ok('T8 picks only the top-level ACTIVE plan',
    res.plans.length === 1 && res.plans[0].slug === 'active-one' && res.plans[0].title === 'Active One',
    JSON.stringify(res.plans));
  const resMissing = sweepMod.collectPlans(path.join(tmpRoot, 'no-such-repo'));
  ok('T8 missing plans dir => ok:false (collection failure, not empty)', resMissing.ok === false);
}

// ---- T9: collectBranches against a real temp git repo -------------------------
{
  let gitOk = true;
  const gdir = path.join(tmpRoot, 'gitrepo');
  try {
    fs.mkdirSync(gdir);
    const g = (args) => execFileSync('git', ['-C', gdir].concat(args),
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    g(['init', '-q', '-b', 'master']);
    g(['config', 'user.email', 'test@example.com']);
    g(['config', 'user.name', 'Test User']);
    fs.writeFileSync(path.join(gdir, 'a.txt'), 'one\n');
    g(['add', '.']); g(['commit', '-q', '-m', 'base']);
    g(['checkout', '-q', '-b', 'feat/unique']);
    fs.writeFileSync(path.join(gdir, 'b.txt'), 'two\n');
    g(['add', '.']); g(['commit', '-q', '-m', 'unique work']);
    g(['checkout', '-q', 'master']);
    g(['branch', '-q', 'feat/empty']); // no unique patches
  } catch (e) { gitOk = false; console.log('SKIP T9 (git unavailable): ' + e.message); }
  if (gitOk) {
    const res = sweepMod.collectBranches(gdir);
    ok('T9 collectBranches ok (local master fallback base)', res.ok === true && /master/.test(res.base), res.base);
    ok('T9 finds the unmerged-unique branch with uniqueCount 1',
      res.branches.length === 1 && res.branches[0].name === 'feat/unique' && res.branches[0].uniqueCount === 1,
      JSON.stringify(res.branches));
  }
}

// ---- T10: repo-config resolution ----------------------------------------------
{
  const cfgFile = path.join(tmpRoot, 'wim-repos.json');
  fs.writeFileSync(cfgFile, JSON.stringify({ repos: [
    { repoKey: 'cfg-repo', path: '~/somewhere/cfg-repo', ghAccount: 'cfg-login' },
  ] }));
  process.env.WIM_SWEEP_REPOS_FILE = cfgFile;
  const repos = sweepMod.defaultRepos();
  ok('T10 env-named config file wins', repos.length === 1 && repos[0].repoKey === 'cfg-repo',
    JSON.stringify(repos));
  ok('T10 ~ expands + defaults derive from repoKey',
    repos[0].path.indexOf('~') === -1 && repos[0].rootNodeId === 'proj-cfg-repo'
    && repos[0].rootTitle === 'cfg-repo' && repos[0].ghAccount === 'cfg-login',
    JSON.stringify(repos[0]));
  process.env.WIM_SWEEP_REPOS_FILE = path.join(tmpRoot, 'no-such-repos.json');
  const fallback = sweepMod.defaultRepos();
  // Lower-precedence machine-local configs may legitimately exist on a dev
  // machine, so only assert the resolution never comes back empty.
  ok('T10 resolution never empty when the env-named file is missing',
    Array.isArray(fallback) && fallback.length >= 1, JSON.stringify(fallback.map(r => r.repoKey)));
  delete process.env.WIM_SWEEP_REPOS_FILE;
}

// ---- T11: parseVercelAgeToMs (age column -> approx epoch) --------------------
{
  const now = 1_700_000_000_000;
  ok('T11 parse "5m"', sweepMod.parseVercelAgeToMs('5m', now) === now - 5 * 60e3);
  ok('T11 parse "9h"', sweepMod.parseVercelAgeToMs('9h', now) === now - 9 * 3600e3);
  ok('T11 parse "3d"', sweepMod.parseVercelAgeToMs('3d', now) === now - 3 * 86400e3);
  ok('T11 garbage -> null', sweepMod.parseVercelAgeToMs('whenever', now) === null);
}

// ---- T12: DEPLOY detection (shipped-not-deployed -> deployed) ----------------
// Self-contained: a fresh repo with one PR. (a) ingest it in-flight. (b) PR
// gone (merged) => item-shipped (shipped-not-deployed). (c) sweep again WITH a
// Ready prod deploy NEWER than the ship => item-deployed; the UI now derives
// Deployed for that item. Then verify the conservative guards.
{
  const prNode = sweepMod.prNodeId('deployrepo', 7);
  function dgt(extra) {
    return [Object.assign({
      repoKey: 'deployrepo', rootNodeId: 'proj-deployrepo', rootTitle: 'Deploy Repo',
      plansOk: true, plans: [], branchesOk: true, branches: [],
      prsOk: true, prs: [{ number: 7, title: 'Ship the thing' }],
      deploysOk: false, deploy: null,
    }, extra || {})];
  }
  // (a) ingest the open PR
  sweep(dgt(), true);
  // (b) PR merged => gone => shipped-not-deployed (deploy still SKIP)
  sweep(dgt({ prsOk: true, prs: [] }), true);
  {
    const snap = readSnap();
    const n = nodeById(snap, prNode);
    ok('T12b PR shipped-not-deployed after merge',
      !!n && uiIsShippedNotDeployed(n.items[0]),
      n && JSON.stringify({ state: n.items[0].state, deployed: n.items[0].deployed }));
  }
  // (c) sweep with a Ready prod deploy NEWER than the ship
  const r12 = sweep(dgt({ prsOk: true, prs: [],
    deploysOk: true, deploy: { ready_at_ms: Date.now(), url: 'https://app.example.test' } }), true);
  ok('T12c plans an item-deployed',
    r12.planned.some(e => e.type === 'item-deployed' && e.node_id === prNode),
    JSON.stringify(r12.planned.map(e => e.type)));
  {
    const snap = readSnap();
    const n = nodeById(snap, prNode);
    ok('T12c PR now Deployed (UI filter shape)', !!n && n.items[0].deployed === true,
      n && JSON.stringify({ deployed: n.items[0].deployed }));
    ok('T12c deploy carries evidence', typeof n.items[0].deploy_evidence === 'string'
      && /production/i.test(n.items[0].deploy_evidence));
  }
  // (d) idempotent: a second deploy-aware sweep emits ZERO deploy events
  const r12d = sweep(dgt({ prsOk: true, prs: [],
    deploysOk: true, deploy: { ready_at_ms: Date.now(), url: 'https://app.example.test' } }), true);
  ok('T12d deploy detection is idempotent (already-deployed => no re-emit)',
    !r12d.planned.some(e => e.type === 'item-deployed'),
    JSON.stringify(r12d.planned.map(e => e.type)));
}

// ---- T13: deploy SKIP never marks work deployed (failure isolation) ---------
{
  const prNode = sweepMod.prNodeId('noverc', 9);
  function ngt(extra) {
    return [Object.assign({
      repoKey: 'noverc', rootNodeId: 'proj-noverc', rootTitle: 'No Vercel',
      plansOk: true, plans: [], branchesOk: true, branches: [],
      prsOk: true, prs: [{ number: 9, title: 'No deploy signal' }],
      deploysOk: false, deploysSkipReason: 'no .vercel/project.json', deploy: null,
    }, extra || {})];
  }
  sweep(ngt(), true);                          // ingest
  sweep(ngt({ prsOk: true, prs: [] }), true);  // merge => shipped-not-deployed
  const r13 = sweep(ngt({ prsOk: true, prs: [] }), true); // deploy still SKIP
  ok('T13 deploy SKIP emits NO item-deployed',
    !r13.planned.some(e => e.type === 'item-deployed'),
    JSON.stringify(r13.planned.map(e => e.type)));
  const snap = readSnap();
  const n = nodeById(snap, prNode);
  ok('T13 item stays shipped-not-deployed when deploy ground truth is unavailable',
    !!n && uiIsShippedNotDeployed(n.items[0]),
    n && JSON.stringify({ deployed: n.items[0].deployed }));
}

// ---- T14: a deploy OLDER than the ship does NOT mark deployed ---------------
{
  const prNode = sweepMod.prNodeId('oldrepo', 11);
  function ogt(extra) {
    return [Object.assign({
      repoKey: 'oldrepo', rootNodeId: 'proj-oldrepo', rootTitle: 'Old Deploy',
      plansOk: true, plans: [], branchesOk: true, branches: [],
      prsOk: true, prs: [{ number: 11, title: 'Shipped after last deploy' }],
      deploysOk: false, deploy: null,
    }, extra || {})];
  }
  sweep(ogt(), true);                          // ingest
  sweep(ogt({ prsOk: true, prs: [] }), true);  // merge now => shipped_ts ~ now
  // deploy that completed 1 day BEFORE this ship: must NOT count as this work's deploy
  const r14 = sweep(ogt({ prsOk: true, prs: [],
    deploysOk: true, deploy: { ready_at_ms: Date.now() - 86400e3, url: 'https://old.example.test' } }), true);
  ok('T14 prod deploy predating the ship does NOT mark it deployed',
    !r14.planned.some(e => e.type === 'item-deployed'),
    JSON.stringify(r14.planned.map(e => e.type)));
}

// ---- T15: gone-this-pass + OLD deploy does NOT mark deployed (ADR-056) ------
// The bug: a PR that ships (merges) in the SAME sweep that supplies a Ready
// prod deploy was marked deployed against ANY pre-existing deploy — including
// one that completed days BEFORE the merge and cannot contain its code. T14
// only exercised the prior-pass branch (ship and deploy in separate sweeps);
// THIS test merges AND deploy-detects in ONE pass so the gone-this-pass branch
// (ship time == now) is exercised. The shared deployIsNewerThanShip predicate
// must suppress item-deployed because the deploy predates the just-now merge.
{
  const prNode = sweepMod.prNodeId('gonerepo', 13);
  function ggt(extra) {
    return [Object.assign({
      repoKey: 'gonerepo', rootNodeId: 'proj-gonerepo', rootTitle: 'Gone This Pass',
      plansOk: true, plans: [], branchesOk: true, branches: [],
      prsOk: true, prs: [{ number: 13, title: 'Merges this pass' }],
      deploysOk: false, deploy: null,
    }, extra || {})];
  }
  sweep(ggt(), true);                          // ingest the open PR
  // ONE sweep: PR is gone (merged) THIS pass AND a Ready prod deploy is supplied
  // whose ready_at_ms is 3 days in the PAST -> the deploy predates this merge.
  const r15 = sweep(ggt({ prsOk: true, prs: [],
    deploysOk: true, deploy: { ready_at_ms: Date.now() - 3 * 24 * 3600 * 1000, url: 'https://stale.example.test' } }), true);
  ok('T15 gone-this-pass + deploy older than the just-now merge does NOT mark deployed',
    !r15.planned.some(e => e.type === 'item-deployed' && e.node_id === prNode),
    JSON.stringify(r15.planned.map(e => e.type)));
}

// ---- summary ----------------------------------------------------------------
try { fs.rmSync(tmpRoot, { recursive: true, force: true }); } catch (_) {}
console.log('work-in-motion-sweep selftest: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
