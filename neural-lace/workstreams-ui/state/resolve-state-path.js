'use strict';
// resolve-state-path.js — SHARED canonical-state-path resolver (JS side).
//
// JS twin of adapters/claude-code/hooks/lib/workstreams-state-resolver.sh.
// Both MUST resolve identically so the writer hooks and the GUI server read
// and write ONE canonical tree-state.json (Workstreams consolidation, Phase A,
// 2026-06-08 — fixes state scattered across ~9 divergent hardcoded paths).
//
// Resolution order (first non-empty wins):
//   1. process.env.CONV_TREE_STATE_PATH — explicit single-sink override.
//      ABSOLUTE precedence, matching the bash resolver and the existing
//      hook/self-test override convention.
//   2. ~/.claude/workstreams-state-path.txt — the home-dir config. Always
//      readable regardless of cwd/worktree. Its single line is the absolute
//      path to the canonical tree-state.json.
//   3. The caller-supplied fallback (the pre-consolidation per-project /
//      module-relative default) — kept so a machine WITHOUT the config file
//      behaves exactly as before (graceful degradation).

const fs = require('fs');
const os = require('os');
const path = require('path');

// The home-dir config file. Overridable via WORKSTREAMS_STATE_CONFIG for tests.
function configPath() {
  return (
    process.env.WORKSTREAMS_STATE_CONFIG ||
    path.join(os.homedir(), '.claude', 'workstreams-state-path.txt')
  );
}

// Read the canonical path from the home config file. Trims surrounding
// whitespace + CR; skips blank/comment lines; returns the first real line, or
// '' if absent/empty/comment-only. Never throws.
function readConfig() {
  const cfg = configPath();
  let raw;
  try {
    raw = fs.readFileSync(cfg, 'utf8');
  } catch (_) {
    return '';
  }
  const lines = raw.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    if (line.charAt(0) === '#') continue;
    return line;
  }
  return '';
}

// resolveWorkstreamsStatePath(fallback)
//   1. CONV_TREE_STATE_PATH env (explicit override)
//   2. canonical home-config path
//   3. fallback (pre-consolidation default)
function resolveWorkstreamsStatePath(fallback) {
  const envOverride = process.env.CONV_TREE_STATE_PATH;
  if (envOverride && String(envOverride).length) return String(envOverride);
  const cfg = readConfig();
  if (cfg) return cfg;
  return fallback;
}

module.exports = { resolveWorkstreamsStatePath, readConfig, configPath };

// --self-test: `node resolve-state-path.js --self-test`. Exit 0 OK / 1 FAIL.
if (require.main === module && process.argv[2] === '--self-test') {
  const assert = require('assert');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wsr-'));
  let failed = 0;
  function ck(name, want, got) {
    try {
      assert.strictEqual(got, want);
      console.log('PASS: ' + name);
    } catch (_) {
      console.log('FAIL: ' + name + ' (want ' + JSON.stringify(want) + ' got ' + JSON.stringify(got) + ')');
      failed++;
    }
  }
  const cfgFile = path.join(tmp, 'cfg.txt');
  fs.writeFileSync(cfgFile, '/canon/from/config.json\n');

  // R1: env override wins
  process.env.WORKSTREAMS_STATE_CONFIG = cfgFile;
  process.env.CONV_TREE_STATE_PATH = '/env/override.json';
  ck('R1 env override wins', '/env/override.json', resolveWorkstreamsStatePath('/fallback.json'));

  // R2: config file used when no env override
  delete process.env.CONV_TREE_STATE_PATH;
  ck('R2 config file used', '/canon/from/config.json', resolveWorkstreamsStatePath('/fallback.json'));

  // R3: fallback when config absent
  process.env.WORKSTREAMS_STATE_CONFIG = path.join(tmp, 'nope.txt');
  ck('R3 fallback when config absent', '/fallback.json', resolveWorkstreamsStatePath('/fallback.json'));

  // R4: trims whitespace + CRLF
  const cfg2 = path.join(tmp, 'cfg2.txt');
  fs.writeFileSync(cfg2, '  /canon/with/space.json  \r\n');
  process.env.WORKSTREAMS_STATE_CONFIG = cfg2;
  ck('R4 trims whitespace+CR', '/canon/with/space.json', resolveWorkstreamsStatePath('/fallback.json'));

  // R5: skips comments/blanks, first real line wins
  const cfg3 = path.join(tmp, 'cfg3.txt');
  fs.writeFileSync(cfg3, '# comment\n\n/canon/after/comment.json\n/second/ignored.json\n');
  process.env.WORKSTREAMS_STATE_CONFIG = cfg3;
  ck('R5 skips comments/blanks', '/canon/after/comment.json', resolveWorkstreamsStatePath('/fallback.json'));

  // R6: empty config -> fallback
  const cfg4 = path.join(tmp, 'empty.txt');
  fs.writeFileSync(cfg4, '');
  process.env.WORKSTREAMS_STATE_CONFIG = cfg4;
  ck('R6 empty config -> fallback', '/fallback.json', resolveWorkstreamsStatePath('/fallback.json'));

  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
  if (failed === 0) { console.log('self-test: OK'); process.exit(0); }
  else { console.log('self-test: ' + failed + ' failed'); process.exit(1); }
}
