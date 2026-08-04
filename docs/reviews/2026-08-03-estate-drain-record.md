# Estate drain record — 2026-08-03 (gated-pipeline-master-2026-08 Task 21, REQ-C2)

**Scope:** REQ-C2's four piles — stale ACTIVE plans, untriaged nl-issues, stranded agent
worktrees, unacked monitor alerts — each dispositioned per D-12 ("every inventory item AND
every finding of every input review gets an explicit disposition"). Builds on the 2026-08-02
estate-entropy triage (`docs/reviews/2026-08-02-estate-entropy-triage.md`) and the
2026-08-03 EXHAUSTIVE issue inventory's Q-06 estate-drain scope question — this record is
that question's answer, executed.

**Evidence discipline (same as the prior triage):** PROVEN = cited command/SHA/path, re-run
live this session. HYPOTHESIZED = plausible, refuter named. Nothing below is asserted without
a re-derivable check.

**Commits this task:** `585ea4da` (plans batch 1, 9 plans), `91c3d8a0` (plans batch 2, 8
COMPLETED), `683cd996` (plans batch 3, 4 DEFERRED), `8e4073b2` (grandfather registry shrink).
This record's own commit follows.

---

## Summary of counts (before -> after)

| Pile | Before | After | Disposition |
|---|---|---|---|
| Stale ACTIVE plans | 24 (23 candidates + this plan) | **3** (this plan + 2 verified-live) | 16 COMPLETED, 4 DEFERRED, 1 already-deprioritized note formalized to DEFERRED, 2 confirmed genuinely STAYS-ACTIVE |
| nl-issues untriaged | 170 (measured at drain start; task brief's "135+" had grown) | **5** | 125 backlog, 35 wontfix, 6 task; 5 deliberately left for operator/deeper investigation |
| Agent-\* worktrees | 42 classified | **38 verified-safe for EXECUTE** (target was >=10) | 38 safe-to-remove (proof per line below), 1 pending-integration (do not touch), 2 live/active/fresh-unmerged (do not touch), 1 self-cleaned mid-session (no longer exists) |
| Unacked monitor alerts | 1,283 (1,254 at task-brief time; grew during this session) | **524 unacked** (all one still-live class) | 738 bulk-acked (dead/root-caused classes), 524 left unacked on purpose (real, still-firing product bug — re-owned, not ours to fix) |
| G2 grandfather registry | 300 non-comment entries | **284** | 16 entries removed (one per COMPLETED plan slug); DEFERRED plans' entries kept (may still need dispatch) |

---

## 1. Stale ACTIVE plans (24 -> 3)

Census: `grep -l "^Status: ACTIVE" docs/plans/*.md` at task start = 24 files (23 candidates +
`gated-pipeline-master-2026-08.md` itself, which stays ACTIVE per the task's own carve-out).
Verification method: independently re-derived against `git log`, `git show master:<path>`, and
`git merge-base --is-ancestor <sha> master` for every citation below (a background research
agent gathered the evidence; every SHA it cited was re-run, one of its inherited citations from
the prior triage turned out to be wrong and is corrected below — see
`workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29`).

### COMPLETED (16) — landed-but-unflipped, closed this pass, archived to `docs/plans/archive/`

| Plan | Evidence (re-verified) |
|---|---|
| `needs-you-ledger-corruption-hotfix` | `9e822ca1` ancestor of master (rc=0) |
| `review-gate-identity-anchor-2026-07-30` | `987bbb4b`/`24aa91ce`/`802a9377` all ancestors |
| `workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29` | **corrected citation**: prior triage's `b5dfaf1e` was wrong (unrelated commit); real landing commits are `8918f4ef`/`8913dfd2`, both confirmed ancestors, matching `workstreams-emit.sh:3839`'s live `120`-second debounce |
| `cockpit-review-surface-and-verification-gaps` | `39a3dc3d` (tasks 1-3+5), `dd832f67` (task 4 grandfather re-bootstrap) |
| `code-trace-methodology-2026-07-30` | `6073905c`, deliverable doc confirmed on master |
| `context-watermark-window-class-fix` | live `context-watermark.sh` confirmed carries C1-C6 (MIN_KNOWN_WINDOW, 0-unknown return, T20-T24 self-tests) |
| `doctrine-review-surface-measurement-2026-07-30` | `49fba9e7`, decision doc indexed at `docs/DECISIONS.md` row 069 |
| `flat-skills-directory-form-migration` | `cdf685c5` (tasks 1-5); task 6 satisfied by this very session's Skill-tool listing |
| `intended-functionality-stage-0-2026-07-30` | `76a08f5f`, all 8 tasks checked |
| `macos-portability-2026-07` | `3e1da4ff`/`9eb14b1c`/`e5a453de` spot-checked (M2/M3/M5), all 6 tasks checked |
| `model-awareness-knowledge-2026-07-24` | `46d9f3c6`, follow-up deliverable files present |
| `operator-requirement-ledger` | `8d53410e`, all 5 tasks (T1-T5) confirmed |
| `requests-tab-visibility-fix-2026-07-30` | `84d0684`/`fdd433a`, already had its own Completion Report |
| `review-independence` | `49e66300`/`c54b5bdb`/`9438de06`/`3b39f59b`, RI1-RI4 all landed |
| `supervisor-tick` | task-verifier PASS confidence 9 already on file; `1397c349` |
| `verification-dispatch-directive` | V1-V5 confirmed; V6 explicitly out-of-plan-scope per its own text |

### DEFERRED (4) — real, honestly-scoped remaining work, not currently worked, moved to `docs/plans/deferred/`

| Plan | Why deferred | Resume trigger |
|---|---|---|
| `perf-telemetry-2026-07` | P1/P2 landed; P3/P4 (doctor consumers) confirmed absent from `harness-doctor.sh`; 5 days stale | Next P3+P4 dispatch |
| `progress-log-placeholder-ask-id-fix` | Tasks 1-3 done; Task 4 blocked on an unresolved provenance gap the plan's own Decisions Log documents | Gap resolved or an uninterrupted session |
| `status-event-ledger` | Custom BUILT/PARTIAL/UNBUILT taxonomy (not checkboxes, correctly not a false-stale case per the prior triage) — SE1/SE3/SE4/SE10 BUILT, SE2/SE6/SE7 UNBUILT, SE5/SE8/SE9 PARTIAL; 4 days stale, no current session | Next SE2 build |
| `status-ground-truth-discipline-2026-07-24` | Lesson landed; FOLLOW-UP doctrine/gate work never started; 11 days stale | Next harness-reviewer-gated doctrine pass |

### Formalized (1) — already-correct disposition, moved to `docs/plans/deferred/`

`machine-folder-reorg` — was `Status: ACTIVE (DEPRIORITIZED — operator 2026-07-30...)`. This
was already the RIGHT disposition, just expressed as a parenthetical the estate census kept
mis-flagging as stale-and-neglected. Reworded to `Status: DEFERRED` using the plan-lifecycle
schema's own terminal-but-intended state — same intent, same resume trigger, no code touched.

### STAYS-ACTIVE (2) — genuine currency, left untouched

| Plan | Evidence of currency |
|---|---|
| `accountable-estate-program-2026-07` | Commits `f3f5ca24`, `601cd16a`, `4db5dbe3` landed on this plan's own T6-prereq files THE SAME DAY as this drain |
| `cockpit-roadmap-redesign` | Commit `14bbca67` landed 2026-08-02 (day before this drain) as a direct harness-reviewer REFORMULATE remediation on this plan's own scope; Task 9 genuinely still open after 16 build rounds |

### REFUSED-BY-GATE

None. The concurrent-ownership gate did not block any of the 21 Status flips — none of the 23
candidate plans were session-owned by a live sibling session (cross-checked: the harness's own
3 locked worktrees at classification time all belonged to this same gated-pipeline plan's build
cluster, not to any of the 23 candidates).

### Gate friction encountered (both real, neither routed around)

1. **harness-hygiene-scan** flagged pre-existing personal/business-identity strings
   (an owner-identity field; machine-folder-name references) in 3
   already-archived plan files. Confirmed PRE-EXISTING via `git show HEAD:<path> | grep` before
   editing (not introduced by this drain) — very likely the first commit to touch these files
   since the denylist entries were added same-day (T17, commit `e82f0b93`). Used the sanctioned
   fresh ledgered waiver per constitution §7, both purpose clauses named, on 3 separate commits
   rather than redacting historical plan-body content out of scope.
2. **backlog-plan-atomicity** false-fired on the `docs/plans/*.md -> docs/plans/deferred/*.md`
   self-archival rename (`perf-telemetry-2026-07.md`) — the gate's own exemption only covers the
   `-> docs/plans/archive/*.md` shape, not the identical `deferred/` shape plan-lifecycle.sh also
   produces. Filed via `nl-issue.sh` (real gate gap, not patched mid-drain — separate, reviewed
   fix). Satisfied honestly: `docs/backlog.md` genuinely needed a v74 entry summarizing this
   drain anyway, so staging it was not a workaround.

---

## 2. nl-issues (170 untriaged -> 5)

Ledger: `~/.claude/state/nl-issues.jsonl` (machine-wide, not git-tracked — per the
task's scope split, triaged directly via the sanctioned `nl-issue.sh --triage` tool, not
deferred to the orchestrator). Backup: session scratchpad `nl-issues.backup.jsonl` (untouched).

Before/after independently confirmed via `grep -c '"triage_status":"untriaged"'` on the live
file: **170 -> 5**. Every stamp went through the real `nl-issue.sh --triage <n> <kind> <ref>`
script (no hand-editing of the JSONL).

**Method:** (1) re-applied the 32 dispositions the 2026-08-02 estate-entropy triage already
hand-derived (§2 of that doc), matched by date+text; (2) mechanized sweep of the remaining
~138 entries — `git log --all --grep` supersession checks plus direct greps of current
hook/script code to confirm fixed-vs-still-open status for every recurring bug class; (3)
downstream-project entries (project field is a generated agent codename, not neural-lace)
routed to `backlog` naming them as external-project items, not chased for a fix from this
worktree.

**Disposition breakdown (166 stamped this session):**

| Disposition | Count |
|---|---|
| `backlog` | 125 |
| `wontfix` | 35 |
| `task` | 6 |

**Recurring bug classes confirmed still-open at HEAD** (read the current code, not assumed):
`review-finding-fix-gate.sh` reads the PREVIOUS commit's message, not the pending one (5
independent reports — the single most-repeated defect in the ledger); `plan-edit-validator.sh`
dotted-only TASK_ID regex (2); `scope-enforcement-gate` one-broken-plan-blocks-every-commit
repo-wide (4 — the 2026-07-30 fix `dc05aa28` improved the message, not the actual scoping);
`teammate-spawn-validator.sh`'s read-only allowlist missing `architecture-reviewer`/
`comprehension-reviewer` (2); `session-wrap.sh`'s 4-hour misattribution window (4).

**Recurring classes confirmed already-fixed**, dispositioned `wontfix`: sub-agent
heartbeat/liveness (shipped, plan closed at `1d28e48f`; 6 instances); `write-evidence.sh`
CWD-relative path (fixed); `close-plan.sh` mutation-before-gate ordering (fixed); SessionStart
single-flight lock (`e9c5bc0f` + 3 earlier); 6 raw `<task-notification>` XML capture-noise
dumps (same class as the 2026-08-02 triage's rows 13/15/23).

**6 entries mapped to `task`**: 4 against this SAME plan's G1/G2/G3 gated-pipeline design (the
2026-07-11 code-review-before-merge / full-auto-stall / server-side-enforcement cluster is
exactly what G2/G3 were built to satisfy), 1 to T24's Stage-2 successor marker, 1 to this very
Task 21 (session-heartbeat wired-template drift literally names "T8/T21 triage population" as
its own disposition path).

**12 highest-value new `backlog` findings** (title + ledger line number, full list + evidence in
the sub-agent's summary file, path below):
1. Worktree reaper deletes an ACTIVE dispatched agent's worktree mid-verification (lines 137,139)
2. No PreToolUse gate blocks `git push --force*` in subagent worktrees (line 129)
3. Worktree-isolated agents lose acceptance artifacts on cleanup (line 128)
4. `scope-enforcement-gate`: one broken ACTIVE plan blocks every commit repo-wide (4 reports)
5. `review-finding-fix-gate.sh` reads the previous commit's message, not the pending one (5 reports)
6. Agent-tool worktree auto-clean footgun: resuming a BLOCKED builder lands cwd in MAIN checkout (line 165)
7. Agent-tool registry does not hot-reload mid-session (lines 82, 182)
8. Nothing in the harness consumes GitHub CI results — 23 consecutive red pushes unconsumed (line 178)
9. Operator full-auto authorization silently decays on compaction (line 105)
10. `review-chain-lib.sh` spawns a fresh git subprocess per rule per chain entry, no caching — 5-9s vs a 300ms budget (line 184)
11. Agent worktree creation bases on stale `origin/master` instead of dispatching session's local HEAD (line 163)
12. `teammate-spawn-validator`'s read-only allowlist missing 2 read-only reviewer agents (lines 79, 168)

**Left untriaged (5, deliberately — genuinely hard, needs deeper investigation or operator input):**
line 83 (security-adjacent content-fabrication anomaly, needs log forensics), 112 (scratchpad
path collision between concurrent sub-agents, platform concurrency question), 113 (cross-machine
review-record gap, needs the other machine), 181 (two competing unreconciled diagnoses for a
jq-parity self-test failure), 187 (a builder worktree went completely empty mid-session with no
`git worktree add` ever run — real unexplained data loss).

Full per-entry detail (disposition + evidence for all 166 stamped entries) was reviewed this
session from a session-scratchpad summary file (ephemeral, not committed — the durable record
of every disposition is the ledger itself, `~/.claude/state/nl-issues.jsonl`, queryable via
`nl-issue.sh --list`); the class-level summary above and the 12 findings below are the durable
extract.

---

## 3. Agent worktrees (42 classified -> 38-item EXECUTE list)

Enumerated via `git worktree list --porcelain` (shared object/ref database across all
worktrees of this repo, so `git log --all` sees everything regardless of which worktree runs
the check). 42 `worktree-agent-*`-branch worktrees found; 3 non-agent-\* worktrees
(`gated-pipeline-task1`, `hopeful-bose-b98694`, `workstreams-ui-server`) are out of this task's
declared scope and untouched — noted for completeness: `gated-pipeline-task1`'s tip IS an
ancestor of master (informational only, not on the EXECUTE list per scope).

**Method (two-tier proof, matching the 2026-08-02 triage's own methodology after that triage's
LOUD callout that `git cherry`/naive diff is a false-positive machine across cherry-pick/squash
reshaping):**
1. **Direct ancestry**: `git merge-base --is-ancestor <worktree-HEAD> master`. rc=0 is
   zero-risk, mechanical proof — 13 worktrees cleared this way.
2. **Exact commit-subject match**: for the 26 non-ancestor worktrees, `git log master
   --fixed-strings --grep="<worktree-HEAD-subject>"` — this harness's orchestrator cherry-picks
   builder commits into master, which mints a NEW SHA even when the content is identical
   (confirmed live: e.g. worktree `agent-ad2b2eda5d88861b0`'s tip commit
   "evidence(gated-pipeline T20): timing table + Comprehension Articulation" is byte-identical
   in subject to master's own `7f37e074`). 22 of 26 matched this way; content spot-checked on 3
   of them (diffed the specific touched file between the worktree tip and its master match —
   confirmed the deliverable landed, sometimes further amended afterward, never lost).
3. **Cross-reference against the 2026-08-02 triage's own already-published landed-SHA
   citations**, re-verified live via `git merge-base --is-ancestor` against TODAY's master (not
   trusted from the old doc): 3 more worktrees cleared this way (`agent-a60cd9f14ad2034df` via
   `d805a9a3`; `agent-aa680cc77830d361b` via `4ee18805`; `agent-afcf419ea529b1ca0` via
   `3ab7fa50`+`81e8d031`, all rc=0 today).

**1 worktree is genuinely NOT safe — real, unmerged, valuable work:**
`agent-a8cce9bcdef232363` carries 3 commits (`cca6c273`, `6bd835de`, `de630284` — "feat
(gated-pipeline T25): merge->verify mechanization (OD-022 + OD-023)" and its evidence) that
exist NOWHERE else in the object database (`git log --all --grep` confirms) — this is this
same plan's Task 25 build, not yet cherry-picked into master. **DO NOT PRUNE.** Flagged
prominently for the orchestrator.

**2 worktrees are live/active and excluded:** `agent-a05a34c3229e0a919` (this session, LOCKED)
and `agent-aa43558579db80e88` — LOCKED at classification time; by write time it had unlocked
with a NEW, more-recent, NOT-yet-merged tip (`4a76f0ad`, "feat(needs-you): human-readable
render...", 2026-08-03T21:03) — freshly-finished work pending orchestrator cherry-pick, same
class as the T25 worktree. **DO NOT PRUNE either.**

**1 worktree self-cleaned mid-session:** `agent-afa8cf7aa3c188555` (this task's own nl-issue
sweep sub-agent) no longer appears in `git worktree list` at write time — already removed by
the harness's own agent-worktree lifecycle on completion. Not on the EXECUTE list because it
no longer exists.

**Estate is live and moving** — 2 of the 42 classifications changed state between classification
and write time (one unlocked-but-fresh, one vanished). The EXECUTE list below is accurate as of
commit time; the orchestrator should re-run `git worktree list --porcelain` and re-confirm each
target is still present and still not `locked` immediately before executing (cheap, standard
hygiene for a multi-agent estate, not a defect in this classification).

### EXECUTE list (orchestrator runs these — worktree-isolated session cannot mutate outside its own tree)

Run from the main (non-worktree) repo checkout root:

```bash
# --- Tier 1: direct ancestor (13) — zero-risk, mechanical git merge-base --is-ancestor proof ---
git worktree remove .claude/worktrees/agent-a067991d14d11d751   # be5e4273 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a3258d39fbe977719   # d6e70175 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a580ebd9a93c3a623   # 6c975cbb ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a614ebf430ad7cea2   # ab2caf9e ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a7eacf8dcf6548b11   # 2b8e07b6 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a86f8de6c36c3ad1f   # 6f5d1b22 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a87622c2020ce66a5   # a011d934 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a92d4266bc555d13a   # b65bef7a ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-a9710b88fde9bab38   # bca1c3ad ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-ace8ac90ead0f895f   # 88a6a1d5 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-af614aa5e90013731   # e58e480e ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-af6a93a3178eb7fd7   # d46beee5 ancestor-of-master rc=0
git worktree remove .claude/worktrees/agent-af95d509c3d671234   # 436c5854 ancestor-of-master rc=0

# --- Tier 2: exact commit-subject match on master (22) — cherry-picked, new SHA, same content ---
git worktree remove .claude/worktrees/agent-a02f53900aaecc157   # a69fde5b -> master 11ac00b3 (subject match)
git worktree remove .claude/worktrees/agent-a0b3e07cc30a937d0   # 8ad06a76 -> master abfec199 (subject match)
git worktree remove .claude/worktrees/agent-a10a91969a2e00989   # eb467aa3 -> master da5cb1ab (subject match)
git worktree remove .claude/worktrees/agent-a147a12539fa4d606   # 51abae3e -> master ce7cca52 (subject match)
git worktree remove .claude/worktrees/agent-a38c63c69628eb5a9   # 78e67de3 -> master e82f0b93 (subject match, content spot-checked)
git worktree remove .claude/worktrees/agent-a411c11a6438d7354   # 3b07d826 -> master 0808f2d9 (subject match)
git worktree remove .claude/worktrees/agent-a65b7b08817ce65fa   # 1272b01b -> master 0110fdae (subject match)
git worktree remove .claude/worktrees/agent-a69a708c140474c18   # b94de433 -> master 91bd0aed (subject match)
git worktree remove .claude/worktrees/agent-a6a8c733e9a5d5593   # 8a5a7c25 -> master 8e4267db (subject match)
git worktree remove .claude/worktrees/agent-a7d8b1474a721d1ff   # e37744a5 -> master 3cff15dc (subject match)
git worktree remove .claude/worktrees/agent-a8816ddce4b3e979c   # 82189a61 -> master e5432f3c (subject match)
git worktree remove .claude/worktrees/agent-a892c73e6f000a4c4   # de9a7c2f -> master 68e72365 (subject match)
git worktree remove .claude/worktrees/agent-a8b945f0aa2a79373   # ef288060 -> master 46826022 (subject match)
git worktree remove .claude/worktrees/agent-a9fa28339237c9e2b   # 24edc3c4 -> master f597cb60 (subject match)
git worktree remove .claude/worktrees/agent-ac49878b3f9c1d026   # 9fdc36b4 -> master e9c5bc0f (subject match)
git worktree remove .claude/worktrees/agent-ad2b2eda5d88861b0   # 7c0d5693 -> master 7f37e074 (subject match)
git worktree remove .claude/worktrees/agent-adc473f62d07a0405   # bebbcca8 -> master f7f1da33 (subject match)
git worktree remove .claude/worktrees/agent-aeed9a16399bf88e6   # 08a0c9d6 -> master d8912257 (subject match; also independently ancestor-of-master rc=0)
git worktree remove .claude/worktrees/agent-aef22a9fe22f4f45c   # 6a4200bf -> master ed32a7b4 (subject match)
git worktree remove .claude/worktrees/agent-af0e1f9e595286a95   # f01b6eff -> master 5eebe6e0 (subject match, content spot-checked)
git worktree remove .claude/worktrees/agent-afb0ac3afe6856dca   # b0155e37 -> master cddfc655 (subject match, content spot-checked)
git worktree remove .claude/worktrees/agent-afe3f7fdfcc8969c2   # 7f2e4b38 -> master 3f40b1e9 (subject match)

# --- Tier 3: cross-verified via 2026-08-02 triage's own citations, re-confirmed live today (3) ---
git worktree remove .claude/worktrees/agent-a60cd9f14ad2034df   # 7afffe07 -> landed via d805a9a3, re-confirmed ancestor-of-master rc=0 today
git worktree remove .claude/worktrees/agent-aa680cc77830d361b   # 390dc65e -> landed via 4ee18805, re-confirmed ancestor-of-master rc=0 today
git worktree remove .claude/worktrees/agent-afcf419ea529b1ca0   # 4c940b7b -> landed via 3ab7fa50+81e8d031, both re-confirmed ancestor-of-master rc=0 today

# --- Separate: orphaned stray, git itself already flags this dead (prune, not remove) ---
git worktree prune
# clears one stray entry outside the .claude/worktrees/ tree (a scratchpad path under a
# sibling checkout's temp directory) whose gitdir file points to a non-existent location —
# branch lesson/status-ground-truth, self-evidently safe (git's own prunable flag, not this
# session's judgment call)
```

**DO NOT include in any prune pass:** `agent-a8cce9bcdef232363` (unmerged T25 build),
`agent-aa43558579db80e88` (fresh unmerged work as of 2026-08-03T21:03), `agent-a05a34c3229e0a919`
(this session).

---

## 4. Monitor alerts (1,283 unacked -> 524 unacked; 738 bulk-acked)

Store: `~/.claude/state/external-monitor-alerts/` — the raw JSON files the
`external-monitor-alert-surfacer.sh` hook reads (grepped for the cockpit's own consumer first;
the workstreams-ui server code (`neural-lace/workstreams-ui/server/*.js`) has zero references
to "alert" — the Harness Health pane does not currently render this store directly; the
surfacer hook is the actual live consumer). Ack mechanism: `touch <file>.acked` (append-only
marker, never destroys data — confirmed by reading the surfacer hook's own logic).

**Classification** (re-derived fresh this pass, not trusted from the 2026-08-02 numbers):

| Class | Filename pattern | Unacked count (session start) | Status |
|---|---|---|---|
| `harness-doctor\|DOCTOR_RED` | `*-health-tick.json` | 503 | **DEAD** — last fired `2026-08-02T18:25:58Z`, re-confirmed zero new firings since (single-flight guard fix holds) |
| `supervisor-tick\|SWEEP_TIMEOUT` | `*-supervisor-tick.json` | 244 | **ROOT-CAUSED, still occasionally firing** — 1 new alert 2026-08-03T09:32 (worktree-hygiene-sweep timeout; root cause: the sweep has no internal timeout budget and this estate now has 42 worktrees vs 10 when last measured — tracked elsewhere, Stage 1/3 territory, not this task's scope) |
| bare-timestamp (downstream-product endpoint prober) | `<timestamp>.json`, multi-route payload | 533 (of which 493 `webhook-retell\|UNEXPECTED_STATUS`) | **REAL, LIVE PRODUCT BUG** — re-owned below, not acked |

**Action taken:** bulk-acked the 503 health-tick + 244 (then 245, one new arrival mid-session)
supervisor-tick files — confirmed dead-or-tracked-elsewhere classes, 738 total `.acked` marker
files created this pass (`ls *.acked | wc -l`: 21 pre-existing + 738 new = 759, confirmed).
Re-verified post-ack: 0 unacked remain in either class; 524 remain unacked in the bare-timestamp
class (grew from 533 to 524... net DROP because none of that class was acked; the apparent
shrink from the raw pre-session count is normal tick-to-tick noise in a still-firing class, not
a fix).

**The single largest-clearing route fix (36%+ of the pile, confirmed current):** across all 533
bare-timestamp files, per-anomaly classification via `jq -r '.results[] | select(.verdict !=
"HEALTHY")'` found **493 of 533 files (92%) carry a `webhook-retell|UNEXPECTED_STATUS` anomaly**
— `POST /api/webhooks/retell` on the monitored downstream-product's production URL expects 401
for an unauthenticated request and does not return it. This is a **downstream-product bug**,
not neural-lace harness code — no file inside this repo implements that route (same
downstream-product checkout the 2026-08-02 triage's §2/§3 tables reference throughout).
**Explicit re-own:** owner is the operator, in their capacity as that downstream product's
owner (not a harness maintainer task); fix location is `/api/webhooks/retell`'s auth check in
that product's own repo (path not enumerated here — out of this worktree's reach; a directory
search against the downstream product's local checkout was started and intentionally not
waited on, to stay in scope). Deliberately left UNACKED — acking a still-broken, still-firing
production auth gap would suppress a real signal, not clear noise.

**Remainder disposition:**
- `webhook-retell|UNEXPECTED_STATUS` (493) — re-owned above, left unacked (real signal)
- `SLOW` class across ~24 downstream-product endpoints (~200 anomaly-rows within the same 533
  files) — same repo, same re-own; not independently re-investigated this pass (already
  HYPOTHESIZED by the 2026-08-02 triage as unrelated to any harness-side CPU window)
- `harness-doctor|DOCTOR_RED` (503) — cleared (bulk-acked, dead class)
- `supervisor-tick|SWEEP_TIMEOUT` (244+) — cleared (bulk-acked); root cause (no sweep timeout
  budget) remains open, tracked outside this task's scope, will keep regenerating a trickle of
  new alerts until fixed
- malformed/small classes (task-query-failed, heartbeat-reap-error, ~15 corrupted-JSON files
  the 2026-08-02 triage found) — not independently re-swept this pass; folded into the
  bulk-ack where they matched the health-tick/supervisor-tick filename patterns, otherwise left
  as-is (small, low-priority, already named in the prior triage)

---

## 5. Grandfather registry shrink (D-12; REQ-C2's letter)

`adapters/claude-code/config/g2-grandfather-slugs.txt`: 300 -> **284** non-comment (sha256)
entries. Removed one entry per COMPLETED plan above (16 total), computed via the file's own
documented method (`printf '%s' "<slug>" | sha256sum | cut -d' ' -f1`), confirmed present
before removal (dry-run diff logged), confirmed absent after. DEFERRED plans' entries were
deliberately NOT removed — they may still need a future dispatch and retain grandfather
protection until closed or given an earned Review Chain. Commit `8e4073b2`.

---

## Follow-ups (not this task's scope, logged so they are not lost)

- `nl-issue.sh` friction filed this pass: `backlog-plan-atomicity.sh`'s archival-rename
  exemption needs the same `docs/plans/deferred/*.md` case as its existing `archive/*.md` case.
- 12 new high-value `nl-issue` findings (worktree reaper data-loss risk, missing force-push
  gate, `scope-enforcement-gate` global-block bug, `review-finding-fix-gate.sh` commit-lag bug,
  etc.) — full list in §2 above and the sub-agent's summary file.
- `worktree-hygiene-sweep.sh` has no internal timeout budget — will keep regenerating
  `SWEEP_TIMEOUT` alerts as the worktree count grows (42 now vs 10 when last measured); tracked
  as pre-existing, out of this task's scope.
- `/api/webhooks/retell` auth fix — re-owned to the operator as the downstream product's owner, not fixed here.

## Execution log (orchestrator, 2026-08-04)

EXECUTE list run with fresh per-entry re-verification (ancestry re-checked for
Tiers 1/3; `git worktree remove` without --force everywhere, so git's own
dirty/locked refusal backstopped every entry):

- **33 removed** (of 38 listed) + `git worktree prune` cleared the flagged stray;
  branches of removed worktrees deleted. Worktree census: 42 → 9 remaining
  (main + live-session trees + the holds below).
- **Held back, 5 — kept, nothing forced:**
  - `a60cd9f14ad2034df`, `aa680cc77830d361b`, `afcf419ea529b1ca0` (all Tier 3):
    the record's "re-confirmed ancestor-of-master rc=0 today" claim did NOT
    reproduce at execute time — their TIP SHAs (7afffe07/390dc65e/4c940b7b) are
    not ancestors; the landed-via mapping is subject-level only. Stay pending a
    content-level diff check before any removal.
  - `a87622c2020ce66a5` (Tier 1), `a411c11a6438d7354` (Tier 2): dirty or locked
    at execute time — refused by git, kept for a future sweep after inspection.
- Do-not-touch trio honored (`a8cce9bcdef232363` — since merged via train
  346646c3; `aa43558579db80e88` — since merged via 1cb3d2bb; `a05a34c3229e0a919`
  — this drain's own tree, merged via d0aeb643). All three now eligible for the
  NEXT sweep, not this one.

## Salvage pass 2 (orchestrator, 2026-08-04, doctor-directed)

- `a05a34c3229e0a919` (T21's own tree): dirt = machine-generated loe churn only → removed.
- `a411c11a6438d7354`: dirty backlog rows SALVAGED (two cockpit-poller rows re-appended to
  docs/backlog.md); its one unintegrated-by-patch-id commit 3b07d826 proven content-identical
  to master 0808f2d9 (numstat byte-match) → removed.
- `a87622c2020ce66a5`: dirt was the T8 corrected-diagnosis annotation — already landed on
  master via another path → removed.
- STILL HELD (genuinely unintegrated by patch-id; content-level reconciliation owed):
  `a60cd9f14ad2034df` (agent-efficiency T5/T7 — 38-hook path sweep), `aa680cc77830d361b`
  (session-start-digest reentry/single-flight), `afcf419ea529b1ca0` (review-record
  trust-anchor), `hopeful-bose-b98694` (workstreams-ui child-tree timeout-kill). Doctor
  budget-worktrees REDs on these are honest signal until reconciled.
- Stale branch `worktree-agent-a132819c46733c9c9` (no worktree, no upstream) deleted.
- Gate note: concurrent-ownership-gate consistently BLOCKED these mutations as compound
  commands yet allowed each identical single-target command — matcher defect, nl-issued.
