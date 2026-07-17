# Plan: Ask-rooted Workstreams — P1 (mechanism-emitted progress log + ask registry + ask-tree surface)
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 3
rung: 4
architecture: hybrid
<!-- hybrid: spans coding-harness (emission splices into hooks/scripts, manifest,
doctrine, templates) and orchestration (dispatch/verifier/merge lifecycle events
+ the operator-facing workstreams surface that renders them). -->
frozen: true
<!-- Both plan-time reviews LANDED. Round 1 (2026-07-10): ux-designer FAIL +
systems-designer FAIL, all amendments applied. Round 2 re-review (2026-07-11):
ux-designer PASS + systems-designer PASS-WITH-CONCERNS (no Critical/Major, zero
unresolved round-1 findings); the five round-2 minors are applied — see
"## Review round 1 (2026-07-10) — applied amendments" (incl. the Round 2 index)
at the end of this file. Plan frozen for build. -->
lifecycle-schema: v2
owner: misha
target-completion-date: 2026-07-24
prd-ref: n/a — harness-development
ask-id: ask-20260710-workstreams-rebuild
<!--
ASK-ID LINKAGE CONVENTION (design sketch §4, modeled here): every plan header
carries `ask-id: <id>` naming the ask-registry entry this plan serves. Plan
creation records the linkage in BOTH directions: the header line here, and the
registry entry's `plan_slugs[]` gains this plan's slug. `start-plan.sh` gains
`--ask-id <id>`; the planning doctrine gains one line (Task 10). BOOTSTRAP NOTE:
this plan predates the registry it builds — Task 10 backfills the entry
`ask-20260710-workstreams-rebuild` (verbatim ref: the operator's 2026-07-10
requirements conversation condensed in the design sketch §1,
`docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md`) so the
convention is self-demonstrating on this plan.
-->

Normative source: `docs/reviews/2026-07-10-ask-rooted-workstreams-design-sketch.md`
(v2 — operator decisions §9; amended log-first law §2; P1 scope §7; pre-registered
metrics §8). Where this plan and the sketch disagree, the sketch wins and this plan
gets amended (amendment emits a `plan_amended` event once Task 6 lands — eating our
own dog food).

## Goal

Rebuild the workstreams surface around the operator's actual unit of thought — the
ASK — on a data layer that cannot rot the way the original did. Every progress
event is emitted by a MECHANISM (verifier flip, orchestrator dispatch, NEEDS-YOU
append, master merge, plan amendment, plan completion), never by model memory; the wave-O derivation
layer is demoted from sole-truth to background AUDITOR that badges drift. On top of
that log: an ask-tree landing page (grouped by project), a My To-Do pane (operator
items + auto-pointer items), a Backlog pane (render/add/disposition), and the six
wave-O panes demoted to a Harness Health tab. This closes NL-FINDING-024's failure
class mechanically and reverses the O.4 cockpit's value regression (operator verdict
2026-07-10: "not helpful at all, super noisy").

## User-facing Outcome

The operator (solo dev today; the team later) can cold-start ANY active ask —
including one whose sessions they haven't touched in days — and answer "what did I
ask, what's the plan, how far along is it, what's waiting on me" in **under 60
seconds without opening a transcript**. Concretely, after this plan ships:

- Opening `http://127.0.0.1:7733/` shows asks grouped by project, newest activity
  first; each card carries a short summary of the original ask (verbatim one click
  away), a chronological mechanism-emitted progress narrative, a plan progress bar
  (done / in flight / not started) hyperlinking the LIVE plan doc, waiting-on-you
  items with full §3 context blocks, artifacts (SHAs, PRs, reviews), and attached
  sessions with spawn lineage.
- Adding a to-do item, checking one off, appending a backlog row, and dispositioning
  a backlog row (SCHEDULE/DEMOTE/FOLD/WONTFIX) all work from the surface and write
  the SAME durable files sessions already read.
- Every decision a session parks on the operator appears as an auto-added pointer
  item in My To-Do and auto-checks itself when the underlying item resolves.
- New sessions register their opening ask automatically — zero ceremony — so the
  surface stays true as the estate grows, not just on demo day.

## Scope

- IN:
  - Progress-log event format + writer lib (`hooks/lib/progress-log-lib.sh` +
    `scripts/progress-log.sh`, mirroring the session-heartbeat script+lib split)
    and the SIX mechanism-emission splices: verifier-flip, dispatch, NEEDS-YOU
    append, master merge, plan amendment, plan completion (review round 1 — the
    ask lifecycle's mechanical exit; splice in `scripts/close-plan.sh`, reached
    via the wired `plan-auto-closure.sh` PostToolUse hook AND manual closes) —
    each a one-line best-effort splice into
    an ALREADY-WIRED hook/script (same convention as the session-heartbeat `touch`
    splices; see manifest entry `session-heartbeat` `honest_status` for the model).
  - Ask registry: `~/.claude/state/ask-registry.jsonl` + in-repo mirror; fully
    automatic capture (first operator prompt), cheap summarizer, verbatim ref;
    plan↔ask linkage convention (doctrine line + template field + `start-plan.sh`).
  - Server: `/api/asks` (landing tree payload), `/api/ask/<id>` (detail), to-do and
    backlog read/write endpoints; background auditor on a relaxed cadence (reuse of
    `derive-cache.js` plumbing) producing per-item drift badges; payload schema
    self-test enforcing the anti-noise law and absolute-href law.
  - UI: ask-tree landing (shallow cards + plan drill-down; ask lifecycle
    affordances done/dismiss/merge; default `status:active` filter with a
    collapsed completed group), My To-Do sidebar pane,
    Backlog sidebar pane (collapsible), Harness Health demotion to a tab.
    Team tab HIDDEN in P1 (review round 1 — no empty shell surfaces).
  - Acceptance: operator cold-start walkthrough (<60s bar) + sketch §8 mechanized
    metrics (anti-noise schema check in self-test + doctor; waiting-on-you count
    reconciliation) + the 2-week scheduled check-in.
  - Manifest entries, doctor predicates, runbook, decision record.
- OUT:
  - P2 inline answering from the surface (decision replies from the UI) — sketch §7.
  - P3 team aggregation; identity/auth; cross-machine transport; realtime (§6 —
    but every payload carries `{user, machine, repo}` provenance from day one).
  - Desktop-app deep-link URL scheme — a build-time SPIKE inside Task 13, not a
    commitment; guaranteed fallback (session id + title + copy button) is IN.
  - Resurrecting any attic'd event-sourced writer/gate (`workstreams-state-gate`,
    old GUI-write `POST /api/event`, etc.) — sketch §5 last row.
  - Backlog row PROGRESS-FIELD-01 (docs/backlog.md): NOT absorbed. This plan
    delivers its part-(3) end-state (in-flight signal derived from ground truth at
    ask/plan level); parts (1)–(2) (per-task `Progress:` field, auto-verifier on
    merge) stay in the backlog with this plan added as a cross-ref at completion.

**Hard constraints binding every task (from the sketch §2 laws + harness budgets):**
1. **Anti-noise law (every UI/server task):** no gate/hook identifier ever reaches
   the landing payload or renders on the landing surface; mechanically enforced by
   the payload schema check (Task 11) — a UI task whose output violates this is NOT
   done regardless of other evidence.
2. **Absolute links, always:** every href/path the surface renders is absolute;
   the schema self-test rejects relative hrefs.
3. **SessionStart cap 8/8:** `settings.json.template` SessionStart array is at its
   cap — ZERO new SessionStart (or Stop, 4/6) entries. All capture/emission lands
   as splices inside already-wired hooks (`session-start-digest.sh`,
   `workstreams-read.sh`, `workstreams-emit.sh`, `plan-lifecycle.sh`) or inside
   scripts (`needs-you.sh`, git-hooks) — the `ensure-cockpit.sh` header documents
   this exact convention.
4. **HARNESS_SELFTEST sandboxing:** every new self-test exports `HARNESS_SELFTEST=1`
   + `HARNESS_SELFTEST_DIR` and writes state ONLY under the sandbox (model:
   `hooks/context-watermark.sh` T10 scenario); `server.selftest.js` additions use a
   temp state dir + non-default port. Production `~/.claude/state` pollution from a
   self-test is a defect (`purge-selftest-pollution.sh` exists because of it).
5. **Writer semantics:** every splice is best-effort, never blocks, exits 0 on all
   runtime paths (`>/dev/null 2>&1 || true`), mirroring the heartbeat splices.
6. **Verifier monopoly preserved:** nothing here flips `- [x]` or adds a second
   done-bit; the log OBSERVES flips, it never makes them.
7. **Exit-mechanism law (review round 1):** every auto-populated collection (ask
   cards, to-do pointer items, backlog rows) must name BOTH its mechanical
   completion path AND its operator-override path in the task that builds it —
   automated entry without a specified exit re-creates the O.4 noise regression
   and fails review regardless of other evidence.
8. **Four-UI-states law (review round 1):** every data surface in Tasks 11–16
   specifies empty/loading/error/ideal. The new panes (`asks.js`, `todo.js`,
   `backlog.js`) inherit the `web/app.js` GLOBAL INVARIANT (named error state +
   Retry wired to refresh; loading DISTINCT from error — the rc===null vs rc!==0
   distinction; stale accent on aged data; failure never renders blank or the
   empty state) but with OPERATOR-ALTITUDE copy: no `od_*`/oracle/gate/hook
   identifiers in ANY state text — the existing app.js state copy embeds oracle
   identifiers and must NOT be inherited verbatim (anti-noise applies to state
   copy too). Per-surface empties: My To-Do = positive empty + add affordance;
   ask card with no linked plan = narrative + "no plan linked yet" (the common
   case, not an error); drill-down with no tasks = honest empty line;
   collapsed completed group with no completed asks = "no completed asks yet"
   (hidden or muted — never an expanded empty shell; review round 2); Backlog
   pane with no rows = honest empty line + the add affordance (review round 2).
   `server.selftest.js`/`cockpit.selftest.js` gain error-state and
   anti-noise-in-copy fixtures.
9. **Affordance + a11y laws (review round 1):** every clickable card region
   carries a visible signifier (hover/cursor/chevron); every landing badge or
   count names its click destination in its task spec; derived/auto controls
   are visually distinct from editable ones; every UI write specifies success
   feedback + mistake recovery; every error/defect render carries at least one
   action — never a terminal message. Tasks 13–16 are bound BY CITATION to the
   existing cockpit WCAG 2.2 AA contract (`web/app.js` header, ux-review
   amendment 12: real buttons/anchors, aria-live pane bodies, focus-managed
   dialogs, ≥24px targets, text+color never color-only); drift badges are
   explicitly text+color.
10. **Key-resolution + provenance law (review round 1):** every derived or
    backfilled event type names its key-resolution path from ground truth to
    `ask_id` (Task 5's merge-attribution rule is the model); every event type
    WITHOUT a ground-truth oracle (`ask_registered`, `session_attached`,
    `plan_amended`) carries provenance-trust rules — emitter allowlist in Task
    2; unknown emitters are auditor-flagged and UI-de-emphasized, never rendered
    as mechanism truth.
11. **Durable-write path law (review round 1):** every splice-written path is
    classified ephemeral-ok vs must-survive-worktree. ALL durable in-repo writes
    (`docs/operator-todo.md` pointer appends, `docs/asks/ask-registry.jsonl`
    mirror) resolve through `nl_main_checkout_root` (`hooks/lib/nl-paths.sh` —
    the same resolver `needs-you.sh` already uses, verified), never `git
    rev-parse` from a worktree cwd, so a builder-worktree write can never land
    in an ephemeral checkout and be destroyed. Every writing self-test gains a
    from-worktree fixture.

## Tasks

<!-- Dispatch per orchestrator pattern: [parallel] groups are file-disjoint.
Mandatory reviews: ux-designer + systems-designer at PLAN time (round 1 LANDED
2026-07-10, both FAIL, all amendments applied; round 2 re-review LANDED 2026-07-11,
ux PASS + systems PASS-WITH-CONCERNS, minors applied — see "## Review round 1" at
the end); harness-reviewer post-build on every hook/script
splice (Tasks 1, 3–7, 9, 10); end-user-advocate owns Acceptance Scenarios;
task-verifier is the only checkbox-flipper.
Serialization added in round 1:
- Task 9 (capture guard) DEPENDS on Task 3's dispatch-provenance marker — Task 3
  merges before Task 9 dispatches (Task 9 is already [serial] after the 2–6 group).
- Task 6 hosts TWO splices (plan_amended in plan-lifecycle.sh + plan_completed in
  close-plan.sh, reached via the wired plan-auto-closure.sh) and stays ONE task:
  same writer family, same harness-reviewer pass and manifest entry (Task 7) —
  no renumbering needed.
- Task 11's lifecycle write endpoint precedes Task 13's card affordances (already
  ordered 11 → 13, both [serial]). -->

- [x] 1. **Walking skeleton** — one event end-to-end: minimal
  `hooks/lib/progress-log-lib.sh` (`pl_emit`, `pl_path_for`, sandbox-aware) +
  `scripts/progress-log.sh emit` CLI + a verifier-flip splice in
  `hooks/plan-lifecycle.sh` + a hand-registered ask entry + a minimal
  `GET /api/asks` in `server/server.js` + one landing card in a new
  `web/asks.js` rendering the event line — Verification: full — Docs impact:
  `docs/runbooks/ask-workstreams.md` stub (event flow diagram + file locations)
  **Prove it works:**
  1. Register a sandbox ask via `bash adapters/claude-code/scripts/ask-registry.sh register --summary "skeleton test" ...` (stub form, Task 8 finalizes)
  2. In a sandbox plan under `docs/plans/`, run the real task-verifier flip flow on a fixture task (evidence-first authorized)
  3. `cat ~/.claude/state/progress-logs/ask-*.jsonl` — the `task_done` event exists with plan slug, task id, ISO ts
  4. `curl http://127.0.0.1:7733/api/asks` — the ask appears with the event
  5. Open `http://127.0.0.1:7733/` — the card renders the narrative line "task N verified done"
  **Wire checks:**
  - `adapters/claude-code/hooks/plan-lifecycle.sh` splice → `adapters/claude-code/scripts/progress-log.sh` `emit`
  - `adapters/claude-code/scripts/progress-log.sh` → `adapters/claude-code/hooks/lib/progress-log-lib.sh` `pl_emit`
  - `neural-lace/workstreams-ui/server/server.js` `/api/asks` → reads `progress-logs` dir + `ask-registry.jsonl`
  - `neural-lace/workstreams-ui/web/asks.js` `fetch('/api/asks')` → `neural-lace/workstreams-ui/web/index.html` script include
  **Integration points:**
  - `plan-lifecycle.sh` is PostToolUse-wired in `settings.json.template` (verified) — the splice sees the post-edit plan content; confirm it can distinguish a fresh `- [x]` flip from a re-save (diff against prior content or the tool-input JSON)
  - Server port 7733 / lobotomy-health contract (master `02ff2f3`) — skeleton inherits it unchanged; verify `/api/health` still grades GREEN after the route addition

- [x] 2. [parallel] Progress-log format finalization + writer hardening: versioned
  JSONL event schema (`{v, event_id, ts, ask_id, type, plan_slug?, task_id?, sha?,
  needs_you_id?, session_id?, summary, evidence_link, emitter, user, machine,
  repo}`), event-id dedup by PER-EVENT-TYPE NATURAL KEY (review round 1 — a single
  hash formula would silently suppress legitimate recurrences):
  | type | natural key (dedup) | legitimate recurrence preserved |
  |---|---|---|
  | `task_done` | plan_slug+task_id+sha | re-verify after revert = new sha |
  | `task_started` | plan_slug+task_id+**session_id** | re-dispatch of a failed task = new child session |
  | `waiting_on_operator` | **needs_you_id** | each parked decision has its own id |
  | `merged` | repo+**sha** | every merge is its own sha |
  | `plan_amended` | plan_slug+**content-hash of the delta** | second amendment = new delta hash |
  | `plan_completed` | plan_slug+**content-hash of the Status-line ts** | re-close after reopen = new Status-line ts → new hash |
  | `ask_registered` / `session_attached` | ask_id(+session_id) | attach per (ask, session) pair |
  (Superset rule, review round 2: every row's dedup-key column must be a
  superset of the discriminators its recurrence column names — audited across
  all rows 2026-07-11; `plan_completed` was the one divergent row, fixed above.)
  Emitter allowlist (constraint 10): `emit` validates `--emitter` against the
  known-mechanism list (plan-lifecycle, workstreams-emit, needs-you, post-commit,
  close-plan, ask-registry, auditor); unknown emitters are recorded but flagged
  `provenance:unknown` for the auditor to badge and the UI to de-emphasize — the
  open CLI cannot impersonate a mechanism. Atomic single-line O_APPEND
  writes, orphan-event lane for unresolvable ask-ids, `--self-test` (sandboxed,
  incl. concurrent-append + replay-dedup + LEGITIMATE-RECURRENCE (re-dispatch of
  the same task with a new session_id → TWO `task_started` events, NOT deduped)
  + unknown-emitter + CRLF-safety scenarios; repo pins `eol=lf`) —
  Verification: mechanical — Docs impact: schema section in
  `docs/runbooks/ask-workstreams.md` + `adapters/claude-code/schemas/progress-log-event.schema.json`
- [x] 3. [parallel] Dispatch emission splice: `task_started` events from the
  already-wired `hooks/workstreams-emit.sh` `--on-builder-dispatch` / `--on-spawn`
  call sites (PreToolUse on Task, verified wired in `settings.json.template`),
  carrying plan slug + task id + child session provenance (the same provenance
  the SESSIONS lineage rendering consumes) AND writing the DISPATCH-PROVENANCE
  MARKER Task 9's guard consumes (review round 1): a state file under
  `~/.claude/state/dispatch-provenance/` keyed by target worktree path + dispatch
  ts, written at dispatch time, pre-attaching the child to the dispatching ask.
  NO spawn-time marker exists today (verified 2026-07-10 against
  `scripts/spawn-worktree.sh` and `scripts/nl.sh` — neither writes one), so this
  task CREATES it and Task 9 depends on it (see dispatch comment). One-line
  best-effort splice; the old
  tree-state write path is untouched (it remains the auditor's comparison input) —
  Verification: mechanical — Docs impact: none — splice documented via Task 7 manifest entry
- [x] 4. [parallel] NEEDS-YOU emission splice: `scripts/needs-you.sh add` emits
  `waiting_on_operator` (needs-you id, section, tier, session id, cold-reader
  lint result carried as the §3-context-present flag) AND appends the auto-pointer
  item to `docs/operator-todo.md` (marker-delimited auto-section; operator section
  untouched; path resolved via `nl_main_checkout_root` per constraint 11 — the
  resolver `needs-you.sh` already uses for its ledger — never the worktree cwd;
  `--self-test` gains a from-worktree fixture proving the pointer lands in the
  MAIN checkout when the splice fires inside a builder worktree).
  Resolution is NOT emitted here — it is derived (auditor, Task 12)
  so pointer auto-check survives resolutions that bypass the script —
  Verification: mechanical — Docs impact: none — covered by Task 7 manifest entry + runbook
- [x] 5. [parallel] Master-merge emission: two lanes, both mechanical —
  (a) splice in `git-hooks/post-commit` for local commits landing on master;
  (b) auditor git-scan backfill (Task 12 consumes this lib function, defined here)
  deriving `merged` events with SHA from `git log origin/master` — the GUARANTEED
  lane, since squash-merges via `gh pr merge` never fire local hooks.
  SHA→ASK ATTRIBUTION RULE (review round 1 — without it the per-ask log files
  cannot be written; constraint 10's model): key-resolution path is
  SHA → plan-slug → plan-header `ask-id:` (Task 10 convention) → per-ask log
  file. Plan-slug resolves from (1) a `plan: <slug>` token in the squash-commit
  subject/body — one-line PR/squash-body convention added to
  `adapters/claude-code/doctrine/git.md` in this task — with (2) fallback: the
  commit's diff touches `docs/plans/<slug>.md` or that plan's evidence dir.
  Multi-match tie-break (review round 2): when one commit's diff touches MORE
  THAN ONE plan's files, the fallback emits a `merged` event per matched ask —
  never guesses a single winner (the repo+sha natural key keeps each per-ask
  log to exactly one event).
  Commits with no resolvable plan-slug are SKIPPED (routine non-plan commits are
  not noise-orphaned). Multi-repo scan set: the auditor iterates the repo roots
  from `neural-lace/workstreams-ui/config/projects.js` (per-machine
  `config/projects.json` carries the real absolute roots), not just this repo —
  Verification: mechanical — Docs impact: attribution rule in runbook + one line
  in `doctrine/git.md`; splice covered by Task 7 manifest entry
- [x] 6. [parallel] Plan-amendment + plan-completion emission splices:
  (a) `hooks/plan-lifecycle.sh` detects newly-introduced task lines /
  scope-section edits on ACTIVE plans (reuse `plan-edit-validator.sh`'s existing
  new-task-line parse) and emits `plan_amended` ("+task 12", scope delta summary);
  (b) the SIXTH emission lane (review round 1 — the ask lifecycle's mechanical
  exit begins here): `plan_completed` emitted from `scripts/close-plan.sh`'s
  successful-close path — reached BOTH via the wired `plan-auto-closure.sh`
  PostToolUse hook (verified 2026-07-10: `settings.json.template` PostToolUse
  Edit|Write → `bash ~/.claude/hooks/plan-auto-closure.sh`, which invokes
  `close-plan.sh close <slug> --auto`) AND via manual `close-plan.sh close` runs,
  so every closure lane emits. Task 12's auditor derives ask-done from it —
  Verification: mechanical — Docs impact: none — covered by Task 7 manifest entry
- [x] 7. [serial] Manifest + review closure for the writer family: one
  `manifest.json` entry (`id: progress-log`, `kind: writer`, `honest_status`
  naming EVERY splice site verbatim — the `session-heartbeat` entry is the
  template), doctor `--quick` stays GREEN, and a **mandatory harness-reviewer
  pass over Tasks 1, 3–6 splice diffs** with findings fixed — Verification:
  mechanical — Docs impact: manifest entry IS the doc; regen via manifest tooling,
  never hand-drift (MANIFEST-NEEDS-YOU-DRIFT-01 lesson)
- [x] 8. [parallel] Ask registry lib: `scripts/ask-registry.sh`
  (register/attach-session/link-plan/set-status/merge/override-project) writing
  `~/.claude/state/ask-registry.jsonl` (sketch §4 schema incl. `{user, machine,
  repo, project}` provenance; project defaulted via
  `neural-lace/workstreams-ui/config/projects.js` mapping; status vocabulary
  `active | done | dismissed | merged` — `set-status`/`merge` are called by BOTH
  the auditor (mechanical completion, Task 12) and the UI lifecycle endpoint
  (operator override, Tasks 11/13), the two exit paths constraint 7 requires;
  every status change appends a record, none rewrites history) + best-effort
  in-repo mirror append (`docs/asks/ask-registry.jsonl` in the ask's repo, path
  resolved via `nl_main_checkout_root` per constraint 11 — never a worktree;
  `--self-test` gains a from-worktree fixture) + summarizer:
  heuristic first (first sentence, ≤140 chars, markdown-stripped) with optional
  `claude -p` haiku-tier upgrade behind `ASK_SUMMARIZER=haiku` (async,
  best-effort, never blocks capture; Fable never used — cheap-model-only by
  design) + verbatim ref (transcript path + prompt offset) + `--self-test`
  (sandboxed) — Verification: mechanical — Docs impact: registry section in runbook
- [x] 9. [serial] Automatic capture splices: (a) first operator prompt of a session
  registers the ask — one-line splice in the already-wired UserPromptSubmit hook
  `hooks/workstreams-read.sh` (prompt text from the hook's stdin JSON; first-prompt
  guard via a per-session marker); (b) session-attach on resume/spawn — splice in
  `hooks/session-start-digest.sh` beside the existing heartbeat splice (lines
  ~1065–1080), resolving origin-session + resume chains to the existing ask node.
  ZERO new settings entries (SessionStart 8/8 cap). Harness-reviewer mandatory —
  Verification: full — Docs impact: capture flow in runbook + manifest entry update
  **Prove it works:**
  1. Install to live `~/.claude` (repo-first, then `install.sh` — never hand-edit live)
  2. Start a genuinely NEW Claude Code session in any repo; type a real opening request
  3. `tail -1 ~/.claude/state/ask-registry.jsonl` — entry exists: summary ≤140 chars, verbatim ref resolves, correct repo/project, `origin_session` set
  4. Resume that session; confirm NO duplicate ask; session-attach recorded
  5. **INVARIANT (not point-in-time):** doctor predicate from Task 17 counts trailing-24h sessions lacking a registered ask — must be 0 on every future doctor run, so regressions surface without anyone re-testing by hand
  **Wire checks:**
  - `adapters/claude-code/hooks/workstreams-read.sh` splice → `adapters/claude-code/scripts/ask-registry.sh` `register`
  - `adapters/claude-code/hooks/session-start-digest.sh` splice → `adapters/claude-code/scripts/ask-registry.sh` `attach-session`
  - `adapters/claude-code/scripts/ask-registry.sh` → `progress-log.sh` `emit` (`ask_registered`, `session_attached` events)
  **Integration points:**
  - UserPromptSubmit stdin JSON carries the prompt text — builder verifies the field name against a live hook invocation before relying on it
  - Sub-agent / builder / spawned-worktree sessions must NOT register new asks. The guard's MECHANICAL PREDICATE (review round 1 — "guard on session type" named no signal): a session is classified SPAWNED when (a) its cwd resolves inside a `.claude/worktrees/` pool — the layout `spawn-worktree.sh` itself creates (`$MAIN/.claude/worktrees/<slug>`) and the desktop app / `--worktree` flag also use — OR (b) a Task 3 dispatch-provenance marker matches the session's worktree path. NO spawn-time marker exists today (verified 2026-07-10: neither `spawn-worktree.sh` nor `nl.sh` writes one) — Task 3 creates it, hence the Task 3 → Task 9 serialization in the dispatch comment. Spawned sessions ATTACH to the dispatching ask via the marker instead of registering. The classification function lives in `hooks/lib/progress-log-lib.sh` and is the SAME function Task 17(c)'s doctor predicate filters by — population parity by construction, never a re-derivation. Prove-it addition: dispatch a real worktree builder → NO new registry entry appears; the child session shows attached to the dispatching ask
- [x] 10. [serial] Plan↔ask linkage convention: one line in
  `adapters/claude-code/doctrine/planning.md` ("plan headers record `ask-id:`;
  plan creation back-links the registry"), `ask-id:` field + comment block in
  `adapters/claude-code/templates/plan-template.md`, `--ask-id` flag in
  `scripts/start-plan.sh`, `plan-reviewer.sh` WARN (never block) when an ACTIVE
  v2 plan lacks the field, and BACKFILL of this plan's own
  `ask-20260710-workstreams-rebuild` entry (self-demonstrating). Tier-2 decision
  record `docs/decisions/06x-ask-rooted-workstreams-p1.md` (next free number)
  lands in the same commit — Verification: mechanical — Docs impact: doctrine
  line + template field + decision record (that IS the delta)
- [x] 11. [serial] Server read surface: `GET /api/asks` (landing payload: project
  groups → ask cards with summary, activity ts, plan progress counts, waiting
  count, drift badges; accepts a `status` filter and DEFAULTS to `status:active`,
  returning done/dismissed/merged asks as a separate `completed` group the UI
  collapses — review round 1) and `GET /api/ask/<id>` (full log narrative,
  per-task plan
  rows with evidence links, waiting items with §3 context blocks or the visible
  "context missing — session violated §3" defect form — the form is never
  terminal (constraint 9): it carries the violation notice + an ABSOLUTE link to
  the raw `NEEDS-YOU.md` entry + the source-session id with copy affordance —
  artifacts, sessions with
  lineage edges) + the ONE lifecycle write endpoint (review round 1):
  `POST /api/ask/<id>/lifecycle` (done/dismiss/reopen/merge) delegating to
  `ask-registry.sh set-status`/`merge` — the operator-override exit path
  constraint 7 requires + `server/payload-schema.js`: the machine-checked landing schema
  — an ALLOWLIST of fields; any field carrying gate/hook identifiers or any
  relative href fails `server.selftest.js`. Plan drill-down links resolve through
  the EXISTING `/api/doc` + `/api/doc/open` (no new link handling — ux-review
  amendment 6). Writes for to-do/backlog land in Tasks 14/15; the ask-lifecycle
  write lands HERE — Verification:
  full — Docs impact: API section in `neural-lace/workstreams-ui/README.md`
  **Prove it works:**
  1. With ≥2 real asks registered (Task 9 live), `curl http://127.0.0.1:7733/api/asks` — grouped by project via `config/projects.js`, newest activity first
  2. `curl http://127.0.0.1:7733/api/ask/<id>` — log narrative chronological; waiting item shows its §3 block; a deliberately context-less fixture item renders the defect form, never a bare ID
  3. `node neural-lace/workstreams-ui/server/server.selftest.js` — PASS including two NEW negative fixtures: payload with a gate identifier field → FAIL; payload with a relative href → FAIL
  4. **INVARIANT:** the schema check runs inside the standing self-test suite (doctor-invoked), so a future endpoint change that leaks telemetry or relative links fails CI-of-record, not operator eyes
  **Wire checks:**
  - `neural-lace/workstreams-ui/server/server.js` `/api/asks` → `neural-lace/workstreams-ui/server/payload-schema.js` `validateLanding`
  - `neural-lace/workstreams-ui/server/server.js` `/api/ask` → `progress-logs` reader + `ask-registry.jsonl` reader
  - `neural-lace/workstreams-ui/server/server.selftest.js` → `payload-schema.js` negative fixtures
  - plan link field → `neural-lace/workstreams-ui/server/server.js` `/api/doc` resolver
  **Integration points:**
  - Waiting items parse `NEEDS-YOU.md` via the same shape `scripts/needs-you.sh` renders — parser fixture pinned against `needs-you.sh --self-test` output, not a hand-written sample
  - Heartbeats (`session-heartbeat.sh` files) supply live/stalled session states — reuse `hooks/lib/session-heartbeat-lib.sh` classification, don't re-derive
- [x] 12. [serial] Background auditor + drift badges: new `server/auditor.js`
  reusing `server/derive-cache.js` plumbing on a RELAXED cadence (default 120s,
  env-tunable; never on the landing request path) comparing the log against
  ground truth — plan checkboxes (done), heartbeats + dispatch records (in
  flight; §2 law 4: in-progress is derived, never declared), NEEDS-YOU parse
  (waiting; also drives To-Do pointer auto-check), `git log origin/master`
  (merges; backfills missed `merged` events per Task 5b) — and attaching drift
  badges to exactly the divergent item. Includes the §8-3 count reconciliation:
  ledger-parsed open items vs rendered waiting items must be equal, else a drift
  badge + a diagnostics-tab detail (never a landing-page banner — anti-noise).
  DIVERGENCE-CLASS TABLE (review round 1 — backfill vs badge is decided PER
  CLASS, never direction-blind; the authoritative side is stated per class):
  | Divergence | Authoritative side | Auditor action |
  |---|---|---|
  | checkbox `[x]`, no `task_done` event (truth ahead of log) | plan file | BACKFILL `task_done` with `emitter=auditor` — heals, no permanent badge |
  | master SHA, no `merged` event (truth ahead of log) | git | BACKFILL `merged` (Task 5b lane) |
  | NEEDS-YOU item resolved, pointer unchecked (truth ahead of log) | ledger file | derive resolution → pointer auto-check |
  | all linked plans terminal, ask still `active` (truth ahead of log) | plan Status | set ask `done` via `ask-registry.sh set-status`, `emitter=auditor` — the mechanical ask exit (constraint 7) |
  | `task_done` event, checkbox unflipped (log ahead of truth) | plan file | BADGE the item — never un-emit, never flip (constraint 6) |
  | `task_started`/`waiting_on_operator` with no matching ground truth (log ahead of truth) | dispatch records / ledger | BADGE |
  | event with `provenance:unknown` emitter (no oracle) | — | BADGE + UI de-emphasis (constraint 10) |
  Every drift badge carries a divergence-detail ref: CLICKING a badge opens its
  divergence detail (popover or deep-link into the diagnostics tab) — badges are
  never unexplained noise (constraint 9) —
  Verification: full — Docs impact: auditor cadence + drift taxonomy in runbook
  **Prove it works:**
  1. Seed both directions of a fixture divergence: (a) mark a sandbox plan task `- [x]` via the verifier flow but delete the log event → within one cadence the auditor BACKFILLS `task_done` with `emitter=auditor` (truth-ahead-of-log HEALS — no permanent badge, per the divergence table); (b) inject a `task_done` event whose checkbox is unflipped → the item wears a drift badge, and clicking the badge opens the divergence detail
  2. Resolve a NEEDS-YOU fixture item directly in the file (bypassing the script) → pointer item in My To-Do auto-checks within one cadence
  3. Merge a sandbox branch to a fixture master → `merged` event backfilled with SHA
  4. `curl /api/asks` during all of the above — landing latency unaffected (auditor is off-path; assert response time in selftest)
  5. **INVARIANT:** reconciliation runs every cadence forever — a future NEEDS-YOU format change that breaks the parser produces a visible count-mismatch badge, not silent wrongness
  **Wire checks:**
  - `neural-lace/workstreams-ui/server/auditor.js` → `neural-lace/workstreams-ui/server/derive-cache.js` (reused oracle plumbing)
  - `neural-lace/workstreams-ui/server/auditor.js` `git log` scan → `progress-log.sh` `emit` backfill (Task 5b lib)
  - `neural-lace/workstreams-ui/server/server.js` drift fields → `neural-lace/workstreams-ui/server/auditor.js` published state
  **Integration points:**
  - `server/reconciler.js` (tree-state comparison) stays as-is for the Harness Health tab; auditor.js is a SIBLING, not a replacement — no shared mutable state
  - Heartbeat reap (master `02ff2f3`) already bounds the session set the auditor reads
- [x] 13. [serial] UI landing — ask tree: project sections (collapsible), ask cards
  (summary + verbatim-one-click, progress narrative excerpt, plan progress bar +
  live-doc hyperlink, waiting count, drift badges inline), shallow-first with plan
  drill-down (per-task rows: done/in-flight/not-started with evidence links);
  SESSIONS list with spawn-lineage edges where provenance exists, flat grouping
  where not (never a lost session); waiting items name + link their source session
  — includes the TIMEBOXED SPIKE (≤2h) on a desktop-app URL scheme, with the
  copy-button fallback shipped regardless of spike outcome.
  Review round 1 additions, all binding:
  - ASK LIFECYCLE AFFORDANCES: each card carries done/dismiss (and merge, per
    sketch §4) actions calling Task 11's lifecycle endpoint, with success
    feedback + brief undo (constraint 9); the landing renders `status:active`
    by default with done/dismissed/merged asks behind a COLLAPSED "completed"
    group — the operator-override half of the ask exit (constraint 7; the
    mechanical half is Task 12's derivation).
  - COMPLETED-GROUP HEADER (review round 2): the collapsed group's header
    carries a count + newest-completed recency ("Completed (N · newest <age>)")
    so a Task 12 mechanical auto-move is visible on the next glance — no
    banner or toast (anti-noise).
  - MULTI-PLAN CARDS (review round 2): when an ask's `plan_slugs[]` has >1
    entry, the card renders ONE aggregate progress bar (task counts summed
    across linked plans) with one live-doc link per plan, and the drill-down
    groups per-task rows by plan. Chosen over stacked per-plan bars because it
    reuses the existing single-bar card and per-task drill-down unchanged and
    matches Task 12's all-linked-plans-terminal derivation (the cheaper fit to
    this plan's structure).
  - DRILL-DOWN SIGNIFIER: an explicit control beside the plan bar (chevron +
    "N tasks" link); the bar is never the sole click target and may also be
    clickable with hover/cursor signifiers (constraint 9).
  - Drift badges click through to their divergence detail (Task 12).
  - The §3-defect form renders with its recovery links (Task 11 payload).
  - Session-id copy button microcopy: "copy session id — resume with
    `claude --resume <id>`".
  - Four UI states per constraint 8; a11y per constraint 9.
  New `web/asks.js` +
  `web/app.css` additions; `web/app.js` becomes shell/router. HARD CONSTRAINT:
  anti-noise law — zero gate/hook identifiers rendered; all links absolute —
  Verification: full — Docs impact: `neural-lace/workstreams-ui/README.md` IA section rewrite
  **Prove it works:**
  1. Open `http://127.0.0.1:7733/` cold with ≥2 projects' real asks — tree renders grouped, newest first
  2. Click the drill-down chevron / "N tasks" link (or the plan bar) → drill-down rows match the plan file's actual checkboxes (spot-check against `docs/plans/<slug>.md` via the `/api/doc` link on the same card)
  3. Click the verbatim affordance → original ask text displays
  4. Click a waiting item's session link/copy → session id lands on the clipboard with the resume microcopy shown (or deep-link opens, if the spike succeeded)
  5. Grep the rendered DOM (`web/cockpit.selftest.js` extension) for a denylist of gate/hook identifier patterns — zero hits INCLUDING state/empty/error copy; all `href`/path attributes absolute
  6. Dismiss a fixture ask → success feedback + undo appear; card leaves the active landing and shows under the collapsed completed group; reload → persists (registry status record appended)
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/index.html` → `neural-lace/workstreams-ui/web/asks.js` include
  - `neural-lace/workstreams-ui/web/asks.js` `fetch('/api/asks')` → `neural-lace/workstreams-ui/server/server.js` route
  - `neural-lace/workstreams-ui/web/asks.js` lifecycle actions → `POST /api/ask/<id>/lifecycle` (Task 11) → `ask-registry.sh set-status`/`merge`
  - `neural-lace/workstreams-ui/web/asks.js` plan link → `/api/doc` + `/api/doc/open` handlers in `server/server.js`
  **Integration points:**
  - Old conv-tree card/popup patterns salvaged from git history `952c9d6`/`e7393bc` (read-only reference — attic code not resurrected wholesale)
  - Layout per Q9 — the ux-designer round-1 ruling LANDED 2026-07-10 and is BINDING (encoded in Task 16): To-Do at the top of a persistent right sidebar with independent scroll + header count, Backlog collapsed below it (top-N by tier), ask tree as the main column; below ~1200px the sidebar stacks under the tree rather than compressing cards; Harness Health as a tab (Team tab hidden in P1)
- [x] 14. [parallel] My To-Do pane: new `web/todo.js` + `GET/POST /api/todo`
  reading/writing `docs/operator-todo.md` (NEW file: operator free-form section +
  marker-delimited auto-pointer section) — operator items: add/edit/check freely
  from the UI; pointer items: rendered with their §3 context, click navigates to
  the ask's waiting item (P1 = navigate; P2 = answer in place). Review round 1:
  pointer items are visually DISTINCT from editable items — never a checkbox
  lookalike: a lock/auto glyph, `aria-disabled`, tooltip "resolves when you
  answer the underlying item — click to go there"; navigation is the pointer
  item's primary affordance, and auto-check comes from Task 12 derivation
  (constraint 9: derived controls distinct from editable ones). PLUS an operator
  OVERRIDE: a dismiss/mark-handled action on any pointer item, writing the same
  durable file with an operator-override flag the auditor respects (never
  fights) — the escape hatch when the NEEDS-YOU parse breaks or a resolution is
  undetectable (constraint 7). All to-do writes show success feedback + mistake
  recovery; four UI states per constraint 8 (My To-Do empty state is POSITIVE +
  carries the add affordance) —
  writes go to the durable file, never a parallel store; anti-noise +
  absolute-links constraints apply — Verification: full — Docs impact:
  `docs/operator-todo.md` self-documenting header + runbook section
  **Prove it works:**
  1. Add "buy more coffee" via the pane → `docs/operator-todo.md` contains it; reload → persists
  2. Trigger a real `needs-you.sh add` from a session → pointer item appears WITHOUT any UI action
  3. Resolve the underlying item → pointer auto-checks within one auditor cadence; operator items untouched
  4. Edit the file by hand in an editor → pane reflects it on refresh (file is truth, UI is a view)
  5. Mark-handled a pointer item whose underlying resolution the auditor cannot see → the durable file carries the operator-override flag; the next auditor cadence does NOT revert it
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/todo.js` `fetch('/api/todo')` → `neural-lace/workstreams-ui/server/server.js` todo routes
  - `neural-lace/workstreams-ui/server/server.js` POST handler → `docs/operator-todo.md` marker-safe writer
  - `adapters/claude-code/scripts/needs-you.sh` splice (Task 4) → `docs/operator-todo.md` auto-section
  **Integration points:**
  - Concurrent writes (session appends pointer while operator edits) — marker-delimited sections + atomic rewrite of only the touched section; fixture in selftest
- [x] 15. [parallel] Backlog pane: new `web/backlog.js` + endpoints — render
  `docs/backlog.md` (compact top-N by tier, collapsible, full list one click);
  ADD form appending a well-formed row (both Claude and operator can add —
  operator's rows follow the same shape the O.9 triage loop parses); disposition
  buttons SCHEDULE / DEMOTE / FOLD / WONTFIX writing the exact disposition
  vocabulary the existing loop understands. Review round 1 — disposition UX
  (constraint 9): a dispositioned row visibly transitions (greys/moves under its
  disposition word) with a brief undo; WONTFIX — four adjacent one-click durable
  writes need misclick protection — gets a confirm instead of undo; the add form
  shows success feedback; four UI states per constraint 8 —
  writes to the real file, no
  parallel store; anti-noise + absolute-links constraints apply — Verification:
  full — Docs impact: one line in `docs/backlog.md` header noting the UI write path
  **Prove it works:**
  1. Open the pane with the REAL (hundreds-of-rows) backlog — renders compact without jank; full list opens
  2. Add a row via the form → `git diff docs/backlog.md` shows one well-formed row in the right section
  3. Click WONTFIX on a fixture row → a confirm appears; after confirming, the row visibly transitions and the file carries the disposition in loop-parseable form (verify against the O.9 loop's parser, not by eyeball); a non-destructive disposition (e.g. DEMOTE) offers undo → undo restores the row unchanged
  4. Reload → both changes persist; no other row disturbed
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/backlog.js` → `neural-lace/workstreams-ui/server/server.js` backlog routes
  - `neural-lace/workstreams-ui/server/server.js` disposition handler → `docs/backlog.md` row-scoped writer
  **Integration points:**
  - O.9 triage loop parser is the contract — its fixture corpus is the golden oracle for rows/dispositions this UI writes
- [x] 16. [serial] Layout integration + Harness Health demotion: sidebar assembly
  per the ux-designer round-1 ruling (LANDED 2026-07-10, binding): To-Do at the
  top of a persistent right sidebar with INDEPENDENT SCROLL + a header count,
  Backlog collapsed below it (top-N by tier), ask tree as the main column;
  below ~1200px the sidebar STACKS UNDER the tree rather than compressing cards.
  Landing route serves the ask tree (default `status:active`, completed group
  collapsed), and the six wave-O panes
  move VERBATIM to a Harness Health tab (operator condition: they stay only if
  they work and stay quiet — a pane that errors or spams gets a follow-up backlog
  row, not landing space). The TEAM TAB IS HIDDEN in P1 (review round 1 — an
  empty shell tab is a dead-end click that reads as breakage): no nav entry
  ships; payload provenance fields still ship, so P3 adds a tab, not a schema.
  Diagnostics (reconciler internals, drift detail)
  live here too — Verification: full — Docs impact: README IA section final pass
  **Prove it works:**
  1. Open `/` → ask tree + sidebar; NO six-question panes on landing; NO Team tab anywhere
  2. Open the Harness Health tab → all six panes function (each returns data or an honest rc-carried error, per the wave-O contract)
  3. Resize to a laptop viewport → glance loop (tree + to-do + backlog) fits one viewport per Q9 rationale; below ~1200px the sidebar stacks under the tree
  4. `web/cockpit.selftest.js` extension asserts landing DOM contains zero pane-family identifiers (anti-noise, mechanized) + a COLOR-ONLY-SIGNAL assertion (every badge/state indicator also carries text — WCAG 1.4.1) + a REAL-BUTTON assertion (interactive elements in new DOM are `button`/`a`, never clickable divs) per constraint 9
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/index.html` tab shell → `neural-lace/workstreams-ui/web/app.js` router
  - Harness Health tab → existing `/api/pane/*` routes in `neural-lace/workstreams-ui/server/server.js` (unchanged)
  **Integration points:**
  - Existing autostart/launcher (`scripts/launch-gui.ps1`, heartbeat/reconciler registrations) keep working — port + health contract unchanged
- [x] 17. [serial] Mechanized metrics + doctor wiring (sketch §8): (a) anti-noise
  schema check + absolute-href check running in `server.selftest.js` AND surfaced
  as a doctor predicate (extend the existing `obs-cockpit-fresh` doctor check);
  (b) waiting-on-you count reconciliation live (Task 12) with a doctor-visible
  failure mode; (c) capture-completeness predicate (Task 9 invariant: trailing-24h
  sessions all have asks) — counts ONLY operator-origin sessions, classified by
  the SAME shared predicate function Task 9's guard uses
  (`hooks/lib/progress-log-lib.sh`), never a re-derivation: population parity is
  what keeps the predicate from false-firing RED on every orchestrated day
  (review round 1; general rule: every doctor predicate names its population
  filter identically to the mechanism it audits); (d) the 2-week operator
  check-in as a scheduled task
  (calendar mechanism, not vibes — model: `install-weekly-hygiene-task.ps1`)
  that ASKS the cold-start question — Verification: mechanical — Docs impact:
  runbook "metrics + falsifiers" section mirroring sketch §8
- [x] 18. [serial] Acceptance: end-user-advocate runtime pass over the Acceptance
  Scenarios below + the OPERATOR cold-start walkthrough — the operator (not
  Claude) cold-starts a real ask and answers the four questions in <60s without
  opening a transcript; result recorded in this plan's completion report with the
  timing. This is the §7 usefulness bar; component greens do not substitute —
  Verification: full — Docs impact: completion report + evidence artifacts
  **Prove it works:**
  1. Advocate executes every scenario below via browser automation; JSON artifacts land under `.claude/state/acceptance/ask-rooted-workstreams-p1/`
  2. Operator walkthrough: pick an ask the operator hasn't looked at in ≥24h; time the four answers AGAINST THE REAL FULL REGISTRY at true volume (never a trimmed fixture set — ux round 1: the metric must reflect scanning at real scale); <60s → PASS, else the gap is named and fixed before closure
  3. Task 17(d) scheduled check-in verified registered (`schtasks /Query`), so the metric re-fires at +2 weeks by mechanism
  **Wire checks:**
  - n/a — acceptance task exercises the assembled surface end-to-end; no new code chain of its own to trace
  **Integration points:**
  - `product-acceptance-gate.sh` Stop hook consumes the artifacts — plan is not closable without them

## Files to Modify/Create

Create:
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — writer lib (pl_emit/pl_path_for/dedup/sandbox)
- `adapters/claude-code/scripts/progress-log.sh` — CLI verbs + `--self-test` (mirrors session-heartbeat split)
- `adapters/claude-code/scripts/ask-registry.sh` — registry CLI + summarizer + mirror + `--self-test`
- `adapters/claude-code/scripts/dispatch-provenance.sh` — DISPATCH-PROVENANCE MARKER writer CLI + write-time prune + `--self-test` (the Task 3 marker Task 9's classification guard consumes). Scope-table omission corrected 2026-07-14: Task 3 mandates this marker and the file was created for it, but the table never named the script — surfaced by `scope-enforcement-gate` on the splice-review fix commit.
- `adapters/claude-code/hooks/lib/merge-scan-lib.sh` — SHA -> ask attribution + `merged` progress-log emission lib (Task 5b, the auditor's GUARANTEED merge-backfill lane); own file header names this plan/task explicitly. Same class of scope-table omission as the dispatch-provenance.sh line above, corrected 2026-07-16: surfaced by `scope-enforcement-gate` on the incremental-cursor production-defect fix commit (auditor's 120s scan-repo cycle was re-scanning the same bounded window forever instead of converging — see the file's own "INCREMENTAL CURSOR" header section).
- `adapters/claude-code/schemas/progress-log-event.schema.json` — versioned event schema
- `neural-lace/workstreams-ui/server/auditor.js` — background reconciler (derive-cache reuse, relaxed cadence)
- `neural-lace/workstreams-ui/server/payload-schema.js` — landing allowlist schema + href checks
- `neural-lace/workstreams-ui/web/asks.js`, `web/todo.js`, `web/backlog.js` — new UI modules (file-disjoint by design)
- `docs/operator-todo.md` — the to-do file (operator + auto sections)
- `docs/asks/ask-registry.jsonl` — in-repo registry mirror
- `docs/runbooks/ask-workstreams.md` — runbook (rung-4 requirement)
- `docs/decisions/06x-ask-rooted-workstreams-p1.md` — consolidated Tier-2 decision record

Modify:
- `adapters/claude-code/hooks/plan-lifecycle.sh` — verifier-flip + plan-amendment emission splices
- `adapters/claude-code/scripts/close-plan.sh` — plan_completed emission splice (Task 6b; fires on auto-closure via the wired `plan-auto-closure.sh` AND on manual closes)
- `adapters/claude-code/hooks/workstreams-emit.sh` — dispatch/spawn emission splices + dispatch-provenance marker write (Task 3)
- `adapters/claude-code/doctrine/git.md` — one line: `plan: <slug>` token in squash/PR bodies (Task 5 attribution)
- `adapters/claude-code/scripts/needs-you.sh` — waiting_on_operator emission + to-do pointer append (via `nl_main_checkout_root`)
- `adapters/claude-code/git-hooks/post-commit` — local master-merge emission splice
- `adapters/claude-code/hooks/workstreams-read.sh` — first-prompt ask capture splice
- `adapters/claude-code/hooks/session-start-digest.sh` — session-attach splice (beside heartbeat splice)
- `adapters/claude-code/manifest.json` — `progress-log` + `ask-registry` writer entries (via regen tooling)
- `adapters/claude-code/hooks/harness-doctor.sh` — predicates (anti-noise, capture-completeness, reconciliation)
- `adapters/claude-code/doctrine/planning.md` — ask-id linkage line
- `adapters/claude-code/templates/plan-template.md` — `ask-id:` header field
- `adapters/claude-code/scripts/start-plan.sh` — `--ask-id` flag
- `adapters/claude-code/hooks/plan-reviewer.sh` — WARN on missing ask-id (never block)
- `neural-lace/workstreams-ui/server/server.js` — new routes + auditor mount
- `neural-lace/workstreams-ui/server/server.selftest.js` — schema/negative fixtures + new-route coverage
- `neural-lace/workstreams-ui/web/index.html`, `neural-lace/workstreams-ui/web/app.js`, `neural-lace/workstreams-ui/web/app.css` — shell/router/layout
- `neural-lace/workstreams-ui/web/cockpit.selftest.js` — landing DOM anti-noise/absolute-href assertions
- `neural-lace/workstreams-ui/README.md` — IA + API docs
- `docs/backlog.md` — header line re UI write path (+ PROGRESS-FIELD-01 cross-ref at completion)

## In-flight scope updates
- 2026-07-17: docs/reviews/2026-07-17-circuit-continuous-building-design-sketch.md — operator-commissioned Circuit continuous-building design pass (v1 + v2 rewrite integrating operator decisions D1-D4); the sketch consumes this plan's ask-registry/cockpit surfaces (Team-tab reserve, provenance fields, payload allowlist) and is committed on its design branch to satisfy the SubagentStop clean-tree gate. Design-record only — no code in this plan's scope is modified.

## Assumptions

- `workstreams-emit.sh` remains wired at PreToolUse `--on-builder-dispatch`/`--on-spawn`, PostToolUse `--on-builder-complete`, SessionStart `--on-session-start` (verified in `settings.json.template` 2026-07-10); its tree-state writes stay as auditor comparison input, per sketch §5.
- `goal-extraction-on-prompt.sh` is a retired shim (verified) — ask capture cannot splice there; `workstreams-read.sh` (UserPromptSubmit, live) is the capture site and its stdin JSON carries the prompt text (builder verifies the exact field before relying on it).
- SessionStart is at its 8/8 cap and Stop at 4/6 (wave-O budget rule §O.0.1-8) — all new behavior is splices, zero new settings entries.
- Squash-merges to master happen via `gh pr merge` remotely, so local git hooks alone cannot see them — the auditor git-scan lane (Task 5b/12) is the guaranteed merge-emission path.
- `plan-lifecycle.sh` (PostToolUse) observes plan-file edits after they land; the fresh-flip vs re-save distinction is resolvable from tool-input JSON or content diff (skeleton task proves this first).
- Server contract as of master `02ff2f3`: port 7733, 127.0.0.1-only, `/api/health` lobotomy self-report, `/api/doc`+`/api/doc/open` link resolver — all inherited unchanged.
- `config/projects.js` supplies repo→project mapping for grouping; operator overrides persist in the registry (sketch §3/§4).
- Repo pins `eol=lf` (2026-07-05); all new writers emit LF; byte-level checks use `od`, not MSYS-filtered tools.
- The harness repo is source of truth: all splices land in `adapters/claude-code/`, deploy via `install.sh`, and are durable only once merged to master.
- `plan-auto-closure.sh` is PostToolUse-wired (Edit|Write) in `settings.json.template` (verified 2026-07-10) and invokes `close-plan.sh close <slug> --auto` — a `plan_completed` splice in `close-plan.sh` therefore fires on BOTH the auto-closure and manual-close lanes (Task 6b).
- `hooks/lib/nl-paths.sh` provides `nl_main_checkout_root`; `needs-you.sh` already resolves its ledger path through it (verified) — the same resolver serves all new durable in-repo writes (constraint 11).
- NO spawn-time marker exists in `spawn-worktree.sh` / `nl.sh` today (verified 2026-07-10) — spawned-session detection rests on the cwd-under-`.claude/worktrees/` predicate plus the Task 3 dispatch-provenance marker this plan CREATES (Task 9).

## Edge Cases

- **Event with unresolvable ask-id** (e.g. verifier flip in a plan whose header lacks `ask-id:` — every pre-existing plan): event lands in the orphan lane keyed by plan-slug; the auditor attaches it retroactively if a linkage appears; the UI shows an "unlinked plan" group rather than dropping progress. Estate-growth safe: old plans never break the surface.
- **Concurrent JSONL appends** (parallel builders flipping tasks simultaneously): single-line O_APPEND writes + event-id dedup; self-test includes a concurrent-append scenario.
- **Duplicate ask on resume/compact**: first-prompt marker + resume-chain attach (Task 9) — a resumed or compact-recovered session attaches, never re-registers.
- **Builder/sub-agent sessions**: never register asks; they attach via dispatch provenance. Mechanical predicate (review round 1): cwd inside a `.claude/worktrees/` pool OR a Task 3 dispatch-provenance marker match — tested in Task 9 with a real worktree dispatch.
- **Legitimate recurrence vs replay** (review round 1): a re-dispatch of a failed task emits a SECOND `task_started` (new session_id in the natural key); a hook replay of the SAME dispatch dedups — Task 2's per-event-type keys distinguish the two, and both are self-test fixtures.
- **Late event on a done/dismissed ask**: the event still lands in the per-ask log; the auditor reopens nothing automatically — the card stays in the completed group wearing a "new activity" indicator; the operator can reopen via the Task 13 lifecycle affordance.
- **Pointer item stuck** (NEEDS-YOU parse broken / resolution undetectable): the operator's dismiss/mark-handled override (Task 14) writes the durable file with an override flag the auditor respects — no derived state ever gates operator attention without a manual exit (constraint 7).
- **Cold-reader-violating waiting item** (missing §3 block): renders as the visible defect form ("context missing — session violated §3"), never a bare ID (sketch §2 law 3).
- **Registry or log file unavailable/corrupt line**: readers skip bad lines and surface a diagnostics-tab count; landing page never 500s on one bad record.
- **Lobotomized server instance** (2026-07-09 incident class): health/lobotomy/restart contract inherited from `02ff2f3`; new endpoints participate in `/api/health` grading (§8-4 invariant).
- **Backlog scale** (hundreds of rows): compact top-N render + on-demand full list; row-scoped writes so a disposition never rewrites the whole file.
- **Operator edits `operator-todo.md` in an editor while the UI is open**: file is truth; marker-delimited section writes; UI refresh reflects the file.
- **Self-test pollution**: every self-test sandboxed under `HARNESS_SELFTEST_DIR`; a T10-style "state written only under sandbox" assertion in each new self-test.
- **First install (no asks yet)**: landing renders an honest empty state with the capture mechanism named, not a blank page.

## Behavioral Contracts

- **Idempotency:** `pl_emit` is idempotent by PER-EVENT-TYPE NATURAL KEY (Task 2 table — e.g. `task_started` includes session_id, so a legitimate re-dispatch is a NEW event while a hook replay dedups; review round 1); re-running any splice, replaying a hook, or auditor backfill racing a live emit produces exactly one logged event per natural key. Registry `register` is idempotent per session-origin; `attach-session` per (ask, session) pair.
- **Performance budget:** each splice adds ≤50ms p95 to its host hook (best-effort subshell, `|| true`, no network); ask capture ≤100ms synchronous (summarizer-upgrade async); auditor runs off the request path on a ≥120s cadence; `GET /api/asks` p95 ≤300ms serving from log+registry reads (no oracle shelling on the landing path — that was the O.4 mistake).
- **Retry semantics:** emissions are fire-and-forget — no splice ever retries or blocks its host (writer semantics, constraint 5). The AUDITOR is the recovery mechanism: any event missed at emit time is backfilled or drift-badged within one cadence. UI writes (to-do/backlog) are synchronous with explicit user-visible failure; no silent retry.
- **Failure modes:** emission failure → host hook unaffected, gap surfaces as auditor drift badge; registry down → sessions run normally, capture-completeness doctor predicate goes RED; auditor down → landing still serves (log is primary), staleness surfaced via the existing freshness header; server down → all writers keep writing files (nothing depends on the UI being alive — the E.6 lesson). Full symptom→diagnosis→fix table in `docs/runbooks/ask-workstreams.md` (Task 1 stub, finalized by Task 17).

## Acceptance Scenarios

### cold-start-ask — the four questions in under 60 seconds

**Slug:** `cold-start-ask`

**User flow:**
1. Open `http://127.0.0.1:7733/` with no prior context on the target ask
2. Locate the ask under its project group; read the card summary
3. Read the progress narrative and plan bar; click drill-down once
4. Read the waiting-on-you item(s) on the card

**Success criteria (prose):** all four answers (what did I ask / what's the plan / how far / what needs me) obtainable in <60s, no transcript opened; every link followed resolves (absolute); plan drill-down matches the live plan file.

**Artifacts to capture:** timed screen recording or stepped screenshots; network log showing only `/api/asks`, `/api/ask/<id>`, `/api/doc` calls; console clean.

### auto-capture-zero-ceremony — a new session's ask appears by itself

**Slug:** `auto-capture-zero-ceremony`

**User flow:**
1. Start a fresh Claude Code session in any repo; type a real request
2. Without any registration action, refresh the landing page

**Success criteria (prose):** the ask appears under the correct project with a readable ≤140-char summary; verbatim original one click away; origin session attached.

**Artifacts to capture:** screenshot of the new card; the registry JSONL tail; capture-completeness doctor predicate output.

### todo-pointer-lifecycle — parked decision arrives and auto-resolves

**Slug:** `todo-pointer-lifecycle`

**User flow:**
1. Have a session append a decision via `needs-you.sh add`
2. Observe My To-Do; click the pointer item; navigate to the ask's waiting item and read its §3 block
3. Resolve the underlying item; observe the pointer

**Success criteria (prose):** pointer appears without UI action, carries §3 context, navigates correctly, and auto-checks within one auditor cadence; operator-created items unaffected throughout.

**Artifacts to capture:** before/after pane screenshots; `docs/operator-todo.md` diff; auditor log line.

### backlog-add-and-disposition — both directions write the real file

**Slug:** `backlog-add-and-disposition`

**User flow:**
1. Add a backlog row via the pane's form
2. Disposition a fixture row via the WONTFIX button
3. Reload; inspect `docs/backlog.md`

**Success criteria (prose):** both writes persist in loop-parseable form in the real file; no adjacent row disturbed; pane renders the full real backlog without jank.

**Artifacts to capture:** `git diff docs/backlog.md`; pane screenshots; O.9 parser check output.

### ask-lifecycle-exit — cards leave the landing when work ends

**Slug:** `ask-lifecycle-exit`

**User flow:**
1. Close a fixture ask's only linked plan through the real closure flow (`close-plan.sh`)
2. Wait one auditor cadence; observe the landing
3. Dismiss a second, planless fixture ask via its card affordance; use undo once; dismiss again

**Success criteria (prose):** the plan-closure ask auto-moves to the collapsed completed group with NO operator action (mechanical exit — `plan_completed` → auditor ask-done); the dismissed ask shows success feedback, undo restores it, the re-dismiss persists across reload (operator exit); the active landing contains neither card afterward.

**Artifacts to capture:** registry JSONL tail (status records incl. `emitter=auditor`); before/after landing screenshots; the `plan_completed` event line.

### anti-noise-landing — telemetry stays off the landing page

**Slug:** `anti-noise-landing`

**User flow:**
1. Open the landing page and the Harness Health tab
2. Run the server + cockpit self-tests

**Success criteria (prose):** landing payload and DOM contain zero gate/hook identifiers and zero relative hrefs (mechanized checks PASS); the six panes function inside their tab only.

**Artifacts to capture:** self-test output; landing payload JSON; DOM assertion output.

## Out-of-scope scenarios

- Answering a decision inline from the surface — P2 by operator decision (sketch §9 Q4); P1 pointer items navigate only.
- Two-operator concurrent use / team view content — P3 (§6); P1 ships provenance fields ONLY; the Team tab itself is HIDDEN until P3 (review round 1 — no empty shell surfaces).
- Desktop-app deep-link guaranteed working — spike only (Q8); the copy-button fallback is the committed path.
- Mobile/phone rendering — desktop-only surfaces per standing operator decision (no-phone-observability).

## Closure Contract

- **Commands that run:** `bash adapters/claude-code/scripts/progress-log.sh --self-test`; `bash adapters/claude-code/scripts/ask-registry.sh --self-test`; `node neural-lace/workstreams-ui/server/server.selftest.js`; `node neural-lace/workstreams-ui/web/cockpit.selftest.js`; `bash adapters/claude-code/hooks/harness-doctor.sh --quick`; advocate runtime pass over the six scenarios; the operator cold-start walkthrough (Task 18).
- **Expected outputs:** every self-test full-PASS with sandboxed state; doctor GREEN including the three new predicates; six scenario artifacts `verdict: PASS`; walkthrough timing <60s recorded in the completion report.
- **On-disk artifact location:** `.claude/state/acceptance/ask-rooted-workstreams-p1/<session-id>-<timestamp>.json` (+ sibling screenshots/logs); structured evidence at `docs/plans/ask-rooted-workstreams-p1-evidence/<task-id>.evidence.json` for mechanical tasks.
- **Done when:** all 18 tasks are task-verifier PASS AND the acceptance artifacts exist with PASS verdicts AND the operator walkthrough is recorded <60s AND doctor `--quick` is GREEN on live `~/.claude` at a master SHA containing this work.

## Testing Strategy

- **Libs/splices (Tasks 1–10):** per-script `--self-test` under `HARNESS_SELFTEST=1` + `HARNESS_SELFTEST_DIR` (concurrency, replay-dedup AND legitimate-recurrence fixtures, orphan lane, unknown-emitter, from-worktree durable-write fixtures, sandbox-only-writes assertions); harness-reviewer pass on every splice diff; `manifest-check.sh` + doctor `--quick` after Task 7; splice hosts' EXISTING self-tests re-run green (no regression in `needs-you.sh --self-test`, `plan-lifecycle` fixtures, `close-plan.sh` fixtures, etc.).
- **Server (Tasks 11–12):** `server.selftest.js` extended — new routes incl. the lifecycle endpoint, payload allowlist with NEGATIVE fixtures (gate-identifier field → FAIL; relative href → FAIL; gate identifier in STATE COPY → FAIL), landing-latency assertion, auditor divergence fixtures (each class in the Task 12 table produces exactly its specified action — backfill classes HEAL, badge classes badge exactly once), count-reconciliation fixture pinned to `needs-you.sh` render output.
- **UI (Tasks 13–16):** `cockpit.selftest.js` extended — DOM anti-noise denylist (incl. state/empty/error copy), absolute-href sweep, empty-state render (per surface, incl. the collapsed completed-group and Backlog-pane empties — review round 2), error-state render (constraint 8), color-only-signal + real-button assertions (constraint 9); live checks in each task's Prove-it-works against the real running server (the user path, not components).
- **Doctor (Task 17):** predicates fail-closed in fixtures (seeded violation → RED) before being trusted GREEN.
- **Acceptance (Task 18):** advocate browser-automation runtime + the human operator walkthrough — the plan-level oracle; no AI-output surface in P1 beyond the optional haiku summarizer, whose live check is one real capture with `ASK_SUMMARIZER=haiku` verifying summary quality + non-blocking failure.

## Walking Skeleton

One event traveling every layer: a task-verifier checkbox flip → `plan-lifecycle.sh` splice → `progress-log.sh emit` → per-ask JSONL → `GET /api/asks` → a landing card rendering "task N verified done." This exercises the emission convention, the log format, the server read, and the UI render before any breadth exists — the exact wires (hook→lib→file→API→DOM) that the integration-vaporware pattern leaves unconnected. First task: 1.

## Decisions Log

Plan-time decide-and-go (all one-revert reversible; consolidated Tier-2 record lands with Task 10):
- **D1 — Log location:** `~/.claude/state/progress-logs/<ask-id>.jsonl` (machine-local; emitting hooks run on this machine; §6 defers sync). Alternative (in-repo) rejected: hooks fire in worktrees/other repos.
- **D2 — Merge emission:** auditor git-scan of `origin/master` is the guaranteed lane; local post-commit splice is additive. Reason: remote squash-merges never fire local hooks — a hook-only design would silently miss most merges.
- **D3 — Capture point:** first UserPromptSubmit (`workstreams-read.sh` splice), not literal SessionStart — the opening ask does not exist yet at SessionStart, and the SessionStart array is capped 8/8. The sketch's "SessionStart machinery" is satisfied in spirit: fully automatic, zero ceremony, zero new settings entries.
- **D4 — Summarizer:** heuristic default + haiku behind `ASK_SUMMARIZER=haiku`, async best-effort. Reason: capture must never block or cost by default; Fable-tier explicitly excluded (model-tiering directive).
- **D5 — UI module split:** new panes as separate files (`asks.js`/`todo.js`/`backlog.js`) with `app.js` as shell — keeps builder tasks file-disjoint for parallel dispatch.
- **D6 — Registry mirror path:** `docs/asks/ask-registry.jsonl` in the ask's repo, append-only, best-effort. Reversible: one directory move.
- **D7 — PROGRESS-FIELD-01:** not absorbed (parts 1–2 out of scope); part-3 end-state delivered here; row gets a cross-ref at completion, per absorb-or-defer discipline.

Review round 1 decide-and-go (2026-07-10; all one-revert reversible):
- **D8 — Merge-SHA attribution (systems Critical):** SHA → plan-slug (`plan: <slug>` squash/PR-body token, one line in `doctrine/git.md`; fallback: commit diff touches the plan file) → plan-header `ask-id:` → per-ask log; unresolvable commits skipped; scan set = projects.js roots. Alternative (orphan-lane every master commit) rejected: floods the orphan lane with routine commits.
- **D9 — Spawned-session detection (systems Major):** cwd-under-`.claude/worktrees/` predicate + Task 3 dispatch-provenance marker (verified: no marker exists today — this plan creates it). Alternative (env var through the spawn chain) rejected: separately-launched `claude` processes don't reliably inherit a dispatcher env.
- **D10 — Ask lifecycle (both reviews Critical/Major):** statuses `active|done|dismissed|merged`; mechanical exit = `plan_completed` (close-plan.sh splice) → auditor derives ask-done when all linked plans terminal; operator exit = card done/dismiss/merge affordances via `POST /api/ask/<id>/lifecycle`; landing defaults `status:active` with a collapsed completed group.
- **D11 — Team tab hidden in P1 (ux Important):** no nav entry; provenance fields still ship in payloads. Alternative (honest empty state) rejected: a tab with no function is a dead-end click either way; hiding is one flag.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept; all five emission entry points + two capture points resolved to live wired hooks/scripts (verified against `settings.json.template` hook dump 2026-07-10); one planned entry point (`goal-extraction-on-prompt.sh`) found RETIRED and replaced with `workstreams-read.sh` (D3).
- S2 (Existing-Code-Claim Verification): swept; verified against files — server routes (`/api/health`, `/api/pane/*`, `/api/doc`, `/api/doc/open` in `server/server.js`), heartbeat splice sites (`session-start-digest.sh` ~1065/1080), `needs-you.sh add` contract + cold-reader lint, `plan-edit-validator.sh` flip authorization, manifest `session-heartbeat` honest_status splice convention, `workstreams-emit.sh` live (not attic'd), 8/8 cap comment in `ensure-cockpit.sh`.
- S3 (Cross-Section Consistency): swept; "auditor is recovery, emit is fire-and-forget" consistent across Constraints/Tasks 5,12/Behavioral Contracts; "no new settings entries" consistent across Constraint 3/Tasks 3,9/Assumptions; anti-noise stated once as law, referenced per UI task.
- S4 (Numeric-Parameter Sweep): swept for params [port 7733, auditor cadence 120s, summary ≤140 chars, splice budget 50ms, landing p95 300ms, <60s bar, cap 8/8 + 4/6, target 2026-07-24] — each appears with one value everywhere.
- S5 (Scope-vs-Analysis Check): swept; all Add/Modify verbs in Tasks/Files checked against Scope OUT — no task builds inline answering, team aggregation, deep-link commitment, or attic resurrection; the deep-link SPIKE in Task 13 is explicitly bounded and non-committal.
- S6 (Review round 1 claim sweep, 2026-07-10): every mechanism the amendments cite re-verified against the repo — `plan-auto-closure.sh` wired PostToolUse Edit|Write in `settings.json.template` (~line 330) invoking `close-plan.sh close <slug> --auto` (both files exist); `nl_main_checkout_root` defined in `hooks/lib/nl-paths.sh` and already used by `needs-you.sh` (~lines 149/207); NO spawn-time marker in `spawn-worktree.sh`/`nl.sh` (verified ABSENT — Task 3 creates one; the worktree layout is `$MAIN/.claude/worktrees/<slug>`); `web/app.js` global state invariant + WCAG 2.2 AA header comment present, and its state copy DOES embed oracle identifiers (must not be inherited verbatim, constraint 8); `config/projects.js` is the two-layer project→root resolver (per-machine `projects.json` carries real roots); `doctrine/git.md` exists for the Task 5 convention line. New numeric param from round 1: sidebar stack breakpoint ~1200px (single occurrence swept into S4's parameter set).

## Definition of Done

- [ ] All tasks checked off (task-verifier only)
- [ ] All tests pass (self-tests sandboxed; server + cockpit selftests; doctor GREEN)
- [ ] Linting/formatting clean
- [ ] Acceptance artifacts PASS + operator walkthrough <60s recorded
- [ ] Merged to master with SHA(s) cited; live `~/.claude` installed from master
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file (incl. all decide-and-go decisions for one-place operator review)

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
Within 60 seconds of opening the landing page, the operator answers what-did-I-ask / what's-the-plan / how-far / what-needs-me for any active ask without opening a transcript — measured at Task 18 and re-measured by the mechanized 2-week check-in (Task 17d). Falsifier: the operator is observed scroll-hunting transcripts again (sketch §8-1).

### 2. End-to-end trace with a concrete example
Operator types "rebuild the workstreams view" in a new session → `workstreams-read.sh` splice calls `ask-registry.sh register` → entry `ask-20260710-workstreams-rebuild` (summary heuristic, verbatim ref = transcript path+offset, project `neural-lace` via projects.js) + `ask_registered` event in `~/.claude/state/progress-logs/ask-20260710-workstreams-rebuild.jsonl`. Plan created with `start-plan.sh --ask-id ask-20260710-workstreams-rebuild` → header line + registry `plan_slugs[]` back-link. Orchestrator dispatches builder on task 3 → `workstreams-emit.sh --on-builder-dispatch` splice emits `task_started {plan_slug, task_id:3, session_id:child}`. Builder finishes; task-verifier flips `- [x] 3` → `plan-lifecycle.sh` splice emits `task_done {task_id:3, evidence_link:<absolute>}`. Builder's decision parks via `needs-you.sh add` → `waiting_on_operator {needs_you_id}` + pointer row appended to `docs/operator-todo.md`. PR squash-merges → next auditor cycle's git-scan emits `merged {sha}`. Landing card now reads: "ask registered · task 3 started · task 3 verified done (SHA link) · decision NY-123 waiting on you · merged abc1234" — bar 1/12 done, 1 in flight. Operator resolves NY-123 → auditor derives resolution → pointer auto-checks, waiting count drops to 0. (The `merged` event resolved its ask_id via Task 5's attribution chain: SHA → `plan: <slug>` body token or plan-file diff → plan-header `ask-id:` → per-ask log.) All tasks verified + closure contract satisfied → `plan-auto-closure.sh` invokes `close-plan.sh --auto` → `plan_completed` emitted → next auditor cycle sees every linked plan terminal → ask status flips `done` (`emitter=auditor`) → the card leaves the active landing for the collapsed completed group — the full entry-to-exit lifecycle with zero operator ceremony.

### 3. Interface contracts between components
- Splice → lib: `progress-log.sh emit --type <t> --ask <id> [...]` promises exit 0 always, ≤50ms, one deduped JSONL line or a logged failure — never stdout/stderr into the host hook.
- Lib → file: one event = one LF-terminated line, schema v1 (versioned; readers skip unknown versions), O_APPEND atomic.
- Registry: append-only JSONL; latest-record-wins per ask_id for mutable fields; mirror is best-effort derived copy, never read as truth.
- Server → UI: `/api/asks` payload conforms to the `payload-schema.js` allowlist (no gate/hook identifiers, absolute hrefs only) — schema validates in selftest AND at serve time (validation failure = 500 with diagnostics detail, not a leaking payload).
- Auditor → server: published drift state read-only; auditor never writes UI payloads directly.
- UI writes → files: to-do/backlog handlers write only their marker-delimited section/row; the file is always the truth the next session reads.

### 4. Environment & execution context
Windows 11 + Git Bash hooks (absolute bash paths, login-shell lessons from `02ff2f3` inherited); node server as user process (autostart via existing `register-autostart.ps1`), 127.0.0.1:7733; state under `~/.claude/state/` (persistent, machine-local); repo worktrees ephemeral — splices must work from any worktree cwd. Path resolution is two-class (review round 1): ephemeral-ok reads may resolve via `git rev-parse`; ALL durable in-repo writes (`docs/operator-todo.md` pointers, `docs/asks/` mirror) resolve via `nl_main_checkout_root` (`hooks/lib/nl-paths.sh` — the convention `needs-you.sh` already follows) so a write fired inside a builder worktree can never land in an ephemeral checkout and be destroyed; ask-id via plan header/dispatch env, never cwd guesses. Server restarts: log+registry are files; nothing in-memory is truth (auditor state rebuilds on boot).

### 5. Authentication & authorization map
None new: server binds loopback only (unchanged); no external APIs except optional `claude -p` haiku summarizer (existing local auth; rate-irrelevant at ~sessions/day volume; hard-fails silent). Git scans are local. UI writes touch repo files as the server's user — same trust domain as today's `/api/doc/open`. P3 team transport explicitly deferred (§6).

### 6. Observability plan (built before the feature)
The feature IS an observability surface, so it self-hosts: every emission failure logs to `~/.claude/logs/progress-log-emit.log` (convention of `conversation-tree-emit.log`); auditor cycle results + drift counts on the diagnostics tab; doctor predicates (anti-noise, capture-completeness, reconciliation) make silent rot RED at session start; `/api/health` grades the new subsystems. Reconstruction path: JSONL logs + registry + git history fully replay any card's state.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery | Escalation |
|---|---|---|---|---|
| Splice emit | lib missing/crash | gap in narrative | `|| true` protects host; auditor BACKFILLS truth-ahead-of-log classes next cycle (Task 12 table), badges the rest | doctor RED if predicate-visible |
| Ask capture | prompt field absent / builder session | missing ask node | orphan lane by plan-slug; capture-completeness predicate | RED at next doctor run |
| Summarizer | model unavailable | heuristic summary only | automatic (heuristic is default path) | none — cosmetic |
| Registry write | file locked/corrupt line | capture lost | readers skip bad lines; re-register on next prompt marker miss | predicate RED |
| Auditor | oracle shell fails | stale drift badges | rc carried per wave-O convention; freshness header shows age | Harness Health pane |
| Merge scan | wrong remote/auth | missing merged events | drift badge on plan rows (done-without-SHA) | operator sees badge |
| UI write | concurrent edit | write rejected | explicit UI error; file untouched | operator retries |
| Server | lobotomized spawn | panes error | inherited health self-report + launcher kill-restart (`02ff2f3`) | existing contract |

### 8. Idempotency & restart semantics
Emissions deduped by per-event-type natural keys (§Behavioral Contracts, Task 2 table) — replaying hooks, re-running installs, or auditor backfills cannot double-log, while legitimate recurrences (re-dispatch, repeat amendments) still log. Registry register/attach idempotent per natural key. Auditor is stateless-restartable (rebuilds from files each cycle). Server restart: no in-memory truth. Partial states (event without registry entry, registry without events) are first-class renders (orphan lane / empty narrative), never crashes.

### 9. Load / capacity model
Volume is tiny by web standards: tens of events/day/ask, tens of asks, backlog ~hundreds of rows. Bottlenecks: (a) landing latency — solved structurally by reading files, never shelling oracles on-path (auditor owns oracle cost at 120s cadence); (b) JSONL growth — bounded by per-ask files + a done/dismissed archival sweep noted in the runbook (P1 ships the convention; enforcement when volume warrants); (c) hook overhead — ≤50ms/splice across ~5 splices/session-lifecycle, negligible against existing chains. Saturation mode: degradation is staleness (badged), never wrongness.

### 10. Decision records & runbook
Consolidated decision record `docs/decisions/06x-ask-rooted-workstreams-p1.md` (Task 10) covering D1–D11 + the amended log-first law's implementation shape. Runbook `docs/runbooks/ask-workstreams.md` (stub Task 1, finalized Task 17): event flow, file locations, drift taxonomy (the Task 12 divergence-class table), symptom→fix table from §7, auditor cadence tuning, archival convention, and the "surface looks wrong" triage order (check doctor predicates → diagnostics tab → logs — never trust the UI over the files).

## Review round 1 (2026-07-10) — applied amendments

Both plan-time reviews returned FAIL with amendment-level fixes: ux-designer (2 Critical, 7 Important, 1 polish, + the binding Q9 layout ruling) and systems-designer (1 Critical, 5 Major, 3 Minor). Review source: the plan-pipeline output consumed by the orchestrator on 2026-07-10. Every finding is applied; each line below names the finding and exactly where this plan was amended. Re-review LANDED 2026-07-11: ux PASS, systems PASS-WITH-CONCERNS (no Critical/Major, zero unresolved round-1 findings) — the round-2 minors are applied per the index at the end of this section, and the plan is frozen.

**ux-designer findings:**
1. Critical — no ask lifecycle on the surface (unbounded card growth) → Hard constraint 7 (exit-mechanism law); Task 11 (`status:active` default + completed group + `POST /api/ask/<id>/lifecycle`); Task 12 (auditor-derived ask-done row in the divergence table); Task 13 (done/dismiss/merge card affordances, collapsed completed group); Task 8 (status vocabulary + set-status callers); new acceptance scenario `ask-lifecycle-exit`; Decisions Log D10.
2. Critical — unspecified loading/error/empty states + `od_*` copy collision → Hard constraint 8 (four-UI-states law binding Tasks 11–16: app.js global invariant inherited with operator-altitude copy; per-surface empties specced); Testing Strategy (error-state + anti-noise-in-copy fixtures); Tasks 13/14/15 state lines.
3. Important — read-only pointer checkbox is a false affordance → Task 14 (lock/auto glyph, `aria-disabled`, tooltip, navigation-primary); constraint 9 (derived controls visually distinct).
4. Important — drift badges with no route to their explanation → Task 12 (every badge click opens its divergence detail); constraint 9 (every badge/count names its click destination).
5. Important — progress bar as sole drill-down target → Task 13 (explicit chevron + "N tasks" control beside the bar; hover/cursor signifiers); prove-it #2 updated.
6. Important — empty Team tab shell → Task 16 + Scope IN + Out-of-scope (Team tab HIDDEN in P1; provenance fields still ship); Decisions Log D11.
7. Important — §3 defect form without recovery → Task 11 (form carries absolute link to the raw NEEDS-YOU.md entry + source-session link/copy); constraint 9 (no terminal error renders).
8. Important — dispositions without feedback/undo → Task 15 (row transition + undo; confirm on WONTFIX only; add-form feedback); constraint 9 (all UI writes get feedback + recovery); prove-it #3 updated.
9. Important — a11y contract not bound to new modules → constraint 9 (Tasks 13–16 bound by citation to the `web/app.js` WCAG 2.2 AA header; drift badges text+color); Task 16 prove-it #4 (color-only-signal + real-button selftest assertions).
10. Polish — session-id copy with no next step → Task 13 (microcopy: "copy session id — resume with `claude --resume <id>`").
Q9 layout ruling (binding) → encoded verbatim in Tasks 13/16 (sidebar spec, header count, top-N backlog, ~1200px stacking); Task 18 walkthrough now runs against the real full registry.

**systems-designer findings:**
1. Critical — merge-SHA→ask attribution undefined → Task 5 (key-resolution path SHA → plan-slug → `ask-id:`; `plan: <slug>` body token in `doctrine/git.md` + plan-file-diff fallback; unresolvable commits skipped; multi-repo scan set from projects.js roots); constraint 10; §2 trace extended; Decisions Log D8.
2. Major — idempotency conflates replay with legitimate recurrence → Task 2 (per-event-type natural-key table + legitimate-recurrence self-test fixture); Behavioral Contracts + Systems Analysis §8 updated; Edge Cases row added.
3. Major — missing Conclude step (no plan_completed lane, no set-status caller, no dismiss) → Task 6 (sixth lane: `plan_completed` splice in `close-plan.sh`, reached via the WIRED `plan-auto-closure.sh` — wiring verified — and manual closes); Scope FIVE→SIX; Goal; Task 12 (ask-done derivation); Tasks 11/13 (operator exit); constraint 7; Assumptions.
4. Major — builder-session guard mechanism-less → Task 9 (mechanical predicate: cwd-under-`.claude/worktrees/` OR Task 3 dispatch-provenance marker; marker verified ABSENT today, so Task 3 CREATES it); Task 3 (marker write); dispatch comment (Task 3 → Task 9 serialization); Edge Cases; Decisions Log D9.
5. Major — auditor reconciliation direction-blind → Task 12 (divergence-class table: truth-ahead-of-log BACKFILLS with `emitter=auditor`, log-ahead-of-truth BADGES; authoritative side stated per class; prove-it #1 REWRITTEN to expect backfill-heal, not a permanent badge); §7 failure table row aligned.
6. Major — durable in-repo writes lost from worktrees → Hard constraint 11 + Systems Analysis §4 (all durable in-repo writes via `nl_main_checkout_root`, `hooks/lib/nl-paths.sh` — verified, same convention as `needs-you.sh`); Tasks 4/8 (resolver named + from-worktree self-test fixtures); Assumptions.
7. Minor — open emit CLI as self-reporting side door → Task 2 (emitter allowlist + `provenance:unknown` flag); Task 12 (unknown-emitter badge row); constraint 10 (provenance-trust rules for oracle-less event types).
8. Minor — doctor predicate population mismatch → Task 17(c) (counts only operator-origin sessions via the SAME shared classification function as the Task 9 guard, in `progress-log-lib.sh`).
9. Minor — pointer items without operator recourse → Task 14 (dismiss/mark-handled override writing the durable file with an auditor-respected flag + prove-it #5); constraint 7; Edge Cases.

**Round 2 (re-review) minors — applied (2026-07-11; ux PASS, systems PASS-WITH-CONCERNS, no Critical/Major):**
1. systems Minor — `plan_completed` dedup key omitted its own recurrence discriminator (bare `plan_slug` would suppress a legitimate re-close after reopen) → Task 2 table (key now `plan_slug+content-hash of the Status-line ts`) + the superset rule noted under the table; all rows audited — only this row diverged.
2. ux nice-to-have — the new collapsed completed group and the Backlog pane had no named empty states in constraint 8's enumeration → constraint 8 (completed-group empty "no completed asks yet", hidden or muted; Backlog-pane empty + add affordance); Testing Strategy (cockpit.selftest empty-state fixture covers both).
3. ux nice-to-have — mechanical auto-move to the completed group was invisible on the landing (H1 visibility) → Task 13 COMPLETED-GROUP HEADER (count + newest-completed recency; no banner/toast — anti-noise).
4. ux nice-to-have — card rendering unspecified when `plan_slugs[]` has >1 entry (single bar vs plural lifecycle logic) → Task 13 MULTI-PLAN CARDS (aggregate bar + per-plan drill-down grouping + one live-doc link per plan; cheapest fit to the existing structure, stated in-task).
5. systems Minor — Task 5 diff-touches-plan-file fallback had no multi-match tie-break → Task 5 (multi-plan-file match emits one `merged` event per matched ask; never guesses a single winner).
## Completion report (2026-07-17)

**18/18 tasks verified and flipped; DEPLOYED live.** The operator's ask — "see, across many parallel
autonomous sessions: what I asked, the plan and its progress, and what's waiting on me, plus an
editable to-do and backlog, grouped by project" — is a running product at `http://127.0.0.1:7733/`
(deployed 2026-07-14: deploy-preflight PASS, concurrent work stash-preserved, `/api/asks` serving
real data). Every task passed TWO gates: task-verifier substance + rung-4 comprehension-review
(orchestrator-dispatched, Opus).

**Acceptance:** end-user-advocate runtime pass over all 6 scenarios — 5 PASS + 1 FAIL
(todo-pointer-lifecycle: the My-To-Do pane clipped at >1200px). The FAIL was fixed (@86e9e69,
`.sidebar>.pane` flex-shrink scoped) and re-verified 6/6 end-to-end at 1920x1080. Artifacts:
`.claude/state/acceptance/ask-rooted-workstreams-p1/` (reconstructed after worktree auto-cleanup ate
the originals — nl-issue filed on that plumbing). **Outstanding (operator, non-blocking by their own
ruling "demonstration, not permission gate"):** the <60s cold-start walkthrough timing.

**Task 7's second half (splice harness-review):** Fable was cancelled mid-plan (operator: not worth
un-subsidized rate) → replaced by a 7-lens diverse Opus panel + adversarial verify (15 agents):
3 classes CLEAN, **7 confirmed defects** (3 Major session-lifecycle), 1 refuted — ALL fixed with
RED→GREEN regression tests (`docs/reviews/2026-07-14-ask-splice-review-panel.md`). Post-plan, the
merge-scan lane also gained an incremental cursor (36/36) closing the backfill-never-completes
degradation.

**Self-test bar:** full server suite **139 passed / 0 failed** — its first-ever complete pass
(unblocked by the ECONNRESET keep-alive fix + an nyBash scoping hoist it unmasked); cockpit.selftest
84/84; every splice lib suite green.

**Notable §8 decisions (batched):** log-first architecture with mechanism-emitted events (operator
amendment honored throughout); six-pane cockpit demoted to a Harness Health tab behind a native
<template> quarantine; Team tab held to P1-hidden with provenance fields shipped; Fable→panel
methodology swap; three severe machine incidents diagnosed and root-caused during the build
(orphan-process contention ×2 → reboots; the auditor timeout-without-kill leak → killTree fix +
reap-what-you-spawn doctrine).

**Legacy this plan leaves in the harness:** the diverse-panel + adversarial-verify deep-review
pattern (validated: 7 real defects no single pass caught); the artifact-evidence-bar standard + its
three enforcement gates (closed under `docs/plans/archive/evidence-bar-enforcement.md`); the
architecture-reviewer agent (whose golden case came from this plan's cockpit-v2 successor design).
Successor work: `docs/plans/cockpit-v2-push-materialized-store.md` (cross-machine store, v3,
architecture-reviewed, ready to build).
