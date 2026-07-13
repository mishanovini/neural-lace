# Evidence — ask-rooted-workstreams-p1

Per-task completion evidence + comprehension articulations for the rung-4 plan
`docs/plans/ask-rooted-workstreams-p1.md`. Each task's articulation is authored by
its builder (comprehension gate, rung ≥ 2) and graded by `comprehension-reviewer`
before `task-verifier` flips the checkbox.

---

## Task 1 — Walking skeleton (merged: master `a96f5dd`; builder worktree commit `63fa574`)

Substance verified independently (task-verifier, 2026-07-11): all 9 files present and
wired; `progress-log-lib.sh` self-test 10/10; `plan-lifecycle.sh` self-test OK (incl.
scenarios 11–13); `progress-log.sh` 5/5; `ask-registry.sh` stub 7/7; `/api/asks` data
path traced hook→lib→file→API→DOM; render path (`web/asks.js` → `#asksSkeletonBody`)
reads the mechanism-emitted `summary` with no intermediate-shape substitution.

### Comprehension Articulation

#### Spec meaning — what Task 1's spec ("walking skeleton: one event end-to-end") asked for
The spec asked to prove ONE progress event can travel every architectural layer of the
ask-rooted-workstreams system before any breadth is built — the tracer-bullet discipline
that de-risks the integrations the "built-but-not-wired" pattern leaves dangling. A single
task-verifier checkbox flip (`- [ ] N.` → `- [x] N.`) must: be OBSERVED by a splice in the
already-wired `plan-lifecycle.sh` PostToolUse hook (never emitted by model memory, never
flipping the box itself — constraint 6), pass through a `progress-log.sh emit` CLI to
`pl_emit`, land as one deduped JSONL line in a per-ask log under
`~/.claude/state/progress-logs/`, be read back by a new `GET /api/asks`, and render as
"task N verified done" on the landing page. The final versioned event schema (Task 2's
table) is required even in the skeleton so later hardening never forces a format migration.
NOT the full feature — grouping/drift-badges/lifecycle/auto-capture are later tasks.

#### Edge cases covered
- **BASH_SOURCE lazy-resolution bug (found+fixed):** `plan-lifecycle.sh:81` resolves
  `_PL_HOOK_DIR` once at load, before the `--self-test` path's `cd` into a fixture repo;
  the splice at `:290` uses that absolute path. Lazy `BASH_SOURCE[0]` inside the function
  located the CLI against the wrong cwd once any prior `cd` had run (initial scenario-11 FAIL).
- **Fresh-flip vs re-save:** `plan-lifecycle.sh:299` skips task ids already in the pre-edit
  checked set; defense-in-depth `pl_emit` natural-key dedup at `progress-log-lib.sh:281`.
  Self-test scenario 12 asserts unchanged line-count after a no-flip re-save.
- **No `ask-id:` header → unlinked log, never dropped:** `plan-lifecycle.sh:276` extracts
  header ask-id; absent → `pl_path_for` (`progress-log-lib.sh:133`) falls back to `unlinked`.
  Scenario 13 proves the event lands in `unlinked.jsonl` rather than being discarded.
- **Sandbox env parity:** lib (`progress-log-lib.sh:109`), hook self-test
  (`plan-lifecycle.sh:531`), and server (`server.js:172`) all honor `PROGRESS_LOG_STATE_DIR`.
- **Emitter allowlist / provenance:** `progress-log-lib.sh:268` stamps `provenance=unknown`
  for emitters outside `_PL_KNOWN_EMITTERS` (`:103`) — the open CLI cannot impersonate a
  mechanism (constraint 10); lib self-test scenario 5 asserts it.
- **Corrupt/missing JSONL:** `server.js:187` `readJsonlLines` skips unparseable lines;
  `/api/asks` (`:256`) try/catch returns `{ok:false}` — the landing never 500s on one bad record.

#### Edge cases NOT covered
- **No browser-rendered screenshot** — data path proven via `curl /api/asks`; DOM render
  (`asks.js:56`) not exercised in a real browser (no Chrome/puppeteer in build env). Card
  visibility verified structurally, not visually. (Covered later: Task 13 + end-user-advocate.)
- **`ask-registry.sh` is a deliberate Task-1 stub** (`:8`, `:266`): only register/list;
  attach-session/link-plan/set-status/merge/summarizer/mirror/auto-capture are Task 8.
- **Concurrency not stress-tested** — O_APPEND single-line writes (`progress-log-lib.sh:306`)
  but the concurrent-append + full replay-dedup battery is Task 2.
- **Dedup key coverage partial by design** — `_pl_natural_key` (`:189`) implements every
  Task-2 table row but only `task_done`/`task_started` have fixtures here; `plan_amended`/
  `plan_completed` content-hash keys wired, exercised by Tasks 5/6.
- **`/api/asks` payload NOT schema-validated** — no anti-noise/absolute-href enforcement
  yet; that is Task 11.
- **No auditor / drift reconciliation / orphan-lane reattachment** — Task 2/12.

#### Assumptions
- `plan-lifecycle.sh` is PostToolUse Edit|Write-wired (`settings.json.template:321`) and
  receives post-edit plan content read from disk.
- The `pl_emit` CLI signature is a FROZEN contract Tasks 3–6 depend on:
  `emit --type/--ask/--plan-slug/--task-id/--sha/--needs-you-id/--session-id/--summary/
  --evidence-link/--emitter/--dedup-extra`; every schema field implemented now.
- State dir `~/.claude/state/progress-logs/<ask-id>.jsonl` is machine-local, NOT an
  in-repo durable write, so it correctly does NOT route through `nl_main_checkout_root`
  (constraint 11 governs in-repo writes only); server honors `CTREE_PORT` for sandbox.
- `ask-id:` header is a single whitespace-delimited token; `extract_ask_id`
  (`plan-lifecycle.sh:252`) parses exactly that, matching the frozen plan's own header.
- `sha1sum`/`openssl`/`cksum` present for the portable hash; `jq` available; readers
  `tr -d '\r'` defensively given MSYS/CRLF history; repo pins `eol=lf`.
- Additive UI — `app.js` need not know about `asks.js` in this task (it becomes
  shell/router only at Task 13); `asks.js` no-ops if its container is absent (`asks.js:21`).

---

## Task 8 — Ask registry lib (merged: master `bfd6c7a`; builder worktree commit `efcc5e1`)

Substance verified independently (orchestrator re-run: ask-registry.sh `--self-test` 24/24
PASS incl. sandbox-hygiene "wrote only under its own sandboxed tempdir" + the from-worktree
mirror fixture proving `nl_main_checkout_root` resolution). Emit-CLI signature confirmed
unchanged. Carry-forwards: (a) ask-id path sanitization belongs at the `pl_path_for` lib
boundary → routed to Task 2 (owns progress-log-lib.sh); (b) haiku summarizer syntax
HYPOTHESIZED (test-injection seam) → Task 18 acceptance proves it live.

### Comprehension Articulation

#### Spec meaning
Replace the Task 1 stub with the full ask-registry primitive: six verbs
(register/attach-session/link-plan/set-status/merge/override-project) writing
`~/.claude/state/ask-registry.jsonl` with sketch §4 `{user,machine,repo,project}`
provenance, `active|done|dismissed|merged` status vocab drivable by BOTH the auditor
(mechanical exit) and the UI (operator exit), a heuristic-first ≤140-char summarizer with
optional non-blocking `ASK_SUMMARIZER=haiku` (never Fable), verbatim ref, best-effort
in-repo mirror at `docs/asks/ask-registry.jsonl`, sandboxed `--self-test`. Load-bearing
intent: an APPEND-ONLY provenance ledger the server reader (Tasks 11/12) folds into current
state — never a mutable store; every status change is a new record, history never rewritten.
The verbs are dispatch call sites for Tasks 9 (register/attach), 10 (link-plan), 11
(set-status/merge from the lifecycle endpoint), 12 (set-status --emitter auditor).

#### Edge cases covered
- **Status-vocab validation:** `cmd_set_status` rejects values outside `_AR_VALID_STATUSES`
  (line 238; checked line 672 via `_ar_in_list`) — no-op, file byte-unchanged. Scenario G2.
- **Append-only + per-field fold:** all verbs route through `_ar_append_record` (line 514,
  `>>`-only); the `record_type` taxonomy + "last-write-wins per non-empty field, blanks
  never overwrite" fold contract documented lines 126–162 — mutation records deliberately
  blank `repo`/`project`/`summary` so an auditor/UI running from an unrelated cwd never
  clobbers the `created` record's origin values.
- **Project default:** `_ar_resolve_project` (line 482) reverse-matches repo against
  `projects.js loadProjects()` (deepest root wins), falls back to `basename(repo)` when node
  absent/no match (wired line 570). Scenario O asserts the fallback.
- **From-worktree mirror:** `_ar_mirror_path` resolves via `nl_main_checkout_root` (lines
  272–279), never worktree cwd (constraint 11). Scenario L (synthetic repo + linked worktree)
  asserts mirror under MAIN (L1), absent under worktree (L2).
- **Auto-id:** omitting `--ask-id` → `_ar_gen_ask_id` (line 431) → `ask-<YYYYMMDD>-<slug>-<4hex>`;
  slug via `_ar_slugify` (line 419) is path-safe by construction. Scenario B.
- **Summarizer:** `_ar_heuristic_summarize` (line 359) markdown-strips + first-sentence
  (line 364); `_ar_truncate140` (line 338) word-boundary trims. Scenarios C/C2.

#### Edge cases NOT covered
- **merge does NOT auto-absorb `plan_slugs`:** `cmd_merge` (line 684) appends only the source's
  `merged`/`merged_into` record; callers re-`link-plan` if needed. Deferred — plan schema names
  only `merged_into?`, no absorption rule.
- **Haiku syntax HYPOTHESIZED:** `_ar_haiku_summarize` (line 376) uses `claude --model haiku -p`;
  no live call — self-test exercises the async path via `_AR_HAIKU_CMD` seam (Scenarios M/N), so
  "async upgrade appends `summary_updated`, failure degrades silently" is PROVEN but the real flag
  string is HYPOTHESIZED (Task 18 refutes/confirms).
- **ask-id path sanitization DEFERRED with caveat:** within ask-registry.sh there is NO traversal
  surface (registry file + mirror are fixed filenames; `ask_id` is only a JSON value via
  `_ar_json_escape`). BUT register/attach pass caller-supplied `--ask-id` unsanitized into
  `pl_emit --ask` (lines 591, 626), and Task 1's `pl_path_for` composes `<dir>/<ask_id>.jsonl` —
  so a `/`- or `..`-bearing ask-id WOULD traverse in that lib. A shared sanitizer belongs in
  `progress-log-lib.sh` (Task 2), not duplicated here. Flagged for Task 2/9 to close at the lib boundary.

#### Assumptions
- **Emit CLI signature unchanged (constraint honored):** calls `pl_emit` via the stable Task 1
  signature `--type/--ask/--session-id/--summary/--emitter ask-registry` (lines 591, 626), sourcing
  `progress-log-lib.sh`, changing nothing in that CLI; `ask-registry` already in `_PL_KNOWN_EMITTERS`.
- **`projects.js loadProjects()` returns `{key: absoluteRoot}`**, config path via `nl_workstreams_ui`;
  verified live (keys neural-lace/workstreams-coordination). Read-only, never edits projects.js.
- **Reader-fold contract is the Tasks 11/12 interface:** iterate all records per ask_id in ts order,
  last-write-wins-per-non-empty-field (lines 141–162); writer blanks non-identity fields on mutation
  records to make that fold correct. Naive whole-record last-wins would null origin fields — this task
  pins that contract.
- **Tool/platform:** assumes git/hostname/date -u, flat-JSON via shell string ops (no jq on write
  path), node for project resolution (graceful basename fallback), Git-Bash drive-letter repo paths
  marshalled via the `TARGET`/`PROJJS` env-var seam (not argv) to sidestep MSYS path mangling.

---

## Task 2 — Progress-log format finalization + writer hardening (merged: master TBD; builder commits `2ddd720`+`83a27db`)

Substance verified independently (orchestrator re-run: progress-log-lib 16/16 incl. sanitizer
scenarios 1c/1d + concurrent-append + CRLF + schema-parity; progress-log.sh 6/6; ask-registry
7/7 no-regression). Emit CLI signature UNCHANGED. Orchestrator addition folded in by the
builder's own hand: the ask-id path-traversal sanitizer at the `pl_path_for` shared boundary
(protects all emitters). Known P1 limitation (documented, not blocking): `task_done`'s sha
discriminator is empty because the plan-lifecycle flip fires BEFORE the commit exists — the
re-verify-after-revert distinction is a P2/auditor-reconciliation refinement.

### Comprehension Articulation

#### Spec meaning
Task 2 finalizes the versioned JSONL event format Task 1's skeleton already implemented
end-to-end and hardens the WRITER around it — it does not re-author the format. Binds: (a) the
versioned schema + per-event-type natural-key dedup table (plan 235-246) whose central rule is
that a single hash formula must never be used — each type keys on the discriminators separating
legitimate recurrence from replay (`task_started`+session_id; `plan_completed`+Status-line-ts
content-hash per the round-2 superset fix); (b) the emitter allowlist (constraint 10) — unknown
emitters recorded but `provenance:unknown`; (c) atomic single-line O_APPEND + orphan lane +
`--self-test` battery (concurrent-append/replay-dedup/legitimate-recurrence/unknown-emitter/
CRLF), all HARNESS_SELFTEST-sandboxed; (d) machine-checked schemas/progress-log-event.schema.json.
Load-bearing interface constraint: the `emit` CLI shape is a STABLE contract four splice builders
write against — harden internals only, never rename/break. The table + allowlist were already in
Task 1 (`_pl_natural_key` lib:272; `_PL_KNOWN_EMITTERS` lib:140), so the delta is the schema file,
writer hardening, the sanitizer, and expanded self-tests.

#### Edge cases covered
- **Splice/auditor double-append race:** `_pl_acquire_lock`/`_pl_release_lock` (lib:306/327)
  wrap the dedup-check+append critical section in a `mkdir`-based mutex (atomic on NTFS via Git
  Bash, no flock needed), bounded ~150ms spin then proceed unlocked (constraint 5 — never hang).
  Proven by Scenario 8 (lib:640, 6 racing procs → 1 line) + progress-log.sh Scenario E (5 racing
  OS procs → 1 line) + Scenario 7 (10 distinct-key concurrent → 10 intact lines).
- **`trap RETURN` scoping bug (fixed):** first release design used a RETURN trap; bash's RETURN
  trap once set in a called function re-fires on the CALLER's later return, dereferencing torn-down
  `local path` under `set -u` (broke ask-registry --self-test). Fixed with explicit
  `_pl_release_lock` at each of pl_emit's three post-lock exits (lib:412-444), no trap.
- **Schema field-parity drift:** Scenario 10 (lib:695) asserts emitted event fields exactly match
  the schema's `additionalProperties:false` allowlist (schema:12) — a new writer field without a
  schema update is a self-test failure, not silent drift.
- **CRLF byte-safety:** Scenario 9 (lib:673) emits raw CR/LF/tab and asserts via `od -tx1` hex
  (not MSYS-maskable grep/cat) zero 0x0d bytes reach the file; escaped to literals, not dropped.
- **ask-id path-traversal sanitizer (orchestrator addition, builder-authored):**
  `_pl_sanitize_ask_id` (lib:189) allowlist-normalizes chars outside `[A-Za-z0-9._-]` (incl. `/`
  `\`) to `_` and collapses `..` runs (lib:196), so `pl_path_for` (lib:214) always composes a
  single component under `pl_state_dir`. Scenario 1c (lib:486): 7 traversal vectors keep resolved
  parent == pl_state_dir; 1d (lib:506): legit id unchanged, real traversal emit writes inside the
  state dir, no `evil.jsonl` escapes. Degenerate results → `sanitized-<hash>` (distinct bad ids
  never merge); empty ask-id keeps `unlinked` fallback.

#### Edge cases NOT covered
- **`task_done` sha discriminator not yet supplied by the splice:** natural key is
  `plan_slug+task_id+sha`, but Task 1's plan-lifecycle.sh emits without `--sha` (the flip fires on
  the Edit PostToolUse, BEFORE any commit sha exists), so every task_done dedups on empty sha —
  the re-verify-after-revert=new-event recurrence does NOT fire today. Honest, out of Task 2's file
  ownership; the lib keys on sha the moment the splice supplies it. Orchestrator disposition: P1
  documented limitation (the auditor can reconcile; rare edge), not a blocking fix.
- **Lock fairness/starvation:** the ~150ms spin can, under pathological sustained contention, time
  out and proceed unlocked, reintroducing a duplicate-line possibility for that one emit —
  deliberate constraint-5 tradeoff (never block the host hook), documented, but the
  timeout-then-proceed path is not itself forced by a test.
- **`_pl_hash` cksum-fallback collision space:** the sha1sum→openssl→cksum chain's cksum last-resort
  has a weak collision space; no distinct-input→distinct-hash test on that path (portability
  last-resort, unlikely on target).

#### Assumptions
- **`mkdir` is atomic create-if-absent** on every target FS (NTFS via Git Bash + POSIX tmpfs in
  self-tests) — the mutex primitive basis (no reliable flock/lockfile on Windows). Verified
  behaviorally by the race scenarios, not a FS-level atomicity proof.
- **`ask_id` is a controlled registry-generated id (Task 8)** so the sanitizer is defense-in-depth;
  the sanitizer normalizes only the FILE PATH, leaving the stored `ask_id` JSON field as the raw
  caller value — if a future consumer (Task 11 reader) keys grouping on the field not the filename,
  that field is unsanitized by design (one-line follow-up if that assumption breaks).
- **`od -tx1` reflects true on-disk bytes** (not MSYS-filtered) per repo CRLF doctrine.
- **exit-124 timeouts are environmental** (~19s machine-wide bash-spawn latency), not code hangs —
  supported by the full 16-green run at lower latency + isolated fast checks of scenarios 9/10.

---

## Task 3 — Dispatch emission splice + provenance marker (merged: master TBD; builder commit `a25e9d9`)

Substance verified: builder directly invoked the REAL hook (not just self-test) proving all 5
new behaviors (task_started emit w/ plan_slug+task_id+ask_id+emitter; replay-dedup; plan-less
no-op; --on-spawn cwd-hint; missing-CLI rc=0 isolation). dispatch-provenance.sh 10/10;
progress-log.sh 6/6 (no regression). Full workstreams-emit suite couldn't finish under
contention (killed at ST25, all PASS) — orchestrator background re-run confirms the standalone
suites. emit CLI unchanged. Marker format for Task 9: `~/.claude/state/dispatch-provenance/
<sanitized-worktree-or-UNRESOLVED>__<ts>.json` = {v,ts,ask_id,plan_slug,task_id,session_id,
child_id,worktree_path}. worktree_path="" for generic Task/Agent/Workflow (path unavailable
at PreToolUse — only spawn_task supplies a cwd hint); honest gap, documented.

### Comprehension Articulation

#### Spec meaning
Task 3 (plan 258-271) bundles two things as one splice: (a) a `task_started` progress-log event
from `--on-builder-dispatch`/`--on-spawn` carrying plan slug + task id + child session
provenance via the finalized `progress-log.sh emit` CLI; (b) a dispatch-provenance marker under
`~/.claude/state/dispatch-provenance/` pre-attaching a spawned child to the dispatching ask
(no such marker existed — verified against spawn-worktree.sh/nl.sh). Implemented as
`_emit_dispatch_provenance()` (workstreams-emit.sh:2452), called from `_run_on_builder_dispatch`
(:2523) and `_run_on_spawn` (:666), marker written by a new dedicated CLI
scripts/dispatch-provenance.sh (script+lib split mirroring Task 2's convention).

#### Edge cases covered
- Plan-less dispatch (Explore/research, no docs/plans/*.md ref) → silent no-op (PL3 scenario
  workstreams-emit.sh:1831-1841; implementing guard `[[ -z "$slug" ]] && return 0` at :2456)
  — prevents anti-noise orphan-lane flooding. [citation corrected per comprehension re-review]
- Replay of identical dispatch → pl_emit natural-key dedup (plan_slug+task_id+session_id) holds
  through the splice (:1808-1814, PL1b).
- Missing progress-log.sh/dispatch-provenance.sh CLIs → `[[ -f ]]` guards + `|| true` keep rc=0
  (PL5 scenario :1859-1866).
- Pre-existing plans lacking an `ask-id:` header → `_resolve_ask_id_for_plan_slug` (:2412-2427)
  returns empty, pl_emit's orphan lane (unlinked.jsonl) absorbs it — same as Task 1, no new mode.
- `--on-spawn` with explicit tool_input.cwd hint → marker worktree_path populated (PL4 scenario :1843-1856).

#### Edge cases NOT covered
- True child worktree path for generic Task|Agent|Workflow is fundamentally unavailable at
  PreToolUse (the SDK creates the worktree DURING tool execution, returning the path only in the
  PostToolUse result) — marker honestly records worktree_path:"" (dispatch-provenance.sh header +
  :2350-2367); no invented workaround convention.
- Multi-plan-reference dispatch text takes only the first docs/plans/*.md match — not distinct.
- Task-id extraction is best-effort regex ("Task N of" preferred, bare "Task N" fallback) — can
  mis-extract on unconventional phrasing; inherent to parsing free-text prompts, out of scope for
  a one-line best-effort splice.

#### Assumptions
- "The same provenance the SESSIONS lineage rendering consumes" (plan 262) = reuse the existing
  sid/child_id values `_builder_classify`/`_run_on_spawn` already compute (dispatching-session-
  derived synthetic ids), not a newly-invented child-session concept — no true child session id
  exists at PreToolUse for either surface.
- Resolving ask_id by reading the plan file's `ask-id:` header directly (mirroring Task 1's
  extract_ask_id) is preferable to adding a reverse-lookup verb to ask-registry.sh (out of file
  ownership; the header-read is the already-reviewed established convention).

---

## Task 4 — NEEDS-YOU emission splice + operator-todo pointer (merged: master TBD; builder commit ce8a961)

Substance verified: needs-you.sh --self-test 41/41 PASS (T1-T30 incl. new T26-T30), focused
Task-4 re-run 9/9 incl. the constraint-11 from-worktree fixture T30 (T30a pointer under MAIN
checkout; T30b absent from worktree). emit CLI unchanged; durable write via nl_main_checkout_root.

### Comprehension Articulation

#### Spec meaning
Task 4 (plan 272-282): a best-effort never-blocking splice in needs-you.sh's `add` path that (a)
emits ONE `waiting_on_operator` progress-log event through the STABLE progress-log.sh emit CLI
(needs-you.sh:625-628: `--type waiting_on_operator --needs-you-id --session-id --summary
--emitter needs-you`), carrying needs-you id/section/tier/session-id + the cold-reader lint result
as a §3-context-present flag; and (b) appends an AUTO-pointer to docs/operator-todo.md in a
marker-delimited section, operator-authored section untouched, path via nl_main_checkout_root
(constraint 11). Intent: the pointer IS "the same mechanism that appends to NEEDS-YOU.md" —
fires where the ledger append already happens (cmd_add), never model memory. Resolution/auto-check
NOT emitted here — derived by the Task 12 auditor so a pointer survives resolutions bypassing the script.

#### Edge cases covered
- Section scoping (needs-you.sh:602 `case decision|question`): only decision/question fire; inflight/
  decided don't (would recreate O.4 noise). T27a/T27b + existing T5.
- §3-context-present flag honesty (:604-611): reuses cmd_add's lint_warnings; `present` on zero
  warnings else `missing(<csv>)`, `n/a` for questions. T26b/T26d/T29.
- AUTO-append insert-before-END, append-only (_ny_operator_todo_append_pointer :355-388): read/printf
  loop inserts before `<!-- AUTO:END -->`, never rewrites; plain loop (not awk -v) so backslash
  titles aren't misread. T28b (two distinct bullets), T28a (operator line above markers survives).
- Constraint-11 durable write (_ny_operator_todo_path :287-308): nl_main_checkout_root (same as
  _ny_md_path), never worktree cwd. From-worktree fixture T30 (:1466-1516): real linked worktree,
  add fires from inside w/ OPERATOR_TODO_PATH="" → pointer under MAIN (T30a), absent from worktree (T30b).
- Never-blocks (constraint 5): both writes in `( ... || true )`; CLI only if file exists (:624). T29
  proves add exits 0 when operator-todo path unwritable.
- First-use file creation (_ny_operator_todo_ensure :321-345): seeds only if absent; never re-templates.

#### Edge cases NOT covered
- No `--ask` on the event (:626-627): needs-you.sh has no ask-id in scope → event lands in `unlinked`
  orphan lane by design; attaching to the right ask is the Task 12 auditor's job. Fixtures assert unlinked.jsonl.
- Pointer resolution/auto-check not implemented here — out of scope; operator-todo.md is append-only,
  resolved ledger item does NOT remove/check its pointer (file header documents). Auditor Task 12.
- Malformed operator-todo.md missing a marker: _ny_operator_todo_append_pointer (:360-361) bails
  silently (return 0) rather than repairing — best-effort, left for human/auditor.
- No dedup fixture for replayed waiting_on_operator — key is needs_you_id alone (Task 2 proven), each
  add mints a fresh id so real replay can't occur; relied on Task 2's dedup coverage.
- Concurrent appends to operator-todo.md not stress-tested (add is single-session-serial in practice).

#### Assumptions
- progress-log.sh emit CLI is a frozen contract — call only --type/--needs-you-id/--session-id/
  --summary/--emitter, change nothing; `needs-you` already in _PL_KNOWN_EMITTERS (provenance:known).
- Frozen v1 schema has no section/tier/context-flag column (additionalProperties:false) → fold them
  into the human-readable summary string (Task 1's technique), not a new field (Task 2 owns schema).
- nl_main_checkout_root (hooks/lib/nl-paths.sh) already sourced by needs-you.sh (:162-165); my
  _ny_operator_todo_path mirrors _ny_md_path's fallback chain (nl_main_checkout_root → git
  rev-parse --show-toplevel → $PWD), total.
- Sandboxing (constraint 4): self-test unsets HARNESS_SELFTEST + drives env overrides
  (PROGRESS_LOG_STATE_DIR + OPERATOR_TODO_PATH :1004-1005); T30 clears OPERATOR_TODO_PATH to
  exercise the real resolver.

---

## Task 5 — Master-merge emission (merged: master 9ba85c2; builder commit 6deab2d)

Substance: merge-scan-lib.sh --self-test 12/0 (attribution + emission + idempotency + multi-match
+ sandbox). emit CLI unchanged (called as OS subprocess, never sourced). Files: merge-scan-lib.sh
(NEW ~480), git-hooks/post-commit (+19), doctrine/git.md (+1 plan:token). Task 12 consumes
`ms_scan_repo_for_merges <repo-root> [--since <ref>] [--limit <n>] [--emitter <name>]`
(merge-scan-lib.sh:281, guaranteed lane) + `ms_emit_merged_for_commit <root> <sha> [--emitter]` (:239).

### Comprehension Articulation

#### Spec meaning
Two mechanical lanes emitting `merged` events. Lane (a): best-effort splice in git-hooks/post-commit
(step 3, :41-59) firing only when the local commit landed on main (`_ms_is_master_branch` :319),
emitting for HEAD via ms_emit_merged_for_commit. Lane (b): GUARANTEED lane ms_scan_repo_for_merges
(:281) that Task 12's auditor consumes — derives merged events w/ SHA by walking git log origin/master
(remote squash-merges via gh pr merge never fire local hooks; plan D2). SHA→ask attribution:
sha→plan-slug→plan-header ask-id:→per-ask JSONL. Slug from a `plan: <slug>` commit-body trailer
(_ms_plan_token_slugs :139; convention at doctrine/git.md:13) else diff touching docs/plans/<slug>.md
(_ms_plan_slugs_from_diff :152); ask-id reads the header (_ms_resolve_ask_id :201). Constraint 6:
OBSERVES merges, never flips a checkbox.

#### Edge cases covered
- Multi-match tie-break (review round 2): commit touching >1 plan emits one merged event PER matched
  ask, never a guessed winner (_ms_commit_plan_slugs :183 returns all deduped; the per-slug emit
  loop in ms_emit_merged_for_commit :259-265; Scenario 3). [citations corrected per re-review]
- No-resolvable-slug → SKIP (`[[ -z "$slugs" ]] && return 0` :256; Scenario 4) so non-plan commits
  never flood the orphan lane.
- Matched plan lacking ask-id: (pre-Task-10 plans) still emits w/ empty --ask → unlinked.jsonl orphan
  lane, never dropped (Scenario 5).
- Idempotency: re-emit same SHA is a no-op via merged's repo+sha natural key (Scenarios 6+8); two
  slugs → same ask-id collapse to one line free.
- Ask-id resolution tries archived path + `git show <sha>:docs/plans/<slug>.md` for moved/vanished
  plans (:210-224). All writes sandboxed (Scenario 10).

#### Edge cases NOT covered
- diff-fallback lists changed files via `git diff-tree --no-commit-id --name-only -r --root` (:155)
  which, on a true two-parent LOCAL merge commit (default mode, no -m/-c/--cc), surfaces NO changed
  files AT ALL — so the diff-fallback attributes NOTHING for such a commit (a total miss, not partial;
  empirically confirmed by the re-reviewer). Only the `plan:` token path can still catch such a commit.
  Guaranteed remote-squash lane (single-parent commits via gh pr merge) UNAFFECTED. Only local merge
  commits (the additive post-commit lane) are affected. [wording corrected per re-review]
- Auditor's iteration over config/projects.js roots + --since incremental bookkeeping = Task 12's
  (this lib is one-repo-per-call by design).
- Malformed `plan:` slug w/ chars outside [A-Za-z0-9_.-] fails the token regex → falls to diff path
  (not separately asserted).
- post-commit splice's LIVE end-to-end (real master commit → live event) NOT exercised — hook not
  installed on this branch; verification is self-test + syntax (runtime-of-hook not exercised).

#### Assumptions
- origin/master is the correct remote-tracking ref (:294; plan D2). Main branch = `master`
  (_ms_is_master_branch default + MS_MASTER_BRANCH override :320-321; must change if estate renames).
- progress-log.sh emit contract stable (Task 2) — called as OS subprocess, never sourced, so
  natural-key dedup (repo+sha for merged), orphan-lane, never-blocks are inherited.
- `plan:` trailer (Co-Authored-By: shape) is the go-forward convention (doctrine/git.md:13);
  pre-existing commits rely wholly on the diff fallback.
- Task 12 enumerates projects.js roots + passes each as <repo-root> (lib deliberately repo-scoped-
  per-call). Emitting from `cd "$repo_root"` (:262) gives pl_emit the correct repo field.

---

## Task 6 — Plan-amendment + plan-completion splices (merged: master TBD; builder commit aae9507)

Substance: plan-lifecycle.sh --self-test 19/19 OK (incl. 6 new scenarios; 14m under contention);
close-plan.sh new behavior proven by direct real-invocation (standalone close → plan_completed w/
correct slug/ask_id/emitter) + dedup test (same close-ts → 1 line; distinct → 2). Task 1's task_done
splice UNTOUCHED. emit CLI unchanged. Files: plan-lifecycle.sh +164, close-plan.sh +201/-3.

### Comprehension Articulation

#### Spec meaning
Task 6 (plan 305-316) is one task hosting two splices sharing the writer-family review: (a)
plan-lifecycle.sh detects newly-introduced task lines / scope-section edits on ACTIVE plans and emits
plan_amended, reusing plan-edit-validator.sh's new-task-line parse principle; (b) close-plan.sh's
successful-close path emits plan_completed (the 6th lane), reached via BOTH the wired
plan-auto-closure.sh hook AND manual closes, deduped by plan_slug + content-hash of the Status-line ts
(Task 2 table). Implemented (a) as emit_plan_amended_progress_log_events (plan-lifecycle.sh:395) invoked
at :529; (b) as emit_plan_completed_progress_log_event (close-plan.sh:146) invoked ONCE at the single
close call site both lanes share (cmd_close). Constraint 6: OBSERVES, never flips a checkbox.

#### Edge cases covered
- Fresh plan creation (pre="") guarded out of amendment detection (plan-lifecycle.sh:401
  `[ -n "$pre" ] || return 0`) so a new plan's initial tasks don't burst false amendments (Scenario 19).
- Non-ACTIVE plans excluded (:406-408, matches "on ACTIVE plans") (Scenario 18).
- close_ts dedup (close-plan.sh:157/1209) proven direct: same close_ts → 1 line; later distinct close_ts
  → distinct 2nd line (DIRECT-DEDUP-TEST PASS).
- Both live task-ID conventions matched: plain-numeric "1." + lettered "A.1"/"F.2b" via
  extract_all_task_line_ids combined regex (:349-354), verified against real docs/plans/*.md.

#### Edge cases NOT covered
- Task-line REMOVAL not detected as amendment — only additions ("newly-introduced task lines"); a plan
  deleting tasks produces no plan_amended event.
- Full 21-scenario close-plan.sh self-test NOT run synchronously (prohibitive subprocess-spawn latency —
  each scenario spawns a full close-plan.sh); the new behavior is proven directly via the real close →
  plan_completed invocation + the dedup test, and the 19 pre-existing scenarios are shielded from Task
  6's change by the best-effort `>/dev/null 2>&1 || true` splice wrapper (constraint 5). [Verification:
  mechanical; justification corrected per re-review — no plan-level "fallback authorization" clause exists.]
- A multi-CHARACTER trailing letter within ONE segment (e.g. "F.2bc") captures only "F.2b" because the
  regex's `[A-Za-z]?` is single-char. NOTE the multi-SEGMENT form "F.2.3b" IS fully captured (the
  repeatable group `(\.[0-9]+[A-Za-z]?)*` carries a per-segment trailing-letter clause — re-reviewer
  ran the committed regex; matched "[F.2.3b]"). Neither form exists in any live plan. [corrected per
  re-review: the original bullet wrongly claimed F.2.3b was uncaptured — a model-vs-code inversion; the
  shipped regex is MORE capable than the builder described, error was in the safe (over-declaring) direction.]

#### Assumptions
- "content-hash of the Status-line ts" (plan 241-242 + schema) requires the CALLER to pre-hash before
  --dedup-extra → added compute_content_hash/cp_compute_content_hash mirroring progress-log-lib's
  _pl_hash (equivalent dedup either way, but matches the literal schema wording).
- plan-edit-validator.sh's check_docs_impact_warn only sees an Edit fragment (old/new_string), never full
  pre/post → interpreted "reuse the existing new-task-line parse" as reusing its PRINCIPLE
  (new-id-not-in-prior-content) generalized to a full-content SET diff (documented at :317-330), not a
  verbatim fragment-scoped copy (which would under-detect this plan's own plain-numeric IDs).

---

## Task 11 — Server read surface (merged: master TBD; builder commit 281afb9)

Substance: server.selftest.js 77/77 PASS in the BUILDER's worktree (re-run by orchestrator;
byte-identical to the cherry-pick), incl. both required negative fixtures (S27a gate-identifier
field→FAIL, S27c relative-href→FAIL) + S23-S26 (landing groups/progress/waiting, completed
group + status filter, detail narrative/plan_rows/§3-block/defect-form-never-bare-ID/absolute
raw_link/lineage/404, real ask-registry.sh lifecycle round-trip). Existing S1-S22 green (no
regression). NOTE: server.selftest.js ECONNRESETs at S23 in the ORCHESTRATOR's integration
worktree (environmental — passes in builder's worktree; revisit at acceptance). Files:
payload-schema.js (new 198), server.js +717/-50, server.selftest.js +308, README +56.
Follow-ups: (a) ask-registry.sh merge has no --emitter → UI merge stamped emitter=ask-registry
not operator-ui (Task 8 follow-up); (b) drift_badges ships [] until Task 12 auditor lands (field
present now, no later migration).

### Comprehension Articulation

#### Spec meaning
Task 11 is the read/lifecycle surface between the mechanism-emitted data layer (Tasks 1-8) and
the UI (Task 13): turn append-only ask-registry.jsonl + per-ask progress-logs + rendered
NEEDS-YOU.md + dispatch-provenance markers + heartbeats into two schema-validated payloads plus
one operator-override write. Load-bearing phrases implemented literally: "DEFAULTS to status:active"
(buildAsksLandingPayload's `filter = statusFilter || 'active'`, completed asks always folded into a
separate completed group regardless of filter); "the form is never terminal" (buildWaitingItems
always emits `{defect,message,raw_link,session_id}` — never a bare id — on missing/failed §3
context); "an ALLOWLIST of fields" (payload-schema.js walk errors on any key not in
LANDING_ALLOWED_KEYS/DETAIL_ALLOWED_KEYS); "no new link handling" (projectDocRefFor returns a
plan_doc {project,path} for the existing /api/doc resolver, the one absolute-href exemption).

#### Edge cases covered
- Thin/missing/unresolvable §3 context → buildWaitingItems routes all three to the defect form
  (hasGenuineContext mirrors needs-you.sh's `_ny_lint_decision_text` no-context heuristic);
  S25f/S25g prove bad-but-present + entirely-unresolvable both render defect forms, never bare ids.
- NEEDS-YOU.md unreadable → readNeedsYouDecisionsResult returns {available:false}; computeWaitingCount
  counts every referencing event so a parse gap never hides a real waiting item.
- In-flight derivation (constraint 2 law 4) → computePlanRows marks in_flight only when
  `!t.done && startedSet[t.id] && !doneMap[t.id]`; S25c asserts task 2 in_flight, task 3 not.
- Corrupt/missing files → readJsonlLines skips unparseable; readDispatchProvenanceMarkers try/catches
  per-file; countPlanTasks returns null on missing plan file — landing never 500s on one bad record.
- Anti-noise vs the required NEEDS-YOU.md link → dropped the bare `needs-you` denylist token so the
  mandated absolute ledger link passes while `/\.sh\b/` still denies the actual script name; S27a
  still proves a real gate identifier FAILs.

#### Edge cases NOT covered
- Live heartbeat classification best-effort → classifySessions resolves empty (all→missing) on spawn
  failure/timeout; a slow-but-alive session could read missing. Off the landing path (only
  /api/ask/<id>); Task 12 auditor is the continuous reconciler.
- plan_progress is a read-time snapshot, not continuously reconciled → aggregatePlanProgress reflects
  plan file + events at request time; a checkbox flipped without a task_done event (log-behind-truth)
  isn't drift-badged here — Task 12's divergence-class job (drift_badges ships []).
- Multi-repo plan resolution → resolvePlanAbsPath tries the ask's repo then this repo root only; a plan
  in a third project root resolves to no plan file (honest empty row, never crash), not a full sweep.
- Merge emitter attribution → lifecycleArgsFor's merge branch can't pass --emitter (Task 8's merge
  verb doesn't accept it) — surfaced as a follow-up.

#### Assumptions
- Registry fold contract → foldAskRegistry implements "last-write-wins per non-empty field, ts order"
  plus accumulated plan_slugs[] from plan_linked records (a list per the MULTI-PLAN CARDS round-2
  decision). Assumes the header fold contract is authoritative.
- NEEDS-YOU.md rendered shape is the contract → parseDecisionBlocks/DECISION_META_RE parse exactly what
  _ny_render_decision_block emits; the self-test pins this against the REAL needs-you.sh add, not a
  hand sample.
- projects.selfRepoRoot() is the correct main-repo anchor → mainRepoRoot/needsYouMdPath reuse it (the
  worktree-pool-aware resolver projects.js already trusts), not git rev-parse from a worktree cwd.
- bashBin()+`-lc` is the right spawn idiom → classifySessions/runAskRegistryCli reuse derive-cache.js's
  bashBin/spawnEnv (absolute bash + login shell, inheriting the 2026-07-09 lobotomy lessons); 180s
  timeouts assume the machine's measured worst-case spawn latency.

---

## Task 9 — Automatic ask-capture splices (merged: master TBD; builder commit 5e240cb)

Substance: progress-log-lib.sh 29/29 (8 new classify scenarios), workstreams-read.sh 45/45
(AC1 first-prompt registers via real ask-registry.sh; AC2 second no re-register; AC3
spawned-worktree cwd never registers; AC4 derived ask_id consistent guard↔register),
session-start-digest _ask_session_attach direct e2e 8/8. Classification fn (Task 17c consumes):
`pl_classify_session` (+ `pl_ask_id_for_session`). ZERO new settings entries; both splices
subshelled + `|| true`. RECOVERY NOTE: reboot had left _ask_session_attach DEFINED but UN-WIRED
(built-but-not-wired) — builder added the run_digest call site + fixed a $PWD-vs-JSON-.cwd
classification bug.

### Comprehension Articulation

#### Spec meaning
Task 9 makes ask-capture fully automatic, zero ceremony, zero new settings entries. Splice (a):
first operator prompt registers the ask — spliced into the wired UserPromptSubmit hook `_run_read`,
calling `_ask_capture_on_prompt` → `ask-registry.sh register`, first-prompt-guarded by a per-session
marker (`[[ -f "$marker" ]] && return 0`). Splice (b): resume/spawn attaches — `_ask_session_attach`
in `run_digest` → `ask-registry.sh attach-session`. Load-bearing review-round-1 requirement: the
builder-session guard (spawned sessions must NOT register). Its mechanical predicate is
`pl_classify_session` (spawned/operator) testing `*/.claude/worktrees/*` on cwd OR a Task-3
dispatch-provenance marker whose worktree_path matches — placed in progress-log-lib.sh so Task 17(c)'s
doctor filters the SAME population (parity by construction).

#### Edge cases covered
- Second+ prompts short-circuit on the marker (`_ask_capture_on_prompt` `[[ -f "$marker" ]]`).
- Resume duplicate prevented by `pl_ask_id_for_session` re-deriving the identical `ask-auto-<hash>` from
  the stable session_id (no file lookup, no race).
- Spawned classification handles Windows backslash + forward-slash cwd (`norm="${cwd//\//}"`); matches
  a marker's worktree_path exactly OR as path-ancestor (`"$norm" == "$wt"/*`).
- UNRESOLVED marker (empty worktree_path, the honest PreToolUse gap) never false-matches
  (`[[ -z "$wt" ]] && continue`).
- No resolvable prompt text → honest marker `skipped=no-prompt-text`, never a fabricated ask.
- `_ask_session_attach` attaches only on resume/compact, never fresh startup; spawned session w/ no
  resolvable marker returns without fabricating.
- FIXED bug: `_ask_capture_on_prompt` classified by $PWD → hook from within a worktree self-mislabeled;
  now uses `_ask_capture_cwd` reading JSON .cwd (matching `_ask_session_attach`).

#### Edge cases NOT covered
- Cross-machine / multi-machine resume chains out of scope (P3). `pl_ask_id_for_session` assumes a
  machine-local stable session_id.
- If Claude Code ever changes session_id across --resume (assumption below), resume attach derives a
  different id → lands on a fresh node not the original; no observable SessionStart-JSON signal to detect.
- Haiku summarizer async path (ASK_SUMMARIZER=haiku) exercised by Task 8's self-test, not re-tested here.
- Manifest/runbook doc updates (Task 9 "Docs impact") = orchestrator follow-on per Task 7 convention.

#### Assumptions
- UserPromptSubmit stdin JSON carries prompt under `.prompt` — VERIFIED vs live sibling hook
  decision-context-reply-emit.sh (`.prompt // .user_prompt // .message // empty`); mirrored, not guessed.
- SessionStart JSON carries `.source` (startup/resume/compact) + `.cwd` — VERIFIED vs workstreams-emit.sh
  `_run_on_session_start`.
- Claude Code keeps session_id stable across --resume — assumed from the harness resume model
  (session-heartbeat/session-resumer treat it stable); refuted if a resumed session presents a new id.
- `DISPATCH_PROVENANCE_STATE_DIR` resolution in `_pl_dispatch_provenance_dir` byte-identical to
  dispatch-provenance.sh's `_dp_state_dir` — asserted by progress-log-lib Scenario 15.

---

## Task 13 — UI landing, ask tree (merged: master TBD; builder commit 6c29fd0)

Substance: web/cockpit.selftest.js 68/68 PASS (re-run by orchestrator). Builder verified
end-to-end via curl + LIVE Claude_Browser MCP against a sandboxed server (port 18844/18845,
never :7733) — real browser render confirmed. Files: web/asks.js (rewrite), web/app.css,
web/app.js, index.html, README (IA section). Note: builder reproduced the S23 ECONNRESET on
CLEAN origin/master HEAD → the earlier "environmental" assessment is REVISED (real pre-existing
Task 11/12 test issue; task_e41fc644 fixing in parallel).

### Comprehension Articulation

#### Spec meaning
Task 13 builds the first operator-facing surface — web/asks.js renders project sections → ask
cards (shallow: narrative_excerpt, plan_progress, waiting_count, drift_badges) with a lazy per-ask
drill-down (`getAskDetail`/`renderDrilldownBody`) that fetches Task 11's GET /api/ask/<id> only on
first <details> expand ("shallow-first with plan drill-down"). Lifecycle affordances
(`renderLifecycleRow`, `postLifecycle`) call POST /api/ask/<id>/lifecycle — the operator-override
exit (constraint 7) with success feedback + an 8s undo (`UNDO_WINDOW_MS`) before the card moves to
the collapsed completed group (`renderCompletedGroup`). MULTI-PLAN CARDS render one aggregate bar
(server-summed plan_progress) plus, in drill-down, one `renderPlanBlock` per plan_slug with its own
live-doc link (`openPlanDocModal`, reusing the shared docModal).

#### Edge cases covered
- No-plan card (`renderProgressArea` `!pp.total` → "no plan linked yet", no bar/control).
- Drill-down-no-tasks per plan (`renderPlanBlock` `!row.tasks.length`) — distinct from the no-plan
  card since it can occur on one plan of a multi-plan ask while a sibling has real rows.
- Empty completed group (`renderCompletedGroup` returns null → hidden entirely).
- §3-defect waiting item vs a real decision block (`renderWaitingItem` `item.defect` branch — both
  verified live vs real needs-you.sh fixtures).
- Session lineage vs flat (`renderSessionsList` `childrenOf`/`isChild`/`seen` cycle guard — never a lost session).
- Non-absolute reference values never becoming a relative <a href> (`absoluteLinkNode`).

#### Edge cases NOT covered
- Fetch-failure/Retry state (`renderError`) implemented + self-test-locked (T13-20) but NOT fired live
  — killing the server routed the tab to a Chrome error page instead of the in-page .catch(); flagged
  not assumed.
- `renderDriftBadges` is generic/defensive since Task 12 hasn't defined the real badge shape yet.
- Concurrent lifecycle writes across two tabs not reconciled vs the client's optimistic undo window.
- The `claude://` deep-link's actual resume grammar deliberately never fired live (copy-button fallback
  shipped; deep-link PROVEN registered in HKEY_CLASSES_ROOT\claude but resume grammar HYPOTHESIZED).

#### Assumptions
- `plan_progress.total === 0` treated uniformly as "no plan linked yet" at card level (payload can't
  distinguish linked-but-unresolvable; drill-down surfaces the honest per-plan empty separately).
- Completed cards show only "Reopen" (Done/Dismiss/Merge meaningless on a terminal ask) — follows from
  Task 8's status vocabulary.
- Session-lineage rendering assumes resumed_from only points within the same ask's session set (per
  buildSessions in server.js).
- `app.js` "becomes shell/router" is Task 16's job — Task 13 adds only a doc note (no functional coupling
  beyond the shared docModal).

## Task 12 — Background auditor + drift badges (merged: master TBD; builder branch `build/askp1-t12`)

Substance: new `server/auditor.js` (1146 lines) implementing all seven divergence-class rows +
the §8-3 count reconciliation; `node server/auditor.js --self-test` 18/18 PASS, including REAL
(non-mocked) end-to-end runs against `progress-log.sh emit`, `ask-registry.sh set-status`, and
`merge-scan-lib.sh scan-repo` (a real git fixture repo, real HEAD sha backfilled). Server wiring
(`server.js` +39/-1, `payload-schema.js` +10 for the new badge field names) verified via a
standalone runtime harness (`verify-task12-wire.js`, 8/8 PASS) proving: the auditor's badges reach
BOTH `GET /api/asks` (card-level) and `GET /api/ask/<id>` (ask-level + the matching
`plan_rows[].tasks[].drift_badges` row); the checkbox is never auto-flipped; `/api/asks` stays
<300ms while a real auditor cycle is concurrently in flight; the new `/api/diagnostics/drift`
endpoint answers. `server.selftest.js` also gained an additive Scenario 28 (+83 lines) covering
the identical assertions in-repo, gated behind a new `AUDITOR_DISABLED=1` self-test env var (the
auditor's `start()` otherwise fires an immediate, unsandboxed cycle at server-listen time, before
the shared self-test's own ask-fixture env vars are set — a genuine self-test-pollution risk this
task's own change introduced and fixed in the same commit).

NOTE (environmental, not this task's regression): running `node server/server.selftest.js` in
THIS worktree crashes with `ECONNRESET` at Scenario 23 — reproduced byte-identically via
`git stash` against the file BEFORE this task's changes, so Scenario 28 (and the pre-existing
S23-27) never execute via that entrypoint here. Task 11's own evidence entry above already flagged
the same symptom ("ECONNRESETs at S23 in the ORCHESTRATOR's integration worktree — environmental —
passes in builder's worktree"), so this is a known, pre-existing class of flake, not a defect this
task introduced. Flagged as a follow-up task (`task_c0d7d962`, "Fix ECONNRESET crash in
workstreams-ui server.selftest.js") rather than fixed here (out of Task 12's file-ownership scope).
The standalone harness above gives equivalent runtime proof of THIS task's own wiring independent
of that unrelated crash.

Follow-ups:
(a) the §8-3 count-reconciliation metric has a documented honest limitation — a NEEDS-YOU.md
parse-format regression that makes the "Awaiting your decision" section unparseable collapses both
sides of the comparison to 0 and reads as a trivial match rather than a visible mismatch (partially,
not fully, mitigated by Class G's independent operator-todo.md-pointer ground-truth set) — see
`auditor.js`'s count-reconciliation comment;
(b) the diagnostics-tab UI that would actually render `/api/diagnostics/drift` and the badge
click-through is Task 13/16's job, not built here;
(c) the pre-existing `server.selftest.js` ECONNRESET (task_c0d7d962, spawned this task).

### Comprehension Articulation

#### Spec meaning
Task 12 is the safety net the log-first law needs: every mechanism splice is explicitly
best-effort/never-blocks, so the log CAN legitimately miss an event, and this auditor is the ONLY
thing that ever reconciles it against ground truth — on a cadence explicitly kept OFF the
`GET /api/asks` request path (Behavioral Contracts: "no oracle shelling on the landing path — that
was the O.4 mistake"). Every load-bearing phrase from the divergence-class table is implemented
literally, one function per row: `auditAsk`'s Class-A branch (`backfillTaskDoneList.push(...)`,
executed by `backfillTaskDone`) never badges a healed task — verified by S1b/S1c in
`auditor.js --self-test`. `auditAsk`'s Class-E branch pushes a `log_ahead_task_not_flipped` badge
and NEVER touches the plan file — `autoCheckOperatorTodo` is the ONLY function in this module that
ever writes to a source-of-truth file the operator also edits, and it is scoped to exactly the
checkbox character on an AUTO-marked line (S2c/S3c prove both halves: the plan file is untouched,
the operator section above the AUTO markers is untouched). "The mechanical ask exit" (constraint 7)
is `backfillAskDone`, gated by `auditAsk`'s `setStatusDoneNeeded` (`reg.status === 'active' &&
allTerminal`, where `allTerminal` requires `plan.status === 'COMPLETED'` on EVERY linked plan) —
S5 proves this is a REAL `ask-registry.sh set-status` call, not a simulated one. "Reused
derive-cache.js plumbing" is literal: `runCli` shells via `bashBin()`/`spawnEnv()` imported from
`derive-cache.js`, the same idiom `server.js`'s own `runAskRegistryCli`/`classifySessions` already
use. "Never a landing-page banner" (§8-3) is why the count-reconciliation result lives ONLY in
`getDiagnostics()`, never in `buildAskCard`'s `drift_badges` — S3e asserts no ask's badge array
ever references the orphaned id.

#### Edge cases covered
- Idempotent re-cycling → `runCycle`'s single-flight guard (`state._cycleInFlight`) plus every
  backfill call routing through `progress-log.sh`'s own natural-key dedup means re-running a cycle
  over an already-healed ask is a no-op (S1d: exactly one backfilled line after two cycles).
- Legitimate re-dispatch vs a genuinely orphaned `task_started` → Class F's match key is
  `(ask_id, plan_slug, task_id, session_id)`, the EXACT four fields `workstreams-emit.sh`'s
  `_emit_dispatch_provenance` stamps from the same call-site variables onto BOTH the `task_started`
  event and the dispatch-provenance marker — a precise match, not a fuzzy heuristic.
- Concurrent read during a slow cycle → `getBadgesForAsk` reads a plain in-memory object, never
  awaiting the in-flight cycle's promise; S6 (`auditor.js`) proves a badge read completes in <50ms
  while a real cycle (with several bash spawns) is running, and S28f (harness proof) proves the SAME
  for a live HTTP `/api/asks` request.
- Multi-repo merge scanning without flooding the machine → `repoRootsForCycle`'s `AUDITOR_REPO_ROOTS`
  env override (checked BEFORE the `config/projects.js` full-discovery fallback) lets a sandboxed
  caller confine the scan to one fixture repo — used by both `auditor.js`'s own self-test and the
  server-wiring harness to avoid walking the real machine's project set on every assertion.
- Path-traversal-safe operator-todo.md rewrite → `autoCheckOperatorTodo` never rewrites a line it
  didn't itself match via `POINTER_RE`, and only ever flips `[ ]`→`[x]` on the FIRST occurrence of
  the exact substring `- [ ] AUTO:`, preserving every other byte via a tmp-file+rename atomic write.

#### Edge cases NOT covered
- The §8-3 count-reconciliation's own blind spot (a total NEEDS-YOU.md parse-format regression
  collapsing both sides to 0) — documented as Follow-up (a) above, not fixed; Class G provides
  partial, not complete, coverage of the same failure mode.
- Task 13's click-through UI for a badge's `detail_ref` and Task 16's diagnostics-tab consumer of
  `/api/diagnostics/drift` are not built by this task — the DATA contract is complete and tested,
  the rendering is explicitly out of scope (file-ownership boundary: `web/*` is Task 13's).
- `AUDITOR_CLI_TIMEOUT_MS` (default 60000ms) could theoretically be too short for a genuinely
  overloaded machine mirroring the 94-119s slow-spawn characteristic `server.js`'s own comments
  document for OTHER (heavier, jq-132-call) oracle scripts — `progress-log.sh`/`ask-registry.sh`/
  `merge-scan-lib.sh` are lightweight standalone scripts, not the heavy `nl`/derive-lib chain, so
  this budget was not stress-tested against that specific documented slow-spawn class.
- Multi-match merge attribution (one commit touching >1 plan's files) is entirely `merge-scan-lib.sh`
  Task 5b's own tested behavior (`ms_scan_repo_for_merges`'s own self-test Scenario 3); this task
  only calls it and does not re-verify that behavior independently.

#### Assumptions
- Circular-require avoidance is worth the reader duplication → `auditor.js` deliberately does NOT
  `require('./server.js')` (would be a real circular require: `server.js` requires `auditor.js` at
  load time, before its own `module.exports` assignment) — instead `foldAskRegistry`/`readAskEvents`/
  `parsePlanFile`/etc. are independently re-implemented, matching this codebase's own established
  precedent (`merge-scan-lib.sh`'s `_ms_resolve_ask_id` duplicating `plan-lifecycle.sh`'s ask-id-header
  parse rather than sourcing across hook boundaries).
- "Terminal" for the mechanical ask-exit means literally `Status: COMPLETED`, not any of this
  estate's other terminal-ish plan statuses (`ABANDONED`/`DEFERRED`/`SUPERSEDED`) — an abandoned
  plan should never silently mark its ask done; scoped deliberately narrower than "not ACTIVE".
- `operatorTodoPath()`'s fallback (`mainRepoRoot()` + `docs/operator-todo.md`) assumes this server
  process always runs from the MAIN checkout in production (never a builder worktree) — the same
  assumption `server.js`'s own `needsYouMdPath()` fallback already makes for `NEEDS-YOU.md`; not a
  new risk this task introduces.
- Dynamic (never-memoized) path resolution is required for correct sandboxing → every stateful path
  resolver (`rProgressLogStateDir`, `rAskRegistryFile`, etc.) re-reads its env var on EVERY
  `runCycle()` call rather than freezing it at `createAuditor()` construction time — discovered as
  necessary mid-build when the FIRST server-wiring harness attempt showed the auditor resolving
  production paths despite the self-test's env vars being set (they were set AFTER
  `require('./server.js')`, which constructs the auditor); fixed before commit, not left as a gap.

---

## Task 10 — Plan↔ask linkage convention + ADR 062 (merged: master 20fd90e; builder commit 48d0a4b)

Substance (mechanical): start-plan.sh --self-test 12/12 (incl. S10 real ask-registry e2e, S11
no-ask-id-no-registry-call); plan-reviewer Check 16 direct-tested (cc8 WARN-non-blocking rc0, cc9
populated-silent, cc10 grandfathered-no-v2-silent); ADR 062 + DECISIONS |062| row present;
registry backfill of ask-20260710-workstreams-rebuild PRESENT + mirror under MAIN checkout.

### Comprehension Articulation

#### Spec meaning
Task 10 makes plan↔ask linkage a real bidirectional convention. Doctrine one-liner in planning.md
states the law; template's new `ask-id: <id | none — no linked ask>` field + comment makes it
concrete. start-plan.sh operationalizes both directions: `parse_flags` accepts --ask-id,
`generate_plan_file`'s awk substitutes it onto the ask-id: line, then `start_plan` calls
`ask-registry.sh link-plan` so the registry's `"record_type":"plan_linked"` back-link lands with
the header field (plan→registry via field, registry→plan via link-plan). plan-reviewer.sh gains
Check 16: computes ASK_ID_MISSING, and ONLY inside the existing `lifecycle-schema: v2` grandfather
gate prints a WARN to stderr, never calls add_finding (advisory, non-blocking). ADR 062 + DECISIONS
row record the redesign. Self-demonstrates by backfilling its own ask-20260710-workstreams-rebuild.

#### Edge cases covered
- Omitted --ask-id → `if [[ -n "${ASK_ID:-}" ]]` guards the back-link; S11 asserts blank field + no
  registry file created.
- Grandfathered legacy plans → Check 16 inside the `LIFECYCLE_SCHEMA_VALUE == v2` block; cc10 pins a
  no-v2 fixture staying silent rc0.
- WARN must not block → cc8 asserts rc0 AND "Check 16" appears (stderr note without touching blocking exit).
- Populated ask-id stays silent → cc9 (`ask-id: ask-selftest-1` → no "Check 16" output).
- Missing/best-effort registry script → back-link guarded by `if [[ -f "$ar_script" ]]` + `|| true`.
- Worktree durability → real backfill w/ --repo pinned to nl_main_checkout_root; mirror landed under
  MAIN checkout (docs/asks/ask-registry.jsonl), not the worktree.
- Placeholder value → Check 16 treats the literal `<id | none — no linked ask>` as missing → still WARNs.

#### Edge cases NOT covered
- No validation of the ask-id's existence → link-plan appends a plan_linked record for any string; a
  typo'd id creates a dangling link with no `created` record (deferred to auditor/reader-fold, Tasks 11/12).
- No dedup of repeated links → re-running --ask-id X for the same slug appends a 2nd plan_linked record
  (append-only fold tolerates; no idempotency guard added).
- Check 16 single-field only → verifies presence/non-placeholder, not that the value resolves to a
  registry entry nor that the registry back-links this slug (a hand-edited header could carry ask-id: w/o a link).
- CRLF/\r on the header value → awk trims surrounding whitespace but no explicit \r-strip; repo eol=lf pin is the backstop.

#### Assumptions
- start-plan.sh's SCRIPT_DIR (via BASH_SOURCE) reaches the real scripts/, so `$SCRIPT_DIR/ask-registry.sh`
  hits Task 8's CLI even in a fixture repo — verified by S10 w/ sandboxed ASK_REGISTRY_STATE_DIR/MIRROR_PATH.
- Template ask-id: line format stable + matches the awk guard (em-dash included); template + substitution
  changed in the SAME commit so they can't drift.
- Check 16 belongs in the v2 grandfather block (convention post-dates every existing plan); WARN-not-finding
  is the correct altitude per ADR 036-d (governing Checks 14/15).
- DECISIONS index tolerates out-of-numeric-order rows (058/059/057 already out of order); appending |062|
  satisfies decisions-index-gate's atomicity (record + row staged together) without reflowing.
- Backfill verbatim ref (docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md#1) is canonical
  for ask-20260710-workstreams-rebuild per the plan header bootstrap note.

## Task 7 — Manifest writer family + doctor-green (MECHANICAL HALF ONLY) (merged: master `6832eba`; builder commit `2a60e3f`)

> NOTE: Task 7's Done-when has TWO halves. This evidence + the checkbox cover ONLY the
> mechanical half (manifest.json + doctor-green). The SECOND half — a mandatory
> harness-reviewer (Fable) pass over the Tasks 1,3-6 splice diffs with findings folded in —
> is OUTSTANDING (see FABLE-HANDOFF.md). Task 7's checkbox stays UNFLIPPED until the Fable
> review lands and its findings are folded in.

**Spec meaning:** Task 7 requires one `manifest.json` entry `id: progress-log, kind: writer`
with `honest_status` naming every splice site verbatim (session-heartbeat is the template
shape), plus `doctor --quick` staying GREEN. Dispatch scoped this builder to the
manifest+doctor mechanical half only — the harness-reviewer pass over Tasks 1,3-6 splice
diffs runs separately on Fable (untouched here).

**Edge cases covered:** (1) Alphabetical insertion — verified all four new ids
(`ask-registry`, `dispatch-provenance`, `merge-scan`, `progress-log`) sort against their
neighbors; confirmed the ONE pre-existing ordering anomaly
(`workstreams-extract-pending`/`workstreams-emitters`) predates this diff (pure-addition,
0 deletions near it). (2) Schema conformance — `hooks: []`/`events: []` for non-hook-file
writers avoids tripping the disk-coverage check (which only scans `hooks/*.sh` top-level).
(3) Doc-generation drift — `gen-architecture-doc.sh --check` surfaced a RED; `git stash`
confirmed baseline GREEN pre-edit, so the drift was this edit's to fix, regenerated via
`--gen`.

**Edge cases NOT covered:** Did not resolve the other 8 doctor REDs (manifest-freshness vs
live ~/.claude, obs-scheduled-tasks, obs-consumer-map `supervisor-pass`, budget-chains,
budget-active-plans, budget-worktrees-branches) — all confirmed pre-existing (present in
both before/after doctor runs, unrelated to progress-log manifest content) and outside
`manifest.json`-only file ownership. Did not exercise splice functions' runtime behavior —
Task 7 is `Verification: mechanical`; Tasks 1-6/9 functional evidence landed with those
tasks.

**Assumptions:** `manifest-freshness` RED against live `~/.claude` is structurally expected
for any unmerged branch (per CLAUDE.md: harness changes durable only once MERGED TO MASTER);
did not run `install.sh` against live config from a WIP worktree (would push unreviewed
content to the shared machine ahead of merge). "doctor stays GREEN" read as "no NEW RED
relative to baseline," confirmed by diffing doctor output before/after.

Evidence: `manifest-check.sh` GREEN — 116 entries, 103 hooks covered, 0 warn (up from 112
pre-edit); self-test 12/12; `node -e "JSON.parse(...)"` valid JSON. Integrated on master at
`274c9b6`→rebased→`6832eba`.

## Task 14 — My To-Do sidebar pane (merged: master TBD; builder commit `a9017ae`; integ `b23905c`)

**Spec meaning:** Task 14 requires ONE To-Do list in a new sidebar pane built from TWO
sources in `docs/operator-todo.md`: the `## Operator items` section (freely add/edit/check,
writing back only there) and the marker-delimited AUTO section whose bullets `needs-you.sh`'s
Task 4 splice (`_ny_operator_todo_append_pointer`) appends and whose checked state is DERIVED
exclusively by Task 12's auditor (`autoCheckOperatorTodo`) — this task RENDERS that
derivation, never computes it, plus adds ONE operator-initiated escape hatch ("Mark handled")
for when the auditor can't see a real resolution. Server: `GET`/`POST /api/todo` in
`server.js`'s routing chain, resolving the path like `needsYouMdPath`/auditor.js's
`operatorTodoPath`. Client: new `web/todo.js` (same IIFE/no-op-if-root-missing convention as
`asks.js`), four UI states, mounted via a sidebar wrapper in `web/index.html`.

**Edge cases covered:** absent file → GET positive empty state vs POST `ensureOperatorTodoFile`
(byte-identical template to `_ny_operator_todo_ensure`); out-of-range index → named 404
(S33/S33b); anti-noise on both write (`containsDenylistedIdentifier` reject, S34) and read
(hand-injected foreign line, S37); double-override → 409 (S35c); auditor-never-reverts proven
against real `auditor.runCycle()` (S35d); real concurrent-writer interleaving via a second
`needs-you.sh` process (S36); `raw_link` re-checked with `payloadSchema.isAbsoluteHref`
before the wire.

**Edge cases NOT covered:** true simultaneous (same-millisecond) writes remain
last-writer-wins — no locking anywhere in this codebase (`autoCheckOperatorTodo` has the
identical exposure); only sequential interleaving tested. Deletion of operator items
intentionally absent — spec names only add/edit/check. An operator hand-reordering lines
between a GET and a subsequent toggle/edit POST can make an in-range index target the wrong
line — accepted limitation of index-based addressing for a solo-operator local tool.

**Assumptions:** the pointer bullet's embedded title (first line of `--text`) is sufficient §3
context once a decision drops out of NEEDS-YOU.md's open-decisions section, with
`readNeedsYouDecisionsResult` cross-reference as best-effort enrichment. "Navigate to the
ask's waiting item" (P1 scope) satisfied by an absolute link to the raw NEEDS-YOU.md file,
mirroring `buildWaitingItems`'s defect-form `raw_link` precedent, since no per-decision anchor
exists and `asks.js` is off-limits. Task 16 owns the FINAL sidebar layout — the
`.ws-layout`/`.sidebar` CSS here is a working, visible placeholder Task 16 refines.

Evidence: builder direct-HTTP proof against sandbox (CTREE_PORT=17811) — add/toggle/edit
round-trip + persist, real `needs-you.sh add` produced an AUTO pointer surfaced with correct
§3-body/section/tier/session/absolute raw_link, override flips box + real auditor cycle left
file byte-identical, all error paths named/recoverable. Orchestrator independent smoke
(CTREE_PORT=17812): `GET /api/todo` → HTTP 200 `{"ok":true,...,"operator_items":[],
"pointer_items":[]}`; `todo.js` → HTTP 200. Automated S29-S37 blocked upstream by the
pre-existing `S22b→S23 ECONNRESET` (task_e41fc644), before any Task 14 code path runs.

## Task 15 — Backlog sidebar pane (builder worktree commit `82aa7e3`; Stage-3c fix follow-up commit TBD)

**Spec meaning:** Task 15 renders `docs/backlog.md` compact top-N-per-tier (collapsible to a
full list), an ADD form, and SCHEDULE/DEMOTE/FOLD/WONTFIX disposition buttons — writing the
EXACT marker vocabulary the O.9 triage loop's golden oracle (`od_backlog_health` in
`observability-derive.sh`) understands, row-scoped, to the REAL file (no parallel store). The
loop's parser is the done-criterion oracle. `parseBacklogRows` ports that oracle's R1–R4
terminal/in-flight regexes VERBATIM (`BACKLOG_RE_TERM_R1..R4` / `BACKLOG_RE_INFLIGHT_R1..R4`
from the `BACKLOG_TERM` / `BACKLOG_INFLIGHT` fragment constants), so a row this module READS
classifies the same way the loop reads it. The `dispose` handler appends markers whose words
come from `BACKLOG_DISPOSITION_WORD`. CALIBRATED CLAIM (post-Stage-3c): the port makes GET
classification agree with the loop; the ADD path does NOT preserve "whatever bytes the operator
typed" verbatim — it preserves their WORDS while restructuring the row (id-only in the bold
lead, verbatim title after a colon, `**`→`*` in verbatim text) precisely so a freshly-added
OPEN row classifies OPEN under the real oracle EVEN when the title/description contains a bare
disposition keyword. "IDENTICALLY" holds for the read/GET path and for dispositions; for the
ADD path the guarantee is narrower and explicit: the emitted row is a well-formed row the loop
classifies OPEN, with the operator's title text intact.

**Edge cases covered:** row-scoped writes via `findBacklogLineIndexForId` (negative-lookahead so
`OPEN-01` never hits `OPEN-01-FOLLOWUP`; S44c = exactly one line changes); byte-exact undo
(`undo` removes exactly the returned `appended_suffix`, 409 on tail-mismatch — S45d/S46);
insert location before the next `## ` heading (`findBacklogInsertIndex`; S42b leaves the
sibling section untouched); missing file → `''` empty state; keyword-guarded id generation
(`backlogIdBaseFromTitle` drops every TERM/INFLIGHT token so the id — which sits inside R1's
bold reach — can never carry one, probe E). **ADD-PATH GRAMMAR-COLLISION GUARD
(comprehension-review Stage 3c):** a freshly-ADDED open row whose title or description contains
a bare disposition/terminal keyword ("Document WONTFIX semantics", "how SCHEDULED rows re-nag",
"Add a CLOSED-state badge") now classifies OPEN under the REAL `od_backlog_health`, via THREE
coordinated guards proven together against the real oracle — (1) structural: only the
keyword-guarded id sits inside the leading `**...**`; the verbatim title moves out after a
COLON separator (`- **ID**: title`, not the em-dash real rows use inside the bold) so a
keyword-LEADING title can't chain off the id's closing `**` via R2 (probe C=TERMINAL vs
D=OPEN); (2) `backlogIdBaseFromTitle` keyword-token strip (probe E); (3)
`backlogNeutralizeMarkdown` collapses operator-typed `**`→`*` in title+description so verbatim
text can't smuggle a `**KEYWORD` bold segment R2/R3/R4 anchor on (probe G/H) — a BARE keyword
in free text is already OPEN-safe (probe F), so no WORD is altered. `BACKLOG_DISPOSITION_KEYWORDS`
is DERIVED from the same ported `BACKLOG_TERM`+`BACKLOG_INFLIGHT` fragments (never a second
hand-list), so the guard can't drift from the classification regexes. `backlogRowParts` reads
the verbatim title from BOTH the canonical `**ID — title**` form and the new `**ID**: title`
form, so display is unaffected. Regression oracle: S42d/S42e/S42f — S42e shells the REAL
`od_backlog_health` over the post-add fixture and asserts OPEN.

**Edge cases NOT covered:** true simultaneous (same-millisecond) writes remain last-writer-wins
— `withBacklogFile` re-reads fresh each call but has no lock (the same accepted exposure
`withOperatorTodoFile` / `autoCheckOperatorTodo` carry); the undo tail-match bounds the blast
radius but does not eliminate the race. A row whose leading bold id is a strict prefix of a
longer real id would resolve to the first match — the oracle's own extraction is likewise
first-wins and real ids are unique, so this is theoretical. The full `server.selftest.js` suite
still cannot REACH S40–S49/S42d-f in THIS environment because of the pre-existing S22b→S23
ECONNRESET (`task_e41fc644`); the scenarios are proven via a standalone runner (byte-identical
assertions) and direct live-server HTTP — the upstream hang is out of scope and unfixed. No
browser-DOM assertion (advocate/Preview owns that); UI states verified by construction + the
JSON payload.

**Assumptions:** the O.9 parser to match is `od_backlog_health` (contract C4) — the three
production consumers parse its output, and the plan's Integration point names "the O.9 loop
parser / its fixture corpus" as the oracle, so I ported its regexes rather than re-deriving.
New rows belong in "Open work — substantive deferrals" (`BACKLOG_ADD_SECTION_HEADING`, a
constant). `BACKLOG_MD_PATH` is the sandbox env override (the same var the real oracle honors,
so a fixture is read identically by both). WONTFIX is the only disposition without an Undo —
the server accepts an undo of any suffix uniformly; the CLIENT enforces "CONFIRM not undo" for
WONTFIX. On the Stage-3c row-structure deviation: real open rows put the title INSIDE the bold
lead (`- **ID — title**`), which is itself vulnerable to this exact collision; since the spec
requires preserving the title verbatim AND classifying OPEN, and those two cannot both hold with
the title inside the bold, the id-only-in-bold + colon structure is the correct resolution
(authorized in the review), preserving the operator's words at the cost of a minor,
documented structural variance from the legacy corpus.

Evidence (all against the REAL `od_backlog_health`, not eyeball): probe of 8 candidate ADD
structures — current-buggy `- **ID — title**` with keyword title → TERMINAL (bug reproduced);
em-dash id-outside with keyword-leading title → TERMINAL (R2); unguarded keyword-in-id →
TERMINAL; colon id-outside + keyword-leading title → OPEN; colon + bare keywords in
title/description → OPEN; literal `**WONTFIX**`/`**SCHEDULED**` in description → TERMINAL/INFLIGHT
(fixed by the `**`-neutralizer). Live server CTREE_PORT=17830: five keyword-laden titles ADDed
("Document WONTFIX semantics", "how SCHEDULED rows re-nag the operator", "Add a CLOSED-state
badge", "WONTFIX and CLOSED handling"+`**DEMOTED**`/`**SUPERSEDED**` description, "normal
title"+"please DEMOTE and check CLOSED policy") → real `od_backlog_health` reads ALL FIVE OPEN
(open_total=5, terminal=0, inflight=0); GET shows each title verbatim, not the id. Standalone
runner (bypasses the S22b hang): 27/27 PASS incl. S42e "keyword row classifies OPEN under the
REAL od_backlog_health (regression oracle, run post-close)". Prior-commit runtime evidence
(WONTFIX→terminal, DEMOTE→dispositioned-in-flight-and-dropped-from-overdue, byte-exact undo,
real-file add+revert) unchanged and still valid.

## Task 17 — Mechanized metrics + doctor wiring (sketch §8) (merged: master TBD; builder commit `a56212e`; integ `c72e9f3`)

**Spec meaning:** Task 17 (`Verification: mechanical`) mechanizes sketch §8's four metrics. (a)+(b) EXTEND the existing `check_obs_cockpit_fresh` (never a duplicate): a new `else` branch — reached only when the health body already graded clean — reads the SERVER's OWN verdicts off the wire (`/api/asks` 500 `"payload schema validation failed"` for anti-noise/href §8; `/api/diagnostics/drift` `count_reconciliation.mismatch` for §8-3) and REDs, never re-deriving `validateLanding`/reconciliation locally. (c) a NEW predicate `check_obs_ask_capture_completeness` proving Task 9's invariant. (d) `ask-cockpit-checkin.sh` + a `-Checkin` mode on `install-weekly-hygiene-task.ps1` register the 2-week cold-start check-in as a calendar task writing into the alert dir the wired `external-monitor-alert-surfacer.sh` reads.

**Edge cases covered:** *Population parity (THE load-bearing property):* `check_obs_ask_capture_completeness` sources the real `progress-log-lib.sh` and calls `pl_classify_session` (the EXACT function `workstreams-read.sh`'s Task 9 splice calls) with `--dispatch-provenance-dir`, and derives each expected ask via `pl_ask_id_for_session` (the same derivation the capture splice mints) — so a spawned/worktree session is excluded from BOTH the guard's registration set and this audit's population BY CONSTRUCTION; proven by the `o6-capture-parity-spawned-excluded` fixture (registered operator + unregistered spawned → GREEN). Unresolvable-cwd heartbeats are SKIPPED not guessed (a false skip is cheap, a false RED is not). The extension's `else` branch is entered only on a clean health body, so a lobotomized/failing cockpit is never further-diagnosed. `curl` for `/api/asks` deliberately omits `-f` (the diagnostic body rides on the 500). Reconciliation grading uses `jq` with a `grep -E` fallback. Installer gained `SupportsShouldProcess` so `-WhatIf` is a true dry-run gating both `Register`/`Set` and `Unregister`. `ask-cockpit-checkin.sh` sandboxes via `HARNESS_SELFTEST_DIR`, degrades silently on mkdir failure (writer semantics), JSON-escapes its summary.

**Edge cases NOT covered:** The full `harness-doctor.sh --self-test` suite (100+ scenarios, each re-running `--quick`) did not run to completion in-environment (each `--quick` ~60-90s under load; suite exceeded the timeout) — proven instead via a standalone runner reusing the doctor's REAL helper definitions + the REAL `--quick` (identical code path); the 6 fixtures are embedded for future full runs. The doctor extension reads live HTTP endpoints (`/api/asks`, `/api/diagnostics/drift`) — proven with PATH-injected `curl` stubs, not a live server (endpoints are Tasks 11/12, already merged). The count-reconciliation predicate inherits `auditor.js`'s documented total-parse-regression blind spot (rename the "Awaiting your decision" header → both sides collapse to 0) — flagged in `auditor.js`, not re-solved. `-WhatIf` validated by forcing UTF-8 decode because these `.ps1` files carry a pre-existing em-dash/no-BOM hazard under Windows PowerShell 5.1 `-File` (filed via nl-issue.sh — pre-existing, not this task's regression).

**Assumptions:** Extending `obs-cockpit-fresh` (per dispatch instruction) rather than duplicating keeps the retirement condition + gates shared. "Doctor stays GREEN" = "no NEW RED vs baseline" — proven by baseline-diff (predicates silent when their mechanism is absent) + never running `install.sh` against live `~/.claude` from the WIP worktree. The `-Checkin` 2-week task reuses the existing `external-monitor-alerts` transport (zero new SessionStart entries, honoring the 8/8 cap). `pl_ask_id_for_session` yields a stable id across `--resume` (per its header). S50–S56 depend only on `payload-schema.js` + a freshly-sandboxed `auditor` (never the live server or the flaky needs-you.sh fixture chain), making them isolatable around the pre-existing ECONNRESET.

Evidence (builder, clean worktree): doctor 6/6 GREEN+RED — `o6-cockpit-t17-extension-green` (silent on clean), `-schema-red` (injected schema-fail → RED), `-recon-red` (injected mismatch → RED), `o6-capture-red-fires` (trailing-24h operator session no ask → RED), `-green-registered` (registered → silent), **`-capture-parity-spawned-excluded` (spawned session excluded via pl_classify_session → GREEN)**; baseline-diff = no NEW unconditional RED. Server S50–S56 7/7 via direct require (isolated around S22b→S23 ECONNRESET). `install-weekly-hygiene-task.ps1 -Checkin -WhatIf` = dry-run registered NeuralLace-AskCockpit-Checkin (2-week trigger) with `Get-ScheduledTask` confirming NO real task created; `ask-cockpit-checkin.sh --self-test` 7/7. ORCHESTRATOR INTEGRATION VERIFY: predicate code byte-identical to a56212e (the 100-line drift vs builder = master's separate check_master_drift_* functions, non-overlapping); `bash -n` harness-doctor.sh + ask-cockpit-checkin.sh syntax OK; server.selftest.js union valid JS (`node --check` OK), both S40-49 (24) + S50-56 (7) blocks present. Full doctor self-test deferred to CI Hooks-self-test (clean env; local run hangs under agent contention).

> Task 17 comprehension-review: PASS conf 9 (population parity PROVEN at code level —
> pl_classify_session 0=SPAWNED/1=operator, predicate `continue`s on spawned). Non-blocking
> ADVISORY (recorded per §5): `check_obs_ask_capture_completeness` confirms registration via a
> fixed-string `grep -qF "\"ask_id\":\"<id>\""` — this couples the predicate to ask-registry's
> compact single-line JSONL shape (no space after colon). If a future edit pretty-prints/reshapes
> the registry line, the predicate silently stops matching. HYPOTHESIZED, low-risk (same task
> family owns the writer); no code change required for this task — flagged for the registry-shape class.

## Task 16 — Layout integration + Harness Health demotion (merged: master TBD; builder commit `8777e58`; integ `a2f4630`)

**Spec meaning:** Make the ask tree + sidebar (Tasks 13-15) the ONLY thing on the landing route; demote the six wave-O panes to a lazily-activated Harness Health tab with ZERO DOM footprint on landing (anti-noise law); ship NO Team tab; add mechanized self-test assertions + a Diagnostics view. Implemented via a native `<template id="harnessHealthTemplate">` (browser-native inertness, not a `display:none` trick) cloned once by `initHarnessHealthTab()` on first activation; `app.js`'s render functions (`renderStatus`/`renderNeedsMe`/`renderHealth`/`renderCosts`/`renderShipped`/`renderBacklog`/`renderReconciler`/`openWhyDrawer`) left byte-identical — only their element-handle assignment moved from module-load to first-activation time.

**Edge cases covered:** DOM-id collision between the six-pane "Backlog health" strip and Task-15's sidebar `#backlogBody` (pre-existing Task-4 bug; would cause a silent-overwrite race once both live in the DOM post-cloning) — fixed via `backlogHealthBody`, locked by self-tests T16-14/14b. Global keydown handler (`Escape`/`Tab` focus-trap) null-guards `whyDrawer` (doesn't exist before first Harness Health activation). Docs-viewer modal kept global/immediate (asks.js plan drill-down needs it on landing). `pollHealth()` ui-build auto-reload kept global.

**Edge cases NOT covered:** The ask tree (`asks.js`) has no periodic auto-refresh/SSE of its own (pre-existing gap from Tasks 13-15, not introduced/fixed here) — an auditor-driven landing change won't appear until manual reload; out of Task 16 scope. The sibling abbreviated-path bullet at plan line 614 carries the identical scope-gate landmine — flagged via nl-issue, not fixed.

**Assumptions:** "Diagnostics (reconciler internals, drift detail) live here too" = wire the already-built-but-unconsumed `GET /api/diagnostics/drift` (server.js's own comment names it "the diagnostics-tab surface, Task 16") into a new section — built `renderDiagnostics()`/`loadDiagnostics()` reading the real `auditor.getDiagnostics()` shape (cycle_count, healed_recent[], backfill_errors[], count_reconciliation, badges_by_ask), verified against real auditor output. Assumed the reconciler badge, interrupt strip, and why-drawer (wave-O/session-derived) belong inside the Harness Health quarantine alongside the six panes (same oracle data the anti-noise law scopes off landing).

Evidence: builder browser-MCP verification (CTREE_PORT=17850, real accessibility tree): (1) landing = ask tree + sidebar, tabs Asks/Harness Health, ZERO six-pane/reconciler/interrupt ids, no Team anywhere; (2) Harness Health tab clones template (healthChildCount 6, hasCockpit true), all six panes real data incl. Diagnostics (real auditor cycle: "cycle 1, took 61045ms, 1 healed backfill, count-reconciliation match"); (3) responsive — 1366px flex row / sidebar sticky 320px, 1024px flex column / sidebar static full-width, geometrically stacked below tree; (4) cockpit.selftest.js 84/84 (14 new T16 assertions). ORCHESTRATOR INTEGRATION VERIFY: cherry-pick a2f4630 clean (0 conflicts); `node web/cockpit.selftest.js` → 84/84 PASS exit 0 on integrated tree. Full runtime acceptance = Task 18 (end-user-advocate). server.selftest.js still blocked at pre-existing S22b→S23 ECONNRESET (task_e41fc644; builder never touched server.js).

## Task 18 — Acceptance (merged: master TBD; acceptance run + fix-forward `86e9e69`)

**Part A — end-user-advocate RUNTIME pass (mechanized, the gate):** all 6 Acceptance Scenarios PASS. Advocate drove the real assembled cockpit in a real browser (Chrome+CDP), fixtures for destructive scenarios, real registry at true volume for read/volume scenarios. Artifacts: `.claude/state/acceptance/ask-rooted-workstreams-p1/{cold-start-ask,auto-capture-zero-ceremony,todo-pointer-lifecycle,backlog-add-and-disposition,ask-lifecycle-exit,anti-noise-landing}.json` (reconstructed after the advocate worktree auto-cleaned; nl-issue filed for the durable-path gap).
- cold-start-ask PASS (four answers cold, no transcript; absolute links resolve; drill-down matches live plan; network only /api/asks,/api/ask,/api/doc).
- auto-capture-zero-ceremony PASS · backlog-add-and-disposition PASS (keyword title stayed OPEN under REAL od_backlog_health — Stage-3c guard held; open52/terminal15 matched UI) · ask-lifecycle-exit PASS (auto-move emitter:auditor + dismiss/undo/redismiss) · anti-noise-landing PASS (DOM+payload denylist-clean, zero relative hrefs, six panes tab-only).
- **todo-pointer-lifecycle: initially FAIL → FIXED → PASS.** Advocate found the My-To-Do pane CLIPPED to a 49px header at >1200px (real 52-row Backlog starved it via `.pane{overflow:hidden}` zeroing flex min-height). Data lifecycle was always sound. FIX `86e9e69` (`.sidebar > .pane { flex-shrink: 0 }`, scoped so the six-question grid panes are untouched). RE-VERIFIED at 1920×1080: `#todoSection` clientHeight 204==scrollHeight (no clip), first item in viewport, real checkbox click → POST /api/todo → durable file checked:true (genuine end-to-end); 1024px stacking unregressed; cockpit.selftest 84/84.

**Part B — OPERATOR <60s cold-start walkthrough:** PENDING as DEMONSTRATION (operator directive: "the acceptance walkthrough still runs — as demonstration, not as a permission gate"). To be recorded in the completion report with the timing once the operator runs it against the deployed cockpit at true volume.

**Known caveat (tracked, not blocking this scenario):** the full `server.selftest.js` still crashes at the pre-existing S22b→S23 `ECONNRESET` (task_e41fc644 / operator's task_c0d7d962), so the closure-contract "every self-test full-PASS" is not yet met; anti-noise negatives S50–S52 were proven directly against `payload-schema.js`. Fold in that fix before final plan closure.

**Checkbox rationale:** flipped on Part A (mechanized acceptance) all-6-PASS + the fix-forward runtime re-verification; Part B is a non-gating demonstration per operator directive; Task 7's Fable-half + the ECONNRESET fix remain before the plan itself can flip Status:COMPLETED.
