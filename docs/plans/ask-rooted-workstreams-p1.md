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
frozen: false
<!-- Spec under plan-time review (ux-designer + systems-designer, in flight now).
Flip to true when both reviews land; amendments before freeze need no thaw cycle. -->
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
append, master merge, plan amendment), never by model memory; the wave-O derivation
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
    and the FIVE mechanism-emission splices: verifier-flip, dispatch, NEEDS-YOU
    append, master merge, plan amendment — each a one-line best-effort splice into
    an ALREADY-WIRED hook/script (same convention as the session-heartbeat `touch`
    splices; see manifest entry `session-heartbeat` `honest_status` for the model).
  - Ask registry: `~/.claude/state/ask-registry.jsonl` + in-repo mirror; fully
    automatic capture (first operator prompt), cheap summarizer, verbatim ref;
    plan↔ask linkage convention (doctrine line + template field + `start-plan.sh`).
  - Server: `/api/asks` (landing tree payload), `/api/ask/<id>` (detail), to-do and
    backlog read/write endpoints; background auditor on a relaxed cadence (reuse of
    `derive-cache.js` plumbing) producing per-item drift badges; payload schema
    self-test enforcing the anti-noise law and absolute-href law.
  - UI: ask-tree landing (shallow cards + plan drill-down), My To-Do sidebar pane,
    Backlog sidebar pane (collapsible), Harness Health demotion to a tab.
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

## Tasks

<!-- Dispatch per orchestrator pattern: [parallel] groups are file-disjoint.
Mandatory reviews: ux-designer + systems-designer at PLAN time (in flight now, on
this document); harness-reviewer post-build on every hook/script splice (Tasks 1,
3–7, 9, 10); end-user-advocate owns Acceptance Scenarios; task-verifier is the only
checkbox-flipper. -->

- [ ] 1. **Walking skeleton** — one event end-to-end: minimal
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

- [ ] 2. [parallel] Progress-log format finalization + writer hardening: versioned
  JSONL event schema (`{v, event_id, ts, ask_id, type, plan_slug?, task_id?, sha?,
  needs_you_id?, session_id?, summary, evidence_link, emitter, user, machine,
  repo}`), event-id dedup (idempotent re-emission), atomic single-line O_APPEND
  writes, orphan-event lane for unresolvable ask-ids, `--self-test` (sandboxed,
  incl. concurrent-append + dedup + CRLF-safety scenarios; repo pins `eol=lf`) —
  Verification: mechanical — Docs impact: schema section in
  `docs/runbooks/ask-workstreams.md` + `adapters/claude-code/schemas/progress-log-event.schema.json`
- [ ] 3. [parallel] Dispatch emission splice: `task_started` events from the
  already-wired `hooks/workstreams-emit.sh` `--on-builder-dispatch` / `--on-spawn`
  call sites (PreToolUse on Task, verified wired in `settings.json.template`),
  carrying plan slug + task id + child session provenance (the same provenance
  the SESSIONS lineage rendering consumes). One-line best-effort splice; the old
  tree-state write path is untouched (it remains the auditor's comparison input) —
  Verification: mechanical — Docs impact: none — splice documented via Task 7 manifest entry
- [ ] 4. [parallel] NEEDS-YOU emission splice: `scripts/needs-you.sh add` emits
  `waiting_on_operator` (needs-you id, section, tier, session id, cold-reader
  lint result carried as the §3-context-present flag) AND appends the auto-pointer
  item to `docs/operator-todo.md` (marker-delimited auto-section; operator section
  untouched). Resolution is NOT emitted here — it is derived (auditor, Task 12)
  so pointer auto-check survives resolutions that bypass the script —
  Verification: mechanical — Docs impact: none — covered by Task 7 manifest entry + runbook
- [ ] 5. [parallel] Master-merge emission: two lanes, both mechanical —
  (a) splice in `git-hooks/post-commit` for local commits landing on master;
  (b) auditor git-scan backfill (Task 12 consumes this lib function, defined here)
  deriving `merged` events with SHA from `git log origin/master` — the GUARANTEED
  lane, since squash-merges via `gh pr merge` never fire local hooks —
  Verification: mechanical — Docs impact: none — covered by Task 7 manifest entry + runbook
- [ ] 6. [parallel] Plan-amendment emission splice: `hooks/plan-lifecycle.sh`
  detects newly-introduced task lines / scope-section edits on ACTIVE plans
  (reuse `plan-edit-validator.sh`'s existing new-task-line parse) and emits
  `plan_amended` ("+task 12", scope delta summary) — Verification: mechanical —
  Docs impact: none — covered by Task 7 manifest entry
- [ ] 7. [serial] Manifest + review closure for the writer family: one
  `manifest.json` entry (`id: progress-log`, `kind: writer`, `honest_status`
  naming EVERY splice site verbatim — the `session-heartbeat` entry is the
  template), doctor `--quick` stays GREEN, and a **mandatory harness-reviewer
  pass over Tasks 1, 3–6 splice diffs** with findings fixed — Verification:
  mechanical — Docs impact: manifest entry IS the doc; regen via manifest tooling,
  never hand-drift (MANIFEST-NEEDS-YOU-DRIFT-01 lesson)
- [ ] 8. [parallel] Ask registry lib: `scripts/ask-registry.sh`
  (register/attach-session/link-plan/set-status/merge/override-project) writing
  `~/.claude/state/ask-registry.jsonl` (sketch §4 schema incl. `{user, machine,
  repo, project}` provenance; project defaulted via
  `neural-lace/workstreams-ui/config/projects.js` mapping) + best-effort in-repo
  mirror append (`docs/asks/ask-registry.jsonl` in the ask's repo) + summarizer:
  heuristic first (first sentence, ≤140 chars, markdown-stripped) with optional
  `claude -p` haiku-tier upgrade behind `ASK_SUMMARIZER=haiku` (async,
  best-effort, never blocks capture; Fable never used — cheap-model-only by
  design) + verbatim ref (transcript path + prompt offset) + `--self-test`
  (sandboxed) — Verification: mechanical — Docs impact: registry section in runbook
- [ ] 9. [serial] Automatic capture splices: (a) first operator prompt of a session
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
  - Sub-agent / builder sessions must NOT register new asks (they attach to the dispatching ask via Task 3 provenance) — guard on session type
- [ ] 10. [serial] Plan↔ask linkage convention: one line in
  `adapters/claude-code/doctrine/planning.md` ("plan headers record `ask-id:`;
  plan creation back-links the registry"), `ask-id:` field + comment block in
  `adapters/claude-code/templates/plan-template.md`, `--ask-id` flag in
  `scripts/start-plan.sh`, `plan-reviewer.sh` WARN (never block) when an ACTIVE
  v2 plan lacks the field, and BACKFILL of this plan's own
  `ask-20260710-workstreams-rebuild` entry (self-demonstrating). Tier-2 decision
  record `docs/decisions/06x-ask-rooted-workstreams-p1.md` (next free number)
  lands in the same commit — Verification: mechanical — Docs impact: doctrine
  line + template field + decision record (that IS the delta)
- [ ] 11. [serial] Server read surface: `GET /api/asks` (landing payload: project
  groups → ask cards with summary, activity ts, plan progress counts, waiting
  count, drift badges) and `GET /api/ask/<id>` (full log narrative, per-task plan
  rows with evidence links, waiting items with §3 context blocks or the visible
  "context missing — session violated §3" defect form, artifacts, sessions with
  lineage edges) + `server/payload-schema.js`: the machine-checked landing schema
  — an ALLOWLIST of fields; any field carrying gate/hook identifiers or any
  relative href fails `server.selftest.js`. Plan drill-down links resolve through
  the EXISTING `/api/doc` + `/api/doc/open` (no new link handling — ux-review
  amendment 6). Writes for to-do/backlog land in Tasks 14/15 — Verification:
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
- [ ] 12. [serial] Background auditor + drift badges: new `server/auditor.js`
  reusing `server/derive-cache.js` plumbing on a RELAXED cadence (default 120s,
  env-tunable; never on the landing request path) comparing the log against
  ground truth — plan checkboxes (done), heartbeats + dispatch records (in
  flight; §2 law 4: in-progress is derived, never declared), NEEDS-YOU parse
  (waiting; also drives To-Do pointer auto-check), `git log origin/master`
  (merges; backfills missed `merged` events per Task 5b) — and attaching drift
  badges to exactly the divergent item. Includes the §8-3 count reconciliation:
  ledger-parsed open items vs rendered waiting items must be equal, else a drift
  badge + a diagnostics-tab detail (never a landing-page banner — anti-noise) —
  Verification: full — Docs impact: auditor cadence + drift taxonomy in runbook
  **Prove it works:**
  1. Flip a fixture divergence: mark a sandbox plan task `- [x]` via the verifier flow but delete the log event → within one cadence the plan row wears a drift badge naming the divergence
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
- [ ] 13. [serial] UI landing — ask tree: project sections (collapsible), ask cards
  (summary + verbatim-one-click, progress narrative excerpt, plan progress bar +
  live-doc hyperlink, waiting count, drift badges inline), shallow-first with plan
  drill-down (per-task rows: done/in-flight/not-started with evidence links);
  SESSIONS list with spawn-lineage edges where provenance exists, flat grouping
  where not (never a lost session); waiting items name + link their source session
  — includes the TIMEBOXED SPIKE (≤2h) on a desktop-app URL scheme, with the
  copy-button fallback shipped regardless of spike outcome. New `web/asks.js` +
  `web/app.css` additions; `web/app.js` becomes shell/router. HARD CONSTRAINT:
  anti-noise law — zero gate/hook identifiers rendered; all links absolute —
  Verification: full — Docs impact: `neural-lace/workstreams-ui/README.md` IA section rewrite
  **Prove it works:**
  1. Open `http://127.0.0.1:7733/` cold with ≥2 projects' real asks — tree renders grouped, newest first
  2. Click a plan bar → drill-down rows match the plan file's actual checkboxes (spot-check against `docs/plans/<slug>.md` via the `/api/doc` link on the same card)
  3. Click the verbatim affordance → original ask text displays
  4. Click a waiting item's session link/copy → session id lands on the clipboard (or deep-link opens, if the spike succeeded)
  5. Grep the rendered DOM (`web/cockpit.selftest.js` extension) for a denylist of gate/hook identifier patterns — zero hits; all `href`/path attributes absolute
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/index.html` → `neural-lace/workstreams-ui/web/asks.js` include
  - `neural-lace/workstreams-ui/web/asks.js` `fetch('/api/asks')` → `neural-lace/workstreams-ui/server/server.js` route
  - `neural-lace/workstreams-ui/web/asks.js` plan link → `/api/doc` + `/api/doc/open` handlers in `server/server.js`
  **Integration points:**
  - Old conv-tree card/popup patterns salvaged from git history `952c9d6`/`e7393bc` (read-only reference — attic code not resurrected wholesale)
  - Layout per Q9: To-Do/Backlog sidebar panes (Tasks 14–15) share the viewport — ux-designer plan review makes the final layout call BEFORE this task dispatches; its verdict is binding
- [ ] 14. [parallel] My To-Do pane: new `web/todo.js` + `GET/POST /api/todo`
  reading/writing `docs/operator-todo.md` (NEW file: operator free-form section +
  marker-delimited auto-pointer section) — operator items: add/edit/check freely
  from the UI; pointer items: rendered with their §3 context, click navigates to
  the ask's waiting item (P1 = navigate; P2 = answer in place), checkbox is
  READ-ONLY and auto-checks on underlying resolution (Task 12 derivation) —
  writes go to the durable file, never a parallel store; anti-noise +
  absolute-links constraints apply — Verification: full — Docs impact:
  `docs/operator-todo.md` self-documenting header + runbook section
  **Prove it works:**
  1. Add "buy more coffee" via the pane → `docs/operator-todo.md` contains it; reload → persists
  2. Trigger a real `needs-you.sh add` from a session → pointer item appears WITHOUT any UI action
  3. Resolve the underlying item → pointer auto-checks within one auditor cadence; operator items untouched
  4. Edit the file by hand in an editor → pane reflects it on refresh (file is truth, UI is a view)
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/todo.js` `fetch('/api/todo')` → `neural-lace/workstreams-ui/server/server.js` todo routes
  - `neural-lace/workstreams-ui/server/server.js` POST handler → `docs/operator-todo.md` marker-safe writer
  - `adapters/claude-code/scripts/needs-you.sh` splice (Task 4) → `docs/operator-todo.md` auto-section
  **Integration points:**
  - Concurrent writes (session appends pointer while operator edits) — marker-delimited sections + atomic rewrite of only the touched section; fixture in selftest
- [ ] 15. [parallel] Backlog pane: new `web/backlog.js` + endpoints — render
  `docs/backlog.md` (compact top-N by tier, collapsible, full list one click);
  ADD form appending a well-formed row (both Claude and operator can add —
  operator's rows follow the same shape the O.9 triage loop parses); disposition
  buttons SCHEDULE / DEMOTE / FOLD / WONTFIX writing the exact disposition
  vocabulary the existing loop understands — writes to the real file, no
  parallel store; anti-noise + absolute-links constraints apply — Verification:
  full — Docs impact: one line in `docs/backlog.md` header noting the UI write path
  **Prove it works:**
  1. Open the pane with the REAL (hundreds-of-rows) backlog — renders compact without jank; full list opens
  2. Add a row via the form → `git diff docs/backlog.md` shows one well-formed row in the right section
  3. Click WONTFIX on a fixture row → the file carries the disposition in loop-parseable form (verify against the O.9 loop's parser, not by eyeball)
  4. Reload → both changes persist; no other row disturbed
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/backlog.js` → `neural-lace/workstreams-ui/server/server.js` backlog routes
  - `neural-lace/workstreams-ui/server/server.js` disposition handler → `docs/backlog.md` row-scoped writer
  **Integration points:**
  - O.9 triage loop parser is the contract — its fixture corpus is the golden oracle for rows/dispositions this UI writes
- [ ] 16. [serial] Layout integration + Harness Health demotion: sidebar assembly
  per the ux-designer verdict (To-Do top, Backlog collapsible below, ask tree as
  the main column), landing route serves the ask tree, and the six wave-O panes
  move VERBATIM to a Harness Health tab (operator condition: they stay only if
  they work and stay quiet — a pane that errors or spams gets a follow-up backlog
  row, not landing space). Diagnostics (reconciler internals, drift detail)
  live here too — Verification: full — Docs impact: README IA section final pass
  **Prove it works:**
  1. Open `/` → ask tree + sidebar; NO six-question panes on landing
  2. Open the Harness Health tab → all six panes function (each returns data or an honest rc-carried error, per the wave-O contract)
  3. Resize to a laptop viewport → glance loop (tree + to-do + backlog) fits one viewport per Q9 rationale
  4. `web/cockpit.selftest.js` extension asserts landing DOM contains zero pane-family identifiers (anti-noise, mechanized)
  **Wire checks:**
  - `neural-lace/workstreams-ui/web/index.html` tab shell → `neural-lace/workstreams-ui/web/app.js` router
  - Harness Health tab → existing `/api/pane/*` routes in `neural-lace/workstreams-ui/server/server.js` (unchanged)
  **Integration points:**
  - Existing autostart/launcher (`scripts/launch-gui.ps1`, heartbeat/reconciler registrations) keep working — port + health contract unchanged
- [ ] 17. [serial] Mechanized metrics + doctor wiring (sketch §8): (a) anti-noise
  schema check + absolute-href check running in `server.selftest.js` AND surfaced
  as a doctor predicate (extend the existing `obs-cockpit-fresh` doctor check);
  (b) waiting-on-you count reconciliation live (Task 12) with a doctor-visible
  failure mode; (c) capture-completeness predicate (Task 9 invariant: trailing-24h
  sessions all have asks); (d) the 2-week operator check-in as a scheduled task
  (calendar mechanism, not vibes — model: `install-weekly-hygiene-task.ps1`)
  that ASKS the cold-start question — Verification: mechanical — Docs impact:
  runbook "metrics + falsifiers" section mirroring sketch §8
- [ ] 18. [serial] Acceptance: end-user-advocate runtime pass over the Acceptance
  Scenarios below + the OPERATOR cold-start walkthrough — the operator (not
  Claude) cold-starts a real ask and answers the four questions in <60s without
  opening a transcript; result recorded in this plan's completion report with the
  timing. This is the §7 usefulness bar; component greens do not substitute —
  Verification: full — Docs impact: completion report + evidence artifacts
  **Prove it works:**
  1. Advocate executes every scenario below via browser automation; JSON artifacts land under `.claude/state/acceptance/ask-rooted-workstreams-p1/`
  2. Operator walkthrough: pick an ask the operator hasn't looked at in ≥24h; time the four answers; <60s → PASS, else the gap is named and fixed before closure
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
- `adapters/claude-code/hooks/workstreams-emit.sh` — dispatch/spawn emission splices
- `adapters/claude-code/scripts/needs-you.sh` — waiting_on_operator emission + to-do pointer append
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
- `neural-lace/workstreams-ui/web/index.html`, `web/app.js`, `web/app.css` — shell/router/layout
- `neural-lace/workstreams-ui/web/cockpit.selftest.js` — landing DOM anti-noise/absolute-href assertions
- `neural-lace/workstreams-ui/README.md` — IA + API docs
- `docs/backlog.md` — header line re UI write path (+ PROGRESS-FIELD-01 cross-ref at completion)

## In-flight scope updates
(no in-flight changes yet)

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

## Edge Cases

- **Event with unresolvable ask-id** (e.g. verifier flip in a plan whose header lacks `ask-id:` — every pre-existing plan): event lands in the orphan lane keyed by plan-slug; the auditor attaches it retroactively if a linkage appears; the UI shows an "unlinked plan" group rather than dropping progress. Estate-growth safe: old plans never break the surface.
- **Concurrent JSONL appends** (parallel builders flipping tasks simultaneously): single-line O_APPEND writes + event-id dedup; self-test includes a concurrent-append scenario.
- **Duplicate ask on resume/compact**: first-prompt marker + resume-chain attach (Task 9) — a resumed or compact-recovered session attaches, never re-registers.
- **Builder/sub-agent sessions**: never register asks; they attach via dispatch provenance. Guard tested in Task 9.
- **Cold-reader-violating waiting item** (missing §3 block): renders as the visible defect form ("context missing — session violated §3"), never a bare ID (sketch §2 law 3).
- **Registry or log file unavailable/corrupt line**: readers skip bad lines and surface a diagnostics-tab count; landing page never 500s on one bad record.
- **Lobotomized server instance** (2026-07-09 incident class): health/lobotomy/restart contract inherited from `02ff2f3`; new endpoints participate in `/api/health` grading (§8-4 invariant).
- **Backlog scale** (hundreds of rows): compact top-N render + on-demand full list; row-scoped writes so a disposition never rewrites the whole file.
- **Operator edits `operator-todo.md` in an editor while the UI is open**: file is truth; marker-delimited section writes; UI refresh reflects the file.
- **Self-test pollution**: every self-test sandboxed under `HARNESS_SELFTEST_DIR`; a T10-style "state written only under sandbox" assertion in each new self-test.
- **First install (no asks yet)**: landing renders an honest empty state with the capture mechanism named, not a blank page.

## Behavioral Contracts

- **Idempotency:** `pl_emit` is idempotent by `event_id` (hash of type+ask+plan+task+sha); re-running any splice, replaying a hook, or auditor backfill racing a live emit produces exactly one logged event. Registry `register` is idempotent per session-origin; `attach-session` per (ask, session) pair.
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

### anti-noise-landing — telemetry stays off the landing page

**Slug:** `anti-noise-landing`

**User flow:**
1. Open the landing page and the Harness Health tab
2. Run the server + cockpit self-tests

**Success criteria (prose):** landing payload and DOM contain zero gate/hook identifiers and zero relative hrefs (mechanized checks PASS); the six panes function inside their tab only.

**Artifacts to capture:** self-test output; landing payload JSON; DOM assertion output.

## Out-of-scope scenarios

- Answering a decision inline from the surface — P2 by operator decision (sketch §9 Q4); P1 pointer items navigate only.
- Two-operator concurrent use / team view content — P3 (§6); P1 ships provenance fields + the Team tab shell only.
- Desktop-app deep-link guaranteed working — spike only (Q8); the copy-button fallback is the committed path.
- Mobile/phone rendering — desktop-only surfaces per standing operator decision (no-phone-observability).

## Closure Contract

- **Commands that run:** `bash adapters/claude-code/scripts/progress-log.sh --self-test`; `bash adapters/claude-code/scripts/ask-registry.sh --self-test`; `node neural-lace/workstreams-ui/server/server.selftest.js`; `node neural-lace/workstreams-ui/web/cockpit.selftest.js`; `bash adapters/claude-code/hooks/harness-doctor.sh --quick`; advocate runtime pass over the five scenarios; the operator cold-start walkthrough (Task 18).
- **Expected outputs:** every self-test full-PASS with sandboxed state; doctor GREEN including the three new predicates; five scenario artifacts `verdict: PASS`; walkthrough timing <60s recorded in the completion report.
- **On-disk artifact location:** `.claude/state/acceptance/ask-rooted-workstreams-p1/<session-id>-<timestamp>.json` (+ sibling screenshots/logs); structured evidence at `docs/plans/ask-rooted-workstreams-p1-evidence/<task-id>.evidence.json` for mechanical tasks.
- **Done when:** all 18 tasks are task-verifier PASS AND the acceptance artifacts exist with PASS verdicts AND the operator walkthrough is recorded <60s AND doctor `--quick` is GREEN on live `~/.claude` at a master SHA containing this work.

## Testing Strategy

- **Libs/splices (Tasks 1–10):** per-script `--self-test` under `HARNESS_SELFTEST=1` + `HARNESS_SELFTEST_DIR` (concurrency, dedup, orphan lane, sandbox-only-writes assertions); harness-reviewer pass on every splice diff; `manifest-check.sh` + doctor `--quick` after Task 7; splice hosts' EXISTING self-tests re-run green (no regression in `needs-you.sh --self-test`, `plan-lifecycle` fixtures, etc.).
- **Server (Tasks 11–12):** `server.selftest.js` extended — new routes, payload allowlist with NEGATIVE fixtures (gate-identifier field → FAIL; relative href → FAIL), landing-latency assertion, auditor drift fixtures (each divergence class produces exactly one badge), count-reconciliation fixture pinned to `needs-you.sh` render output.
- **UI (Tasks 13–16):** `cockpit.selftest.js` extended — DOM anti-noise denylist, absolute-href sweep, empty-state render; live checks in each task's Prove-it-works against the real running server (the user path, not components).
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

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept; all five emission entry points + two capture points resolved to live wired hooks/scripts (verified against `settings.json.template` hook dump 2026-07-10); one planned entry point (`goal-extraction-on-prompt.sh`) found RETIRED and replaced with `workstreams-read.sh` (D3).
- S2 (Existing-Code-Claim Verification): swept; verified against files — server routes (`/api/health`, `/api/pane/*`, `/api/doc`, `/api/doc/open` in `server/server.js`), heartbeat splice sites (`session-start-digest.sh` ~1065/1080), `needs-you.sh add` contract + cold-reader lint, `plan-edit-validator.sh` flip authorization, manifest `session-heartbeat` honest_status splice convention, `workstreams-emit.sh` live (not attic'd), 8/8 cap comment in `ensure-cockpit.sh`.
- S3 (Cross-Section Consistency): swept; "auditor is recovery, emit is fire-and-forget" consistent across Constraints/Tasks 5,12/Behavioral Contracts; "no new settings entries" consistent across Constraint 3/Tasks 3,9/Assumptions; anti-noise stated once as law, referenced per UI task.
- S4 (Numeric-Parameter Sweep): swept for params [port 7733, auditor cadence 120s, summary ≤140 chars, splice budget 50ms, landing p95 300ms, <60s bar, cap 8/8 + 4/6, target 2026-07-24] — each appears with one value everywhere.
- S5 (Scope-vs-Analysis Check): swept; all Add/Modify verbs in Tasks/Files checked against Scope OUT — no task builds inline answering, team aggregation, deep-link commitment, or attic resurrection; the deep-link SPIKE in Task 13 is explicitly bounded and non-committal.

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
Operator types "rebuild the workstreams view" in a new session → `workstreams-read.sh` splice calls `ask-registry.sh register` → entry `ask-20260710-workstreams-rebuild` (summary heuristic, verbatim ref = transcript path+offset, project `neural-lace` via projects.js) + `ask_registered` event in `~/.claude/state/progress-logs/ask-20260710-workstreams-rebuild.jsonl`. Plan created with `start-plan.sh --ask-id ask-20260710-workstreams-rebuild` → header line + registry `plan_slugs[]` back-link. Orchestrator dispatches builder on task 3 → `workstreams-emit.sh --on-builder-dispatch` splice emits `task_started {plan_slug, task_id:3, session_id:child}`. Builder finishes; task-verifier flips `- [x] 3` → `plan-lifecycle.sh` splice emits `task_done {task_id:3, evidence_link:<absolute>}`. Builder's decision parks via `needs-you.sh add` → `waiting_on_operator {needs_you_id}` + pointer row appended to `docs/operator-todo.md`. PR squash-merges → next auditor cycle's git-scan emits `merged {sha}`. Landing card now reads: "ask registered · task 3 started · task 3 verified done (SHA link) · decision NY-123 waiting on you · merged abc1234" — bar 1/12 done, 1 in flight. Operator resolves NY-123 → auditor derives resolution → pointer auto-checks, waiting count drops to 0.

### 3. Interface contracts between components
- Splice → lib: `progress-log.sh emit --type <t> --ask <id> [...]` promises exit 0 always, ≤50ms, one deduped JSONL line or a logged failure — never stdout/stderr into the host hook.
- Lib → file: one event = one LF-terminated line, schema v1 (versioned; readers skip unknown versions), O_APPEND atomic.
- Registry: append-only JSONL; latest-record-wins per ask_id for mutable fields; mirror is best-effort derived copy, never read as truth.
- Server → UI: `/api/asks` payload conforms to the `payload-schema.js` allowlist (no gate/hook identifiers, absolute hrefs only) — schema validates in selftest AND at serve time (validation failure = 500 with diagnostics detail, not a leaking payload).
- Auditor → server: published drift state read-only; auditor never writes UI payloads directly.
- UI writes → files: to-do/backlog handlers write only their marker-delimited section/row; the file is always the truth the next session reads.

### 4. Environment & execution context
Windows 11 + Git Bash hooks (absolute bash paths, login-shell lessons from `02ff2f3` inherited); node server as user process (autostart via existing `register-autostart.ps1`), 127.0.0.1:7733; state under `~/.claude/state/` (persistent, machine-local); repo worktrees ephemeral — splices must work from any worktree cwd (resolve repo root via `git rev-parse`, ask-id via plan header/dispatch env, never cwd guesses). Server restarts: log+registry are files; nothing in-memory is truth (auditor state rebuilds on boot).

### 5. Authentication & authorization map
None new: server binds loopback only (unchanged); no external APIs except optional `claude -p` haiku summarizer (existing local auth; rate-irrelevant at ~sessions/day volume; hard-fails silent). Git scans are local. UI writes touch repo files as the server's user — same trust domain as today's `/api/doc/open`. P3 team transport explicitly deferred (§6).

### 6. Observability plan (built before the feature)
The feature IS an observability surface, so it self-hosts: every emission failure logs to `~/.claude/logs/progress-log-emit.log` (convention of `conversation-tree-emit.log`); auditor cycle results + drift counts on the diagnostics tab; doctor predicates (anti-noise, capture-completeness, reconciliation) make silent rot RED at session start; `/api/health` grades the new subsystems. Reconstruction path: JSONL logs + registry + git history fully replay any card's state.

### 7. Failure-mode analysis per step
| Step | Failure | Symptom | Recovery | Escalation |
|---|---|---|---|---|
| Splice emit | lib missing/crash | gap in narrative | `|| true` protects host; auditor badges drift next cycle | doctor RED if predicate-visible |
| Ask capture | prompt field absent / builder session | missing ask node | orphan lane by plan-slug; capture-completeness predicate | RED at next doctor run |
| Summarizer | model unavailable | heuristic summary only | automatic (heuristic is default path) | none — cosmetic |
| Registry write | file locked/corrupt line | capture lost | readers skip bad lines; re-register on next prompt marker miss | predicate RED |
| Auditor | oracle shell fails | stale drift badges | rc carried per wave-O convention; freshness header shows age | Harness Health pane |
| Merge scan | wrong remote/auth | missing merged events | drift badge on plan rows (done-without-SHA) | operator sees badge |
| UI write | concurrent edit | write rejected | explicit UI error; file untouched | operator retries |
| Server | lobotomized spawn | panes error | inherited health self-report + launcher kill-restart (`02ff2f3`) | existing contract |

### 8. Idempotency & restart semantics
Emissions deduped by event_id (§Behavioral Contracts) — replaying hooks, re-running installs, or auditor backfills cannot double-log. Registry register/attach idempotent per natural key. Auditor is stateless-restartable (rebuilds from files each cycle). Server restart: no in-memory truth. Partial states (event without registry entry, registry without events) are first-class renders (orphan lane / empty narrative), never crashes.

### 9. Load / capacity model
Volume is tiny by web standards: tens of events/day/ask, tens of asks, backlog ~hundreds of rows. Bottlenecks: (a) landing latency — solved structurally by reading files, never shelling oracles on-path (auditor owns oracle cost at 120s cadence); (b) JSONL growth — bounded by per-ask files + a done/dismissed archival sweep noted in the runbook (P1 ships the convention; enforcement when volume warrants); (c) hook overhead — ≤50ms/splice across ~5 splices/session-lifecycle, negligible against existing chains. Saturation mode: degradation is staleness (badged), never wrongness.

### 10. Decision records & runbook
Consolidated decision record `docs/decisions/06x-ask-rooted-workstreams-p1.md` (Task 10) covering D1–D7 + the amended log-first law's implementation shape. Runbook `docs/runbooks/ask-workstreams.md` (stub Task 1, finalized Task 17): event flow, file locations, drift taxonomy, symptom→fix table from §7, auditor cadence tuning, archival convention, and the "surface looks wrong" triage order (check doctor predicates → diagnostics tab → logs — never trust the UI over the files).