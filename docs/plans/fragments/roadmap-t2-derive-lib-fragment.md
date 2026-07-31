# Fragment: roadmap-t2 → derive-lib.js title fold precedence (A3)

Producer: task-2 builder (branch `build/roadmap-t2`), 2026-07-19.
Consumer: the cockpit-roadmap-redesign orchestrator, AFTER task 1 lands
(task 1 OWNS `neural-lace/workstreams-ui/server/derive-lib.js` +
`server.selftest.js`; task 2 must not edit them — this fragment carries the
exact patch instead).

## What it does

Implements the plan's BINDING A3 fold rule at the reader fold seam:
`foldAskRegistry()`'s `summary` field (the item's TITLE) stops following
plain last-non-empty-wins. Operator-sourced title records
(`title_source:"operator"`, written by the new `ask-registry.sh set-title`
verb — landed on `build/roadmap-t2`) ALWAYS outrank auto-sourced ones
REGARDLESS of timestamp. Within a source class, last-non-empty-wins as
before. Records with no `title_source` (all legacy records) fold as auto.
The folded entry also carries `title_source` so views can label the source.

Without this hunk the F3 race is live: capture t0 → operator edits title
t1 → async distiller lands t2>t1 → the operator's own edit is silently
reverted (PROVEN below — the red run reproduces it against the pristine
fold).

## Verification (already executed by the task-2 builder in its worktree)

- RED (pristine derive-lib.js + this selftest hunk):
  `T2-A3a ... FAIL (got summary="distiller re-run title")` — the distiller
  clobbers the operator title. `self-test summary: 166 passed, 2 failed`.
- GREEN (both hunks applied): `node server/server.selftest.js` →
  `self-test summary: 168 passed, 0 failed` (T2-A3a/b/c all PASS; zero
  regressions in the pre-existing 165).
- `git apply --check` of this exact diff passes against master @ 8f8880a.

## How to apply

From repo root, save the diff block below to a file (or `git apply` the
fenced content directly):

    git apply roadmap-t2-derive-lib.patch

If task 1's changes moved the context, apply with `--3way` or hand-splice:
the derive-lib hunk replaces the field-fold loop inside `foldAskRegistry()`
(drop `'summary'` from the plain-fold list, add the precedence block); the
selftest hunk is purely additive, anchored immediately before the final
`self-test summary` print in `main()`.

## The patch (proven, apply-ready)

```diff
diff --git a/neural-lace/workstreams-ui/server/derive-lib.js b/neural-lace/workstreams-ui/server/derive-lib.js
index adf3551..93ad041 100644
--- a/neural-lace/workstreams-ui/server/derive-lib.js
+++ b/neural-lace/workstreams-ui/server/derive-lib.js
@@ -107,9 +107,25 @@ function foldAskRegistry() {
   lines.forEach((rec) => {
     if (!rec || !rec.ask_id) return;
     const cur = byAsk[rec.ask_id] || { plan_slugs: [] };
-    ['repo', 'project', 'summary', 'verbatim_ref', 'status'].forEach((f) => {
+    ['repo', 'project', 'verbatim_ref', 'status'].forEach((f) => {
       if (rec[f]) cur[f] = rec[f];
     });
+    // TITLE FOLD PRECEDENCE (cockpit-roadmap-redesign Task 2, A3 — BINDING):
+    // `summary` (the item's title) does NOT follow plain last-non-empty-wins.
+    // Operator-sourced title records (title_source:"operator") ALWAYS outrank
+    // auto-sourced ones REGARDLESS of timestamp — an async distiller re-run
+    // landing after an operator edit must never clobber it (capture t0 ->
+    // operator edit t1 -> distiller lands t2>t1 silently reverted the
+    // operator's own edit under the plain fold). Within the same source
+    // class, last-non-empty-wins as before. Records without a title_source
+    // (legacy) are auto: every legacy record is machine-captured.
+    if (rec.summary) {
+      const src = rec.title_source === 'operator' ? 'operator' : 'auto';
+      if (src === 'operator' || cur.title_source !== 'operator') {
+        cur.summary = rec.summary;
+        cur.title_source = src;
+      }
+    }
     if (rec.record_type === 'plan_linked' && rec.plan_slug && cur.plan_slugs.indexOf(rec.plan_slug) === -1) {
       cur.plan_slugs.push(rec.plan_slug);
     }
diff --git a/neural-lace/workstreams-ui/server/server.selftest.js b/neural-lace/workstreams-ui/server/server.selftest.js
index 99ce1bb..ea3c068 100644
--- a/neural-lace/workstreams-ui/server/server.selftest.js
+++ b/neural-lace/workstreams-ui/server/server.selftest.js
@@ -1733,6 +1733,55 @@ async function main() {
     try { if (typeof planAbsPath === 'string') fs.rmSync(planAbsPath, { force: true }); } catch (_) {}
   }
 
+  // ========================================================
+  // cockpit-roadmap-redesign Task 2 (A3) — TITLE FOLD PRECEDENCE:
+  // operator-sourced titles ALWAYS outrank auto-sourced ones REGARDLESS
+  // of timestamp (the async-distiller-clobbers-operator-edit race, arch
+  // review F3). Pure-unit: dedicated fixture dir, env saved/restored;
+  // runs after the server fixture is torn down.
+  // ========================================================
+  {
+    const deriveLibT2 = require('./derive-lib.js');
+    const t2Dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ar-t2-fold-'));
+    const t2Prev = process.env.ASK_REGISTRY_STATE_DIR;
+    try {
+      process.env.ASK_REGISTRY_STATE_DIR = t2Dir;
+      const t2Line = (o) => JSON.stringify(Object.assign({
+        ask_id: 'ask-t2', record_type: '', ts: '', user: 't', machine: 'm', repo: '', project: '',
+        summary: '', verbatim_ref: '', origin_session: '', status: '', plan_slug: '',
+        session_id: '', resumed_from: '', merged_into: '', emitter: 'ask-registry',
+        title_source: '', candidate_id: '', classification: '',
+      }, o));
+      fs.writeFileSync(path.join(t2Dir, 'ask-registry.jsonl'), [
+        t2Line({ record_type: 'created', ts: '2026-07-19T10:00:00Z', summary: 'auto captured title', title_source: 'auto', status: 'active' }),
+        t2Line({ record_type: 'summary_updated', ts: '2026-07-19T10:05:00Z', summary: 'Operator renamed this', title_source: 'operator', emitter: 'operator-ui' }),
+        t2Line({ record_type: 'summary_updated', ts: '2026-07-19T10:10:00Z', summary: 'distiller re-run title', title_source: 'auto', emitter: 'ask-registry-summarizer' }),
+      ].join('\n') + '\n');
+      const foldedT2 = deriveLibT2.foldAskRegistry();
+      ok('T2-A3a operator title survives a NEWER auto distiller re-run (operator-beats-auto regardless of ts)',
+        foldedT2['ask-t2'] && foldedT2['ask-t2'].summary === 'Operator renamed this',
+        'got summary=' + JSON.stringify(foldedT2['ask-t2'] && foldedT2['ask-t2'].summary));
+      ok('T2-A3b folded entry labels its title_source operator (views can render the source)',
+        foldedT2['ask-t2'] && foldedT2['ask-t2'].title_source === 'operator',
+        'got title_source=' + JSON.stringify(foldedT2['ask-t2'] && foldedT2['ask-t2'].title_source));
+
+      // Auto-only asks (incl. legacy records with no title_source value):
+      // plain last-non-empty-wins WITHIN the auto class — the distiller
+      // upgrade still lands when no operator edit exists.
+      fs.writeFileSync(path.join(t2Dir, 'ask-registry.jsonl'), [
+        t2Line({ ask_id: 'ask-t2-auto', record_type: 'created', ts: '2026-07-19T10:00:00Z', summary: 'first heuristic', status: 'active' }),
+        t2Line({ ask_id: 'ask-t2-auto', record_type: 'summary_updated', ts: '2026-07-19T10:05:00Z', summary: 'better distilled', title_source: 'auto' }),
+      ].join('\n') + '\n');
+      const foldedT2b = deriveLibT2.foldAskRegistry();
+      ok('T2-A3c auto-only asks keep last-non-empty-wins (distiller upgrade lands when no operator edit exists)',
+        foldedT2b['ask-t2-auto'] && foldedT2b['ask-t2-auto'].summary === 'better distilled',
+        'got summary=' + JSON.stringify(foldedT2b['ask-t2-auto'] && foldedT2b['ask-t2-auto'].summary));
+    } finally {
+      if (t2Prev === undefined) delete process.env.ASK_REGISTRY_STATE_DIR; else process.env.ASK_REGISTRY_STATE_DIR = t2Prev;
+      try { fs.rmSync(t2Dir, { recursive: true, force: true }); } catch (_) {}
+    }
+  }
+
   console.log('');
   console.log('self-test summary: ' + PASSED + ' passed, ' + FAILED + ' failed');
   process.exit(FAILED === 0 ? 0 : 1);
```

## Second seam, task-4-owned (NOT part of the diff above — orchestrator call)

`neural-lace/workstreams-ui/server/auditor.js:274-290` carries a DELIBERATE
duplicate of `foldAskRegistry` whose stated contract is "identical
semantics to server.js's own versions". Once the hunk above lands, that
contract is broken unless the duplicate learns the same title precedence.
The auditor folds `summary` (auditor.js:280) but its decision logic
consumes `status`/`plan_slugs`, so the practical exposure is label-level,
not correctness-level. RECOMMENDATION: splice the identical precedence
block (same 11 lines, `'summary'` dropped from the plain list) into the
duplicate when task 4 reworks auditor.js — auditor.js is task-4-owned, so
this fragment deliberately ships NO diff for it; parity there is
UNTESTED-IN-ISOLATION and should get its own assertion in task 4's suite.

## Honest limits

- The selftest hunk's anchor (the final summary print) is stable but task 1
  edits the SAME file; expect `--3way` or a hand-splice if contexts drift.
- The writer side (`ask-registry.sh` on `build/roadmap-t2`) already
  defends independently: the async distiller skips its append when an
  operator title record exists. That defense is NOT a substitute for this
  fold rule (a distiller mid-flight during the operator edit can still
  append; the fold is the contract).
