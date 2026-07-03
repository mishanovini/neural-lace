#!/usr/bin/env node
// blocking-budget-check.js — asserts the ADR 058 D5 "blocking gates <= 12" budget
// against manifest.json, using the D.0-frozen counting rule (specs-d §D.0.4):
// count manifest entries with blocking:true AND wired_template:true wired to
// live-session events, grouped into consolidated UNITS. git-boundary hooks
// (precommit/prepush) are a separate budget class. F.1 wires this into the doctor.
const path = require('path');
const m = require(path.join(__dirname, '..', 'manifest.json'));

const UNIT_MAP = {
  // command-safety unit: dangerous-command artifact screens (specs-d §D.0.4 #6)
  'env-local-protection': 'command-safety',
  'deploy-automation-mode': 'command-safety',
  // commit-boundary unit: gates firing only on git-commit-shaped Bash commands (#11;
  // vaporware-volume added at D.5 — as-built amendment, CI relocation follows E.4)
  'pre-commit-chain': 'commit-boundary',
  'findings-ledger': 'commit-boundary',
  'plan-deletion-protection': 'commit-boundary',
  'claude-md-hygiene': 'commit-boundary',
  'vaporware-volume': 'commit-boundary',
  // agent-teams unit: spawn/task validation (#12; workstreams-state-gate is the
  // same spawn-validation class — counted here, formal fold deferred to F-wave)
  'agent-teams': 'agent-teams',
  'workstreams-spawn-gate': 'agent-teams',
};

const SESSION_EVENTS = ['Stop', 'SessionStart', 'PreToolUse', 'PostToolUse', 'UserPromptSubmit', 'TaskCreated', 'TaskCompleted'];
const units = new Set(
  m.entries
    .filter(e => e.blocking && e.wired_template && (e.events || []).some(ev => SESSION_EVENTS.includes(ev)))
    .map(e => UNIT_MAP[e.id] || e.id)
);
const sorted = [...units].sort();
console.log(`blocking session-event units: ${units.size}/12`);
for (const u of sorted) console.log('  ' + u);
if (units.size > 12) {
  console.error(`RED: blocking budget exceeded (${units.size} > 12)`);
  process.exit(1);
}
console.log('GREEN: blocking budget met');
