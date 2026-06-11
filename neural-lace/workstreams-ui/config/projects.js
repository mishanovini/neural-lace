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
const os = require('os');

const CFG = path.join(__dirname, 'projects.json'); // gitignored per-machine

// The conv-tree-ui module lives at <repo>/neural-lace/conversation-tree-ui;
// climb to the repo root deterministically (no git dependency at read time).
function selfRepoRoot() {
  // __dirname = <repo>/neural-lace/conversation-tree-ui/config
  return path.resolve(__dirname, '..', '..', '..');
}

// A git-worktree / Dispatch-sandbox dir is named `<adjective>-<surname>-<hex>`
// (Docker-style moniker, e.g. `cool-banzai-41ea8a`, `clever-lewin-8c4b2f`).
// Dozens accumulate under the per-org worktree pools; they are ephemeral
// build isolation, NOT projects, and must never pollute the doc browser. The
// trailing segment is 6+ lowercase-hex; the first two are lowercase-alnum
// words. Deliberately does NOT match ordinary repo names: 2-segment names
// (`<word>-<word>`) have no hex tail, and longer names whose final segment
// is not 6+ hex (e.g. ending in `-v2`) also fail — only the exact
// three-part Docker-moniker shape with a hex suffix is treated as a pool.
function isWorktreeName(name) {
  return /^[a-z0-9]+-[a-z0-9]+-[0-9a-f]{6,}$/.test(name);
}

function isSkippedDir(name) {
  if (!name || name.charAt(0) === '.') return true;       // dotfiles / .git
  if (name === '_archived') return true;                  // archived repos
  if (name === 'node_modules') return true;
  if (isWorktreeName(name)) return true;                  // worktree pool
  return false;
}

// True if some key already points at this absolute root, so an explicit
// projects.json entry or the self/neural-lace alias is never shadowed by a
// duplicate auto-discovered key.
function hasRoot(map, root) {
  const target = path.resolve(root);
  return Object.keys(map).some(function (k) {
    try { return path.resolve(map[k]) === target; } catch (_) { return false; }
  });
}

// Auto-discover sibling projects: scan the parent of the conv-tree-ui repo
// (the claude-projects root, computed at runtime — NO machine path in source)
// two levels deep for any directory containing a `docs/` subdir. L1 keys are
// the bare basename; L2 keys are `<parent>/<child>` so they stay unique and
// readable. Worktree pools, `_archived`, dotdirs, node_modules are excluded so
// the ~80 sandbox dirs never surface. Cheap: one readdir per level, a regex
// filter before each existsSync, fully wrapped so a scan failure degrades to
// the explicit map rather than crashing the passive read surface.
// The projects root is `~/claude-projects` by documented convention
// (CLAUDE.md: "Directory-based: ~/claude-projects/<org>/"). Anchoring on
// os.homedir() (runtime-computed, NOT a committed machine path) makes
// discovery layout-independent: it works identically whether the server runs
// from the main checkout or from a git worktree (where selfRepoRoot() would
// otherwise resolve into the worktree pool, one level too deep). Falls back
// to the parent of the repo root if the conventional dir is absent.
function projectsScanRoot() {
  try {
    const conv = path.join(os.homedir(), 'claude-projects');
    if (fs.existsSync(conv) && fs.statSync(conv).isDirectory()) return conv;
  } catch (_) { /* fall through */ }
  return path.dirname(selfRepoRoot());
}

function discoverProjects(map) {
  const scanRoot = projectsScanRoot();
  let l1;
  try { l1 = fs.readdirSync(scanRoot, { withFileTypes: true }); } catch (_) { return; }
  l1.forEach(function (e1) {
    if (!e1.isDirectory() || isSkippedDir(e1.name)) return;
    const p1 = path.join(scanRoot, e1.name);
    try {
      if (fs.existsSync(path.join(p1, 'docs')) && !hasRoot(map, p1)) {
        map[e1.name] = p1;
      }
    } catch (_) { /* ignore */ }
    let l2;
    try { l2 = fs.readdirSync(p1, { withFileTypes: true }); } catch (_) { return; }
    l2.forEach(function (e2) {
      if (!e2.isDirectory() || isSkippedDir(e2.name)) return;
      const p2 = path.join(p1, e2.name);
      try {
        if (fs.existsSync(path.join(p2, 'docs')) && !hasRoot(map, p2)) {
          map[e1.name + '/' + e2.name] = p2;
        }
      } catch (_) { /* ignore */ }
    });
  });
}

// { key: absoluteRoot }. Always includes the conv-tree-ui repo under a key
// derived from its basename AND a stable `neural-lace` alias; the per-machine
// projects.json adds/overrides; filesystem auto-discovery then fills in every
// sibling project that has a docs/ dir (worktree pools excluded).
function loadProjects() {
  const map = {};
  const self = selfRepoRoot();
  // Stable alias always present so same-repo docs work out of the box. The
  // basename key is added too for readability — UNLESS the server was launched
  // from a git worktree (selfRepoRoot() would then be `<pool>/<adjective-
  // surname-hex>`); a worktree is not a project, so only the stable alias is
  // kept in that case.
  if (!isWorktreeName(path.basename(self))) map[path.basename(self)] = self;
  map['neural-lace'] = self;
  // Workstreams coordination repo — its docs live at the repo ROOT (no docs/
  // subdir), so auto-discovery skips it. Stable alias by documented convention
  // (~/claude-projects/workstreams-coordination, runtime-computed — no machine
  // path in source) when present, so item-detail doc links like
  // "REDESIGN-PRD-DRAFT-….md in workstreams-coordination" resolve via
  // /api/doc (resolveDoc's traversal guard applies to this root identically).
  try {
    const coord = path.join(os.homedir(), 'claude-projects', 'workstreams-coordination');
    if (fs.existsSync(coord) && fs.statSync(coord).isDirectory() && !hasRoot(map, coord)) {
      map['workstreams-coordination'] = coord;
    }
  } catch (_) { /* best-effort; absent on machines without the repo */ }
  try {
    if (fs.existsSync(CFG)) {
      const raw = JSON.parse(fs.readFileSync(CFG, 'utf8'));
      Object.keys(raw).forEach(function (k) {
        if (k === '_comment') return;
        if (typeof raw[k] === 'string' && raw[k]) map[k] = path.resolve(raw[k]);
      });
    }
  } catch (_) { /* malformed instance config → fall back to auto-detected self */ }
  // Explicit config + self aliases win; discovery only ADDS new roots.
  try { discoverProjects(map); } catch (_) { /* discovery is best-effort */ }
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
    if (!fs.existsSync(docsDir)) {
      // Root-level *.md fallback (the workstreams-coordination shape: docs at
      // the repo root, no docs/ subdir). Shallow walk (depth ≤ 2) with the
      // same skip rules as discovery so the Docs drawer can list them. Only
      // explicit-alias / per-machine-config projects can lack docs/ (auto-
      // discovery requires it), so the blast radius is those entries only.
      const rootFiles = [];
      (function walkRoot(dir, depth) {
        if (depth > 2) return;
        let ents;
        try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
        ents.forEach(function (e) {
          if (e.name.charAt(0) === '.') return;
          const fp = path.join(dir, e.name);
          if (e.isDirectory()) { if (!isSkippedDir(e.name)) walkRoot(fp, depth + 1); }
          else if (e.isFile() && /\.md$/i.test(e.name)) {
            rootFiles.push(path.relative(root, fp).split(path.sep).join('/'));
          }
        });
      })(root, 0);
      rootFiles.sort();
      out[key] = { root: root, missing: false, files: rootFiles };
      return;
    }
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
