'use strict';
// server/completion-oracle.js — per-project completion-oracle config
// (cockpit-roadmap-redesign plan, Task 1; architecture-review amendment A4,
// binding).
//
// ============================================================
// WHY THIS EXISTS
// ============================================================
//
// The roadmap's "complete" bucket must never lie in either direction: a
// merged-but-undeployed item riding to Complete is the confident lie the
// operator's round-3/4 definition explicitly forbids; an item that IS live
// in production sitting "incomplete" forever is the other betrayal
// (everything-forever-in-progress). Three named oracle classes, per
// project, resolve this honestly:
//
//   deploy-oracle       — a merged item is complete only once DEPLOY
//                         EVIDENCE strictly newer than the merge is
//                         supplied. The age-guard PREDICATE below
//                         (deployIsNewerThanShip) is PORTED VERBATIM from
//                         scripts/work-in-motion-sweep.js:394-398
//                         (ADR-056 fix) — same function body, same
//                         semantics, NOT re-derived. That script's actual
//                         deploy-signal COLLECTION (collectDeploys/
//                         runVercelLs, work-in-motion-sweep.js:268-332) is
//                         a live `vercel ls --prod` CHILD-PROCESS SPAWN —
//                         out of THIS module's scope per A6's binding
//                         "no child-process spawn on any GET path" pin.
//                         This module therefore accepts an
//                         ALREADY-COLLECTED deploy timestamp
//                         (deployReadyAtMs) as a plain argument; a project
//                         configured deploy-oracle with no
//                         deployReadyAtMs available yet renders exactly
//                         like "no evidence" (merged-deploy-unverified) —
//                         never a crash, never a guess, never blocked on
//                         a future sweep landing.
//   merged-is-deployed  — this repo's own project: merging to master
//                         triggers session-start-auto-install.sh syncing
//                         every session live from origin/master (documented
//                         harness convention, CLAUDE.md "Harness source of
//                         truth"), and `harness-doctor.sh --quick` green is
//                         the functional "this estate is actually running
//                         the merged code" signal — so for THIS project,
//                         merged IS deployed: complete-PROVEN, no separate
//                         deploy check required.
//   no-signal           — no deploy-confirmation mechanism is configured
//                         for this project at all. BINDING RULE (A4): a
//                         merged item under this class renders the
//                         DISTINCT "merged — deploy unverified" state,
//                         OUTSIDE the Complete bucket — never silently
//                         complete just because nothing contradicts it.
//
// Every function in this module is a PLAIN, SYNCHRONOUS, PURE computation
// over its arguments (or a single fs.readFileSync of a small JSON config) —
// no spawn, no network, safe on any GET/landing path (A6).
//
// ============================================================
// PER-PROJECT CLASS RESOLUTION (two-layer config, projects.js precedent)
// ============================================================
//
// A small checked-in default map (this repo's own project keys) plus an
// optional per-machine override file (config/completion-oracle.json,
// gitignored — mirrors config/projects.json's exact two-layer convention:
// a tracked completion-oracle.example.json placeholder + a gitignored real
// instance). Any project key present in NEITHER layer defaults to
// `no-signal` — the safe default that can never silently render complete.

const fs = require('fs');
const path = require('path');

const ORACLE_CLASSES = Object.freeze(['deploy-oracle', 'merged-is-deployed', 'no-signal']);

// DEFAULT_ORACLE_CLASSES — checked-in defaults. 'neural-lace' is the SAME
// stable alias config/projects.js#loadProjects() always registers for this
// repo's own root; the harness's merged-is-deployed mechanism (see header)
// applies specifically to that project.
const DEFAULT_ORACLE_CLASSES = Object.freeze({
  'neural-lace': 'merged-is-deployed',
});

function configPath() {
  return process.env.COMPLETION_ORACLE_CONFIG ||
    path.join(__dirname, '..', 'config', 'completion-oracle.json');
}

// readOverrides() — best-effort read of the per-machine override file.
// Missing file, malformed JSON, or a non-object value all resolve to `{}`
// (silently absent config is normal — most machines never create the
// override file at all); this NEVER throws.
function readOverrides() {
  try {
    const raw = JSON.parse(fs.readFileSync(configPath(), 'utf8'));
    if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw;
  } catch (_) { /* absent/malformed override -> no overrides, not a crash */ }
  return {};
}

// oracleClassForProject(projectKey) -> one of ORACLE_CLASSES. Resolution
// order: per-machine override file > checked-in default > 'no-signal'
// (the safe default — an unconfigured/unknown project NEVER silently
// completes). An override value that is not one of the three named
// classes is IGNORED (treated as absent) rather than trusted verbatim —
// a typo in a hand-edited config file must never smuggle in a made-up
// fourth class.
function oracleClassForProject(projectKey) {
  if (!projectKey) return 'no-signal';
  const overrides = readOverrides();
  if (overrides[projectKey] && ORACLE_CLASSES.indexOf(overrides[projectKey]) !== -1) {
    return overrides[projectKey];
  }
  if (DEFAULT_ORACLE_CLASSES[projectKey]) return DEFAULT_ORACLE_CLASSES[projectKey];
  return 'no-signal';
}

// ----------------------------------------------------------------------
// deployIsNewerThanShip(readyMs, shipMs) — PORTED VERBATIM (same body,
// same semantics) from scripts/work-in-motion-sweep.js:394-398 (ADR-056):
// the SINGLE predicate every path to "this merge is confirmed deployed"
// must satisfy. A Ready prod deploy may only confirm an item deployed
// when the deploy is strictly newer than (or equal to) the item's merge —
// a deploy that completed BEFORE the merge cannot contain its code.
// null/NaN on either side => not deployable (an unknown ship or deploy
// time must never be treated as "older than the other" by omission).
// ----------------------------------------------------------------------
function deployIsNewerThanShip(readyMs, shipMs) {
  if (shipMs == null || isNaN(shipMs)) return false;
  if (readyMs == null || isNaN(readyMs)) return false;
  return readyMs >= shipMs;
}

// evaluateComplete(ctx) -> { state: 'complete'|'merged-deploy-unverified', overridden }
//
// Call ONLY for an item whose own ground truth is already "done"/merged
// (checkbox checked, ask promoted, etc.) — this function decides which of
// the two MERGED-side states it renders in, never whether it is merged at
// all (that is the caller's own ground-truth read).
//
//   ctx.oracleClass      - one of ORACLE_CLASSES (see oracleClassForProject).
//   ctx.mergedAtMs        - number|null: this item's own merge/ship time.
//   ctx.deployReadyAtMs   - number|null: an already-collected deploy signal
//                           (see header — this module never collects one).
//   ctx.overrideComplete  - bool: a labeled, explicit per-item operator
//                           override (A4: "manual 'done' is always an
//                           override, labeled") — short-circuits to
//                           complete regardless of oracle class, since an
//                           explicit human override outranks every
//                           mechanism-derived signal here by design.
function evaluateComplete(ctx) {
  ctx = ctx || {};
  if (ctx.overrideComplete) {
    return { state: 'complete', overridden: true };
  }
  if (ctx.oracleClass === 'merged-is-deployed') {
    return { state: 'complete', overridden: false };
  }
  if (ctx.oracleClass === 'deploy-oracle') {
    const confirmed = ctx.deployReadyAtMs != null &&
      deployIsNewerThanShip(ctx.deployReadyAtMs, ctx.mergedAtMs);
    return { state: confirmed ? 'complete' : 'merged-deploy-unverified', overridden: false };
  }
  // 'no-signal' (and any unrecognized class, defensively): BINDING RULE —
  // never silently complete.
  return { state: 'merged-deploy-unverified', overridden: false };
}

module.exports = {
  ORACLE_CLASSES,
  DEFAULT_ORACLE_CLASSES,
  configPath,
  readOverrides,
  oracleClassForProject,
  deployIsNewerThanShip,
  evaluateComplete,
};

// ============================================================
// --self-test — sandboxed fixture suite (unit-level; server.selftest.js /
// derive-lib's own self-test cover the WIRING over real ask+plan data).
// ============================================================
async function selfTest() {
  const os = require('os');
  let passed = 0, failed = 0;
  function ok(name, cond, detail) {
    if (cond) { passed++; console.log('  PASS: ' + name); }
    else { failed++; console.log('  FAIL: ' + name + (detail ? ' (' + detail + ')' : '')); }
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'completion-oracle-st-'));
  const savedEnv = process.env.COMPLETION_ORACLE_CONFIG;

  try {
    // ---- Scenario 1: deployIsNewerThanShip boundary conditions (ported
    // predicate — same truth table as work-in-motion-sweep.js's own).
    ok('1. deployIsNewerThanShip: deploy strictly after merge -> true',
      deployIsNewerThanShip(2000, 1000) === true);
    ok('1b. deployIsNewerThanShip: deploy exactly equal to merge -> true (>=)',
      deployIsNewerThanShip(1000, 1000) === true);
    ok('1c. deployIsNewerThanShip: deploy before merge -> false',
      deployIsNewerThanShip(500, 1000) === false);
    ok('1d. deployIsNewerThanShip: null deploy time -> false (never a guessed true)',
      deployIsNewerThanShip(null, 1000) === false);
    ok('1e. deployIsNewerThanShip: null merge time -> false (never a guessed true)',
      deployIsNewerThanShip(2000, null) === false);
    ok('1f. deployIsNewerThanShip: NaN either side -> false',
      deployIsNewerThanShip(NaN, 1000) === false && deployIsNewerThanShip(2000, NaN) === false);

    // ---- Scenario 2: oracleClassForProject — checked-in default.
    process.env.COMPLETION_ORACLE_CONFIG = path.join(tmp, 'nonexistent.json');
    ok('2. neural-lace resolves merged-is-deployed with NO override file present',
      oracleClassForProject('neural-lace') === 'merged-is-deployed');
    ok('2b. an unknown/unconfigured project resolves no-signal (the safe default)',
      oracleClassForProject('some-random-project') === 'no-signal');
    ok('2c. an empty/falsy project key resolves no-signal, never a crash',
      oracleClassForProject('') === 'no-signal' && oracleClassForProject(null) === 'no-signal');

    // ---- Scenario 3: per-machine override file wins over the default.
    const cfg3 = path.join(tmp, 'override.json');
    fs.writeFileSync(cfg3, JSON.stringify({ 'neural-lace': 'deploy-oracle', 'my-app': 'deploy-oracle' }));
    process.env.COMPLETION_ORACLE_CONFIG = cfg3;
    ok('3. an override file value wins over the checked-in default',
      oracleClassForProject('neural-lace') === 'deploy-oracle');
    ok('3b. an override file can configure a project the defaults never named',
      oracleClassForProject('my-app') === 'deploy-oracle');

    // ---- Scenario 4: a malformed/invalid override value is IGNORED, not
    // trusted verbatim (never a made-up fourth class).
    const cfg4 = path.join(tmp, 'bogus.json');
    fs.writeFileSync(cfg4, JSON.stringify({ 'neural-lace': 'totally-made-up-class' }));
    process.env.COMPLETION_ORACLE_CONFIG = cfg4;
    ok('4. an override value outside the three named classes is ignored (falls back to the checked-in default)',
      oracleClassForProject('neural-lace') === 'merged-is-deployed');

    // ---- Scenario 5: malformed JSON / absent file never throws.
    const cfg5 = path.join(tmp, 'corrupt.json');
    fs.writeFileSync(cfg5, '{ not json');
    process.env.COMPLETION_ORACLE_CONFIG = cfg5;
    let threw5 = false;
    try { oracleClassForProject('neural-lace'); } catch (_) { threw5 = true; }
    ok('5. a corrupt override JSON file never throws (fails open to the checked-in default)',
      threw5 === false && oracleClassForProject('neural-lace') === 'merged-is-deployed');

    // ---- Scenario 6: evaluateComplete — merged-is-deployed always complete.
    ok('6. evaluateComplete: merged-is-deployed -> complete regardless of deploy signal',
      evaluateComplete({ oracleClass: 'merged-is-deployed', mergedAtMs: 1000, deployReadyAtMs: null }).state === 'complete');

    // ---- Scenario 7: evaluateComplete — no-signal NEVER silently complete
    // (A4 binding rule), even with a deploy signal present (no-signal means
    // no MECHANISM is configured, so a deploy signal reaching here would be
    // a caller bug, not something this function should trust).
    const ev7 = evaluateComplete({ oracleClass: 'no-signal', mergedAtMs: 1000, deployReadyAtMs: 5000 });
    ok('7. evaluateComplete: no-signal renders merged-deploy-unverified, never complete',
      ev7.state === 'merged-deploy-unverified' && ev7.overridden === false);

    // ---- Scenario 8: evaluateComplete — deploy-oracle, confirmed.
    ok('8. evaluateComplete: deploy-oracle with a deploy signal newer than merge -> complete',
      evaluateComplete({ oracleClass: 'deploy-oracle', mergedAtMs: 1000, deployReadyAtMs: 2000 }).state === 'complete');

    // ---- Scenario 9: evaluateComplete — deploy-oracle, no signal yet.
    ok('9. evaluateComplete: deploy-oracle with NO deploy signal yet -> merged-deploy-unverified, never a crash/guess',
      evaluateComplete({ oracleClass: 'deploy-oracle', mergedAtMs: 1000, deployReadyAtMs: null }).state === 'merged-deploy-unverified');

    // ---- Scenario 10: evaluateComplete — deploy-oracle, deploy predates
    // merge (a stale deploy from before this work landed).
    ok('10. evaluateComplete: deploy-oracle with a deploy OLDER than the merge -> merged-deploy-unverified, not a false complete',
      evaluateComplete({ oracleClass: 'deploy-oracle', mergedAtMs: 5000, deployReadyAtMs: 1000 }).state === 'merged-deploy-unverified');

    // ---- Scenario 11: labeled operator override outranks every class,
    // including no-signal (A4: "manual done is always an override, labeled").
    const ev11 = evaluateComplete({ oracleClass: 'no-signal', mergedAtMs: 1000, deployReadyAtMs: null, overrideComplete: true });
    ok('11. evaluateComplete: an explicit override renders complete even under no-signal, and is labeled (overridden:true)',
      ev11.state === 'complete' && ev11.overridden === true);
  } finally {
    if (savedEnv === undefined) delete process.env.COMPLETION_ORACLE_CONFIG;
    else process.env.COMPLETION_ORACLE_CONFIG = savedEnv;
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) { /* best-effort cleanup */ }
  }

  console.log('\n' + passed + ' passed, ' + failed + ' failed');
  return failed === 0 ? 0 : 1;
}

if (require.main === module) {
  if (process.argv.indexOf('--self-test') !== -1) {
    selfTest().then((code) => process.exit(code));
  } else {
    process.stdout.write(JSON.stringify({
      classes: ORACLE_CLASSES,
      defaults: DEFAULT_ORACLE_CLASSES,
      config_path: configPath(),
    }, null, 2) + '\n');
  }
}
