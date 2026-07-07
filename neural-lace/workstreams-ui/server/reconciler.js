'use strict';
// reconciler.js — the divergence reconciler (specs-o §O.4 deliverable 3 +
// §O.4.3 lifecycle amendment).
//
// WHY THIS EXISTS
// ============================================================
// Law 1's escape hatch: while ANY legacy tree-state consumer remains (the
// old event-sourced workstreams-ui/state tree), the cockpit must never
// silently trust it. This module compares the tree-state snapshot's
// session/branch claims against the derived-truth oracle (`nl status
// --json` / od_sessions) and surfaces a visible drift badge whenever they
// disagree. The cockpit NEVER renders tree-state as truth on its own — this
// is comparison-only; every pane's actual data still comes from
// derive-cache.js (the `nl` oracle), never from this module's tree-state
// read.
//
// LIFECYCLE (ux-review + advocate reviews 2026-07-06, specs-o §O.4.3 —
// binding):
//   - Quiet state: "reconciler: 0 drift (checked <ts>)" when the current
//     comparison finds no mismatch.
//   - Firing state: "drift: N claims" with a per-mismatch list (tree says
//     X, derived says Y, "derived is authoritative") + a ledger event id.
//   - CLEARS on reconvergence — this is computed FRESH every check() call
//     from current state, never latched. A mismatch that resolves itself
//     (e.g. the tree-state file gets fixed, or the session concludes on
//     both sides) simply stops appearing on the next check.
//   - The `warn` ledger event (gate=cockpit-reconciler) fires ONCE PER
//     DISTINCT MISMATCH SIGNATURE (dedup key = sorted session/branch
//     claims), never per refresh tick — a stuck drift does not spam the
//     ledger every 30s forever.
//
// If trust-path retirement (specs-o §O.4 deliverable 4) has already
// happened on this checkout (workstreams-ui no longer reads tree-state.json
// at all), `readTreeStateClaims` degrades to an empty claim set and check()
// always reports "0 drift" — see the "superseded-with-evidence" scenario
// note (acceptance scenario 7) for how a runtime check handles that case
// honestly rather than crashing.

const { spawnSync } = require('child_process');
const path = require('path');

function nowIso() { return new Date().toISOString(); }

// _emittedSignatures — process-local memory of ledger-warn signatures
// already emitted, so repeated identical drift does not re-emit every
// refresh tick (the dedup rule above). This is intentionally in-process
// (not persisted): a server restart re-emitting once for a still-live
// drift is an acceptable, honest re-announcement, not a violation of the
// "never per refresh tick" rule (which is about NOT spamming within one
// server's own polling loop).
const _emittedSignatures = new Set();

// readTreeStateClaims() — best-effort read of the legacy tree-state
// snapshot, reduced to the comparable claim: for every node with a bound
// session (session-bound events reduced by the state library), what
// session_id + branch/title does the TREE believe is live. Returns [] on
// any failure (missing file, retired consumer, parse error) — this is the
// honest "tree has nothing to say" case, not an error; check() treats an
// empty claim set as trivially "0 drift" rather than fabricating mismatches
// against nothing.
function readTreeStateClaims(stateLib) {
  if (!stateLib) return [];
  let snapshot;
  try {
    const r = stateLib.readState();
    snapshot = r && r.snapshot;
  } catch (_) {
    return [];
  }
  if (!snapshot || !Array.isArray(snapshot.nodes)) return [];
  const claims = [];
  snapshot.nodes.forEach((n) => {
    // A node is "live" in the tree's own vocabulary when its state is not
    // archived/concluded and it carries at least one bound session
    // (session-bound/unbound events reduced onto node.bound_sessions by
    // the reducer — see state/reducer.js case 'session-bound').
    if (!n || n.state === 'archived' || n.state === 'concluded') return;
    const sids = Array.isArray(n.bound_sessions) ? n.bound_sessions : [];
    sids.forEach((sid) => {
      if (!sid) return;
      claims.push({ session_id: sid, branch: n.title || n.node_id || n.id || 'unknown' });
    });
  });
  return claims;
}

// _sigOf(claims) — deterministic dedup key: sorted "session_id=branch"
// pairs joined. Two checks with the SAME set of mismatched claims produce
// the same signature regardless of ordering or refresh-tick timing.
function _sigOf(mismatches) {
  return mismatches
    .map((m) => m.session_id + '=' + m.tree_branch + '|' + m.derived_state)
    .sort()
    .join(',');
}

// check(stateLib, deriveCache, ledgerEmit) — runs ONE comparison:
//   tree claims (session_id + branch, "this session is live on this branch")
//   vs
//   derived truth (od_sessions rows: session_id + state + branch)
// A mismatch is: a tree-claimed session_id that derived truth does NOT
// list as a live/working session at all (ghost claim — the acceptance
// scenario 7 case: "inject a ghost live-node claim into tree-state"), OR
// a tree-claimed branch that disagrees with the derived branch for that
// same session_id.
//
// Returns the render-ready badge payload:
//   { checked_at, drift_count, mismatches: [{session_id, tree_branch,
//     derived_state, note}], ledger_event_id (or null if none emitted
//     this call) }
function check(stateLib, deriveCache, ledgerEmit) {
  const treeClaims = readTreeStateClaims(stateLib);
  const statusEntry = deriveCache.get('status');
  const derivedSessions = (statusEntry && statusEntry.data && Array.isArray(statusEntry.data.sessions))
    ? statusEntry.data.sessions
    : [];
  const derivedBySid = {};
  derivedSessions.forEach((s) => { derivedBySid[s.session_id] = s; });

  const mismatches = [];
  treeClaims.forEach((claim) => {
    const derived = derivedBySid[claim.session_id];
    if (!derived) {
      mismatches.push({
        session_id: claim.session_id,
        tree_branch: claim.branch,
        derived_state: 'absent',
        note: 'tree claims session "' + claim.session_id + '" is live on "' + claim.branch +
          '"; derived truth (nl status) has no such session — derived is authoritative',
      });
      return;
    }
    if (derived.branch && derived.branch !== 'unknown' && derived.branch !== claim.branch) {
      mismatches.push({
        session_id: claim.session_id,
        tree_branch: claim.branch,
        derived_state: derived.state + ' on ' + derived.branch,
        note: 'tree says branch "' + claim.branch + '", derived says "' + derived.branch +
          '" — derived is authoritative',
      });
    }
  });

  const checkedAt = nowIso();
  let ledgerEventId = null;
  if (mismatches.length > 0 && typeof ledgerEmit === 'function') {
    const sig = _sigOf(mismatches);
    if (!_emittedSignatures.has(sig)) {
      _emittedSignatures.add(sig);
      ledgerEventId = ledgerEmit('cockpit-reconciler', 'warn',
        'drift: ' + mismatches.length + ' claim(s) — ' + mismatches.map((m) => m.session_id).join(','));
    }
  } else if (mismatches.length === 0) {
    // Reconvergence: the badge CLEARS (never latched). Forget every
    // previously-emitted signature so a FUTURE recurrence of the same
    // drift shape is treated as new and re-announced once, per the
    // "never per refresh tick" rule applying to the CURRENT episode only.
    _emittedSignatures.clear();
  }

  return {
    schema: 1,
    checked_at: checkedAt,
    drift_count: mismatches.length,
    mismatches: mismatches,
    ledger_event_id: ledgerEventId,
  };
}

// emitLedgerWarn(gate, event, detail) — default ledger writer: shells the
// bash signal-ledger.sh lib exactly as any other emitter does (there is no
// Node-side ledger writer; the ledger is bash-owned). Returns a synthetic
// event id (ts-based) since ledger_emit itself does not return one — the
// badge only needs SOME stable identifier to display, not a real primary
// key. Best-effort: a failure to emit never throws (the badge still shows
// the drift even if the ledger write silently no-ops on a machine without
// the lib available, e.g. under a fixture NL_BIN with no real repo tree).
function defaultLedgerEmit(gate, event, detail) {
  try {
    // Same three-level walk as derive-cache.js's defaultNlBin (server ->
    // workstreams-ui -> neural-lace -> repo root; adapters/claude-code/ is
    // a sibling of neural-lace/, not of workstreams-ui/ — see that
    // function's comment for the verified-live layout note).
    const repoRoot = path.join(__dirname, '..', '..', '..', 'adapters', 'claude-code');
    const libPath = path.join(repoRoot, 'hooks', 'lib', 'signal-ledger.sh');
    const script = 'source "' + libPath.replace(/"/g, '\\"') + '" && ledger_emit "' + gate + '" "' + event + '" "' +
      String(detail).replace(/"/g, '\\"') + '"';
    spawnSync('bash', ['-c', script], { encoding: 'utf8', timeout: 5000 });
  } catch (_) { /* best-effort; badge still renders the drift */ }
  return 'cockpit-reconciler-' + Date.now();
}

module.exports = { check, readTreeStateClaims, defaultLedgerEmit, _sigOf };
