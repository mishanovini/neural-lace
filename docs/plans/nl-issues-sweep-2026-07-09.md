# Plan: nl-issues ledger triage + fix sweep (2026-07-09)

## Completion report (2026-07-09)

**All 36 in-scope ledger rows [21]–[56] reached terminal dispositions; all 17 plan tasks verifier-flipped; five batches merged to master + public mirror same-day.**

- **Merged batches:** #94 `4504db0` (A2/A4 + ADR approval trail) · #95 `43f76c2` (A1/A3/A5/B1/B5/B6 — end-manifest false-block, cockpit FM-037 engine, denylist narrowing) · #96 `3ba155c` (B2/B3/B4/B8 — dispatcher verdict visibility, doctor cockpit re-point) · #97 `08a3351` (B7 set-e sweep + ADR-061 P1b: reentry-safe heartbeats, health tick) · #98 `4fd706a` (ADR-061 P1a supervisor core + final flips). Plus #92/#93 (the ADR itself + decision trail).
- **Dispositions:** 16 rows FIXED with merged SHAs · 4 already-fixed-at-master (verify-first) · 2 not-a-bug/wontfix · 8 routed to new backlog rows with fold-in points · 6 folded into ADR-061 (evidence/ops steps) · 1 junk (accidental probe). Zero untriaged in scope; rows [57]/[58]/[61] (other sessions', <1d old) left for weekly triage.
- **Reviews:** harness-reviewer on A5 (security control — PASS, independent 24-shape battery), B1 (PASS + Major hardened same-day), B8 (builder-self-routed, PASS), P1a (REFORMULATE → 5/5 findings fixed same-day; reviewer mutation-tested the hang-class regression scenario). Every reviewed diff's findings closed before merge.
- **Verification:** task-verifier two rounds, 17/17 PASS conf 8–9, all oracles re-run foreground at master tips; orchestrator re-ran every touched suite on each integrated branch before its PR.
- **Incidents absorbed en route (all ledgered):** three live limit-pauses (usage-credits ×2, session-window ×1 — recovered via transcript-resume; direct D4 evidence); a mid-run worktree sweep against a live verifier; the gh-auth account race (3×); the compound-command-denial silent-kill (Stop gate caught it); the 100644-exec-bit Linux class (six call-sites fixed).
- **Follow-ups spawned (tracked):** 8 backlog rows (SHARED-CHECKOUT-BRANCH-GUARD-01, CRED-403-JIT-TRIGGER-01, COLD-READER-MECH-LAYER-01, BG-AGENT-AUTO-RETRY-01, CLAUDE-PREVIEW-WORKTREE-01, PERF-BUDGET-SELFTEST-01, GH-AUTH-RACE-01, INSTALL-SYNC-PARITY-01) + post-sweep ledger rows (denylist grep-exit-2 class, end-manifest structured-path generalization, stale manifest honest_status, worktree-sweep-liveness).
- **ADR-061 state at close:** design ACCEPTED; Phase 1 BUILT and merged (unarmed, shadow default); health-tick registration enabled in install.sh this commit — live registration + doctor green is the session's final ops step; Phase 2 (arming) remains operator-gated behind the shadow-metrics checklist.

- **Status:** COMPLETED
- **Mode:** code
- **Execution Mode:** orchestrator
- **Owner session:** angry-hypatia-45f5b0 (Fable continuation)
- **Trigger:** operator directive 2026-07-09 — "review the lessons learned ledger and make all those fixes"; ledger = `~/.claude/state/nl-issues.jsonl` (36 untriaged, [21]–[56], escalation-flagged at session start).

## Goal

Every nl-issue row [21]–[56] reaches a terminal disposition — fixed (merged SHA), folded into ADR-061, routed to backlog with a fold-in point, or documented-upstream — and the mechanical fixes land on master with green self-tests. Zero untriaged rows afterward.

## Scope

In: the 36 ledger rows below; ADR-061 amendments for the fold-ins; Wave A/B fixes; backlog rows for routed items; ledger disposition marks.
Out: arming the resumer (operator-gated, ADR-061 Phase 2); GAP-54 exit-1→exit-2 flips (deferred behind documented preconditions); building the mechanism proposals [34]/[40]/[46] (they get reviewed backlog rows, not builds).

## Triage dispositions (full ledger)

**FOLD INTO ADR-061 (amend ADR; no separate build):**
- [33] od_sessions mid-turn false-stall (mtime join unimplemented at od seam) → D3 evidence; verify-first ("fix-1 return" may exist)
- [36] check_obs_heartbeats_fresh re-implements staleness math → D3 one-oracle rule; verify-first ("round 3 dispatched")
- [43]+[44] background Agent dies on terminal API error pre-final-write; SendMessage-resume recovered → D7 note (surfacing now; auto-retry mechanism → backlog)
- [28]+[29]+[50] schtask /TR → wiped wrapper; install.sh wipes machine-local scripts; resumer task RED → ADR Phase-1 ops steps + D6 "/TR target exists" predicate

## Tasks

**WAVE A — small mechanical (parallel builders, file-disjoint):**
- [x] A.1 [48]+[52] sandbox unresolved-gaps feed path under HARNESS_SELFTEST in session-start-digest self-test S2
  - verifier 2026-07-09: PASS — self-test re-run 74/74 green; UNRESOLVED_GAPS_PATH override at :600 exercised both directions (S2/S2b) @ origin/master 43f76c2 (evidence file A.1)
- [x] A.2 [49] add `info` (work-integrity-gate) to observability-consumer-map with named consumer, or constrain emitter
  - verifier 2026-07-09: PASS — jq-valid; event_types.info.consumers[0] names the dispatcher self-test consumer of work-integrity-gate's emission, closing [49] as option (a) @ origin/master 43f76c2 (evidence file A.2)
- [x] A.3 [51] cold-reader-lint: require §3 block shape, exclude negation; self-test scenario
  - verifier 2026-07-09: PASS — dispatcher self-test re-run 66/66 green; scenario 24 passes both directions (negated prose exit 0, real §3 block still detected) @ origin/master 43f76c2 (evidence file A.3)
- [x] A.4 [31] install.sh sync loops gain skills/ + templates/
  - verifier 2026-07-09: PASS — sync loop :928 enumerates skills+templates (preview loop :452 mirrors); bash -n clean; install.sh not executed per directive @ origin/master 43f76c2 (evidence file A.4)
- [x] A.5 [47]+[25] denylist: narrow codename pattern (word-boundary/case-aware; stop matching the generic two-word idiom) + relocate literal test-password VALUE to gitignored business-patterns.d — harness-reviewer REQUIRED (security control)
  - verifier 2026-07-09: PASS — scan self-test OK (0 SKIP/0 FAIL, c1-c9 exercised); independent fixture probe: idiom exits 0 (space+hyphen), codename trips [denylist] exit 1 (prose+EOL); [25] literal relocated pre-sweep (bebe811) @ origin/master 43f76c2 (evidence file A.5)
- [x] A.6 [54] verify/extend .gitattributes eol=lf coverage for workflow .js paths
  - verifier 2026-07-09: PASS — .gitattributes:21 pins *.js eol=lf; zero CR matches in committed .js blobs on origin/master (grep control-proven against a known-CR .md blob) @ origin/master 43f76c2 (evidence file A.6)

**WAVE B — medium (verify-first; Stop-gate diffs get harness-reviewer):**
- [x] B.1 [26]+[27]+[30]+[45]+[53] end-manifest cluster: establish what fb7ab9a/wave-o-integration already fixed; then residuals — truncation mutual-prefix match, per-line jq -e → slurp any(), and a sanctioned resolution path for stale gaps ([53] class; decide-and-go with trail)
  - verifier 2026-07-09: PASS — end-manifest self-test re-run 32/32 green incl. s13b (both directions) + s13c (apostrophe path fails closed) @ origin/master 43f76c2 (evidence file B.1)
- [x] B.2 [42] dispatcher: surface combined verdict in the block message (stderr never reaches session context)
  - verifier 2026-07-09 (round 2): PASS — dispatcher self-test re-run 73/73 green incl. s25/s26 (per-gate reason + remediation in block-JSON, stop-verdict-full-*.txt on truncation); landed 3ba155c, re-run @ origin/master 08a3351 (evidence file B.2)
- [x] B.3 [22] live ~/.claude CRLF drift: extend doctor line-endings check to $live_home OR normalize-on-copy (verify "live CRLF deliberate" memory first)
  - verifier 2026-07-09 (round 2): PASS — docs-only close verified: LIVE-MIRROR-CRLF scan at master (5 hits; 1d6954a is master ancestor), cp_normalized live in install.sh, verify-first note at Decisions Log :131, doctor self-test 83/83 @ origin/master 08a3351 (evidence file B.3)
- [x] B.4 [56] scheduled-task naming drift: repoint/rename doctor↔registration; coordinate with sweet-hamilton session (it plans to unregister ConversationTreeUI-AutoStart); sequence after B3 (same file)
  - verifier 2026-07-09 (round 2): PASS — doctor self-test re-run 83/83 green; check_obs_cockpit_fresh re-pointed (ensure-cockpit.sh gate :1276, nested path :1266, curl probe :1303, WARN-never-RED); landed 3ba155c, re-run @ origin/master 08a3351 (evidence file B.4)
- [x] B.5 [37]+[39]+[55] cockpit/derive-cache: single-instance lock or listen-gate before cache.start(); single-flight poll guard; OBS_NL_TIMEOUT_MS review
  - verifier 2026-07-09: PASS — node server/server.selftest.js re-run 35/35 green incl. S17a-d single-flight poll guard ([39]) and S18a-c single-instance guard ([55]) @ origin/master 43f76c2 (evidence file B.5)
- [x] B.6 [23]+[35]+[38] doctrine/docs: orchestrator-pattern brief-template worktree-check + branch-verify-before-commit + ls-remote-after-push; acceptance conventions registered-event-types-only + scrub coordination
  - verifier 2026-07-09: PASS — full.md:105 has Shared-checkout git-state disciplines; compact 2870B (<3000) with all three disciplines; acceptance doc has REGISTERED-EVENT-TYPES-ONLY + FIXTURE-SCRUB COORDINATION; rules-index-coverage.sh 4/4 exit 0 @ origin/master 43f76c2 (evidence file B.6)
- [x] B.7 [24] set-e assignment-from-failing-pipeline audit across hooks/*.sh; verify plan-edit-validator instance fix merged
  - verifier 2026-07-09 (round 2): PASS — tdd-gate self-test 6/6 (incl. E-deletion-only-test-diff-allowed) + plan-edit-validator 15/15; record-test-pass outside-repo guard + replica alignment confirmed in 08a3351 diff; re-run @ origin/master 08a3351 (evidence file B.7)
- [x] B.8 [59] (added mid-sweep) pr-template-inline-gate: expand shell vars in --body-file path before the existence test (or skip when path contains '$') — false-WARNed 3× this session; WARN-only hook, still harness-reviewer per doctrine
  - verifier 2026-07-09 (round 2): PASS — pr-template gate self-test re-run 17/17 green (T13-T17: undefined-var/command-subst/operator-form paths skip silently, defined vars expand and still validate); landed 3ba155c, re-run @ origin/master 08a3351 (evidence file B.8)

**ROUTE / DEFER (persist, no build):**
- [x] R.1 [34] shared-checkout branch guard proposal + [46] credentials/403 JIT-trigger proposal + [40] cold-reader mechanical layer + [43]/[44] bg-agent auto-retry → backlog rows with fold-in points
  - verifier 2026-07-09: PASS — all four rows in docs/backlog.md (:15 SHARED-CHECKOUT-BRANCH-GUARD-01, :17 CRED-403-JIT-TRIGGER-01, :19 COLD-READER-MECH-LAYER-01, :21 BG-AGENT-AUTO-RETRY-01), each with fold-in point @ origin/master 43f76c2 (evidence file R.1)
- [x] R.2 [21] GAP-54 → confirm backlog row current; stays deferred. [32] Claude_Preview parent-worktree launch.json → document-upstream note in doctrine
  - verifier 2026-07-09: PASS — backlog.md:928 HARNESS-GAP-54 current; :29 CLAUDE-PREVIEW-WORKTREE-01 upstream-labeled note (caveat: [32] note homed in backlog, not doctrine/ — substance present, location deviates) @ origin/master 43f76c2 (evidence file R.2)
- [x] R.3 mark every ledger row's disposition via nl-issue.sh (terminal state; zero untriaged)
  - verifier 2026-07-09: PASS — nl-issue.sh --list --untriaged shows only post-sweep rows ([57][58][61][66]-[70]); zero untriaged in sweep scope [21]-[56] @ origin/master 43f76c2 (evidence file R.3)

## Files to Modify/Create

hooks/session-start-digest.sh · observability-consumer-map.json + hooks/work-integrity-gate.sh · cold-reader lint hook · install.sh · patterns/harness-denylist.txt (+ business-patterns.d doc) · .gitattributes · hooks/end-manifest.sh · hooks/stop-verdict-dispatcher.sh · hooks/harness-doctor.sh · workstreams-ui/server/server.js + derive-cache.js · doctrine/orchestrator-pattern* · docs/reviews/2026-07-06-o4-acceptance-scenarios.md · docs/backlog.md · docs/decisions/061 (amendments) · this plan.

## Assumptions

- nl-issues.jsonl is the ledger the operator means ("machine-wide ledger", constitution §5); docs/lessons/ holds one stale May file. If wrong, redirect costs one word.
- Rows claiming "fix dispatched/proven on branch/PR opened" ([24][27][30][33][36]) may already be partially on master — verify-first precedes every such build.
- Builders run in isolated worktrees (≤5 parallel, file-disjoint); orchestrator verifies on-disk evidence; task-verifier flips checkboxes.

## Edge Cases

- A5 touches the publication security control — no weakening: narrowed pattern must still catch the real codename in all case/word forms (add fixture proofs both directions).
- B1's resolution path must not create a "gaps silently vanish" hole — resolution requires re-derivable evidence (e.g. clean worktree re-check), never bare deletion; ADR-059 D4 honesty-assertion non-waivability respected.
- B4: another live session is actively unregistering one of the tasks involved — file-based coordination via SCRATCHPAD before touching registrations.
- B3: live-mirror CRLF was once deliberate (memory) — confirm intent before normalizing, else doctor false-REDs every machine.
- Wave A/B diffs land on master while the ADR-061 branch is open — keep sweeps on their own branches to avoid entangling the ADR merge.

## Testing Strategy

Each fix extends the touched artifact's own `--self-test` (house oracle) with a scenario reproducing the ledger symptom (red-before/green-after where feasible). B1: end-manifest self-test gains a >truncation-length message scenario + a stale-resolved-gap scenario. A5: hygiene-scan fixture asserting codename still blocked AND generic idiom passes. B5: two-instance spawn test asserting single poller. Doctor-touching fixes run `harness-doctor.sh --self-test` green. Final: `harness-doctor.sh --quick` green estate-wide; task-verifier per checkbox.

## Done-when

- Zero untriaged nl-issue rows; every row has a terminal disposition recorded.
- Wave A+B merged to master with green self-tests; verifier-flipped checkboxes.
- ADR-061 amended with fold-ins and merged.

## Verify-first results (2026-07-09, self-run on HEAD — research agent died on spend limit, recovered directly)

Master HEAD = `3c2bf7a` branch tip; findings are against the current tree (== origin/master content for these files, unmodified this branch).

| Row | Claim | Verdict at HEAD | Proof |
|---|---|---|---|
| [26] | end-manifest field-vs-substring | **FIXED** | validate check-2 does jq field-equality `(.gate)+"/"+(.check)+": "+(.message)==$item` (`end-manifest.sh:366-368`); write composes same via `jq -cs` (`:220-222`) |
| [30] | write truncates stored item, validate compares full | **NOT-A-BUG at HEAD** | stored `.item` is full; `${item:0:60}...` is display-only in the echo (`:379,381`) |
| [45] | validate per-line `jq -e`, last line masks | **NOT-FIXED** | `jq -e '…==$item' "$recorded_at"` streams the JSONL with no `-s`/`any()` — exit tracks only the LAST line (`:366-368`). Real defect remains. |
| [53] | stale resolved gap re-blocks forever | **NOT-FIXED** | write rebuilds ALL session ledger lines, no resolved-state filter (`:220-222`); no resolution path anywhere |
| [33] | od_sessions mtime-join unimplemented | **FIXED** | `hb_is_stale`/`hb_classify` carry the C1 transcript-mtime join, mtime ABOVE pid (`session-heartbeat-lib.sh:39-61`) |
| [36] | doctor reimplements staleness math | **FIXED** | `check_obs_heartbeats_fresh` now sources + calls `hb_classify` (`harness-doctor.sh:997-1092`) |
| [48]/[52] | digest S2 reads real unresolved-gaps | **NOT-FIXED** | feed 12 reads `${HOME:-$PWD}/.claude/state/unresolved-gaps.jsonl`, no env sandbox (`session-start-digest.sh:590-598`) |
| [54] | workflow .js CRLF smudge | **MOSTLY-CLOSED** | `.gitattributes:21` pins `*.js text eol=lf`; residual = existing committed blobs may need `git add --renormalize` |
| [24] | plan-edit-validator set-e death | **LIKELY-FIXED** | no `new_task_lines=` occurrence remains at HEAD (refactored/guarded); class-scan of hooks/*.sh still owed |

**Consequences for the plan:**
- B1 shrinks from 5 rows to **2 real fixes: [45] (jq slurp/`any()`) + [53] (sanctioned resolution path).** [26]/[30] drop out (fixed / not-a-bug).
- Fold-ins **[33] and [36] are already fixed at master** → ADR-061 D3 cites them as confirmed-implemented precedent, not new work.
- A6 [54] narrows to a `--renormalize` check, not a .gitattributes change.
- A1 [48]/[52] and A2–A5 stand as written.

## Build evidence (batch 2, 2026-07-09 — orchestrator-verified; checkbox flips await task-verifier)

- A1 [48]/[52]: `daf812f` (from builder 8f59ca5) — digest self-test 70/1 → 74/0; re-run green on integrated branch (74/74). Convention-matching env-override chain verified in diff.
- A3 [51]: `2041059` (from fa655b1) — dispatcher self-test 61/1 → 66/0; pre-existing failing scenario 22 WAS the [51] symptom, now green; new scenario 24 red-green both directions.
- A5 [47]/[25]: from `a40b5d0` — harness-reviewer **PASS** (independent 24-shape no-weakening battery; 3 Minor, none blocking). CORRECTED COUNT per reviewer finding 1: hygiene-scan FAIL-capable assertion blocks 12 → 23 (builder's "20→30" was unreproducible; derivation = `grep -c 'self-test: FAIL ('`). [25]'s literal was already relocated at master (bebe811); A5's delta = narrowed line-23 pattern + bidirectional oracle + scenario (d). Reviewer Minors recorded: fixture-token hardening only-as-class-sweep; scenario-(d) exemption-scope divergence is intentional (one comment line owed on next touch).
- B1 [45]/[53]: `0d1d476` + hardening `86cd4b8` (from 3cc7901+bad2d9e) — harness-reviewer **PASS with one Major follow-up**, Major FIXED same-day (fail-closed template-strip parse; s13c proves the apostrophe trap fails closed with the clean prefix dir existing); end-manifest self-test 19 → 32; wedged-session 442916d1 replay validates PASS. Class-generalization (structured wt_path field) filed as ledger row.
- B6 [23]/[34-doctrine]/[35]/[38]/[63]: `52d98b5` (from b3347f9) — docs-only; three shared-checkout git-state disciplines in orchestrator doctrine (compact + full), two acceptance-run conventions; one contradicting sentence amended (scope call, defensible).
- A5 residual filed by builder (verified by reviewer): scanner treats grep exit-2 as no-match → one invalid ERE silently no-ops Layer 1; three non-POSIX `(?:` lines remain (ubuntu-grep CI canary now covers the class via c1-c9).

## Decisions Log

- 2026-07-09: ledger = nl-issues.jsonl (see Assumptions).
- 2026-07-09: verify-first for rows claiming prior fixes — re-derive master state before building. PAID OFF: cut the end-manifest cluster in half and confirmed two ADR fold-ins already landed.
- 2026-07-09: mechanism proposals ([34][40][46], bg-agent auto-retry) are ROUTED not built — each is a new gate/trigger needing its own golden-scenario + FP-rate case per constitution §10; bundling them into a fix sweep would under-review them.
- 2026-07-09: builder-sweep dispatch (Wave A/B) is deferred until after ADR-061 review+merge — the operator scoped the sweep as "when you're done with everything here," and a 5-builder fan-out immediately after a spend-limit hit warrants finishing the design gate first. Not a scope change; a sequencing call.
- 2026-07-09 (post ADR-061 merge, on Opus after the Fable spend-limit pause): Wave A builders dispatched (background, worktree-isolated) — A1 [48]/[52] digest-S2 sandbox (build/nl-issue-48-digest-s2-sandbox), A2 [49] consumer-map info (build/nl-issue-49-consumer-map-info), A3 [51] cold-reader negation (build/nl-issue-51-coldreader-negation), A4 [31] install-sync skills/templates (build/nl-issue-31-install-sync-skills). A5 (denylist — public-mirror security control) HELD for harness-reviewer; Wave B HELD until Wave A verifies. Orchestrator verifies each on-disk before merge; task-verifier flips checkboxes.
- 2026-07-09: operator APPROVE-BUILD (NEEDS-YOU NY-1783623638-90f3 resolved) — full build greenlit: ADR-061 Phase 1 + entire sweep. Operator clarified the limit class: usage-credits monthly pool 101% ($201.51, resets Aug 1); Fable weekly 0% — captured as a real D4 account-cap instance in the ADR status line. ADR status flipped PROPOSED → ACCEPTED (design); arming still a separate Phase-2 gate.
- 2026-07-09: origin/master advanced with the sweet-hamilton session's cockpit-sessionstart merge (bf2b8c7 — logon-task retirement recorded): B4's coordination target has landed; B4 re-verifies task-name state against that merge before touching anything.
- 2026-07-09 (B3 [22] verify-first, builder): **already fixed and converged — documentation-only, no code change.** Both remedies the task offered landed on master 2026-07-06 in `1d6954a`: (a) `check_line_endings` live-mirror WARN scan (LIVE-MIRROR-CRLF-01, `harness-doctor.sh` ~1904-1926, WARN-never-RED) and (b) `install.sh` normalize-on-copy (`cp_normalized`/`is_text_sync_target`). Self-test fixtures for exactly the dispatch's scenarios already exist (`line-endings-live-mirror-warns`, `-lib-warns`, `-green`, `-never-red`). The drift itself has converged: live mirror measured **0/166** files with CR bytes today (byte-accurate `tr -cd '\r'` count + `od -tx1` hex spot-check across `~/.claude/hooks`, `hooks/lib`, `scripts`; the issue's 96/101 measurement predates convergence via auto-install git-blob copies + cp_normalized). The "live ~/.claude CRLF is deliberate" memory described the pre-1d6954a tolerated equilibrium (`_content_same` modulo-\r anti-ping-pong) and is now stale — live is LF. Disposition for [22]: already-fixed (`1d6954a`), drift converged, memory note needs refresh (routed to orchestrator).
- 2026-07-09 (B4 [56] re-verify + fix, builder): re-verified against bf2b8c7 — `ConversationTreeUI-AutoStart` is unregistered (read-only `schtasks /Query`: not found; `NL-workstreams-cockpit` likewise, never registered by anything). The canonical launch path is now session-tied, not a scheduled task: `session-start-digest.sh` `run_digest()` → `scripts/ensure-cockpit.sh` → `launch-gui.ps1` (machine-wide via `nl_repo_root()`). Re-verify found **three** dead layers in `check_obs_cockpit_fresh`, not one: (1) the schtask gate queried a never-registered name; (2) the cockpit-present gate checked `${repo_root}/workstreams-ui/server` but the O.4 build actually landed at `neural-lace/workstreams-ui/server` (flat path empty at master — gate permanently false); (3) the freshness signal read `state/workstreams-cache/derived-cache-stamp.txt`, which has **no producer anywhere** (zero writers repo-wide + in the running server tree) — post-gate-fix it would have standing-false-WARNed on a healthy cockpit (cockpit live HTTP 200 right now, no stamp exists). Fix: gate 1 → live `scripts/ensure-cockpit.sh` presence; gate 2 → nested canonical path; liveness → direct `curl` probe of `http://127.0.0.1:7733/` (the real user-facing surface; port is the server + launch-gui.ps1 fixed default), curl-absent → green skip. WARN-never-RED kept. Fixtures: fake-schtasks PATH stub → fake-curl PATH stub (same idiom); `warn-fires` (down→WARN, deterministic — proves the previously-unreachable WARN), `green-up` (healthy→silent, the FP guard), `green-nomech` (mechanism absent→silent, gate regression). Decide-and-go: probe replaces stamp rather than building a stamp producer (producer would touch server.js = B5's files; probe observes the actual outcome; staleness-of-derivation dimension can return if B5 ever lands a stamp writer). No OS guard — mechanism-file presence is the signal; worst case a WARN. No registrations touched (read-only queries only); sweet-hamilton coordination target already landed, so no SCRATCHPAD handshake needed.
- 2026-07-09 (~14:4x PT): THIRD live limit-pause instance this session — session-limit (5h window, reset 4:40pm PT) killed the P1a builder near-finish + verifier round 2 at start; both recovered via SendMessage transcript-resume with commit-checkpoint-first instructions. (Instances 1-2: usage-credits monthly pool, recorded in ADR-061 status line.) Direct live evidence for ADR-061 D4's deferral classes + the BG-AGENT-AUTO-RETRY-01 backlog row.
