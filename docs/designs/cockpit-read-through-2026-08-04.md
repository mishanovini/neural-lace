# Design: Cockpit read-through — accuracy by construction, not by cache coherence

**Status:** r1 — awaiting review

**Author:** design-author (model: fable — running as claude-fable-5, matching this agent's pin; not inherited)

**Changelog:** r1 — initial authoring, no prior rounds.

**Supersedes:**
- The **snapshot-persistence patch in flight** (parallel worktree, subject: "snapshot persistence
  for derive-cache") — superseded in full, discard. A read path measured at ~12–25 ms warm needs no
  persisted snapshot; a snapshot is a second copy of the truth that can rot, which is D1's defect
  class re-introduced one layer up. See §3 DEC-9 and §7.
- `derive-cache.js`'s standing role as "the ONLY place server.js reads derived truth from"
  (derive-cache.js:29–31) — superseded at end state M4; the module is deleted, not extended. Law 1
  (DERIVE-DON'T-MAINTAIN) itself is **unchanged and binding**; what dies is its implementation via
  subprocess shell-outs plus an in-memory cache (see §3 DEC-4/DEC-5 for what preserves Law 1's
  intent).
- `server/derive-lib.js:71-73` `mainRepoRoot()`'s delegation to `projects.selfRepoRoot()` as the
  plan-resolution root — superseded by the canonical-root resolver (§4.2, REQ-A1).

**Inputs (all read in full unless marked otherwise):**
- Grounding sweep at worktree root `master@2afa84fc` (this worktree): `neural-lace/workstreams-ui/server/derive-lib.js` (full, 1,689 lines, two passes), `derive-cache.js` (full, 612 lines), `state-watch.js` (full, 221 lines), `config/projects.js` (full, 276 lines), `completion-oracle.js` (lines 1–100: header + class resolution — targeted read), `plan-parse.js` (lines 1–120: header/API contract — targeted read), `roadmap-routes.js` (targeted: header 1–400, buildRoadmapTree/handle 1857–2056, grep-verified sections for discoverPlanFiles/derivePlanRootNode/buildWaitingOnYouMap), `server.js` (targeted: route table via structural grep, handler section 1200–1440, pane endpoints 1560–1814 via grep, cache wiring), `inbox-routes.js` (structural grep: reader vs writer split).
- `adapters/claude-code/hooks/lib/observability-derive.sh` — structural grep only (od_* function inputs: heartbeats, signal-ledger, remote-ledgers, git log, doctor-cache, costs-cache, backlog.md). NOT read in full (3,200+ lines); every claim about it below is scoped to its input files, not its internal logic.
- `adapters/claude-code/config/operator-directives.json` (all 23 entries enumerated; OD-001/002/006/010/016 instructions read verbatim).
- Live config: `~/.claude/config/active-repos.txt`, `~/.claude/config/register-path` (both read in full — neither is a cockpit canonical-root mechanism; see §4.2).
- Dispatcher-supplied measurements, **all independently re-verified on this machine 2026-08-04** (scratchpad `measure.js`): 31 live plans / 1,056,815 bytes → 12.1 ms full read; `~/.claude/state/dispatch-ledger.jsonl` 3,076 rows → 5.4 ms full JSON parse; 266 archived plans / 5.1 MB → 68.8 ms; `~/.claude/state/signal-ledger.jsonl` 17,735,505 bytes / 63,327 rows → 101.5 ms read+split (parse extrapolates to ~220 ms full); 17 heartbeat files; direct `git.exe log --since=2026-08-01` spawn on the canonical checkout → **93 ms** (no bash, no login shell); `~/claude-projects/workstreams-ui-server/.git` is a **file** containing `gitdir: <home>/claude-projects/neural-lace/.git/worktrees/workstreams-ui-server` (the worktree-dereference mechanism, proven live).
- Operator directive verbatim (2026-08-04): "is there a way to modify the server to make it super lightweight and to always pull directly from the ledger so that there is no possibility of it ever being inaccurate?"

---

## 0. What this design is, in three sentences

Every cockpit read becomes a per-request, in-process filesystem read of the canonical copy of each
source — no subprocess on any GET path, no derived-state cache, no snapshot, no invalidation — so a
wrong or stale render is structurally impossible rather than prevented by cache-coherence
discipline. The one genuine root cause of the operator's wrong-counts defect (D1) is fixed by a
canonical-repo resolver that dereferences git-worktree `.git` pointer files, and the seconds-scale
latency (D2) is fixed by deleting the `nl <sub> --json` shell-outs in favor of in-process readers
(most of which already exist in this codebase). Sources that are inherently snapshots produced
elsewhere (doctor cache, costs cache, deploy evidence, peer ledgers) are the one place staleness
survives — and there it is always rendered with its age, never as current.

## 1. Problem statement (evidence-anchored)

**D1 — wrong-copy reads (PROVEN).** `server/derive-lib.js:71-73` `mainRepoRoot()` returns
`projects.selfRepoRoot()` — `config/projects.js:21-24` computes `path.resolve(__dirname,'..','..','..')`,
i.e. **the repo containing the running server's own files**. The operator runs the cockpit from the
worktree `~/claude-projects/workstreams-ui-server` (branch ws-ui-server-stable, 36
commits behind master at incident time). Consumer: `roadmap-routes.js:310`
(`planScanRoot()` → `deriveLib.mainRepoRoot()`), plus `server.js:296-500` (NEEDS-YOU.md,
operator-todo.md, backlog.md all resolve through the same function). Result observed twice on
2026-08-04: the cockpit rendered "11/25 tasks done" with total confidence while master's plan file
said 24/25 — **no staleness signal of any kind**. A hand-sync fixed it for hours, then it rotted
again. PROVEN mechanism for the fix: the worktree's `.git` is a plain file containing
`gitdir: <home>/claude-projects/neural-lace/.git/worktrees/workstreams-ui-server`
(re-verified 2026-08-04) — the canonical main checkout is recoverable from the worktree itself with
one `fs.readFileSync`, no git spawn.

**D2 — derive-on-read behind subprocesses (PROVEN).** `derive-cache.js` has zero disk persistence
(grep: no writeFileSync/snapshot anywhere in the module), so every cold start serves
`{data:null, rc:null}` (derive-cache.js:363-365, server.js paneResponse loading state) until the
first refresh cycle completes — and that cycle is subprocess-bound: `nl status --json` measured at
~77 s (derive-cache.js:172-175, pinned timeout 180 s), `nl backlog --json` at 80–258 s
(derive-cache.js:157-171, default timeout 360 s), login-shell bash spawns measured at 94 s and
119 s worst-case on this machine (derive-lib.js:525-529). The G2 chain validation measured
5.7–9.6 s from per-entry git-through-bash spawns (dispatcher measurement, 2026-08-04; consistent
with the per-spawn costs above). Meanwhile the actual data is small: the six panes' and the
roadmap's entire first-party input set reads in-process in tens of milliseconds (see Inputs).
**The latency is subprocess cost, not derivation cost** — PROVEN by the measurement pair (77 s
shelled vs 12 ms direct for strictly more bytes than the status pane needs).

**Corrective to the brief's framing (PROVEN, matters for scoping):** `GET /api/roadmap` is
*already* a per-request, in-process, spawn-free derivation — `roadmap-routes.js:2030-2039` calls
`buildRoadmapPayload()` synchronously per request; `buildRoadmapTree()` (1857–1923) does pure fs
reads. The A6 pin "no child-process spawn on any GET path" already exists as reviewed precedent
(completion-oracle.js:27-28, 53-55). So D1 is a **root-resolution** defect, not a caching defect,
and D2 lives in the **pane layer** (DeriveCache's six subcommands) and one GET-path straggler:
`derive-lib.js classifySessions` (485–531) spawns login-shell bash with a 180 s budget on the
ask-detail GET path. This design therefore generalizes what `/api/roadmap` already does right,
rather than inventing a new architecture.

**Where the operator's framing is wrong (two points, said plainly):**
1. *"always pull directly from the ledger"* — checkbox/task truth does not live in a ledger; it
   lives in git-resident plan files, and the server was **already** reading them directly. Directly
   from the wrong checkout. Directness alone does not produce accuracy; **canonical resolution +
   fail-loud** does. (§4.2, DEC-1, DEC-3.)
2. *"no possibility of it ever being inaccurate"* — attainable by construction for first-party
   stores (machine-global state files, canonical-checkout files); **not attainable** for
   second-party materialized inputs (doctor cache, costs cache, deploy evidence, remote peer
   ledgers) which are snapshots by nature. For those the honest contract is: always rendered with
   their age, never as current (§4.5, REQ-A7).
3. *"always pull"* is, however, **correct here** — and provably so under the estate's own OD-006
   rule: pull-on-demand is sanctioned "when changes >> reads". Measured: state writes arrive at
   ≥2 heartbeat touches per turn × 17 live-session files plus continuous ledger appends
   (63k signal-ledger rows), while cockpit reads are one operator's page loads — changes exceed
   reads by orders of magnitude. The 2026-08-02 storm OD-006 encodes was caused by *pull via
   subprocess on a clock*; per-request in-process pull at ~25 ms shares no mechanism with it.

## 2. Binding constraints

- **OD-006 (push-over-pull)** — binding on `neural-lace/workstreams-ui/**`. This design takes its
  pull-on-demand branch and must keep push as the browser-notification path (SSE), never
  reintroduce timer-driven derivation on a hot path. See §1 point 3 and DEC-2.
- **OD-002 (anti-bloat)** — every addition must name what it displaces; the end-state scorecard
  must count DOWN (it does: §"What this design gives up", D-07 ledger).
- **OD-004 (complete-instruction failures)** — every error state this design specifies carries
  WHAT/WHY/FIX, never a bare empty pane (§4.4).
- **OD-010 (disposition-everything)** — the four in-flight patch worktrees each get an explicit
  disposition (§7), never a silent collision.
- **OD-001 (no WSL)** — trivially honored: pure Node fs + one direct git.exe spawn; nothing here
  has a WSL-shaped dependency.
- **One-writer discipline** (doctrine/planning.md; ask-registry.sh/needs-you.sh headers): the
  cockpit's POST paths delegate writes to the owning shell CLI. This design does not touch any
  write path; the write-side spawns are explicitly retained (DEC-6).
- **Chesterton's fences already standing in this code, which this design must not re-burn:**
  `state-watch.js` was built to fix a real subprocess-storm incident (its header, 2026-08-02
  operator correction) — it is repurposed, not deleted (DEC-5). `plan-parse.js` exists because
  three plan grammars once disagreed (its header: "a THIRD grammar never ships") — no new plan
  grammar is introduced anywhere in this design. `derive-cache.js killTree`/lane/timeout machinery
  encodes three separate production incidents (2026-07-08/09/10, 2026-08-02/03) — all of that
  machinery becomes unnecessary *because the spawns it defends against are deleted*, which is the
  correct way to retire an incident fence: remove the hazard, not the guard alone.
- **Two-layer/live-copy rule** (CLAUDE.md "Harness source of truth"): this design targets the
  repo (`neural-lace/workstreams-ui/**`, project layer — not `adapters/claude-code/` →
  `~/.claude/` install surface). It reaches the operator's running server via merge to master +
  the operator's server checkout sync; M1 explicitly includes restarting the live server from a
  canonical-resolving build (§7).

## 3. Decisions (each with rationale + reversal cost)

| # | Decision | Rationale | Reversal cost |
|---|---|---|---|
| DEC-1 | **Task/checkbox state stays in git plan files.** No task-state ledger migration. | The plan file is the reviewable artifact (PR diffs, blame, history) and `task-verifier` is its only checkbox writer (doctrine/planning.md) — a ledger would buy single-path accuracy that the canonical-root resolver (DEC-3) already buys for free, while destroying git-reviewability and forcing a migration of every plan, every hook grammar (plan-lifecycle.sh), and every agent contract. The brief's framing is accepted with one sharpening: D1 was never evidence against git-residency — it was evidence against *ambient* root resolution. | Cheap to reverse later, by design: because task-verifier is the single writer, a materialized task-state ledger can be added additively (verifier writes both) without touching readers first. Staying costs: N-checkout ambiguity is permanent and must be held closed by REQ-A1/A2's regression pins forever. |
| DEC-2 | **Per-request in-process pull is the read path; push (state-watch → SSE) is retained as change-*notification* only** — "something changed, refetch", never a server-side re-derivation trigger. | OD-006's own rule sorts this case into pull-on-demand (changes >> reads, measured — §1 point 3). Pushing *data* requires a materialized derived store, which is a second copy that can rot (the snapshot patch's defect, DEC-9). Pushing *notification* keeps open browsers live at zero derived state. | One module: re-adding a cache in front of the read functions is additive and mechanical. The SSE notifier reversal is `git revert` of the M4 state-watch commit. |
| DEC-3 | **Canonical repo root resolved by one function, `canonicalRepoRoot()`, resolution order: (1) explicit env override (test sandbox), (2) per-machine `config/projects.json` pin for the `neural-lace` key, (3) `selfRepoRoot()` dereferenced through a `.git` pointer *file* (`gitdir: <main>/.git/worktrees/<name>` → `<main>`), (4) `selfRepoRoot()` when `.git` is a directory.** No new config file, no git spawn. | The dereference mechanism is proven live (Inputs: the operator's exact worktree derefs to the canonical checkout via one fs read). `projects.json` already has override-wins precedence (projects.js:133-151) — reusing it beats inventing a registry (`register-path` was investigated: it is a single-purpose pointer at workstreams-coordination, not a general mechanism; `active-repos.txt` is the PR-health gate's slug list — neither fits). A worktree of the same repo resolving to itself becomes structurally impossible: step 3 fires before step 4 whenever `.git` is a file. | Swap one function body; all consumers call through `mainRepoRoot()` already (derive-lib.js:1155 export). The pin (step 2) is per-machine gitignored config — reversible per machine. |
| DEC-4 | **The six DeriveCache panes migrate per-pane to in-process readers; where the derivation grammar genuinely lives in bash (`od_harness_health` gate fold, `od_sessions` composition), the Node port ships only behind a parity selftest that runs BOTH implementations on the same fixture** — never a frozen expected-output file. | Most "ports" are not ports: backlog already has a full in-process parser (server.js:608 `parseBacklogRows` — the 258 s `nl backlog` shell-out duplicates a reader that runs in ms); needs-me already has one (inbox-routes.js `buildInboxPayload`); costs/doctor are direct reads of materialized JSON caches. Only health and the sessions half of status are real grammar ports — the "third grammar" hazard derive-lib.js:200-207 and state-watch.js:19-28 warn about — and the parity oracle converts that hazard from silent drift into a pinned, breakable contract. | Per-pane: each migration is its own commit deleting its `SUBCOMMANDS` entry; reverting one pane is one `git revert` re-adding the entry while DeriveCache still exists (pre-M4). Post-M4, reverting a port means restoring the module from history — priced, and why parity tests land in the SAME commit as each port. |
| DEC-5 | **`DeriveCache` is deleted at M4 (whole module, 612 lines, incl. timeout/lane/killTree/anti-entropy machinery and `isLobotomized`); `state-watch.js` is retained and reduced to the SSE change-notifier.** | The cache's entire defensive apparatus exists to manage subprocess pathology (its own header comments cite four incidents); with zero read-path spawns there is nothing left to defend. state-watch's fence (spawn cost scales with change rate, not clock) is *honored more deeply* by this design — spawns now scale to zero — and its watch list is exactly the right trigger list for "tell open browsers to refetch". | DeriveCache: restore from git history (it is one self-contained file with a selftest). state-watch repurpose: one-commit revert. |
| DEC-6 | **Three named subprocess exceptions survive, none on a hot GET path:** (a) *shipped* — one direct `git.exe log` spawn per request (93 ms measured; no bash, no login shell, no jq), result stamped `derived_at` and rendered with age; (b) *why-drawer* — on-demand single spawn per operator click (unchanged); (c) *all POST write delegations* to ask-registry.sh / needs-you.sh (one-writer discipline, unchanged). `classifySessions`' GET-path bash spawn is deleted, replaced by the age-only `classifyHeartbeatAge` already in derive-lib. | git history has no Node-stdlib reader; reimplementing git is absurd; 93 ms direct-spawn is inside budget for the one pane that needs it. The login-shell tax (94–119 s worst case) is what must never be paid on a read — direct binary spawn does not pay it. The write CLIs are bash by contract and POST-only. | Each exception is one function; converting shipped to a port or a materialized input later is additive. |
| DEC-7 | **Fail-loud contract: every payload carries a `sources[]` block** (per store: `{name, path, ok, reason?, benign_empty?, corrupt_rows, read_ms, snapshot_ts?}`); any `ok:false` renders a named error state in the affected pane — never an empty list, never last-known-good, never a silent fallback. | Extends three precedents already in this codebase to ALL sources uniformly: `listRawHeartbeatsResult`'s three-state contract (derive-lib.js:552-573), `readNeedsYouLedgerItems`' three-state contract (inbox-routes.js:130-168), roadmap's `ok:false`-renders-error C4 rule (roadmap-routes.js:2033-2037). Also upgrades `readJsonlLines`' silent corrupt-row skip (derive-lib.js:78-86) to a *counted* skip. | Additive envelope field; removing it is deleting a field. The behavioral change (no last-known-good) is the named sacrifice — reversing THAT means re-growing a cache, priced at DEC-2. |
| DEC-8 | **Staleness is unrepresentable for first-party stores and age-labeled for second-party snapshots.** First-party (all `~/.claude/state/*` + canonical-checkout files): the payload is a pure function of reads performed inside the request; `generated_at` == read time by construction; there is no stored derived state to go stale. Second-party (doctor-cache.json, obs-costs-cache.json, deploy evidence, remote-ledgers, maintenance snapshots): rendered with their own `snapshot_ts` age, and past a per-source threshold rendered in a degraded "as of <age>" state — never as current. | This is the honest resolution of the operator's "no possibility of inaccuracy": achievable where we read the origin, impossible where the origin is itself a snapshot — so label it, following the A3c raw-timestamp precedent (derive-lib.js:575-588: never ship a baked classification across a time boundary; ship the timestamp and let the reader classify by age). | Threshold values are env-tunable constants; the rendering contract is client-side and revertible per pane. |
| DEC-9 | **In-flight patch reconciliation:** canonical-root+staleness → **FOLD IN** (becomes M1, reconciled to DEC-3's resolver spec — dereference + pin, not a hardcoded path); snapshot-persistence → **DISCARD, superseded** (header of this doc); roadmap row layout / verification-stage chips → **KEEP** (UI layer, orthogonal; chips consuming deploy evidence must adopt DEC-8's age labels); deploy-verified oracle → **KEEP** (it *produces* a second-party snapshot this design consumes under REQ-A7; it must stamp `snapshot_ts`). | OD-010: every in-flight item dispositioned explicitly so the orchestrator can reconcile without archaeology. | Each disposition is per-worktree; a discarded worktree's commits remain salvageable from its branch. |
| DEC-10 | **The signal-ledger is read as a bounded byte-tail (default: last 4 MB, first partial line dropped), not whole-file, wherever a windowed fold suffices (health 7d window, sessions recent-events).** | Whole-file is already 101 ms read+split at 17.7 MB and the file only grows; the health fold's own window is 7 days, so bytes older than the window are dead weight. Bounded-tail keeps the read O(window), not O(history). | One constant + one read function; whole-file fallback is the trivial revert. If a future fold needs full history it calls the unbounded reader explicitly. |

## 4. Architecture

### 4.1 Source inventory — one canonical resolution rule per store

Class **G** = machine-**g**lobal (one path per machine — D1 structurally impossible);
class **R** = git-**r**esident (exists in N checkouts — D1's home; resolves via §4.2);
class **S** = second-party **s**napshot (produced by another process; age-labeled per DEC-8).

| # | Store | Class | Canonical path rule | Reader (in-process) |
|---|---|---|---|---|
| 1 | Plan files `docs/plans/*.md` + `archive/` | R | `canonicalRepoRoot()`; cross-repo linked plans: the ask's own `repo` field (roadmap-routes.js:631-639), itself passed through the worktree dereference | `plan-parse.js` (exists) |
| 2 | Ask registry `ask-registry.jsonl` | G | `$HOME/.claude/state/` (env override tests-only, derive-lib.js:51-55) | `readAskRegistry`/folds (exist) |
| 3 | Progress logs `progress-logs/*.jsonl` | G | `$HOME/.claude/state/progress-logs/` | `readAskEvents` (exists) |
| 4 | Dispatch provenance `dispatch-provenance/*.json` | G | `$HOME/.claude/state/dispatch-provenance/` | exists (derive-lib.js:155-168) |
| 5 | Heartbeats `heartbeats/*.json` | G | `$HOME/.claude/state/heartbeats/` | `listRawHeartbeatsResult` (exists) |
| 6 | Needs-you ledger `needs-you/ledger.json` | G | `$HOME/.claude/state/needs-you/` | `readNeedsYouLedgerItems` (exists) |
| 7 | Signal ledger `signal-ledger.jsonl` (17.7 MB / 63k rows) | G | `$HOME/.claude/state/` | NEW: bounded-tail JSONL reader (DEC-10) feeding the health/sessions folds |
| 8 | Dispatch ledger `dispatch-ledger.jsonl` (3,076 rows / 5.4 ms) | G | `$HOME/.claude/state/` | `readJsonlLines` (exists) |
| 9 | nl-issues `nl-issues.jsonl` | G | `$HOME/.claude/state/` | `readJsonlLines` (exists) |
| 10 | `docs/backlog.md` | R | `canonicalRepoRoot()` | `parseBacklogRows` (exists, server.js:608) |
| 11 | `NEEDS-YOU.md`, `docs/operator-todo.md` | R | `canonicalRepoRoot()` | exist (server.js:298-312, 392+) |
| 12 | Doctor cache `state/digest/doctor-cache.json` | S | `$HOME/.claude/state/digest/` | NEW: direct JSON read + `snapshot_ts` |
| 13 | Costs cache `obs-costs-cache.json` | S | `$HOME/.claude/state/` | NEW: direct JSON read + `snapshot_ts` |
| 14 | Remote peer ledgers `remote-ledgers/` | S | `$HOME/.claude/state/remote-ledgers/` | raw-timestamp discipline already pinned (A3c) |
| 15 | Git history (shipped pane) | R | one direct `git.exe` spawn against `canonicalRepoRoot()` (DEC-6a) | n/a — named exception, age-stamped |
| 16 | Deploy evidence (deploy-verified oracle, in flight) | S | wherever that patch materializes it; MUST stamp `snapshot_ts` (DEC-9) | consumed as `deployReadyAtMs` (completion-oracle contract, exists) |
| 17 | Maintenance snapshots (`nl-maintenance`) | S | existing `maintenanceSnapshotDir()` | already direct-read, not cached (server.js:233-268) — the in-repo precedent this design generalizes |

### 4.2 Canonical-root resolution (the D1 fix)

`canonicalRepoRoot()` lives beside `selfRepoRoot()` in `config/projects.js` (the module that owns
root-resolution today) and is what `deriveLib.mainRepoRoot()` returns. Resolution order per DEC-3;
step 3 in full: read `<selfRepoRoot()>/.git`; if it is a **file** matching
`/^gitdir:\s*(.+?)[\\\/]\.git[\\\/]worktrees[\\\/]/`, the canonical root is the captured path.
Applied recursively once (a worktree's target is by definition a main checkout; a second hop is a
config error and fails loud). The same dereference is applied to an ask's cross-repo `repo` field
before plan resolution, so a registry record pointing at a worktree also lands on that repo's main
checkout. Unresolvable (no `.git` at all, pin pointing at a nonexistent dir) is a **named
resolution failure** rendered per §4.4 — never a silent `process.cwd()` fallback (the current
catch-arm at derive-lib.js:72 is deleted).

*Checkout freshness (the residual R-class staleness):* even the canonical checkout can sit behind
origin/master. Cheap, honest, no-network signal: surface the age of
`<root>/.git/FETCH_HEAD` (or HEAD's commit time when FETCH_HEAD is absent) as
`sources[].snapshot_ts` for R-class stores; the client renders an age chip when it exceeds
`COCKPIT_CHECKOUT_FRESH_MIN` (default 120 min). This is a SHOULD (REQ-A8) — it bounds the
stale-clone pre-mortem case, it does not claim to prove currency.

### 4.3 The read path

Per request: resolve roots → read every needed store (in-process, fail-loud, corrupt rows counted)
→ fold → validate (payload-schema.js unchanged) → respond, with `sources[]` attached and
`generated_at` = now. No module-scope mutable derived state anywhere on the path (request-scoped
context objects like `hbCtx` are the existing, correct pattern — roadmap-routes.js:1864-1878).

**Budget (committed, with derivation):** `/api/roadmap` **p95 ≤ 50 ms warm**; the full pane read
set (all migrated panes, one burst) **≤ 250 ms warm**; cold-start first paint **≤ 2 s** (Defender
first-touch tax). Derivation: 12.1 ms (31 live plans) + ≤ 5.4 ms-class JSONL reads (registry,
provenance, dispatch ledger — each ≤ 3k-row scale today) + heartbeats (17 small files) + pure-JS
folds (sub-ms per 1k items) ≈ 20–30 ms measured-sum for roadmap; ×2 headroom → 50. Health adds the
signal-ledger bounded tail (≤ 60 ms at the 4 MB cap); backlog adds one ~1 MB md parse; shipped adds
its 93 ms git spawn (its own budget: ≤ 300 ms). **Re-derivation command** (REQ-A6 ships it):
`node server/read-bench.js` — 100 iterations per endpoint against the live estate, prints
p50/p95/max per endpoint and per `sources[]` entry `read_ms`; the budget numbers above are
re-derived by re-running it, and MUST be re-run on any machine where the corpus grows past 2× the
Inputs figures.

**Event-loop note (why sync reads are acceptable here):** the reads are 10–60 ms bursts on a
single-operator localhost server; blocking the loop for one burst is invisible at this request
rate. The moment a read exceeds its budget it shows up in `read_ms` — observable, not silent
(contrast: the old spawnSync hazard was *seconds-to-minutes*, derive-cache.js:195-211).

**DeriveCache / state-watch disposition** (DEC-4/5): panes re-point per-pane (M3) —
`paneResponse`'s envelope shape (`rc`/`stderr_tail`/`derived_at`) is preserved per pane during
migration so the client changes once, at the end, not per step. `SUBCOMMANDS` shrinks
monotonically; when it is empty, M4 deletes the module, its timer, `isLobotomized` (a detector for
a failure mode — permanent all-panes rc≠0 — that no longer has a mechanism), and `/api/refresh`
(its POST becomes a 200 no-op that just answers with current `generated_at`, because every GET is
already a refresh). state-watch keeps its watch list and debounce; its `onTrigger` becomes
`broadcastRefresh` only (the second watch group at server.js:1804 already works exactly this way —
the maintenance pane is the proof this shape works in production).

### 4.4 Fail-loud contract (observable behavior per failure mode)

| Failure | Observable behavior (WHAT/WHY/FIX per OD-004) |
|---|---|
| Store unreadable (EACCES, ENOTDIR, mid-read race) | `sources[]` entry `ok:false` + reason with errno; the consuming pane renders a named error card: "ask-registry.jsonl could not be read (EACCES) at `<abs path>` — cockpit data for asks is unavailable, not empty. Fix: check file permissions / retry." HTTP 200, `ok:false` scoped to the affected block. Never `[]`, never last-known-good. |
| Store absent, never written (ENOENT on a state dir) | `benign_empty:true` — rendered as the honest empty state ("no sessions have ever heartbeated on this machine"), visually distinct from failure. (Existing three-state contracts, DEC-7, now uniform.) |
| Canonical root unresolvable | `/api/roadmap` and every R-class consumer return `ok:false` naming each resolution step attempted and its result; client renders error + Retry (existing C4 behavior, roadmap-routes.js:2033-2037). |
| One plan file unreadable | Existing per-root `unknown`/`scanIssue` handling (roadmap-routes.js:388-397) — kept verbatim; the rest of the tree still renders. |
| Corrupt JSONL row(s) | Row skipped AND counted: `corrupt_rows: N` in `sources[]`; N>0 renders a warning chip on the consuming pane ("3 unreadable records skipped in signal-ledger.jsonl"). Upgrades today's silent skip (derive-lib.js:78-86). |
| Second-party snapshot older than threshold | Value rendered WITH age ("doctor: green — as of 4 h ago") in degraded styling; never bare. Missing entirely: named "never produced on this machine" state. |
| Shipped git spawn fails | Pane renders the spawn's rc/stderr verbatim as an error card (never empty), `derived_at` of the last successful run NOT shown — there is no last-known-good (DEC-7). |

### 4.5 Staleness contract (explicit, per architecture-reviewer's requirement)

Worst-case staleness of a reader's view, by class: **G and R stores: zero** beyond filesystem
read-consistency — the render is a pure function of the bytes on disk at request time; the only
"staleness" possible is the operator not having refetched, which SSE notification bounds at the
state-watch debounce (2–15 s) for open tabs. **R stores additionally** carry the checkout-freshness
age (§4.2) because disk-truth on this machine can lag master — surfaced, not hidden. **S stores:
unbounded by this design** (they are other processes' outputs) — therefore always rendered with
age, with per-source degraded-state thresholds. There is no fourth class: any new source a future
pane adds MUST be declared G, R, or S in `sources[]` (REQ-A4 makes the block mandatory), which is
this design's Parnas boundary: panes may change freely; the source-class contract is the stable
seam.

## Requirements

### Phase A — foreclose D1/D2 (ships first; M1–M2)

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-A1 | MUST | `canonicalRepoRoot()` implements DEC-3's four-step order (env override → projects.json `neural-lace` pin → `.git`-file worktree dereference → self root), replaces `derive-lib.js mainRepoRoot()`'s body, and every R-class consumer (plan scan, backlog.md, NEEDS-YOU.md, operator-todo.md, cross-repo ask `repo` fields) resolves through it. Verify: selftest fixture — a synthetic worktree dir whose `.git` file points at a synthetic main checkout; assert resolution lands on the main checkout; plus livesmoke: server started from `~/claude-projects/workstreams-ui-server`, `GET /api/roadmap` task counts equal a direct `plan-parse` count of the canonical checkout's same plan file. |
| REQ-A2 | MUST | Regression pin for D1's exact shape: a worktree of the same repo NEVER resolves to itself. Verify: dedicated selftest case asserting `canonicalRepoRoot()` from inside a `.git`-file worktree ≠ the worktree path, and that the silent `process.cwd()` fallback is gone (unresolvable root throws/returns a named failure, never cwd). |
| REQ-A3 | MUST | Per-request read-through: no cross-request cache of any derived payload, no snapshot persistence, no invalidation logic anywhere on a GET path; `generated_at` == request time. Verify: selftest flips one checkbox byte in a sandboxed plan file between two GETs with no restart/no trigger; the two payloads differ. Grep-verify: no `writeFileSync` of derived state, no module-scope derived-payload variable in the read modules. |
| REQ-A4 | MUST | Every read payload carries the `sources[]` block (name, path, ok, reason, benign_empty, corrupt_rows, read_ms, snapshot_ts, class G/R/S) and the client renders §4.4's states: store-failure → named error card (never empty/stale), benign-empty → distinct honest-empty, corrupt rows → counted warning. Verify: selftest per failure mode — chmod/rename a sandboxed store, assert the payload's named state; corrupt-row fixture asserts the count surfaces. |
| REQ-A5 | MUST | Zero `child_process` use on any GET path except the two named exceptions (shipped: one direct `git.exe` spawn; why-drawer: on-demand). Includes deleting `classifySessions`' bash spawn in favor of `classifyHeartbeatAge`. Verify: selftest boots the server with a `child_process.spawn` wrapper that records call sites, exercises every GET route, asserts the recorded set ⊆ {shipped, why}; plus static grep in CI/selftest over the server modules. |
| REQ-A6 | MUST | Budgets held and re-derivable: `/api/roadmap` p95 ≤ 50 ms warm, migrated-pane burst ≤ 250 ms warm, shipped ≤ 300 ms, on this machine at current corpus scale. Verify: `read-bench.js` ships in the same plan and its output is cited in task evidence; the selftest carries a generous machine-independent ceiling (2 s) as the regression tripwire, with the real numbers re-derived by running the bench. |
| REQ-A7 | MUST | Second-party snapshots (doctor, costs, deploy evidence, remote ledgers, maintenance) always render with their own `snapshot_ts` age and degrade visibly past per-source thresholds; never rendered as current. Verify: fixture with an aged `snapshot_ts` asserts the age field in the payload and the degraded flag past threshold. |
| REQ-A8 | SHOULD | Checkout-freshness signal for R-class stores (§4.2): FETCH_HEAD/HEAD age surfaced as `snapshot_ts`, client age-chip past `COCKPIT_CHECKOUT_FRESH_MIN`. Verify: fixture repo with an old FETCH_HEAD mtime asserts the surfaced age. |
| REQ-A9 | MUST | Corrupt-row counting replaces silent skipping in every JSONL reader used by the cockpit (`readJsonlLines` gains a counted variant; call sites migrate). Verify: fixture ledger with 2 corrupt rows → `corrupt_rows:2` in `sources[]`, fold output unchanged for valid rows. |

### Phase B — de-subprocess the panes; delete the cache (M3–M4)

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-B1 | MUST | Backlog pane serves the existing in-process parser's output (server.js `parseBacklogRows`/`buildBacklogPayload`) against `canonicalRepoRoot()`; the `nl backlog --json` shell-out and its 360 s timeout are deleted. Verify: selftest asserts `/api/pane/backlog` renders from a fixture backlog.md with zero spawns; live: pane populates in <1 s from cold where it previously took 80–258 s. |
| REQ-B2 | MUST | Needs-me pane serves the inbox ledger reader's output (inbox-routes' three-state read), deleting its shell-out. Verify: fixture ledger → pane payload with zero spawns; ledger-unavailable fixture → named error per REQ-A4. |
| REQ-B3 | MUST | Costs pane and the doctor half of status read their materialized caches (obs-costs-cache.json, doctor-cache.json) directly with `snapshot_ts` per REQ-A7, deleting their shell-outs. Verify: fixture caches → payload; absent cache → "never produced" named state. |
| REQ-B4 | MUST | Sessions/status composition folds heartbeats + signal-ledger bounded tail in Node, with a **parity selftest that executes BOTH `od_sessions` (bash, via the existing lib) AND the Node fold on one shared sandbox fixture and diffs the normalized output** — run in the selftest suite, not a frozen golden file. Verify: parity test green in the same commit as the port; the pane serves the Node fold with zero spawns. |
| REQ-B5 | MUST | Health pane: same parity-gated port for `od_harness_health`'s gate fold (bounded-tail ledger read, DEC-10). Until parity passes, the pane stays subprocess-backed AND renders its `derived_at` age per REQ-A7 (interim honesty). Verify: parity selftest as REQ-B4; interim state verified by the age field's presence. |
| REQ-B6 | MUST | Shipped pane: one direct `git.exe log` spawn per request against `canonicalRepoRoot()` (93 ms measured), no bash, no jq, result stamped `derived_at` and age-rendered. Verify: selftest with a fixture repo asserts single-spawn + payload shape; bench asserts ≤ 300 ms warm. |
| REQ-B7 | MUST | End state: `SUBCOMMANDS` empty → `derive-cache.js` deleted entirely (incl. anti-entropy timer, lanes, killTree, `isLobotomized`, `/api/refresh` derivation semantics); `state-watch.js` `onTrigger` re-pointed to `broadcastRefresh` only; `bashBin`/`spawnEnv` relocate to the one write-path module that still needs them. Verify: grep — no `require('./derive-cache` anywhere; server boots and serves every pane; state-watch selftest still green; the OD-002 scorecard in the task evidence counts net-negative modules/spawn-sites. |
| REQ-B8 | MUST | Signal-ledger bounded-tail reader (DEC-10): byte-tail default 4 MB, first partial line dropped, env-tunable, with an explicit unbounded escape hatch for callers that state why. Verify: fixture ledger larger than the cap — fold sees only in-window rows; boundary selftest for the partial-first-line drop. |
| REQ-B9 | SHOULD | The `nl` CLI keeps its own bash oracles unchanged (out of scope); the parity fixtures land in a shared location both suites can consume, so CLI-side changes break the parity test rather than silently diverging the cockpit. Verify: fixture path referenced by both selftests. |

## Non-goals

- **Moving task state out of git plan files** — REJECTED, DEC-1; tracked only as the priced
  reversal path there (task-verifier dual-write), no plan exists or should.
- **Multi-machine / peer-view accuracy** — remote-ledgers stay snapshot-class (S) with the
  existing A3c raw-timestamp discipline; making peers read-through would require networked reads.
  n/a — no future plan.
- **Proving R-class currency against origin/master** — no network fetch on any read path, ever;
  REQ-A8's age chip is the honest bound. A background fetch is a separate concern for a separate
  design if the operator wants it.
- **Fixing `nl <sub> --json` / observability-derive.sh performance for CLI users** — the CLI's own
  latency (O.9's backlog-oracle issue etc.) is untouched; this design only stops the cockpit
  paying it. Tracked where it already is (O.9 / backlog).
- **auditor.js redesign** — the background drift auditor is not on the read path; its spawns are
  background-scheduled, out of scope. Tracked: nothing owed.
- **Write-path changes** — one-writer CLI delegation stays byte-for-byte (DEC-6c).
- **Plan-grammar changes** — `plan-parse.js` is consumed as-is; no new grammar (constraint §2).
- **Archive-corpus rendering beyond the existing recent-evidence gate** — the 68.8 ms full-archive
  read is NOT added to the hot path; the roadmap's evidence-gated archive subset (roadmap-routes.js
  scanPlanDir cutoff) stays as-is.

## What this design gives up (named sacrifice)

- **Rejected cheaper alternative:** patching D1/D2 point-wise (the four in-flight patches) and
  keeping DeriveCache. Rejected because it leaves the subprocess layer — the proven source of four
  named production incidents and the operator's visible latency — alive and defended by timeouts,
  lanes, and reapers instead of removed; accuracy would remain a discipline, not a construction.
- **Sacrifice 1 — last-known-good display is gone.** Today a transient oracle failure keeps
  showing the previous good data with an rc flag (derive-cache.js:33-40). Under DEC-7 a failed
  source shows a named error card with nothing behind it. Deliberate: the operator hit D1
  precisely because confident-looking data papered over a broken read; honest absence beats
  comfortable staleness. Cost accepted: a mid-read race renders an error until the next refetch.
- **Sacrifice 2 — the mechanical single-data-path property.** derive-cache's acceptance bar was
  "what the pane shows and what `nl <sub> --json` returns are mechanically the same data path"
  (derive-cache.js:28-31). This design breaks that identity for ported panes: cockpit and CLI can
  now disagree if either side changes. The replacement guarantee is parity-by-test (REQ-B4/B5/B9)
  — strictly weaker, honestly named, and a **standing maintenance burden**: every change to the
  bash folds now owes a parity-test run.
- **Sacrifice 3 — per-request read cost with zero amortization.** Every GET re-reads and re-folds
  (~20–60 ms warm, measured basis in §4.3) versus a cache hit's ~0 ms. Against the measured
  alternative — spawn chains of 77–258 s feeding that cache, plus its 612 lines of incident
  machinery — this is the trade the whole design exists to make.
- **D-07/OD-002 displacement ledger (net inventory change):** deleted — derive-cache.js (612
  lines, 6 shell-out subcommands, anti-entropy timer, 2 refresh lanes, killTree reaper,
  isLobotomized detector), classifySessions' GET-path bash spawn, the snapshot-persistence patch
  (discarded pre-merge), `/api/refresh`'s derivation semantics. Added — `canonicalRepoRoot()` (one
  function), a counted-JSONL reader variant, a bounded-tail reader, 2 direct snapshot readers, 2
  Node folds + 2 parity selftests, `read-bench.js`, the `sources[]` envelope. Net: −1 module,
  −6 recurring spawn sites, −1 timer; additions are all passive readers/tests.

## Pre-mortem

It is 2027-02. The health pane shows 15 gates green; `nl health` in a terminal shows 16, one
blocking. Sequence: (1) in November a builder added a new signal type to
observability-derive.sh's gate fold and, being CLI-focused, never touched the cockpit's Node fold;
(2) the parity selftest stayed green because its fixture ledger predates the new signal type —
parity on a stale fixture proves nothing about new record shapes; (3) the operator trusts the
cockpit precisely because this design promised accuracy-by-construction, so the divergence reads
as "CLI is being weird" for weeks; (4) separately, in January the operator moved the server to a
fresh machine by *copying* the checkout directory — `.git` is a real directory there, so
`canonicalRepoRoot()` step 4 declares the stale copy canonical, and D1 returns wearing a clone
costume, with REQ-A8 unshipped because it was a SHOULD. Nobody notices for weeks because both
failures produce *confident, plausible* renders — the exact phenotype of the original defect.

**What changes now to make that story impossible:**
1. REQ-B4/B5's parity tests are specified as **executing both implementations live on a shared
   fixture** (never frozen expected-output), AND the fixture generator enumerates record types
   from the live ledger's observed `type` set, failing the test when the live ledger contains a
   record type the fixture doesn't cover — new-shape drift becomes a red test, not a silent gap.
2. `sources[]` carries the reader's module+version per store, so a cockpit/CLI dispute is
   diagnosable from the payload itself in one glance.
3. REQ-A8 exists specifically to bound the stale-clone case (the age chip fires on a copy that
   never fetches); it stays SHOULD for scope honesty, but M1's task list orders it inside the
   first migration stage so it ships with the resolver, and the resolver's named-failure path
   (REQ-A2) refuses to guess when `.git` is absent entirely.
4. The livesmoke in REQ-A1 is pinned to the operator's real deployment shape (server run FROM the
   worktree), not a synthetic fixture only — the D1 replay stays the acceptance demonstration
   forever.

## Verification strategy

The maintainer is the user (constitution §4): the demonstration is the operator's own deployment
shape. (1) **D1 replay:** start the server from `workstreams-ui-server` (the real worktree),
`curl /api/roadmap`, and diff the rendered done-counts against a direct `plan-parse.js` count of
the canonical checkout's plan files — equality is the fix, and this exact replay is REQ-A1's
standing livesmoke. (2) **D2 replay:** cold-start wall-clock to first fully-populated pane set —
previously bounded below by a 77 s spawn, target < 2 s (REQ-A6 bench output cited in evidence).
(3) **Selftest suites:** every REQ's inline verification lands in the existing per-module
selftests (server.selftest.js, roadmap-routes.selftest.js, state-watch.selftest.js patterns);
parity suites per REQ-B4/B5; the spawn-recording GET sweep per REQ-A5 is the structural
regression net. (4) **Failure-mode drills** per §4.4's table, each a selftest case. (5)
**Anti-bloat scorecard** in the closing task's evidence per OD-002 (the D-07 ledger above, counted
against the merged tree).

## Directives honored

- OD-006 (push-over-pull-push-materialize) — honored via its own pull-on-demand branch: measured
  changes >> reads (§1 point 3); push retained as the SSE notification path; no timer-driven hot
  path anywhere (DEC-2, REQ-B7).
- OD-002 (anti-bloat-modify-not-add) — displacement ledger in the named-sacrifice section; net
  inventory counts down (−1 module, −6 spawn sites, −1 timer); REQ-B7 verifies at merge.
- OD-004 (gate-philosophy-complete-instruction) — §4.4's fail-loud states each carry WHAT/WHY/FIX;
  no silent block or empty-list failure anywhere (REQ-A4).
- OD-010 (disposition-everything) — all four in-flight patches explicitly dispositioned (DEC-9,
  §7); nothing left to age out.
- OD-016 (observability-equal-clarity) — `sources[]` is the machine-readable counterpart of every
  human-visible error/age chip; the same block serves both audiences (REQ-A4).
- OD-001 (no-wsl-dependency) — nothing here depends on WSL; pure Node fs + one direct git.exe
  spawn (DEC-6).
- OD-012 (standing-autonomy-reversible-work) — every decision above is priced reversible
  (Decisions table); no operator pause required; the one operator-taste item (age-chip thresholds)
  ships env-tunable rather than blocking.

## 7. Migration (no big-bang; every stage shippable and individually revertible)

- **M1 — canonical root (folds in the in-flight canonical-root+staleness worktree, reconciled to
  DEC-3's spec):** `canonicalRepoRoot()` + REQ-A1/A2/A8 + delete the cwd fallback. Interim state:
  everything else unchanged; D1 is dead the moment the operator's server restarts on this commit.
- **M2 — fail-loud envelope:** `sources[]` + counted corrupt rows + three-state normalization
  (REQ-A4/A9) + snapshot age labels (REQ-A7). Interim: panes still cache-backed but every payload
  now carries source truth-status; the client gains the error/age rendering it will keep.
- **M3 — pane migrations, one commit each, cheapest first:** backlog (REQ-B1) → needs-me (REQ-B2)
  → costs+doctor (REQ-B3) → sessions/status (REQ-B4) → health (REQ-B5) → shipped (REQ-B6), plus
  the classifySessions deletion (REQ-A5). Interim states: `SUBCOMMANDS` shrinks; un-migrated panes
  keep exact current behavior; both paths coexist without interference because each pane has
  exactly one backing at any commit.
- **M4 — deletion:** DeriveCache + timer + `/api/refresh` semantics + lobotomy detector removed;
  state-watch re-pointed to `broadcastRefresh` (REQ-B7). Interim: none — this is the end state.
- **In-flight reconciliation for the orchestrator (DEC-9):** canonical-root+staleness worktree →
  FOLD INTO M1 (keep its tests; replace any hardcoded canonical path with the resolver);
  snapshot-persistence worktree → DISCARD (superseded — do not merge; salvage nothing, its premise
  is obsolete at a 12–25 ms read); row-layout/verification-chips worktree → MERGE as-is (UI-only;
  one follow-up: chips consuming deploy evidence adopt REQ-A7's age field); deploy-verified-oracle
  worktree → MERGE (its output is source #16; require it to stamp `snapshot_ts`).

## Review Chain

authored-by: design-author (model: fable)
design-reviews:
  - reviewer: architecture-reviewer  verdict: PENDING  record: docs/reviews/ (to be created on review)
  - reviewer: harness-reviewer       verdict: PENDING  record: docs/reviews/ (to be created on review — harness surface: OD-006's declared surface covers neural-lace/workstreams-ui/**, and the parity contract touches the estate's nl oracle conventions)
