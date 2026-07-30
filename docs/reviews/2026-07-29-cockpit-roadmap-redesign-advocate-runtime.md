# cockpit-roadmap-redesign — end-user-advocate RUNTIME verdict (Task 9)

Run: 2026-07-29, end-user-advocate (mode=runtime), session a3fcb6ea.
Target: LIVE cockpit http://127.0.0.1:7733 (LaunchAgent `local.neurallace.workstreams-cockpit`,
serving the main checkout at branch `wip/harness-hardening-2026-07-29`, HEAD e5ce1bc) +
a fixture-seeded SANDBOX second instance on :7799 (same code, env-redirected state — live
state untouched; zero-pollution verified: real ask-registry/needs-you ledger/NEEDS-YOU.md
contain no fixture ids after the run).
Browser: REAL headless Chrome via puppeteer-core (no browser MCP available in-session; the
curl-only fallback was NOT needed). Per-probe assertions, screenshots, network + console
logs: `docs/reviews/records/acceptance-cockpit-roadmap-redesign-2026-07-29/`.
Plan: `docs/plans/cockpit-roadmap-redesign.md` (Acceptance Scenarios, lines 531-554).

## VERDICT: FAIL — 5 of 9 scenarios PASS, 3 FAIL, 1 pending-operator

The shell, the three views, the R12/R13 rounds, and the narrow-viewport regression are
solid — every probe against them passed, with zero console errors and zero non-2xx
responses across both runs. The three FAILs are cross-task wiring gaps, not rendering
bugs: two acceptance scenarios promise signals no code path produces (S5 peers surface,
S6 waiting-on-you), and S7's error-vs-empty law breaks on exactly one errno branch.

| # | Scenario | Verdict | Ground |
|---|---|---|---|
| 1 | Archived done plan renders COMPLETE, never ACTIVE, not no-signal fallback | **PASS** | 6 archived complete plans render in Shipped; zero done==total items render outside complete (live P1/P1b/P1r). The original 18/18 exemplar (ask-rooted-workstreams-p1) has since left the registry; the class is proven on its siblings (e.g. cockpit-v2 8/8, archive path). |
| 2 | Merged-undeployed renders "merged — deploy unverified" OUTSIDE Complete + labeled override | **PASS** (sandbox; no live instance exists) | X2r: all-done fixture under `no-signal` renders chip "merged — deploy unverified", outside Shipped, with button "Mark complete anyway (override)"; kanban gives it its own labeled column, rendered only when non-empty (X10). Screenshot `X2r-merged-unverified.png`. |
| 3 | Context-less interactive add REFUSED w/ teaching; mechanical lands STORED+QUARANTINED; ONE defect per item lifetime | **PASS** | Real needs-you.sh (sandboxed ledger): interactive add exits 1 + teaching message; `--mechanical` stores NY id labeled quarantined; Inbox renders it under "arrived without context — defects filed…", EXCLUDED from Inbox (N); auditor filed EXACTLY 1 defect across many 5s-cadence cycles (stub call log); §3 anatomy renders full (context/options/pick/reply-with/channel/copy-stub) — `X4final-inbox.png`. |
| 4 | 700 bookkeeping badges → at most one counted chip per belief-changing class | **PASS** | 700 recent `unmatched_dispatch` injected: Requests board shows ZERO chips for them (suppression); the one belief-changing class renders exactly ONE counted chip (`log_ahead_task_not_flipped ×1`); Harness Health counts "progress-log bookkeeping divergences: 701 (1 class)" — `X7b-health.png`. Advisory: the auditor's nl-issue channel filed ~700 individual defects (see defect 4). |
| 5 | Peer view updates ≤~2min; idle machine shows fresh exported_at, never peer-unreachable | **FAIL** | (a) No view on the live cockpit renders `payload.peers` at all — the only renderer (asks.js Peers section) went down with the interim ask tree retired from Requests (b496b4f). Swept all four tabs for peer/exported/unreachable text: absent. (b) This machine has zero peer entries ever received (`has_data:false`), so the two-machine event-path timing is untestable here regardless — implementation-level coverage exists (t7 evidence) but the user-observable outcome is HYPOTHESIZED, not proven. |
| 6 | Stalled(waiting-on-you) descendant → counted labeled ancestor badges; click expands; #inbox link lands; Back restores | **FAIL (partial)** | The waiting-on-you signal is NEVER produced: roadmap-routes.js never populates `stalledSignals.waitingOnYouId` (inbox-routes.js:55-68 documents it as an honest limit; backlog row ROADMAP-WAITING-ON-YOU-SIGNAL-01, filed 2026-07-19, still open). No user can ever see the badge this scenario requires. The legs that exist DO pass: unknown-class rolls up into the group header ("2 status unknown", X3b); `#inbox/<id>` lands highlighted+focused and Back restores roadmap scroll+expansion (live P11); `#roadmap/<id>` lands highlighted (X3e). |
| 7 | Corrupt plan → unknown("plan parse failed"), rolls up, never confident; unreadable ledger → pane-error+Retry, never win state | **FAIL (2 of 4 legs)** | PASS legs: registry-linked absent plan → unknown("plan file not found"); registry-linked unreadable plan → unknown("plan file unreadable (EACCES…)"); both roll up ("2 status unknown"); corrupt-CONTENT ledger → (!) + pane-error + Retry, Retry recovers (X12/X12b). FAIL legs: defects 1 and 2 below — the win state renders over an EACCES-unreadable ledger, and a scanned corrupt plan renders confident not-started (or vanishes). |
| 8 | Operator title survives distiller re-run | **PASS** | X6r: UI-delegated POST /api/roadmap/title → title_source operator; a NEWER auto-sourced summary_updated record appended (simulated distiller); after cache expiry the operator title still wins in payload AND DOM (`domAuto=false`). |
| 9 | Operator cold-start walkthrough <60s | **PENDING-OPERATOR** | Machine proxy: the four bucket answers were extractable in ~1.6s from one screen — waiting-on-me = Inbox (1) tab + top item; in-motion = "4 in progress" + per-plan "<id> next" tokens; upcoming/complete = group header "(13 upcoming, … 4 complete)" + "Shipped (4)"; provenance = "from your request(s)" chip + Requests ledger. The <60s cold-start claim is the operator's own to time. |

### Round 12/13 + regression legs (all PASS)

- **R12 task-id correlation**: plan rows carry "<id> next" ("9 next" on cockpit-roadmap-redesign at 8/9, "P1 next", "T1 next"; token grammar mirrors the plan's actual task-id scheme — plans with unlettered `slug/9` ids render "9 next", not "T9 next"). The child flagged "next" is the id the parent names (P8r: exactly one chip, on "task 9: Acceptance"); a task with a live session renders "running", never "next" (sandbox fixture heartbeat).
- **R12 Shipped (n)**: collapsed by default, count consistent (default "Shipped (4)" = 6 complete − 2 machine-provenance chores; chores toggled ON → "Shipped (6)"/23 plans, matching the payload of the moment).
- **R12 Inbox count**: all three states proven — number (live `(1)` == answerable count), genuine zero (`(0)` + win state, quarantine still visible below per delta R1), error (`(!)` on corrupt ledger, X12).
- **R12 filter by task id**: typing `T9` opens the owning plan rows and reveals the matching task line + "matches: task T9 …" note (P4); `M4`/garbage filters render a named filtered-empty ("no items match \"…\" — clear filters"), never a win state; clearing restores all rows (P4b/P5).
- **R13**: completed titles are the ONLY dim state (42 dim titles, 0 non-done offenders, no dim "next" rows — P6); group rail visible (2px solid + per-node rails — P7); ✓ on done tasks (P8r); no "N–M done" duplication (P9); parent→child gap 28px < plan→next-plan 30px (P10r — correct ordering, thin margin; observation only).
- **Narrow viewport**: at 800px the roadmap section is 1184px tall with 136/136 rows visibly rendered (`P14-narrow-800px.png`) — ROADMAP-NARROW-VIEWPORT-COLLAPSE-01 (f3c0f75) verified fixed against the live app.
- **Shell adversarial probes**: tab double-click idempotent; reload on `#requests` restores the tab; hash landing + Back preserves roadmap scroll/expansion; zero console errors, zero non-2xx network responses across both full runs (P12/P15, X11/X13).

## Defects (all filed to the machine ledger via nl-issue.sh this run)

**1. INBOX-UNREADABLE-LEDGER-WIN-STATE-01 — Critical (fails scenario 7)**
- Line(s): `neural-lace/workstreams-ui/server/inbox-routes.js:158`
- Defect: `try { raw = fs.readFileSync(needsYouLedgerFile(), 'utf8'); } catch (_) { return null; }` treats EVERY read error as "absent — TRUE-empty". A present-but-EACCES-unreadable ledger.json makes /api/inbox return `ok:true, status:"not_yet_derived", ledger_present:false` and the cockpit renders **Inbox (0) + "Nothing waiting on you — all sessions running free"** while open items actually wait (screenshot `X8-ledger-error.png`; the module's own contract comment at :354-366 promises the distinction).
- Class: errno-conflation-on-best-effort-read (ENOENT=true-empty vs EACCES/EIO=error).
- Sweep query: `rg -n "catch \(_\) \{ return" neural-lace/workstreams-ui/server/`
- Required fix: catch ENOENT → null (true-empty); every other errno → the existing ok:false pane-error path (which already renders correctly — proven by the corrupt-CONTENT leg, X12).
- Required generalization: this exact class was already fixed for heartbeats in Task 1's fix round (`listRawHeartbeatsResult`, ENOENT-vs-unreadable) — sweep every best-effort reader the query surfaces and apply the same partition; the ledger reader is a missed sibling.
- Repro: `chmod 000 ~/.claude/state/needs-you/ledger.json; curl -s localhost:7733/api/inbox` (restore after).

**2. ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 — Critical (fails scenario 7)**
- Line(s): `neural-lace/workstreams-ui/server/roadmap-routes.js:266-269` (eligibility), `:311` (scan read + parse), vs the file's own header claim `:135` ("plan file absent/unreadable -> unknown(reason)").
- Defect: three corruption modes of a SCANNED docs/plans file, three wrong outcomes — (a) corrupt content with a surviving `Status:` header renders confident **"not started"** (fixture fx-corrupt2: binary bytes, `Status: WHAT`, zero parseable tasks — `X3-unknown-rows.png` shows it chipless among honest unknowns); (b) corrupt content that lost its Status header VANISHES silently (eligibility treats it as a non-plan stub); (c) an unreadable (EACCES) file is silently skipped by the scan's catch. Registry-LINKED plans do this right (absent → unknown "plan file not found"; unreadable → unknown "plan file unreadable (EACCES…)") — only the scan path guesses or vanishes.
- Class: default-guess-on-derivation-input-failure (the exact class Task 1's enum outlaws: "NO default-guess branch anywhere").
- Sweep query: `rg -n "catch \(_\) \{ return" neural-lace/workstreams-ui/server/roadmap-routes.js` + `rg -n "isEligiblePlanStatus" neural-lace/workstreams-ui/server/`
- Required fix: scan-path read failure → emit the item as unknown("plan file unreadable"), matching :135; an eligible file whose Status value is outside the known enum, or whose body yields zero tasks AND unparseable structure, → unknown("plan parse failed"), never not-started.
- Required generalization: audit every scanPlanDir caller for the silently-dropped-vs-named-unknown decision; the named-absence pattern (Task 1 generalization) must hold at the SCAN layer, not just the registry-join layer.
- Repro: `printf 'garbage\nStatus: WHAT\n\x01\xff\n' > docs/plans/fx-corrupt2.md` against a sandboxed instance → /api/roadmap shows `not-started`.

**3. ROADMAP-WAITING-ON-YOU-SIGNAL-01 — Critical for plan closure (fails scenario 6; pre-existing, already tracked)**
- Line(s): `neural-lace/workstreams-ui/server/inbox-routes.js:55-68` (documented honest limit); `docs/backlog.md` row ROADMAP-WAITING-ON-YOU-SIGNAL-01 (2026-07-19, priority:medium).
- Defect: no code path ever computes a roadmap item as "stalled: waiting-on-you"; the roll-up badge machinery (unit-proven) and the Inbox "blocks:" chip are unreachable by real data. Scenario 6 as written cannot pass on the live product.
- Class: unit-proven-but-unwired-signal (cross-task wiring gap: task 1 built the consumer, task 3 never built the producer).
- Sweep query: `rg -n "waitingOnYouId|blocks_roadmap_id" neural-lace/workstreams-ui/server/`
- Required fix: wire per the backlog row, OR narrow scenario 6 to the unknown-class roll-up + move the waiting-on-you leg to `## Out-of-scope scenarios` with the backlog row as rationale — an orchestrator/operator call, not the advocate's.
- Required generalization: at plan closure, every acceptance scenario that names a data signal should be checked against an actual producer, not just a selftest-supplied one.

**4. PEERS-SURFACE-RETIRED-01 — Critical (fails scenario 5)**
- Line(s): `neural-lace/workstreams-ui/web/asks.js:1000-1050` (only renderer of payload.peers); commit b496b4f ("interim ask tree retired from Requests").
- Defect: after the ask tree's retirement from the Requests tab, NO live view renders `payload.peers` — task 7's person-grouped peer view has no user-visible surface (all four tabs swept: zero peer/exported_at/unreachable text). The payload side works (peers block present, honest `has_data:false` on this machine).
- Class: surface-orphaned-by-retirement (a retirement removed the only mount point of an unrelated feature).
- Sweep query: `rg -n "payload.peers|\.peers\b" neural-lace/workstreams-ui/web/`
- Required fix: give the peers block a mount (Harness Health is the natural home per the bookkeeping precedent) or explicitly de-scope the peer VIEW from this plan's closure.
- Required generalization: when retiring a view, sweep it for sections other tasks own before deletion.

**5. AUDITOR-NL-ISSUE-STORM-AMPLIFICATION-01 — Important (advisory; S4 itself passes)**
- Line(s): `neural-lace/workstreams-ui/server/auditor.js:860-905`.
- Defect: a RECENT-event badge storm files one nl-issue per distinct badge id — 700 injected badges produced ~700 individual filings + 1 escalation in one cycle (sandbox stub log). Per-id once-per-lifetime + ADDITIVE recurrence escalation is design-conformant, but the ledger amplification channel survives the board-chip suppression fix; the age-bound fix only kills the STALE-event storm shape.
- Class: unbounded-fan-out-side-channel (capped at the render, uncapped at the defect-filing sink).
- Sweep query: `rg -n "runCli\(cliPath" neural-lace/workstreams-ui/server/auditor.js`
- Required fix: per-class per-cycle filing cap (file K exemplars + one "N more" summary).
- Required generalization: every auditor side-effect channel (filings, backfills) deserves the same storm-cap audit the badge renderer got.

**6. ROADMAP-SUPERSEDED-RENDERS-PENDING-01 — Important**
- Line(s): `neural-lace/workstreams-ui/server/roadmap-routes.js:265` (`PLAN_STATUS_EXCLUDE_RE = /^(REFERENCE|NORMATIVE)\b/i`).
- Defect: `Status: SUPERSEDED` is neither excluded nor labeled — cockpit-ui-polish (flipped SUPERSEDED by THIS plan's own closure contract) renders on the live roadmap as an ordinary "not started / 1 next / 0-5 bar" plan among live work (visible in `P14-narrow-800px.png`). The operator reads dead plans as pending work; same for any CANCELLED/ABANDONED terminal status.
- Class: unhandled-terminal-status-enum-value.
- Sweep query: `rg -l "^Status: (SUPERSEDED|CANCELLED|ABANDONED)" docs/plans/ docs/plans/archive/`
- Required fix: route terminal statuses to the Shipped/aged group with their own label ("superseded"), or exclude with a counted note — never the pending list.
- Required generalization: the six-value derived enum handles derivation outcomes; AUTHORED terminal statuses need their own named handling everywhere plan Status is read.

**Observation (Nice-to-have):** R13 spacing hierarchy holds by only 2px (28 vs 30) — correct ordering, but near the threshold of visual legibility; if the operator walkthrough still reads groups as flat, this is the first dial to turn.

## What this verdict means for Task 9 / plan closure

The plan's Closure Contract requires "advocate pass green over the 9 scenarios". This run is
NOT green: defects 1 and 2 are code fixes well inside this plan's files (one errno branch,
one scan branch); defects 3 and 4 are wiring/scoping calls the orchestrator must make
explicitly (fix, or narrow the scenario into `## Out-of-scope scenarios` with the tracked
rationale) — silently closing over them would ship acceptance scenarios that no user action
can ever satisfy. Scenario 9 additionally awaits the operator's own timed walkthrough.

Machine-readable summary:

```json
{
  "plan_slug": "cockpit-roadmap-redesign",
  "mode": "runtime",
  "session_id": "a3fcb6ea-7fab-460d-8506-e2a655016f09",
  "ran_at": "2026-07-29",
  "target": { "live": "http://127.0.0.1:7733 @ e5ce1bc", "sandbox": "http://127.0.0.1:7799 (env-redirected fixtures)" },
  "browser": "headless Chrome via puppeteer-core (real DOM assertions; no MCP available)",
  "scenarios": {
    "s1_archived_complete": "PASS", "s2_merged_unverified": "PASS", "s3_context_contract": "PASS",
    "s4_badge_storm": "PASS", "s5_peer_view": "FAIL", "s6_waiting_on_you_rollup": "FAIL",
    "s7_corrupt_inputs": "FAIL", "s8_title_fold": "PASS", "s9_operator_walkthrough": "PENDING_OPERATOR"
  },
  "r12_r13_narrow_viewport": "PASS",
  "console_errors": 0, "non_2xx_responses": 0,
  "defects": [
    "INBOX-UNREADABLE-LEDGER-WIN-STATE-01 (Critical, inbox-routes.js:158)",
    "ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01 (Critical, roadmap-routes.js:266-311)",
    "ROADMAP-WAITING-ON-YOU-SIGNAL-01 (Critical for closure, pre-existing backlog row)",
    "PEERS-SURFACE-RETIRED-01 (Critical, no renderer of payload.peers)",
    "AUDITOR-NL-ISSUE-STORM-AMPLIFICATION-01 (Important, advisory)",
    "ROADMAP-SUPERSEDED-RENDERS-PENDING-01 (Important)"
  ],
  "verdict": "FAIL"
}
```

---

# RE-RUN 2026-07-29 (Round 14, commit 2d48b71) — end-user-advocate runtime, session a3fcb6ea

Target: LIVE cockpit http://127.0.0.1:7733 + fixture-seeded SANDBOX :7799 (same code,
env-redirected state). The six R14-touched files verified byte-identical between 2d48b71,
the post-merge branch HEAD, and the disk the LaunchAgent serves. **Deploy note:** the live
LaunchAgent process predated R14 (started 10:34, R14 landed 17:25) and was still serving
pre-R14 in-memory server code — the exact merged-undeployed class this cockpit's own chip
names. Restarted via `launchctl kickstart -k gui/501/local.neurallace.workstreams-cockpit`
(17:31) before probing; all live probes below ran against R14 code. Method: headless Chrome
via puppeteer-core, per-probe assertions; zero-fixture-leak verified after the run (real
ledger untouched incl. mtime/perms, no fixture ids in real ask-registry/needs-you/NEEDS-YOU.md,
no fx-* files in the real plans dir). Evidence: `R2-*`/`R2L-*` files + three `*-rerun*-results.json`
in `docs/reviews/records/acceptance-cockpit-roadmap-redesign-2026-07-29/`.

## RE-RUN VERDICT: FAIL on exactly ONE residual leg — 8 of 9 scenarios green, S9 pending-operator

Five of the six Round-14 fixes verify end-to-end against the running product. The sixth
(corrupt-bucket) closes 2 of its 3 corruption shapes; the third shape (Status-header-destroyed)
still vanishes silently — R14's commit declares it deliberately out of scope, the re-run brief
declared it in scope. That single conflict is the only thing between this re-run and green.

| # | Scenario | Was | Now | Ground (probe ids in the results JSONs) |
|---|---|---|---|---|
| 1 | Archived complete never ACTIVE | PASS | **PASS** (regression spot-check) | R2L-S1: payload sweep — 0 all-done plans outside complete/merged-unverified; 5 archived complete plans render complete (archive fact = plan_path). |
| 2 | Merged-undeployed labeled | PASS | **PASS** (regression spot-check) | R2-S2: fx-deploy-done payload `merged-unverified` + "merged — deploy unverified" chip rendered. |
| 3 | Context contract / quarantine | PASS | **PASS** (regression spot-check) | R2L-S3: live payload shape intact (links/blocks_roadmap_id/reply_stub on every item), tab count == answerable count. Sandbox quarantine leg re-exercised incidentally (867a renders quarantined). |
| 4 | Badge-storm cap | PASS | **PASS** (surface spot-check) | R2L-S4: Harness Health Diagnostics (bookkeeping divergences row) renders post-R14-app.js; requests-routes untouched by R14 (selftest 173/25 unchanged per commit). |
| 5 | Peer view surface | **FAIL** | **PASS (surface) — timing leg HYPOTHESIZED** | PEERS-SURFACE-RETIRED-01 closed: live Harness Health renders the new "Machines" section; empty state names the exact tracked reason ("no peer exports received — … COORD-SYNC-NO-PEER-EXPORTS-YET-01 (docs/backlog.md)") — R2L-S5 + screenshot R2L-S5-machines-empty.png; double-click idempotent. Non-empty path proven in sandbox: seeded peer export renders "peer-laptop (fresh, Xm ago)" chip (R2-S5, R2-S5-machines-sandbox.png). The scenario's cross-machine ≤2min flip→update leg remains HYPOTHESIZED, not proven: zero real peers have ever exported (the named backlog row); refuter = first real peer export not appearing within ~2min. Not fakeable from one machine — saying so per the brief. |
| 6 | Waiting-on-you roll-up (C1/C2) | **FAIL** | **PASS — full leg, end to end** | Producer exists and fires: answerable ledger item naming docs/plans/fx-active.md + "task 3" → fx-active/3 derives `stalled — waiting-on-you` with `unblock {label:"open in Inbox", hash:"#inbox/NY-…-f68a"}` (R2-S6-producer-payload); plan roll_up counts it (R2-S6-plan-rollup). DOM, tree fully collapsed: counted labeled badge "1 stalled — waiting on you" VISIBLE on the collapsed plan row (row 174→36px summary-only; badge 132×30, hit-test confirmed; project groups are non-collapsible sections — no ancestor can hide the badge); badge click expands the path to the stalled task; "open in Inbox" lands `#inbox/<id>` focused + `.landing-highlight`; Back restores roadmap with expansion intact and row position delta 0px (R2-S6-* probes + 3 screenshots). Reverse chip: Inbox item shows "blocks: fx-active/3". CONSERVATIVE-matcher probes: an item naming a nonexistent "task 99" fabricates nothing (no node, no chip); a RESOLVED item referencing task 2 stalls nothing. Note the derivation precondition: only a STARTED task can stall (not-started stays not-started even when referenced) — matches the scenario's "stall one deep descendant", worth knowing for operator expectations. |
| 7 | Corrupt inputs (C5/C4) | **FAIL** | **FAIL (1 of 6 legs residual)** | FIXED legs: scan-path corrupt plan with surviving-but-bogus `Status: WHAT` → unknown("plan parse failed (unrecognized Status: …)"), never not-started (R2-S7a; INBOX defect 2's shape (a)); scan-path unreadable (chmod-000) plan → unknown("plan file unreadable (EACCES)") (shape (c)); both roll up ("3 status unknown"); chmod-000 LEDGER → `/api/inbox {ok:false, status:"unavailable", ledger_present:true}` AND pane renders `(!)` + pane-error + Retry, NEVER the win state; Retry after restore recovers to the true count (R2-S7c ×3 — defect 1 closed, both halves). RESIDUAL FAIL: a scanned plan whose Status: header was itself destroyed by corruption (binary body, no header — fx-corrupt3) still VANISHES silently (shape (b)); R14 declares header-less files deliberately excluded (anti-flooding rationale vs evidence.md stubs), but the re-run brief's bar is "a Status-less corrupt plan must NOT vanish", and the narrow fix (apply the existing PLAN_BODY_CORRUPTION_RE signature to header-less files too) would not flood clean stubs. Filed: ROADMAP-STATUSLESS-CORRUPT-VANISH-01 (nl-issues ledger). Orchestrator call: fix the narrow leg, or move it to `## Out-of-scope scenarios` with the R14 rationale — either unblocks S7. |
| 8 | Operator title survives distiller | PASS | **PASS** (regression re-run) | R2-S8: POST title → newer auto summary_updated appended → after cache expiry title_source=operator, operator text wins. |
| 9 | Operator cold-start <60s | PENDING | **PENDING-OPERATOR** | Unchanged — the operator's own timed walkthrough. |

**Mid-round scope addition (live operator complaint) — VERIFIED:** the multi-line §3 anatomy
contract. The real production item NY-1785369704-ecbf was RESOLVED (live inbox empty) during
the run gap, so its exact raw text (7-line, "Option NAME -> effect -> outcome" arrow grammar,
inline repo-path anchor, no producer links) was replayed VERBATIM into the sandbox ledger:
renders FULL anatomy expanded — title label-stripped (no "Decision needed: Decision needed:"
doubling), BOTH arrow-options with their complete outcome text in the trade-offs structure,
My pick, Reply-with, and a "Links:" section carrying the extracted `docs/plans/review-independence.md`
anchor as text + copy button — zero `<a>` elements with fabricated/relative hrefs (dead-link
sweep: 0) (R2-INBOX-arrow-anatomy-full + screenshot). SUPERSEDED placement (defect 6): live
cockpit-ui-polish renders inside Shipped with the distinct "superseded" terminal chip
(`rm-status-terminal-superseded`), zero instances outside Shipped, plain complete siblings
chipless — R2L-superseded-shipped-chip + screenshot.

Console errors: 0 across both instances and all probe passes. Non-2xx responses: 0.
Probe-harness corrections during the run (recorded honestly in the results JSONs, superseded
probes kept): the first ancestor-badge/back-restore probes used slug-text row matching and the
`offsetParent` oracle — both invalid (rows are titled via the R14 title fold; Chrome implements
closed `<details>` with content-visibility, so descendants keep measurement boxes). Corrected
oracles: `data-item-id` selectors, geometry (row height 174→36px) + `elementFromPoint` hit-test.

```json
{
  "rerun_of": "2026-07-29 first pass (5/9)",
  "fix_commit": "2d48b712967998f7bd3434868342413d23aa1120",
  "verified_against": "live :7733 (post-restart, R14 in memory) + sandbox :7799 (R14 code)",
  "scenarios": {
    "s1_archived_complete": "PASS", "s2_merged_unverified": "PASS", "s3_context_contract": "PASS",
    "s4_badge_storm": "PASS",
    "s5_peer_view": "PASS_SURFACE_TIMING_LEG_HYPOTHESIZED",
    "s6_waiting_on_you_rollup": "PASS",
    "s7_corrupt_inputs": "FAIL_RESIDUAL_1_OF_6_LEGS",
    "s8_title_fold": "PASS", "s9_operator_walkthrough": "PENDING_OPERATOR"
  },
  "defect_closure": {
    "INBOX-UNREADABLE-LEDGER-WIN-STATE-01": "CLOSED-VERIFIED",
    "ROADMAP-CORRUPT-PLAN-CONFIDENT-BUCKET-01": "PARTIALLY-CLOSED (shapes a+c verified; shape b residual -> ROADMAP-STATUSLESS-CORRUPT-VANISH-01)",
    "ROADMAP-WAITING-ON-YOU-SIGNAL-01": "CLOSED-VERIFIED",
    "PEERS-SURFACE-RETIRED-01": "CLOSED-VERIFIED",
    "ROADMAP-SUPERSEDED-RENDERS-PENDING-01": "CLOSED-VERIFIED",
    "INBOX-MULTILINE-ASK-TRUNCATED-AT-RENDER-01": "CLOSED-VERIFIED",
    "AUDITOR-NL-ISSUE-STORM-AMPLIFICATION-01": "advisory, unchanged (not in R14 scope)"
  },
  "console_errors": 0, "non_2xx_responses": 0,
  "verdict": "FAIL (single residual leg: Status-less corrupt plan vanishes; orchestrator: fix or de-scope with rationale)"
}
```
