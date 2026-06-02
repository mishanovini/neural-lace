'use strict';
// workstreams-task-bridge.js — the transcript→Workstreams bridge.
//
// Part of the TaskCreate/TaskList ↔ Workstreams binding
// (docs/plans/taskcreate-workstreams-binding.md). Invoked by
// workstreams-task-binding.sh --on-stop.
//
// What it does, in ONE transcript scan:
//   1. Counts total tool calls (tool_use blocks) and task-list MUTATIONS
//      (TaskCreate + TaskUpdate) in the session transcript.
//   2. (when --emit) mirrors every Task* mutation into the durable
//      Workstreams (ADR-032) event log via the FROZEN appendEvent facade:
//        TaskCreate                    -> action-added   (a WorkItem of kind=action)
//        TaskUpdate status=in_progress -> session-bound  (provenance: this session)
//        TaskUpdate status=completed   -> action-done    (item checked / shipped)
//        TaskUpdate status=deleted     -> item-backlogged (parked, NOT shipped)
//      NO new event type is introduced — every event above already exists in
//      schema.js EVENT_TYPES, so the reducer/schema are untouched (zero
//      collision with the concurrent Component B work on reducer.js/schema.js).
//
// The bridge is a WRITER: every emission failure is isolated and logged; the
// process always exits 0 with a JSON summary on stdout so the calling bash
// hook can make the (separate) Mechanism-1 block decision deterministically.
//
// Idempotency: every emitted event carries a deterministic event_id derived
// from (session, node/item, task-id), so a re-fired Stop / re-run is a
// per-file no-op. The session tree node is `ss-<sha1(session)>` — the SAME id
// scheme conversation-tree-emit.sh uses — so the bridge's branch-opened
// dedupes against the emit hook's instead of creating a duplicate node.
//
// CLI:
//   node workstreams-task-bridge.js \
//     --transcript <path> --session <sid> \
//     [--state-lib <state.js>] [--state-path <sink.json>] [--emit] \
//     [--project-root <id>] [--project-title <title>]
//
// stdout (always, single line):
//   {"toolCalls":N,"taskCalls":M,"taskMutations":K,"taskCreates":C,
//    "taskUpdates":U,"emitted":E,"ok":true}

const fs = require('fs');
const crypto = require('crypto');

// ---- tiny arg parser -------------------------------------------------------
function parseArgs(argv) {
  const a = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k.slice(0, 2) === '--') {
      const name = k.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.slice(0, 2) === '--') { a[name] = true; }
      else { a[name] = next; i++; }
    }
  }
  return a;
}

function sha1hex(s) {
  return crypto.createHash('sha1').update(String(s)).digest('hex');
}

function sanitizeId(s) {
  return String(s || '')
    .replace(/[^A-Za-z0-9._-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

const TASK_TOOLS = { TaskCreate: 1, TaskUpdate: 1, TaskList: 1, TaskGet: 1 };

// Extract result text from a tool_result block's `.content` (string OR array
// of {type:'text', text} blocks — both shapes occur in the transcript).
function resultText(block) {
  const c = block && block.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    return c.map(function (x) {
      if (typeof x === 'string') return x;
      if (x && typeof x.text === 'string') return x.text;
      return '';
    }).join('\n');
  }
  return '';
}

// ---- transcript scan -------------------------------------------------------
// Returns { toolCalls, taskCalls, creates:[{taskId,subject}], updates:[{taskId,status}] }.
function scanTranscript(transcriptPath) {
  const out = { toolCalls: 0, taskCalls: 0, creates: [], updates: [], _byUseId: {} };
  let raw = '';
  try { raw = fs.readFileSync(transcriptPath, 'utf8'); }
  catch (e) { return out; } // no transcript -> zero counts (caller no-ops)

  const lines = raw.split('\n');
  // tool_use_id -> {name, input} so a later tool_result recovers the assigned id.
  const useById = out._byUseId;
  // taskId -> subject (enriched from TaskCreate results + TaskList results).
  const subjectById = {};

  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    if (!ln) continue;
    let obj;
    try { obj = JSON.parse(ln); } catch (e) { continue; }
    const msg = obj && obj.message;
    const content = msg && msg.content;
    if (!Array.isArray(content)) continue;

    for (let j = 0; j < content.length; j++) {
      const b = content[j];
      if (!b || typeof b !== 'object') continue;

      if (b.type === 'tool_use') {
        out.toolCalls++;
        const name = b.name;
        if (TASK_TOOLS[name]) {
          out.taskCalls++;
          useById[b.id] = { name: name, input: b.input || {} };
          if (name === 'TaskCreate') {
            // subject known immediately; id arrives in the tool_result.
            out.creates.push({ taskId: null, subject: (b.input && b.input.subject) || '', useId: b.id });
          } else if (name === 'TaskUpdate') {
            const inp = b.input || {};
            if (inp.status) {
              out.updates.push({ taskId: String(inp.taskId), status: String(inp.status) });
            }
          }
        }
      } else if (b.type === 'tool_result') {
        const use = useById[b.tool_use_id];
        if (!use) continue;
        const txt = resultText(b);
        if (use.name === 'TaskCreate') {
          // "Task #1 created successfully: <subject>"
          const m = txt.match(/#(\d+)/);
          if (m) {
            const id = m[1];
            // back-fill the matching create record's taskId.
            for (let k = out.creates.length - 1; k >= 0; k--) {
              if (out.creates[k].useId === b.tool_use_id) { out.creates[k].taskId = id; break; }
            }
            if (use.input && use.input.subject) subjectById[id] = use.input.subject;
          }
        } else if (use.name === 'TaskList') {
          // Lenient: "#1. [status] subject" lines. Enriches subjectById only.
          const re = /#?(\d+)\.?\s*\[(?:pending|in_progress|completed|deleted)\]\s*(.+)/g;
          let mm;
          while ((mm = re.exec(txt)) !== null) { subjectById[mm[1]] = mm[2].trim(); }
        }
      }
    }
  }

  // For any create still missing a subject but with a known id, recover it.
  for (let k = 0; k < out.creates.length; k++) {
    const c = out.creates[k];
    if (!c.subject && c.taskId && subjectById[c.taskId]) c.subject = subjectById[c.taskId];
    if (!c.subject) c.subject = '(untitled task)';
  }
  return out;
}

// ---- event building --------------------------------------------------------
// Session-scoped, deterministic item id: same (session,taskId) -> same id, so
// a TaskUpdate event targets the item its TaskCreate produced.
function itemId(sidSafe, taskId) {
  return 'wt-' + sha1hex(sidSafe + '|' + String(taskId)).slice(0, 12);
}

function buildEvents(scan, opts) {
  const sidSafe = sanitizeId(opts.session);
  const rootId = opts.projectRoot || 'global';
  const rootTitle = opts.projectTitle || rootId;
  const nodeId = 'ss-' + sha1hex(sidSafe).slice(0, 12);
  const events = [];

  // Branch-opened for root + session node — event_id matches the emit hook's
  // scheme (cte-bo-<sha1(id):32>) so it dedupes instead of duplicating.
  events.push({
    event_id: 'cte-bo-' + sha1hex(rootId).slice(0, 32),
    type: 'branch-opened', node_id: rootId, parent_id: null, title: rootTitle, actor: 'dispatch',
  });
  events.push({
    event_id: 'cte-bo-' + sha1hex(nodeId).slice(0, 32),
    type: 'branch-opened', node_id: nodeId, parent_id: rootId, title: 'tasks — session ' + sidSafe.slice(0, 12), actor: 'dispatch',
  });

  // TaskCreate -> action-added
  for (let i = 0; i < scan.creates.length; i++) {
    const c = scan.creates[i];
    const key = c.taskId != null ? c.taskId : ('subj:' + c.subject);
    const iid = itemId(sidSafe, key);
    events.push({
      event_id: 'wtb-aa-' + sha1hex(nodeId + '|' + iid).slice(0, 24),
      type: 'action-added', node_id: nodeId, item_id: iid, text: String(c.subject).slice(0, 200), actor: 'dispatch',
    });
  }

  // TaskUpdate -> status-mapped event
  for (let i = 0; i < scan.updates.length; i++) {
    const u = scan.updates[i];
    const iid = itemId(sidSafe, u.taskId);
    if (u.status === 'in_progress') {
      // provenance link — last-writer-wins; key on (node,session) so re-fire dedupes.
      events.push({
        event_id: 'wtb-sb-' + sha1hex(nodeId + '|' + sidSafe).slice(0, 24),
        type: 'session-bound', node_id: nodeId, session_id: sidSafe, actor: 'dispatch',
      });
    } else if (u.status === 'completed') {
      events.push({
        event_id: 'wtb-ad-' + sha1hex(nodeId + '|' + iid).slice(0, 24),
        type: 'action-done', node_id: nodeId, item_id: iid, actor: 'dispatch',
      });
    } else if (u.status === 'deleted') {
      events.push({
        event_id: 'wtb-bk-' + sha1hex(nodeId + '|' + iid).slice(0, 24),
        type: 'item-backlogged', node_id: nodeId, item_id: iid, actor: 'dispatch',
      });
    }
  }
  return events;
}

// ---- main ------------------------------------------------------------------
function main() {
  const args = parseArgs(process.argv);
  const summary = { toolCalls: 0, taskCalls: 0, taskMutations: 0, taskCreates: 0, taskUpdates: 0, emitted: 0, ok: true };
  try {
    const scan = scanTranscript(args.transcript || '');
    summary.toolCalls = scan.toolCalls;
    summary.taskCalls = scan.taskCalls;
    summary.taskCreates = scan.creates.length;
    summary.taskUpdates = scan.updates.length;
    summary.taskMutations = scan.creates.length + scan.updates.length;

    if (args.emit && args['state-lib'] && args['state-path']) {
      let lib;
      try { lib = require(args['state-lib']); }
      catch (e) { summary.ok = false; summary.error = 'lib:' + (e && e.message || e); process.stdout.write(JSON.stringify(summary)); return; }
      const events = buildEvents(scan, {
        session: args.session || '',
        projectRoot: args['project-root'] || 'global',
        projectTitle: args['project-title'] || (args['project-root'] || 'global'),
      });
      for (let i = 0; i < events.length; i++) {
        try { lib.appendEvent(events[i], { statePath: args['state-path'] }); summary.emitted++; }
        catch (e) { process.stderr.write('evt-skip[' + events[i].type + ']:' + (e && e.message || e) + '\n'); }
      }
    }
  } catch (e) {
    summary.ok = false; summary.error = String(e && e.message || e);
  }
  process.stdout.write(JSON.stringify(summary));
}

main();
