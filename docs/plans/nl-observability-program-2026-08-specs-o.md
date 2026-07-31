# Wave O mechanical specs (specs-o) — NL Observability Program

Status: NORMATIVE for Wave O builders (O.0 output, authored 2026-07-06, strongest
available model per D9). Parent plan: `docs/plans/nl-observability-program-2026-08.md`
(Status: ACTIVE, operator early-activation 2026-07-06 "Let's do the full redesign on
the Workstreams UI"). Normative design: `docs/reviews/2026-07-04-observability-design-sketch.md`
— the two laws (DERIVE-DON'T-MAINTAIN; EVERY-SIGNAL-HAS-A-CONSUMER), the six operator
questions, three surfaces, non-goals, pre-registered success metrics. Where this spec
and the sketch conflict, the sketch wins.

Evidence base folded in at O.0 (per activation directive):
- Backlog rows ABSORBED by this wave (marked in `docs/backlog.md` in the O.0 commit):
  CANONICAL-COUNTERS-01 → §O.3 (the derivation lib IS the canonical-oracle host);
  SCHEDULED-TASK-HEALTH-01 → §O.6 (Last Result==0 for every NL-owned scheduled task);
  E6-HEADER-HARDENING-01 → §O.6 (4-header predicate gated on ny_open>0).
- BACKLOG-LOOP-01 (merged 2cf7c92, live): digest tiers + absorption-warn + KPI health.
  §O.9 hardens it and re-derives its counts from the §O.3 oracle.
- NL-FINDING-024 (open, docs/findings.md:214): spawn writer→gate PreToolUse race
  (workstreams-emit --on-spawn entry 29 × workstreams-state-gate entry 30, same
  matcher; disk-sync window). §O.3's `nl why` drill uses a 024-class fixture; §O.4's
  trust-path retirement closes the class at the root.
- WORKSTREAMS-UI-PURPOSE-AUDIT-01 (backlog P1, operator verdict "failed completely"):
  disposition per sketch = keep the GUI shell, replace event-sourced truth with
  derived truth (§O.4).
- Scheduled-task registration lesson (docs/runbooks/session-resumer.md §Registration
  pattern, 2026-07-06): schtasks collapses nested quotes — ALWAYS wrapper `.cmd` +
  `wscript run-hidden.vbs` launcher, both in `~/.claude/scripts/`; verify
  `Last Result: 0` after a forced run. Any O-wave scheduled-task change follows this
  pattern, orchestrator-supervised, per-machine.

---

## §O.0.1 Serialization rules (BINDING on every builder)

1. **Orchestrator-only surfaces — builders NEVER edit:** `settings.json.template`,
   `manifest.json`, `harness-doctor.sh`, `install.sh`. Builders ship FRAGMENTS under
   `adapters/claude-code/tests/fixtures/wave-o/O.<n>/`:
   - `manifest-amendments.md` — complete entry JSON blocks, schema-valid
     (`schemas/manifest.schema.json`), incl. `jit_triggers` for new doctrine files.
   - `doctor-predicate.md` — complete `check_*()` bash function(s) + RED fixture +
     GREEN fixture descriptions mirroring the doctor's self-test pattern.
   - `template-wiring.md` — exact hooks-block JSON to add/REMOVE (removals are
     Wave-O-specific: §O.4 retires entries).
   - `install-sync.md` — only if a new top-level dir/file class needs the apply pass
     (hooks/*.sh, scripts/*.sh, schemas/*.json are already glob-synced — most tasks
     need NO install fragment; say "none" explicitly).
   The orchestrator integrates fragments serially, self-tests the composed result.
2. **Also builder-forbidden:** flipping plan checkboxes (task-verifier is the ONLY
   flipper), editing `docs/backlog.md` rows, editing other tasks' files. File-disjoint
   ownership is per the dispatch map (§O.0.2); a needed cross-file edit = STOP and
   report back, don't touch.
3. **Self-tests sandbox ALL writes** (findings 025/028/034): `HARNESS_SELFTEST=1`
   plumbing + explicit env overrides (`SIGNAL_LEDGER_PATH`, `NEEDS_YOU_STATE_DIR`,
   `NEEDS_YOU_MD_PATH`, `RETRY_GUARD_STATE_DIR`, new vars this wave:
   `HEARTBEAT_STATE_DIR`, `NTFY_STATE_DIR`, `NTFY_TOPIC_FILE`, `OBS_CONSUMER_MAP`,
   and — advocate review 2026-07-06: every C4 ground-truth input is redirectable —
   `OBS_TRANSCRIPTS_ROOT` (transcripts dir for od_costs/od_why/od_sessions),
   `OBS_MAIN_CHECKOUT` (git root for od_shipped_since), `OBS_DOCTOR_CACHE_DIR`
   (od_harness_health), `OBS_BACKLOG_PATH` (od_backlog_health)).
   No test writes to `~/.claude/state/`, `~/.claude/backups/`, or the real repo docs.
4. **Every fix ships a self-test mirroring the REAL flagless invocation shape**
   (findings 034/035/036 masked-defect class): at least one scenario invokes the
   artifact exactly as production wires it (no extra flags, no fixture-scoped paths
   on the command line) with only env-var sandboxing.
5. **CRLF:** verify byte-level with `cmp`/`tr`, never grep/od-piped-to-grep (findings
   030/038); all new `*.sh` inherit `eol=lf` from `.gitattributes` — do not add CRLF
   exceptions.
6. **Exit codes captured directly** (`rc=$?` on the command itself), never through
   `| tail`/`| head` pipelines.
7. **Git:** builders work ONLY in their assigned worktree/branch (`build/wave-o-<task>`);
   before assigning any new NL-FINDING or fixture ID, `git fetch origin master` and
   grep master + all `origin/build/wave-o-*` branches for the current max (4 collisions
   in one day during Wave E); never rebase a diverged branch — merge; push success is
   verified via `git ls-remote` (not local refs); `git branch --show-current` before
   any commit. Fix-edits are not commits — verify the commit call happened
   (NL-FINDING-016).
8. **Hook-budget invariants (doctor-enforced, F.1):** SessionStart is AT CAP (8/8) —
   NO new SessionStart entries; fold into existing hooks. Stop is 4/6 — Wave O adds
   NO new Stop entries; fold into the `workstreams-stop-writer.sh` chain or
   `stop-verdict-dispatcher.sh`. Blocking session-gates 10/12 — Wave O adds ZERO new
   blocking gates (doctor checks are not session gates) and §O.4 RETIRES two.
9. **No secrets:** the ntfy topic is a capability token — it lives ONLY in
   `~/.claude/local/ntfy-topic` (never repo, never docs, never chat, never fragments).
   The personal mirror is PUBLIC by design; treat every committed byte as published.
10. **Report-back shape:** each builder ends with: branch + SHAs, self-test
    invocation + PASS counts, fragment file list, livesmoke evidence (the real
    flagless run), and explicit "orchestrator TODO" list (fragments to integrate).

## §O.0.2 Dispatch map

| Batch | Task | Model | Branch | Files owned (disjoint) | Notes |
|---|---|---|---|---|---|
| 1 | O.1 emit extension + consumer map | sonnet | build/wave-o-o1 | `hooks/lib/signal-ledger.sh` (extend), `hooks/stop-verdict-dispatcher.sh` + `hooks/workstreams-stop-writer.sh` (span timing), `hooks/session-start-digest.sh` (lifecycle emit call ONLY — marked section), `observability-consumer-map.json` (new), fixtures wave-o/O.1 | |
| 1 | O.2 session heartbeat | sonnet | build/wave-o-o2 | `scripts/session-heartbeat.sh` (new), `hooks/lib/session-heartbeat-lib.sh` (new), fixtures wave-o/O.2 | Touch-points in digest/stop-writer are ONE marked call-line each — coordinate: O.1 owns those files; O.2 ships the call-lines as a fragment `callsite-wiring.md`; orchestrator splices |
| 1 | O.5 ntfy push | sonnet | build/wave-o-o5 | `scripts/ntfy-push.sh` (new), `scripts/needs-you.sh` (push call), fixtures wave-o/O.5 | Build + self-test now; live drill blocked on operator topic (NEEDS-YOU ask NY-open) — drill is an orchestrator step |
| 1 | O.8 estate-coordination protocol | sonnet | build/wave-o-o8 | `skills/coordinate-estate.md` (new), `doctrine/estate-coordination.md` (new), fixtures wave-o/O.8 | Pure docs+skill+drill fixture; no hook edits |
| 2 | O.3 derivation lib + nl CLI | sonnet | build/wave-o-o3 | `hooks/lib/observability-derive.sh` (new), `scripts/nl.sh` (new), fixtures wave-o/O.3 | Builds against §O.0.3 contracts; dispatched after batch-1 MERGE (reads O.1 events + O.2 heartbeats live) |
| 2 | O.9 backlog-loop hardening | sonnet | build/wave-o-o9 | `hooks/session-start-digest.sh` feed_backlog_accountability (refactor to oracle), KPI backlog-health section, plan-edit absorption validator, fixtures wave-o/O.9 | Builds against the §O.0.3 `od_backlog_health` CONTRACT in parallel with O.3 (contract-first; integration re-verified after both merge) |
| 2 | O.6 pipeline-health fragments | sonnet | build/wave-o-o6 | fixtures wave-o/O.6 ONLY (doctor predicates + red/green fixtures + schtasks-health helper `scripts/scheduled-task-health.sh` new) | Doctor itself is orchestrator-only; O.6 output is ~all fragments |
| 3 | O.4 cockpit rebuild | sonnet | build/wave-o-o4 | `workstreams-ui/**` (server, web, state facade), retirement fragments wave-o/O.4 | PRE-DISPATCH: ux-designer plan-time review of §O.4 (orchestrator runs it, folds findings into the dispatch prompt). POST-BUILD: end-user-advocate runtime acceptance (six-question drill) before verifier |
| 3 (serial, orchestrator) | integrate + verify | — | claude/wave-o-integration | the four orchestrator-only files | After each batch: merge, compose fragments, doctor --quick + goldens, adversarial task-verifier round (expect masked defects; Wave E needed 3 rounds) |
| 4 (serial) | O.7 retro | strongest available | — | docs/reviews/wave-o-retro.md | Measures the pre-registered metrics; runs the Q1–Q6 time-to-answer drill |

Parallelism ≤5 (batch 1 = 4 builders; batch 2 = 3). Builders get worktree isolation.
Orchestrator merges batch N fully (verify battery green) before dispatching batch N+1,
EXCEPT O.6 which may run during batch 2 (fragment-only output, no file contention).

## §O.0.3 Contracted interfaces (FROZEN — builders code against these)

### C1. Heartbeat file (written by O.2, read by O.3/O.6)

Path: `${HEARTBEAT_STATE_DIR:-$HOME/.claude/state/heartbeats}/<session-id>.json`,
one file per session, atomic write (tmp+mv), schema:

```json
{"schema":1,"session_id":"...","pid":12345,"cwd":"C:/...","repo_root":"C:/...",
 "worktree_root":"C:/... or same as repo_root","branch":"...","model":"...",
 "last_activity_ts":"ISO-8601-UTC","last_event":"start|turn-end|compact|resume",
 "marker_state":"DONE|PAUSING|BLOCKED|CONTINUING|none"}
```

Staleness is NEVER written — it is computed on read (law 1): stale =
`now - last_activity_ts > OBS_STALE_MIN` (default 30) AND no fresh transcript mtime
for that session. Crashed = stale + pid not alive. `marker_state` comes from the last
Stop-time scan of the final assistant message (same regex family as session-honesty).

### C2. New ledger event types (emitted by O.1, mapped in consumer-map)

Existing classes stay: `block|warn|waiver|downgrade|skip|flush|demote|soft-counter`.
Wave O adds (gate field = emitting hook, detail ≤1 line):
`session-start`, `session-stop`, `session-compact`, `session-resume`,
`throttle-detected`, `spawn-dispatched`, `spawn-concluded`, `bg-task-started`,
`bg-task-finished`, `turn-trace`.
`turn-trace` detail is a compact JSON string:
`{"hooks":[{"n":"<basename>","ms":123,"v":"allow|block|warn|n/a"}],"total_ms":456}` —
emitted once per Stop by each chain aggregator for its own members (that is the cheap
mechanical tap; per-hook PreToolUse spans are OUT of scope — their verdict events
already land individually).

### C3. Consumer map (created by O.1, doctor-read via O.6)

Path: `adapters/claude-code/observability-consumer-map.json` (synced live by install
glob? NO — top-level new file: O.1 ships `install-sync.md` fragment adding it).

```json
{"schema":1,"event_types":{
  "block":{"consumers":["digest:feed_ledger_summary","cli:nl-status","doctor:check_obs_consumer_map"]},
  "turn-trace":{"consumers":["cli:nl-why"]}, "...":{}}}
```

Invariant (law 2, doctor-enforced by O.6): every event type observed in the ledger
(last 1000 lines) AND every literal event string passed to `ledger_emit` in the repo
has an entry with ≥1 consumer. Unknown-in-map = RED naming the type.

### C4. Derivation lib API (O.3 implements; O.9/O.4/O.6 consume)

File: `adapters/claude-code/hooks/lib/observability-derive.sh` — pure READ functions,
zero state writes, every function has `--json` mode; every COUNT output names its
oracle inline (CANONICAL-COUNTERS-01 rule: `"<n> <thing> (oracle: <definition-id>)"`).

- `od_sessions [--json]` — Q1. Enumerates heartbeat files + transcript mtimes +
  resumer classification signals; per session: state ∈
  `working|blocked|waiting-on-me|throttled|stalled|crashed|unobserved-cloud`; joins
  NEEDS-YOU `has-entry-for-session` for waiting-on-me; honest `unobserved: cloud`
  for sessions with no local heartbeat (sketch edge case).
  DERIVATION RULES (advocate plan-time review 2026-07-06 — every enum value has a
  written ground-truth rule; builders never invent one): `waiting-on-me` =
  needs-you open entry joined on session id (trumps all below); `crashed` = C1
  stale AND pid not alive; `stalled` = C1 stale AND pid alive (chip detail carries
  pid-liveness); `throttled` = ledger `throttle-detected` (or resumer 429-class
  event) newer than the session's last activity; `blocked` = newest ledger `block`
  event for the session is newer than its last transcript activity (a block it has
  not yet responded past); `unobserved-cloud` = session id appears in ledger
  lifecycle/spawn events or a remote ledger but has NO local heartbeat AND no
  local transcript — unknown fields render as unknown, never fabricated;
  `working` = fresh heartbeat, none of the above. Priority on ties: waiting-on-me
  > crashed > stalled > throttled > blocked > working.
- `od_needs_me [--json]` — Q2. Parses `~/.claude/state/needs-you/ledger.json`
  (THE oracle; never re-derives from the rendered md).
- `od_shipped_since <iso-ts> [--json]` — Q3. git log on main checkout master:
  shipped SHAs + subjects, plans transitioned (COMPLETED/archived), decide-and-go
  decisions (docs/decisions/ added), failures (ledger block/downgrade events in window).
- `od_harness_health [--json]` — Q4. Doctor cached verdict + per-gate 7d
  block/waiver/downgrade counts from ledger (waiver-dominant flag per E.3).
- `od_costs [--session <id>] [--json]` — Q5. Sums transcript JSONL `usage` blocks
  (tail-first read, tolerates partial/rotated transcripts, labels stale sections);
  throttle events + estimated time lost from `throttle-detected`/resumer events.
- `od_backlog_health [--json]` — THE backlog oracle (O.9's single definition):
  open rows (position-anchored terminal-marker detection — same algorithm the loop
  shipped in 87f357f, extracted here as the one implementation), per-priority counts,
  age tiers (high>7d, medium>30d, low>90d), adds-vs-terminal 7d.
- `od_why <session-id> [--last-block] [--json]` — Q6 core: ledger events for the
  session (time-ordered, all gates) joined with transcript hook-relevant lines →
  causal chain: hooks fired → state read → verdict → session's response.

### C5. `nl` CLI (O.3): `adapters/claude-code/scripts/nl.sh`

Subcommands: `nl status` (Q1, plus one-line Q4 header), `nl needs-me` (Q2),
`nl why <session> [--last-block]` (Q6), `nl costs [<session>]` (Q5),
`nl shipped [--since <ts>]` (Q3), `nl backlog` (od_backlog_health), each `--json`.
Thin dispatcher over C4; `--self-test` sandbox-seeds fixture heartbeats/ledger/
transcripts and asserts each subcommand's output shape. Installed via existing
scripts/*.sh glob (no install fragment).

---

## §O.1 Emit extension + turn-traces + consumer map

**Deliverables.**
1. `hooks/lib/signal-ledger.sh`: add `ledger_emit_typed` = alias of `ledger_emit`
   (no schema change — the 5-field JSONL line is FROZEN); add a comment-registry
   listing all known event types + pointer to the consumer map. No breaking changes;
   existing callers untouched.
2. Lifecycle events: `session-start` emitted from a marked call in
   `session-start-digest.sh` main (file owned by O.1 this batch); `session-stop` +
   `turn-trace` from `stop-verdict-dispatcher.sh` and `workstreams-stop-writer.sh`
   (each aggregator times its own chain members via `date +%s%3N` deltas and emits
   ONE turn-trace event per Stop); `session-compact` from the PreCompact hook's
   existing flow (`pre-compact-continuity.sh` — add one emit line);
   `session-resume`/`throttle-detected` — the resumer already emits via
   `ledger_emit`; NORMALIZE its event names to C2 (keep old names as detail text).
3. Spawn/task events: `spawn-dispatched`/`spawn-concluded` emitted from
   `workstreams-emit.sh` --on-spawn/--on-stop paths (one emit line each — these
   survive §O.4 retirement decisions because the LEDGER, not the tree, is the spine);
   `bg-task-started`/`bg-task-finished` from the existing background-task touchpoints
   if a mechanical tap exists; if none exists, document the gap in the report-back
   (law: no cooperative-discipline mechanisms) — do NOT invent a convention.
4. `observability-consumer-map.json` per C3, seeded with ALL types (existing 8 + new
   10), every entry ≥1 real consumer (the C4/C5 consumers count once O.3 lands —
   name them now, that is the point of the map).
5. Fragments: `manifest-amendments.md` (writer entries for new emit points;
   consumer-map as a governed artifact), `install-sync.md` (consumer-map sync line),
   `doctor-predicate.md` — none (O.6 owns doctor); `template-wiring.md` — none
   (no new settings entries; budget rule §O.0.1-8).

**Self-test** (sandboxed per §O.0.1-3/4): each new event class lands exactly one
schema-valid JSONL line under a fixture `SIGNAL_LEDGER_PATH`; turn-trace detail
round-trips through `jq`; the flagless-shape scenario invokes the real dispatcher
with a fixture Stop-JSON stdin and asserts the trace event appears.

**Done-when** (plan): self-test proves each event class lands; consumer-map covers
100% of event types (O.6's doctor predicate is the enforcement; O.1 ships the map
correct on day one).

## §O.2 Session heartbeat

**Deliverables.**
1. `scripts/session-heartbeat.sh` — verbs: `touch --event <start|turn-end|compact|resume>
   [--marker <state>]` (atomic write per C1; reads pid/cwd/branch/model from env +
   `git branch --show-current` in `$CLAUDE_PROJECT_DIR`; never blocks, exit 0 always),
   `sweep` (report-only: list stale/crashed per C1 rules — computation lives here,
   shared with od_sessions via sourcing `hooks/lib/session-heartbeat-lib.sh`),
   `--self-test`.
2. `hooks/lib/session-heartbeat-lib.sh` — `hb_path_for <sid>`, `hb_write <event> <marker>`,
   `hb_is_stale <file>`, `hb_classify <file>` (the C1 read-side rules; single
   implementation for O.3).
3. Call-site fragment `callsite-wiring.md` (orchestrator splices; O.1 owns the files):
   one line in `session-start-digest.sh` main (`session-heartbeat.sh touch --event start`),
   one line in `workstreams-stop-writer.sh` chain (`touch --event turn-end --marker <scanned>`),
   one line in `pre-compact-continuity.sh` (`touch --event compact`).
4. Fragments: `manifest-amendments.md` (writer entry, selftest:true). No template/
   install/doctor fragments (globs cover scripts+lib; O.6 owns doctor freshness).

**Self-test:** fixture `HEARTBEAT_STATE_DIR`; touch→file schema-valid (jq); staleness
math (fixture old ts → stale; fresh → live); crashed = stale + dead pid (use a
just-exited subshell pid); flagless-shape scenario: invoke via the exact spliced
call-line with env sandbox only.

**Done-when** (plan): kill-drill — kill a sacrificial session, its heartbeat goes
stale and `nl status` reports stalled within one refresh (orchestrator runs this
drill after O.3 merges; O.2's own bar = self-test + livesmoke `touch`+`sweep` on the
real estate listing this session as live).

## §O.3 Derivation lib + `nl` CLI

**Deliverables.** C4 lib + C5 CLI, exactly. Plus:
1. CANONICAL-COUNTERS-01 rule encoded: every count in every output names its oracle;
   `doctrine/observability.md` (new, compact) documents the rule ("never report an
   estate count from an ad-hoc query when a canonical oracle exists; else name the
   definition inline") + the six questions + `nl` usage; manifest fragment carries
   the doctrine file + jit_triggers (paths: scripts/nl.sh, lib/observability-derive.sh;
   keywords: "estate count", "nl status").
2. `nl why` (Q6): given a session id, merge (a) ledger lines for that session_id,
   (b) that session's transcript hook_progress/tool_use entries — into a time-ordered
   causal chain with one line per step: `ts  gate  event  detail`. `--last-block`
   narrows to the newest block event ± context. Output ends with a one-line verdict:
   what blocked, which state it read, what the session did next.
3. 024-class fixture: seeded ledger + transcript reproducing the spawn writer→gate
   race shape (spawn-dispatched event, state-gate block event "verified snapshot has
   no live node naming this spawn's branch", retry, allow). Self-test asserts
   `nl why <fixture-sid> --last-block` names the writer, the gate, the ordering, and
   the retry in ≤20 output lines. (This is the sketch's "024 diagnosis in ~2 min"
   inverted into a mechanical oracle.)
4. Cross-machine: `od_sessions` reads BOTH ledgers when
   `~/.claude/state/remote-ledgers/*.jsonl` exist (read-both per sketch; no sync
   built — out of scope).

**Self-test:** fixture estate (heartbeats + ledger + transcripts + needs-you ledger +
backlog file) under env overrides; each subcommand asserts exact-shape output; every
count line matches `oracle:` regex; tail-first partial-transcript scenario (truncated
JSONL mid-line) must not error and must label the stale section.

**Done-when** (plan): drill — Q1–Q5 each answered <10s on the LIVE estate (orchestrator
times it); 024 fixture end-to-end. Strongest-available model reviews `nl why` output
quality before the verifier flips (dispatch map batch-2 note; orchestrator runs the
review inline).

## §O.4 Cockpit rebuild (the Workstreams UI redesign)

**Pre-dispatch gate (orchestrator):** ux-designer plan-time review of THIS section +
the sketch's six-questions spec; findings folded into the builder prompt. In the same
pass, end-user-advocate PLAN-TIME mode authors `## Acceptance Scenarios` for the
six-question drill (doctrine/acceptance-scenarios.md loop) — the runtime run executes
exactly those scenarios.
**Post-build gate:** end-user-advocate runtime acceptance — the six-question drill in
the GUI, PASS artifact recorded (constitution §4).

**Deliverables.**
1. `workstreams-ui/server/server.js`: replace tree-state reads with derived JSON:
   shells `nl <sub> --json` (batch-refreshed ≤ every 30s into an in-memory cache +
   on-demand refresh endpoint; SSE keeps pushing refresh events). Keep port 7733,
   launcher scripts, autostart registration (any scheduled-task change follows the
   runbook wrapper-cmd pattern, orchestrator-applied).
2. `workstreams-ui/web/`: six-questions layout — panes: (Q1) session board with
   state chips (working/blocked/WAITING-ON-ME/throttled/stalled/unobserved-cloud),
   (Q2) needs-me list rendering the §3-format blocks from `nl needs-me --json` with
   clickable links, (Q3) diff-since-last-look (persist last-look ts client-side),
   (Q4) harness health strip (doctor verdict + waiver-dominant gates), (Q5) costs
   strip, (Q6) a per-session "why" drawer calling `nl why`. Empty/loading/error/ideal
   states per surface (ux-designer will check exactly this).
3. **Divergence reconciler** (law 1's escape hatch): while any legacy tree-state
   consumer remains, a reconciler compares tree-state-derived session/branch claims
   vs `nl status --json` and renders a visible "derived-vs-displayed drift" badge +
   emits ledger event `warn` gate=cockpit-reconciler on mismatch. The cockpit NEVER
   renders tree-state as truth. LIFECYCLE (advocate review): badge renders in the
   primary viewport; quiet state reads "reconciler: 0 drift (checked <ts>)"; it
   CLEARS on reconvergence (reflects current state, never latched); the warn event
   is emitted once per distinct mismatch SIGNATURE (dedup key = sorted
   session/branch claims), never per refresh tick.
3b. **Interrupt priority + freshness (BINDING layout rules, ux-designer +
   advocate reviews 2026-07-06 — see docs/reviews/2026-07-06-o4-cockpit-ux-review.md
   for the full 13 amendments, all binding):** on load, WAITING-ON-ME rows sort
   above all other session states and open NEEDS-YOU entries render above
   Q3/Q4/Q5 content, both inside the initial viewport with mechanically distinct
   emphasis (ONE accent color, spent only on interrupt-worthy classes). Every pane
   shows its derived-as-of timestamp; cache served during derivation failure is
   explicitly labeled stale (rc≠0 renders ERROR, never empty); a visible Refresh
   control triggers the on-demand endpoint with in-flight/failed feedback; Q3
   shows its last-look timestamp with an explicit Mark-seen control.
4. **Trust-path retirement** (fragments; orchestrator integrates + decides timing):
   the UI stops reading `tree-state.json`; then per law 2 the consumer map shows the
   tree pipeline consumer-less → retirement fragments: REMOVE from template+manifest:
   `workstreams-state-gate.sh` (PreToolUse entry 30) and `workstreams-stop-gate.sh`
   (via stop-writer chain) — the two blockers whose only protected consumer was the
   tree (this closes NL-FINDING-024 at the ROOT; blocking budget 10→8);
   `workstreams-turn-emit.sh` + `workstreams-extract-pending.sh` item-extraction
   (superseded by needs-you.sh per its own header) → retire to attic/.
   KEEP: `workstreams-emit.sh` spawn/stop paths ONLY as re-pointed ledger emitters
   (O.1), the correlation ledger (resumer reads it), heartbeat tick (re-pointed to
   `session-heartbeat.sh sweep` semantics stays an O.6 health surface).
   Every removal lands as `template-wiring.md`/`manifest-amendments.md` fragments +
   an attic/ move list; NOTHING is deleted outside attic/ (salvage-before-reset).
5. Findings hygiene: fragment updates `docs/findings.md` NL-FINDING-024 → closed
   (root retired + `nl why` fixture demonstrates the historical diagnosis) — ships as
   a proposed diff in the report-back; the ORCHESTRATOR applies findings edits.

**Self-test:** server unit self-test with a fixture `nl` stub (env `NL_BIN` override)
asserting each pane endpoint returns derived JSON + the reconciler flags a seeded
mismatch; web smoke via the existing launcher (livesmoke: real `nl`, real estate).

**Done-when** (plan): operator exercises the six questions in the GUI; acceptance
scenario recorded (end-user-advocate artifact). Verifier flips only after that
artifact exists.

## §O.5 Push (ntfy.sh) — exactly three rules

> **DESCOPED by operator 2026-07-07** (no phone observability wanted; see plan O.5
> terminal disposition + memory `no-phone-observability`). The built script stays
> dormant (topic-absent no-op is self-tested); scan-tick wiring and the phone drill
> are cancelled. Spec text below retained for the record.

**Deliverables.**
1. `scripts/ntfy-push.sh`: verbs `send --class <needs-you|stalled|doctor-red>
   --title <t> --body <b>` (reads topic from `${NTFY_TOPIC_FILE:-$HOME/.claude/local/ntfy-topic}`;
   topic absent → exit 0 silent no-op; UNKNOWN --class → exit 1, NO network — the
   negative is a hard contract); `scan` (stalled/throttled >N min via
   `hb_classify`/od_sessions when available, doctor cached-verdict RED transition,
   new NEEDS-YOU open entries; dedup via `${NTFY_STATE_DIR:-$HOME/.claude/state/ntfy}/sent.jsonl`
   — one push per item-id, ever, unless item recreated); `--self-test` (network
   mocked via `NTFY_CURL_CMD` override; asserts all three classes format, the
   negative class-rejection, the dedup, and topic-absent no-op).
2. `needs-you.sh add` gains one guarded call:
   `ntfy-push.sh send --class needs-you ...` (best-effort, never blocks add).
3. `scan` wiring: one line appended to the EXISTING 5-min heartbeat tick wrapper
   `.cmd` (per-machine, orchestrator-applied per runbook pattern) — no new scheduled
   task.
4. Fragments: `manifest-amendments.md` (surfacer entry). No template fragment.

**Operator input (front-loaded, NEEDS-YOU id in the O.0 commit message):** the ntfy
topic string (or NTFY-DEFER). Builder proceeds without it; the LIVE drill is an
orchestrator step after the reply.

**Done-when** (plan): drill fires all three classes to the operator's phone; the
negative is tested (no other class can reach push).

## §O.6 Pipeline health in doctor (fragments-only task)

**Deliverables** — `doctor-predicate.md` fragments (each with RED + GREEN fixtures)
for orchestrator integration, plus `scripts/scheduled-task-health.sh` (new, owned
file: queries `schtasks /Query /V /FO LIST` per NL-owned task name pattern `NL-*` +
the heartbeat task; outputs name + Last Result; `--self-test` with fixture query
output — this keeps doctor thin and testable):
1. `check_obs_writers_firing` — ledger mtime <24h AND line-count grew since the
   doctor cache's last stamp (stamp file in doctor cache dir).
2. `check_obs_heartbeats_fresh` — every session with a transcript mtime <30min has a
   heartbeat file (else RED naming sids); zero live sessions = GREEN. MUST consume
   the canonical read-side oracle in `hooks/lib/session-heartbeat-lib.sh`
   (`hb_classify`/`hb_is_stale`, C1 transcript-mtime join) rather than
   re-implementing heartbeat-file-mtime staleness math locally — a raw-mtime
   re-implementation cannot see that heartbeats only refresh at Stop, so it
   false-REDs any session whose current turn runs past the 30min window even
   though the session is demonstrably alive (fixed 2026-07-06, duplicated-
   staleness-oracle / mid-turn false-stall, O.6 re-verifier FAIL conf 9). RED
   fires ONLY when `hb_classify` returns `missing` (no heartbeat file at all for a
   live-transcript session — the genuine writer-not-wired signal); a present
   heartbeat that is stale-by-mtime-but-transcript-fresh classifies `live` via the
   lib's own join and must NOT RED.
3. `check_obs_scheduled_tasks` — SCHEDULED-TASK-HEALTH-01: every registered NL-owned
   task has Last Result ∈ {0, 267009 running, 267011 not-yet-run}; else RED naming
   task + code. Not-registered stays the existing WARN semantics.
4. `check_obs_consumer_map` — C3 invariant (two-sided: ledger-observed types ⊆ map;
   repo-emitted literals ⊆ map; every map entry ≥1 consumer).
5. `check_obs_cockpit_fresh` — WARN (not RED) if the cockpit server is registered
   for autostart but its derived-cache stamp is >1h old while sessions are live;
   GREEN when server intentionally not running (cockpit is optional per machine).
6. `check_needs_you_headers` — E6-HEADER-HARDENING-01: when needs-you ledger
   open-count >0, NEEDS-YOU.md contains all 4 `NY_CANONICAL_HEADERS`.

**Done-when** (plan): red-fixtures per check; live GREEN after integration.

## §O.7 Retro (strongest model, serial, last)

`docs/reviews/wave-o-retro.md` vs the sketch's pre-registered metrics: measured
median time-to-answer Q1–Q6 (drill transcript cited), consumer-map coverage
(doctor output), operator-trust check (the inverted Workstreams question: does the
operator consult the cockpit instead of asking sessions? — ask directly), plus
deviations-from-spec log and findings filed. Done-when: doc exists with measured
numbers (no vibes).

## §O.8 Estate-coordination protocol

**Deliverables.**
1. `skills/coordinate-estate.md` — the 2026-07-04 manual run mechanized:
   inventory (list_sessions), classify each session
   `active | stalled>2h | wedged-undeliverable | superseded`, re-home orphan work via
   `nl-issue.sh`, stand-down superseded satellites (message queued IN THEIR channel,
   file-based), freeze-window protocol (declare in main-checkout SCRATCHPAD
   coordination section; satellites land-or-hold; cutover owner proceeds on ACTIVE
   flag; unfreeze line), spawn-time supersession check (grep master + origin branches
   for an existing fix BEFORE building). File-based channels ONLY — send_message is a
   per-message-confirmed nudge, never an orchestration primitive. Chips wedge on
   unattended permission dialogs → autonomous satellites are ORCHESTRATOR-OWNED Agent
   worktree dispatches (the O.8 lesson from SCRATCHPAD).
2. `doctrine/estate-coordination.md` (compact) + manifest fragment with jit_triggers
   (paths: SCRATCHPAD.md; keywords: "freeze", "coordinate sessions", "stand down").
3. Drill fixture: a seeded stale-session fixture (transcript + dead heartbeat) that
   the skill's classification steps label correctly and whose orphan task lands one
   nl-issue line (sandboxed `NL_ISSUES_PATH`).

**Done-when** (plan): skill + doctrine exist with JIT trigger; drill passes;
coordination-section format documented.

## §O.9 Backlog accountability loop hardening

BACKLOG-LOOP-01 is LIVE (2cf7c92: digest tiers, absorption-warn, KPI health;
87f357f: position-anchored terminal-marker fix). O.9 = derive it from ground truth:
1. Extract the row-parsing/terminal-marker/age-tier logic from
   `feed_backlog_accountability` (+ its two sibling consumers) into the ONE oracle
   `od_backlog_health` (C4 contract; O.3 owns the lib file — O.9 ships the extracted
   functions as a reviewed patch against the CONTRACT, coordinated at orchestrator
   merge), then re-point all three consumers.
2. Digest proposals stay idempotent per item-week; disposition words
   `SCHEDULE|FOLD|DEMOTE|WONTFIX` documented in doctrine/observability.md §backlog.
3. KPI backlog-health section reads the oracle (adds-vs-terminal 7d, aging histogram,
   priority counts).
4. Plan-edit absorption validator: on plan-file edits, grep backlog rows naming
   plan-touched surfaces; warn lists each unabsorbed row id (existing behavior,
   re-pointed to the oracle's row model).

**Self-test:** seeded aged fixture rows surface exactly once per tier with correct
proposals; fixture plan touching a backlog-named surface without absorbing → warn;
KPI fixture renders; terminal-marker positional cases from 87f357f regression-covered.

**Done-when** (plan): the above + drill — operator answers one digest proposal word
and the row reaches terminal state (orchestrator drill post-merge).

---

## §O.0.4 Verification battery (orchestrator, after every batch merge)

1. Composed-surface self-tests: doctor --self-test, manifest-check, affected hooks'
   --self-test.
2. `harness-doctor.sh --quick` GREEN on the integrated tree's live mirror after
   install; goldens 6/6; synthetic where touched.
3. Adversarial task-verifier round per task (checkbox flips ONLY there); expect
   masked defects (Wave E: 3 rounds) — fixers must follow §O.0.1-4.
4. Drills in Done-whens are ORCHESTRATOR-run on the live estate, cited with output.
5. Push both remotes (gh auth switch dance for personal), verify via `git ls-remote`.

## §O.0.5 Decisions log (decide-and-go, constitution §8 — for operator §8 review)

- D-O1 `nl` = new `scripts/nl.sh` dispatcher + `hooks/lib/observability-derive.sh`
  (no existing dispatcher; hooks/lib is the shared-lib precedent). Reversible.
- D-O2 Heartbeat = per-session JSON (C1) written from existing chains (budget caps:
  SessionStart 8/8, Stop 4/6 — zero new settings entries). Reversible.
- D-O3 Turn-traces from the two Stop aggregators only; PreToolUse per-hook spans out
  of scope (their verdicts already land; full instrumentation = cooperative-discipline
  risk + budget cost). Reversible; revisit at O.7 if `nl why` drill shows gaps.
- D-O4 §O.4 retires the tree trust path INCLUDING both workstreams gates (closes
  NL-FINDING-024 at root; blocking budget 10→8) — per law 2 once the cockpit stops
  consuming the tree. Retirement via attic/ + fragments; one revert restores.
- D-O5 ntfy topic = capability token, lives only in ~/.claude/local/ntfy-topic;
  push script no-ops without it (program never blocks on the operator reply).
- D-O6 O.9 builds against the C4 contract in parallel with O.3 (contract-first);
  merge-time reconciliation owned by orchestrator. Reversible (worst case: serial
  re-run of O.9).
