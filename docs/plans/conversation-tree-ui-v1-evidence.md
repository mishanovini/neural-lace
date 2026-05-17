# Evidence Log — Conversation Tree UI v1

Companion evidence file for `docs/plans/conversation-tree-ui-v1.md`. The plan
declares `rung: 2`, so tasks at or above R2 require a `## Comprehension
Articulation` block (per `~/.claude/rules/comprehension-gate.md`) before
`task-verifier` flips the checkbox.

---

## Task 0.1 — Walking Skeleton: file-mediated read/write spine

Code shipped as commit `952c9d6` (Phase 0 Walking Skeleton). The functional
spine was independently corroborated by task-verifier (1-node baseline → SSE
push → 2 nodes, no reload). This entry supplies the comprehension articulation
the rung-2 gate requires; no checkbox is flipped here.

## Comprehension Articulation

### Spec meaning

The Walking Skeleton has to prove, end-to-end and for real, the *passive
file-mediated tracker spine* that ADR-031 Option 2 commits the whole v1 to —
not a feature, just the load-bearing data path. Concretely: a writer mutates a
single well-known JSON file whose shape carries a `schema_version` integer, an
append-only `events` array, and a `snapshot` that is *derived* (reduced) from
those events rather than independently authored. A separate Node process,
using only the standard library (no framework, no build step, no new runtime
dep), serves the static page and exposes the current snapshot — it only ever
*reads* the file; it never writes state and never spawns or steers a Claude
Code session. A vanilla browser page renders exactly one visual node per
`branch-opened` event. The skeleton must demonstrate liveness: appending a
second event makes the page go from one node to two with no manual reload,
pushed to the browser. ADR-031 r7 Pin 3b is the hard correctness requirement —
a state mutation must publish as a *single atomic step* so any concurrent
reader of the well-known path sees either the pre-mutation file or the
post-mutation file in whole, never a half-written event. Everything binds to
localhost only (NFR-5). The state shape is deliberately *forward-shaped*
toward ADR-032 but the full event-type enum / node layout is explicitly NOT
pre-built — Phase 0 ships exactly one event type and the minimal reducer for
it.

### Edge cases covered

- **Atomic publish (Pin 3b).** Every mutation writes to a unique temp path
  then `renameSync`s it over the well-known file in one step:
  `state/state.js:77` builds `STATE_FILE + '.tmp.' + process.pid + '.' +
  Date.now()`, `state/state.js:78` writes the whole serialized state to that
  temp, and `state/state.js:79` `fs.renameSync(tmp, STATE_FILE)` performs the
  single atomic publish. The whole file (events + recomputed snapshot) is
  replaced in one rename, so a reader never observes a torn append.
- **Server survives the inode swap.** Because write-temp-then-rename replaces
  the file's inode, watching the file directly would stop firing after the
  first rename. The server instead watches the *directory* and filters on the
  basename: `server/server.js:45` computes `stateBase =
  path.basename(STATE_FILE)`, `server/server.js:46` calls
  `fs.watch(path.dirname(STATE_FILE), ...)`, and `server/server.js:47`
  filters `if (filename && filename !== stateBase) return;` — so the watcher
  keeps firing across every atomic-rename swap. The rename's
  create/rename event pair is coalesced by a 40 ms debounce at
  `server/server.js:48-49`.
- **Missing / torn state file read fallback.** `state/state.js:39-45`
  catches read/parse failure: `ENOENT` returns a fresh `emptyState()` at
  `state/state.js:40` (first-run, no file yet), and any other parse failure
  writes a diagnostic to stderr at `state/state.js:43` and returns
  `emptyState()` at `state/state.js:44` — surfaced, not silently swallowed.
  A non-numeric `schema_version` is also treated as empty at
  `state/state.js:37`.
- **SSE initial-frame-on-connect vs push-on-change.** On a new SSE
  connection the server immediately pushes the current snapshot:
  `server/server.js:80` calls `sendState(res)` right after adding the client
  at `server/server.js:79`, so a freshly loaded page renders the existing
  state without waiting for a mutation. Subsequent changes are pushed via
  `broadcastState()` (`server/server.js:35-39`) driven by the directory
  watcher. The client treats a zero-node snapshot as the empty state
  (`web/app.js:17-20`) rather than rendering nothing ambiguous.

### Edge cases NOT covered

- **Torn-snapshot recovery by log replay (Pin 3a).** Phase 0 deliberately
  degrades a corrupt/torn file to `emptyState()` (`state/state.js:41-44`
  comment says so explicitly). Real recovery — replaying the append-only log
  to rebuild the snapshot — is Phase A work, not in this skeleton. Correctly
  deferred: Pin 3a recovery depends on the ADR-032 schema field layout which
  does not exist yet.
- **Multi-project + global-tree path resolution.** The well-known path is a
  single global file fixed at `state/state.js:24-25` (`STATE_DIR =
  __dirname`, `tree-state.json`). Per-project and global-tree resolution
  (FR-18 / FR-25) is owned by ADR-032 / Phase A and explicitly flagged
  not-decided-here in the `state/state.js:22-23` comment. Correctly deferred.
- **Event types beyond `branch-opened`.** The reducer at
  `state/state.js:49-62` handles exactly one event type; the full enum
  (decision-raised, question-raised, answered, action-added, concluded,
  re-opened, archived, …) is ADR-032's. A non-`branch-opened` event is
  silently ignored by the reducer loop — acceptable for Phase 0 because no
  other type is emitted yet; the full reduction is Phase A.
- **Enforcement substrate.** No PreToolUse / Stop gate, no Pattern rule, no
  hook wiring exists in this commit — the server is a pure passive reader
  (`server/server.js:11-12`). Enforcement (`conversation-tree-state-gate.sh`,
  the Stop gate, the Pattern rule) is Phase B; the skeleton intentionally
  proves only the read/write data path.
- **Concurrent-writer correctness / NFR-2.** Phase 0 has a single writer
  (the CLI seed entrypoint at `state/state.js:87-98`). True concurrent
  GUI-append + Dispatch-append conflict resolution (NFR-2 conflict-unit) is
  ADR-032 / Phase A; this skeleton does not exercise two simultaneous
  writers.

### Assumptions

- **Same-filesystem `rename()` atomicity.** The Pin-3b guarantee at
  `state/state.js:79` holds only because the temp file
  (`state/state.js:77`, built from `STATE_FILE + '.tmp...'`) lives in the
  *same directory* as `STATE_FILE` (`state/state.js:24-25`), so the rename is
  same-filesystem and POSIX-atomic. A cross-filesystem temp would make
  `renameSync` a non-atomic copy+unlink; the code structurally avoids that by
  deriving the temp path from `STATE_FILE` itself.
- **Single writer for Phase 0.** Correctness of the read-modify-write in
  `appendBranchOpened` (`state/state.js:65-81`: `readState()` →
  `events.push` → `deriveSnapshot` → atomic publish) assumes no second writer
  interleaves between the read at `state/state.js:67` and the rename at
  `state/state.js:79`. Phase 0 only has the single CLI seed writer
  (`state/state.js:87-98`), so this holds; multi-writer is explicitly
  Phase A.
- **Localhost-only trust.** The server does no auth and serves arbitrary
  `web/` assets via `serveStatic` (`server/server.js:52-59`). Safe only
  because it binds `127.0.0.1` (`server/server.js:21`, `HOST = '127.0.0.1'`,
  passed to `server.listen` at `server/server.js:89`) per NFR-5 — a
  non-localhost bind would expose an unauthenticated file server.
- **Browser `EventSource` support.** Liveness depends entirely on the
  client's `new EventSource('/api/events')` at `web/app.js:44`; there is no
  polling fallback. Assumes a modern browser with native SSE support
  (true for the single-user localhost target).
- **Directory watch fires on rename.** The push-on-change path assumes
  `fs.watch` on the directory (`server/server.js:46`) emits an event whose
  `filename` equals the basename when the atomic rename lands. The 40 ms
  debounce at `server/server.js:48-49` assumes the create/rename pair arrives
  within that window so it coalesces to one `broadcastState`. Both hold on
  the local OS the single-user tracker runs on; cross-platform fs.watch
  quirks are out of Phase-0 scope.

---

EVIDENCE BLOCK
==============
Task ID: 0.1
Task description: Minimal state writer + minimal localhost GUI proving the file-mediated read/write spine end-to-end (one `branch-opened` event + one snapshot → Node server + one HTML page reads + renders one node; SSE push-on-change). — Verification: full
Verified at: 2026-05-17T18:44:00Z
Verifier: task-verifier agent (third pass — environment blockers from passes 1-2 resolved)

Comprehension-gate: PASS (confidence 8) — orchestrator-mediated comprehension-reviewer dispatch (Task tool unavailable in sub-agents per Anthropic no-nested-subagents; documented orchestrator-mediated path). Stage 1 schema PASS, Stage 2 substance PASS, Stage 3 diff-correspondence PASS. All four canonical sub-sections (`### Spec meaning` / `### Edge cases covered` / `### Edge cases NOT covered` / `### Assumptions`) present, ordered, substantive, task-specific; ~30 file:line citations verified to resolve in 952c9d6; no Assumptions premise contradicted by the diff; heading-depth note resolved in 55b8689. Verifier independently re-confirmed a representative citation sample (state.js:77-79, server.js:45-49, server.js:79-80, app.js:17-20, app.js:44) resolves to the claimed content.

Checks run:
1. Branch state confirmation
   Command: git log --oneline -5
   Output: 55b8689 (heading normalization) / 4d5c08b (comprehension articulation) / 952c9d6 (Phase 0 skeleton) present in order on claude/kind-faraday-c5fe05
   Result: PASS

2. Skeleton byte-identical at branch tip
   Command: git diff 952c9d6 HEAD -- neural-lace/conversation-tree-ui/
   Output: (empty) — skeleton files unchanged since 952c9d6; only the evidence file changed in 4d5c08b/55b8689
   Result: PASS

3. Comprehension articulation schema + substance
   Command: read docs/plans/conversation-tree-ui-v1-evidence.md
   Output: canonical `## Comprehension Articulation` + four ordered `### ` sub-sections, all substantive and task-specific with file:line citations; matches supplied comprehension-reviewer PASS
   Result: PASS

4. Live functional spine — Step 1 (minimal writer)
   Command: node state/state.js seed "Root branch"  (cwd = neural-lace/conversation-tree-ui)
   Output: tree-state.json written with schema_version:1, 1 branch-opened event, derived 1-node snapshot; readState() confirms events=1 nodes=1 schema_version=1
   Result: PASS

5. Live functional spine — Step 2 (localhost server serves page + state)
   Command: CTREE_PORT=8842 node server/server.js & ; curl -s http://127.0.0.1:8842/ ; curl -s http://127.0.0.1:8842/api/state
   Output: server bound 127.0.0.1:8842; GET / returned index.html (<!DOCTYPE html>); GET /api/state returned the 1-node baseline snapshot
   Result: PASS

6. Live functional spine — Step 3 + Integration points (SSE push-on-change over ONE connection, no reload)
   Command: curl -sN http://127.0.0.1:8842/api/events (single connection held open) ; node state/state.js seed "Second branch" mid-stream
   Output: frame 1 = initial-frame-on-connect (1 node "Root branch"); appended 2nd branch-opened while SSE connection stayed open; frame 2 arrived over the SAME connection = 2 nodes ("Root branch","Second branch"). No reconnect, no manual reload. Satisfies Integration points (2-event state → rendered node count = 2). Pin 3b corroborated: state.js:77-79 write-temp-then-renameSync; server survived inode swap (frame 2 delivered post atomic rename) confirming server.js:45-49 directory-watch + 40ms debounce.
   Result: PASS

7. Working tree integrity
   Command: git status --porcelain ; git check-ignore -v neural-lace/conversation-tree-ui/state/tree-state.json
   Output: skeleton + plan + evidence files clean; only unrelated untracked .claude/launch.json present (editor config, not this task, not staged); tree-state.json correctly gitignored so live test left no trace
   Result: PASS

Git evidence:
  Files modified in recent history:
    - neural-lace/conversation-tree-ui/{state/state.js,server/server.js,web/app.js,web/index.html,web/app.css,state/.gitignore}  (952c9d6, Phase 0 skeleton)
    - docs/plans/conversation-tree-ui-v1-evidence.md  (4d5c08b comprehension articulation; 55b8689 heading normalization)

Runtime verification: test neural-lace/conversation-tree-ui/state/state.js::seed-produces-1-node-snapshot — `node state/state.js seed "Root branch"` → tree-state.json with schema_version:1, 1 branch-opened event, 1-node derived snapshot (Step 1, re-executed live this pass)
Runtime verification: curl http://127.0.0.1:8842/api/state — returns the current 1-node snapshot JSON from the file-mediated contract; GET / returns index.html (Step 2, re-executed live this pass)
Runtime verification: curl -sN http://127.0.0.1:8842/api/events — over ONE held-open SSE connection: frame 1 (1 node), then after a mid-stream `node state/state.js seed "Second branch"` append, frame 2 (2 nodes) pushed without reconnect or reload (Step 3 + Integration points, re-executed live this pass; Pin 3b atomic-rename / inode-swap survival corroborated)
Runtime verification: file neural-lace/conversation-tree-ui/state/state.js::fs\.renameSync\(tmp, STATE_FILE\) — atomic single-fs publish primitive (Pin 3b) present at state.js:79

Verdict: PASS
Confidence: 9
Reason: All three "Prove it works" steps + Integration points executed live end-to-end this pass (resolving the prior two passes' environment-only INCOMPLETE); rung-2 comprehension-gate SATISFIED (comprehension-reviewer PASS supplied, citations independently re-spot-checked); skeleton byte-identical at branch tip; working tree clean.
