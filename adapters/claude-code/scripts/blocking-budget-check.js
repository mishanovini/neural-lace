#!/usr/bin/env node
// blocking-budget-check.js — asserts the ADR 058 D5 "blocking gates <= 13" budget
// (raised from 12 -> 13, harness-governance-batch 2026-07-16: gh-merge-
// canonical + review-before-deploy are this batch's governance gates,
// each carrying the full §10 evidence bar -- evidence-before-fix (task 3)
// was converted to WARN-MODE per its own review and consumes no blocking
// unit. 13 is the MEASURED integrated count (`node blocking-budget-check.js`
// against the current manifest), not headroom -- budget stays deliberately
// tight; raise only with named gates.)
// against manifest.json, using the D.0-frozen counting rule (specs-d §D.0.4):
// count manifest entries with blocking:true AND wired_template:true wired to
// live-session events, grouped into consolidated UNITS. git-boundary hooks
// (precommit/prepush) are a separate budget class. This is the SOLE
// implementation of the frozen counting rule — harness-doctor.sh's
// budget-blocking-gates check (Wave F task F.1, wired at integration) shells
// out to this script rather than reimplementing the UNIT_MAP consolidation a
// third time, so there is exactly one place this rule can drift.
//
// Usage: node blocking-budget-check.js [path/to/manifest.json]
// Defaults to the sibling manifest.json (../manifest.json relative to this
// script) when no path argument is given — preserves the original bare-CLI
// ergonomics; the optional argument lets callers (harness-doctor.sh) point it
// at a live-home or fixture manifest instead.
const path = require('path');
const manifestPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(__dirname, '..', 'manifest.json');
const m = require(manifestPath);

const UNIT_MAP = {
  // command-safety unit: dangerous-command artifact screens (specs-d §D.0.4 #6)
  'env-local-protection': 'command-safety',
  'deploy-automation-mode': 'command-safety',
  // commit-boundary unit: gates firing only on git-commit-shaped Bash commands (#11;
  // vaporware-volume added at D.5 — as-built amendment, CI relocation follows E.4).
  // NOTE: evidence-before-fix (harness-governance-batch-2026-07-15 task 3) was
  // briefly consolidated here, then REMOVED (2026-07-16 harness-review REJECT
  // remediation) when the gate was converted to warn-mode (blocking:false) --
  // the filter below already excludes non-blocking entries, so a UNIT_MAP row
  // for a non-blocking id is dead weight, not merely redundant. If it is ever
  // promoted back to blocking:true (see its manifest entry's PROMOTION
  // CONDITION), re-add 'evidence-before-fix': 'commit-boundary' here at the
  // same time -- it is definitionally the same class as this unit's members.
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
const BUDGET = 13;
const sorted = [...units].sort();
console.log(`blocking session-event units: ${units.size}/${BUDGET}`);
for (const u of sorted) console.log('  ' + u);
if (units.size > BUDGET) {
  console.error(`RED: blocking budget exceeded (${units.size} > ${BUDGET})`);
  process.exit(1);
}
console.log('GREEN: blocking budget met');
