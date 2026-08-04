# Design: Mechanism liveness — proving that what was built actually fires

**Status:** r1 — awaiting review

**Author:** design-author (model: fable / claude-fable-5)

**Changelog:** r1 (worktree agent-a766b00940f17e644, rooted at master 87ddda29): initial
authoring, no prior rounds.

**Supersedes:**
- `harness-doctor.sh` `check_verify_event_silence` (hooks/harness-doctor.sh:2827-2842, wired
  :4292) — absorbed as one row of the generalized sweep this design specifies (REQ-B3); the
  flip-verdict mechanism becomes a declared liveness entry and the bespoke check is retired in the
  same commit that lands its replacement. Not deleted before the replacement covers it.
- `scripts/install-daily-harness-eval-task.ps1` as the harness-evaluator scheduling path — an
  installer that no code path invokes (grep over `install.sh` and `scripts/*.sh`: zero call sites)
  and whose task (`NeuralLace-HarnessEvaluator-Daily`, install-daily-harness-eval-task.ps1:36) is
  not registered on this machine (PROVEN: `schtasks /query` filtered for harness/eval returns
  nothing, rc=1, 2026-08-04). Superseded by a `config/schedule-manifest.json` entry (REQ-D3),
  following the same retirement convention that file's `retired_installer_note` field documents.
- The operator's own "testing plan per feature" proposal, as a standing convention — evaluated in
  §3 DEC-1 and narrowed to a one-line birth declaration rather than a per-feature document. The
  operator asked for ideas, not agreement; §3 gives the honest comparison.

**Inputs (all read in full):**
- Operator problem statement, verbatim 2026-08-04 (dispatch text; quoted in §1).
- `adapters/claude-code/manifest.json` @ 87ddda29 — 166 entries (jq-verified); full field census
  in §1.
- `adapters/claude-code/scripts/verify-event-audit.sh` @ 87ddda29 (all 536 lines) — the working
  silence-detector precedent, including its measured 17MB-ledger single-fetch performance lesson
  (lines 156-164).
- `adapters/claude-code/hooks/harness-doctor.sh` — `check_verify_event_silence` (:2822-2842) and
  its wiring (:4291-4292).
- `adapters/claude-code/agents/harness-evaluator.md` (all 200 lines) — the design-vs-operating
  effectiveness framing (:18-21) and false-positive doctrine (:112) this design inherits.
- `adapters/claude-code/config/schedule-manifest.json` (entire file) — 7 mechanism entries, none
  for harness-evaluator; the `declared_cadence_seconds`/`measured_cycle_seconds`/`cadence_check`
  precedent.
- `adapters/claude-code/scripts/ask-registry.sh` (header + schema contract, lines 1-930 of 3827) —
  status vocabulary, fold contract, requirement/invariant-verdict ledger precedent.
- `neural-lace/workstreams-ui/server/requests-routes.js` (:20-58 payload contract),
  `web/asks.js` (header contract), `web/app.js` (:1333-1345 Health tab init),
  `server/state-watch.js` (:7 fs-watched doctor-cache) — the two cockpit surfaces this design
  feeds.
- `docs/backlog.md` HARNESS-GAP-62 entry + 2026-08-04 amendment + LANDED record (:138-142).
- `docs/plans/deferred/status-event-ledger.md` (header + taxonomy table) — the "deterministic
  trigger for every status event" law this design generalizes.
- `adapters/claude-code/config/operator-directives.json` (entire file, 23 entries) — OD citations
  in `## Directives honored`.
- `adapters/claude-code/scripts/nl-maintenance.sh` (grounding grep: jobs dir :109, completion
  marking :250-251, self-test scenarios S2-S5) — the scheduled-mechanism liveness substrate.
- `adapters/claude-code/scripts/harness-evaluator-daily.sh`,
  `scripts/install-daily-harness-eval-task.ps1`, `scripts/schedule-weekly-eval.md` — the
  built-and-never-registered evaluator scheduling artifacts.
- Live-machine measurements, all run 2026-08-04 by this author (commands in §1):
  `~/.claude/state/signal-ledger.jsonl` (17,812,862 bytes), scheduled-task query, self-eval packet
  inventory, manifest/ledger gate join.
- `docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md` (P-31/P-32/D-13 anchors, per this
  agent's charter) and `templates/design-template.md` (the section contract this file follows).

---

## 0. What this design is, in three sentences

A mechanism in this harness can be built, self-tested, merged, manifest-registered, and marked
done while never firing in production — and today nothing notices, because the manifest records
what a mechanism IS but not what observable proves it FIRED. This design adds a birth-time
liveness declaration (which signal, at what cadence) to `manifest.json`, one derivation-first
sweep that reads the declared substrates and surfaces only anomalies into the doctor and the
cockpit Health pane, and a fourth "observed working" link on the cockpit Requests tab so the
operator can see request → built → verified → observed without lifting a finger. It deliberately
does NOT add per-feature test plans, blocking gates, or a hand-maintained status field — the
sweep derives state from substrates at read time, because a stored status is just one more thing
that rots.

## 1. Problem statement (evidence-anchored)

**The operator's problem, verbatim (2026-08-04):** "it's frustrating and wasteful that I find
myself proposing the same thing all over again, simply because you built something that didn't
work. … A lot of the stuff that I propose gets either partially worked and forgotten about or
built and forgotten about. … what I really do want is an easy way to keep track of all the things
that I have requested and which of them have actually been built. Maybe also a way of thinking
about how I should start using or testing or validating that what was built is actually the
solution that I was looking for."

**The class:** a mechanism can pass every point-in-time check — self-test green, wired, merged,
manifest-registered, checkbox flipped — and still never fire in production. Tests prove a
mechanism CAN work; nothing proves it DOES. This is `harness-evaluator.md`'s own
design-effectiveness vs. operating-effectiveness distinction (agents/harness-evaluator.md:18-21):
design-effective is a point-in-time property, operating-effective is a period property requiring
observed evidence, and the harness measures only the first.

**Golden case 1 — SE4 flip-verdict events (five days of total silence from an unskippable
chokepoint).** `docs/plans/deferred/status-event-ledger.md` row 7: SE4 shipped 2026-07-30,
marked BUILT, emitting from the sole checkbox-flip authorization chokepoint — mechanically
unskippable BY CONSTRUCTION, with passing self-tests (F16/F17). PROVEN
(docs/backlog.md:140, 2026-08-04 amendment): `verify-event-audit.sh --sweep docs/plans` measured
**926 currently-checked tasks, 0 with a matching flip-verdict event on record**; the ledger
carried ZERO flip-verdict rows in total. Root cause: the gate's TASK_ID regex rejected
bare-numeric ids — the estate's dominant convention (863 occurrences in the id-shape census,
docs/backlog.md:142; independently, 400 checked bare-numeric-with-trailing-dot lines under this
worktree's `docs/plans`, this author's grep 2026-08-04). Re-verified today: the live ledger
(17,812,862 bytes) still contains 0 `flip-verdict` rows (`grep -c '"event":"flip-verdict"'`,
this author, 2026-08-04 — the fix landed at b7730fb0 today; newly-authorized flips have not yet
accumulated). The silence was found only because the operator re-proposed the idea from scratch —
the exact waste the problem statement names.

**Golden case 2 — the detector for this class is itself an un-fired mechanism.**
`agents/harness-evaluator.md` exists; its literal remit is "which mechanisms are being bypassed
or silently eroded" (line 3). PROVEN it has no live schedule: `config/schedule-manifest.json`
(read in full) carries 7 mechanism entries, none for the evaluator; `schtasks /query` on this
machine returns no harness/eval task (rc=1, 2026-08-04); `install.sh` never invokes
`install-daily-harness-eval-task.ps1` (grep: zero call sites). The declared cadence was DAILY
("Per Misha 2026-05-28", install-daily-harness-eval-task.ps1:4-5); the actual output record is
3 packets in 71 days (`docs/reviews/`: 2026-05-25, 2026-07-18, 2026-07-29 — ls, this author,
2026-08-04). The recursion is the point: the scheduling artifacts for the watchdog were
themselves built, tested (harness-evaluator-daily.sh has a `--self-test`), and never fired.

**The instrument gap, measured.** `manifest.json` has 166 entries (jq, 2026-08-04) across 19
distinct fields (`id, kind, doctrine_file, hooks, events, wired_template, selftest, jit_triggers,
blocking, budget_class, added_after, golden_scenario, fp_expectation, retirement_condition,
honesty_rationale, honest_status, waiver_path, chokepoint, bypass_paths` — jq key census). **No
field records what observable proves the mechanism fired, or when it last did.** 125 of 166
entries have `selftest: true` — the estate is rich in CAN-work evidence and structurally blind to
DOES-work evidence. Kind distribution: 58 gate / 42 writer / 41 pattern / 22 surfacer /
3 convention.

**How much is derivable today, and where derivation is ambiguous.** Join of manifest gate ids
against every `gate` value ever written to the live signal ledger (this author, 2026-08-04):
**9 of 58 manifest gates have ever emitted a ledger row; 49 have zero rows ever.** But
ledger-absence conflates two states: `plan-edit-validator` is among the 49 despite PROVEN
production firing (it BLOCKS plan edits — docs/backlog.md:140 documents real blocks), because
until b7730fb0 it had no ledger emission at all. So "absent from the ledger" means "not
observable via this substrate," not "never fired." A liveness check therefore cannot be a naive
ledger diff over all mechanisms; it needs a per-mechanism statement of WHICH observable proves
firing — which is exactly the declaration this design adds. HYPOTHESIZED: most of the 49
ledger-absent gates block via exit-code/stderr with no durable trace at all, making them
genuinely unobservable today (refuter: a per-gate audit finding durable side effects; Tier-2
backfill in §4.5 performs exactly that audit, opportunistically).

**The working precedent to generalize.** `verify-event-audit.sh --recent-silence` +
`harness-doctor.sh check_verify_event_silence` (landed b7730fb0, 2026-08-04): derives recent
flips from `git log -p` (independent of the ledger), compares against ledger events in the same
window, WARNs only on total silence above a min-activity floor, and fired live at build time
(`recent_flips=109 has_event=0`, docs/backlog.md:142). It is one mechanism's liveness check,
hand-built. This design is that check generalized to all 166 — declaration where derivation
needs a pointer, derivation everywhere a substrate exists.

## 2. Binding constraints

- **OD-002 (anti-bloat, surfaces `docs/designs/**`):** every addition names what it displaces.
  This design displaces: `check_verify_event_silence` (absorbed), the orphan evaluator installer
  path (superseded), and adds ZERO new scheduled tasks, ZERO new SessionStart hooks (SessionStart
  is at its 8/8 cap per manifest limit-resume entry's honest_status), ZERO new hook chains.
- **OD-006 (push-over-pull, surfaces `docs/designs/**`):** the sweep push-materializes a state
  file; the cockpit consumes it via the existing fs-watch push path (server/state-watch.js:7).
  No new polling loop anywhere.
- **OD-001 / OD-003 (no WSL, no new hardware, surfaces `docs/designs/**`):** portable bash + jq,
  runs on all current machines; no new OS dependency.
- **Constitution §10 (no evidence, no gate):** the sweep is WARN-only observability, never a
  blocking gate. The one new lint (REQ-A2, new-manifest-entry completeness) extends an existing
  blocking check (`manifest-check.sh`) with a named golden scenario (golden case 1), an fp
  expectation, and a retirement condition — stated in §7.
- **Spawn tax (P-01/P-16, ~132-190 ms/spawn on Windows; schedule-manifest.json:34 pins 152 ms):**
  the sweep must be priced in spawns × fire-rate. Priced in §4.3: one bounded pass at
  doctor-cadence (≤48/day worst case), single-fetch ledger read per verify-event-audit.sh's own
  measured lesson (its :156-164 comment: per-task re-parse of the 17MB ledger did not finish).
- **Two-layer repo/live:** everything here lands in `adapters/claude-code/` and reaches
  `~/.claude/` via install/auto-install sync. `harness-doctor.sh` is file-copied wholesale, so
  the retirement of `check_verify_event_silence` inside it propagates with the same sync — no
  manual per-machine reconcile needed for that removal. The retired `.ps1` is NOT deleted
  (rollback convention per schedule-manifest.json's `retired_installer_note` precedent); since it
  was never registered on any machine (PROVEN above for this machine; HYPOTHESIZED for the other
  two — refuter: `schtasks`/`launchctl` query on each), there is no live task to unregister here,
  and REQ-D3 names the per-machine check anyway.
- **Prior incident this design must not re-learn:** P-42/OD-006's "TTL cache was still pull" —
  the first instinct for "is it alive?" is a poll; this design's answer is
  materialize-on-doctor-run + fs-watch push, never a UI-side poll.
- **The false-positive doctrine (harness-evaluator.md:112):** repeated false alarm trains the
  operator to ignore the surface, which is this design's own death (pre-mortem, §8). Anomaly
  budget and SUSPECT-declaration handling in §4.3 are constraints, not niceties.

## 3. Decisions (each with rationale + reversal cost)

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-1 | **Reject per-feature testing plans as the fix; build post-ship observation instead. Salvage the idea as a one-line birth declaration.** | Both golden cases had passing tests at ship time (SE4: F16/F17 green; evaluator wrapper: `--self-test` present). A test plan is a bigger point-in-time instrument aimed at the CAN-work axis; the failure class lives on the DOES-work axis, observable only after shipping, over a period. A per-feature plan is also a per-feature document the operator must curate — the opposite of "no more effort on my plate" — and it rots exactly like the mechanism it watches (nothing re-runs a test plan either). What survives from the operator's idea: the birth-time question "how would we know this is working?" is genuinely valuable — captured as ONE declared line (the liveness signal + optional `operator_check` hint), not a document. Full comparison in §4.1. | Near zero to revisit: nothing in this design prevents adding test plans later; the declaration field would even tell such plans what to probe. |
| DEC-2 | **The liveness declaration lives in `manifest.json` as a per-entry `liveness` block — not a separate registry file.** | The manifest is already THE per-mechanism enforcement inventory, doctor-verified, with the §10 evidence-bar fields (`golden_scenario`/`fp_expectation`/`retirement_condition`) as direct precedent for birth-time obligations. A second file keyed by the same 166 ids is the two-store drift class the operator-directives register note explicitly warns against (operator-directives.json:3, "a new binding standing rule cannot silently re-create an eighth store"). For the 7 scheduled mechanisms, the block REFERENCES `schedule-manifest.json` by id rather than duplicating cadence — one source per fact. | Moderate: extracting the blocks to a separate file later is one jq script + updating two readers (sweep, manifest-check). No data loss; schema is additive. |
| DEC-3 | **Derivation over declaration: the declaration is a POINTER to a substrate, never a hand-asserted status; no last-fired value is ever stored in the repo.** | Golden case 1 was caught by derivation (git-log vs. ledger diff), not by anyone updating a status field. A stored `last_fired` in manifest.json would churn a versioned file constantly and rot the moment anyone stops updating it — becoming precisely the false record this design exists to kill. The sweep computes state at read time from the declared substrate (ledger row timestamps, artifact mtimes/git-log dates, nl-maintenance completion markers) and writes results only to `~/.claude/state/` (unversioned, regenerated every run, cannot rot in git). | Low: adding a cached last-seen to state files is additive if derivation proves too slow; putting status INTO the manifest would be a deliberate reversal of this design's core stance and should ring alarms. |
| DEC-4 | **One sweep script, WARN-only, run as a doctor check at the existing doctor cadence; output materialized to state and rendered in the cockpit Health pane. No new scheduled task, no new hook.** | The doctor already runs `--quick` per session-start flow and on a 30-min TTL via the `doctor-verdict-refresh` schedule entry (schedule-manifest.json:143-164) — piggybacking costs zero new infrastructure and inherits the existing cadence guarantees. The Health tab already exists (app.js:1333-1345) and already consumes fs-watched doctor state (state-watch.js:7) — push-based, OD-006-compliant. A blocking gate is excluded by §10 (an observability WARN has no golden blocking scenario). | Trivial: remove one doctor check function + one pane card. The sweep script stands alone (`--self-test`, manual invocation) regardless. |
| DEC-5 | **The operator chain's fourth link is derived per-request via ask → `became.plan_slug` → manifest entries declaring `born_of_plan: <slug>` → those entries' liveness states. No new ask-registry record types.** | The first three links exist: Requests tab renders ask → `became.plan_slug` (requests-routes.js:38-41), plan checkboxes are flipped only by task-verifier, and flip-verdict events now fire post-b7730fb0. The missing join is plan→mechanism; a new optional manifest field (`born_of_plan`) closes it at birth, required for new entries by the same lint as the liveness block. Extending the ask registry instead would add a fifth writer to an append-only fold contract for data that is derivable — the registry's own header warns how expensive its fold semantics are to extend safely (its FOLD-FIELD ABSTENTION history). Old asks without the join render honestly as chain-ends-at-verified. | Low: the chip is server-derived; removing it is one route + one render block. `born_of_plan` values remain useful metadata regardless. |
| DEC-6 | **Backfill is tiered: mechanical seeding now for derivable entries; ratchet-on-touch for the rest; the remainder stays explicitly `undeclared` and is displayed as a count, not a nag list.** | 166 hand-audits in one build is a fabrication factory — an author guessing signals for mechanisms they didn't build produces confident-wrong declarations, worse than honest absence (constitution §1). Mechanically derivable NOW: the 9 ledger-present gates, all ledger-present writer/surfacer emitters (27 distinct `gate` values measured), the 7 schedule-manifest ids, flip-verdict itself. The rest ratchet in when touched (harness-reviewer already reviews every mechanism edit). "Undeclared" is a named, counted, honest state per OD-010 — never a fabricated declaration. | None — backfill is monotonic; any entry can be upgraded any time. |
| DEC-7 | **Scheduling harness-evaluator is IN this design as one requirement (REQ-D3), because this design supersedes its dead installer path — but it is severable and could land as a standalone one-liner first.** | The evaluator and the sweep are complements, not substitutes: the sweep is mechanical, cheap, per-doctor-run, and detects SILENCE only; the evaluator is judgment-priced (Fable), weekly, and detects EROSION/bypass/degradation the sweep cannot (a mechanism firing frequently but wrongly is OK to the sweep, a finding to the evaluator). Scheduling the evaluator without the sweep re-creates golden case 2's shape one level up (a weekly packet nobody's mechanism confirms was produced); with the sweep, the evaluator's own packet artifact is a declared liveness signal — the detector's detector. If the implementing plan is delayed, the operator may land REQ-D3 alone immediately; this design records that as sanctioned. | Trivial: one schedule-manifest entry, removable in one commit. |
| DEC-8 | **The `on-demand` cadence exists in the vocabulary, is structurally exempt from silence anomalies, and requires a non-empty one-line justification.** | Without an on-demand class, every manually-invoked tool (e.g. `verify-event-audit.sh --sweep` itself) would WARN forever — cry-wolf by construction. Without justification friction, `on-demand` becomes the lint-silencing default and hollows the whole scheme (pre-mortem §8 names this as the predicted failure). One required sentence is the cheapest real friction (OD-018: the honest path must not cost more than the evasion). | None — tightening or loosening the justification requirement is a lint constant. |

## 4. Architecture

Module boundaries are drawn around what is likely to change (Parnas): the **substrate readers**
(how each signal class is observed — most volatile), behind one interface inside the sweep; the
**declaration vocabulary** (the stable contract everything else compiles against); the
**surfaces** (doctor line, Health card, Requests chip — presentation, freely changeable).

```
manifest.json (declarations: WHAT proves firing, WHAT cadence — versioned, repo)
        │  read-only
        ▼
mechanism-liveness-sweep.sh ──reads──► substrates:
        │                       • ~/.claude/state/signal-ledger.jsonl  (ledger-gate:/ledger-event:)
        │                       • repo artifacts via git log / fs      (artifact:)
        │                       • ~/.claude/state/nl-maintenance/jobs/ (scheduled:<id>)
        │                       • arbitrary state files                (state-file:)
        ▼  materializes (push, OD-006)
~/.claude/state/liveness/liveness-report.json   (unversioned, regenerated whole each run)
        │                                   │
        ▼ doctor WARN (anomalies only)      ▼ fs-watch push (state-watch.js pattern)
harness-doctor.sh check_mechanism_liveness  cockpit Health pane card + Requests-tab chip
```

### 4.1 The comparison the operator asked for (testing plans vs. observation)

| | Per-feature testing plan (operator's proposal) | Post-ship observation (this design) |
|---|---|---|
| What it proves | CAN work, at authoring time (design-effectiveness) | DOES work, over time (operating-effectiveness) |
| Would it have caught golden case 1? | No — SE4's tests passed; the regex gap was between test fixtures and production id conventions | Yes — 926/0 was found by exactly this kind of derivation, five days late only because it ran once, by hand |
| Would it have caught golden case 2? | No — the wrapper self-tests; the gap was registration, which no test exercises | Yes — packet-artifact age vs. declared weekly cadence is a trivial derivation |
| Operator effort | Authoring/curating a plan per feature; re-running it or scheduling it (which itself needs liveness…) | Zero mandatory; optional glance at a pane |
| Rot behavior | Rots like the mechanism it watches (nothing re-runs it) | Recomputed from substrates every run; only the declaration pointer can rot, and §4.3's SUSPECT state watches it |
| What survives of the idea | The birth question "how would we know?" | Captured as the one-line declaration + optional `operator_check` hint |

**Recommendation:** observation. The dispatch's prior stands, on evidence: both golden cases are
instances where more pre-ship testing would have tested the wrong axis. One honest pushback on
the framing, in the operator's favor: for operator-facing features, where the operator is
themselves the sensor, "how should I start using/validating this?" is a real unmet need that
observation alone doesn't answer — served here by the `operator_check` field (≤140 chars, plain
text, rendered on the request card), which is the testing-plan idea compressed to its useful
residue.

### 4.2 The liveness declaration (the birth-time contract)

New optional block on each `manifest.json` entry (REQUIRED for entries added after the lint
lands — REQ-A2):

```json
"liveness": {
  "signal": "ledger-gate:plan-edit-validator/flip-verdict",
  "expected_cadence": "per-flip",
  "silence_horizon_days": 7,
  "min_activity_floor": "3 plan-checkbox flips in window (git-derived)",
  "on_demand_justification": "",
  "operator_check": "flip any plan checkbox via task-verifier; a flip-verdict row appears in the signal ledger"
},
"born_of_plan": "status-event-ledger"
```

- **`signal`** — an enumerated-scheme pointer, never free prose: `ledger-gate:<gate>[/<event>]` |
  `ledger-event:<event>` | `artifact:<repo-glob>` | `state-file:<abs-glob>` |
  `scheduled:<schedule-manifest-id>` | `derived-git:<root>` | `unobservable`. The scheme prefix
  selects the substrate reader (OD-023: an agent never wonders what to call something).
  `unobservable` is a legal, honest declaration ("this mechanism leaves no durable trace") — it
  renders as such and generates no anomaly, but is counted, so the unobservable population is a
  visible number with pressure to shrink.
- **`expected_cadence`** — `per-session` | `per-dispatch` | `per-flip` | `daily` | `weekly` |
  `on-demand`. Human-facing label; the machine check uses the horizon.
- **`silence_horizon_days`** — integer, or `null` iff cadence is `on-demand`. The sweep flags
  SILENT only when the last derived observation is older than the horizon AND the activity floor
  (below) is met. `on-demand`/`null` entries are structurally exempt — never a silence anomaly,
  by construction, which is how the check does not cry wolf on manual tools (DEC-8).
- **`min_activity_floor`** — optional; names the demand-side precondition that must hold before
  silence is anomalous (generalizing `--recent-silence`'s min-flips=3 floor: zero flips with zero
  events is idleness, not silence). Entries without a floor treat any elapsed horizon as
  reportable.
- **`on_demand_justification`** — REQUIRED non-empty iff cadence is `on-demand` (DEC-8's
  friction). Lint-checked.
- **`operator_check`** — optional, operator-facing only; never parsed.
- **`born_of_plan`** — optional plan slug; the DEC-5 join key. Required for new entries.

Nothing else. Deliberately absent: `last_fired`, `status`, `verified_on` — any field a human or
agent would have to keep true by hand (DEC-3).

### 4.3 The sweep (`scripts/mechanism-liveness-sweep.sh`)

One read-only pass, exit 0 always (a report, not a gate), `--self-test` sandboxed:

1. Parse manifest once (one jq spawn). Partition entries: declared vs. undeclared vs.
   unobservable vs. on-demand.
2. Read each substrate ONCE, batched by scheme — one jq pass over the signal ledger extracting
   `(gate, event, max ts)` tuples for ALL ledger-declared entries together (the
   verify-event-audit.sh:156-164 lesson, promoted to a design rule: REQ-B4); one `git log
   --since` pass per distinct artifact root; one directory listing of nl-maintenance job markers.
3. Classify each declared entry: `OK(last_seen)` | `NEVER_FIRED` | `SILENT(age > horizon,
   floor met)` | `ON_DEMAND` | `UNOBSERVABLE` | `SUSPECT_DECLARATION`.
   **SUSPECT_DECLARATION** is the anti-rot state (pre-mortem-driven): a `ledger-gate:` pointer
   whose gate name has matched zero rows EVER while sibling evidence shows the mechanism active
   (e.g. its hook file mtime/git activity is recent) is more likely a renamed emitter than a dead
   mechanism — reported as "declaration suspect: signal never matched," distinctly, so a rotten
   pointer cannot masquerade as a dead mechanism (or vice versa) indefinitely.
4. Materialize the FULL report to `~/.claude/state/liveness/liveness-report.json` (atomic
   replace); print ONLY anomalies (NEVER_FIRED, SILENT, SUSPECT_DECLARATION) to stdout, capped
   at 10 lines + an aggregate line (the false-positive doctrine's anomaly budget; the JSON has
   everything, the human surface stays short).

**Cost pricing (invariant 10, platform-priced):** per run ≈ 3-6 subprocess spawns (jq × 2, git ×
1-3, ls × 1) at 152 ms each plus one 17MB jq parse (measured class: seconds, not minutes, when
single-pass — verify-event-audit's `--plan` mode with pre-fetch completes where per-task re-parse
did not). At doctor cadence (30-min TTL ⇒ ≤48 runs/day) worst case ≈ 300 spawn-events/day —
comparable to one `coord-sync` cycle's budget line, and strictly bounded because it rides an
already-scheduled mechanism. HYPOTHESIZED: total wall time ≤ 15 s per run on this machine
(refuter: the timed run REQ-B5 requires as landing evidence).

**Doctor wiring:** `check_mechanism_liveness` invokes the sweep (same degrade-to-silent contract
as check_verify_event_silence: missing script/git/jq ⇒ silent pass, never takes the doctor
down), WARNs with the anomaly lines. `check_verify_event_silence` is retired in the same commit;
its subject becomes the flip-verdict entry's declaration (Supersedes, above). Net doctor check
count: unchanged (+1/−1).

### 4.4 The operator chain (request → built → verified → observed)

Existing links, PROVEN: (1) request = ask registry + Requests tab (requests-routes.js:20-58);
(2) built = `became.plan_slug` → plan checkboxes (task-verifier is the only flipper);
(3) verified = flip-verdict ledger rows (firing post-b7730fb0) + the invariant-verdict ledger for
operator-requirement checks (ask-registry.sh requirement ledger). Missing link, built here:

- Server: a small join in the requests payload — for each ask with `became.plan_slug`, collect
  manifest entries with matching `born_of_plan`, read their states from
  `liveness-report.json` (already on the fs-watch path family), and attach
  `observed: {state: 'observed'|'not-yet'|'silent'|'unobservable'|'n/a', last_seen, detail}`.
  `n/a` = no mechanism claims this plan (docs-only/feature work — the chain honestly ends at
  verified; most historical asks will be `n/a`, and the card says why).
- UI: one chip per request card, with `operator_check` text revealed on expand — the "how should
  I start using/testing this" answer, per feature, zero effort to reach.

**Operator effort, total:** nothing mandatory. The pane and chip render in surfaces the operator
already opens; every state is derived. The single optional habit that adds value: when a chip
says NOT-YET-OBSERVED on something they care about, the expanded `operator_check` line tells
them the one action that would exercise it.

### 4.5 Backfill (what gets declared, what stays honestly unknown)

- **Tier 1 (mechanical, in the implementing plan):** seed declarations for every manifest entry
  whose id or emitter name appears in the measured ledger census (27 distinct gate values; 9 are
  manifest gate ids, the rest map to writer/surfacer entries), the 7 `schedule-manifest.json`
  ids (scheme `scheduled:`, horizon = declared_cadence × safety factor), the flip-verdict
  declaration, and the harness-evaluator packet artifact. Expected yield ≥ 25 entries, each
  derived from an observed substrate — zero guessed signals.
- **Tier 2 (ratchet-on-touch):** any plan task that modifies a mechanism file must add/update its
  liveness block — enforced socially by harness-reviewer's existing per-edit review, plus a
  WARN-level lint (not blocking) when a diff touches a mechanism whose entry lacks the block.
- **Tier 3 (the honest remainder):** everything else stays undeclared; the Health card leads
  with "liveness declared: N/166 · observable now: K · undeclared: M." The number is the
  pressure; no per-entry nagging. What stays unknown stays LABELED unknown — never inferred.
- **New mechanisms:** REQUIRED at birth via `manifest-check.sh` (REQ-A2) — the same mechanical
  bar that already makes `golden_scenario`/`fp_expectation`/`retirement_condition` unavoidable.

**Staleness contract (template requirement):** the Health card and Requests chip may lag reality
by at most one doctor cadence (30 min) + fs-watch delivery (~instant); a mechanism that fired 29
minutes ago may still render NOT-YET-OBSERVED. Acceptable for a weekly-attention operator
surface; stated on the card ("as of <ts>").

## Requirements

### Phase A — declaration substrate

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-A1 | MUST | `manifest.json` schema gains the optional per-entry `liveness` block and `born_of_plan` field exactly as §4.2 specifies (enumerated `signal` schemes; `silence_horizon_days: null` iff `expected_cadence: "on-demand"`; `on_demand_justification` non-empty iff on-demand), documented in the manifest's own top-level note. Verify: `manifest-check.sh --self-test` gains scenarios accepting a valid block and rejecting each malformed shape (bad scheme prefix, null horizon with non-on-demand cadence, empty justification). |
| REQ-A2 | MUST | A manifest entry whose id is NEW relative to the previous manifest revision fails `manifest-check.sh` unless it carries both `liveness` and `born_of_plan`; the block message is a complete {WHAT/WHY/FIX/ESCAPE} instruction per OD-004. Verify: self-test scenario adds an entry without the block → RED with all four fields present in the message; pre-existing entries without blocks stay GREEN. |
| REQ-A3 | MUST | No repo-versioned file stores any last-fired/liveness STATUS value; declarations are pointers only. Verify: `grep -E 'last_fired|last_seen|liveness_status' adapters/claude-code/manifest.json` returns nothing after Tier-1 seeding; sweep output path is under `~/.claude/state/`. |

### Phase B — the sweep

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-B1 | MUST | `scripts/mechanism-liveness-sweep.sh` derives, per declared entry, the classification {OK, NEVER_FIRED, SILENT, ON_DEMAND, UNOBSERVABLE, SUSPECT_DECLARATION} from the declared substrate at read time, honoring `min_activity_floor` (silence requires demand) and the on-demand exemption. Verify: `--self-test` with sandboxed fixtures (own ledger path, scratch git repo, fake job markers) producing each of the six states, including a floor-not-met case that yields OK-idle rather than SILENT. |
| REQ-B2 | MUST | The sweep is read-only, exit 0 always, anomalies-only on stdout (cap 10 + aggregate), full report atomically materialized to `~/.claude/state/liveness/liveness-report.json`. Verify: self-test asserts exit code, stdout cap, and JSON completeness against a >10-anomaly fixture. |
| REQ-B3 | MUST | `harness-doctor.sh` gains `check_mechanism_liveness` (WARN-only, silent-degrade when script/git/jq missing) and retires `check_verify_event_silence` in the same commit, with the flip-verdict liveness declaration landing in the same commit (no coverage gap). Verify: doctor `--self-test` scenario for the new check; `grep -c check_verify_event_silence hooks/harness-doctor.sh` = 0; jq confirms the flip-verdict declaration present. |
| REQ-B4 | MUST | Every substrate is read at most once per sweep run (one ledger fetch shared by all ledger-declared entries — the verify-event-audit.sh:156-164 measured lesson as a design rule). Verify: self-test runs the sweep under a PATH-shimmed jq/git wrapper that counts invocations; assert ledger-jq count == 1 regardless of declared-entry count. |
| REQ-B5 | SHOULD | Sweep wall time ≤ 15 s against this machine's real 17MB ledger and full manifest. Verify: a timed real run cited in the implementing plan's evidence file. |

### Phase C — surfaces

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-C1 | MUST | The cockpit Health tab gains a Mechanism Liveness card reading `liveness-report.json` via the existing fs-watch push path (state-watch.js pattern; no new client polling), leading with the declared/observable/undeclared counts and listing at most the report's anomalies, each with age and signal. Verify: cockpit self-test asserts the card renders from a fixture report; live demonstration screenshot/curl in evidence. |
| REQ-C2 | MUST | The Requests tab payload gains the `observed` join of §4.4 (`ask → became.plan_slug → born_of_plan → state`), rendering one chip per request card with `operator_check` on expand; asks with no claiming mechanism render `n/a` with the chain-ends-at-verified explanation. Verify: server self-test with a fixture ask/plan/manifest triple asserting each chip state incl. `n/a`; UI demonstration in evidence. |
| REQ-C3 | MUST | Chip and card copy comply with asks.js's anti-noise law (no hook/script identifiers in fabricated copy; `operator_check` is operator-authored/reviewed text). Verify: reuse the existing payload-schema scan self-test over the new fields. |

### Phase D — backfill + the evaluator

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-D1 | MUST | Tier-1 seeding lands ≥ 25 derived declarations (ledger-census entries + 7 scheduled ids + flip-verdict + evaluator packet artifact), each with a substrate-derived signal, none guessed. Verify: jq count of entries with `liveness` ≥ 25; spot-check in review that each seeded signal scheme matches a measured substrate hit. |
| REQ-D2 | MUST | Undeclared entries remain untouched and are surfaced as the counted `undeclared` population (OD-010: explicit disposition, here "declared-unknown"), never auto-filled. Verify: jq confirms entry count still 166 with M entries lacking the block; Health card fixture renders the split. |
| REQ-D3 | SHOULD | `harness-evaluator` gains a `config/schedule-manifest.json` entry (managed_by `nl-maintenance`, weekly floor, platform_cost_lines populated) running the §7-named wrapper; `install-daily-harness-eval-task.ps1` is marked retired via the `retired_installer_note` convention; each machine's absent legacy task is verified during rollout. Its own liveness declaration (`artifact:docs/reviews/*harness-self-eval*.md`, horizon 9 days) lands in Tier 1 regardless — so if scheduling slips again, the sweep says so within one horizon. Verify: schedule-manifest entry present; sweep against the real repo reports the evaluator row (SILENT today, OK after the first scheduled run). |
| REQ-D4 | SHOULD | `doctrine/harness-dev.md` gains the liveness-declaration discipline (birth question, scheme vocabulary, on-demand justification bar) in its new-mechanism checklist. Verify: section present; doctrine-jit surfaces it on mechanism-file edits per existing jit_triggers. |

## Non-goals

- **Universal runtime instrumentation** (an emit-wrapper forcing all 166 mechanisms to write
  ledger rows on every fire) — true fire-counts everywhere, but a spawn per fire across 40+
  blocking gates at Windows spawn cost is exactly the per-Bash-call regression class invariant 10
  exists to prevent; excluded, not deferred. The `unobservable` declaration is the honest
  alternative; entries can graduate to observability individually when touched.
- **Blocking on silence** — the sweep never gates anything; §10's evidence bar for a blocking
  version is not met (no golden scenario where a block, rather than a WARN, would have changed
  the outcome — golden case 1 needed visibility, not obstruction). Tracked nowhere; a future
  design must bring its own §10 case.
- **Hand-backfilling all 166 entries** — DEC-6; fabricated declarations are worse than counted
  unknowns. Tier 2/3 is the standing path.
- **Correctness auditing of firing mechanisms** (fires-but-wrongly, bypass, erosion) — the
  harness-evaluator's remit (agents/harness-evaluator.md Phases 2-4), sharpened by REQ-D3's
  scheduling; not the sweep's.
- **Cross-machine liveness aggregation** — each machine's ledger/state is local; a mechanism
  alive on one machine and dead on another renders per-machine. Tracked as a natural follow-on
  in the coord-sync family, not designed here.
- **Ask-registry schema changes** — DEC-5 derives the fourth link; the fold contract stays
  untouched.
- **HARNESS-GAP-63** (the awk double-print bug, docs/backlog.md:144) — unrelated, stays open,
  named per OD-010.

## What this design gives up (named sacrifice)

- **Rejected cheaper alternative: "just schedule harness-evaluator and stop."** One
  schedule-manifest entry, near-zero build cost. Rejected as the whole fix because it is
  judgment-priced (Fable weekly), human-consumed (a packet the operator must read), and
  non-mechanical — and because "the mechanism that audits mechanisms was itself never scheduled"
  is the standing proof that unscheduled-judgment is exactly the shape that fails here. It ships
  anyway (REQ-D3), as a complement.
- **Rejected: per-feature testing plans** (DEC-1) — the operator's own proposal, declined with
  the §4.1 comparison rather than absorbed politely.
- **Capability deliberately NOT built: true fire-counting.** The sweep sees last-observed-signal,
  not frequency or correctness; a mechanism that fired once into its horizon reads OK. Frequency
  anomalies (fired 500×/day last month, 2×/day now) are invisible. Tracked as: harness-evaluator
  Phase 5 drift-over-time territory, plus the per-entry graduation path in Non-goals #1.
- **Standing cost accepted:** ~3-6 spawns + one 17MB parse per doctor run (≤48/day; ≈ one
  coord-sync cycle's budget class) + one new manifest block per future mechanism (~8 lines of
  JSON each, amortized against OD-002 by the two retirements named in Supersedes) + one more
  Health-pane card competing for the operator's glance (bounded by the 10-anomaly cap). Against
  the measured alternative: the status quo's cost was 926 checked tasks silently unverified-
  on-record for 5 days and a watchdog unscheduled for 71 days, each discovered only by operator
  re-proposal — the exact waste the problem statement prices in operator trust.

## Pre-mortem

Six months out, the postmortem reads: the lint made every new mechanism declare liveness, and
authors learned that `"expected_cadence": "on-demand"` plus a boilerplate justification
("invoked manually as needed") silences it — 60% of new entries took that exit, so the sweep
watched an ever-shrinking fraction of the estate. Meanwhile three seeded `ledger-gate:` pointers
went stale when a hook was renamed in a refactor (the manifest entry was updated, the liveness
signal string wasn't), and the pane showed the same three SILENT rows for eleven weeks. The
operator, trained by eleven weeks of false red, stopped opening the card in week four — so when
review-verdict emission genuinely broke in month five, its SILENT row joined three false ones in
a pane nobody read. The design died of the exact disease it was built to cure: a mechanism
(the sweep) that was design-effective and operating-ignored.

**What changes now to make that story impossible:**
1. **SUSPECT_DECLARATION is a first-class state** (§4.3): a never-matching pointer on an
   otherwise-active mechanism is reported as declaration rot, not mechanism death — different
   copy, different fix instruction — so stale pointers cannot manufacture standing false-SILENT
   rows. (This is also why derivation is preferred wherever possible: a derived signal cannot
   drift from its substrate, only a pointer can, and the pointer-check is itself mechanical.)
2. **The on-demand exit has friction and a meter:** non-empty justification required (DEC-8,
   REQ-A1), and the Health card's headline split counts the on-demand population explicitly — a
   climbing on-demand share is visible on the same card, and the harness-evaluator's weekly
   Phase-2 pass (REQ-D3 makes it actually run) audits whether on-demand declarations are honest,
   closing the loop mechanically-plus-judgment.
3. **The sweep carries its own §10 retirement condition** (in its manifest entry, per REQ-A2's
   own bar applied to itself): if over any 30-day window the majority of its anomalies are
   declaration-rot rather than real silence, the declaration substrate is redesigned or the
   sweep retired — written into the entry at birth, so the failure mode has a named tripwire
   instead of a slow fade.
4. **The anomaly cap (10 + aggregate)** keeps the pane short enough that a real new row is
   conspicuous rather than lost in a wall — the false-positive doctrine applied to layout.

## Verification strategy

The whole-design proof is the two golden cases replayed through the built system, plus one live
demonstration — not the per-REQ checks alone:

1. **Golden-case-1 replay (fixture):** a sandboxed sweep run against a fixture manifest carrying
   the flip-verdict declaration and an empty ledger MUST classify it NEVER_FIRED; the same run
   after injecting one matching row MUST flip to OK. This is the 926/0 world and its repair,
   as a standing self-test scenario.
2. **Golden-case-2 replay (live):** the first real sweep run on this machine, before REQ-D3's
   schedule entry activates, MUST report the harness-evaluator row SILENT (last packet
   2026-07-29 against a 9-day horizon) — a true positive on real data, cited in the evidence
   file with its output line. After the first scheduled run, the row flips OK. This is the
   maintainer-as-user demonstration (constitution §4): the harness's own defect class, caught by
   the shipped mechanism, shown live.
3. **Operator-path demonstration:** one request card in the live cockpit showing all four links,
   with the `observed` chip in a real state and `operator_check` rendered — screenshot/curl in
   evidence. Functionality over components: the operator can DO the thing (glance and know).
4. All `--self-test` suites (sweep, manifest-check additions, doctor scenario, cockpit/server
   fixtures) green on both interpreters per house convention, and `harness-doctor.sh --quick`
   stays GREEN post-integration.

## Directives honored

- OD-001 (`no-wsl-dependency`, surfaces `docs/designs/**`) — pure portable bash + jq; no WSL
  anywhere in §4.
- OD-002 (`anti-bloat-modify-not-add`, surfaces `docs/designs/**`) — two named retirements
  (check_verify_event_silence absorbed, evaluator installer path superseded), zero new scheduled
  tasks/hooks; net doctor check count unchanged.
- OD-003 (`no-new-hardware`, surfaces `docs/designs/**`) — runs on all current machines;
  scheduled parts ride nl-maintenance's existing per-platform adapters.
- OD-004 (`gate-philosophy-complete-instruction`) — the one blocking surface touched (REQ-A2's
  manifest-check extension) emits the four-field {WHAT/WHY/FIX/ESCAPE} message, verified by
  self-test.
- OD-006 (`push-over-pull-push-materialize`, surfaces `docs/designs/**` +
  `neural-lace/workstreams-ui/**`) — sweep materializes state; cockpit consumes via fs-watch
  push; no new polling loop (§4 diagram; REQ-C1's "no new client polling" clause).
- OD-010 (`disposition-everything`) — all 166 entries get an explicit liveness disposition,
  including the honest `undeclared` and `unobservable` states; nothing silently unclassified
  (REQ-D2).
- OD-016 (`observability-equal-clarity`) — the same report feeds the doctor (machine) and the
  Health card + Requests chip (human), one derivation, two surfaces.
- OD-017 (`self-learning-closed-loop`, surfaces `docs/reviews/**`) — both golden cases become
  standing regression scenarios (Verification strategy 1-2); the closure names the mechanism
  preventing recurrence, not just the diff.
- OD-018 (`incentive-by-design-cheapest-path`) — declaring at birth is one JSON block inside a
  file the author is already editing; the evasion (`on-demand` boilerplate) costs a justification
  sentence and is metered (pre-mortem defense 2).
- OD-022 (`merge-verify-mechanization`) — extends the operator's "continuously getting cleaner"
  directive one link past verification: built→verified→observed, mechanically derived.
- OD-023 (`task-id-determinism`) — the signal vocabulary is an enumerated scheme grammar, never
  free text an agent must guess at (§4.2).
- D-13 / D-15 (docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4; not yet OD-mapped)
  — this design is Fable-authored by the pinned design-author agent, and enters the gated
  pipeline: architecture-reviewer + harness-reviewer next, per the Review Chain below.

## Review Chain

authored-by: design-author (model: fable / claude-fable-5)
design-reviews:
  - reviewer: architecture-reviewer  verdict: PENDING  record: docs/reviews/ (to be created on review)
  - reviewer: harness-reviewer       verdict: PENDING  record: docs/reviews/ (to be created on review — harness-surface design: manifest.json, harness-doctor.sh, scripts/, cockpit)
