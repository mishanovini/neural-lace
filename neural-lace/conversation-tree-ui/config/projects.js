'use strict';
/* conv-tree-ui v1.1.1 item 19 — cross-repo project→root resolver.
 *
 * Two-layer config (harness-hygiene + the established ~/.claude/local pattern):
 *   - SHIPPED, generic: config/projects.example.json (placeholders only).
 *   - PER-MACHINE, gitignored: config/projects.json (real absolute roots).
 * The kit contains NO machine paths / product codenames; the real map lives
 * only in the gitignored instance file. The conv-tree-ui's OWN repo root is
 * auto-detected even with no config so same-repo docs work out of the box.
 *
 * Node stdlib only — NO runtime deps, NO build step (module-wide invariant).
 */
const fs = require('fs');
const path = require('path');

const CFG = path.join(__dirname, 'projects.json'); // gitignored per-machine

// The conv-tree-ui module lives at <repo>/neural-lace/conversation-tree-ui;
// climb to the repo root deterministically (no git dependency at read time).
function selfRepoRoot() {
  // __dirname = <repo>/neural-lace/conversation-tree-ui/config
  return path.resolve(__dirname, '..', '..', '..');
}

// { key: absoluteRoot }. Always includes the conv-tree-ui repo under a key
// derived from its basename AND a stable `neural-lace` alias; the per-machine
// projects.json adds/overrides everything else (cross-repo roots).
function loadProjects() {
  const map = {};
  const self = selfRepoRoot();
  map[path.basename(self)] = self;
  map['neural-lace'] = self;
  try {
    if (fs.existsSync(CFG)) {
      const raw = JSON.parse(fs.readFileSync(CFG, 'utf8'));
      Object.keys(raw).forEach(function (k) {
        if (k === '_comment') return;
        if (typeof raw[k] === 'string' && raw[k]) map[k] = path.resolve(raw[k]);
      });
    }
  } catch (_) { /* malformed instance config → fall back to auto-detected self */ }
  return map;
}

// Resolve (project,relPath) to an absolute path that is PROVABLY inside the
// project root. Rejects traversal, absolute relPaths, unknown projects, and
// missing files. Returns { ok, abs } or { ok:false, code, error }.
function resolveDoc(project, relPath) {
  const map = loadProjects();
  const root = map[project];
  if (!root) return { ok: false, code: 400, error: 'unknown project: ' + String(project) };
  if (!fs.existsSync(root)) return { ok: false, code: 404, error: 'project root not on this machine: ' + project };
  const rel = String(relPath || '');
  if (!rel || rel.indexOf('\0') !== -1) return { ok: false, code: 400, error: 'empty/invalid path' };
  if (path.isAbsolute(rel) || /(^|[\\/])\.\.([\\/]|$)/.test(rel)) {
    return { ok: false, code: 400, error: 'path traversal rejected' };
  }
  const abs = path.resolve(root, rel);
  const rootN = path.resolve(root) + path.sep;
  if (abs !== path.resolve(root) && abs.indexOf(rootN) !== 0) {
    return { ok: false, code: 400, error: 'path escapes project root' };
  }
  if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) {
    return { ok: false, code: 404, error: 'doc not found: ' + rel };
  }
  return { ok: true, abs: abs };
}

// Walk <root>/docs for *.md (recursive, depth-capped, symlink-safe enough for
// a localhost read-only browser). Returns the per-project listing for /api/docs.
function listDocs() {
  const map = loadProjects();
  const out = {};
  Object.keys(map).sort().forEach(function (key) {
    const root = map[key];
    const docsDir = path.join(root, 'docs');
    if (!fs.existsSync(root)) { out[key] = { root: root, missing: true, files: [] }; return; }
    if (!fs.existsSync(docsDir)) { out[key] = { root: root, missing: false, files: [] }; return; }
    const files = [];
    (function walk(dir, depth) {
      if (depth > 6) return;
      let ents;
      try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
      ents.forEach(function (e) {
        if (e.name.charAt(0) === '.') return;
        const fp = path.join(dir, e.name);
        if (e.isDirectory()) { walk(fp, depth + 1); }
        else if (e.isFile() && /\.md$/i.test(e.name)) {
          files.push(path.relative(root, fp).split(path.sep).join('/'));
        }
      });
    })(docsDir, 0);
    files.sort();
    out[key] = { root: root, missing: false, files: files };
  });
  return out;
}

module.exports = { loadProjects, resolveDoc, listDocs, selfRepoRoot };
