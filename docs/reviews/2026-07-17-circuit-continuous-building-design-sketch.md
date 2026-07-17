# Circuit continuous-building system — design sketch

Status: DRAFT design sketch (2026-07-17). Not a plan. Written to survive `architecture-reviewer`
(`adapters/claude-code/agents/architecture-reviewer.md`): named forces, one explicit invariant, an
honest what-each-choice-SACRIFICES pass, per-stage staleness contracts, and **zero false mechanism
claims** — where a primitive does not exist I say so and name the gap, rather than describe the dream as
if it were wired.

Author's frame: the operator's vision (verbatim, 2026-07-17) bundles **four different problems** into one
sentence — "Claude continuously ingests our meeting notes, builds them, and everyone sees the status."
Decomposed, they have four different designs and four very different maturities:

| Problem | What it actually is | Maturity in THIS harness today |
|---|---|---|
| A — meeting intent evaporates | a connector + extraction problem | **greenfield** (no connector exists) |
| B — nobody can see status | a read-only derived-view problem | **~80% built** (cockpit + deferred Team tab) |
| C — building needs babysitting | an autonomy problem | **partially built, and platform-capped** (orchestrator-prime; ADR 050) |
| D — two builders collide | a cross-machine coordination problem | **~90% built** (claims + coord-sync + ownership gate) |

The honest headline: **B and D are nearly done and this sketch mostly wires them together; A is real new
work; C is where the dream meets a hard platform wall that no amount of design removes.** A sketch that
pretends C is "just point orchestrator-prime at a queue" would be the exact false-mechanism failure the
architecture-reviewer exists to catch. §7 (THE ONE THING) states the wall plainly.

---

## §3 DECISION BLOCK — the calls only the operator can make

These four are genuinely yours (business intent · irreversible spend · customer-facing merge authority ·
external access). Everything else in this sketch I have decided and recorded inline with its reasoning —
you review those in one place at build time, you do not answer them now. Cold-reader note: each row below
names the concrete system so you can answer without session context.

**Decision needed:** four inputs that gate the pipeline; the design proceeds on the recommended answers
until you say otherwise.

| # | Decision | Options | My pick | Why it's yours |
|---|---|---|---|---|
| D1 | **Where do Circuit meeting notes live, and what reads them daily?** The pipeline's whole input. | (a) Google Docs/Drive folder via a Google connector; (b) a synced Markdown folder (Obsidian/Drive-desktop/a repo `meeting-notes/`) read by a local file trigger; (c) Zoom/Meet auto-transcripts via their API | **(b) a synced folder** for P1 (zero new auth, push-triggerable, git-native), migrate to (a) if notes live in Docs and won't move | Only you know where your team actually writes notes + which account owns them |
| D2 | **Does an extracted item auto-become build work, or wait for a human "approve"?** | (a) auto-schedule everything; (b) extract → `PROPOSED` backlog row → a human promotes to `SCHEDULED` (the meeting itself, or one click); (c) auto-schedule only "improvement" class, gate "roadmap" class | **(b)** — the promote IS the roadmap decision; costs one click, prevents building un-vetted intent | "What should we build at all" is business judgment, not a mechanism |
| D3 | **The 24/7 token spend ceiling + stand-down threshold.** You hit the weekly limit TWICE this month; an ungoverned loop hits it faster. | a daily-tokens (or daily-USD-equiv) cap the loop self-enforces via `nl costs`, plus a "% of weekly remaining" at which it drops to human-gated-only | **name a daily cap + stand down at 20% weekly-remaining** (I'll wire whatever number you give) | Only you know your plan's limit and how much of it Circuit may consume vs your other work |
| D4 | **What may the builder merge to Circuit UNATTENDED vs queue for a human?** | (a) nothing auto — every Circuit PR queued; (b) auto-merge green + reviewed non-customer-facing changes, queue anything touching customer-facing surfaces; (c) full auto | **(b)** via Circuit's own `automation-mode.json` = `review-before-deploy` for customer-facing paths | Circuit has real users; an unattended prod merge is a one-way door onto them |

**Reply with:** `D1: a|b|c`, `D2: a|b|c`, `D3: <daily cap> / <stand-down %>`, `D4: a|b|c`. Anything you
skip, I proceed on my pick and record it in the Decisions Log for your later review.

---

## Phase-0 — independent derivation (problem · forces · invariant · candidate · sacrifice)

Written before proposing, per the reviewer's anti-anchoring discipline, so a reviewer can check where my
derivation and my own proposal diverge.

**The real problem (not the proxy).** The proxy problem is "Claude should run 24/7." The *real* problem is
that **team intent has no durable, provenance-traced path from the meeting where it is spoken to the build
queue, and the building itself stalls whenever a human stops poking a session** — while two people building
in parallel cannot see each other's work. "Run 24/7" is a *proposed mechanism* for the second half, not the
problem; the problem is *intent-loss + poke-dependence + invisibility*, and some of that is solvable without
any 24/7 loop at all.

**The forces that shape any solution here.**
- **Cost is the binding constraint, not latency.** The operator hit the weekly token limit twice this
  month. A design that is correct but burns budget is wrong here. Every other force yields to this one.
- **Consistency across two machines / ~59 worktrees.** Any machine-global read-modify-write blob loses
  updates on the *routine* path (architecture-reviewer known hazard; `broadcast-active-session.sh` header).
- **Durability of intent.** A meeting item must survive a failed pull, a crash, a reboot — it is the
  product's roadmap, not a cache.
- **Operability / does-anyone-know-it-died.** A 24/7 loop that silently stops is worse than no loop: the
  team believes work is happening when it is not (a §1 honesty violation rendered as a dashboard).
- **Who maintains it:** a two-person team, part-time. Complexity they cannot debug at 11pm is a liability.
- **How it fails:** slow < wrong-and-loud < wrong-and-silent. The whole status surface must obey this.

**The invariant (one sentence).** *Every row on the status page traces to a real, provenance-stamped
operator/meeting intent, and every state it shows is DERIVED from ground truth — git, session heartbeats,
the append-only ask registry, merged SHAs — never self-reported by a builder, and never rendered as more
complete than what is merged to Circuit's master.*

**My candidate design, in three lines.** (1) Extraction writes meeting items into the **existing
append-only ask registry** (`ask-registry.sh`) with `verbatim_ref` back to the note line, then into the
**existing backlog** as `PROPOSED` rows; a human promote turns them `SCHEDULED`. (2) Status is the
**existing read-only cockpit** with the **already-reserved-but-hidden Team tab** un-hidden, per-person
"working now" DERIVED from **session heartbeats** (never self-report), peer state via the **existing
coord-sync git ref**. (3) The builder is **orchestrator-prime as it exists**, self-pacing via
ScheduleWakeup, running builders as in-session subagents, budget-governed by `nl costs`, honest that it is
"self-driving while alive" not "autonomous across its own death."

**What my candidate sacrifices.** It does NOT deliver zero-human 24/7 building — it cannot, because the
verified tool surface has no unattended new-session-spawn primitive (§4, §7). It buys honesty and reuse at
the cost of the literal dream. It also accepts up-to-~10-minute cross-machine status staleness (the
coord-sync throttle) rather than building a real-time transport that would cost far more than a two-person
team needs.

**Divergence from the operator's framing.** The operator specifies an *implementation* ("Claude runs 24/7,
building everything"). The *outcomes* behind it — intent captured, built under the evidence bar, visible to
everyone, with minimal poking — are largely deliverable. The literal "24/7 fully-autonomous" is capped by a
platform limit (no unattended spawn; §4). Where the dream and the primitives disagree, the primitive wins,
and I name the gap rather than paper it.

---

## 1. The pipeline, end to end

Notation per stage: **Trigger** (push preferred over poll) · **Mechanism** (the deterministic thing that
runs — REUSED unless marked NEW) · **Human decision** (where a person must judge) · **Sacrifice**.

```
meeting note ──①extract──▶ ask registry (verbatim_ref) ──②register──▶ backlog PROPOSED rows
     │                                                                        │
     │                                                          ③ HUMAN PROMOTE (roadmap gate, D2)
     ▼                                                                        ▼
 (the source of truth for intent)                                    backlog SCHEDULED / build-ready
                                                                              │
                                                        ④ plan formation UNDER THE EVIDENCE BAR
                                                     (design→plan→architecture-reviewer→build→verify)
                                                                              │
                                                         ⑤ continuous builder consumes the queue
                                                                              │
                                              ⑥ progress DERIVED back to the status page (no new emit)
```

**① Extract.** *Trigger:* file-write on the synced notes folder (D1-b) or a daily scheduled pull (D1-a/c)
— push where the source allows it, poll once daily otherwise. *Mechanism (NEW):* a small extractor
(one Claude subagent invocation, tiered to Sonnet — this is mechanical breadth, not the highest-value hard
work reserved for Fable per `feedback-fable-only-when-real-value`) reads the day's note and emits, per
extracted item: `{class: action|roadmap|improvement, text, owner, source_ref}` where `source_ref` is the
note path + line. *Human decision:* none yet — extraction is lossless capture, not judgment. *Sacrifice:*
an LLM extractor is non-deterministic; two runs over the same note may phrase items differently. Mitigation
is idempotency by `source_ref` (see the failure table) — re-extraction of the same line updates, never
duplicates.

**② Register.** *Trigger:* extractor output. *Mechanism (REUSE):* `ask-registry.sh register --text <item>
--verbatim-ref <note#line> --project circuit` appends one `created` record to the append-only registry
(`~/.claude/state/ask-registry.jsonl` + the in-repo mirror `docs/asks/ask-registry.jsonl`). This is the
system's existing "record the operator's ask verbatim" primitive — meeting items ARE asks, so they get the
same provenance carrier (`user`, `machine`, `verbatim_ref`, `origin_session`) the whole cockpit already
reads. *Human decision:* none. *Sacrifice:* the registry gains rows that were never typed by a human into a
session — the `origin_session` field is empty for note-sourced asks. Handled by a distinct
`emitter:"notes-extractor"` value so the UI can label provenance honestly ("from the 07-17 standup") rather
than pretending a session authored it.

**③ Promote (the roadmap gate — D2).** *Trigger:* human. *Mechanism (REUSE):* the item lands as a backlog
row in state `PROPOSED`; a human promotes it to `SCHEDULED` using the **existing backlog triage vocabulary**
(`SCHEDULE` / `DEMOTE` / `FOLD` / `WONTFIX` — `docs/backlog.md`). Promotion is one affordance on the status
page, or simply the meeting's own decision recorded. *Human decision:* **this is the roadmap-approval gate,
and I recommend it sits HERE** — before plan formation, not after. Rationale: "should we build this at all"
is business intent (a human call); "is this plan sound" is the mechanical evidence bar (④). Two distinct
gates; conflating them either builds un-vetted intent (gate too late) or asks the reviewer panel to make
product calls (gate too early). *Sacrifice:* nothing auto-flows to build; an item nobody promotes sits in
`PROPOSED` forever — which is correct (unpromoted intent is a parking lot, not a leak), and the backlog
digest already surfaces age-crossed rows so nothing rots silently.

**④ Plan formation under the evidence bar.** *Trigger:* a `SCHEDULED` row with no linked plan. *Mechanism
(REUSE):* the normal delivery pipeline — a plan is authored in `docs/plans/`, back-linked to the ask
(`start-plan.sh --ask-id` → `ask-registry.sh link-plan`), and **cannot move to build until it clears the
existing gates**: `architecture-reviewer` for any data/flow shape, `systems-designer` for Mode:design,
`end-user-advocate` acceptance scenarios, comprehension gates, `task-verifier`. *Human decision:* the
reviewer verdicts are mechanical, but a NEEDS-RESHAPING verdict surfaces to a human. *Sacrifice:* this is
deliberately NOT fast. Meeting-to-merged is gated by real review, so "built into the plan" means *composed
with* the evidence bar, never *bypassing* it. The operator who wants same-day turnaround on a roadmap item
trades that for the bar that keeps Circuit from shipping unreviewed architecture.

**⑤ Continuous builder consumes the queue.** *Trigger:* orchestrator-prime's self-wake cycle. *Mechanism
(REUSE + one honest gap):* see §4 in full — this is the stage with the platform wall. The queue it consumes
is **DERIVED** from `SCHEDULED` backlog rows + build-ready plans, NOT a new hand-maintained store (avoiding a
second source of truth). *Human decision:* what merges unattended (D4). *Sacrifice:* named in §4.

**⑥ Progress flows back.** *Trigger:* none — this is the key reuse. *Mechanism (REUSE):* the status page is
READ-ONLY and DERIVES everything from ground truth already. A builder committing, a plan's checkbox
flipping, a PR merging, a heartbeat ticking — all are *already* observed by the existing `nl`
derivation lib and the ask-tree read surface. **No new emission path is added; adding one would be the
maintain-don't-derive anti-pattern the cockpit was rebuilt to kill** (`workstreams-ui/README.md`,
NL-FINDING-024). *Human decision:* none. *Sacrifice:* progress is only as fresh as the derivation cache
(30s local) + the cross-machine pull (§3-staleness) — real-time it is not, and the page must timestamp
every pane rather than imply live.

---

## 2. The KEY unresolved input — where meeting notes live (D1)

**This is the operator's question and the design does not assume an answer.** The entire pipeline hangs off
one connector, and the harness has **none today** (verified: no meeting-notes reader exists in
`adapters/claude-code/scripts/` or the cockpit). Three realistic options, with the tradeoff that actually
matters (auth surface × trigger quality × who maintains it):

| Option | How it reads | Auth / access | Trigger | Cost / risk |
|---|---|---|---|---|
| **(a) Google Docs/Drive connector** | Drive API lists a shared folder; Docs API pulls text daily | A Google OAuth token scoped to one Drive folder — a real secret to store + rotate; **which of the two accounts owns it matters** (the two-GitHub-account lesson generalizes: wrong account = 403) | **Poll** (daily) — Drive push-notifications exist but need a public webhook endpoint this local harness has no place to host | Highest: external secret, an OAuth app, no clean push. Wins only if notes truly live in Docs and won't move |
| **(b) Synced Markdown folder** (Drive-desktop / Obsidian-sync / a `meeting-notes/` git dir) | read a local path | **none** — it's a local file | **Push:** a file-write trigger fires extraction the moment a note lands (or a cheap hourly scan) | Lowest. Git-native, no secret, no external API. The catch: someone must put notes in the folder (a workflow habit, not a mechanism). **Recommended for P1.** |
| **(c) Zoom/Meet auto-transcript API** | pull the transcript after each meeting | a Zoom/Meet API token (another external secret + account-ownership question) | webhook on meeting-end (same public-endpoint problem as (a)) | Transcripts are raw speech — extraction quality is far lower than from written notes; you'd build a heavier extractor to compensate |

**My recommendation:** start on **(b)** — it is the only option that is push-triggered, secret-free, and
survives a reviewer's "what happens when the connector's auth breaks at 3am" question (answer: a local file
can't 403). Migrate to (a) only if your team's notes genuinely live in Google Docs and moving them to a
synced folder is more friction than an OAuth app. **Do not** build (a) or (c) speculatively — a connector
with a stored external secret and no local push endpoint is real one-way-door complexity (secret rotation,
account-blindness, webhook hosting) that YAGNI says to defer until (b) is proven insufficient.

---

## 3. Status page — what changes vs today's cockpit

Today's cockpit (`neural-lace/workstreams-ui/`) is a localhost READ-ONLY dashboard: an Asks landing tab + a
demoted Harness Health tab. It DERIVES from the `nl` oracle; it renders NO write affordances; and — by
deliberate design — **it ships no Team tab in P1** ("No Team tab ships in P1 … no nav entry and no markup",
README Task 16). The asks/payloads already carry the multi-user provenance fields (`user`, `machine`,
`origin_session`, per-record author-stamped in `ask-registry.sh`) reserved for exactly this. So the status
work is mostly **un-hiding and joining, not building.**

**Changes:**

1. **Un-hide the Team tab.** A third nav tab beside Asks / Harness Health. It renders two derived views:
   - **"Working on now" — per person, DERIVED from session heartbeats, NEVER self-reported.** The heartbeat
     files (`session-heartbeat.sh`, classified `live | stale | throttled | crashed | missing` on READ by
     the shared `hb_classify`) carry pid, cwd, **branch**, model, and the last turn's marker
     (DONE/PAUSING/BLOCKED/CONTINUING). Joined to the ask registry by branch/plan, this yields "Misha is
     live on `circuit/checkout-flow` (plan X, task 3)" with **zero self-report** — the reviewer's "un-merged
     worktree state must never render as done" hazard is respected because the source is liveness + git, not
     a builder's claim.
   - **Cross-machine merge:** the peer machine's heartbeats/tree-state arrive via the **existing coord-sync
     git ref** (`coord-pull.sh` refreshes the local clone of the private `workstreams-coordination` repo;
     each machine writes only its own `tree-state/<hostname>.json`). This is the cockpit-v2 foundation
     (§5 phasing) — the status page reads the merged set and shows which machine each row came from.

2. **Meeting-visible view.** A large-type, low-chrome layout of the Team tab suitable for projecting in a
   standup — same derived data, bigger. No new data path; a CSS/layout mode.

3. **Provenance labelling.** Note-sourced asks (§1-②) render "from the 07-17 standup" via their
   `emitter:"notes-extractor"` + `verbatim_ref`, distinct from session-authored asks. **Anti-noise law
   holds:** no gate/hook identifier ever appears on this surface (mechanically checked in
   `cockpit.selftest.js`); "notes-extractor" is a provenance label, not a harness-internal identifier — I
   flag this as a line to watch in review, because it widens what appears on the operator surface and the
   payload allowlist (`payload-schema.js`) must be extended by KEY, exactly as the cockpit-v2 `description`
   carve-out was (that plan's finding m1).

**Multi-user contract (the part a reviewer will attack):**

- **Identity = `git config user.email`, displayed via a small `config/people.js` map** (mirroring the
  existing `config/projects.js`). Rationale, and why this is MY call not yours: the ask registry already
  stamps `user` (git identity) on every record; `hostname` identifies the *machine*, not the *person* (one
  person can drive two machines, or two people could share one — so hostname-as-person is a latent bug). Git
  email is stable, already captured, and survives a machine swap. This is a reversible technical choice
  (`feedback-dont-surface-reversible-technical-decisions`), so I decide it and record it here rather than
  spending your attention.
- **Who sees what:** it is a two-person team on a localhost read-only dashboard; there is no auth server and
  none is warranted. Each person runs their own cockpit, which shows *everyone's* work (self + peer via
  coord-pull). No per-user filtering. If the team grows past a handful, revisit — but building RBAC for two
  people is the accidental-complexity the reviewer would rightly flag.
- **Single-writer rule for shared state (the invariant that keeps two machines from corrupting each other):**
  *no shared mutable blob exists.* Each machine writes ONLY (i) its own `tree-state/<hostname>.json`
  (partitioned by hostname — single-writer-per-file) and (ii) append-only ask-registry records stamped with
  its own `user`/`machine`. The merged view is a deterministic **union + per-field last-write-wins fold**
  (the registry's existing fold contract: "last-write-wins per field, blanks never overwrite"). There is no
  read-modify-write of a shared object anywhere on the path, so the "machine-global blob loses updates"
  hazard cannot fire — by construction, not by luck.

---

## 4. The continuous 24/7 builder — engine choice, honestly

**Candidate engines evaluated against the verified tool surface** (not against the dream):

| Engine | What it really is | Fatal gap for "24/7 autonomous building" |
|---|---|---|
| **orchestrator-prime** (`~/.claude/skills/orchestrator-prime/`, ADR 050) | a long-lived Code session that self-wakes (ScheduleWakeup, clamped 60–3600s), holds full harness awareness, and per cycle: coord-pulls, sweeps sessions, spawns work, PR-sweeps + **auto-merges** per policy, surfaces to Misha via a chip | **No unattended new-session spawn.** `spawn_task` surfaces a CHIP THAT MISHA MUST CLICK (SKILL.md, verified) — it is notification + human-gated spawn, not autonomous spawn. The orchestrator CAN run builders as **in-session Agent subagents** (consuming ITS OWN token budget, in ITS OWN context), but that is bounded by one session's lifetime and budget, not "24/7." |
| **Scheduled cloud agents / routines** (`mcp__scheduled-tasks`, the `schedule` skill) | headless cron-run agents in Anthropic's cloud | **Harness-blind** (project `.claude/` only, Decision 011) AND **skill-registry-blind** — the 2026-06-11 discovery PROVED `Skill("orchestrator-prime")` returns "Unknown skill" in scheduled-task context. A cloud agent cannot BE orchestrator-prime, cannot see `~/.claude/agents`, cannot invoke the specialist reviewers. It re-creates the sandbox-blindness ADR 050 was built to escape. |
| **A cron `claude -p` local session** | a scripted headless local invocation on a timer | Runs on the local machine (so it CAN see the harness), but a fresh `-p` session cold-starts every fire (re-hydrate cost) and still cannot spawn independent child sessions unattended — same wall, plus per-fire cold-start burn against D3's budget. |

**Verdict: orchestrator-prime is the right engine — but its honest capability is "self-driving WHILE
ALIVE," not "autonomous across its own death," and the sketch must say so.** Concretely:

- **What is mechanically true:** while an orchestrator-prime session is alive, it self-paces via
  ScheduleWakeup, runs builders as in-session subagents, auto-merges green reviewed PRs per policy, and
  keeps the queue moving without Misha poking each session. That is a large, real fraction of the dream.
- **The wall (THE ONE THING — see §7):** there is **no verified primitive for an unattended process to
  spin up a NEW independent full-autonomy building session.** `spawn_task` needs a human click; the
  scheduled-task Skill registry can't load the orchestrator; cloud agents can't see the harness. So
  "continuous building with zero human involvement" is **not available today** — not as a design choice,
  as a platform fact. When the orchestrator session dies (reboot, crash, or **hitting the weekly limit —
  which happened twice this month**), restarting it needs a human, because the keepalive's own cold-start
  path is the exact thing the 2026-06-11 discovery proved broken in scheduled context (parked per
  DEC-2026-07-02-002). **Any claim that this system "runs 24/7 autonomously" is false until that upstream
  primitive exists; what it does is run continuously while alive and require a human to relaunch across
  deaths.** I am filing this as the load-bearing honest boundary, not a footnote.

**Budget governance (D3) — mandatory, because the loop that ignores it re-hits the weekly limit.**
- **Idle-when-queue-empty:** ScheduleWakeup backs off toward its 3600s ceiling when the derived queue is
  empty; a busy queue tightens it. No fork-per-tick polling (the ~87ms/spawn Windows floor forbids busy
  loops — architecture-reviewer known hazard).
- **Tiering:** Fable ONLY for the highest-value hard work — architecture/plan/design/review of a
  substantial roadmap item (`feedback-fable-only-when-real-value`). Extraction, triage, mechanical breadth,
  status derivation → Sonnet/Haiku. This is the single biggest lever on burn.
- **Self-enforced ceiling:** each cycle reads `nl costs`; at the D3 stand-down threshold the loop drops to
  **human-gated-only** (surface chips, stop spawning builders) and, near the hard limit, stands down
  entirely with a chip. The loop that budgets itself is the difference between "dream" and "third weekly
  limit."

**Unattended safety (D4) — the guardrails already exist; the DECISION is the policy.**
- The mechanism is the existing **per-repo `automation-mode.json`** + the **full-auto-merge authorization**
  (memory: operator 2026-07-07) + the orchestrator's **hard exclusion "never merge onto a master without a
  green prod deploy."** For Circuit specifically, D4 sets the policy: recommend `review-before-deploy` for
  customer-facing surfaces (Circuit has real users — an unattended prod merge onto them is a one-way door),
  auto-merge for green + reviewed internal changes. The evidence-bar gates (architecture-reviewer,
  end-user-advocate, task-verifier) are the technical guardrail; D4 is the business one.

**Failure recovery (reap-what-you-spawn).** A subagent builder that stalls is detected by the same
heartbeat classification (`crashed`/`stale`) and the agent-heartbeat watchdog
(`docs/lessons/2026-07-14-background-agent-heartbeat-watchdog.md`); the orchestrator respawns a REPLACEMENT
(it cannot message the original — RC1). Every spawned unit is a tracked obligation until its result is
consumed (constitution §8). The one gap it cannot self-heal is its OWN death — that surfaces a relaunch
chip; it does not silently vanish.

**Two-machine coordination (both running builders).** This is D (nearly built). Before spawning, the
orchestrator `coord-pull`s and **respects peer claims** — `broadcast-active-session.sh claim` writes a
per-branch claim; `concurrent-ownership-gate.sh` blocks a second builder from taking a branch/plan a peer
holds an unexpired claim on (2h freshness). So "both machines build" resolves to: partitioned by claim, and
a queue item a peer is building is skipped, not double-taken. The shared queue is DERIVED (not a mutable
store two writers race on), so there is no lost-update path on the queue itself.

---

## 5. Phasing (each phase: user-visible outcome). Explicitly AFTER cockpit-v2.

**Sequencing constraint (hard):** cockpit-v2's cross-machine store
(`docs/plans/cockpit-v2-push-materialized-store.md`, currently DRAFT v3, post-architecture-review) is the
**foundation** for the Team tab's cross-machine merge and for the derived queue. It must land first. This
sketch does not re-open that design — it consumes it. (Note the reviewer's standing warning on that plan:
the store is justified ONLY as a cross-machine artifact via a dedicated git ref; if cross-machine is ever
dropped, it reverts to the in-memory cache. This sketch is precisely the cross-machine consumer that
justifies it.)

| Phase | Smallest end-to-end slice | User-visible outcome |
|---|---|---|
| **P0 (prerequisite)** | cockpit-v2 cross-machine store lands | peer machine's plan/session state appears, current, in this cockpit |
| **P1** | **one meeting note → one backlog item → visible on the status page.** Connector (D1-b synced folder), extractor (Sonnet subagent, idempotent by `source_ref`), `ask-registry.sh register` + `PROPOSED` backlog row, Team tab un-hidden showing that row + who's live (heartbeat-derived) | drop a note in the folder → its action items appear as PROPOSED rows on a status page everyone can see. **No autonomous building yet.** |
| **P2** | **promote → plan → built under the bar, with progress derived back.** The D2 promote affordance; `SCHEDULED` rows form plans through the evidence bar; orchestrator-prime consumes the derived queue as in-session subagents; progress flows back via existing derivation. Budget governance (D3) live. | a promoted roadmap item gets planned, reviewed, and built while you watch progress on the status page — poking-minimal while the orchestrator is alive. |
| **P3** | **cross-machine builder coordination + meeting-visible view + provenance polish.** Both machines' orchestrators respect claims; the standup projection layout; note-provenance labels; relaunch-chip UX for orchestrator death. | two people build in parallel without collision; the team projects one live status board in standup; every row shows where it came from. **Still human-relaunch across orchestrator death — that boundary does not move without an upstream primitive.** |

---

## 6. Forces · invariant · sacrifices · staleness contracts (the reviewer's explicit bar)

**Invariant** (restated, load-bearing): *every status row traces to a provenance-stamped intent; every state
is DERIVED from ground truth, never self-reported, never shown more-done than merged.*

**Load-bearing premises — and which are shaky (stated so a reviewer needn't dig):**

| For this design to be right… | Status |
|---|---|
| Meeting items are asks → the existing ask registry is the right home | **TRUE** — the registry's whole purpose is "record the operator's ask verbatim"; note items are asks with an empty `origin_session`, labelled by `emitter`. |
| Status can stay 100% DERIVED (no new emit path) | **TRUE for progress** — the cockpit already derives commits/merges/heartbeats. **NEW** is only the *input* (asks from notes), which is a write to the registry, not a new status-emit. |
| orchestrator-prime can build continuously | **PARTLY FALSE** — continuous *while alive* (subagents), NOT autonomous across its own death (no unattended spawn; broken scheduled cold-start). This is the premise the whole "24/7" framing rests on, and it is the one that does not fully hold. §7. |
| Two machines won't corrupt shared state | **TRUE by construction** — no shared mutable blob; per-host partition + append-only fold + claim-gated queue. |
| The connector exists | **FALSE today** — greenfield; D1 is unanswered. |

**Staleness contracts (worst-case per source — the reviewer demands numbers, not "the auditor fixes it"):**
- **Local derivation (own machine):** ≤ 30s (derive-cache batch refresh). Rendered with each pane's
  `derived_at`.
- **Cross-machine peer status:** ≈ peer's coord-push throttle (600s) + this machine's pull cadence.
  Worst-case a peer's "working now" is ~10 min stale. **Contract: the Team tab timestamps every peer row
  "as of <pushed_at>" and never renders a >freshness-window peer row as live** — it degrades to "last seen
  10m ago," never a confident-but-wrong "live." (Mirrors the reconciler's `oracle_unavailable` honesty.)
- **Meeting notes:** as of the last successful pull/scan. **Contract: a failed pull renders "notes not
  ingested since <date>," never a silent stale backlog.** Absence is a named state, never `0` items implied
  as "no work."
- **Absence is never zero:** a missing heartbeat → `missing`/`crashed`, never "idle/done"; a note-sourced
  ask with no plan → "PROPOSED, no plan," never "0% — nothing to do."

**What each major choice SACRIFICES (collected):**
- *Reusing the ask registry as the intent store* sacrifices a purpose-built roadmap schema — note items
  share a table with session asks and are distinguished only by `emitter`/empty `origin_session`. Accepted:
  a second store would be a second source of truth, the exact anti-pattern.
- *Human promote gate (D2-b)* sacrifices auto-flow speed for un-vetted-build safety.
- *orchestrator-prime engine* sacrifices the literal 24/7 dream for honesty + full harness access.
- *coord-sync (10-min) staleness* sacrifices real-time for a secret-free, force-push-free, account-blind-safe
  transport a two-person team can actually operate.
- *No RBAC / localhost read-only* sacrifices access control for zero accidental complexity at two users.

---

## Pre-mortem (Klein) — six months on, the ways this fails

1. **The orchestrator quietly died and everyone believed work was happening.** It hit the weekly limit on a
   Thursday, stood down, surfaced a chip nobody clicked; the status page kept showing last-known heartbeats
   as "live" because a crashed session's last heartbeat looked recent. → **Prevention now:** heartbeat
   staleness is computed on READ (already true); the Team tab MUST render `crashed`/`stale` distinctly and
   MUST show an "orchestrator last cycle: <ts>" health row, so a dead loop is loud, not silent.
2. **Extraction drifted the roadmap.** The LLM extractor re-phrased the same standup item three ways across
   three daily runs; the backlog filled with near-duplicate PROPOSED rows; the team stopped trusting it. →
   **Prevention now:** idempotency by `source_ref` (note path + line) is a P1 requirement, not a P3 polish;
   re-extraction updates the existing ask, never appends a new one.
3. **An unattended merge shipped a broken Circuit build to real users.** → **Prevention now:** D4 =
   review-before-deploy for customer-facing surfaces + the "never merge onto a red master" hard exclusion;
   this is why D4 is an operator decision, not a default.
4. **Both machines built the same roadmap item.** claim freshness (2h) lapsed while a builder ran long; the
   peer took the branch. → **Prevention now:** the claim is refreshed each Stop (existing), and the queue is
   claim-gated; a long build must re-claim. Watch this in P3 — long builds vs 2h claim freshness is the
   sharp edge.
5. **The connector's OAuth token expired at 3am (if D1-a was chosen).** Notes silently stopped ingesting. →
   **Prevention now:** D1-b (local folder) has no token to expire; if D1-a is chosen anyway, the "notes not
   ingested since" contract makes the outage loud within a day.

## Steelman of the alternatives

- **Cheapest viable / do-nothing on C:** *don't build the 24/7 loop at all* — deliver A+B+D (notes →
  backlog → visible status → coordinated manual building) and let humans keep launching builders. This is a
  genuinely strong option: it removes the one premise that doesn't hold (unattended spawn), ships the
  outcomes that ARE reachable, and avoids budget-burn risk entirely. **Crossover:** the 24/7 loop wins only
  if the in-session-subagent throughput (while alive) meaningfully exceeds what two humans launching
  sessions achieve, AND D3 budget governance actually holds. If either fails, A+B+D alone is the better
  product. I recommend building A+B+D first (P1) precisely so this stays a live option.
- **Steelman the full design:** capturing intent losslessly + deriving status + a self-pacing budgeted
  builder is a real force-multiplier for a two-person team, and every piece except the connector already
  exists — the marginal build is small and mostly integration, which is why it's worth doing even though the
  literal dream is capped.

## What would change this design

- **An unattended new-session-spawn primitive** (or a fix to the scheduled-task Skill registry so
  orchestrator-prime cold-starts headless) would move the §7 wall and make true 24/7 autonomy real — the
  design is deliberately staged so P1/P2 don't depend on it and can adopt it later without rework.
- **If cross-machine is dropped** as a requirement, cockpit-v2 reverts to the in-memory cache and the Team
  tab's peer-merge simplifies — but the single-machine status + notes pipeline is unaffected.
- **A measurement that in-session-subagent building burns less budget than feared** would strengthen the
  case for C over the do-nothing steelman; the opposite would kill it. That measurement should gate P2.

---

## §7 — THE ONE THING (if you fix nothing else, fix the framing of this)

**"Claude runs 24/7 building autonomously" is not mechanically available today, and the design must be
honest that what ships is "continuous while the orchestrator session is alive; human-relaunch across its
death."** The blocker is a verified platform limit, not a design gap: `spawn_task` surfaces a chip a human
must click; scheduled/cloud agents are harness- and skill-registry-blind (PROVEN 2026-06-11); there is no
primitive for an unattended process to spin up a new full-autonomy building session. Everything else in this
sketch is reachable and mostly-built. Building the dream *as if* that primitive existed would ship a system
that looks autonomous and silently stalls — the precise failure this harness (and its architecture-reviewer)
exists to prevent. Stage it so the reachable outcomes (A+B+D, then budgeted in-session building) land first,
and adopt true autonomy the day the upstream primitive arrives.

---

## Operator decisions (2026-07-17, verbatim intent — supersede the §3 block above)

- **D1 — Meeting notes source:** Google Docs, in the operator's Pocket Tech Google account.
  (Overrides the sketch's synced-folder recommendation; the connector design must handle Google
  auth via machine-local credentials — never in the repo.)
- **D2 — Approval gate:** YES — extract → PROPOSED → human promote makes it buildable.
- **D3 — Spend posture: NO ceiling.** Verbatim: "I wanted to maximize productivity across every
  period of time and manage restarting yourself when you hit 5-hour limits or weekly limits or
  API errors." The continuous builder is NOT budget-capped; it must be LIMIT-AWARE and
  SELF-RESUMING: detect 5-hour window limits, weekly limits, and API errors; park state cleanly;
  and restart/resume when capacity returns. This is a first-class design requirement, not an
  afterthought.
- **D4 — Unattended merge/deploy:** "Anything I tell you to build includes permission to merge
  and deploy it. There are no reviews required." Standing authorization: operator-requested work
  auto-merges and auto-deploys with no human review gate. (The harness's own mechanical gates —
  self-tests, CI, evidence bar — remain, as internal quality controls, not approval gates.)
- **Model tiering (re-established):** design-tier work (design sketches, architecture review,
  plan formation for hard problems) runs on FABLE now that access is restored; the
  architecture-reviewer agent is pinned model: fable by the operator.
