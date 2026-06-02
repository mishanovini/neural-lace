'use strict';
// Component B — the cascading orchestrator's BRAIN.
// orchestration-architecture-2026-05-30.md §3 ("The reconciliation pass").
//
// This module is a PURE, IDEMPOTENT function of its inputs. It performs NO I/O,
// spawns nothing, mutates no global state. The runner (reconciler-run.js) does
// the I/O (read state, scan liveness, append events, write surface, spawn); this
// module just computes WHAT should happen. Running it twice on the same inputs
// produces the same result and (after the first pass's events are applied) the
// second pass emits nothing — idempotency falls out of deriving everything from
// the full snapshot rather than from a per-event delta.
//
// ── The work-item model (derived; see the schema note) ─────────────────────
// Lifecycle events (`item-committed/shipped/blocked`) target an *item* on a
// node (the kind=action/decision/question entries in `node.items[]`). There is
// NO `item-in-flight` event in v1; in-flight is DERIVED. The reconciler's
// per-item state:
//   done       : it.state==='shipped' OR it.checked===true   (the work is finished)
//   blocked    : it.state==='blocked'                          (optionally blocked_on:<id>)
//   committed  : it.state==='committed' && !done              (spawnable)
//   in-flight  : !done && !blocked && the item's node has a LIVE bound session
//   (untracked): no lifecycle state, not done — NOT spawnable (awaits triage)
//
// ── The reconciliation steps (design §3) ───────────────────────────────────
//   3. Compute cascades: blocked items whose blocker is now done → committed.
//   4. Inventory live sessions (passed in from sessions.js).
//   5. Detect stalls: in-flight items whose bound sessions are all stale →
//      orphaned; release the (local) claim.
//   6. Free slots = maxConcurrent − live-session count.
//   7. Spawnable = committed, unclaimed items, priority-ordered.
//   9. Pending-Misha = decision/question items + retry-exhausted items (these
//      are NOT spawned; a session can't resolve a Misha decision).
//  10. Emit the transition events (cascade item-committed, claim-release).
//
// Step 8 (spawn) is the runner's job; this module produces the spawnPlan +
// per-entry spawn command so the runner (and the selftest) can act on it.

// ---- per-item state predicates --------------------------------------------
function isDone(it) {
  return it.state === 'shipped' || it.checked === true;
}
function isBlocked(it) {
  return it.state === 'blocked';
}
function isCommitted(it) {
  return it.state === 'committed' && !isDone(it);
}
function isPendingMishaKind(it) {
  // decision/question items waiting on Misha (unchecked, not parked).
  return (it.kind === 'decision' || it.kind === 'question')
    && !it.checked && !it.deferred && !it.backlogged;
}

// Priority sort key: lower = more urgent.
//   1) explicit priority 1..5 (P1 most urgent; unassigned ⇒ 5)
//   2) cascaded-this-pass jumps ahead within its priority tier (unblock recency)
//   3) stable node/item order as the commit-recency FIFO proxy
// (The snapshot does not store per-item commit timestamps, so (3) is a stable
//  ordering proxy, not a true FIFO — documented limitation for v1.)
function priorityKey(entry) {
  const p = (entry.priority >= 1 && entry.priority <= 5) ? entry.priority : 5;
  const cascadeBoost = entry.cascaded_this_pass ? 0 : 1;
  return [p, cascadeBoost, entry._order];
}
function cmpKey(a, b) {
  const ka = priorityKey(a), kb = priorityKey(b);
  for (let i = 0; i < ka.length; i++) {
    if (ka[i] < kb[i]) return -1;
    if (ka[i] > kb[i]) return 1;
  }
  return 0;
}

// Default config (the runner merges over these from reconciler-config.js).
const DEFAULT_CONFIG = {
  maxConcurrent: 4,            // §3 step 6 — orchestrator slot ceiling
  autoSpawn: false,           // §8 — surface-first; only headless-local is runner-executable
  stallMinutes: 60,           // §3 step 5 — in-flight w/ all sessions older ⇒ orphan
  retryMax: 2,                // §3 spawn-failure — then → pending-Misha
  machineId: 'local',
  // kind → runner_kind. Only 'headless-local' is runner-executable (via
  // `claude -p`); 'code-task'/'cowork'/'routine' are surfaced for Dispatch's
  // agent loop (it alone can call the MCP spawn tools — ADR-031 r5).
  runnerKindMap: { action: 'code-task', decision: 'cowork', question: 'cowork' },
};

// Build the spawn prompt for a work item — the Component-A composition point.
// Cloud/Code/Cowork sessions have NO local /goal Stop hook, so the audit/DoD
// text is carried INLINE in the spawn prompt (orchestration-architecture §3
// "the spawn prompt always carries the work item's DoD + verification command").
function buildSpawnPrompt(item, node) {
  const details = item.details || {};
  const dod = details.dod || details.definition_of_done
    || ('the work described above is complete and demonstrably works end-to-end');
  const verification = details.verification || details.verify
    || 'demonstrate the user-facing outcome (run the command / exercise the path), do not stop at "it compiles"';
  const lines = [];
  lines.push('Work item: ' + String(item.text || '(untitled)'));
  if (node && node.title) lines.push('Context (branch): ' + String(node.title));
  lines.push('');
  lines.push('Definition of done: ' + String(dod));
  lines.push('Verification command / evidence: ' + String(verification));
  lines.push('');
  // Inline /goal-style audit clause (Component A carried inline for non-local
  // sessions). Mirrors the Codex continuation discipline: disqualify proxy
  // signals; require artifact evidence.
  lines.push('Before declaring done: audit your work against the definition of done above. '
    + 'Disqualify proxy signals — passing tests / "substantial effort" are evidence ONLY if they cover the full definition. '
    + 'Cite the file paths, commit SHAs, and command output that prove each requirement is met. '
    + 'If any requirement is unmet, keep working; if blocked, surface the blocker rather than '
    + 'claiming completion.');
  return lines.join('\n');
}

// Build the runner-executable spawn command for a plan entry. ONLY
// runner_kind==='headless-local' yields an executable `claude -p` argv; every
// other runner_kind is surfaced (executable=false) for Dispatch to launch.
//   Returns { executable, runner_kind, argv|null, prompt }
function buildSpawnCommand(entry, config) {
  const cfg = Object.assign({}, DEFAULT_CONFIG, config || {});
  const prompt = entry.prompt;
  if (entry.runner_kind !== 'headless-local') {
    return { executable: false, runner_kind: entry.runner_kind, argv: null, prompt: prompt };
  }
  // Headless one-shot local session. The runner unsets CLAUDECODE before exec
  // (the nested-session guard) — see reconciler-run.js. `-p` = print/non-
  // interactive; permission-mode dontAsk so it runs unattended; json output so
  // the runner can capture the result.
  const argv = [
    '-p', prompt,
    '--output-format', 'json',
    '--permission-mode', 'dontAsk',
  ];
  if (cfg.spawnModel) { argv.push('--model', String(cfg.spawnModel)); }
  return { executable: true, runner_kind: 'headless-local', argv: argv, prompt: prompt };
}

// ── reconcile(input) → result ──────────────────────────────────────────────
// input:
//   snapshot     : { nodes:[{node_id,title,items:[...],bound_sessions:[sid],...}], backlog }
//   liveSessions : [{ session_id, fresh, age_min }]  (from sessions.js)
//   claims       : { <item_id>: { machine_id, claimed_at, lease_ttl_min } }  (Component C; v1 local-stub, usually {})
//   config       : partial override of DEFAULT_CONFIG
//   now          : ms epoch (default Date.now())
function reconcile(input) {
  input = input || {};
  const config = Object.assign({}, DEFAULT_CONFIG, input.config || {});
  const snapshot = input.snapshot || { nodes: [], backlog: [] };
  const nodes = Array.isArray(snapshot.nodes) ? snapshot.nodes : [];
  const live = Array.isArray(input.liveSessions) ? input.liveSessions : [];
  const claims = input.claims || {};
  const now = input.now != null ? Number(input.now) : Date.now();

  const liveBySid = new Map();
  for (const s of live) liveBySid.set(s.session_id, s);
  const freshLiveCount = live.filter(function (s) { return s.fresh; }).length;

  // Flatten items with their owning node + a stable order index, and index by
  // item_id so the cascade can resolve a blocker by id.
  const itemsFlat = [];
  const itemById = new Map();
  let order = 0;
  for (const node of nodes) {
    const items = Array.isArray(node.items) ? node.items : [];
    for (const it of items) {
      const rec = { it: it, node: node, _order: order++ };
      itemsFlat.push(rec);
      itemById.set(it.item_id, rec);
    }
  }

  // ── Step 3: cascades ──────────────────────────────────────────────────────
  // A blocked item whose blocker (it.blocked_on) is now done → committed.
  // Idempotent: after we emit item-committed, the item's state is no longer
  // 'blocked' on the next pass, so the cascade never re-fires.
  const cascades = [];
  const emittedEvents = [];
  const cascadedItemIds = new Set();
  for (const rec of itemsFlat) {
    const it = rec.it;
    if (!isBlocked(it)) continue;
    if (it.blocked_on == null) continue;            // blocked, but no declared dependency
    const blocker = itemById.get(it.blocked_on);
    if (blocker && isDone(blocker.it)) {
      cascades.push({
        item_id: it.item_id, node_id: rec.node.node_id,
        title: it.text, unblocked_by: it.blocked_on,
      });
      cascadedItemIds.add(it.item_id);
      emittedEvents.push({
        type: 'item-committed', node_id: rec.node.node_id, item_id: it.item_id,
        reason: 'cascade: unblocked by ' + String(it.blocked_on) + ' shipping',
      });
    }
  }

  // ── Steps 4+5: live-session inventory → stall/orphan detection ─────────────
  // An item is in-flight if it's not done/blocked AND its node has ≥1 bound
  // session. It's orphaned if EVERY bound session is stale (age > stallMinutes)
  // or absent from the live set. Orphan ⇒ release its (local) claim, surface it.
  const orphans = [];
  for (const rec of itemsFlat) {
    const it = rec.it;
    if (isDone(it) || isBlocked(it)) continue;
    const bound = Array.isArray(rec.node.bound_sessions) ? rec.node.bound_sessions : [];
    if (bound.length === 0) continue;               // not session-bound ⇒ not in-flight
    // in-flight: is ANY bound session fresh?
    let anyFresh = false;
    let oldestAge = 0;
    for (const sid of bound) {
      const s = liveBySid.get(sid);
      const age = s ? s.age_min : Infinity;          // absent transcript ⇒ infinitely stale
      if (s && s.fresh) anyFresh = true;
      if (age > oldestAge) oldestAge = age;
    }
    if (!anyFresh) {
      // All bound sessions stale ⇒ orphaned. (We can't kill the session, only
      // surface + release the claim so the item is eligible for re-spawn.)
      orphans.push({
        item_id: it.item_id, node_id: rec.node.node_id, title: it.text,
        session_ids: bound.slice(), oldest_age_min: oldestAge,
        stall_minutes: config.stallMinutes,
      });
      if (claims[it.item_id] && claims[it.item_id].machine_id === config.machineId) {
        emittedEvents.push({
          type: 'claim-released', item_id: it.item_id, machine_id: config.machineId,
          reason: 'orphan: in-flight item stalled > ' + config.stallMinutes + 'min',
        });
      }
    }
  }
  // Note: 'claim-released' is NOT a v1 schema event type (Component C owns the
  // claim event-classes). In single-machine v1 the runner writes these to the
  // local claims stub, NOT to the ADR-032 log. They are surfaced here for the
  // runner to act on; the runner filters schema-valid events before appendEvent.

  // ── Step 6: free slots ─────────────────────────────────────────────────────
  const freeSlots = Math.max(0, config.maxConcurrent - freshLiveCount);

  // ── Step 7: spawnable (committed + unclaimed), priority-ordered ────────────
  // Committed = state==='committed' (incl. items cascaded THIS pass — their
  // emitted item-committed makes them committed once applied; we treat them as
  // committed now so the cascade→spawn pipeline completes in one pass).
  const committedNow = new Set(cascadedItemIds);
  const spawnableRaw = [];
  for (const rec of itemsFlat) {
    const it = rec.it;
    // ONLY action items are auto-spawnable. A committed decision/question is a
    // Misha touchpoint, not work a session can pick up — it goes to
    // pending-Misha exclusively (even when lifecycle-backfill set its state to
    // 'committed'). This is the spawn-queue / attention-queue orthogonality
    // (design §3 "Misha-pending does NOT block the spawn queue").
    if (it.kind !== 'action') continue;
    const committed = isCommitted(it) || committedNow.has(it.item_id);
    if (!committed) continue;
    if (isDone(it)) continue;
    // Skip items with a live claim from ANOTHER machine (Component C). In v1
    // local-stub claims, this is effectively never true.
    const claim = claims[it.item_id];
    if (claim && !_claimExpired(claim, now) && claim.machine_id !== config.machineId) continue;
    // retry exhaustion → pending-Misha, not spawnable.
    const retry = Number(it.retry_count || 0);
    if (retry >= config.retryMax) continue;
    const runnerKind = config.runnerKindMap[it.kind] || 'code-task';
    spawnableRaw.push({
      item_id: it.item_id, node_id: rec.node.node_id, title: it.text,
      kind: it.kind, priority: Number(it.priority || 5),
      runner_kind: runnerKind, retry_count: retry,
      cascaded_this_pass: cascadedItemIds.has(it.item_id),
      _order: rec._order, _node: rec.node, _it: it,
    });
  }
  spawnableRaw.sort(cmpKey);

  // ── Step 9: pending-Misha ──────────────────────────────────────────────────
  const pendingMisha = [];
  for (const rec of itemsFlat) {
    const it = rec.it;
    if (isPendingMishaKind(it)) {
      pendingMisha.push({
        item_id: it.item_id, node_id: rec.node.node_id, title: it.text, kind: it.kind,
        reason: 'awaiting Misha (' + it.kind + ')',
      });
    } else if (Number(it.retry_count || 0) >= config.retryMax && !isDone(it)) {
      pendingMisha.push({
        item_id: it.item_id, node_id: rec.node.node_id, title: it.text, kind: it.kind,
        reason: 'spawn retries exhausted (' + it.retry_count + '/' + config.retryMax + ') — needs Misha',
      });
    }
  }

  // ── Step 8 (plan only): fill free slots with the top spawnable items ───────
  const spawnPlan = [];
  for (let i = 0; i < spawnableRaw.length && spawnPlan.length < freeSlots; i++) {
    const s = spawnableRaw[i];
    const prompt = buildSpawnPrompt(s._it, s._node);
    const cmd = buildSpawnCommand({ runner_kind: s.runner_kind, prompt: prompt }, config);
    spawnPlan.push({
      item_id: s.item_id, node_id: s.node_id, title: s.title, kind: s.kind,
      runner_kind: s.runner_kind, priority: s.priority,
      executable: cmd.executable, argv: cmd.argv, prompt: prompt,
    });
  }
  const spawnDeferredCount = Math.max(0, spawnableRaw.length - spawnPlan.length);

  // Strip internal sort fields from the surfaced spawnable list.
  const spawnable = spawnableRaw.map(function (s) {
    return {
      item_id: s.item_id, node_id: s.node_id, title: s.title, kind: s.kind,
      priority: s.priority, runner_kind: s.runner_kind,
      retry_count: s.retry_count, cascaded_this_pass: s.cascaded_this_pass,
    };
  });

  return {
    cascades: cascades,
    orphans: orphans,
    liveCount: freshLiveCount,
    freeSlots: freeSlots,
    spawnable: spawnable,
    spawnPlan: spawnPlan,
    spawnDeferredCount: spawnDeferredCount,   // spawnable but no free slot this pass (no silent cap)
    pendingMisha: pendingMisha,
    emittedEvents: emittedEvents,             // runner appends the schema-valid ones; filters the rest
    config: { maxConcurrent: config.maxConcurrent, autoSpawn: config.autoSpawn, machineId: config.machineId },
    computed_at: now,
  };
}

function _claimExpired(claim, now) {
  if (!claim || claim.claimed_at == null) return true;
  const ttlMs = (Number(claim.lease_ttl_min) || 30) * 60000;
  return now - Number(claim.claimed_at) > ttlMs;
}

module.exports = {
  DEFAULT_CONFIG,
  reconcile,
  buildSpawnPrompt,
  buildSpawnCommand,
  isDone, isBlocked, isCommitted, isPendingMishaKind,
};
