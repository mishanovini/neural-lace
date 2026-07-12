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
- Plan-less dispatch (Explore/research, no docs/plans/*.md ref) → silent no-op (:1799-1806, PL3)
  — prevents anti-noise orphan-lane flooding.
- Replay of identical dispatch → pl_emit natural-key dedup (plan_slug+task_id+session_id) holds
  through the splice (:1808-1814, PL1b).
- Missing progress-log.sh/dispatch-provenance.sh CLIs → `[[ -f ]]` guards + `|| true` keep rc=0
  (:1855-1861, PL5).
- Pre-existing plans lacking an `ask-id:` header → `_resolve_ask_id_for_plan_slug` (:2412-2427)
  returns empty, pl_emit's orphan lane (unlinked.jsonl) absorbs it — same as Task 1, no new mode.
- `--on-spawn` with explicit tool_input.cwd hint → marker worktree_path populated (:1836-1845, PL4).

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
