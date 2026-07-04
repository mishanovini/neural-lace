# Wave E specs — signal loop + telemetry: exact per-task build specs (appendix to nl-overhaul-program-2026-07.md)

Authored by the Wave-E orchestrator (E.0), 2026-07-03, immediately after the Wave-E
reconciliation merge (ADR 059 estate + the parallel E.8/E.9 task strand; the ADR 059
tasks were renumbered E.8→E.11 and E.9→E.12 at that merge — see the plan's Decisions
Log). Waves A–D are live: doctor GREEN, Stop=6 / SessionStart=8 / blocking units 12/12,
signal-ledger lib + surfacer pack + attic shims all on master.

## §E.0.1 Serialization rules for this wave (binding on every builder)

The Wave-D collision lessons generalize; these four surfaces are ORCHESTRATOR-ONLY
this wave — builders MUST NOT edit them (build hooks + self-tests only; wiring lands
at §E.W integration, mirroring "wiring lands in D.5, not here"):

1. `adapters/claude-code/settings.json.template` — E.1 (SessionStart entry swap),
   E.9a (PostToolUse add), E.9b (PreCompact add), E.11 (Stop chain rewrite) all touch
   it. Orchestrator applies all four at §E.W.
2. `adapters/claude-code/manifest.json` — every new hook needs an entry; builders
   ship a `manifest-entry.json` FRAGMENT (one object, schema-valid) beside their hook
   under `adapters/claude-code/tests/fixtures/wave-e/<task>/`; orchestrator merges.
3. `adapters/claude-code/hooks/harness-doctor.sh` — E.6/E.7/E.8/E.9/E.10 all add
   checks. ONLY the E.10 builder edits the doctor (it owns the manifest-freshness
   check anyway); other builders document their check as a PREDICATE (exact command +
   RED condition + fixture) in their section's `doctor-predicate.md` fragment, which
   E.10 implements verbatim.
4. `adapters/claude-code/install.sh` — E.10 only (NL-FINDING-017 backup fix +
   NL-FINDING-022 heartbeat registration).

Builder protocol (unchanged from Wave D, all findings-hardened): first action
`git rev-parse --git-dir` ≠ `--git-common-dir` else STOP (NL-FINDING-014); second
action `git checkout -b worker-E.<n> <dispatch-sha>`; no plan edits; fix-calls and
commit-calls are SEPARATE Bash invocations (NL-FINDING-016); grep-verify every
scripted edit (CRLF); re-run `--self-test` after ANY block/warn message edit
(quote-nesting broke 3 cases on 2026-07-03); self-tests pin the canonical repo root
via `hooks/lib/nl-paths.sh`, never ambient cwd (SELFTEST-ORACLE-PIN-01).

## §E.0.2 Dispatch map (orchestrator)

| Batch | Task | Model | Branch | Key outputs (all + self-tests + fragments) |
|-------|------|-------|--------|--------------------------------------------|
| 1 | E.1 | sonnet | worker-E.1 | `hooks/session-start-digest.sh`, monitor-probe emission fix |
| 1 | E.2 | haiku | worker-E.2 | sandbox sweep, pollution purge script, NL-FINDING-025 tempdir isolation |
| 1 | E.7 | sonnet | worker-E.7 | `scripts/session-resumer.sh` + fixtures (registration = §E.W) |
| 1 | E.8 | sonnet | worker-E.8 | `scripts/nl-issue.sh` + skill |
| 1 | E.9 | sonnet | worker-E.9 | `hooks/context-watermark.sh`, `hooks/pre-compact-continuity.sh`, `scripts/session-snapshot.sh` |
| 2 | E.3 | sonnet | worker-E.3 | `scripts/waiver-density.sh` (digest + backlog append) |
| 2 | E.4 | sonnet | worker-E.4 | 3 deferred scenarios + design-skip companion plan + CI workflow |
| 2 | E.5 | haiku | worker-E.5 | `scripts/harness-kpis.sh` |
| 2 | E.6 | sonnet | worker-E.6 | `scripts/needs-you.sh` + NEEDS-YOU.md machinery |
| 2 | E.10 | sonnet | worker-E.10 | pins-d/e/f retrofit + doctor edits + install.sh fixes + findings 017/019/020/022/023/024/026/027 |
| 3 | E.11+E.12 | sonnet | worker-E.11 | `hooks/stop-verdict-dispatcher.sh` + end-manifest (ONE builder — same file cluster as E.10; dispatched only after E.10 merges) |

Batch 2 dispatches after batch 1 merges (E.3/E.5 consume digest surfaces; E.10's
message sweep must not race E.2's sandbox edits in the same hooks). Batch 3 after
batch 2 (E.11/E.12 rewrite the same gates E.10 just swept). ≤5 builders live at once.

## §E.W Wave-E integration runbook (SERIAL, orchestrator)

1. Tag `pre-wave-e-cutover` before any template edit. 2. Merge batch branches
(verify tips on disk, never builder claims). 3. Template edits: SessionStart entry 8
`session-start-surfacer-pack.sh` → `session-start-digest.sh`; add PostToolUse
`context-watermark.sh`; add PreCompact (auto+manual) `pre-compact-continuity.sh`;
after batch 3: Stop chain 6→4 per §E.11. 4. Merge builders' manifest fragments;
`manifest-check.sh` green. 5. Install; doctor --quick AND --full green; golden evals
green; `evals/synthetic/run-all.sh` green (8/8 after E.4, no deferred lines).
6. E.7 registration: `schtasks /Create` per §E.7 (+ NL-FINDING-022 heartbeat task per
§E.10.6) — then the kill-and-resume drill on a sacrificial session. 7. Chain-count
assertions on template AND live. 8. Merge to master via PR when green; push BOTH
remotes (gh auth switch per account map; restore after).

## §E.1 session-start-digest.sh — exact spec

New `adapters/claude-code/hooks/session-start-digest.sh` (SessionStart, non-blocking).
Replaces the TRANSITIONAL `session-start-surfacer-pack.sh` entry (specs-d §D.0.3 #8);
the pack members stay on disk (attic at F-wave) but their SessionStart voice becomes
ONE block, hard-capped at 15 output lines (assert in self-test: `wc -l ≤ 15`).

- **Feeds (call each member in --collect mode or read its state dir directly):**
  pending discoveries (`docs/discoveries/*.md` status:pending count + oldest), stale
  ACTIVE plans, external-monitor alerts (unacked count post-dedup), spawned-task
  results (unacked), pending decisions, git freshness (branch vs both remotes),
  worktree count/age advice, doctor --quick verdict line (reuse its exit code — do
  not re-run checks), ledger 24h summary (blocks/warns/waivers/downgrades via
  `ledger_tail`), nl-issues untriaged count (§E.8; tolerate absent file), waiver-density
  alarm line (§E.3; tolerate absent), unresolved-gaps entries (§E.11; tolerate absent),
  NEEDS-YOU.md link + open-item count (§E.6; tolerate absent).
- **Line economy:** one line per NON-EMPTY feed, `<icon> <feed>: <count> <one-line
  summary> → <path or command>`; feeds with nothing to say emit NOTHING (a quiet
  harness produces a 2-line digest: doctor verdict + "all quiet").
- **Dedup + auto-expiry + auto-ack:** state at `~/.claude/state/digest/seen.jsonl`
  {feed, item-key, first-seen, count}. An item surfaced ≥3 sessions with no state
  change collapses into a count suffix ("+N repeats"); monitor alerts that are
  byte-identical duplicates of an acked class are AUTO-ACKED (`.acked` sibling) with
  one ledger event per class, not per file.
- **NL-FINDING-021 fix (same task, upstream of the digest):** the external-monitor
  probe writer must NOT emit an alert whose anomaly string is empty or whose health
  field is "healthy" (fix at the emission site; grep the probe script for the
  alert-write and add the guard). Ack the 32 stale `principles-gate-r3` duplicates as
  ONE class via a dated `.acked` sweep + one ledger event citing NL-FINDING-021.
- **GUI mirror (demoted-optional per the operator's Workstreams verdict):** emit the
  digest body via `workstreams-emit.sh --digest` if that entry point exists; if not,
  skip silently — do NOT build new GUI plumbing.
- `--self-test` ≥8 scenarios: cap enforced on an everything-firing fixture; empty
  feeds silent; dedup collapse; auto-ack class (fixture alert dir); missing-feed
  tolerance (no §E.3/E.8/E.11 files); doctor-line passthrough; monitor-emission guard
  (fixture probe with empty anomaly produces NO alert file); HARNESS_SELFTEST sandbox.
- Done-when: self-test green; fixture digest ≤15 lines; probe-guard grep present;
  zero unacked pre-2026-07-04 principles-gate-r3 alerts on the live machine.

## §E.2 HARNESS_SELFTEST sandbox sweep — exact spec

- Enumerate from manifest.json every entry with `selftest: true`; for each hook,
  verify its self-test writes state/ledger ONLY under the sandbox dir when
  `HARNESS_SELFTEST=1` (the D.1 shared helper in `lib/signal-ledger.sh` is the
  pattern; extract `lib/selftest-sandbox.sh` if ≥3 hooks hand-roll it).
- Purge existing self-test pollution from production logs/state: identify by the
  self-test marker patterns (fixture slugs, tmpdir paths) in
  `~/.claude/logs/*.log` + `~/.claude/state/*.jsonl`; ship
  `scripts/purge-selftest-pollution.sh` (dry-run default, `--apply` flag, prints
  per-file line counts removed). Run --apply once at §E.W.
- NL-FINDING-025 remediation (assigned here): work-integrity-gate self-test gets
  per-scenario UNIQUE tempdirs (mktemp -d per scenario, not shared) + retry-guard
  state isolation per scenario; then run the full suite 5x consecutively — all green
  = the finding's refutation condition executed (record result in the finding entry).
- Done-when (review finding 9 anchor, unchanged from the plan): fresh install to a
  TEMP HOME; hash the manifest-derived production state/ledger file list; run the
  full self-test sweep; hash again — identical. Plus: 5x work-integrity suite green;
  purge script self-test (fixture log in, pollution out, real lines intact).

## §E.3 waiver-density alarm — exact spec

- New `scripts/waiver-density.sh`: reads the signal ledger, computes per-gate waiver
  count over a 7-day sliding window; threshold ≥3 → (a) emits the digest line
  "⚠ waiver-density: <gate> N waivers/7d → fix-or-retire item filed"; (b) IDEMPOTENTLY
  appends the backlog entry `WAIVER-DENSITY-<GATE>-<yyyymmdd>` ("fix or retire <gate>:
  N waivers in 7d; ledger refs inline") — idempotence = grep for the ID before append.
- The E.5 KPI report calls the same script (`--report` mode, table for all gates).
  ADR 059 D7 auto-DEMOTION explicitly does NOT land here — that is F.5; this task
  detects + files only.
- `--self-test`: fixture ledger with 3 waivers on one gate → digest line + backlog
  entry in a sandbox backlog copy; 2 waivers → silence; re-run → no duplicate entry.
- Done-when: self-test green; digest (E.1) renders the line from the fixture.

## §E.4 synthetic-runner completion — exact spec

- Build the 3 deferred scenarios against the NOW-LIVE Wave-D gates, then delete
  `deferred.txt` (run-all must report 8/8, zero SKIPPED-deferred):
  `scenario-false-done.sh` — session-honesty-gate blocks DONE-while-work-integrity-
  blocked (bad) / honest DONE passes (good); `scenario-marker-missing.sh` — no marker
  blocks / single marker passes; `scenario-waiver-abuse.sh` — stale (>1h) and
  empty-reason waivers are REJECTED by work-integrity checks / fresh substantive
  waiver honored. Follow the existing scenario pattern (mktemp fixture,
  HARNESS_SELFTEST=1, bad-blocks + good-passes pair).
- Author the `Mode: design-skip` companion plan
  `docs/plans/nl-overhaul-synthetic-ci-2026-07.md` (systems-design-gate requirement,
  review finding 3) covering: `.github/workflows/synthetic-runner.yml` — weekly cron
  + PR-touching-hooks trigger, runs `evals/synthetic/run-all.sh`; plus the
  vaporware-volume CI relocation (specs-d §D.4 item 5: its check joins this workflow;
  its commit-boundary membership drops at the next manifest touch, §E.W).
- Done-when: `run-all.sh` exits 0 locally with 8/8 PASS; companion plan exists with
  all seven sections; workflow file present + green on the wave branch (CI proof =
  the PR's checks tab; cite the run URL in evidence).

## §E.5 KPI script — exact spec

- New `scripts/harness-kpis.sh` → writes `docs/reviews/harness-kpis-<yyyy-mm-dd>.md`:
  per-gate waiver + downgrade counts/rates (7d + 30d, from ledger), doctor drift
  count (RED lines over the window, from doctor runs logged in ledger), FM recurrence
  (grep docs/failure-modes.md IDs against ledger events), waiver-density table
  (§E.3 --report), nl-issue triage section (§E.8: untriaged list + this-week's
  conversions; each triaged issue → backlog ID, plan task, or wont-fix+reason).
- Scheduled-task registration DOCUMENTED (exact `schtasks /Create ... /SC WEEKLY`
  line in the script header) — actual registration is an §E.W/operator step; the
  doctor predicate (implemented by E.10) checks task existence and reports
  honest-status "documented, not registered" until then.
- `--self-test`: fixture ledger + fixture nl-issues.jsonl → report matches expected
  numbers (golden fixture diff); live run produces a well-formed report.
- Done-when: fixture numbers match; live report generated and committed.

## §E.6 NEEDS-YOU ledger — exact spec

- New `scripts/needs-you.sh` with `add|resolve|expire|render` verbs maintaining
  `NEEDS-YOU.md` at the MAIN-CHECKOUT root (resolve via `nl_main_checkout_root()`;
  gitignored — add the .gitignore line; machine-local like SCRATCHPAD.md). Four
  sections exactly as the task line: Awaiting your decision (compact §3 blocks +
  links) / Open questions / In flight / Recently decided for §8 review (7-day
  auto-expire into a collapsed count).
- Writers: `add` called by the decision-log flow and by session-wrap when a turn
  ends PAUSING (parse the exact ask from the marker line); `expire` runs inside
  `render`; digest (E.1) links the file + open count.
- The D.3 extension (warn when a final-message decision block lacks a same-turn
  NEEDS-YOU entry) is REASSIGNED to E.10 (single owner of session-honesty-gate
  edits this wave); E.6 ships the `has-entry-for-session` query flag E.10's warn
  will call.
- Doctor predicate (E.10 implements): NEEDS-YOU.md exists at main-checkout root AND
  mtime ≤7d when any Awaiting-decision item is open.
- `--self-test`: add/resolve/expire/render round-trip in sandbox; section-shape
  asserted (4 headers, §3 block format); 8-day-old decided item auto-collapses;
  `has-entry-for-session` true/false fixtures.
- Done-when: self-test green; live NEEDS-YOU.md rendered with the four sections and
  the wave's real pending items (populate at §E.W from the plan's open asks).

## §E.7 session-resumer watchdog — exact spec

- New `scripts/session-resumer.sh` (bash, invoked by a Windows scheduled task every
  10 min via git-bash): scans `~/.claude/projects/*/`+ transcript JSONLs modified in
  the last 48h. Death signature: last event is an API error matching
  `429|529|rate.?limit|overloaded` OR mtime stale >30min while in-flight work exists
  (in_progress tasks in the session's task state, OR a `CONTINUING:` final marker,
  OR ACTIVE-plan file activity in the last hour of the transcript). Natural end
  (DONE:/PAUSING: final marker) → leave alone, log classify-skip.
- Resume: `claude -p --resume <session-id> "<nudge: re-read SCRATCHPAD.md +
  NEEDS-YOU.md, verify branch state, continue the in-flight task>"` with backoff
  state per session at `~/.claude/state/resumer/<id>.json` (attempts, next-eligible;
  5→15→45→120 min; max 5 attempts then a digest escalation line + stop). Fresh-spawn
  fallback (`claude -p "<substrate nudge>"` in the session's cwd) only when --resume
  exits non-zero with an unresumable error.
- Every action → `ledger_emit resumer <event> <detail>` + a digest feed line.
- `--self-test` against fixture transcripts in `tests/fixtures/resumer/`:
  dead-429 (resume command constructed verbatim — assert string), dead-stale-with-
  in-flight (resume), natural-DONE (skip), PAUSING (skip), backoff arithmetic
  (2nd failure → 15min), max-attempts cap (6th eligible → escalation, no command).
- Registration + live kill-and-resume drill are §E.W steps (supervised): register
  `NL-session-resumer` via schtasks; drill = start a sacrificial `claude -p` session,
  kill its process mid-turn, wait one watchdog cycle, verify the resume fired and the
  session continued (cite the resumer ledger events + resumed transcript lines).
- Done-when: self-test green; task registered (doctor predicate: schtasks query
  finds it); drill evidence recorded in the plan evidence file.

## §E.8 nl-issue capture loop — exact spec

- New `scripts/nl-issue.sh "<one line>"`: appends `{ts, project (basename of
  git-toplevel or cwd), session ($CLAUDE_SESSION_ID if set), text}` to
  `~/.claude/state/nl-issues.jsonl`; `--list [--untriaged]` and
  `--triage <n> <backlog|task|wontfix> <ref-or-reason>` verbs (triage stamps the
  entry in place). Byte-identical text within 24h dedups (count++ not new line).
- New skill `adapters/claude-code/skills/nl-issue/SKILL.md`: one-paragraph
  instruction — any harness friction in ANY project → `bash ~/.claude/scripts/nl-issue.sh "<what>"`.
  (Constitution §5 pointer ALREADY LANDED in the reconcile merge — do not re-edit.)
- Digest feed (E.1 consumes): untriaged count + oldest age; >5 untriaged or oldest
  >7d → escalation line + idempotent backlog entry `NL-ISSUES-TRIAGE-<yyyymmdd>`
  (waiver-density pattern). KPI (E.5) renders the triage section from the same file.
- Doctor predicate (E.10 implements): `~/.claude/scripts/nl-issue.sh` exists +
  executable + digest wiring grep.
- `--self-test`: append/read/dedup/triage round-trip in sandbox; cross-project proof
  = append from a fixture dir OUTSIDE the repo (mktemp cwd) and assert the project
  field differs; escalation fixture (6 untriaged → backlog line in sandbox copy).
- Done-when: self-test green; a real entry from a different project dir lands and
  surfaces in the digest fixture; KPI fixture shows the triage section.

## §E.9 pre-compaction continuity (E.9a + E.9b) — exact spec

- **Shared** `scripts/session-snapshot.sh <transcript-path>`: writes
  `~/.claude/state/session-handoff/<session-id>.md` — git branch/HEAD/status +
  worktree list, open task list (task state files), in-flight background ids
  (report-back dirs), ACTIVE plan + its unchecked tasks, pending NEEDS-YOU items
  (E.6 query), SCRATCHPAD.md copy-in if stale >30min. Pure shell — zero model tokens.
- **E.9a** `hooks/context-watermark.sh` (PostToolUse, matcher all, early-exit fast):
  context measurement PRIMARY = parse the LAST assistant event's
  `usage.input_tokens + usage.cache_read_input_tokens` from the transcript JSONL
  (exact, platform-exposed); FALLBACK = transcript bytes × calibration factor
  (default in `lib/`, overridable via local config; builder records the measured
  bytes-per-token ratio from one real transcript in the lib header comment).
  Watermarks: ≥70% of 200,000 → inject once (additionalContext, doctrine-jit dedup
  marker pattern): "context ≥70%: checkpoint state NOW per §5 — durable files, not
  chat"; ≥85% → inject once + RUN session-snapshot.sh (proactive, zero-cost).
- **E.9b** `hooks/pre-compact-continuity.sh` (PreCompact, matchers auto+manual):
  (1) runs session-snapshot.sh; (2) emits summarizer instructions naming ALL SIX
  normative categories EXPLICITLY, priority order, verbatim category names from the
  plan task: (1) operator directives given this session, verbatim intent; (2)
  decisions made + rationale; (3) exact execution state — branch/HEAD,
  committed-vs-uncommitted, in-flight background work with report-back ids, the
  specific next action; (4) hard-learned constraints/lessons; (5) pending asks in
  BOTH directions; (6) verified-vs-claimed status per work item.
  MECHANISM PIN (constitution §1 — no unverified mechanism claims): the builder must
  VERIFY the PreCompact injection surface empirically before relying on it (probe:
  does stdout / hookSpecificOutput.additionalContext reach the summarizer on this
  Claude Code version?). If NO honored channel exists, the fallback IS the design:
  instructions embed at the TOP of the snapshot file + the existing SessionStart
  compact-recovery echo (chain #1) reads the handoff file back after compaction —
  record which mechanism proved true in the hook header + manifest honest_status.
- `--self-test` (each hook): E.9a — fixture transcript below/at/above each
  watermark → 0/1/2 injections, dedup on re-run, snapshot triggered at 85; usage-parse
  primary + bytes fallback both exercised. E.9b — per-category grep: all six category
  names present in the emitted instruction string; snapshot file contains the
  mechanical members of categories 3 and 5 from a fixture session; fires on both
  matchers; snapshot idempotent (re-run overwrites, no duplicates).
- Done-when: both self-tests green; six-category greps pass; wired in template
  (§E.W); doctor predicate (E.10): both hooks in template + snapshot dir writable.

## §E.10 incentive-pin retrofit + defect-fix cluster — exact spec

The wave's one gate-surgery task; single builder; owns harness-doctor.sh and
install.sh edits for the whole wave (§E.0.1).

1. **Pin (d) block-message contract sweep** over the 12 blocking units' member hooks
   (specs-d §D.0.4 table): every BLOCK message contains (i) what failed specifically,
   (ii) the exact copy-pasteable next command/edit, (iii) the honest hatch WITH its
   cost, (iv) what did/did-not execute. Record a per-gate conformance row in
   §E.10-CHECKLIST below (builder appends grep evidence per member).
2. **Pin (f) purpose-clause waivers**: every waiver-accepting check (enumerate:
   `rg -l "waiver" adapters/claude-code/hooks/*.sh` then classify) validates TWO
   named clauses — "this gate exists to prevent X" + "that does not apply here
   because Y" — non-empty both; extend the shared `_wig_check_waiver` (checks a+b)
   and route check (c) through it (NL-FINDING-026 class 1); same for bug-persistence
   and any other waiver reader. Self-test: clause-missing waiver REJECTED with a
   message quoting the required shape.
3. **Pin (e) economics review**: per surviving gate, one verdict row (compliance
   cost vs waiver cost, cheaper path named) appended to §E.10-CHECKLIST; any gate
   where the waiver is cheaper gets a redesign note routed to F.5.
4. **NL-FINDING-017**: install.sh backup becomes copy-then-verify (lock-tolerant:
   copy to backup dir, hash-compare, proceed; never mv the live tree); doctor gains
   `check_manifest_freshness` — live `~/.claude/manifest.json` hash vs repo
   manifest.json hash, RED with "run install" remediation; red-fixture self-test.
5. **NL-FINDING-019/020 residue**: check (a) marker-aware pass-through — a
   PAUSING/CONTINUING final marker with an exact ask satisfies check (a) for plans
   whose unchecked tasks belong to future waves (parse marker from transcript tail;
   the ADR 059 honesty scoping stays: COMPLETED-but-unchecked and
   checked-box-without-evidence remain unwaivable and marker-immune). Verify the
   valve self-test scenarios (2b/2c/2d) still pass; add the marker-pass-through
   scenario.
6. **NL-FINDING-022 heartbeat — DECISION: WIRE** (decide-and-go, plan Decisions Log
   entry in the same commit): install.sh registers scheduled task
   `NL-workstreams-heartbeat` (`workstreams-emit.sh --heartbeat`, every 5 min);
   doctor predicate checks task existence; doc claims restored to honest-wired
   wording. Rationale: reversible (one unregister), preserves Layer-C data integrity
   for the pending Workstreams purpose audit; DELETE remains one commit away.
7. **NL-FINDING-023 class sweep**: `rg -n 'self-test|\.sh' hooks/*.sh` occurrences
   inside block/warn MESSAGE BODIES — verify each named command performs the claimed
   action against the user's artifact (not an embedded suite); fix or reword each.
8. **NL-FINDING-024 spawn race**: workstreams-state-gate performs bounded re-read
   (3× ~700ms) before blocking; block message gains "if you JUST spawned this title,
   the writer may still be flushing — retry once before waiving"; fix the
   `conversation-tree-state-gate` self-naming residue in its block JSON.
9. **NL-FINDING-026 class 2**: check (c) untracked-dirt computation excludes
   `.claude/state/` (one grep -v); doctor predicate verifies the ignore rule in
   governed repos.
10. **NL-FINDING-027**: session-honesty `done_contradicted_by_block` becomes
    resolution-aware — a block followed by a LATER work-integrity PASS or a valid
    (fresh, purpose-clause) waiver for the same plan-slug in the same session is
    non-contradicting; THEN register session-honesty-gate in
    `RETRY_GUARD_VERIFICATION_HOOKS` (self-test: honest block-resolve-DONE passes;
    DONE-riding still blocks and is not downgradeable).
11. **E.6's D.3 warn extension** (reassigned here): session-honesty emits a ledger
    warn when the final message contains a decision block but `needs-you.sh
    has-entry-for-session` is false.
12. **Doctor predicates from E.5/E.6/E.7/E.8/E.9 fragments** implemented verbatim
    (one `check_wave_e_surfaces` or individual checks — builder's call; each with a
    red fixture in the self-test).
13. **Discovery 2026-06-17 option E** (dispositioned decided at E.0):
    scope-enforcement-gate exempts `docs/discoveries/*` (same mechanism as the
    existing `docs/plans/archive/*` exemption at scope-enforcement-gate.sh:154) —
    ad-hoc process capture is off-plan by nature, and bug-persistence-gate WANTS
    those commits; self-test scenario: staged discovery file passes under a foreign
    ACTIVE plan.
- Done-when: §E.10-CHECKLIST fully populated with grep evidence + economics verdicts;
  all touched hooks' self-tests green; doctor --self-test green incl. new red
  fixtures; install.sh dry-run green on a temp HOME.

### §E.10-CHECKLIST (builder populates; orchestrator verifies)

| Unit | pin-d conformant (grep ref) | pin-f waiver path | pin-e verdict |
|------|-----------------------------|-------------------|---------------|
| 1. bug-persistence | Conformant: block body (`bug-persistence-gate.sh` ~L428-490) states what failed (trigger phrases, no persistence), 5 copy-pasteable remediation options (backlog/reviews/discoveries/findings/attestation), the attestation escape hatch + its cost (one line per false-positive, gitignored dir), and never demands final-message content. | Yes — `.claude/state/bugs-attested-*.txt`, now routed through `waiver_has_purpose_clauses` (this session's item-2 fix; grep `waiver_has_purpose_clauses` in the file). Existence-only pre-fix theater closed. | Compliance (persist to backlog/findings) is cheaper for real bugs; attestation is cheaper ONLY for genuine false positives — by design the two paths serve different truths, not a waiver-vs-compliance tradeoff. |
| 2. work-integrity | Conformant: all three checks' block bodies (`work-integrity-gate.sh` check-a ~L340-350, check-b ~L565-660, check-c ~L710-770) name the failing check, the exact next command/edit, the waiver hatch + freshness cost, and "this block prevented only session-end" scope framing. | Yes — three waiver families (work-integrity-waiver, acceptance-waiver, worktree-teardown-waiver) all route through `_wig_check_waiver` / the check-c teardown path, both now purpose-clause-validated via `waiver_has_purpose_clauses` (item-2 fix this session). | Compliance (check a box, run end-user-advocate, commit/stash) is cheaper than authoring a substantive two-clause waiver in the common case; the waiver exists for the genuine multi-session/incidental-touch case, not as a shortcut. |
| 3. session-honesty | Conformant: block body (`session-honesty-gate.sh` ~L644-665, contradiction path ~L685-703) names the exact defect (missing/multi marker, or DONE-vs-block contradiction), the minimal-delta fix (append one marker line), and never demands report re-statement (§D.3 design pin). | N/A — no waiver file; the marker contract itself is the only satisfying action by design. The DONE-vs-block contradiction check now resolves via a LATER work-integrity PASS or a valid purpose-clause waiver (NL-FINDING-027 fix, item 10a), not a dedicated waiver of its own. | Compliance (append the correct marker) costs seconds; there is no cheaper waiver path because none exists — this is the intended shape (a contract that is always trivially satisfiable honestly). |
| 4. spec-freeze (spec-freeze-gate.sh + scope-enforcement-gate.sh) | Partial: scope-enforcement's 3-option block message (verified clean of waiver references by this session's self-test scenario 11) names the failing file(s) and the exact remediation (declare scope, or move file, or open a new plan) but spec-freeze-gate.sh's own block text is terser than pin-d's full 4-element bar. | N/A for scope-enforcement (waiver path deliberately REMOVED 2026-05-04, per file header comment); spec-freeze's only "escape hatch" is flipping `frozen: true` in the plan header, which is the direct compliance action, not a separate waiver artifact. | Compliance (flip the plan's frozen field, or declare in-scope files) is a one-line edit — strictly cheaper than any alternative, and no waiver exists to compare against. |
| 5. tdd / no-test-skip | Conformant: block body names the specific skip pattern + file, three concrete remediation options (seed data and un-skip, add an issue reference inline, or surface the blocker to the user), and cites `~/.claude/doctrine/testing.md`. | N/A — no waiver mechanism; test-skip violations must be resolved (fixed, referenced, or escalated), never waived — this is intentional (a waiver here would re-legalize the exact anti-pattern the gate exists to catch). | Compliance (fix or reference the skip) costs minutes; no waiver exists to be cheaper, so compliance is structurally the only path — correctly gate-designed under pin (e). |
| 6. command-safety (consolidated: env-local-protection.sh + inline greps + automation-mode-gate.sh) | Partial: `env-local-protection.sh` names the specific dangerous pattern + an env-var override with its cost; the inline curl-pipe-sh/force-push/lockfile greps and `automation-mode-gate.sh` are terser and vary in whether they enumerate all 4 pin-d elements per hit. | Partial — `env-local-protection.sh` accepts an env-var override (`ENV_LOCAL_OVERWRITE_OK=1`), not a file-based purpose-clause waiver; this unit was NOT in this session's item-2 grep sweep of `hooks/*.sh` waiver files (no `*-waiver-*.txt` glob here) — env-var overrides are a different escape-hatch class outside pin (f)'s file-based scope. | Compliance (fix the env/lockfile/force-push issue directly) is cheaper than the potential cost of the dangerous command executing — asymmetric by design; this is the class of gate where compliance-cheaper holds most strongly. |
| 7. migration-naming | Conformant: block names the bare-integer-prefix violation + affected files, gives the exact `git mv` command with a timestamp-prefix example, and has NO waiver (by design — a coordination invariant that must never be silently bypassed). | N/A — no waiver mechanism; renaming is the only remediation, preventing the exact silent-collision class the gate exists to catch. | Compliance (one `git mv` command) is trivially cheaper than any hypothetical waiver, and none exists — correctly gate-designed. |
| 8. local-edit-authorization | Conformant: block (`local-edit-gate.sh`) names the missing/stale/wrong-slug marker, the exact next action (`/grant-local-edit <file>`), the escape hatch (a 30-min fresh marker) and its cost (re-invoke after expiry). | Yes, but structurally different from pin-f's file-waiver shape — the marker itself IS the authorization token (time-limited, slug-scoped), created via the `/grant-local-edit` skill rather than a free-text purpose-clause file; not swept by this session's item-2 waiver-file grep since it is not a `*-waiver-*.txt` pattern. | Compliance (invoke `/grant-local-edit`, ~1 command) is nearly free — cheaper than the cost of forgetting and repeating the edit after the 30-min window lapses. |
| 9. plan-edit-validator | Conformant: block explains checkbox-flip requires task-verifier-authored evidence, names the exact next action (run task-verifier, or write the evidence block first), and the authorization model (evidence-first, mtime-windowed) IS the escape hatch — no separate bypass exists (`TASK_VERIFIER_MODE` plaintext bypass was removed). | N/A — no file-based waiver; evidence blocks (`<plan>-evidence.md` / per-task JSON) are the authorization token, not a purpose-clause waiver. | Compliance (produce real evidence via task-verifier) is the only path and IS the point — the gate exists specifically to make self-certification impossible, so "cheaper than waiver" degenerates to "the only path," which trivially satisfies pin (e). |
| 10. wire-check | Conformant: block names the specific broken static-trace element (missing file, unreferenced token, broken arrow) and the fix (add/repair the wire path); the only "exit" is a plan-time `n/a` carve-out (Check 13, ≥30-char reason) declared BEFORE the gate fires, not a post-hoc waiver. | N/A at hook-time — no waiver file; the carve-out is a plan-authoring decision, not an escape hatch from an already-fired block. | Compliance (fix the wire chain) is the required path; no comparable waiver exists post-block, so pin (e) holds by construction. |
| 11. commit-boundary (consolidated: pre-commit-gate.sh + findings-ledger-schema-gate.sh + plan-deletion-protection.sh + claude-md-hygiene-gate.sh) | Partial: `pre-commit-gate.sh`'s retry-guard-routed block aggregates sub-check failures (TDD/plan-review/build) with per-sub-check remediation; `findings-ledger-schema-gate.sh` names the missing/malformed field per the six-field schema. Consistency across all four members was not independently re-verified this session (existing D.0.6 banner requirement covers "ENTIRE command not executed" per NL-FINDING-016). | Partial/none — no unit-wide waiver; each member either has no waiver (findings-ledger, plan-deletion, claude-md-hygiene) or relies on fixing the actual precondition (pre-commit-gate's sub-checks). Not in this session's pin-f scope (no waiver-file glob found). | Compliance (fix the failing sub-check: write tests, fix the schema entry, correct CLAUDE.md) is cheaper than any bypass, since none of the four members offers file-based waiver theater to begin with. |
| 12. agent-teams (teammate-spawn-validator.sh + task-completed-evidence-gate.sh) | Conformant: DAG-review block (`teammate-spawn-validator.sh` ~L440-460) names the Tier-3+ requirement, the exact next action (review the DAG with the user, then write the waiver), the escape hatch + cost (≥40 substantive chars, now ALSO purpose-clause-validated), and cites why the gate exists. `task-completed-evidence-gate.sh`'s plan-scoped block (§D.0.5) names the missing evidence block + which plan declared the task. | Yes — `dag-approved-<slug>-*.txt` via `_dag_find_substantive_waiver`, now routed through `waiver_has_purpose_clauses` (this session's item-2 fix; confirmed by `declare -F waiver_has_purpose_clauses` guard in the function). | Compliance (a real DAG review with the user, ~5-10 min) is cheaper than the cost of a mid-execution parallelism/dependency failure the gate exists to prevent — waiver-dominance would be the redesign trigger per pin (e), not observed here. |

Item-7 class sweep (NL-FINDING-023, "gate messages naming remediation commands that do not perform the claimed action"): re-swept `hooks/*.sh` for the same command-in-message idiom beyond the already-fixed `pr-template-inline-gate.sh` instance (a read-only Explore-agent pass over `automation-mode-gate.sh`, `migration-claude-md-gate.sh`, `local-edit-gate.sh`, `wire-check-gate.sh`, `plan-edit-validator.sh`, `observed-errors-gate.sh`, `outcome-evidence-gate.sh`, and every `harness-doctor.sh` check). Zero further instances found — every remediation command named in a live block/warn message actually performs the claimed action against the artifact in question. No fix needed beyond the pr-template-inline-gate.sh instance already on master.

## §E.11 batched Stop verdict — exact spec (ADR 059 D1+D2)

- New `hooks/stop-verdict-dispatcher.sh` replaces the three BLOCKING Stop entries
  (work-integrity, session-honesty, bug-persistence) with ONE entry; Stop chain
  becomes 4: dispatcher, workstreams-stop-writer, signal-ledger-flush, session-wrap.
- Each blocking gate gains `--report` mode: run all checks, exit 0, emit its gap
  list as JSON lines to stdout (no block). The dispatcher invokes all three in
  --report mode, aggregates, and: FIRST blocking Stop of the session → ONE combined
  block message listing every gap (grouped per gate, each with its pin-d remediation).
  SECOND Stop with unresolved gaps → write each to
  `~/.claude/state/unresolved-gaps.jsonl` + NEEDS-YOU.md (E.6 add) + digest feed,
  ledger-log the end as `protocol-downgrade` (designed, not failure), exit 0.
- DONE-refusal retained VERBATIM: verification-class gaps + a `DONE:` claim → block
  regardless of cycle count (never downgraded; regression self-test mandatory).
  RETRY_GUARD_THRESHOLD → 2 for world-state checks via the dispatcher's own state
  (the retry-guard lib keeps its semantics for the DONE-refusal path).
- `--self-test` ≥8: two-gap session gets ONE block listing both; second Stop with
  one unresolved gap → exit 0 + gap in unresolved ledger + digest fixture; DONE-claim
  regression (blocks, refuses downgrade); clean session passes; marker still
  required (session-honesty's report mode carries its checks); ledger shows
  protocol-downgrade event; HARNESS_SELFTEST sandbox; gaps grouped per gate.
- Done-when: self-test green; template Stop chain = 4 (§E.W); ADR 059 refutation
  metric wired: dispatcher ledger-logs `stop-cycle` events so mean-cycles-per-end is
  measurable by E.5.

## §E.12 session end-manifest — exact spec (ADR 059 D6+D3)

- Schema `schemas/end-manifest.schema.json`: {shipped: [{sha, remote}], unresolved:
  [{item, recorded_at}], needs_operator: [string], marker: string(last line)}.
- Writer `scripts/end-manifest.sh write` — generates from session state (git log
  for session-created SHAs, unresolved-gaps ledger, NEEDS-YOU session entries,
  final marker) to `~/.claude/state/end-manifest/<session-id>.json`.
- Validator (`end-manifest.sh validate`, called by the E.11 dispatcher when a
  manifest exists): each shipped SHA reachable from master; each unresolved item's
  `recorded_at` file exists and contains the item; worktree clean if manifest says
  torn-down; marker matches the transcript's last line. Manifest CLAIMS validated
  mechanically REPLACE per-gate transcript forensics: work-integrity's plan-touch
  derivation switches to manifest scoping when a manifest is present (transcript
  fallback stays for manifest-less sessions).
- Scoping rule (harness-reviewer pin, verbatim): manifest scoping distinguishes
  "created the state" from "touched the file" — an incidental toucher of someone
  else's COMPLETED-but-unchecked plan must not inherit remedies only the plan owner
  can honestly execute.
- World-state assertion sweep: grep the surviving Stop chain for transcript-derived
  plan-touch/world-state logic; relocate each hit to digest/doctor/CI; the
  NL-FINDING-019 golden scenario (scope-line-only touch) must pass WITHOUT a waiver.
- `--self-test`: schema-valid write from fixture session; validator catches
  fabricated SHA / missing recorded_at / dirty-tree lie / marker mismatch; golden
  019 scenario; incidental-toucher scenario (foreign plan touch, no inherited
  remedy); grep-assertion no surviving Stop gate greps transcript for plan-touch
  derivation when a manifest exists.
- Done-when: all self-tests green; grep proof recorded; 019 golden green.

## §SYNC-CLONE-C — B.12 durable follow-on, defined here per the B.12 task line

Design (option C from discovery 2026-06-02): the cross-machine sync daemon operates
on a DEDICATED bare-ish clone (`~/.claude/sync-clone/<repo>`) and never touches
interactive checkouts; sync = fetch in the clone + push to the mirror remote;
interactive checkouts pull normally. The B.12 interactive-session-lock stays as
defense-in-depth. Assigned to Wave F as new task F.6 (added to the plan in the E.0
commit); Model: sonnet; Done-when: sync-pt-to-personal.sh operates from the dedicated
clone (grep), a live sync run succeeds with an interactive session open, lock
refusal-log shows zero interactive-checkout touches.

## §E.0-DECISIONS (decide-and-go, recorded in the plan Decisions Log this commit)

1. ADR-059 task renumbering E.8/E.9→E.11/E.12 (reconciliation merge — own entry).
2. NL-FINDING-022: WIRE the heartbeat (§E.10.6) — reversible, data-integrity for the
   pending Workstreams audit.
3. E.11 mechanics: single dispatcher + per-gate --report modes (vs shared-state
   accumulator) — one owner for aggregation, gates stay independently testable.
4. Serialization: template/manifest/doctor/install single-owner rules (§E.0.1).
5. E.6's D.3 warn extension reassigned to E.10 (single session-honesty owner).
6. NL-FINDING-027 + SELFTEST-ORACLE-PIN-01 + NL-FINDING-025-isolation assigned to
   E.10 / E.10 / E.2 respectively.
7. F.6 (sync-clone option C) added to the plan per B.12's "defined in specs-e" clause.
