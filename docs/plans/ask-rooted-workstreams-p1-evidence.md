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
