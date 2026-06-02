'use strict';
// Component B — config defaults + loader.
// orchestration-architecture-2026-05-30.md §7 decisions 3/4/6/9.
//
// Two-layer: hard-coded defaults here (shareable), overridden by an optional
// per-machine file at ~/.claude/state/orchestrator/config.json (gitignored,
// machine-local). Mirrors the harness's two-layer config convention.

const fs = require('fs');
const path = require('path');
const os = require('os');

const ORCH_DIR = path.join(os.homedir(), '.claude', 'state', 'orchestrator');

const PATHS = {
  dir: ORCH_DIR,
  queue: path.join(ORCH_DIR, 'queue'),
  processed: path.join(ORCH_DIR, 'queue', 'processed'),
  surface: path.join(ORCH_DIR, 'surface.json'),
  claims: path.join(ORCH_DIR, 'claims.json'),
  config: path.join(ORCH_DIR, 'config.json'),
  lock: path.join(ORCH_DIR, '.lock'),
  spawnLog: path.join(ORCH_DIR, 'spawn.log'),
};

// Defaults — every value is the design-doc default (§7).
const DEFAULTS = {
  maxConcurrent: 4,          // Q3 — matches orchestrator-pattern's ~5 ceiling
  autoSpawn: false,          // §8 — surface-first; flip ON only after Components A+C land
  stallMinutes: 60,          // §3 step 5 / matches CONV_TREE_HEARTBEAT_STALE_MIN
  freshMinutes: 15,          // matches CONV_TREE_HEARTBEAT_FRESH_MIN
  retryMax: 2,               // Q6 — then → pending-Misha
  leaseTtlMin: 30,           // Q9 — Component C lease (v1 local-stub)
  debounceSeconds: 60,       // §3 throttling
  lockStaleMinutes: 10,      // steal a lock older than this (crashed runner)
  machineId: null,           // resolved to os.hostname() at load if null
  spawnModel: null,          // optional --model for headless-local spawns
  runnerKindMap: { action: 'code-task', decision: 'cowork', question: 'cowork' },
};

function resolveMachineId(cfg) {
  if (cfg.machineId) return String(cfg.machineId);
  try { return os.hostname(); } catch (_) { return 'local'; }
}

// Load config: defaults merged with the optional machine-local file. Never
// throws — a bad config file degrades to defaults (Rule: a config typo must not
// break the orchestrator).
function loadConfig(opts) {
  opts = opts || {};
  const cfgPath = opts.configPath || PATHS.config;
  let fileCfg = {};
  try {
    if (fs.existsSync(cfgPath)) {
      fileCfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')) || {};
    }
  } catch (_) { fileCfg = {}; }
  const merged = Object.assign({}, DEFAULTS, fileCfg);
  // Allow an env override of autoSpawn for explicit one-off arming/disarming.
  if (process.env.ORCHESTRATOR_AUTOSPAWN === '1') merged.autoSpawn = true;
  if (process.env.ORCHESTRATOR_AUTOSPAWN === '0') merged.autoSpawn = false;
  merged.machineId = resolveMachineId(merged);
  return merged;
}

module.exports = { PATHS, DEFAULTS, loadConfig, resolveMachineId, ORCH_DIR };
