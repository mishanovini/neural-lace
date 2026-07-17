# Circuit continuous-building system — design sketch v2

Status: DESIGN v2 (2026-07-17). Rewrites v1 in place, integrating the operator's four verbatim
decisions (recorded at the bottom of this file, each now marked INTEGRATED) as **settled inputs,
not open questions**. Written to survive `architecture-reviewer`
(`adapters/claude-code/agents/architecture-reviewer.md`): named forces, one explicit invariant, an
honest what-each-choice-SACRIFICES pass, per-stage staleness contracts, and **zero false mechanism
claims** — every "exists" below was re-verified on this machine on 2026-07-17 (scheduled-task
states via `Get-ScheduledTask`, `claude --version`, armed-marker/digest-feed file probes), and
where a primitive does not exist I say so and name the gap.

**What changed v1 → v2 (headline).** v1's §7 wall — "no unattended relaunch primitive exists;
human-relaunch across orchestrator death" — was **half right and importantly wrong**. It is true
INSIDE the platform (no in-app unattended-spawn primitive; that finding stands). It is false at the
OS level: this machine already carries a **built, reviewed, shadow-defaulted session-death watchdog**
(`adapters/claude-code/scripts/session-resumer.sh`, ADR-061 Phase 1a, 3,240 lines, self-tested, its
scheduled task `NL-session-resumer` registered-but-Disabled, its digest feed live with 2,499
entries) whose exact purpose is external detection + `claude -p --resume` relaunch of dead sessions
— designed, adversarially reviewed (harness-reviewer REFORMULATE → all findings fixed), and parked
one operator gate away from armed. D3's requirement ("manage restarting yourself when you hit
5-hour limits or weekly limits or API errors") is therefore **not greenfield: it is arm + extend**.
§4 is the core of this document.

The four decomposed problems, maturity updated:

| Problem | What it actually is | Maturity in THIS harness today |
|---|---|---|
| A — meeting intent evaporates | a Google Docs connector + extraction problem | **greenfield** (no connector exists; D1 settles the source) |
| B — nobody can see status | a read-only derived-view problem | **~80% built** (cockpit + deferred Team tab) |
| C — building needs babysitting | an autonomy + continuity problem | **~70% built** — orchestrator-prime (alive-phase) + ADR-061 watchdog (death-phase, shadow, unarmed). The gap is arming + one orchestrator-relaunch branch, not new invention |
| D — two builders collide | a cross-machine coordination problem | **~90% built** (claims + coord-sync + ownership gate) |

---

## §0 — The four settled inputs and what each changes

These were the §3 decision block in v1; the operator answered all four on 2026-07-17 (verbatim at
the bottom). They are design INPUTS now. One narrow confirmation remains open (D1's folder/naming
convention, §2.4) — everything else in this sketch is decided and proceeds.

| # | Settled input | What it changes in the design |
|---|---|---|
| D1 | Meeting notes live in **Google Docs, in the operator's Pocket Tech Google account** | v1's synced-folder recommendation is overridden. §2 designs the real connector: Drive/Docs API, service-account-first auth, credentials machine-local under `~/.claude/local/` (NEVER the repo — it has a public mirror), incremental polling (no public webhook endpoint exists here), folder-convention recognition |
| D2 | Approval gate confirmed: **extract → PROPOSED → human promote → buildable** | Unchanged from v1's recommendation; now settled. §1-③. The promote is the ONLY human gate left in the whole pipeline (see D4) |
| D3 | **NO spend ceiling.** "Maximize productivity across every period of time and manage restarting yourself when you hit 5-hour limits or weekly limits or API errors" | v1's budget-governance section (daily cap + stand-down %) is DELETED. Replaced by §4: limit-aware, self-resuming continuous operation — detection matrix, parking contract, next-eligible-at computation, external relaunch, duplicate suppression. Model tiering SURVIVES — not as a spend cap but as a productivity-per-token lever (more work per window) |
| D4 | **Standing authorization:** operator-requested work auto-merges and auto-deploys, no human reviews | v1's D4-(b) (queue customer-facing merges) is overridden. §5: the promote event doubles as the merge/deploy authorization token; Circuit's `automation-mode.json` flips to full-auto; the harness's MECHANICAL gates (self-tests, CI, evidence bar, reviewer agents, never-merge-onto-red-master) remain as internal quality controls, not approval gates |

---

## Phase-0 — independent derivation (problem · forces · invariant · candidate · sacrifice)

Re-derived for v2, because D3 changes the force ranking.

**The real problem (not the proxy).** Team intent has no durable, provenance-traced path from the
meeting where it is spoken to the build queue; the building stalls whenever a human stops poking a
session; and capacity arrives in WINDOWS (5-hour rolling, weekly) that no session can see past its
own death. "Run 24/7" decomposes into: capture intent losslessly (A), make state visible (B),
keep the engine running while capacity exists (C-alive), and **bridge the engine across capacity
gaps and deaths** (C-dead — the part D3 makes first-class).

**Forces, re-ranked for v2:**
- **Capacity is windowed, not priced.** With D3 there is no spend ceiling; the binding constraint
  becomes the shape of the windows themselves (5-hour rolling, weekly, API incidents). The design
  goal flips from "don't overspend" to "never leave a window's capacity unused, and never burn
  capacity on busy-retries against a closed window."
- **Machine safety is non-negotiable.** The one prior attempt at unattended relaunch contributed to
  a machine crash (FM-037 / NL-FINDING-040, 2026-07-08 spawn cascade). Every relaunch path must
  inherit the hardened guard stack (storm cap, spawn breaker, cooldown, one-spawn-per-tick,
  tombstones) — a design that re-earns that incident is worse than no design.
- **Consistency across two machines / ~59 worktrees.** No shared mutable blob, ever (v1's analysis
  stands; §3).
- **Durability of intent.** A meeting item must survive a failed pull, a crash, a reboot.
- **Operability.** A dead loop must be loud. Absence is a named state, never zero.
- **Two-person, part-time maintainers.** Complexity they cannot debug at 11pm is a liability.

**The invariant (one sentence, unchanged).** *Every row on the status page traces to a real,
provenance-stamped operator/meeting intent, and every state it shows is DERIVED from ground truth —
git, session heartbeats, the append-only ask registry, merged SHAs — never self-reported by a
builder, and never rendered as more complete than what is merged to Circuit's master.*

**Candidate design, in four lines.** (1) A scheduled, claude-free **notes-pull** fetches Google
Docs from one agreed Drive folder into a durable local queue; extraction (Sonnet, in-orchestrator)
writes items into the **existing ask registry** with `verbatim_ref`, then the **existing backlog**
as `PROPOSED`; a human promote makes them `SCHEDULED` **and** stamps D4's merge/deploy
authorization. (2) Status = the **existing cockpit** with the reserved Team tab un-hidden, all
DERIVED. (3) The engine = **orchestrator-prime as it exists** (self-pacing while alive). (4) The
bridge across deaths = the **ADR-061 watchdog, armed** (per its own Phase-2 operator-gated
checklist) plus one NEW branch: relaunch the orchestrator itself when it is dead, capacity is
believed available, and the derived queue is non-empty.

**What the candidate sacrifices.** It accepts the watchdog's deliberate slowness (10-minute ticks,
30-minute throttle floor, one spawn per tick) — resume latency is minutes-to-hours, not seconds, in
exchange for cascade-proof spawning. It accepts that weekly-limit detection is heuristic (no
structured signal exists — §4.3) and over-parks rather than busy-retries when ambiguous. It keeps
the evidence bar intact even though D4 removes human review, so meeting-to-merged is still gated by
real (mechanical) review time.

---

## 1. The pipeline, end to end

Notation per stage: **Trigger** (push preferred over poll) · **Mechanism** (REUSED unless marked
NEW) · **Human decision** · **Sacrifice**.

```
Google Docs folder ──①pull(NEW,claude-free)──▶ local notes queue (durable, gitignored state)
        │
        ②extract(NEW, Sonnet, in-orchestrator)
        ▼
 ask registry (verbatim_ref, emitter:"notes-extractor") ──▶ backlog PROPOSED rows
        │
        ③ HUMAN PROMOTE (D2) — the ONLY human gate; promote ALSO stamps D4 authorization
        ▼
 backlog SCHEDULED / build-ready
        │
        ④ plan formation UNDER THE EVIDENCE BAR (mechanical gates, no human review — D4)
        ▼
        ⑤ continuous builder consumes the derived queue   ◀──┐
        │                                                    │ ⑦ ADR-061 watchdog: detect death /
        ⑥ AUTO-MERGE + AUTO-DEPLOY (D4; hard exclusions)     │   limit-park / relaunch (§4)
        ▼                                                    │
 merged SHA + green deploy ──▶ ⑧ progress DERIVED to the status page (no new emit path)
```

**① Pull (NEW, claude-free).** *Trigger:* a scheduled task (`NL-notes-pull`, default hourly —
cheap: an incremental `changes.list` poll is one HTTPS call when nothing changed). *Mechanism:*
§2.3. Writes raw exported Markdown + metadata into `~/.claude/state/notes-queue/<docId>/` —
durable, idempotent, no model tokens. *Human decision:* none. *Sacrifice:* polling, not push —
Drive push notifications require a public HTTPS webhook this machine cannot host (unchanged v1
finding). Worst-case ingest latency = one poll interval.

**② Extract (NEW, Sonnet).** *Trigger:* orchestrator-prime's per-cycle sweep finds unprocessed
queue entries (or any interactive session runs the same skill on demand). *Mechanism:* one Sonnet
subagent per new/changed doc revision — mechanical breadth, never Fable
(`feedback-fable-only-when-real-value`). Emits per item: `{class: action|roadmap|improvement,
text, owner, source_ref}` where `source_ref = docId + revisionId + heading/paragraph anchor`.
*Human decision:* none — extraction is lossless capture, not judgment. *Sacrifice:* extraction
needs a live model, so ingest-to-PROPOSED waits for the next orchestrator cycle (or the watchdog
relaunching one — §4.5). The queue is durable, so nothing is lost while waiting; latency is the
cost. Idempotency is by `source_ref`: re-extraction of the same anchor UPDATES the existing ask,
never appends a duplicate (pre-mortem #2).

**③ Register + Promote (D2 — the one human gate).** *Mechanism (REUSE):* `ask-registry.sh register
--text <item> --verbatim-ref <docId#anchor> --project circuit` appends one `created` record to the
append-only registry (`~/.claude/state/ask-registry.jsonl` + in-repo mirror
`docs/asks/ask-registry.jsonl`), with `emitter:"notes-extractor"` and empty `origin_session` so
provenance renders honestly ("from the 07-17 standup", never pretending a session authored it).
The item lands as a backlog row in state `PROPOSED`; a human promotes to `SCHEDULED` using the
existing triage vocabulary (`SCHEDULE`/`DEMOTE`/`FOLD`/`WONTFIX`, `docs/backlog.md`). **v2 change
(D4 composition):** the promote event IS the standing authorization — a promoted item carries
"operator-requested" status, which is exactly the class D4 authorizes to auto-merge and
auto-deploy. One click = roadmap approval + deploy authorization. Unpromoted items sit in
`PROPOSED` forever (a parking lot, not a leak — the backlog digest surfaces age-crossed rows).
*Sacrifice:* nothing auto-flows to build; intent nobody promotes is never built — which is D2's
point.

**④ Plan formation under the evidence bar.** *Mechanism (REUSE, unchanged from v1):* plans in
`docs/plans/` back-linked to the ask (`start-plan.sh --ask-id` → `ask-registry.sh link-plan`);
gated by `architecture-reviewer` / `systems-designer` / `end-user-advocate` / comprehension gates /
`task-verifier`. **v2 note (D4):** these gates are MECHANICAL quality controls and they stay. What
D4 removes is any human sitting between a green pipeline and production. A NEEDS-RESHAPING verdict
still stops the line — that is the gate doing its job, and fixing the design is the builder's work,
not a human approval.

**⑤ Continuous builder.** *Mechanism:* orchestrator-prime as it exists (ADR 050;
`~/.claude/skills/orchestrator-prime/SKILL.md`): self-pacing via ScheduleWakeup, builders as
in-session subagents, coord-pull/push per cycle, claims respected. §4 adds the death-bridge.
*Sacrifice:* in-session subagents share the orchestrator's context and its account's capacity
windows — a correlated exhaustion (§4.6) pauses everything at once. Accepted: the watchdog is
API-free bash, so it survives precisely that event and schedules the mass resume.

**⑥ Auto-merge + auto-deploy (D4).** §5.

**⑦ The watchdog.** §4.

**⑧ Progress flows back.** *Mechanism (REUSE, unchanged):* the status page is READ-ONLY and
derives from ground truth the existing `nl` derivation lib already observes. **No new emission
path** — adding one would be the maintain-don't-derive anti-pattern the cockpit was rebuilt to kill
(`neural-lace/workstreams-ui/README.md`, NL-FINDING-024). *Sacrifice:* freshness = derivation
cache (≤30s local) + coord-sync staleness cross-machine (§7); every pane timestamps itself.

---

## 2. D1 — the Google Docs connector, designed for real

Settled: notes live in Google Docs under the operator's **Pocket Tech Google account**. The harness
has NO Google connector today (verified: nothing under `adapters/claude-code/scripts/` reads
Drive). Everything in this section is NEW build.

### 2.1 Access model — service account vs OAuth

| | (a) Service account + shared folder — **RECOMMENDED** | (b) OAuth (operator's own account) |
|---|---|---|
| How it works | Create a GCP project under the Pocket Tech account → create a service account (SA) → the operator shares ONE Drive folder with the SA's e-mail address → SA reads that folder (and nothing else) via Drive API | OAuth client + one-time browser consent by the operator → refresh token stored locally → API calls as the operator |
| Blast radius | **Folder-scoped by construction** — the SA sees only what is explicitly shared with it | The token can read whatever scope was granted; `drive.readonly` = the operator's ENTIRE Drive (over-broad); narrower `drive.file` only sees files the app created — useless for reading human-written notes |
| Credential lifetime | SA key is long-lived (no refresh dance, no browser). Cost: it is a real secret requiring rotation discipline | Refresh tokens on an unverified/"Testing"-status OAuth app **expire every 7 days** — a silent 3am-class outage generator; avoiding that requires publishing the app, and `drive.readonly` is a restricted scope with a verification process — heavy machinery for reading one folder |
| Unattended fit | Perfect — no human in any loop | The consent + token-refresh path is exactly what breaks unattended |
| Named risk | If the Pocket Tech account is a Workspace domain whose admin policy blocks sharing to external e-mails, the SA (external to the domain) cannot be granted access → fall back to (b) with eyes open, or an admin policy exception. This is checked in the P1 bootstrap task before anything else is built | — |

**Decision (mine — reversible, technical):** service-account-first; OAuth only as the named
fallback if Workspace sharing policy blocks the SA. Rationale: least privilege (one folder), zero
recurring human involvement, no refresh-token expiry class. This mirrors the harness's
"connector auth breaks at 3am" test: an SA key does not expire on a schedule; a Testing-status
OAuth token does.

### 2.2 Where credentials live — and where they NEVER go

Per `~/.claude/local/credentials-reference.md` conventions (no central vault; machine-local
non-repo files under `~/.claude/local/` — the same directory that holds `resumer-armed.txt`):

```
~/.claude/local/google/pocket-tech-notes-sa.json   # the SA key (chmod 600; NEVER the repo)
~/.claude/local/google/notes-connector.json        # config: folder_id, page_token bootstrap,
                                                   # account label ("pocket-tech"), poll cadence
```

**Hard law:** the neural-lace repo has a **public personal mirror by design**
(memory: `project_nl_personal_mirror_public_by_design`). No key, no folder ID with the key, no
token EVER enters the repo — the hygiene denylist + CI backstop are the publication gate, and this
connector must add its filename patterns to that denylist as part of P1 (defense in depth, not the
primary control; the primary control is the file simply living outside the repo).
`credentials-reference.md` gains one row documenting the SA convention (via `grant-local-edit`).

### 2.3 Pull mechanics — incremental poll, no webhook, claude-free

- **Enumeration:** Drive API `files.list` scoped to the agreed folder (`'<folderId>' in parents`,
  `mimeType='application/vnd.google-apps.document'`) for the initial sweep; thereafter
  **`changes.list` with a stored page token** — the incremental changes feed costs one call when
  nothing changed and returns exactly the delta when something did.
- **Fetch:** Drive `files.export` per changed doc — `text/markdown` (Drive supports Markdown
  export for Google Docs; `text/plain` is the fallback if a doc refuses), stored with
  `{docId, name, modifiedTime, revisionId (from files.get fields=headRevisionId)}` under
  `~/.claude/state/notes-queue/<docId>/` — one dir per doc, newest export + metadata JSON,
  processed-marker written by the extractor (②) when consumed. Single-writer per file (the pull
  task is the only writer of exports; the extractor only writes its own marker) — no
  read-modify-write blob.
- **Why not push:** Drive `changes.watch` push notifications require a public HTTPS endpoint;
  this harness is a local Windows machine with no hosted endpoint — same wall v1 named. Poll wins.
- **Cadence + registration:** a new `NL-notes-pull` Windows Scheduled Task, default **hourly**
  (meeting notes are a daily-granularity source; hourly is generous and near-free with
  `changes.list`), registered via the established PowerShell installer pattern
  (`adapters/claude-code/scripts/install-weekly-hygiene-task.ps1` is the precedent: idempotent
  register, `-Uninstall`, `-WhatIf`, logs under `.claude/state/`, alert files into
  `~/.claude/state/external-monitor-alerts/` on failure — consumed by the EXISTING
  `external-monitor-alert-surfacer.sh` at next SessionStart). It does NOT touch `NL-health-tick`
  (that tick has a fixed three-surface contract and a 5-minute budget; the pull gets its own task).
- **The pull never spawns `claude`.** Extraction (which needs a model) is decoupled behind the
  durable queue and runs inside the orchestrator's next cycle — so the scheduled task stays in the
  same safety class as `NL-health-tick` (passive, claude-free), entirely outside the FM-037 hazard
  perimeter.

### 2.4 How a meeting doc is recognized — THE one remaining operator confirmation

**Proposed convention (awaiting operator YES — the only open input in this design):**

> One Drive folder named **"Circuit Meeting Notes"** in the Pocket Tech account's My Drive (or
> anywhere — the connector pins the folder by ID after one-time discovery by name, so location and
> renames don't break it). **Membership in the folder IS the contract:** every Google Doc in it is
> treated as a meeting note; nothing outside it is ever read. Recommended (not enforced) doc
> naming: `YYYY-MM-DD <meeting name>` — the extractor prefers the doc's own date-in-title over
> `modifiedTime` when stamping which meeting an item came from, falling back to `createdTime`.
> Sub-folders included (year/quarter organization stays possible).

Why folder-membership over name-pattern: a name convention silently drops every note that
mis-formats the date (a workflow habit failure becomes invisible data loss); folder membership
fails loudly (the doc either is or is not in the folder, and the folder is visible to the humans
putting notes there). **Reply needed from the operator: folder name/location, or "create it
exactly as proposed."**

### 2.5 Failure + staleness contracts (connector-specific)

- **Contract:** the status page renders "notes: last successful pull `<ts>`; N docs, M unprocessed"
  from the queue's own metadata. A failed poll (SA key revoked, API error, network) writes one
  alert file into `~/.claude/state/external-monitor-alerts/` → surfaced at next SessionStart AND
  visible as a stale `last successful pull` timestamp. **"Notes not ingested since `<date>`" is a
  named, rendered state — never a silent zero-new-items.**
- **Auth breakage class:** SA key deleted/rotated server-side → every poll fails loudly (alert +
  stale timestamp) within one cadence. No 7-day silent-expiry class exists on the SA path (that
  class is why OAuth lost §2.1).
- **Quota:** Drive API free-tier quotas are orders of magnitude above one folder polled hourly —
  not a force. (Stated so the reviewer sees it was considered, not missed.)

### 2.6 Idempotency + provenance

`source_ref = docId + revisionId + anchor` (heading path or paragraph index). Re-runs over the
same revision are no-ops; a NEW revision of the same doc re-extracts and UPSERTS by
`(docId, anchor)` — the ask's text updates, its identity and history persist in the append-only
registry (last-write-wins per field, blanks never overwrite — the registry's existing fold
contract). The cockpit renders note-sourced asks with their meeting provenance ("from the 07-17
standup") via `emitter` + `verbatim_ref`. The anti-noise law holds: `notes-extractor` is a
provenance label, not a harness-internal identifier; the payload allowlist
(`workstreams-ui/server/payload-schema.js`) is extended by KEY, exactly as cockpit-v2's
`description` carve-out was (that plan's finding m1).

---

## 3. Status page — what changes vs today's cockpit (carried from v1, verbatim where unchanged)

Today's cockpit (`neural-lace/workstreams-ui/`) is a localhost READ-ONLY dashboard (Asks tab +
demoted Harness Health tab), deriving from the `nl` oracle, with the Team tab deliberately
not shipped in P1 of its own plan ("no nav entry and no markup", README Task 16) while the
payloads already carry multi-user provenance (`user`, `machine`, `origin_session`). The status
work is mostly **un-hiding and joining, not building**:

1. **Un-hide the Team tab** — two derived views:
   - **"Working on now"** per person, DERIVED from session heartbeats
     (`session-heartbeat.sh` files classified `live|stale|throttled|crashed|missing` on READ by
     `hb_classify`; carrying pid, cwd, branch, model, last marker). Joined to the ask registry by
     branch/plan. Zero self-report — liveness + git only. **v2 addition:** the same pane renders
     the WATCHDOG's state (§4.4): last `supervisor-pass` timestamp from the digest feed, sessions
     currently limit-parked with their `next_check` times — so "resting until the window resets" is
     visibly different from "dead" for a human too, not just for the watchdog.
   - **Cross-machine merge** via the existing coord-sync git ref (`coord-pull.sh`; each machine
     writes only `tree-state/<hostname>.json`) — consuming the cockpit-v2 store (P0, §6).
2. **Meeting-visible view** — large-type projection layout of the Team tab; CSS mode, no new data.
3. **Provenance labelling** — §2.6.

**Multi-user contract (unchanged from v1, kept binding):** identity = `git config user.email`
mapped through a small `config/people.js` (hostname identifies machines, not people); no RBAC/auth
for a two-person localhost tool; **single-writer rule** — no shared mutable blob exists anywhere on
the path: per-host tree-state files, append-only registry records, deterministic union +
per-field-LWW fold on read. **v2 extension of the same rule to §4's new state:** deferral records
are one-file-per-session-id written only by the watchdog; the orchestrator's `state.json` is
per-machine, written only by its own orchestrator, atomically (temp-then-rename per its SKILL). The
lost-update hazard cannot fire by construction, not by luck.

---

## 4. D3 — limit-aware, self-resuming continuous operation (the hard problem)

**Requirement (operator, verbatim):** "maximize productivity across every period of time and manage
restarting yourself when you hit 5-hour limits or weekly limits or API errors." No spend ceiling.

### 4.0 What already exists — the substrate inventory (all re-verified 2026-07-17)

| Piece | State on this machine |
|---|---|
| `session-resumer.sh` (ADR-061 Phase 1a — `docs/decisions/061-session-continuity-supervision.md`) | **BUILT** (69-assertion self-test; mutation-tested live-scale scenario). Two-stage heartbeat-first detection funnel, field-aware API-error classification, throttle-deferral ladder, backoff, storm cap, spawn breaker, cooldown, tombstones, liveness guard, shadow mode that rehearses the full ladder, auto-disarm |
| `NL-session-resumer` scheduled task | **Registered, currently DISABLED** (`Get-ScheduledTask`: State=Disabled). 10-minute cadence when enabled (runbook `docs/runbooks/session-resumer.md`) |
| Armed marker `~/.claude/local/resumer-armed.txt` | **ABSENT** — shadow is the default even when the task is enabled; the live spawn path cannot execute without this file (mechanical gate, not convention) |
| `NL-health-tick` scheduled task + `health-tick.sh` | **LIVE (State=Ready, hourly)** — passive, claude-free: doctor-cache refresh + scheduled-task health + heartbeat reap; anomalies → alert files → surfaced at next SessionStart |
| Heartbeats + `hb_classify` | LIVE — `live|stale|throttled|crashed|missing` computed on read; automation children visible since ADR-061 D2 (`-auto` events) |
| `session-snapshot.sh` | **BUILT + producing** (`~/.claude/state/session-handoff/<sid>.md` files exist on this machine) — zero-token mechanical handoff: git state, worktrees, in-flight background work, ACTIVE plan + next unchecked task, NEEDS-YOU, SCRATCHPAD copy-in when stale. Takes a transcript path — **it can be run by an outside process against a DEAD session's transcript** |
| Resume primitive | `claude -p --resume <session-id> "<nudge>"` — the watchdog's action verb; fixed never-claim-DONE nudge pointing the child at SCRATCHPAD + NEEDS-YOU + branch state; fresh-spawn fallback (`claude -p` in the session's own cwd) only on unresumable-error exits |
| Digest feed `~/.claude/state/resumer/digest-feed.jsonl` | **LIVE — 2,499 entries** (the observation channel; read by the session-start digest) |
| Concurrency guards | `broadcast-active-session.sh` claims (2h freshness) + `concurrent-ownership-gate.sh` (cross-machine); `interactive-session-lock.sh` (B.12, the don't-inject-while-a-human-is-looking guard, consumed by the resumer's liveness guardrail) |
| Task Scheduler precedents | `install-weekly-hygiene-task.ps1` / `install-daily-harness-eval-task.ps1` (idempotent, `-WhatIf`, `-Uninstall`); ADR-061's finding: **OS schtasks survive the app being closed; MCP scheduled tasks do not** — durability lives at the OS layer |
| CLI | **2.1.69 (verified today)** — ADR-061's named prerequisite (upgrade + re-verify `claude -p --resume` semantics and internal-retry behavior on the newer binary) is **still open** |

The design consequence: **D3 is delivered by arming and extending ADR-061's machinery under its own
Phase-2 checklist — not by building a second watchdog.** Building a parallel mechanism would be the
exact two-sources-of-truth defect this harness's reviewers exist to catch.

### 4.1 Detection — the interruption taxonomy × detection matrix

Two vantage points: INSIDE a live session (can act before dying: park early), and OUTSIDE (the
watchdog; the only vantage that survives the session's death — and, being API-free bash on an OS
timer, survives the API being down entirely).

| Interruption class | Inside signal (live session) | Outside signal (watchdog) | Confidence |
|---|---|---|---|
| Transient API 429/5xx | Structured retry events in-transcript (`type:"system", subtype:"api_error"` with `retryAttempt/maxRetries/retryInMs` — captured real shape, ADR-061 §2); CLI auto-retries internally | Usually invisible (self-heals). If terminal: last transcript event field-parses as API-error (`isApiErrorMessage:true`, `apiErrorStatus:429` — second captured shape) → `throttled` classification when pid alive | PROVEN (both envelope shapes captured as fixtures) |
| 5-hour window exhaustion | The session sees requests start failing; the limit surfaces as prose in the transcript (no structured usage-limit event exists — ADR-061 §2, sampled-corpus finding, falsifiable). `nl costs` (od_costs) reports per-session tokens + throttle-time-lost, derived from transcripts — trend telemetry, not a window gauge | `throttled` (pid alive + API-error tail) or `crashed/stale` with an API-error tail; **next-eligible-at computed per §4.3** | Detection PROVEN (error-shaped); window-attribution HEURISTIC |
| Weekly limit | Same as 5-hour but the reset is days away; message prose names the longer horizon | Deferral ladder exhausts (>24h still throttled) → session PARKED `awaiting-limit-reset`, checks drop to twice daily (built: `DEFERRAL_PARK_AFTER_SECONDS=86400`, `DEFERRAL_PARKED_MINUTES=720`) | HYPOTHESIZED classification (ADR-061 D4 says exactly this — no mechanical signal distinguishes weekly from long-transient; the design over-parks rather than fabricates certainty) |
| Network outage | Same api_error retry shapes; CLI internal retry | Sessions go stale in bulk; resume attempts themselves fail → per-session backoff ladder (5→15→45→120→120 min, max 5 attempts, then escalate + stop) absorbs the outage without busy-retry | PROVEN mechanics |
| Machine reboot | None (no warning) | All heartbeats+transcripts go stale at once; on next logon the 10-min task tick classifies en masse; **storm cap (2 actions/rolling-hour) + one-spawn-per-tick** meter the recovery queue oldest-first (built for exactly this reboot-burst case) | PROVEN mechanics |
| Session crash/hang mid-task | None | Heartbeat `crashed`/`stale` + in-flight-work signals (TodoWrite in_progress / `CONTINUING:` marker / ACTIVE-plan reference in last hour) → resume-eligible. `DONE:`/`PAUSING:`/`BLOCKED:` are skip-always (never resumed) | PROVEN mechanics |

**Inside-detection posture — "park early, park often" (NEW, cheap):** parking is zero-token
(§4.2), so the orchestrator does not wait for death to park. Per cycle N (every cycle, or every
2nd): run `bash session-snapshot.sh <own transcript>` and rewrite SCRATCHPAD at milestones (already
doctrine). On the FIRST structured `api_error` retry event observed in its own work, it
additionally parks immediately — if the CLI's internal retry wins, the park was a no-op overwrite;
if the window is exhausted, the parked state is already on disk when the process dies. There is no
"detect the 5-hour limit from inside with certainty" primitive — so the design makes detection
unnecessary for lossless parking.

### 4.2 The parking contract — what is durably on disk BEFORE death, so resume is lossless

Two writers, by design: the SESSION (best-effort, may die mid-write) and the WATCHDOG (mechanical,
post-mortem, cannot lose a race with death because it runs after it). Everything below exists
today except the two marked NEW.

| Artifact | Writer | When | Resume consumer |
|---|---|---|---|
| `SCRATCHPAD.md` (repo root) | session | milestone rewrites (existing doctrine: ≤30 lines, pointer not log) | the resume nudge's first instruction ("re-read SCRATCHPAD.md + NEEDS-YOU.md") |
| Plan files `docs/plans/*.md` + checkboxes | session (task-verifier flips) | per task completion | resumed child finds the first unchecked task (also in the snapshot) |
| Ask-registry + progress-log events (`ask-registry.sh`, `progress-log.sh emit` — never-block writers) | session mechanisms | at each state change, same-response persistence (constitution §5) | cockpit + resumed child re-derive "where was I" from ground truth |
| `NEEDS-YOU.md` | session | when an operator ask surfaces | nudge instruction; PAUSING/BLOCKED states are never auto-resumed |
| Session-handoff snapshot `~/.claude/state/session-handoff/<sid>.md` | session (proactive, §4.1) AND watchdog (post-mortem — NEW wiring: on classifying a session dead-with-work, run `session-snapshot.sh <transcript>` BEFORE the resume spawn; zero tokens, idempotent overwrite) | pre-compact watermark (existing), per-cycle proactive (NEW), post-mortem (NEW) | resumed/fresh-spawned child; also the fresh-spawn fallback's substrate when the original session is unresumable |
| Deferral record `~/.claude/state/resumer/deferrals/<sid>.json` — `{reason, first_seen, last_throttled, next_check, checks, parked}` | watchdog | on `throttled` classification | the watchdog's own gate — **`next_check` IS the parked next-eligible-at timestamp** (§4.3) |
| `docs/RESUME-HERE.md` | session / operator | cross-machine work routing (exists; decision 064) | a resumed child or the peer machine picking work up |
| The transcript itself `~/.claude/projects/<slug>/<sid>.jsonl` | the CLI | continuously | `claude --resume <sid>` restores the full conversation — the deepest layer of the contract, owned by the platform |

**Contract statement:** a session is RESUMABLE-LOSSLESSLY when (transcript exists) ∧ (SCRATCHPAD or
snapshot ≤ one milestone stale) ∧ (in-flight state is in plan/registry files, not chat-only). The
first is platform-guaranteed; the second is guaranteed by proactive parking (worst case: one
cycle's staleness); the third is constitution §5 discipline **enforced by the existing evidence/
persistence gates**, plus the mechanical snapshot as the backstop that captures repo-observable
state even when the session violated §5.

### 4.3 Computing next-eligible-at — three tiers, honestly labeled

The watchdog must distinguish "resting until the window resets" (do NOT spawn — a spawn burns a
storm-cap slot and fails) from "capacity available" (spawn). Three tiers, best available wins:

- **Tier 1 — parse the reset time from the limit message (HYPOTHESIZED until fixtured).** When the
  platform refuses for usage-limit reasons, the refusal text names when the limit resets. But ADR-061's
  corpus sweep found **no structured usage-limit event and no captured fixture of the prose shape**
  — so this tier ships as *capture-first instrumentation*: on any terminal API-error tail that is
  NOT one of the two known 429/5xx shapes, the watchdog copies the last transcript lines into
  `~/.claude/state/resumer/limit-shape-captures/` and emits one digest line. The first real 5-hour
  and weekly hits after go-live hand us the fixtures; the parser is then built against REAL shapes
  and promoted to Tier 1. Building a prose parser against guessed text would be theater.
- **Tier 2 — derive the 5-hour window from the transcript corpus (HEURISTIC, buildable now).** The
  5-hour window is anchored to first activity: scan the estate's transcript mtimes/timestamps
  (the watchdog already enumerates them in stage 1), find the current activity block's start
  (first event after the last ≥5h-wide gap in account-wide activity), and park
  `next_eligible_at = block_start + 5h`. This is the same derivation the ecosystem's usage tools
  use; it is an approximation of an unpublished server-side rule, and is labeled so.
- **Tier 3 — the deferral ladder (BUILT, the floor).** When neither tier yields a timestamp:
  re-check at 30min → 60min → 2h → then every 5h (`DEFERRAL_MINUTES=(30 60 120 300)`), park after
  24h with twice-daily checks. Convergence guarantee: a 5-hour reset is rediscovered at most ~2h
  late by ladder alone; with Tier 2 typically <10min late. The 30-minute throttle floor
  (`RESUMER_THROTTLE_FLOOR_MIN`) everywhere prevents racing the CLI's internal retry.

"Probe" design: no separate ping burner. The resume attempt at `next_eligible_at` IS the probe —
if the limit persists, the child dies with the same error shape, the deferral record updates, the
ladder widens. Cost per false probe: one bounded spawn, metered by storm cap + spawn breaker.

### 4.4 The resume trigger — the external watchdog, armed

Sessions cannot restart themselves after death (platform fact, unchanged from v1). The external
mechanism, concretely:

- **The timer:** `NL-session-resumer` (exists, Disabled) — 10-minute cadence, Git-Bash invocation,
  two-file wrapper pattern under `%USERPROFILE%\.claude\state\task-wrappers\` (runbook
  `docs/runbooks/session-resumer.md`). OS schtasks chosen over MCP scheduled tasks because only the
  former survives the app being closed (ADR-061 §2).
- **Resting vs crashed:** a session with a live deferral record whose `next_check` is in the future
  is RESTING — classified, logged, never spawned. `stale/crashed` + in-flight-work + no future
  `next_check` is RESUMABLE. `DONE:/PAUSING:/BLOCKED:` are natural ends — never touched. The Team
  tab renders both states distinctly (§3), so humans see "resting until 14:05" not a scary silence.
- **Duplicate suppression (the FM-037 lesson, five layers, all built):** per-session cooldown
  (15min) so the next tick never re-resumes the child it just spawned; per-session backoff ladder
  with a 5-attempt escalate-and-stop; storm cap (2 actions/rolling hour) for reboot bursts; the
  hard spawn breaker (max 3 spawns/hour machine-wide + live-process ceiling 8, script-shape-aware);
  one-spawn-per-tick. Plus tombstones (`--never <sid>`) for deliberate ends, and the interactive-
  session-lock liveness guard so a resume nudge is never injected into a repo a human is actively
  working in.
- **Auto-disarm:** if the watchdog's OWN spawn-window log exceeds its ceiling, it renames its armed
  marker and drops to shadow, loudly (built — supervisor-attributable signal only; ambient machine
  load defers, never disarms).
- **Arming is the operator gate (ADR-061 Phase 2, unchanged and inherited here):** (i) ≥5 days of
  shadow metrics green (zero false `would-have-resumed` on sessions later shown alive), (ii) live
  process-probe verification, (iii) a kill-drill (kill a real session, watch ONE supervised resume,
  verify cooldown blocks a second), (iv) the operator creates `~/.claude/local/resumer-armed.txt`.
  Rollback = delete one file + `schtasks /Change /TN NL-session-resumer /DISABLE`. **This design
  does not weaken, re-litigate, or route around that checklist — it is the named activation step of
  P1, and the one PAUSING-class moment in the whole program** (arming a spawner with a crash
  history is the irreversibility-adjacent step; everything else is one revert).
- **Prerequisite (open):** CLI upgrade from 2.1.69 + re-verify `--resume` semantics and internal
  retry behavior on the new binary (ADR-061 names this; still unmet as of today).

### 4.5 Relaunching the ENGINE — the orchestrator branch (NEW, the one genuinely new mechanism)

The resumer resumes SESSIONS that died mid-work. D3 additionally needs the ENGINE (orchestrator-
prime) relaunched so extraction, planning, spawning, merging resume — otherwise resumed builders
finish their task and the pipeline still stalls. One new watchdog branch, `engine-check`, appended
to the per-pass funnel:

1. **Is an orchestrator alive?** Probe the orchestrator singleton lock (below) + its session
   heartbeat freshness. Alive → done (zero cost).
2. **Is relaunch warranted?** Require ALL: derived queue non-empty (≥1 `SCHEDULED` backlog row or
   unprocessed notes-queue entry — a cheap file/grep probe, consistent with derive-don't-maintain)
   ∧ no account-wide limit-park in force (no deferral record with future `next_check` attributed to
   the orchestrator's own session, and Tier-2 says inside-window) ∧ all spawn guards have room.
3. **Relaunch:** prefer `claude -p --resume <last-orchestrator-sid>` (context restored — it
   re-hydrates per its own SKILL startup: state.json, manifest, coord-pull, list_sessions
   reconcile); fresh `claude -p` cold-start with the orchestrator-prime skill prompt only on
   unresumable-error fallback, mirroring the resumer's existing fallback contract. The spawn counts
   against every existing guard (no privileged path).
4. **Singleton lock (NEW — must be built, does not exist):** ADR-061 explicitly listed the
   cockpit's missing single-instance lock as a known incident engine; the orchestrator gets one
   BEFORE any auto-relaunch is armed: `~/.claude/state/orchestrator-prime/instance.lock`
   `{sid, pid, hostname, acquired_at}`, atomically created (temp-then-rename), refreshed each
   cycle, considered stale after 2× cycle interval (freshness-based, like claims — never trust a
   lock file older than its lease). The orchestrator acquires it at startup and refuses to run as a
   second instance; the watchdog's engine-check treats a fresh lock as "alive" (step 1). Two
   machines each run their own orchestrator (per-machine state; cross-machine dedup is the CLAIMS
   layer, not this lock — the lock is per-machine singleton, the claim is per-branch/plan
   ownership).

**Cadence economics:** engine-check adds ~zero cost per pass (one lock stat + one grep-class queue
probe) and at most one spawn per tick shared with the session-resume budget — the watchdog's
existing one-spawn-per-tick ceiling covers both (engine relaunch and session resume compete for the
same slot; oldest-work-first, engine wins ties because it unblocks the most downstream work).

### 4.6 Throughput posture under D3 — no ceiling, windows managed

v1's budget-governance (daily cap, 20% stand-down) is DELETED per D3. What replaces it:

- **Maximize-per-window:** while capacity exists, the orchestrator keeps the queue moving —
  ScheduleWakeup tightens toward its floor when the queue is non-empty (existing behavior), and no
  self-imposed token ceiling ever idles it.
- **Model tiering SURVIVES as a throughput lever, not a cost cap** (memory:
  `feedback-fable-only-when-real-value`): Fable exclusively for design/architecture/hard planning;
  Sonnet/Haiku for extraction, triage, mechanical breadth. Under a fixed 5-hour/weekly capacity
  window, tiering is what converts the SAME window into MORE shipped work — it is how "maximize
  productivity across every period of time" is actually achieved, and it stays even with no budget
  ceiling.
- **Never busy-retry a closed window:** all retry behavior is the deferral ladder + backoff —
  burning requests against an exhausted window is throughput-negative (it spends storm-cap slots
  and delays the honest reset estimate).
- **Correlated exhaustion is THE expected event, and the design centers it:** orchestrator +
  in-session builders share one account's window; when it exhausts, everything pauses at once.
  The watchdog is API-free bash on an OS timer — it survives, parks everyone (mechanical snapshots,
  deferral records with next-eligible-at), renders "resting until <ts>" on the Team tab, and
  executes the mass resume oldest-first under the storm cap when the window reopens. **The window
  gap becomes scheduled rest, not silent death.**

### 4.7 Honesty — what D3's design makes possible, and the residual gaps

**Becomes mechanically possible (once P1 lands + Phase-2 arming is granted):** a session dies at
2am on the weekly limit → its state is already parked (proactive snapshot + SCRATCHPAD + plan
files) → the watchdog classifies `throttled`, writes a deferral record, parks `awaiting-limit-reset`
after ladder exhaustion, shows "resting" on the cockpit → when the window reopens, the scheduled
task's next tick resumes the orchestrator via `claude -p --resume`, it re-hydrates, coord-pulls,
and continues the queue — **zero human involvement across the death**. That closes v1's §7 wall at
the OS level. v1's in-platform finding stands unmodified (no in-app unattended-spawn primitive;
`spawn_task` still needs a human click; cloud/scheduled agents are still harness-blind per Decision
011) — the wall was routed around, not removed.

**Residual gaps, named precisely:**

1. **Headless permission prompts.** A resumed `claude -p` child inherits the harness's permission
   configuration; any tool call outside the pre-approved surface stalls or fails in headless mode —
   an unattended session cannot answer an interactive prompt. Required for unattended runs: a
   curated automation permission profile (project `settings.json`/`settings.local.json` allowlists
   covering the builder tool surface; the same surface interactive sessions already exercise), and
   an explicit decision on `--dangerously-skip-permissions` — which constitution §7 treats as a
   bypass flag needing operator say-so; the DESIGN default is the curated allowlist, NOT the bypass
   flag. Watchdog mitigation: a child that stalls at a prompt goes heartbeat-stale with in-flight
   work and gets classified — but it would be re-resumed into the same wall, so the P1 task list
   includes the allowlist audit BEFORE arming. This is the gap most likely to bite first.
2. **`claude` CLI auth expiry.** The CLI's own credential (`~/.claude.json`, per
   `credentials-reference.md`) can expire; every headless spawn then fails at auth
   (`authentication_failed` is a known error value). No unattended re-login exists (and building
   one would handle credentials — prohibited). Mitigation: the failure is loud (resume attempts
   fail → escalation after 5 attempts → digest + NEEDS-YOU line + alert file); a human runs
   `claude login`. Accepted as a human-gated residual.
3. **Weekly-limit shape is fixture-less.** Tier 1 of §4.3 cannot be built until a real limit
   message is captured (capture-first instrumentation is the P1 answer). Until then weekly hits
   ride Tier 3 (ladder → park), costing up to ~24h of over-parking beyond the actual reset in the
   worst case. Honest cost, bounded, temporary.
4. **CLI 2.1.69.** The upgrade + `--resume`-semantics re-verification (ADR-061 prerequisite) is
   unmet. Arming before it is done would be running the relauncher on a binary whose resume/retry
   behavior differs from the docs the design was checked against.
5. **Logon requirement.** The scheduled tasks here run in the user's logged-on context (the
   established pattern registers "run only when user logged in" — `install-weekly-hygiene-task.ps1`
   settings). After a reboot, nothing fires until the operator logs on. Closable via
   auto-logon/`/RU`-credentialed task configuration — an OS-policy decision deliberately left to
   the operator (it trades lock-screen security for unattended reboot recovery); until then,
   reboot-recovery latency = time-to-next-logon.
6. **The arming gate itself.** Phase-2 arming is operator-gated BY DESIGN (FM-037 history). Until
   armed, everything runs in shadow: full rehearsal, real deferral records, zero spawns. The system
   is honest about being in rehearsal — the cockpit's watchdog row shows shadow vs armed.

---

## 5. D4 — standing authorization: the human-free merge/deploy path

**Settled input (verbatim):** "Anything I tell you to build includes permission to merge and deploy
it. There are no reviews required." The memory `feedback_full_auto_merge_authorization` (operator
2026-07-07: merge PRs yourself, squash, never ask again) already established the merge half
machine-wide; D4 extends it through deploy for Circuit and removes v1's queue-for-human option.

**The scope boundary (the design's load-bearing line):** the authorization attaches to
**operator-requested work** — and in this pipeline, "operator-requested" has a mechanical
definition: **a backlog item a human PROMOTED (D2), or a directive the operator gave a session
directly.** The promote event is the authorization token; it is recorded on the ask (promoted-by,
promoted-at — the registry's append-only records carry it). Extracted-but-unpromoted items carry NO
authorization (they cannot reach build anyway); harness-self-improvement work continues under its
existing policies unchanged. This composition is why D2 survives as the single human gate: one
click grants both "build this" and "ship it when green."

**Pipeline mechanics:**
- **Circuit's repo policy flips to full-auto:** its `automation-mode.json` set to full-auto
  (mechanism exists: ADR 003 established the per-repo mode file + the `automation-mode` skill to
  flip it; v1's recommendation of `review-before-deploy` for customer-facing surfaces is overridden
  by D4 and this flip is the recorded, one-file-reversible expression of that override).
- **The orchestrator's merge sweep applies its existing policy:** green checks + mergeable + not
  draft + no hold label → squash-merge; **the hard exclusion stands — never merge onto a master
  without a green prod deploy** (orchestrator-prime SKILL, non-negotiable). D4 removes human
  review, not this mechanical tripwire.
- **Deploy:** the existing deploy pipeline + `deploy-preflight.sh` checks run unattended; a red
  deploy → no further merges onto that master (the exclusion above) + alert file + NEEDS-YOU line.
  Auto-deploy without auto-rollback is a named risk: mitigation is the preflight + the
  merge-freeze-on-red behavior + loud surfacing; full auto-rollback is deliberately OUT of P1
  scope (a bad rollback automation is worse than a loud red).
- **What REMAINS between code and production (internal quality controls, not approval gates):**
  plan-time reviewer agents (architecture/systems/end-user-advocate) with blocking verdicts,
  comprehension gates, task-verifier, self-tests, CI, the evidence bar, deploy preflight, the
  green-master exclusion. D4 removes HUMANS from the path; it does not remove MECHANISMS. If a
  mechanical gate blocks, the work is not done (constitution §6) — autonomy never out-waits a gate.

**Sacrifice (named for the reviewer):** an unattended merge+deploy CAN ship a regression the
mechanical gates miss to Circuit's real users with no human having looked. D4 accepts this
explicitly (operator's call, verbatim, and it is his product). The design's compensations are speed
of detection (deploy preflight, red-master freeze, loud alerts) rather than prevention-by-waiting.

---

## 6. Phasing (each phase: user-visible outcome). Still explicitly AFTER cockpit-v2.

**Sequencing constraint (unchanged):** cockpit-v2's cross-machine store
(`docs/plans/cockpit-v2-push-materialized-store.md`, DRAFT v3 post-architecture-review) is the
foundation for the Team tab's cross-machine merge and the derived queue. This sketch consumes that
design; it does not re-open it. (The reviewer's standing warning is honored: the store is justified
ONLY as a cross-machine artifact; this sketch is precisely the cross-machine consumer.)

| Phase | Smallest end-to-end slice | User-visible outcome |
|---|---|---|
| **P0 (prerequisite)** | cockpit-v2 cross-machine store lands | peer machine's plan/session state appears, current, in this cockpit |
| **P1** | **one real Google Doc meeting note → extracted PROPOSED items → promote → visible in the cockpit; PLUS the watchdog MVP: park + scheduled relaunch + resume demonstrated once.** Full task list at the end of this document | drop a note in the Drive folder → its items appear as PROPOSED rows with meeting provenance; promote one; kill a sacrificial session mid-task and watch the machine resume it with no human touch (the drill from `docs/runbooks/session-resumer.md` Step 4, run for real) |
| **P2** | **promoted → planned → built → auto-merged → auto-deployed, unattended.** Plan formation under the bar; orchestrator consumes the derived queue; D4 full-auto flip for Circuit; engine-check relaunch branch armed; Tier-2 window derivation live | a promoted roadmap item ships to production while the operator watches progress derive onto the status page — including across a 5-hour window exhaustion |
| **P3** | **cross-machine builder coordination + meeting-visible view + provenance polish + Tier-1 limit parsing** (fixtures captured by then) | two people build in parallel without collision; the standup projects one live board; parked/resting states show precise reset times |

---

## 7. Forces · invariant · premises · staleness (the reviewer's explicit bar)

**Invariant** (restated): *every status row traces to a provenance-stamped intent; every state is
DERIVED from ground truth, never self-reported, never shown more-done than merged.*

**Load-bearing premises — and which are shaky:**

| For this design to be right… | Status |
|---|---|
| Meeting items are asks → the existing ask registry is the right home | **TRUE** — unchanged from v1 |
| Status can stay 100% DERIVED (no new emit path) | **TRUE** — the only new WRITES are inputs (asks from notes; deferral records), both single-writer, both read-derived by the cockpit |
| The ADR-061 watchdog can bridge orchestrator death | **TRUE mechanically, UNARMED operationally** — built, self-tested, shadow-rehearsed; the live path is gated on Phase-2 arming + CLI upgrade. This is the premise the whole D3 promise rests on, and its remaining risk is operational (arming safely), not architectural |
| The 5-hour/weekly reset time can be computed | **PARTLY** — Tier 3 (ladder) PROVEN-built; Tier 2 heuristic buildable; Tier 1 (exact reset) fixture-less today. The design degrades gracefully across tiers |
| Headless children can actually work unattended | **OPEN until the P1 permission-profile audit** — the gap most likely to produce a stalled-not-dead child (§4.7-1) |
| The connector exists | **FALSE today** — greenfield; §2 is its design; the folder convention is the one open operator input |
| Two machines won't corrupt shared state | **TRUE by construction** — unchanged; extended to deferral records + singleton lock (§3, §4.5) |

**Staleness contracts (worst-case per source):**
- **Local derivation:** ≤30s (derive-cache), rendered with `derived_at`.
- **Cross-machine peer status:** ≈ peer's coord-push throttle (600s) + pull cadence; ~10min worst.
  Peer rows render "as of <pushed_at>", degrade to "last seen Xm ago", never confident-live.
- **Meeting notes:** ≤1 poll interval (default hourly) behind Drive; "last successful pull <ts>"
  always rendered; failed pulls alert within one cadence. Absence is a named state.
- **Watchdog state:** the digest feed's last `supervisor-pass` timestamp IS the liveness signal for
  the watchdog itself, rendered on the Team tab; a watchdog that stops ticking is visible within
  one 10-min cadence (and `NL-health-tick`'s scheduled-task health check REDs a failing task
  hourly, alert-filed at next SessionStart).
- **Limit parks:** deferral records carry `next_check`; the UI renders "resting until <ts>" from
  the record, never guesses.
- **Absence is never zero:** missing heartbeat → `missing`/`crashed`; no plan → "PROPOSED, no
  plan"; failed pull → "not ingested since", never 0-items-implied-done.

**What each major choice SACRIFICES (collected):**
- *Ask-registry as intent store:* no purpose-built roadmap schema (accepted — one source of truth).
- *Human promote (D2):* no auto-flow from meeting to build (accepted — that IS the gate).
- *SA + folder-share (D1):* a long-lived key secret with rotation discipline; blocked if Workspace
  policy forbids external sharing (fallback named).
- *Poll not push (D1):* ≤1h ingest latency (no public webhook endpoint exists here).
- *ADR-061 watchdog as the bridge (D3):* minutes-to-hours resume latency by design (safety floors);
  weekly-limit over-parking until fixtures exist.
- *D4 full-auto:* regressions the mechanical gates miss reach users without a human look
  (operator-accepted, compensated by loud fast detection).
- *No RBAC / localhost read-only:* unchanged from v1.

---

## Pre-mortem (Klein) — six months on, the ways this fails

1. **The watchdog re-ignited a spawn cascade (the FM-037 shape).** A novel failure pattern — e.g. a
   child that dies instantly at a headless permission prompt — made every resume produce another
   dead-with-work session. → **Prevention now:** the five-layer guard stack + auto-disarm are
   built; the P1 permission audit removes the known instant-death cause; the kill-drill is run
   BEFORE arming; shadow metrics (≥5 days, zero false positives) gate arming. Residual risk is
   real and is why arming stays operator-gated.
2. **Everyone believed work was happening while everything rested.** The weekly limit hit Thursday;
   parked sessions showed as quiet rows; nobody read the digest. → **Prevention now:** "resting
   until <ts>" is a first-class rendered state on the Team tab (§3); the watchdog's own last-pass
   timestamp is rendered; parking emits NEEDS-YOU lines. A dead loop and a resting loop are
   visually distinct, and both are loud.
3. **Extraction drift filled the backlog with near-duplicates.** → **Prevention now (unchanged
   v1):** idempotency by `source_ref` upsert is a P1 requirement; re-extraction updates, never
   appends.
4. **An unattended deploy shipped a broken Circuit to real users overnight.** → **Prevention now:**
   this is D4's accepted risk, compensated: deploy preflight, never-merge-onto-red-master freeze,
   alert files + NEEDS-YOU on red. Named to the operator in §5, not hidden.
5. **The SA key leaked into the public mirror.** → **Prevention now:** the key lives outside the
   repo entirely (`~/.claude/local/google/`); the hygiene denylist gains its patterns as a CI
   backstop; the connector config in-repo carries only non-secret conventions.
6. **Both machines built the same item / two orchestrators ran on one machine.** → **Prevention
   now:** claims + ownership gate (cross-machine, existing, 2h freshness — long-build re-claim
   remains the sharp edge to watch); the NEW per-machine singleton lock (§4.5-4) closes the
   same-machine duplicate the cockpit incident taught us about.
7. **The 7-day OAuth expiry class — dodged, but check the assumption.** If Workspace policy forces
   the OAuth fallback, the refresh-token expiry class returns; the "notes not ingested since"
   contract makes it loud within a day, but P1's bootstrap task must verify SA sharing works
   BEFORE building on it.

## Steelman of the alternatives

- **Cheapest viable: ship A+B+D, keep C human-launched.** Still genuinely strong: notes → backlog →
  visible status, humans launch builders when they sit down. It avoids arming a spawner with a
  crash history entirely. **Crossover (sharpened by D3):** the operator has explicitly bought the
  other side — "maximize productivity across every period of time" is precisely the capacity a
  human-launched pattern leaves on the floor (nights, the hours after a window reset at 3am, the
  weekend after a weekly reset). The do-nothing option now contradicts a settled input; it survives
  only as the fallback posture if Phase-2 arming is refused or the shadow metrics fail.
- **Alternative bridge: a cron `claude -p` cold-start loop instead of arming the resumer.** Simpler
  to reason about (no resume semantics) — but it cold-starts context every fire (re-hydration burn
  against the very windows D3 wants maximized), duplicates ADR-061's guard machinery or runs
  unguarded (FM-037 says never), and abandons the transcript-resume losslessness the parking
  contract is built on. Rejected on both throughput and safety.
- **Steelman of THIS design:** every load-bearing mechanism except the connector and the singleton
  lock already exists, reviewed and self-tested, most of it live in shadow on this machine today.
  The marginal build for the full D1–D4 vision is: one API connector, one extractor, one watchdog
  branch, one lock file, one Team tab un-hide, plus ops (upgrade, register, arm). That is a
  remarkably small distance for "meeting note in, deployed software out, across limit windows,
  with one human click in the middle."

## What would change this design

- **A platform primitive for unattended session spawn / a usage-limit API or structured
  limit event** — Tier 1 becomes exact, and chunks of §4 simplify. The design is staged so P1/P2
  adopt such primitives without rework (the watchdog's classification layer is where they'd slot).
- **Workspace policy blocking SA sharing** → OAuth fallback with its named expiry class (§2.1).
- **Shadow metrics failing** (false-positive resumes on the real estate) → arming is refused,
  D3 degrades to detect-and-surface (park + loud "needs relaunch" chip), C stays human-relaunched.
- **A measured cold-start-resume cost** far above expectation would strengthen the cron-cold-start
  alternative for the ENGINE (sessions would still use resume); measure in P1's drill.

---

## §7→ THE ONE THING (updated for v2)

**v1's wall — "no unattended relaunch primitive" — was an in-platform fact used as a
whole-system conclusion. The OS layer already holds a built, reviewed, shadow-running watchdog one
operator gate away from closing exactly that gap. So the ONE thing is no longer discovery, it is
discipline: D3 is delivered by arming ADR-061's machinery THROUGH its own Phase-2 checklist (shadow
metrics → kill-drill → armed marker), on an upgraded CLI, with the headless permission profile
audited FIRST — and by resisting every temptation to build a second, parallel, unguarded relaunch
path to get there faster.** The failure mode that kills this program is not a missing mechanism; it
is an impatient bypass of the guard stack that exists because this exact machine already crashed
once (FM-037) doing this exact thing carelessly.

---

## Operator decisions (2026-07-17, verbatim — now settled inputs)

- **D1 — Meeting notes source:** Google Docs, in the operator's Pocket Tech Google account.
  (Overrides the sketch's synced-folder recommendation; the connector design must handle Google
  auth via machine-local credentials — never in the repo.)
  **→ INTEGRATED: §2 (connector design); §1-① / ②; pre-mortem 5/7. Open sub-item: folder/naming
  convention confirmation, §2.4.**
- **D2 — Approval gate:** YES — extract → PROPOSED → human promote makes it buildable.
  **→ INTEGRATED: §1-③; composed with D4 (promote = authorization token, §5).**
- **D3 — Spend posture: NO ceiling.** Verbatim: "I wanted to maximize productivity across every
  period of time and manage restarting yourself when you hit 5-hour limits or weekly limits or
  API errors." The continuous builder is NOT budget-capped; it must be LIMIT-AWARE and
  SELF-RESUMING: detect 5-hour window limits, weekly limits, and API errors; park state cleanly;
  and restart/resume when capacity returns. This is a first-class design requirement, not an
  afterthought.
  **→ INTEGRATED: §4 in full (detection matrix 4.1, parking contract 4.2, next-eligible-at 4.3,
  watchdog 4.4, engine relaunch 4.5, throughput posture 4.6, honesty 4.7); v1's budget-cap
  section deleted; Phase-0 forces re-ranked.**
- **D4 — Unattended merge/deploy:** "Anything I tell you to build includes permission to merge
  and deploy it. There are no reviews required." Standing authorization: operator-requested work
  auto-merges and auto-deploys with no human review gate. (The harness's own mechanical gates —
  self-tests, CI, evidence bar — remain, as internal quality controls, not approval gates.)
  **→ INTEGRATED: §5 (scope boundary: promote = the authorization token; full-auto flip;
  mechanical gates retained; red-master freeze); §1-④/⑥.**
- **Model tiering (re-established):** design-tier work (design sketches, architecture review,
  plan formation for hard problems) runs on FABLE now that access is restored; the
  architecture-reviewer agent is pinned model: fable by the operator.
  **→ INTEGRATED: §4.6 (tiering as throughput lever); §1-② (extractor pinned Sonnet).**

---

## Proposed P1 plan task list — ready to become `docs/plans/circuit-continuous-building-p1.md`

The smallest end-to-end slice honoring D1 and D3: **one real Google Doc meeting note → extracted
PROPOSED items → promote → visible in the cockpit**, plus **the watchdog MVP: park + scheduled
relaunch + resume demonstrated once**. Ordered; ⊘ marks operator-touch points.

1. **Connector bootstrap (ops + runbook; ⊘ one-time).** Create the GCP project + service account
   under the Pocket Tech account; operator creates/confirms the "Circuit Meeting Notes" folder
   (§2.4) and shares it with the SA's e-mail; key lands at
   `~/.claude/local/google/pocket-tech-notes-sa.json` (0600); `notes-connector.json` pins the
   folder ID. **Verify FIRST that SA sharing works in this account** (pre-mortem 7); fall back to
   OAuth per §2.1 only if blocked. Add key-filename patterns to the hygiene denylist. One row in
   `credentials-reference.md` (via `grant-local-edit`). *Verification: a curl/script fetch of one
   doc's Markdown export, cited.*
2. **`notes-pull.sh` (NEW script + self-test).** `changes.list` incremental poll → `files.export`
   Markdown → `~/.claude/state/notes-queue/<docId>/` with metadata; alert-file on failure;
   staleness fields for the cockpit; HARNESS_SELFTEST sandbox + fixtures. *Verification: self-test
   PASS + one real pull of the operator's actual note.*
3. **`install-notes-pull-task.ps1` (NEW, from the weekly-hygiene precedent).** Registers
   `NL-notes-pull` hourly; idempotent, `-WhatIf`, `-Uninstall`; cron log under `.claude/state/`.
   *Verification: `Get-ScheduledTask` + one `Start-ScheduledTask` one-shot with a cited log line.*
4. **Extractor (NEW skill/subagent contract, Sonnet-pinned).** Queue entry → items
   `{class, text, owner, source_ref=docId+revisionId+anchor}` → `ask-registry.sh register`
   (`emitter:"notes-extractor"`) + `PROPOSED` backlog rows; idempotent upsert by `(docId, anchor)`;
   processed-markers. *Verification: run twice over the same real note — second run makes zero new
   rows (the idempotency oracle); items visible via `nl` derivation.*
5. **Promote affordance (REUSE backlog vocabulary; minimal cockpit surface).** Promote flips
   `PROPOSED → SCHEDULED` and stamps promoted-by/at on the ask (the D4 authorization token, §5).
   Note-sourced asks render in the existing Asks tab with meeting provenance (Team tab un-hide can
   ride P2 — smallest slice ships provenance in the tab that already exists). Payload allowlist
   extended by KEY. *Verification: ⊘ operator promotes one real extracted item; cockpit shows the
   state change + provenance label; `cockpit.selftest.js` extended and green.*
6. **CLI upgrade + resume re-verification (ADR-061 prerequisite; ops).** Upgrade from 2.1.69;
   re-verify `claude -p --resume` semantics + internal-retry behavior on the new binary; record
   findings in the plan evidence. *Blocking precondition for tasks 8–10.*
7. **Headless permission profile audit (NEW; the §4.7-1 gap).** Enumerate the tool surface a
   resumed builder/orchestrator child actually needs (from real transcripts); land the allowlist in
   project settings; document the explicit NON-use of `--dangerously-skip-permissions`.
   *Verification: a sacrificial `claude -p` run completes a representative file-edit+commit task
   with zero interactive prompts, cited.*
8. **Watchdog shadow re-enable (ops).** Re-enable `NL-session-resumer` in SHADOW per the runbook;
   add the §4.2 post-mortem-snapshot wiring (watchdog runs `session-snapshot.sh` on
   dead-with-work transcripts before any would-be action) + the §4.3 Tier-1 capture-first
   instrumentation (unknown limit shapes → `limit-shape-captures/` + digest line) + per-cycle
   proactive parking in the orchestrator prompt. *Verification: self-tests green; ≥5 days shadow
   with zero false `would-have-resumed` (the ADR-061 Phase-2 metric), digest lines cited.*
9. **⊘ ARMING (the one PAUSING-class gate).** Present shadow evidence; run the live kill-drill
   (runbook Step 4: sacrificial session, kill mid-turn, one supervised resume, cooldown blocks a
   second); operator creates `~/.claude/local/resumer-armed.txt`. *This step is the operator's,
   arrive with evidence prepared (constitution §8).*
10. **The demonstration (the D3 MVP oracle).** With arming live: kill a sacrificial session
    mid-task (in-flight TodoWrite + CONTINUING-shaped state); observe with zero human touches:
    park (snapshot + deferral/classification) → scheduled relaunch → resumed child continues and
    completes the task. Cite: digest-feed lines, the resumed transcript, the completed artifact.
    **This single demonstrated cycle IS P1-D3 done** (functionality over components).
11. **Close-out.** Backlog reconciliation (absorb-or-defer matching rows), completion report,
    plan archived per close-plan.

Deferred to P2 by name (so deferral is a decision, not a leak): engine-check relaunch branch + the
orchestrator singleton lock (§4.5), Circuit `automation-mode.json` full-auto flip + unattended
deploy path (§5), Team tab un-hide + resting-state rendering (§3), Tier-2 window derivation (§4.3).
