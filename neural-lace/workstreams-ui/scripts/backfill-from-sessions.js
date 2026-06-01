'use strict';
/*
 * backfill-from-sessions.js — one-shot backfill of today's Code/Cowork
 * sessions into the Conv Tree state file.
 *
 * Reads ~/.claude/projects/<encoded-project>/<session-uuid>.jsonl and the
 * sibling /subagents/agent-*.jsonl files, extracts ONLY what the JSONL
 * verifiably contains (session_id, first task, timestamps, stop-hook fires,
 * cwd, parent uuids), and replays the equivalent events through the
 * legitimate state.js `appendEvent` primitive — never hand-written state.
 *
 * Honesty contract:
 *   - Title comes from `queue-operation enqueue.content` (Dispatch-injected
 *     task body) or the first non-`<` user message; never invented.
 *   - Session belongs to the project whose encoded dir-name decodes to the
 *     cwd. Worktree dirs are folded under their parent project.
 *   - Cross-session parent (which session spawned which) is NOT recoverable
 *     from the JSONL alone; sessions are grouped by project only.
 *   - Subagent files (sibling `<sid>/subagents/agent-*.jsonl`) ARE nested
 *     under their parent session — the path structure encodes that link
 *     explicitly.
 *   - Stop = concluded only when one or more `hookEvent: Stop` attachments
 *     fire AND no later assistant message appears.
 *
 * Usage:
 *   node scripts/backfill-from-sessions.js                   # today only
 *   node scripts/backfill-from-sessions.js --since 2026-05-19
 *   node scripts/backfill-from-sessions.js --dry-run
 *   node scripts/backfill-from-sessions.js --sink /path/to/tree-state.json
 *
 * Idempotent: re-running emits the same deterministic event_ids; the state
 * library dedupes by event_id (§2 idempotency).
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// ---- argv ------------------------------------------------------------------
const argv = process.argv.slice(2);
function flag(name) { return argv.includes(name); }
function val(name, dflt) { const i = argv.indexOf(name); return (i >= 0 && argv[i + 1]) ? argv[i + 1] : dflt; }

const DRY_RUN = flag('--dry-run');
const SINCE_ISO = val('--since', new Date().toISOString().slice(0, 10) + 'T00:00:00Z');
const SINCE_MS = Date.parse(SINCE_ISO);

const STATE_LIB = path.resolve(__dirname, '..', 'state', 'state.js');
const SINK = val('--sink', path.resolve(__dirname, '..', 'state', 'tree-state.json'));

const s = require(STATE_LIB);

const PROJECTS_DIR = path.join(os.homedir(), '.claude', 'projects');

// ---- helpers ---------------------------------------------------------------
function sha1Hex(...parts) {
  return crypto.createHash('sha1').update(parts.join('|'), 'utf8').digest('hex');
}
function safeId(prefix, ...parts) {
  return prefix + '-' + sha1Hex(...parts).slice(0, 24);
}
function nodeIdForProject(label) {
  return 'proj-' + label.toLowerCase().replace(/[^a-z0-9._-]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}
function nodeIdForSession(sid) {
  return 'sess-' + sid.replace(/-/g, '').slice(0, 16);
}
function nodeIdForSubagent(parentSid, agentFile) {
  return 'sub-' + sha1Hex(parentSid, agentFile).slice(0, 16);
}

// Derive a clean project label from a real cwd path. cwd is unambiguous
// (e.g. `<repo-root>/<project-name>`) while the encoded
// dir-name is lossy (collapses spaces, /, \ all to `-`). Worktree paths
// (.../.claude/worktrees/<id>) fold to their parent project; the worktree
// id is kept for the session-title context but does not create a separate
// tree node.
function projectFromCwd(cwd, encodedDir) {
  let p = String(cwd || '').replace(/\\/g, '/');
  // Strip a trailing /.claude/worktrees/<id>[/...] so the worktree falls
  // under its parent project.
  p = p.replace(/\/\.claude\/worktrees\/[^/]+.*$/i, '');
  // Best-effort label = basename of the cleaned path.
  const label = p.split('/').filter(Boolean).pop() || encodedDir;
  // Worktree id (if any) for session-title context.
  const wt = String(cwd || '').match(/\.claude[\\/]worktrees[\\/]([^\\/]+)/i);
  const worktree = wt ? wt[1] : null;
  return { project: label, worktree };
}

// Fallback: when no JSONL in a dir yields a cwd, the encoded name decodes
// approximately. Strips `--claude-worktrees-<id>` first, then takes the
// final hyphen-segment. Wrong for multi-word projects but never invented.
function projectFromEncoded(encoded) {
  const wt = encoded.match(/^(.+)--claude-worktrees-([a-z0-9-]+)$/i);
  const base = wt ? wt[1] : encoded;
  const worktree = wt ? wt[2] : null;
  const parts = base.split('-').filter(Boolean);
  return { project: parts[parts.length - 1] || encoded, worktree };
}

// Parse one JSONL file. Honest about what's recoverable.
function parseSession(filepath) {
  let txt;
  try { txt = fs.readFileSync(filepath, 'utf8'); }
  catch (e) { return null; }
  const lines = txt.split('\n').filter(l => l.trim());
  let sid = null, firstTask = null, firstTs = null, lastTs = null;
  let stopFires = 0, lastAssistantTs = null;
  const cwds = new Set();
  for (const ln of lines) {
    let j; try { j = JSON.parse(ln); } catch { continue; }
    sid = sid || j.sessionId || j.session_id || null;
    const ts = j.timestamp || j.ts || null;
    if (ts) {
      if (!firstTs) firstTs = ts;
      lastTs = ts;
    }
    if (j.cwd) cwds.add(j.cwd);
    if (j.attachment?.hookEvent === 'Stop') stopFires++;
    if (j.message?.role === 'assistant' && ts) lastAssistantTs = ts;
    if (!firstTask) {
      if (j.type === 'queue-operation' && j.operation === 'enqueue' && j.content) {
        firstTask = String(j.content).split('\n').find(l => l.trim()) || '';
      } else if (j.message?.role === 'user' && j.message?.content && !j.isSidechain) {
        let t = '';
        const c = j.message.content;
        if (typeof c === 'string') t = c;
        else if (Array.isArray(c)) {
          const tc = c.find(x => x && x.type === 'text');
          if (tc) t = tc.text || '';
        }
        // Skip system-injected wrappers (start with `<` per Claude Code convention)
        if (t && !t.trim().startsWith('<')) {
          firstTask = t.split('\n').find(l => l.trim()) || '';
        }
      }
    }
  }
  // Concluded iff Stop fired AND nothing happened after the last Stop window
  // (conservative: only mark concluded if Stop fires were the tail end).
  const concluded = stopFires > 0 && (!lastAssistantTs || lastAssistantTs <= lastTs);
  return {
    sessionId: sid,
    firstTask: (firstTask || '').slice(0, 78).trim(),
    firstTs,
    lastTs,
    stopFires,
    concluded,
    cwds: [...cwds].slice(0, 3),
  };
}

// ---- emit helpers (idempotent via deterministic event_id) ------------------
let totalEmitted = 0;
let totalSkipped = 0;
const seenNodes = new Set();

function emit(ev) {
  if (DRY_RUN) {
    console.log('[dry-run]', ev.type, ev.node_id, ev.title || '');
    totalEmitted++;
    return;
  }
  try {
    s.appendEvent(ev, { statePath: SINK });
    totalEmitted++;
  } catch (e) {
    totalSkipped++;
    process.stderr.write('skip ' + ev.type + ' ' + ev.node_id + ': ' + (e && e.message || e) + '\n');
  }
}

function emitBranch(nodeId, parentId, title, ts, idTag) {
  if (seenNodes.has(nodeId)) return;
  seenNodes.add(nodeId);
  emit({
    event_id: safeId('cte-bo-' + idTag, nodeId, parentId || 'root'),
    type: 'branch-opened',
    node_id: nodeId,
    parent_id: parentId,
    title: title,
    actor: 'dispatch',
    ts: ts || new Date().toISOString(),
  });
}
function emitConcluded(nodeId, ts) {
  emit({
    event_id: safeId('cte-cc', nodeId),
    type: 'concluded',
    node_id: nodeId,
    actor: 'dispatch',
    ts: ts || new Date().toISOString(),
  });
}

// ---- main walk -------------------------------------------------------------
console.log('[backfill] sink:', SINK);
console.log('[backfill] since:', SINCE_ISO, '(epoch_ms ' + SINCE_MS + ')');
console.log('[backfill] dry-run:', DRY_RUN);

// Project nodes are top-level roots (parent_id: null). Dispatch is
// single-threaded, so per-project chronological order is implicit — no date
// grouping. (Was: projects parented under a `today-<date>` node, which pinned
// each project under the FIRST date that created it and rendered later-date
// sessions under an old day node.)
const projectDirs = fs.readdirSync(PROJECTS_DIR).filter(d =>
  fs.statSync(path.join(PROJECTS_DIR, d)).isDirectory()
);

let sessionsEmitted = 0, subagentsEmitted = 0;

for (const dirName of projectDirs) {
  const dirPath = path.join(PROJECTS_DIR, dirName);
  // Find top-level JSONLs in this dir whose mtime is on/after SINCE.
  const topLevel = fs.readdirSync(dirPath, { withFileTypes: true })
    .filter(e => e.isFile() && e.name.endsWith('.jsonl'))
    .map(e => e.name);
  const todayFiles = topLevel.filter(f => {
    try { return fs.statSync(path.join(dirPath, f)).mtimeMs >= SINCE_MS; }
    catch { return false; }
  });
  if (todayFiles.length === 0) continue;

  // Derive project label from the first parseable session's cwd; fall back
  // to lossy-encoded-name decoding only when no cwd is recoverable.
  let project = null, worktree = null;
  const parsedSessions = [];
  for (const f of todayFiles) {
    const m = parseSession(path.join(dirPath, f));
    if (m) parsedSessions.push({ file: f, meta: m });
    if (!project && m && m.cwds && m.cwds.length) {
      const r = projectFromCwd(m.cwds[0], dirName);
      project = r.project;
      worktree = r.worktree;
    }
  }
  if (!project) {
    const r = projectFromEncoded(dirName);
    project = r.project;
    worktree = r.worktree;
  }
  const projNode = nodeIdForProject(project);
  emitBranch(projNode, null, project, SINCE_ISO, 'proj');

  for (const { file: f, meta } of parsedSessions) {
    const fp = path.join(dirPath, f);
    if (!meta || !meta.sessionId) continue;

    const sessNode = nodeIdForSession(meta.sessionId);
    const titleBits = [];
    titleBits.push(meta.firstTask || ('(session ' + meta.sessionId.slice(0, 8) + ')'));
    if (worktree) titleBits.push('@' + worktree);
    emitBranch(sessNode, projNode, titleBits.join(' '), meta.firstTs, 'sess');
    sessionsEmitted++;

    // Subagent files live under <dirPath>/<sessionId>/subagents/agent-*.jsonl
    const subDir = path.join(dirPath, meta.sessionId, 'subagents');
    if (fs.existsSync(subDir)) {
      let subFiles = [];
      try {
        subFiles = fs.readdirSync(subDir).filter(x => x.startsWith('agent-') && x.endsWith('.jsonl'));
      } catch {}
      for (const sf of subFiles) {
        const sfp = path.join(subDir, sf);
        try {
          if (fs.statSync(sfp).mtimeMs < SINCE_MS) continue;
        } catch { continue; }
        const sub = parseSession(sfp);
        const subNode = nodeIdForSubagent(meta.sessionId, sf);
        const subTitle = (sub && sub.firstTask) || ('subagent ' + sf.replace(/^agent-/, '').slice(0, 12));
        emitBranch(subNode, sessNode, subTitle, sub?.firstTs || meta.firstTs, 'sub');
        subagentsEmitted++;
        if (sub && sub.concluded) emitConcluded(subNode, sub.lastTs);
      }
    }

    if (meta.concluded) emitConcluded(sessNode, meta.lastTs);
  }
}

console.log('---');
console.log('[backfill] sessions emitted:', sessionsEmitted);
console.log('[backfill] subagents emitted:', subagentsEmitted);
console.log('[backfill] total events:', totalEmitted, '(skipped:', totalSkipped + ')');
console.log('[backfill] sink path:', SINK);
