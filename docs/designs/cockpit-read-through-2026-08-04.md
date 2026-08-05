# Design: Cockpit read-through — accuracy by construction, not by cache coherence

**Status:** r2 — delta integration, awaiting re-review

**Author:** design-author (model: fable — running as claude-fable-5, matching this agent's pin; not inherited)

**Changelog:** r1 (624df7ac, base master@2afa84fc): initial authoring. r1 → r2 (base rebased to master@87ddda29): integrated harness review of 624df7ac — C1: DEC-3 rewritten to consume the install-written `~/.claude/local/nl-repo-path` pin (the estate's actual refreshed pin; the r1 projects.json second-pin idea REJECTED as D1-at-the-config-layer) with the launcher-identical NL_REPO_ROOT-first chain; C2: full M4 consumer-disposition table added (reconciler/auditor/4× bashBin-spawnEnv consumers/killTree relocation/selftest retirements) — killTree contradiction fixed by relocating it with bashBin/spawnEnv; M1: §7/DEC-9 rewritten against merged reality (ec4be5a2 resolver REPLACE-not-fold, scan_provenance ABSORBED into REQ-A8, chips/liveness fixes MERGED-no-action, deploy-oracle re-verified still in flight); M2: M2 interim cache-level `sources[]` shape specified; minors: REQ-A6 build-time-only budget acknowledgment + production read_ms observability, §4.4 client-render verification named (cockpit.selftest.js regex convention), measurement seed persisted as evidence file, all line citations re-anchored to 87ddda29.

**Supersedes:**
- The **snapshot-persistence patch** (parallel worktree, subject: "snapshot persistence for
  derive-cache") — superseded in full, discard. Re-verified at r2: it was verifier-REFUTED and
  never merged (no snapshot commit in 2afa84fc..87ddda29), so the discard costs nothing. A read
  path measured at ~12–25 ms warm needs no persisted snapshot; a snapshot is a second copy of the
  truth that can rot, which is D1's defect class re-introduced one layer up. See §3 DEC-9 and §7.
- `derive-cache.js`'s standing role as "the ONLY place server.js reads derived truth from"
  (derive-cache.js:29–31) — superseded at end state M4; the module is deleted, not extended. Law 1
  (DERIVE-DON'T-MAINTAIN) itself is **unchanged and binding**; what dies is its implementation via
  subprocess shell-outs plus an in-memory cache (see §3 DEC-4/DEC-5 for what preserves Law 1's
  intent).
- The **merged ec4be5a2 resolver body** (`derive-lib.js:109-152` at 87ddda29:
  `gitFieldSync`×2 + `resolveCanonicalRepoRoot` + the retained `process.cwd()` catch-arm at
  :150-152) — its git-spawn resolution and silent cwd fallback are REPLACED by DEC-3's
  pin-first, fs-read chain; its pure decision function `deriveCanonicalRoot` and its selftest
  series (derive-lib selftest 22.x, :1961-1978) are KEPT (§7 M1). Its `scan_provenance` staleness
  signal is ABSORBED, not replaced (REQ-A8).

**Inputs (all read in full unless marked otherwise):**
- r2 re-base: worktree rebased onto `master@87ddda29` (13+ commits past r1's base); r2 grounding
  additions, each verified live: `~/.claude/local/nl-repo-path` (exists; content `/c/Users/<user>/claude-projects/neural-lace`, POSIX form, one line), `install.sh` (~:1539: `printf ... > "$CLAUDE_DIR/local/nl-repo-path"` — rewritten EVERY install, "a RESOLVED VALUE ... safe — and necessary — to overwrite on every install run"), `adapters/claude-code/hooks/lib/nl-paths.sh:60-80` (`nl_repo_root()`: NL_REPO_ROOT env → nl-repo-path file, with CR/whitespace trim + dir-exists check), `adapters/claude-code/scripts/ensure-cockpit.sh:63` (launcher resolution order documents the same chain), merged commits `ec4be5a2` (canonical-root git-spawn resolver + scan_provenance), `fa4b924d`/`3c669d90` (stage chips), `3c93bc15` (pid-aware liveness), `1d16834b`/`d0af551d` (dispatch attribution); deploy-oracle `6ac88bce` confirmed NOT in master (`git merge-base --is-ancestor` false; lives in worktree-wf_b0c65996-356-4); C2 consumer sweep verified at 87ddda29: `reconciler.js:127` (`deriveCache.get('status')`), `reconciler.js:~219` (spawnSync login-shell bash in `defaultLedgerEmit`), `server.js:1673-1674` (GET `/api/reconciler` → `reconciler.check(stateLib, cache, ...)`), `auditor.js:164` (top-level `require('./derive-cache.js')`), bashBin/spawnEnv consumers at `inbox-routes.js:232`, `requests-routes.js:447`, `roadmap-routes.js:2240`, `server.js:1153-1154` (also destructures `killTree`), `web/cockpit.selftest.js:180-182` (R28 asserts derive-cache.js file content), `maintenance-pane.selftest.js:69-72` (require-cache bust list names derive-cache.js).
- Grounding sweep at worktree root `master@2afa84fc` (r1; line citations below re-anchored to 87ddda29 at r2): `neural-lace/workstreams-ui/server/derive-lib.js` (full, 1,689 lines, two passes), `derive-cache.js` (full, 612 lines), `state-watch.js` (full, 221 lines), `config/projects.js` (full, 276 lines), `completion-oracle.js` (lines 1–100: header + class resolution — targeted read), `plan-parse.js` (lines 1–120: header/API contract — targeted read), `roadmap-routes.js` (targeted: header 1–400, buildRoadmapTree/handle 1857–2056, grep-verified sections for discoverPlanFiles/derivePlanRootNode/buildWaitingOnYouMap), `server.js` (targeted: route table via structural grep, handler section 1200–1440, pane endpoints 1560–1814 via grep, cache wiring), `inbox-routes.js` (structural grep: reader vs writer split).
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
canonical-repo resolver that consumes the estate's install-refreshed pin (`~/.claude/local/
nl-repo-path`, the launcher's own chain) and falls back to a spawn-free `.git`-pointer-file
dereference, and the seconds-scale latency (D2) is fixed by deleting the `nl <sub> --json`
shell-outs in favor of in-process readers (most of which already exist in this codebase). Sources that are inherently snapshots produced
elsewhere (doctor cache, costs cache, deploy evidence, peer ledgers) are the one place staleness
survives — and there it is always rendered with its age, never as current.

## 1. Problem statement (evidence-anchored)

**D1 — wrong-copy reads (PROVEN; partially fixed on master since r1).** Pre-fix,
`derive-lib.js:71-73` `mainRepoRoot()` returned `projects.selfRepoRoot()` —
`config/projects.js:21-24` computes `path.resolve(__dirname,'..','..','..')`, i.e. **the repo
containing the running server's own files**. The operator runs the cockpit from the worktree
`~/claude-projects/workstreams-ui-server` (branch ws-ui-server-stable, 36 commits behind master at
incident time). Consumers: `roadmap-routes.js:327-331` (`planScanRoot()` →
`deriveLib.mainRepoRoot()`), plus `server.js:296-500` (NEEDS-YOU.md, operator-todo.md, backlog.md
resolve through the same function). Result observed twice on 2026-08-04: the cockpit rendered
"11/25 tasks done" with total confidence while master's plan file said 24/25 — **no staleness
signal of any kind**. A hand-sync fixed it for hours, then it rotted again. **Master has since
merged ec4be5a2** (`derive-lib.js:109-152` at 87ddda29): a worktree→canonical redirect via two
`git rev-parse` spawns (process-lifetime memoized, `gitFieldSync`) plus a `scan_provenance`
staleness signal (roadmap-routes.js:82, :2193). That closes the worktree case but carries two
residuals this design removes: (a) `gitFieldSync` returns `''` on any spawn failure or missing git
binary, and `deriveCanonicalRoot(self,'','')` then **silently returns self** — a fail-open that
re-opens D1 on any git-less or spawn-broken environment; (b) the silent `process.cwd()` catch-arm
survives at `derive-lib.js:150-152`. PROVEN spawn-free alternative mechanism: the worktree's
`.git` is a plain file containing
`gitdir: <home>/claude-projects/neural-lace/.git/worktrees/workstreams-ui-server` (re-verified
2026-08-04) — recoverable with one `fs.readFileSync`, no git dependency. And the estate already
maintains an **install-refreshed canonical pin** this codebase never consulted:
`~/.claude/local/nl-repo-path` (exists on this machine, POSIX form `/c/...`), rewritten on every
install run (install.sh ~:1539 — "a RESOLVED VALUE ... safe — and necessary — to overwrite on
every install run"), read by `nl_repo_root()` (hooks/lib/nl-paths.sh:60-80, NL_REPO_ROOT env
first) and named in the cockpit launcher's own resolution order (ensure-cockpit.sh:63) — the
chain the server must share (DEC-3).

**D2 — derive-on-read behind subprocesses (PROVEN).** `derive-cache.js` has zero disk persistence
(grep: no writeFileSync/snapshot anywhere in the module), so every cold start serves
`{data:null, rc:null}` (derive-cache.js:363-365, server.js paneResponse loading state) until the
first refresh cycle completes — and that cycle is subprocess-bound: `nl status --json` measured at
~77 s (derive-cache.js:172-175, pinned timeout 180 s), `nl backlog --json` at 80–258 s
(derive-cache.js:157-171, default timeout 360 s), login-shell bash spawns measured at 94 s and
119 s worst-case on this machine (derive-lib.js:659-662). The G2 chain validation measured
5.7–9.6 s from per-entry git-through-bash spawns (dispatcher measurement, 2026-08-04; consistent
with the per-spawn costs above). Meanwhile the actual data is small: the six panes' and the
roadmap's entire first-party input set reads in-process in tens of milliseconds (see Inputs).
**The latency is subprocess cost, not derivation cost** — PROVEN by the measurement pair (77 s
shelled vs 12 ms direct for strictly more bytes than the status pane needs).

**Corrective to the brief's framing (PROVEN, matters for scoping):** `GET /api/roadmap` is
*already* a per-request, in-process derivation — `roadmap-routes.js:2286` calls
`buildRoadmapPayload()` (:2175) synchronously per request; `buildRoadmapTree()` (:2050) does pure
fs reads. The A6 pin "no child-process spawn on any GET path" already exists as reviewed precedent
(completion-oracle.js:27-28, 53-55). So D1 is a **root-resolution** defect, not a caching defect,
and D2 lives in the **pane layer** (DeriveCache's six subcommands) plus two GET-path stragglers:
`derive-lib.js classifySessions` (:619) spawns login-shell bash with a 180 s budget on the
ask-detail GET path, and `GET /api/reconciler` (server.js:1673-1674) both consumes cache data
(reconciler.js:127) and can fire a login-shell spawnSync from `defaultLedgerEmit`
(reconciler.js:~219) when drift is detected. This design therefore generalizes what
`/api/roadmap` already does right, rather than inventing a new architecture.

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
| DEC-3 | **Canonical repo root resolved by one function, `canonicalRepoRoot()`, sharing the launcher's exact chain: (1) `NL_REPO_ROOT` env — the SAME variable `nl_repo_root()` and ensure-cockpit.sh:63 honor first, so launcher and server can never resolve differently; (2) the install-written pin `~/.claude/local/nl-repo-path` — first line, CR/whitespace-trimmed, POSIX→win32 normalized (`/c/...` → `C:/...` on win32; the live file holds the POSIX form), dir-exists-checked, mirroring nl-paths.sh:60-80's own parsing; (3) `selfRepoRoot()` dereferenced through a `.git` pointer *file* (`gitdir: <main>/.git/worktrees/<name>` → `<main>`, one fs read, no git spawn — REPLACES ec4be5a2's two `gitFieldSync` spawns while KEEPING its pure `deriveCanonicalRoot()` decision function and selftest series 22.x, now fed from the fs read); (4) `selfRepoRoot()` when `.git` is a directory. Unresolvable → named failure; the `process.cwd()` catch-arm (derive-lib.js:150-152) and ec4be5a2's spawn-failure→self fail-open are both deleted.** `ROADMAP_PLAN_SCAN_ROOT` stays exactly where it is (roadmap-routes.js:331 / inbox-routes.js's twin) as the roadmap-layer test override — it short-circuits BEFORE this resolver and is unchanged. **The r1 idea of a `config/projects.json` `neural-lace` pin is REJECTED**: it would be a second canonical pin that nothing refreshes — install.sh rewrites nl-repo-path on every run, nothing rewrites projects.json — i.e. D1's defect class relocated to the config layer. projects.json remains what it is today: the docs-browser project map, not a root pin. | The estate already HAS a maintained pin; the r1 survey missed it (harness review C1) — consuming it beats inventing a rival. Pin-first also makes the resolver correct on a machine where the server runs from a plain stale *clone* (`.git` is a directory — the r1 pre-mortem's worst case): the pin outranks self-detection. The fs-read dereference stays as the no-pin fallback (fresh machine pre-install) because it fails LOUD, whereas the merged git-spawn form fails OPEN to self on spawn failure (§1 D1 residual a). `register-path`/`active-repos.txt` re-checked and still rejected (single-purpose pointer; PR-health slug list). | Swap one function body; consumers already call through `mainRepoRoot()` (derive-lib.js exports). Normalization is ~5 lines mirroring an existing bash parser. Reverting to the merged git-spawn resolver is one `git revert` of the M1 commit; ec4be5a2's tests are kept so the revert lands on a still-tested body. |
| DEC-4 | **The six DeriveCache panes migrate per-pane to in-process readers; where the derivation grammar genuinely lives in bash (`od_harness_health` gate fold, `od_sessions` composition), the Node port ships only behind a parity selftest that runs BOTH implementations on the same fixture** — never a frozen expected-output file. | Most "ports" are not ports: backlog already has a full in-process parser (server.js:608 `parseBacklogRows` — the 258 s `nl backlog` shell-out duplicates a reader that runs in ms); needs-me already has one (inbox-routes.js `buildInboxPayload`); costs/doctor are direct reads of materialized JSON caches. Only health and the sessions half of status are real grammar ports — the "third grammar" hazard derive-lib.js:200-207 and state-watch.js:19-28 warn about — and the parity oracle converts that hazard from silent drift into a pinned, breakable contract. | Per-pane: each migration is its own commit deleting its `SUBCOMMANDS` entry; reverting one pane is one `git revert` re-adding the entry while DeriveCache still exists (pre-M4). Post-M4, reverting a port means restoring the module from history — priced, and why parity tests land in the SAME commit as each port. |
| DEC-5 | **`DeriveCache` is deleted at M4 (the module, its six shell-out subcommands, timeout/lane/anti-entropy machinery, `isLobotomized`); `bashBin`/`spawnEnv`/`killTree` are NOT deleted — they RELOCATE to a small `server/spawn-util.js` (a move, not an add: net module count still −1 vs today, +util −derive-cache), and every consumer re-points per the §7 M4 disposition table. `state-watch.js` is retained and reduced to the SSE change-notifier.** | The cache's defensive apparatus exists to manage subprocess pathology (its header cites four incidents); with zero read-path spawns there is nothing left to defend. But the surviving write-path/exception spawns (DEC-6) still need the environment hardening and the tree-kill on timeout — r1 slated `killTree` for deletion while DEC-6c retained callers that use it (server.js:1154 destructures it today): that contradiction is resolved by relocating all three helpers together. state-watch's fence (spawn cost scales with change rate, not clock) is *honored more deeply* — spawns now scale to zero on reads — and its watch list is exactly the right trigger list for "tell open browsers to refetch". | DeriveCache: restore from git history (self-contained file + selftest). spawn-util extraction: mechanical, reverted by re-pointing imports. state-watch repurpose: one-commit revert. |
| DEC-6 | **Five named subprocess exceptions survive, none timer-driven:** (a) *shipped* — one direct `git.exe log` spawn per request (93 ms measured; no bash, no login shell, no jq), result stamped `derived_at` and rendered with age; (b) *why-drawer* — on-demand single spawn per operator click (unchanged); (c) *all POST write delegations* to ask-registry.sh / needs-you.sh (one-writer discipline, unchanged); (d) *scan_provenance's* TTL-bounded, request-triggered direct-git staleness probes (merged in ec4be5a2, ABSORBED — see REQ-A8); (e) *reconciler drift-emit* — `defaultLedgerEmit`'s signal-ledger append (reconciler.js:~219) fires only when drift is actually detected on `/api/reconciler` (rare by construction; the no-drift path spawns nothing) — retained as-is because the signal-ledger's writer is a bash lib (one-writer discipline; a Node-side append would fork the write grammar), flagged for a future queue-off-GET refinement. `classifySessions`' GET-path bash spawn (derive-lib.js:619) is deleted, replaced by the age-only `classifyHeartbeatAge` already in derive-lib. | git history has no Node-stdlib reader; reimplementing git is absurd; 93 ms direct-spawn is inside budget for the one pane needing it. The login-shell tax (94–119 s worst case) is what must never be paid on a read — direct binary spawn does not pay it; (d)/(e) are bounded by TTL and by drift-rarity respectively, and both are named here so REQ-A5's spawn-recording selftest can pin the exception set exactly. | Each exception is one function; converting shipped to a port, or queueing (e) off the GET path, is additive later. |
| DEC-7 | **Fail-loud contract: every payload carries a `sources[]` block** (per store: `{name, path, ok, reason?, benign_empty?, corrupt_rows, read_ms, snapshot_ts?}`); any `ok:false` renders a named error state in the affected pane — never an empty list, never last-known-good, never a silent fallback. | Extends three precedents already in this codebase to ALL sources uniformly: `listRawHeartbeatsResult`'s three-state contract (derive-lib.js:686-707), `readNeedsYouLedgerItems`' three-state contract (inbox-routes.js:130-168), roadmap's `ok:false`-renders-error C4 rule (roadmap-routes.js:2290-2293). Also upgrades `readJsonlLines`' silent corrupt-row skip (derive-lib.js:212-220) to a *counted* skip. | Additive envelope field; removing it is deleting a field. The behavioral change (no last-known-good) is the named sacrifice — reversing THAT means re-growing a cache, priced at DEC-2. |
| DEC-8 | **Staleness is unrepresentable for first-party stores and age-labeled for second-party snapshots.** First-party (all `~/.claude/state/*` + canonical-checkout files): the payload is a pure function of reads performed inside the request; `generated_at` == read time by construction; there is no stored derived state to go stale. Second-party (doctor-cache.json, obs-costs-cache.json, deploy evidence, remote-ledgers, maintenance snapshots): rendered with their own `snapshot_ts` age, and past a per-source threshold rendered in a degraded "as of <age>" state — never as current. | This is the honest resolution of the operator's "no possibility of inaccuracy": achievable where we read the origin, impossible where the origin is itself a snapshot — so label it, following the A3c raw-timestamp precedent (derive-lib.js:709-722: never ship a baked classification across a time boundary; ship the timestamp and let the reader classify by age). | Threshold values are env-tunable constants; the rendering contract is client-side and revertible per pane. |
| DEC-9 | **Patch reconciliation, re-verified against master@87ddda29 (r2 — two of r1's four "in-flight" items had ALREADY MERGED):** canonical-root+staleness → **MERGED as ec4be5a2**; disposition is now REPLACE-the-body, not fold-in: M1 swaps its git-spawn resolution for DEC-3's pin-first fs-read chain, deletes its cwd fallback and spawn-failure fail-open, KEEPS its `deriveCanonicalRoot` pure function + selftest 22.x series + its `scan_provenance` signal (absorbed by REQ-A8, per OD-002 absorb-don't-duplicate). Row-layout/verification-stage chips → **MERGED** (fa4b924d, 3c669d90, plus the follow-ons 3c93bc15 pid-aware liveness and 1d16834b/d0af551d dispatch attribution) — no action owed; the one obligation stands: chips consuming deploy evidence adopt DEC-8's age labels when source #16 lands. Snapshot-persistence → **DISCARD holds** (re-verified: verifier-REFUTED, never merged — nothing in 2afa84fc..87ddda29). Deploy-verified oracle → **KEEP, still in flight** (re-verified: 6ac88bce is NOT an ancestor of 87ddda29; lives in worktree-wf_b0c65996-356-4); it produces second-party source #16 and MUST stamp `snapshot_ts`. | OD-010: every item dispositioned explicitly, against the CURRENT tree — r1's dispositions were written against a base that moved (harness review M1), and stale dispositions are how an orchestrator merges a conflict blind. | Each disposition is per-worktree/per-commit; the REPLACE in M1 is one commit reverting cleanly onto ec4be5a2's still-kept tests. |
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

`canonicalRepoRoot()` lives beside the merged resolver in `derive-lib.js` (where
`resolveCanonicalRepoRoot` sits today) and is what `mainRepoRoot()` returns. Chain per DEC-3,
identical to the launcher's (`nl_repo_root()` / ensure-cockpit.sh:63): **(1)** `NL_REPO_ROOT` env;
**(2)** `~/.claude/local/nl-repo-path` — first line, CR/whitespace trim, POSIX→win32
normalization (`^/([a-zA-Z])/` → `$1:/` on win32; the live file holds `/c/...`), must name an
existing directory; **(3)** fs-read worktree dereference: read `<selfRepoRoot()>/.git`; if it is a
**file** matching `/^gitdir:\s*(.+?)[\\\/]\.git[\\\/]worktrees[\\\/]/`, the canonical root is the
captured path (feeds the KEPT pure `deriveCanonicalRoot()` so ec4be5a2's selftest 22.x series
keeps passing against the same decision logic, now with fs-derived inputs instead of
`git rev-parse` output); applied recursively once — a second hop is a config error and fails loud;
**(4)** `selfRepoRoot()` when `.git` is a directory. The same dereference applies to an ask's
cross-repo `repo` field before plan resolution, so a registry record pointing at a worktree lands
on that repo's main checkout. Unresolvable (no `.git`, pin naming a nonexistent dir at every
step) is a **named resolution failure** rendered per §4.4 — the merged `process.cwd()` catch-arm
(derive-lib.js:150-152) and the `gitFieldSync`-failure→self fail-open are both deleted.
**Launcher/server divergence is impossible by construction**: both sides read the same env var
then the same pin file; steps 3–4 only fire where the launcher chain also falls through
(pin absent — i.e. pre-install fresh machines), and there the fs dereference fails loud rather
than open.

*Checkout freshness (the residual R-class staleness):* even the canonical checkout can sit behind
origin/master. The merged `scan_provenance` signal (ec4be5a2: roadmap-routes.js:82 contract,
:2193 producer; TTL-bounded `gitInfoCache`, derive-lib.js:193-205, request-triggered — never a
timer) already surfaces `{root, resolved_via, head_sha, behind_origin_master, ...}` — it is
ABSORBED as this design's freshness signal (REQ-A8) and its bounded direct-git probes are DEC-6
exception (d). Its `resolved_via` field extends to name which DEC-3 step resolved the root.

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

**M2 interim honesty for cache-backed panes (harness review M2):** until a pane migrates in M3,
the server has never read that pane's underlying stores, so a store-level `sources[]` block for it
would be a fabrication. Interim shape: each unmigrated pane carries exactly ONE cache-level entry
— `{name: 'derive-cache:<sub>', class: 'S', path: '(in-memory cache, nl ' + sub + ' --json)',
ok: entry.rc === 0, reason: entry.stderr_tail || null, snapshot_ts: entry.derived_at,
corrupt_rows: null, read_ms: null}` — which is also *taxonomically* honest: a cache entry IS a
second-party snapshot under DEC-8, so it gets the age label like any other S-class source. Each
M3 migration replaces that pane's single cache-level entry with its real store-level entries in
the same commit.

**M4 consumer dispositions (harness review C2 — the sweep lives HERE, not at build time; every
row verified at 87ddda29):**

| Consumer (site) | What it takes from derive-cache today | M4 disposition |
|---|---|---|
| `server.js:35` (`DeriveCache`, `runWhy`), `:158` (instance) | the cache itself + why-drawer | cache instance deleted; `runWhy`'s on-demand spawn (DEC-6b) moves to `spawn-util.js` alongside its helpers |
| `server.js:1153-1154` | `bashBin`, `spawnEnv`, **`killTree`** (ask-registry lifecycle POST) | import from `spawn-util.js`; killTree relocates WITH the helpers (DEC-5) — write-path timeouts still tree-kill |
| `reconciler.js:127` (via `server.js:1673-1674`, GET `/api/reconciler`) | `deriveCache.get('status')` data as its drift oracle | oracle input re-pointed to the M3 sessions fold's in-process result (REQ-B4) — same data, no cache; its `oracle_unavailable` branch keys off the fold's `sources[]` ok instead of `rc` |
| `reconciler.js:~219` (`defaultLedgerEmit` spawnSync) | `bashBin`/`spawnEnv` | import from `spawn-util.js`; the spawn itself is DEC-6 exception (e) — drift-only, rare |
| `auditor.js:164` (top-level require) | `bashBin`, `spawnEnv` | import from `spawn-util.js` — without this, M4 deletion is a boot crash (top-level require of a deleted file) |
| `inbox-routes.js:232`, `requests-routes.js:447`, `roadmap-routes.js:2240` | lazy `require('./derive-cache.js')` for `bashBin`/`spawnEnv` (POST write delegations) | import from `spawn-util.js`; behavior byte-identical (DEC-6c) |
| `derive-lib.js:619` (`classifySessions`) | lazy require for `bashBin`/`spawnEnv` | function DELETED outright (REQ-A5) — no re-point needed |
| `web/cockpit.selftest.js:180-182` (R28) | asserts derive-cache.js **file content** (timeout-override strings) | R28 RETIRED in the M4 commit — its subject is deliberately deleted; a content assertion on a removed file is not a regression net, it is a tombstone |
| `maintenance-pane.selftest.js:69-72` | `require.resolve('./derive-cache.js')` in its cache-bust list | line dropped in the M4 commit (`require.resolve` on a missing file throws) |
| `server.selftest.js` (S7/S22/S22b and every scenario pinning `runNl`/refresh-cycle behavior) | black-box pins on cache behavior | dispositioned as a class: each M3 pane commit retires/replaces the scenarios for that pane; M4's Files-to-Modify list MUST name all four selftest files so the scope gate holds the retirements to the same commit as the deletions |

### 4.4 Fail-loud contract (observable behavior per failure mode)

| Failure | Observable behavior (WHAT/WHY/FIX per OD-004) |
|---|---|
| Store unreadable (EACCES, ENOTDIR, mid-read race) | `sources[]` entry `ok:false` + reason with errno; the consuming pane renders a named error card: "ask-registry.jsonl could not be read (EACCES) at `<abs path>` — cockpit data for asks is unavailable, not empty. Fix: check file permissions / retry." HTTP 200, `ok:false` scoped to the affected block. Never `[]`, never last-known-good. |
| Store absent, never written (ENOENT on a state dir) | `benign_empty:true` — rendered as the honest empty state ("no sessions have ever heartbeated on this machine"), visually distinct from failure. (Existing three-state contracts, DEC-7, now uniform.) |
| Canonical root unresolvable | `/api/roadmap` and every R-class consumer return `ok:false` naming each resolution step attempted and its result; client renders error + Retry (existing C4 behavior, roadmap-routes.js:2290-2293). |
| One plan file unreadable | Existing per-root `unknown`/`scanIssue` handling (roadmap-routes.js:~417) — kept verbatim; the rest of the tree still renders. |
| Corrupt JSONL row(s) | Row skipped AND counted: `corrupt_rows: N` in `sources[]`; N>0 renders a warning chip on the consuming pane ("3 unreadable records skipped in signal-ledger.jsonl"). Upgrades today's silent skip (derive-lib.js:212-220). |
| Second-party snapshot older than threshold | Value rendered WITH age ("doctor: green — as of 4 h ago") in degraded styling; never bare. Missing entirely: named "never produced on this machine" state. |
| Shipped git spawn fails | Pane renders the spawn's rc/stderr verbatim as an error card (never empty), `derived_at` of the last successful run NOT shown — there is no last-known-good (DEC-7). |

*Client-render verification mechanism for every row above (harness review minor):* the
established `web/cockpit.selftest.js` convention — DOM-free source-text regex over the client
modules (its own header: "source-text regex, not a headless-browser DOM check", :200, :368) —
each §4.4 row's client half is pinned by a regex asserting the rendering branch exists and names
the state (error-card string, `benign_empty` branch, age-chip class), alongside the server-side
payload fixture assertions in the per-module selftests.

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
| REQ-A1 | MUST | `canonicalRepoRoot()` implements DEC-3's launcher-identical four-step chain (`NL_REPO_ROOT` env → `~/.claude/local/nl-repo-path` with POSIX→win32 normalization + trim + exists-check → `.git`-file worktree dereference → self root when `.git` is a directory), REPLACES the merged ec4be5a2 resolver body (keeping `deriveCanonicalRoot` + selftest 22.x), and every R-class consumer (plan scan, backlog.md, NEEDS-YOU.md, operator-todo.md, cross-repo ask `repo` fields) resolves through it. Verify: selftest fixtures — (i) a pin file in POSIX form resolves to the win32 path and OUTRANKS a `.git`-file worktree self; (ii) a synthetic worktree with no pin dereferences to its main checkout; (iii) `NL_REPO_ROOT` outranks the pin (parity with nl-paths.sh:60-80's order); plus livesmoke: server started from `~/claude-projects/workstreams-ui-server`, `GET /api/roadmap` task counts equal a direct `plan-parse` count of the canonical checkout's same plan file. |
| REQ-A2 | MUST | Regression pin for D1's exact shape AND ec4be5a2's residual fail-opens: a worktree of the same repo NEVER resolves to itself; an unresolvable root NEVER silently falls back. Verify: dedicated selftest cases asserting (i) `canonicalRepoRoot()` from inside a `.git`-file worktree ≠ the worktree path; (ii) the `process.cwd()` catch-arm (derive-lib.js:150-152) is gone — unresolvable returns a named failure, never cwd; (iii) the git-spawn-failure→self path is gone by construction (no git spawn exists in the resolver to fail). |
| REQ-A3 | MUST | Per-request read-through: no cross-request cache of any derived payload, no snapshot persistence, no invalidation logic anywhere on a GET path; `generated_at` == request time. Verify: selftest flips one checkbox byte in a sandboxed plan file between two GETs with no restart/no trigger; the two payloads differ. Grep-verify: no `writeFileSync` of derived state, no module-scope derived-payload variable in the read modules. |
| REQ-A4 | MUST | Every read payload carries the `sources[]` block (name, path, ok, reason, benign_empty, corrupt_rows, read_ms, snapshot_ts, class G/R/S) and the client renders §4.4's states: store-failure → named error card (never empty/stale), benign-empty → distinct honest-empty, corrupt rows → counted warning. During M2–M3, unmigrated panes carry the single cache-level entry per §4.3's M2 interim shape, upgraded to store-level in each pane's own M3 commit. Verify: server side — selftest per failure mode (chmod/rename a sandboxed store, assert the payload's named state; corrupt-row fixture asserts the count surfaces); client side — `web/cockpit.selftest.js` source-text regex per §4.4's named convention (one assertion per rendered state class). |
| REQ-A5 | MUST | Zero `child_process` use on any GET path except the DEC-6 named exceptions — {shipped direct-git, why-drawer, scan_provenance TTL probes, reconciler drift-emit} — and zero login-shell bash on ANY GET path (the drift-emit's current `-lc` form is grandfathered until its queue-off-GET refinement, named in DEC-6e). Includes deleting `classifySessions` (derive-lib.js:619) in favor of `classifyHeartbeatAge`. Verify: selftest boots the server with a `child_process` wrapper that records call sites, exercises every GET route (drift and no-drift reconciler fixtures both), asserts the recorded set ⊆ the DEC-6 exception set; plus static grep in CI/selftest over the server modules. |
| REQ-A6 | MUST | Budgets held and re-derivable — with the honesty note (harness review minor) that the 50 ms figure is **bench-verified at build time only**: the standing selftest tripwire is a machine-independent 2 s ceiling, and the continuous observability is `sources[].read_ms` riding EVERY production payload (drift shows up in the payload the operator is already looking at, not in a silent gap between bench runs). Targets: `/api/roadmap` p95 ≤ 50 ms warm, migrated-pane burst ≤ 250 ms warm, shipped ≤ 300 ms, at current corpus scale. Verify: `read-bench.js` (seeded from this design's committed measurement script, `docs/designs/cockpit-read-through-evidence/measure-seed.js`) ships in the implementing plan with its output cited in task evidence; selftest asserts the 2 s tripwire AND that `read_ms` is populated on real payloads. |
| REQ-A7 | MUST | Second-party snapshots (doctor, costs, deploy evidence, remote ledgers, maintenance, and — interim — the M2 cache-level entries) always render with their own `snapshot_ts` age and degrade visibly past per-source thresholds; never rendered as current. Verify: fixture with an aged `snapshot_ts` asserts the age field in the payload and the degraded flag past threshold. |
| REQ-A8 | SHOULD | Checkout-freshness signal for R-class stores: ABSORB the merged `scan_provenance` mechanism (ec4be5a2 — roadmap-routes.js:82/:2193, TTL-bounded request-triggered `gitInfoCache`, derive-lib.js:193-205) as-is rather than building the r1 FETCH_HEAD-mtime alternative (OD-002: it exists, it is richer — `behind_origin_master` beats an mtime proxy — and its bounded git probes are DEC-6 exception (d)); extend its `resolved_via` to name the DEC-3 step that resolved the root; surface its age/behind fields on every R-class `sources[]` entry, not only the roadmap payload. Verify: existing scan_provenance selftests stay green; new case asserts `resolved_via` names the pin step when the pin resolves. |
| REQ-A9 | MUST | Corrupt-row counting replaces silent skipping in every JSONL reader used by the cockpit (`readJsonlLines` gains a counted variant; call sites migrate). Verify: fixture ledger with 2 corrupt rows → `corrupt_rows:2` in `sources[]`, fold output unchanged for valid rows. |

### Phase B — de-subprocess the panes; delete the cache (M3–M4)

| REQ | Level | Requirement (verification inline) |
|---|---|---|
| REQ-B1 | MUST | Backlog pane serves the existing in-process parser's output (server.js `parseBacklogRows`/`buildBacklogPayload`) against `canonicalRepoRoot()`; the `nl backlog --json` shell-out and its 360 s timeout are deleted. Verify: selftest asserts `/api/pane/backlog` renders from a fixture backlog.md with zero spawns; live: pane populates in <1 s from cold where it previously took 80–258 s. |
| REQ-B2 | MUST | Needs-me pane serves the inbox ledger reader's output (inbox-routes' three-state read), deleting its shell-out. Verify: fixture ledger → pane payload with zero spawns; ledger-unavailable fixture → named error per REQ-A4. |
| REQ-B3 | MUST | Costs pane and the doctor half of status read their materialized caches (obs-costs-cache.json, doctor-cache.json) directly with `snapshot_ts` per REQ-A7, deleting their shell-outs. Verify: fixture caches → payload; absent cache → "never produced" named state. |
| REQ-B4 | MUST | Sessions/status composition folds heartbeats + signal-ledger bounded tail in Node, with a **parity selftest that executes BOTH `od_sessions` (bash, via the existing lib) AND the Node fold on one shared sandbox fixture and diffs the normalized output** — run in the selftest suite, not a frozen golden file. The reconciler's drift oracle (reconciler.js:127, today `deriveCache.get('status')`) re-points to this fold's result in the same commit (§4.3 M4 table). Verify: parity test green in the same commit as the port; the pane serves the Node fold with zero spawns; reconciler selftest passes against the fold-backed oracle. |
| REQ-B5 | MUST | Health pane: same parity-gated port for `od_harness_health`'s gate fold (bounded-tail ledger read, DEC-10). Until parity passes, the pane stays subprocess-backed AND renders its `derived_at` age per REQ-A7 (interim honesty). Verify: parity selftest as REQ-B4; interim state verified by the age field's presence. |
| REQ-B6 | MUST | Shipped pane: one direct `git.exe log` spawn per request against `canonicalRepoRoot()` (93 ms measured), no bash, no jq, result stamped `derived_at` and age-rendered. Verify: selftest with a fixture repo asserts single-spawn + payload shape; bench asserts ≤ 300 ms warm. |
| REQ-B7 | MUST | End state: `SUBCOMMANDS` empty → `derive-cache.js` deleted (module, anti-entropy timer, lanes, `isLobotomized`, `/api/refresh` derivation semantics); `bashBin`/`spawnEnv`/`killTree`/`runWhy`'s spawn plumbing RELOCATE to `server/spawn-util.js`; EVERY consumer in §4.3's M4 disposition table re-pointed or retired exactly as that table states (reconciler oracle re-point, auditor import, 3× lazy-require POST sites, classifySessions deletion, cockpit.selftest R28 retirement, maintenance-pane cache-bust line drop, server.selftest scenario class); `state-watch.js` `onTrigger` re-pointed to `broadcastRefresh` only. The M4 task's Files-to-Modify list MUST enumerate every file in that table. Verify: grep — no `require('./derive-cache` anywhere; server boots and serves every pane (the auditor top-level require is the boot-crash canary); all four selftest suites green post-retirement; the OD-002 scorecard in the task evidence counts net-negative modules/spawn-sites. |
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
- **D-07/OD-002 displacement ledger (net inventory change):** deleted — derive-cache.js (6
  shell-out subcommands, anti-entropy timer, 2 refresh lanes, isLobotomized detector),
  classifySessions' GET-path bash spawn, ec4be5a2's two resolver git spawns + cwd fallback, the
  snapshot-persistence patch (discarded pre-merge), `/api/refresh`'s derivation semantics,
  cockpit.selftest R28 + the retiring server.selftest cache scenarios. Relocated (not deleted) —
  `bashBin`/`spawnEnv`/`killTree`/`runWhy` plumbing → `server/spawn-util.js` (write-path/exception
  spawns still need the env hardening and tree-kill). Added — the DEC-3 resolver body (pin
  consumption + fs dereference), a counted-JSONL reader variant, a bounded-tail reader, 2 direct
  snapshot readers, 2 Node folds + 2 parity selftests, `read-bench.js`, the `sources[]` envelope.
  Net: −1 module (−derive-cache +spawn-util), −6 recurring spawn sites, −1 timer, −2 resolver
  spawns; additions are all passive readers/tests.

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
3. The stale-clone case now has a PRIMARY structural defense, not just the age chip: DEC-3's
   pin-first order (r2, harness review C1) means a copied checkout with a directory `.git` is
   outranked by the install-refreshed `nl-repo-path` pin on any machine that has ever run
   install.sh — step 4 (self-detection) only governs pin-less pre-install machines. REQ-A8's
   absorbed scan_provenance signal (already merged, so no longer at risk of being dropped as a
   SHOULD) remains the visible backstop, and the resolver's named-failure path (REQ-A2) refuses
   to guess when nothing resolves.
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
- OD-010 (disposition-everything) — all four r1 "in-flight" items re-verified against the CURRENT
  master and explicitly dispositioned, including the two that turned out already merged (DEC-9,
  §7); nothing left to age out.
- OD-016 (observability-equal-clarity) — `sources[]` is the machine-readable counterpart of every
  human-visible error/age chip; the same block serves both audiences (REQ-A4).
- OD-001 (no-wsl-dependency) — nothing here depends on WSL; pure Node fs + one direct git.exe
  spawn (DEC-6).
- OD-012 (standing-autonomy-reversible-work) — every decision above is priced reversible
  (Decisions table); no operator pause required; the one operator-taste item (age-chip thresholds)
  ships env-tunable rather than blocking.

## 7. Migration (no big-bang; every stage shippable and individually revertible)

- **M1 — resolver REPLACE (r2, against merged ec4be5a2):** swap `resolveCanonicalRepoRoot`'s
  body for DEC-3's pin-first chain (REQ-A1); delete the `process.cwd()` catch-arm and the
  spawn-failure fail-open (REQ-A2); KEEP `deriveCanonicalRoot` + selftest 22.x + `scan_provenance`
  (REQ-A8 absorb, `resolved_via` extended). One commit, reverting cleanly onto the kept tests.
  Interim state: everything else unchanged; the pin-first chain is live the moment the operator's
  server restarts on this commit.
- **M2 — fail-loud envelope:** `sources[]` + counted corrupt rows + three-state normalization
  (REQ-A4/A9) + snapshot age labels (REQ-A7). Unmigrated panes carry the single cache-level
  `sources[]` entry per §4.3's M2 interim shape (harness review M2) — never a fabricated
  store-level block for stores the server has not read. Interim: panes still cache-backed but
  every payload now carries honest truth-status at the granularity that actually exists; the
  client gains the error/age rendering it will keep.
- **M3 — pane migrations, one commit each, cheapest first:** backlog (REQ-B1) → needs-me (REQ-B2)
  → costs+doctor (REQ-B3) → sessions/status (REQ-B4) → health (REQ-B5) → shipped (REQ-B6), plus
  the classifySessions deletion (REQ-A5). Interim states: `SUBCOMMANDS` shrinks; un-migrated panes
  keep exact current behavior; both paths coexist without interference because each pane has
  exactly one backing at any commit.
- **M4 — deletion + relocation, executed exactly per §4.3's consumer disposition table (REQ-B7):**
  DeriveCache + timer + `/api/refresh` semantics + lobotomy detector removed; spawn helpers
  relocate to `spawn-util.js` with all seven consumer sites re-pointed; reconciler oracle
  re-pointed to the REQ-B4 fold; R28 + the maintenance-pane cache-bust line + the cache-pinned
  server.selftest scenarios retired in the same commit; state-watch re-pointed to
  `broadcastRefresh`. Interim: none — this is the end state.
- **Reconciliation for the orchestrator (DEC-9, re-verified at 87ddda29):**
  canonical-root+staleness → ALREADY MERGED (ec4be5a2); the owed action is M1's REPLACE above, not
  a merge; snapshot-persistence worktree → DISCARD (verifier-REFUTED, never merged — do not merge;
  salvage nothing, its premise is obsolete at a 12–25 ms read); row-layout/verification-chips →
  ALREADY MERGED (fa4b924d, 3c669d90; follow-ons 3c93bc15, 1d16834b/d0af551d) — nothing to
  reconcile; standing obligation only: chips adopt REQ-A7's age field when deploy evidence lands;
  deploy-verified-oracle worktree (6ac88bce, wf_b0c65996-356-4) → still in flight, MERGE when
  ready (its output is source #16; require it to stamp `snapshot_ts`).

## Review Chain

authored-by: design-author (model: fable)
design-reviews:
  - reviewer: architecture-reviewer  verdict: PENDING  record: docs/reviews/ (to be created on review)
  - reviewer: harness-reviewer       verdict: PENDING  record: docs/reviews/ (to be created on review — harness surface: OD-006's declared surface covers neural-lace/workstreams-ui/**, and the parity contract touches the estate's nl oracle conventions)
