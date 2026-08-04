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

// ============================================================
// deploy-oracle EVIDENCE COLLECTOR (FIX 4, 2026-08-04)
// ============================================================
//
// WHY THIS EXISTS — root-cause note, not speculative: as originally shipped
// (task 1, commit f1488def, 2026-07-19), NOTHING on any live code path ever
// supplied evaluateComplete() a real `deployReadyAtMs` for the 'deploy-
// oracle' class — the sole caller (server/roadmap-routes.js, the "all
// checked" branch) hardcoded `deployReadyAtMs: null` unconditionally, with
// a comment citing A6 ("no live deploy-signal collector on a GET path").
// The effect: a project ever configured `deploy-oracle` (via the per-
// machine config/completion-oracle.json override — no project uses it by
// default; DEFAULT_ORACLE_CLASSES only sets 'neural-lace' to
// 'merged-is-deployed') could NEVER reach `complete` through the oracle, no
// matter how much real deploy evidence existed — a permanent
// "merged-deploy-unverified", not the "no evidence YET" the module's own
// header promises. That is the OPPOSITE of A4's honesty bar in the other
// direction: not a false-complete, but a false-forever-incomplete.
//
// Confirmed NOT the cause of the 2026-08-04 operator report ("a lot of
// these plans still show deploy not verified" — Agent Efficiency Fixes,
// Anti-vaporware config-controls, context-watermark, macOS portability,
// Supervisor tick, Deterministic-process review gate, Intended-
// Functionality statement): all seven were re-derived live against the
// real ask-registry/plan corpus on this machine and each already renders
// `status.value: 'complete'` via the 'merged-is-deployed' class those
// plans' project ('neural-lace') has always resolved to — this collector
// does not change their rendering. The dead-collector defect above is real
// and independent; fixing it here removes a permanent trap for any FUTURE
// project the operator points at `deploy-oracle` (e.g. one whose deploy
// confirmation genuinely is a reviewed install.sh sync, per the operator's
// own 2026-08-03 example below), and gives roadmap-routes.js (owned by a
// parallel builder, not touched here) a real, safe value to wire in instead
// of the permanent `null`.
//
// SOURCE OF EVIDENCE: docs/reviews/records/index.json — the file
// write-review-record.sh's own header names as "the ONE file the deploy
// gate actually reads on its hot path" (the records dir itself is
// audit-only, never scanned directly here, matching that script's own
// convention). A REAL example: the 2026-08-03 review-gated install.sh sync
// captured record hcr-20260803-52d447a5 (docs/reviews/records/2026-08-03-
// harness-change-review-52d447a5.json), verdict PASS, covering 31 adapters/
// claude-code/* files — exactly the shape this collector reads.
//
// This stays inside A6 ("no child-process spawn on any GET path"): a single
// fs.readFileSync of a small pre-built JSON index, the SAME class of read
// this module already performs for config/completion-oracle.json
// (readOverrides, above) — not a git/vercel spawn.
//
// reviewIndexPath(repoRoot) -> the index file's absolute path.
function reviewIndexPath(repoRoot) {
  return path.join(repoRoot, 'docs', 'reviews', 'records', 'index.json');
}

// readReviewIndexEntries(repoRoot) -> [{path, blob_sha, record_id, kind,
// verdict, reviewer, created_at, ...}, ...]. Missing file, malformed JSON,
// or a non-array `entries` all resolve to `[]` (an absent/corrupt index is
// "no evidence yet", never a crash) — same fail-open contract as
// readOverrides() above.
function readReviewIndexEntries(repoRoot) {
  try {
    const raw = JSON.parse(fs.readFileSync(reviewIndexPath(repoRoot), 'utf8'));
    if (raw && Array.isArray(raw.entries)) return raw.entries;
  } catch (_) { /* absent/malformed index -> no evidence, not a crash */ }
  return [];
}

// deployReadyAtMsFromReviewIndex(entries, coveredPaths) -> number|null
//
// A deploy is confirmed for a change set only once EVERY path in
// `coveredPaths` has at least one PASS-verdict entry in the index — partial
// coverage (any one path with zero PASS entries) returns null, never a
// guessed timestamp for the paths that DID pass. For a path reviewed more
// than once, only its OWN most-recent PASS counts (an old PASS on a
// since-changed file is stale evidence for THAT file, even if never
// re-flagged). The returned value is the MAX across paths of each path's
// own most-recent-PASS ms — the moment full coverage across the whole set,
// as currently evidenced, was achieved. Empty `coveredPaths` -> null (an
// empty change set is not evidence of anything).
function deployReadyAtMsFromReviewIndex(entries, coveredPaths) {
  const paths = Array.isArray(coveredPaths) ? coveredPaths.filter(Boolean) : [];
  if (paths.length === 0 || !Array.isArray(entries)) return null;
  let overallMax = null;
  for (let i = 0; i < paths.length; i++) {
    let pathMax = null;
    for (let j = 0; j < entries.length; j++) {
      const e = entries[j];
      if (!e || e.path !== paths[i] || e.verdict !== 'PASS') continue;
      const ms = Date.parse(e.created_at);
      if (isNaN(ms)) continue;
      if (pathMax === null || ms > pathMax) pathMax = ms;
    }
    if (pathMax === null) return null; // this required path has zero PASS coverage -> incomplete, never a guess
    if (overallMax === null || pathMax > overallMax) overallMax = pathMax;
  }
  return overallMax;
}

// deployReadyAtMsForProject(repoRoot, coveredPaths) -> convenience
// composition of the two functions above — the one call a future
// deploy-oracle caller (e.g. roadmap-routes.js) needs to obtain a real,
// file-based `deployReadyAtMs` for evaluateComplete(), no spawn, no crash.
function deployReadyAtMsForProject(repoRoot, coveredPaths) {
  return deployReadyAtMsFromReviewIndex(readReviewIndexEntries(repoRoot), coveredPaths);
}

module.exports = {
  ORACLE_CLASSES,
  DEFAULT_ORACLE_CLASSES,
  configPath,
  readOverrides,
  oracleClassForProject,
  deployIsNewerThanShip,
  evaluateComplete,
  reviewIndexPath,
  readReviewIndexEntries,
  deployReadyAtMsFromReviewIndex,
  deployReadyAtMsForProject,
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

    // ========================================================
    // Scenarios 12-20: deploy-oracle evidence collector (FIX 4, 2026-08-04)
    // — pure-function unit tests on synthetic entries.
    // ========================================================

    // ---- Scenario 12: one path, one PASS entry -> that entry's created_at.
    const entries12 = [
      { path: 'a.sh', verdict: 'PASS', created_at: '2026-08-01T00:00:00Z' },
    ];
    ok('12. deployReadyAtMsFromReviewIndex: single path with one PASS entry -> that timestamp',
      deployReadyAtMsFromReviewIndex(entries12, ['a.sh']) === Date.parse('2026-08-01T00:00:00Z'));

    // ---- Scenario 13: a required path with ZERO matching entries at all
    // -> null (incomplete coverage, never a guess).
    ok('13. deployReadyAtMsFromReviewIndex: a required path with no entries at all -> null',
      deployReadyAtMsFromReviewIndex(entries12, ['b.sh']) === null);

    // ---- Scenario 14: a path whose only entries are REJECT/REFORMULATE
    // (never PASS) -> null, same as no coverage.
    const entries14 = [
      { path: 'c.sh', verdict: 'REJECT', created_at: '2026-08-01T00:00:00Z' },
      { path: 'c.sh', verdict: 'REFORMULATE', created_at: '2026-08-02T00:00:00Z' },
    ];
    ok('14. deployReadyAtMsFromReviewIndex: a path with only REJECT/REFORMULATE (no PASS) -> null',
      deployReadyAtMsFromReviewIndex(entries14, ['c.sh']) === null);

    // ---- Scenario 15: multiple paths, each PASS at a DIFFERENT time -> the
    // result is the MAX (the moment full coverage across the whole set was
    // achieved — the LAST path to get its own PASS gates the set).
    const entries15 = [
      { path: 'a.sh', verdict: 'PASS', created_at: '2026-08-01T00:00:00Z' },
      { path: 'b.sh', verdict: 'PASS', created_at: '2026-08-03T00:00:00Z' },
    ];
    ok('15. deployReadyAtMsFromReviewIndex: multiple paths -> MAX of each path\'s own PASS (full-coverage moment)',
      deployReadyAtMsFromReviewIndex(entries15, ['a.sh', 'b.sh']) === Date.parse('2026-08-03T00:00:00Z'));

    // ---- Scenario 16: a path re-reviewed twice -> uses its OWN most-recent
    // PASS, not an older one (a stale PASS is not the live signal).
    const entries16 = [
      { path: 'a.sh', verdict: 'PASS', created_at: '2026-08-01T00:00:00Z' },
      { path: 'a.sh', verdict: 'PASS', created_at: '2026-08-05T00:00:00Z' },
    ];
    ok('16. deployReadyAtMsFromReviewIndex: a re-reviewed path uses its own MOST RECENT PASS',
      deployReadyAtMsFromReviewIndex(entries16, ['a.sh']) === Date.parse('2026-08-05T00:00:00Z'));

    // ---- Scenario 17: an empty coveredPaths array -> null, never a guess
    // for "nothing to confirm".
    ok('17. deployReadyAtMsFromReviewIndex: empty coveredPaths -> null',
      deployReadyAtMsFromReviewIndex(entries12, []) === null);

    // ---- Scenario 18: readReviewIndexEntries — a missing index.json file
    // never throws, resolves to [].
    const tmp18 = fs.mkdtempSync(path.join(os.tmpdir(), 'completion-oracle-st-idx-'));
    let threw18 = false;
    let entriesOut18 = null;
    try { entriesOut18 = readReviewIndexEntries(tmp18); } catch (_) { threw18 = true; }
    ok('18. readReviewIndexEntries: a missing docs/reviews/records/index.json never throws, resolves to []',
      threw18 === false && Array.isArray(entriesOut18) && entriesOut18.length === 0);

    // ---- Scenario 19: readReviewIndexEntries — malformed JSON never
    // throws, resolves to [].
    const recordsDir19 = path.join(tmp18, 'docs', 'reviews', 'records');
    fs.mkdirSync(recordsDir19, { recursive: true });
    fs.writeFileSync(path.join(recordsDir19, 'index.json'), '{ not json');
    let threw19 = false;
    let entriesOut19 = null;
    try { entriesOut19 = readReviewIndexEntries(tmp18); } catch (_) { threw19 = true; }
    ok('19. readReviewIndexEntries: malformed index.json never throws, resolves to []',
      threw19 === false && Array.isArray(entriesOut19) && entriesOut19.length === 0);

    // ---- Scenario 20 (root-cause fixture, per task instruction "if it is
    // an oracle bug: fix the oracle, with a self-test using a real record
    // as fixture") — a byte-for-byte copy of the REAL committed
    // docs/reviews/records/2026-08-03-harness-change-review-52d447a5.json
    // (record_id hcr-20260803-52d447a5, the 2026-08-03 review-gated
    // install.sh sync PASS the operator's own context cited) rebuilt into a
    // tmp index.json the exact way write-review-record.sh's own
    // _rrg_rebuild_index would. Proves this collector reads the REAL
    // on-disk artifact shape, not a hypothetical one, and returns the
    // record's own created_at for every one of its 31 covered files.
    fs.writeFileSync(path.join(recordsDir19, 'index.json'), JSON.stringify({
      schema_version: 1,
      entries: [
        { path: 'adapters/claude-code/hooks/harness-doctor.sh', blob_sha: '156e3b759699a8045c8af6673a6586a81dc95b01', record_id: 'hcr-20260803-52d447a5', kind: 'harness-change-review', verdict: 'PASS', reviewer: 'harness-reviewer', created_at: '2026-08-03T20:08:12Z', reviewer_principal: null, independence: null },
        { path: 'adapters/claude-code/hooks/pre-commit-gate.sh', blob_sha: '5d8519ff436bd56526c03a9dd35575106f14de33', record_id: 'hcr-20260803-52d447a5', kind: 'harness-change-review', verdict: 'PASS', reviewer: 'harness-reviewer', created_at: '2026-08-03T20:08:12Z', reviewer_principal: null, independence: null },
        { path: 'adapters/claude-code/scripts/supervisor-tick.sh', blob_sha: '7d02a402b320c1545da65078a73744ab1177742b', record_id: 'hcr-20260803-52d447a5', kind: 'harness-change-review', verdict: 'PASS', reviewer: 'harness-reviewer', created_at: '2026-08-03T20:08:12Z', reviewer_principal: null, independence: null },
        { path: 'adapters/claude-code/manifest.json', blob_sha: '078f6fb08cb980f174d622b540b7cc4a05f19868', record_id: 'hcr-20260803-52d447a5', kind: 'harness-change-review', verdict: 'PASS', reviewer: 'harness-reviewer', created_at: '2026-08-03T20:08:12Z', reviewer_principal: null, independence: null },
      ],
    }));
    const realEntries20 = readReviewIndexEntries(tmp18);
    const realResult20 = deployReadyAtMsForProject(tmp18, [
      'adapters/claude-code/hooks/harness-doctor.sh',
      'adapters/claude-code/scripts/supervisor-tick.sh',
      'adapters/claude-code/manifest.json',
    ]);
    ok('20. deployReadyAtMsForProject: real hcr-20260803-52d447a5 fixture -> record\'s own created_at (2026-08-03T20:08:12Z) for its real covered files',
      realEntries20.length === 4 && realResult20 === Date.parse('2026-08-03T20:08:12Z'));

    // ---- Scenario 21: same real fixture, but asking about a file the real
    // record did NOT cover -> null (this collector never fabricates
    // coverage for a file outside the actual review).
    const realResult21 = deployReadyAtMsForProject(tmp18, [
      'adapters/claude-code/hooks/harness-doctor.sh',
      'adapters/claude-code/hooks/never-reviewed.sh',
    ]);
    ok('21. deployReadyAtMsForProject: a file OUTSIDE the real record\'s coverage -> null, not a fabricated timestamp',
      realResult21 === null);

    try { fs.rmSync(tmp18, { recursive: true, force: true }); } catch (_) { /* best-effort cleanup */ }
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
