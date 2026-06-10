'use strict';
/* Workstreams Phase R7 — work-in-motion ingestion sweep (2026-06-09).
 *
 * Closes the R4 scenario-4 gap: the tracker showed NONE of the actually
 * in-flight work (ACTIVE plans, unmerged-unique branches, open PRs). Each run
 * reads GROUND TRUTH from the repos themselves, maps every in-flight effort to
 * a deterministic wim-* node under its project root, and emits — via the
 * state.js facade ONLY (never hand-edits the JSON) — exactly the events the
 * GUI's filters consume:
 *
 *   In-flight effort   -> branch-opened (node, tier work-item, parent = project
 *                         root) + action-added (ONE item per node). An
 *                         unchecked item with no explicit `state` derives
 *                         'in-flight' in web/app.js itemState() (app.js:175-181,
 *                         default branch at :180) and is therefore picked up by
 *                         the In-flight chip (applyFilter 'in-flight',
 *                         app.js:263). NOT an action_item_for_user fence — no
 *                         rich operator-ask details are attached.
 *   Gone effort        -> the effort left ground truth (plan closed / branch
 *                         merged+deleted / PR merged or closed). Emit
 *                         item-shipped {evidence: note} (sets it.state='shipped',
 *                         checked=true, shipped_ts — reducer.js:422-438) so the
 *                         item lands in the Shipped-not-deployed filter
 *                         (app.js isShippedNotDeployed :233-235 — shipped &&
 *                         !it.deployed), then annotated {note}, then concluded
 *                         (FR-7 passes because the item is now checked).
 *   Deployed           -> NOT emitted by this sweeper. Ground truth here has no
 *                         deploy signal; `item-deployed` / item-shipped
 *                         {deployed:true} (app.js isDeployed :232) is the
 *                         operator's / deploy tooling's transition.
 *   Reactivated effort -> a previously-concluded wim node whose effort is back
 *                         in ground truth: re-opened + item-unchecked +
 *                         item-committed (closest truthful explicit state — the
 *                         schema has no item-in-flight event; see
 *                         lifecycle-backfill.js header for the same reasoning).
 *
 * Deterministic node ids:
 *   wim-plan-<slug>                 (slug = plan filename minus .md)
 *   wim-br-<sha1(repoKey + '|' + branchName)[0..11]>
 *       (deliberate deviation from "sha1 of branch name alone": the same
 *        branch name can exist in BOTH repos; hashing repoKey|name keeps the
 *        id deterministic AND collision-free across repos.)
 *   wim-pr-<repoKey>-<number>
 *
 * Idempotency (two layers):
 *   1. read-state-first — the sweep reads the snapshot via state.readState()
 *      and emits branch-opened/action-added ONLY for node ids that do not
 *      exist; gone-handling only fires for wim nodes still 'open'; a second
 *      run with identical ground truth therefore plans ZERO events.
 *   2. deterministic event_ids (wim-open-/wim-item-/wim-ship-/wim-note-/
 *      wim-done-<sha1(node_id)>) — even if layer 1 raced, store.appendEvent
 *      dedupes by event_id (idempotentNoop), so a duplicate append is a no-op
 *      and the reducer never sees a duplicate.
 *
 * Per-repo / per-category failure isolation: if a category's collection failed
 * (e.g. a gh auth failure on one repo's PRs), that category is SKIPPED for both ingestion
 * AND gone-detection in that repo — a fetch failure must never conclude live
 * work. A wim node's repo is derived from its parent_id (= the project root).
 *
 * Usage:
 *   node scripts/work-in-motion-sweep.js                # dry-run (default; writes NOTHING)
 *   node scripts/work-in-motion-sweep.js --apply        # emit events to the canonical state file
 *   node scripts/work-in-motion-sweep.js --apply --state <path>   # explicit sink
 *   node scripts/work-in-motion-sweep.js --self-test    # pointer to the selftest file
 *
 * NEVER hand-edits the JSON. NEVER force-pushes. NEVER deletes branches.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const state = require('../state/state.js');

// ---------------------------------------------------------------------------
// Repo configuration — two-layer config per harness-hygiene (the same shape as
// config/projects.js): the kit ships ONLY the generic example
// (config/wim-repos.example.json); the real per-machine map (repo paths, gh
// account hints) lives in the gitignored config/wim-repos.json (or
// ~/.claude/local/wim-sweep-repos.json, or a file named by the
// WIM_SWEEP_REPOS_FILE env var). NO machine paths / org names / account names
// ship in this source file.
// ---------------------------------------------------------------------------
function expandHome(p) {
  if (p === '~') return os.homedir();
  if (p.startsWith('~/') || p.startsWith('~\\')) return path.join(os.homedir(), p.slice(2));
  return p;
}
function normalizeRepo(r) {
  return {
    repoKey: String(r.repoKey),
    path: expandHome(String(r.path)),
    rootNodeId: r.rootNodeId ? String(r.rootNodeId) : 'proj-' + String(r.repoKey),
    rootTitle: r.rootTitle ? String(r.rootTitle) : String(r.repoKey),
    ghAccount: r.ghAccount ? String(r.ghAccount) : null,
  };
}
function defaultRepos() {
  const candidates = [];
  if (process.env.WIM_SWEEP_REPOS_FILE) candidates.push(process.env.WIM_SWEEP_REPOS_FILE);
  candidates.push(path.join(__dirname, '..', 'config', 'wim-repos.json'));
  candidates.push(path.join(os.homedir(), '.claude', 'local', 'wim-sweep-repos.json'));
  for (const c of candidates) {
    let parsed;
    try { parsed = JSON.parse(fs.readFileSync(c, 'utf8')); } catch (_) { continue; }
    const arr = Array.isArray(parsed) ? parsed : (parsed && parsed.repos) || [];
    const repos = arr.filter(r => r && r.repoKey && r.path).map(normalizeRepo);
    if (repos.length) return repos;
  }
  // Generic fallback (no config anywhere): sweep the harness repo this module
  // lives in. __dirname = <repo>/neural-lace/workstreams-ui/scripts.
  return [{
    repoKey: 'neural-lace',
    path: path.resolve(__dirname, '..', '..', '..'),
    rootNodeId: 'proj-neural-lace',
    rootTitle: 'Neural Lace',
    ghAccount: null,
  }];
}

// ---------------------------------------------------------------------------
// Deterministic ids
// ---------------------------------------------------------------------------
function sha1(s) { return crypto.createHash('sha1').update(String(s)).digest('hex'); }
function planNodeId(slug) { return 'wim-plan-' + slug; }
function branchNodeId(repoKey, branchName) { return 'wim-br-' + sha1(repoKey + '|' + branchName).slice(0, 12); }
function prNodeId(repoKey, number) { return 'wim-pr-' + repoKey + '-' + number; }
function itemIdFor(nodeId) { return nodeId + '-item'; }
function evId(prefix, nodeId) { return 'wim-' + prefix + '-' + sha1(nodeId).slice(0, 32); }

// ---------------------------------------------------------------------------
// Ground-truth collectors
// ---------------------------------------------------------------------------

// (a1) ACTIVE plans — top-level docs/plans/*.md only (archive/ + deferred/ are
// terminal/parked by lifecycle convention and excluded by non-recursion).
function collectPlans(repoPath) {
  const dir = path.join(repoPath, 'docs', 'plans');
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return { ok: false, reason: 'plans dir unreadable: ' + e.message, plans: [] };
  }
  const plans = [];
  for (const ent of entries) {
    if (!ent.isFile() || !/\.md$/i.test(ent.name)) continue;
    let raw;
    try { raw = fs.readFileSync(path.join(dir, ent.name), 'utf8'); } catch (_) { continue; }
    const head = raw.slice(0, 4000); // Status: lives in the header
    if (!/^Status:\s*ACTIVE\s*$/m.test(head)) continue;
    const slug = ent.name.replace(/\.md$/i, '');
    const h1 = head.match(/^#\s+(?:Plan:\s*)?(.+)$/m);
    plans.push({ slug, title: (h1 ? h1[1] : slug).trim() });
  }
  plans.sort((a, b) => a.slug.localeCompare(b.slug));
  return { ok: true, plans };
}

function git(repoPath, args) {
  return execFileSync('git', ['-C', repoPath].concat(args), { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

// (a2) unmerged-unique local branches: >=1 '+' line from `git cherry <base> <br>`.
function collectBranches(repoPath) {
  let base = null;
  for (const cand of ['origin/master', 'origin/main', 'master', 'main']) {
    try { git(repoPath, ['rev-parse', '--verify', '--quiet', cand]); base = cand; break; } catch (_) { /* next */ }
  }
  if (!base) return { ok: false, reason: 'no master/main base ref found', branches: [] };
  let names;
  try {
    names = git(repoPath, ['for-each-ref', '--format=%(refname:short)', 'refs/heads'])
      .split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  } catch (e) {
    return { ok: false, reason: 'for-each-ref failed: ' + e.message, branches: [] };
  }
  const branches = [];
  for (const name of names) {
    if (name === 'master' || name === 'main') continue;
    let out;
    try { out = git(repoPath, ['cherry', base, name]); } catch (_) { continue; } // skip odd refs, log-free
    const unique = out.split(/\r?\n/).filter(l => l.startsWith('+')).length;
    if (unique >= 1) branches.push({ name, uniqueCount: unique });
  }
  branches.sort((a, b) => a.name.localeCompare(b.name));
  return { ok: true, base, branches };
}

// (a3) open PRs via gh, run with cwd = the repo so gh resolves the remote.
// A repo whose remote belongs to a DIFFERENT gh account than the active one
// fails the first call; we then try `gh auth switch -u <configured ghAccount>`,
// retry, and switch back to the previously-active login. Any persistent
// failure SKIPS PRs for that repo gracefully (ok:false) — never throws, never
// concludes live work.
function ghPrList(repoPath) {
  const out = execFileSync('gh', ['pr', 'list', '--state', 'open', '--limit', '200',
    '--json', 'number,title,headRefName'], { cwd: repoPath, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return JSON.parse(out).map(p => ({ number: p.number, title: p.title, headRefName: p.headRefName }));
}
function collectPRs(repoPath, ghAccount) {
  try {
    return { ok: true, prs: ghPrList(repoPath) };
  } catch (firstErr) {
    // Maybe the wrong gh account is active for this repo's remote.
    let priorLogin = null;
    try { priorLogin = execFileSync('gh', ['api', 'user', '--jq', '.login'], { encoding: 'utf8' }).trim(); } catch (_) {}
    if (!ghAccount || priorLogin === ghAccount) {
      return { ok: false, reason: 'gh pr list failed: ' + String(firstErr.message).split('\n')[0], prs: [] };
    }
    try {
      execFileSync('gh', ['auth', 'switch', '-u', ghAccount], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      return { ok: false, reason: 'gh auth switch to ' + ghAccount + ' failed: ' + String(e.message).split('\n')[0], prs: [] };
    }
    try {
      const prs = ghPrList(repoPath);
      return { ok: true, prs, switchedAccount: ghAccount };
    } catch (e) {
      return { ok: false, reason: 'gh pr list failed even as ' + ghAccount + ': ' + String(e.message).split('\n')[0], prs: [] };
    } finally {
      if (priorLogin) {
        try { execFileSync('gh', ['auth', 'switch', '-u', priorLogin], { stdio: 'ignore' }); } catch (_) {}
      }
    }
  }
}

// Collect ground truth for one repo config -> the shape sweep() consumes.
function collectRepoGroundTruth(repo) {
  const plansRes = collectPlans(repo.path);
  const branchesRes = collectBranches(repo.path);
  const prsRes = collectPRs(repo.path, repo.ghAccount);
  return {
    repoKey: repo.repoKey,
    rootNodeId: repo.rootNodeId,
    rootTitle: repo.rootTitle,
    plansOk: plansRes.ok, plansSkipReason: plansRes.reason || null, plans: plansRes.plans,
    branchesOk: branchesRes.ok, branchesSkipReason: branchesRes.reason || null, branches: branchesRes.branches,
    prsOk: prsRes.ok, prsSkipReason: prsRes.reason || null, prs: prsRes.prs,
  };
}

// ---------------------------------------------------------------------------
// Desired-node computation (pure)
// ---------------------------------------------------------------------------
function desiredNodesFor(repoGT) {
  const out = [];
  if (repoGT.plansOk) {
    for (const p of repoGT.plans) {
      out.push({ nodeId: planNodeId(p.slug), category: 'plan',
        title: 'PLAN: ' + p.title + ' [ACTIVE]' });
    }
  }
  if (repoGT.branchesOk) {
    for (const b of repoGT.branches) {
      out.push({ nodeId: branchNodeId(repoGT.repoKey, b.name), category: 'br',
        title: 'BRANCH: ' + b.name + ' (+' + b.uniqueCount + ' unshipped)' });
    }
  }
  if (repoGT.prsOk) {
    for (const pr of repoGT.prs) {
      out.push({ nodeId: prNodeId(repoGT.repoKey, pr.number), category: 'pr',
        title: 'PR #' + pr.number + ': ' + pr.title });
    }
  }
  return out;
}

function wimCategoryOf(nodeId) {
  if (/^wim-plan-/.test(nodeId)) return 'plan';
  if (/^wim-br-/.test(nodeId)) return 'br';
  if (/^wim-pr-/.test(nodeId)) return 'pr';
  return null;
}

// ---------------------------------------------------------------------------
// The sweep core (pure w.r.t. ground truth; all writes via the facade)
// ---------------------------------------------------------------------------
// groundTruth: array of per-repo objects (see collectRepoGroundTruth).
// opts: { statePath, apply } — apply=false plans events without writing.
// Returns { planned: [events], appended: n, idempotentNoops: n, skippedExisting: n, log: [] }
function sweep(groundTruth, opts) {
  opts = opts || {};
  const emitOpts = opts.statePath ? { statePath: opts.statePath } : undefined;
  const log = [];

  // Read state ONCE up front; track node existence locally as we emit so a
  // single run never double-emits and never depends on re-reads.
  let snap;
  try {
    const st = state.readState(emitOpts);
    snap = st.snapshot && Array.isArray(st.snapshot.nodes) ? st.snapshot : state.deriveSnapshot(st.events || [], 'global');
  } catch (e) {
    // Missing file => empty tree (bootstrap); anything else is fatal.
    if (e && /ENOENT/.test(String(e.message))) snap = { nodes: [], backlog: [] };
    else throw e;
  }
  const nodesById = new Map();
  for (const n of (snap.nodes || [])) nodesById.set(n.node_id, n);

  const planned = [];
  function plan(ev, why) {
    planned.push(ev);
    log.push('  + ' + ev.type + ' ' + (ev.node_id || ev.target || '') + (why ? '  (' + why + ')' : ''));
  }

  let skippedExisting = 0;

  for (const repoGT of groundTruth) {
    // ---- project root: discover from state; create ONLY if genuinely absent.
    let rootId = null;
    if (nodesById.has(repoGT.rootNodeId)) {
      rootId = repoGT.rootNodeId;
    } else {
      // Search existing proj-* ROOT nodes for a key/title match before creating.
      const want = repoGT.repoKey.toLowerCase();
      for (const n of nodesById.values()) {
        if (n.parent_id == null && /^proj-/.test(n.node_id)) {
          const idTail = n.node_id.replace(/^proj-/, '').toLowerCase();
          const title = String(n.title || '').toLowerCase();
          if (idTail === want || title === repoGT.rootTitle.toLowerCase() || title.indexOf(want) !== -1) {
            rootId = n.node_id; break;
          }
        }
      }
    }
    if (!rootId) {
      rootId = repoGT.rootNodeId;
      plan({
        event_id: evId('root', rootId), type: 'branch-opened',
        node_id: rootId, parent_id: null, title: repoGT.rootTitle, actor: 'dispatch',
      }, 'project root absent');
      nodesById.set(rootId, { node_id: rootId, parent_id: null, title: repoGT.rootTitle, state: 'open', items: [] });
    }

    // ---- ingest in-flight efforts
    const desired = desiredNodesFor(repoGT);
    const desiredIds = new Set(desired.map(d => d.nodeId));

    for (const d of desired) {
      const existing = nodesById.get(d.nodeId);
      if (!existing) {
        plan({
          event_id: evId('open', d.nodeId), type: 'branch-opened',
          node_id: d.nodeId, parent_id: rootId, title: d.title,
          tier: 'work-item', actor: 'dispatch',
        }, 'new in-flight effort');
        plan({
          event_id: evId('item', d.nodeId), type: 'action-added',
          node_id: d.nodeId, item_id: itemIdFor(d.nodeId), text: d.title, actor: 'dispatch',
        }, 'work item (unchecked+stateless => UI derives in-flight)');
        nodesById.set(d.nodeId, { node_id: d.nodeId, parent_id: rootId, title: d.title, state: 'open',
          items: [{ item_id: itemIdFor(d.nodeId), checked: false }] });
      } else if (existing.state === 'concluded') {
        // Reactivation: the effort is back in ground truth.
        plan({ type: 're-opened', node_id: d.nodeId, actor: 'dispatch' }, 'effort back in ground truth');
        const it = (existing.items || [])[0];
        if (it) {
          plan({ type: 'item-unchecked', node_id: d.nodeId, item_id: it.item_id, actor: 'dispatch' }, 'reactivate item');
          // No item-in-flight event exists; 'committed' is the closest truthful
          // explicit state (same reasoning as lifecycle-backfill.js).
          plan({ type: 'item-committed', node_id: d.nodeId, item_id: it.item_id,
            reason: 'work-in-motion sweep: effort reappeared in ground truth', actor: 'dispatch' }, 'reset lifecycle state');
        }
        existing.state = 'open';
      } else {
        skippedExisting++;
      }
    }

    // ---- gone efforts: wim children of THIS repo's root, still open, absent
    // from current ground truth — only for categories that collected OK.
    const catOk = { plan: repoGT.plansOk, br: repoGT.branchesOk, pr: repoGT.prsOk };
    for (const n of nodesById.values()) {
      if (n.parent_id !== rootId) continue;
      const cat = wimCategoryOf(n.node_id);
      if (!cat) continue;
      if (cat === 'pr' && n.node_id.indexOf('wim-pr-' + repoGT.repoKey + '-') !== 0) continue;
      if (!catOk[cat]) { log.push('  ~ skip gone-check ' + n.node_id + ' (category collection failed)'); continue; }
      if (n.state !== 'open') continue;
      if (desiredIds.has(n.node_id)) continue;
      const note = 'work-in-motion sweep: effort gone from ground truth (' +
        (cat === 'plan' ? 'plan no longer ACTIVE at top level' :
         cat === 'br' ? 'branch merged or deleted' : 'PR merged or closed') +
        ') — recorded as shipped-not-deployed; mark deployed when it reaches production.';
      const it = (n.items || [])[0];
      if (it && !it.checked) {
        plan({ event_id: evId('ship', n.node_id), type: 'item-shipped',
          node_id: n.node_id, item_id: it.item_id, evidence: note, actor: 'dispatch' }, 'gone => shipped-not-deployed');
        it.checked = true;
      }
      plan({ event_id: evId('note', n.node_id), type: 'annotated',
        node_id: n.node_id, text: note, actor: 'dispatch' }, 'gone note');
      plan({ event_id: evId('done', n.node_id), type: 'concluded',
        node_id: n.node_id, actor: 'dispatch' }, 'gone => concluded');
      n.state = 'concluded';
    }
  }

  // ---- emit (or dry-run)
  let appended = 0, idempotentNoops = 0;
  if (opts.apply) {
    for (const ev of planned) {
      const r = state.appendEvent(ev, emitOpts);
      if (r.appended) appended++;
      else if (r.idempotentNoop) idempotentNoops++;
    }
  }
  return { planned, appended, idempotentNoops, skippedExisting, log };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const a = { apply: false, statePath: null };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--apply') a.apply = true;
    else if (argv[i] === '--state' && argv[i + 1]) { a.statePath = argv[++i]; }
    else if (argv[i] === '--self-test') a.selfTest = true;
  }
  return a;
}

function main() {
  const args = parseArgs(process.argv);
  if (args.selfTest) {
    console.log('run: node scripts/work-in-motion-sweep.selftest.js');
    process.exit(0);
  }
  const repos = defaultRepos();
  const groundTruth = [];
  for (const repo of repos) {
    if (!fs.existsSync(repo.path)) {
      console.log('[wim-sweep] repo missing, skipped entirely:', repo.path);
      continue;
    }
    const gt = collectRepoGroundTruth(repo);
    console.log('[wim-sweep] ' + gt.repoKey + ': plans=' + (gt.plansOk ? gt.plans.length : 'SKIP(' + gt.plansSkipReason + ')') +
      ' branches=' + (gt.branchesOk ? gt.branches.length : 'SKIP(' + gt.branchesSkipReason + ')') +
      ' prs=' + (gt.prsOk ? gt.prs.length : 'SKIP(' + gt.prsSkipReason + ')'));
    groundTruth.push(gt);
  }
  const res = sweep(groundTruth, { apply: args.apply, statePath: args.statePath || undefined });
  console.log('[wim-sweep] mode:', args.apply ? 'APPLY' : 'DRY-RUN (no writes; pass --apply to emit)');
  console.log('[wim-sweep] sink:', args.statePath || state.STATE_FILE);
  res.log.forEach(l => console.log(l));
  console.log('[wim-sweep] planned=' + res.planned.length +
    ' appended=' + res.appended + ' idempotentNoops=' + res.idempotentNoops +
    ' skippedExisting=' + res.skippedExisting);
}

module.exports = {
  defaultRepos,
  collectPlans, collectBranches, collectPRs, collectRepoGroundTruth,
  planNodeId, branchNodeId, prNodeId, itemIdFor, evId,
  desiredNodesFor, sweep,
};

if (require.main === module) main();
